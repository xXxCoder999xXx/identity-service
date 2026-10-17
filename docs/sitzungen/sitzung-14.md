# Sitzungsbericht Sitzung 14

**Datum:** 17.10.2026
**Phase:** Schritt 5 (CD), Teil A unverändert. Testplattform auf MTP v2 umgestellt (erster Schritt Richtung Phase 5 nach E-5-16); Threat-Modeling für den Staging-Server begonnen, nicht abgeschlossen
**Vorgänger:** sitzung-13.md (abgeschlossen 17.10.2026)

---

## 1. Erledigt

### 1.1 Sitzungsstart und Stand des Repositorys

Der Bericht 13 war bereits als #85 gemergt (`8e28c63`). Der lokale Branch
`docs/sitzung-13` hatte keinen Remote mehr (`[gone]`). Der offene Punkt
„Dieser Bericht ist noch nicht committet“ aus Bericht 13 ist damit erledigt.

Während der Sitzung meldete der Harness, `CLAUDE.md` habe sich geändert: Die
Regeln aus PR #82 standen scheinbar wieder doppelt darin. Ursache war keine
Änderung, sondern ein veralteter lokaler `main` (5 Commits hinter
`origin/main`, Stand vor #82). Nach `git pull --ff-only` war alles korrekt.

### 1.2 Pflichtrecherche zu den Test-Paketen (17.10.2026)

Quellen: nuget.org (Flat-Container, Registration, Katalog), GitHub Advisory
Database, Release Notes auf xunit.net, Microsoft Learn.

| Paket | Alt | Aktuell stabil | Herausgeber | Advisories |
|---|---|---|---|---|
| `xunit.v3` | 3.2.2 | 4.0.2 (09.10.2026) | jnewkirk, bradwilson | keine |
| `xunit.runner.visualstudio` | 4.0.1 | 4.0.1 | dieselben | keine |
| `Microsoft.NET.Test.Sdk` | 18.10.1 | 18.11.0 | Microsoft | keine |

- **Gegenprobe zur Advisory-Abfrage:** Die erste Kontrolle mit
  `System.Text.Json` lieferte scheinbar nichts. Ursache war ein Suchmuster,
  das die formatierte JSON-Antwort (`"ghsa_id": "…"` mit Leerzeichen) nicht
  traf. Nach der Korrektur kamen Funde (z. B. `GHSA-8g4q-xg66-9fp4`). Die
  leeren Antworten (HTTP 200, `[]`) für die drei Test-Pakete sind damit echt.
- **Release Notes gelesen:** 4.0.0 (MTP v1 entfällt, Reihenfolge in
  Schichten, Parallelisierungs-APIs veraltet, Altlasten entfernt), 4.0.1 (MTP
  2.4.0, Define `XUNIT_GENERATED_DISABLE_WARNINGS`, Markdown-Bericht), 4.0.2
  (MTP 2.5.1, Analyzer 2.2.0, Fix für nicht parallele Tests, die parallel
  liefen, Fix „Thread-Faktor 0 = unbegrenzt“). Unser Testcode (zwei `[Fact]`,
  nur `using Xunit;`) nutzt keine der betroffenen APIs.
- **Microsoft Learn:** Unter SDK 10 wird der MTP-Modus von `dotnet test` per
  `global.json` (`"test": { "runner": "Microsoft.Testing.Platform" }`)
  eingeschaltet; `--configuration` und `--no-build` bleiben gültig.
- OWASP und thehackernews.com wurden nicht eigens abgefragt (siehe Offene
  Punkte).

### 1.3 xUnit 4.0.2 auf Testplattform v2 (PR #86)

Branch `build/xunit-v3-mtp-v2`, vom aktuellen `main`. Option B gewählt
(E-5-20): nur noch MTP, VSTest-Pakete entfernt. Die Projekt-Ownerin arbeitet
mit Visual Studio 2026, das für xUnit-v3-Projekte den MTP-Test-Explorer
nutzt.

| Datei | Änderung |
|---|---|
| `Directory.Packages.props` | `xunit.v3` 3.2.2 → 4.0.2; `xunit.runner.visualstudio` und `Microsoft.NET.Test.Sdk` entfernt; Kommentar mit Begründung |
| `IdentityService.ArchitectureTests.csproj` | zwei `PackageReference` entfernt |
| `global.json` | Abschnitt `test.runner` = `Microsoft.Testing.Platform`; SDK-Pin unverändert |
| `tests/IdentityService.ArchitectureTests/packages.lock.json` | neu aufgelöst |
| `docs/adr/ADR-002-xunit-v3.md` | Nachtrag vom 17.10.2026 |

Lockfile-Diff, Paket für Paket geprüft:

- entfernt: `Microsoft.NET.Test.Sdk`, `xunit.runner.visualstudio`,
  `Microsoft.TestPlatform.ObjectModel`, `Microsoft.TestPlatform.TestHost`,
  `Microsoft.CodeCoverage`
- angehoben: Microsoft-Testing-Platform-Pakete 1.9.1 → 2.5.1,
  `xunit.analyzers` 1.27.0 → 2.2.0, `xunit.v3.*` 3.2.2 → 4.0.2
  (`*.mtp-v1` → `*.mtp-v2`)
- neu: `System.Security.AccessControl` 6.0.1, exakt gepinnt von
  `xunit.v3.runner.common`. Katalog: Herausgeber Microsoft, gelistet, keine
  Deprecation, keine Advisories

Die vier `src`-Lockfiles kamen beim Neuauflösen (`--force-evaluate`) nur mit
CRLF statt LF zurück, inhaltlich identisch; sie wurden zurückgesetzt.

Lokal verifiziert (Exit-Codes):

| Prüfung | Ergebnis |
|---|---|
| Restore `--locked-mode` / Build / Format / Test | 0 / 0 (0 Warnungen trotz Analyzer 2.2.0) / 0 / 0, 2 von 2 Tests |
| Fail-closed-Gegenprobe: `dotnet test … -- --filter-method "Gibt.Es.Nicht"` | Exit-Code 8, „gesamt: 0“, Lauf rot |
| `docker compose up --build -d`, `/health` über nginx | 200 |
| `docker compose exec api dotnet --list-runtimes` | `Microsoft.AspNetCore.App 10.0.13`, `Microsoft.NETCore.App 10.0.13` |
| `git grep` nach Restverweisen auf die alten Pakete (außer Berichte, ADRs, Lockfiles) | nur der neue Begründungskommentar |

`ci.yml` blieb unverändert. Commit `cf1106b`, signiert (lokal `%G?` = `U`,
GitHub: `verified: true, valid`).

CI an #86: alle sechs Checks grün. Im Protokoll von `Build & Test` (Lauf
`39061659513`) steht die MTP-Ausgabe „Test run summary: Passed! total: 2,
succeeded: 2“. Von der Projekt-Ownerin gemergt (`038442a`).

### 1.4 Veröffentlichung nach #86

„Publish“ `39061869893` zu `038442a`: alle Schritte grün (Build, Zertifikate,
Stack, Smoke-Test, Scan, Anmeldung, Hochladen, Herkunftsnachweis, Stückliste,
Prüf-Gate mit Gegenprobe). CI `39061869849` und CodeQL `39061869860` auf
`main` ebenfalls grün.

### 1.5 Lokale Branches aufgeräumt

Gelöscht nach Prüfung gegen den Kopf-Commit des jeweils gemergten PR:
`build/bump-dotnet-10-0-13` (#83), `build/xunit-v3-mtp-v2` (#86),
`docs/sitzung-12` (#84), `docs/sitzung-13` (#85).
`docs/move-duplicate-rules` stand lokal auf `18a1f90`, der PR-Kopf von #82
war `db8e79f` (Branch auf GitHub nach #83 aktualisiert). Datei für Datei
verglichen: Inhalt identisch mit dem Squash-Merge `54edf38`, dann gelöscht.
Lokal existiert nur noch `main` (`038442a`).

### 1.6 Threat-Modeling Staging-Server: erster Entwurf

Systemmodell, Vertrauensgrenzen, STRIDE-Tabelle und drei Entscheidungen
wurden als Entwurf vorgelegt. Die Projekt-Ownerin hat noch nicht
geantwortet; nichts davon ist entschieden. Der vollständige Entwurf steht in
der Roadmap, Punkt 1.

---

## 2. Gelernt

- Ein veralteter lokaler `main` kann so aussehen, als habe jemand Dateien
  geändert. Vor einem Urteil über „geänderte“ Dateien zuerst prüfen, ob der
  Branch hinter dem Remote liegt.
- Eine leere Antwort einer Prüfabfrage ist erst aussagekräftig, wenn eine
  Gegenprobe mit einem bekannten Treffer etwas findet. Hier lag der Fehler im
  eigenen Suchmuster, nicht in der Datenquelle.
- `xunit.v3` 4.x läuft nur auf MTP v2, und MTP v2 lässt sich unter SDK 10
  nicht mehr im VSTest-Modus von `dotnet test` ausführen. Der Modus wird in
  `global.json` gewählt.
- Bei MTP ist das Testprojekt selbst das Programm. Adapter
  (`xunit.runner.visualstudio`) und Vermittler (`Microsoft.NET.Test.Sdk`)
  entfallen, und mit ihnen drei transitive Pakete.
- MTP beendet einen Lauf ohne ausgeführten Test mit Exit-Code 8. Das ist fail
  closed: Ein Testprojekt, das nichts findet, wird rot.
- `XUNIT_GENERATED_DISABLE_WARNINGS` schaltet Warnungen im generierten Code
  pauschal ab. So ein Schalter wäre ein abgeschwächtes Gate.
- „0 bedeutet unbegrenzt“ (Thread-Fix in xUnit 4.0.2) ist dasselbe
  Fail-open-Muster wie leere `KnownNetworks`.
- `dotnet restore --force-evaluate` kann Lockfiles mit anderen Zeilenenden
  schreiben, ohne dass sich der Inhalt ändert. Vor dem Commit den echten Diff
  prüfen.
- Squash-Merges machen `git branch -d` unbrauchbar. Ob ein lokaler Branch
  sicher gelöscht werden kann, zeigt der Vergleich mit dem Kopf-Commit des PR
  oder ein Inhaltsvergleich mit dem Squash-Commit.
- Pull-Deploy kehrt die Vertrauensrichtung nur für den Deploy um. Sobald der
  Server Ereignisse an GitHub meldet (DORA), braucht er selbst ein Token mit
  Schreibrecht.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-20** | `xunit.v3` 4.0.2 nur auf MTP v2; `xunit.runner.visualstudio` und `Microsoft.NET.Test.Sdk` entfernt; MTP-Modus per `global.json`; `XUNIT_GENERATED_DISABLE_WARNINGS` wird nicht genutzt (als Nachtrag in **ADR-002** dokumentiert) | Unterstützter Stand vor Test-first in Phase 5; ein Testweg statt zwei; weniger Lieferkette; Visual Studio 2026 kann MTP |
| **E-H-20** | Lokale Branches gemergter PRs werden nur nach Abgleich mit dem PR-Kopf-Commit oder nach Inhaltsvergleich mit dem Squash-Commit gelöscht | Squash-Merge macht die Git-eigene Prüfung (`branch -d`) blind; nichts ungeprüft verwerfen |

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- Threat-Modeling Staging-Server: drei Rückfragen an die Projekt-Ownerin
  offen (Roadmap, Punkt 1.5)
- Welcher GitHub-Token-Typ für GHCR **nur** Leserecht erlaubt, ist nicht aus
  der Primärquelle gelesen
- `Microsoft.Testing.Extensions.Telemetry` ist (wie schon in 1.9.1) transitiv
  enthalten. Ob und wohin MTP Telemetrie sendet und ob die CI sie per
  Umgebungsvariable abschalten soll, ist nicht geprüft
- Test-Explorer von Visual Studio 2026 mit dem neuen Stand nicht von der
  Projekt-Ownerin ausprobiert
- Die Runtime 10.0.13 ist am lokal gebauten Image gemessen (gleicher
  Basis-Digest), nicht am Image aus der Registry
- Recherche: OWASP und thehackernews.com wieder nicht eigens abgefragt
- Warum `ls docs/sitzungen/` in Sitzung 13 `sitzung-12.md` nicht anzeigte:
  vermutlich dieselbe Ursache wie 1.1 (Arbeitsverzeichnis auf altem Stand),
  nicht belegt

**Aus Sitzung 13, weiter offen**

- Nachtrag zu ADR-009: Grype meldet den Patch-Stand der .NET-Runtime
- Warum die sechs libc-Funde der Stufe Medium im Scan zu #83 fehlen
- Rot-Beweis für „Publish“ bei fehlschlagendem Smoke-Test
- Der Lauf von „Publish“ zu `a414d8e` (#81) ist rot; für diesen Commit liegt
  gewollt kein Image in der Registry
- Server-Fragen (GHCR privat/öffentlich, Domain): jetzt Teil des
  Threat-Modelings

**Aus Sitzung 12 und früher, weiter offen**

- Skill-Schritte 2 und 3 (E-H-14), zurückgestellt (E-H-19)
- Ob `disable-model-invocation` in der eingesetzten Claude-Code-Version wirkt
- Warum Dependabot #78 mit „no longer updatable“ schloss; Bot-Titel ohne
  `(deps)` bei #77
- Nachtrag zu ADR-005 (Wartefrist, Lücke bei Container-Images); ADR-006 und
  ADR-008 nachschreiben
- „Publish“ ist kein Pflicht-Check; Aufräumregel für die Registry fehlt
- Ob Dependabot den Pin von `actions/attest` pflegt; Version von `gh` auf dem
  Runner nicht festgelegt
- Wegwerf-Zertifikate der Pipeline weichen von den lokalen ab;
  `scripts/invoke-image-scan.sh` läuft lokal nicht (`jq` fehlt)
- `nginx.conf` ohne `limit_req_status` und `proxy_ssl_verify_depth`;
  Gegentest zu `proxy_ssl_verify` fehlt
- Projektauftrag und `Test-RepoState.ps1` nicht im Repository; veralteter
  Kommentar zum Locked Mode in `Directory.Build.props`; `README.md` ohne
  Befehle; `sitzung-01.md` fehlt
- HSTS bewusst auf `max-age=300`
- Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches“ nicht eingeschaltet
- Dieser Bericht ist noch nicht committet

**Bekannte Grenzen**

- Der Herkunftsnachweis liegt in einem öffentlichen, unveränderlichen
  Protokoll
- Bei Container-Images wendet Dependabot keine Wartefrist an

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD): Teil A fertig, Prüf-Gate mit Gegenproben belegt.
Die Testplattform ist auf dem unterstützten Stand. Es fehlen:

- Threat-Modeling und ADR-011 (begonnen)
- Staging-Server
- Pull-Deploy mit Gate auf dem Server
- Freigabe vor dem Deploy
- DORA-Events

| Thema | Status |
|---|---|
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher, unverändert |
| **DAST** (OWASP ZAP) | Wird mit dem ersten Staging-Deploy fällig (Plan: Sitzung 18); eine Domain mit echtem Zertifikat macht ihn realistischer |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Lieferketten-Gate** | Durchlaufen: Test-Pakete geprüft, Lockfile-Diff einzeln verifiziert, ein neues transitives Paket geprüft |
| **Agentic-Gate 6.5** | Nicht ausgelöst |
| **Contract Testing, Mutation Testing, k6, LLM-Gate 6.4** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

**Versionen, am 17.10.2026 gegen nuget.org aufgelöst:**

```
xunit.v3                            4.0.2   (direkt)
Microsoft.Testing.Platform          2.5.1   (transitiv)
xunit.analyzers                     2.2.0   (transitiv)
System.Security.AccessControl       6.0.1   (transitiv, exakt gepinnt)
```

Die Pins aus `sitzung-13.md` (SDK 10.0.402, Runtime 10.0.13, Digests,
`codeql-action` v4.38.3) gelten unverändert; nginx, Grype und
`actions/attest` weiterhin Stand `sitzung-11.md`.

**Läufe dieser Sitzung:**

```
39061659513  CI an #86 (Build & Test, Container & nginx, Image-Scan), grün
39061659520  CodeQL an #86, grün
39061659415  PR-Titel an #86, grün
39061869893  Publish 038442a (#86), alle Schritte grün
39061869849  CI auf main zu 038442a, grün
39061869860  CodeQL auf main zu 038442a, grün
```

**Nützliche Befehle:**

- Fail-closed-Gegenprobe der Testplattform:
  `dotnet test --configuration Release --no-build -- --filter-method "Gibt.Es.Nicht"`
  (erwartet Exit-Code 8)
- Runtime im laufenden Container:
  `docker compose exec api dotnet --list-runtimes`
- Advisories eines NuGet-Pakets:
  `https://api.github.com/advisories?ecosystem=nuget&affects=<Paket>`; beim
  Auswerten Leerzeichen nach dem Doppelpunkt im JSON beachten
- Versionen eines Pakets:
  `https://api.nuget.org/v3-flatcontainer/<paket-kleingeschrieben>/index.json`
- Signaturstatus auf GitHub:
  `gh api repos/<owner>/<repo>/commits/<sha> --jq '.commit.verification'`

**Fallstricke, die Zeit gekostet haben:**

- Veralteter lokaler `main` täuschte eine geänderte `CLAUDE.md` vor
- `dotnet restore --force-evaluate` schrieb unveränderte Lockfiles mit CRLF
- Ein Suchmuster ohne Leerzeichen-Toleranz ließ eine Advisory-Abfrage blind
  erscheinen

---

# Roadmap Sitzung 15

## 1. Threat-Modeling für den Staging-Server fortsetzen (zuerst)

Warum zuerst: Nichts wird bestellt, bevor feststeht, wogegen der Server
geschützt werden muss. Der Entwurf aus Sitzung 14 liegt vollständig vor; die
Sitzung beginnt mit den drei Rückfragen unter 1.5. Die Pflichtrecherche nach
CVEs folgt, sobald konkrete Werkzeuge für den Server gewählt werden
(Betriebssystem-Image, Prüfwerkzeug für den Nachweis); für das Modell selbst
ist sie nicht nötig.

**Methode (STRIDE):** System als Datenflüsse aufzeichnen, Vertrauensgrenzen
markieren (wo Daten von „weniger vertraut“ nach „mehr vertraut“ fließen), an
jeder Grenze die sechs Fragen stellen. Jede Antwort wird eine Maßnahme oder
ein bewusst akzeptiertes Risiko.

### 1.1 Systemmodell (Entwurf, von der Projekt-Ownerin zu bestätigen)

```
 [Du] --SSH:22--> |  netcup VPS (Wien)                     |
                  |   Deploy-Agent --pull--> GHCR          | --> HTTPS ausgehend
 [netcup-Konto]-->|   (Konsole, Rescue)   --verify--> Sigstore/GitHub
                  |   nginx:443 --> api (internes Netz)    |
 [Internet] -443->|   OS-Updates <-- Ubuntu-Mirror         |
                  |   (DORA-Events --> GitHub ?)           |
```

### 1.2 Vertrauensgrenzen

1. Internet → nginx
2. Projekt-Ownerin → SSH
3. netcup-Konto → Server (Konsole und Rescue-System umgehen SSH; wird oft
   übersehen)
4. Registry und Sigstore → Server (beim Pull)
5. Server → GitHub (falls der Server DORA-Events meldet)

### 1.3 STRIDE, erste Fassung

| | Bedrohung („Als Angreifer möchte ich …“) | Vorgeschlagene Maßnahme |
|---|---|---|
| **S** Spoofing | … mich per SSH als Admin anmelden | nur SSH-Schlüssel (ed25519), kein Passwort, kein Root-Login |
| | … dem Server ein fremdes Image unterschieben | Deploy nur nach Prüfung des Herkunftsnachweises: Repository, `refs/heads/main`, `publish.yml` (wie das Prüf-Gate in der CI) |
| | … das netcup-Konto übernehmen (Konsole, Rescue-System umgehen SSH) | 2FA am netcup-Konto, eigenes Passwort |
| **T** Tampering | … ein Image nach der Prüfung austauschen | per **Digest** prüfen und per Digest starten, nie per Tag |
| | … die Konfiguration auf dem Server ändern | Dateirechte, eigener Benutzer ohne Login für den Deploy-Agenten |
| **R** Repudiation | … unbemerkt deployen oder mich anmelden | Logs für Deploys (mit Digest und Zeit) und SSH-Anmeldungen; DORA-Events als zweite Spur |
| **I** Information Disclosure | … das GHCR-Token vom Server stehlen | nur Leserecht, Ablaufdatum, Dateirechte `600`; oder kein Token (Entscheidung 1) |
| | … Interna über offene Ports sehen | Firewall: nur 443 öffentlich (dazu 80 für ACME), 22 nach Möglichkeit eingeschränkt |
| **D** Denial of Service | … den Dienst lahmlegen | Rate Limit in nginx (vorhanden), Ressourcengrenzen in Compose; der Rest wird für Staging **als Risiko akzeptiert** (Vorschlag) |
| **E** Elevation of Privilege | … aus dem Container auf den Host ausbrechen | Container ohne Root (chiseled, nginx-unprivileged), `no-new-privileges`, Docker-Socket nie in einen Container |
| | … über eine bekannte Lücke im OS Root werden | automatische Sicherheitsupdates, Neustart-Fenster |

### 1.4 Drei Entscheidungen mit Zielkonflikt

**Entscheidung 1: GHCR privat lassen oder öffentlich machen**

| | Privat + Lese-Token | Öffentlich |
|---|---|---|
| Geheimnis auf dem Server | ja, ein langlebiges Token (Widerspruch zu „keine langlebigen Secrets“) | keins |
| Umkehrbar | ja | **nein** (bei GitHub endgültig) |
| Was sichtbar wird | nichts | das Image: Aufbau und Abhängigkeiten, keine Secrets (laut Regel) |

Empfehlung: **privat**, mit einem Token nur zum Lesen und kurzem
Ablaufdatum, Rotation als Termin. Begründung: Was sich nicht umkehren lässt,
entscheidet man nicht für Staging. Das Repository ist öffentlich (ADR-004),
ein öffentliches Image wäre aber ein eigener Schritt ohne Rückweg. Vor der
Festlegung aus der Primärquelle klären, welcher Token-Typ für GHCR nur
Leserecht erlaubt.

**Entscheidung 2: Domain kaufen (rund 1 € pro Monat)**

Mit Domain: echtes Zertifikat von Let's Encrypt, HSTS und DAST testen
realistisch, keine Browser-Warnung. Ohne Domain: selbstsigniertes Zertifikat
für eine IP-Adresse, jeder Test braucht `-k`. Das gewöhnt an
Zertifikatswarnungen, ein Anti-Pattern. Empfehlung: **Domain kaufen**.

**Entscheidung 3: DORA-Events vom Server (für Sitzung 18, jetzt nur
vormerken)**

Pull-Deploy heißt: GitHub hat keinen Zugang zum Server. Meldet der Server
aber Deploys an GitHub, braucht **er** ein Token mit Schreibrecht, und die
Vertrauensrichtung kehrt sich teilweise wieder um. Wege: ein eng begrenztes
Token nur für Deployment-Status, oder der Server schreibt die Events nur
lokal ins Log und ausgewertet wird anders. ADR-011 darf die Pull-Richtung
deshalb nicht absolut formulieren.

### 1.5 Rückfragen an die Projekt-Ownerin (Einstieg der Sitzung)

1. Stimmt das Systemmodell? Fehlt ein Zugang (z. B. Monitoring-Dienst,
   Backups)?
2. Fehlen Bedrohungen in der Tabelle, oder ist ein Risiko anders zu bewerten
   (insbesondere DoS als akzeptiert)?
3. Entscheidungen 1 und 2: Den Empfehlungen folgen (GHCR privat, Domain
   kaufen)?

## 2. ADR-011: Staging-Ziel und Pull-Deploy

Warum: Die Entscheidungen E-5-16 und E-5-17 und das Ergebnis des
Threat-Modelings sollen dauerhaft begründet sein, bevor bestellt wird.

- Mit `/adr` nach Freigabe
- Inhalt: netcup VPS Wien (Vorgaben Österreich, ≤ 15 €/Monat, jederzeit
  kündbar, Lernziel), Pull-Deploy mit Prüfung des Nachweises auf dem Server,
  Härtungsliste aus der STRIDE-Tabelle, Entscheidungen 1 bis 3, akzeptierte
  Risiken
- Danach bestellt die Projekt-Ownerin; Preis und Laufzeit im Bestellvorgang
  prüfen

## 3. Folgende Sitzungen bis Phase 5 (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 16 | Server einrichten und härten (Härtungsliste aus ADR-011) |
| 17 | Pull-Deploy mit Prüfung des Nachweises; Gegentest mit fremdem Image |
| 18 | Freigabe vor dem Deploy, DORA-Events (Entscheidung 3); DAST wird fällig |
| ab 18/19 | Phase 5: STRIDE, erster Use Case test-first |

## 4. Kleine Nachträge (wenn Zeit bleibt)

- Telemetrie der Testplattform prüfen (`Microsoft.Testing.Extensions.Telemetry`):
  Was wird gesendet, Abschalten in der CI?
- Nachtrag zu ADR-009: Grype meldet den Patch-Stand der .NET-Runtime
- Nachtrag zu ADR-005; ADR-006 (Signaturen), ADR-008 (`rollForward: disable`)

## 5. Vor oder in der Sitzung zu verstehen (vor Code)

- **Vertrauensgrenze:** Eine Stelle, an der Daten oder Befehle von einer
  weniger vertrauten Seite in eine vertrautere kommen. Genau dort entstehen
  die meisten Bedrohungen, deshalb wird STRIDE an jeder Grenze einzeln
  angewendet.
- **Prüfen per Digest statt per Tag:** Ein Tag ist ein beweglicher Zeiger,
  ein Digest ist der Fingerabdruck des Inhalts. Wer per Tag prüft und per Tag
  startet, kann dazwischen ein anderes Image bekommen (Time-of-Check vs.
  Time-of-Use).
- **Akzeptiertes Risiko:** Nicht jede Bedrohung braucht eine Maßnahme. Ein
  bewusst und schriftlich akzeptiertes Risiko (z. B. DoS auf Staging) ist eine
  Entscheidung; ein übersehenes ist eine Lücke.

## 6. Optionale Vorbereitung

- Systemmodell und STRIDE-Tabelle (Punkt 1) lesen und die drei Rückfragen
  vorab beantworten
- netcup-Angebot ansehen: Preis, Laufzeit, Kündigungsfrist, 2FA für das
  Kundenkonto
- „Automatically delete head branches“ einschalten
- Das Ablaufdatum des Tokens (06.11.2026) vormerken
