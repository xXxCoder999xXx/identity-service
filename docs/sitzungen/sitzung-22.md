# Sitzungsbericht Sitzung 22

**Datum:** 27.10.2026
**Phase:** Schritt 5 (CD): nginx 1.30.6 und SDK 10.0.403 im Einsatz; lego-Image,
Scan-Profile und Scan fremder Images in der CI (ADR-014, Teil 1); Konzept für
Ports 80/443, IPv6 und gemeinsame Volumes beschlossen; Veröffentlichung des
lego-Images offen
**Vorgänger:** sitzung-21.md (abgeschlossen 26.10.2026)

---

## 1. Erledigt

| PR | Titel | Inhalt |
|---|---|---|
| #106 | `chore(deps): Bump the codeql-action group with 2 updates` | Dependabot |
| #107 | `chore(deps): Bump dotnet/aspnet from 84def27 to c89a6a6` | Dependabot, Runtime 10.0.14 |
| #108 | `chore(deps): Bump anchore/grype from v0.120.1 to v0.121.0` | Dependabot, Scanner |
| #109 | `chore(deps): Bump nginxinc/nginx-unprivileged from 1.30.5 to 1.30.6` | Dependabot, Roadmap-Punkt 1 |
| #111 | `build(sdk): bump .NET SDK to 10.0.403` | `global.json` und Build-Stage-Digest gemeinsam |
| #110 | `chore(deps): Bump dotnet/sdk from 0d99ebf to de4fe90` | nach #111 gemergt, **leerer Commit** (siehe 1.2) |
| #112 | `build(lego): add lego image and third-party image scan` | ADR-014, Umsetzung Teil 1 |

Alle PRs von der Projekt-Ownerin per Squash gemergt. #106 bis #109 hat die
Projekt-Ownerin selbst geprüft und gemergt; ihre Release Notes wurden in
dieser Sitzung nicht gemeinsam gelesen.

### 1.1 nginx 1.30.6 (Roadmap-Punkt 1)

- Dependabot-Lauf vom 26.10.2026 (06:47 UTC) öffnete #109; damit entfiel der
  Handweg aus E-5-69.
- Lokal gemessen: `docker compose up --build`, `/health` über nginx mit 200
  und allen Security-Headern (HSTS `max-age=300`, `nosniff`, `DENY`,
  `no-referrer`, CSP); `docker compose ps` zeigt
  `nginx-unprivileged:1.30.6@sha256:ec0f7ecb…`.
- In der CI scannt der neue Job das Image mit Profil `nginx`: grün.

### 1.2 SDK 10.0.403 (#110, #111)

- #110 (nur Build-Stage-Digest) war rot: `Requested SDK version: 10.0.402 …
  Installed SDKs: 10.0.403`, `dotnet restore` mit Exit 155.
- Ursache im Protokoll des Laufs `dotnet_sdk` (26.10.2026, 06:48 UTC):
  `Filtered out 7 versions due to cooldown`, `Latest version is 10.0.402`.
  Die Cooldown hielt die Version zurück, den neuen Digest des Tags
  `10.0-noble` aber nicht.
- Release Notes aus `dotnet/core` (`release-notes/10.0/releases.json`):
  10.0.403 erschien am 25.10.2026 mit Runtime 10.0.14, Sicherheits-Release mit
  CVE-2026-111497, CVE-2026-70197, CVE-2026-102870, CVE-2026-114148.
- MCR-Tag `10.0.403-noble` existiert; `10.0-noble` und `10.0.403-noble`
  zeigen auf denselben Index-Digest.
- SDK 10.0.403 lokal installiert (ersetzt 10.0.402). Lokal grün: Restore
  (locked), Build, Format, Test (2/2), Compose-Stack mit Smoke-Test über
  nginx.
- #111 mit allen fünf Pflicht-Checks grün. #110 wurde danach von Dependabot
  neu aufgesetzt und ebenfalls gemergt; sein Commit `791010e` ändert keine
  Datei.

### 1.3 lego-Image (Roadmap-Punkt 2a)

- `docker/lego/Dockerfile`: `goacme/lego:v5.5.2` als Quelle der
  Programmdatei, `gcr.io/distroless/static-debian13:nonroot` als Basis, beide
  per Index-Digest. `USER 65532:65532`, `ENTRYPOINT ["/lego"]`, kein `CMD`,
  kein `EXPOSE`.
- `docker/lego/.dockerignore` enthält nur `*` (leerer Build-Kontext).
- Zusätzlicher Dependabot-Eintrag `docker` für `/docker/lego`.
- Lokal gemessen: Build Exit 0; Start mit `--read-only --cap-drop ALL
  --security-opt no-new-privileges:true` liefert `lego version 5.5.2
  linux/amd64`; Start mit `/bin/sh` scheitert; `docker export` zeigt `/lego`
  als `0/0 rwxr-xr-x`; Größe rund 96 MB (Programmdatei 68 MB).
- Grype-Stückliste des eigenen Images: debian 13.7, 6 deb-Pakete, 203
  Go-Module inklusive `stdlib go1.27.1`. 15 Funde High+ mit Fix, alle aus der
  Programmdatei (Go-stdlib 1.27.1, `golang.org/x/net` 0.59.0). Die
  Alpine-Funde des Upstream-Images sind weg.

### 1.4 Scan-Profile (Roadmap-Punkt 2b)

- `scripts/invoke-image-scan.sh` nimmt einen optionalen zweiten Parameter
  (`api`, `lego`, `nginx`; Standard `api`). Je Profil: erwartetes
  Betriebssystem und Anforderungen an die Stückliste (`purl:` für ein
  Ökosystem, `name:` für eine Komponente). Unbekanntes Profil: Exit 2 vor dem
  Export.
- Der blinde Fleck bei nginx (Paket von nginx.org, als Debian-Paket geführt)
  steht mit der zweiten Quelle im Profil.
- Aufrufe in `ci.yml` und `publish.yml` unverändert; Ausgabedateien
  unverändert.
- `bash -n` Exit 0; Datei reines ASCII, nur LF. Lokal nicht lauffähig (kein
  `jq`); Beweis über die CI (1.5).

### 1.5 CI-Job für fremde Images (Roadmap-Punkt 2c)

Neuer Job `Image-Scan Drittanbieter (lego|nginx)` in `ci.yml`: Matrix mit
`fail-fast: false`, kein Required Check, kein `continue-on-error`.
nginx-Image zur Laufzeit aus `compose.yaml`. Je Zweig zuerst eine Gegenprobe
mit falschem Profil (nur Exit 3 zählt), dann das Gate.

Gemessen im Lauf von #112:

| Zweig | Gegenprobe | Blindheits-Schutz | Gate |
|---|---|---|---|
| nginx (Gegenprobe mit `lego`) | Exit 3: debian passt, `purl:pkg:golang/=0` | deb 150, `nginx=1` | grün |
| lego (Gegenprobe mit `api`) | Exit 3: `debian (erwartet: ubuntu)` | deb 6, golang 203, `stdlib=1` | **rot, Exit 4** (nur Go-Funde) |

Damit ist der Rot-Beweis aus ADR-014 erbracht und läuft ab jetzt in jedem
Lauf mit. Die fünf Pflicht-Checks waren grün.

### 1.6 Ports 80/443 und IPv6 (Roadmap-Punkt 3, Konzept und Messung)

- Ausgangslage aus früheren Berichten: E-5-34 (`ip_unprivileged_port_start=80`)
  gesetzt; Gegenproben 8 (Loopback, IPv4 und IPv6), 9 und 11 (IPv4)
  bestanden.
- Aktualität: RootlessKit 3.3.0 ist aktuell, ohne Advisory. Docker 29.9.2
  (20.10.2026) behebt CVE-2026-111943 (Go 1.26.10, gesperrte
  eMudhra-Zwischenzertifikate).
- IPv6-Messung über Proton VPN (IPv6 im Client eingeschaltet), mit
  befristeter netcup-Regel (eine Quelladresse, TCP 8080), Zählregel in
  nftables und Probe-Container `nginx-unprivileged:1.30.6` als `deploy`:

| Schritt | Ergebnis |
|---|---|
| Aufruf ohne Host-Freigabe | Zählregel 8080: +13 Pakete / +1040 Bytes; Drop-Zähler: +13 / +1040. 80 Bytes je Paket = TCP-SYN über IPv6. **Gegenprobe 9 über IPv6 bestanden** |
| Aufrufe auf 8081 und 47111 | nicht im Drop-Zähler des Hosts: von der netcup-Firewall verworfen |
| Aufruf mit Host-Freigabe | `Connection was reset` |
| `ss -tlnp sport = :8080` | nur `0.0.0.0:8080` (`rootlesskit`), kein `[::]:8080` |
| `docker ps` | nur `0.0.0.0:8080->8080/tcp` |

- Ursache belegt in `docker/docs`: IPv6-Ports des Hosts werden nur bei
  `userland-proxy=true` auf IPv4-Container abgebildet; die echte Client-IP
  unter rootless braucht aber `userland-proxy` aus.
- Messfalle: Proton VPN beantwortet jeden TCP-Handshake selbst (auch zu
  Cloudflare auf 8081). `curl` meldet immer `Connected`; aussagekräftig sind
  nur die Zähler auf dem Server.
- Aufgeräumt und belegt: `nft -f /etc/nftables.conf` (Kette wieder wie in
  Bericht 18, 6.1, Zähler 0), Container entfernt, netcup-Regel gelöscht und
  gespeichert (Screenshot: Regeln 1 bis 6 wie in Bericht 18, 6.2).

### 1.7 Gemeinsame Volumes und Reload (Roadmap-Punkt 3, Konzept)

Quellcode lego v5.5.2: Zertifikate, Schlüssel und Kontodaten mit `0o600`
(`cmd/internal/storage/storage_certificates_writer.go`, `storage_accounts.go`),
Kontoverzeichnis `0o700`, Challenge-Dateien `0o644` und Verzeichnisse `0o755`
(`providers/http/webroot/webroot.go`). Entscheidungen E-5-75 und E-5-76.

### 1.8 Lehrstoff

[Lehrstoff: Scan-Profile, Cooldown und IPv6 unter rootless Docker](https://claude.ai/artifact/W5L3m2zHhiobnuV9mWSbBn)
(eigenes Image aus fremder Programmdatei, Scan-Profile und Gegenprobe, CI-Job
für fremde Images, Cooldown und gekoppelte Updates, IPv6 unter rootless
Docker mit Diagramm des Messwegs, Zertifikate teilen, Spickzettel).

---

## 2. Gelernt

- `COPY --from` aus einem gepinnten fremden Image übernimmt eine einzelne
  Datei, ohne dessen Basis-Image und dessen Funde zu erben.
- Ein Build-Kontext, aus dem das Image nichts braucht, wird mit einer
  `.dockerignore` aus nur `*` vollständig gesperrt.
- Ein neues Dockerfile in einem eigenen Ordner braucht einen eigenen
  Dependabot-Eintrag, sonst bleiben seine Pins still stehen.
- Ein Scan-Profil macht „0 Funde“ erst aussagekräftig: Es legt fest, welches
  Betriebssystem und welche Komponenten der Scanner erkennen muss.
- Eine Gegenprobe akzeptiert genau einen Exit-Code; ein beliebiger Fehler
  wäre kein Beweis, dass der Schutz greift.
- Eine Matrix in einem bestehenden Job ändert den Check-Namen und bricht
  damit das Ruleset.
- Die Cooldown von Dependabot hält neue Versionen zurück, aber keinen neuen
  Digest eines gleichbleibenden Tags; gekoppelte Updates kommen dann nur halb.
- Ein ersetzter Bot-PR, der später gemergt wird, kann als leerer Commit in
  der Historie landen.
- `curl -s` verschluckt die Fehlermeldung; Exit 6 hieß hier: keine
  IPv6-Auflösung durch den VPN-Tunnel.
- Ein VPN-Client kann jeden TCP-Handshake selbst beantworten; Messungen von
  außen zählen dann nur mit den Zählern auf dem Ziel.
- Die Paketgröße verrät das Protokoll: 80 Bytes ist ein TCP-SYN über IPv6,
  60 Bytes über IPv4.
- Unter Docker schließen sich `userland-proxy: false` (echte Client-IP) und
  IPv6-Ports für reine IPv4-Netze aus.
- Ein Rate Limit pro IPv6-Adresse ist umgehbar, weil Kunden meist ein ganzes
  `/64` haben.
- lego schreibt Schlüssel fest mit `0o600`; eine gemeinsame Gruppe reicht
  deshalb nicht, damit nginx sie liest.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-70** | Gegenprobe je Matrix-Zweig mit einem falschen Profil, nur genau Exit 3 zählt; lego/api prüft das Betriebssystem, nginx/lego die Komponenten | Beweist bei jedem Lauf, dass beide Pfade des Blindheits-Schutzes greifen |
| **E-5-71** | Der Drittanbieter-Scan liest Images aus `compose.yaml` | Eine Quelle der Wahrheit; Dependabot pflegt nur dort |
| **E-5-72** | SDK 10.0.403 von Hand trotz Cooldown, beide Hälften in einem PR | Sicherheits-Release, Herausgeber Microsoft, Digest-Hälfte lag schon vor |
| **E-5-73** | Staging nur IPv4; AAAA, IPv6-Client-IP und Rate Limit pro `/64` vor Production | Gemessen: kein IPv6-Port mit `userland-proxy: false` und reinen IPv4-Netzen |
| **E-5-74** | Port 80 für alle (HTTP-01); Port 443 für alle, aber erst mit fertigem nginx samt Zertifikat und Härtung; beide Firewall-Schichten; danach Gegenprobe 9 erneut | Let's Encrypt prüft von mehreren Standorten; Zero Trust statt IP-Allowlist |
| **E-5-75** | lego läuft als UID 101 (über `compose.yaml`), drei getrennte Volumes: Konto nur lego, Zertifikate und Webroot für nginx nur lesend | lego schreibt fest `0o600`; die Trennung leisten die Mounts |
| **E-5-76** | Täglicher systemd-Timer von `deploy`: Renew mit ARI, `nginx -s reload`, Warnung über ADR-013 bei Fehler; kein Docker-Socket in Containern | Kein Root-Äquivalent im Container; stille Fehlerkette verhindert |
| **E-5-77** | Scan-Profile als `case`-Block im Skript, Standard `api` | Sicherheitslogik im geprüften Code; Standard fail closed für fremde Images |

ADR-Kandidaten: E-5-73 bis E-5-76 gehören mit E-5-65 bis E-5-68 in das ADR zum
Schritt DNS/TLS. E-5-70, E-5-71 und E-5-77 als Nachtrag zu ADR-014. E-5-72
und die Cooldown-Erkenntnis als Nachtrag zu ADR-005.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **lego-Gate rot** bis zu einem lego-Release mit Go ≥ 1.27.2 und `x/net` ≥
  0.60.0 (Stand 26.10.2026: v5.5.2 ist das neueste Release). Bei jedem roten
  Lauf prüfen, ob es noch dieselben Funde sind.
- Veröffentlichung des lego-Images über `publish.yml` (ADR-010-Muster) offen.
- Länge der Cooldown weiter unbekannt; bekannt ist nur, dass sie Versionen
  und nicht Digests betrifft. Nachtrag zu ADR-005.
- Release Notes von #106 (CodeQL) und #108 (Grype v0.121.0) nicht gemeinsam
  gelesen.
- Docker 29.9.2 auf dem Server nicht gemessen: Ist es per
  `unattended-upgrades` angekommen, und lief der automatische Weg (Hook,
  Neustart 04:00)? Das ist der Auslöser „nächstes echtes Docker-Update“.
- CVE-2026-111943: Fix in Docker 29.9.2 belegt; Eintrag bei NVD und CISA KEV
  weiter nicht geprüft.
- Aufnahme von `Image-Scan Drittanbieter` als Required Check: fällig vor dem
  ersten Deploy von lego (Ruleset ändert die Projekt-Ownerin).
- ADR-013 und ADR-014 stehen auf „Vorgeschlagen“ (wie ADR-006, ADR-008,
  ADR-012).
- Lokale Branches `build/lego-image`, `build/sdk-10-0-403`,
  `docs/adr-013-alert-channel`, `docs/adr-014-third-party-image-gate`,
  `docs/sitzung-21`: gemergt; die letzten vier inhaltlich identisch mit
  `main` geprüft. Löschen braucht die Freigabe der Projekt-Ownerin.
- Arbeitsdateien im ignorierten Ordner `scan/` (zusätzlich `lego-own.tar`,
  `lego-own*.json`, `nginx6.cdx.json`) bei Bedarf löschen.
- Signatur der distroless-Basis nicht selbst geprüft (cosign wäre ein neues
  Werkzeug).
- CAA um `accounturi` und `validationmethods=http-01` ergänzen, sobald das
  ACME-Konto existiert. TTL des A-Eintrags später erhöhen.
- `jq` lokal nicht installiert; `invoke-image-scan.sh` läuft lokal unter
  Windows nicht.
- KEV-Einträge vom 16.10.2026 nicht namentlich geprüft.
- Beschreibung des Checks bei Healthchecks.io auf ADR-013 kürzen
  (freigestellt).

**Aus Sitzung 21 und früher, weiter offen**

- Eintrag der Ping-URL im Verlauf der Zwischenablage (`Win+V`) löschen, falls
  aktiv (nicht bestätigt)
- IPv4-Erreichbarkeit von `hc-ping.com` nicht getestet
- Vor Production: zweiter Warnkanal oder eigene Instanz bewerten (ADR-013)
- Gegenprobe „Update-Lücke über 26 Stunden“ nicht gemessen
- Frist des Journals ab 18.11.2026 prüfen
- runc 1.5.2 und CVE-2026-41579: Fix im GitHub-Advisory nachsehen
- NTS und die netcup-Regel `ntp-antworten`
- Zugriffslog von nginx mit Client-IPs (Staging-Variante von `compose.yaml`)
- Journal des Rücksprungs (`nft-rollback.service`) aus Sitzung 18
- Nachträge zu ADR-012 (zweiter), ADR-011, ADR-009, ADR-005
- Maschinenkonto; `compose.yaml` ohne `pids_limit`; Staging-Variante mit
  Image per Digest
- **Token des Agenten läuft am 06.11.2026 ab** (in 10 Tagen)

**Bekannte Grenzen**

- Ausgaben vom Server und aus den Panels von netcup liegen nur als
  Rückmeldung oder Screenshot der Projekt-Ownerin vor. CI-Läufe, Registry,
  Primär-Repos und lokale Builds sind selbst gemessen.
- Die IPv6-Messung lief über die Ausgangsadresse von Proton VPN, nicht über
  einen eigenen Anschluss.
- Domain, Server-IPs und die VPN-Adresse stehen bewusst nicht in diesem
  Bericht (öffentliches Repository, ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Neu: nginx 1.30.6 und SDK 10.0.403 im Einsatz;
lego-Image gebaut und in der CI gescannt (rot, erwartet); Gate für fremde
Images aktiv; Konzept für Ports, IPv6 und Volumes beschlossen. Es fehlen:
Veröffentlichung lego-Image, Staging-Variante von `compose.yaml`, Öffnen von
80/443, erstes Zertifikat, NTS, Maschinenkonto, Pull-Deploy mit Gate,
Freigabe, DORA-Events.

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: neues eigenes Image mit zwei Pins, neuer Dependabot-Eintrag, SDK-Update trotz Cooldown (E-5-72) |
| **Image-Gate für fremde Images** | Umgesetzt (E-5-61): nginx grün, lego rot; noch kein Required Check |
| **A09 (Alerting)** | Erneuerung der Zertifikate meldet Fehler über ADR-013 (E-5-76, noch nicht umgesetzt) |
| **Zero Trust / A02** | Port 443 öffentlich erst mit fertigem nginx (E-5-74) |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** (OWASP ZAP) | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet; lego ist ein ausgehender Aufruf des Hosts, nicht der Anwendung |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant) |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Digests (aufgelöst am 26.10.2026 aus der Registry)

| Image | Index-Digest |
|---|---|
| `goacme/lego:v5.5.2` | `sha256:1944e8c36055beec47c7de6f15202b41128be75eea0ffa257f0c14d93c5155fd` |
| `gcr.io/distroless/static-debian13:nonroot` | `sha256:18f4cc26c9ffa7f20a359298be7deadac5c607c8e03a02b8119f1a5fc2f82c99` |
| `mcr.microsoft.com/dotnet/sdk:10.0-noble` (= `10.0.403-noble`) | `sha256:de4fe90a98845d75910b9769662465c84de1a934665c431279d1382b2bddc02b` |

`nginxinc/nginx-unprivileged:1.30.6@sha256:ec0f7ecb…` (aus Bericht 21, 6.1)
lief lokal und in der CI. Die Runtime-Stage steht nach #107 auf
`aspnet:10.0-noble-chiseled@sha256:c89a6a6…` (gelesen aus dem Dockerfile,
nicht selbst aufgelöst).

### 6.2 Versionen und Primärquellen (26.10.2026)

| Gegenstand | Stand |
|---|---|
| lego | v5.5.2 (23.09.2026) neuestes Release |
| RootlessKit | v3.3.0 (14.10.2026), keine Advisories |
| Docker Engine | 29.9.2 (20.10.2026): Go 1.26.10, CVE-2026-111943 |
| .NET | Runtime 10.0.14 / SDK 10.0.403 (25.10.2026) |

### 6.3 lego-Image

- Pfad `docker/lego/`, Kontext dieser Ordner, Tag in der CI
  `identity-service-lego:ci`.
- Benutzer im Image 65532; zur Laufzeit 101 über `compose.yaml` (E-5-75).
- Dateirechte in lego v5.5.2 siehe 1.7.

### 6.4 Scan-Profile

```
bash scripts/invoke-image-scan.sh IMAGE PROFIL
```

| Profil | Betriebssystem | Anforderungen |
|---|---|---|
| `api` | ubuntu | `purl:pkg:deb/`, `name:Microsoft.NETCore.App.Runtime.linux-x64` |
| `lego` | debian | `purl:pkg:deb/`, `purl:pkg:golang/`, `name:stdlib` |
| `nginx` | debian | `purl:pkg:deb/`, `name:nginx` |

Exit-Codes: 2 Voraussetzung/Profil, 3 Blindheit, 4 Gate.

### 6.5 Messweg über IPv6 (Sitzung 22)

```
sudo nft insert rule inet host_fw input tcp dport PORT counter
sudo nft list chain inet host_fw input
sudo nft insert rule inet host_fw input ip6 saddr ADRESSE tcp dport PORT counter accept
sudo ss -tlnp sport = :PORT
sudo nft -f /etc/nftables.conf
```

### 6.6 Fallstricke, die Zeit gekostet haben

- `curl -s` ohne Blick auf den Exit-Code: „nichts“ war Exit 6.
- Proton VPN beantwortet TCP-Handshakes selbst; `curl -v` zeigt
  `Connected` auch ohne Ziel.
- Im netcup-Panel wirkt eine Regeländerung erst nach **Speichern** im Dialog
  (und gegebenenfalls auf der Seite dahinter).
- Ein versehentlich abgelehnter Tool-Aufruf (Commit) musste wiederholt
  werden.
- Der Hook `Protect-Secrets` blockiert jeden Befehl, der `certs/` berührt,
  auch `Test-Stack.ps1 -CaFile …`; ersatzweise `curl.exe --ssl-no-revoke`
  gegen `/health` (lokale CA im Windows-Speicher).
- Branches löschen wird vom Auto-Modus blockiert und braucht die
  ausdrückliche Freigabe.

### 6.7 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Digests auflösen | Pins per Inhalt aus der Registry | `docker buildx imagetools inspect` | identisch mit Bericht 21 |
| Image prüfen | Messen statt lesen | `docker run --read-only --cap-drop ALL …`, `docker export \| tar -tv` | läuft, keine Shell, `/lego` gehört root |
| Profil ableiten | Profil aus Messung | Grype-Stückliste, `ConvertFrom-Json` | Tabelle 6.4 |
| Rot-Beweis | Schutz muss scheitern können | Gegenprobe im CI-Job | Exit 3 in beiden Zweigen |
| Bot-Lauf lesen | Fehlender PR | `gh run view RUN_ID --log` | Cooldown filtert Versionen |
| Release Notes | SemVer ist nicht das Risiko | `releases.json` in `dotnet/core` | 4 CVEs in 10.0.14 |
| IPv6 messen | Zähler statt Handshake | Zählregel, `ss -tlnp` | Sperre belegt, kein IPv6-Socket |
| Quellcode lesen | Rechte von lego | `gh api repos/go-acme/lego/contents/…?ref=v5.5.2` | `0o600` für Schlüssel |

---

# Roadmap Sitzung 23

## 1. Veröffentlichung des lego-Images über `publish.yml` (Konzept)

Warum zuerst: Ohne veröffentlichtes Image mit Herkunftsnachweis kann der
Server lego nicht per Digest ziehen, und ohne lego gibt es kein Zertifikat.
Zuerst prüfen, ob lego ein neues Release hat (Go ≥ 1.27.2); davon hängt ab,
ob die Veröffentlichung bis zum Ende messbar ist.

Bausteine:
- Gleiches Muster wie ADR-010 (bauen, Scan mit Profil `lego`, veröffentlichen,
  Nachweise, Prüf-Gate); keine zweite Quelle für den Schwellenwert
- Name und Tag des Images in GHCR; eigener Job oder eigener Workflow
- Bleibt das Gate rot: Workflow bauen, Fehlschlag als korrektes Verhalten
  belegen, keine Ausnahme ohne ADR (E-5-61)

## 2. Staging-Variante von `compose.yaml` mit lego und Volumes

Warum: Setzt E-5-75 und E-5-76 um und ist Voraussetzung für das erste
Zertifikat. Bausteine: Images per Digest, drei Volumes, `user: "101:101"` für
lego, nginx-Konfiguration für `/.well-known/acme-challenge/` und Weiterleitung
auf https, `pids_limit`, Zugriffslog mit Client-IP.

## 3. Ports 80/443 öffnen und erstes Zertifikat

Warum: E-5-74. Erst gegen die Staging-Umgebung von Let's Encrypt, dann
Produktion. Danach Gegenprobe 9 für einen nicht freigegebenen Port, CAA um
`accounturi` und `validationmethods` ergänzen, Timer nach E-5-76.

## 4. Server: Docker-Update beobachten

Warum: Docker 29.9.2 ist der Auslöser „nächstes echtes Docker-Update“ aus
Bericht 20. Messen, ob es angekommen ist und ob Hook und Neustart wie geplant
liefen.

## 5. Zurückgestellt, nicht aufgehoben

- **NTS und netcup-Regel `ntp-antworten`:** spätestens vor Production.
- **ADR-Nachträge:** ADR-014 (E-5-70, E-5-71, E-5-77), ADR-005 (E-5-72,
  Cooldown), ADR-011, ADR-012 (zweiter).
- **ADR zum Schritt DNS/TLS:** E-5-65 bis E-5-68 und E-5-73 bis E-5-76, sobald
  das erste Zertifikat läuft.
- **IPv6 vor Production:** Dual-Stack-Netze unter rootless, Client-IP über
  IPv6, Rate Limit pro `/64`, dann AAAA.

## 6. Folgende Sitzungen (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 23 | Veröffentlichung lego-Image; Staging-Compose; Ports 80/443; erstes Zertifikat (abhängig vom lego-Release) |
| 24 | Maschinenkonto, Pull-Deploy mit Prüfung von Nachweis und Signatur |
| 25 | Freigabe vor dem Deploy, DORA-Events; DAST fällig |
| ab 26 | Phase 5: STRIDE, erster Use Case test-first |

Schätzung: Der Plan hält. Risiko ist das lego-Release; ohne neueres Go kann
lego nicht deployt werden, und das erste Zertifikat verschiebt sich.

## 7. Vor oder in der Sitzung zu verstehen (vor Code)

- **Herkunftsnachweis für ein zweites Image:** `publish.yml` hat Schreibrechte
  und ist kein Pflicht-Check; ein Fehlschlag zeigt sich erst nach dem Merge.
  Ein zweites Image darf das bestehende Muster nicht aufweichen.
- **HTTP-01 im Detail:** Let's Encrypt ruft
  `/.well-known/acme-challenge/TOKEN` über Port 80 von mehreren Standorten
  ab; nginx liefert nur diesen Pfad aus dem Webroot, alles andere wird auf
  https weitergeleitet.
- **Staging-Umgebung von Let's Encrypt:** Gleiche Abläufe, nicht
  vertrauenswürdige Zertifikate, großzügige Rate Limits; erst dort testen.
- Lehrstoff zu dieser Sitzung:
  [Scan-Profile, Cooldown und IPv6 unter rootless Docker](https://claude.ai/artifact/W5L3m2zHhiobnuV9mWSbBn)

## 8. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- Gemergte lokale Branches löschen (Liste in Abschnitt 4)
- ADR-013 und ADR-014 lesen und den Status setzen
- Ablauf des Agenten-Tokens am 06.11.2026 vormerken und Erneuerung planen
- In der Proton-App die IPv6-Einstellung nach Wunsch zurücksetzen
