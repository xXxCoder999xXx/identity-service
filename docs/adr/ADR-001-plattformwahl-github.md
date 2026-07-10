# ADR-001: GitHub als Entwicklungs- und Automatisierungsplattform

- **Status:** Akzeptiert
- **Datum:** 2026-07-08

## Kontext

Das Projekt verlangt vor der ersten Fachlogik ein vollständiges Automatisierungsfundament:
CI-Pipeline mit hart fehlschlagenden Checks, geschützter Merge-Prozess mit Auto-Merge,
automatisierte Dependency-Updates, eine Container-Registry für „dasselbe Image überall"
sowie einen Secret-Store außerhalb des Repositories. Die Wahl der Plattform bestimmt die
konkrete Mechanik all dieser Pfeiler und ist daher die erste Architekturentscheidung.

## Entscheidung

Wir verwenden **GitHub** (Repository, GitHub Actions als CI/CD, Branch-Protection-Rulesets,
natives Auto-Merge, Dependabot, GitHub Container Registry, Actions-Secrets/Environments).

## Betrachtete Alternativen

1. **GitLab** – CI, Registry und Dependency-Scanning in einer Anwendung, sehr gut
   self-hostbar. Dagegen sprach: Die relevanten Security-Features liegen teilweise hinter
   der Ultimate-Lizenz, und das Ökosystem geprüfter Pipeline-Bausteine ist kleiner.
2. **Azure DevOps** – etabliert in klassischen .NET-Umgebungen. Dagegen sprach: Microsofts
   Investitionsschwerpunkt liegt erkennbar auf GitHub; für ein neues, langlebiges Projekt
   setzen wir nicht auf die stagnierende Plattform desselben Herstellers.

## Begründung

GitHub erfüllt jeden Punkt des Anforderungskatalogs mit Bordmitteln – Branch Protection mit
erzwungenen Status-Checks, natives Auto-Merge, Dependabot, GHCR – und folgt damit dem
Projektprinzip minimaler Abhängigkeiten: kein Zusatzdienst, kein Fremd-Bot, keine externe
Registry nötig.

## Konsequenzen

- **Supply-Chain-Härtung ist Pflicht, keine Option.** Der Angriff auf
  `tj-actions/changed-files` (CVE-2025-30066, CISA-KEV) zeigte, dass Versions-Tags von
  Actions nachträglich auf bösartigen Code umgebogen werden können. Daher gilt verbindlich:
  1. Alle Actions werden auf **vollständige Commit-SHAs** gepinnt, nie auf Tags.
  2. Jeder Workflow deklariert einen **restriktiven `permissions:`-Block** (Least Privilege
     für das automatisch erzeugte `GITHUB_TOKEN`).
  3. Secrets liegen ausschließlich in Actions-Secrets/Environments, nie im Repository.
- Dependabot wird aktiviert, sobald die CI existiert (Update-PRs ohne CI wären ungeprüft).
- Die CD-Kette nutzt GHCR als Registry (Konzeption in Schritt 5).
- Lock-in-Risiko akzeptiert: Git selbst bleibt portabel; Workflow-YAML wäre bei einem
  Plattformwechsel zu übersetzen. Das Risiko wird durch schlanke, gut dokumentierte
  Workflows klein gehalten.
