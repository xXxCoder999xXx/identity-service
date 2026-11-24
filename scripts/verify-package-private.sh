#!/usr/bin/env bash
# =============================================================================
# Prueft, dass ein Paket in der GitHub Container Registry anonym NICHT lesbar
# ist (E-5-115, E-5-131).
#
# Aufruf:  bash scripts/verify-package-private.sh IMAGE_NAME [PUBLIC_PACKAGE]
#          IMAGE_NAME      Name in der Registry ohne Tag, z. B. ghcr.io/owner/name
#          PUBLIC_PACKAGE  optional: bekannt oeffentliches Paket fuer die
#                          Gegenprobe, gleiche Form. Fehlt es, gilt das Paket
#                          aus compose.scan.yaml (CI). Der Server uebergibt
#                          PUBLIC_COUNTER_PACKAGE aus lib/registry-only.sh,
#                          weil er keine Repository-Wurzel hat (E-5-171).
#
# Warum: Neue Pakete aus diesem Repository waren dreimal oeffentlich, ohne
# dass jemand umgestellt hat (Sitzung 27, lego und nginx; gemessen am
# 2026-11-10), entgegen der GitHub-Doku ("default private"). Die Pruefung
# verhindert nichts - das Image liegt beim Aufruf schon in der Registry -,
# meldet es aber sofort statt erst beim Deploy.
#
# Wie: Der Token-Endpunkt der Registry wird OHNE Anmeldung gefragt. Gemessen:
#   privat          401
#   nicht vorhanden 403
#   oeffentlich     200
# Nur 401 besteht. Nach dem Hochladen existiert das Paket; 403 waere deshalb
# unerwartet und zaehlt ebenfalls als Fehlschlag (fail closed).
#
# Gegenprobe zuerst: Ein bekannt oeffentliches Paket muss 200 liefern, sonst
# kann diese Pruefung "oeffentlich" gar nicht erkennen (etwa weil die Registry
# ihr Verhalten geaendert hat). Quelle ist der gepinnte Scanner aus
# compose.scan.yaml - eine Quelle der Wahrheit, die Dependabot pflegt - oder
# PUBLIC_PACKAGE. Wird das Vergleichspaket privat oder geloescht, endet die
# Pruefung mit Exit 4 (fail closed), bis die Quelle angepasst ist.
#
# Warum ein Skript: Alle Veroeffentlichungs-Workflows (publish.yml,
# publish-lego.yml, publish-nginx.yml), release-staging.yml und der Server
# pruefen nach denselben Regeln. Faelle: scripts/test-package-private.sh.
#
# Exit-Codes (jeder ungleich 0 macht den Lauf rot - fail closed):
#   0  Paket anonym nicht lesbar (401), Gegenprobe bestanden
#   2  Voraussetzung oder Parameter fehlt bzw. ist ungueltig, oder die
#      Registry war nicht erreichbar
#   3  Paket anonym nicht eindeutig gesperrt (alles ausser 401)
#   4  Gegenprobe gescheitert: Das oeffentliche Paket lieferte nicht 200
#
# Geschrieben fuer den Linux-Runner. Braucht curl. Kein Token, keine
# Anmeldung: Die Pruefung soll genau sehen, was ein Fremder sieht.
# =============================================================================
set -euo pipefail

# Abbruch mit eindeutiger Meldung. "::error::" hebt die Zeile im Protokoll von
# GitHub Actions hervor; lokal ist es gewoehnlicher Text.
fail() {
  echo "::error::$2" >&2
  exit "$1"
}

[ "$#" -eq 1 ] || [ "$#" -eq 2 ] \
  || fail 2 "Erwartet: IMAGE_NAME [PUBLIC_PACKAGE] (erhalten: $# Parameter)."
command -v curl >/dev/null 2>&1 || fail 2 "curl wurde nicht gefunden."

# Nur GHCR und nur die Form ghcr.io/<owner>/<name> ohne Tag oder Digest; der
# Name landet in einer URL. Gibt den Namen ohne "ghcr.io/" aus.
# Aufruf ohne "$( )": fail muss den ganzen Lauf beenden.
check_name() {
  local label="$1" value="$2"
  case "${value}" in
    ghcr.io/*/*) ;;
    *) fail 2 "${label} muss mit ghcr.io/<owner>/ beginnen: '${value}'" ;;
  esac
  printf '%s' "${value#ghcr.io/}" | grep --quiet --extended-regexp '^[a-z0-9._-]+(/[a-z0-9._-]+)+$' \
    || fail 2 "${label} ist kein gueltiger Paketname ohne Tag: '${value}'"
}
check_name IMAGE_NAME "$1"
own="${1#ghcr.io/}"

# HTTP-Status des Token-Endpunkts ohne Anmeldung. Ein Netzfehler beendet curl
# mit Exit ungleich 0; der Aufrufer macht daraus Exit 2.
anonymous() {
  curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --max-time 20 "https://ghcr.io/token?scope=repository:$1:pull&service=ghcr.io"
}

# Vergleichspaket: ausdruecklich uebergeben (Server, E-5-171: Konstante
# PUBLIC_COUNTER_PACKAGE in lib/registry-only.sh) oder aus compose.scan.yaml
# in der Wurzel des Repositories (CI). Ohne cd: Auf dem Server gibt es keine
# Repository-Wurzel.
if [ "$#" -eq 2 ]; then
  check_name PUBLIC_PACKAGE "$2"
  public="${2#ghcr.io/}"
else
  scan_file="$(cd "$(dirname "$0")/.." && pwd)/compose.scan.yaml"
  [ -r "${scan_file}" ] || fail 2 "compose.scan.yaml nicht gefunden: ${scan_file} (auf dem Server PUBLIC_PACKAGE angeben)."
  public="$(sed --quiet --regexp-extended \
    's/^ *image: ghcr\.io\/([^:@]+)[:@].*/\1/p' "${scan_file}" | head -n 1)"
  [ -n "${public}" ] || fail 2 "Kein oeffentliches Paket fuer die Gegenprobe in compose.scan.yaml gefunden."
fi
[ "${public}" != "${own}" ] || fail 2 "PUBLIC_PACKAGE und IMAGE_NAME sind gleich: '${own}'"

code="$(anonymous "${public}")" || fail 2 "Registry nicht erreichbar (Gegenprobe ${public})."
echo "Gegenprobe ${public}: HTTP ${code} (erwartet 200)"
[ "${code}" = "200" ] \
  || fail 4 "Gegenprobe: Das oeffentliche Paket ${public} ergab HTTP ${code}. Die Pruefung erkennt 'oeffentlich' nicht."

code="$(anonymous "${own}")" || fail 2 "Registry nicht erreichbar (${own})."
echo "${own}: HTTP ${code} (erwartet 401)"
[ "${code}" = "401" ] \
  || fail 3 "Das Paket ${own} ist anonym nicht eindeutig gesperrt (HTTP ${code}). Sichtbarkeit in den Paket-Einstellungen auf privat stellen (E-5-115)."

echo "Paket anonym nicht lesbar: ${own}"
