# shellcheck shell=bash
# =============================================================================
# Gemeinsame Werte und Vorbereitung fuer Pruef-Einstiege, die Nachweise NUR
# aus der Registry laden (Server-Bedingungen, ADR-015, ADR-017). Bibliothek:
# wird per "source" geladen und setzt beim Laden nur Konstanten.
#
# Einstiege:
#   scripts/verify-attestations-server.sh  Images (Herkunft, Stueckliste)
#   scripts/verify-release.sh              Freigabe-Nachweis (ADR-017)
#
# Warum eine Bibliothek: Beide Einstiege laufen auf dem Server und in der CI
# unter denselben Bedingungen (E-5-139). Erwartete Werte, Mindestversion und
# Platzhalter stehen deshalb an EINER Stelle.
#
# Installation (E-5-117): root-eigen, zusammen mit den Einstiegen.
#
# Der Einstieg muss vor registry_only_prepare attest_fail bereitstellen
# (siehe lib/attestation-rules.sh).
# =============================================================================

# --- Erwartete Werte (E-5-122) -----------------------------------------------
# Nicht geheim; Aenderungen nur per PR mit CODEOWNERS. Die Kennungen sind
# die festen Nummern von Repository und Besitzer (E-5-121), abgelesen am
# 2026-11-23 ueber die GitHub-API (repos/xXxCoder999xXx/identity-service).
readonly EXPECTED_REPO="xXxCoder999xXx/identity-service"
readonly EXPECTED_SERVER_URL="https://github.com"
readonly EXPECTED_REPO_ID="1296648545"
readonly EXPECTED_OWNER_ID="291064355"
readonly REGISTRY_PREFIX="ghcr.io/xxxcoder999xxx"

# Mindestversion von gh (E-5-140): Die erwarteten Fehlermeldungen der
# Gegenproben sind an 2.102.0 und 2.103.3 belegt; die Advisories vom
# 2026-09-30 (GHSA-wjmr-j3rp-mh2g, GHSA-4mq3-hpgx-9cx8) betreffen gh
# attestation verify. Neuere Versionen sind erlaubt; aendert eine davon eine
# Meldung, endet der Lauf mit Exit 5, nicht still gruen.
readonly GH_MIN_VERSION="2.103.3"

# Platzhalter statt Token (E-5-136). Gemessen am 2026-11-10 mit gh 2.103.3:
# Mit --bundle-from-oci verlangt gh eine gesetzte Variable, sendet sie aber
# nicht; mit Platzhalter bestand die Pruefung, die Gegenprobe "falscher
# Workflow" scheiterte am erwarteten Grund. Ruft eine kuenftige Version doch
# die API, scheitert sie hier sichtbar (fail closed) statt mit einem echten
# Token ein neues Netzziel zu bekommen.
readonly GH_TOKEN_PLACEHOLDER="placeholder-not-a-token-registry-only"

# Prueft gh (vorhanden, Mindestversion) und setzt die Umgebung fuer gh
# (E-5-139). Unabhaengig davon, was der Aufrufer gesetzt hat: kein echtes
# Token, kein anderer Host, keine Debug-Ausgabe, keine Telemetrie (E-5-108).
# Kein Aufruf in "$(...)": attest_fail muss den ganzen Lauf beenden.
registry_only_prepare() {
  local gh_version
  command -v gh >/dev/null 2>&1 || attest_fail 2 "gh wurde nicht gefunden."
  gh_version="$(gh --version 2>/dev/null | sed --quiet --regexp-extended '1s/^gh version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')" || true
  [ -n "${gh_version}" ] || attest_fail 2 "Version von gh nicht lesbar."
  printf '%s\n%s\n' "${GH_MIN_VERSION}" "${gh_version}" | sort --version-sort --check=quiet \
    || attest_fail 2 "gh ${gh_version} ist aelter als die Mindestversion ${GH_MIN_VERSION}."
  echo "gh ${gh_version} (Mindestversion ${GH_MIN_VERSION})"

  unset GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_HOST GH_DEBUG
  export GH_TOKEN="${GH_TOKEN_PLACEHOLDER}"
  export GH_TELEMETRY=false
  export DO_NOT_TRACK=true
}
