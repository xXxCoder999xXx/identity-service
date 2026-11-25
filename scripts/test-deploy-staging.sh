#!/usr/bin/env bash
# =============================================================================
# Faelle fuer scripts/deploy-staging.sh (Pull-Deploy, PR 4d-3a) mit Ersatz
# fuer docker, curl, flock, sleep, fetch-release.sh,
# verify-package-private.sh und verify-attestations-server.sh.
#
# Aufruf:  bash scripts/test-deploy-staging.sh
#
# Warum ein Ersatz: deploy-staging.sh laeuft echt nur auf dem Server. Der
# Ersatz laesst jeden Exit-Pfad gezielt eintreten, ohne Registry, Token und
# laufenden Stack. Jeder Fall verlangt Exit-Code UND Grund (E-5-114). Nach
# jedem Fall wird geprueft, dass das Token in keiner Ausgabe und keinem
# Aufruf eines Ersatzprogramms steht und DOCKER_CONFIG wieder entfernt ist.
#
# Die Fachlogik der Bausteine (Downgrade-Regel, Nachweise, Sichtbarkeit)
# testen test-release-state.sh, test-package-private.sh und die Gegenproben
# selbst. Hier zaehlt der Ablauf: Reihenfolge, Weitergabe der Exit-Codes,
# Punkt ohne Wiederkehr, Rueckweg, current und Zustand.
#
# Braucht symbolische Links. Fehlen sie (Git Bash auf NTFS legt Kopien an),
# werden die Faelle uebersprungen und gezaehlt; in der CI (CI=true) ist das
# ein Fehler.
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
for f in deploy-staging.sh lib/release-rules.sh lib/release-state.sh lib/registry-only.sh lib/staging-runtime.sh; do
  [ -r "${here}/${f}" ] || fail 2 "Datei fehlt: ${here}/${f}"
done
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

ln -s "${work}" "${work}/linkprobe" 2>/dev/null || true
if [ ! -L "${work}/linkprobe" ]; then
  echo "SKIP alle Faelle (Dateisystem ohne symbolische Links)"
  if [ "${CI:-}" = "true" ]; then fail 3 "In der CI muessen die Faelle laufen."; fi
  exit 0
fi
rm -f "${work}/linkprobe"

hex() { printf "$1%.0s" $(seq 1 "$2"); }
prefix="ghcr.io/xxxcoder999xxx"
run_a="45202570572"
run_b="45437830490"
commit_a="$(hex a 40)"
commit_b="$(hex b 40)"
bundle_a="sha256:$(hex c 64)"
bundle_b="sha256:$(hex d 64)"
old_api="${prefix}/identity-service@sha256:$(hex a 64)"
old_nginx="${prefix}/identity-service-nginx@sha256:$(hex a 64)"
old_lego="${prefix}/identity-service-lego@sha256:$(hex a 64)"
new_api="${prefix}/identity-service@sha256:$(hex 1 64)"
new_nginx="${prefix}/identity-service-nginx@sha256:$(hex 2 64)"
new_lego="${prefix}/identity-service-lego@sha256:$(hex 3 64)"
token="ghp_$(hex Q 36)"
ping_url="https://hc-ping.example/abc-123"

# --- Installation wie auf dem Server --------------------------------------------
inst="${work}/inst"
mkdir -p "${inst}/lib" "${work}/bin"
cp "${here}/deploy-staging.sh" "${inst}/"
cp "${here}/lib/release-rules.sh" "${here}/lib/release-state.sh" "${here}/lib/registry-only.sh" "${here}/lib/staging-runtime.sh" "${inst}/lib/"
export FAKE_LOG="${work}/calls.log"
export FAKE_RUNNING="${work}/running"
export FAKE_LOGIN_STDIN="${work}/login.stdin"
export FAKE_CONTAINERS="${work}/containers"

# staging.json wie in deploy/: Parameter DATEI API NGINX LEGO
cat >"${work}/write-json" <<'EOF'
mkdir -p "$(dirname "$1")"
printf '{\n  "schema": 1,\n  "environment": "staging",\n  "images": {\n    "api": "%s",\n    "nginx": "%s",\n    "lego": "%s"\n  }\n}\n' "$2" "$3" "$4" >"$1"
EOF

cat >"${inst}/fetch-release.sh" <<EOF
#!/usr/bin/env bash
echo "fetch \$*" >>"\${FAKE_LOG}"
echo "== Ersatz fuer fetch-release.sh"
[ "\${FAKE_FETCH_EXIT:-0}" = "0" ] || exit "\${FAKE_FETCH_EXIT}"
if [ -n "\${FAKE_FETCH_OUT:-}" ]; then printf '%s' "\${FAKE_FETCH_OUT}"; exit 0; fi
dir="-"
if [ "\${FAKE_DECISION}" != "noop" ]; then
  dir="\${FAKE_FETCH_DIR:-\$3/\${FAKE_COMMIT}}"
  if [ "\${FAKE_NO_DIR:-}" != "yes" ]; then
    mkdir -p "\${dir}/docker/nginx"
    touch "\${dir}/compose.yaml" "\${dir}/compose.staging.yaml" "\${dir}/docker/nginx/Dockerfile"
    . "${work}/write-json" "\${dir}/deploy/staging.json" "\${FAKE_API}" "\${FAKE_NGINX}" "\${FAKE_LEGO}"
  fi
fi
printf 'release\tdecision\t%s\n' "\${FAKE_DECISION}"
printf 'release\tdir\t%s\n' "\${dir}"
printf 'release\trun\t%s\n' "\${FAKE_RUN}"
printf 'release\tattempt\t1\n'
printf 'release\tcommit\t%s\n' "\${FAKE_COMMIT}"
printf 'release\tsubject\t%s\n' "\${FAKE_BUNDLE}"
printf 'release\tapi\t%s\n' "\${FAKE_API}"
printf 'release\tnginx\t%s\n' "\${FAKE_NGINX}"
printf 'release\tlego\t%s\n' "\${FAKE_LEGO}"
EOF

cat >"${inst}/verify-package-private.sh" <<'EOF'
#!/usr/bin/env bash
echo "visibility $*" >>"${FAKE_LOG}"
exit "${FAKE_VIS_EXIT:-0}"
EOF

cat >"${inst}/verify-attestations-server.sh" <<'EOF'
#!/usr/bin/env bash
echo "attest $*" >>"${FAKE_LOG}"
if [ "$1" = "${FAKE_ATTEST_FAIL_REF:-}" ]; then exit "${FAKE_ATTEST_EXIT}"; fi
exit 0
EOF

cat >"${work}/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $* | API_IMAGE=${API_IMAGE:-} NGINX_IMAGE=${NGINX_IMAGE:-} LEGO_IMAGE=${LEGO_IMAGE:-}" >>"${FAKE_LOG}"
case "$1" in
  info)
    [ "${FAKE_INFO_EXIT:-0}" = "0" ] || exit "${FAKE_INFO_EXIT}"
    printf '%s\n' "${FAKE_SECURITY:-[name=seccomp,profile=builtin name=rootless name=cgroupns]}"
    exit 0 ;;
  login)
    [ -n "${DOCKER_CONFIG:-}" ] && [ -d "${DOCKER_CONFIG}" ] || { echo "kein DOCKER_CONFIG" >&2; exit 1; }
    cat >"${FAKE_LOGIN_STDIN}"
    exit "${FAKE_LOGIN_EXIT:-0}" ;;
  pull) exit "${FAKE_PULL_EXIT:-0}" ;;
  image)
    if [ -n "${FAKE_INSPECT_OUT:-}" ]; then printf '%s\n' "${FAKE_INSPECT_OUT}"; else printf '%s\n' "${@: -1}"; fi
    exit 0 ;;
  ps)
    [ "${FAKE_PS_EXIT:-0}" = "0" ] || exit "${FAKE_PS_EXIT}"
    n=$(( $(cat "${FAKE_CONTAINERS}.calls" 2>/dev/null || echo 0) + 1 ))
    echo "${n}" >"${FAKE_CONTAINERS}.calls"
    [ -z "${FAKE_PS_FAIL_FROM:-}" ] || [ "${n}" -lt "${FAKE_PS_FAIL_FROM}" ] || exit 1
    cat "${FAKE_CONTAINERS}" 2>/dev/null || true
    exit 0 ;;
  rm)
    [ "${FAKE_RM_KEEP:-}" = "yes" ] || rm -f "${FAKE_CONTAINERS}"
    exit "${FAKE_RM_EXIT:-0}" ;;
  compose)
    # Einmal-Lauf (lego): startet keinen Dienst, hinterlaesst auf Wunsch
    # einen Container wie nach einem Abbruch.
    for a in "$@"; do
      if [ "${a}" = "run" ]; then
        [ "${FAKE_LEGO_LEAVE:-}" != "yes" ] || printf '%s\n' "$(printf 'f%.0s' $(seq 1 64))" >>"${FAKE_CONTAINERS}"
        exit "${FAKE_LEGO_EXIT:-0}"
      fi
    done
    for bad in ${FAKE_COMPOSE_FAIL_API:-}; do
      [ "${API_IMAGE}" != "${bad}" ] || exit 1
    done
    printf '%s' "${API_IMAGE}" >"${FAKE_RUNNING}"
    exit 0 ;;
esac
echo "unerwarteter Aufruf: $*" >&2
exit 99
EOF

cat >"${work}/bin/curl" <<'EOF'
#!/usr/bin/env bash
ping="no"
data=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -K) ping="yes" ;;
    --data-binary) data="$2"; shift ;;
  esac
  shift
done
if [ "${ping}" = "yes" ]; then
  config="$(cat)"
  url="${config#url = \"}"
  url="${url%\"}"
  echo "ping ${url} | ${data}" >>"${FAKE_LOG}"
  exit "${FAKE_PING_EXIT:-0}"
fi
echo "health" >>"${FAKE_LOG}"
running="$(cat "${FAKE_RUNNING}" 2>/dev/null || true)"
[ -n "${running}" ] || exit 7
for bad in ${FAKE_BAD_API:-}; do
  [ "${running}" != "${bad}" ] || exit 22
done
exit 0
EOF

cat >"${work}/bin/flock" <<'EOF'
#!/usr/bin/env bash
exit "${FAKE_FLOCK_EXIT:-0}"
EOF

cat >"${work}/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "${work}/bin/"* "${inst}/"*.sh

# --- Ausgangszustand je Fall ----------------------------------------------------
sd="${work}/state-dir"
reset() {
  rm -rf -- "${sd}" "${work}/cred" "${work}/run" "${work}/site" "${FAKE_LOG}" "${FAKE_RUNNING}" "${FAKE_LOGIN_STDIN}" "${FAKE_CONTAINERS}" "${FAKE_CONTAINERS}.calls"
  mkdir -p "${sd}/releases" "${work}/cred" "${work}/run" "${work}/site/ca" "${work}/site/api-tls"
  printf '%s\n' "${token}" >"${work}/cred/ghcr-token"
  printf '%s\n' "${ping_url}" >"${work}/cred/ping-url"
  printf 'server_name staging.example.test;\n' >"${work}/site/server_name.conf"
  printf 'FROM nginxinc/nginx-unprivileged@sha256:%s\n' "$(hex e 64)" >"${work}/site/install.Dockerfile"
  : >"${FAKE_LOG}"
  export CREDENTIALS_DIRECTORY="${work}/cred"
  export RUNTIME_DIRECTORY="${work}/run"
  export GHCR_USERNAME="deploy-bot"
  export STAGING_SERVER_NAME_FILE="${work}/site/server_name.conf"
  export STAGING_CA_DIR="${work}/site/ca"
  export STAGING_API_CERT_DIR="${work}/site/api-tls"
  export FAKE_DECISION="deploy" FAKE_RUN="${run_b}" FAKE_COMMIT="${commit_b}" FAKE_BUNDLE="${bundle_b}"
  export FAKE_API="${new_api}" FAKE_NGINX="${new_nginx}" FAKE_LEGO="${new_lego}"
  unset FAKE_FETCH_EXIT FAKE_FETCH_OUT FAKE_FETCH_DIR FAKE_NO_DIR FAKE_VIS_EXIT FAKE_ATTEST_FAIL_REF \
    FAKE_ATTEST_EXIT FAKE_LOGIN_EXIT FAKE_PULL_EXIT FAKE_INSPECT_OUT FAKE_COMPOSE_FAIL_API \
    FAKE_BAD_API FAKE_PING_EXIT FAKE_FLOCK_EXIT FAKE_INFO_EXIT FAKE_SECURITY \
    FAKE_PS_EXIT FAKE_PS_FAIL_FROM FAKE_RM_KEEP FAKE_RM_EXIT FAKE_LEGO_LEAVE FAKE_LEGO_EXIT
}

# Laufender alter Stand: Release a ist ausgerollt und gesund.
with_current() {
  mkdir -p "${sd}/releases/${commit_a}/docker/nginx"
  touch "${sd}/releases/${commit_a}/compose.yaml" "${sd}/releases/${commit_a}/compose.staging.yaml"
  printf 'FROM nginxinc/nginx-unprivileged@sha256:%s\n' "$(hex f 64)" >"${sd}/releases/${commit_a}/docker/nginx/Dockerfile"
  . "${work}/write-json" "${sd}/releases/${commit_a}/deploy/staging.json" "${old_api}" "${old_nginx}" "${old_lego}"
  ln -s "releases/${commit_a}" "${sd}/current"
  release_state_render "${run_a}" "${commit_a}" "${bundle_a}" >"${sd}/state"
  printf '%s' "${old_api}" >"${FAKE_RUNNING}"
}

# deploy LABEL CODE GRUND [Parameter statt der drei ueblichen]
# GRUND wird in stdout und stderr gesucht.
deploy() {
  local label="$1" code="$2" reason="$3" got=0 all
  shift 3
  local args=("${sd}" "${work}/kein-schalter" "${work}/site/install.Dockerfile")
  [ "$#" -eq 0 ] || args=("$@")
  PATH="${work}/bin:${PATH}" bash "${inst}/deploy-staging.sh" "${args[@]}" \
    >"${work}/out" 2>"${work}/err" || got=$?
  all="$(cat "${work}/out" "${work}/err")"
  if [ "${got}" -eq "${code}" ] && [[ "${all}" == *"${reason}"* ]]; then
    ok "${label}"
  else
    bad "${label}: erwartet Exit ${code} mit '${reason}', erhalten Exit ${got}"
    tail -n 5 "${work}/err" | sed 's/^/  stderr: /'
  fi
  if grep -qF -- "${token}" "${work}/out" "${work}/err" "${FAKE_LOG}"; then
    bad "${label}: Token in Ausgabe oder Aufruf"
  fi
  if grep -qF -- "${ping_url}" "${work}/out" "${work}/err"; then
    bad "${label}: Ping-URL in der Ausgabe"
  fi
  if [ -e "${work}/run/docker" ]; then
    bad "${label}: DOCKER_CONFIG nach dem Lauf noch vorhanden"
  fi
}

# Erwartungen an das Protokoll der Ersatzprogramme.
has() { if grep -qF -- "$2" "${FAKE_LOG}"; then ok "$1"; else bad "$1: '$2' nicht aufgerufen"; fi; }
hasnt() { if grep -qF -- "$2" "${FAKE_LOG}"; then bad "$1: '$2' aufgerufen"; else ok "$1"; fi; }
count() {
  local n
  n="$(grep -cF -- "$2" "${FAKE_LOG}" || true)"
  if [ "${n}" = "$3" ]; then ok "$1"; else bad "$1: '$2' ${n}-mal statt $3-mal"; fi
}
current_is() {
  local got
  got="$(readlink "${sd}/current" 2>/dev/null || echo "-")"
  if [ "${got}" = "$2" ]; then ok "$1"; else bad "$1: current '${got}' statt '$2'"; fi
}
state_run_is() {
  STATE_RUN=""
  release_state_parse "${sd}/state" 2>/dev/null || true
  if [ "${STATE_RUN}" = "$2" ]; then ok "$1"; else bad "$1: Zustand '${STATE_RUN}' statt '$2'"; fi
}
ping_is() {
  local n
  n="$(grep -c '^ping ' "${FAKE_LOG}" || true)"
  if [ "${n}" = "1" ] && grep -qF -- "ping $2 | $3" "${FAKE_LOG}"; then ok "$1"; else bad "$1: erwartet ein Ping '$2 | $3'"; grep '^ping ' "${FAKE_LOG}" | sed 's/^/  /'; fi
}

# =============================================================================
echo "== Erfolg"
reset
with_current
deploy "neue Freigabe: deploy" 0 "Ausgerollt: run ${run_b}"
current_is "deploy: current zeigt auf neuen Commit" "releases/${commit_b}"
state_run_is "deploy: Zustand hat neue Run-ID" "${run_b}"
has "deploy: compose up mit neuen Images" "API_IMAGE=${new_api} NGINX_IMAGE=${new_nginx} LEGO_IMAGE=${new_lego}"
has "deploy: compose mit festem Projektnamen" "compose -p identity-service-staging"
has "deploy: compose ohne Pull und Build" "--no-build --pull never"
has "deploy: Gegenprobe mit Dockerfile aus current (E-5-177)" "${sd}/releases/${commit_a}/docker/nginx/Dockerfile"
count "deploy: vier Pakete auf Sichtbarkeit" "visibility " 4
count "deploy: drei Images im Pruef-Gate" "attest " 3
count "deploy: drei Pulls" "docker pull " 3
hasnt "deploy: kein lego (nur bei first)" "--profile acme"
hasnt "deploy: keine Leer-Pruefung (nur bei first)" "docker ps"
ping_is "deploy: ok-Ping" "${ping_url}" "deploy-staging exit 0"
if [ "$(cat "${FAKE_LOGIN_STDIN}")" = "${token}" ]; then ok "deploy: Token per stdin, ohne Zeilenende"; else bad "deploy: Token per stdin weicht ab"; fi
if [ -z "$(find "${sd}" -maxdepth 1 -name '.current.*' -o -maxdepth 1 -name '.state.*')" ]; then
  ok "deploy: keine temporaeren Dateien"
else
  bad "deploy: temporaere Dateien uebrig"
fi
# Reihenfolge: Sichtbarkeit, Freigabe, Pruef-Gate, Pull, compose.
order="$(grep -oE '^(visibility|fetch|attest|docker pull|docker compose)' "${FAKE_LOG}" | uniq | tr '\n' ',')"
if [ "${order}" = "visibility,fetch,attest,docker pull,docker compose," ]; then
  ok "deploy: Reihenfolge der Schritte"
else
  bad "deploy: Reihenfolge ${order}"
fi

reset
export FAKE_DECISION="first"
deploy "kein Zustand: first" 0 "Den Erst-Schalter jetzt von Hand loeschen"
current_is "first: current angelegt" "releases/${commit_b}"
state_run_is "first: Zustand angelegt" "${run_b}"
has "first: Gegenprobe mit Dockerfile aus der Installation" "${work}/site/install.Dockerfile"
ping_is "first: ok-Ping" "${ping_url}" "deploy-staging exit 0"
has "first: lego als Einmal-Lauf im Profil acme" "compose -p identity-service-staging --project-directory ${sd}/releases/${commit_b} -f ${sd}/releases/${commit_b}/compose.yaml -f ${sd}/releases/${commit_b}/compose.staging.yaml --profile acme run --rm -T --pull never --publish 0.0.0.0:80:8080 lego"
has "first: lego standalone auf 8080, Name edge, Domain vom Server" "lego run --path /data --accept-tos --http --http.address :8080 --cert.name edge --domains staging.example.test |"
has "first: lego mit geprueftem Digest" "--profile acme run --rm -T --pull never --publish 0.0.0.0:80:8080 lego run --path /data --accept-tos --http --http.address :8080 --cert.name edge --domains staging.example.test | API_IMAGE=${new_api} NGINX_IMAGE=${new_nginx} LEGO_IMAGE=${new_lego}"
hasnt "first: keine E-Mail an Let's Encrypt (E-5-66)" "--email"
hasnt "first: kein Webroot im Standalone-Lauf" "--http.webroot"
count "first: Projekt vor und nach lego geprueft" "docker ps -a -q --no-trunc --filter label=com.docker.compose.project=identity-service-staging |" 2
has "first: Port 80 nur auf IPv4 (E-5-73)" "--publish 0.0.0.0:80:8080"
hasnt "first: kein Container-Name (Aufraeumen nur ueber Labels)" "--name"
has "first: nach lego Einmal-Container von lego gesucht" "--filter label=com.docker.compose.project=identity-service-staging --filter label=com.docker.compose.service=lego --filter label=com.docker.compose.oneoff=True |"
hasnt "first: nichts zu entfernen, kein docker rm" "docker rm"
order="$(grep -oE '^(docker pull|docker ps|docker compose .* run --rm|docker rm|docker compose .* up -d)' "${FAKE_LOG}" | sed -E 's/^docker compose .* run --rm$/lego/; s/^docker compose .* up -d$/up/' | uniq | tr '\n' ',')"
if [ "${order}" = "docker pull,docker ps,lego,docker ps,up," ]; then
  ok "first: Reihenfolge Pull, leer, lego, aufraeumen und leer, up"
else
  bad "first: Reihenfolge ${order}"
fi

echo "== Erst-Zertifikat (Exit 2, 13)"
for code in 1 124 137; do
  reset
  export FAKE_DECISION="first" FAKE_LEGO_EXIT="${code}"
  deploy "first, lego Exit ${code}" 13 "Erst-Zertifikat nicht erhalten (lego Exit ${code})"
  hasnt "lego ${code}: kein compose up" "up -d"
  current_is "lego ${code}: kein current" "-"
  if [ ! -e "${sd}/state" ]; then ok "lego ${code}: kein Zustand"; else bad "lego ${code}: Zustand geschrieben"; fi
  ping_is "lego ${code}: fail-Ping mit Code" "${ping_url}/fail" "deploy-staging exit 13"
done

reset
export FAKE_DECISION="first"
printf '%s\n' "$(hex 7 64)" >"${FAKE_CONTAINERS}"
deploy "first, Projekt nicht leer" 2 "Erst-Modus verlangt ein leeres Projekt identity-service-staging (vor lego), gefunden 1"
hasnt "nicht leer: kein lego, kein up" "docker compose"
hasnt "nicht leer: nichts entfernt (Mensch entscheidet)" "docker rm"

reset
export FAKE_DECISION="first" FAKE_PS_EXIT=1
deploy "first, docker ps scheitert" 2 "docker ps gescheitert (vor lego)"
hasnt "ps rot: kein lego" "docker compose"

reset
export FAKE_DECISION="first" FAKE_LEGO_LEAVE="yes" FAKE_RM_KEEP="yes" FAKE_RM_EXIT=1
deploy "first, Einmal-Container bleibt" 13 "(nach lego), gefunden 1"
hasnt "Container bleibt: kein compose up" "up -d"

reset
export FAKE_DECISION="first" FAKE_PS_FAIL_FROM=2
deploy "first, docker ps scheitert nach lego" 13 "docker ps gescheitert (nach lego)"
hasnt "ps rot nach lego: kein compose up" "up -d"
hasnt "ps rot nach lego: nichts entfernt" "docker rm"

reset
export FAKE_DECISION="first" FAKE_LEGO_LEAVE="yes" FAKE_LEGO_EXIT=124
deploy "first, Abbruch hinterlaesst Container, rm raeumt auf" 13 "lego Exit 124"
has "Abbruch: Entfernen per ID" "docker rm -f $(hex f 64)"
if [ ! -s "${FAKE_CONTAINERS}" ]; then ok "Abbruch: Container entfernt"; else bad "Abbruch: Container uebrig"; fi

echo "== Bibliothek: Label-Filter"
for label in "com.docker.compose.oneoff" "" "a=b c"; do
  got=0
  (PATH="${work}/bin:${PATH}" FAKE_LOG=/dev/null; . "${inst}/lib/staging-runtime.sh"; staging_container_ids "${label}") >/dev/null 2>&1 || got=$?
  if [ "${got}" -ne 0 ]; then ok "Label-Filter '${label}' abgelehnt"; else bad "Label-Filter '${label}' angenommen"; fi
done
: >"${FAKE_LOG}"
got=0
(PATH="${work}/bin:${PATH}"; . "${inst}/lib/staging-runtime.sh"; staging_container_ids "com.docker.compose.oneoff=False") >/dev/null 2>&1 || got=$?
if [ "${got}" -eq 0 ]; then ok "Label-Filter gueltig angenommen"; else bad "Label-Filter gueltig abgelehnt (Exit ${got})"; fi
has "Label-Filter gueltig: Projekt plus Zusatz" "docker ps -a -q --no-trunc --filter label=com.docker.compose.project=identity-service-staging --filter label=com.docker.compose.oneoff=False |"

reset
printf '%s\r\n' "${token}" >"${work}/cred/ghcr-token"
deploy "Token mit CRLF" 0 "angemeldet"
if [ "$(cat "${FAKE_LOGIN_STDIN}")" = "${token}" ]; then ok "CRLF: Token ohne CR uebergeben"; else bad "CRLF: Token mit CR uebergeben"; fi

echo "== noop"
reset
with_current
export FAKE_DECISION="noop" FAKE_RUN="${run_a}" FAKE_COMMIT="${commit_a}" FAKE_BUNDLE="${bundle_a}"
deploy "noop, Stand gesund" 0 "Nichts zu tun"
hasnt "noop: kein compose" "docker compose"
hasnt "noop: kein lego" "--profile acme"
hasnt "noop: kein Pruef-Gate" "attest "
ping_is "noop: ok-Ping" "${ping_url}" "deploy-staging exit 0"

reset
with_current
export FAKE_DECISION="noop" FAKE_RUN="${run_a}" FAKE_COMMIT="${commit_a}" FAKE_BUNDLE="${bundle_a}"
export FAKE_BAD_API="${old_api}"
deploy "noop, Stand ungesund" 12 "laufende Stand ist ungesund"
hasnt "noop ungesund: kein compose" "docker compose"
ping_is "noop ungesund: fail-Ping mit Code" "${ping_url}/fail" "deploy-staging exit 12"

echo "== Sperre und Ping"
reset
with_current
export FAKE_FLOCK_EXIT=1
deploy "Sperre belegt" 0 "Sperre belegt (Deploy oder API-Neustart)"
hasnt "Sperre: keine Freigabe geholt" "fetch "
hasnt "Sperre: kein Ping" "ping "

reset
with_current
mkdir "${sd}/.deploy.lock"
deploy "Sperrdatei nicht anlegbar" 2 "Sperrdatei nicht anlegbar"
hasnt "Sperrdatei rot: keine Freigabe geholt" "fetch "

reset
with_current
rm -f "${work}/cred/ping-url"
deploy "ohne Ping-URL: Deploy laeuft, kein Ping" 0 "kein Ping gesendet"
hasnt "ohne Ping-URL: kein Ping" "ping "

reset
with_current
printf 'http://hc-ping.example/x\n' >"${work}/cred/ping-url"
deploy "Ping-URL ohne https" 0 "unerwartete Form"
hasnt "Ping-URL ohne https: kein Ping" "ping "

reset
with_current
export FAKE_PING_EXIT=7
deploy "Ping scheitert: Exit bleibt" 0 "Ping fehlgeschlagen"

echo "== Voraussetzungen (Exit 2)"
reset
deploy "zu wenige Parameter" 2 "Erwartet: STATE_DIR" "${sd}"
ping_is "Parameter: fail-Ping" "${ping_url}/fail" "deploy-staging exit 2: Erwartet"
reset
deploy "relativer Pfad" 2 "Pfad muss absolut sein" "state" "${work}/kein-schalter" "${work}/site/install.Dockerfile"
reset
unset RUNTIME_DIRECTORY
deploy "ohne RUNTIME_DIRECTORY" 2 "RUNTIME_DIRECTORY fehlt"
reset
export GHCR_USERNAME="bad name"
deploy "ungueltiger Benutzername" 2 "GHCR_USERNAME fehlt"
reset
export STAGING_CA_DIR="relativ/ca"
deploy "STAGING_CA_DIR relativ" 2 "STAGING_CA_DIR fehlt"
reset
printf 'server_name a; include /etc/passwd;\n' >"${work}/site/server_name.conf"
deploy "server_name mit Zusatz" 2 "nicht genau 'server_name <name>;'"
reset
printf 'ghp_kurz\n' >"${work}/cred/ghcr-token"
deploy "Token falsche Form" 2 "nicht die Form eines klassischen Tokens"
hasnt "Token falsche Form: kein Login" "docker login"
reset
printf 'github_pat_%s\n' "$(hex Z 60)" >"${work}/cred/ghcr-token"
deploy "fein abgestuftes Token" 2 "nicht die Form eines klassischen Tokens"
reset
rm -f "${work}/cred/ghcr-token"
deploy "Token fehlt" 2 "ghcr-token nicht lesbar"
reset
export FAKE_SECURITY="[name=seccomp,profile=builtin name=cgroupns]"
deploy "Docker nicht rootless: kein Token an den Daemon" 2 "Docker laeuft nicht rootless"
hasnt "nicht rootless: kein Login" "docker login"
reset
export FAKE_INFO_EXIT=1
deploy "docker info scheitert" 2 "docker info gescheitert"
hasnt "docker info rot: kein Login" "docker login"
reset
deploy "Pruefung vor dem Login (Reihenfolge)" 0 "docker rootless"
order="$(grep -oE '^docker (info|login)' "${FAKE_LOG}" | head -n 2 | tr '\n' ',')"
if [ "${order}" = "docker info,docker login," ]; then ok "info vor login"; else bad "Reihenfolge info/login: ${order}"; fi
reset
export FAKE_LOGIN_EXIT=1
deploy "Login scheitert" 2 "docker login an ghcr.io gescheitert"
hasnt "Login scheitert: keine Freigabe geholt" "fetch "
reset
with_current
rm -f "${sd}/current"
deploy "Zustand ohne current" 2 "current fehlt oder ist ungueltig"
hasnt "Zustand ohne current: keine Freigabe geholt" "fetch "
reset
with_current
rm -f "${sd}/current"
ln -s "/tmp" "${sd}/current"
deploy "current zeigt nach aussen" 2 "current fehlt oder ist ungueltig"
reset
rm -f "${work}/site/install.Dockerfile"
deploy "Installations-Dockerfile fehlt" 2 "Dockerfile fuer die Gegenprobe fehlt"

echo "== Sichtbarkeit (Exit 7)"
for code in 2 3 4; do
  reset
  with_current
  export FAKE_VIS_EXIT="${code}"
  deploy "verify-package-private.sh Exit ${code}" 7 "Sichtbarkeit nicht belegt"
  hasnt "Sichtbarkeit ${code}: keine Freigabe geholt" "fetch "
done

echo "== Freigabe (Exit 2 bis 6, 3)"
for code in 2 3 4 5 6; do
  reset
  with_current
  export FAKE_FETCH_EXIT="${code}"
  deploy "fetch-release.sh Exit ${code} wird weitergegeben" "${code}" "fetch-release.sh Exit ${code}"
  hasnt "fetch ${code}: kein compose" "docker compose"
done
reset
with_current
export FAKE_FETCH_EXIT=9
deploy "fetch-release.sh unerwarteter Exit" 3 "endete unerwartet"
reset
with_current
export FAKE_FETCH_OUT=$'release\tdecision\tdeploy\n'
deploy "Ergebnis unvollstaendig" 3 "genau neun Ergebniszeilen"
reset
with_current
FAKE_FETCH_OUT="$(PATH="${work}/bin:${PATH}" FAKE_LOG=/dev/null bash "${inst}/fetch-release.sh" a b "${sd}/releases" d)"$'\nnoch eine Zeile\n'
export FAKE_FETCH_OUT
deploy "Ergebnis nicht am Ende" 3 "nicht am Ende"
reset
with_current
export FAKE_API="${prefix}/fremd@sha256:$(hex 1 64)"
deploy "API-Referenz mit fremdem Paket" 3 "API-Referenz ungueltig"
reset
with_current
export FAKE_NGINX="${new_nginx}:latest"
deploy "nginx-Referenz mit Tag" 3 "nginx-Referenz ungueltig"
reset
with_current
export FAKE_FETCH_DIR="${work}/anderswo"
deploy "Release-Ordner ausserhalb" 3 "passt nicht zum Commit"
reset
with_current
export FAKE_DECISION="vielleicht"
deploy "unbekannte Entscheidung" 3 "Unbekannte Entscheidung"

echo "== Pruef-Gate (Exit 2 bis 5, 3)"
for code in 2 3 4 5; do
  reset
  with_current
  export FAKE_ATTEST_FAIL_REF="${new_nginx}" FAKE_ATTEST_EXIT="${code}"
  deploy "Pruef-Gate Exit ${code} wird weitergegeben" "${code}" "Pruef-Gate abgelehnt: ${new_nginx}"
  hasnt "Pruef-Gate ${code}: kein Pull" "docker pull"
done
reset
with_current
export FAKE_ATTEST_FAIL_REF="${new_lego}" FAKE_ATTEST_EXIT=1
deploy "Pruef-Gate unerwarteter Exit" 3 "endete unerwartet"

echo "== Pull (Exit 8)"
reset
with_current
export FAKE_PULL_EXIT=1
deploy "Pull scheitert" 8 "Pull gescheitert"
hasnt "Pull: kein compose" "docker compose"
reset
with_current
export FAKE_INSPECT_OUT="${prefix}/identity-service@sha256:$(hex 9 64)"
deploy "Digest nach Pull weicht ab" 8 "Digest nach dem Pull weicht ab"
hasnt "Digest: kein compose" "docker compose"

echo "== Rueckweg (Exit 9, 10)"
reset
with_current
export FAKE_BAD_API="${new_api}"
deploy "Health rot, Rueckweg gruen" 9 "Rueckweg auf ${commit_a} erfolgreich"
current_is "Rueckweg: current bleibt alt" "releases/${commit_a}"
state_run_is "Rueckweg: Zustand bleibt alt" "${run_a}"
has "Rueckweg: compose up mit alten Images" "API_IMAGE=${old_api} NGINX_IMAGE=${old_nginx} LEGO_IMAGE=${old_lego}"
has "Rueckweg: compose mit altem Release-Ordner" "--project-directory ${sd}/releases/${commit_a}"
ping_is "Rueckweg: fail-Ping mit Code" "${ping_url}/fail" "deploy-staging exit 9"

reset
with_current
export FAKE_COMPOSE_FAIL_API="${new_api}"
deploy "compose up scheitert, Rueckweg gruen" 9 "compose up fuer ${commit_b} gescheitert"
current_is "compose rot: current bleibt alt" "releases/${commit_a}"

reset
with_current
export FAKE_BAD_API="${new_api} ${old_api}"
deploy "Health rot, Rueckweg ungesund" 10 "Rueckweg ungesund"
state_run_is "Rueckweg ungesund: Zustand bleibt alt" "${run_a}"

reset
with_current
export FAKE_BAD_API="${new_api}" FAKE_COMPOSE_FAIL_API="${old_api}"
deploy "Health rot, Rueckweg compose rot" 10 "Rueckweg (compose up) gescheitert"

reset
export FAKE_BAD_API="${new_api}"
deploy "first, Health rot: kein Rueckweg" 10 "kein Rueckweg moeglich"
current_is "first rot: kein current" "-"
if [ ! -e "${sd}/state" ]; then ok "first rot: kein Zustand"; else bad "first rot: Zustand geschrieben"; fi

reset
with_current
printf '{ "images": { "api": "%s" } }\n' "${old_api}" >"${sd}/releases/${commit_a}/deploy/staging.json"
export FAKE_BAD_API="${new_api}"
deploy "alte Freigabe unlesbar: kein Rueckweg" 10 "kein Rueckweg moeglich"

reset
with_current
. "${work}/write-json" "${sd}/releases/${commit_a}/deploy/staging.json" \
  "ghcrXio/xxxcoder999xxx/identity-service@sha256:$(hex a 64)" "${old_nginx}" "${old_lego}"
export FAKE_BAD_API="${new_api}"
deploy "alte Freigabe mit fremdem Host: kein Rueckweg" 10 "kein Rueckweg moeglich"

# Absturz nach dem Umstellen von current, vor dem Zustand: current zeigt schon
# auf den neuen Commit, der Zustand ist alt. Der naechste Lauf rollt denselben
# Commit erneut aus; ein "Rueckweg" auf ihn waere keiner.
crashed() {
  with_current
  mkdir -p "${sd}/releases/${commit_b}/docker/nginx"
  cp "${sd}/releases/${commit_a}/docker/nginx/Dockerfile" "${sd}/releases/${commit_b}/docker/nginx/"
  rm -f "${sd}/current"
  ln -s "releases/${commit_b}" "${sd}/current"
}
reset
crashed
deploy "nach Absturz: derselbe Commit erneut" 0 "Ausgerollt: run ${run_b}"
state_run_is "nach Absturz: Zustand nachgezogen" "${run_b}"
reset
crashed
export FAKE_BAD_API="${new_api}"
deploy "nach Absturz, Health rot: kein Rueckweg auf sich selbst" 10 "kein Rueckweg moeglich"
count "nach Absturz: nur ein compose up" "docker compose" 1

echo "== current und Zustand (Exit 11)"
reset
mkdir "${sd}/current"
deploy "current nicht umstellbar" 11 "current nicht umgestellt"
if [ ! -e "${sd}/state" ]; then ok "current rot: kein Zustand"; else bad "current rot: Zustand geschrieben"; fi
if [ -z "$(find "${sd}" -maxdepth 1 -name '.current.*')" ]; then ok "current rot: kein temporaerer Link"; else bad "current rot: temporaerer Link uebrig"; fi

reset
with_current
mkdir "${sd}/state.dir" && rm -f "${sd}/state" && mv "${sd}/state.dir" "${sd}/state"
deploy "Zustand nicht schreibbar" 11 "Zustand nicht geschrieben"
current_is "Zustand rot: current schon neu (naechster Lauf wiederholt)" "releases/${commit_b}"

# =============================================================================
echo
echo "Ergebnis: ${failures} Abweichung(en), ${skipped} uebersprungen"
[ "${failures}" -eq 0 ] || exit 3
