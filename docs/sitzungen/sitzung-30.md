# Sitzungsbericht Sitzung 30

**Datum:** 23.11.2026 (begonnen 10.11.2026)
**Phase:** Schritt 5 (CD): Server-Messungen abgeschlossen, Server-Einstieg des
Prüf-Gates (PR 3b) gemergt und am Server rot/grün belegt; SDK 10.0.404 und
Runtime 10.0.15 auf `main`, `main` vollständig grün; Deploy-Skript (PR 4)
offen (Frist 27.12.2026)
**Vorgänger:** sitzung-29.md (abgeschlossen 10.11.2026)

---

## 1. Erledigt

| PR | Titel | Merge |
|---|---|---|
| #157 | `build(deps): bump .NET SDK to 10.0.404` | `6e13fc7` |
| #158 | `feat(scripts): add server entry for attestation verification` | `768bbb4` |

Beide von der Projekt-Ownerin per Squash gemergt, überwiegend KI-erzeugt, kein
Auto-Merge. In dieser Sitzung außerdem gemergt (Bot-PRs): #152 (aspnet
`f2557fb` → `7c625e4`, Runtime 10.0.15), #154 (distroless lego `25ac8f0` →
`aafe993`), #156 (grype v0.121.3 → v0.122.1). Geschlossen: #153
(SDK-Digest allein, ersetzt durch #157), #155 (SDK 11.0.100, Hauptversion).
Bericht 29 als #151 gemergt.

### 1.1 Aktualität

- 10.11.2026: `gh` v2.103.3 neuestes Release; keine neuen Advisories seit
  30.09.2026.
- 23.11.2026: neu `gh` v2.104.0 (sigstore-go 1.3.0 → 1.4.0) und v2.105.0
  (18.11.2026, `gh event`, keine Änderung an `attestation`); Runner-Image
  `ubuntu-24.04` 20261116.376.1 mit `gh` 2.104.0; keine neuen Advisories.
- .NET 10: Runtime 10.0.15 und SDK 10.0.404 vom 10.11.2026 (Release-Metadaten
  von Microsoft).
- grype v0.122.0 (16.11.) und v0.122.1 (18.11.) nachträglich gelesen (siehe
  1.7).

### 1.2 Server-Messungen (Roadmap-Punkt 1, 10.11.2026)

Alle Läufe als Deploy-Benutzer, rootless Docker über
`/run/user/<UID>/docker.sock`, Registry-Anmeldung über temporären
`DOCKER_CONFIG`, Token aus `/etc/credstore/identity-service-deploy.ghcr-token`
(`600 root:root`) per Umleitung in `--password-stdin`; `trap` räumt auf
(nachgeprüft: Verzeichnis entfernt).

| Messung | Ergebnis | Gegenprobe |
|---|---|---|
| Server-Werkzeuge | `gh` 2.103.3; `strace` fehlt | – |
| Gespeicherte Anmeldung `/home/<deploy>/.docker/config.json` | nur leeres `"auths"`, kein `"auth"` | Muster trifft `"auths"` |
| Pull per Digest mit Maschinenkonto (API, nginx, lego) | alle drei erfolgreich → Leserecht belegt | ohne Anmeldung `unauthorized` |
| `gh` mit leerem `HOME` | Verifikation erfolgreich; schreibt `$HOME/.cache/gh/.sigstore/root/{tuf-repo.github.com,tuf-repo-cdn.sigstore.dev}/…` und `$HOME/.local/state/gh/device-id`; nichts außerhalb des Homes | Home vorher 0 Einträge |
| Netzziele (`GH_DEBUG=api` + `GODEBUG=netdns=go+2`) | DNS: `ghcr.io`, `pkg-containers.githubusercontent.com`, `tuf-repo.github.com`, `tuf-repo-cdn.sigstore.dev`; HTTP (`gh` selbst): 13× tuf-repo.github.com, 9× tuf-repo-cdn.sigstore.dev; **kein `api.github.com`**, kein Telemetrie-Ziel | `ghcr.io` im DNS-Protokoll |
| `GH_TOKEN` = Platzhalter | Verifikation besteht, dieselben vier Ziele | falscher Workflow → `Error: verifying with issuer "sigstore.dev"` (erwarteter Grund) |

### 1.3 Server-Einstieg (#158, Roadmap-Punkt 2)

- `scripts/verify-attestations-server.sh IMAGE_REF NGINX_DOCKERFILE`: nur
  `--bundle-from-oci`, Herkunftsnachweis und Stückliste, drei Gegenproben
  (fremdes Image, falscher Workflow, falscher Branch), Exit 0/2/3/4/5.
  Konstanten: Repository, Server-URL, Repository-ID `1296648545`,
  Besitzer-ID `291064355` (API, 23.11.2026), Zuordnung Paket → Workflow →
  Gegenprobe-Workflow. Setzt selbst `GH_TOKEN`-Platzhalter,
  `GH_TELEMETRY=false`, `DO_NOT_TRACK=true`, entfernt `GITHUB_TOKEN`,
  `GH_ENTERPRISE_TOKEN`, `GITHUB_ENTERPRISE_TOKEN`, `GH_HOST`, `GH_DEBUG`.
  Mindestversion `gh` 2.103.3 (`sort --version-sort`).
- Kopf von `scripts/lib/attestation-rules.sh` nennt beide Einstiege.
- `publish.yml`, `publish-lego.yml` (auch Pfadfilter), `publish-nginx.yml`:
  Schritt „Server-Prüfung nachstellen (nur Registry, ohne Token)“ nach dem
  Prüf-Gate.
- Lokal belegt: `bash -n`, ASCII, Workflows per `docker compose config`
  geparst; Exit 2 für keine Parameter, Tag statt Digest, kurzer Digest,
  fremdes Paket, anderer Besitzer, Großbuchstaben im Digest, `gh` 2.102.0;
  Exit 3 mit `gh`-Attrappe.
- **Rot-Beweis am Server** (23.11.2026, Commit `2c0fc4a0`, Archiv statt Klon,
  Prüfsummen beider Skripte gleich den lokal berechneten), Image
  `identity-service@sha256:cb8bcbcc…1354`: Lauf G (echte Werte) Exit 0, alle
  Gegenproben am erwarteten Grund; Lauf R (Repository-ID um 1 verfälscht)
  Exit 3, Zertifikat zeigt `1296648545`.
- Nach dem Merge: `Publish` `45177231370`, `Publish nginx` `45177231435`,
  `Publish lego` `45177231313` grün, neuer Schritt je 3/3 Gegenproben, `gh`
  2.104.0, ohne Token. CI `45177231333`, CodeQL `45177231289` grün.

### 1.4 `main` rot seit 16.11.2026 und Behebung

- Wochenlauf CI `43875490877`: `Image-Scan` rot, ASP.NET-Core-Runtime 10.0.14
  im API-Image, High: GHSA-wr8v-9x5q-ggcm, GHSA-x33c-w48q-qrgc,
  GHSA-67wp-ghc2-fw2g (Fix 10.0.15).
- #152 (Runtime 10.0.15) von der Ownerin gemergt; CI `45166408329` und
  Publish `45166408254` grün. Das Prüf-Gate darin zeigte mit `gh` 2.104.0
  dieselben Feldnamen und Kennungen (sigstore-go 1.4.0 unkritisch).

### 1.5 Vier blockierte Bot-PRs

Keiner hatte einen Git-Konflikt (alle `MERGEABLE`). Blockiert durch rote
Pflicht-Checks und `BEHIND` (Strict-Mode). #153: SDK 10.0.404 im Image,
`global.json` 10.0.403 → „A compatible .NET SDK was not found“. #155:
`global.json` 11.0.100, Image SDK 10. `Image-Scan` war in allen rot wegen 1.4.

### 1.6 SDK 10.0.404 (#157)

- `global.json` 10.0.403 → 10.0.404; Build-Stage-Digest aus der Registry
  (Registry-API und `docker buildx imagetools inspect`), neuer als in #153.
- Lokal: SDK per `winget` (Herausgeber Microsoft Corporation); Installer-URL
  im winget-Manifest (`download.microsoft.com`) weicht von der Release-Liste
  (`builds.dotnet.microsoft.com`) ab; unabhängiger Beleg: Authenticode von
  `sdk\10.0.404\dotnet.dll` `Valid`, `CN=.NET, O=Microsoft Corporation`,
  Issuer `Microsoft Code Signing PCA 2024`.
- Lokale Kette grün: `restore --locked-mode` (Lockfiles unverändert), Build 0
  Warnungen, Format, Test 2/2, `compose up --build`, `/health` 200 über nginx.
- CI `45174096304`: `setup-dotnet` installierte 10.0.404, Container-Build mit
  `bef136a37196…`; alle 8 Checks grün.

### 1.7 Bot-PRs #154 und #156 (nachträglich geprüft)

Vor dem Lesen der Release Notes gemergt. Nachträglich: grype-Digest gleich der
Registry; v0.122.0/v0.122.1 reguläre Releases (Versionsabgleich rpm/Java, DHI
OSV, 13 Abhängigkeiten, GHSA-q7gw-24fr-5p69 in grype behoben, Korrektur
`--scope all-layers` betrifft uns nicht, Scan läuft mit Standard `squashed`).
distroless `aafe993` existiert (Index amd64/arm64), ist aber schon überholt
(`nonroot` → `8ce6dd87…`). Läufe auf `238e56d` und `de2e17e` grün,
Blindheits-Schutz mit grype v0.122.1 bestanden.

### 1.8 Lehrstoff

- [Lehrstoff: Server-Prüfung messen und einführen](https://claude.ai/artifact/JxATbrPegN97BLkcvqBdsZ)
  (Messen mit Gegenprobe, Bordmittel vor Paket, Platzhalter-Token, TUF-Gedächtnis,
  zwei Einstiege mit Diagramm, Rot-Beweis, gekoppelte Änderungen, Fallen,
  Spickzettel)

---

## 2. Gelernt

- `gh attestation verify --bundle-from-oci` spricht die GitHub-API nicht an;
  es braucht nur Registry (`ghcr.io` und dessen Blob-Speicher
  `pkg-containers.githubusercontent.com`) und zwei TUF-Quellen.
- `gh` verlangt `GH_TOKEN` als gesetzte Variable, sendet sie mit
  `--bundle-from-oci` aber nicht; die Registry-Anmeldung liest es aus der
  Docker-Konfiguration.
- Die Go-Laufzeit protokolliert mit `GODEBUG=netdns=go+2` jede Namensauflösung
  eines Prozesses; das ersetzt `strace` für die Frage „welche Hosts?“.
- `GH_DEBUG=api` zeigt nur den HTTP-Client von `gh` selbst, nicht den
  Registry-Client.
- `gh` legt seinen TUF-Zwischenspeicher unter `$HOME/.cache/gh/.sigstore/root/`
  an und eine `device-id` unter `$HOME/.local/state/gh/`.
- TUF schützt nur mit gespeichertem Zustand gegen Rollback auf ältere, gültig
  signierte Metadaten.
- Befehlszeilen sind für alle Benutzer per `ps` sichtbar, Umgebungsvariablen nur
  für root und den Besitzer.
- systemd kann Netzziele nur per IP-Adresse erlauben; CDN-Ziele lassen sich so
  nicht eingrenzen.
- „Nicht mergebar“ in GitHub heißt bei aktivem Strict-Mode oft „Checks rot“
  oder „Branch veraltet“, nicht Git-Konflikt.
- Dependabot ändert gekoppelte Pins (`global.json`, SDK-Digest) einzeln; keiner
  der Einzel-PRs kann grün werden.
- Ein winget-Manifest ist nicht die Primärquelle; die Authenticode-Signatur der
  installierten Dateien ist ein unabhängiger Herkunftsbeleg.
- Der erste Start eines neuen .NET-SDK legt ein (nicht vertrautes)
  ASP.NET-Core-Entwicklungszertifikat im Benutzerspeicher an.
- GitHub liefert jeden Commit als `tar.gz` über die volle Commit-SHA; ohne
  Signatur, aber per Prüfsumme gegen einen lokalen Stand prüfbar.
- Der Commit-Hook liest den Betreff nur aus `-m`; Heredoc mit `-F -` wird
  blockiert.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-134** | TUF-Zwischenspeicher der Deploy-Unit dauerhaft: `CacheDirectory=identity-service-deploy`, `XDG_CACHE_HOME` dorthin; Home bleibt `tmpfs` | Rollback-Schutz von TUF braucht Zustand; weniger Abrufe; Inhalt ist signiert |
| **E-5-135** | Netzziele der Deploy-Unit: IP-Allowlist nicht möglich (CDN); Wahl zwischen nur `RestrictAddressFamilies`, Egress-Proxy oder DNS-befüllten nftables-Sets in PR 4 | gemessen: vier Hostnamen hinter CDNs |
| **E-5-136** | Server-Einstieg setzt festen Platzhalter in `GH_TOKEN`; echtes Token nur im temporären `DOCKER_CONFIG`. **Ersetzt den Token-Teil von E-5-109** | gemessen: Platzhalter genügt; Token nicht in der Umgebung; Stolperdraht bei künftigen API-Aufrufen (fail closed) |
| **E-5-137** | Aufruf mit `IMAGE_REF` und `NGINX_DOCKERFILE`; Zuordnung Paket → Workflow → Gegenprobe-Workflow als Konstante im Einstieg | Aufrufer kann keinen Workflow hineinreichen (E-5-122) |
| **E-5-138** | Server verifiziert auch die Stückliste aus der Registry | gehört zum ausgerollten Digest; ein Aufruf mehr |
| **E-5-139** | Einstieg setzt `GH_TOKEN`-Platzhalter, `GH_TELEMETRY=false`, `DO_NOT_TRACK=true` selbst. **Verschiebt E-5-108 von der Unit in den Einstieg** | gleiche Bedingungen auch bei Läufen von Hand; eine Quelle |
| **E-5-140** | Mindestversion `gh` 2.103.3, darunter Exit 2 | Advisories vom 30.09.2026 betreffen `attestation verify`; Meldungen an 2.102.0/2.103.3 belegt |
| **E-5-141** | Server-Einstieg läuft in jedem `publish*.yml` nach dem Prüf-Gate, ohne Token | selten Laufendes bricht still (Lehre aus #146) |
| **E-5-142** | `git`, `jq`, `gpg` fehlen auf dem Server; Aufnahme als Debian-Pakete wird in PR 4 entschieden (Aufnahme- und Slopsquatting-Prüfung) | Deploy-Ablauf E-5-113 braucht `git fetch`, Signaturprüfung, JSON |

ADR-Kandidaten: alle als Nachtrag zu ADR-015 (Pull-Deploy, Prüfer und
Registry-Zugriff); E-5-134, E-5-135 und E-5-142 zusätzlich im geplanten ADR
„Pull-Deploy auf Staging“.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Bot-PRs vor dem Merge lesen:** #154 und #156 wurden vor dem Lesen der
  Release Notes gemergt (wie #147 in Sitzung 29). Nachprüfung unauffällig.
- distroless für lego schon wieder veraltet (`nonroot` → `8ce6dd87…`,
  23.11.2026); neuer Dependabot-PR zu erwarten.
- `dependabot.yml`: Hauptversions-Sprünge des SDK ignorieren (sonst kehrt
  #155 wieder); additiv, eigener PR.
- Lokales `gh` 2.102.0 liegt unter der Mindestversion des Server-Einstiegs;
  Advisories vom 30.09.2026 low.
- Lokal installierte SDKs 10.0.303 und 11.0.100 unbenutzt; ASP.NET-Core-
  Entwicklungszertifikat angelegt (nicht vertraut, nicht verwendet, kein
  `--trust`).
- Telemetrie: `device-id` wird angelegt, ein Telemetrie-Ziel war nicht zu
  sehen; Hintergrundprozesse und reine IP-Verbindungen waren mit der Methode
  unsichtbar → Gegenprobe ist die Sandbox der Unit.
- `gh` auf dem Server (2.103.3) hinter dem neuesten Release (2.105.0);
  Update-Weg offen.
- Server-Einstieg ist noch nicht unter `/usr/local/lib/identity-service/`
  installiert (E-5-117); Installation gehört zu PR 4.
- Lokale Branches löschen (Freigabe nötig): `feat/server-attestation-entry`,
  `build/dotnet-sdk-10-0-404`, `docs/sitzung-29` und die Liste aus Bericht 29.

**Aus Sitzung 29 und früher, weiter offen**

- **Deploy-Skript und Units bis spätestens 27.12.2026** (`restart_api`,
  Restart-Unit E-5-120, drei Digests API/nginx/lego, E-5-111).
- **Token des Agenten läuft am 27.11.2026 ab** (Erneuerung fällig).
- **GHCR-Token läuft am 28.01.2027 04:31 UTC ab;** Erinnerung ab etwa
  14.01.2027.
- Lokale Zertifikate laufen am 31.01.2027 12:46 UTC ab; Erinnerung ab etwa
  24.01.2027.
- E-5-128 nicht umgesetzt (Wochenlauf scannt nginx als frischen Build).
- Push- und Digest-Logik dreifach in `publish*.yml` (`scripts/push-image.sh`).
- `verify-package-private.sh`: Pfad „Registry nicht erreichbar“ nicht gemessen.
- „Manage Actions access“: Write statt Admin nicht belegt.
- Aufbewahrungsregel für Image-Versionen in GHCR fehlt.
- ADR-016 und ADR-015 auf „Akzeptiert“ (Ownerin); Nachträge zu ADR-015
  (E-5-109, E-5-110, E-5-121 bis E-5-123, jetzt auch E-5-134 bis E-5-142),
  ADR-016 (E-5-130, E-5-132), ADR-010/015 (E-5-131, E-5-133); ADR
  „Pull-Deploy auf Staging“ (E-5-111 bis E-5-120); weitere Nachträge siehe
  Bericht 29.
- `.claude/rules/container-und-nginx.md` und `.claude/rules/lieferkette-und-ci.md`
  nachziehen (Ownerin); zusätzlich: zweiter Einstieg
  `verify-attestations-server.sh`.
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy.
- Kestrel-Neuladen auf dem Server, nginx und alte TLS-Sitzungen nach
  Zertifikatswechsel nicht gemessen.
- Erster automatischer Lauf des Erneuerungs-Timers nicht abgelesen.
- Server: `PermitRootLogin`, `unattended-upgrades`, Docker 29.9.2, runc 1.5.2,
  Journal-Frist, NTS, `nft-rollback.service`; `user: "1654:1654"` in
  `compose.staging.yaml`; Units von host-health-check nicht im Repository.
- CI-Job für die Exit-Pfade der Bash-Skripte.
- CA-Wechsel vor dem 28.10.2027.
- Weitere Einzelpunkte unverändert aus Bericht 29, Abschnitt 4.

**Bekannte Grenzen**

- Das Archiv eines Commits hat keine Signatur; der Rot-Beweis stützte sich auf
  Prüfsummen gegen den lokalen Stand.
- Der Platzhalter beruht auf nicht dokumentiertem Verhalten von `gh`; eine
  Änderung führt zu Exit 3 bzw. 5 (fail closed).
- Domain, Server-IPs, Hostnamen und Benutzernamen stehen bewusst nicht in
  diesem Bericht (ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Prüf-Gate für Server und CI aus einer Bibliothek,
am Server belegt; `main` vollständig grün (`768bbb4`).

| Nr. | Schritt | Abhängig von |
|---|---|---|
| 1 | ~~Staging-Konfiguration~~ erledigt | – |
| 2 | Interne CA: erledigt bis auf **API-Neustart** (E-5-120) | 5 |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer | Required Check |
| 4 | ~~Maschinenkonto, Leserecht auf drei Paketen~~ erledigt (gemessen) | – |
| 5 | Pull-Deploy: ~~Ablauf, Prüfregeln, Messungen, 3b~~; **Skript, Units, Pakete offen** | E-5-142 |
| 6 | Freigabe vor dem Deploy (Digest-Commit, E-5-111), DORA-Events | 5 |
| 7 | DAST (OWASP ZAP) | 5, 6 |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: SDK 10.0.404 (Digest aus Registry, Signatur lokal), Runtime 10.0.15, grype v0.122.1 und distroless nachträglich geprüft; drei Server-Pakete stehen an (E-5-142) |
| **A01 / Zugriff** | Leserecht des Maschinenkontos auf alle drei Pakete gemessen; Pakete weiter privat (Gegenprobe `unauthorized`) |
| **A10 / fail closed** | Server-Einstieg: jeder Fehler Exit ≠ 0, Mindestversion, Platzhalter als Stolperdraht |
| **Secrets (6.3.3)** | Token nur über stdin und temporären `DOCKER_CONFIG`; kein echtes Token an `gh`; Debug-Ausgabe nur gefiltert |
| **Image-Gate** | grün für API, nginx, lego |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7; Timeouts je Netzaufruf (`curl --max-time`) |
| **mTLS, Contract Testing, Feature Flags, Mutation Testing, k6** | Nicht fällig |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (aufgelöst 23.11.2026, sofern nicht anders angegeben)

| Gegenstand | Wert | Quelle |
|---|---|---|
| `mcr.microsoft.com/dotnet/sdk:10.0-noble` = `:10.0.404-noble` | `sha256:bef136a371963aaa46ec97882845ef6f54dec15728bb4b128b1c2a400ffbc9b4` (Manifest-Liste amd64, arm/v7, arm64) | Registry-API, `imagetools` |
| `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` = `:10.0.15-noble-chiseled` | `sha256:7c625e44e5d588b4d7b2a913e94ca4bd5098ce47442da404829e4c7936a764e1` | Registry-API |
| `…aspnet:10.0.14-noble-chiseled` (alt) | `sha256:f2557fb81b1cfcfdfcde9d3bf247ed60b2cd38f00a88153f61e34737fab8ade7` | Registry-API |
| `ghcr.io/anchore/grype:v0.122.1` | `sha256:661583704a253c0448ed63998b5ea2cd9d5a76ee71eedc4aed439b8ce3e93a1c` | `imagetools` |
| `gcr.io/distroless/static-debian13:nonroot` | aktuell `sha256:8ce6dd87e9823c5b48dcfb2c8604714ccb351ce59607327bcc4957448da279b5`; auf `main` `aafe993…3931` | `imagetools` |
| `gh` | Server 2.103.3; Runner 2.104.0 (Image 20261116.376.1); neuestes 2.105.0 (18.11.2026); lokal 2.102.0 | Messung, `actions/runner-images`, `cli/cli` |
| .NET 10 | Runtime 10.0.15, SDK 10.0.404 (10.11.2026) | Release-Metadaten Microsoft |
| Repository-ID / Besitzer-ID | `1296648545` / `291064355` | GitHub-API, Zertifikat |
| API-Image | `sha256:63a1ae6e173e43cd5a2ff9a9ab817d7da0efa4f1700d36c2dcfe0a94887ed6a8` (`768bbb4`); `cb8bcbcc…1354` (`de2e17e`, Rot-Beweis) | `Publish` |
| nginx-Image | `sha256:df0163508f6836f314c81014234f54b69385b4148735c48417e99b76d9c7e629` (`768bbb4`) | `Publish nginx` |
| lego-Image | `sha256:55b687f90172014478983f66591ee62b634cf36d081ccb9205348ef6dadcf612` (`768bbb4`) | `Publish lego` |
| `main` nach der Sitzung | `768bbb4` | `git log` |

### 6.2 Server: Werkzeuge und Pfade (gemessen)

| Gegenstand | Wert |
|---|---|
| vorhanden | `gh` 2.103.3, `curl`, `tar`, `flock` |
| fehlt | `git`, `jq`, `gpg`, `strace` |
| Token des Maschinenkontos | `/etc/credstore/identity-service-deploy.ghcr-token`, `600 root:root` |
| Docker-Socket (rootless) | `/run/user/<UID des Deploy-Benutzers>/docker.sock` |
| TUF-Zwischenspeicher | `$XDG_CACHE_HOME/gh/.sigstore/root/` bzw. `$HOME/.cache/gh/…` |
| Netzziele des Prüfers | `ghcr.io`, `pkg-containers.githubusercontent.com`, `tuf-repo.github.com`, `tuf-repo-cdn.sigstore.dev` |

### 6.3 Exit-Codes `scripts/verify-attestations-server.sh`

| Code | Bedeutung |
|---|---|
| 0 | Herkunftsnachweis und Stückliste verifiziert, drei Gegenproben abgelehnt |
| 2 | Parameter ungültig, unbekanntes Paket, `gh` fehlt oder älter als 2.103.3, Bibliothek fehlt |
| 3 | Nachweis fehlt, ungültig oder Angaben/Kennungen weichen ab |
| 4 | Gegenprobe akzeptiert |
| 5 | Gegenprobe nicht am erwarteten Grund gescheitert |

### 6.4 Läufe als Belege

| Zweck | Lauf |
|---|---|
| `main` rot (Runtime 10.0.14) | CI `43875490877` |
| nach #152 | CI `45166408329`, Publish `45166408254` |
| #157 im PR | `45174096304` |
| nach #154/#156 | CI `45175999644`, Publish `45175999655`, Publish nginx `45175999790` |
| nach #158 | Publish `45177231370`, Publish nginx `45177231435`, Publish lego `45177231313`, CI `45177231333` |

### 6.5 Fallstricke, die Zeit gekostet haben

- `git` fehlt auf dem Server → erster Rot-Beweis brach ab; vorher
  `command -v` für alle Werkzeuge eines Blocks.
- Commit-Hook blockiert `git commit -F -`; mehrere `-m` verwenden.
- Lokale SDKs passten nicht zu `global.json` (lokal ≠ CI unbemerkt).
- Bot-Digest war schon überholt; immer aus der Registry auflösen.
- Debug-Protokolle können Header enthalten: in root-eigene Datei schreiben,
  nur Hostnamen herausfiltern.
- `runuser` ohne `-l` setzt `HOME` neu: `HOME` danach per `env` setzen.

### 6.6 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Leserecht | Deploy muss ziehen können | `docker login --password-stdin < credstore`, `docker pull …@sha256` | 3/3, ohne Login `unauthorized` |
| TUF-Ort | Sandbox braucht beschreibbaren Pfad | leeres `HOME`, `find` | `$HOME/.cache/gh/.sigstore/root` |
| Netzziele | Sandbox-Grenzen | `GODEBUG=netdns=go+2` | vier Hosts, keine API |
| Platzhalter | Least Privilege | `GH_TOKEN=platzhalter…` | besteht, Gegenprobe ok |
| #158 | zweiter Einstieg | `verify-attestations-server.sh` | Rot 3 / Grün 0 am Server |
| #157 | gekoppelte Pins | `global.json` + Digest | 8/8 Checks, SDK 10.0.404 |

---

# Roadmap Sitzung 31

## 1. Agenten-Token erneuern (vor oder zu Beginn der Sitzung)

Warum zuerst: Es läuft am 27.11.2026 ab; ohne Token kann der Agent keine
Läufe, PRs oder Checks mehr ablesen. Ablauf: GitHub → Fine-grained tokens →
Regenerate (Rechte unverändert), dann `gh auth login` in eigenem Fenster.

## 2. PR 4 Konzept: Deploy-Skript, Units, Digest-Datei

Warum: fristgebunden (27.12.2026); alle Voraussetzungen gemessen. Bausteine:

- Paketentscheidungen E-5-142 (`git`, `jq`, `gpg`): Aufnahme-Prüfung,
  Slopsquatting-Prüfung gegen das Debian-Archiv, Alternativen (z. B. Archiv
  per Commit-SHA statt `git`, aber dann keine Commit-Signatur).
- Digest-Datei mit drei Digests (API, nginx, lego) und ihr Format (E-5-111).
- Unit-Sandbox nach E-5-118 plus E-5-134 (`CacheDirectory`), E-5-135
  (Netzziele), Installation des Prüfers unter
  `/usr/local/lib/identity-service/` (E-5-117).
- Restart-Unit, `restart_api`, Gegenprobe „Neustart scheitert → /fail“
  (E-5-120); ADR „Pull-Deploy auf Staging“.
- Aufteilung in mehrere PRs (ein Thema pro Branch).

## 3. E-5-128: Wochenlauf scannt den veröffentlichten nginx-Digest

Warum: Das veröffentlichte nginx-Image veraltet sonst still; spätestens vor
dem ersten Staging-Deploy.

## 4. `dependabot.yml`: SDK-Hauptversionen ignorieren

Warum: verhindert, dass #155 wiederkehrt; additiv, kleiner PR.

## 5. refactor: `scripts/push-image.sh`

Warum: dritte Kopie der Push- und Digest-Logik; Beleg „Ausgabe vorher =
nachher“.

## 6. Kurze Punkte der Ownerin

- ADR-015 und ADR-016 auf „Akzeptiert“
- `.claude/rules/*.md` nachziehen (nginx-Image, `publish-nginx.yml`,
  `verify-package-private.sh`, `verify-attestations-server.sh`)
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy
- Gemergte lokale Branches löschen
- Bericht 30 ins Repository (Branch `docs/sitzung-30`)
- Neuen distroless-PR für lego **vor** dem Merge lesen lassen

## 7. Zurückgestellt, nicht aufgehoben

- E-5-129: ungenutzte Pakete aus dem nginx-Image entfernen
- Aufbewahrungsregel für Image-Versionen in GHCR
- Ports 80/443 und erstes Zertifikat
- Server-Härtung; Update-Weg von `gh` auf dem Server
- Telemetrie von `gh` in der CI abschalten
- ADR-Nachträge (siehe Offene Punkte)
- „Manage Actions access“: Write statt Admin belegen
- CA-Wechsel vor dem 28.10.2027; vor Production: NTS, IPv6, zweiter
  Warnkanal, HSTS

## 8. Vor oder in der Sitzung zu verstehen (vor Code)

- **Commit-Signatur als Freigabe:** E-5-111 macht den Merge-Commit auf `main`
  zur Freigabe des Deploys. Der Server prüft die Web-Flow-Signatur mit einem
  eigenen Schlüsselbund; dafür braucht er `git` und `gpg`. Ohne `git` gäbe es
  nur das unsignierte Archiv.
- **Netzziele hinter CDNs:** systemd erlaubt nur IP-Adressen; Hostnamen-
  Allowlists brauchen einen Proxy oder DNS-befüllte Firewall-Sets. Die Wahl
  ist ein Trade-off zwischen Schutz und beweglichen Teilen.
- **TUF-Gedächtnis:** Ein dauerhafter Zwischenspeicher signierter Metadaten
  ist der Schutz gegen Rollback, nicht ein Risiko.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Server-Prüfung messen und einführen](https://claude.ai/artifact/JxATbrPegN97BLkcvqBdsZ)

## 9. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- Agenten-Token erneuern (vor dem 27.11.2026)
- SSH-Zugang zum Server bereithalten
- Erinnerungen: GHCR-Token vor dem 28.01.2027, lokale Zertifikate vor dem
  31.01.2027
