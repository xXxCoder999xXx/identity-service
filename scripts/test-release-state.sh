#!/usr/bin/env bash
# =============================================================================
# Faelle fuer scripts/lib/release-state.sh (Downgrade-Regel, Zustandsformat)
# und scripts/fetch-release.sh (Server-Einstieg, PR 4c) mit Ersatz fuer
# docker und verify-release.sh.
#
# Aufruf:  bash scripts/test-release-state.sh
#
# Warum ein Ersatz: fetch-release.sh laeuft echt nur auf dem Server. Ein
# Fehler zeigte sich erst dort. Der Ersatz spielt verify-release.sh (Fakten,
# Exit-Codes) und docker (info, create, cp, rm) nach und laesst jeden
# Fehlerpfad gezielt eintreten, ohne Registry und ohne Token. Jeder Fall
# verlangt Exit-Code UND Grund (E-5-114).
#
# Der gueltige Erst-Schalter muss root gehoeren und fuer den Testbenutzer
# nicht schreibbar sein. Der Test nimmt dafuer /etc/hostname. Fehlt so eine
# Datei (etwa unter Git Bash auf Windows), werden diese Faelle uebersprungen
# und gezaehlt; in der CI (CI=true) ist das ein Fehler, damit ein Lauf ohne
# diese Faelle nicht gruen wird.
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
for f in fetch-release.sh lib/release-rules.sh lib/release-state.sh; do
  [ -r "${here}/${f}" ] || fail 2 "Datei fehlt: ${here}/${f}"
done
# shellcheck source=lib/release-rules.sh
. "${here}/lib/release-rules.sh"
# shellcheck source=lib/release-state.sh
. "${here}/lib/release-state.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

failures=0
skipped=0
ok() { echo "ok   $1"; }
bad() {
  echo "FEHLER $1"
  failures=$((failures + 1))
}

hex() { printf "$1%.0s" $(seq 1 "$2"); }
run_a="45202570572"
run_low="45202570000"
run_high="45202579999"
commit_a="$(hex a 40)"
commit_b="$(hex b 40)"
bundle_a="sha256:$(hex c 64)"

# =============================================================================
# Teil A: Bibliothek
# =============================================================================
echo "== Teil A: release_decide (Tabelle aus ADR-017)"

# decide LABEL ERWARTET GRUND [Parameter fuer release_decide]
decide() {
  local label="$1" want="$2" reason="$3" got err
  shift 3
  got="$(release_decide "$@" 2>"${work}/err")"
  err="$(cat "${work}/err")"
  if [ "${got}" = "${want}" ] && [[ "${err}" == *"${reason}"* ]]; then
    ok "${label}"
  else
    bad "${label}: erwartet '${want}' mit '${reason}', erhalten '${got}' / ${err}"
  fi
}

decide "neuere Run-ID" deploy "" valid "${run_a}" "${commit_a}" "${run_high}" "${commit_b}" no
decide "gleiche Run-ID, gleicher Commit" noop "" valid "${run_a}" "${commit_a}" "${run_a}" "${commit_a}" no
decide "kleinere Run-ID" reject "kleiner als gespeichert" valid "${run_a}" "${commit_a}" "${run_low}" "${commit_a}" no
decide "gleiche Run-ID, anderer Commit" reject "anderem Commit" valid "${run_a}" "${commit_a}" "${run_a}" "${commit_b}" no
decide "kein Zustand, kein Schalter" reject "kein Zustand und kein Erst-Schalter" none "" "" "${run_a}" "${commit_a}" no
decide "kein Zustand, Schalter" first "erster Deploy ohne Vergleich" none "" "" "${run_a}" "${commit_a}" yes
decide "Zustand und Schalter: Warnung, Vergleich gilt" deploy "Erst-Schalter wird ignoriert" valid "${run_a}" "${commit_a}" "${run_high}" "${commit_b}" yes
decide "Zustand und Schalter: Downgrade bleibt Downgrade" reject "kleiner als gespeichert" valid "${run_a}" "${commit_a}" "${run_low}" "${commit_a}" yes
decide "ungueltiger Zustand mit Schalter" reject "nicht lesbar oder ungueltig" invalid "" "" "${run_a}" "${commit_a}" yes
decide "unbekannte Zustands-Angabe" reject "Zustands-Angabe ungueltig" kaputt "" "" "${run_a}" "${commit_a}" no
decide "unbekannte Schalter-Angabe" reject "Schalter-Angabe ungueltig" none "" "" "${run_a}" "${commit_a}" vielleicht
decide "zu wenige Parameter" reject "sechs Parameter" valid "${run_a}"
decide "Run-ID mit fuehrender Null" reject "keine gueltige Run-ID" valid "${run_a}" "${commit_a}" "0${run_high}" "${commit_b}" no
decide "Run-ID mit 19 Ziffern" reject "keine gueltige Run-ID" valid "${run_a}" "${commit_a}" "$(hex 9 19)" "${commit_b}" no
decide "Commit in Grossbuchstaben" reject "keinen gueltigen Commit" valid "${run_a}" "${commit_a}" "${run_high}" "$(hex A 40)" no
decide "gespeicherte Run-ID ungueltig" reject "gespeicherter Zustand ungueltig" valid "x" "${commit_a}" "${run_high}" "${commit_b}" no

# Arithmetik-Einschleusung: Der Wert darf nie in $(( )) landen.
decide "Einschleusung in neue Run-ID" reject "keine gueltige Run-ID" valid "${run_a}" "${commit_a}" "a[\$(touch ${work}/pwned)]" "${commit_b}" no
decide "Einschleusung in gespeicherte Run-ID" reject "gespeicherter Zustand ungueltig" valid "a[\$(touch ${work}/pwned)]" "${commit_a}" "${run_high}" "${commit_b}" no
if [ -e "${work}/pwned" ]; then bad "Einschleusung wurde ausgefuehrt"; else ok "Einschleusung nicht ausgefuehrt"; fi

echo "== Teil A: Zustandsdatei"

# parse LABEL ERWARTET(0|1) GRUND DATEI
parse() {
  local label="$1" want="$2" reason="$3" file="$4" got=0 err
  release_state_parse "${file}" 2>"${work}/err" || got=$?
  err="$(cat "${work}/err")"
  if [ "${got}" -eq "${want}" ] && [[ "${err}" == *"${reason}"* ]]; then
    ok "${label}"
  else
    bad "${label}: erwartet ${want} mit '${reason}', erhalten ${got} / ${err}"
  fi
}

release_state_render "${run_a}" "${commit_a}" "${bundle_a}" >"${work}/state.ok"
parse "Rundweg render -> parse" 0 "" "${work}/state.ok"
if [ "${STATE_RUN}" = "${run_a}" ] && [ "${STATE_COMMIT}" = "${commit_a}" ] && [ "${STATE_BUNDLE}" = "${bundle_a}" ]; then
  ok "Rundweg liefert dieselben Werte"
else
  bad "Rundweg liefert andere Werte: ${STATE_RUN} ${STATE_COMMIT} ${STATE_BUNDLE}"
fi
if release_state_render "0${run_a}" "${commit_a}" "${bundle_a}" >"${work}/out" 2>/dev/null; then
  bad "render nimmt ungueltige Run-ID an"
elif [ -s "${work}/out" ]; then
  bad "render schreibt bei ungueltiger Run-ID trotzdem"
else
  ok "render lehnt ungueltige Run-ID ab, ohne Ausgabe"
fi

: >"${work}/state.empty"
parse "leere Datei" 1 "leer" "${work}/state.empty"
printf 'run\t%s\ncommit\t%s\nbundle\t%s' "${run_a}" "${commit_a}" "${bundle_a}" >"${work}/state.nonl"
parse "letzte Zeile ohne Zeilenende" 1 "ohne Zeilenende" "${work}/state.nonl"
printf 'run\t%s\r\ncommit\t%s\r\nbundle\t%s\r\n' "${run_a}" "${commit_a}" "${bundle_a}" >"${work}/state.crlf"
parse "Zeilenende CRLF" 1 "ungueltige Run-ID" "${work}/state.crlf"
{ cat "${work}/state.ok"; printf 'extra\tx\n'; } >"${work}/state.four"
parse "vier Zeilen" 1 "mehr als drei Zeilen" "${work}/state.four"
printf 'commit\t%s\nrun\t%s\nbundle\t%s\n' "${commit_a}" "${run_a}" "${bundle_a}" >"${work}/state.order"
parse "falsche Reihenfolge" 1 "muss mit run beginnen" "${work}/state.order"
printf 'run\t%s\ncommit\t%s\n' "${run_a}" "${commit_a}" >"${work}/state.two"
parse "zwei Zeilen" 1 "erwartet drei Zeilen" "${work}/state.two"
printf 'run %s\ncommit\t%s\nbundle\t%s\n' "${run_a}" "${commit_a}" "${bundle_a}" >"${work}/state.space"
parse "Leerzeichen statt Tabulator" 1 "ohne Tabulator" "${work}/state.space"
printf 'run\t%s\tx\ncommit\t%s\nbundle\t%s\n' "${run_a}" "${commit_a}" "${bundle_a}" >"${work}/state.tabs"
parse "zwei Tabulatoren" 1 "ungueltige Run-ID" "${work}/state.tabs"
printf 'run\t%s\ncommit\t%s\nbundle\tsha256:abc\n' "${run_a}" "${commit_a}" >"${work}/state.digest"
parse "Bundle-Digest zu kurz" 1 "ungueltiger Bundle-Digest" "${work}/state.digest"
head -c 2000 /dev/zero | tr '\0' 'x' >"${work}/state.big"
parse "zu gross" 1 "zu gross" "${work}/state.big"
mkdir "${work}/state.dir"
parse "Ordner statt Datei" 1 "keine gewoehnliche Datei" "${work}/state.dir"
ln -s "${work}/state.ok" "${work}/state.link" 2>/dev/null || true
if [ -L "${work}/state.link" ]; then
  parse "symbolischer Link" 1 "symbolischer Link" "${work}/state.link"
else
  echo "SKIP symbolischer Link (Dateisystem ohne Links)"
  skipped=$((skipped + 1))
fi

# =============================================================================
# Teil B: Einstieg fetch-release.sh mit Ersatz
# =============================================================================
echo "== Teil B: fetch-release.sh"

# Installationsaufbau wie auf dem Server: Einstieg, lib/ und ein Ersatz fuer
# verify-release.sh im selben Ordner.
inst="${work}/inst"
mkdir -p "${inst}/lib" "${work}/bin" "${work}/leer"
cp "${here}/fetch-release.sh" "${inst}/"
cp "${here}/lib/release-rules.sh" "${here}/lib/release-state.sh" "${inst}/lib/"

cat >"${inst}/verify-release.sh" <<'EOF'
#!/usr/bin/env bash
echo "== Ersatz fuer verify-release.sh: $*"
printf '%s' "${FAKE_FACTS:-}"
exit "${FAKE_VERIFY_EXIT:-0}"
EOF

# docker-Ersatz. cp liest aus FAKE_BUNDLE (Links bleiben Links wie bei
# docker cp).
cat >"${work}/bin/docker" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  info) printf '%s\n' "${FAKE_SECURITY:-[name=seccomp,profile=builtin name=rootless name=cgroupns]}"; exit 0 ;;
  create)
    [ "${FAKE_CREATE_EXIT:-0}" = "0" ] || exit "${FAKE_CREATE_EXIT}"
    printf '%s\n' "$(printf 'd%.0s' $(seq 1 64))"; exit 0 ;;
  cp)
    src="${2#*:}"
    [ -e "${FAKE_BUNDLE}${src}" ] || [ -L "${FAKE_BUNDLE}${src}" ] || { echo "no such file" >&2; exit 1; }
    cp -RP "${FAKE_BUNDLE}${src}" "$3"; exit $? ;;
  rm) exit 0 ;;
esac
echo "unerwarteter Aufruf: $*" >&2
exit 99
EOF
chmod +x "${work}/bin/docker"

# Gueltiges Bundle aus der echten Dateiliste.
make_bundle() {
  rm -rf -- "${work}/bundle"
  local file
  for file in "${RELEASE_FILES[@]}"; do
    mkdir -p "${work}/bundle/$(dirname "${file}")"
    printf 'inhalt von %s\n' "${file}" >"${work}/bundle/${file}"
  done
}

# Fakten wie von verify-release.sh. Parameter: RUN COMMIT
facts() {
  printf 'freigabe\tsubject\t%s\n' "${bundle_a}"
  printf 'freigabe\trun\t%s\n' "$1"
  printf 'freigabe\tattempt\t3\n'
  printf 'freigabe\tcommit\t%s\n' "$2"
  printf 'freigabe\tapi\tghcr.io/xxxcoder999xxx/identity-service@sha256:%s\n' "$(hex 1 64)"
  printf 'freigabe\tnginx\tghcr.io/xxxcoder999xxx/identity-service-nginx@sha256:%s\n' "$(hex 2 64)"
  printf 'freigabe\tlego\tghcr.io/xxxcoder999xxx/identity-service-lego@sha256:%s\n' "$(hex 3 64)"
}

# Gueltiger Erst-Schalter: root-eigen, fuer uns nicht schreibbar.
root_switch=""
if [ -f /etc/hostname ] && [ ! -L /etc/hostname ] && [ "$(stat -c '%u' /etc/hostname 2>/dev/null)" = "0" ] \
  && [ ! -w /etc/hostname ] && [ "$(id -u)" != "0" ]; then
  root_switch="/etc/hostname"
fi
no_switch="${work}/kein-schalter"

# Frischer Ausgangszustand je Fall.
reset() {
  rm -rf -- "${work}/rel" "${work}/state"
  mkdir "${work}/rel"
  make_bundle
  export FAKE_BUNDLE="${work}/bundle"
  export FAKE_FACTS
  FAKE_FACTS="$(facts "${run_a}" "${commit_a}")"$'\n'
  export FAKE_VERIFY_EXIT=0
  unset FAKE_SECURITY FAKE_CREATE_EXIT
}

# fetch LABEL CODE GRUND ENTSCHEIDUNG STATE SWITCH
# GRUND wird in stderr gesucht, ENTSCHEIDUNG (oder "-") in stdout als
# release<TAB>decision<TAB>... Danach darf kein .incoming-Ordner bleiben.
fetch() {
  local label="$1" code="$2" reason="$3" want="$4" state="$5" switch="$6" got=0 out err
  PATH="${work}/bin:${PATH}" bash "${inst}/fetch-release.sh" \
    "${state}" "${switch}" "${work}/rel" "${work}/Dockerfile" \
    >"${work}/out" 2>"${work}/err" || got=$?
  out="$(cat "${work}/out")"
  err="$(cat "${work}/err")"
  local leftovers
  leftovers="$(find "${work}/rel" -maxdepth 1 -name '.incoming.*' | wc -l)"
  leftovers="${leftovers//[[:space:]]/}"
  if [ "${got}" -eq "${code}" ] && [[ "${err}" == *"${reason}"* ]] \
    && { [ "${want}" = "-" ] || [[ "${out}" == *$'release\tdecision\t'"${want}"* ]]; } \
    && [ "${leftovers}" = "0" ]; then
    ok "${label}"
  else
    bad "${label}: erwartet Exit ${code} mit '${reason}' und '${want}', erhalten Exit ${got}, Reste ${leftovers}"
    printf '%s\n' "${err}" | tail -n 5 | sed 's/^/  stderr: /'
  fi
}

need_switch() {
  if [ -z "${root_switch}" ]; then
    echo "SKIP $1 (keine root-eigene, nicht schreibbare Datei als Schalter)"
    skipped=$((skipped + 1))
    return 1
  fi
}

state_with() {
  release_state_render "$1" "$2" "${bundle_a}" >"${work}/state"
}

# --- Entscheidungen --------------------------------------------------------------
reset
fetch "kein Zustand, kein Schalter" 6 "kein Zustand und kein Erst-Schalter" - "${work}/state" "${no_switch}"
if [ -z "$(ls -A "${work}/rel")" ]; then ok "abgelehnt: nichts angelegt"; else bad "abgelehnt, aber Ordner angelegt"; fi

if need_switch "erster Deploy"; then
  reset
  fetch "kein Zustand, Schalter: first" 0 "erster Deploy ohne Vergleich" first "${work}/state" "${root_switch}"
  target="${work}/rel/${commit_a}"
  all=1
  for file in "${RELEASE_FILES[@]}"; do
    cmp -s "${work}/bundle/${file}" "${target}/${file}" || all=0
    [ "$(stat -c '%a' "${target}/${file}")" = "644" ] || all=0
  done
  if [ "${all}" = "1" ]; then ok "first: alle Dateien gleich, Rechte 644"; else bad "first: Dateien oder Rechte weichen ab"; fi
  if [ "$(find "${target}" -type f | wc -l | tr -d '[:space:]')" = "${#RELEASE_FILES[@]}" ]; then
    ok "first: genau die Dateiliste"
  else
    bad "first: andere Anzahl Dateien"
  fi
  if grep -q $'^release\tdir\t'"${target}"'$' "${work}/out" && grep -q $'^release\tapi\t' "${work}/out"; then
    ok "first: Ausgabe nennt Ordner und Referenzen"
  else
    bad "first: Ausgabe unvollstaendig"
  fi

  reset
  state_with "${run_a}" "${commit_a}"
  FAKE_FACTS="$(facts "${run_high}" "${commit_b}")"$'\n'
  fetch "Zustand und Schalter: Warnung, deploy" 0 "Erst-Schalter wird ignoriert" deploy "${work}/state" "${root_switch}"

  reset
  printf 'kaputt\n' >"${work}/state"
  fetch "kaputter Zustand mit Schalter: kein first" 6 "nicht lesbar oder ungueltig" - "${work}/state" "${root_switch}"

  reset
  : >"${work}/state"
  fetch "leerer Zustand mit Schalter: kein first" 6 "nicht lesbar oder ungueltig" - "${work}/state" "${root_switch}"
fi

reset
state_with "${run_a}" "${commit_a}"
FAKE_FACTS="$(facts "${run_high}" "${commit_b}")"$'\n'
fetch "neuere Freigabe: deploy" 0 "" deploy "${work}/state" "${no_switch}"

reset
state_with "${run_a}" "${commit_a}"
fetch "gleiche Freigabe: noop" 0 "" noop "${work}/state" "${no_switch}"
if [ -z "$(ls -A "${work}/rel")" ]; then ok "noop: nichts angelegt"; else bad "noop, aber Ordner angelegt"; fi

reset
state_with "${run_high}" "${commit_b}"
fetch "aeltere Freigabe: Downgrade" 6 "kleiner als gespeichert" - "${work}/state" "${no_switch}"

reset
state_with "${run_a}" "${commit_b}"
fetch "gleiche Run-ID, anderer Commit" 6 "anderem Commit" - "${work}/state" "${no_switch}"

reset
printf 'run\t0%s\ncommit\t%s\nbundle\t%s\n' "${run_a}" "${commit_a}" "${bundle_a}" >"${work}/state"
fetch "ungueltiger Zustand ohne Schalter" 6 "nicht lesbar oder ungueltig" - "${work}/state" "${no_switch}"

reset
state_with "${run_a}" "${commit_a}"
ln -s "${work}/state" "${work}/state.link" 2>/dev/null || true
if [ -L "${work}/state.link" ]; then
  FAKE_FACTS="$(facts "${run_high}" "${commit_b}")"$'\n'
  fetch "Zustand als Link" 6 "nicht lesbar oder ungueltig" - "${work}/state.link" "${no_switch}"
  rm -f "${work}/state.link"
fi

# --- Erst-Schalter ---------------------------------------------------------------
reset
printf 'x\n' >"${work}/eigener-schalter"
fetch "Schalter gehoert nicht root" 2 "Erst-Schalter gehoert nicht root" - "${work}/state" "${work}/eigener-schalter"
if need_switch "Schalter als Link"; then
  reset
  ln -s "${root_switch}" "${work}/schalter.link"
  fetch "Schalter als Link" 2 "Erst-Schalter ist ein symbolischer Link" - "${work}/state" "${work}/schalter.link"
  rm -f "${work}/schalter.link"
fi
reset
mkdir "${work}/schalter.dir"
fetch "Schalter ist Ordner" 2 "keine gewoehnliche Datei" - "${work}/state" "${work}/schalter.dir"
rmdir "${work}/schalter.dir"

# --- Freigabe und Fakten ---------------------------------------------------------
for code in 2 3 4 5; do
  reset
  state_with "${run_a}" "${commit_a}"
  FAKE_VERIFY_EXIT="${code}"
  fetch "verify-release.sh Exit ${code} wird weitergegeben" "${code}" "Freigabe nicht verifiziert" - "${work}/state" "${no_switch}"
done
reset
FAKE_VERIFY_EXIT=7
fetch "verify-release.sh unerwarteter Exit" 3 "endete unerwartet" - "${work}/state" "${no_switch}"

reset
state_with "${run_a}" "${commit_a}"
# Ueber eine Datei statt "facts | head": head schliesst die Leitung frueh,
# facts endet dann mit SIGPIPE, und pipefail beendet den Test (Exit 141).
facts "${run_high}" "${commit_b}" >"${work}/facts"
FAKE_FACTS="$(head -n 6 "${work}/facts")"$'\n'
fetch "nur sechs Fakten" 3 "genau sieben Fakten-Zeilen" - "${work}/state" "${no_switch}"

reset
state_with "${run_a}" "${commit_a}"
facts "${run_low}" "${commit_b}" >"${work}/facts"
FAKE_FACTS="$(printf 'freigabe\trun\t%s\n' "${run_high}"; cat "${work}/facts")"$'\n'
fetch "vorgetaeuschte Fakten-Zeile davor" 3 "genau sieben Fakten-Zeilen" - "${work}/state" "${no_switch}"

reset
state_with "${run_a}" "${commit_a}"
FAKE_FACTS="$(printf 'freigabe\trun\t%s\n' "${run_high}"; head -n 6 "${work}/facts")"$'\n'
fetch "Fakten in falscher Reihenfolge" 3 "Fakten unvollstaendig" - "${work}/state" "${no_switch}"

reset
state_with "${run_a}" "${commit_a}"
FAKE_FACTS="$(facts "${run_high}" "${commit_b}")"$'\nnoch eine Zeile\n'
fetch "Fakten nicht am Ende" 3 "nicht am Ende" - "${work}/state" "${no_switch}"

reset
state_with "${run_a}" "${commit_a}"
FAKE_FACTS="$(facts "a[\$(touch ${work}/pwned2)]" "${commit_b}")"$'\n'
fetch "Einschleusung in Run-ID der Fakten" 3 "Run-ID ungueltig" - "${work}/state" "${no_switch}"
if [ -e "${work}/pwned2" ]; then bad "Einschleusung im Einstieg ausgefuehrt"; else ok "Einschleusung im Einstieg nicht ausgefuehrt"; fi

# --- Bundle -----------------------------------------------------------------------
deploy_case() {
  reset
  state_with "${run_a}" "${commit_a}"
  FAKE_FACTS="$(facts "${run_high}" "${commit_b}")"$'\n'
}

deploy_case
rm "${work}/bundle/nginx.staging.conf"
fetch "Datei fehlt im Bundle" 3 "Fehlt im Bundle: nginx.staging.conf" - "${work}/state" "${no_switch}"

deploy_case
rm "${work}/bundle/compose.yaml"
ln -s /etc/hostname "${work}/bundle/compose.yaml" 2>/dev/null || true
if [ -L "${work}/bundle/compose.yaml" ]; then
  fetch "Link im Bundle" 3 "symbolischer Link: compose.yaml" - "${work}/state" "${no_switch}"
else
  echo "SKIP Link im Bundle (Dateisystem ohne Links)"
  skipped=$((skipped + 1))
fi

deploy_case
: >"${work}/bundle/compose.yaml"
fetch "leere Datei im Bundle" 3 "leer: compose.yaml" - "${work}/state" "${no_switch}"

deploy_case
rm "${work}/bundle/compose.yaml"
mkdir "${work}/bundle/compose.yaml"
printf 'x\n' >"${work}/bundle/compose.yaml/x"
fetch "Ordner statt Datei im Bundle" 3 "keine gewoehnliche Datei: compose.yaml" - "${work}/state" "${no_switch}"

deploy_case
head -c 300000 /dev/zero | tr '\0' 'x' >"${work}/bundle/compose.yaml"
fetch "zu grosse Datei im Bundle" 3 "zu gross" - "${work}/state" "${no_switch}"

deploy_case
export FAKE_CREATE_EXIT=1
fetch "Bundle nicht anlegbar" 3 "nicht anlegbar" - "${work}/state" "${no_switch}"

# Wiederholung nach gescheitertem Deploy: gleicher Inhalt ist in Ordnung,
# anderer bricht ab.
deploy_case
fetch "erster Lauf legt Ordner an" 0 "" deploy "${work}/state" "${no_switch}"
PATH="${work}/bin:${PATH}" bash "${inst}/fetch-release.sh" "${work}/state" "${no_switch}" "${work}/rel" "${work}/Dockerfile" \
  >"${work}/out" 2>"${work}/err" && grep -q "gleichem Inhalt" "${work}/out" \
  && ok "Wiederholung mit gleichem Inhalt" || bad "Wiederholung mit gleichem Inhalt"
printf 'veraendert\n' >"${work}/rel/${commit_b}/compose.yaml"
cp -r "${work}/rel" "${work}/rel.keep"
got=0
PATH="${work}/bin:${PATH}" bash "${inst}/fetch-release.sh" "${work}/state" "${no_switch}" "${work}/rel" "${work}/Dockerfile" \
  >"${work}/out" 2>"${work}/err" || got=$?
if [ "${got}" -eq 3 ] && grep -q "weicht ab: compose.yaml" "${work}/err" && diff -r "${work}/rel" "${work}/rel.keep" >/dev/null; then
  ok "Wiederholung mit anderem Inhalt: Abbruch, nichts ueberschrieben"
else
  bad "Wiederholung mit anderem Inhalt: Exit ${got}"
fi
rm -rf "${work}/rel.keep"

# --- Voraussetzungen ---------------------------------------------------------------
reset
FAKE_SECURITY="[name=seccomp,profile=builtin name=cgroupns]"
export FAKE_SECURITY
fetch "Docker nicht rootless" 2 "nicht rootless" - "${work}/state" "${no_switch}"
reset
FAKE_SECURITY="[name=rootlessX]"
export FAKE_SECURITY
fetch "nur aehnliche Option" 2 "nicht rootless" - "${work}/state" "${no_switch}"

reset
got=0
PATH="${work}/bin:${PATH}" bash "${inst}/fetch-release.sh" "${work}/state" "${no_switch}" "${work}/rel" \
  >"${work}/out" 2>"${work}/err" || got=$?
if [ "${got}" -eq 2 ] && grep -q "Erwartet: STATE_FILE" "${work}/err"; then ok "drei Parameter"; else bad "drei Parameter: Exit ${got}"; fi

reset
got=0
PATH="${work}/bin:${PATH}" bash "${inst}/fetch-release.sh" "state" "${no_switch}" "${work}/rel" "${work}/Dockerfile" \
  >"${work}/out" 2>"${work}/err" || got=$?
if [ "${got}" -eq 2 ] && grep -q "absolut" "${work}/err"; then ok "relativer Pfad"; else bad "relativer Pfad: Exit ${got}"; fi

reset
rm -rf "${work}/rel"
got=0
PATH="${work}/bin:${PATH}" bash "${inst}/fetch-release.sh" "${work}/state" "${no_switch}" "${work}/rel" "${work}/Dockerfile" \
  >"${work}/out" 2>"${work}/err" || got=$?
if [ "${got}" -eq 2 ] && grep -q "RELEASES_DIR fehlt" "${work}/err"; then ok "Releases-Ordner fehlt"; else bad "Releases-Ordner fehlt: Exit ${got}"; fi
mkdir "${work}/rel"

# docker fehlt: Exit 2, nie 0 (CLAUDE.md Abschnitt 7). Die uebrigen
# Werkzeuge bleiben erreichbar, nur docker nicht.
for tool in bash id stat cmp timeout mktemp cat grep tail find chmod mkdir dirname mv wc rm cp; do
  p="$(command -v "${tool}")" && ln -sf "${p}" "${work}/leer/${tool}" 2>/dev/null || cp "${p}" "${work}/leer/" 2>/dev/null || true
done
# Unter Git Bash auf Windows laufen kopierte Programme ohne ihre DLLs nicht;
# dann ist der Fall nicht pruefbar und wird gezaehlt uebersprungen.
if PATH="${work}/leer" dirname / >/dev/null 2>&1; then
  got=0
  PATH="${work}/leer" "${BASH}" "${inst}/fetch-release.sh" "${work}/state" "${no_switch}" "${work}/rel" "${work}/Dockerfile" \
    >"${work}/out" 2>"${work}/err" || got=$?
  if [ "${got}" -eq 2 ] && grep -q "docker wurde nicht gefunden" "${work}/err"; then ok "docker fehlt"; else bad "docker fehlt: Exit ${got}"; fi
else
  echo "SKIP docker fehlt (Werkzeuge im leeren PATH nicht lauffaehig)"
  skipped=$((skipped + 1))
fi

# =============================================================================
if [ "${skipped}" -ne 0 ]; then
  echo "${skipped} Fall/Faelle uebersprungen."
  [ "${CI:-}" != "true" ] || fail 3 "In der CI darf kein Fall uebersprungen werden."
fi
if [ "${failures}" -ne 0 ]; then
  fail 3 "${failures} Fall/Faelle weichen ab."
fi
echo "Alle Faelle wie erwartet."
