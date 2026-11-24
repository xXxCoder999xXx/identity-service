#!/usr/bin/env bash
# =============================================================================
# Faelle fuer scripts/restart-api.sh (API-Neustart, PR 4d-3c) mit Ersatz fuer
# docker, curl, flock und sleep.
#
# Aufruf:  bash scripts/test-restart-api.sh
#
# Warum ein Ersatz: restart-api.sh laeuft echt nur auf dem Server, und das
# erste Mal bei der ersten Erneuerung des API-Zertifikats. Ein Fehler zeigte
# sich sonst erst dort. Jeder Fall verlangt Exit-Code UND Grund (E-5-114).
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
for f in restart-api.sh lib/staging-runtime.sh; do
  [ -r "${here}/${f}" ] || fail 2 "Datei fehlt: ${here}/${f}"
done

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

failures=0
ok() { echo "ok   $1"; }
bad() {
  echo "FEHLER $1"
  failures=$((failures + 1))
}

inst="${work}/inst"
mkdir -p "${inst}/lib" "${work}/bin"
cp "${here}/restart-api.sh" "${inst}/"
cp "${here}/lib/staging-runtime.sh" "${inst}/lib/"
export FAKE_LOG="${work}/calls.log"
id_a="$(printf 'a%.0s' $(seq 1 64))"
id_b="$(printf 'b%.0s' $(seq 1 64))"

cat >"${work}/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"${FAKE_LOG}"
case "$1" in
  info)
    [ "${FAKE_INFO_EXIT:-0}" = "0" ] || exit "${FAKE_INFO_EXIT}"
    printf '%s\n' "${FAKE_SECURITY:-[name=seccomp,profile=builtin name=rootless name=cgroupns]}"
    exit 0 ;;
  ps)
    [ "${FAKE_PS_EXIT:-0}" = "0" ] || exit "${FAKE_PS_EXIT}"
    [ -z "${FAKE_IDS:-}" ] || printf '%s\n' ${FAKE_IDS}
    exit 0 ;;
  restart)
    [ "${FAKE_RESTART_EXIT:-0}" = "0" ] || exit "${FAKE_RESTART_EXIT}"
    printf '%s\n' "$2"
    exit 0 ;;
esac
echo "unerwarteter Aufruf: $*" >&2
exit 99
EOF

cat >"${work}/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"${FAKE_LOG}"
grep -q '^docker restart' "${FAKE_LOG}" || exit 7
exit "${FAKE_HEALTH_EXIT:-0}"
EOF

cat >"${work}/bin/flock" <<'EOF'
#!/usr/bin/env bash
echo "flock $*" >>"${FAKE_LOG}"
exit "${FAKE_FLOCK_EXIT:-0}"
EOF

cat >"${work}/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${work}/bin/"* "${inst}/restart-api.sh"

sd="${work}/state-dir"
reset() {
  rm -rf -- "${sd}" "${work}/site"
  mkdir -p "${sd}" "${work}/site"
  : >"${FAKE_LOG}"
  printf 'server_name staging.example.test;\n' >"${work}/site/server_name.conf"
  export STAGING_SERVER_NAME_FILE="${work}/site/server_name.conf"
  export FAKE_IDS="${id_a}"
  unset FAKE_INFO_EXIT FAKE_SECURITY FAKE_PS_EXIT FAKE_RESTART_EXIT FAKE_HEALTH_EXIT FAKE_FLOCK_EXIT
}

# restart LABEL CODE GRUND [Parameter]
restart() {
  local label="$1" code="$2" reason="$3" got=0 all
  shift 3
  local args=("${sd}")
  [ "$#" -eq 0 ] || args=("$@")
  PATH="${work}/bin:${PATH}" bash "${inst}/restart-api.sh" "${args[@]}" \
    >"${work}/out" 2>"${work}/err" || got=$?
  all="$(cat "${work}/out" "${work}/err")"
  if [ "${got}" -eq "${code}" ] && [[ "${all}" == *"${reason}"* ]]; then
    ok "${label}"
  else
    bad "${label}: erwartet Exit ${code} mit '${reason}', erhalten Exit ${got}"
    tail -n 3 "${work}/err" | sed 's/^/  stderr: /'
  fi
}
has() { if grep -qF -- "$2" "${FAKE_LOG}"; then ok "$1"; else bad "$1: '$2' nicht aufgerufen"; fi; }
hasnt() { if grep -qF -- "$2" "${FAKE_LOG}"; then bad "$1: '$2' aufgerufen"; else ok "$1"; fi; }

echo "== Erfolg"
reset
restart "Neustart und Health gruen" 0 "API neu gestartet und gesund"
has "Neustart genau dieses Containers" "docker restart ${id_a}"
has "Container ueber Projekt-Label" "label=com.docker.compose.project=identity-service-staging"
has "Container ueber Dienst-Label" "label=com.docker.compose.service=api"
has "ohne Einmal-Container (compose run)" "label=com.docker.compose.oneoff=False"
has "Sperre wartend mit Frist" "flock -w 3000 9"
has "Health ueber nginx an die eigene Adresse" "--resolve staging.example.test:443:127.0.0.1 https://staging.example.test/health"
order="$(grep -oE '^(docker info|flock|docker ps|docker restart|curl)' "${FAKE_LOG}" | uniq | tr '\n' ',')"
if [ "${order}" = "docker info,flock,docker ps,docker restart,curl," ]; then
  ok "Reihenfolge: rootless, Sperre, Suche, Neustart, Health"
else
  bad "Reihenfolge ${order}"
fi
if [ -e "${sd}/.deploy.lock" ]; then ok "Sperrdatei im STATE_DIR"; else bad "keine Sperrdatei im STATE_DIR"; fi

echo "== Voraussetzungen (Exit 2)"
reset
restart "zwei Parameter" 2 "Erwartet: STATE_DIR" "/a" "/b"
reset
restart "relativer Pfad" 2 "Pfad muss absolut sein" "state"
reset
restart "STATE_DIR fehlt" 2 "STATE_DIR fehlt" "${work}/gibt-es-nicht"
reset
unset STAGING_SERVER_NAME_FILE
restart "ohne STAGING_SERVER_NAME_FILE" 2 "STAGING_SERVER_NAME_FILE fehlt"
reset
printf 'server_name a; include /etc/passwd;\n' >"${work}/site/server_name.conf"
restart "server_name mit Zusatz" 2 "nicht genau 'server_name <name>;'"
hasnt "server_name ungueltig: kein Docker" "docker "
reset
export FAKE_SECURITY="[name=seccomp,profile=builtin name=cgroupns]"
restart "Docker nicht rootless" 2 "Docker laeuft nicht rootless"
hasnt "nicht rootless: kein Neustart" "docker restart"
hasnt "nicht rootless: keine Sperre" "flock"
reset
export FAKE_INFO_EXIT=1
restart "docker info scheitert" 2 "docker info gescheitert"

echo "== Sperre (Exit 6, 2)"
reset
mkdir "${sd}/.deploy.lock"
restart "Sperrdatei nicht anlegbar" 2 "Sperrdatei nicht anlegbar"
hasnt "Sperrdatei rot: kein Neustart" "docker restart"
reset
export FAKE_FLOCK_EXIT=1
restart "Sperre nicht rechtzeitig" 6 "Sperre nach 3000 s nicht erhalten"
hasnt "Sperre rot: kein Neustart" "docker restart"

echo "== API-Container (Exit 3)"
reset
export FAKE_IDS=""
restart "kein API-Container (vor dem ersten Deploy)" 3 "gefunden 0"
hasnt "kein Container: kein Neustart" "docker restart"
reset
export FAKE_IDS="${id_a} ${id_b}"
restart "zwei API-Container" 3 "gefunden 2"
hasnt "zwei Container: kein Neustart" "docker restart"
reset
export FAKE_IDS="kaputt"
restart "keine Container-ID" 3 "keine Container-ID"
reset
export FAKE_PS_EXIT=1
restart "docker ps scheitert" 7 "docker ps gescheitert"

echo "== Neustart und Health (Exit 4, 5)"
reset
export FAKE_RESTART_EXIT=1
restart "docker restart scheitert" 4 "docker restart gescheitert"
hasnt "Neustart rot: keine Health" "curl "
reset
export FAKE_HEALTH_EXIT=22
restart "Health nach Neustart rot" 5 "API nach dem Neustart ungesund"
if [ "$(grep -c '^curl ' "${FAKE_LOG}")" = "12" ]; then ok "Health: zwoelf Versuche"; else bad "Health: $(grep -c '^curl ' "${FAKE_LOG}") Versuche statt 12"; fi

echo
echo "Ergebnis: ${failures} Abweichung(en)"
[ "${failures}" -eq 0 ] || exit 3
