#!/usr/bin/env bash
# =============================================================================
# Legt die interne CA fuer Staging an (nginx -> API, E-5-92 bis E-5-98).
#
# Aufruf:  sudo /usr/local/sbin/new-internal-ca.sh SCHLUESSEL_ORDNER CA_ORDNER
#          SCHLUESSEL_ORDNER: nimmt internal-ca.key auf (root:root, 0700),
#                             liegt ausserhalb aller Compose-Mounts (E-5-93)
#          CA_ORDNER:         nimmt internal-ca.crt auf (0644), wird nginx
#                             als STAGING_CA_DIR eingebunden; muss existieren
#          Beide Pfade absolut, ohne Standardwerte: Das Skript schreibt nie an
#          einen Ort, den niemand gewaehlt hat.
#
# NUR VON HAND (E-5-94): Kein Timer und kein Deploy ruft dieses Skript auf.
# Liegt schon eine CA vor, bricht es ab, statt sie zu ersetzen - eine neue CA
# wuerde jedes ausgestellte API-Zertifikat ungueltig machen. Die Ausstellung
# uebernimmt issue-api-certificate.sh.
#
# Ablageort auf dem Server: /usr/local/sbin, root:root, 0755. Root fuehrt nur
# Dateien aus, die nur root aendern kann; eine Kopie im Ordner von deploy
# oder in einem Git-Checkout waere ein Weg zu root.
#
# Alles entsteht in einem temporaeren Ordner und wird erst nach bestandener
# Selbstpruefung an den Zielort verschoben: Ein Abbruch hinterlaesst keine
# halbe CA, die den naechsten Versuch mit Exit 3 blockieren wuerde.
#
# Die Konfiguration wird mitgeliefert (-config), nicht aus /usr/lib/ssl
# gelesen: Die Erweiterungen haengen so nicht von der openssl.cnf des
# Systems ab.
#
# Exit-Codes:
#   0  CA erzeugt und selbst geprueft
#   2  Aufruf falsch (Argumente, Pfade, CA_ORDNER fehlt)
#   3  CA existiert bereits; nichts veraendert
#   4  nicht als root gestartet
#   5  Selbstpruefung gescheitert; nichts am Zielort abgelegt
#   6  SCHLUESSEL_ORDNER existiert, aber nicht root:root 0700; nichts veraendert
#   sonst: Fehler von openssl oder Dateisystem (set -e)
#
# Das Skript gibt nie den Inhalt eines Schluessels aus.
# =============================================================================
set -euo pipefail

# Jede Datei entsteht sofort als 0600 bzw. 0700: Der Schluessel ist auch
# zwischen Erzeugen und chmod fuer niemanden sonst lesbar.
umask 077

usage() {
  echo "Aufruf: $0 SCHLUESSEL_ORDNER CA_ORDNER (beide absolut)" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
key_dir="$1"
cert_dir="$2"

case "${key_dir}" in /*) ;; *) usage ;; esac
case "${cert_dir}" in /*) ;; *) usage ;; esac

# Gleicher Ordner hiesse: Der CA-Schluessel laege im Mount von nginx.
if [ "$(realpath -m -- "${key_dir}")" = "$(realpath -m -- "${cert_dir}")" ]; then
  echo "Abbruch: SCHLUESSEL_ORDNER und CA_ORDNER muessen verschieden sein." >&2
  exit 2
fi

key="${key_dir}/internal-ca.key"
crt="${cert_dir}/internal-ca.crt"

# Vor der root-Pruefung: Die Abbrueche lassen sich so ohne root testen.
if [ -e "${key}" ] || [ -e "${crt}" ]; then
  echo "Abbruch: Es existiert bereits eine CA ('${key}' oder '${crt}'). Nichts veraendert." >&2
  exit 3
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "Abbruch: Nur root darf die CA anlegen (Schluessel gehoert root:root)." >&2
  exit 4
fi

if [ ! -d "${cert_dir}" ]; then
  echo "Abbruch: CA_ORDNER '${cert_dir}' existiert nicht." >&2
  exit 2
fi

# Ohne -p: Der uebergeordnete Ordner wird bewusst angelegt, nicht nebenbei.
# Ein vorhandener Ordner wird nicht still repariert: Falsche Rechte koennen
# heissen, dass jemand anderes ihn angelegt hat.
if [ -d "${key_dir}" ]; then
  if [ "$(stat -c '%u %g %a' -- "${key_dir}")" != "0 0 700" ]; then
    echo "Abbruch: '${key_dir}' gehoert nicht root oder hat nicht die Rechte 0700. Bitte pruefen, nichts veraendert." >&2
    exit 6
  fi
else
  mkdir -m 0700 -- "${key_dir}"
fi

# Im Schluessel-Ordner: gleiches Dateisystem, mv ist atomar.
tmp="$(mktemp -d -- "${key_dir}/.new-ca.XXXXXX")"
trap 'rm -rf -- "${tmp}"' EXIT

cat > "${tmp}/ca.cnf" <<'EOF'
[req]
prompt             = no
distinguished_name = dn
x509_extensions    = v3_ca

[dn]
CN = IdentityService Staging Internal CA

[v3_ca]
basicConstraints     = critical, CA:TRUE, pathlen:0
keyUsage             = critical, keyCertSign, cRLSign
nameConstraints      = critical, permitted;DNS:api
subjectKeyIdentifier = hash
EOF

openssl ecparam -name prime256v1 -genkey -noout -out "${tmp}/internal-ca.key"
openssl req -x509 -new -sha256 -days 365 \
  -config "${tmp}/ca.cnf" \
  -key "${tmp}/internal-ca.key" \
  -out "${tmp}/internal-ca.crt"

# --- Selbstpruefung: Steht im Zertifikat, was wir wollten? ---
check_failed() {
  echo "Abbruch: Selbstpruefung gescheitert: $1. Nichts am Zielort abgelegt." >&2
  exit 5
}

text="$(openssl x509 -in "${tmp}/internal-ca.crt" -noout -text)"
for expected in \
  "X509v3 Basic Constraints: critical" \
  "CA:TRUE, pathlen:0" \
  "X509v3 Key Usage: critical" \
  "Certificate Sign, CRL Sign" \
  "X509v3 Name Constraints: critical" \
  "DNS:api" \
  "ASN1 OID: prime256v1"; do
  grep -qF -- "${expected}" <<< "${text}" || check_failed "'${expected}' fehlt"
done

cmp -s \
  <(openssl pkey -in "${tmp}/internal-ca.key" -pubout) \
  <(openssl x509 -in "${tmp}/internal-ca.crt" -noout -pubkey) \
  || check_failed "Schluessel passt nicht zum Zertifikat"

openssl verify -CAfile "${tmp}/internal-ca.crt" "${tmp}/internal-ca.crt" > /dev/null \
  || check_failed "Zertifikat nicht selbst signiert"

# Gueltig in 364 Tagen, nicht mehr in 366: Die Laufzeit ist wirklich 365 Tage.
openssl x509 -in "${tmp}/internal-ca.crt" -noout -checkend $((364 * 86400)) > /dev/null \
  || check_failed "Laufzeit kuerzer als 364 Tage"
if openssl x509 -in "${tmp}/internal-ca.crt" -noout -checkend $((366 * 86400)) > /dev/null; then
  check_failed "Laufzeit laenger als 365 Tage"
fi

# --- Ablegen: Schluessel 0400 root:root, Zertifikat 0644 root:root ---
chmod 0400 -- "${tmp}/internal-ca.key"
mv -- "${tmp}/internal-ca.key" "${key}"
install -m 0644 -o root -g root -- "${tmp}/internal-ca.crt" "${cert_dir}/.internal-ca.crt.new"
mv -- "${cert_dir}/.internal-ca.crt.new" "${crt}"

echo "CA erzeugt. Schluessel: '${key}', Zertifikat: '${crt}'."
openssl x509 -in "${crt}" -noout -subject -enddate -fingerprint -sha256
echo "Erinnerung: CA-Wechsel rund zehn Monate vor dem Ablaufdatum planen (beide CAs eine Zeit lang vertrauen)."
