#!/usr/bin/env bash
# =============================================================================
# Stellt das Zertifikat der API fuer Staging aus oder erneuert es
# (nginx -> API, E-5-94 bis E-5-98). Gegenstueck zu new-internal-ca.sh.
#
# Aufruf:  sudo /usr/local/sbin/issue-api-certificate.sh \
#            SCHLUESSEL_ORDNER CA_ORDNER API_ORDNER API_HOST_UID
#          SCHLUESSEL_ORDNER: enthaelt internal-ca.key (von new-internal-ca.sh)
#          CA_ORDNER:         enthaelt internal-ca.crt (STAGING_CA_DIR)
#          API_ORDNER:        nimmt api.key und api.crt auf
#                             (STAGING_API_CERT_DIR); root gehoert, fuer
#                             Gruppe und andere nicht beschreibbar
#          API_HOST_UID:      UID der API auf dem Host unter rootless Docker
#                             (Container-UID 1654 -> SUBUID_START + 1653);
#                             gemessener Wert, deshalb Argument
#          Alles absolut bzw. numerisch, ohne Standardwerte.
#
# Aufgerufen taeglich vom systemd-Timer (E-5-97). Erzeugt NIE eine CA: Fehlt
# sie, bricht das Skript ab (E-5-94). Ping an Healthchecks.io und Neustart der
# API uebernimmt die Unit, nicht dieses Skript: So bleibt es ohne Netz und
# ohne Docker testbar, und die Ping-URL steht nicht im Repository.
#
# Neu ausgestellt wird nur, wenn kein gueltiges Paar vorliegt, das Zertifikat
# in weniger als 30 Tagen ablaeuft, nicht von der aktuellen CA stammt oder
# nicht zum Schluessel passt. Jede Ausstellung erzeugt einen neuen Schluessel.
#
# Ablageort auf dem Server: /usr/local/sbin, root:root, 0755 (wie
# new-internal-ca.sh: root fuehrt nur aus, was nur root aendern kann).
#
# Exit-Codes:
#   0   neues Zertifikat ausgestellt und geprueft (Unit startet die API neu)
#   10  Zertifikat noch gueltig; nichts veraendert (fuer systemd ein Erfolg:
#       SuccessExitStatus=10)
#   2   Aufruf falsch (Argumente, Pfade, Ordner fehlt)
#   3   CA fehlt; nichts veraendert
#   4   nicht als root gestartet
#   5   Selbstpruefung gescheitert; nichts am Zielort abgelegt
#   6   API_ORDNER gehoert nicht root oder ist fuer andere beschreibbar
#   7   CA laeuft in weniger als 90 Tagen ab; CA-Wechsel faellig. Der Timer
#       scheitert, der Ping bleibt aus, Healthchecks.io alarmiert (A09).
#   sonst: Fehler von openssl oder Dateisystem (set -e)
#
# Das Skript gibt nie den Inhalt eines Schluessels aus.
# =============================================================================
set -euo pipefail

umask 077

usage() {
  echo "Aufruf: $0 SCHLUESSEL_ORDNER CA_ORDNER API_ORDNER API_HOST_UID (Ordner absolut)" >&2
  exit 2
}

[ "$#" -eq 4 ] || usage
key_dir="$1"
cert_dir="$2"
api_dir="$3"
api_uid="$4"

for dir in "${key_dir}" "${cert_dir}" "${api_dir}"; do
  case "${dir}" in /*) ;; *) usage ;; esac
done

# Nur Ziffern, nicht 0: Der Schluessel darf nie root gehoeren.
case "${api_uid}" in '' | *[!0-9]*) usage ;; esac
[ "${api_uid}" -ne 0 ] || usage

# Gleicher Ordner hiesse: Der CA-Schluessel laege im Mount der API.
if [ "$(realpath -m -- "${key_dir}")" = "$(realpath -m -- "${api_dir}")" ]; then
  echo "Abbruch: SCHLUESSEL_ORDNER und API_ORDNER muessen verschieden sein." >&2
  exit 2
fi

# Vor der CA-Pruefung: Ohne root ist der Schluessel-Ordner (0700) nicht
# lesbar, "CA fehlt" waere dann eine falsche Meldung.
if [ "$(id -u)" -ne 0 ]; then
  echo "Abbruch: Nur root darf das API-Zertifikat ausstellen." >&2
  exit 4
fi

ca_key="${key_dir}/internal-ca.key"
ca_crt="${cert_dir}/internal-ca.crt"
api_key="${api_dir}/api.key"
api_crt="${api_dir}/api.crt"

if [ ! -f "${ca_key}" ] || [ ! -f "${ca_crt}" ]; then
  echo "Abbruch: CA fehlt ('${ca_key}' oder '${ca_crt}'). Anlegen nur von Hand mit new-internal-ca.sh. Nichts veraendert." >&2
  exit 3
fi

if [ ! -d "${api_dir}" ]; then
  echo "Abbruch: API_ORDNER '${api_dir}' existiert nicht." >&2
  exit 2
fi

# Melden statt reparieren: Wer den Ordner beschreiben kann, kann Schluessel
# und Zertifikat austauschen.
read -r dir_owner dir_mode <<< "$(stat -c '%u %a' -- "${api_dir}")"
if [ "${dir_owner}" -ne 0 ] || [ $((8#${dir_mode} & 8#022)) -ne 0 ]; then
  echo "Abbruch: '${api_dir}' gehoert nicht root oder ist fuer Gruppe/andere beschreibbar (${dir_owner} ${dir_mode}). Nichts veraendert." >&2
  exit 6
fi

# Ein API-Zertifikat (90 Tage) soll nicht laenger leben als seine CA.
if ! openssl x509 -in "${ca_crt}" -noout -checkend $((90 * 86400)) > /dev/null; then
  echo "Abbruch: Die CA laeuft in weniger als 90 Tagen ab. CA-Wechsel faellig. Nichts veraendert." >&2
  openssl x509 -in "${ca_crt}" -noout -enddate >&2
  exit 7
fi

# --- Ist das vorhandene Paar noch brauchbar? ---
reason=""
if [ ! -f "${api_key}" ] || [ ! -f "${api_crt}" ]; then
  reason="kein Zertifikat vorhanden"
elif ! openssl x509 -in "${api_crt}" -noout -checkend $((30 * 86400)) > /dev/null; then
  reason="laeuft in weniger als 30 Tagen ab"
elif ! openssl verify -CAfile "${ca_crt}" -purpose sslserver -verify_hostname api "${api_crt}" > /dev/null 2>&1; then
  reason="nicht von der aktuellen CA oder nicht fuer 'api'"
elif ! cmp -s \
  <(openssl pkey -in "${api_key}" -pubout) \
  <(openssl x509 -in "${api_crt}" -noout -pubkey); then
  reason="Schluessel passt nicht zum Zertifikat"
fi

if [ -z "${reason}" ]; then
  echo "API-Zertifikat noch gueltig, nichts zu tun."
  openssl x509 -in "${api_crt}" -noout -enddate
  exit 10
fi
echo "Neu ausstellen: ${reason}."

# --- Ausstellen im temporaeren Ordner (gleiches Dateisystem, mv atomar) ---
tmp="$(mktemp -d -- "${api_dir}/.new-api.XXXXXX")"
trap 'rm -rf -- "${tmp}"' EXIT

cat > "${tmp}/api.cnf" <<'EOF'
[req]
prompt             = no
distinguished_name = dn

[dn]
CN = api

[v3_api]
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = serverAuth
subjectAltName         = DNS:api
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid
EOF

openssl ecparam -name prime256v1 -genkey -noout -out "${tmp}/api.key"
openssl req -new -config "${tmp}/api.cnf" -key "${tmp}/api.key" -out "${tmp}/api.csr"
# Ohne -CAserial: zufaellige Seriennummer, keine .srl-Datei im CA_ORDNER
# (der ist in nginx eingebunden).
openssl x509 -req -sha256 -days 90 \
  -in "${tmp}/api.csr" \
  -CA "${ca_crt}" \
  -CAkey "${ca_key}" \
  -extfile "${tmp}/api.cnf" \
  -extensions v3_api \
  -out "${tmp}/api.crt"

# --- Selbstpruefung ---
check_failed() {
  echo "Abbruch: Selbstpruefung gescheitert: $1. Nichts am Zielort abgelegt." >&2
  exit 5
}

# Kette, Zweck und Name; dabei greift auch nameConstraints der CA.
openssl verify -CAfile "${ca_crt}" -purpose sslserver -verify_hostname api "${tmp}/api.crt" > /dev/null \
  || check_failed "Kette, Zweck oder Name ungueltig"

cmp -s \
  <(openssl pkey -in "${tmp}/api.key" -pubout) \
  <(openssl x509 -in "${tmp}/api.crt" -noout -pubkey) \
  || check_failed "Schluessel passt nicht zum Zertifikat"

text="$(openssl x509 -in "${tmp}/api.crt" -noout -text)"
for expected in \
  "CA:FALSE" \
  "Digital Signature" \
  "TLS Web Server Authentication" \
  "ASN1 OID: prime256v1"; do
  grep -qF -- "${expected}" <<< "${text}" || check_failed "'${expected}' fehlt"
done

# Genau ein Name: keine weiteren SAN-Eintraege neben DNS:api.
san="$(openssl x509 -in "${tmp}/api.crt" -noout -ext subjectAltName | sed -n '2p' | tr -d ' ')"
[ "${san}" = "DNS:api" ] || check_failed "SAN ist '${san}' statt 'DNS:api'"

openssl x509 -in "${tmp}/api.crt" -noout -checkend $((89 * 86400)) > /dev/null \
  || check_failed "Laufzeit kuerzer als 89 Tage"
if openssl x509 -in "${tmp}/api.crt" -noout -checkend $((91 * 86400)) > /dev/null; then
  check_failed "Laufzeit laenger als 90 Tage"
fi

# --- Ablegen: Schluessel nur fuer die API (0400), Zertifikat lesbar (0444) ---
# Gruppe root statt der abgebildeten GID: Bei 0400 hat die Gruppe ohnehin
# kein Recht, und /etc/subgid muss so nicht stimmen.
chown "${api_uid}:0" -- "${tmp}/api.key"
chmod 0400 -- "${tmp}/api.key"
chown 0:0 -- "${tmp}/api.crt"
chmod 0444 -- "${tmp}/api.crt"

[ "$(stat -c '%u %a' -- "${tmp}/api.key")" = "${api_uid} 400" ] \
  || check_failed "Besitz oder Rechte von api.key"
[ "$(stat -c '%u %a' -- "${tmp}/api.crt")" = "0 444" ] \
  || check_failed "Besitz oder Rechte von api.crt"

mv -- "${tmp}/api.key" "${api_key}"
mv -- "${tmp}/api.crt" "${api_crt}"

echo "API-Zertifikat ausgestellt: '${api_crt}'."
openssl x509 -in "${api_crt}" -noout -enddate
