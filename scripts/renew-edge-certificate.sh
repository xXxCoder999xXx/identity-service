#!/usr/bin/env bash
# =============================================================================
# Server: erneuert das Zertifikat von nginx ("edge") mit lego ueber den
# Webroot und laedt nginx neu (ADR-014, E-5-76, E-5-88).
#
# Aufruf:  ueber identity-service-edge-cert.service (taeglich):
#          bash renew-edge-certificate.sh STATE_DIR [--force]
#          STATE_DIR  StateDirectory des Deploys (current, .deploy.lock)
#          --force    nur von Hand: Erneuerung erzwingen (lego --renew-force),
#                     um den Weg ueber den Webroot zu belegen. Die Unit
#                     uebergibt es nie; ohne Zwang erneuert lego nur, wenn
#                     ARI es vorgibt.
#
# Umgebung (setzt die Unit; keine davon ist ein Secret):
#   CREDENTIALS_DIRECTORY     von LoadCredential: ping-url
#   STAGING_SERVER_NAME_FILE  Datei "server_name <name>;" (E-5-82)
#   STAGING_CA_DIR            interne CA (liest Compose)
#   STAGING_API_CERT_DIR      Zertifikat der API (liest Compose)
#   DOCKER_HOST               Socket des rootless Daemons von deploy
#
# Warum ohne Token und ohne Pull: Compose-Dateien und Digests kommen aus
# current/ (E-5-182). Der Deploy hat diese Images geprueft und per Digest
# gezogen; sie liegen lokal (--pull never). Fehlt eines, scheitert der Lauf.
#
# Ablauf:
#   0. Ping-URL, Parameter, Umgebung, Servername, Docker rootless.
#   1. Sperre des Deploys wartend: nie waehrend eines Deploys.
#   2. current lesen, Freigabe darin lesen.
#   3. Genau ein nginx-Container (ohne laufenden Stack kein HTTP-01 ueber den
#      Webroot); Einmal-Container von lego aus abgebrochenen Laeufen
#      entfernen.
#   4. lego run --http.webroot; danach Einmal-Container per Label entfernen.
#   5. nginx per HUP neu laden, nach jedem erfolgreichen Lauf (billig, ohne
#      Unterbrechung; so ist nie offen, ob ein neues Zertifikat geladen ist).
#      Danach Health ueber nginx.
#   6. Das ausgelieferte Zertifikat muss noch mindestens 14 Tage gelten.
#   7. Ping an den Totmannschalter bei jedem Ausgang (trap EXIT).
#
# Exit-Codes (jeder ungleich 0 geht als /fail an den Totmannschalter):
#   0   geprueft, bei Bedarf erneuert, nginx neu geladen, gesund und das
#       ausgelieferte Zertifikat gilt noch mindestens 14 Tage
#   2   Voraussetzung, Parameter oder Umgebung
#   3   kein gueltiges current oder Freigabe darin unlesbar
#   4   nicht genau ein nginx-Container (Stack laeuft nicht)
#   5   lego gescheitert; das bisherige Zertifikat bleibt geladen
#   6   Sperre nicht rechtzeitig erhalten (Deploy laeuft zu lange)
#   7   docker ps gescheitert (Daemon antwortet nicht)
#   8   nginx nicht neu geladen (docker kill -s HUP gescheitert)
#   9   Einmal-Container von lego vor oder nach dem Lauf vorhanden
#   10  Health nach dem Neuladen rot
#   11  ausgeliefertes Zertifikat gilt keine 14 Tage mehr (Erneuerung oder
#       Neuladen still gescheitert) oder ist nicht lesbar
#
# Installation (E-5-117, E-5-191): root-eigen unter
# /usr/local/lib/identity-service/ mit lib/staging-runtime.sh und
# lib/registry-only.sh.
# =============================================================================
set -euo pipefail

# Zeitbudget unter TimeoutStartSec der Unit (58 Minuten = 3480 s), damit
# systemd nie mitten in lego oder im Aufraeumen abbricht:
#   Sperre 2700 (= TimeoutStartSec des Deploys) + docker info 30 + 4 x docker
#   ps 120 + lego 310 + docker rm 60 + HUP 30 + Health bis 115 + Zertifikat
#   30 = rund 3395 s.
readonly LOCK_WAIT_SECONDS=2700
# Das ausgelieferte Zertifikat muss noch mindestens 14 Tage gelten. Let's
# Encrypt stellt heute fuer 90 Tage aus; ARI legt die Erneuerung etwa auf
# das letzte Drittel. Scheitert die Erneuerung oder das Neuladen still,
# meldet diese Grenze es mit rund zwei Wochen Vorlauf. Bei kuerzeren
# Laufzeiten (von Let's Encrypt angekuendigt) neu bewerten.
readonly MIN_VALID_SECONDS=1209600

fail_reason=""
fail() {
  fail_reason="$2"
  echo "FEHLER (Exit $1): $2" >&2
  exit "$1"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in lib/staging-runtime.sh lib/registry-only.sh; do
  [ -r "${script_dir}/${f}" ] || fail 2 "Datei nicht gefunden: ${script_dir}/${f}"
done
# shellcheck source=lib/staging-runtime.sh
. "${script_dir}/lib/staging-runtime.sh"
# REGISTRY_PREFIX (E-5-122).
# shellcheck source=lib/registry-only.sh
. "${script_dir}/lib/registry-only.sh"

readonly API_NAME="${REGISTRY_PREFIX}/identity-service"
readonly NGINX_NAME="${REGISTRY_PREFIX}/identity-service-nginx"
readonly LEGO_NAME="${REGISTRY_PREFIX}/identity-service-lego"

# --- Ausgang: Ping ---------------------------------------------------------------
on_exit() {
  local rc=$?
  set +e
  local body="renew-edge-certificate exit ${rc}"
  if [ "${rc}" -ne 0 ] && [ -n "${fail_reason}" ]; then body="${body}: ${fail_reason}"; fi
  staging_ping "${rc}" "${body}"
  exit "${rc}"
}
trap on_exit EXIT

# --- 0. Voraussetzungen --------------------------------------------------------
echo "== Voraussetzungen"
# Ping-URL zuerst: Ab hier meldet jeder Ausgang sein Ergebnis.
staging_read_ping_url

force="no"
case "$#" in
  1) ;;
  2) [ "$2" = "--force" ] || fail 2 "Zweiter Parameter darf nur --force sein: '$2'"
     force="yes" ;;
  *) fail 2 "Erwartet: STATE_DIR [--force] (erhalten: $# Parameter)." ;;
esac
state_dir="$1"
case "${state_dir}" in
  /*) ;;
  *) fail 2 "Pfad muss absolut sein: '${state_dir}'" ;;
esac
[ "$(id -u)" != "0" ] || fail 2 "Darf nicht als root laufen."
for c in docker curl flock timeout readlink sleep openssl; do
  command -v "${c}" >/dev/null 2>&1 || fail 2 "${c} wurde nicht gefunden."
done
[ ! -L "${state_dir}" ] && [ -d "${state_dir}" ] || fail 2 "STATE_DIR fehlt oder ist ein Link: ${state_dir}"
for v in STAGING_SERVER_NAME_FILE STAGING_CA_DIR STAGING_API_CERT_DIR; do
  [[ "${!v:-}" =~ ^/[A-Za-z0-9._/-]+$ ]] || fail 2 "${v} fehlt oder ist kein absoluter Pfad."
done
[ -d "${STAGING_CA_DIR}" ] || fail 2 "STAGING_CA_DIR fehlt: ${STAGING_CA_DIR}"
[ -d "${STAGING_API_CERT_DIR}" ] || fail 2 "STAGING_API_CERT_DIR fehlt: ${STAGING_API_CERT_DIR}"
export STAGING_SERVER_NAME_FILE STAGING_CA_DIR STAGING_API_CERT_DIR
staging_read_server_name "${STAGING_SERVER_NAME_FILE}" || fail 2 "Servername nicht lesbar (Grund oben)."
staging_require_rootless || fail 2 "Docker-Pruefung gescheitert (Grund oben)."

# --- 1. Sperre -------------------------------------------------------------------
echo "== Sperre"
exec 9>"${state_dir}/.deploy.lock" || fail 2 "Sperrdatei nicht anlegbar: ${state_dir}/.deploy.lock"
flock -w "${LOCK_WAIT_SECONDS}" 9 || fail 6 "Sperre nach ${LOCK_WAIT_SECONDS} s nicht erhalten (Deploy laeuft?)."
echo "Sperre erhalten"

# --- 2. current und Freigabe -----------------------------------------------------
echo "== current"
staging_read_current "${state_dir}" || fail 3 "current fehlt oder ist ungueltig (noch kein Deploy?)."
release_dir="${state_dir}/releases/${STAGING_CURRENT_COMMIT}"
release_json="${release_dir}/deploy/staging.json"
for f in "${release_dir}/compose.yaml" "${release_dir}/compose.staging.yaml" "${release_json}"; do
  [ -f "${f}" ] && [ ! -L "${f}" ] || fail 3 "Datei in current fehlt oder ist ein Link: ${f}"
done
api_ref="$(staging_release_ref api "${API_NAME}" "${release_json}")" || fail 3 "API-Referenz in current unlesbar."
nginx_ref="$(staging_release_ref nginx "${NGINX_NAME}" "${release_json}")" || fail 3 "nginx-Referenz in current unlesbar."
lego_ref="$(staging_release_ref lego "${LEGO_NAME}" "${release_json}")" || fail 3 "lego-Referenz in current unlesbar."
echo "current ${STAGING_CURRENT_COMMIT}"

# --- 3. nginx und Einmal-Container -----------------------------------------------
echo "== nginx"
ids="$(staging_container_ids "com.docker.compose.service=nginx" "com.docker.compose.oneoff=False")" \
  || fail 7 "docker ps gescheitert."
count="$(grep -c . <<<"${ids}" || true)"
[ "${count}" = "1" ] || fail 4 "Erwartet genau einen nginx-Container im Projekt ${STAGING_COMPOSE_PROJECT}, gefunden ${count}."
[[ "${ids}" =~ ^[0-9a-f]{64}$ ]] || fail 4 "docker ps lieferte keine Container-ID."
nginx_id="${ids}"
# Uebrige Einmal-Container von lego koennen nur aus einem eigenen,
# abgebrochenen Lauf stammen (Timeout der Unit, Neustart des Servers): Nur
# Deploy und diese Unit starten lego, beide unter der Sperre. Deshalb hier
# aufraeumen statt jeden Tag mit Exit 9 zu stehen.
staging_remove_lego_oneoffs
leftovers="$(staging_container_ids "com.docker.compose.service=lego" "com.docker.compose.oneoff=True")" \
  || fail 7 "docker ps gescheitert."
[ -z "${leftovers}" ] || fail 9 "Einmal-Container von lego vor dem Lauf nicht entfernbar; von Hand pruefen."
echo "nginx-Container ${nginx_id:0:12}"

# --- 4. lego ---------------------------------------------------------------------
# Webroot statt Standalone: nginx beantwortet die Pruefung aus dem Volume
# acme-webroot (E-5-83); lego braucht keinen Port. Keine E-Mail (E-5-66),
# Name "edge" (E-5-82), Konto aus dem Volume (CAA accounturi).
echo "== lego"
lego_args=(run --path /data --accept-tos --http --http.webroot /webroot
  --cert.name edge --domains "${STAGING_SERVER_NAME}")
[ "${force}" = "no" ] || lego_args+=(--renew-force)
lego_code=0
API_IMAGE="${api_ref}" NGINX_IMAGE="${nginx_ref}" LEGO_IMAGE="${lego_ref}" \
  timeout --kill-after=10 300 docker compose -p "${STAGING_COMPOSE_PROJECT}" --project-directory "${release_dir}" \
  -f "${release_dir}/compose.yaml" -f "${release_dir}/compose.staging.yaml" --profile acme \
  run --rm -T --pull never lego "${lego_args[@]}" || lego_code=$?
staging_remove_lego_oneoffs
leftovers="$(staging_container_ids "com.docker.compose.service=lego" "com.docker.compose.oneoff=True")" \
  || fail 7 "docker ps gescheitert (nach lego)."
[ -z "${leftovers}" ] || fail 9 "Einmal-Container von lego nach dem Lauf nicht entfernt."
[ "${lego_code}" = "0" ] || fail 5 "lego gescheitert (Exit ${lego_code}); bisheriges Zertifikat bleibt geladen."

# --- 5. nginx neu laden und Health ---------------------------------------------
# HUP an PID 1 des Containers: nginx liest Konfiguration und Zertifikate neu,
# bestehende Verbindungen laufen weiter. Kein exec in den Container.
echo "== nginx neu laden"
timeout 30 docker kill -s HUP "${nginx_id}" >/dev/null || fail 8 "nginx nicht neu geladen (docker kill -s HUP)."
echo "== Health"
staging_health || fail 10 "Health nach dem Neuladen rot."

# --- 6. Ausgeliefertes Zertifikat ----------------------------------------------
# HUP belegt nur, dass das Signal ankam. Lehnt nginx das Neuladen ab, liefert
# es still das alte Zertifikat aus, und die Health bleibt gruen. Gemessen
# wird deshalb, was ein Client bekommt: dasselbe Zertifikat wie von aussen
# (SNI mit dem Servernamen, an die eigene Adresse).
echo "== Ausgeliefertes Zertifikat"
timeout 30 openssl s_client -connect 127.0.0.1:443 -servername "${STAGING_SERVER_NAME}" </dev/null 2>/dev/null \
  | openssl x509 -noout -checkend "${MIN_VALID_SECONDS}" >/dev/null \
  || fail 11 "Ausgeliefertes Zertifikat gilt keine 14 Tage mehr oder ist nicht lesbar (Erneuerung oder Neuladen gescheitert?)."
echo "Zertifikat geprueft, nginx neu geladen, gesund und noch mindestens 14 Tage gueltig"
