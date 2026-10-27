# Sitzungsbericht Sitzung 23

**Datum:** 27.10.2026
**Phase:** Schritt 5 (CD): Veröffentlichung des lego-Images gebaut (Gate rot,
nichts veröffentlicht); Konzept der Staging-Variante beschlossen; nginx-Härtung
als Snippets (PR 1 von 3 für Staging)
**Vorgänger:** sitzung-22.md (abgeschlossen 27.10.2026)

---

## 1. Erledigt

| PR | Titel | Inhalt |
|---|---|---|
| #115 | `ci(publish): add lego image publication` | `publish-lego.yml`, `scripts/verify-attestations.sh`, Umbau `publish.yml`, Regel `lieferkette-und-ci.md` |
| #116 | `refactor(nginx): extract hardening into include snippets` | `nginx/snippets/` (5 Dateien), `nginx.conf`, Mount in `compose.yaml`, CODEOWNERS `/nginx/` |

Beide PRs von der Projekt-Ownerin per Squash gemergt; überwiegend KI-erzeugt,
kein Auto-Merge.

### 1.1 lego-Release geprüft (Roadmap-Punkt 1, Vorbedingung)

- `go-acme/lego`: neuestes Release weiterhin v5.5.2 (23.09.2026), Stand
  27.10.2026.
- Hauptzweig: `golang.org/x/net v0.61.0` in `go.mod`; die Go-Version der
  Programmdatei hängt von der Toolchain des Releases ab. Für ein Image ohne
  bekannte Funde braucht es Go ≥ 1.27.3 (wegen `GO-2026-6809`).

### 1.2 Veröffentlichung des lego-Images (Roadmap-Punkt 1, #115)

- **Eigener Workflow `publish-lego.yml`** (E-5-78): Auslöser nur Push auf
  `main` mit `paths` (`docker/lego/**`, der Workflow selbst, beide Skripte);
  dieselben vier Rechte wie `publish.yml`; Ablauf bauen → gehärteter Start →
  Scan (Profil `lego`) → Push (Tag = Commit-SHA) → Herkunftsnachweis und
  Stückliste → Prüf-Gate.
- **Gehärteter Start** statt Smoke-Test: UID 101, `--read-only`,
  `--cap-drop ALL`, `no-new-privileges`; Version muss zur `FROM`-Zeile passen;
  `--entrypoint /bin/sh` muss mit genau Exit 127 scheitern. Lokal gemessen:
  `lego version 5.5.2 linux/amd64` (Exit 0), Shell `stat /bin/sh: no such file
  or directory` (Exit 127), ganzer Block aus dem Workflow Exit 0.
- **`scripts/verify-attestations.sh`**: Prüfung aus `publish.yml` ausgelagert,
  Parameter `IMAGE_NAME DIGEST WORKFLOW WRONG_WORKFLOW`, Exit-Codes 2
  (Voraussetzung), 3 (Nachweis), 4 (Gegenprobe akzeptiert). Gegenprobe
  „falscher Workflow“ nutzt den Workflow des jeweils anderen Images.
  `bash -n` Exit 0, ASCII, LF; Aufruf mit 2 Parametern Exit 2.
- **Regel angepasst** (Freigabe der Projekt-Ownerin in dieser Sitzung):
  `.claude/rules/lieferkette-und-ci.md`: Schreibrechte nur in `publish*.yml`,
  je Image ein Workflow; `verify-attestations.sh` als geteilter Schritt.
- Action-Pins `actions/checkout` v7.0.1 und `actions/attest` v4.2.2 am
  27.10.2026 per `git ls-remote` bestätigt (identisch mit `publish.yml`).
- PR-Checks: fünf Pflicht-Checks grün; `Image-Scan Drittanbieter (lego)` rot
  mit denselben 15 Funden High+ wie in Bericht 22, dazu `GO-2026-6809`
  (Unknown) und 2 Medium.

**Gemessen nach dem Merge (Commit `0466315`):**

| Lauf | Ergebnis |
|---|---|
| `Publish` (API) | grün; Image `ghcr.io/xxxcoder999xxx/identity-service@sha256:07fe73b7f8c81d2722cd49eea7eb5f635ab647372d10678ac4eae2657c5a97d4`; drei Nachweise verifiziert; drei Gegenproben abgelehnt, darunter „falscher Workflow (`publish-lego.yml`)“ |
| `Publish lego` | Build und gehärteter Start grün; Scan Exit 4; Login, Push, Nachweise und Prüf-Gate übersprungen |

- GHCR: `docker manifest inspect` für das API-Image Exit 0; für
  `identity-service-lego:<Commit>` `denied`. Die Antwort unterscheidet nicht
  zwischen privat und fehlend; harter Beleg ist der übersprungene Push.
- Der rote CI-Lauf auf `main` zu `f5dfc41` kam nur von
  `Image-Scan Drittanbieter (lego)`.

### 1.3 Konzept der Staging-Variante (Roadmap-Punkt 2)

Entscheidungen E-5-79 bis E-5-83 (Abschnitt 3). Aufteilung in drei PRs:
nginx-Snippets (#116, erledigt), Mountpunkte im lego-Image, Staging-Compose mit
`nginx.staging.conf` und Prüfschritt.

### 1.4 Messung: Volume übernimmt Besitz aus dem Image (E-5-80)

Lokal unter Docker Desktop mit Wegwerf-Image auf Basis
`goacme/lego:v5.5.2@sha256:1944e8c3…` (Mountpunkte mit Besitzer 101) und
`nginx-unprivileged:1.30.6@sha256:ec0f7ecb…` als Leser; alle Container mit
UID 101, `--read-only`, `--cap-drop ALL`, `no-new-privileges`.

| Nr. | Ablauf | Gemessen |
|---|---|---|
| M1 | lego bindet neues Volume zuerst ein | `101:101 700`, Schreiben Exit 0 |
| M2 | nginx zuerst (Pfad im Image unbekannt), danach lego | nginx `0:0 755`; danach lego `101:101 700`, Schreiben Exit 0; anschließend nginx `101:101 700` |
| M3 | lego schreibt `0600`, nginx liest `:ro` | Datei `101:101 600`; Lesen Exit 0; Schreiben `Read-only file system`, Exit 1 |
| M4 | Gegenprobe: Pfad nicht vorbereitet | `0:0 755`, `Permission denied`, Exit 1 |
| M5 | Volume vorab mit `docker volume create` | `101:101 700`, Schreiben Exit 0 |

Aufgeräumt: keine `probe-`-Volumes, kein `probe-lego`-Image.

### 1.5 lego-Option für den Zertifikatsnamen

Quellcode lego v5.5.2 (`cmd/internal/flags/flags.go`, `names.go`,
`cmd/internal/storage/storage_certificates_writer.go`): Flag `--cert.name`
(Alias `-c`) bestimmt die ID, unter der die Dateien gespeichert werden;
Standard ist die erste Domain.

### 1.6 nginx-Snippets (Roadmap-Punkt 2, PR 1, #116)

- `nginx/snippets/`: `http-common.conf` (http), `tls.conf`,
  `security-headers.conf` (ohne HSTS), `limits.conf` (server),
  `proxy-api.conf` (location). Einbinden einzeln mit festem Namen, keine
  Wildcard.
- `nginx.conf` enthält nur noch Ports, `server_name`, Zertifikatspfade, HSTS
  (neben dem Header-Snippet im selben Kontext) und den Catch-all.
- `compose.yaml`: Bind-Mount `./nginx/snippets` → `/etc/nginx/snippets`,
  `read_only: true`. CODEOWNERS: `/nginx/`.
- Lokal gemessen: `nginx -t` erfolgreich; Header-Werte für 200 und 404 vorher
  und nachher per `diff` identisch; normalisierte Ausgabe von `nginx -T`
  (146 Zeilen) identisch; 7 geladene Dateien; Gegenprobe (umbenanntes
  `tls.conf`) `nginx -t` Exit 1.
- CI: fünf Pflicht-Checks grün; in `Container & nginx` `test is successful`
  und Smoke-Test `alle Pruefungen bestanden` (alle fünf Header bei 200 und
  404). lego wie bisher rot (15 Funde).
- Nach dem Merge (Commit `1a3fc3c`): `Publish` grün.

### 1.7 Lehrstoff

[Lehrstoff: Zweites Image veröffentlichen, Volumes und nginx-Snippets](https://claude.ai/artifact/8n2YYUSeYxPWnFokLGbsVa)
(ein Workflow je Image, gehärteter Start und Rot-Pfad, Compose-Override,
Volume-Übernahme mit Diagramm, bewiesener Umbau, angreiferkontrollierte Werte
und Port 80, Spickzettel).

---

## 2. Gelernt

- Ein Herkunftsnachweis nennt den signierenden Workflow; mit einem Workflow je
  Image wird der Erbauer zu einer zweiten Prüfbedingung.
- Ein Prüfskript, das von zwei Workflows geteilt wird, hält die Prüfregeln an
  einer Stelle; die Gegenprobe mit dem Workflow des anderen Images beweist die
  Trennung bei jedem Lauf.
- Ein Image ohne Dienst lässt sich vor dem Push mit einem gehärteten Start
  prüfen: Version melden lassen und belegen, dass keine Shell existiert.
- `docker run` meldet Exit 127, wenn das Programm im Image fehlt; 125 ist ein
  Fehler des Daemons. Eine Gegenprobe akzeptiert genau den erwarteten Code.
- Ein rotes Gate, nach dem alle Schreib-Schritte übersprungen werden, ist der
  Beleg, dass nichts veröffentlicht wurde; die Registry antwortet bei privat
  und fehlend gleich (`denied`).
- Ein `paths`-Filter verhindert, dass ein bekannt rotes Gate jeden Lauf nach
  einem Merge rot färbt.
- Compose führt mehrere Dateien zusammen; Listen wie `ports:` werden dabei
  angehängt, nicht ersetzt.
- Ein leeres Volume übernimmt Inhalt, Besitz und Rechte beim ersten Container,
  dessen Image den Pfad vorbereitet hat, auch wenn ein anderer Container es
  vorher eingebunden hatte. Ein gefülltes Volume wird nie neu übernommen.
- Ein Umbau ohne Verhaltensänderung ist bewiesen, wenn `diff` vorher gegen
  nachher leer ist (Header-Werte und normalisierte `nginx -T`-Ausgabe).
- Ein neuer Ordner ist nicht automatisch CODEOWNERS-pflichtig, auch wenn die
  Datei, aus der er entstand, es war.
- Ein Wert aus der Anfrage (SNI, Host-Header) darf nie zu einem Dateipfad oder
  Weiterleitungsziel werden.
- Der Hook `Test-CommitConvention` verlangt den Betreff über `-m`; ein Commit
  mit `-F -` wird blockiert.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-78** | Je Image ein Veröffentlichungs-Workflow (`publish.yml`, `publish-lego.yml`); Prüfung in `scripts/verify-attestations.sh`; Gegenprobe mit dem Workflow des anderen Images | Server prüft Name und Erbauer; eine Quelle der Prüfregeln |
| **E-5-79** | Staging als Override `compose.staging.yaml` auf `compose.yaml`; CI rendert die zusammengeführte Konfiguration und prüft sie; API-Image als `${API_IMAGE:?…}` | Härtung und Pins an einer Stelle; Merge-Falle durch Messung abgesichert |
| **E-5-80** | Mountpunkte `/data/accounts` (`0700`), `/data/certificates`, `/webroot` im lego-Image mit Besitzer 101; Volumes übernehmen den Besitz | Kein Container braucht Zusatzrechte; gemessen M1 bis M5 |
| **E-5-81** | nginx-Härtung als Snippets, einzeln per festem Namen eingebunden; HSTS in der Hauptdatei | Eine Quelle für lokal und Staging; fail closed bei fehlender Datei |
| **E-5-82** | lego mit `--cert.name edge`; Domain als `server_name.conf` vom Server, `:ro`; kein `$ssl_server_name` in Pfaden | Domain nicht im Repository (ADR-004); kein Angreifer-Text in Dateipfaden |
| **E-5-83** | Port 80: unbekannter Host `444`; nur `GET` auf `/.well-known/acme-challenge/` aus dem Webroot; sonst `308` auf `https://$server_name$request_uri` | HTTP-01 möglich, keine lenkbare Weiterleitung |

ADR-Kandidaten: E-5-78 als Nachtrag zu ADR-010. E-5-79 bis E-5-83 gehören mit
E-5-65 bis E-5-68 und E-5-73 bis E-5-76 in das ADR zum Schritt DNS/TLS (darin
auch: ein gefülltes Volume übernimmt spätere Image-Änderungen nicht).

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **lego-Gate rot** bis zu einem lego-Release mit Go ≥ 1.27.3 und `x/net` ≥
  0.60.0. Bis dahin ist jeder CI-Lauf auf `main` rot; bei jedem roten Lauf
  prüfen, ob es nur `Image-Scan Drittanbieter (lego)` ist. Für `1a3fc3c` nicht
  einzeln geprüft.
- `Publish lego` grün noch nie gelaufen: Push, Nachweise und das Prüf-Gate für
  lego sind ungetestet, bis das Gate grün wird.
- `/docker/lego/` (bzw. `/docker/`) fehlt in `.github/CODEOWNERS`; Vorschlag:
  in PR 2 mitnehmen.
- `.claude/rules/container-und-nginx.md` nennt nur `nginx.conf`; ein Satz zu
  `nginx/snippets/` wäre sinnvoll (Entscheidung der Projekt-Ownerin).
- M1 und M2 unter rootless Docker auf dem Server wiederholen (beim ersten
  Staging-Start).
- `proxy_ssl_trusted_certificate` zeigt in `proxy-api.conf` auf
  `/etc/nginx/ca/local-dev-ca.crt`; Name und Ort der CA für Staging offen
  (neuer Roadmap-Punkt „interne CA“).
- Push- und Digest-Logik steht doppelt in `publish.yml` und
  `publish-lego.yml`; Kandidat für einen Folge-PR.
- Gegenproben in `verify-attestations.sh` akzeptieren jeden Fehler von
  `gh attestation verify`, auch einen Netzfehler (unverändert übernommen).
- Paketliste in GHCR nicht abrufbar: Agenten-Token ohne `read:packages`
  (HTTP 403). Sichtprüfung unter Profil → Packages durch die Projekt-Ownerin
  nicht bestätigt.
- YAML der Workflows lokal nicht maschinell geparst (kein Parser ohne neue
  Abhängigkeit); Beleg nur über die Ausführung auf GitHub.
- `Test-Stack.ps1` lokal nicht lauffähig (Hook blockiert `-CaFile`); ersetzt
  durch direkten Vergleich der Header-Werte.

**Aus Sitzung 22 und früher, weiter offen**

- Nachtrag zu ADR-009: Umgang mit Funden der Schwere `Unknown`
- Länge der Dependabot-Cooldown; Nachtrag zu ADR-005
- Release Notes von #106 (CodeQL) und #108 (Grype v0.121.0) nicht gemeinsam
  gelesen
- Docker 29.9.2 auf dem Server nicht gemessen (Roadmap-Punkt)
- CVE-2026-111943 bei NVD und CISA KEV nicht geprüft
- `Image-Scan Drittanbieter` als Required Check: fällig vor dem ersten Deploy
  von lego
- ADR-006, ADR-008, ADR-012, ADR-013, ADR-014 auf „Vorgeschlagen“
- Lokale gemergte Branches löschen (Freigabe nötig): `build/lego-image`,
  `build/sdk-10-0-403`, `docs/adr-013-alert-channel`,
  `docs/adr-014-third-party-image-gate`, `docs/sitzung-21`, neu
  `docs/report-22-unknown-severity`, `ci/publish-lego-image`,
  `refactor/nginx-snippets`
- Arbeitsdateien im ignorierten Ordner `scan/`
- Signatur der distroless-Basis nicht selbst geprüft
- CAA um `accounturi` und `validationmethods=http-01`; TTL des A-Eintrags
- `jq` lokal nicht installiert
- KEV-Einträge vom 16.10.2026 nicht namentlich geprüft
- Beschreibung des Checks bei Healthchecks.io kürzen (freigestellt)
- Ping-URL im Verlauf der Zwischenablage; IPv4-Erreichbarkeit von
  `hc-ping.com`; zweiter Warnkanal vor Production; Gegenprobe „Update-Lücke
  über 26 Stunden“; Frist des Journals ab 18.11.2026; runc 1.5.2 und
  CVE-2026-41579; NTS und netcup-Regel `ntp-antworten`; Journal von
  `nft-rollback.service`; Nachträge ADR-012, ADR-011; Maschinenkonto
- **Token des Agenten läuft am 06.11.2026 ab** (in 10 Tagen)

**Bekannte Grenzen**

- Volume-Messung unter Docker Desktop, nicht unter rootless Docker.
- Ausgaben vom Server und aus den Panels von netcup liegen nur als Rückmeldung
  der Projekt-Ownerin vor; CI-Läufe, Primär-Repos und lokale Messungen sind
  selbst gemessen.
- Domain, Server-IPs und Hostnamen stehen bewusst nicht in diesem Bericht
  (öffentliches Repository, ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Neu: Veröffentlichungs-Workflow für lego (rot,
erwartet), geteiltes Prüfskript, Konzept der Staging-Variante, nginx-Snippets.

Bis zum Beginn von Phase 5 fehlen:

| Nr. | Schritt | Abhängig von |
|---|---|---|
| 1 | Staging-Konfiguration: PR 2 Mountpunkte lego, PR 3 `compose.staging.yaml` + `nginx.staging.conf` + Prüfschritt | – |
| 2 | Interne CA auf dem Server (nginx → API) | 1 |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer (E-5-76) | 1, 2, **veröffentlichtes lego-Image** |
| 4 | Maschinenkonto (ADR-011) | – |
| 5 | Pull-Deploy mit Prüfung von Nachweis und Signatur | 1, 4 |
| 6 | Freigabe vor dem Deploy, DORA-Events | 5 |
| 7 | DAST (OWASP ZAP) | 5, 6 |

Bleibt lego nach Schritt 1 blockiert: 4 bis 6 vorziehen.

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: zweiter Workflow mit Schreibrechten (E-5-78), Regel angepasst; keine neue Abhängigkeit |
| **Image-Gate für fremde Images** | lego rot (15 Funde), nginx grün; noch kein Required Check |
| **Zero Trust / A01** | Port-80-Aufbau ohne lenkbare Weiterleitung, kein Angreifer-Text in Pfaden (E-5-82, E-5-83) |
| **A09 (Alerting)** | unverändert; Erneuerung über ADR-013 geplant (E-5-76) |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** (OWASP ZAP) | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant) |
| **Feature Flags** | Nicht fällig |
| **Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Digests und Pins (27.10.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| `actions/checkout` v7.0.1 | `3d3c42e5aac5ba805825da76410c181273ba90b1` | `git ls-remote` |
| `actions/attest` v4.2.2 | `1e69f48acb82d1966a394da916b4c1698aa569d6` | `git ls-remote` |
| API-Image (Commit `0466315`) | `sha256:07fe73b7f8c81d2722cd49eea7eb5f635ab647372d10678ac4eae2657c5a97d4` | Lauf `Publish` |

### 6.2 Veröffentlichung

| | API | lego |
|---|---|---|
| Workflow | `publish.yml` | `publish-lego.yml` |
| Registry-Name | `ghcr.io/xxxcoder999xxx/identity-service` | `ghcr.io/xxxcoder999xxx/identity-service-lego` |
| Prüfung vor dem Push | Stack + `Test-Stack.ps1` | gehärteter Start (Version, Exit 127) |
| Auslöser | jeder Push auf `main` | Push auf `main` mit `paths` |

```
bash scripts/verify-attestations.sh IMAGE_NAME DIGEST WORKFLOW WRONG_WORKFLOW
```

Exit-Codes: 2 Voraussetzung/Parameter, 3 Nachweis fehlt oder weicht ab,
4 Gegenprobe akzeptiert.

### 6.3 Volumes für Staging (E-5-75, E-5-80)

| Volume | lego | nginx | Mountpunkt im Image |
|---|---|---|---|
| `lego-accounts` | `/data/accounts` rw | – | `0700`, 101:101 |
| `tls-certificates` | `/data/certificates` rw | `/etc/nginx/acme` ro | `0755`, 101:101 |
| `acme-webroot` | `/webroot` rw | `/var/www/acme` ro | `0755`, 101:101 |

### 6.4 nginx-Snippets

| Datei | Kontext |
|---|---|
| `nginx/snippets/http-common.conf` | `http` |
| `nginx/snippets/tls.conf` | `server` |
| `nginx/snippets/security-headers.conf` | `server` (ohne HSTS) |
| `nginx/snippets/limits.conf` | `server` |
| `nginx/snippets/proxy-api.conf` | `location` |

### 6.5 Fallstricke, die Zeit gekostet haben

- Hook `Test-CommitConvention` blockiert `git commit -F -`; Betreff und
  Absätze über mehrere `-m`.
- `grep -c $'\r'` innerhalb von `"$( … )"` zählte jede Zeile; Zeilenenden mit
  `git ls-files --eol` prüfen.
- `docker manifest inspect` gegen GHCR antwortet bei privat und fehlend gleich
  (`denied`).
- Docker Desktop lief anfangs nicht; Messungen erst nach dem Start möglich.

### 6.6 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| lego-Release | Gate grün möglich? | `gh api repos/go-acme/lego/releases` | v5.5.2 bleibt neuestes |
| Pins bestätigen | Pin aus Primär-Repo | `git ls-remote …/actions/attest` | identisch |
| Exit 127 messen | Gegenprobe nicht raten | `docker run … --entrypoint /bin/sh` | Exit 127 |
| Läufe ablesen | Grün ist nicht funktionierend | `gh run view RUN_ID --log` | Gegenproben abgelehnt, Scan Exit 4 |
| Volume-Übernahme | Besitz ohne Zusatzrechte | `stat -c '%u:%g %a'` in M1–M5 | `101:101 700`, Gegenprobe `0:0 755` |
| Option lesen | Zertifikatsname | `gh api repos/go-acme/lego/contents/…?ref=v5.5.2` | `--cert.name` |
| Umbau beweisen | Verhalten unverändert | `nginx -T`, `curl.exe -D -`, `diff` | `diff` leer |

---

# Roadmap Sitzung 24

## 1. PR 2: Mountpunkte im lego-Image (E-5-80)

Warum zuerst: klein, unabhängig, und Voraussetzung dafür, dass lego auf
Staging in seine Volumes schreiben kann. Bausteine:

- `docker/lego/Dockerfile`: Verzeichnisse in der Quell-Stufe anlegen und
  `COPY --chown=101:101` in die Laufzeit-Stufe; Rechte `0700` für
  `/data/accounts`
- CODEOWNERS um `/docker/` ergänzen (offener Punkt)
- Beweis: lokaler Build, M1 gegen das echte Image, gehärteter Start;
  `publish-lego.yml` läuft nach dem Merge (`paths`) und muss bis zum Scan grün
  sein

## 2. PR 3: `compose.staging.yaml`, `nginx.staging.conf`, Prüfschritt (E-5-79, E-5-81 bis E-5-83)

Warum: setzt das Konzept um; ohne ihn kein Staging-Start. Bausteine:

- Override mit `!reset`/`!override` für `build:` und `ports:`; API-Image als
  `${API_IMAGE:?…}`; lego-Dienst mit `user: "101:101"`, drei Volumes,
  `pids_limit` für alle Dienste
- `nginx.staging.conf` aus den Snippets; Port 80 nach E-5-83; Zertifikat
  `/etc/nginx/acme/edge.crt`; `server_name.conf` von außen
- Prüfschritt in der CI: gerenderte Konfiguration prüfen (kein `build:`,
  erwartete Ports, Härtung je Dienst, Images per Digest) und `nginx -t` mit
  Wegwerf-Zertifikat und Dummy-`server_name.conf`
- Rot-Beweis als Wegwerf-PR vor dem Merge (z. B. `build:` im Override)

## 3. Interne CA auf dem Server

Warum: nginx prüft das TLS-Zertifikat der API (`proxy_ssl_verify on`); auf
Staging fehlt dafür eine CA. Klären: Erzeugung, Ablage, Pfad in
`proxy-api.conf`, Erneuerung.

## 4. Abhängig vom lego-Release: Ports 80/443 und erstes Zertifikat

Warum: E-5-74. Erst mit veröffentlichtem lego-Image möglich. Zu Beginn der
Sitzung prüfen, ob es ein neues lego-Release gibt. Wenn nicht: Punkte 5 und 6
vorziehen.

## 5. Maschinenkonto und Pull-Deploy mit Gate

Warum: braucht kein öffentliches Zertifikat und hält den Plan, falls lego
blockiert bleibt. Der Server prüft vor dem Start dieselben Bedingungen wie
`verify-attestations.sh`.

## 6. Server: Docker-Update beobachten

Warum: Docker 29.9.2 ist der Auslöser „nächstes echtes Docker-Update“; offen
seit Bericht 22.

## 7. Zurückgestellt, nicht aufgehoben

- **ADR-Nachträge:** ADR-010 (E-5-78), ADR-014 (E-5-70, E-5-71, E-5-77),
  ADR-005 (E-5-72, Cooldown), ADR-009 (`Unknown`), ADR-011, ADR-012
- **ADR zum Schritt DNS/TLS:** E-5-65 bis E-5-68, E-5-73 bis E-5-76,
  E-5-79 bis E-5-83
- **Vor Production:** NTS, IPv6 (Dual-Stack, Client-IP, Rate Limit pro `/64`,
  AAAA), zweiter Warnkanal, HSTS auf ein Jahr

## 8. Vor oder in der Sitzung zu verstehen (vor Code)

- **Compose-Merge mit `!reset` und `!override`:** Beim Zusammenführen werden
  Listen angehängt. `!reset` entfernt einen Wert der Basis, `!override`
  ersetzt ihn vollständig; das Ergebnis zeigt nur `docker compose … config`.
- **`COPY --chown` in ein distroless-Image:** Das Ziel-Image hat keine Shell;
  Verzeichnisse entstehen deshalb in der Quell-Stufe und werden mit Besitzer
  übernommen. Rechte wie `0700` müssen dort gesetzt sein.
- **Interne CA vs. öffentliches Zertifikat:** Die öffentliche Kette (Let's
  Encrypt) schützt den Weg zum Client; die interne CA schützt den Weg von
  nginx zur API. Zero Trust verlangt beide Prüfungen.
- Lehrstoff zu dieser Sitzung:
  [Zweites Image veröffentlichen, Volumes und nginx-Snippets](https://claude.ai/artifact/8n2YYUSeYxPWnFokLGbsVa)

## 9. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- Unter Profil → Packages prüfen, dass es kein Paket `identity-service-lego`
  gibt
- Satz zu `nginx/snippets/` in `.claude/rules/container-und-nginx.md` erwägen
- Gemergte lokale Branches löschen (Liste in Abschnitt 4)
- Erneuerung des Agenten-Tokens vor dem 06.11.2026 planen
