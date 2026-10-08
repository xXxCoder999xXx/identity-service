# Sitzungsbericht Sitzung 10

**Datum:** 08.10.2026
**Phase:** Schritt 5 (CD), Teil A umgesetzt – das Image wird bei jedem Merge nach `main` mit Herkunftsnachweis und Stückliste in der GitHub Container Registry veröffentlicht; ein Deploy gibt es noch nicht
**Vorgänger:** sitzung-09.md (abgeschlossen 07.10.2026)

---

## 1. Erledigt

### 1.1 Reste aus Schritt 4b Teil 4 (PR #63, #64)

- **Datei-Nachtrag für `Image-Scan` (#63):** `main-ruleset.json`, Abschnitt 4
  der `CLAUDE.md`, die Regeldatei und der Kommentar in `ci.yml` nennen fünf
  Pflicht-Checks; `compose.scan.yaml` steht in der Repository-Karte.
- **`# syntax=docker/dockerfile:1` entfernt (#64):** Die Zeile ließ Docker vor
  jedem Build ein Hilfs-Image über einen beweglichen Tag ohne Digest nachladen.
  Das Dockerfile nutzt keine Anweisung, die den neueren Übersetzer braucht; ein
  Kommentar beschreibt den Weg zurück. Verifiziert: Build ohne Cache lädt kein
  Übersetzer-Image mehr, Image-Nutzer unverändert `1654`, Smoke-Test bestanden.
- **Dependabot findet `compose.scan.yaml`:** im Protokoll eines Dependabot-Laufs
  belegt (Ökosystem `docker_compose`, Image `anchore/grype`). Der in Sitzung 9
  vorgesehene Umzug des Scanner-Dienstes entfällt.

Damit ist Schritt 4b vollständig abgeschlossen.

### 1.2 Grundsatzentscheidung für Schritt 5 und ADR-010 (PR #65)

Die Frage „Wo läuft Staging?" wurde zurückgestellt: Zuerst entsteht der Teil
der Auslieferung, der vom Ziel unabhängig ist – Registry, Herkunftsnachweis,
Stückliste und ein Prüf-Gate. ADR-010 (akzeptiert) hält das fest.

Aufnahme-Prüfung aus dem Primär-Repository (07.10.2026): Die Actions
`actions/attest-build-provenance` und `actions/attest-sbom` sind nur Hüllen um
`actions/attest`, jede mit eigenem inneren Pin. `actions/attest` nimmt selbst
eine Stückliste entgegen. Verwendet wird deshalb die eine Action direkt.

### 1.3 Wegwerf-Zertifikate als Skript (PR #66)

Die rund 40 Zeilen openssl-Befehle wanderten unverändert aus `ci.yml` nach
`scripts/new-throwaway-certificates.sh`, weil der Veröffentlichungs-Workflow
dieselben Zertifikate braucht. Neu: optionaler Zielordner und Abbruch, wenn
dort schon eine CA liegt (als Skript wäre der Block sonst lokal startbar und
würde die Entwicklungs-CA überschreiben). Aufruf über `bash scripts/...`,
unabhängig vom Ausführungs-Bit.

Verifiziert: lokaler Testlauf in einem Ordner außerhalb des Projekts
(Kettenprüfung beider Zertifikate bestanden, SAN-Listen wie zuvor, Gültigkeit
ein Tag, CA-Schlüssel danach gelöscht, zweiter Lauf bricht mit Exit-Code 1
ab). Auf dem Runner: Skript, `nginx -t` und Smoke-Test grün (PR #66).

### 1.4 Image-Scan als Skript, in drei Zuständen bewiesen (PR #67, #69, #70)

Export, Bericht mit Stückliste, Blindheits-Schutz und Gate wanderten aus
`ci.yml` nach `scripts/invoke-image-scan.sh`; der Schwellenwert
(`--only-fixed --fail-on high`) steht damit nur noch an einer Stelle. Neu
gegenüber dem Inline-Code:

- unterscheidbare Exit-Codes: `2` Voraussetzung fehlt oder Scanner konnte
  nicht arbeiten, `3` Blindheits-Schutz, `4` Gate,
- alte Ergebnisse werden vor dem Scan entfernt,
- eine nicht auswertbare Anzahl im Blindheits-Schutz führt zum Abbruch. Im
  alten Code wäre der Vergleich nur mit einer Fehlermeldung gescheitert und
  die Prüfung durchgelaufen.

Verifiziert auf dem Runner über den Wegwerf-PR #69 (Lauf `37835546718`):

| Image | Erwartet | Erhalten | Protokoll |
|---|---|---|---|
| aktuelles Image | 0 | 0 | `No vulnerabilities found` |
| nginx (ohne .NET-Runtime) | 3 | 3 | `Betriebssystem=debian Systempakete=150 Runtime-Paket=0` |
| Image mit der Runtime vom August | 4 | 4 | Abbruch am Scan-Gate |

### 1.5 Vorfall: Wegwerf-Beweis auf `main` (PR #68, #69, #70)

Zwei Dinge liefen in der falschen Reihenfolge:

1. PR #67 wurde gemergt, bevor die Rot-Zustände bewiesen waren. Der erste
   Wegwerf-PR #68 hatte dadurch einen Konflikt mit `main`; GitHub startete
   keinen einzigen Check. Er wurde geschlossen und durch #69 ersetzt (frisch
   vom aktuellen `main` geschnitten).
2. Der Wegwerf-PR #69 (Entwurf, im Text „NIE MERGEN") wurde nach dem Ablesen
   gemergt, während die Frage nach dem Schließen noch offen war. Auf `main`
   stand danach rund elf Minuten lang der Beweis-Schritt im Job `Image-Scan`,
   der eigentliche Scan-Schritt war mit `if: false` abgeschaltet.

Einordnung: kein Sicherheitsloch – der Beweis-Schritt scannte auch das aktuelle
Image und erwartete Exit-Code 0. Der Check hing aber an zwei fremden Images
und fuhr drei Scans. PR #70 setzte `ci.yml` exakt auf den Stand von #67 zurück
(Unterschied zu `af9161c` leer, `Image-Scan` grün).

Folge: Der Agent schließt Wegwerf-PRs künftig sofort nach dem Ablesen selbst
(E-H-11).

Nebenbefund am Beweis-Schritt selbst: GitHub startet `run:`-Schritte mit
`bash -e`. Der erste Lauf auf #69 endete nach dem erwarteten Exit-Code 3,
bevor der dritte Zustand lief; erst nach dem Abfangen des Exit-Codes liefen
alle drei.

### 1.6 Veröffentlichungs-Workflow (PR #71)

Neue Datei `.github/workflows/publish.yml`, ausgelöst nur durch Pushes nach
`main`. Ein Job `Image veröffentlichen` mit genau vier Rechten
(`contents: read`, `packages: write`, `id-token: write`,
`attestations: write`):

1. Image einmal bauen (`docker compose build --pull api`)
2. Wegwerf-Zertifikate, Stack im Production-Modus mit `--no-build`, Vergleich
   der Image-IDs (gebaut gegen laufend), Smoke-Test
3. Image-Scan mit demselben Skript wie der Pflicht-Check
4. Anmeldung an GHCR mit dem Token des Laufs über stdin, Hochladen mit dem
   Commit als Tag, Digest auslesen und prüfen
5. Herkunftsnachweis und Stückliste über `actions/attest` (`v4.2.2`, per SHA),
   zusätzlich in die Registry gelegt (`push-to-registry: true`), ohne Storage
   Records (`create-storage-record: false`, deshalb kein fünftes Recht)
6. Prüf-Gate mit `gh attestation verify`

Der Workflow läuft nicht auf Pull Requests und ist kein Pflicht-Check.

Verifiziert im ersten Lauf auf `main` (`37838934893`, Commit `4c7b623`), beim
ersten Versuch grün: Production-Modus im Container, Image-IDs identisch,
Smoke-Test und Scan bestanden, Image hochgeladen, beide Nachweise bei GitHub,
im Sigstore-Protokoll und in der Registry abgelegt. Unabhängig über die
GitHub-API gegengeprüft: Zum Digest liegen genau zwei Nachweise vor
(Herkunft, Stückliste); im Herkunftsnachweis stehen dieses Repository,
`.github/workflows/publish.yml` auf `refs/heads/main` und der Commit des
Merges.

Das Paket `identity-service` ist laut Ansicht der Projekt-Ownerin **privat**.

### 1.7 Prüf-Gate geschärft (PR #72)

Der erste Lauf war grün, bewies aber wenig: `gh attestation verify` schreibt
ohne Terminal bei Erfolg nichts, und die Gegenprobe scheiterte nur, weil das
fremde Image gar keinen Nachweis hat (HTTP 404). Jetzt gilt:

- Jede der drei Verifikationen (Herkunft von GitHub, Herkunft aus der
  Registry, Stückliste) gibt Art, Repository, Branch, Workflow und Runner aus
  dem Nachweis aus und vergleicht sie mit den erwarteten Werten; eine leere
  oder abweichende Ausgabe macht den Lauf rot.
- Drei Gegenproben müssen scheitern: fremdes nginx-Image; eigenes Image mit
  falschem Workflow (`ci.yml`); eigenes Image mit falschem Branch.

Verifiziert vor dem Merge: Feldnamen im Quelltext nachgelesen und mit `gh`
2.102.0 an einem öffentlichen Nachweis (`cli/cli`) ausprobiert; Simulation
des Schritts unter `bash -e` mit nachgestelltem `gh` in fünf Zuständen (Gutfall
grün, vier Fehlzustände rot). Verifiziert im zweiten Lauf auf `main`
(`37840917638`, Commit `f3808a0`): drei Zeilen mit den erwarteten Angaben,
alle drei Gegenproben abgelehnt, die zum falschen Branch mit der Meldung
`expected SourceRepositoryRef to be refs/heads/not-main, got refs/heads/main`.

### 1.8 Aufräumen

Lokal existiert nur `main` und der Branch dieses Berichts. Keine offenen Pull
Requests.

---

## 2. Gelernt

- Ein Herkunftsnachweis sagt, woher ein Image kommt, nicht, ob es gut ist;
  Tests und Scan gehören deshalb vor die Veröffentlichung
- Ein Nachweis schützt erst, wenn jemand ihn verlangt: Ohne Deploy, das ihn
  prüft, ist er Vorbereitung
- Vor dem Übernehmen einer Action ihre Definition lesen: Zwei empfohlene
  Actions waren nur Hüllen um eine dritte
- Eine Gegenprobe muss aus dem richtigen Grund scheitern: Ein Image ganz ohne
  Nachweis beweist nicht, dass die Bedingungen der Prüfung wirken
- Ein Werkzeug, das bei Erfolg schweigt, liefert im Protokoll keinen Beleg;
  die geprüften Angaben ausgeben und vergleichen
- GitHub startet `run:`-Schritte mit `bash -e`: Ein absichtlich erwarteter
  Fehlercode beendet den Schritt, wenn er nicht abgefangen wird
- Ein Pull Request mit Konflikt startet keine Checks; „keine Checks" ist dann
  kein Zeichen für eine defekte Pipeline
- Ein Rot-Beweis gehört vor den Merge; danach lässt er sich nur noch über einen
  frischen Branch vom neuen `main` nachholen
- Ein Entwurfs-PR ist kein Schutz vor dem Mergen: „Ready for review" ist ein
  Klick. Wegwerf-PRs sofort schließen
- Ein Skript, das vorher nur in der Pipeline lief, ist plötzlich lokal
  startbar und braucht einen Schutz vor dem Überschreiben lokaler Dateien
- Ein Vergleich mit einem leeren Wert kann in der Shell mit einer Fehlermeldung
  scheitern und die Prüfung trotzdem durchlassen
- Ein Workflow, der nur auf `main` läuft, lässt sich auf dem Pull Request nicht
  beweisen; die Logik vorher simulieren und den ersten Lauf Zeile für Zeile
  lesen
- Der Container-Build ist nicht bitgenau wiederholbar: Zwei Läufe ohne
  Änderung am Programm ergaben zwei verschiedene Digests
- GHCR legt ein neues Paket privat an; der Wechsel auf öffentlich lässt sich
  laut Dokumentation nicht zurücknehmen

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-4b-31** | `# syntax`-Zeile entfernen statt per Digest pinnen | Die Abhängigkeit entfällt ganz; das Dockerfile braucht den neueren Übersetzer nicht |
| **E-5-1** | Schritt 5 beginnt mit Registry, Nachweis und Prüf-Gate; kein Staging-Ziel, kein Deploy | Dieser Teil ist vom Ziel unabhängig (ADR-010) |
| **E-5-2** | GitHub Artifact Attestations statt cosign | Kein weiteres Werkzeug; stammt vom Plattformbetreiber und ist mit `gh` prüfbar (ADR-010) |
| **E-5-3** | `actions/attest` direkt statt der zwei Hüllen-Actions | Eine Abhängigkeit statt dreier Bausteine mit zwei mitgeschleppten Pins (ADR-010) |
| **E-5-4** | Bauen, prüfen und veröffentlichen in einem Job eines eigenen Workflows | Veröffentlicht wird, was getestet wurde; keine Action zum Weiterreichen des Images (ADR-010) |
| **E-5-5** | Zertifikats-Erzeugung und Image-Scan als Bash-Skripte unter `scripts/` | Zwei Workflows nutzen sie; Kopplungen und Schwellenwert stehen an einer Stelle |
| **E-5-6** | Nachweise zusätzlich in die Registry legen, keine Storage Records | Der Nachweis reist mit dem Image; Storage Records gibt es nur für Organisationen |
| **E-5-7** | Prüf-Gate vergleicht die Angaben aus dem Nachweis und fährt Gegenproben am eigenen Image | Ein stilles Bestehen und eine Ablehnung mangels Nachweis beweisen die Bedingungen nicht (ADR-Kandidat, Nachtrag zu ADR-010) |
| **E-5-8** | Das Paket in der Registry bleibt privat | Der Wechsel auf öffentlich ist nicht umkehrbar; kein Bedarf vor dem ersten Deploy |
| **E-5-9** | Die Nicht-Root-Prüfung wird im Veröffentlichungs-Workflow nicht wiederholt | Sie läuft auf jedem Pull Request im Check `Container & nginx` |
| **E-H-11** | Der Agent schließt Wegwerf-PRs sofort nach dem Ablesen selbst | Ein offener Wegwerf-PR wurde gemergt, während die Rückfrage lief |

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Nicht empirisch bewiesen:** dass der Veröffentlichungs-Workflow vor dem
  Hochladen abbricht, wenn Smoke-Test oder Scan fehlschlagen. Das folgt aus
  der Schrittfolge; einen Rot-Lauf dazu gab es nicht
- Der Veröffentlichungs-Workflow ist kein Pflicht-Check und läuft erst nach dem
  Merge; ein Fehlschlag zeigt sich nur unter „Actions" und per E-Mail
- Die Ablehnung beim falschen Workflow meldet `gh` unspezifisch
  (`verifying with issuer "sigstore.dev"`); dass der Workflow der Grund ist,
  folgt nur aus dem unmittelbar davor bestandenen Aufruf
- Die Sichtbarkeit des Pakets und seine Verknüpfung mit dem Repository hat nur
  die Projekt-Ownerin gesehen; das Token des Agenten darf Pakete nicht lesen
- Die Aussagen „Paket standardmäßig privat", „automatisch verknüpft" und
  „öffentlich ist nicht umkehrbar" stammen aus einer zusammengefassten Abfrage
  der GitHub-Dokumentation
- Jeder Merge erzeugt ein neues Image mit neuem Digest, auch ohne Änderung am
  Programm; eine Aufräumregel für die Registry fehlt. Sie darf die Nachweise
  neben den Images nicht löschen
- ADR-010 führt zwei Punkte noch als unbelegt, die der erste Lauf geklärt hat,
  und kennt das geschärfte Prüf-Gate nicht (E-5-7)
- `CLAUDE.md` Abschnitt 3 und die Regeldateien nennen weder `publish.yml` noch
  die beiden Bash-Skripte; `scripts/` ist dort als „PowerShell" beschrieben.
  Der Kopfkommentar von `compose.scan.yaml` beschreibt noch den Aufruf von Hand
- Die Wegwerf-Zertifikate der Pipeline weichen von den lokalen ab (SAN-Liste,
  fehlende Angabe des Verwendungszwecks). Bewusst nicht angefasst; die
  gemeinsame Nutzung von `New-LocalDevCertificates.ps1` würde es beheben,
  verlangt aber den Umbau eines auf Windows geschriebenen Skripts
- `scripts/invoke-image-scan.sh` läuft auf dem Entwicklungsrechner nicht, weil
  `jq` fehlt; unter Git Bash ist zusätzlich `MSYS_NO_PATHCONV=1` nötig
- Ob Dependabot den Pin von `actions/attest` pflegt, ist nicht belegt; seit dem
  Merge von #71 lief Dependabot nicht
- Die Version von `gh` auf dem Runner ist nicht festgelegt; sie kommt mit dem
  Runner-Image
- Auf GitHub liegen die Branches `test/image-scan-red-proof` (zu #68) und
  `test/image-scan-red-proof-2` (zu #69) sowie die Branches der gemergten PRs
- Die Historie von `main` enthält den Wegwerf-Commit `670e669` (#69) und seine
  Rücknahme `aa4514a` (#70)
- Der erste zeitgesteuerte Lauf von `ci.yml` (12.10.2026) und der Patch
  Tuesday (13.10.2026) lagen bei Sitzungsende noch in der Zukunft
- Dieser Bericht ist noch nicht committet

**Bekannte Grenzen**

- Keiner der gemessenen Scanner meldet etwas zum Patch-Stand der .NET-Runtime
  (ADR-009); das gilt auch für den Scan vor der Veröffentlichung
- Der Herkunftsnachweis liegt in einem öffentlichen, unveränderlichen
  Protokoll; Repository, Workflow und Commit sind dort dauerhaft einsehbar
- Hooks und Leitplanken gelten nur für den Agenten, nicht für Befehle im
  Terminal; der Hook für Commit-Betreffs verlangt die Form `git commit -m`

**Unverändert aus früheren Sitzungen**

- `nginx.conf` enthält weder `limit_req_status` noch `proxy_ssl_verify_depth`
- Der Gegentest zu `proxy_ssl_verify` (Zertifikat einer fremden CA) fehlt
- ADR-Rückstand: ADR-005 (Dependabot), ADR-006 (Signaturen), ADR-007
  (chiseled Runtime-Image), ADR-008 (`rollForward: disable`), dazu die
  Kandidaten aus den Abschnitten 3 der Sitzungen 8 bis 10. ADR-005 und
  ADR-007 sind als Nächstes vereinbart
- Der Projektauftrag liegt nicht im Repository; `Test-RepoState.ps1` ebenfalls
  nicht
- `Directory.Build.props`: veralteter Kommentar zum Locked Mode; `README.md`
  ohne Build- und Startbefehle; `sitzung-01.md` fehlt
- HSTS steht bewusst auf `max-age=300`
- Das Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches" ist nicht eingeschaltet

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 4b: abgeschlossen.

Phase 4, Schritt 5 (CD): Teil A umgesetzt – Registry, Stückliste,
Herkunftsnachweis ohne gespeichertes Geheimnis, Prüf-Gate. Vom Phasenplan
fehlen noch: ein Staging-Ziel, der Deploy mit Anmeldung über OIDC, das
Prüf-Gate **vor** dem Deploy (heute prüft es nach der Veröffentlichung),
Environments mit Freigabe und die DORA-Events. Offen ist die Reihenfolge:
Schritt 5 erst vollenden oder mit Phase 5 (erster fachlicher Use Case)
beginnen und das Deploy nachziehen.

| Thema | Status |
|---|---|
| **Resilienz-Patterns** (Retry, Timeout, Circuit Breaker) | Ausgelöst seit Sitzung 7, unbearbeitet |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher – weiterhin nur einseitige Verifikation |
| **DAST** (OWASP ZAP gegen Staging) | Rückt näher – wird mit dem ersten Staging-Deploy fällig |
| **Lieferketten-Gate** | In dieser Sitzung einmal durchlaufen: `actions/attest` (ADR-010) |
| **Feature Flags** | Rückt näher, falls Phase 5 vor dem Deploy beginnt: Jeder Merge veröffentlicht bereits ein Image |
| **Agentic-Gate 6.5** | Nicht ausgelöst; die erweiterte Befugnis des Agenten ist als E-H-11 festgehalten |
| **Contract Testing, Mutation Testing, k6, LLM-Gate 6.4** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

**Pins:** Die Image- und SDK-Pins sind gegenüber Sitzung 9 unverändert und
wurden in dieser Sitzung nicht neu aufgelöst. Neu:

```
actions/attest v4.2.2
  1e69f48acb82d1966a394da916b4c1698aa569d6
  (am 07.10.2026 per git ls-remote gegen das offizielle Repository aufgelöst)
```

**Veröffentlichte Images** (Paket privat):

```
ghcr.io/xxxcoder999xxx/identity-service

Lauf 37838934893, Commit 4c7b623 (#71)
  sha256:53a2c9e9715ae7743fe6e5ee2fb3fe7bec8a04cbdd66964ef58f3f2311ac445b
  Nachweise 54086603 (Herkunft), 54086630 (Stückliste)

Lauf 37840917638, Commit f3808a0 (#72)
  sha256:a8c7673955b3e0234cc171027abd825cbdac5979d8f7e28efac7a0cdc29bbd22
  Nachweise 54091726, 54091746
```

Der Tag eines Images ist der volle Commit-Hash; `latest` gibt es nicht.

**Nachweis von Hand prüfen** (verlangt eine Anmeldung an der Registry):

```
gh attestation verify oci://ghcr.io/xxxcoder999xxx/identity-service@<digest> --repo xXxCoder999xXx/identity-service --signer-workflow xXxCoder999xXx/identity-service/.github/workflows/publish.yml --source-ref refs/heads/main --deny-self-hosted-runners
```

Für die Stückliste zusätzlich `--predicate-type https://cyclonedx.org/bom`.
Ohne Zugriff auf die Registry lassen sich die Nachweise über die API lesen:
`gh api repos/xXxCoder999xXx/identity-service/attestations/<digest>`.

**Skripte:**

| Skript | Aufruf | Exit-Codes |
|---|---|---|
| `scripts/new-throwaway-certificates.sh` | `bash scripts/new-throwaway-certificates.sh [Zielordner]` | 1, wenn im Zielordner schon eine CA liegt |
| `scripts/invoke-image-scan.sh` | `bash scripts/invoke-image-scan.sh [Image]` | 2 Voraussetzung/Scanner, 3 Blindheits-Schutz, 4 Gate |

Zum Nachstellen der Rot-Zustände des Scans: nginx-Image aus `compose.yaml`
(Exit 3) und ein Build mit dem Runtime-Digest vom August aus Sitzung 9
(Exit 4).

**Arbeitsteilung:** wie in Sitzung 9. Neu: Wegwerf-PRs schließt der Agent
sofort nach dem Ablesen; Branches auf GitHub löscht weiterhin die
Projekt-Ownerin.

**Fallstricke, die Zeit gekostet haben:**

- `gh pr checks --watch` meldet unmittelbar nach dem Anlegen eines PRs „no
  checks reported"; erst warten, bis Checks erscheinen. Bleibt es dabei, den
  PR auf einen Konflikt prüfen (`mergeable`, `mergeStateStatus`)
- Der Hook für Commit-Betreffs erkennt nur `git commit -m "..."`; mehrere
  Absätze über weitere `-m`
- Unter Git Bash schreibt MSYS Angaben um, die wie Pfade aussehen
  (`-subj "/CN=..."`, `docker-archive:/in/...`, `origin/main:pfad`); Abhilfe
  `MSYS_NO_PATHCONV=1` oder ein anderer Befehl
- `gh attestation verify` gibt ohne Terminal bei Erfolg nichts aus; mit
  `--format json --jq` erhält man die geprüften Angaben
- Ein `git push` über das Ausrufezeichen kann länger als zwei Minuten dauern
  und läuft dann im Hintergrund weiter; vor dem nächsten Schritt mit
  `git ls-remote` prüfen, ob der Branch angekommen ist
- Werkzeuge zum Suchen und Ersetzen können ein Leerzeichen am Ende der
  Fundstelle verschlucken (`if [` wurde zu `if[`); nach jeder Änderung an
  einem Skript die Syntax prüfen (`bash -n`)

---

# Roadmap Sitzung 11

## 1. Pflichtrecherche und Blick auf die Automatik (zuerst, kurz)

Warum zuerst: Seit dieser Sitzung veröffentlicht jeder Merge ein Image, und
zwei zeitgebundene Ereignisse lagen bei Sitzungsende noch in der Zukunft.

- Patch Tuesday vom 13.10.2026: Sind SDK und Image-Digests noch aktuell?
- Ergebnis des ersten zeitgesteuerten CI-Laufs vom 12.10.2026
- Welche PRs hat Dependabot geöffnet, auch für `actions/attest`? Titel lesen,
  nichts ungelesen mergen
- Sind alle Läufe von „Publish" seit dieser Sitzung grün?

## 2. Dokumentation an den neuen Stand anpassen (klein)

Warum jetzt: Mehrere Dateien beschreiben den Stand vor Schritt 5; eine zweite
Wahrheit entsteht sonst genau dort, wo der Agent seine Regeln liest.

1. `CLAUDE.md` Abschnitt 3 und die Regeldateien: `publish.yml`, die beiden
   Bash-Skripte, die Regel für Wegwerf-PRs (nur nach ausdrücklicher Freigabe)
2. ADR-010 nachtragen: die zwei geklärten Punkte und das geschärfte Prüf-Gate
3. Kopfkommentar von `compose.scan.yaml` auf das Skript verweisen lassen

## 3. ADR-005 und ADR-007 nachschreiben

Warum: so vereinbart („nach Schritt 5"), und beide sind inzwischen
inhaltsreicher als bei der Entscheidung: ADR-005 (Dependabot, fünf Ökosysteme,
`ignore`-Regel für nginx) und ADR-007 (chiseled Runtime-Image, mit der
Scanner-Messung aus Sitzung 9). Mit `/adr`, je ein PR.

## 4. Grundsatzentscheidung: Deploy jetzt oder Fachlogik zuerst?

Warum: Der Phasenplan sieht das Deploy nach Staging vor dem ersten Use Case
vor; Schritt 5 wurde bewusst mit dem zielunabhängigen Teil begonnen. Zwei Wege:

- **Schritt 5 vollenden:** Staging-Ziel wählen (eigener Server oder
  Cloud-Dienst), Deploy mit OIDC, Prüf-Gate vor dem Deploy, Environment mit
  Freigabe, DORA-Events. Hält den Phasenplan ein; der Walking Skeleton reicht
  dann wirklich bis Staging.
- **Phase 5 vorziehen:** STRIDE und erster Use Case test-first; das Deploy
  folgt, sobald es etwas Fachliches auszuliefern gibt. Schneller bei der
  Fachlogik, weicht aber von der verbindlichen Reihenfolge ab und braucht eine
  bewusste Entscheidung.

Konzept und Empfehlung zuerst, keine Datei vor der Entscheidung.

## 5. Vor oder in der Sitzung zu verstehen (vor Code)

- **Prüf-Gate vor dem Deploy:** Heute prüft die Pipeline ihren eigenen
  Nachweis direkt nach der Veröffentlichung. Schutz entsteht erst, wenn das
  Ziel ein Image ohne gültigen Nachweis ablehnt – dieselbe Prüfung, aber an
  der Stelle, an der gestartet wird.
- **OIDC gegenüber einem Ziel außerhalb von GitHub:** Der Lauf weist sich mit
  einem kurzlebigen Nachweis aus; das Ziel legt fest, welchem Repository und
  welchem Branch es vertraut. Derselbe Mechanismus hat in dieser Sitzung die
  Signatur ohne gespeicherten Schlüssel ermöglicht.
- **Environments:** GitHub kann Deployments an Umgebungen mit eigenen Regeln
  binden. Dort stimmt ein Mensch vor Produktion zu.
- **Aufräumregel für eine Registry:** Alte Images kosten Platz, aber ein
  gelöschtes Image nimmt seinen Nachweis mit. Die Regel muss festlegen, was
  bleibt (z. B. alles, was je ausgeliefert wurde).
- **STRIDE (für Phase 5):** sechs Fragen an ein Feature – Identität fälschen,
  Daten manipulieren, Handlungen abstreiten, Informationen preisgeben, Dienst
  lahmlegen, Rechte ausweiten. Aus jeder Antwort wird ein Testfall.

## 6. Optionale Vorbereitung

- Die beiden Wegwerf-Branches auf GitHub löschen und „Automatically delete
  head branches" einschalten
- Unter „Packages" nachsehen, ob das Paket `identity-service` mit dem
  Repository verknüpft ist
- Überlegen, wo Staging laufen könnte
- `jq` auf dem Entwicklungsrechner installieren, wenn der Image-Scan lokal
  laufen soll (eine Entscheidung der Projekt-Ownerin, kein Auftrag an den
  Agenten)
- Den Projektauftrag als Datei unter `docs/` bereitstellen
- Das Ablaufdatum des Tokens (06.11.2026) vormerken
