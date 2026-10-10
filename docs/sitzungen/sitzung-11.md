# Sitzungsbericht Sitzung 11

**Datum:** 10.10.2026
**Phase:** Schritt 5 (CD), Teil A unverändert – diese Sitzung hat Dokumentation und ADRs an den Stand nach Teil A angeglichen; die Grundsatzentscheidung zum Deploy ist vertagt
**Vorgänger:** sitzung-10.md (abgeschlossen 08.10.2026)

---

## 1. Erledigt

### 1.1 Pflichtrecherche und Blick auf die Automatik (teilweise)

Am 10.10.2026 aus Registry bzw. Primär-Repository geprüft:

- SDK-Pin `10.0.401` ist aktuell: Neueste Version laut den Release-Metadaten
  von Microsoft ist 10.0.12 vom 08.09.2026 mit SDK `10.0.401`.
- Die vier Image-Digests (Build-Image, Runtime-Image, nginx, Grype) sind
  identisch mit den Pins. `1.30.5` ist der neueste Tag des nginx-Zweigs 1.30
  (05.10.2026), Grype `v0.120.1` die neueste Version (06.10.2026).
- `actions/attest` `v4.2.2` ist die neueste Version; der Tag zeigt weiter auf
  den gepinnten SHA.
- Sicherheitslage: für .NET im Oktober nichts Neues gemeldet. Im September
  wurden zwei kompromittierte Actions von `actions-cool` wieder freigeschaltet;
  das Projekt nutzt sie nicht (in den Workflows stehen nur `actions/checkout`,
  `actions/setup-dotnet`, `actions/attest`, `github/codeql-action`, alle per
  SHA).

Nicht möglich, weil die Termine nach der Sitzung liegen: Patch Tuesday
(13.10.2026) und der erste zeitgesteuerte Lauf von CodeQL und CI (12.10.2026).

### 1.2 Dokumentation an den Stand nach Schritt 5 angepasst (PR #74)

- `CLAUDE.md` Abschnitt 3: `scripts/` enthält PowerShell (lokale Werkzeuge)
  und Bash (von CI und Veröffentlichung geteilte Schritte); die drei Workflows
  sind genannt.
- `CLAUDE.md` Abschnitt 4: Regel für Wegwerf-PRs (nur nach ausdrücklicher
  Freigabe, als Entwurf, sofort schließen, nie mergen; Rot-Beweis vor dem
  Merge).
- `CLAUDE.md` Abschnitt 7: Die Skript-Regel unterscheidet PowerShell 5.1
  (lokal) und Bash (Runner, unterscheidbare Exit-Codes, `bash -n`).
- `.claude/rules/lieferkette-und-ci.md`: `scripts/*.sh` in der `paths`-Liste;
  Verweis auf ADR-009, ADR-010 und `publish.yml`; je ein Punkt zu `publish.yml`
  und zu den geteilten Skripten.
- `compose.scan.yaml`: Der Kopfkommentar verweist auf
  `bash scripts/invoke-image-scan.sh` statt auf den Aufruf von Hand, der
  Blindheits-Schutz und Gate überspringt.

Anlass: Die Regeldateien laden pfadgebunden, und `scripts/*.sh` stand in
keiner `paths`-Liste; bei einer Änderung an den Bash-Skripten lud keine Regel.

Verifiziert: `docker compose --file compose.scan.yaml config` mit Exit-Code 0,
`compose.scan.yaml` rein ASCII, der alte Aufruf steht außerhalb der Berichte
nur noch im Skript. Die Änderung an `CLAUDE.md` und `.claude/**` geschah nach
ausdrücklicher Freigabe der Projekt-Ownerin.

### 1.3 Nachtrag zu ADR-010 (PR #75)

Ein datierter Abschnitt „Nachtrag vom 08.10.2026" am Ende des ADR; der
akzeptierte Text darüber blieb unverändert. Inhalt: Das Paket in GHCR ist
privat (die Aussage „Das Image … wird öffentlich" gilt nur für den Nachweis),
das Prüf-Gate arbeitet mit `gh` auf dem Runner, das geschärfte Gate (E-5-7),
die Nachweise in der Registry (E-5-6), dazu die zwei weiter offenen Punkte.

### 1.4 ADR-005: Dependabot (PR #76)

Neu `docs/adr/ADR-005-dependabot-fuer-pin-updates.md` (akzeptiert): Dependabot
statt Renovate, fünf Ökosysteme, Gruppen nur bei nachgewiesener Kopplung,
`ignore`-Regel für nginx, kein Auto-Merge; mit den Befunden aus den Sitzungen
4, 9 und 10. Im selben PR: vier Kommentarzeilen im Kopf von
`.github/dependabot.yml` („ADR-005" statt „ADR-005-Kandidat", „fünf
Ökosysteme" statt „zwei").

Verifiziert: Jede geänderte Zeile in `dependabot.yml` beginnt mit `#`; ohne
Kommentarzeilen ist die Datei identisch mit der Fassung davor. Nach dem Merge
liefen die Dependabot-Jobs grün und ohne Hinweis auf eine ungültige
Konfiguration (Ansicht der Projekt-Ownerin unter „Insights" → „Dependency
graph" → „Dependabot").

### 1.5 ADR-007: chiseled Runtime-Image (PR #79)

Neu `docs/adr/ADR-007-chiseled-runtime-image.md` (akzeptiert). Messungen vom
10.10.2026, beide Images per Digest:

| | volles Image `10.0-noble` | chiseled (Pin) |
|---|---|---|
| `/bin/sh` starten | startet | scheitert: „no such file or directory" |
| `apt-get` | vorhanden | scheitert: „no such file or directory" |
| Nutzer | root (UID 0) | `1654` |
| Pakete | 97 (`dpkg-query`) | 9 (Scanner, Sitzung 9) |
| Größe komprimiert, `linux/amd64` | 91,4 MiB, 6 Schichten | 52,6 MiB, 5 Schichten |

Gegenprobe: `dotnet --list-runtimes` startet im chiseled Image und meldet die
Runtime 10.0.12. Die Größen stammen aus den Manifesten der Registry.

### 1.6 Bot-PRs von Dependabot (PR #77, #78)

Nach dem Merge von #76 öffnete Dependabot zwei PRs:

- **#77** `xunit.runner.visualstudio` 4.0.0 → 4.0.1 (Patch): alle Checks grün,
  von der Projekt-Ownerin gemergt.
- **#78** `xunit.v3` 3.2.2 → 4.0.2 (Major): `Build & Test` rot im Schritt
  „Tests" mit der Meldung „Testing with VSTest target is no longer supported
  by Microsoft.Testing.Platform on .NET 10 SDK and later". Das Lockfile im PR
  zeigt den Wechsel von `xunit.v3.mtp-v1` auf `xunit.v3.mtp-v2`; die Release
  Notes zu 4.0.0 nennen die Unterstützung der Testplattform v1 als eingestellt
  und verlangen für diese Meldung eine Anpassung an `global.json`. Nicht
  gemergt. Dependabot schloss den PR drei Minuten nach dem Merge von #77
  selbst („Looks like xunit.v3 is no longer updatable").

### 1.7 Veröffentlichung und Aufräumen

Jeder der fünf Merges löste „Publish" aus; alle fünf Läufe sind grün. In der
Registry liegen damit acht Images. Lokal existiert nur `main` und der Branch
dieses Berichts; auf GitHub gibt es keine offenen Pull Requests. Die Branches
der PRs dieser Sitzung hat die Projekt-Ownerin auf GitHub von Hand gelöscht.

---

## 2. Gelernt

- Regeln, die pfadgebunden laden, wirken nur für Pfade in ihrer Liste; eine
  neue Dateiart braucht einen neuen Eintrag, sonst gilt für sie still nichts
- Ein akzeptiertes ADR wird nicht umgeschrieben, sondern um einen datierten
  Nachtrag ergänzt: So bleibt sichtbar, was Annahme war und was Messung
- Pin und Update-Bot sind zwei Hälften einer Maßnahme: Der Pin verhindert
  Bewegung von selbst, der Bot verhindert stilles Veralten
- Ein Major-Update kündigt an, dass etwas bricht; der Bot hebt nur die Nummer,
  die nötige Umstellung kann er nicht
- Ein Bot-PR ist kein Merkzettel: Der Bot kann seinen Vorschlag selbst
  schließen, ohne dass das Problem gelöst ist
- Einen Konflikt in einem Bot-PR löst man nicht von Hand im Web-Editor; der
  Hash im Lockfile stimmt danach nicht mehr
- Fehlt ein Parser, lässt sich für eine reine Kommentaränderung ersatzweise
  zeigen, dass die Datei ohne Kommentarzeilen unverändert ist; für Änderungen
  an Schlüsseln reicht das nicht
- Zahlen aus zwei verschiedenen Zählungen sind eine Größenordnung, kein
  Vergleich
- Eine Gegenprobe gehört auch zu einer Messung: Erst der gelungene Start von
  `dotnet` zeigt, dass der Start der Shell an der fehlenden Datei scheitert
- Größe und Schichten eines Images lassen sich aus dem Manifest der Registry
  lesen, ohne das Image zu laden
- Dependabot wartet seit Juli 2026 standardmäßig drei Tage, bevor er ein
  Versions-Update vorschlägt; bei Container-Images greift das nicht, weil die
  Registry kein Veröffentlichungsdatum liefert
- Der Status eines ADR sagt, ob die Entscheidung gilt: „Vorgeschlagen" ist ein
  Entwurf, „Akzeptiert" ist beschlossen, „Abgelöst" ist Geschichte

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-10** | Bash-Skripte unter `scripts/` fallen unter die Regeldatei zur Lieferkette | Sie sind Pipeline-Schritte; ohne Eintrag lud für sie keine Regel |
| **E-5-11** | ADR-010 erhält einen datierten Nachtrag statt einer Korrektur im Text | Der akzeptierte Text bleibt der Stand der Entscheidung |
| **E-5-12** | ADR-005 erhält die seit Sitzung 2 vorgesehene Nummer, obwohl ADR-010 schon existiert | Die Nummer war reserviert; ADR-006 und ADR-008 bleiben offen |
| **E-5-13** | `xunit.v3` 4.x wird nicht über den Bot-PR übernommen; die Umstellung auf die Testplattform v2 wird ein eigener PR vor Phase 5 | Sie berührt `global.json` und den Testbefehl und braucht einen Nachtrag zu ADR-002 (ADR-Kandidat) |
| **E-5-14** | Kein `@dependabot ignore` für Major-Versionen per Kommentar | Der Bot merkt sich das außerhalb von `dependabot.yml`: eine zweite Wahrheit |
| **E-5-15** | Die Grundsatzentscheidung „Deploy vollenden oder Phase 5 vorziehen" ist vertagt | Die Projekt-Ownerin will sie in einer eigenen Sitzung besprechen |
| **E-H-12** | Die Regel für Wegwerf-PRs steht in `CLAUDE.md` Abschnitt 4 | Sie stand bisher nur im Gedächtnis des Agenten (E-H-11) |

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **`xunit.v3` steht auf 3.2.2** und damit auf der Testplattform v1, deren
  Unterstützung der Herausgeber eingestellt hat. Es gibt keinen offenen PR
  mehr dazu. Welche Einträge `global.json` und das Testprojekt für 4.x
  brauchen, ist noch nicht aus der Primärquelle gelesen
- Warum Dependabot #78 mit „no longer updatable" schloss, ist ungeklärt; ob er
  den Vorschlag erneut bringt, ebenfalls
- Der Titel von #77 lautet `chore: Bump …` ohne `(deps)` und mit großem „B";
  der frühere Bot-PR #16 hieß `chore(deps): bump …`. Der Check `PR-Titel` ließ
  es durch, so steht es auf `main`. Die Ursache ist ungeklärt
- Ob die Release Notes zu #77 vor dem Merge gelesen wurden, ist nicht
  festgehalten
- ADR-005 kennt die Wartefrist von Dependabot nicht und nicht die Lücke bei
  Container-Images (Warnung „Cooldown was not applied" bei `Dockerfile` und
  `compose.scan.yaml`). Kandidat für einen Nachtrag. Der Wortlaut der Warnung
  wurde in keiner Quelle gefunden; die Erklärung folgt aus der Meldung und aus
  der Ankündigung von GitHub
- Ob der neue `paths`-Eintrag `scripts/*.sh` die Regeldatei tatsächlich lädt,
  ist nicht geprüft; das zeigt sich beim nächsten Eingriff in ein `.sh`-Skript
- Für `dependabot.yml` lief kein YAML-Parser (auf dem Entwicklungsrechner ist
  keiner vorhanden); belegt ist nur die unveränderte Struktur
- Patch Tuesday (13.10.2026) und der erste zeitgesteuerte Lauf von CodeQL und
  CI (12.10.2026) lagen bei Sitzungsende noch in der Zukunft
- CISA KEV und OWASP wurden in der Recherche nicht eigens abgefragt; was
  nginx 1.30.5 behebt, wurde nicht nachgelesen
- Von den fünf Läufen von „Publish" wurde nur das Gesamtergebnis gelesen,
  nicht die Zeilen des Prüf-Gates
- Die Dependabot-Alerts kann der Agent nicht lesen (HTTP 403 für sein Token)
- Dieser Bericht ist noch nicht committet

**Weiter offen aus Sitzung 10**

- Kein Rot-Lauf dafür, dass „Publish" vor dem Hochladen abbricht, wenn
  Smoke-Test oder Scan fehlschlagen
- „Publish" ist kein Pflicht-Check; ein Fehlschlag zeigt sich erst nach dem
  Merge
- Eine Aufräumregel für die Registry fehlt (acht Images, jedes mit zwei
  Nachweisen); sie darf die Nachweise nicht löschen
- Ob Dependabot den Pin von `actions/attest` pflegt, ist unbelegt (seit der
  Aufnahme gab es kein Release)
- Die Version von `gh` auf dem Runner ist nicht festgelegt
- Die Wegwerf-Zertifikate der Pipeline weichen von den lokalen ab
- `scripts/invoke-image-scan.sh` läuft lokal nicht, weil `jq` fehlt

**Bekannte Grenzen**

- Kein Scanner meldet etwas zum Patch-Stand der .NET-Runtime (ADR-009)
- Der Herkunftsnachweis liegt in einem öffentlichen, unveränderlichen
  Protokoll
- Bei Container-Images wendet Dependabot keine Wartefrist an

**Unverändert aus früheren Sitzungen**

- `nginx.conf` enthält weder `limit_req_status` noch `proxy_ssl_verify_depth`;
  der Gegentest zu `proxy_ssl_verify` fehlt
- ADR-Rückstand: ADR-006 (Signaturen), ADR-008 (`rollForward: disable`), dazu
  die Kandidaten aus den Abschnitten 3 der Sitzungen 8 bis 11
- Der Projektauftrag liegt nicht im Repository; `Test-RepoState.ps1` ebenfalls
  nicht
- `Directory.Build.props`: veralteter Kommentar zum Locked Mode; `README.md`
  ohne Build- und Startbefehle; `sitzung-01.md` fehlt
- HSTS steht bewusst auf `max-age=300`
- Das Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches" ist nicht eingeschaltet (die Branches wurden von Hand gelöscht);
  auf GitHub liegen weiter die Branches älterer, gemergter PRs

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD): unverändert Teil A. Es fehlen ein Staging-Ziel, der
Deploy mit Anmeldung über OIDC, das Prüf-Gate vor dem Deploy, Environments mit
Freigabe und die DORA-Events. Die Entscheidung über die Reihenfolge (Schritt 5
vollenden oder Phase 5 vorziehen) ist vertagt (E-5-15). Die Empfehlung des
Agenten lautet: Schritt 5 vollenden, davor die xUnit-Umstellung.

| Thema | Status |
|---|---|
| **Resilienz-Patterns** (Retry, Timeout, Circuit Breaker) | Ausgelöst seit Sitzung 7, unbearbeitet |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher – weiterhin nur einseitige Verifikation |
| **DAST** (OWASP ZAP gegen Staging) | Wird mit dem ersten Staging-Deploy fällig |
| **Feature Flags** | Wird fällig, falls Phase 5 vor dem Deploy beginnt: Jeder Merge veröffentlicht ein Image |
| **Lieferketten-Gate** | In dieser Sitzung an zwei Bot-PRs durchlaufen (#77 gemergt, #78 abgelehnt) |
| **Agentic-Gate 6.5** | Nicht ausgelöst; die Regel für Wegwerf-PRs steht jetzt in `CLAUDE.md` |
| **Contract Testing, Mutation Testing, k6, LLM-Gate 6.4** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

**Pins, am 10.10.2026 gegen Registry bzw. Primär-Repository geprüft und
unverändert:**

```
mcr.microsoft.com/dotnet/sdk:10.0-noble
  sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317
mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
  sha256:48e51f2f6798897be7ac4e775c049ed8fe60d3190f637e1f9c9dc7513efa659c
nginxinc/nginx-unprivileged:1.30.5
  sha256:d715f7a85cdfea820fec743ea5aee8a22f91e00ff310ad6275d2638112d8cf8d
ghcr.io/anchore/grype:v0.120.1
  sha256:e4a44ef45d285b829ce6efe2642980329661bd2d18eab5fc539138d4adaebbbe
actions/attest v4.2.2
  1e69f48acb82d1966a394da916b4c1698aa569d6
SDK 10.0.401 (Runtime 10.0.12)
```

Nur zum Vergleich gemessen, nicht im Projekt verwendet:

```
mcr.microsoft.com/dotnet/aspnet:10.0-noble
  sha256:222759b391a1aaf241166672c8f99b2d4ada452e7b5319f3c6e8f265a37b5ad4
```

**Paketstand der Tests nach #77:** `Microsoft.NET.Test.Sdk` 18.10.1,
`xunit.v3` 3.2.2, `xunit.runner.visualstudio` 4.0.1.

**Läufe von „Publish" in dieser Sitzung** (alle grün; Digests nicht
ausgelesen):

```
38074453233  5e96567 (#74)
38074834785  5f7dc19 (#75)
38075602004  c8512e0 (#76)
38076176488  e4a98d5 (#77)
38077988288  5f7b36c (#79)
```

**Größe eines Images ohne laufendes Docker lesen:**
`docker buildx imagetools inspect <Image> --raw` liefert die Manifest-Liste;
derselbe Aufruf mit dem Digest des Eintrags `linux/amd64` liefert die
Schichten mit ihren Größen.

**Arbeitsteilung:** wie in Sitzung 10. Lokale Branches gemergter PRs löscht
der Agent nach einem Inhaltsvergleich mit `main` und auf Zuruf; Branches auf
GitHub löscht die Projekt-Ownerin.

**Fallstricke, die Zeit gekostet haben:**

- `docker compose config` und `docker buildx imagetools inspect` laufen ohne
  Docker Desktop, `docker pull` und `docker run` nicht; vor einer Messung
  prüfen, ob der Dienst läuft (`docker info`)
- Auf dem Entwicklungsrechner gibt es keinen YAML-Parser (`pyyaml`, `yq`,
  `ruby` fehlen)
- `gh pr view` meldet für einen gemergten oder geschlossenen PR `mergeable`
  als `UNKNOWN`; zuerst `state` lesen
- Ein Squash-Merge macht `git branch -d` unbrauchbar; nach leerem
  Inhaltsvergleich mit `main` hilft `-D`
- Unter Git Bash braucht `docker run --entrypoint /bin/sh`
  `MSYS_NO_PATHCONV=1`

---

# Roadmap Sitzung 12

## 1. Pflichtrecherche und Blick auf die Automatik (zuerst, kurz)

Warum zuerst: Zwei zeitgebundene Ereignisse lagen bei Sitzungsende in der
Zukunft, und seit dieser Sitzung liegt ein abgelehntes Major-Update vor.

- Patch Tuesday vom 13.10.2026: SDK-Pin und die beiden .NET-Digests neu
  auflösen. Ändert sich das SDK, gehören `global.json` und der Build-Digest
  im Dockerfile in einen PR
- Ergebnis der zeitgesteuerten Läufe von CodeQL und CI vom 12.10.2026
- Welche PRs hat Dependabot geöffnet? Hat er `xunit.v3` 4.x erneut
  vorgeschlagen? Titel und Release Notes lesen, nichts ungelesen mergen
- Sind alle Läufe von „Publish" grün?

## 2. Grundsatzentscheidung: Deploy jetzt oder Fachlogik zuerst?

Warum jetzt: Sie wurde in Sitzung 11 vertagt und bestimmt alles Weitere.

- **Schritt 5 vollenden:** Staging-Ziel wählen (eigener Server oder
  Cloud-Dienst), Deploy mit OIDC, Prüf-Gate vor dem Deploy, Environment mit
  Freigabe, DORA-Events. Hält den verbindlichen Phasenplan ein; der Nachweis
  schützt erst, wenn ein Ziel ihn verlangt.
- **Phase 5 vorziehen:** STRIDE und erster Use Case test-first. Schneller bei
  der Fachlogik, weicht aber vom Plan ab; jeder Merge veröffentlicht bereits
  ein Image, also wird das Thema Feature Flags fällig.

Offene Fragen an die Projekt-Ownerin: Wo könnte Staging laufen, und gibt es
ein Budget oder eine Vorgabe aus dem Projektauftrag? Konzept und Empfehlung
zuerst, keine Datei vor der Entscheidung.

## 3. xUnit-Umstellung auf die Testplattform v2 (eigener PR, vor Phase 5)

Warum: `xunit.v3` 3.2.2 hängt an der Testplattform v1, deren Unterstützung der
Herausgeber eingestellt hat; test-first in Phase 5 soll auf dem unterstützten
Stand beginnen. Der Bot-PR dazu existiert nicht mehr.

1. Aus der Primärquelle lesen, was `global.json` und das Testprojekt für
   `xunit.v3` 4.x auf dem SDK 10 brauchen, und ob `xunit.runner.visualstudio`
   und `Microsoft.NET.Test.Sdk` dann noch nötig sind
2. Optionen mit Trade-offs vorlegen; prüfen, ob der Testbefehl der
   Urteils-Hierarchie (`dotnet test --configuration Release --no-build`)
   unverändert bleibt
3. Ein atomarer PR: Paketversion, Lockfile, `global.json`, gegebenenfalls
   Testprojekt und `ci.yml`. `global.json` wird ins Image kopiert, der Check
   `Container & nginx` urteilt mit
4. Nachtrag zu ADR-002

## 4. Kleine Nachträge

- Nachtrag zu ADR-005: Wartefrist von Dependabot und die Lücke bei
  Container-Images
- Klären, warum Bot-Titel jetzt `chore: Bump …` lauten, und ob der Check
  `PR-Titel` das weiter durchlassen soll
- ADR-006 (Signaturen) und ADR-008 (`rollForward: disable`) nachschreiben

## 5. Vor oder in der Sitzung zu verstehen (vor Code)

- **Zwei Testplattformen in .NET:** VSTest ist der alte Weg, auf dem
  `dotnet test` Tests über einen Adapter startet. Die Microsoft Testing
  Platform ist der neue: Das Testprojekt ist selbst ein Programm. Mit dem SDK
  10 muss man sich für den neuen Weg ausdrücklich entscheiden.
- **Prüf-Gate vor dem Deploy:** Heute prüft die Pipeline ihren eigenen
  Nachweis nach der Veröffentlichung. Schutz entsteht erst, wenn das Ziel ein
  Image ohne gültigen Nachweis ablehnt.
- **OIDC gegenüber einem Ziel außerhalb von GitHub:** Der Lauf weist sich mit
  einem kurzlebigen Nachweis aus; das Ziel legt fest, welchem Repository und
  welchem Branch es vertraut.
- **Environments:** GitHub kann Deployments an Umgebungen mit eigenen Regeln
  binden; dort stimmt ein Mensch vor Produktion zu.
- **Wartefrist für Updates:** Eine gekaperte Version fällt meist binnen Tagen
  auf. Wer wartet, bekommt sie oft nicht vorgeschlagen; gegen spät entdeckte
  Angriffe hilft das nicht.

## 6. Optionale Vorbereitung

- Überlegen, wo Staging laufen könnte, und ob es ein Budget gibt
- Unter „Security" → „Dependabot" nachsehen, ob Alerts offen sind
- „Automatically delete head branches" einschalten und die alten Branches
  gemergter PRs einmal von Hand löschen
- Unter „Packages" nachsehen, ob das Paket `identity-service` mit dem
  Repository verknüpft ist
- Die Seite „Testing with dotnet test" der xUnit-Dokumentation überfliegen
- Den Projektauftrag als Datei unter `docs/` bereitstellen
- Das Ablaufdatum des Tokens (06.11.2026) vormerken
