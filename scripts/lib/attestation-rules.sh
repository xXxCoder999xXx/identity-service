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
#   5  eine Gegenprobe ist gescheitert, aber nicht am erwarteten Grund: Sie
#      beweist nichts (z. B. Netzfehler, Token, Ratenbegrenzung)
# =============================================================================

readonly ATTEST_BRANCH="refs/heads/main"
readonly ATTEST_PROVENANCE="https://slsa.dev/provenance/v1"
readonly ATTEST_SBOM="https://cyclonedx.org/bom"

# Was im verifizierten Nachweis stehen muss (eine Zeile je Nachweis).
# Die beiden letzten Spalten sind die festen Kennungen von Repository und
# Besitzer (Fulcio-OIDs 1.3.6.1.4.1.57264.1.15 und .17, E-5-121). Namen
# lassen sich umbenennen und neu vergeben, Kennungen nicht. gh vergleicht
# beim Laden aus der Registry (--bundle-from-oci) nur den Namen; laut
# Hilfetext von gh 2.103.3 erkennt es dort weder Umbenennung noch
# Neuvergabe. Deshalb prueft die Bibliothek die Kennungen selbst. Fehlt ein
# Feld im Zertifikat, bleibt die Spalte leer und der Vergleich scheitert
# (fail closed). Feldnamen aus sigstore-go v1.3.0 (von gh 2.102.0 und
# 2.103.3 verwendet), Werte am 2026-11-03 an unserem Nachweis gemessen.
readonly ATTEST_FACTS='.[] | .verificationResult
  | [ .statement.predicateType,
      .signature.certificate.sourceRepositoryURI,
      .signature.certificate.sourceRepositoryRef,
      .signature.certificate.buildSignerURI,
      .signature.certificate.runnerEnvironment,
      .signature.certificate.sourceRepositoryIdentifier,
      .signature.certificate.sourceRepositoryOwnerIdentifier ]
  | @tsv'

# Prueft die Eingaben und legt die abgeleiteten Werte fest.
# $1 REPO            owner/name, z. B. xXxCoder999xXx/identity-service
# $2 SERVER_URL      z. B. https://github.com
# $3 IMAGE_NAME      Name in der Registry ohne Tag und ohne Digest
# $4 DIGEST          sha256:... des Images
# $5 WORKFLOW        Dateiname des Workflows, der signiert haben MUSS
# $6 WRONG_WORKFLOW  Dateiname eines anderen Workflows (Gegenprobe)
# $7 REPO_ID         feste Kennung des Repositorys (Zahl)
# $8 OWNER_ID        feste Kennung des Besitzers (Zahl)
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

  [ "$#" -eq 8 ] || attest_fail 2 "attest_init erwartet 8 Parameter (erhalten: $#)."
  local repo="$1" server_url="$2" image_name="$3" digest="$4"
  local workflow_file="$5" wrong_workflow_file="$6" repo_id="$7" owner_id="$8"

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
  # Nur Ziffern ohne fuehrende Null: Eine leere oder anders geschriebene
  # Kennung koennte sonst mit einer leeren Spalte uebereinstimmen.
  [[ "${repo_id}" =~ ^[1-9][0-9]*$ ]] || attest_fail 2 "REPO_ID '${repo_id}' ist keine Kennung."
  [[ "${owner_id}" =~ ^[1-9][0-9]*$ ]] || attest_fail 2 "OWNER_ID '${owner_id}' ist keine Kennung."

  readonly ATTEST_REPO="${repo}"
  readonly ATTEST_SUBJECT="oci://${image_name}@${digest}"
  readonly ATTEST_WORKFLOW="${repo}/.github/workflows/${workflow_file}"
  readonly ATTEST_WRONG_WORKFLOW_FILE="${wrong_workflow_file}"
  readonly ATTEST_WRONG_WORKFLOW="${repo}/.github/workflows/${wrong_workflow_file}"
  readonly ATTEST_EXPECTED_REPO="${server_url}/${repo}"
  readonly ATTEST_EXPECTED_SIGNER="${server_url}/${ATTEST_WORKFLOW}@${ATTEST_BRANCH}"
  readonly ATTEST_EXPECTED_REPO_ID="${repo_id}"
  readonly ATTEST_EXPECTED_OWNER_ID="${owner_id}"
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
  printf 'Art | Repository | Branch | Workflow | Runner | Repository-ID | Besitzer-ID\n%s\n' "${out}"
  want="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "${type}" "${ATTEST_EXPECTED_REPO}" "${ATTEST_BRANCH}" "${ATTEST_EXPECTED_SIGNER}" github-hosted \
    "${ATTEST_EXPECTED_REPO_ID}" "${ATTEST_EXPECTED_OWNER_ID}")"
  if [ -z "${out}" ] || printf '%s\n' "${out}" \
    | grep --invert-match --line-regexp --fixed-strings --quiet -- "${want}"; then
    attest_fail 3 "${title}: Die verifizierten Angaben fehlen oder weichen ab."
  fi
  attest_group_end
}

# Muss scheitern, UND zwar am erwarteten Grund (E-5-114).
# $1 Titel, $2 erwarteter Grund (erweiterter regulaerer Ausdruck, muss eine
# ganze Zeile der Ausgabe treffen), Rest: vollstaendiger Aufruf nach "verify"
#
# Ob die Gegenprobe gescheitert ist, entscheidet allein der Exit-Code. Die
# Meldung ordnet nur einen feststehenden Fehlschlag ein: gh kennt fuer
# "abgelehnt" und "Netz weg" denselben Exit-Code 1. Ohne diese Einordnung
# gaelte jeder zufaellige Fehler als Beweis (fail open).
# Die Meldungen stammen aus dem Quellcode von gh (cli/cli, pkg/cmd/attestation,
# v2.102.0 und v2.103.3 gleich, geprueft am 2026-11-03). Aendert eine neue
# gh-Version eine Meldung, wird der Lauf rot (Exit 5), nicht still gruen.
attest_verify_must_fail() {
  local title="$1" reason="$2" out
  shift 2
  attest_group_start "Gegenprobe: ${title}"
  if out="$(gh attestation verify "$@" 2>&1)"; then
    printf '%s\n' "${out}"
    attest_fail 4 "Gegenprobe '${title}' wurde akzeptiert. Das Pruef-Gate ist wertlos."
  fi
  printf '%s\n' "${out}"
  if ! printf '%s\n' "${out}" | grep --extended-regexp --line-regexp --quiet -- "${reason}"; then
    attest_fail 5 "Gegenprobe '${title}' ist nicht am erwarteten Grund gescheitert und beweist nichts. Erwartet (Muster): ${reason}"
  fi
  echo "Gegenprobe bestanden: abgelehnt aus dem erwarteten Grund."
  attest_group_end
}

# Macht einen Wert in einem erweiterten regulaeren Ausdruck woertlich
# (Punkte in Namen, das Fragezeichen der URL usw.).
attest_ere_literal() {
  printf '%s' "$1" | sed --regexp-extended 's/[][\.*^$()+?{}|]/\\&/g'
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

# Gegenproben. Erster Parameter ist die Quelle der Nachweise:
#   api  von der GitHub-API (gh ohne --bundle-from-oci)
#   oci  aus der Registry (gh mit --bundle-from-oci)
# Die Funktion haengt die Option fuer die Quelle selbst an und waehlt den
# dazu passenden erwarteten Grund. Ein Einstieg kann keine weiteren Optionen
# hineinreichen, die nicht zum Grund passen.
#
# Fehlermeldungen beim Laden aus der Registry (cli/cli,
# pkg/cmd/attestation/verification/attestation.go und artifact/oci/client.go,
# v2.102.0 und v2.103.3 gleich, geprueft am 2026-11-03): "no attestations
# found in the OCI registry" kommt NUR, wenn die Registry geantwortet und
# keinen Nachweis geliefert hat. Abruf- und Anmeldefehler haben eigene
# Meldungen ("failed to fetch OCI attestations", "remote registry
# authorization failed", "failed to fetch remote image").

# Setzt ATTEST_SOURCE_OPTS (Optionen fuer gh) und ATTEST_SOURCE_LABEL (fuer
# den Titel). Kein Aufruf in "$(...)", damit attest_fail den Lauf beendet.
attest_select_source() {
  case "$1" in
    api) ATTEST_SOURCE_OPTS=(); ATTEST_SOURCE_LABEL="GitHub-API" ;;
    oci) ATTEST_SOURCE_OPTS=(--bundle-from-oci); ATTEST_SOURCE_LABEL="Registry" ;;
    *) attest_fail 2 "Unbekannte Quelle fuer Gegenprobe: '$1' (erwartet: api oder oci)." ;;
  esac
}

# Erwartet (api): Die API kennt zu diesem Digest in unserem Repository keinen
# Nachweis (HTTP 404, URL mit genau diesem Digest). Derselbe Abruf mit
# demselben Token hat eben fuer das eigene Image funktioniert, ein 404 wegen
# fehlender Rechte ist damit ausgeschlossen.
# Erwartet (oci): Die Registry hat geantwortet, aber keinen Nachweis
# geliefert (gemessen am 2026-11-03, nginx von Docker Hub). Die Meldung nennt
# den Digest nicht; gh hat ihn aber vorher bei der Registry aufgeloest,
# sonst kaeme "failed to fetch remote image".
attest_reject_foreign_image() {
  local reason
  attest_select_source "$1"
  case "$1" in
    api) reason="Error: HTTP 404: Not Found \(https://[^ ]+/repos/$(attest_ere_literal "${ATTEST_REPO}")/attestations/$(attest_ere_literal "${ATTEST_FOREIGN#*@}")\?[^ ]*\)" ;;
    oci) reason="Error: no attestations found in the OCI registry\. Retry the command without the --bundle-from-oci flag to check GitHub for the attestation" ;;
  esac
  attest_verify_must_fail "fremdes Image ${ATTEST_FOREIGN} (${ATTEST_SOURCE_LABEL})" "${reason}" "oci://${ATTEST_FOREIGN}" \
    --repo "${ATTEST_REPO}" --signer-workflow "${ATTEST_WORKFLOW}" \
    --source-ref "${ATTEST_BRANCH}" --deny-self-hosted-runners "${ATTEST_SOURCE_OPTS[@]}"
}

# Erwartet (beide Quellen): Die Signaturpruefung (Sigstore) ist gelaufen und
# hat abgelehnt. Die Bedingung "signiert von Workflow X" prueft gh nicht
# selbst, sondern uebergibt sie an Sigstore; die Meldung nennt deshalb nicht
# den Workflow. Schwaechste der Gegenproben. Aussagekraeftig wird sie durch
# die Kontrollpaarung: Derselbe Aufruf mit dem richtigen Workflow und
# derselben Quelle hat unmittelbar davor bestanden (attest_verify_ok). Abruf,
# Token und Netz sind damit ausgeschlossen, uebrig bleibt der Workflow.
attest_reject_wrong_workflow() {
  attest_select_source "$1"
  attest_verify_must_fail "eigenes Image, falscher Workflow (${ATTEST_WRONG_WORKFLOW_FILE}, ${ATTEST_SOURCE_LABEL})" \
    'Error: verifying with issuer "[^"]+"' "${ATTEST_SUBJECT}" \
    --repo "${ATTEST_REPO}" --signer-workflow "${ATTEST_WRONG_WORKFLOW}" \
    --source-ref "${ATTEST_BRANCH}" --deny-self-hosted-runners "${ATTEST_SOURCE_OPTS[@]}"
}

# Erwartet (beide Quellen): gh nennt genau die geaenderte Bedingung (falscher
# Branch statt des tatsaechlichen). gh prueft sie nach dem Laden, unabhaengig
# von der Quelle.
attest_reject_wrong_branch() {
  local wrong_branch="refs/heads/not-main" reason
  attest_select_source "$1"
  reason="Error: expected SourceRepositoryRef to be $(attest_ere_literal "${wrong_branch}"), got $(attest_ere_literal "${ATTEST_BRANCH}")"
  attest_verify_must_fail "eigenes Image, falscher Branch (${ATTEST_SOURCE_LABEL})" "${reason}" "${ATTEST_SUBJECT}" \
    --repo "${ATTEST_REPO}" --signer-workflow "${ATTEST_WORKFLOW}" \
    --source-ref "${wrong_branch}" --deny-self-hosted-runners "${ATTEST_SOURCE_OPTS[@]}"
}
