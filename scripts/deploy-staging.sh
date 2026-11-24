#!/usr/bin/env bash
# =============================================================================
# Server: Pull-Deploy auf Staging (ADR-017, PR 4d-3a). Rollt die geprueften
# Images der Staging-Freigabe aus, prueft die Health ueber nginx und stellt
# erst danach current und den Zustand um.
#
# Aufruf:  bash deploy-staging.sh STATE_DIR SWITCH_FILE INSTALL_NGINX_DOCKERFILE
#          STATE_DIR                 StateDirectory der Unit; enthaelt state,
#                                    current (Link) und releases/
#          SWITCH_FILE               Erst-Schalter, root-eigen unter
#                                    /etc/identity-service/ (E-5-147)
#          INSTALL_NGINX_DOCKERFILE  root-eigene Kopie aus der Installation;
#                                    nur ohne Zustand benutzt (E-5-177)
#
# Umgebung (setzt die Unit; keine davon ist ein Secret):
#   RUNTIME_DIRECTORY         Ordner nur fuer diesen Lauf (DOCKER_CONFIG)
#   CREDENTIALS_DIRECTORY     von LoadCredential: ghcr-token, ping-url
#   GHCR_USERNAME             Maschinenkonto fuer die Registry (ADR-004)
#   STAGING_SERVER_NAME_FILE  Datei "server_name <name>;" (E-5-82)
#   STAGING_CA_DIR            interne CA
#   STAGING_API_CERT_DIR      Zertifikat und Schluessel der API
# Die drei STAGING_* liest Compose direkt (compose.staging.yaml). Die
# erwarteten Werte der Pruefungen kommen nie aus der Umgebung (E-5-122),
# sondern aus lib/.
#
# Ablauf:
#   0. Parameter, Umgebung, Ping-URL; flock auf STATE_DIR/.deploy.lock.
#   1. Token aus dem Credential, Zeilenende entfernen, Form pruefen;
#      docker login --password-stdin in DOCKER_CONFIG unter
#      RUNTIME_DIRECTORY (E-5-174).
#   2. Vier Pakete anonym nicht lesbar (E-5-115, E-5-171).
#   3. fetch-release.sh: Freigabe, Downgrade-Regel, Dateien (PR 4c).
#      NGINX_DOCKERFILE aus current/, ohne Zustand aus der Installation
#      (E-5-177). Bei noop: nur Health pruefen und enden.
#   4. Pruef-Gate der drei Images (ADR-015).
#   5. Pull per Digest und Abgleich der RepoDigests.
#   6. PUNKT OHNE WIEDERKEHR: docker compose up mit dem neuen Release.
#   7. Health ueber nginx. Rot: Rueckweg mit altem current und alten
#      Digests (E-5-175); Zustand und current bleiben alt.
#   8. Gruen: erst current, dann Zustand atomar umstellen (mv -T). Diese
#      Reihenfolge, weil ein Absturz dazwischen dann nur zu einem erneuten
#      Deploy desselben Commits fuehrt, nie zu einem falschen noop.
#   9. Ping an den Totmannschalter bei jedem Ausgang (trap EXIT): Exit 0 auf
#      ok, sonst /fail mit dem Exit-Code. Ausnahme: Sperre belegt.
#
# Exit-Codes (0 bis 8 und 12: am laufenden Stand hat sich nichts geaendert):
#   0   ausgerollt, noop mit gesunder Health oder Sperre belegt
#   2   Voraussetzung, Parameter, Umgebung oder Token
#   3   Nachweis oder Freigabe ungueltig (fetch-release.sh oder Pruef-Gate)
#   4   eine Gegenprobe wurde akzeptiert
#   5   eine Gegenprobe scheiterte am falschen Grund
#   6   ALARM: Downgrade-Regel lehnt ab
#   7   ein Paket ist anonym lesbar oder die Pruefung konnte nicht laufen
#   8   Pull oder Digest-Abgleich gescheitert
#   9   neuer Stand ungesund; Rueckweg erfolgreich, alter Stand laeuft
#   10  KRITISCH: Rueckweg gescheitert oder nicht moeglich
#   11  neuer Stand gesund, aber current oder Zustand nicht geschrieben
#   12  noop, aber der laufende Stand ist ungesund (nichts neu gestartet)
#
# Installation (E-5-117): root-eigen unter /usr/local/lib/identity-service/
# zusammen mit fetch-release.sh, verify-release.sh,
# verify-attestations-server.sh, verify-package-private.sh und lib/. Nie aus
# dem Release-Ordner ausfuehren.
# =============================================================================
set -euo pipefail

# Projektname fest im Skript, nicht aus compose.yaml des Releases: Ein
# Release mit anderem Namen saehe den laufenden Stack sonst nicht, und der
# Rueckweg traefe ein anderes Projekt. Die Restart-Unit (4d-3c) nutzt
# denselben Namen.
readonly COMPOSE_PROJECT="identity-service-staging"
readonly HEALTH_ATTEMPTS=12
readonly HEALTH_DELAY_SECONDS=5

fail_reason=""
fail() {
  fail_reason="$2"
  echo "FEHLER (Exit $1): $2" >&2
  exit "$1"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in fetch-release.sh verify-attestations-server.sh verify-package-private.sh \
  lib/release-rules.sh lib/release-state.sh lib/registry-only.sh; do
  [ -r "${script_dir}/${f}" ] || fail 2 "Datei nicht gefunden: ${script_dir}/${f}"
done
# shellcheck source=lib/release-rules.sh
. "${script_dir}/lib/release-rules.sh"
# shellcheck source=lib/release-state.sh
. "${script_dir}/lib/release-state.sh"
# shellcheck source=lib/registry-only.sh
. "${script_dir}/lib/registry-only.sh"

readonly API_NAME="${REGISTRY_PREFIX}/identity-service"
readonly NGINX_NAME="${REGISTRY_PREFIX}/identity-service-nginx"
readonly LEGO_NAME="${REGISTRY_PREFIX}/identity-service-lego"

# --- Ausgang: Aufraeumen und Ping ---------------------------------------------
ping_url=""
skip_ping="no"
work=""
docker_config=""
on_exit() {
  local rc=$?
  set +e
  if [ -n "${docker_config}" ]; then rm -rf -- "${docker_config}"; fi
  if [ -n "${work}" ]; then rm -rf -- "${work}"; fi
  if [ "${skip_ping}" = "yes" ]; then exit "${rc}"; fi
  if [ -z "${ping_url}" ]; then
    echo "WARNUNG: Ping-URL nicht lesbar, kein Ping gesendet (Totmannschalter alarmiert)." >&2
    exit "${rc}"
  fi
  local target="${ping_url}" body="deploy-staging exit ${rc}"
  if [ "${rc}" -ne 0 ]; then
    target="${ping_url}/fail"
    [ -z "${fail_reason}" ] || body="${body}: ${fail_reason}"
  fi
  # Die URL steht nie in einer Kommandozeile (curl -K -, E-5-55).
  if ! printf 'url = "%s"\n' "${target}" \
    | curl -fsS -m 10 --retry 3 --retry-max-time 30 -o /dev/null -K - --data-binary "${body}"; then
    echo "WARNUNG: Ping fehlgeschlagen." >&2
  fi
  exit "${rc}"
}
trap on_exit EXIT

# --- 0. Voraussetzungen --------------------------------------------------------
echo "== Voraussetzungen"
# Ping-URL zuerst: Ab hier meldet jeder Ausgang sein Ergebnis.
if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -r "${CREDENTIALS_DIRECTORY}/ping-url" ]; then
  candidate="$(cat -- "${CREDENTIALS_DIRECTORY}/ping-url")"
  candidate="${candidate%$'\r'}"
  if [[ "${candidate}" =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9/_-]+$ ]]; then
    ping_url="${candidate}"
  else
    echo "WARNUNG: Ping-URL hat eine unerwartete Form (nicht ausgegeben)." >&2
  fi
  unset candidate
fi

[ "$#" -eq 3 ] || fail 2 "Erwartet: STATE_DIR SWITCH_FILE INSTALL_NGINX_DOCKERFILE (erhalten: $# Parameter)."
state_dir="$1"
switch_file="$2"
install_dockerfile="$3"
for p in "${state_dir}" "${switch_file}" "${install_dockerfile}"; do
  case "${p}" in
    /*) ;;
    *) fail 2 "Pfad muss absolut sein: '${p}'" ;;
  esac
done
[ "$(id -u)" != "0" ] || fail 2 "Darf nicht als root laufen."
for c in docker curl flock timeout readlink sleep; do
  command -v "${c}" >/dev/null 2>&1 || fail 2 "${c} wurde nicht gefunden."
done

[ ! -L "${state_dir}" ] && [ -d "${state_dir}" ] || fail 2 "STATE_DIR fehlt oder ist ein Link: ${state_dir}"
[ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -d "${CREDENTIALS_DIRECTORY}" ] \
  || fail 2 "CREDENTIALS_DIRECTORY fehlt (LoadCredential der Unit)."
[ -n "${RUNTIME_DIRECTORY:-}" ] && [ -d "${RUNTIME_DIRECTORY}" ] && [ ! -L "${RUNTIME_DIRECTORY}" ] \
  || fail 2 "RUNTIME_DIRECTORY fehlt (RuntimeDirectory der Unit)."
[[ "${GHCR_USERNAME:-}" =~ ^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}$ ]] \
  || fail 2 "GHCR_USERNAME fehlt oder ist kein GitHub-Benutzername."
for v in STAGING_SERVER_NAME_FILE STAGING_CA_DIR STAGING_API_CERT_DIR; do
  [[ "${!v:-}" =~ ^/[A-Za-z0-9._/-]+$ ]] || fail 2 "${v} fehlt oder ist kein absoluter Pfad."
done
[ -f "${STAGING_SERVER_NAME_FILE}" ] || fail 2 "STAGING_SERVER_NAME_FILE fehlt: ${STAGING_SERVER_NAME_FILE}"
[ -d "${STAGING_CA_DIR}" ] || fail 2 "STAGING_CA_DIR fehlt: ${STAGING_CA_DIR}"
[ -d "${STAGING_API_CERT_DIR}" ] || fail 2 "STAGING_API_CERT_DIR fehlt: ${STAGING_API_CERT_DIR}"
export STAGING_SERVER_NAME_FILE STAGING_CA_DIR STAGING_API_CERT_DIR

# Servername fuer die Health-Pruefung: genau eine Zeile, wie nginx sie liest.
server_line="$(cat -- "${STAGING_SERVER_NAME_FILE}")"
[[ "${server_line}" =~ ^server_name\ ([a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?)\;$ ]] \
  || fail 2 "STAGING_SERVER_NAME_FILE enthaelt nicht genau 'server_name <name>;'."
server_name="${BASH_REMATCH[1]}"

# Sperre im STATE_DIR, nicht im RuntimeDirectory: Ein Lauf von Hand hat ein
# anderes RuntimeDirectory, aber denselben Zustand.
exec 9>"${state_dir}/.deploy.lock"
if ! flock -n 9; then
  echo "Ein anderer Deploy laeuft; dieser Lauf endet ohne Aenderung."
  skip_ping="yes"
  exit 0
fi
echo "Sperre erhalten"

state_file="${state_dir}/state"
releases_dir="${state_dir}/releases"
current_link="${state_dir}/current"
[ ! -L "${releases_dir}" ] && [ -d "${releases_dir}" ] || fail 2 "Releases-Ordner fehlt oder ist ein Link: ${releases_dir}"

# current muss relativ auf releases/<commit> zeigen; alles andere ist kein
# current von uns.
current_commit=""
read_current() {
  local target
  current_commit=""
  [ -L "${current_link}" ] || return 1
  target="$(readlink -- "${current_link}")" || return 1
  [[ "${target}" =~ ^releases/([0-9a-f]{40})$ ]] || return 1
  [ -d "${releases_dir}/${BASH_REMATCH[1]}" ] || return 1
  current_commit="${BASH_REMATCH[1]}"
}

# NGINX_DOCKERFILE nach E-5-177. Ein vorhandener Zustand ohne gueltiges
# current ist ein Widerspruch: abbrechen statt raten.
if [ -e "${state_file}" ] || [ -L "${state_file}" ]; then
  read_current || fail 2 "Zustand vorhanden, aber current fehlt oder ist ungueltig: ${current_link}"
  nginx_dockerfile="${releases_dir}/${current_commit}/docker/nginx/Dockerfile"
  echo "current: ${current_commit}"
else
  nginx_dockerfile="${install_dockerfile}"
  read_current || true
  echo "kein Zustand; Dockerfile fuer die Gegenprobe aus der Installation"
fi
[ -f "${nginx_dockerfile}" ] && [ ! -L "${nginx_dockerfile}" ] \
  || fail 2 "Dockerfile fuer die Gegenprobe fehlt oder ist ein Link: ${nginx_dockerfile}"

work="$(mktemp -d)"

# --- 1. Anmeldung an der Registry ----------------------------------------------
echo "== Anmeldung"
token_file="${CREDENTIALS_DIRECTORY}/ghcr-token"
[ -r "${token_file}" ] || fail 2 "Credential ghcr-token nicht lesbar."
# $(...) entfernt abschliessende LF; ein CR (Datei aus Windows) einzeln.
token="$(cat -- "${token_file}")"
token="${token%$'\r'}"
# Form des klassischen Tokens (E-5-168). Der Wert wird nie ausgegeben.
if ! [[ "${token}" =~ ^ghp_[A-Za-z0-9]{36}$ ]]; then
  token=""
  fail 2 "Credential ghcr-token hat nicht die Form eines klassischen Tokens (Wert nicht ausgegeben)."
fi
docker_config="${RUNTIME_DIRECTORY}/docker"
rm -rf -- "${docker_config}"
(umask 077 && mkdir -- "${docker_config}")
export DOCKER_CONFIG="${docker_config}"
# printf ist eingebaut: Das Token steht in keiner Kommandozeile.
if ! printf '%s' "${token}" | timeout 60 docker login --username "${GHCR_USERNAME}" --password-stdin ghcr.io >/dev/null; then
  token=""
  fail 2 "docker login an ghcr.io gescheitert."
fi
token=""
echo "angemeldet (DOCKER_CONFIG im RuntimeDirectory)"

# --- 2. Sichtbarkeit -------------------------------------------------------------
echo "== Sichtbarkeit"
for pkg in "${API_NAME}" "${NGINX_NAME}" "${LEGO_NAME}" "${RELEASE_IMAGE_NAME}"; do
  # Anonym: verify-package-private.sh sendet keine Anmeldung.
  bash "${script_dir}/verify-package-private.sh" "${pkg}" "${PUBLIC_COUNTER_PACKAGE}" \
    || fail 7 "Sichtbarkeit nicht belegt: ${pkg}"
done

# --- 3. Freigabe -----------------------------------------------------------------
echo "== Freigabe"
fetch_code=0
bash "${script_dir}/fetch-release.sh" "${state_file}" "${switch_file}" "${releases_dir}" "${nginx_dockerfile}" \
  >"${work}/fetch.out" || fetch_code=$?
cat "${work}/fetch.out"
case "${fetch_code}" in
  0) ;;
  2 | 3 | 4 | 5 | 6) fail "${fetch_code}" "fetch-release.sh Exit ${fetch_code}." ;;
  *) fail 3 "fetch-release.sh endete unerwartet mit Exit ${fetch_code}." ;;
esac

# Genau neun Ergebniszeilen, alle am Ende, feste Reihenfolge.
total="$(grep -c "^release"$'\t' "${work}/fetch.out" || true)"
[ "${total}" = "9" ] || fail 3 "Erwartet genau neun Ergebniszeilen, gefunden ${total:-0}."
keys=()
values=()
while IFS=$'\t' read -r tag key value; do
  [ "${tag}" = "release" ] || fail 3 "Ergebniszeilen stehen nicht am Ende der Ausgabe."
  keys+=("${key}")
  values+=("${value}")
done < <(tail -n 9 "${work}/fetch.out")
[ "${keys[*]}" = "decision dir run attempt commit subject api nginx lego" ] \
  || fail 3 "Ergebnis unvollstaendig oder in unerwarteter Reihenfolge: ${keys[*]}"
decision="${values[0]}"
new_dir="${values[1]}"
new_run="${values[2]}"
new_commit="${values[4]}"
new_bundle="${values[5]}"
new_api="${values[6]}"
new_nginx="${values[7]}"
new_lego="${values[8]}"
release_state_valid_run "${new_run}" || fail 3 "Run-ID ungueltig: '${new_run}'"
release_state_valid_commit "${new_commit}" || fail 3 "Commit ungueltig: '${new_commit}'"
release_state_valid_bundle "${new_bundle}" || fail 3 "Bundle-Digest ungueltig: '${new_bundle}'"
valid_ref() { [[ "$2" =~ ^"$1"@sha256:[0-9a-f]{64}$ ]]; }
valid_ref "${API_NAME}" "${new_api}" || fail 3 "API-Referenz ungueltig: '${new_api}'"
valid_ref "${NGINX_NAME}" "${new_nginx}" || fail 3 "nginx-Referenz ungueltig: '${new_nginx}'"
valid_ref "${LEGO_NAME}" "${new_lego}" || fail 3 "lego-Referenz ungueltig: '${new_lego}'"

# --- Health ----------------------------------------------------------------------
# Ueber nginx wie ein Client, aber an die eigene Adresse (--resolve). Das
# Zertifikat prueft curl gegen den System-Trust-Store (Let's Encrypt).
health() {
  local i
  for ((i = 1; i <= HEALTH_ATTEMPTS; i++)); do
    if curl -fsS -o /dev/null -m 5 --resolve "${server_name}:443:127.0.0.1" "https://${server_name}/health"; then
      echo "Health gruen (Versuch ${i})"
      return 0
    fi
    [ "${i}" -eq "${HEALTH_ATTEMPTS}" ] || sleep "${HEALTH_DELAY_SECONDS}"
  done
  echo "Health rot nach ${HEALTH_ATTEMPTS} Versuchen" >&2
  return 1
}

case "${decision}" in
  noop)
    [ "${new_dir}" = "-" ] || fail 3 "noop mit Release-Ordner: '${new_dir}'"
    echo "== Health (noop)"
    health || fail 12 "Freigabe ist ausgerollt, aber der laufende Stand ist ungesund."
    echo "Nichts zu tun; Stand gesund."
    exit 0
    ;;
  deploy | first) ;;
  *) fail 3 "Unbekannte Entscheidung: '${decision}'" ;;
esac
[ "${new_dir}" = "${releases_dir}/${new_commit}" ] \
  || fail 3 "Release-Ordner passt nicht zum Commit: '${new_dir}'"
[ -d "${new_dir}" ] && [ ! -L "${new_dir}" ] || fail 3 "Release-Ordner fehlt: ${new_dir}"

# --- 4. Pruef-Gate der Images ----------------------------------------------------
echo "== Pruef-Gate"
for ref in "${new_api}" "${new_nginx}" "${new_lego}"; do
  attest_code=0
  bash "${script_dir}/verify-attestations-server.sh" "${ref}" "${nginx_dockerfile}" || attest_code=$?
  case "${attest_code}" in
    0) ;;
    2 | 3 | 4 | 5) fail "${attest_code}" "Pruef-Gate abgelehnt: ${ref}" ;;
    *) fail 3 "verify-attestations-server.sh endete unerwartet mit Exit ${attest_code}: ${ref}" ;;
  esac
done

# --- 5. Pull per Digest ----------------------------------------------------------
echo "== Pull"
for ref in "${new_api}" "${new_nginx}" "${new_lego}"; do
  timeout 300 docker pull --quiet "${ref}" >/dev/null || fail 8 "Pull gescheitert: ${ref}"
  digests="$(timeout 30 docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "${ref}")" \
    || fail 8 "Image nach dem Pull nicht lesbar: ${ref}"
  grep -Fxq -- "${ref}" <<<"${digests}" || fail 8 "Digest nach dem Pull weicht ab: ${ref}"
  echo "ok ${ref}"
done

# --- Rueckweg vorbereiten (vor dem Punkt ohne Wiederkehr) ------------------------
# Alte Digests aus current/deploy/staging.json, Zeile fuer Zeile per Regex
# (kein jq auf dem Server). Die Datei ist byte-gleich mit dem damals
# gepruften Bundle.
old_dir=""
old_api=""
old_nginx=""
old_lego=""
read_old_ref() {
  local key="$1" name="$2" lines ref
  lines="$(grep -E "^[[:space:]]*\"${key}\": \"${name}@sha256:[0-9a-f]{64}\",?$" -- "$3" || true)"
  [ -n "${lines}" ] && [ "$(wc -l <<<"${lines}" | tr -d '[:space:]')" = "1" ] || return 1
  [[ "${lines}" =~ \"([^\"]+)\",?$ ]] || return 1
  # Sofort sichern: valid_ref ueberschreibt BASH_REMATCH.
  ref="${BASH_REMATCH[1]}"
  # Der Punkt in ghcr.io ist im Muster oben ein beliebiges Zeichen; erst
  # valid_ref vergleicht den Namen woertlich.
  valid_ref "${name}" "${ref}" || return 1
  printf '%s' "${ref}"
}
if [ -n "${current_commit}" ] && [ "${current_commit}" != "${new_commit}" ]; then
  old_json="${releases_dir}/${current_commit}/deploy/staging.json"
  if [ -f "${old_json}" ] && [ ! -L "${old_json}" ] \
    && old_api="$(read_old_ref api "${API_NAME}" "${old_json}")" \
    && old_nginx="$(read_old_ref nginx "${NGINX_NAME}" "${old_json}")" \
    && old_lego="$(read_old_ref lego "${LEGO_NAME}" "${old_json}")"; then
    old_dir="${releases_dir}/${current_commit}"
    echo "Rueckweg: ${current_commit}"
  else
    echo "WARNUNG: alte Freigabe in current nicht lesbar; kein Rueckweg moeglich." >&2
  fi
else
  echo "Kein Rueckweg (kein anderes current)."
fi

compose_up() {
  local dir="$1"
  API_IMAGE="$2" NGINX_IMAGE="$3" LEGO_IMAGE="$4" \
    timeout 300 docker compose -p "${COMPOSE_PROJECT}" --project-directory "${dir}" \
    -f "${dir}/compose.yaml" -f "${dir}/compose.staging.yaml" \
    up -d --no-build --pull never --remove-orphans
}

rollback() {
  echo "== Rueckweg" >&2
  [ -n "${old_dir}" ] || fail 10 "KRITISCH: $1; kein Rueckweg moeglich."
  compose_up "${old_dir}" "${old_api}" "${old_nginx}" "${old_lego}" \
    || fail 10 "KRITISCH: $1; Rueckweg (compose up) gescheitert."
  health || fail 10 "KRITISCH: $1; Rueckweg ungesund."
  fail 9 "$1; Rueckweg auf ${current_commit} erfolgreich, Zustand unveraendert."
}

# --- 6. Punkt ohne Wiederkehr ----------------------------------------------------
echo "== compose up ${new_commit}"
compose_up "${new_dir}" "${new_api}" "${new_nginx}" "${new_lego}" \
  || rollback "compose up fuer ${new_commit} gescheitert"

# --- 7. Health -------------------------------------------------------------------
echo "== Health"
health || rollback "Health fuer ${new_commit} rot"

# --- 8. current und Zustand ------------------------------------------------------
echo "== current und Zustand"
tmp_link="${state_dir}/.current.$$.${RANDOM}"
ln -s "releases/${new_commit}" "${tmp_link}" \
  || fail 11 "Neuer Stand gesund, temporaerer Link nicht anlegbar."
if ! mv -T -- "${tmp_link}" "${current_link}"; then
  rm -f -- "${tmp_link}"
  fail 11 "Neuer Stand gesund, current nicht umgestellt (Zustand bleibt alt)."
fi
tmp_state="$(mktemp "${state_dir}/.state.XXXXXX")" \
  || fail 11 "Neuer Stand gesund, current umgestellt, Zustand nicht schreibbar."
if ! release_state_render "${new_run}" "${new_commit}" "${new_bundle}" >"${tmp_state}" \
  || ! chmod 0644 -- "${tmp_state}" || ! mv -T -- "${tmp_state}" "${state_file}"; then
  rm -f -- "${tmp_state}"
  fail 11 "Neuer Stand gesund, current umgestellt, Zustand nicht geschrieben."
fi
echo "Ausgerollt: run ${new_run}, commit ${new_commit}, bundle ${new_bundle}"
if [ "${decision}" = "first" ]; then
  echo "HINWEIS: erster Deploy. Den Erst-Schalter jetzt von Hand loeschen: ${switch_file}"
fi
exit 0
