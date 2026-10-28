#!/usr/bin/env bash
# =============================================================================
# Huelle fuer den taeglichen Timer (E-5-97): ruft issue-api-certificate.sh
# auf, wertet den Exit-Code aus und meldet das Ergebnis an den
# Totmannschalter (ADR-013).
#
# Aufruf:  nur ueber identity-service-api-cert.service; die Argumente gehen
#          unveraendert an issue-api-certificate.sh.
#
# Warum eine Huelle: Fuer systemd sind 0 ("neu ausgestellt") und 10 ("nichts
# zu tun") beide Erfolg; nur nach 0 muss die API neu starten. Das
# Ausstellungs-Skript bleibt so ohne Netz und ohne Docker.
#
#   Exit des Skripts   Wirkung
#   10                 ok-Ping
#   0                  API neu starten, dann ok-Ping; scheitert der Neustart:
#                      Ping auf /fail
#   alles andere       Ping auf /fail mit dem Exit-Code
#
# Die Ping-URL kommt per LoadCredential und steht nie in einer Kommandozeile
# (curl -K -, E-5-55). Ohne lesbares Credential geht kein Ping raus; die
# Stille alarmiert nach Periode und Grace. Bei /fail mailt Healthchecks.io
# sofort.
#
# Exit 0 nur, wenn alles in Ordnung war und der Ping ankam; sonst 1, damit
# die Unit als failed erscheint.
#
# Ablageort auf dem Server: /usr/local/sbin, root:root, 0755.
# =============================================================================
set -u

tag="identity-service-api-cert"
issue="/usr/local/sbin/issue-api-certificate.sh"

log_info() { logger -p user.info -t "${tag}" "$1"; }
log_warn() { logger -p user.warning -t "${tag}" "$1"; }

ping_hc() {
  printf 'url = "%s"\n' "$1" \
    | curl -fsS -m 10 --retry 3 --retry-max-time 30 -o /dev/null -K - --data-binary "$2"
}

# Neustart der API nach einer Erneuerung. Auf Staging laeuft noch kein
# Stack: Projektname und Weg zu Docker von deploy legt erst der Pull-Deploy
# fest. Bis dahin meldet der Zweig einen Fehler, statt still nichts zu tun.
# Frist: erste Erneuerung am 27.12.2026.
restart_api() {
  return 1
}

"${issue}" "$@"
rc=$?

problem=""
case "${rc}" in
  10)
    log_info "Zertifikat noch gueltig"
    ;;
  0)
    if restart_api; then
      log_info "Zertifikat erneuert, API neu gestartet"
    else
      problem="Zertifikat erneuert, API-Neustart nicht eingerichtet oder gescheitert"
    fi
    ;;
  *)
    problem="issue-api-certificate exit ${rc}"
    ;;
esac
[ -z "${problem}" ] || log_warn "${problem}"

url=""
if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -r "${CREDENTIALS_DIRECTORY}/ping-url" ]; then
  url="$(cat -- "${CREDENTIALS_DIRECTORY}/ping-url")"
fi
if [ -z "${url}" ]; then
  log_warn "Ping-URL nicht lesbar, kein Ping gesendet"
  exit 1
fi

if [ -z "${problem}" ]; then
  ping_hc "${url}" "" && exit 0
  log_warn "Ping fehlgeschlagen"
  exit 1
fi
ping_hc "${url}/fail" "${problem}" || log_warn "Ping fehlgeschlagen"
exit 1
