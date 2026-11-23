#!/usr/bin/env bash
# =============================================================================
# Baut das Staging-Bundle (ADR-017, E-5-149, E-5-155): ein Image FROM scratch
# mit genau der Dateiliste RELEASE_FILES aus scripts/lib/release-rules.sh.
#
# Aufruf:  bash scripts/build-release-bundle.sh LOCAL_IMAGE
#          LOCAL_IMAGE  lokaler Name des gebauten Images, z. B.
#                       identity-service-release:build
#
# Warum ein eigener, leerer Build-Kontext: Das Bundle soll nur die Dateien
# der Liste enthalten, nichts anderes aus dem Repository. Das Skript
# kopiert sie in einen leeren Ordner und baut nur daraus. Die
# .dockerignore der Wurzel (fuer das API-Image) spielt keine Rolle.
#
# Warum FROM scratch: kein Basis-Image, also keine Abhaengigkeit und nichts
# Ausfuehrbares. Das Bundle wird nie gestartet; der Server kopiert die
# Dateien heraus (PR 4c).
#
# Jede Datei muss eine gewoehnliche Datei sein (kein symbolischer Link):
# Ein Link koennte beim Herauskopieren auf dem Server ausserhalb des
# Release-Ordners zeigen.
#
# Exit-Codes (jeder ungleich 0 macht den Lauf rot - fail closed):
#   0  gebaut; Dateiliste mit SHA-256 im Protokoll
#   2  Parameter fehlt, docker oder Bibliothek fehlt
#   3  Datei der Liste fehlt, ist ein Link oder kein gewoehnliche Datei,
#      oder der Build ist gescheitert
#
# Geschrieben fuer den Linux-Runner. Braucht docker und sha256sum.
# =============================================================================
set -euo pipefail

fail() {
  echo "::error::$2" >&2
  exit "$1"
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"

[ "$#" -eq 1 ] || fail 2 "Erwartet: LOCAL_IMAGE (erhalten: $# Parameter)."
local_image="$1"
[ -n "${local_image}" ] || fail 2 "LOCAL_IMAGE ist leer."
command -v docker >/dev/null 2>&1 || fail 2 "docker wurde nicht gefunden."
command -v sha256sum >/dev/null 2>&1 || fail 2 "sha256sum wurde nicht gefunden."
[ -r "${here}/lib/release-rules.sh" ] || fail 2 "Bibliothek fehlt: ${here}/lib/release-rules.sh"
# shellcheck source=lib/release-rules.sh
. "${here}/lib/release-rules.sh"

context="$(mktemp -d)"
trap 'rm -rf -- "${context}"' EXIT

for file in "${RELEASE_FILES[@]}"; do
  # Nur relative Pfade ohne "..": die Liste ist fest, aber eine Aenderung
  # soll nie aus dem Repository herausgreifen.
  case "${file}" in
    /* | *..*) fail 3 "Unzulaessiger Pfad in RELEASE_FILES: '${file}'" ;;
  esac
  source_file="${root}/${file}"
  [ ! -L "${source_file}" ] || fail 3 "Ist ein symbolischer Link: ${file}"
  [ -f "${source_file}" ] || fail 3 "Fehlt oder ist keine gewoehnliche Datei: ${file}"
  mkdir -p "${context}/$(dirname "${file}")"
  cp -- "${source_file}" "${context}/${file}"
  chmod 0644 "${context}/${file}"
done

echo "Inhalt des Bundles (SHA-256):"
(cd "${context}" && sha256sum -- "${RELEASE_FILES[@]}")

# Dockerfile ueber stdin: Es liegt dadurch nicht im Bundle.
docker build --no-cache --tag "${local_image}" --file - "${context}" <<'DOCKERFILE' \
  || fail 3 "Build des Bundles gescheitert."
FROM scratch
COPY . /
DOCKERFILE

echo "Bundle gebaut: ${local_image}"
