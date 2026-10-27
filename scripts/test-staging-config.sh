#!/usr/bin/env bash
# =============================================================================
# Prueft die zusammengefuehrte Staging-Konfiguration (E-5-79, E-5-91).
#
# Aufruf:  bash scripts/test-staging-config.sh
#          Erwartet die Pflichtvariablen aus compose.staging.yaml (API_IMAGE,
#          LEGO_IMAGE, STAGING_*) in der Umgebung.
#
# Geprueft wird, was Compose aus compose.yaml und compose.staging.yaml
# ZUSAMMENBAUT ("docker compose config"), nicht der Text der Dateien. Nur so
# faellt auf, wenn beim Zusammenfuehren eine Liste angehaengt statt ersetzt
# wird oder Haertung aus der Basis verloren geht.
#
# Warum ein Skript: Die CI prueft damit jeden Pull Request, und der Server
# fuehrt dasselbe Skript vor dem Start aus (Pull-Deploy). Die Regeln stehen an
# EINER Stelle.
#
# Exit-Codes (jeder ungleich 0 ist ein Fehlschlag - fail closed):
#   0  alle Pruefungen bestanden
#   2  Voraussetzung fehlt, oder Compose kann die Konfiguration nicht rendern
#   3  eine Pruefung ist verletzt
#   4  Gegenprobe: Compose rendert trotz fehlender Pflichtvariable
#
# Geschrieben fuer Linux (Runner, Server). Braucht docker (mit compose) und jq.
# =============================================================================
set -euo pipefail

# Abbruch mit eindeutiger Meldung. "::error::" hebt die Zeile im Protokoll von
# GitHub Actions hervor; auf dem Server ist es gewoehnlicher Text.
fail() {
  echo "::error::$2" >&2
  exit "$1"
}

# Die Compose-Dateien liegen in der Wurzel des Repositories.
cd "$(dirname "$0")/.."

command -v docker >/dev/null 2>&1 || fail 2 "docker wurde nicht gefunden."
command -v jq >/dev/null 2>&1 || fail 2 "jq wurde nicht gefunden. Ohne jq kann nichts geprueft werden."

# Profil "acme" aktiv, damit lego in der gerenderten Konfiguration erscheint
# und ebenfalls geprueft wird.
staging=(--file compose.yaml --file compose.staging.yaml --profile acme)

config="$(docker compose "${staging[@]}" config --format json)" \
  || fail 2 "Compose kann die Staging-Konfiguration nicht rendern (fehlt eine Pflichtvariable?)."

# Ein jq-Ausdruck, der "true" liefern muss. --exit-status macht false und null
# zu einem Fehlschlag.
check() {
  if jq --exit-status "$2" <<<"${config}" >/dev/null; then
    echo "ok  $1"
  else
    fail 3 "Verletzt: $1"
  fi
}

# Eine Bedingung fuer JEDEN Dienst; die Meldung nennt die Dienste, die sie
# verletzen.
check_each() {
  local violators
  violators="$(jq --raw-output \
    "[.services | to_entries[] | select(.value | ($2) | not) | .key] | join(\", \")" \
    <<<"${config}")"
  if [ -z "${violators}" ]; then
    echo "ok  $1"
  else
    fail 3 "Verletzt: $1 (Dienste: ${violators})"
  fi
}

# 1. Staging baut nie selbst: dasselbe Image wie in CI und Production.
check_each "kein Dienst hat build" 'has("build") | not'

# 2. Pins per Inhalt statt Zeiger (A03).
check_each "jedes Image per Digest" '(.image // "") | test("@sha256:[0-9a-f]{64}$")'

# 3. Nur nginx ist von aussen erreichbar, genau auf 80 und 443, nur IPv4.
check "nur nginx veroeffentlicht Ports" \
  '[.services | to_entries[] | select(.key != "nginx") | (.value.ports // []) | length] | all(. == 0)'
check "nginx: genau 80->8080 und 443->8443 auf 0.0.0.0" \
  '[.services.nginx.ports[] | "\(.host_ip)|\(.published)|\(.target)|\(.protocol)"] | sort
   == ["0.0.0.0|443|8443|tcp", "0.0.0.0|80|8080|tcp"]'

# 4. Haertung je Dienst; aus der Basis geerbt oder (lego) hier gesetzt.
check_each "read_only" '.read_only == true'
check_each "cap_drop ALL" '.cap_drop == ["ALL"]'
check_each "no-new-privileges" 'any(.security_opt[]?; . == "no-new-privileges:true")'
check_each "mem_limit" '.mem_limit != null'
check_each "cpus" '.cpus != null'
check_each "pids_limit" '.pids_limit != null'

# 5. Kein Entwicklungsmodus: Development zeigt Stacktraces an Clients (A10).
check "api: ASPNETCORE_ENVIRONMENT ist Production" \
  '.services.api.environment.ASPNETCORE_ENVIRONMENT == "Production"'

# 6. lego laeuft nur auf Abruf, als UID 101 und nur im Netz nach aussen.
check "lego: nur im Profil acme" '.services.lego.profiles == ["acme"]'
check "lego: UID 101" '.services.lego.user == "101:101"'
check "lego: nur Netz public" '(.services.lego.networks | keys) == ["public"]'

# 7. nginx liest nur; den Konto-Schluessel sieht nur lego (E-5-75).
check "nginx: alle Mounts read_only" '[.services.nginx.volumes[] | .read_only == true] | all'
check "lego-accounts nur bei lego" \
  '[.services | to_entries[] | select(.key != "lego") | .value.volumes[]?
    | select(.type == "volume" and .source == "lego-accounts")] | length == 0'

# 8. Gegenprobe: Ohne Pflichtvariable darf Compose nicht rendern. Sonst wuerde
# der Server mit leerem Wert starten statt abzubrechen.
if env -u API_IMAGE docker compose "${staging[@]}" config --quiet 2>/dev/null; then
  fail 4 "Gegenprobe: Compose rendert ohne API_IMAGE. Die Variable ist nicht mehr Pflicht."
fi
echo "ok  Gegenprobe: ohne API_IMAGE bricht Compose ab"

echo "Staging-Konfiguration bestanden."
