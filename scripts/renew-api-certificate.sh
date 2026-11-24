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
#   10                 ok-Ping; steht ein Neustart aus (.restart-pending),
#                      zuerst nachholen, scheitert er wieder: /fail
#   0                  API neu starten, dann ok-Ping; scheitert der Neustart:
#                      Merker .restart-pending anlegen, Ping auf /fail
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

# Neustart der API nach einer Erneuerung (E-5-97) ueber eine eigene Unit mit
# User=deploy (E-5-120, E-5-178). systemctl start wartet, bis der oneshot
# fertig ist, und liefert ungleich 0, wenn er scheitert: kein API-Container,
# Neustart oder Health rot, Sperre nicht erhalten. Die Sandbox dieser Unit
# waechst dafuer nicht (gemessen in Sitzung 32).
restart_api() {
  systemctl --no-ask-password start identity-service-api-restart.service
}

# Ausstehender Neustart (Sitzung 33): Scheitert der Neustart nach einer
# Erneuerung, liefert der naechste Lauf Exit 10 ("noch gueltig") - ohne
# Merker gaebe es keinen zweiten Versuch, der ok-Ping loeschte den Alarm,
# und die API zeigte das alte Zertifikat bis zu dessen Ablauf. Der Merker
# liegt im Ordner der API-Zertifikate, dem einzigen, in den diese Unit
# schreiben darf (E-5-102, E-5-178); die API liest nur ihre festen Dateien.
# Ordner = drittes Argument, wie es auch issue-api-certificate.sh bekommt.
api_dir="${3-}"
pending=""
case "${api_dir}" in
  /*) [ -d "${api_dir}" ] && pending="${api_dir}/.restart-pending" ;;
esac

mark_pending() {
  [ -n "${pending}" ] && (umask 077 && : >"${pending}")
}

"${issue}" "$@"
rc=$?

problem=""
case "${rc}" in
  10)
    if [ -n "${pending}" ] && [ -e "${pending}" ]; then
      if restart_api; then
        rm -f -- "${pending}"
        log_info "Zertifikat noch gueltig, ausstehender API-Neustart nachgeholt"
      else
        problem="API-Neustart nach Erneuerung weiter ausstehend"
      fi
    else
      log_info "Zertifikat noch gueltig"
    fi
    ;;
  0)
    # Merker VOR dem Neustart: Bricht systemd die Unit waehrenddessen ab,
    # bleibt er stehen, und der naechste Lauf holt den Neustart nach.
    marked="no"
    if mark_pending; then marked="yes"; fi
    if restart_api; then
      [ -z "${pending}" ] || rm -f -- "${pending}"
      log_info "Zertifikat erneuert, API neu gestartet"
      [ "${marked}" = "yes" ] || problem="Zertifikat erneuert, API neu gestartet; Merker war nicht anlegbar"
    elif [ "${marked}" = "yes" ]; then
      problem="Zertifikat erneuert, API-Neustart gescheitert; wird beim naechsten Lauf wiederholt"
    else
      problem="Zertifikat erneuert, API-Neustart gescheitert; Merker nicht anlegbar, kein zweiter Versuch"
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
