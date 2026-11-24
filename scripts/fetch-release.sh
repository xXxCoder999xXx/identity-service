#!/usr/bin/env bash
# =============================================================================
# Server: prueft die Staging-Freigabe, wendet die Downgrade-Regel an und holt
# die Dateien aus dem Bundle (ADR-017, PR 4c; Schritte 0, 2, 3 und 5 des
# Server-Ablaufs).
#
# Aufruf:  bash fetch-release.sh STATE_FILE SWITCH_FILE RELEASES_DIR NGINX_DOCKERFILE
#          STATE_FILE        Zustandsdatei im StateDirectory der Unit
#          SWITCH_FILE       Erst-Schalter, root-eigen unter /etc/identity-service/
#          RELEASES_DIR      Ordner fuer releases/<commit>/ (muss existieren)
#          NGINX_DOCKERFILE  Quelle des fremden Images fuer die Gegenproben
#                            (E-5-132), wird an verify-release.sh gereicht
#
# Ablauf:
#   0. Voraussetzungen: nicht als root, docker vorhanden und rootless,
#      Erst-Schalter (falls vorhanden) root-eigen und fuer uns nicht
#      schreibbar, Releases-Ordner gehoert uns und ist kein Link.
#   1. Zustand lesen (fehlt / gueltig / ungueltig). Kein Netz.
#   2. verify-release.sh per Tag staging: Nachweis, Fakten, Gegenproben. Ab
#      hier gilt nur der verifizierte Digest (subject).
#   3. Entscheidung mit release_decide (lib/release-state.sh).
#   4. Bei deploy/first: Bundle per verifiziertem Digest anlegen (nie
#      gestartet), genau RELEASE_FILES herauskopieren, jede Datei pruefen,
#      Rechte selbst setzen, atomar nach RELEASES_DIR/<commit> umbenennen.
#      Existiert der Ordner schon (Wiederholung nach gescheitertem Deploy),
#      muss sein Inhalt Byte fuer Byte gleich sein.
#
# Was dieses Skript NICHT tut (PR 4d): flock, Paket-Sichtbarkeit (E-5-115),
# Pruef-Gate der drei Images, compose up, Zustand schreiben, current
# umstellen. Es aendert keinen Zustand und keinen laufenden Dienst.
#
# Ausgabe: Am Ende Zeilen "release<TAB><schluessel><TAB><wert>" mit den
# Schluesseln decision, dir, run, attempt, commit, subject, api, nginx, lego
# (in dieser Reihenfolge; dir ist "-" bei noop). Nur bei Exit 0 gueltig.
#
# Exit-Codes (jeder ungleich 0 heisst: NICHT ausrollen - fail closed):
#   0  Freigabe verifiziert; decision deploy/first (Dateien bereit) oder noop
#   2  Voraussetzung oder Parameter fehlt bzw. ist ungueltig
#   3  Nachweis/Fakten ungueltig oder Bundle-Inhalt weicht ab
#   4  eine Gegenprobe wurde akzeptiert (von verify-release.sh)
#   5  eine Gegenprobe scheiterte am falschen Grund (von verify-release.sh)
#   6  ALARM: Downgrade-Regel lehnt ab (aeltere Freigabe, kaputter Zustand,
#      kein Zustand ohne Schalter)
#
# Installation (E-5-117): root-eigen unter /usr/local/lib/identity-service/
# zusammen mit verify-release.sh und lib/. Nie aus dem Release-Ordner
# ausfuehren.
# =============================================================================
set -euo pipefail

fail() {
  echo "FEHLER (Exit $1): $2" >&2
  exit "$1"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in verify-release.sh lib/release-rules.sh lib/release-state.sh; do
  [ -r "${script_dir}/${f}" ] || fail 2 "Datei nicht gefunden: ${script_dir}/${f}"
done
# shellcheck source=lib/release-rules.sh
. "${script_dir}/lib/release-rules.sh"
# shellcheck source=lib/release-state.sh
. "${script_dir}/lib/release-state.sh"

# Obergrenze je Datei aus dem Bundle. Die groesste (compose.yaml) hat wenige
# KiB; alles darueber ist kein Bestandteil einer Freigabe von uns.
readonly MAX_FILE_BYTES=262144

# --- 0. Voraussetzungen --------------------------------------------------------
echo "== Voraussetzungen"
[ "$#" -eq 4 ] || fail 2 "Erwartet: STATE_FILE SWITCH_FILE RELEASES_DIR NGINX_DOCKERFILE (erhalten: $# Parameter)."
state_file="$1"
switch_file="$2"
releases_dir="$3"
nginx_dockerfile="$4"
for p in "${state_file}" "${switch_file}" "${releases_dir}"; do
  case "${p}" in
    /*) ;;
    *) fail 2 "Pfad muss absolut sein: '${p}'" ;;
  esac
done

# Der Deploy laeuft als eigener Benutzer mit rootless Docker, nie als root.
[ "$(id -u)" != "0" ] || fail 2 "Darf nicht als root laufen."
command -v docker >/dev/null 2>&1 || fail 2 "docker wurde nicht gefunden."
command -v stat >/dev/null 2>&1 || fail 2 "stat wurde nicht gefunden."
command -v cmp >/dev/null 2>&1 || fail 2 "cmp wurde nicht gefunden."
security="$(timeout 30 docker info --format '{{.SecurityOptions}}')" \
  || fail 2 "docker info gescheitert (Daemon nicht erreichbar?)."
[[ " ${security//[\[\]]/ } " == *" name=rootless "* ]] \
  || fail 2 "Docker laeuft nicht rootless: ${security}"
echo "docker rootless"

# Erst-Schalter: Wer ihn anlegen oder loeschen darf, darf den Vergleich
# abschalten (E-5-147). Deshalb muss er root gehoeren und fuer uns nur
# lesbar sein. Ein Schalter, der das nicht erfuellt, bricht ab, statt still
# als "nicht vorhanden" zu gelten.
switch="no"
if [ -e "${switch_file}" ] || [ -L "${switch_file}" ]; then
  [ ! -L "${switch_file}" ] || fail 2 "Erst-Schalter ist ein symbolischer Link: ${switch_file}"
  [ -f "${switch_file}" ] || fail 2 "Erst-Schalter ist keine gewoehnliche Datei: ${switch_file}"
  owner="$(stat -c '%u' -- "${switch_file}")" || fail 2 "Eigentuemer des Erst-Schalters nicht lesbar."
  [ "${owner}" = "0" ] || fail 2 "Erst-Schalter gehoert nicht root (UID ${owner}): ${switch_file}"
  [ ! -w "${switch_file}" ] || fail 2 "Erst-Schalter ist fuer diesen Benutzer schreibbar: ${switch_file}"
  switch="yes"
fi
echo "Erst-Schalter: ${switch}"

[ ! -L "${releases_dir}" ] || fail 2 "RELEASES_DIR ist ein symbolischer Link: ${releases_dir}"
[ -d "${releases_dir}" ] || fail 2 "RELEASES_DIR fehlt: ${releases_dir}"
dir_owner="$(stat -c '%u' -- "${releases_dir}")" || fail 2 "Eigentuemer von RELEASES_DIR nicht lesbar."
[ "${dir_owner}" = "$(id -u)" ] || fail 2 "RELEASES_DIR gehoert nicht diesem Benutzer: ${releases_dir}"

# --- 1. Zustand ------------------------------------------------------------------
echo "== Zustand"
if [ ! -e "${state_file}" ] && [ ! -L "${state_file}" ]; then
  state_kind="none"
  echo "kein Zustand"
elif release_state_parse "${state_file}"; then
  state_kind="valid"
  echo "gespeichert: run ${STATE_RUN}, commit ${STATE_COMMIT}, bundle ${STATE_BUNDLE}"
else
  state_kind="invalid"
  echo "Zustand vorhanden, aber ungueltig"
fi

# --- 2. Freigabe pruefen -------------------------------------------------------
# stdout von verify-release.sh landet in einer Datei, stderr bleibt im
# Journal. Exit-Codes 2 bis 5 werden unveraendert weitergegeben.
work="$(mktemp -d)"
cid=""
incoming=""
cleanup() {
  if [ -n "${cid}" ]; then docker rm "${cid}" >/dev/null 2>&1 || true; fi
  if [ -n "${incoming}" ]; then rm -rf -- "${incoming}"; fi
  rm -rf -- "${work}"
}
trap cleanup EXIT

verify_code=0
bash "${script_dir}/verify-release.sh" "${RELEASE_IMAGE_NAME}:${RELEASE_TAG}" "${nginx_dockerfile}" \
  >"${work}/verify.out" || verify_code=$?
# Das Protokoll gehoert ins Journal, auch bei Erfolg.
cat "${work}/verify.out"
case "${verify_code}" in
  0) ;;
  2 | 3 | 4 | 5) fail "${verify_code}" "Freigabe nicht verifiziert (verify-release.sh Exit ${verify_code})." ;;
  *) fail 3 "verify-release.sh endete unerwartet mit Exit ${verify_code}." ;;
esac

# Fakten: genau die letzten sieben Zeilen, alle "freigabe<TAB>...", und keine
# weitere solche Zeile davor. So kann keine fruehere Ausgabe Fakten
# vortaeuschen.
echo "== Fakten"
facts_total="$(grep -c "^freigabe"$'\t' "${work}/verify.out" || true)"
[ "${facts_total}" = "7" ] || fail 3 "Erwartet genau sieben Fakten-Zeilen, gefunden ${facts_total:-0}."
keys=()
values=()
while IFS=$'\t' read -r tag key value; do
  [ "${tag}" = "freigabe" ] || fail 3 "Fakten stehen nicht am Ende der Ausgabe."
  keys+=("${key}")
  values+=("${value}")
done < <(tail -n 7 "${work}/verify.out")
[ "${keys[*]}" = "subject run attempt commit api nginx lego" ] \
  || fail 3 "Fakten unvollstaendig oder in unerwarteter Reihenfolge: ${keys[*]}"
subject="${values[0]}"
new_run="${values[1]}"
new_attempt="${values[2]}"
new_commit="${values[3]}"
release_state_valid_bundle "${subject}" || fail 3 "subject ist kein Digest: '${subject}'"
release_state_valid_run "${new_run}" || fail 3 "Run-ID ungueltig: '${new_run}'"
[[ "${new_attempt}" =~ ^[1-9][0-9]{0,3}$ ]] || fail 3 "Versuch ungueltig: '${new_attempt}'"
release_state_valid_commit "${new_commit}" || fail 3 "Commit ungueltig: '${new_commit}'"
echo "Freigabe: run ${new_run}, Versuch ${new_attempt}, commit ${new_commit}, bundle ${subject}"

# --- 3. Entscheidung -----------------------------------------------------------
echo "== Entscheidung"
decision="$(release_decide "${state_kind}" "${STATE_RUN:-}" "${STATE_COMMIT:-}" \
  "${new_run}" "${new_commit}" "${switch}")"
echo "Entscheidung: ${decision}"

print_result() {
  local i
  printf 'release\tdecision\t%s\n' "${decision}"
  printf 'release\tdir\t%s\n' "$1"
  printf 'release\trun\t%s\n' "${new_run}"
  printf 'release\tattempt\t%s\n' "${new_attempt}"
  printf 'release\tcommit\t%s\n' "${new_commit}"
  printf 'release\tsubject\t%s\n' "${subject}"
  for i in 4 5 6; do
    printf 'release\t%s\t%s\n' "${keys[$i]}" "${values[$i]}"
  done
}

case "${decision}" in
  deploy | first) ;;
  noop)
    echo "Freigabe ist bereits ausgerollt; nichts zu tun."
    print_result "-"
    exit 0
    ;;
  reject) fail 6 "ALARM: Downgrade-Regel lehnt die Freigabe ab (Grund oben)." ;;
  *) fail 6 "ALARM: unbekannte Entscheidung '${decision}'." ;;
esac

# --- 4. Dateien aus dem Bundle -------------------------------------------------
echo "== Dateien aus dem Bundle"
# Angelegt, nie gestartet: Das Bundle ist FROM scratch und hat keinen
# Startbefehl; ohne Befehl lehnt docker create ab (gemessen am 2026-11-24).
# /nonexistent wird nie ausgefuehrt. Nur per verifiziertem Digest.
cid="$(timeout 180 docker create "${RELEASE_IMAGE_NAME}@${subject}" /nonexistent)" \
  || fail 3 "Bundle ${subject} nicht anlegbar."
[[ "${cid}" =~ ^[0-9a-f]{64}$ ]] || fail 3 "docker create lieferte keine Container-ID."

incoming="$(mktemp -d "${releases_dir}/.incoming.XXXXXX")"
for file in "${RELEASE_FILES[@]}"; do
  case "${file}" in
    /* | *..* | "") fail 3 "Unzulaessiger Pfad in RELEASE_FILES: '${file}'" ;;
  esac
  mkdir -p -- "${incoming}/$(dirname -- "${file}")"
  timeout 60 docker cp "${cid}:/${file}" "${incoming}/${file}" >/dev/null \
    || fail 3 "Fehlt im Bundle: ${file}"
  # docker cp kopiert einen Link als Link; er koennte aus dem Release-Ordner
  # hinauszeigen.
  [ ! -L "${incoming}/${file}" ] || fail 3 "Ist im Bundle ein symbolischer Link: ${file}"
  [ -f "${incoming}/${file}" ] || fail 3 "Ist im Bundle keine gewoehnliche Datei: ${file}"
  size="$(wc -c <"${incoming}/${file}")"
  size="${size//[[:space:]]/}"
  [ "${size}" -gt 0 ] || fail 3 "Ist im Bundle leer: ${file}"
  [ "${size}" -le "${MAX_FILE_BYTES}" ] || fail 3 "Ist im Bundle zu gross (${size} Bytes): ${file}"
  # Rechte selbst setzen, unabhaengig davon, wie das Bundle gebaut wurde.
  chmod 0644 -- "${incoming}/${file}"
  echo "ok ${file} (${size} Bytes)"
done
# Ordner lesbar fuer die Container (rootless: andere UIDs), nicht schreibbar.
find "${incoming}" -type d -exec chmod 0755 {} +

target="${releases_dir}/${new_commit}"
if [ -e "${target}" ] || [ -L "${target}" ]; then
  # Wiederholung nach gescheitertem Deploy (ADR-017): derselbe Commit muss
  # denselben Inhalt haben. Sonst bricht der Lauf ab, statt zu ueberschreiben.
  [ ! -L "${target}" ] || fail 3 "Release-Ordner ist ein symbolischer Link: ${target}"
  [ -d "${target}" ] || fail 3 "Release-Ordner ist kein Ordner: ${target}"
  for file in "${RELEASE_FILES[@]}"; do
    [ ! -L "${target}/${file}" ] && [ -f "${target}/${file}" ] \
      || fail 3 "Vorhandener Release-Ordner unvollstaendig: ${file}"
    cmp -s -- "${incoming}/${file}" "${target}/${file}" \
      || fail 3 "Vorhandener Release-Ordner weicht ab: ${file}"
  done
  echo "Release-Ordner existiert bereits mit gleichem Inhalt: ${target}"
else
  mv -T -- "${incoming}" "${target}"
  incoming=""
  echo "Release-Ordner angelegt: ${target}"
fi

print_result "${target}"
