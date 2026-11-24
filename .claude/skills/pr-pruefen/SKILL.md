---
name: pr-pruefen
description: Prüft im IdentityService-Projekt eine Änderung vor dem Commit bzw. vor dem Pull Request mit lokalen Gates, Code-Review, Security-Review und Abgleich gegen frühere Entscheidungen. Verwenden, bevor ein Commit für einen PR entsteht, bevor ein PR angelegt wird und wenn der Nutzer „committe“ oder „PR“ sagt.
---

# Änderung vor dem PR prüfen

Ziel: Fehler und Regelbrüche finden, bevor die CI oder die Ownerin sie findet. KI-erzeugter Code durchläuft dieselben Gates wie menschlicher (CLAUDE.md 6.3.1); dieser Skill kommt davor, nicht an ihrer Stelle.

## Umfang

- **Voll** (alle Schritte): jede Änderung außerhalb von `docs/sitzungen/` und `docs/adr/`. Dazu gehören ausdrücklich `src/`, `tests/`, `scripts/`, `.github/`, `docker/`, `deploy/`, `nginx/`, `Dockerfile`, `.dockerignore`, `compose*.yaml`, `nginx*.conf`, die Build-Governance-Dateien (`Directory.Build.props`, `Directory.Packages.props`, `nuget.config`, `global.json`), `docs/governance/`, `CLAUDE.md` und `.claude/**`.
- **Kurz** (nur Schritt 4 und 6): reine Sitzungsberichte und ADRs. Hier zählt der Abgleich mit früheren Entscheidungen, nicht Code- oder Security-Review.
- **Nicht erneut:** Ein Push ohne neue Commits seit der letzten Prüfung, oder Commits, die nur Befunde der letzten Prüfung umsetzen, nachdem Schritt 1 grün war.

## Ablauf

1. **Lokale Gates**, soweit die Änderung sie berührt; Ergebnis nur am Exit-Code ablesen:
   - .NET (`src/`, `tests/`, Build-Governance): die ganze Kette aus CLAUDE.md Abschnitt 3.
   - Bash (`scripts/`): `bash -n` und die zugehörigen `scripts/test-*.sh`.
   - Container und nginx (`Dockerfile`, `.dockerignore`, `docker/`, `compose*.yaml`, `nginx*.conf`, `nginx/`): `docker compose up --build` und ein echter Request auf `https://localhost:8443/health` mit Prüfung der Header (`scripts/Test-Stack.ps1`); Staging-Varianten über `scripts/test-staging-config.sh`. Läuft Docker lokal nicht, das als „nicht geprüft“ melden, nicht als grün.
   - YAML und JSON (`.github/`, `deploy/`): Struktur maschinell prüfen (`.claude/rules/lieferkette-und-ci.md`); `deploy/staging.json` mit `scripts/verify-release-file.sh` und `scripts/test-release-file.sh`.
2. **Code-Review:** den Skill `code-review` mit der Stufe `high` auf den aktuellen Diff anwenden. Ohne Stufe würde die zuletzt benutzte wiederverwendet; `max` und `ultra` nur, wenn der Nutzer sie ausdrücklich verlangt.
3. **Security-Review:** den Skill `security-review` auf die Änderungen des Branches anwenden.
4. **Abgleich mit früheren Entscheidungen:** den Skill `entscheidungen-suchen` für die Themen der Änderung anwenden. Widerspricht der Diff einer gültigen Entscheidung, ist das ein Befund wie ein Bug.
5. **Befunde bearbeiten:** jeden Befund einordnen („Fehler“, „kein Fehler“, „bewusst“, jeweils mit Begründung) und für Fehler eine Korrektur vorschlagen. Umgesetzt wird nach CLAUDE.md Abschnitt 1 erst mit Freigabe des Nutzers; liegt die Freigabe für die Änderung schon vor und bleibt die Korrektur in ihrem Rahmen, gilt sie mit. Nach Korrekturen Schritt 1 wiederholen. Höchstens drei Runden; danach dem Nutzer den Ansatz zur Prüfung vorlegen statt weiter zu flicken.
6. **Ergebnis in den PR-Text**, Abschnitt „Prüfung vor dem PR“: Umfang (voll/kurz), Gates mit Ergebnis, Befunde aus Code- und Security-Review mit Behandlung, berührte Entscheidungen (Codes), was nicht geprüft werden konnte. Bei `CLAUDE.md` und `.claude/**` zusätzlich die Freigabe der Ownerin im Gespräch und CLAUDE.md Abschnitt 6 nennen.

## Grenzen

- Ein grünes Review ersetzt weder CI noch die Prüfung durch die Ownerin. Kein Auto-Merge (CLAUDE.md Abschnitt 4).
- Commit und Push weiterhin nur auf Aufforderung (CLAUDE.md Abschnitt 6).
- Befunde, die eine Abschwächung von Tests, Architekturtests oder Gates nahelegen, nicht umsetzen, sondern melden.
