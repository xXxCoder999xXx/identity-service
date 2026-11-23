#!/usr/bin/env bash
# =============================================================================
# Prueft die Staging-Freigabe deploy/staging.json (ADR-017, E-5-145,
# E-5-151).
#
# Aufruf:  bash scripts/verify-release-file.sh DATEI
#
# Warum vor dem Merge: Die Datei IST die Freigabe. Ein Formatfehler soll den
# Pull Request rot machen, nicht erst den Release-Workflow nach dem Merge.
# Ob die Digests in der Registry existieren und von unseren Workflows
# stammen, prueft dieses Skript bewusst NICHT; das tut der Release-Workflow
# vor dem Signieren mit dem bestehenden Pruef-Gate.
#
# Pruefungen in dieser Reihenfolge:
#   1. Datei vorhanden, nicht leer, hoechstens 4096 Byte
#   2. gueltiges JSON, genau ein Dokument
#   3. kanonische Form: Die Datei gleicht Byte fuer Byte der Ausgabe von
#      "jq ." (E-5-151). Grund: Bei doppelten Schluesseln nimmt jq still den
#      LETZTEN Wert; im Review sieht man den ersten. Nach dem Neuformatieren
#      ist der doppelte Schluessel verschwunden, die Datei weicht ab.
#      Nebenwirkung: kein BOM, feste Einrueckung, ruhige Diffs.
#   4. Regeln aus scripts/lib/release-rules.sh (RELEASE_RULES)
#   5. genau drei Ergebniszeilen api, nginx, lego (leere Eingabe erzeugt in
#      jq weder Ausgabe noch Fehler - ohne diese Pruefung waere das fail open)
#
# Exit-Codes (jeder ungleich 0 macht den Lauf rot - fail closed):
#   0  Freigabe gueltig; die drei Referenzen stehen auf stdout
#   2  Parameter fehlt, Datei fehlt oder ist nicht lesbar, jq fehlt,
#      Bibliothek fehlt
#   3  Inhalt ungueltig (Grund in der Meldung)
#
# Geschrieben fuer Linux (Runner). Braucht jq und cmp.
# =============================================================================
set -euo pipefail

# Abbruch mit eindeutiger Meldung. "::error::" hebt die Zeile im Protokoll von
# GitHub Actions hervor; lokal ist es gewoehnlicher Text.
fail() {
  echo "::error::$2" >&2
  exit "$1"
}

# Ohne externes dirname: Die Rot-Faelle rufen das Skript mit leerem PATH auf,
# und dann soll genau die jq-Pruefung anschlagen, nichts davor.
here="${BASH_SOURCE[0]%/*}"
[ "${here}" != "${BASH_SOURCE[0]}" ] || here="."

[ "$#" -eq 1 ] || fail 2 "Erwartet: DATEI (erhalten: $# Parameter)."
file="$1"

command -v jq >/dev/null 2>&1 || fail 2 "jq wurde nicht gefunden. Ohne jq kann nichts geprueft werden."
command -v cmp >/dev/null 2>&1 || fail 2 "cmp wurde nicht gefunden."

[ -r "${here}/lib/release-rules.sh" ] || fail 2 "Bibliothek ${here}/lib/release-rules.sh fehlt."
# shellcheck source=lib/release-rules.sh
. "${here}/lib/release-rules.sh"

[ -f "${file}" ] || fail 2 "Datei nicht gefunden: ${file}"
[ -r "${file}" ] || fail 2 "Datei nicht lesbar: ${file}"

# 1. Groesse
[ -s "${file}" ] || fail 3 "Freigabe ungueltig: Datei ist leer."
size="$(wc -c <"${file}")"
[ "${size}" -le 4096 ] || fail 3 "Freigabe ungueltig: Datei ist groesser als 4096 Byte (${size})."

# 2. Genau ein gueltiges JSON-Dokument. --slurp sammelt alle Dokumente in ein
# Array; ein Parse-Fehler beendet jq mit Exit ungleich 0.
count="$(jq --slurp 'length' "${file}" 2>/dev/null)" \
  || fail 3 "Freigabe ungueltig: kein gueltiges JSON."
[ "${count}" = "1" ] || fail 3 "Freigabe ungueltig: erwartet genau ein JSON-Dokument, gefunden ${count}."

# 3. Kanonische Form
jq . "${file}" | cmp --silent - "${file}" \
  || fail 3 "Freigabe ungueltig: nicht in kanonischer Form (doppelter Schluessel, BOM oder Formatierung). Vergleich: jq . ${file}"

# 4. Regeln. Die Meldung von jq enthaelt den Grund aus error(...).
if ! result="$(jq --raw-output "${RELEASE_RULES}" "${file}" 2>&1)"; then
  fail 3 "${result}"
fi

# 5. Genau drei Zeilen in fester Reihenfolge
lines=()
while IFS= read -r line; do
  lines+=("${line}")
done <<<"${result}"
[ "${#lines[@]}" -eq 3 ] \
  || fail 3 "Freigabe ungueltig: erwartet drei Ergebniszeilen, erhalten ${#lines[@]}."
[ "${lines[0]%%$'\t'*}" = "api" ] && [ "${lines[1]%%$'\t'*}" = "nginx" ] && [ "${lines[2]%%$'\t'*}" = "lego" ] \
  || fail 3 "Freigabe ungueltig: Ergebniszeilen nicht in der Reihenfolge api, nginx, lego."

echo "Freigabe gueltig: ${file}"
printf '%s\n' "${lines[@]}"
