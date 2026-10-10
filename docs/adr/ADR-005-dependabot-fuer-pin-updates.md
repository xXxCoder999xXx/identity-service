# ADR-005: Dependabot für kontrollierte Updates der gepinnten Abhängigkeiten

- **Status:** Akzeptiert
- **Datum:** 2026-10-10

## Kontext

Alle Abhängigkeiten des Projekts sind per Inhalt gepinnt (ADR-003): Actions
per Commit-SHA, NuGet-Pakete über Lockfiles, Images per Digest, das SDK in
`global.json` mit `rollForward: disable`. Ein Pin sorgt dafür, dass sich nichts
von selbst bewegt – er sorgt aber auch dafür, dass nichts von selbst aktuell
bleibt. Ohne Gegenstück veraltet jeder Pin still, und Sicherheitskorrekturen
kommen nicht an.

Kräfte:

- **Jede Abhängigkeit ist eine Sicherheitsentscheidung (A03, 6.2a):** Das gilt
  auch für das Werkzeug, das Updates vorschlägt. Es braucht Zugriff auf das
  Repository.
- **Kein blindes Vertrauen:** Ein Update darf nie ohne Pipeline und ohne
  menschliche Prüfung nach `main` gelangen.
- **Gekoppelte Änderungen gehören atomar in einen PR:** Die CI prüft Zustände,
  nicht Absichten.
- **Open/Closed:** Ein weiteres Ökosystem soll ein zusätzlicher Block sein,
  keine Änderung an den bestehenden.

Die Entscheidung fiel in Sitzung 2 als ADR-Kandidat für zwei Ökosysteme
(`github-actions`, `nuget`) und wurde in Sitzung 9 auf Images und das SDK
ausgeweitet (E-4b-19). Dieses ADR hält den Stand vom 10.10.2026 fest. Die
Nummer 005 war seit Sitzung 2 dafür vorgesehen; ADR-006 bis ADR-008 sind
weiterhin offen.

## Entscheidung

Wir verwenden Dependabot, um Updates für alle gepinnten Abhängigkeiten als
Pull Requests vorschlagen zu lassen, die dieselbe Pipeline durchlaufen wie
jeder andere Code und von einem Menschen gemergt werden.

Im Einzelnen (`.github/dependabot.yml`):

- Fünf Ökosysteme: `github-actions`, `nuget`, `docker` (Dockerfile),
  `docker-compose` (`compose.yaml`, `compose.scan.yaml`) und `dotnet-sdk`
  (`global.json`).
- Lauf wöchentlich am Montag; Commit-Präfix `chore` mit Scope, passend zu
  Conventional Commits.
- Gruppen nur für nachweislich gekoppelte Abhängigkeiten. Derzeit gibt es
  genau eine: `github/codeql-action*`, weil `init` und `analyze` eine
  gemeinsame Laufzeit-Konfiguration teilen.
- Eine `ignore`-Regel hält `nginxinc/nginx-unprivileged` auf dem Stable-Zweig:
  Minor- und Major-Updates schlägt der Bot nicht vor, Patch-Updates weiterhin.
- Kein Auto-Merge, auch nicht für Patch-Updates.

## Betrachtete Alternativen

- **Renovate:** mächtiger bei Gruppierung und mit eigenen Regeln für beliebige
  Dateien. Verworfen, weil es eine Dritt-App mit Zugriff auf das Repository
  ist und damit die Lieferketten-Fläche vergrößert, während Dependabot vom
  Plattformbetreiber selbst stammt (ADR-001) und für unsere Ökosysteme
  ausreicht.
- **Updates von Hand:** war bis Sitzung 9 der Zustand für Images und SDK.
  Verworfen, weil es auf Erinnerung beruht; ein vergessenes Update ist eine
  offene Schwachstelle ohne Meldung.
- **Eine Sammelgruppe für alle Updates** (`patterns: ["*"]`): verworfen, weil
  sie Diffs verwässert und Reviews erschwert, ohne einen Kopplungsgrund zu
  belegen.
- **Auto-Merge für Patch-Updates:** verworfen. SemVer beschreibt die Absicht
  des Herausgebers, nicht unser Risiko, und „Checks grün" ist ohne fachliche
  Testsubstanz ein schwaches Urteil.

## Begründung

Pin und Bot sind zwei Hälften derselben Maßnahme: Der Pin liefert
Determinismus, der Bot kontrollierte Bewegung. Dependabot fügt keine weitere
Partei hinzu, der wir vertrauen müssen – GitHub hat den Zugriff auf das
Repository ohnehin.

Befunde aus dem Betrieb, die die Einzelregeln tragen:

- **Gruppe `codeql-action` (Sitzung 4):** Nach der Korrektur der Datei (PR #15)
  erzeugte der nächste Lauf einen einzigen PR (#16) mit beiden SHAs in einem
  Diff; die zwei unvereinbaren Einzel-PRs schloss der Bot selbst.
- **`ignore`-Regel für nginx (Sitzung 9):** Der Bot schlug in PR #48 den
  Sprung von 1.30.5 auf 1.31.5 vor, also auf den Entwicklungszweig. Alle
  Checks waren grün, der PR wurde gemergt und wieder zurückgenommen. Die
  Wirkung der Regel ist im Protokoll eines Dependabot-Laufs belegt.
- **`compose.scan.yaml` (Sitzung 10):** Im Protokoll eines Laufs belegt, dass
  der Bot die Datei im Ökosystem `docker-compose` findet und das Image des
  Scanners führt.

## Konsequenzen

Positiv:

- Jeder Pin hat einen Weg, aktuell zu bleiben, ohne dass jemand daran denken
  muss.
- Jedes Update ist ein eigener, lesbarer Diff mit denselben Gates wie
  menschlicher Code.
- Ein weiteres Ökosystem ist ein zusätzlicher Block in der Datei.

Negativ und neue Pflichten:

- **Grün heißt nicht regelkonform.** Der Bot kennt unsere Regeln nicht (Fall
  nginx). Release Notes lesen, bevor ein Bot-PR gemergt wird.
- **Die Konfiguration scheitert still.** Ein falsch eingerückter
  `groups`-Block ließ die ganze Datei durch die Schema-Prüfung fallen; das
  SAST-Gate war rund zwei Wochen außer Betrieb. Nach jeder Änderung an
  `dependabot.yml` die Struktur maschinell prüfen, und ein Gruppenmuster erst
  einführen, wenn echte Bot-PRs die Namen zeigen.
- **Der Bot arbeitet je Ökosystem.** Ein neues SDK erzeugt zwei PRs
  (`global.json` und Build-Image), und jeder für sich wird im Check
  `Container & nginx` rot. Das ist gewollt: Der Bot meldet, die Pipeline
  urteilt, zusammengeführt wird von Hand in einem PR.
- **Der Bot sieht nur, was in einer Datei steht, die er kennt.** Ein Image in
  einem `run:`-Schritt eines Workflows bleibt unsichtbar; deshalb steht der
  Scanner in `compose.scan.yaml` (ADR-009).
- **Der Wechsel auf den nächsten Stable-Zweig von nginx ist Handarbeit:** Pin
  anheben und die `ignore`-Regel prüfen.
- **Offen:** eine Gruppe für die beiden .NET-Images im Dockerfile; und der
  Beleg, dass der Bot den Pin von `actions/attest` pflegt – seit dessen
  Aufnahme (ADR-010) gab es kein neues Release.

Auslöser für eine Neubewertung: spürbarer Lärm durch Bot-PRs; ein Ökosystem
oder eine Datei, die Dependabot nicht pflegen kann; ein Sicherheitsvorfall bei
Dependabot; eine tragfähige fachliche Testsuite (Phase 5) als Anlass, die
Frage nach dem Auto-Merge neu zu stellen.
