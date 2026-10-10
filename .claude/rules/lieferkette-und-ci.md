---
paths:
  - ".github/**"
  - "Directory.Build.props"
  - "Directory.Packages.props"
  - "nuget.config"
  - "global.json"
  - "**/packages.lock.json"
  - "scripts/*.sh"
---

# Lieferkette und CI – Regeln für diese Pfade

Gilt zusätzlich zu `CLAUDE.md`. Die Begründungen stehen in ADR-003, ADR-009, ADR-010 und in den Kopfkommentaren von `ci.yml`, `codeql.yml`, `publish.yml` und `dependabot.yml`.

## Workflows

- Baseline `permissions: contents: read`. Ein Job-Block **ersetzt** die Baseline (er erweitert sie nicht): `contents: read` dort wiederholen. Schreibrechte nur in einem eigenen Job mit kleinstem Scope (Vorbild: `security-events: write` nur im CodeQL-Job).
- Checkout mit `persist-credentials: false`; `runs-on: ubuntu-24.04` (nie `-latest`); `timeout-minutes` setzen; kein Paket- oder Actions-Cache; kein `pull_request_target`; keine Secrets für Fork-PRs. Deploy-Workflows (Phase 4): `cancel-in-progress: false` und Authentifizierung per OIDC.
- **Script Injection:** Vom Angreifer kontrollierten Text (PR-Titel und -Body, Branch-Name, Commit-Nachricht, Issue-Text) niemals per `${{ ... }}` in ein `run:` einsetzen. Über `env:` übergeben und in der Shell als Variable lesen.
- **Action-Pins:** `uses: owner/repo@<volle 40-stellige SHA> # vX.Y.Z`. Die SHA wird ausschließlich aus dem offiziellen Repo per `git ls-remote` aufgelöst (gepeelte Tags `^{}`, Bundle-Tags wie bei `codeql-action` ausfiltern); Auflösungsdatum im Dateikopf vermerken. Nie Tags oder Branches, nie SHAs aus Gedächtnis oder Blog.
- **Job-Namen sind die Status-Check-Namen des Rulesets** (`Build & Test`, `Analyse (C#)`, `Container & nginx`, `PR-Titel`, `Image-Scan`): nie umbenennen ohne gleichzeitige Ruleset-Anpassung. Ein neuer Job wird erst bewusst als Required Check aufgenommen.
- **Schrittfolge** in `ci.yml` ist die Urteils-Hierarchie und bleibt: Restore (`--locked-mode`, eigener benannter Schritt) → Build mit `--no-restore` → Format mit `--verify-no-changes --no-restore` → Test mit `--no-build`. Folgestufen lösen nie still neu auf und bauen nie neu.
- Sicherheitswerkzeuge in der Pipeline sind fail-closed: Kann ein Werkzeug nicht arbeiten (keine Datenbank, kein Netz), wird die Pipeline rot, nie grün.
- Lädt ein Werkzeug zur Laufzeit Binaries nach, pinnt der Action-SHA nur den Wrapper, nicht das Werkzeug. Bevorzugt: per Digest gepinntes Container-Image. Jedes neue Pipeline-Werkzeug ist eine Abhängigkeit (Vetting, Pin, ADR).
- **`publish.yml`** (ADR-010) ist der einzige Workflow mit Schreibrechten (`packages: write`, `id-token: write`, `attestations: write`): Auslöser nur Push nach `main`, nie Pull Request, kein vom Einreicher kontrollierter Text. Reihenfolge bleibt: bauen → Smoke-Test → Image-Scan → veröffentlichen → Nachweise → Prüf-Gate. Er ist kein Pflicht-Check; ein Fehlschlag zeigt sich erst nach dem Merge.
- **Geteilte Schritte** stehen als Bash-Skript unter `scripts/` (`new-throwaway-certificates.sh`, `invoke-image-scan.sh`), Aufruf über `bash scripts/...`. Der Schwellenwert des Image-Scans steht nur in `invoke-image-scan.sh`, nie zusätzlich in einem Workflow.

## Konfigurationsdateien für andere Werkzeuge

- Syntaktisch gültiges YAML ist nicht semantisch gültig. Nach jeder Änderung die Struktur maschinell prüfen (parsen, Schlüsselhierarchie ausgeben) und kontrollieren, dass die Checks im PR wirklich gelaufen sind. Diagnoseoberflächen von Werkzeugen melden eigene Fehlkonfiguration nicht zuverlässig.
- `dependabot.yml`: Änderungen **additiv** (bestehende Blöcke unangetastet), Commit-Präfix `chore` mit `include: scope`. Gruppen nur für nachweislich gekoppelte Abhängigkeiten (Vorbild: `github/codeql-action*`), nie `patterns: ["*"]`. Dependabot sieht keine `docker run`-Aufrufe in Workflow-Schritten.
- Bot-PRs durchlaufen dieselbe Pipeline, werden nie auto-gemergt und nie ungelesen übernommen.

## NuGet und SDK

- Central Package Management: Versionen ausschließlich in `Directory.Packages.props`. `packages.lock.json` wird mit committet. `nuget.config` enthält `<clear />` und Package Source Mapping (nuget.org als einzige Quelle); bei einem internen Feed wird erweitert, nicht umgebaut.
- NuGetAudit-Warnungen (NU1901 bis NU1904) sind durch `TreatWarningsAsErrors` Build-Fehler. Nie per `NoWarn`, `WarningsNotAsErrors` oder `NuGetAudit=false` wegkonfigurieren; Ausnahmen nur per begründetem ADR.
- `global.json` pinnt das SDK mit `rollForward: disable`. Ein SDK-Wechsel ist **ein** PR mit `global.json` + Build-Stage-Digest im Dockerfile. Vorher das SDK lokal installieren (`dotnet --list-sdks`), dann den Pin anheben. Für jede SDK-Version prüfen, ob es ein passendes Container-Image gibt (Tag-Liste bei MCR): nicht jede Patch-Version hat eines.
- Neue `PackageReference`: Slopsquatting-Verifikation und Aufnahme-Prüfung (ADR-003); `Version` nur in `Directory.Packages.props`.
