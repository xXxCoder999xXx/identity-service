# shellcheck shell=bash
# =============================================================================
# Gemeinsame Laufzeit-Pruefungen fuer den laufenden Staging-Stack
# (ADR-017). Bibliothek: wird per "source" geladen und setzt beim Laden nur
# Konstanten.
#
# Einstiege:
#   scripts/deploy-staging.sh   Pull-Deploy (PR 4d-3a)
#   scripts/restart-api.sh      API-Neustart nach Zertifikatserneuerung (4d-3c)
#
# Warum eine Bibliothek: Beide Einstiege muessen denselben Daemon, denselben
# Projektnamen und dieselbe Health-Pruefung verwenden. Stuende das zweimal
# da, koennte ein Neustart einen anderen Stack treffen oder anders "gesund"
# bewerten als der Deploy (eine Quelle der Wahrheit).
#
# Kein exit in dieser Datei: Die Funktionen melden ueber den Rueckgabewert
# und stderr; der Einstieg entscheidet, wie er abbricht.
# =============================================================================

# Projektname fest, nicht aus compose.yaml des Releases: Ein Release mit
# anderem Namen saehe den laufenden Stack sonst nicht, Rueckweg und Neustart
# traefen ein anderes Projekt.
readonly STAGING_COMPOSE_PROJECT="identity-service-staging"
readonly STAGING_API_SERVICE="api"
readonly STAGING_HEALTH_ATTEMPTS=12
readonly STAGING_HEALTH_DELAY_SECONDS=5

# staging_require_rootless
# Rueckgabe 0 nur, wenn der Daemon hinter DOCKER_HOST rootless laeuft
# (E-5-112). Vor jeder Weitergabe von Token oder Befehlen an den Daemon.
staging_require_rootless() {
  local security
  security="$(timeout 30 docker info --format '{{.SecurityOptions}}')" \
    || { echo "docker info gescheitert (Daemon nicht erreichbar?)." >&2; return 1; }
  [[ " ${security//[\[\]]/ } " == *" name=rootless "* ]] \
    || { echo "Docker laeuft nicht rootless: ${security}" >&2; return 1; }
  echo "docker rootless"
}

# staging_read_server_name DATEI
# Liest genau eine Zeile "server_name <name>;" (E-5-82), wie nginx sie
# einbindet, und setzt STAGING_SERVER_NAME.
staging_read_server_name() {
  local line
  STAGING_SERVER_NAME=""
  [ -f "${1-}" ] || { echo "Datei mit server_name fehlt: '${1-}'" >&2; return 1; }
  line="$(cat -- "$1")" || return 1
  [[ "${line}" =~ ^server_name\ ([a-z0-9]([a-z0-9.-]{0,251}[a-z0-9])?)\;$ ]] \
    || { echo "STAGING_SERVER_NAME_FILE enthaelt nicht genau 'server_name <name>;'." >&2; return 1; }
  STAGING_SERVER_NAME="${BASH_REMATCH[1]}"
}

# staging_health
# Health ueber nginx wie ein Client, aber an die eigene Adresse (--resolve).
# Das Zertifikat prueft curl gegen den System-Trust-Store (Let's Encrypt).
# Braucht STAGING_SERVER_NAME.
staging_health() {
  local i
  [ -n "${STAGING_SERVER_NAME:-}" ] || { echo "Servername nicht gesetzt." >&2; return 1; }
  for ((i = 1; i <= STAGING_HEALTH_ATTEMPTS; i++)); do
    if curl -fsS -o /dev/null -m 5 --resolve "${STAGING_SERVER_NAME}:443:127.0.0.1" \
      "https://${STAGING_SERVER_NAME}/health"; then
      echo "Health gruen (Versuch ${i})"
      return 0
    fi
    [ "${i}" -eq "${STAGING_HEALTH_ATTEMPTS}" ] || sleep "${STAGING_HEALTH_DELAY_SECONDS}"
  done
  echo "Health rot nach ${STAGING_HEALTH_ATTEMPTS} Versuchen" >&2
  return 1
}

# staging_container_ids [LABEL=WERT ...]
# Gibt die vollen IDs aller Container (auch gestoppter, "ps -a") des
# Staging-Projekts aus, eine je Zeile; weitere Labels schraenken ein. Das
# Projekt-Label steht immer dabei: So kann kein Aufrufer versehentlich
# Container eines anderen Projekts zaehlen. Rueckgabe ungleich 0, wenn
# docker ps scheitert oder ein Argument nicht die Form LABEL=WERT hat; die
# Ausgabe ist dann nicht zu verwenden. Ein nackter Schluessel waere fail
# open: docker filtert dann nur auf das Vorhandensein des Labels (etwa
# oneoff=True und oneoff=False zugleich). Die Form der IDs prueft der
# Aufrufer, der sie weiterverwendet.
staging_container_ids() {
  local -a filters=(--filter "label=com.docker.compose.project=${STAGING_COMPOSE_PROJECT}")
  local label
  for label in "$@"; do
    [[ "${label}" =~ ^[A-Za-z0-9._-]+=[^[:space:]]+$ ]] \
      || { echo "Label-Filter nicht in der Form LABEL=WERT: '${label}'" >&2; return 1; }
    filters+=(--filter "label=${label}")
  done
  timeout 30 docker ps -a -q --no-trunc "${filters[@]}"
}
