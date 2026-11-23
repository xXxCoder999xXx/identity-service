#!/usr/bin/env bash
# =============================================================================
# Prueft den Freigabe-Nachweis des Staging-Bundles (ADR-017, E-5-144 bis
# E-5-146, E-5-157) unter Server-Bedingungen: nur Registry, Platzhalter statt
# Token, erwartete Werte als Konstanten.
#
# Aufruf:  bash verify-release.sh RELEASE_REF NGINX_DOCKERFILE
#          RELEASE_REF       ghcr.io/xxxcoder999xxx/identity-service-release:staging
#                            oder ...identity-service-release@sha256:<64 hex>
#          NGINX_DOCKERFILE  Quelle des fremden Images fuer die Gegenprobe
#                            (E-5-132)
#
# Ablauf:
#   1. Bei einem Tag: gh loest ihn selbst auf und verifiziert; ab hier gilt
#      NUR der verifizierte Digest (kein Zeitfenster zwischen Pruefen und
#      Nutzen, gemessen am 2026-11-23).
#   2. Freigabe-Nachweis mit den Regeln der Bibliothek (Repository,
#      Kennungen, Workflow release-staging.yml, refs/heads/main, Runner,
#      Predicate-Typ).
#   3. Fakten lesen (RELEASE_FACTS): subject, Run-ID, Versuch, Commit und die
#      drei Image-Referenzen aus dem Predicate (RELEASE_RULES).
#   4. Gegenproben: fremdes Image, falscher Workflow, falscher Branch,
#      falscher Predicate-Typ - jede muss am erwarteten Grund scheitern.
#
# Ausgabe: Die Fakten stehen am Ende als Zeilen
#   freigabe<TAB><schluessel><TAB><wert>
# mit den Schluesseln subject, run, attempt, commit, api, nginx, lego (in
# dieser Reihenfolge). Nur bei Exit 0 gueltig. Der Aufrufer vergleicht sie
# (CI: Run-ID und Commit dieses Laufs; Server: gespeicherter Zustand).
#
# Exit-Codes (jeder ungleich 0 heisst: NICHT ausrollen - fail closed):
#   0  Freigabe verifiziert, alle Gegenproben abgelehnt
#   2  Voraussetzung oder Parameter fehlt bzw. ist ungueltig
#   3  Nachweis fehlt, ist ungueltig oder hat abweichende Angaben/Fakten
#   4  eine Gegenprobe wurde akzeptiert: das Pruef-Gate ist wertlos
#   5  eine Gegenprobe ist nicht am erwarteten Grund gescheitert
#
# Installation (E-5-117): root-eigen, zusammen mit lib/attestation-rules.sh,
# lib/registry-only.sh und lib/release-rules.sh im selben Aufbau. Nie aus
# dem Release-Ordner ausfuehren.
# =============================================================================
set -euo pipefail

# --- Darstellung --------------------------------------------------------------
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

# --- Bibliotheken (immer neben diesem Skript) ---------------------------------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for lib in attestation-rules.sh registry-only.sh release-rules.sh; do
  [ -r "${script_dir}/lib/${lib}" ] || attest_fail 2 "Bibliothek nicht gefunden: ${script_dir}/lib/${lib}"
done
# shellcheck source=lib/attestation-rules.sh
. "${script_dir}/lib/attestation-rules.sh"
# shellcheck source=lib/registry-only.sh
. "${script_dir}/lib/registry-only.sh"
# shellcheck source=lib/release-rules.sh
. "${script_dir}/lib/release-rules.sh"

attest_group_start "Voraussetzungen"
[ "$#" -eq 2 ] || attest_fail 2 "Erwartet: RELEASE_REF NGINX_DOCKERFILE (erhalten: $# Parameter)."
release_ref="$1"
nginx_dockerfile="$2"

case "${release_ref}" in
  "${RELEASE_IMAGE_NAME}:${RELEASE_TAG}") digest="" ;;
  "${RELEASE_IMAGE_NAME}@sha256:"*)
    digest="${release_ref#"${RELEASE_IMAGE_NAME}@"}"
    [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] \
      || attest_fail 2 "RELEASE_REF hat keinen gueltigen Digest: '${release_ref}'"
    ;;
  *) attest_fail 2 "RELEASE_REF muss ${RELEASE_IMAGE_NAME}:${RELEASE_TAG} oder ${RELEASE_IMAGE_NAME}@sha256:<64 hex> sein: '${release_ref}'" ;;
esac

registry_only_prepare
attest_group_end

# Gemeinsame Bedingungen jeder Verifikation der Freigabe.
verify_opts=(
  --bundle-from-oci
  --repo "${EXPECTED_REPO}"
  --signer-workflow "${EXPECTED_REPO}/.github/workflows/${RELEASE_WORKFLOW}"
  --source-ref "${ATTEST_BRANCH}"
  --deny-self-hosted-runners
  --predicate-type "${RELEASE_PREDICATE_TYPE}"
)

# 1. Tag aufloesen. gh verifiziert dabei bereits; verwendet wird danach nur
# der Digest, den gh als subject nennt.
if [ -z "${digest}" ]; then
  attest_group_start "Tag ${RELEASE_TAG} aufloesen (verifiziert)"
  resolved="$(gh attestation verify "oci://${release_ref}" "${verify_opts[@]}" \
    --format json --jq '.[].verificationResult.statement.subject[].digest.sha256')" \
    || attest_fail 3 "Freigabe-Nachweis fuer ${release_ref} nicht verifiziert."
  [[ "${resolved}" =~ ^[0-9a-f]{64}$ ]] \
    || attest_fail 3 "Tag ${RELEASE_TAG} ergab keinen eindeutigen Digest: '${resolved}'"
  digest="sha256:${resolved}"
  echo "${release_ref} -> ${digest}"
  attest_group_end
fi

attest_init "${EXPECTED_REPO}" "${EXPECTED_SERVER_URL}" "${RELEASE_IMAGE_NAME}" "${digest}" \
  "${RELEASE_WORKFLOW}" "publish.yml" "${EXPECTED_REPO_ID}" "${EXPECTED_OWNER_ID}"

# 2. Freigabe-Nachweis mit den Regeln der Bibliothek.
attest_verify_ok "Freigabe-Nachweis (aus der Registry geladen)" "${RELEASE_PREDICATE_TYPE}" --bundle-from-oci

# 3. Fakten. Nur stdout wird eingefangen; gh schreibt seine Meldungen
# ("Loaded digest ...") nach stderr, sie stehen im Protokoll. Bei einem
# Fehler kann gh/gojq vor dem Abbruch schon Zeilen ausgegeben haben
# (gemessen am 2026-11-23); verwendet wird die Ausgabe nur bei Exit 0.
attest_group_start "Fakten der Freigabe"
if ! facts="$(gh attestation verify "${ATTEST_SUBJECT}" "${verify_opts[@]}" \
  --format json --jq "${RELEASE_FACTS}")"; then
  printf '%s\n' "${facts}"
  attest_fail 3 "Fakten der Freigabe nicht lesbar oder ungueltig."
fi
printf '%s\n' "${facts}"

keys=()
values=()
while IFS=$'\t' read -r key value; do
  keys+=("${key}")
  values+=("${value}")
done <<<"${facts}"
[ "${keys[*]}" = "subject run attempt commit api nginx lego" ] \
  || attest_fail 3 "Fakten unvollstaendig oder in unerwarteter Reihenfolge: ${keys[*]}"
[ "${values[0]}" = "${digest}" ] \
  || attest_fail 3 "subject ${values[0]} ist nicht der gepruefte Digest ${digest}."
attest_group_end

# 4. Gegenproben. Fuer "falscher Workflow" und "falscher Branch" gilt der
# Predicate-Typ der Freigabe, sonst scheiterten sie schon am Typ.
attest_set_counter_predicate_type "${RELEASE_PREDICATE_TYPE}"
attest_find_foreign_image "${nginx_dockerfile}"
attest_reject_foreign_image oci
attest_reject_wrong_workflow oci
attest_reject_wrong_branch oci

# Falscher Predicate-Typ: dasselbe Bundle, richtige Bedingungen, aber als
# SLSA-Herkunftsnachweis verlangt. Das Bundle hat keinen; ein Freigabe-
# Nachweis darf nie als Herkunftsnachweis gelten und umgekehrt. Meldung aus
# cli/cli pkg/cmd/attestation/api/attestation.go (FilterAttestations),
# v2.103.3 und v2.105.0 gleich, geprueft am 2026-11-23.
attest_verify_must_fail "Bundle, falscher Predicate-Typ" \
  "Error: no attestations found with predicate type: $(attest_ere_literal "${ATTEST_PROVENANCE}")" \
  "${ATTEST_SUBJECT}" --bundle-from-oci --repo "${EXPECTED_REPO}" \
  --signer-workflow "${EXPECTED_REPO}/.github/workflows/${RELEASE_WORKFLOW}" \
  --source-ref "${ATTEST_BRANCH}" --deny-self-hosted-runners \
  --predicate-type "${ATTEST_PROVENANCE}"

echo "Freigabe-Nachweis bestanden: ${ATTEST_SUBJECT}"
for i in "${!keys[@]}"; do
  printf 'freigabe\t%s\t%s\n' "${keys[$i]}" "${values[$i]}"
done
