#!/usr/bin/env bash
# =============================================================================
# Faelle fuer scripts/renew-edge-certificate.sh (Erneuerung des Zertifikats
# von nginx, E-5-76) mit Ersatz fuer docker, curl, flock und sleep.
#
# Aufruf:  bash scripts/test-renew-edge-certificate.sh
#
# Warum ein Ersatz: Das Skript laeuft echt nur auf dem Server, und eine
# Erneuerung ist nur alle paar Wochen faellig. Ein Fehler zeigte sich sonst
# erst dann. Jeder Fall verlangt Exit-Code UND Grund (E-5-114).
#
# Braucht symbolische Links (current). Fehlen sie (Git Bash auf NTFS legt
# Kopien an), werden die Faelle uebersprungen; in der CI (CI=true) ist das
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
for f in renew-edge-certificate.sh lib/staging-runtime.sh lib/registry-only.sh; do
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

ln -s "${work}" "${work}/linkprobe" 2>/dev/null || true
if [ ! -L "${work}/linkprobe" ]; then
  echo "SKIP alle Faelle (Dateisystem ohne symbolische Links)"
  if [ "${CI:-}" = "true" ]; then fail 3 "In der CI muessen die Faelle laufen."; fi
  exit 0
fi
rm -f "${work}/linkprobe"

hex() { printf "$1%.0s" $(seq 1 "$2"); }
prefix="ghcr.io/xxxcoder999xxx"
commit_a="$(hex a 40)"
api_ref="${prefix}/identity-service@sha256:$(hex 1 64)"
nginx_ref="${prefix}/identity-service-nginx@sha256:$(hex 2 64)"
lego_ref="${prefix}/identity-service-lego@sha256:$(hex 3 64)"
nginx_id="$(hex 4 64)"
nginx_id2="$(hex 5 64)"
lego_left="$(hex 6 64)"
ping_url="https://hc-ping.example/edge-123"

inst="${work}/inst"
mkdir -p "${inst}/lib" "${work}/bin"
cp "${here}/renew-edge-certificate.sh" "${inst}/"
cp "${here}/lib/staging-runtime.sh" "${here}/lib/registry-only.sh" "${inst}/lib/"
export FAKE_LOG="${work}/calls.log"
export FAKE_LEFT="${work}/lego-left"

cat >"${work}/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $* | API_IMAGE=${API_IMAGE:-} NGINX_IMAGE=${NGINX_IMAGE:-} LEGO_IMAGE=${LEGO_IMAGE:-}" >>"${FAKE_LOG}"
case "$1" in
  info)
    [ "${FAKE_INFO_EXIT:-0}" = "0" ] || exit "${FAKE_INFO_EXIT}"
    printf '%s\n' "${FAKE_SECURITY:-[name=seccomp,profile=builtin name=rootless name=cgroupns]}"
    exit 0 ;;
  ps)
    [ "${FAKE_PS_EXIT:-0}" = "0" ] || exit "${FAKE_PS_EXIT}"
    case "$*" in
      *com.docker.compose.service=nginx*) [ -z "${FAKE_NGINX_IDS:-}" ] || printf '%s\n' ${FAKE_NGINX_IDS} ;;
      *com.docker.compose.service=lego*)
        [ -z "${FAKE_PS_LEGO_EXIT:-}" ] || exit "${FAKE_PS_LEGO_EXIT}"
        cat "${FAKE_LEFT}" 2>/dev/null || true ;;
    esac
    exit 0 ;;
  rm)
    [ "${FAKE_RM_KEEP:-}" = "yes" ] || rm -f "${FAKE_LEFT}"
    exit 0 ;;
  kill) exit "${FAKE_KILL_EXIT:-0}" ;;
  compose)
    for a in "$@"; do
      if [ "${a}" = "run" ]; then
        [ -z "${FAKE_LEGO_LEAVE:-}" ] || printf '%s\n' "${FAKE_LEGO_LEAVE}" >>"${FAKE_LEFT}"
        exit "${FAKE_LEGO_EXIT:-0}"
      fi
    done ;;
esac
echo "unerwarteter Aufruf: $*" >&2
exit 99
EOF

cat >"${work}/bin/curl" <<'EOF'
#!/usr/bin/env bash
ping="no"
data=""
args="$*"
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
  exit 0
fi
echo "curl ${args}" >>"${FAKE_LOG}"
exit "${FAKE_HEALTH_EXIT:-0}"
EOF

cat >"${work}/bin/openssl" <<'EOF'
#!/usr/bin/env bash
echo "openssl $*" >>"${FAKE_LOG}"
case "$1" in
  s_client)
    [ "${FAKE_SCLIENT_EXIT:-0}" = "0" ] || exit "${FAKE_SCLIENT_EXIT}"
    echo "-----BEGIN CERTIFICATE-----"
    exit 0 ;;
  x509)
    cat >/dev/null
    exit "${FAKE_CHECKEND_EXIT:-0}" ;;
esac
exit 99
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
chmod +x "${work}/bin/"* "${inst}/"*.sh

sd="${work}/state-dir"
rel="${sd}/releases/${commit_a}"
reset() {
  rm -rf -- "${sd}" "${work}/cred" "${work}/site" "${FAKE_LOG}" "${FAKE_LEFT}"
  mkdir -p "${rel}/deploy" "${work}/cred" "${work}/site/ca" "${work}/site/api-tls"
  touch "${rel}/compose.yaml" "${rel}/compose.staging.yaml"
  printf '{\n  "schema": 1,\n  "environment": "staging",\n  "images": {\n    "api": "%s",\n    "nginx": "%s",\n    "lego": "%s"\n  }\n}\n' \
    "${api_ref}" "${nginx_ref}" "${lego_ref}" >"${rel}/deploy/staging.json"
  ln -s "releases/${commit_a}" "${sd}/current"
  printf '%s\n' "${ping_url}" >"${work}/cred/ping-url"
  printf 'server_name staging.example.test;\n' >"${work}/site/server_name.conf"
  : >"${FAKE_LOG}"
  export CREDENTIALS_DIRECTORY="${work}/cred"
  export STAGING_SERVER_NAME_FILE="${work}/site/server_name.conf"
  export STAGING_CA_DIR="${work}/site/ca"
  export STAGING_API_CERT_DIR="${work}/site/api-tls"
  export FAKE_NGINX_IDS="${nginx_id}"
  unset FAKE_INFO_EXIT FAKE_SECURITY FAKE_PS_EXIT FAKE_PS_LEGO_EXIT FAKE_RM_KEEP FAKE_KILL_EXIT \
    FAKE_LEGO_EXIT FAKE_LEGO_LEAVE FAKE_HEALTH_EXIT FAKE_FLOCK_EXIT FAKE_SCLIENT_EXIT FAKE_CHECKEND_EXIT
}

# renew LABEL CODE GRUND [Parameter statt STATE_DIR]
renew() {
  local label="$1" code="$2" reason="$3" got=0 all
  shift 3
  local args=("${sd}")
  [ "$#" -eq 0 ] || args=("$@")
  PATH="${work}/bin:${PATH}" bash "${inst}/renew-edge-certificate.sh" "${args[@]}" \
    >"${work}/out" 2>"${work}/err" || got=$?
  all="$(cat "${work}/out" "${work}/err")"
  if [ "${got}" -eq "${code}" ] && [[ "${all}" == *"${reason}"* ]]; then
    ok "${label}"
  else
    bad "${label}: erwartet Exit ${code} mit '${reason}', erhalten Exit ${got}"
    tail -n 3 "${work}/err" | sed 's/^/  stderr: /'
  fi
  if grep -qF -- "${ping_url}" "${work}/out" "${work}/err"; then
    bad "${label}: Ping-URL in der Ausgabe"
  fi
}
has() { if grep -qF -- "$2" "${FAKE_LOG}"; then ok "$1"; else bad "$1: '$2' nicht aufgerufen"; fi; }
hasnt() { if grep -qF -- "$2" "${FAKE_LOG}"; then bad "$1: '$2' aufgerufen"; else ok "$1"; fi; }
ping_is() {
  local n
  n="$(grep -c '^ping ' "${FAKE_LOG}" || true)"
  if [ "${n}" = "1" ] && grep -qF -- "ping $2 | $3" "${FAKE_LOG}"; then ok "$1"; else bad "$1: erwartet ein Ping '$2 | $3'"; grep '^ping ' "${FAKE_LOG}" | sed 's/^/  /'; fi
}
lego_cmd="--profile acme run --rm -T --pull never lego run --path /data --accept-tos --http --http.webroot /webroot --cert.name edge --domains staging.example.test"

# =============================================================================
echo "== Erfolg"
reset
renew "geprueft, neu geladen, gesund, Zertifikat gueltig" 0 "noch mindestens 14 Tage gueltig"
has "lego ueber den Webroot, Name edge, Domain vom Server" "${lego_cmd} |"
has "Compose aus current mit festem Projektnamen" "compose -p identity-service-staging --project-directory ${rel} -f ${rel}/compose.yaml -f ${rel}/compose.staging.yaml"
has "Digests aus current/deploy/staging.json" "API_IMAGE=${api_ref} NGINX_IMAGE=${nginx_ref} LEGO_IMAGE=${lego_ref}"
hasnt "ohne Zwang kein --renew-force" "--renew-force"
hasnt "kein Port (Webroot statt Standalone)" "--publish"
hasnt "keine E-Mail (E-5-66)" "--email"
hasnt "kein Token, kein Login" "docker login"
hasnt "kein Pull" "docker pull"
has "nginx per HUP an genau diesen Container" "docker kill -s HUP ${nginx_id}"
has "nginx ohne Einmal-Container gesucht" "--filter label=com.docker.compose.service=nginx --filter label=com.docker.compose.oneoff=False"
has "Sperre wartend mit Frist (= Timeout des Deploys)" "flock -w 2700 9"
has "ausgeliefertes Zertifikat ueber SNI an die eigene Adresse" "openssl s_client -connect 127.0.0.1:443 -servername staging.example.test"
has "Zertifikat muss noch 14 Tage gelten" "openssl x509 -noout -checkend 1209600"
hasnt "ohne Reste: nichts entfernt" "docker rm"
has "Health ueber nginx an die eigene Adresse" "--resolve staging.example.test:443:127.0.0.1 https://staging.example.test/health"
ping_is "ok-Ping" "${ping_url}" "renew-edge-certificate exit 0"
order="$(grep -oE '^(docker info|flock|docker ps|docker compose|docker kill|curl|openssl s_client)' "${FAKE_LOG}" | uniq | tr '\n' ',' || true)"
if [ "${order}" = "docker info,flock,docker ps,docker compose,docker ps,docker kill,curl,openssl s_client," ]; then
  ok "Reihenfolge: rootless, Sperre, Suche, lego, Aufraeumen, Neuladen, Health, Zertifikat"
else
  bad "Reihenfolge ${order}"
fi

reset
renew "von Hand mit --force" 0 "nginx neu geladen" "${sd}" "--force"
has "--force wird zu --renew-force" "${lego_cmd} --renew-force |"

echo "== Voraussetzungen (Exit 2)"
reset
renew "zweiter Parameter nicht --force" 2 "nur --force sein" "${sd}" "--forcex"
hasnt "falscher Parameter: kein lego" "docker compose"
reset
renew "drei Parameter" 2 "Erwartet: STATE_DIR [--force]" "${sd}" "--force" "x"
ping_is "Parameter: fail-Ping mit Grund" "${ping_url}/fail" "renew-edge-certificate exit 2: Erwartet"
reset
renew "relativer Pfad" 2 "Pfad muss absolut sein" "state"
reset
unset STAGING_CA_DIR
renew "ohne STAGING_CA_DIR" 2 "STAGING_CA_DIR fehlt"
reset
printf 'server_name a; include /etc/passwd;\n' >"${work}/site/server_name.conf"
renew "server_name mit Zusatz" 2 "nicht genau 'server_name <name>;'"
reset
export FAKE_SECURITY="[name=seccomp,profile=builtin name=cgroupns]"
renew "Docker nicht rootless" 2 "Docker laeuft nicht rootless"
hasnt "nicht rootless: keine Sperre" "flock"
reset
rm -f "${work}/cred/ping-url"
renew "ohne Ping-URL: Lauf geht, kein Ping" 0 "kein Ping gesendet"
hasnt "ohne Ping-URL: kein Ping" "ping "

echo "== Sperre (Exit 6)"
reset
export FAKE_FLOCK_EXIT=1
renew "Sperre nicht rechtzeitig" 6 "Sperre nach 2700 s nicht erhalten"
hasnt "Sperre rot: kein lego" "docker compose"

echo "== current (Exit 3)"
reset
rm -f "${sd}/current"
renew "kein current (vor dem ersten Deploy)" 3 "current fehlt oder ist ungueltig"
reset
rm -f "${sd}/current"
ln -s "${rel}" "${sd}/current"
renew "current absolut" 3 "current fehlt oder ist ungueltig"
reset
rm -f "${rel}/compose.staging.yaml"
renew "Compose-Datei fehlt" 3 "Datei in current fehlt"
reset
sed -i '/"lego"/d' "${rel}/deploy/staging.json"
renew "lego-Referenz fehlt" 3 "lego-Referenz in current unlesbar"
hasnt "Referenz rot: kein lego" "docker compose"
reset
sed -i "s|${prefix}/identity-service-lego@|${prefix}/fremd@|" "${rel}/deploy/staging.json"
renew "lego-Referenz mit fremdem Paket" 3 "lego-Referenz in current unlesbar"

echo "== nginx und Einmal-Container (Exit 4, 7, 9)"
reset
export FAKE_NGINX_IDS=""
renew "kein nginx-Container" 4 "gefunden 0"
hasnt "kein nginx: kein lego" "docker compose"
reset
export FAKE_NGINX_IDS="${nginx_id} ${nginx_id2}"
renew "zwei nginx-Container" 4 "gefunden 2"
reset
export FAKE_PS_EXIT=1
renew "docker ps scheitert" 7 "docker ps gescheitert"
reset
printf '%s\n' "${lego_left}" >"${FAKE_LEFT}"
renew "Einmal-Container aus altem Lauf wird entfernt" 0 "noch mindestens 14 Tage gueltig"
has "alter Rest: Entfernen per ID" "docker rm -f ${lego_left}"
order="$(grep -oE '^(docker rm|docker compose)' "${FAKE_LOG}" | head -n 2 | tr '\n' ',' || true)"
if [ "${order}" = "docker rm,docker compose," ]; then ok "alter Rest: erst entfernt, dann lego"; else bad "alter Rest: Reihenfolge ${order}"; fi
reset
printf '%s\n' "${lego_left}" >"${FAKE_LEFT}"
export FAKE_RM_KEEP="yes"
renew "Einmal-Container vor dem Lauf nicht entfernbar" 9 "vor dem Lauf nicht entfernbar"
hasnt "Rest bleibt: kein lego" "docker compose"

echo "== lego (Exit 5, 9)"
reset
export FAKE_LEGO_EXIT=1
renew "lego scheitert" 5 "lego gescheitert (Exit 1)"
hasnt "lego rot: nginx nicht neu geladen" "docker kill"
ping_is "lego rot: fail-Ping mit Code" "${ping_url}/fail" "renew-edge-certificate exit 5"
reset
export FAKE_LEGO_EXIT=124 FAKE_LEGO_LEAVE="${lego_left}"
renew "lego Timeout hinterlaesst Container, wird entfernt" 5 "lego gescheitert (Exit 124)"
has "Abbruch: Entfernen per ID" "docker rm -f ${lego_left}"
reset
export FAKE_LEGO_LEAVE="${lego_left}" FAKE_RM_KEEP="yes"
renew "Einmal-Container bleibt nach dem Lauf" 9 "nach dem Lauf nicht entfernt"
hasnt "Container bleibt: nginx nicht neu geladen" "docker kill"

echo "== Neuladen und Health (Exit 8, 10)"
reset
export FAKE_KILL_EXIT=1
renew "HUP scheitert" 8 "nginx nicht neu geladen"
hasnt "HUP rot: keine Health" "curl "
reset
export FAKE_HEALTH_EXIT=22
renew "Health nach dem Neuladen rot" 10 "Health nach dem Neuladen rot"
hasnt "Health rot: keine Zertifikatspruefung" "openssl"

echo "== Ausgeliefertes Zertifikat (Exit 11)"
reset
export FAKE_CHECKEND_EXIT=1
renew "Zertifikat gilt keine 14 Tage mehr (Neuladen still gescheitert)" 11 "gilt keine 14 Tage mehr"
ping_is "Zertifikat alt: fail-Ping mit Code" "${ping_url}/fail" "renew-edge-certificate exit 11"
reset
export FAKE_SCLIENT_EXIT=1
renew "Zertifikat nicht lesbar" 11 "nicht lesbar"

# =============================================================================
echo
echo "Ergebnis: ${failures} Abweichung(en)"
[ "${failures}" -eq 0 ] || exit 3
