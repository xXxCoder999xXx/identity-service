#!/usr/bin/env bash
# =============================================================================
# Faelle fuer scripts/renew-api-certificate.sh (Huelle des Zertifikats-Timers,
# E-5-97, E-5-101) mit Ersatz fuer issue-api-certificate.sh, systemctl,
# logger und curl.
#
# Aufruf:  bash scripts/test-renew-api-certificate.sh
#
# Warum: Die Huelle entscheidet, ob nach einer Erneuerung neu gestartet wird
# und ob ein gescheiterter Neustart beim naechsten Lauf nachgeholt wird
# (Merker .restart-pending, Sitzung 33). Echt laeuft sie nur einmal taeglich
# auf dem Server. Jeder Fall verlangt Exit-Code, Ping und Merker-Zustand.
#
# Der Pfad des Ausstellungs-Skripts ist im Einstieg fest (/usr/local/sbin).
# Der Test ersetzt in seiner Kopie genau diese eine Zeile; geprueft wird,
# dass sie vorhanden war.
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
[ -r "${here}/renew-api-certificate.sh" ] || fail 2 "Datei fehlt: ${here}/renew-api-certificate.sh"

work="$(mktemp -d)"
trap 'rm -rf -- "${work}"' EXIT

failures=0
ok() { echo "ok   $1"; }
bad() {
  echo "FEHLER $1"
  failures=$((failures + 1))
}

mkdir -p "${work}/bin" "${work}/inst"
export FAKE_LOG="${work}/calls.log"
line='issue="/usr/local/sbin/issue-api-certificate.sh"'
grep -qxF "${line}" "${here}/renew-api-certificate.sh" || fail 2 "Zeile mit dem Pfad des Ausstellungs-Skripts nicht gefunden."
sed "s|^issue=\"/usr/local/sbin/issue-api-certificate.sh\"\$|issue=\"${work}/bin/issue-api-certificate.sh\"|" \
  "${here}/renew-api-certificate.sh" >"${work}/inst/renew-api-certificate.sh"

cat >"${work}/bin/issue-api-certificate.sh" <<'EOF'
#!/usr/bin/env bash
echo "issue $*" >>"${FAKE_LOG}"
exit "${FAKE_ISSUE_EXIT:-10}"
EOF
cat >"${work}/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"${FAKE_LOG}"
exit "${FAKE_RESTART_EXIT:-0}"
EOF
cat >"${work}/bin/logger" <<'EOF'
#!/usr/bin/env bash
echo "logger ${*: -1}" >>"${FAKE_LOG}"
EOF
cat >"${work}/bin/curl" <<'EOF'
#!/usr/bin/env bash
data=""
while [ "$#" -gt 0 ]; do
  case "$1" in --data-binary) data="$2"; shift ;; esac
  shift
done
config="$(cat)"
url="${config#url = \"}"
url="${url%\"}"
echo "ping ${url} | ${data}" >>"${FAKE_LOG}"
EOF
chmod +x "${work}/bin/"*

api="${work}/api-tls"
url="https://hc-ping.example/cert-123"
reset() {
  rm -rf -- "${api}" "${work}/cred"
  mkdir -p "${api}" "${work}/cred"
  printf '%s' "${url}" >"${work}/cred/ping-url"
  : >"${FAKE_LOG}"
  export CREDENTIALS_DIRECTORY="${work}/cred"
  unset FAKE_ISSUE_EXIT FAKE_RESTART_EXIT
}

# renew LABEL CODE PING-ZIEL MERKER(yes|no) [Text im Ping]
renew() {
  local label="$1" code="$2" target="$3" marker="$4" text="${5-}" got=0 have="no"
  PATH="${work}/bin:${PATH}" bash "${work}/inst/renew-api-certificate.sh" \
    "${work}/ca-private" "${work}/ca" "${api}" 167189 >/dev/null 2>&1 || got=$?
  [ ! -e "${api}/.restart-pending" ] || have="yes"
  if [ "${got}" -eq "${code}" ] && grep -F -- "ping ${target} | " "${FAKE_LOG}" | grep -qF -- "${text}" \
    && [ "$(grep -c '^ping ' "${FAKE_LOG}")" = "1" ] && [ "${have}" = "${marker}" ]; then
    ok "${label}"
  else
    bad "${label}: erwartet Exit ${code}, Ping ${target} '${text}', Merker ${marker}; erhalten Exit ${got}, Merker ${have}"
    sed 's/^/  /' "${FAKE_LOG}"
  fi
}
restarts() {
  local n
  n="$(grep -c '^systemctl ' "${FAKE_LOG}" || true)"
  if [ "${n}" = "$2" ]; then ok "$1"; else bad "$1: ${n} Neustarts statt $2"; fi
}

echo "== Normalfaelle"
reset
renew "noch gueltig: ok-Ping, kein Neustart" 0 "${url}" no
restarts "noch gueltig: kein Neustart" 0
reset
export FAKE_ISSUE_EXIT=0
renew "erneuert, Neustart gruen: ok-Ping" 0 "${url}" no
restarts "erneuert: genau ein Neustart" 1
if grep -qF "systemctl --no-ask-password start identity-service-api-restart.service" "${FAKE_LOG}"; then
  ok "Neustart ueber die Restart-Unit"
else
  bad "Neustart nicht ueber die Restart-Unit"
fi
if grep -qF "issue ${work}/ca-private ${work}/ca ${api} 167189" "${FAKE_LOG}"; then
  ok "Argumente unveraendert an das Ausstellungs-Skript"
else
  bad "Argumente veraendert"
fi
reset
export FAKE_ISSUE_EXIT=7
renew "Ausstellung rot: /fail mit Code" 1 "${url}/fail" no "issue-api-certificate exit 7"
restarts "Ausstellung rot: kein Neustart" 0

echo "== Ausstehender Neustart"
reset
export FAKE_ISSUE_EXIT=0 FAKE_RESTART_EXIT=1
renew "erneuert, Neustart rot: Merker und /fail" 1 "${url}/fail" yes "wird beim naechsten Lauf wiederholt"
# Naechster Tag: Zertifikat gilt (10), Neustart wieder rot.
export FAKE_ISSUE_EXIT=10 FAKE_RESTART_EXIT=1
: >"${FAKE_LOG}"
renew "naechster Lauf, Neustart wieder rot: weiter /fail" 1 "${url}/fail" yes "weiter ausstehend"
restarts "naechster Lauf: Neustart versucht" 1
# Dritter Tag: Neustart gruen.
export FAKE_RESTART_EXIT=0
: >"${FAKE_LOG}"
renew "naechster Lauf, Neustart gruen: Merker weg, ok-Ping" 0 "${url}" no
# Vierter Tag: nichts mehr ausstehend.
: >"${FAKE_LOG}"
renew "danach: kein Neustart mehr" 0 "${url}" no
restarts "danach: kein Neustart" 0

echo "== Merker nicht anlegbar"
reset
rmdir "${api}"
export FAKE_ISSUE_EXIT=0 FAKE_RESTART_EXIT=1
renew "Ordner fehlt, Neustart rot: /fail ohne zweiten Versuch" 1 "${url}/fail" no "kein zweiter Versuch"
reset
rmdir "${api}"
export FAKE_ISSUE_EXIT=0
renew "Ordner fehlt, Neustart gruen: /fail, Merker fehlte" 1 "${url}/fail" no "Merker war nicht anlegbar"

echo
echo "Ergebnis: ${failures} Abweichung(en)"
[ "${failures}" -eq 0 ] || exit 3
