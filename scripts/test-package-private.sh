#!/usr/bin/env bash
# =============================================================================
# Faelle fuer scripts/verify-package-private.sh mit einem curl-Ersatz
# (E-5-115, E-5-171).
#
# Aufruf:  bash scripts/test-package-private.sh
#
# Warum ein Ersatz: Gegen die echte Registry lassen sich "oeffentlich",
# "nicht vorhanden" und "Registry nicht erreichbar" nicht gezielt erzeugen.
# Der Ersatz antwortet je Paket mit einem festen HTTP-Status und schreibt
# mit, welche Pakete gefragt wurden. Jeder Fall verlangt Exit-Code UND Grund
# (E-5-114).
#
# Steuerung des Ersatzes ueber Umgebungsvariablen:
#   FAKE_CODES      "paket=status ..." (ohne ghcr.io/), sonst 403
#   FAKE_CURL_EXIT  Exit-Code von curl (Standard 0); ungleich 0: keine Ausgabe
#   FAKE_LOG        Datei, in die jedes gefragte Paket geschrieben wird
#
# Exit-Codes:
#   0  alle Faelle wie erwartet
#   2  Voraussetzung fehlt
#   3  mindestens ein Fall weicht ab
# =============================================================================
set -euo pipefail

fail() {
  echo "::error::$2" >&2
  exit "$1"
}

here="${BASH_SOURCE[0]%/*}"
[ "${here}" != "${BASH_SOURCE[0]}" ] || here="."
script="${here}/verify-package-private.sh"
[ -r "${script}" ] || fail 2 "Skript fehlt: ${script}"
[ -r "${here}/lib/registry-only.sh" ] || fail 2 "Bibliothek fehlt: ${here}/lib/registry-only.sh"
# shellcheck source=lib/registry-only.sh
. "${here}/lib/registry-only.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
mkdir "${work}/bin" "${work}/leer"

cat >"${work}/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${!#}"
pkg="${url#*scope=repository:}"
pkg="${pkg%%:pull*}"
printf '%s\n' "${pkg}" >>"${FAKE_LOG}"
[ "${FAKE_CURL_EXIT:-0}" = "0" ] || exit "${FAKE_CURL_EXIT}"
code=403
for entry in ${FAKE_CODES:-}; do
  [ "${entry%%=*}" = "${pkg}" ] && code="${entry#*=}"
done
printf '%s' "${code}"
EOF
chmod +x "${work}/bin/curl"

own="ghcr.io/xxxcoder999xxx/identity-service-release"
scan_public="$(sed --quiet --regexp-extended \
  's/^ *image: ghcr\.io\/([^:@]+)[:@].*/\1/p' "${here}/../compose.scan.yaml" | head -n 1)"
[ -n "${scan_public}" ] || fail 2 "Kein Vergleichspaket in compose.scan.yaml gefunden."
server_public="${PUBLIC_COUNTER_PACKAGE#ghcr.io/}"
export FAKE_LOG="${work}/log"

failures=0

# run LABEL CODE GRUND [Parameter fuer verify-package-private.sh]
run() {
  local label="$1" code="$2" reason="$3"
  shift 3
  local got=0 err
  : >"${FAKE_LOG}"
  PATH="${work}/bin:${PATH}" bash "${script}" "$@" >"${work}/out" 2>"${work}/err" || got=$?
  err="$(cat "${work}/err")"
  if [ "${got}" -eq "${code}" ] && [[ "${err}" == *"${reason}"* ]]; then
    echo "ok   ${label}"
  else
    echo "FEHLER ${label}: erwartet Exit ${code} mit '${reason}', erhalten Exit ${got}"
    printf '%s\n' "${err}" | sed 's/^::error::/  stderr: /'
    failures=$((failures + 1))
  fi
}

# asked WERT: Der Ersatz muss als Vergleichspaket (erste Frage) WERT gesehen
# haben.
asked() {
  local label="$1" want="$2" first
  first="$(head -n 1 "${FAKE_LOG}")"
  if [ "${first}" = "${want}" ]; then
    echo "ok   ${label}"
  else
    echo "FEHLER ${label}: erwartet Vergleichspaket '${want}', gefragt '${first}'"
    failures=$((failures + 1))
  fi
}

# --- Erfolg ---------------------------------------------------------------------
export FAKE_CODES="${scan_public}=200 ${server_public}=200 ${own#ghcr.io/}=401"
run "CI-Weg: Vergleichspaket aus compose.scan.yaml" 0 "" "${own}"
asked "CI-Weg fragt das Paket aus compose.scan.yaml" "${scan_public}"
run "Server-Weg: PUBLIC_COUNTER_PACKAGE" 0 "" "${own}" "${PUBLIC_COUNTER_PACKAGE}"
asked "Server-Weg fragt PUBLIC_COUNTER_PACKAGE" "${server_public}"
# CI und Server nutzen heute dasselbe Paket; nur ein anderes beweist, dass
# PUBLIC_PACKAGE wirklich gilt (gefunden per Mutations-Gegenprobe).
export FAKE_CODES="example/other-public=200 ${own#ghcr.io/}=401"
run "PUBLIC_PACKAGE ungleich compose.scan.yaml" 0 "" "${own}" ghcr.io/example/other-public
asked "PUBLIC_PACKAGE wird gefragt, nicht compose.scan.yaml" "example/other-public"
export FAKE_CODES="${scan_public}=200 ${server_public}=200 ${own#ghcr.io/}=401"

# Der Server-Weg darf compose.scan.yaml nicht brauchen: Kopie des Skripts
# ohne Repository-Wurzel daneben.
mkdir -p "${work}/inst"
cp "${script}" "${work}/inst/"
got=0
PATH="${work}/bin:${PATH}" bash "${work}/inst/verify-package-private.sh" "${own}" "${PUBLIC_COUNTER_PACKAGE}" \
  >"${work}/out" 2>"${work}/err" || got=$?
if [ "${got}" -eq 0 ]; then echo "ok   Server-Weg ohne compose.scan.yaml"; else echo "FEHLER Server-Weg ohne compose.scan.yaml: Exit ${got}"; failures=$((failures + 1)); fi
got=0
PATH="${work}/bin:${PATH}" bash "${work}/inst/verify-package-private.sh" "${own}" \
  >"${work}/out" 2>"${work}/err" || got=$?
if [ "${got}" -eq 2 ] && grep -q "compose.scan.yaml nicht gefunden" "${work}/err"; then
  echo "ok   CI-Weg ohne compose.scan.yaml: Exit 2"
else
  echo "FEHLER CI-Weg ohne compose.scan.yaml: Exit ${got}"
  failures=$((failures + 1))
fi

# --- Eigenes Paket nicht gesperrt ---------------------------------------------------
export FAKE_CODES="${server_public}=200 ${own#ghcr.io/}=200"
run "eigenes Paket oeffentlich (200)" 3 "nicht eindeutig gesperrt (HTTP 200)" "${own}" "${PUBLIC_COUNTER_PACKAGE}"
export FAKE_CODES="${server_public}=200"
run "eigenes Paket nicht vorhanden (403)" 3 "nicht eindeutig gesperrt (HTTP 403)" "${own}" "${PUBLIC_COUNTER_PACKAGE}"

# --- Gegenprobe ------------------------------------------------------------------------
export FAKE_CODES="${server_public}=401 ${own#ghcr.io/}=401"
run "Vergleichspaket nicht mehr oeffentlich (401)" 4 "Gegenprobe" "${own}" "${PUBLIC_COUNTER_PACKAGE}"
export FAKE_CODES="${own#ghcr.io/}=401"
run "Vergleichspaket verschwunden (403)" 4 "ergab HTTP 403" "${own}" "${PUBLIC_COUNTER_PACKAGE}"

# --- Netz ------------------------------------------------------------------------------
export FAKE_CODES="${server_public}=200 ${own#ghcr.io/}=401"
FAKE_CURL_EXIT=7 run "Registry nicht erreichbar" 2 "Registry nicht erreichbar" "${own}" "${PUBLIC_COUNTER_PACKAGE}"

# --- Parameter -------------------------------------------------------------------------
run "keine Parameter" 2 "Erwartet: IMAGE_NAME [PUBLIC_PACKAGE]"
run "drei Parameter" 2 "Erwartet: IMAGE_NAME [PUBLIC_PACKAGE]" "${own}" "${PUBLIC_COUNTER_PACKAGE}" x
run "PUBLIC_PACKAGE andere Registry" 2 "PUBLIC_PACKAGE muss" "${own}" docker.io/anchore/grype
run "PUBLIC_PACKAGE mit Tag" 2 "PUBLIC_PACKAGE ist kein gueltiger" "${own}" "${PUBLIC_COUNTER_PACKAGE}:latest"
run "PUBLIC_PACKAGE mit Grossbuchstaben" 2 "PUBLIC_PACKAGE ist kein gueltiger" "${own}" ghcr.io/Anchore/grype
run "PUBLIC_PACKAGE mit Zeichen fuer die URL" 2 "PUBLIC_PACKAGE ist kein gueltiger" "${own}" "ghcr.io/anchore/grype&scope=x"
run "PUBLIC_PACKAGE gleich IMAGE_NAME" 2 "sind gleich" "${own}" "${own}"
run "IMAGE_NAME andere Registry" 2 "IMAGE_NAME muss" docker.io/owner/name "${PUBLIC_COUNTER_PACKAGE}"
run "IMAGE_NAME mit Digest" 2 "IMAGE_NAME ist kein gueltiger" "${own}@sha256:abc" "${PUBLIC_COUNTER_PACKAGE}"

# --- curl fehlt: Exit 2, nie 0 (CLAUDE.md Abschnitt 7) ---------------------------------
got=0
PATH="${work}/leer" "${BASH}" "${script}" "${own}" "${PUBLIC_COUNTER_PACKAGE}" \
  >"${work}/out" 2>"${work}/err" || got=$?
if [ "${got}" -eq 2 ] && grep -q "curl wurde nicht gefunden" "${work}/err"; then
  echo "ok   curl fehlt"
else
  echo "FEHLER curl fehlt: erwartet Exit 2, erhalten Exit ${got}"
  failures=$((failures + 1))
fi

if [ "${failures}" -ne 0 ]; then
  fail 3 "${failures} Fall/Faelle weichen ab."
fi
echo "Alle Faelle wie erwartet."
