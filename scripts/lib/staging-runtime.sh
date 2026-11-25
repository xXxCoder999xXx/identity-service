# shellcheck shell=bash
# =============================================================================
# Gemeinsame Laufzeit-Pruefungen fuer den laufenden Staging-Stack
# (ADR-017). Bibliothek: wird per "source" geladen und setzt beim Laden nur
# Konstanten.
#
# Einstiege:
#   scripts/deploy-staging.sh   Pull-Deploy (PR 4d-3a)
#   scripts/restart-api.sh      API-Neustart nach Zertifikatserneuerung (4d-3c)
#   scripts/renew-edge-certificate.sh  Erneuerung nginx-Zertifikat (E-5-76)
#
# Warum eine Bibliothek: Alle Einstiege muessen denselben Daemon, denselben
# Projektnamen, dieselbe Container-Suche und dieselbe Health-Pruefung
# verwenden. Stuende das zweimal da, koennte ein Neustart einen anderen
# Stack treffen oder anders "gesund" bewerten als der Deploy (eine Quelle
# der Wahrheit).
#
# Inhalt:
#   staging_require_rootless   Daemon rootless (E-5-112)
#   staging_read_server_name   setzt STAGING_SERVER_NAME (E-5-82)
#   staging_health             Health ueber nginx
#   staging_container_ids      Container des Projekts per Label
#   staging_remove_lego_oneoffs  Einmal-Container von lego entfernen
#   staging_valid_ref          Referenz "NAME@sha256:<64 hex>"
#   staging_read_current       setzt STAGING_CURRENT_COMMIT aus STATE_DIR/current
#   staging_release_ref        Referenz aus deploy/staging.json (E-5-182)
#   staging_read_ping_url      setzt STAGING_PING_URL aus dem Credential
#   staging_ping               Ping an den Totmannschalter (ADR-013, E-5-55)
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

# staging_remove_lego_oneoffs
# Entfernt Einmal-Container ("compose run") des Dienstes lego in diesem
# Projekt, per Label, nie per Name: Ein fremder Container mit gleichem Namen
# bleibt unberuehrt (Melden statt reparieren). Nur unter der Sperre des
# Deploys aufrufen: Nur Deploy und Erneuerung starten lego, beide unter der
# Sperre; jeder Treffer stammt also aus einem eigenen Lauf (etwa nach Abbruch
# durch timeout oder Neustart). Rueckgabe immer 0; das Urteil faellt danach
# mit staging_container_ids.
staging_remove_lego_oneoffs() {
  local ids id
  ids="$(staging_container_ids "com.docker.compose.service=lego" "com.docker.compose.oneoff=True")" || return 0
  while read -r id; do
    [[ "${id}" =~ ^[0-9a-f]{64}$ ]] || continue
    timeout 60 docker rm -f "${id}" >/dev/null 2>&1 || true
  done <<<"${ids}"
}

# staging_valid_ref NAME REF
# Rueckgabe 0 nur fuer genau "NAME@sha256:<64 hex>"; NAME wird woertlich
# verglichen. Achtung: ueberschreibt BASH_REMATCH.
staging_valid_ref() { [[ "$2" =~ ^"$1"@sha256:[0-9a-f]{64}$ ]]; }

# staging_read_current STATE_DIR
# Setzt STAGING_CURRENT_COMMIT, wenn STATE_DIR/current relativ auf
# releases/<commit> zeigt und der Ordner existiert; alles andere ist kein
# current von uns (Rueckgabe 1, STAGING_CURRENT_COMMIT leer).
staging_read_current() {
  local target
  STAGING_CURRENT_COMMIT=""
  [ -L "$1/current" ] || return 1
  target="$(readlink -- "$1/current")" || return 1
  [[ "${target}" =~ ^releases/([0-9a-f]{40})$ ]] || return 1
  [ -d "$1/releases/${BASH_REMATCH[1]}" ] || return 1
  STAGING_CURRENT_COMMIT="${BASH_REMATCH[1]}"
}

# staging_release_ref KEY NAME DATEI
# Gibt die Referenz zu KEY aus einer Freigabe deploy/staging.json aus (E-5-182):
# Zeile fuer Zeile per Regex (kein jq auf dem Server), genau eine Zeile,
# Name woertlich verglichen. Die Datei ist byte-gleich mit dem gepruften
# Bundle; ihr Format prueft verify-release-file.sh vor dem Merge.
staging_release_ref() {
  local key="$1" name="$2" lines ref
  lines="$(grep -E "^[[:space:]]*\"${key}\": \"${name}@sha256:[0-9a-f]{64}\",?$" -- "$3" || true)"
  [ -n "${lines}" ] && [ "$(wc -l <<<"${lines}" | tr -d '[:space:]')" = "1" ] || return 1
  [[ "${lines}" =~ \"([^\"]+)\",?$ ]] || return 1
  # Sofort sichern: staging_valid_ref ueberschreibt BASH_REMATCH.
  ref="${BASH_REMATCH[1]}"
  # Der Punkt in ghcr.io ist im Muster oben ein beliebiges Zeichen; erst
  # staging_valid_ref vergleicht den Namen woertlich.
  staging_valid_ref "${name}" "${ref}" || return 1
  printf '%s' "${ref}"
}

# staging_read_ping_url
# Liest CREDENTIALS_DIRECTORY/ping-url (LoadCredential, ADR-013) und setzt
# STAGING_PING_URL; fehlt sie oder hat sie eine unerwartete Form, bleibt sie
# leer (Warnung ohne den Wert). Ohne Ping alarmiert der Totmannschalter.
staging_read_ping_url() {
  local candidate
  STAGING_PING_URL=""
  if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -r "${CREDENTIALS_DIRECTORY}/ping-url" ]; then
    candidate="$(cat -- "${CREDENTIALS_DIRECTORY}/ping-url")" \
      || { echo "WARNUNG: Ping-URL nicht lesbar, kein Ping." >&2; return 0; }
    candidate="${candidate%$'\r'}"
    if [[ "${candidate}" =~ ^https://[A-Za-z0-9.-]+/[A-Za-z0-9/_-]+$ ]]; then
      STAGING_PING_URL="${candidate}"
    else
      echo "WARNUNG: Ping-URL hat eine unerwartete Form (nicht ausgegeben)." >&2
    fi
  fi
}

# staging_ping EXITCODE TEXT
# Meldet an den Totmannschalter: Exit 0 auf die URL, sonst auf URL/fail; TEXT
# als Inhalt. Die URL steht nie in einer Kommandozeile (curl -K -, E-5-55).
# Scheitert der Ping, nur Warnung: Das Ausbleiben alarmiert ohnehin.
staging_ping() {
  local target
  if [ -z "${STAGING_PING_URL:-}" ]; then
    echo "WARNUNG: Ping-URL nicht lesbar, kein Ping gesendet (Totmannschalter alarmiert)." >&2
    return 0
  fi
  target="${STAGING_PING_URL}"
  [ "$1" -eq 0 ] || target="${STAGING_PING_URL}/fail"
  if ! printf 'url = "%s"\n' "${target}" \
    | curl -fsS -m 10 --retry 3 --retry-max-time 30 -o /dev/null -K - --data-binary "$2"; then
    echo "WARNUNG: Ping fehlgeschlagen." >&2
  fi
}
