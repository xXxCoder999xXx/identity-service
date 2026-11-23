#!/usr/bin/env bash
# =============================================================================
# Pruef-Gate auf dem Server (ADR-010, ADR-015, E-5-116): verifiziert
# Herkunftsnachweis und Stueckliste eines unserer Images, BEVOR es
# ausgerollt wird, und beweist mit Gegenproben, dass die Pruefung ablehnen
# kann.
#
# Aufruf:  bash verify-attestations-server.sh IMAGE_REF NGINX_DOCKERFILE
#          IMAGE_REF         ghcr.io/xxxcoder999xxx/<paket>@sha256:<64 hex>
#          NGINX_DOCKERFILE  docker/nginx/Dockerfile aus dem Release-Ordner
#                            (Quelle des fremden Images fuer die Gegenprobe,
#                            E-5-132)
#
# Zweiter Einstieg der Bibliothek scripts/lib/attestation-rules.sh; der erste
# ist scripts/verify-attestations.sh (CI). Die Regeln stehen nur in der
# Bibliothek. Hier stehen die Darstellung fuer das Journal, die erwarteten
# Werte und die Auswahl der Pruefungen.
#
# Unterschiede zum CI-Einstieg:
# - Nachweise nur aus der Registry (--bundle-from-oci, E-5-109). Der Server
#   spricht die GitHub-API nicht an (gemessen am 2026-11-10: Ziele nur
#   ghcr.io, pkg-containers.githubusercontent.com, tuf-repo.github.com,
#   tuf-repo-cdn.sigstore.dev).
# - Erwartete Werte als Konstanten in dieser Datei, nicht aus der Umgebung
#   (E-5-122). Die Zuordnung Paket -> Workflow steht hier; der Aufrufer kann
#   keinen Workflow hineinreichen (E-5-137).
# - Die Umgebung fuer gh setzt der Einstieg selbst (E-5-139), damit auch ein
#   Lauf von Hand ohne Unit dieselben Bedingungen hat.
#
# Anmeldung an der Registry: gh liest sie aus der Docker-Konfiguration
# (DOCKER_CONFIG bzw. ~/.docker). Das echte Token gehoert nur dorthin.
#
# Exit-Codes (jeder ungleich 0 heisst: NICHT ausrollen - fail closed):
#   0  alle Nachweise verifiziert, alle Gegenproben abgelehnt
#   2  Voraussetzung oder Parameter fehlt bzw. ist ungueltig
#   3  ein Nachweis fehlt, ist ungueltig oder hat abweichende Angaben
#   4  eine Gegenprobe wurde akzeptiert: das Pruef-Gate ist wertlos
#   5  eine Gegenprobe ist nicht am erwarteten Grund gescheitert: Sie beweist
#      nichts (Details in lib/attestation-rules.sh)
#
# Installation (E-5-117): root-eigen, fuer den Deploy-Benutzer nicht
# beschreibbar, zusammen mit lib/attestation-rules.sh und
# lib/registry-only.sh im selben Aufbau
# (Verzeichnis/verify-attestations-server.sh, Verzeichnis/lib/...). Nie aus
# dem Release-Ordner ausfuehren: Ein Release braechte sonst seinen eigenen
# Pruefer mit.
# =============================================================================
set -euo pipefail

# --- Darstellung fuer das Journal ---------------------------------------------
attest_fail() {
  echo "FEHLER (Exit $1): $2" >&2
  exit "$1"
}

attest_group_start() {
  echo "== $1"
}

attest_group_end() {
  :
}

# --- Bibliothek ---------------------------------------------------------------
# Immer neben diesem Skript, nie aus einer Umgebungsvariable (sonst liesse
# sich eine Bibliothek unterschieben, die alles durchwinkt).
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rules="${script_dir}/lib/attestation-rules.sh"
[ -r "${rules}" ] || attest_fail 2 "Pruefregeln nicht gefunden: ${rules}"
# shellcheck source=lib/attestation-rules.sh
. "${rules}"
# Erwartete Werte, Mindestversion und Umgebung fuer gh (E-5-122, E-5-139,
# E-5-140), gemeinsam mit scripts/verify-release.sh.
registry_only="${script_dir}/lib/registry-only.sh"
[ -r "${registry_only}" ] || attest_fail 2 "Bibliothek nicht gefunden: ${registry_only}"
# shellcheck source=lib/registry-only.sh
. "${registry_only}"

attest_group_start "Voraussetzungen"
[ "$#" -eq 2 ] || attest_fail 2 "Erwartet: IMAGE_REF NGINX_DOCKERFILE (erhalten: $# Parameter)."
image_ref="$1"
nginx_dockerfile="$2"

# Nur eines unserer Pakete, nur mit vollstaendigem Digest.
[[ "${image_ref}" =~ ^([a-z0-9./-]+)@(sha256:[0-9a-f]{64})$ ]] \
  || attest_fail 2 "IMAGE_REF '${image_ref}' hat nicht die Form NAME@sha256:<64 hex>."
image_name="${BASH_REMATCH[1]}"
digest="${BASH_REMATCH[2]}"

# Zuordnung Paket -> signierender Workflow -> Workflow der Gegenprobe
# (E-5-137). Gleich wie in den publish*.yml: Die Gegenprobe nimmt den
# Workflow eines ANDEREN Images (E-5-78).
case "${image_name}" in
  "${REGISTRY_PREFIX}/identity-service") workflow="publish.yml"; wrong_workflow="publish-lego.yml" ;;
  "${REGISTRY_PREFIX}/identity-service-nginx") workflow="publish-nginx.yml"; wrong_workflow="publish.yml" ;;
  "${REGISTRY_PREFIX}/identity-service-lego") workflow="publish-lego.yml"; wrong_workflow="publish.yml" ;;
  *) attest_fail 2 "Unbekanntes Paket '${image_name}' (erlaubt: identity-service, identity-service-nginx, identity-service-lego unter ${REGISTRY_PREFIX})." ;;
esac

registry_only_prepare

attest_init "${EXPECTED_REPO}" "${EXPECTED_SERVER_URL}" "${image_name}" "${digest}" \
  "${workflow}" "${wrong_workflow}" "${EXPECTED_REPO_ID}" "${EXPECTED_OWNER_ID}"
attest_group_end

attest_verify_ok "Herkunftsnachweis (aus der Registry geladen)" "${ATTEST_PROVENANCE}" --bundle-from-oci
# E-5-138: Die Stueckliste gehoert zum Digest, der ausgerollt wird.
attest_verify_ok "Stueckliste (aus der Registry geladen)" "${ATTEST_SBOM}" --bundle-from-oci

attest_find_foreign_image "${nginx_dockerfile}"

# Gegenproben nur ueber die Registry. Kontrollpaarung: der Herkunftsnachweis
# oben mit derselben Quelle hat unmittelbar davor bestanden.
attest_reject_foreign_image oci
attest_reject_wrong_workflow oci
attest_reject_wrong_branch oci

echo "Pruef-Gate bestanden: ${ATTEST_SUBJECT}"
