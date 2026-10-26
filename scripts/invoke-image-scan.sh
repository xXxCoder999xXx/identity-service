#!/usr/bin/env bash
# =============================================================================
# Image-Schwachstellen-Scan mit Grype (ADR-009): Export, Bericht mit
# Stueckliste, Blindheits-Schutz, Gate.
#
# Aufruf:  bash scripts/invoke-image-scan.sh [Image] [Profil]
#          Image ist ein lokal vorhandenes Image, Standard: identity-service-api:ci
#          Profil ist das Scan-Profil des Images (api, lego, nginx), Standard: api
#
# Scan-Profil (ADR-014, E-5-61): legt je Image fest, welches Betriebssystem
# und welche Komponenten der Scanner erkennen MUSS, damit "0 Funde" etwas
# bedeutet. Der Standard "api" ist auch fuer fremde Images fail closed: Ein
# Image ohne passendes Profil scheitert am Blindheits-Schutz (Exit 3).
#
# Warum ein Skript: CI und Veroeffentlichung (ADR-010) scannen dasselbe Image
# nach denselben Regeln. Der Schwellenwert des Gates soll an EINER Stelle
# stehen, nicht in jedem Workflow.
#
# Exit-Codes (jeder ungleich 0 macht den Lauf rot - fail closed):
#   0  kein Fund der Stufe High oder hoeher mit verfuegbarem Fix
#   2  Voraussetzung fehlt, oder Export bzw. Bericht fehlgeschlagen
#   3  Blindheits-Schutz: der Scanner erkennt das Image nicht vollstaendig
#   4  Gate: Fund der Stufe High oder hoeher mit verfuegbarem Fix
#
# Ergebnisdateien: scan/out/grype.json und scan/out/sbom.cdx.json (CycloneDX).
# Der Ordner scan/ ist nie versioniert und liegt ausserhalb des Build-Kontexts.
#
# Der Scanner ist in compose.scan.yaml per Digest gepinnt und laeuft gehaertet:
# Er bekommt das Image nur als Datei, keinen Zugriff auf Docker.
#
# Geschrieben fuer den Linux-Runner. Braucht docker (mit compose) und jq.
# Unter Git Bash fuer Windows verfaelscht die Pfadumschreibung die Angaben
# "docker-archive:/in/..." und "/out/..."; dort MSYS_NO_PATHCONV=1 setzen.
# =============================================================================
set -euo pipefail

image="${1:-identity-service-api:ci}"
profile="${2:-api}"

# Abbruch mit eindeutiger Meldung. "::error::" hebt die Zeile im Protokoll von
# GitHub Actions hervor; lokal ist es gewoehnlicher Text.
fail() {
  echo "::endgroup::"
  echo "::error::$2" >&2
  exit "$1"
}

# compose.scan.yaml bindet ./scan relativ zur Wurzel des Repositories ein.
cd "$(dirname "$0")/.."

echo "::group::Voraussetzungen"
command -v docker >/dev/null 2>&1 || fail 2 "docker wurde nicht gefunden."
command -v jq >/dev/null 2>&1 || fail 2 "jq wurde nicht gefunden. Ohne jq kann der Blindheits-Schutz nicht pruefen."
docker image inspect "${image}" >/dev/null 2>&1 || fail 2 "Das Image '${image}' ist lokal nicht vorhanden."

# Scan-Profile. Jede Anforderung ist "purl:<Praefix>" (mindestens eine
# Komponente dieses Oekosystems) oder "name:<Name>" (mindestens eine
# Komponente mit genau diesem Namen). Ein neues Image bekommt einen neuen
# Zweig; bestehende Zweige werden nicht abgeschwaecht.
case "${profile}" in
  api)
    # Chiseled Ubuntu ohne Paketmanager plus .NET-Runtime.
    expected_distro="ubuntu"
    required=("purl:pkg:deb/" "name:Microsoft.NETCore.App.Runtime.linux-x64")
    ;;
  lego)
    # distroless static (Debian) plus Go-Programmdatei. Ohne "stdlib" waeren
    # die Luecken der Go-Standardbibliothek unsichtbar.
    # Zweite Quelle: Dependabot-PRs und Releases von go-acme/lego.
    expected_distro="debian"
    required=("purl:pkg:deb/" "purl:pkg:golang/" "name:stdlib")
    ;;
  nginx)
    # nginx-unprivileged (Debian). BLINDER FLECK: Das Paket nginx stammt von
    # nginx.org und erscheint als Debian-Paket; dessen CVEs fehlen in Debians
    # Liste (gemessen an 1.30.5). "0 Funde" deckt nginx selbst nicht ab.
    # Zweite Quelle: https://nginx.org/en/security_advisories.html
    expected_distro="debian"
    required=("purl:pkg:deb/" "name:nginx")
    ;;
  *)
    fail 2 "Unbekanntes Scan-Profil '${profile}'."
    ;;
esac
echo "Image: ${image}"
echo "Profil: ${profile}"
echo "::endgroup::"

echo "::group::Image als Datei exportieren"
mkdir -p scan/in scan/db scan/out
# Alte Ergebnisse entfernen: Ein Bericht aus einem frueheren Lauf darf den
# Blindheits-Schutz nie bestehen lassen.
rm -f scan/in/app.tar scan/out/grype.json scan/out/sbom.cdx.json
docker save --output scan/in/app.tar "${image}" || fail 2 "Export des Images fehlgeschlagen."
# Der Scanner laeuft als root OHNE Capabilities (cap_drop: ALL), darf also
# fremde Dateirechte nicht uebergehen. Er muss die Image-Datei lesen und in
# die Ordner fuer Datenbank und Bericht schreiben koennen.
chmod 0644 scan/in/app.tar
chmod 0777 scan/db scan/out
echo "::endgroup::"

echo "::group::Scan-Bericht (alle Funde, ohne Abbruch)"
# Zeigt auch Funde ohne verfuegbaren Fix - sie blockieren nicht, sollen aber
# sichtbar bleiben. Laedt die Datenbank; ohne Netz oder Datenbank bricht
# Grype mit Fehler ab.
docker compose --file compose.scan.yaml run --rm grype \
  docker-archive:/in/app.tar \
  --output table \
  --output json=/out/grype.json \
  --output cyclonedx-json=/out/sbom.cdx.json \
  || fail 2 "Der Scanner konnte den Bericht nicht erzeugen (Netz, Datenbank oder Image-Datei)."
echo "::endgroup::"

echo "::group::Blindheits-Schutz (Betriebssystem und Pakete erkannt)"
# Schutz gegen ein Pruefwerkzeug, das nichts findet, weil es nicht suchen
# konnte (etwa ein Image ohne Paketmanager). Erkennt Grype nicht alles, was
# das Profil verlangt, wird der Lauf rot statt still gruen.
if [ ! -s scan/out/grype.json ] || [ ! -s scan/out/sbom.cdx.json ]; then
  fail 3 "Bericht oder Stueckliste fehlt oder ist leer."
fi
distro="$(jq -r '.distro.name // ""' scan/out/grype.json)" \
  || fail 3 "Der Bericht ist nicht lesbar."
echo "Betriebssystem=${distro} (erwartet: ${expected_distro})"
[ "${distro}" = "${expected_distro}" ] \
  || fail 3 "Der Scanner erkennt das Betriebssystem nicht wie im Profil '${profile}'. Ein Ergebnis ohne Funde waere wertlos (ADR-009)."
for requirement in "${required[@]}"; do
  kind="${requirement%%:*}"
  value="${requirement#*:}"
  case "${kind}" in
    purl) query='[.components[] | select((.purl // "") | startswith($v))] | length' ;;
    name) query='[.components[] | select(.name == $v)] | length' ;;
    *) fail 2 "Unbekannte Anforderung '${requirement}' im Profil '${profile}'." ;;
  esac
  count="$(jq --arg v "${value}" "${query}" scan/out/sbom.cdx.json)" \
    || fail 3 "Die Stueckliste ist nicht lesbar."
  echo "${requirement}=${count}"
  # Keine Zahl => Abbruch. Ein Vergleich mit einem leeren Wert schluege sonst
  # nur mit einer Fehlermeldung fehl und liesse die Pruefung durch.
  case "${count}" in
    ''|*[!0-9]*) fail 3 "Die Stueckliste liefert keine auswertbare Anzahl." ;;
  esac
  [ "${count}" -ge 1 ] \
    || fail 3 "Der Scanner erkennt das Image nicht vollstaendig (${requirement}). Ein Ergebnis ohne Funde waere wertlos (ADR-009)."
done
echo "::endgroup::"

echo "::group::Scan-Gate (High oder hoeher mit verfuegbarem Fix)"
# Schwellenwert nach ADR-009: Funde ohne Fix liegen im Basis-Image und sind
# nicht behebbar - sie stehen im Bericht oben, stoppen aber nicht.
# Nutzt die im Berichtsschritt geladene Datenbank desselben Laufs.
docker compose --file compose.scan.yaml run --rm grype \
  docker-archive:/in/app.tar \
  --only-fixed \
  --fail-on high \
  --output table \
  || fail 4 "Scan-Gate: Fund der Stufe High oder hoeher mit verfuegbarem Fix, oder der Scanner konnte nicht arbeiten."
echo "::endgroup::"

echo "Image-Scan bestanden: ${image} (Profil ${profile})"
