# Sitzungsbericht Sitzung 21

**Datum:** 26.10.2026
**Phase:** Schritt 5 (CD): Warnkanal per ADR-013 dokumentiert; DNS für Staging
mit DNSSEC und CAA aktiv; ACME-Client gewählt und Gate für fremde Images
beschlossen (ADR-014); Umsetzung offen
**Vorgänger:** sitzung-20.md (abgeschlossen 22.10.2026)

---

## 1. Erledigt

| PR | Titel | Inhalt |
|---|---|---|
| #103 | `docs(adr): add ADR-013 alert channel via dead man's switch` | ADR-013, Status Vorgeschlagen |
| #104 | `docs(adr): add ADR-014 third-party image gate and ACME client` | ADR-014, Status Vorgeschlagen |

Beide PRs mit allen fünf Pflicht-Checks grün, von der Projekt-Ownerin per
Squash gemergt.

### 1.1 Aufräumen

- Lokales `main` per Fast-Forward auf den Stand nach #102 gebracht.
- Lokale Branches `chore/session-lesson-doc`, `docs/sitzung-18`,
  `docs/sitzung-19`, `docs/sitzung-20` gelöscht. Vorher für jeden Branch die
  Dateien, die er selbst geändert hat, mit `main` verglichen: alle identisch.
  `-D` war nötig, weil Squash-Merges für Git nicht als gemergt gelten.
- „Automatically delete head branches“ in den Repository-Settings von der
  Projekt-Ownerin eingeschaltet. Die entfernten Branches `docs/sitzung-19`
  und `docs/sitzung-20` sind nach `git fetch --prune` nicht mehr vorhanden.

### 1.2 ADR-013: Kanal für Warnungen (Roadmap-Punkt 1)

- Entscheidung für ein eigenes ADR statt eines Nachtrags zu ADR-011 (E-5-64).
- Inhalt: E-5-54, E-5-55, E-5-57, Aufnahme-Prüfung aus Bericht 20, die vier
  Gegenproben, Restrisiken, Auslöser der Neubewertung.
- Nachprüfung am 25.10.2026 im Primär-Repo: kein neues Advisory für
  Healthchecks (weiter nur GHSA-frxj-v529-jv6w), neueste Version weiter
  v5.0.1.
- E-Mail direkt vom Server mit zwei Gründen verworfen (toter Server sendet
  nicht; neues Mailpaket). Eigene Healthchecks-Instanz als „nicht geprüft“
  aufgenommen, nicht als verworfen.

### 1.3 Konten bei netcup

- Zwei-Faktor-Anmeldung in CCP und SCP aktiv (bestätigt durch die
  Projekt-Ownerin). Offener Punkt aus Bericht 20 damit erledigt.
- Die Domain (`.at`) hat keine Transfer-Sperre wie bei gTLDs; Schutz ist der
  Authcode. Er wurde bewusst **nicht** angefordert (E-5-68).

### 1.4 DNS für Staging (Roadmap-Punkt 2, Schritt 1)

Domain und Server liegen beim selben Anbieter (netcup, CloudDNS).

| Schritt | Ergebnis | Beleg |
|---|---|---|
| Bestand | Ein vorbelegter A-Eintrag auf `@`, der nicht zum Server gehört (Standardeintrag des Anbieters) | Vergleich mit dem SCP durch die Projekt-Ownerin |
| Änderung | `@ A` gelöscht; `staging A <server-ipv4>` TTL 300; `@ CAA 0 issue "letsencrypt.org"`; `@ CAA 0 issuewild ";"` (je TTL 3600) | Abfrage über DNS over HTTPS (Cloudflare): genau diese Antworten |
| Kein AAAA | bewusst (E-5-66) | Abfrage: keine Antwort |
| DNSSEC | im Reiter DNSSEC aktiviert; Zone sofort signiert (DNSKEY 257 und 256, Algorithmus 13) | DNSKEY und RRSIG bei Cloudflare sichtbar |
| DS bei `.at` | erst nicht vorhanden (NSEC3-Beweis), am 26.10.2026 übernommen | DS mit Schlüsselnummer 42182, Algorithmus 13, Digest-Typ 2 |
| Kette | geschlossen | `AD:true` bei Cloudflare und bei Google |

Die Schlüsselnummer des DS (42182) entspricht dem KSK, der die DNSKEY-Liste
signiert.

### 1.5 Recherche (Aktualität nach CLAUDE.md 1)

| Gegenstand | Ergebnis |
|---|---|
| CISA KEV Oktober 2026 | Einträge vom 01., 02., 13., 14., 20. und 23.10. (u. a. FortiMail, Zammad, Ivanti, PAN-OS, Cisco, Plex, Siemens, Collabora); keiner betrifft den Stack. Für den 16.10. nur die Anzahl gefunden, keine Namen |
| The Hacker News | Nichts zu nginx, certbot oder ACME im Oktober |
| Let's Encrypt | 64-Tage-Zertifikate ab 10.02.2027, 45 Tage ab 16.02.2028 |
| CAA bei netcup | unterstützt (Liste von SSLMate) |
| nginx 1.30.6 | am 14.10.2026 erschienen; behebt CVE-2026-15176, CVE-2026-93479, CVE-2026-95101, CVE-2026-97629, CVE-2026-97205; `compose.yaml` pinnt noch 1.30.5 |

### 1.6 Wahl des ACME-Clients und Messung

Vier Kandidaten gegen GitHub-API, Launchpad und Docker Hub geprüft (Details
in ADR-014). Ergebnis: lego, als Container, in einem eigenen minimalen Image
(E-5-62, E-5-63).

Scan mit Grype v0.120.1 über `compose.scan.yaml`, direkt aufgerufen statt
über `invoke-image-scan.sh`, weil dessen Blindheits-Schutz auf das API-Image
zugeschnitten ist (Ubuntu und .NET) und bei fremden Images mit Exit 3
abbräche:

| Image | Basis | Größe | Benutzer | High+ mit Fix |
|---|---|---|---|---|
| `certbot/certbot:v5.8.0` | Alpine 3.23.5 | 293 MB | root | 13 |
| `goacme/lego:v5.5.2` | Alpine 3.24.2 | 125 MB | root | 20 |
| `nginxinc/nginx-unprivileged:1.30.5` | Debian 13.7 | – | 101 | 13 |
| `nginxinc/nginx-unprivileged:1.30.6` | Debian 13.7 | – | 101 | 0 |

Blindheits-Prüfung über die Stückliste bei allen vier bestanden. Gemessener
blinder Fleck: Grype meldet für `nginx 1.30.5-1~trixie` keinen der fünf CVEs,
die 1.30.6 behebt.

### 1.7 Dependabot und nginx 1.30.6

Kein Dependabot-PR für 1.30.6. Protokoll des Laufs `docker_compose` vom
19.10.2026 (Run 39210828594):

```
Skipping tag 1.30.6 due to cooldown period
Latest version is 1.30.5
Updating nginxinc/nginx-unprivileged from 1.30.5 to 1.30.5
```

Daraus entstand PR #95 (nur neuer Digest für denselben Tag). In
`dependabot.yml` ist keine Cooldown konfiguriert; die Länge steht nicht im
Protokoll. Der Lauf vom 26.10. stand bei Sitzungsende noch aus (letzte Läufe
gegen 06:35 UTC).

### 1.8 Lehrstoff

[Lehrstoff: DNS, DNSSEC und ACME-Client-Wahl](https://claude.ai/artifact/2ZACcjPCWVPH6AbeKn6jGg)
(ADR für externe Dienste, DNS und Negative Caching, DNSSEC mit Diagramm der
Vertrauenskette, CAA und CT, ACME und ARI, eigenes Image per `COPY --from`,
Gate und blinde Flecken, Cooldown, Spickzettel).

---

## 2. Gelernt

- Ein externer Dienst lässt sich nicht pinnen; das ADR hält stattdessen
  Gründe, akzeptierte Restrisiken und Auslöser der Neubewertung fest.
- Squash-Merges erscheinen Git nicht als gemergt; `git branch -d` verweigert
  dann, `-D` ist erst nach einem Inhaltsvergleich vertretbar.
- Negative Caching: Auch „gibt es nicht“ wird gespeichert, so lange wie der
  letzte Wert der SOA (hier 86400 Sekunden).
- Let's Encrypt prüft über IPv6, sobald ein AAAA-Eintrag existiert; ein
  AAAA ohne erreichbaren Dienst lässt die Ausstellung scheitern.
- DNSSEC hat drei sichere Zustände (unsigniert, Insel, geschlossene Kette)
  und einen gefährlichen: DS bei der Registry ohne gültige Signaturen.
- Der KSK signiert nur die Schlüsselliste und steht als DS bei der Registry;
  der ZSK signiert die Einträge und lässt sich ohne Registry wechseln.
- CAA begrenzt vorher, wer ausstellt; Certificate Transparency macht jedes
  Zertifikat und damit jeden Hostnamen öffentlich.
- DNS-01 bräuchte einen Schlüssel, der das ganze DNS ändern kann; HTTP-01
  braucht nur einen offenen Port.
- ARI lässt die CA den Zeitpunkt der Erneuerung bestimmen und schützt bei
  Massen-Sperrungen vor Ausfällen.
- `FROM image@digest AS stufe` plus `COPY --from=stufe` übernimmt eine Datei
  aus einem gepinnten Image, ohne dessen Basis zu erben; Dependabot pflegt
  beide `FROM`-Zeilen.
- Ein Gate, das nur das eigene Image prüft, lässt fremde Images mit
  behebbaren Lücken ungesehen laufen.
- Ein Scanner kann für Pakete außerhalb der Distribution blind sein (nginx
  aus nginx.org); „0 Funde“ zählt nur mit Profil und zweiter Quelle.
- Dependabot kann neue Versionen per Cooldown zurückhalten; der Grund steht
  im Protokoll des Laufs (Ereignis `dynamic` in den Actions).
- Ein Werkzeug, das ausfällt (Docker Desktop beendet), liefert keine Datei;
  das Fehlen eines Ergebnisses ist kein Ergebnis.
- Unter Windows ohne `jq` lässt sich JSON mit `ConvertFrom-Json` in
  PowerShell auswerten, ohne ein neues Werkzeug zu installieren.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-61** | Gate aus ADR-009 für jedes Image auf Staging; Prüfung in der CI; Scan-Profil je Image mit blinden Flecken; zweite Quelle; Ausnahmen nur per ADR mit Ablaufdatum | Ein Maßstab statt keinem; Scanner-Blindheit gemessen (ADR-014) |
| **E-5-62** | ACME-Client lego, als Container mit Digest-Pin | Statische Datei, ARI, kleinste Fläche unter den Kandidaten (ADR-014) |
| **E-5-63** | Eigenes Image: `COPY --from` aus `goacme/lego` auf `gcr.io/distroless/static-debian13:nonroot`, fester Benutzer ohne Root | Einzige Variante, die das Gate einhält; Basis ohne Shell (ADR-014) |
| **E-5-64** | Warnkanal als eigenes ADR-013, nicht als Nachtrag zu ADR-011 | Eine Abhängigkeit, eine Quelle der Wahrheit; einzeln ablösbar |
| **E-5-65** | Staging unter der Subdomain `staging.<domain>` | Hauptdomain frei für Production; Umgebungen schon am Namen getrennt |
| **E-5-66** | DNS: Standardeintrag des Anbieters gelöscht; A mit TTL 300; CAA `issue "letsencrypt.org"` und `issuewild ";"`; AAAA erst nach Nachweis des IPv6-Wegs; kein `iodef` | Sichere Defaults; nur eintragen, was funktioniert; keine öffentliche Mailadresse |
| **E-5-67** | DNSSEC sofort aktiviert, bevor etwas an der Domain hängt | Ein Fehler hätte niemandem geschadet; schützt später auch HTTP-01 |
| **E-5-68** | Authcode der Domain nicht anfordern | Ein angeforderter Authcode ist ein herumliegendes Secret |
| **E-5-69** | Port 443 erst nach nginx 1.30.6; den Dependabot-PR abwarten statt den Pin von Hand zu heben | Fünf CVEs, die der Scanner nicht sieht; Dependabot bleibt einzige Quelle für Pin-Updates |

ADR-Kandidaten: E-5-65 bis E-5-68 gehören in das ADR zum Schritt DNS/TLS
(zusammen mit Port-Freigabe und Erneuerung). Die Cooldown aus 1.7 ist ein
Kandidat für einen Nachtrag zu ADR-005. E-5-61 bis E-5-64 sind in ADR-013 und
ADR-014 dokumentiert.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **nginx 1.30.6:** PR von Dependabot nach dem Lauf vom 26.10. prüfen. Kommt
  keiner, die Cooldown-Länge klären und den Pin in einem eigenen PR heben.
  Gate vor dem Öffnen von Port 443.
- Länge der Cooldown bei Dependabot unbekannt; Nachtrag zu ADR-005 prüfen.
- ADR-013 und ADR-014 stehen auf „Vorgeschlagen“ (wie ADR-006, ADR-008,
  ADR-012).
- Umsetzung ADR-014: Dockerfile für lego, Scan-Profile in
  `invoke-image-scan.sh` (additiv, Rot-Beweis für das API-Profil), CI-Job,
  Veröffentlichung über `publish.yml`.
- Das Gate für das lego-Image wird erst grün, wenn lego mit neuerem Go
  veröffentlicht (Funde in Go-stdlib 1.27.1 und `x/net` 0.59.0).
- Signatur der distroless-Basis nicht selbst geprüft (cosign wäre ein neues
  Werkzeug).
- AAAA-Eintrag fehlt; IPv6-Weg zu nginx unter rootless Docker messen.
  Negative Caching beachten (bis 24 Stunden).
- CAA um `accounturi` und `validationmethods=http-01` ergänzen, sobald das
  ACME-Konto existiert. TTL des A-Eintrags später erhöhen.
- Rootless Docker und Port 80/443; gemeinsame Volumes von lego und nginx
  (UID, Rechte).
- KEV-Einträge vom 16.10.2026 nicht namentlich geprüft.
- `jq` lokal nicht installiert; `invoke-image-scan.sh` läuft lokal unter
  Windows daher nicht (in der CI unverändert).
- Arbeitsdateien im ignorierten Ordner `scan/` (rund 229 MB Image-Archive in
  `scan/in`, rund 3,2 GB Datenbank in `scan/db`) bei Bedarf löschen.
- Lokale Branches `docs/adr-013-alert-channel` und
  `docs/adr-014-third-party-image-gate` sind gemergt und können weg.
- Beschreibung des Checks bei Healthchecks.io auf einen Verweis auf ADR-013
  kürzen (freigestellt).

**Aus Sitzung 20 und früher, weiter offen**

- Eintrag der Ping-URL im Verlauf der Zwischenablage (`Win+V`) löschen, falls
  aktiv (nicht bestätigt)
- IPv4-Erreichbarkeit von `hc-ping.com` nicht getestet
- Vor Production: zweiter Warnkanal oder eigene Instanz bewerten (ADR-013)
- Automatischer Weg (Hook, `unattended-upgrades`, Neustart 04:00) beim
  nächsten echten Docker-Update beobachten
- Gegenprobe „Update-Lücke über 26 Stunden“ nicht gemessen
- Frist des Journals ab 18.11.2026 prüfen
- runc 1.5.2 und CVE-2026-41579: Fix im GitHub-Advisory nachsehen
- CVE-2026-111943: Eintrag bei NVD und CISA KEV nicht geprüft
- NTS und die netcup-Regel `ntp-antworten`
- Zugriffslog von nginx mit Client-IPs (Staging-Variante von `compose.yaml`)
- Journal des Rücksprungs (`nft-rollback.service`) aus Sitzung 18
- Nachträge zu ADR-012 (zweiter), ADR-011, ADR-009, ADR-005
- Maschinenkonto; `compose.yaml` ohne `pids_limit`; Staging-Variante mit
  Image per Digest
- **Token des Agenten läuft am 06.11.2026 ab** (in 11 Tagen)

**Bekannte Grenzen**

- Ausgaben vom Server und aus den Panels von netcup liegen nur als
  Rückmeldung oder Screenshot der Projekt-Ownerin vor. DNS-Zustand und
  Scans sind dagegen selbst gemessen.
- Domain und Server-IP stehen bewusst nicht in diesem Bericht (öffentliches
  Repository, ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Staging-Server gehärtet und überwacht (Bericht 20).
Neu: Domain mit DNSSEC und CAA, Subdomain für Staging. Es fehlen: nginx
1.30.6, lego-Image mit Pipeline, Ports 80/443, Zertifikat, NTS,
Maschinenkonto, Pull-Deploy mit Gate, Freigabe, DORA-Events.

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: lego und distroless aufgenommen (ADR-014); Healthchecks.io dokumentiert (ADR-013) |
| **Image-Gate für fremde Images** | Beschlossen (E-5-61), nicht umgesetzt; nginx 1.30.5 würde scheitern, 1.30.6 besteht |
| **A09 (Alerting)** | Für den Staging-Host erfüllt (Bericht 20) |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** (OWASP ZAP) | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet. lego ruft Let's Encrypt auf; das ist ein ausgehender Aufruf des Hosts, nicht der Anwendung |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant) |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Digests (aufgelöst 25. und 26.10.2026 aus der Registry)

| Image | Index-Digest |
|---|---|
| `gcr.io/distroless/static-debian13:nonroot` | `sha256:18f4cc26c9ffa7f20a359298be7deadac5c607c8e03a02b8119f1a5fc2f82c99` |
| `goacme/lego:v5.5.2` | `sha256:1944e8c36055beec47c7de6f15202b41128be75eea0ffa257f0c14d93c5155fd` |
| `nginxinc/nginx-unprivileged:1.30.6` | `sha256:ec0f7ecb1fbd84959ac114e65fb36074ffc97d4d51db0f18ee925162d889dcef` |
| `nginxinc/nginx-unprivileged:1.30.5` (im Einsatz) | `sha256:8f18dedfceea3d7feb98792810c8c9925c985890ade257f2ec1b2f492b4eaebb` |
| `certbot/certbot:v5.8.0` (verworfen) | `sha256:f70ad0adbb7e117f0fe42a63c553f28ea451edabc0148757b6efcd9735acaa20` |

distroless ist laut README per cosign keyless signiert: Aussteller
`https://accounts.google.com`, Identität
`keyless@distroless.iam.gserviceaccount.com`.

### 6.2 DNS (Stand 26.10.2026)

| Name | Typ | Wert | TTL |
|---|---|---|---|
| `staging` | A | `<server-ipv4>` | 300 |
| `@` | CAA | `0 issue "letsencrypt.org"` | 3600 |
| `@` | CAA | `0 issuewild ";"` | 3600 |

- Nameserver: fünf von netcup; SOA-Minimum 86400 (Negative Caching).
- DNSSEC: Algorithmus 13; DS bei `.at` mit Schlüsselnummer 42182, Digest-Typ
  2; `AD:true` bei Cloudflare und Google.
- Prüfung von außen (Git Bash):
  `curl -s -H "accept: application/dns-json" "https://cloudflare-dns.com/dns-query?name=NAME&type=TYP&do=true"`

### 6.3 Inhalte der lego-Images (Stückliste)

- Upstream `goacme/lego`: `alpine:3` plus `git`, `ca-certificates`, `tzdata`
  und `/lego`; Einstiegspunkt `/lego`; kein `USER`. Gebaut mit Go 1.27.1,
  `golang.org/x/net` v0.59.0. Auf `main` von lego steht `x/net` auf v0.61.0.
- Behebbare Funde: Go-stdlib (Fix 1.26.9 bzw. 1.27.2), `x/net` (0.60.0),
  brotli, expat, pcre2, zlib.

### 6.4 Lokaler Scan fremder Images

```
docker save -o scan/in/DATEI.tar IMAGE:TAG
docker compose --file compose.scan.yaml run --rm grype docker-archive:/in/DATEI.tar --output json=/out/DATEI.json
```

Unter Git Bash vorher `MSYS_NO_PATHCONV=1`. Auswertung ohne `jq` in
PowerShell per `ConvertFrom-Json` (Schwere: `.matches[].vulnerability.severity`,
Fix: `.vulnerability.fix.state -eq 'fixed'`; Blindheit über die
`purl`-Typen in der CycloneDX-Stückliste).

### 6.5 Protokoll eines Dependabot-Laufs

```
gh api "repos/xXxCoder999xXx/identity-service/actions/runs?event=dynamic&per_page=15"
gh run view RUN_ID --log
```

Relevante Zeilen: `Checking if … needs updating`, `Skipping tag … due to
cooldown period`, `Latest version is …`.

### 6.6 Fallstricke, die Zeit gekostet haben

- `git commit -F -` wird vom Hook `Test-CommitConvention` blockiert
  („Betreff nicht lesbar“); Betreff und Text mit mehreren `-m` übergeben.
- `gh pr checks` direkt nach `gh pr create` meldet „no checks reported“;
  kurz warten, dann mit `--watch` beobachten.
- Docker Desktop lief erst nicht, später wurde es während eines Scans
  beendet; `docker buildx imagetools inspect` funktioniert ohne Daemon.
- `invoke-image-scan.sh` passt nur auf das API-Image (Exit 3 bei fremden
  Images) und braucht `jq`.
- Die Änderungen im CloudDNS wurden vor dem vereinbarten Screenshot
  angewendet; die Prüfung von außen hat den Stand trotzdem belegt.

### 6.7 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Branches löschen | Nur Gemergtes entfernen | `git diff --quiet main BRANCH -- DATEIEN`, `git branch -D` | 4 × identisch, gelöscht |
| DNS ändern | Sichere Defaults, kurzer Cache | CloudDNS im CCP | DoH-Abfrage zeigt genau die Einträge |
| DNSSEC einschalten | Fälschung von DNS-Antworten verhindern | Reiter DNSSEC | Insel, dann `AD:true` |
| Kandidaten prüfen | Slopsquatting, Pflege | `gh api repos/OWNER/REPO`, Launchpad, Docker Hub | Organisation, Alter, Releases |
| Images scannen | Messen statt Gefühl | `docker save`, Grype über `compose.scan.yaml` | Tabelle in 1.6 |
| Blindheit prüfen | „0 Funde“ absichern | `purl`-Typen der Stückliste | alle vier erkannt; nginx-CVEs nicht |
| Dependabot verstehen | Fehlender PR | `gh run view … --log` | Cooldown |

---

# Roadmap Sitzung 22

## 1. nginx auf 1.30.6 heben

Warum zuerst: Fünf behobene CVEs, die Grype nicht sieht (1.6), und das
Öffnen von Port 443 hängt daran (E-5-69). Klein und schnell abzuschließen.

Bausteine:
- Prüfen, ob Dependabot am 26.10. einen PR geöffnet hat; Release Notes lesen
  (CLAUDE.md 4: SemVer ist die Absicht des Herausgebers, nicht das Risiko)
- Fehlt der PR: Länge der Cooldown klären, den Pin in einem eigenen PR heben
  (Digest aus 6.1, vorher erneut aus der Registry auflösen)
- `Container & nginx` muss grün sein; Header per echtem Request prüfen

## 2. Umsetzung ADR-014, Teil 1: lego-Image und Scan-Profile

Warum: Ohne geprüftes lego-Image gibt es kein Zertifikat, ohne Zertifikat
keinen TLS-Schritt. Bausteine, erst Konzept, Code nach Freigabe:
- Dockerfile für lego (Ort im Repository, UID, `.dockerignore` als
  Erlaubnisliste beachten)
- `invoke-image-scan.sh` additiv um Profile erweitern; das API-Profil bleibt
  unverändert; Rot-Beweis, dass es bei Blindheit weiter mit Exit 3 scheitert
- CI-Job, der das lego-Image und die Images aus `compose.yaml` scannt;
  Aufnahme als Required Check als eigene Entscheidung
- ADR-Pflicht beachten: neue Pipeline-Schritte sind CODEOWNERS-Pfade

## 3. Danach: Ports 80/443 unter rootless Docker und IPv6

Warum: Voraussetzung für HTTP-01 und den AAAA-Eintrag. Bausteine: Optionen
für privilegierte Ports ohne Root (mit Trade-offs), IPv6-Weg messen, dann
AAAA eintragen; gemeinsame Volumes von lego und nginx.

## 4. Zurückgestellt, nicht aufgehoben

- **NTS und netcup-Regel `ntp-antworten`:** spätestens vor Production; eine
  falsche Uhr bricht TLS und die Prüfung von Zertifikaten.
- **ADR-Nachträge:** ADR-011 (E-5-40 bis E-5-45, E-5-50 bis E-5-53, E-5-56,
  E-5-58), zweiter Nachtrag zu ADR-012, ADR-005 (Cooldown).
- **ADR zum Schritt DNS/TLS:** E-5-65 bis E-5-68 plus Ports und Erneuerung,
  sobald der Schritt abgeschlossen ist.

## 5. Folgende Sitzungen (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 22 | nginx 1.30.6; Konzept und Umsetzung lego-Image, Scan-Profile, CI-Job |
| 23 | Veröffentlichung lego-Image; Ports 80/443, IPv6, Volumes; erstes Zertifikat (zuerst gegen die Staging-Umgebung von Let's Encrypt) |
| 24 | Maschinenkonto, Pull-Deploy mit Prüfung von Nachweis und Signatur, Staging-Variante von `compose.yaml` |
| 25 | Freigabe vor dem Deploy, DORA-Events; DAST fällig |
| ab 26 | Phase 5: STRIDE, erster Use Case test-first |

Schätzung: Der Plan ist in Sitzung 21 um etwa eine Sitzung gerutscht
(Gate für fremde Images, eigenes lego-Image). Phase 5 realistisch nach 4
bis 5 Sitzungen. Abhängig vom nächsten lego-Release.

## 6. Vor oder in der Sitzung zu verstehen (vor Code)

- **Scan-Profil:** Für jedes Image steht fest, welches Betriebssystem und
  welche Paket-Ökosysteme der Scanner finden muss und was er grundsätzlich
  nicht sieht. Erst dann bedeutet „0 Funde“ etwas.
- **Privilegierte Ports ohne Root:** Ports unter 1024 darf unter Linux nur
  root öffnen. Rootless Docker braucht dafür einen Umweg; jeder hat eigene
  Risiken.
- **Cooldown:** Wartezeit vor neuen Versionen schützt vor kompromittierten
  Releases und verzögert Sicherheitsfixes.
- Lehrstoff zu dieser Sitzung:
  [DNS, DNSSEC und ACME-Client-Wahl](https://claude.ai/artifact/2ZACcjPCWVPH6AbeKn6jGg)

## 7. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- ADR-013 und ADR-014 lesen und den Status setzen
- Beschreibung des Checks bei Healthchecks.io auf ADR-013 kürzen
- `Win+V` prüfen und den Eintrag der Ping-URL löschen
- Ablauf des Agenten-Tokens am 06.11.2026 vormerken und Erneuerung planen
