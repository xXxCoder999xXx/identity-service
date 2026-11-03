# shellcheck shell=bash
# =============================================================================
# Pruefregeln fuer Herkunftsnachweise unserer Images (ADR-010, E-5-78,
# E-5-116). Bibliothek: wird von einem Einstieg per "source" geladen und
# fuehrt beim Laden nichts aus ausser Konstanten zu setzen.
#
# Warum eine Bibliothek: Die Regeln (welches Repository, welcher Workflow,
# welcher Branch, welcher Runner, welche Gegenproben) gelten in der CI und
# spaeter auf dem Server. Sie stehen deshalb an EINER Stelle. Der Einstieg
# entscheidet nur, wie Meldungen aussehen und welche Pruefungen er aufruft
# (Open/Closed: eine neue Umgebung ist ein neuer Einstieg, keine Aenderung
# hier).
#
# Die Bibliothek liest keine Umgebungsvariablen und wechselt kein
# Verzeichnis. Alle Werte kommen als Parameter von attest_init.
#
# Der Einstieg muss vor attest_init drei Funktionen bereitstellen:
#   attest_fail CODE MELDUNG   Abbruch mit Exit-Code CODE (kehrt nie zurueck)
#   attest_group_start TITEL   Beginn eines Abschnitts in der Ausgabe
#   attest_group_end           Ende eines Abschnitts
#
# Exit-Codes, die die Bibliothek ueber attest_fail ausloest:
#   2  Voraussetzung oder Parameter fehlt bzw. ist ungueltig
#   3  ein Nachweis fehlt, ist ungueltig oder hat abweichende Angaben
#   4  eine Gegenprobe wurde akzeptiert: das Pruef-Gate ist wertlos
# =============================================================================

readonly ATTEST_BRANCH="refs/heads/main"
readonly ATTEST_PROVENANCE="https://slsa.dev/provenance/v1"
readonly ATTEST_SBOM="https://cyclonedx.org/bom"

# Was im verifizierten Nachweis stehen muss (eine Zeile je Nachweis).
readonly ATTEST_FACTS='.[] | .verificationResult
  | [ .statement.predicateType,
      .signature.certificate.sourceRepositoryURI,
      .signature.certificate.sourceRepositoryRef,
      .signature.certificate.buildSignerURI,
      .signature.certificate.runnerEnvironment ]
  | @tsv'

# Prueft die Eingaben und legt die abgeleiteten Werte fest.
# $1 REPO            owner/name, z. B. xXxCoder999xXx/identity-service
# $2 SERVER_URL      z. B. https://github.com
# $3 IMAGE_NAME      Name in der Registry ohne Tag und ohne Digest
# $4 DIGEST          sha256:... des Images
# $5 WORKFLOW        Dateiname des Workflows, der signiert haben MUSS
# $6 WRONG_WORKFLOW  Dateiname eines anderen Workflows (Gegenprobe)
attest_init() {
  local fn
  # Fail closed: Ohne die Funktionen des Einstiegs koennte ein Fehler nicht
  # abbrechen. Ausgabe direkt, weil attest_fail ja gerade fehlen kann.
  for fn in attest_fail attest_group_start attest_group_end; do
    if ! declare -F "${fn}" >/dev/null; then
      echo "Einstieg stellt ${fn} nicht bereit." >&2
      exit 2
    fi
  done

  [ "$#" -eq 6 ] || attest_fail 2 "attest_init erwartet 6 Parameter (erhalten: $#)."
  local repo="$1" server_url="$2" image_name="$3" digest="$4"
  local workflow_file="$5" wrong_workflow_file="$6"

  [ -n "${repo}" ] || attest_fail 2 "Repository ist leer."
  [ -n "${server_url}" ] || attest_fail 2 "Server-URL ist leer."
  case "${image_name}" in
    *:* | *@*) attest_fail 2 "IMAGE_NAME '${image_name}' enthaelt Tag oder Digest." ;;
  esac
  case "${digest}" in
    sha256:*) ;;
    *) attest_fail 2 "DIGEST '${digest}' beginnt nicht mit sha256:." ;;
  esac
  [ "${#digest}" -eq 71 ] || attest_fail 2 "DIGEST hat nicht die erwartete Laenge: '${digest}'."
  [ "${workflow_file}" != "${wrong_workflow_file}" ] || attest_fail 2 "WORKFLOW und WRONG_WORKFLOW sind gleich; die Gegenprobe waere wertlos."

  readonly ATTEST_REPO="${repo}"
  readonly ATTEST_SUBJECT="oci://${image_name}@${digest}"
  readonly ATTEST_WORKFLOW="${repo}/.github/workflows/${workflow_file}"
  readonly ATTEST_WRONG_WORKFLOW_FILE="${wrong_workflow_file}"
  readonly ATTEST_WRONG_WORKFLOW="${repo}/.github/workflows/${wrong_workflow_file}"
  readonly ATTEST_EXPECTED_REPO="${server_url}/${repo}"
  readonly ATTEST_EXPECTED_SIGNER="${server_url}/${ATTEST_WORKFLOW}@${ATTEST_BRANCH}"
}

# Muss bestehen UND die erwarteten Angaben enthalten.
# $1 Titel, $2 Art des Nachweises, Rest: weitere Optionen
# gh schreibt ohne Terminal bei Erfolg nichts: Deshalb gibt jede
# Verifikation aus, was im Nachweis steht, und vergleicht es mit den
# erwarteten Werten. Fehlt die Ausgabe, wird der Lauf rot (fail closed).
# Die Feldnamen der Ausgabe sind am 2026-10-08 mit gh 2.102.0 an einem
# oeffentlichen Nachweis (cli/cli) ausprobiert.
attest_verify_ok() {
  local title="$1" type="$2" out want
  shift 2
  attest_group_start "${title}"
  out="$(gh attestation verify "${ATTEST_SUBJECT}" \
    --repo "${ATTEST_REPO}" \
    --signer-workflow "${ATTEST_WORKFLOW}" \
    --source-ref "${ATTEST_BRANCH}" \
    --deny-self-hosted-runners \
    --predicate-type "${type}" \
    "$@" \
    --format json --jq "${ATTEST_FACTS}")" || attest_fail 3 "${title}: Verifikation fehlgeschlagen."
  printf 'Art | Repository | Branch | Workflow | Runner\n%s\n' "${out}"
  want="$(printf '%s\t%s\t%s\t%s\t%s' \
    "${type}" "${ATTEST_EXPECTED_REPO}" "${ATTEST_BRANCH}" "${ATTEST_EXPECTED_SIGNER}" github-hosted)"
  if [ -z "${out}" ] || printf '%s\n' "${out}" \
    | grep --invert-match --line-regexp --fixed-strings --quiet -- "${want}"; then
    attest_fail 3 "${title}: Die verifizierten Angaben fehlen oder weichen ab."
  fi
  attest_group_end
}

# Muss scheitern. $1 Titel, Rest: vollstaendiger Aufruf nach "verify"
attest_verify_must_fail() {
  local title="$1"
  shift
  attest_group_start "Gegenprobe: ${title}"
  if gh attestation verify "$@"; then
    attest_fail 4 "Gegenprobe '${title}' wurde akzeptiert. Das Pruef-Gate ist wertlos."
  fi
  echo "Gegenprobe bestanden: abgelehnt."
  attest_group_end
}

# Die Gegenproben schuetzen vor einem Pruefwerkzeug, das alles durchwinkt.
# Das fremde Image (nginx aus compose.yaml) hat gar keinen Nachweis. Die
# beiden anderen pruefen das EIGENE Image und aendern je genau eine
# Bedingung: Derselbe Aufruf besteht unmittelbar davor, also loest genau
# diese Bedingung die Ablehnung aus. WRONG_WORKFLOW ist der Workflow des
# jeweils ANDEREN Images: Ein Nachweis des einen Images gilt nie fuer das
# andere.

# Sucht das fremde Image fuer die Gegenprobe und legt es in ATTEST_FOREIGN ab.
# $1 Ordner mit der compose.yaml
# Kein Aufruf in "$(...)": attest_fail muss den ganzen Lauf beenden, nicht nur
# eine Subshell.
attest_find_foreign_image() {
  local compose_dir="$1" foreign
  attest_group_start "Fremdes Image fuer die Gegenprobe"
  foreign="$(cd "${compose_dir}" && docker compose config --images \
    | grep --max-count 1 '^nginxinc/.*@sha256:' \
    | sed --regexp-extended 's/:[^:@/]+@/@/')" || true
  [ -n "${foreign}" ] || attest_fail 2 "Kein fremdes Image fuer die Gegenprobe gefunden."
  echo "${foreign}"
  attest_group_end
  readonly ATTEST_FOREIGN="${foreign}"
}

# Gegenproben. Weitere Optionen (Rest) haengt der Einstieg an, z. B. die
# Quelle der Nachweise.
attest_reject_foreign_image() {
  attest_verify_must_fail "fremdes Image ${ATTEST_FOREIGN}" "oci://${ATTEST_FOREIGN}" \
    --repo "${ATTEST_REPO}" --signer-workflow "${ATTEST_WORKFLOW}" \
    --source-ref "${ATTEST_BRANCH}" --deny-self-hosted-runners "$@"
}

attest_reject_wrong_workflow() {
  attest_verify_must_fail "eigenes Image, falscher Workflow (${ATTEST_WRONG_WORKFLOW_FILE})" "${ATTEST_SUBJECT}" \
    --repo "${ATTEST_REPO}" --signer-workflow "${ATTEST_WRONG_WORKFLOW}" \
    --source-ref "${ATTEST_BRANCH}" --deny-self-hosted-runners "$@"
}

attest_reject_wrong_branch() {
  attest_verify_must_fail "eigenes Image, falscher Branch" "${ATTEST_SUBJECT}" \
    --repo "${ATTEST_REPO}" --signer-workflow "${ATTEST_WORKFLOW}" \
    --source-ref refs/heads/not-main --deny-self-hosted-runners "$@"
}
