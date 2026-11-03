#!/usr/bin/env bash
# =============================================================================
# Pruef-Gate fuer veroeffentlichte Images (ADR-010, E-5-78): verifiziert
# Herkunftsnachweis und Stueckliste und beweist mit Gegenproben, dass die
# Pruefung ablehnen kann.
#
# Aufruf:  bash scripts/verify-attestations.sh IMAGE_NAME DIGEST WORKFLOW WRONG_WORKFLOW
#          IMAGE_NAME      Name in der Registry ohne Tag, z. B. ghcr.io/owner/name
#          DIGEST          sha256:... des hochgeladenen Images
#          WORKFLOW        Dateiname des Workflows, der signiert haben MUSS
#          WRONG_WORKFLOW  Dateiname eines anderen Workflows (Gegenprobe)
#
# Einstieg fuer GitHub Actions. Die Regeln stehen in
# scripts/lib/attestation-rules.sh (E-5-116); hier stehen nur die Darstellung
# fuer Actions, die Werte aus der Runner-Umgebung und die Auswahl der
# Pruefungen.
#
# Warum ein Skript: Jedes Image hat seinen eigenen Veroeffentlichungs-
# Workflow und damit seine eigene Signatur-Identitaet (E-5-78). Die Regeln der
# Pruefung sollen trotzdem an EINER Stelle stehen.
#
# Verlangt werden dieses Repository, GENAU der Workflow WORKFLOW, der Branch
# main, ein von GitHub betriebener Runner und die festen Kennungen von
# Repository und Besitzer (E-5-121).
#
# Exit-Codes (jeder ungleich 0 macht den Lauf rot - fail closed):
#   0  alle Nachweise verifiziert, alle Gegenproben abgelehnt
#   2  Voraussetzung oder Parameter fehlt bzw. ist ungueltig
#   3  ein Nachweis fehlt, ist ungueltig oder hat abweichende Angaben
#   4  eine Gegenprobe wurde akzeptiert: das Pruef-Gate ist wertlos
#   5  eine Gegenprobe ist nicht am erwarteten Grund gescheitert: Sie beweist
#      nichts (Details in scripts/lib/attestation-rules.sh)
#
# Geschrieben fuer den Linux-Runner. Braucht gh, docker (mit compose) und die
# Umgebungsvariablen GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SERVER_URL,
# GITHUB_REPOSITORY_ID und GITHUB_REPOSITORY_OWNER_ID.
# =============================================================================
set -euo pipefail

# Abbruch mit eindeutiger Meldung. "::error::" hebt die Zeile im Protokoll von
# GitHub Actions hervor; lokal ist es gewoehnlicher Text.
attest_fail() {
  echo "::endgroup::"
  echo "::error::$2" >&2
  exit "$1"
}

attest_group_start() {
  echo "::group::$1"
}

attest_group_end() {
  echo "::endgroup::"
}

# Die Bibliothek liegt immer neben diesem Skript. Der Pfad kommt bewusst
# nicht aus einer Umgebungsvariable: Sonst liesse sich eine Bibliothek
# unterschieben, die alles durchwinkt. Fehlt sie, bricht der Lauf ab, bevor
# irgendetwas geprueft wird (fail closed).
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rules="${script_dir}/lib/attestation-rules.sh"
[ -r "${rules}" ] || attest_fail 2 "Pruefregeln nicht gefunden: ${rules}"
# shellcheck source=lib/attestation-rules.sh
. "${rules}"

# compose.yaml liegt in der Wurzel des Repositories (fremdes Image, unten).
cd "${script_dir}/.."

attest_group_start "Voraussetzungen"
[ "$#" -eq 4 ] || attest_fail 2 "Erwartet: IMAGE_NAME DIGEST WORKFLOW WRONG_WORKFLOW (erhalten: $# Parameter)."

command -v gh >/dev/null 2>&1 || attest_fail 2 "gh wurde nicht gefunden."
command -v docker >/dev/null 2>&1 || attest_fail 2 "docker wurde nicht gefunden."
[ -n "${GH_TOKEN:-}" ] || attest_fail 2 "GH_TOKEN ist nicht gesetzt."
[ -n "${GITHUB_REPOSITORY:-}" ] || attest_fail 2 "GITHUB_REPOSITORY ist nicht gesetzt."
[ -n "${GITHUB_SERVER_URL:-}" ] || attest_fail 2 "GITHUB_SERVER_URL ist nicht gesetzt."
[ -n "${GITHUB_REPOSITORY_ID:-}" ] || attest_fail 2 "GITHUB_REPOSITORY_ID ist nicht gesetzt."
[ -n "${GITHUB_REPOSITORY_OWNER_ID:-}" ] || attest_fail 2 "GITHUB_REPOSITORY_OWNER_ID ist nicht gesetzt."

# Die Kennungen setzt der Runner selbst (Standard-Umgebungsvariablen von
# GitHub Actions); sie gehoeren zu dem Repository, dessen Workflow laeuft.
# Auf dem Server kommen sie aus der root-eigenen Konfiguration (E-5-121).
attest_init "${GITHUB_REPOSITORY}" "${GITHUB_SERVER_URL}" "$1" "$2" "$3" "$4" \
  "${GITHUB_REPOSITORY_ID}" "${GITHUB_REPOSITORY_OWNER_ID}"
attest_group_end

attest_verify_ok "Herkunftsnachweis (von GitHub geladen)" "${ATTEST_PROVENANCE}"
attest_verify_ok "Herkunftsnachweis (aus der Registry geladen)" "${ATTEST_PROVENANCE}" --bundle-from-oci
attest_verify_ok "Stueckliste" "${ATTEST_SBOM}"

attest_find_foreign_image .

# Gegenproben ueber beide Quellen. Der Server laedt Nachweise nur aus der
# Registry (E-5-116); die Gegenproben ueber "oci" belegen bei jedem Lauf mit
# dem echten gh und der echten Registry, dass die erwarteten Gruende dafuer
# stimmen. Kontrollpaarung je Quelle: die beiden Herkunftsnachweise oben.
for source in api oci; do
  attest_reject_foreign_image "${source}"
  attest_reject_wrong_workflow "${source}"
  attest_reject_wrong_branch "${source}"
done

echo "Pruef-Gate bestanden: ${ATTEST_SUBJECT}"
