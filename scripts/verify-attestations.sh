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
# Warum ein Skript: Jedes Image hat seinen eigenen Veroeffentlichungs-
# Workflow und damit seine eigene Signatur-Identitaet (E-5-78). Die Regeln der
# Pruefung sollen trotzdem an EINER Stelle stehen. WRONG_WORKFLOW ist der
# Workflow des jeweils ANDEREN Images: Die Gegenprobe beweist, dass ein
# Nachweis des einen Images nie fuer das andere gilt.
#
# Verlangt werden dieses Repository, GENAU der Workflow WORKFLOW, der Branch
# main und ein von GitHub betriebener Runner.
#
# Exit-Codes (jeder ungleich 0 macht den Lauf rot - fail closed):
#   0  alle Nachweise verifiziert, alle Gegenproben abgelehnt
#   2  Voraussetzung oder Parameter fehlt bzw. ist ungueltig
#   3  ein Nachweis fehlt, ist ungueltig oder hat abweichende Angaben
#   4  eine Gegenprobe wurde akzeptiert: das Pruef-Gate ist wertlos
#
# Geschrieben fuer den Linux-Runner. Braucht gh, docker (mit compose) und die
# Umgebungsvariablen GH_TOKEN, GITHUB_REPOSITORY und GITHUB_SERVER_URL.
# =============================================================================
set -euo pipefail

# Abbruch mit eindeutiger Meldung. "::error::" hebt die Zeile im Protokoll von
# GitHub Actions hervor; lokal ist es gewoehnlicher Text.
fail() {
  echo "::endgroup::"
  echo "::error::$2" >&2
  exit "$1"
}

# compose.yaml liegt in der Wurzel des Repositories (fremdes Image, unten).
cd "$(dirname "$0")/.."

echo "::group::Voraussetzungen"
[ "$#" -eq 4 ] || fail 2 "Erwartet: IMAGE_NAME DIGEST WORKFLOW WRONG_WORKFLOW (erhalten: $# Parameter)."
image_name="$1"
digest="$2"
workflow_file="$3"
wrong_workflow_file="$4"

command -v gh >/dev/null 2>&1 || fail 2 "gh wurde nicht gefunden."
command -v docker >/dev/null 2>&1 || fail 2 "docker wurde nicht gefunden."
[ -n "${GH_TOKEN:-}" ] || fail 2 "GH_TOKEN ist nicht gesetzt."
[ -n "${GITHUB_REPOSITORY:-}" ] || fail 2 "GITHUB_REPOSITORY ist nicht gesetzt."
[ -n "${GITHUB_SERVER_URL:-}" ] || fail 2 "GITHUB_SERVER_URL ist nicht gesetzt."

case "${image_name}" in
  *:* | *@*) fail 2 "IMAGE_NAME '${image_name}' enthaelt Tag oder Digest." ;;
esac
case "${digest}" in
  sha256:*) ;;
  *) fail 2 "DIGEST '${digest}' beginnt nicht mit sha256:." ;;
esac
[ "${#digest}" -eq 71 ] || fail 2 "DIGEST hat nicht die erwartete Laenge: '${digest}'."
[ "${workflow_file}" != "${wrong_workflow_file}" ] || fail 2 "WORKFLOW und WRONG_WORKFLOW sind gleich; die Gegenprobe waere wertlos."
echo "::endgroup::"

subject="oci://${image_name}@${digest}"
workflow="${GITHUB_REPOSITORY}/.github/workflows/${workflow_file}"
wrong_workflow="${GITHUB_REPOSITORY}/.github/workflows/${wrong_workflow_file}"
branch="refs/heads/main"
provenance="https://slsa.dev/provenance/v1"
sbom="https://cyclonedx.org/bom"

# Was im verifizierten Nachweis stehen muss (eine Zeile je Nachweis).
expected_repo="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
expected_signer="${GITHUB_SERVER_URL}/${workflow}@${branch}"
facts='.[] | .verificationResult
  | [ .statement.predicateType,
      .signature.certificate.sourceRepositoryURI,
      .signature.certificate.sourceRepositoryRef,
      .signature.certificate.buildSignerURI,
      .signature.certificate.runnerEnvironment ]
  | @tsv'

# Muss bestehen UND die erwarteten Angaben enthalten.
# $1 Titel, $2 Art des Nachweises, Rest: weitere Optionen
# gh schreibt ohne Terminal bei Erfolg nichts: Deshalb gibt jede
# Verifikation aus, was im Nachweis steht, und vergleicht es mit den
# erwarteten Werten. Fehlt die Ausgabe, wird der Lauf rot (fail closed).
# Die Feldnamen der Ausgabe sind am 2026-10-08 mit gh 2.102.0 an einem
# oeffentlichen Nachweis (cli/cli) ausprobiert.
verify_ok() {
  local title="$1" type="$2" out want
  shift 2
  echo "::group::${title}"
  out="$(gh attestation verify "${subject}" \
    --repo "${GITHUB_REPOSITORY}" \
    --signer-workflow "${workflow}" \
    --source-ref "${branch}" \
    --deny-self-hosted-runners \
    --predicate-type "${type}" \
    "$@" \
    --format json --jq "${facts}")" || fail 3 "${title}: Verifikation fehlgeschlagen."
  printf 'Art | Repository | Branch | Workflow | Runner\n%s\n' "${out}"
  want="$(printf '%s\t%s\t%s\t%s\t%s' \
    "${type}" "${expected_repo}" "${branch}" "${expected_signer}" github-hosted)"
  if [ -z "${out}" ] || printf '%s\n' "${out}" \
    | grep --invert-match --line-regexp --fixed-strings --quiet -- "${want}"; then
    fail 3 "${title}: Die verifizierten Angaben fehlen oder weichen ab."
  fi
  echo "::endgroup::"
}

# Muss scheitern. $1 Titel, Rest: vollstaendiger Aufruf nach "verify"
verify_must_fail() {
  local title="$1"
  shift
  echo "::group::Gegenprobe: ${title}"
  if gh attestation verify "$@"; then
    fail 4 "Gegenprobe '${title}' wurde akzeptiert. Das Pruef-Gate ist wertlos."
  fi
  echo "Gegenprobe bestanden: abgelehnt."
  echo "::endgroup::"
}

verify_ok "Herkunftsnachweis (von GitHub geladen)" "${provenance}"
verify_ok "Herkunftsnachweis (aus der Registry geladen)" "${provenance}" --bundle-from-oci
verify_ok "Stueckliste" "${sbom}"

# Die Gegenproben schuetzen vor einem Pruefwerkzeug, das alles durchwinkt.
# Das fremde Image (nginx aus compose.yaml) hat gar keinen Nachweis. Die
# beiden anderen pruefen das EIGENE Image und aendern je genau eine
# Bedingung: Derselbe Aufruf besteht unmittelbar davor, also loest genau
# diese Bedingung die Ablehnung aus.
echo "::group::Fremdes Image fuer die Gegenprobe"
foreign="$(docker compose config --images \
  | grep --max-count 1 '^nginxinc/.*@sha256:' \
  | sed --regexp-extended 's/:[^:@/]+@/@/')" || true
[ -n "${foreign}" ] || fail 2 "Kein fremdes Image fuer die Gegenprobe gefunden."
echo "${foreign}"
echo "::endgroup::"

verify_must_fail "fremdes Image ${foreign}" "oci://${foreign}" \
  --repo "${GITHUB_REPOSITORY}" --signer-workflow "${workflow}" \
  --source-ref "${branch}" --deny-self-hosted-runners
verify_must_fail "eigenes Image, falscher Workflow (${wrong_workflow_file})" "${subject}" \
  --repo "${GITHUB_REPOSITORY}" --signer-workflow "${wrong_workflow}" \
  --source-ref "${branch}" --deny-self-hosted-runners
verify_must_fail "eigenes Image, falscher Branch" "${subject}" \
  --repo "${GITHUB_REPOSITORY}" --signer-workflow "${workflow}" \
  --source-ref refs/heads/not-main --deny-self-hosted-runners

echo "Pruef-Gate bestanden: ${subject}"
