#!/usr/bin/env bash
# =============================================================================
# Faelle fuer scripts/push-image.sh mit einem docker-Ersatz (E-5-158).
#
# Aufruf:  bash scripts/test-push-image.sh
#
# Warum ein Ersatz: push-image.sh laeuft echt nur in den publish*-Workflows,
# also erst nach dem Merge und ohne Pflicht-Check. Ein Fehler zeigte sich
# dann auf main. Der Ersatz spielt docker nach (tag, push, image inspect) und
# laesst jeden Fehlerpfad gezielt eintreten, ohne Registry und ohne Token.
# Jeder Fall verlangt Exit-Code UND Grund (E-5-114); im Erfolgsfall muss
# stdout GENAU den Digest enthalten.
#
# Steuerung des Ersatzes ueber Umgebungsvariablen:
#   FAKE_LOCAL_IMAGES  lokale Images, durch Leerzeichen getrennt
#   FAKE_PUSH_EXIT     Exit-Code von "docker push" (Standard 0)
#   FAKE_REPO_DIGESTS  Ausgabe von "image inspect --format ..." fuer den Ref
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
script="${here}/push-image.sh"
[ -r "${script}" ] || fail 2 "Skript fehlt: ${script}"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT
mkdir "${work}/bin" "${work}/leer"

# docker-Ersatz. "image inspect REF" ohne --format: Erfolg nur fuer bekannte
# lokale Images oder getaggte Refs. Mit --format: FAKE_REPO_DIGESTS.
cat >"${work}/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$1 ${2:-}" in
  "image inspect")
    if [ "$#" -ge 4 ] && [ "$4" = "--format" ]; then
      printf '%s' "${FAKE_REPO_DIGESTS:-}"
      exit 0
    fi
    for i in ${FAKE_LOCAL_IMAGES:-}; do
      [ "$3" = "${i}" ] && exit 0
    done
    exit 1
    ;;
  "tag "*)
    echo "tagged $2 $3"
    exit 0
    ;;
  "push "*)
    echo "pushing $2"
    exit "${FAKE_PUSH_EXIT:-0}"
    ;;
esac
echo "unerwarteter Aufruf: $*" >&2
exit 99
EOF
chmod +x "${work}/bin/docker"

name="ghcr.io/owner/identity-service"
good="sha256:$(printf 'a%.0s' {1..64})"
other="sha256:$(printf 'b%.0s' {1..64})"

failures=0

# run CODE GRUND ERWARTETES_STDOUT [Parameter fuer push-image.sh]
# Laeuft mit dem Ersatz vorne im PATH. GRUND wird in stderr gesucht; ist
# ERWARTETES_STDOUT nicht "-", muss stdout genau diesem Text gleichen.
run() {
  local label="$1" code="$2" reason="$3" want="$4"
  shift 4
  local got=0
  PATH="${work}/bin:${PATH}" bash "${script}" "$@" \
    >"${work}/out" 2>"${work}/err" || got=$?
  local out err
  out="$(cat "${work}/out")"
  err="$(cat "${work}/err")"
  if [ "${got}" -eq "${code}" ] && [[ "${err}" == *"${reason}"* ]] \
    && { [ "${want}" = "-" ] || [ "${out}" = "${want}" ]; }; then
    echo "ok   ${label}"
  else
    echo "FEHLER ${label}: erwartet Exit ${code} mit '${reason}', erhalten Exit ${got}"
    echo "  stdout: ${out}"
    printf '%s\n' "${err}" | sed 's/^::error::/  stderr: /'
    failures=$((failures + 1))
  fi
}

export FAKE_LOCAL_IMAGES="local-image"
export FAKE_PUSH_EXIT=0

# Erfolg: stdout ist genau der Digest; Fortschritt landet in stderr.
export FAKE_REPO_DIGESTS="${name}@${good}"$'\n'
run "Erfolg" 0 "pushing ${name}:abc123" "${good}" local-image "${name}" abc123

# Mehrere Eintraege: der passende Name gewinnt, auch wenn er nicht vorn steht.
export FAKE_REPO_DIGESTS="${name}-evil@${other}"$'\n'"${name}@${good}"$'\n'
run "passender Name nicht vorn" 0 "" "${good}" local-image "${name}" abc123

# Nur ein Name mit gleichem Anfang: kein Treffer.
export FAKE_REPO_DIGESTS="${name}-evil@${other}"$'\n'
run "nur aehnlicher Name" 3 "Kein gueltiger Digest" - local-image "${name}" abc123

export FAKE_REPO_DIGESTS=""
run "keine RepoDigests" 3 "Kein gueltiger Digest" - local-image "${name}" abc123

export FAKE_REPO_DIGESTS="${name}@sha256:abc"$'\n'
run "Digest zu kurz" 3 "Kein gueltiger Digest" - local-image "${name}" abc123

export FAKE_REPO_DIGESTS="${name}@sha256:$(printf 'A%.0s' {1..64})"$'\n'
run "Grossbuchstaben im Digest" 3 "Kein gueltiger Digest" - local-image "${name}" abc123

export FAKE_REPO_DIGESTS="${name}@${good}"$'\n'
FAKE_PUSH_EXIT=1 run "Hochladen gescheitert" 3 "Hochladen gescheitert" - local-image "${name}" abc123

# Parameter
run "keine Parameter" 2 "Erwartet: LOCAL_IMAGE IMAGE_NAME TAG" -
run "zwei Parameter" 2 "Erwartet: LOCAL_IMAGE IMAGE_NAME TAG" - local-image "${name}"
run "LOCAL_IMAGE leer" 2 "LOCAL_IMAGE ist leer" - "" "${name}" abc123
run "lokales Image fehlt" 2 "Lokales Image nicht gefunden" - fehlt "${name}" abc123
run "andere Registry" 2 "IMAGE_NAME muss" - local-image docker.io/owner/name abc123
run "Grossbuchstaben im Namen" 2 "IMAGE_NAME muss" - local-image ghcr.io/Owner/name abc123
run "Name mit Tag" 2 "IMAGE_NAME muss" - local-image "${name}:abc" abc123
run "Name ohne Paket" 2 "IMAGE_NAME muss" - local-image ghcr.io/owner abc123
run "Tag leer" 2 "TAG ist kein gueltiger Tag" - local-image "${name}" ""
run "Tag mit Doppelpunkt" 2 "TAG ist kein gueltiger Tag" - local-image "${name}" "a:b"
run "Tag beginnt mit Punkt" 2 "TAG ist kein gueltiger Tag" - local-image "${name}" ".abc"
run "Tag latest" 2 "TAG latest ist nicht erlaubt" - local-image "${name}" latest

# docker fehlt: Exit 2, nie 0 (CLAUDE.md Abschnitt 7).
got=0
PATH="${work}/leer" "${BASH}" "${script}" local-image "${name}" abc123 \
  >"${work}/out" 2>"${work}/err" || got=$?
if [ "${got}" -eq 2 ] && grep --quiet "docker wurde nicht gefunden" "${work}/err"; then
  echo "ok   docker fehlt"
else
  echo "FEHLER docker fehlt: erwartet Exit 2, erhalten Exit ${got}"
  failures=$((failures + 1))
fi

if [ "${failures}" -ne 0 ]; then
  fail 3 "${failures} Fall/Faelle weichen ab."
fi
echo "Alle Faelle wie erwartet."
