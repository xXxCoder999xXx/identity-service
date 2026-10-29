# Sitzungsbericht Sitzung 26

**Datum:** 29.10.2026
**Phase:** Schritt 5 (CD): Staging-CA auf dem Server in Betrieb, API-Zertifikat
ausgestellt, täglicher Erneuerungs-Timer mit Totmannschalter aktiv (#127,
#128); API-Neustart nach Erneuerung fehlt noch (Frist 27.12.2026); lego-Gate
weiterhin rot (kein neues Release)
**Vorgänger:** sitzung-25.md (abgeschlossen 28.10.2026)

---

## 1. Erledigt

| PR | Titel | Inhalt |
|---|---|---|
| #127 | `feat(tls): add staging internal ca and api certificate scripts` | `scripts/new-internal-ca.sh`, `scripts/issue-api-certificate.sh` |
| #128 | `feat(tls): add daily api certificate renewal timer with dead man's switch` | `scripts/renew-api-certificate.sh`, `scripts/systemd/identity-service-api-cert.{service,timer}` |

Beide von der Projekt-Ownerin per Squash gemergt (`e68e741`, `fbbaa78`;
GitHub-Signatur „verified“); überwiegend KI-erzeugt, kein Auto-Merge.

### 1.1 Messungen auf dem Server (Roadmap-Punkt 1)

| Messung | Ergebnis |
|---|---|
| openssl | `3.5.7-1~deb13u3` (openssl und libssl3t64) aus trixie-security, kein Update ausstehend |
| CVE-2026-84782 | laut Debian-Tracker behoben in deb13u3 (DSA-6531-1) |
| CVE-2026-84783 | laut Debian-Tracker nicht betroffen |
| CVE-2026-63072 | laut Debian-Tracker behoben in deb13u2 (DSA-6465-1) |
| Docker-Daemon | genau ein `dockerd`, läuft als Docker-Benutzer (UID 1001); kein root-Docker |
| `/etc/subuid` | Docker-Benutzer: Start 165536, Anzahl 65536 |
| `uid_map` des Daemons | `0 1001 1` und `1 165536 65536` |
| Container-UID der API | 1654 (`Config.User` des lokalen Images) → **Host-UID 167189** |
| `nproc` | 2; `worker_processes auto` bleibt (offener Punkt aus Bericht 24 erledigt) |

### 1.2 Skripte für CA und API-Zertifikat (#127)

- `new-internal-ca.sh SCHLUESSEL_ORDNER CA_ORDNER`: `umask 077`, eigene
  `-config`, ECDSA P-256, 365 Tage, `basicConstraints critical CA:TRUE
  pathlen:0`, `keyUsage critical keyCertSign,cRLSign`, `nameConstraints
  critical permitted;DNS:api`; Aufbau im Temp-Ordner, Selbstprüfung, dann
  `mv`. Exit-Codes: 0 ok, 2 Aufruf, 3 CA existiert, 4 nicht root,
  5 Selbstprüfung, 6 Schlüssel-Ordner nicht `0 0 700`.
- `issue-api-certificate.sh SCHLUESSEL_ORDNER CA_ORDNER API_ORDNER
  API_HOST_UID`: Exit-Codes 0 ausgestellt, 10 noch gültig, 2 Aufruf, 3 CA
  fehlt, 4 nicht root, 5 Selbstprüfung, 6 API-Ordner nicht root bzw. für
  Gruppe/andere beschreibbar, 7 CA läuft in weniger als 90 Tagen ab.
  Erneuert, wenn das Paar fehlt, weniger als 30 Tage gilt, nicht von der
  aktuellen CA stammt oder der Schlüssel nicht passt. P-256, 90 Tage, SAN nur
  `DNS:api`, serverAuth, digitalSignature, CA:FALSE. Schlüssel
  `API_HOST_UID:0 0400`, Zertifikat `0:0 0444`.
- Keine `.srl`-Datei: Ohne `-CAserial` vergibt openssl eine zufällige
  Seriennummer (Doku 3.5 und Messung).
- Alle Exit-Pfade im gepinnten SDK-Image mit `--network none` getestet;
  `nameConstraints` gemessen: ein Zertifikat für einen anderen Namen scheitert
  mit `permitted subtree violation`.

### 1.3 Installation und Inbetriebnahme der CA

- Installation nach E-5-56/E-5-99: lokal `main`, Hash aus dem Commit, `scp`,
  `sha256sum -c`, `sudo install -m 0755 -o root -g root` nach
  `/usr/local/sbin` (`root:root 755`), erneut hashen, Kopien löschen.
- Ordner per `sudo mkdir -m 0755`: `/etc/identity-service`,
  `/etc/identity-service/ca`, `/etc/identity-service/api-tls` (alle
  `root:root 0755`). `ca-private` (`0700`) hat das Skript angelegt.
- CA: Schlüssel `/etc/identity-service/ca-private/internal-ca.key`
  (`0:0 0400`), Zertifikat `/etc/identity-service/ca/internal-ca.crt`
  (`0:0 0644`), notAfter 28.10.2027 07:21:49 GMT. Zweiter Lauf: Exit 3.
- API-Zertifikat: `api.key` (`167189:0 400`), `api.crt` (`0:0 444`), notAfter
  26.01.2027 07:24:48 GMT. Zweiter Lauf: Exit 10.
- Gegenprobe mit `setpriv`: UID 167189 liest den Schlüssel; UID 165636 (nginx)
  und 1001 (Docker-Benutzer) erhalten „Permission denied“.

### 1.4 Erneuerungs-Timer mit Totmannschalter (#128)

- `renew-api-certificate.sh` (Hülle): Exit 10 → ok-Ping; Exit 0 →
  `restart_api` (heute Platzhalter `return 1`) → `/fail` „Zertifikat erneuert,
  API-Neustart nicht eingerichtet oder gescheitert“; sonst → `/fail`
  „issue-api-certificate exit N“. Ping per `curl -K -` (URL nie in der
  Kommandozeile), logger-Tag `identity-service-api-cert`.
- Service: `Type=oneshot`, Argumente fest in `ExecStart` (API-UID 167189),
  `LoadCredential=ping-url:/etc/credstore/identity-service-api-cert.ping-url`,
  `TimeoutStartSec=2min`, Sandbox (E-5-102).
- Timer: `OnCalendar=daily`, `RandomizedDelaySec=1h`, `Persistent=true`.
- Installiert: Hülle in `/usr/local/sbin` (0755), Units in
  `/etc/systemd/system` (0644); `systemd-analyze verify` Exit 0;
  `daemon-reload`; Timer enabled, erster Lauf geplant 29.10.2026 00:21:07 CET.
- Credential-Datei mit `sudo install -m 0600 -o root -g root /dev/null …`
  angelegt, URL per `sudoedit` eingetragen; geprüft nur über Format, Größe
  und Rechte (`root:root 600 57`, eine Zeile).

| Gegenprobe | Ergebnis |
|---|---|
| Echter Start der Unit | `Result=success`, Ping kam vom Server, Laufzeit unter 1 s; `logger` funktioniert unter `PrivateDevices` |
| `systemd-run --wait` mit ungültiger UID | Exit 1, Check sofort „down“, Mail mit Text „issue-api-certificate exit 2“ |
| Credential-Datei fehlt | `243/CREDENTIALS` nach 24 ms, kein Start |
| Periode und Grace auf je 1 min | Mail „DOWN … grace time passed“ genau 2 min nach dem letzten Ping |

### 1.5 Vorfall: Ping-URL im Browser-Verlauf, Rotation

- Ein Ping ohne zugehörigen Lauf im Journal kam von einer fremden Adresse
  (eigener Anschluss der Projekt-Ownerin): Die URL war versehentlich
  angeklickt worden und lag damit im Browser-Verlauf.
- Rotation: neuer Check `staging-api-cert-2` (Periode 1 Tag, Grace 3 Stunden,
  E-Mail aktiv), URL per `sudoedit` eingetragen und geprüft, Start → „up“ vom
  Server; alter Check `staging-api-cert` gelöscht; Verlauf und Zwischenablage
  bereinigt. Die übrigen Ereignisse kamen nachweislich vom Server.

### 1.6 lego-Release geprüft (Roadmap-Punkt 2)

| Prüfung | Ergebnis | Quelle |
|---|---|---|
| neuestes Release | v5.5.2 (23.09.2026), unverändert | GitHub-Releases `go-acme/lego` |
| Image unter `v5.5.2` | Index-Digest gleich unserem Pin, zuletzt gepusht 23.09.2026 | `docker buildx imagetools inspect`, Docker Hub |
| `x/net` in v5.5.2 / auf `main` | v0.59.0 / **v0.61.0** (Abhängigkeits-Update #3329 am 27.10.2026) | `go.mod` |
| Go im Release-Build | `GO_VERSION: stable`; aktuell go1.27.3 | `release.yml`, go.dev |

Ergebnis: Der Fix liegt auf lego-`main`, ist aber nicht veröffentlicht. Kein
eigener Build von `main` (unveröffentlichter Code, neues Pipeline-Werkzeug,
geringer Gewinn). Dependabot öffnet beim nächsten Tag einen PR; der lego-Scan
läuft darin automatisch.

### 1.7 CI bei #127 und #128

Alle Pflicht-Checks grün. `Image-Scan Drittanbieter (lego)` rot im bekannten
Schritt „Image scannen (Bericht, Blindheits-Schutz, Gate)“, Exit 4 (go1.27.1,
x/net v0.59.0, u. a. GO-2026-6612/6604 Critical); Blindheits-Schutz ok
(debian, 6 deb, 203 golang). Bei #128 dauerte der Job 6,5 Minuten, ohne neuen
Befund.

### 1.8 Lehrstoff

- [Lehrstoff: Staging-CA, Erneuerungs-Timer und Totmannschalter](https://claude.ai/artifact/P8pEtstmPm5ZZt9ztTskDi)
  (Backports, UID-Abbildung mit Diagramm, zwei Skripte und Exit-Codes,
  Installation mit Hash, Totmannschalter mit Ablaufdiagramm, Sandbox,
  Gegenproben, Rotation, lego-Prüfung, Fallen, Spickzettel)

---

## 2. Gelernt

- Bei Distributionspaketen entscheidet die Paket-Revision im Security-Tracker,
  ob eine CVE behoben ist, nicht die Upstream-Versionsnummer (Backports).
- Unter rootless Docker gilt: Host-UID = subuid-Start + Container-UID − 1;
  ablesbar in `/proc/PID/uid_map` des Daemons.
- Ohne `-CAserial` vergibt `openssl x509 -req` eine zufällige Seriennummer und
  schreibt keine `.srl`-Datei.
- `nameConstraints` wirkt bei `openssl verify` als „permitted subtree
  violation“; damit lässt sich die Beschränkung messen.
- Glob `*` und Umleitung `<` wertet die eigene Shell vor `sudo` aus, also ohne
  root-Rechte; in root-Ordnern explizite Pfade verwenden.
- `LoadCredential` startet einen Dienst gar nicht (`243/CREDENTIALS`), wenn
  die Quelldatei fehlt; die Stille alarmiert dann über den Totmannschalter.
- `logger` funktioniert auch unter `PrivateDevices=yes`.
- `curl -K -` liest Optionen samt URL aus der Standardeingabe; die URL steht
  so in keiner Prozessliste.
- Healthchecks.io zeigt die Quell-Adresse jedes Pings; damit lassen sich
  fremde Pings vom Server unterscheiden.
- Ein Geheimnis, das an einem unkontrollierten Ort lag (Browser-Verlauf), wird
  rotiert, nicht nur dort gelöscht.
- „Auf main behoben“ ist bei einem fremden Projekt nicht „ausgeliefert“; der
  Index-Digest unter dem Tag zeigt, ob ein Image neu gebaut wurde.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-99** | Host-Skripte bis zum Pull-Deploy nach E-5-56: nur von `main`, Signatur des Merge-Commits prüfen, Hash vor und nach `install`, Ziel `/usr/local/sbin` `root:root 0755` | root führt nur aus, was nur root ändern kann; Inhalt belegt identisch mit dem Geprüften |
| **E-5-100** | Ordner `/etc/identity-service/{ca,api-tls}` `root:root 0755` per `mkdir` von Hand | Skripte melden falsche Rechte statt sie zu reparieren; Anlage bewusst, nicht nebenbei |
| **E-5-101** | Exit 10 (noch gültig) und 7 (CA läuft bald ab); Hülle mit ok-Ping und `/fail`; fehlender API-Neustart meldet `/fail` | Erfolg ohne Wirkung wird nicht als Erfolg gemeldet (A09, fail closed) |
| **E-5-102** | Sandbox der Unit: nur `api-tls` beschreibbar, CA nur lesbar, drei Capabilities (`CAP_CHOWN`, `CAP_FOWNER`, `CAP_DAC_OVERRIDE`) | ein Fehler im Skript kann die CA nicht verändern; Erweiterung erst mit dem Neustart |
| **E-5-103** | systemd-Units versioniert unter `scripts/systemd/` | dieselben Gates und CODEOWNERS wie Skripte; Server-Stand nachvollziehbar |
| **E-5-104** | Eigener Healthchecks.io-Check pro Job; Rotation, sobald eine Ping-URL an einem unkontrollierten Ort war | wer die URL kennt, kann den Alarm unterdrücken (ADR-013) |

ADR-Kandidaten: E-5-92 bis E-5-104 gehören mit E-5-65 bis E-5-68, E-5-73 bis
E-5-76 und E-5-79 bis E-5-91 in das ADR zum Schritt DNS/TLS.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **API-Neustart nach Erneuerung bis spätestens 27.12.2026** (erste
  Erneuerung bei weniger als 30 Tagen Restlaufzeit). `restart_api` in
  `scripts/renew-api-certificate.sh` ist ein Platzhalter (`return 1`) und
  meldet heute `/fail`. Kommt mit dem Pull-Deploy; danach die Sandbox gezielt
  erweitern.
- Erster echter Timer-Lauf (geplant 29.10.2026 00:21 CET) nicht geprüft:
  `systemctl list-timers`, Journal und Ereignis bei Healthchecks.io ansehen.
- `user: "1654:1654"` für `api` in `compose.staging.yaml` (Folge-PR), damit
  die UID nicht nur vom Image abhängt.
- `.claude/rules/skripte.md`: Bash auf dem Server ausdrücklich erlauben
  (Entscheidung der Projekt-Ownerin).
- Server: `PermitRootLogin` prüfen (im Shell-Verlauf stehen `ssh root@…`);
  `unattended-upgrades` prüfen.
- Units von host-health-check stehen nicht im Repository (vgl. E-5-103).
- CI-Job, der die Bash-Skripte ausführt (Exit-Pfade), würde `ci.yml` ändern.
- Lokale lego-Images `identity-service-lego:local` und `:publish` mit UID 65532
  sind veraltet.
- Lokale gemergte Branches `feat/staging-internal-ca` und
  `feat/api-cert-renewal-timer` (remote gelöscht) löschen (Freigabe nötig).
- CA-Wechsel: CA läuft am 28.10.2027 ab; `issue-api-certificate.sh` meldet
  ab 90 Tagen vorher Exit 7. Wechsel mit Übergangszeit (beide CAs) rund zehn
  Monate nach Erzeugung planen.
- Ob Kestrel ein erneuertes Zertifikat ohne Neustart einliest: weiter nicht
  gemessen (kein Stack auf dem Server).

**Aus Sitzung 25 und früher, weiter offen**

- **lego-Gate rot** bis zu einem lego-Release mit Go ≥ 1.27.3 und `x/net` ≥
  0.60.0 (Stand 29.10.2026: kein Release, Fix auf lego-`main`).
- `Publish lego` grün noch nie gelaufen.
- `pids_limit: 256` der API ohne Gegenprobe.
- `scripts/test-staging-config.sh` lokal nicht lauffähig (`jq` fehlt); auf dem
  Server muss `jq` vorhanden sein.
- lego ohne `tmpfs`: beim ersten Lauf messen; `--key-type ec256` im
  lego-Timer ausdrücklich setzen.
- Herkunft der Pflichtvariablen auf dem Server und Ort von
  `server_name.conf`: beim Pull-Deploy.
- Catch-all 443 mit passender SNI und fremdem Host: generisches 404 ohne
  Security-Header.
- Prüfskript prüft die Netze der API nicht.
- M1 und M2 unter rootless Docker auf dem Server wiederholen.
- Push- und Digest-Logik doppelt in `publish.yml` und `publish-lego.yml`.
- Gegenproben in `verify-attestations.sh` akzeptieren jeden Fehler.
- Paketliste in GHCR nicht abrufbar (Token ohne `read:packages`).
- `Test-Stack.ps1` lokal nicht lauffähig (Hook blockiert `-CaFile`).
- Nachträge zu ADR-005, ADR-009, ADR-010, ADR-011, ADR-012, ADR-014;
  ADR-006, ADR-008, ADR-012, ADR-013, ADR-014 auf „Vorgeschlagen“.
- Release Notes von #106 und #108 nicht gemeinsam gelesen.
- Docker 29.9.2 auf dem Server nicht gemessen.
- CVE-2026-111943 bei NVD und CISA KEV nicht geprüft.
- `Image-Scan Drittanbieter` als Required Check: fällig vor dem ersten Deploy
  von lego.
- Arbeitsdateien im ignorierten Ordner `scan/`.
- Signatur der distroless-Basis nicht selbst geprüft.
- CAA um `accounturi` und `validationmethods=http-01`; TTL des A-Eintrags.
- KEV-Einträge vom 16.10.2026 nicht namentlich geprüft.
- Healthchecks.io: zweiter Warnkanal vor Production, IPv4-Erreichbarkeit von
  `hc-ping.com`, Gegenprobe „Update-Lücke über 26 Stunden“.
- Frist des Journals ab 18.11.2026; runc 1.5.2 und CVE-2026-41579; NTS und
  netcup-Regel `ntp-antworten`; Journal von `nft-rollback.service`.
- Lokal OpenSSL 3.2.1 (Git für Windows): aktuell halten.
- `git log --show-signature`: „No principal matched“ (lokale
  `allowed_signers`).
- `.claude/hooks/Protect-Secrets.ps1` nennt im Kommentar noch den alten
  CA-Dateinamen; `.claude/rules/container-und-nginx.md` ohne Satz zu
  `internal-ca.crt` (beides Entscheidung der Projekt-Ownerin).
- Remote-Branch `test/staging-red-proof`: Stand nicht geprüft.
- Token des Agenten: am 28.10.2026 erneuert, **läuft am 27.11.2026 ab**;
  Erinnerung ab etwa 20.11.2026.

**Bekannte Grenzen**

- Auf dem Server läuft noch kein Stack; nginx hat das API-Zertifikat noch nie
  geprüft. Die Kette ist nur mit `openssl verify` belegt.
- Domain, Server-IPs, Hostnamen und Benutzernamen stehen bewusst nicht in
  diesem Bericht (öffentliches Repository, ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Neu: Staging-CA und API-Zertifikat auf dem Server,
täglicher Erneuerungs-Timer mit Totmannschalter.

Bis zum Beginn von Phase 5 fehlen:

| Nr. | Schritt | Abhängig von |
|---|---|---|
| 1 | ~~Staging-Konfiguration~~ erledigt (#118, #119, #121) | – |
| 2 | Interne CA auf dem Server: ~~Dateiname~~ (#123), ~~Konzept~~, ~~Messungen~~, ~~Skripte~~ (#127), ~~Timer~~ (#128); **API-Neustart offen** | 5 |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer (E-5-76) | **veröffentlichtes lego-Image** |
| 4 | Maschinenkonto (ADR-011) | – |
| 5 | Pull-Deploy mit Prüfung von Nachweis, Signatur und Staging-Konfiguration; API-Neustart für die Erneuerung | 4 |
| 6 | Freigabe vor dem Deploy, DORA-Events | 5 |
| 7 | DAST (OWASP ZAP) | 5, 6 |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: keine neue Abhängigkeit (openssl, systemd, curl, logger des Systems) |
| **Zero Trust / A01** | API-Schlüssel nur für Host-UID 167189 lesbar (gemessen); CA mit `nameConstraints` (gemessen) |
| **A09 (Alerting)** | Totmannschalter für die Erneuerung aktiv, alle Alarmwege ausgelöst und belegt |
| **A10 / fail closed** | fehlendes Credential → kein Start; fehlender Neustart → `/fail` |
| **Image-Gate für fremde Images** | lego rot, nginx grün; noch kein Required Check |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **mTLS** | Rückt näher: dieselbe CA könnte Client-Zertifikate ausstellen (dann `nameConstraints` erweitern, eigene Entscheidung) |
| **DAST** (OWASP ZAP) | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing** | Rückt näher (weitere Microservices geplant) |
| **Feature Flags, Mutation Testing, k6** | Nicht fällig |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (28./29.10.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| openssl auf dem Server | `3.5.7-1~deb13u3` | `dpkg -l`, Debian-Tracker |
| lego, neuestes Release | v5.5.2 (23.09.2026) | GitHub-Releases |
| `goacme/lego:v5.5.2` Index-Digest | `sha256:1944e8c36055beec47c7de6f15202b41128be75eea0ffa257f0c14d93c5155fd` (gleich Pin in `docker/lego/Dockerfile`) | `docker buildx imagetools inspect` |
| Go stable | go1.27.3 | go.dev |
| `main` nach der Sitzung | `fbbaa78` | `git log` |

### 6.2 Dateien und Rechte auf dem Server

| Pfad | Besitz und Rechte | Inhalt |
|---|---|---|
| `/usr/local/sbin/new-internal-ca.sh` | `root:root 0755` | SHA-256 `26875a44…1220` |
| `/usr/local/sbin/issue-api-certificate.sh` | `root:root 0755` | SHA-256 `1bb4e7d3…c48d` |
| `/usr/local/sbin/renew-api-certificate.sh` | `root:root 0755` | SHA-256 `1d7bd029…b019` |
| `/etc/systemd/system/identity-service-api-cert.service` | `root:root 0644` | SHA-256 `a51eb402…0c42` |
| `/etc/systemd/system/identity-service-api-cert.timer` | `root:root 0644` | SHA-256 `35c81940…e68e` |
| `/etc/identity-service`, `…/ca`, `…/api-tls` | `root:root 0755` | – |
| `/etc/identity-service/ca-private` | `root:root 0700` | – |
| `…/ca-private/internal-ca.key` | `0:0 0400` | CA-Schlüssel |
| `…/ca/internal-ca.crt` | `0:0 0644` | CA, notAfter 28.10.2027 07:21:49 GMT, SHA-256-Fingerprint `25:1B:9D:5E:50:59:ED:D6:31:2D:8B:D5:84:92:8C:46:D6:FF:2E:38:95:FE:44:02:F0:6F:81:0E:B1:00:AD:A9` |
| `…/api-tls/api.key` | `167189:0 0400` | API-Schlüssel |
| `…/api-tls/api.crt` | `0:0 0444` | notAfter 26.01.2027 07:24:48 GMT |
| `/etc/credstore/identity-service-api-cert.ping-url` | `root:root 0600` | Ping-URL des Checks `staging-api-cert-2` |

### 6.3 UIDs unter rootless Docker

| Container-UID | Host-UID | Wer |
|---|---|---|
| 0 | 1001 | Docker-Benutzer |
| 101 | 165636 | nginx |
| 1654 | 167189 | API |

### 6.4 Fallstricke, die Zeit gekostet haben

- `sudo cat ORDNER/*` bzw. `sudo … < DATEI`: Glob und Umleitung laufen vor
  `sudo` als normaler Benutzer; in root-Ordnern explizite Pfade.
- SSH zum Server nur mit `-i` und dem vollständigen Hostnamen.
- Das gepinnte SDK-Image lag lokal nicht vor; mit `--network none` kann es
  nicht nachgeladen werden, vorher holen.
- Ping-URL nie anklicken oder in den Browser kopieren; ein Klick ist ein
  echter ok-Ping und legt die URL im Verlauf ab.
- Der lego-Scan kann über 6 Minuten dauern; maßgeblich sind Exit-Code und
  Bericht.

### 6.5 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| openssl prüfen | Aktualität vor der CA | `dpkg -l`, Debian-Tracker | Backports behoben |
| UID ermitteln | Rechte des API-Schlüssels | `/proc/PID/uid_map`, `/etc/subuid` | 1654 → 167189 |
| Skripte installieren | root nur auf root-Dateien | `sha256sum -c`, `install -m 0755 -o root -g root` | Hash gleich vor und nach |
| CA erzeugen | Vertrauensanker nginx → API | `new-internal-ca.sh` | Exit 0, zweiter Lauf Exit 3 |
| API-Zertifikat | Endzertifikat `api` | `issue-api-certificate.sh` | Exit 0, zweiter Lauf Exit 10 |
| Rechte gegenprüfen | nur die API liest | `setpriv --reuid=…` | 167189 ja, 165636/1001 nein |
| Timer | tägliche Erneuerung | `systemctl enable --now …timer` | nächster Lauf geplant |
| Alarmwege | Schweigen alarmiert | Start, `systemd-run`, fehlendes Credential, kurze Grace | alle vier belegt |
| Rotation | URL war im Verlauf | neuer Check, `sudoedit`, alter gelöscht | „up“ vom Server |
| lego prüfen | Gate rot | Releases, `go.mod`, `release.yml`, `imagetools inspect` | kein neues Release |

---

# Roadmap Sitzung 27

## 1. Maschinenkonto und Pull-Deploy mit Gate

Warum zuerst: Laut Roadmap wird dieser Punkt vorgezogen, weil es kein neues
lego-Release gibt. Er ist zudem fristgebunden: Ohne Pull-Deploy gibt es keinen
API-Neustart, und die erste Erneuerung des API-Zertifikats steht spätestens
am 27.12.2026 an. Braucht kein öffentliches Zertifikat.

Bausteine (erst Konzept, dann Code):

- Konzept Maschinenkonto (ADR-011): wer zieht, mit welchen Rechten, ohne
  langlebige Secrets.
- Prüfung auf dem Server vor dem Start: Nachweise
  (`verify-attestations.sh`) und Konfiguration (`test-staging-config.sh`,
  `jq` auf dem Server; Aufnahme-Prüfung).
- Ort der Pflichtvariablen; `STAGING_CA_DIR=/etc/identity-service/ca`,
  `STAGING_API_CERT_DIR=/etc/identity-service/api-tls`.
- `restart_api` in `renew-api-certificate.sh` umsetzen und die Sandbox der
  Unit gezielt erweitern (E-5-102); Gegenprobe „Neustart scheitert → /fail“.
- `user: "1654:1654"` für `api` in `compose.staging.yaml`.
- Host-Skripte danach über den Pull-Deploy statt E-5-99.
- Vorher: Aktualität nach CLAUDE.md Abschnitt 1.

## 2. Ersten Timer-Lauf ablesen

Warum: Der automatische Lauf am 29.10.2026 ist der erste ohne Zuschauer;
Journal (`identity-service-api-cert`) und Ereignis bei Healthchecks.io zeigen,
ob `Persistent`, Versatz und Ping wie geplant wirken. Kurzer Blick zu Beginn.

## 3. lego-Release prüfen; wenn neu: Ports 80/443 und erstes Zertifikat

Warum: E-5-74. Wenn ein Release mit Go ≥ 1.27.3 und `x/net` ≥ 0.60.0
erscheint (Dependabot-PR in `/docker/lego`): Pin anheben, `Publish lego` grün,
erstes Zertifikat, M1/M2 unter rootless Docker.

## 4. Server-Härtung prüfen

Warum: `PermitRootLogin` (Verlauf mit `ssh root@…`) und
`unattended-upgrades` sind ungeprüft; Docker 29.9.2 als Auslöser „nächstes
Docker-Update“ offen seit Bericht 22.

## 5. Kleine Folge-PRs (nach Bedarf)

- Units von host-health-check unter `scripts/systemd/` versionieren (E-5-103)
- CI-Job für die Exit-Pfade der Bash-Skripte (berührt `ci.yml`)
- Regel-Sätze in `.claude/rules/skripte.md` (Bash auf dem Server) und
  `.claude/rules/container-und-nginx.md` (Entscheidung der Projekt-Ownerin)
- Push- und Digest-Logik aus `publish.yml` und `publish-lego.yml`
  zusammenführen
- Gegenproben in `verify-attestations.sh` auf den erwarteten Fehler eingrenzen

## 6. Zurückgestellt, nicht aufgehoben

- **ADR-Nachträge:** ADR-010 (E-5-78), ADR-014 (E-5-70, E-5-71, E-5-77),
  ADR-005 (E-5-72, Cooldown), ADR-009 (`Unknown`), ADR-011, ADR-012
- **ADR zum Schritt DNS/TLS:** E-5-65 bis E-5-68, E-5-73 bis E-5-76,
  E-5-79 bis E-5-104
- **CA-Wechsel** (CA läuft am 28.10.2027 ab): Übergang mit beiden CAs
- **Vor Production:** NTS, IPv6, zweiter Warnkanal, HSTS auf ein Jahr,
  Neubewertung von E-5-93 (CA-Schlüssel offline?)

## 7. Vor oder in der Sitzung zu verstehen (vor Code)

- **Pull- statt Push-Deploy:** Der Server holt sich das Image selbst und
  prüft es vor dem Start (Signatur, Provenance, Konfiguration). Die CI braucht
  keinen Zugang zum Server; ein kompromittierter CI-Lauf kann nichts
  ausrollen, was die Prüfung auf dem Server nicht besteht.
- **Maschinenkonto:** Ein eigenes Konto nur für das Ziehen, mit den kleinsten
  nötigen Rechten und ohne langlebiges Secret; es ist von Menschen-Konten und
  vom Docker-Benutzer getrennt.
- **Neustart aus einem root-Timer in rootless Docker:** Der Timer läuft als
  root, Docker gehört dem Docker-Benutzer. Der Neustart muss den richtigen
  Daemon erreichen, ohne der Unit pauschal mehr Rechte zu geben; das erweitert
  die Sandbox gezielt.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Staging-CA, Erneuerungs-Timer und Totmannschalter](https://claude.ai/artifact/P8pEtstmPm5ZZt9ztTskDi)

## 8. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- Auf GitHub bei `go-acme/lego` „Watch → Custom → Releases“ einstellen
- Gemergte lokale Branches und Remote-Branch `test/staging-red-proof` löschen
- Git für Windows aktualisieren (openssl 3.2.1)
- Erinnerung: Token des Agenten vor dem 27.11.2026 erneuern
