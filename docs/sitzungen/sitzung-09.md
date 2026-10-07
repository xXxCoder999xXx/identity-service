# Sitzungsbericht Sitzung 9

**Datum:** 07.10.2026
**Phase:** Schritt 4b Teil 4 umgesetzt – alle vier PRs gemergt und in beide Richtungen bewiesen; fünf Pflicht-Checks im Ruleset, der Datei-Nachtrag für den fünften steht als PR aus
**Vorgänger:** sitzung-08.md (abgeschlossen 07.10.2026)

---

## 1. Erledigt

### 1.1 Pin-Prüfung (Roadmap-Punkt 1)

Alle Pins waren aktuell: SDK `10.0.401` (lokal auflösbar, neuestes Tag bei
MCR), beide .NET-Digests und `nginx-unprivileged:1.30.5` identisch mit der
Registry. Der Patch Tuesday am 13.10.2026 stand noch aus.

### 1.2 PR 2: Dependabot für Images und SDK, CODEOWNERS (PR #47, #51)

- **`dependabot.yml` (#47):** drei zusätzliche Blöcke `docker` (Dockerfile),
  `docker-compose` (compose.yaml) und `dotnet-sdk` (global.json), rein additiv.
  Keine Gruppe für die .NET-Images, weil ein nicht passendes Muster lautlos
  ignoriert würde.
- **`CODEOWNERS` (#51):** `Dockerfile`, `.dockerignore`, `compose.yaml`,
  `nginx.conf`, `CLAUDE.md`, `.claude/` ausdrücklich eingetragen; der
  Platzhalter-Kommentar ist entfernt.

Verifiziert: Dependabot führt die drei neuen Dateien auf seiner
Übersichtsseite; die Struktur der Datei wurde maschinell geprüft und die
Prüfung selbst mit einem absichtlich falsch platzierten Schlüssel gegengetestet.

### 1.3 Vorfall und Korrektur: nginx auf dem Entwicklungszweig (PR #48, #50)

Dependabot öffnete unmittelbar PR #48 (`nginx-unprivileged` 1.30.5 → 1.31.5).
Bei nginx sind ungerade Nebenversionen der Entwicklungszweig. Alle Checks
einschließlich Smoke-Test waren grün, und der PR wurde gemergt, bevor die
Abweichung von der Regel „Stable-Zweig" besprochen war. Rund neun Minuten
später stellte PR #50 den Stand wieder her:

- `compose.yaml` zurück auf `1.30.5` (identisch mit dem Stand vor #48),
- `ignore`-Regel im Block `docker-compose` für Neben- und
  Hauptversionssprünge von `nginxinc/nginx-unprivileged`.

Verifiziert: lokal `nginx -t`, laufendes Image `nginx/1.30.5`, Smoke-Test. Die
Wirkung der Regel ist im Protokoll eines Dependabot-Laufs belegt („Ignored
versions: version-update:semver-minor / semver-major – from
.github/dependabot.yml"), obwohl in der Registry bereits `1.31.6` lag.

### 1.4 Pflicht-Checks und Ruleset-Abgleich (PR #52, #54, #57)

Die Projekt-Ownerin hat das Ruleset in der Weboberfläche erweitert; die Datei
`docs/governance/main-ruleset.json`, Abschnitt 4 der `CLAUDE.md` und die
Regeldatei wurden jeweils nachgezogen:

- `Container & nginx` als Pflicht-Check (#52),
- Quelle „GitHub Actions" für alle Pflicht-Checks statt „any source" (#54),
- `PR-Titel` als Pflicht-Check (#57),
- `Image-Scan` als Pflicht-Check; der Datei-Nachtrag liegt am Sitzungsende als
  Commit `4b55248` auf dem Branch `docs/add-image-scan-to-ruleset-definition`
  und ist noch nicht gemergt.

Verifiziert: Die Datei wurde nach jeder Änderung gegen das über die API
gelesene Ruleset verglichen. Stand am Sitzungsende: fünf Pflicht-Checks
(`Build & Test`, `Analyse (C#)`, `Container & nginx`, `PR-Titel`,
`Image-Scan`), alle mit Quelle GitHub Actions, Strict-Mode, Squash-only,
signierte Commits, keine Bypass-Akteure.

Die Aufnahme von `Image-Scan` war beim ersten Mal als gespeichert gemeldet,
stand aber nicht im über die API gelesenen Ruleset; erst der zweite Versuch
wurde wirksam. Die Dateien wurden deshalb erst nach der Bestätigung durch die
API angepasst.

### 1.5 GitHub-CLI für den Agenten (PR #53)

Die GitHub-CLI `gh` wurde installiert und mit einem fein abgestuften Token
angemeldet: nur dieses Repository, Ablauf 06.11.2026. Seitdem legt der Agent
Pull Requests selbst an, liest Check-Ergebnisse, Protokolle und das Ruleset
und pusht Feature-Branches – jeweils nach Rückfrage. Das Mergen bleibt bei der
Projekt-Ownerin.

- **Harte Grenze:** Das Token hat kein Workflow-Recht. GitHub lehnt jeden Push
  ab, der `.github/workflows/**` ändert; solche Branches pusht die
  Projekt-Ownerin selbst.
- **Leitplanken in `.claude/settings.json` (#53):** `deny` für das Mergen von
  PRs, das Verwalten von Secrets und Variablen, das Löschen und Bearbeiten des
  Repositories, das Ausgeben oder Erneuern des Tokens und schreibende
  API-Aufrufe; `ask` für das Anlegen, Bearbeiten, Schließen und Kommentieren
  von PRs und für Pushes mit einer `-c`-Option.

Verifiziert: Der Merge-Befehl wird über PowerShell, Bash, den vollen
Programmpfad und eine Variable abgelehnt; lesende Aufrufe funktionieren.

Nebenwirkung der Anmeldung: Der Git Credential Manager hatte zeitweise
ebenfalls das beschränkte Token gespeichert, sodass auch die Pushes der
Projekt-Ownerin an Workflow-Dateien scheiterten. Behoben durch Abmelden und
erneute Browser-Anmeldung.

### 1.6 PR 3: PR-Titel-Check (PR #55)

Neuer Workflow `.github/workflows/pr-title.yml` mit einem Job `PR-Titel`:
prüft den Titel gegen das Conventional-Commits-Muster (Groß-/Kleinschreibung
beachtet) und lehnt einen Punkt am Ende ab. Der Titel kommt nur über `env:` in
den Schritt; `permissions: {}`, kein Checkout, keine Action, `pull_request`.

Verifiziert: Der Schritt wurde aus der Datei herausgelöst und lokal mit 23
Titeln ausgeführt, darunter die drei historischen Fehl-Titel und vier
Einschleusungsversuche (keiner wurde ausgeführt). Grün auf PR #55.
**Rot-Beweis** über den Wegwerf-PR #56: Titel `Add something` rot; nach reiner
Titeländerung ohne neuen Commit lief der Job von selbst neu und wurde grün.

### 1.7 PR 4: Image-Scanner (ADR-009 in PR #58, Umsetzung in PR #60)

- **Messung vor der Entscheidung:** Grype v0.120.1 und Trivy 0.75.0 liefen
  lokal als gehärtete Container gegen exportierte Image-Dateien. Beide
  erkennen im chiseled Image Ubuntu 24.04, die Systempakete und die
  .NET-Runtime, melden im Runtime-Image vom August dieselbe High-Lücke in
  OpenSSL (CVE-2026-84782) und brechen ohne Netz und Datenbank mit Fehler ab.
  Docker Scout schied aus, weil es eine Registry-Anmeldung verlangt.
- **ADR-009 (#58, akzeptiert):** Grype als per Digest gepinntes
  Container-Image, Abbruch ab „High" bei verfügbarem Fix, wöchentlicher Lauf.
- **Umsetzung (#60):** `compose.scan.yaml` mit dem Scanner als gehärtetem
  Dienst; Job `Image-Scan` in `ci.yml` mit Bericht, Blindheits-Schutz
  (Betriebssystem, Systempakete und Runtime müssen erkannt sein) und Gate;
  dazu ein wöchentlicher Lauf des ganzen Workflows (montags 05:00 UTC).

Verifiziert: grün auf dem Runner (PR #60), im Protokoll
`Betriebssystem=ubuntu Systempakete=9 Runtime-Paket=1`; der Job dauert rund
zweieinhalb Minuten. **Rot-Beweis** über den Wegwerf-PR #61 (Runtime-Stage auf
den Digest vom August zurückgesetzt): `Image-Scan` rot im Schritt „Scan-Gate",
alle anderen Checks einschließlich Smoke-Test grün.

### 1.8 ADR-004 nachgeschrieben, Sicherheitsfunktionen eingeschaltet (PR #59)

ADR-004 (öffentliches Repository) war laut Sitzung 2 geschrieben und
akzeptiert, lag aber nie im Repository. Es wurde aus `sitzung-02.md` und dem
Kopf von `codeql.yml` rekonstruiert; nicht Überliefertes ist gekennzeichnet.

Dabei fiel auf: Secret Scanning und Push Protection waren in den
Repository-Einstellungen nicht aktiviert. Die Projekt-Ownerin hat sie
eingeschaltet. Über die API geprüft: Secret Scanning, Push Protection,
Dependabot-Alerts und Dependabot Security Updates sind aktiv.

### 1.9 Aufräumen

Alle erledigten lokalen Branches gelöscht; lokal existiert nur `main` und der
Branch dieses Berichts. Die Wegwerf-Branches zu #56 und #61 sind auch auf
GitHub entfernt. Scanner-Images und Messdaten wurden vom Entwicklungsrechner
gelöscht.

---

## 2. Gelernt

- Grün heißt nicht regelkonform: Ein Bot-PR kann alle Checks bestehen und
  trotzdem einer Entscheidung widersprechen – der Titel muss gelesen werden
- Dependabot kennt keine Projektregeln und schlägt die höchste Versionsnummer
  vor; eine `ignore`-Regel muss zum Stand auf `main` passen, sonst schreibt sie
  den falschen Zweig fest
- Dependabot arbeitet je Ökosystem: Compose-Dateien brauchen `docker-compose`,
  das Dockerfile `docker`, `global.json` `dotnet-sdk`
- Die Wartezeit von Dependabot vor neuen Versionen greift bei Images nicht,
  weil viele Registries kein Veröffentlichungsdatum liefern
- GitHub zeigt gemergte Pull Requests ebenfalls als „closed" an; violettes
  Etikett heißt gemergt, rotes heißt verworfen
- Ein Pflicht-Check ist für GitHub nur ein Name; ohne festgelegte Quelle darf
  jede Integration mit Schreibzugriff ihn melden
- „Kein PR" ist kein Beweis für eine wirksame Dependabot-Regel; der Beweis
  steht im Protokoll des Laufs
- Ein Token ohne Workflow-Recht ist eine harte Grenze: Die Pipeline lässt sich
  damit nicht verändern, egal was ein Agent versucht
- Textregeln sind unscharf in beide Richtungen: Sie sperrten auch harmlose
  Befehle, die zufällig dieselben Zeichen enthielten
- Der PR-Titel ist Text des Einreichers und gehört in eine Umgebungsvariable,
  nie per `${{ }}` in ein Skript
- Ein Job, der auch bei reiner Titeländerung laufen soll, braucht den
  Auslöser-Typ `edited`
- Ältere Fehlerberichte über ein Werkzeug ersetzen keine Messung am eigenen
  Gegenstand: Beide Scanner lasen das chiseled Image entgegen den Berichten
- Ein Image-Scanner deckt Systempakete ab, nach dieser Messung aber nicht den
  Patch-Stand der .NET-Runtime
- Ein Container, der als root ohne Capabilities läuft, darf fremde Dateirechte
  nicht übergehen; unter Docker Desktop fällt das nicht auf, auf einem
  Linux-Runner schon
- Verfügbar ist nicht eingeschaltet: Zwei Sicherheitsfunktionen, mit denen eine
  Entscheidung begründet war, liefen knapp drei Monate nicht
- Eine Entscheidung, die nur im Sitzungsbericht steht, ist kein ADR
- Eine Einstellung gilt erst als gespeichert, wenn eine Abfrage sie bestätigt:
  Ein Pflicht-Check stand nach dem ersten Versuch nicht im Ruleset

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-4b-19** | Dependabot auch für Images und SDK, ohne Gruppe | Pin-Updates waren Handarbeit; ein Gruppenmuster wäre ungeprüft (gehört zu ADR-005) |
| **E-4b-20** | `dotnet-sdk` mit aufnehmen, obwohl SDK-Pin und Build-Digest als zwei PRs kommen | Der Bot meldet, die Pipeline urteilt; die Zusammenführung von Hand ist gewollt |
| **E-4b-21** | nginx per `ignore`-Regel auf dem Stable-Zweig halten | Zweigwechsel ist eine bewusste Entscheidung, kein Routine-Update (ADR-Kandidat) |
| **E-4b-22** | `Container & nginx`, `PR-Titel` und `Image-Scan` als Pflicht-Checks | Beide Richtungen bewiesen; ein überstimmbarer Check wird überstimmt |
| **E-4b-23** | Quelle aller Pflicht-Checks auf GitHub Actions festlegen | Ohne Quelle kann jede Integration einen grünen Status melden |
| **E-4b-24** | PR-Titel-Check als eigene Workflow-Datei mit wenigen Zeilen Bash | Muss bei Titeländerung laufen; eine fertige Action wäre eine Abhängigkeit |
| **E-4b-25** | Das Titel-Muster steht an drei Stellen statt in einer gemeinsamen Datei | Der Job müsste sonst Code aus dem Pull Request ausführen |
| **E-4b-26** | Scanner erst messen, dann entscheiden | Berichte über chiseled Images waren widersprüchlich |
| **E-4b-27** | Grype statt Trivy (ADR-009) | Technisch gleichwertig; Vertrauen in die Lieferkette des Herausgebers |
| **E-4b-28** | Eigener Job `Image-Scan`, Scanner-Digest in `compose.scan.yaml` | Eigene Aussage, Smoke-Test bleibt schnell; Dependabot kann den Pin pflegen |
| **E-4b-29** | Blindheits-Schutz als eigener Schritt | Ein Scanner ohne erkannte Pakete darf nicht grün melden |
| **E-4b-30** | Ganzer CI-Workflow läuft wöchentlich | NuGetAudit und Image-Scan sehen Lücken, die nach dem letzten Commit bekannt wurden |
| **E-H-8** | Agent erhält ein beschränktes Token: Branches und PRs, kein Merge, kein Workflow-Recht | Weniger Handarbeit, die menschliche Kontrolle vor `main` bleibt (ADR-Kandidat) |
| **E-H-9** | Leitplanken für `gh` streng als Textregeln, Fehlsperren werden hingenommen | Zu streng ist besser als zu locker; die harte Grenze ist der Rechteumfang des Tokens |
| **E-H-10** | ADR-Nummern 004–008 gelten als vergeben; neue ADRs zählen ab 009 weiter | Sitzungsberichte und Kommentare verweisen bereits auf diese Nummern |

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Der Datei-Nachtrag für `Image-Scan` ist nicht gemergt.** Commit `4b55248`
  auf `docs/add-image-scan-to-ruleset-definition` zieht `main-ruleset.json`,
  Abschnitt 4 der `CLAUDE.md`, die Regeldatei und den Kommentar in `ci.yml`
  nach und trägt `compose.scan.yaml` in die Repository-Karte ein. Weil er
  `ci.yml` berührt, muss die Projekt-Ownerin ihn pushen. Bis zum Merge nennen
  diese Dateien vier statt fünf Pflicht-Checks
- Ob Dependabot `compose.scan.yaml` findet, ist nicht belegt; seit dem Merge
  von #60 lief Dependabot nicht
- Der erste zeitgesteuerte Lauf von `ci.yml` steht aus (Montag, 12.10.2026);
  ein Fehlschlag kommt nur per E-Mail
- Patch-Updates innerhalb von nginx `1.30.x` trotz `ignore`-Regel sind nicht
  belegt; zeigt sich mit `1.30.6`
- Die Rechte des Tokens bei „Administration" sind nur lesend getestet; ob
  Schreiben erlaubt wäre, ist nicht geprüft
- Das Token läuft am 06.11.2026 ab
- Die Leitplanken für `gh` sperren auch harmlose Befehle, in denen ein Wort auf
  „gh" endet und ein gesperrtes Wort folgt, oder die den Schalter `-f` an
  anderer Stelle enthalten
- Auf GitHub liegen noch die Branches der gemergten PRs; „Automatically delete
  head branches" ist nicht eingeschaltet
- Dieser Bericht ist noch nicht committet

**Bekannte Grenzen**

- Keiner der gemessenen Scanner meldete etwas zur .NET-Runtime 10.0.11, obwohl
  das September-Update acht CVEs behob (ADR-009)
- Das Titel-Muster steht an drei Stellen; `Test-RepoState.ps1` liegt weiter
  außerhalb des Repositories und vergleicht ohne Beachtung der
  Groß-/Kleinschreibung
- Hooks und Leitplanken gelten nur für den Agenten, nicht für Befehle im
  Terminal

**Unverändert aus früheren Sitzungen**

- `Dockerfile` Zeile 1 (`# syntax=docker/dockerfile:1`) lädt ein Hilfs-Image
  über einen beweglichen Tag ohne Digest
- `nginx.conf` enthält weder `limit_req_status` noch `proxy_ssl_verify_depth`
- Der Gegentest zu `proxy_ssl_verify` (Zertifikat einer fremden CA) fehlt
- ADR-Rückstand: ADR-005 (Dependabot), ADR-006 (Signaturen), ADR-007
  (chiseled Runtime-Image), ADR-008 (`rollForward: disable`), dazu die
  Kandidaten E-4b-1 bis E-4b-9 und die aus den Abschnitten 3 der Sitzungen 8
  und 9
- Der Projektauftrag liegt nicht im Repository
- `Directory.Build.props`: veralteter Kommentar zum Locked Mode; `README.md`
  ohne Build- und Startbefehle; `sitzung-01.md` fehlt
- HSTS steht bewusst auf `max-age=300`

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 4b: inhaltlich abgeschlossen. Teil 4 umfasste am Ende sieben
Arbeitspakete statt der geplanten vier Bausteine. Offen ist nur der Merge des
Datei-Nachtrags für den fünften Pflicht-Check.

Als Nächstes folgt Schritt 5 (CD): Registry, SBOM, Signatur und Provenance,
OIDC, Staging-Deploy, DORA-Events. Erst danach beginnt Phase 5 mit dem ersten
fachlichen Use Case. Für Schritt 5 ist eine Grundsatzfrage offen: Wo läuft
Staging?

| Thema | Status |
|---|---|
| **Resilienz-Patterns** (Retry, Timeout, Circuit Breaker) | Ausgelöst seit Sitzung 7, unbearbeitet |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher – weiterhin nur einseitige Verifikation |
| **DAST** (OWASP ZAP gegen Staging) | Rückt näher – wird mit dem ersten Staging-Deploy fällig |
| **Lieferketten-Gate** | In dieser Sitzung zweimal durchlaufen: Grype (ADR-009) und die GitHub-CLI (ohne ADR, siehe E-H-8) |
| **Agentic-Gate 6.5** | Nicht ausgelöst: Der Agent mit Token ist Entwicklungswerkzeug, kein Produktbestandteil. Die Erweiterung seiner Rechte ist als E-H-8 festgehalten |
| **Feature Flags, Contract Testing, Mutation Testing, k6, LLM-Gate 6.4** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

**Pins (aus den Registries aufgelöst, Scanner am 07.10.2026, übrige am 06./07.10.2026):**

```
global.json: SDK 10.0.401 (rollForward: disable)

mcr.microsoft.com/dotnet/sdk:10.0-noble
  sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317

mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
  sha256:48e51f2f6798897be7ac4e775c049ed8fe60d3190f637e1f9c9dc7513efa659c

nginxinc/nginx-unprivileged:1.30.5
  sha256:d715f7a85cdfea820fec743ea5aee8a22f91e00ff310ad6275d2638112d8cf8d

ghcr.io/anchore/grype:v0.120.1
  sha256:e4a44ef45d285b829ce6efe2642980329661bd2d18eab5fc539138d4adaebbbe
```

Zum Nachstellen des Rot-Beweises: Das Runtime-Image vom August trägt den
Digest `sha256:0839314d08bb65da369135389a5d8291f75ace587fbb0488f469eb92c62eef68`.

**Ruleset:** `main-protection`, ID `19061452`; Quelle GitHub Actions hat die
`integration_id` `15368`.

**Image lokal scannen:**

```
docker build --tag identity-service-api:ci .
docker save --output scan/in/app.tar identity-service-api:ci
docker compose --file compose.scan.yaml run --rm grype docker-archive:/in/app.tar
```

Der Ordner `scan/` ist nicht versioniert. Der erste Lauf lädt die
Schwachstellen-Datenbank (lokal gut fünf Minuten, auf dem Runner knapp zwei).

**Arbeitsteilung beim Pushen:**

| Änderung betrifft | Push | PR anlegen | Mergen |
|---|---|---|---|
| `.github/workflows/**` | Projekt-Ownerin | Agent über `gh` | Projekt-Ownerin |
| alles andere | Agent mit Token, nach Rückfrage | Agent über `gh` | Projekt-Ownerin |

**Dependabot-Protokolle lesen:** Die Läufe gehören zum Workflow „Dependabot
Updates" und lassen sich mit `gh run list --workflow "Dependabot Updates"` und
`gh run view <id> --log` lesen.

**Fallstricke, die Zeit gekostet haben:**

- `gh auth login` mit Token kann dazu führen, dass auch Git selbst das
  beschränkte Token verwendet. Abhilfe in einem eigenen Terminal:
  `git credential-manager github logout <konto>` und danach
  `git credential-manager github login --browser`
- Ein Push-Befehl außerhalb des Projektordners scheitert mit „not a git
  repository"; das hat nichts mit der Anmeldung zu tun
- In einer Sitzung, die vor der Installation von `gh` begonnen hat, ist `gh`
  nicht im Suchpfad
- Eine Zeile, die mit `::` beginnt, liest der Runner als Befehl; Text des
  Einreichers deshalb nie am Zeilenanfang ausgeben
- Eine Compose-Datei mit eigenem Projektnamen (`name:`) vermeidet, dass ein
  Werkzeug Netz und Namen mit dem Stack teilt
- Vor dem Löschen eines Branches nach einem Squash-Merge den Inhalt gegen
  `main` vergleichen; Git erkennt ihn nicht als gemergt

---

# Roadmap Sitzung 10

## 1. Pflichtrecherche und Blick auf die Automatik (zuerst, kurz)

Warum zuerst: Zwischen den Sitzungen arbeitet jetzt erstmals Automatik ohne
Aufsicht. Zu prüfen:

- Patch Tuesday vom 13.10.2026: Sind SDK und Image-Digests noch aktuell?
- Welche PRs hat Dependabot geöffnet, auch als Paar aus `dotnet-sdk` und
  `docker`? Titel lesen, nichts ungelesen mergen
- Ergebnis des ersten zeitgesteuerten CI-Laufs vom 12.10.2026

## 2. Reste aus 4b Teil 4 schließen

Warum jetzt: Sie sind klein und hängen an bereits bewiesener Arbeit.

1. Prüfen, dass der Datei-Nachtrag für `Image-Scan` gemergt ist
   (Branch `docs/add-image-scan-to-ruleset-definition`); falls nicht, zuerst
   erledigen
2. Im Dependabot-Protokoll nachsehen, ob `compose.scan.yaml` gefunden wird;
   wenn nicht, den Scanner-Dienst unter einem Profil nach `compose.yaml`
   verlegen
3. `# syntax=docker/dockerfile:1` entfernen oder per Digest pinnen

## 3. Schritt 5 (CD): Konzept vor jeder Datei

Warum: Schritt 4 ist abgeschlossen; nach dem Phasenplan folgt die Auslieferung.
Zuerst die Grundsatzfrage klären, weil sie den Umfang bestimmt: **Wo läuft
Staging?** Empfehlung aus Sitzung 8: den Block bewusst klein schneiden –
zuerst Registry, Signatur und ein minimales Staging, alles Weitere später.

Konzeptblöcke: Image in eine Registry veröffentlichen (GHCR nach ADR-001),
SBOM, Signatur und Provenance als Gate vor dem Deploy, OIDC statt langlebiger
Secrets, Deploy-Workflow mit `cancel-in-progress: false`, DORA-Events.

## 4. ADR-Rückstand abbauen (ein kleiner Stapel)

Warum: Diese Sitzung hat gezeigt, dass eine nur im Bericht vermerkte
Entscheidung verloren gehen kann (ADR-004). Vorschlag: mit `/adr` zuerst
ADR-005 (Dependabot, jetzt mit fünf Ökosystemen und `ignore`-Regel) und
ADR-007 (chiseled Runtime-Image, jetzt mit Scanner-Messung) schreiben.

## 5. Vor oder in der Sitzung zu verstehen (vor Code)

- **OIDC in GitHub Actions:** Der Workflow weist sich mit einem kurzlebigen,
  von GitHub ausgestellten Nachweis aus, statt ein gespeichertes Passwort zu
  verwenden. Das Ziel prüft, aus welchem Repository und Branch der Lauf stammt.
- **Signatur und Provenance:** Die Signatur belegt, wer ein Image
  veröffentlicht hat; die Provenance belegt, aus welchem Commit und welchem
  Lauf es gebaut wurde. Beides beweist Herkunft, nicht Gutartigkeit.
- **SBOM:** die Stückliste eines Images. Der Scanner erzeugt sie bereits als
  Nebenprodukt; in Schritt 5 wird sie zum ausgelieferten Artefakt.
- **Environments:** GitHub kann Deployments an Umgebungen mit eigenen Regeln
  und Freigaben binden. Das ist die Stelle, an der ein Mensch vor Produktion
  zustimmt.
- **Dasselbe Image überall:** Gebaut wird einmal; Staging und Produktion
  erhalten denselben Digest, die Konfiguration kommt von außen. Der Smoke-Test
  im Production-Modus aus Sitzung 8 ist die Vorarbeit dafür.

## 6. Optionale Vorbereitung

- In den Repository-Einstellungen „Automatically delete head branches"
  einschalten und die alten Branches auf GitHub löschen
- Überlegen, wo Staging laufen könnte (eigener Server, Cloud-Dienst, zunächst
  nur Registry ohne Deploy)
- Den Projektauftrag als Datei unter `docs/` bereitstellen
- Das Ablaufdatum des Tokens (06.11.2026) vormerken
