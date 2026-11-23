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
# Zusaetzlich (ADR-017, PR 4b):
#   - Abgleich Bundle-Dateiliste (RELEASE_FILES) <-> Pfadfilter von
#     release-staging.yml <-> nginx/snippets/, und RELEASE_IMAGE und
#     predicate-type im Workflow <-> Konstanten der Bibliothek
#   - RELEASE_FACTS mit jq gegen Gut- und Rot-Faelle (gojq: lokal belegt,
#     im Release-Workflow bei jedem Lauf)
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

# --- Abgleich: Bundle, Pfadfilter, Konstanten (ADR-017, E-5-155, E-5-159) ---
# Dateiliste, Pfadfilter des Release-Workflows und die Werte im Workflow
# stehen an verschiedenen Stellen. Laufen sie auseinander, entsteht Drift:
# eine Aenderung ohne neue Freigabe oder ein Workflow, der etwas anderes
# signiert, als der Server erwartet.
# shellcheck source=lib/release-rules.sh
. "${here}/lib/release-rules.sh"
root="${here}/.."
workflow="${root}/.github/workflows/release-staging.yml"

consistency() {
  local label="$1" ok="$2" detail="$3"
  if [ "${ok}" = "ja" ]; then
    echo "ok   ${label}"
  else
    echo "FEHLER ${label}: ${detail}"
    failures=$((failures + 1))
  fi
}

[ -r "${workflow}" ] || fail 2 "Workflow fehlt: ${workflow}"

# Eintraege des Pfadfilters (Zeilen '      - "..."' direkt unter paths:).
mapfile -t filter < <(awk '
  /^    paths:/ { inside = 1; next }
  inside && /^      #/ { next }
  inside && /^      - "/ { sub(/^      - "/, ""); sub(/".*$/, ""); print; next }
  inside { exit }
' "${workflow}")

covered() {
  local file="$1" pattern
  for pattern in "${filter[@]}"; do
    [ "${pattern}" = "${file}" ] && return 0
    case "${pattern}" in
      */\*\*) [[ "${file}" == "${pattern%\*\*}"* ]] && return 0 ;;
    esac
  done
  return 1
}

for file in "${RELEASE_FILES[@]}"; do
  if [ -f "${root}/${file}" ] && [ ! -L "${root}/${file}" ]; then
    consistency "Bundle-Datei vorhanden: ${file}" ja ""
  else
    consistency "Bundle-Datei vorhanden: ${file}" nein "fehlt, ist ein Link oder keine gewoehnliche Datei"
  fi
  if covered "${file}"; then
    consistency "Pfadfilter deckt ${file}" ja ""
  else
    consistency "Pfadfilter deckt ${file}" nein "Aenderung erzeugte keine neue Freigabe (Drift)"
  fi
done

# Jede nginx-Snippet-Datei muss ins Bundle: nginx.staging.conf bindet den
# ganzen Ordner ein.
for snippet in "${root}"/nginx/snippets/*; do
  rel="nginx/snippets/${snippet##*/}"
  listed=nein
  for file in "${RELEASE_FILES[@]}"; do
    [ "${file}" = "${rel}" ] && listed=ja
  done
  consistency "Snippet im Bundle: ${rel}" "${listed}" "fehlt in RELEASE_FILES"
done

if grep --quiet --line-regexp --fixed-strings "      RELEASE_IMAGE: ${RELEASE_IMAGE_NAME}" "${workflow}"; then
  consistency "RELEASE_IMAGE im Workflow = RELEASE_IMAGE_NAME" ja ""
else
  consistency "RELEASE_IMAGE im Workflow = RELEASE_IMAGE_NAME" nein "weicht ab oder fehlt"
fi
if grep --quiet --line-regexp --fixed-strings "          predicate-type: ${RELEASE_PREDICATE_TYPE}" "${workflow}"; then
  consistency "predicate-type im Workflow = RELEASE_PREDICATE_TYPE" ja ""
else
  consistency "predicate-type im Workflow = RELEASE_PREDICATE_TYPE" nein "weicht ab oder fehlt"
fi

# --- RELEASE_FACTS mit jq (der Server nutzt gojq; lokal belegt) -------------
pred="$(jq --compact-output . "${base}")"
facts_input() { # URI COMMIT DIGEST PREDICATE ANZAHL
  jq --null-input --compact-output \
    --argjson uri "$1" --argjson commit "$2" --argjson digest "$3" --argjson pred "$4" --argjson n "$5" '
    { verificationResult: {
        signature: { certificate: { runInvocationURI: $uri, sourceRepositoryDigest: $commit } },
        statement: { subject: [ { name: "x", digest: { sha256: $digest } } ], predicate: $pred } } }
    | [ limit($n; repeat(.)) ]'
}
uri='"https://github.com/xXxCoder999xXx/identity-service/actions/runs/45177231370/attempts/2"'
commit='"768bbb42c5387682d63087b1ad6be24f494b9aa2"'
digest='"63a1ae6e173e43cd5a2ff9a9ab817d7da0efa4f1700d36c2dcfe0a94887ed6a8"'

facts_case() { # NAME EXIT GRUND EINGABE
  local out got=0
  out="$(printf '%s' "$4" | jq --raw-output "${RELEASE_FACTS}" 2>&1)" || got=$?
  if { [ "$2" -eq 0 ] && [ "${got}" -eq 0 ]; } || { [ "$2" -ne 0 ] && [ "${got}" -ne 0 ]; }; then
    if [[ "${out}" == *"$3"* ]]; then
      echo "ok   Fakten: $1"
      return
    fi
  fi
  echo "FEHLER Fakten: $1: erwartet Exit $2 mit '$3', erhalten Exit ${got}:"
  printf '%s\n' "${out}" | sed 's/^/  /'
  failures=$((failures + 1))
}

# Erwartete erste vier Zeilen; danach folgen die drei Referenzen.
good_facts="$(printf 'subject\tsha256:%s\nrun\t45177231370\nattempt\t2\ncommit\t%s' \
  "$(jq --raw-output . <<<"${digest}")" "$(jq --raw-output . <<<"${commit}")")"
facts_case "gueltiger Nachweis" 0 "${good_facts}" "$(facts_input "${uri}" "${commit}" "${digest}" "${pred}" 1)"
facts_case "zwei Nachweise" 5 "genau einen Nachweis, gefunden 2" "$(facts_input "${uri}" "${commit}" "${digest}" "${pred}" 2)"
facts_case "kein Nachweis" 5 "genau einen Nachweis, gefunden 0" "$(facts_input "${uri}" "${commit}" "${digest}" "${pred}" 0)"
facts_case "fremdes Repository in runInvocationURI" 5 "runInvocationURI" \
  "$(facts_input '"https://github.com/evil/identity-service/actions/runs/1/attempts/1"' "${commit}" "${digest}" "${pred}" 1)"
facts_case "runInvocationURI fehlt" 5 "runInvocationURI" "$(facts_input null "${commit}" "${digest}" "${pred}" 1)"
facts_case "Commit gekuerzt" 5 "sourceRepositoryDigest" "$(facts_input "${uri}" '"768bbb4"' "${digest}" "${pred}" 1)"
facts_case "subject ohne Digest" 5 "subject hat keinen sha256-Digest" "$(facts_input "${uri}" "${commit}" '"abc"' "${pred}" 1)"
facts_case "Predicate production" 5 "environment muss staging sein" \
  "$(facts_input "${uri}" "${commit}" "${digest}" "$(jq --compact-output '.environment = "production"' <<<"${pred}")" 1)"
facts_case "Predicate vertauscht" 5 "images.api ist keine Referenz" \
  "$(facts_input "${uri}" "${commit}" "${digest}" "$(jq --compact-output '.images.api = .images.lego' <<<"${pred}")" 1)"

# Die Referenz fuer api ist unveraendert (Selbstkontrolle der Mutationen).
[ "$(jq --raw-output '.images.api' "${base}")" = "${api_ref}" ] \
  || fail 3 "Die Freigabe-Datei wurde waehrend der Tests veraendert."

if [ "${failures}" -ne 0 ]; then
  fail 3 "${failures} Fall/Faelle weichen ab."
fi
echo "Alle Faelle wie erwartet."
