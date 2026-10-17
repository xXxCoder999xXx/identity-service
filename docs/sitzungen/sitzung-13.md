# Sitzungsbericht Sitzung 13

**Datum:** 17.10.2026
**Phase:** Schritt 5 (CD), Teil A unverändert. Grundsatzentscheidung gefallen: Schritt 5 wird vollendet, bevor Phase 5 beginnt (E-5-16). Dazu ein Sicherheits-Update auf .NET 10.0.13
**Vorgänger:** sitzung-12.md (abgeschlossen 16.10.2026)

---

## 1. Erledigt

### 1.1 Ladetest der Regeldateien bestanden, Regeln verschoben (PR #82)

In einer frischen Sitzung auf `docs/move-duplicate-rules` per Read geöffnet:

| Geöffnete Datei | Geladene Regeldateien |
|---|---|
| `scripts/invoke-image-scan.sh` | `skripte.md`, `lieferkette-und-ci.md` |
| `Directory.Build.props` | `lieferkette-und-ci.md` |

Damit ist der Fehlschlag aus Sitzung 12 aufgeklärt: Die Messung im selben
Gespräch, in dem die Dateien bearbeitet wurden, war nicht aussagekräftig. Auch
der offene Punkt aus Sitzung 11 ist belegt: Der `paths`-Eintrag `scripts/*.sh`
greift.

Beim Diff fiel eine Lücke auf. Der Satz aus `CLAUDE.md` §3 nannte
`TreatWarningsAsErrors`, Analyzer, NuGetAudit und Lockfiles. `dotnet-und-tests.md`
nannte dagegen nur `TargetFramework`, `Nullable` und `ImplicitUsings`. Nach
Freigabe der Projekt-Ownerin wurde die Zeile in `dotnet-und-tests.md` um die
fehlenden Einträge und den Hinweis „nie wiederholt (zweite Wahrheit)“ ergänzt.

PR #82 enthält `CLAUDE.md`, `lieferkette-und-ci.md`, neu `skripte.md` und
`dotnet-und-tests.md`. Alle sechs Checks liefen, nach dem Update von #83 grün.
Gemergt.

### 1.2 Pflichtrecherche (16.10.2026)

Quellen: Registry bzw. Primär-Repository.

- **.NET-Release vom 13.10.2026:** 10.0.13, `security: true`, 44 CVEs, SDK
  `10.0.402`. Die Werte sind direkt aus `releases.json` gelesen, nicht nur aus
  einer Zusammenfassung übernommen.
- **CISA KEV** (Katalog vom 15.10.2026, 1746 Einträge): keine der 44 CVEs ist
  enthalten.
- **Digests:** Die beweglichen Tags `sdk:10.0-noble` und
  `aspnet:10.0-noble-chiseled` zeigen auf dieselben Digests wie die
  Versions-Tags `10.0.402-noble` und `10.0.13-noble-chiseled`.
- **Läufe:** Die zeitgesteuerten Läufe vom 12.10.2026 waren grün (CI
  `38251805866`, CodeQL `38243644015`), ebenso alle Läufe von „Publish“ bis
  zum Sitzungsbeginn.
- **Dependabot:** `xunit.v3` 4.x wurde nicht erneut vorgeschlagen. Neu war
  PR #81 (`codeql-action` init und analyze, 4.38.2 → 4.38.3). Die Release
  Notes wurden gelesen. Die SHA `24c54180…` wurde per `git ls-remote` als
  gepeelter Tag `v4.38.3^{}` bestätigt. Alle Checks grün, von der
  Projekt-Ownerin gemergt (`a414d8e`).

### 1.3 Gate schlägt an: Image-Scan rot für Runtime 10.0.12

Der erste CI-Lauf an #82 brach im Pflicht-Check `Image-Scan` ab (Lauf
`38820154952`). Grype meldete 14 Funde der Stufe High oder Critical in
`Microsoft.NETCore.App.Runtime` und `Microsoft.AspNetCore.App.Runtime`
10.0.12, alle mit Fix in 10.0.13; zwei davon Critical. Bis zum Update konnte
kein PR gemergt werden.

Der Lauf von „Publish“ zum Merge von #81 (`38820291609`) scheiterte am
selben Gate:

| Schritt | Ergebnis |
|---|---|
| Build, Zertifikate, Stack, Smoke-Test | grün |
| Image scannen | rot |
| Anmeldung, Hochladen, beide Nachweise, Prüf-Gate | übersprungen |

Damit ist der Rot-Beweis aus Sitzung 10 für den Scan erbracht: „Publish“
bricht vor dem Hochladen ab, ein verwundbares Image erreicht die Registry
nicht.

### 1.4 Sicherheits-Update .NET 10.0.13 (PR #83)

Branch `build/bump-dotnet-10-0-13`, vom aktuellen `main` geschnitten.
Enthalten in einem PR:

| Datei | alt | neu |
|---|---|---|
| `global.json` | `10.0.401` | `10.0.402` |
| Dockerfile, Build-Stage | `sha256:e70cdb7f…` | `sha256:0d99ebf1…` |
| Dockerfile, Runtime-Stage | `sha256:48e51f2f…` | `sha256:84def277…` |

Verifiziert:

- Digests am 17.10.2026 erneut aufgelöst und unverändert.
- `git grep` außerhalb von Berichten und ADRs findet keinen alten Pin mehr.
- Lokal mit SDK 10.0.402: Restore `--locked-mode`, Build, Format und Test
  mit Exit-Code 0 (2 von 2 Tests).
- CI: alle sechs Checks grün. Im Protokoll von `Image-Scan` (Lauf
  `39055733688`): Blindheits-Schutz `Betriebssystem=ubuntu Systempakete=9
  Runtime-Paket=1`, „No vulnerabilities found“. Auch die sechs libc-Funde der
  Stufe Medium aus dem Lauf an #82 tauchen nicht mehr auf.
- „Publish“ zum Merge (`39055965866`): alle Schritte grün.

Gemergt (`9eedb47`).

### 1.5 Prüf-Gate von „Publish“ gelesen

Das war offen seit Sitzung 11. Gelesen wurden die Zeilen des Schritts
„Nachweise verifizieren“ im Lauf `39055965866`:

| Prüfung | Ergebnis |
|---|---|
| Herkunftsnachweis von GitHub und aus der Registry | Repository, `refs/heads/main`, `publish.yml@refs/heads/main`, Runner von GitHub |
| Stückliste (CycloneDX) | gleiche Bindung an Repository, Branch und Workflow |
| Gegenprobe: fremdes Image (nginx-Digest) | abgelehnt (HTTP 404, kein Nachweis) |
| Gegenprobe: eigenes Image, falscher Workflow (`ci.yml`) | abgelehnt |
| Gegenprobe: eigenes Image, falscher Branch | abgelehnt („expected … not-main, got main“) |

### 1.6 Bericht 12 nachgetragen (PR #84)

`sitzung-12.md` lag nur als unversionierte Datei im Arbeitsverzeichnis. Beim
Sitzungsstart zeigte `ls docs/sitzungen/` sie nicht an, deshalb startete
diese Sitzung zunächst auf `sitzung-11.md`. Die erledigten Punkte decken sich
mit Roadmap 13, Punkte 1 und 2. Der Bericht wurde unverändert auf eigenem
Branch `docs/sitzung-12` committet. Alle Checks grün, gemergt (`a5edc14`).

### 1.7 Grundsatzentscheidung: Phase 4 vollenden (E-5-16)

Besprochen wurden Weg A (Phase 4 vollenden) und ein Mittelweg (Phase 5
vorziehen, Deploy später, Feature Flags minimal, Abweichung per ADR).
Entschieden ist Weg A.

Die Vorgaben der Projekt-Ownerin für den Server gelten unverändert:

- Standort Österreich
- höchstens 15 € pro Monat
- jederzeit kündbar
- sie will dabei lernen

Kandidat ist ein netcup VPS in Wien. Deploy als **Pull**: Der Server holt das
Image selbst und startet es nur mit gültigem Herkunftsnachweis. GitHub braucht
dafür keinen Zugang zum Server. OIDC ist auf der GitHub-Seite durch
`publish.yml` bereits abgedeckt.

Schätzung bis zum ersten C#-Code: etwa Sitzung 18. Die Reihenfolge steht in
der Roadmap.

### 1.8 Veröffentlichung

Jeder Merge außer #81 löste einen grünen Lauf von „Publish“ aus: `39055965866`
(#83), `39056297156` (#82), `39057021638` (#84). In der Registry liegt damit
das Image mit SDK 10.0.402 und Runtime 10.0.13 samt beiden Nachweisen.

---

## 2. Gelernt

- Eine Messung, ob eine Regeldatei lädt, ist nur in einer frischen Sitzung
  aussagekräftig. Im Gespräch, in dem sie bearbeitet wurde, liefert der
  Harness sie nicht erneut mit.
- Ein Scan-Gate blockiert über Nacht jeden PR, sobald ein Sicherheits-Release
  erscheint, auch reine Doku-PRs. Das ist gewollt: Geprüft wird der Zustand
  des Image, nicht der Inhalt des PR.
- Grype erkennt die .NET-Runtime-Pakete im chiseled Image und meldet ihre
  GHSA-Einträge samt der Version mit dem Fix. Die Annahme aus ADR-009, kein
  Scanner melde den Patch-Stand der Runtime, ist überholt.
- Ein roter Pflicht-Lauf kann den geplanten Rot-Beweis ersetzen, wenn man ihn
  Schritt für Schritt liest: „übersprungen“ bei Hochladen und Nachweisen ist
  der Beleg.
- Ohne Funde druckt Grype keine Paketzeilen. Die installierte Version steht
  dann nicht im Protokoll und muss anders gemessen werden.
- Bei einem Sicherheits-Release wartet man nicht auf Dependabot. Sein
  wöchentlicher Lauf kann vor dem Release liegen, und gekoppelte Pins hebt er
  getrennt an.
- Microsoft Update kann ein SDK innerhalb des Feature-Bands ersetzen. Mit
  `rollForward: disable` baut der alte Pin lokal dann nicht mehr.
- Eine Zusammenfassung einer großen Datei durch ein Werkzeug ist eine
  Vermutung. Zahlen wie „44 CVEs“ werden an der Rohdatei nachgezählt.
- Der Commit-Hook liest den Betreff nur aus `-m`. Ein Heredoc mit `-F -` wird
  blockiert; Absätze kommen als weitere `-m`-Angaben.
- Pull-Deploy dreht die Vertrauensrichtung um: Das Ziel prüft und holt, die
  Pipeline braucht keinen Schlüssel zum Ziel.
- Ein Sitzungsbericht, der nicht committet ist, existiert für den nächsten
  Sitzungsstart nicht verlässlich.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-16** | Schritt 5 (CD) wird vollendet, bevor Phase 5 beginnt; löst die vertagte E-5-15 auf (**ADR-Kandidat**, zusammen mit ADR-011) | Plantreue. Das Prüf-Gate schützt erst, wenn ein Ziel es verlangt. Fachlogik vor Automatik war das Muster des Vorgängers |
| **E-5-17** | Staging-Ziel: netcup VPS in Wien, Deploy als Pull mit Prüfung des Herkunftsnachweises auf dem Server (vorgesehen, **ADR-011** nach dem Threat-Modeling) | Vorgaben Österreich, ≤ 15 €, kündbar. Pull braucht keinen Server-Zugang in GitHub |
| **E-5-18** | Das Sicherheits-Update wird selbst umgesetzt statt auf Dependabot zu warten: SDK-Pin, Build-Digest und Runtime-Digest in einem PR | 14 Funde High/Critical blockierten jeden PR. Ein Release, ein Thema. Der Bot hätte gekoppelte Pins getrennt |
| **E-5-19** | Weg A der Umsetzung (SDK und Runtime zusammen) statt nur des Runtime-Digests | Ein konsistenter Stand; das Build-SDK bleibt nicht auf einem Stand mit bekannten CVEs |
| **E-H-18** | Ein nie committeter Bericht wird unverändert auf eigenem Branch nachgetragen; spätere Erkenntnisse stehen im Folgebericht | Ein Bericht hält einen Stand fest, wie ein akzeptiertes ADR |
| **E-H-19** | Die Skills `/pflichtrecherche` und `/bot-pr-pruefen` (E-H-14, Schritt 2) werden hinter Phase 4 zurückgestellt | Sie liegen nicht auf dem Weg zum ersten Use Case |

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Nachtrag zu ADR-009:** Grype erkennt die .NET-Runtime-Pakete und meldet
  deren Patch-Stand. Die „bekannte Grenze“ aus den Berichten ist überholt
- Die Runtime-Version 10.0.13 im veröffentlichten Image ist nur indirekt
  belegt (Digest gleich Tag `10.0.13-noble-chiseled`, keine Funde,
  Blindheits-Schutz). Nicht gemessen ist `dotnet --list-runtimes` im Image
- `docker compose up --build` lief für #83 lokal nicht (Docker Desktop war
  aus). Das Urteil über das Image kam nur aus der CI
- Warum die sechs libc-Funde der Stufe Medium im Scan zu #83 fehlen, ist
  nicht nachgelesen (vermutlich neue Pakete im Basis-Image)
- Warum `ls docs/sitzungen/` beim Sitzungsstart `sitzung-12.md` nicht anzeigte,
  ist ungeklärt
- Rot-Beweis für „Publish“ bei fehlschlagendem Smoke-Test fehlt weiter; für
  den Scan ist er erbracht (Abschnitt 1.3)
- Der Lauf von „Publish“ zu `a414d8e` (#81) ist rot. Für diesen Commit liegt
  kein Image in der Registry; das ist gewollt, aber nicht vermerkt außer hier
- Recherche: OWASP und thehackernews.com wurden nicht eigens abgefragt, CISA
  KEV schon
- Offene Fragen zum Server: GHCR-Paket privat lassen (Lese-Token auf dem
  Server) oder öffentlich machen (bei GitHub nicht umkehrbar); Domain für
  echtes TLS (rund 1 € pro Monat)
- Lokale Branches gemergter PRs: `build/bump-dotnet-10-0-13`,
  `docs/move-duplicate-rules`, `docs/sitzung-12`. Löschen nach
  Inhaltsvergleich mit `main` und auf Zuruf
- Dieser Bericht ist noch nicht committet

**Aus Sitzung 12, weiter offen**

- Skill-Schritte 2 und 3 (E-H-14), jetzt zurückgestellt (E-H-19)
- Ob `disable-model-invocation` in der eingesetzten Claude-Code-Version
  wirkt, ist nicht geprüft

**Aus Sitzung 11 und früher, weiter offen**

- `xunit.v3` steht auf 3.2.2 (Testplattform v1, ohne Unterstützung des
  Herausgebers)
- Warum Dependabot #78 mit „no longer updatable“ schloss; Bot-Titel
  `chore: Bump …` ohne `(deps)` bei #77 (bei #81 wieder `chore(deps): Bump …`)
- Nachtrag zu ADR-005 (Wartefrist, Lücke bei Container-Images); ADR-006 und
  ADR-008 nachschreiben
- „Publish“ ist kein Pflicht-Check; Aufräumregel für die Registry fehlt
- Ob Dependabot den Pin von `actions/attest` pflegt, ist unbelegt; Version von
  `gh` auf dem Runner nicht festgelegt
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

**Bekannte Grenzen**

- Der Herkunftsnachweis liegt in einem öffentlichen, unveränderlichen
  Protokoll
- Bei Container-Images wendet Dependabot keine Wartefrist an

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD): Teil A fertig, und das Prüf-Gate ist mit
Gegenproben gelesen. Es fehlen weiterhin:

- Staging-Server
- Pull-Deploy mit Gate auf dem Server
- Freigabe vor dem Deploy
- DORA-Events

Die Reihenfolge ist entschieden (E-5-16): erst Schritt 5 vollenden, dann
Phase 5.

| Thema | Status |
|---|---|
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher, unverändert |
| **DAST** (OWASP ZAP) | Wird mit dem ersten Staging-Deploy fällig (Plan: Sitzung 18) |
| **Feature Flags** | Durch E-5-16 nicht fällig: Phase 5 beginnt erst nach dem Deploy |
| **Lieferketten-Gate** | Durchlaufen: Bot-PR #81 geprüft (Release Notes, SHA); Scan-Gate blockierte 10.0.12 |
| **Agentic-Gate 6.5** | Nicht ausgelöst |
| **Contract Testing, Mutation Testing, k6, LLM-Gate 6.4** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

**Pins, am 16. und 17.10.2026 gegen Registry bzw. Primär-Repository
geprüft:**

```
mcr.microsoft.com/dotnet/sdk:10.0-noble            (= 10.0.402-noble)
  sha256:0d99ebf1ccad15037b5c98c9fe8979d6b8dbac23812feae2277a0b277b5c5ffa
mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled (= 10.0.13-noble-chiseled)
  sha256:84def277556c2843a44fdeefbd3145d0a2e32d8f736d0c1a7b0a96b2880b0187
github/codeql-action v4.38.3
  24c54180a607b1449ed407dd24f251e4e9147c8d
SDK 10.0.402 (Runtime 10.0.13)
```

Die Pins von nginx (`1.30.5`), Grype (`v0.120.1`) und `actions/attest`
(`v4.2.2`) wurden in dieser Sitzung nicht neu aufgelöst; es gilt der Stand
aus `sitzung-11.md`.

**Lokales SDK:** installiert sind `10.0.303` und `10.0.402`; `10.0.401` ist
nicht mehr vorhanden.

**Läufe dieser Sitzung:**

```
38820154952  CI an #82, Image-Scan rot (Runtime 10.0.12)
38820291609  Publish a414d8e (#81), rot im Scan, Hochladen übersprungen
39055733688  CI an #83, alle grün
39055965866  Publish 9eedb47 (#83), grün, Prüf-Gate gelesen
39056297156  Publish 54edf38 (#82), grün
39057021638  Publish a5edc14 (#84), grün
```

**Nützliche Befehle:**

- Release-Metadaten ohne `jq` auswerten (PowerShell):
  `Invoke-RestMethod https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json`,
  dann `.releases[0].'cve-list'`
- CISA KEV:
  `https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json`,
  Abgleich über `cveID`
- Schrittergebnisse eines Laufs:
  `gh run view <id> --json jobs --jq '.jobs[].steps[] | "\(.conclusion)\t\(.name)"'`
- Auf Checks warten: `gh pr checks <nr> --watch --interval 20`

**Fallstricke, die Zeit gekostet haben:**

- Der Commit-Hook blockiert `git commit -F -`. Betreff und Absätze als
  mehrere `-m` übergeben
- `git switch -c <branch> origin/main` setzt `origin/main` als Upstream;
  `--no-track` verwenden
- Docker Desktop läuft nicht immer; vor einem Image-Test `docker info`
  prüfen

---

# Roadmap Sitzung 14

## 1. xUnit-Umstellung auf die Testplattform v2 (zuerst)

Warum zuerst: Nach E-5-16 ist sie der erste Schritt auf dem Weg zu Phase 5.
Sie hängt nicht vom Server ab, und `xunit.v3` 3.2.2 hängt an der
Testplattform v1, die der Herausgeber nicht mehr unterstützt. Test-first in
Phase 5 soll auf dem unterstützten Stand beginnen.

1. Kurze Pflichtrecherche: Release Notes von `xunit.v3` 4.x, neue
   Sicherheitsmeldungen zu den Test-Paketen
2. Aus der Primärquelle lesen, was `global.json` und das Testprojekt für
   `xunit.v3` 4.x auf dem SDK 10 brauchen, und ob `xunit.runner.visualstudio`
   und `Microsoft.NET.Test.Sdk` dann noch nötig sind. Fällt ein Paket weg,
   sinkt die Last in der Lieferkette
3. Optionen mit Trade-offs; prüfen, ob `dotnet test --configuration Release
   --no-build` unverändert bleibt (Urteils-Hierarchie)
4. Ein atomarer PR: Paketversion, Lockfiles, `global.json`, gegebenenfalls
   Testprojekt und `ci.yml`. `global.json` wird ins Image kopiert, deshalb
   urteilt `Container & nginx` mit
5. Nachtrag zu ADR-002

## 2. Threat-Modeling für den Staging-Server und ADR-011

Warum: Nichts wird bestellt, bevor feststeht, wogegen der Server geschützt
werden muss.

- STRIDE für den Server: SSH, offene Ports, Updates, Token für GHCR,
  Pull-Deploy, Logs
- Entscheidungen: GHCR privat oder öffentlich, Domain, Härtungsliste
- ADR-011 (Staging-Ziel und Pull-Deploy, mit E-5-16 und E-5-17)
- Danach bestellt die Projekt-Ownerin; Preis und Laufzeit im Bestellvorgang
  prüfen

## 3. Folgende Sitzungen bis Phase 5 (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 16 | Server einrichten und härten |
| 17 | Pull-Deploy mit Prüfung des Nachweises; Gegentest mit fremdem Image |
| 18 | Freigabe vor dem Deploy, DORA-Events; DAST wird fällig |
| ab 18/19 | Phase 5: STRIDE, erster Use Case test-first |

## 4. Kleine Nachträge (wenn Zeit bleibt)

- Nachtrag zu ADR-009: Grype meldet den Patch-Stand der .NET-Runtime
- Nachtrag zu ADR-005: Wartefrist und Lücke bei Container-Images
- ADR-006 (Signaturen), ADR-008 (`rollForward: disable`), dabei die
  Erfahrung mit dem ersetzten lokalen SDK
- Lokale Branches gemergter PRs aufräumen

## 5. Vor oder in der Sitzung zu verstehen (vor Code)

- **Zwei Testplattformen in .NET:** VSTest ist der alte Weg; `dotnet test`
  startet die Tests über einen Adapter. Bei der Microsoft Testing Platform
  ist das Testprojekt selbst ein ausführbares Programm. Mit dem SDK 10 muss
  man sich für den neuen Weg ausdrücklich entscheiden, sonst bricht
  `xunit.v3` 4.x ab.
- **Pull-Deploy:** Der Server fragt die Registry nach einem neuen Image,
  prüft dessen Herkunftsnachweis und startet es nur bei Erfolg. Die Pipeline
  braucht keinen Zugang zum Server; das Gate sitzt beim Ziel.
- **Threat-Modeling mit STRIDE:** Sechs Fragen an ein System: Kann jemand
  sich als jemand anderes ausgeben, Daten verändern, Taten abstreiten, Daten
  lesen, den Dienst lahmlegen, sich mehr Rechte holen? Jede Antwort wird eine
  Maßnahme oder ein bewusst akzeptiertes Risiko.

## 6. Optionale Vorbereitung

- Die Seite „Testing with dotnet test“ der xUnit-Dokumentation überfliegen
- Überlegen: Domain kaufen (rund 1 € pro Monat) und GHCR privat oder
  öffentlich
- Docker Desktop vor der Sitzung starten
- „Automatically delete head branches“ einschalten
- Das Ablaufdatum des Tokens (06.11.2026) vormerken
