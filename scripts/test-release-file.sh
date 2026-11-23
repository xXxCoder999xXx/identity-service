#!/usr/bin/env bash
# =============================================================================
# Rot-Faelle fuer scripts/verify-release-file.sh (ADR-017, E-5-114,
# E-5-151).
#
# Aufruf:  bash scripts/test-release-file.sh
#
# Warum: Ein Pruefer, der alles durchlaesst, ist gruen und wertlos. Dieses
# Skript erzeugt aus der echten deploy/staging.json kaputte Varianten und
# verlangt fuer jede den erwarteten Exit-Code UND den erwarteten Grund
# (E-5-114: Ein Fehlschlag aus anderem Grund beweist nichts). Es laeuft in
# jedem CI-Lauf und ersetzt einen Wegwerf-PR fuer die Formatpruefung.
#
# Die Ausgaben der erwarteten Fehlschlaege werden nur gespeichert, nicht
# gedruckt: Ihre "::error::"-Zeilen wuerden in GitHub Actions sonst als
# Fehler am Pull Request erscheinen. Gedruckt wird nur bei Abweichung.
#
# Exit-Codes:
#   0  alle Faelle wie erwartet
#   2  Voraussetzung fehlt (jq, Pruefskript, Freigabe-Datei)
#   3  mindestens ein Fall weicht ab
#
# Geschrieben fuer Linux (Runner). Braucht jq.
# =============================================================================
set -euo pipefail

fail() {
  echo "::error::$2" >&2
  exit "$1"
}

here="${BASH_SOURCE[0]%/*}"
[ "${here}" != "${BASH_SOURCE[0]}" ] || here="."
verify="${here}/verify-release-file.sh"
base="${here}/../deploy/staging.json"

command -v jq >/dev/null 2>&1 || fail 2 "jq wurde nicht gefunden."
[ -r "${verify}" ] || fail 2 "Pruefskript fehlt: ${verify}"
[ -r "${base}" ] || fail 2 "Freigabe-Datei fehlt: ${base}"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

failures=0

# expect NAME CODE GRUND DATEI [weitere Parameter fuer das Pruefskript]
# Ruft das Pruefskript mit DATEI auf und verlangt Exit CODE und GRUND als
# Teil der Ausgabe.
expect() {
  local name="$1" code="$2" reason="$3"
  shift 3
  local out got=0
  out="$(bash "${verify}" "$@" 2>&1)" || got=$?
  if [ "${got}" -eq "${code}" ] && [[ "${out}" == *"${reason}"* ]]; then
    echo "ok   ${name}"
  else
    echo "FEHLER ${name}: erwartet Exit ${code} mit '${reason}', erhalten Exit ${got}:"
    printf '%s\n' "${out}" | sed 's/^::error::/  /'
    failures=$((failures + 1))
  fi
}

# mutate NAME JQ-AUSDRUCK: Variante der echten Datei in kanonischer Form,
# damit genau die gemeinte Regel anschlaegt und nicht die Formpruefung.
mutate() {
  jq "$2" "${base}" >"${work}/$1.json"
  echo "${work}/$1.json"
}

# Gruenfall: die echte Datei
expect "echte Freigabe" 0 "Freigabe gueltig" "${base}"

# Regeln der Wurzel
expect "Schluessel falsch geschrieben" 3 "Wurzel muss genau" \
  "$(mutate typo '{schema, enviroment: .environment, images}')"
expect "zusaetzlicher Schluessel" 3 "Wurzel muss genau" \
  "$(mutate extra '. + {extra: 1}')"
expect "fehlender Schluessel" 3 "Wurzel muss genau" \
  "$(mutate missing 'del(.environment)')"
expect "Array statt Objekt" 3 "Wurzel ist kein Objekt" \
  "$(mutate array '[.]')"
expect "schema als Text" 3 "schema muss eine Zahl sein" \
  "$(mutate schema-text '.schema = "1"')"
expect "schema 2" 3 "schema wird nicht unterstuetzt" \
  "$(mutate schema-2 '.schema = 2')"
expect "environment production" 3 "environment muss staging sein" \
  "$(mutate production '.environment = "production"')"

# Regeln der Images
expect "images als Array" 3 "images ist kein Objekt" \
  "$(mutate images-array '.images = []')"
expect "zusaetzliches Image" 3 "images muss genau" \
  "$(mutate images-extra '.images.extra = .images.api')"
expect "fehlendes Image" 3 "images muss genau" \
  "$(mutate images-missing 'del(.images.lego)')"
expect "nginx-Digest unter api" 3 "images.api ist keine Referenz" \
  "$(mutate swapped '.images.api = .images.nginx')"
expect "api-Digest unter nginx" 3 "images.nginx ist keine Referenz" \
  "$(mutate swapped-nginx '.images.nginx = .images.api')"
expect "Tag statt Digest" 3 "images.lego ist keine Referenz" \
  "$(mutate tag '.images.lego = "ghcr.io/xxxcoder999xxx/identity-service-lego:latest"')"
expect "Digest mit 63 Zeichen" 3 "images.api ist keine Referenz" \
  "$(mutate short '.images.api |= .[0:-1]')"
expect "Digest mit 65 Zeichen" 3 "images.api ist keine Referenz" \
  "$(mutate long '.images.api += "0"')"
expect "Grossbuchstaben im Digest" 3 "images.nginx ist keine Referenz" \
  "$(mutate upper '.images.nginx |= sub("sha256:[0-9a-f]"; "sha256:A")')"
expect "anderer Besitzer" 3 "images.api ist keine Referenz" \
  "$(mutate owner '.images.api |= sub("xxxcoder999xxx"; "fremd")')"
expect "andere Registry" 3 "images.lego ist keine Referenz" \
  "$(mutate registry '.images.lego |= sub("^ghcr\\.io"; "docker.io")')"
expect "Zahl statt Referenz" 3 "images.api ist keine Referenz" \
  "$(mutate number '.images.api = 1')"

# Form und Inhalt der Datei
api_ref="$(jq --raw-output '.images.api' "${base}")"
nginx_ref="$(jq --raw-output '.images.nginx' "${base}")"
awk -v ref="${nginx_ref}" '
  { print }
  /^    "api": / { print "    \"api\": \"" ref "\"," }
' "${base}" >"${work}/duplicate.json"
expect "doppelter Schluessel" 3 "nicht in kanonischer Form" "${work}/duplicate.json"

jq --indent 4 . "${base}" >"${work}/indent.json"
expect "andere Einrueckung" 3 "nicht in kanonischer Form" "${work}/indent.json"

sed 's/$/\r/' "${base}" >"${work}/crlf.json"
expect "Windows-Zeilenenden" 3 "nicht in kanonischer Form" "${work}/crlf.json"

{ printf '\357\273\277'; cat "${base}"; } >"${work}/bom.json"
expect "BOM" 3 "Freigabe ungueltig" "${work}/bom.json"

: >"${work}/empty.json"
expect "leere Datei" 3 "Datei ist leer" "${work}/empty.json"

printf ' \n' >"${work}/blank.json"
expect "nur Leerraum" 3 "gefunden 0" "${work}/blank.json"

printf 'kein JSON\n' >"${work}/text.json"
expect "kein JSON" 3 "kein gueltiges JSON" "${work}/text.json"

cat "${base}" "${base}" >"${work}/two.json"
expect "zwei Dokumente" 3 "gefunden 2" "${work}/two.json"

{ cat "${base}"; printf '%5000s\n' ''; } >"${work}/big.json"
expect "groesser als 4096 Byte" 3 "groesser als 4096" "${work}/big.json"

# Voraussetzungen: Exit 2, nie gruen
expect "keine Parameter" 2 "Erwartet: DATEI"
expect "zwei Parameter" 2 "Erwartet: DATEI" "${base}" "${base}"
expect "Datei fehlt" 2 "Datei nicht gefunden" "${work}/gibt-es-nicht.json"

# Der Pruefer konnte nicht laufen (CLAUDE.md Abschnitt 7): ohne jq im PATH
# muss Exit 2 kommen, nie Exit 0.
mkdir "${work}/leer"
got=0
out="$(PATH="${work}/leer" "${BASH}" "${verify}" "${base}" 2>&1)" || got=$?
if [ "${got}" -eq 2 ] && [[ "${out}" == *"jq wurde nicht gefunden"* ]]; then
  echo "ok   jq fehlt"
else
  echo "FEHLER jq fehlt: erwartet Exit 2, erhalten Exit ${got}:"
  printf '%s\n' "${out}" | sed 's/^::error::/  /'
  failures=$((failures + 1))
fi

# Die Referenz fuer api ist unveraendert (Selbstkontrolle der Mutationen).
[ "$(jq --raw-output '.images.api' "${base}")" = "${api_ref}" ] \
  || fail 3 "Die Freigabe-Datei wurde waehrend der Tests veraendert."

if [ "${failures}" -ne 0 ]; then
  fail 3 "${failures} Fall/Faelle weichen ab."
fi
echo "Alle Faelle wie erwartet."
