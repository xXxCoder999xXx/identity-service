#!/usr/bin/env bash
# =============================================================================
# Server: startet den API-Container von Staging neu und prueft danach die
# Health ueber nginx (ADR-017, PR 4d-3c, E-5-97, E-5-120).
#
# Aufruf:  nur ueber identity-service-api-restart.service:
#          bash restart-api.sh STATE_DIR
#          STATE_DIR  StateDirectory des Deploys; enthaelt .deploy.lock
#
# Umgebung (setzt die Unit):
#   STAGING_SERVER_NAME_FILE  Datei "server_name <name>;" (E-5-82)
#   DOCKER_HOST               Socket des rootless Daemons von deploy
#
# Warum: Nach einer Erneuerung des API-Zertifikats liest die API das neue
# Zertifikat erst nach einem Neustart, bis gemessen ist, ob Kestrel selbst
# neu laedt (E-5-97). Aufgerufen wird die Unit von renew-api-certificate.sh
# per systemctl start (E-5-178); der Exit-Code geht dort an /fail (E-5-101).
#
# Ablauf:
#   0. Parameter, Servername, Docker rootless (E-5-112).
#   1. Dieselbe Sperre wie der Deploy, wartend (hoechstens 50 Minuten): Ein
#      Neustart mitten in compose up wuerde den Deploy stoeren.
#   2. Genau einen API-Container ueber die Compose-Labels finden (Projekt aus
#      lib/staging-runtime.sh), ohne Einmal-Container aus "compose run"
#      (oneoff). Unabhaengig von Compose-Dateien und Digests.
#   3. docker restart, danach Health ueber nginx.
#
# Exit-Codes (jeder ungleich 0 meldet renew-api-certificate.sh als /fail):
#   0  neu gestartet und gesund
#   2  Voraussetzung oder Parameter fehlt bzw. ist ungueltig
#   3  nicht genau ein API-Container (etwa vor dem ersten Deploy)
#   4  Neustart gescheitert
#   5  Health nach dem Neustart rot
#   6  Sperre nicht rechtzeitig erhalten (Deploy laeuft zu lange)
#   7  docker ps gescheitert (Daemon antwortet nicht)
#
# Installation (E-5-117): root-eigen unter /usr/local/lib/identity-service/
# mit lib/staging-runtime.sh.
# =============================================================================
set -euo pipefail

# Wartezeit auf die Sperre: unter TimeoutStartSec der Unit (58 Minuten) und
# ueber TimeoutStartSec des Deploys (45 Minuten).
readonly LOCK_WAIT_SECONDS=3000

fail() {
  echo "FEHLER (Exit $1): $2" >&2
  exit "$1"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -r "${script_dir}/lib/staging-runtime.sh" ] || fail 2 "Datei nicht gefunden: ${script_dir}/lib/staging-runtime.sh"
# shellcheck source=lib/staging-runtime.sh
. "${script_dir}/lib/staging-runtime.sh"

# --- 0. Voraussetzungen --------------------------------------------------------
echo "== Voraussetzungen"
[ "$#" -eq 1 ] || fail 2 "Erwartet: STATE_DIR (erhalten: $# Parameter)."
state_dir="$1"
case "${state_dir}" in
  /*) ;;
  *) fail 2 "Pfad muss absolut sein: '${state_dir}'" ;;
esac
[ "$(id -u)" != "0" ] || fail 2 "Darf nicht als root laufen."
for c in docker curl flock timeout sleep; do
  command -v "${c}" >/dev/null 2>&1 || fail 2 "${c} wurde nicht gefunden."
done
[ ! -L "${state_dir}" ] && [ -d "${state_dir}" ] || fail 2 "STATE_DIR fehlt oder ist ein Link: ${state_dir}"
[[ "${STAGING_SERVER_NAME_FILE:-}" =~ ^/[A-Za-z0-9._/-]+$ ]] \
  || fail 2 "STAGING_SERVER_NAME_FILE fehlt oder ist kein absoluter Pfad."
staging_read_server_name "${STAGING_SERVER_NAME_FILE}" || fail 2 "Servername nicht lesbar (Grund oben)."
staging_require_rootless || fail 2 "Docker-Pruefung gescheitert (Grund oben)."

# --- 1. Sperre -------------------------------------------------------------------
echo "== Sperre"
exec 9>"${state_dir}/.deploy.lock" || fail 2 "Sperrdatei nicht anlegbar: ${state_dir}/.deploy.lock"
flock -w "${LOCK_WAIT_SECONDS}" 9 || fail 6 "Sperre nach ${LOCK_WAIT_SECONDS} s nicht erhalten (Deploy laeuft?)."
echo "Sperre erhalten"

# --- 2. API-Container ------------------------------------------------------------
echo "== API-Container"
ids="$(timeout 30 docker ps -a -q --no-trunc \
  --filter "label=com.docker.compose.project=${STAGING_COMPOSE_PROJECT}" \
  --filter "label=com.docker.compose.service=${STAGING_API_SERVICE}" \
  --filter "label=com.docker.compose.oneoff=False")" \
  || fail 7 "docker ps gescheitert."
count="$(grep -c . <<<"${ids}" || true)"
[ "${count}" = "1" ] || fail 3 "Erwartet genau einen API-Container im Projekt ${STAGING_COMPOSE_PROJECT}, gefunden ${count}."
[[ "${ids}" =~ ^[0-9a-f]{64}$ ]] || fail 3 "docker ps lieferte keine Container-ID."
echo "API-Container ${ids:0:12}"

# --- 3. Neustart und Health ------------------------------------------------------
echo "== Neustart"
timeout 120 docker restart "${ids}" >/dev/null || fail 4 "docker restart gescheitert."
echo "== Health"
staging_health || fail 5 "API nach dem Neustart ungesund."
echo "API neu gestartet und gesund"
