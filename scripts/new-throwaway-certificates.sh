#!/usr/bin/env bash
# =============================================================================
# Erzeugt Wegwerf-Zertifikate fuer die Pipeline (nginx -t und Smoke-Test).
#
# Aufruf:  bash scripts/new-throwaway-certificates.sh [Zielordner]
#          Zielordner ist relativ zum aktuellen Verzeichnis, Standard: certs
#
# Warum ein Skript: CI und Veroeffentlichung (ADR-010) brauchen dieselben
# Zertifikate. Service-Name, SAN und proxy_ssl_name sind gekoppelt - sie
# sollen an EINER Stelle stehen, nicht in jedem Workflow.
#
# NICHT fuer den lokalen Rechner gedacht: Dort erzeugt
# New-LocalDevCertificates.ps1 die Zertifikate. Dieses Skript bricht ab, wenn
# im Zielordner schon eine CA liegt, statt sie zu ueberschreiben (fail closed).
# Unter Git Bash fuer Windows verfaelscht die Pfadumschreibung zudem die
# -subj-Angaben; das Skript ist fuer den Linux-Runner geschrieben.
#
# nginx und Kestrel oeffnen die konfigurierten Zertifikatsdateien; im
# Repository liegen bewusst keine. Die Dateien entstehen im Lauf, gelten einen
# Tag und verschwinden mit dem Runner - keine Secrets. ECDSA P-256 wie
# New-LocalDevCertificates.ps1.
# Das API-Zertifikat traegt den SAN "api": Weicht Service-Name, SAN oder
# proxy_ssl_name ab, wird der Smoke-Test rot.
# Das Skript gibt nie den Inhalt eines Schluessels aus.
# =============================================================================
set -euo pipefail

out="${1:-certs}"

if [ -e "${out}/ca/local-dev-ca.crt" ] || [ -e "${out}/ca/local-dev-ca.key" ]; then
  echo "Abbruch: In '${out}/ca' liegt bereits eine CA. Dieses Skript ueberschreibt keine bestehenden Zertifikate." >&2
  exit 1
fi

mkdir -p "${out}/ca" "${out}/edge" "${out}/api"

# --- CA: nur fuer diesen Lauf, signiert die beiden Server-Zertifikate ---
openssl ecparam -name prime256v1 -genkey -noout -out "${out}/ca/local-dev-ca.key"
openssl req -x509 -new -sha256 -days 1 \
  -key "${out}/ca/local-dev-ca.key" \
  -subj "/CN=ci-throwaway-ca" \
  -out "${out}/ca/local-dev-ca.crt"

# --- edge: nginx, vom Smoke-Test ueber localhost adressiert ---
openssl ecparam -name prime256v1 -genkey -noout -out "${out}/edge/edge.key"
openssl req -new \
  -key "${out}/edge/edge.key" \
  -subj "/CN=localhost" \
  -out "${out}/edge/edge.csr"
printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\n' > "${out}/edge/edge.ext"
openssl x509 -req -sha256 -days 1 \
  -in "${out}/edge/edge.csr" \
  -CA "${out}/ca/local-dev-ca.crt" \
  -CAkey "${out}/ca/local-dev-ca.key" \
  -CAcreateserial \
  -extfile "${out}/edge/edge.ext" \
  -out "${out}/edge/edge.crt"

# --- api: Anwendungsservice, von nginx ueber den Service-Namen adressiert ---
openssl ecparam -name prime256v1 -genkey -noout -out "${out}/api/api.key"
openssl req -new \
  -key "${out}/api/api.key" \
  -subj "/CN=api" \
  -out "${out}/api/api.csr"
printf 'subjectAltName=DNS:api,DNS:localhost\n' > "${out}/api/api.ext"
openssl x509 -req -sha256 -days 1 \
  -in "${out}/api/api.csr" \
  -CA "${out}/ca/local-dev-ca.crt" \
  -CAkey "${out}/ca/local-dev-ca.key" \
  -CAcreateserial \
  -extfile "${out}/api/api.ext" \
  -out "${out}/api/api.crt"

# Der CA-Schluessel wird nach dem letzten Signieren geloescht: Danach kann
# niemand im Lauf weitere Zertifikate ausstellen. Zwischenprodukte ebenso.
rm "${out}/ca/local-dev-ca.key" \
  "${out}/edge/edge.csr" "${out}/edge/edge.ext" \
  "${out}/api/api.csr" "${out}/api/api.ext"

# nginx (UID 101) und die API (UID 1654) muessen ihren Wegwerf-Schluessel
# lesen koennen; die Dateien gehoeren dem Runner-Nutzer.
chmod 0644 "${out}/edge/edge.key" "${out}/api/api.key"

echo "Wegwerf-Zertifikate erzeugt in '${out}' (gueltig: 1 Tag)."
