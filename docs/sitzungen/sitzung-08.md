# Sitzungsbericht Sitzung 8

**Datum:** 07.10.2026 (begonnen am 06.10.2026)
**Phase:** Schritt 4b Teil 4 begonnen – PR 1 und PR 1b von fünf gemergt; davor Claude-Code-Harness eingerichtet und alle Pins aktualisiert
**Vorgänger:** sitzung-07.md (abgeschlossen 21.08.2026)

---

## 1. Erledigt

### 1.1 Claude-Code-Harness eingerichtet (PR #39)

Die Arbeit wurde vom Chat in Claude Code (CLI) verlegt. Dafür entstand ein
versionierter Harness im Repository:

- **`CLAUDE.md`** (Wurzel): Projektanweisungen, werden in jeder Sitzung geladen.
- **`.claude/rules/`**: drei pfadgebundene Regeldateien (`lieferkette-und-ci.md`,
  `container-und-nginx.md`, `dotnet-und-tests.md`). Sie laden erst, wenn eine
  passende Datei angefasst wird. Im Einsatz bestätigt: Beim Bearbeiten von
  `Dockerfile`, `global.json` und `Program.cs` wurden die jeweils passenden
  Regeln automatisch geladen.
- **`.claude/settings.json`**: Berechtigungen in drei Listen.
  `deny`: Lesen von `certs/**` und `.env*`, Force-Push, Umgehen von Hooks und
  Signierung, `dotnet add package`. `ask`: Commits, Pushes und Änderungen an
  den CODEOWNERS-pflichtigen Pfaden sowie an `CLAUDE.md` und `.claude/**`.
  `allow`: die vier CI-Befehle und lesende Git-Befehle.
- **`.claude/hooks/`**: `Protect-Secrets.ps1` blockiert Shell-Befehle, die
  Zertifikatsordner, Env-Dateien oder User Secrets berühren.
  `Test-CommitConvention.ps1` blockiert Commits auf `main` und Betreffs, die
  kein Conventional Commit sind. Beide sind fail closed.
- **`.claude/skills/`**: `/sitzung-starten`, `/sitzung-beenden`, `/adr`. Das
  Berichtsformat steht nur noch im Skill `sitzung-beenden`; Abschnitt 9 der
  `CLAUDE.md` verweist darauf.

Verifiziert: Lesesperre greift (Zugriff auf eine Datei im Zertifikatsordner
wurde vom Harness abgelehnt); Hooks mit 37 Testfällen über die Skripte geprüft,
darunter die drei historischen Fehl-Titel (#21, #25, #31) und ein Commit auf
`main` in einem Wegwerf-Repository; Hooks blockieren live über PowerShell und
Bash; die Rückfrage bei `git commit` erscheint; die Skills erscheinen als
Slash-Befehle. Dieser Bericht ist der erste, der mit `/sitzung-beenden`
entstanden ist; die Sitzung zu 4b Teil 4 wurde mit `/sitzung-starten` begonnen.

Außerhalb des Repositories liegt eine Memory-Notiz von Claude Code mit den
Eigenheiten des Entwicklungsrechners (siehe Abschnitt 6).

### 1.2 Compose in Langform, nginx-Kommentare (PR #38)

`compose.yaml`: `ports`, Bind-Mounts und `depends_on` in Langform.
`nginx.conf`: nur Kommentare und Ausrichtung. Die Änderungen lagen zu
Sitzungsbeginn uncommittet auf `main` und wurden auf einen eigenen Branch
verschoben. Verhalten unverändert; verifiziert mit `docker compose config`,
`nginx -t`, `/health` über nginx, Security-Header bei 200 und 404.

Dabei wurde der offene Punkt aus Sitzung 7 erledigt: Die Ressourcenlimits
greifen (`docker stats`: `128MiB` für nginx, `256MiB` für die API). Leerlauf:
rund 14 MiB (nginx) und 19–23 MiB (API).

### 1.3 Pin-Updates (PR #40 und PR #41)

Die Pflichtrecherche zu Beginn von 4b Teil 4 ergab drei veraltete Pins und
einen defekten lokalen Build:

- Lokal waren nur die SDKs `10.0.303` und `10.0.401` installiert, gepinnt war
  `10.0.400`. Wegen `rollForward: disable` meldete `dotnet` im Repository
  „A compatible .NET SDK was not found". Die CI war nicht betroffen.
- **PR #40:** `global.json` auf `10.0.401`, dazu Build-Stage- und
  Runtime-Stage-Digest im Dockerfile. `10.0.401` ist laut Release Notes zu
  `10.0.12` das September-SDK (08.09.2026, acht CVEs für .NET 10). Lockfiles
  blieben unverändert.
- **PR #41:** `nginxinc/nginx-unprivileged` von `1.30.4` auf `1.30.5`
  (15.09.2026, behebt CVE-2026-90439 im HTTP/3-Modul, das die Konfiguration
  nicht nutzt).

Beide PRs lokal verifiziert: die vier CI-Befehle, Container-Build, Runtime
`10.0.12` im Container, `/health`, Header, `nginx -t`, UID `101` bzw. `1654`
mit schreibgeschütztem Dateisystem.

### 1.4 4b Teil 4, PR 1: Container-Build und `nginx -t` in der CI (PR #42)

Neuer Job `Container & nginx` in `ci.yml` (kein Required Check): Image bauen
ohne Push und Cache, Image-Nutzer prüfen (numerisch, ungleich 0),
Wegwerf-Zertifikate im Lauf erzeugen, `nginx -t` über
`docker compose run --rm --no-deps nginx nginx -t`.

Verifiziert: grün auf dem PR (CI #96) und auf `main` (CI #97). **Rot-Beweis**
über den Wegwerf-PR #43 (unbekannte Direktive in `nginx.conf`): CI #98 rot im
Schritt `nginx -t`, alle Schritte davor grün, `Build & Test` grün.

Abweichung vom Plan: PR #42 wurde gemergt, bevor der Rot-Beweis vorlag. Der
Beweis wurde danach über den Wegwerf-PR nachgeholt.

### 1.5 4b Teil 4, PR 1b: Smoke-Test im Production-Modus (PR #44)

- **`scripts/Test-Stack.ps1`** (neu): prüft den laufenden Stack mit echten
  Anfragen. `/health` liefert 200 und `Healthy`; fünf Security-Header bei 200
  und 404; `Server`-Header ohne Version; Dienst `api` läuft und veröffentlicht
  keinen Port. Parameter für Adresse, CA-Datei, Dienstname und Wartezeit; kein
  Schalter zum Abschalten der Zertifikatsprüfung. Läuft unter Windows
  PowerShell 5.1 und PowerShell 7 (Windows und Linux).
- **`ci.yml`:** drittes Wegwerf-Zertifikat für die API (SAN `api`), Schritte
  „Stack starten (Production-Modus)", „Smoke-Test", „Container-Logs (nur bei
  Fehlschlag)".
- **`compose.yaml`:** `ASPNETCORE_ENVIRONMENT` ist von außen überschreibbar,
  Vorgabe `Development`. Die CI setzt `Production` und weist den Wert im
  Container nach.

Verifiziert: lokal grün unter beiden PowerShell-Editionen und im
Production-Modus; lokale Gegenproben rot (fehlender Header, gestoppter Stack,
unbekannter Dienst, veröffentlichter Port, fehlende CA-Datei); grün auf dem
Runner (CI #99). **Rot-Beweis** über den Wegwerf-PR #45 (Header
`Referrer-Policy` entfernt): CI #101 rot im Schritt „Smoke-Test", `nginx -t`
grün, Log-Schritt gelaufen.

### 1.6 Aufräumen

Alle erledigten lokalen Branches gelöscht; lokal existiert nur `main`. In der
Zwischenzeit sind außerdem die Dependabot-PRs #34 (CodeQL-Action) und #37
(`Microsoft.NET.Test.Sdk`) auf `main` angekommen.

---

## 2. Gelernt

- `CLAUDE.md` ist Kontext, keine Erzwingung: Was technisch gelten soll, gehört
  zusätzlich in Berechtigungen und Hooks
- Regeldateien mit `paths:`-Kopf wirken nur unter `.claude/rules/`; in der
  Projektwurzel sind es gewöhnliche Markdown-Dateien
- Berechtigungsregeln und Hooks prüfen den Befehlstext; ein zur Laufzeit
  zusammengesetzter Pfad wird nicht erkannt
- Ein Hook muss fail closed sein: leere Eingabe oder kaputtes JSON führen zum
  Blockieren, sonst prüft er im Fehlerfall still gar nichts
- Tags sind bewegliche Zeiger: `sdk:10.0.400-noble` und
  `nginx-unprivileged:1.30.4` zeigten sechs Wochen nach dem Pinnen auf neu
  gebaute Images mit anderem Digest
- Ein SDK-Pin mit `rollForward: disable` bricht den lokalen Build, sobald ein
  Visual-Studio-Update die gepinnte Version ersetzt
- Squash-Merges machen Branches für Git unsichtbar „ungemergt"; das Löschen
  braucht `-D`, deshalb vorher den Inhalt gegen `main` vergleichen
- Ein Workflow, der nur auf `pull_request` und Pushes nach `main` reagiert,
  läuft bei einem Push auf einen Feature-Branch nicht – erst der PR löst ihn aus
- `nginx -t` prüft Syntax und Dateipfade, nicht das Verhalten: Ein fehlender
  Security-Header bleibt dort grün und wird erst im Smoke-Test rot
- Ein Prüfschritt ist erst belegt, wenn er einmal rot war; ein Wegwerf-PR als
  Entwurf liefert den Beweis, ohne dass der Fehler `main` erreicht
- Prozess-Substitution (`<(...)`) hängt von der Shell ab; eine gewöhnliche
  Datei ist robuster
- Eine Überschreibung per Umgebungsvariable braucht einen Nachweis, dass sie
  ankommt – sonst testet die CI still die Vorgabe
- Der Stack läuft schon heute im Production-Modus; getestet wird ab jetzt der
  Modus, der später ausgeliefert wird

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-H-1** | Harness versioniert im Repository statt in Benutzereinstellungen | Reviewbar, CODEOWNERS-fähig, eine Quelle der Wahrheit (ADR-Kandidat) |
| **E-H-2** | Projektstatus bleibt in `docs/sitzungen/`, keine eigene Statusdatei | Vermeidet eine zweite Wahrheit |
| **E-H-3** | `git commit` und `git push` unter `ask`, Force-Push und Hook-Umgehung unter `deny` | Setzt „Commits nur auf Aufforderung" technisch durch |
| **E-H-4** | Hooks blockieren streng auf Wortebene, auch in Commit-Nachrichten | Eine Ausnahme für Nachrichten wäre ein Schlupfloch |
| **E-H-5** | Commit-Betreff-Muster wörtlich aus `Test-RepoState.ps1`, aber Groß-/Kleinschreibung beachtet | Eine Quelle für das Muster; `Chore:` soll durchfallen |
| **E-H-6** | Keine MCP-Server, keine eigenen Subagenten | Wären Abhängigkeiten ohne aktuellen Bedarf |
| **E-H-7** | Kein automatisches `dotnet format` per Hook | Kaum C#-Code; Neubewertung ab Phase 5 |
| **E-4b-10** | Pin-Updates in zwei PRs (.NET, nginx) statt einem | Ein Thema pro Branch; getrennt rückholbar |
| **E-4b-11** | 4b Teil 4 in fünf kleinen PRs statt gebündelt | Die Container-Dateien sind seit #32 gemergt; kleine PRs sind einzeln beweisbar |
| **E-4b-12** | Container-Job in `ci.yml`, ohne Pfadfilter | Pfadfilter verursachten „Config-only-PR mit 0 Checks" |
| **E-4b-13** | Nur Runner-Bordmittel (`docker`, `docker compose`, `openssl`, `curl`, `pwsh`), keine Build-Action | Keine neue Abhängigkeit, solange nichts gepusht wird (ADR-Kandidat) |
| **E-4b-14** | `nginx -t` über `docker compose run` statt eigenem `docker run` | Prüft gegen exakt das gepinnte Image mit denselben Mounts |
| **E-4b-15** | Prüflogik als Skript `scripts/Test-Stack.ps1` für lokal und CI | Lokales Urteil == CI-Urteil |
| **E-4b-16** | CI testet den Production-Modus; `compose.yaml` gibt `Development` nur vor | Development und Production sollen nicht unbemerkt auseinanderlaufen (ADR-Kandidat) |
| **E-4b-17** | Neue Prüfschritte werden über Wegwerf-PRs als Entwurf rot bewiesen | Prüfwerkzeug vor dem Scharfschalten am echten Gegenstand verifizieren |
| **E-4b-18** | `Container & nginx` vorerst kein Required Check | Ruleset-Änderung ist eine bewusste Entscheidung der Projekt-Ownerin |

---

## 4. Offene Punkte

**4b Teil 4**

- PR 2 (Dependabot `docker`, `CODEOWNERS`), PR 3 (PR-Titel-Check) und PR 4
  (Image-Scanner mit ADR) stehen aus
- `Container & nginx` ist kein Required Check; beide Beweise (grün und rot)
  liegen vor, die Aufnahme ins Ruleset ist offen
- Die Wegwerf-PRs #43 und #45 sollten ohne Merge geschlossen und ihre Branches
  auf GitHub gelöscht werden – in dieser Sitzung nicht nachgeprüft
- Der Gegentest zu `proxy_ssl_verify` (API-Zertifikat einer fremden CA muss
  abgelehnt werden) fehlt
- Das nginx-Image wird in der CI anonym von Docker Hub gezogen; ein Rate-Limit
  ist in sechs Läufen nicht aufgetreten, bleibt aber möglich

**Befunde ohne Änderung**

- `Dockerfile` Zeile 1 (`# syntax=docker/dockerfile:1`) lädt bei jedem Build
  ein Hilfs-Image über einen beweglichen Tag ohne Digest
- `CODEOWNERS` nennt `Dockerfile`, `compose.yaml`, `nginx.conf`, `CLAUDE.md`
  und `.claude/` nicht ausdrücklich (nur über den `*`-Fallback)
- `nginx.conf` enthält weder `limit_req_status` (die Regel verlangt 429, die
  Vorgabe ist 503) noch `proxy_ssl_verify_depth`
- `Directory.Build.props`: Kommentar „Die CI wird später im Locked Mode
  restaurieren" ist veraltet
- `README.md` enthält keine Build- oder Startbefehle

**Scanner-Recherche (unvollständig)**

- Aktuelle Versionen und Pflegezustand von Trivy und Grype nicht belegt
- Ob Trivys Datenbank-Updates nach dem Vorfall vom März 2026 wieder normal
  laufen, nicht belegt
- Ob Docker Scout für jeden Aufruf eine Docker-Hub-Anmeldung verlangt, nicht
  belegt

**Harness**

- Der Projektauftrag (Kollaborationsvertrag v2.0) liegt nicht im Repository;
  Regelnummern wie 6.1.1, 6.2a, 6.3.2 sind dort nicht nachschlagbar
- `Test-RepoState.ps1` liegt weiter außerhalb des Repositories und vergleicht
  ohne Beachtung der Groß-/Kleinschreibung
- Die Hooks gelten nur für den Agenten, nicht für Commits im Terminal
- Die GitHub-CLI `gh` ist nicht installiert; PRs werden im Browser angelegt.
  Eine Installation wäre eine neue Abhängigkeit mit Aufnahme-Prüfung

**Unverändert aus früheren Sitzungen**

- ADR-Rückstand: E-4b-1 bis E-4b-9, ADR-005 (Dependabot), ADR-006
  (Signaturen), ADR-008 (`rollForward: disable`), Zero-Trust-Fundament,
  Re-Encryption, TLS-Strategie, nginx-unprivileged, chiseled; neu dazu die
  Kandidaten aus Abschnitt 3
- HSTS steht bewusst auf `max-age=300`
- Alte Branches auf GitHub (`fix(build)`, `rollForward-disable`,
  `docs/sitzung-04` und weitere)
- `sitzung-01.md` fehlt im Repository
- Dieser Bericht ist noch nicht committet

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 4b: Teile 1–3 abgeschlossen (Sitzung 7), Teil 4 zu zwei
Fünfteln (PR 1 und PR 1b). Danach folgt der Rest von Phase 4 (CD: Registry,
Signatur- und Provenance-Gate, OIDC, Staging, DORA-Events), erst dann Phase 5
mit dem ersten fachlichen Use Case.

| Thema | Status |
|---|---|
| **Resilienz-Patterns** (Retry, Timeout, Circuit Breaker) | Ausgelöst seit Sitzung 7, unbearbeitet |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher – weiterhin nur einseitige Verifikation (nginx prüft die API) |
| **DAST** (OWASP ZAP gegen Staging) | Rückt näher – der Stack startet jetzt automatisiert in der CI, ein Staging gibt es noch nicht |
| **Lieferketten-Gate** | Steht mit PR 4 an: Der Scanner ist eine neue Abhängigkeit (Vetting, Pin, ADR) |
| **LLM-Gate 6.4, Agentic-Gate 6.5** | Nicht ausgelöst – der Harness ist Entwicklungswerkzeug, kein Produktbestandteil |

---

## 6. Technische Referenz (für Folgesitzungen)

**Gepinnte Versionen und Digests (aus den Registries aufgelöst am 06.10.2026):**

```
global.json: SDK 10.0.401 (rollForward: disable)

mcr.microsoft.com/dotnet/sdk:10.0-noble          (= 10.0.401-noble)
  sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317

mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled   (= 10.0.12-noble-chiseled)
  sha256:48e51f2f6798897be7ac4e775c049ed8fe60d3190f637e1f9c9dc7513efa659c

nginxinc/nginx-unprivileged:1.30.5
  sha256:d715f7a85cdfea820fec743ea5aee8a22f91e00ff310ad6275d2638112d8cf8d
```

Der nächste Patch Tuesday ist der 13.10.2026; danach sind die .NET-Pins
voraussichtlich wieder fällig.

**Digest auflösen (oberster Digest, Manifest-Liste bzw. OCI-Index):**

```
docker buildx imagetools inspect <image>:<tag> --format "{{.Manifest.Digest}} {{.Manifest.MediaType}}"
```

**Stack lokal prüfen:**

```
docker compose up --detach --build
.\scripts\Test-Stack.ps1
docker compose stop
```

Im Production-Modus: vor `docker compose up` die Umgebungsvariable
`ASPNETCORE_ENVIRONMENT` auf `Production` setzen.

**CI-Ergebnisse ohne Anmeldung lesen (das Repository ist öffentlich):**

```
https://api.github.com/repos/xXxCoder999xXx/identity-service/actions/runs?head_sha=<sha>
```

Die Antwort enthält je Lauf eine `jobs_url` mit den Ergebnissen der einzelnen
Schritte. Ohne Anmeldung sind 60 Abfragen pro Stunde möglich; die Log-Ausgabe
der Schritte ist so nicht abrufbar.

**Eigenheiten des Entwicklungsrechners:**

- `git push` scheitert aus Claude Code mit `terminal prompts disabled`; der
  Push läuft über die Eingabezeile mit vorangestelltem `!`
- `curl.exe` gegen den lokalen Stack braucht `--ssl-no-revoke` (die lokale CA
  bietet keine Sperrliste an); die Kettenprüfung bleibt aktiv
- Docker Desktop läuft nicht dauerhaft
- Commit-Signierung per SSH funktioniert ohne Eingabe

**Fallstricke, die Zeit gekostet haben:**

- Der Hook `Protect-Secrets.ps1` blockiert das Wort für den Zertifikatsordner
  auch in Commit-Nachrichten; Nachrichten entsprechend formulieren
- Der Hook `Test-CommitConvention.ps1` blockiert jeden Commit des Agenten auf
  `main`; vor jeder Arbeit zuerst einen Feature-Branch anlegen
- `docker compose ps --format json` liefert je nach Version eine JSON-Zeile pro
  Container oder ein Array
- Bei mehreren Commits schlägt GitHub den Branch-Namen als PR-Titel vor; der
  Titel wird beim Squash zum Commit auf `main`
- Ein PR existiert erst nach dem Klick auf den Knopf im Formular; ein geöffnetes
  Formular löst keine Checks aus

---

# Roadmap Sitzung 9

## 1. Pflichtrecherche und Pin-Prüfung (zuerst, kurz)

Warum zuerst: Am 13.10.2026 ist Patch Tuesday. Liegt die Sitzung danach, sind
die .NET-Pins voraussichtlich veraltet, und ein Pin-PR ist der erste
Arbeitsschritt – wie in dieser Sitzung. Zu prüfen: `dotnet --list-sdks` gegen
`global.json`, Tag-Listen bei MCR und Docker Hub, nginx.org, Release Notes.

## 2. 4b Teil 4, PR 2: Dependabot `docker` und `CODEOWNERS`

Warum jetzt: Jedes Pin-Update war in dieser Sitzung Handarbeit. Dependabot
soll die Digests in `Dockerfile` und `compose.yaml` künftig als PR vorschlagen;
der neue Job `Container & nginx` prüft diese PRs dann automatisch.

Bausteine:

1. `dependabot.yml` additiv um das `docker`-Ökosystem erweitern (bestehende
   Blöcke unangetastet, Commit-Präfix `chore` mit `include: scope`)
2. `CODEOWNERS` um `Dockerfile`, `.dockerignore`, `compose.yaml`, `nginx.conf`,
   `CLAUDE.md` und `.claude/` ergänzen
3. Struktur der geänderten YAML-Datei maschinell prüfen und kontrollieren, dass
   die Checks im PR wirklich gelaufen sind

## 3. 4b Teil 4, PR 3: PR-Titel-Check

Warum: Drei dokumentierte Fehl-Titel (#21, #25, #31). Der Hook aus dieser
Sitzung prüft nur Commits des Agenten; der PR-Titel wird beim Squash zum
Commit auf `main` und ist bisher ungeprüft. Muster wie in Gruppe 5 von
`Test-RepoState.ps1`. Rot-Beweis wieder über einen Wegwerf-PR.

## 4. 4b Teil 4, PR 4: Image-Scanner mit ADR

Warum zuletzt: Es ist eine Abhängigkeitsentscheidung und baut auf dem
Container-Job auf. Vorläufige Empfehlung aus dieser Sitzung: Grype als per
Digest gepinntes Container-Image. Vor der Entscheidung die Recherchelücken aus
Abschnitt 4 schließen und das ADR mit `/adr` anlegen.

Vor dem Scharfschalten zwei Beweise: Der Scanner sieht im chiseled-Image eine
Paketliste größer null, und er findet im alten Runtime-Digest vom August die
im September behobenen Lücken.

## 5. Kleine Entscheidungen

- `# syntax=docker/dockerfile:1` entfernen oder per Digest pinnen
- `Container & nginx` als Required Check ins Ruleset aufnehmen
- `Test-RepoState.ps1` nach `scripts/` aufnehmen und auf Beachtung der
  Groß-/Kleinschreibung umstellen

## 6. Vor oder in der Sitzung zu verstehen (vor Code)

- **Dependabot und gekoppelte Pins:** Dependabot hebt den Digest der
  Build-Stage an, ohne `global.json` anzufassen. Passt das SDK im neuen Image
  nicht zum Pin, wird der Container-Job rot. Das ist gewollt: Der Bot schlägt
  vor, die Pipeline urteilt, und die Kopplung wird von Hand im selben PR
  vervollständigt.
- **Script Injection über den PR-Titel:** Der Titel ist Text, den jeder
  Einreicher frei wählt. Wird er per `${{ ... }}` in ein `run:` eingesetzt,
  führt die Shell ihn als Code aus. Er gehört in eine Umgebungsvariable und
  wird in der Shell nur als Daten gelesen.
- **`pull_request` gegen `pull_request_target`:** Der zweite Auslöser läuft mit
  den Rechten des Ziel-Repositories und ist für Fork-PRs gefährlich. Für einen
  Titel-Check genügt `pull_request` mit lesenden Rechten.
- **Was ein Image-Scanner prüft:** Paketmetadaten der Image-Schichten gegen
  CVE-Datenbanken, keinen Anwendungscode. Ein Scan nur zur Build-Zeit reicht
  nicht, weil ein unverändertes Image morgen eine bekannte Lücke haben kann –
  die drei veralteten Pins dieser Sitzung waren genau dieser Fall.
- **Schwellenwert:** Was passiert bei einem Fund ohne verfügbaren Fix? Zu
  streng blockiert Arbeit an nicht behebbaren Funden im Basis-Image; zu locker
  erzeugt einen Schalter, den niemand beachtet.

## 7. Optionale Vorbereitung

- Wegwerf-PRs #43 und #45 schließen, ihre Branches und die alten Branches auf
  GitHub löschen
- Den Projektauftrag als Datei unter `docs/` bereitstellen, damit die
  Regelnummern nachschlagbar sind
- Entscheiden, ob die GitHub-CLI `gh` installiert werden soll (Aufnahme-Prüfung)
- `Test-RepoState.ps1` ausführen; erwartet werden die drei bekannten
  Commit-Titel-Befunde
