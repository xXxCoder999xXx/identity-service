# Sitzungsbericht Sitzung 24

**Datum:** 27.10.2026
**Phase:** Schritt 5 (CD): Staging-Konfiguration abgeschlossen (Mountpunkte im
lego-Image, `compose.staging.yaml`, `nginx.staging.conf`, Prüfschritt in der
CI); lego-Gate weiterhin rot, nichts von lego veröffentlicht
**Vorgänger:** sitzung-23.md (abgeschlossen 27.10.2026)

---

## 1. Erledigt

| PR | Titel | Inhalt |
|---|---|---|
| #118 | `build(lego): add volume mount points owned by uid 101` | Mountpunkte im lego-Image, `USER 101:101`, CODEOWNERS `/docker/` |
| #119 | `build(staging): add staging compose override and config check` | `compose.staging.yaml`, `nginx.staging.conf`, `scripts/test-staging-config.sh`, zwei Schritte in `ci.yml`, `pids_limit` in `compose.yaml`, CODEOWNERS |
| #120 | `test(staging): red proof build in staging override` | Wegwerf-PR (Entwurf), Rot-Beweis zu #119, geschlossen, nie gemergt |
| #121 | `ci(staging): let compose create the certificate volume` | Nachbesserung zu #119 (Warnung im CI-Log beseitigt) |

#118, #119 und #121 von der Projekt-Ownerin per Squash gemergt; überwiegend
KI-erzeugt, kein Auto-Merge.

### 1.1 lego-Release geprüft

- `go-acme/lego`: neuestes Release weiterhin v5.5.2 (23.09.2026), Stand
  27.10.2026 (`gh api repos/go-acme/lego/releases`). Das lego-Gate bleibt rot.

### 1.2 Mountpunkte im lego-Image (Roadmap-Punkt 1, #118, E-5-80, E-5-84)

- Widerspruch gefunden und aufgelöst: Das Image setzte `USER 65532:65532`,
  Workflow und Konzept nutzen UID 101. Jetzt `USER 101:101` im Image; Compose
  setzt die UID zusätzlich.
- Erster Ansatz (`COPY --chown=101:101` je Ordner) **lokal als falsch
  gemessen**: `/data/accounts` bekam `755` statt `700` (COPY legt den
  Zielordner neu an), `/data` gehörte `101` (`--chown` trifft automatisch
  angelegte Elternordner).
- Umsetzung: Besitz und Rechte vollständig in der Alpine-Stufe, Übernahme mit
  `COPY --from=lego /mounts/ /` ohne `--chown`.
- Lokal gemessen (`docker export | tar -tv --numeric-owner`):

| Pfad | Ergebnis |
|---|---|
| `/data` | `0:0 755` |
| `/data/accounts` | `101:101 700` |
| `/data/certificates` | `101:101 755` |
| `/webroot` | `101:101 755` |
| `/lego` | `0:0 755` |

- Gehärteter Start, Block aus `publish-lego.yml` unverändert ausgeführt:
  `lego version 5.5.2 linux/amd64`, Shell-Gegenprobe Exit 127, Block Exit 0.
  Start ohne `--user` Exit 0.
- M1 gegen das echte Image (Docker Desktop): neue Volumes übernehmen
  `101:101 700` bzw. `755`, Schreiben als UID 101 Exit 0. Gegenprobe UID
  65532 in `accounts`: `Permission denied`.
- PR-Checks: fünf Pflicht-Checks grün; `Image-Scan Drittanbieter (lego)` rot
  mit denselben 15 Funden High+ (3 Critical, 12 High), dazu `GO-2026-6809`
  (Unknown) und 2 Medium.
- Nach dem Merge (Commit `0a3567a`): `Publish lego` Build und gehärteter Start
  grün, Scan rot, Login, Push, Nachweise und Prüf-Gate übersprungen. `Publish`
  (API) grün. CI rot nur durch den lego-Scan.
- CI zu `33dc77e` (Bericht 23): rot nur durch den lego-Scan (offener Punkt aus
  Bericht 23 für diesen Commit erledigt).

### 1.3 Staging-Konfiguration (Roadmap-Punkt 2, #119, #121, E-5-85 bis E-5-91)

- `compose.staging.yaml`: `!override` für nginx `ports`/`volumes` und api
  `volumes`, `build: !reset null`, `ASPNETCORE_ENVIRONMENT: Production` fest,
  lego im Profil `acme` mit voller Härtung, nur Netz `public`,
  `restart: "no"`. Pflichtvariablen: `API_IMAGE`, `LEGO_IMAGE`,
  `STAGING_SERVER_NAME_FILE`, `STAGING_CA_DIR`, `STAGING_API_CERT_DIR`.
- `nginx.staging.conf`: Port 8080 (Host 80) mit Catch-all `444`, HTTP-01 nur
  `GET` aus `/var/www/acme`, sonst `308` auf `https://$server_name$request_uri`;
  Port 8443 (Host 443) mit `/etc/nginx/acme/edge.crt`, HSTS `max-age=86400`,
  Snippets; `server_name.conf` unter `/etc/nginx/site/`.
- `scripts/test-staging-config.sh`: 16 Prüfungen an der gerenderten
  Konfiguration plus Gegenprobe ohne `API_IMAGE`; Exit 2/3/4.
- `ci.yml`, Job `Container & nginx`: Schritt „Staging-Konfiguration prüfen
  (gerendert)“ und „nginx-Konfiguration Staging validieren (nginx -t)“;
  Platzhalter per YAML-Anker `&staging-env`.
- `compose.yaml`: `pids_limit` 64 (nginx), 256 (api).
- CODEOWNERS: `/compose.staging.yaml`, `/nginx.staging.conf`.

**Lokal gemessen (Docker Desktop, Compose v5.6.1):**

| Messung | Ergebnis |
|---|---|
| Gerenderte Konfiguration | entspricht dem Soll (kein `build`, Digests, Ports, Härtung, Production, lego) |
| Gegenprobe ohne `!override`/`!reset` | lokaler Port auf Loopback, lokaler Zertifikats-Bind von nginx und `build` blieben still erhalten |
| Ohne `API_IMAGE` | `required variable API_IMAGE is missing a value`, Exit 1 |
| `nginx -t` Staging | erfolgreich |
| Port 80, bekannter Host | `308` auf `https://<server_name>/health?x=1` |
| Port 80, fremder oder fehlender Host | Verbindung ohne Antwort (curl 52) |
| Challenge GET / POST / fehlend | `200` mit Token / `403` / `404` |
| Traversal `../../etc/passwd` | bereinigt, `308` auf den eigenen Host |
| Port 443, passende SNI | HSTS `max-age=86400` (`502` erwartet, keine API in der Probe) |
| Port 443, fremde SNI | Handshake abgewiesen (curl 35) |
| Port 443, passende SNI, fremder Host | generisches `404` aus dem Catch-all |
| `pids_limit` | gesetzt; nginx 17 PIDs, api 16 im Leerlauf; 80 Prozesse in nginx: `Cannot fork`, `/health` danach 200 |

**CI:**

- #119: alle 16 Prüfungen und die Gegenprobe im Log, `nginx -t` Staging
  erfolgreich, YAML-Anker funktioniert. Warnung `volume … was not created by
  Docker Compose` im Log; behoben mit #121.
- Rot-Beweis #120 (`build:` bei lego): `Container & nginx` rot,
  `Verletzt: kein Dienst hat build (Dienste: lego)`, Exit 3, Folgeschritte
  übersprungen. PR geschlossen.
- #121: Warnung verschwunden (`Volume "identity-service_tls-certificates"
  Created`), alle Schritte grün.
- Nach den Merges (`ede668e`, `2d99867`): `Publish` grün, CodeQL grün, CI rot
  nur durch den lego-Scan.

### 1.4 lego-Schlüsseltyp

Quellcode lego v5.5.2 (`cmd/internal/flags/flags.go`): Standard für
`--key-type` ist `certcrypto.EC256`. Passt zu `tls.conf` (nur ECDSA-Suiten).

### 1.5 Lehrstoff

- [Lehrstoff: Staging-Konfiguration und Mountpunkte im lego-Image](https://claude.ai/artifact/McJ5HYq2WkhLd8DF4N34Ft)
  (Mountpunkte ohne Shell, Compose-Merge, Prüfskript und Rot-Beweis, nginx
  Port 80 mit Diagramm, `pids_limit`, Fehler der Sitzung, Spickzettel)
- Kurzfassung als Seite: [Mountpunkte im lego-Image](https://claude.ai/artifact/M92LWQBG8kJymUUMqAFewo)

---

## 2. Gelernt

- `COPY` eines Ordners kopiert nur seinen Inhalt; der Zielordner entsteht neu
  mit Standardrechten.
- `COPY --chown` gilt auch für automatisch angelegte Elternordner.
- Besitz und Rechte eines Images ohne Shell liest man mit `docker export` und
  `tar -tv --numeric-owner`.
- Ein grüner Build sagt nichts über Rechte im Image.
- Compose hängt Listen beim Zusammenführen an; `volumes` werden über das Ziel
  zusammengeführt, Einträge mit anderem Ziel bleiben stehen.
- `!override` ersetzt einen Wert vollständig, `!reset` entfernt ihn.
- `${VAR:?Meldung}` lässt Compose abbrechen, wenn die Variable fehlt.
- Eine Prüfung auf die gerenderte Konfiguration findet Fehler, die in keiner
  einzelnen Datei sichtbar sind.
- Eine Prüfung ist erst durch einen Rot-Beweis belegt.
- `$server_name` stammt aus der Konfiguration, `$host` aus der Anfrage; nur
  Ersteres taugt als Weiterleitungsziel.
- `pids_limit` zählt Prozesse und Threads; `worker_processes auto` richtet sich
  nach den Kernen des Hosts, nicht nach `cpus`.
- Ein von Hand angelegtes Volume quittiert Compose mit einer Warnung; legt
  Compose es an, trägt es das Label `com.docker.compose.volume`.
- Git Bash schreibt Pfade wie `/bin/sh` in Argumenten um;
  `MSYS_NO_PATHCONV=1` schaltet das ab.
- `git switch -c NAME origin/main` setzt `origin/main` als Upstream.
- Bei einem roten Job zählt der Schritt mit dem Exit-Code, nicht die erste
  Fehlerzeile.
- GitHub Actions unterstützt YAML-Anker (`&name`, `*name`) in Workflows
  (belegt durch den Lauf zu #119).

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-84** | CODEOWNERS auf Ordnerebene `/docker/`, im selben PR wie die Änderung am lego-Image | Besitz wird mit der Änderung festgelegt; künftige Images automatisch erfasst |
| **E-5-85** | `pids_limit` in der Basis `compose.yaml` (nginx 64, api 256, lego 64) | Härtung lokal, in CI und auf Staging gleich |
| **E-5-86** | Im Override `!override` für Listen, `!reset` für `build` | gemessen: ohne sie bleiben lokaler Port, lokaler Zertifikats-Bind und `build` |
| **E-5-87** | Staging fest auf `ASPNETCORE_ENVIRONMENT: Production` | Development zeigt Stacktraces (A10); Production ist der in der CI getestete Modus |
| **E-5-88** | lego als Compose-Dienst im Profil `acme`, gestartet nur per `run --rm` vom Timer; `restart: "no"` | kein Dauerprozess; kein Neustart-Kreislauf gegen Rate Limits |
| **E-5-89** | HSTS auf Staging `max-age=86400`, ohne `includeSubDomains` und `preload` | genug für Messungen und DAST, begrenzter Schaden bei Zertifikatsausfall |
| **E-5-90** | `limits.conf` auch auf Port 80 | Port 80 ist genauso öffentlich |
| **E-5-91** | `scripts/test-staging-config.sh` prüft die gerenderte Konfiguration, aufgerufen im Pflicht-Check `Container & nginx`; später auch auf dem Server | Ruleset unverändert; eine Quelle der Regeln für CI und Deploy |

Empfehlung ohne endgültige Entscheidung: erstes Zertifikat mit lego im
Standalone-Modus bei gestopptem nginx, danach sofort ein erzwungener Renew über
den Webroot (Henne-Ei-Problem); entschieden wird beim ersten Zertifikat.

ADR-Kandidaten: E-5-84 bis E-5-91 gehören mit E-5-65 bis E-5-68, E-5-73 bis
E-5-76 und E-5-79 bis E-5-83 in das ADR zum Schritt DNS/TLS.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- `worker_processes auto` startet einen Worker je Kern des Hosts; lokal 17
  PIDs. Auf einem Host mit mehr als rund 60 Kernen scheitert nginx an
  `pids_limit: 64`. Kernzahl des Servers beim ersten Staging-Start prüfen;
  fester Wert wäre ein eigener PR.
- `pids_limit: 256` der API ohne Last gemessen; keine Gegenprobe für die API.
- `scripts/test-staging-config.sh` lokal nicht lauffähig (`jq` fehlt); Beleg
  nur über CI. Auf dem Server muss `jq` vorhanden sein, bevor das Skript dort
  läuft.
- lego-Dienst ohne `tmpfs`: ob lego als UID 101 mit `read_only` ein
  beschreibbares `/tmp` braucht, beim ersten Lauf messen.
- Woher die Pflichtvariablen auf dem Server kommen (z. B. `.env` neben den
  Compose-Dateien) und wo `server_name.conf` liegt: festlegen beim
  Pull-Deploy. Keine der Variablen ist ein Secret.
- `proxy-api.conf` verweist auf `/etc/nginx/ca/local-dev-ca.crt`; der
  Dateiname ist auf Staging irreführend (Roadmap-Punkt 1).
- `--key-type ec256` im Timer-Befehl ausdrücklich setzen.
- Catch-all auf 443 antwortet bei passender SNI und fremdem Host mit einem
  generischen 404 ohne Security-Header (kein Inhalt preisgegeben; gleiches
  Verhalten wie lokal).
- Prüfskript prüft die Netze der API nicht (nur lego); mögliche Erweiterung.
- `.claude/rules/container-und-nginx.md` nennt nur `compose.yaml` und
  `nginx.conf`; ein Satz zu `nginx/snippets/`, `compose.staging.yaml` und
  `nginx.staging.conf` wäre sinnvoll (Entscheidung der Projekt-Ownerin).
- Remote-Branch `test/staging-red-proof` existiert noch (Löschen per `!`).
- Lokale gemergte Branches löschen (Freigabe nötig): `build/lego-image`,
  `build/sdk-10-0-403`, `docs/adr-013-alert-channel`,
  `docs/adr-014-third-party-image-gate`, `docs/sitzung-21`, `docs/sitzung-22`,
  `docs/sitzung-23`, `docs/report-22-unknown-severity`,
  `ci/publish-lego-image`, `refactor/nginx-snippets`, neu
  `build/lego-volume-mountpoints`, `build/staging-compose`,
  `test/staging-red-proof`, `ci/staging-volume-warning`.

**Aus Sitzung 23 und früher, weiter offen**

- **lego-Gate rot** bis zu einem lego-Release mit Go ≥ 1.27.3 und `x/net` ≥
  0.60.0. Jeder CI-Lauf auf `main` ist rot; bei jedem roten Lauf prüfen, ob es
  nur `Image-Scan Drittanbieter (lego)` ist. Für `1a3fc3c` nicht einzeln
  geprüft; `33dc77e`, `0a3567a`, `ede668e`, `2d99867` geprüft.
- `Publish lego` grün noch nie gelaufen: Push, Nachweise und Prüf-Gate für lego
  ungetestet.
- M1 und M2 unter rootless Docker auf dem Server wiederholen (beim ersten
  Staging-Start); in dieser Sitzung M1 gegen das echte Image nur unter Docker
  Desktop.
- Push- und Digest-Logik doppelt in `publish.yml` und `publish-lego.yml`.
- Gegenproben in `verify-attestations.sh` akzeptieren jeden Fehler von
  `gh attestation verify`, auch einen Netzfehler.
- Paketliste in GHCR nicht abrufbar (Agenten-Token ohne `read:packages`);
  Sichtprüfung unter Profil → Packages nicht bestätigt.
- `Test-Stack.ps1` lokal nicht lauffähig (Hook blockiert `-CaFile`).
- Nachtrag zu ADR-009 (`Unknown`), ADR-005 (Cooldown), ADR-010 (E-5-78),
  ADR-014 (E-5-70, E-5-71, E-5-77), ADR-011, ADR-012
- Release Notes von #106 (CodeQL) und #108 (Grype v0.121.0) nicht gemeinsam
  gelesen
- Docker 29.9.2 auf dem Server nicht gemessen
- CVE-2026-111943 bei NVD und CISA KEV nicht geprüft
- `Image-Scan Drittanbieter` als Required Check: fällig vor dem ersten Deploy
  von lego
- ADR-006, ADR-008, ADR-012, ADR-013, ADR-014 auf „Vorgeschlagen“
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
  `nft-rollback.service`; Maschinenkonto
- **Token des Agenten läuft am 06.11.2026 ab** (in 10 Tagen)

**Bekannte Grenzen**

- Alle Messungen dieser Sitzung unter Docker Desktop, nicht unter rootless
  Docker auf dem Server.
- `docker compose config` beweist die Konfiguration, nicht das Verhalten auf
  dem Server; der erste Staging-Start steht aus.
- Domain, Server-IPs und Hostnamen stehen bewusst nicht in diesem Bericht
  (öffentliches Repository, ADR-004); in Messungen wurde
  `staging.example.invalid` verwendet.

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Neu: Staging-Konfiguration vollständig und in jedem
Pull Request geprüft; lego-Image mit Mountpunkten.

Bis zum Beginn von Phase 5 fehlen:

| Nr. | Schritt | Abhängig von |
|---|---|---|
| 1 | ~~Staging-Konfiguration~~ erledigt (#118, #119, #121) | – |
| 2 | Interne CA auf dem Server (nginx → API) | – |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer (E-5-76) | 2, **veröffentlichtes lego-Image** |
| 4 | Maschinenkonto (ADR-011) | – |
| 5 | Pull-Deploy mit Prüfung von Nachweis, Signatur und Staging-Konfiguration | 2, 4 |
| 6 | Freigabe vor dem Deploy, DORA-Events | 5 |
| 7 | DAST (OWASP ZAP) | 5, 6 |

Bleibt lego blockiert: 4 bis 6 nach Schritt 2 vorziehen.

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: keine neue Abhängigkeit (`jq` ist Runner-Bordmittel); Digest-Pflicht für Staging-Images jetzt maschinell geprüft |
| **Image-Gate für fremde Images** | lego rot (15 Funde), nginx grün; noch kein Required Check |
| **Zero Trust / A01** | Port-80-Aufbau gemessen: unbekannte Hosts 444, keine lenkbare Weiterleitung, fremde SNI abgewiesen |
| **A10 / fail closed** | Staging fest auf Production; Pflichtvariablen brechen ab |
| **A09 (Alerting)** | unverändert; Erneuerung über ADR-013 geplant (E-5-76) |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** (OWASP ZAP) | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant); interne CA ist Vorstufe zu mTLS |
| **Feature Flags** | Nicht fällig |
| **Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (27.10.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| lego, neuestes Release | v5.5.2 (23.09.2026) | `gh api repos/go-acme/lego/releases` |
| lego `--key-type` Standard | `EC256` | `cmd/internal/flags/flags.go` @ v5.5.2 |
| Docker Compose lokal | v5.6.1 | `docker compose version` |
| `main` nach der Sitzung | `2d99867` | `git log` |

Keine neuen Digests oder Action-Pins in dieser Sitzung.

### 6.2 lego-Image

| Pfad | Besitz und Rechte |
|---|---|
| `/data` | `0:0 755` |
| `/data/accounts` | `101:101 700` |
| `/data/certificates` | `101:101 755` |
| `/webroot` | `101:101 755` |
| `/lego` | `0:0 755` |
| `Config.User` | `101:101` |

### 6.3 Staging

```
docker compose -f compose.yaml -f compose.staging.yaml up -d
docker compose -f compose.yaml -f compose.staging.yaml run --rm lego ...
bash scripts/test-staging-config.sh
```

| Pflichtvariable | Inhalt |
|---|---|
| `API_IMAGE` | API-Image per Digest |
| `LEGO_IMAGE` | lego-Image per Digest |
| `STAGING_SERVER_NAME_FILE` | Datei mit `server_name <name>;` |
| `STAGING_CA_DIR` | Ordner der internen CA (Mount `/etc/nginx/ca`) |
| `STAGING_API_CERT_DIR` | Zertifikat und Schlüssel der API (Mount `/certs`) |

| Mount in nginx | Quelle |
|---|---|
| `/etc/nginx/nginx.conf` | `./nginx.staging.conf` |
| `/etc/nginx/snippets` | `./nginx/snippets` |
| `/etc/nginx/site/server_name.conf` | `STAGING_SERVER_NAME_FILE` |
| `/etc/nginx/ca` | `STAGING_CA_DIR` |
| `/etc/nginx/acme` | Volume `tls-certificates` (ro) |
| `/var/www/acme` | Volume `acme-webroot` (ro) |

Exit-Codes `test-staging-config.sh`: 2 Voraussetzung/Rendern, 3 Regel
verletzt, 4 Gegenprobe akzeptiert.

### 6.4 Fallstricke, die Zeit gekostet haben

- Hook `Protect-Secrets` blockiert jeden Bash-Befehl, der das Wort `certs`
  enthält, auch in PR-Texten per Heredoc; PR-Text mit dem Write-Werkzeug in
  eine Datei schreiben und `--body-file` nutzen.
- `gh api -X DELETE …/git/refs/…` ist für den Agenten gesperrt; Branches
  löscht die Projekt-Ownerin per `! git push origin --delete BRANCH`.
- Git Bash: `/bin/sh` wird zu `C:/Program Files/Git/usr/bin/sh`; lokal
  `MSYS_NO_PATHCONV=1`.
- Branch von `origin/main` folgt `origin/main`; erster Push mit `-u`.
- Nachbesserung nach dem Merge: #119 wurde gemergt, während die Korrektur noch
  lokal lag; der Push legte den gelöschten Branch neu an. Reparatur über
  neuen Branch vom aktuellen `main` (#121).

### 6.5 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Rechte im Image | Build beweist keine Rechte | `docker export ID \| tar -tv --numeric-owner -f -` | `accounts` 755 → nach Umbau 700 |
| Gehärteter Start | wie im Workflow | Block aus `publish-lego.yml` per `bash -c` | Version 5.5.2, Exit 127 |
| M1 echtes Image | Volume-Übernahme | lego bindet zuerst ein, nginx schreibt als 101 | `101:101 700`, Exit 0 |
| Merge-Gegenprobe | `!override` nötig? | `sed` entfernt Tags, `docker compose config` | lokaler Port und Bind bleiben |
| Port-80-Verhalten | Grün ist nicht funktionierend | `docker compose run -p …`, `curl.exe -H Host:` | 308, 444, 200/403/404 |
| `pids_limit` | Grenze wirkt? | 80 × `sleep &` im Container | `Cannot fork`, Health 200 |
| Rot-Beweis | Prüfung kann rot werden | Wegwerf-PR #120 | Exit 3, Folgeschritte übersprungen |

---

# Roadmap Sitzung 25

## 1. Interne CA auf dem Server (nginx → API)

Warum zuerst: Ohne CA kann nginx auf Staging das TLS-Zertifikat der API nicht
prüfen (`proxy_ssl_verify on`); `STAGING_CA_DIR` und `STAGING_API_CERT_DIR`
sind Pflicht, haben aber noch keinen Inhalt. Hängt nicht von lego ab. Klären:

- Erzeugung (Werkzeug auf dem Server, Schlüsseltyp ECDSA P-256 wie lokal),
  Ablage und Rechte des CA-Schlüssels, Laufzeit von CA und API-Zertifikat
- SAN `api` (Kopplung Service-Name, SAN, `proxy_ssl_name`)
- Dateiname in `proxy-api.conf` neutral (z. B. `internal-ca.crt`): lokal,
  CI-Skript `new-throwaway-certificates.sh` und Staging in **einem** PR
- Erneuerung und Warnung bei Ablauf (ADR-013)
- Vor sicherheitsrelevanten Werkzeugentscheidungen: Aktualität nach CLAUDE.md
  Abschnitt 1

## 2. lego-Release prüfen; wenn neu: Ports 80/443 und erstes Zertifikat

Warum: E-5-74. Zu Beginn der Sitzung prüfen, ob es ein lego-Release mit
Go ≥ 1.27.3 und `x/net` ≥ 0.60.0 gibt. Wenn ja: Dependabot-PR bzw. Pin
anheben, `Publish lego` grün, dann erstes Zertifikat (Henne-Ei-Problem,
Empfehlung Standalone + sofortiger Webroot-Renew), M1/M2 unter rootless
Docker, Kernzahl für `worker_processes` prüfen. Wenn nein: Punkte 3 und 4
vorziehen.

## 3. Maschinenkonto und Pull-Deploy mit Gate

Warum: braucht kein öffentliches Zertifikat und hält den Plan, falls lego
blockiert bleibt. Der Server prüft vor dem Start: Nachweise wie
`verify-attestations.sh` und die Konfiguration mit `test-staging-config.sh`
(`jq` auf dem Server). Festlegen, wo die Pflichtvariablen liegen.

## 4. Server: Docker-Update beobachten

Warum: Docker 29.9.2 ist der Auslöser „nächstes echtes Docker-Update“; offen
seit Bericht 22.

## 5. Kleine Folge-PRs (nach Bedarf)

- `worker_processes` fest setzen, falls die Kernzahl des Servers es nahelegt
- Regel-Satz in `.claude/rules/container-und-nginx.md` (Entscheidung der
  Projekt-Ownerin)
- Push- und Digest-Logik aus `publish.yml` und `publish-lego.yml` zusammenführen
- Gegenproben in `verify-attestations.sh` auf den erwarteten Fehler eingrenzen

## 6. Zurückgestellt, nicht aufgehoben

- **ADR-Nachträge:** ADR-010 (E-5-78), ADR-014 (E-5-70, E-5-71, E-5-77),
  ADR-005 (E-5-72, Cooldown), ADR-009 (`Unknown`), ADR-011, ADR-012
- **ADR zum Schritt DNS/TLS:** E-5-65 bis E-5-68, E-5-73 bis E-5-76,
  E-5-79 bis E-5-91
- **Vor Production:** NTS, IPv6 (Dual-Stack, Client-IP, Rate Limit pro `/64`,
  AAAA), zweiter Warnkanal, HSTS auf ein Jahr

## 7. Vor oder in der Sitzung zu verstehen (vor Code)

- **Interne CA vs. öffentliches Zertifikat:** Let's Encrypt schützt den Weg vom
  Client zu nginx; die interne CA schützt den Weg von nginx zur API. Zero Trust
  verlangt beide Prüfungen, auch im internen Netz `edge`.
- **Kopplung Service-Name, SAN, `proxy_ssl_name`:** nginx prüft, dass das
  Zertifikat der API auf den Namen `api` lautet. Ändert sich einer der drei
  Werte allein, scheitert jede Anfrage; sie ändern sich nur gemeinsam.
- **CA-Schlüssel als sensibelstes Artefakt:** Wer ihn hat, kann Zertifikate
  ausstellen, denen nginx vertraut. Er liegt nie im Repository, nie im Image
  und nie in einem Container, der ihn nicht braucht.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Staging-Konfiguration und Mountpunkte im lego-Image](https://claude.ai/artifact/McJ5HYq2WkhLd8DF4N34Ft)

## 8. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- Remote-Branch `test/staging-red-proof` und gemergte lokale Branches löschen
  (Liste in Abschnitt 4)
- Erneuerung des Agenten-Tokens vor dem 06.11.2026 planen
- Unter Profil → Packages prüfen, dass es kein Paket `identity-service-lego`
  gibt
