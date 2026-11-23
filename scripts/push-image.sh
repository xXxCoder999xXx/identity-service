#!/usr/bin/env bash
# =============================================================================
# Laedt ein lokal gebautes Image in die GitHub Container Registry hoch und
# gibt seinen Digest aus (ADR-010, E-5-158).
#
# Aufruf:  bash scripts/push-image.sh LOCAL_IMAGE IMAGE_NAME TAG
#          LOCAL_IMAGE  lokales Image, z. B. identity-service-api
#          IMAGE_NAME   Name in der Registry ohne Tag, z. B. ghcr.io/owner/name
#          TAG          Tag in der Registry, z. B. die Commit-SHA (nie latest)
#
# Ausgabe: auf stdout GENAU eine Zeile, der Digest (sha256:<64 hex>). Alles
# andere (Fortschritt von docker push, Fehler) geht nach stderr, damit der
# Aufrufer den Digest mit $(...) sauber einfangen kann.
#
# Warum ein Skript: Die Logik stand dreimal gleich in publish.yml,
# publish-nginx.yml und publish-lego.yml; der Release-Workflow (ADR-017)
# waere die vierte Kopie gewesen. Eine Quelle der Wahrheit. Die Anmeldung
# an der Registry bleibt im Workflow, weil nur er das Token des Laufs hat.
#
# Warum der Digest aus RepoDigests: Er ist der Fingerabdruck, den die
# Registry nach dem Hochladen vergeben hat. Alle folgenden Schritte
# (Nachweise, Pruef-Gate) bezeichnen das Image nur noch ueber ihn.
#
# Exit-Codes (jeder ungleich 0 macht den Lauf rot - fail closed):
#   0  hochgeladen, Digest auf stdout
#   2  Parameter fehlt oder ist ungueltig, docker fehlt, lokales Image fehlt
#   3  Taggen oder Hochladen gescheitert, oder kein gueltiger Digest
#      fuer IMAGE_NAME ermittelt
#
# Geschrieben fuer den Linux-Runner. Braucht docker (angemeldet an ghcr.io).
# Pruefungen mit Bash-Bordmitteln: Die Tests rufen das Skript mit einem
# docker-Ersatz und ohne weitere Programme auf.
# =============================================================================
set -euo pipefail

# Abbruch mit eindeutiger Meldung. "::error::" hebt die Zeile im Protokoll von
# GitHub Actions hervor; lokal ist es gewoehnlicher Text.
fail() {
  echo "::error::$2" >&2
  exit "$1"
}

[ "$#" -eq 3 ] || fail 2 "Erwartet: LOCAL_IMAGE IMAGE_NAME TAG (erhalten: $# Parameter)."
local_image="$1"
image_name="$2"
tag="$3"

command -v docker >/dev/null 2>&1 || fail 2 "docker wurde nicht gefunden."

[ -n "${local_image}" ] || fail 2 "LOCAL_IMAGE ist leer."

# Nur GHCR, nur Kleinbuchstaben (Vorgabe der Registry), ohne Tag und Digest.
[[ "${image_name}" =~ ^ghcr\.io/[a-z0-9._-]+(/[a-z0-9._-]+)+$ ]] \
  || fail 2 "IMAGE_NAME muss die Form ghcr.io/<owner>/<name> ohne Tag haben: '${image_name}'"

# Syntax eines Docker-Tags; "latest" ist verboten, weil ein Tag auf einen
# wechselnden Stand nichts beweist.
[[ "${tag}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] \
  || fail 2 "TAG ist kein gueltiger Tag: '${tag}'"
[ "${tag}" != "latest" ] || fail 2 "TAG latest ist nicht erlaubt."

docker image inspect "${local_image}" >/dev/null 2>&1 \
  || fail 2 "Lokales Image nicht gefunden: '${local_image}'"

ref="${image_name}:${tag}"
docker tag "${local_image}" "${ref}" >&2 || fail 3 "Taggen gescheitert: ${ref}"
docker push "${ref}" >&2 || fail 3 "Hochladen gescheitert: ${ref}"

repo_digests="$(docker image inspect "${ref}" \
  --format '{{range .RepoDigests}}{{println .}}{{end}}')" \
  || fail 3 "RepoDigests fuer ${ref} nicht lesbar."

# Der erste Eintrag GENAU dieses Namens. Vergleich als Zeichenkette, nicht als
# Regex: Punkte im Namen sind keine Platzhalter, und ein Name wie
# "<name>-evil" passt nicht auf "<name>@".
digest=""
while IFS= read -r line; do
  if [[ "${line}" == "${image_name}@sha256:"* ]]; then
    digest="${line#"${image_name}@"}"
    break
  fi
done <<<"${repo_digests}"

[[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] \
  || fail 3 "Kein gueltiger Digest fuer ${image_name} ermittelt: '${digest}'"

echo "${digest}"
