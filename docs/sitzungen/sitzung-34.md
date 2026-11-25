# Sitzungsbericht Sitzung 34

**Datum:** 25.11.2026
**Phase:** Schritt 5 (CD), Phase 4: erstes lego-Zertifikat geholt, **erster
Deploy auf Staging erfolgreich**, Ports 80/443 in beiden Firewall-Schichten
offen, Gegenprobe 9 bestanden, CAA verschärft. Erneuerung des
nginx-Zertifikats gebaut und gemergt (#179), **noch nicht installiert**.
Deploy-Timer weiterhin aus.
**Vorgänger:** sitzung-33.md (abgeschlossen 24.11.2026)

---

## 1. Erledigt

| PR | Titel | Merge | Signatur |
|---|---|---|---|
| #175 | `refactor(deploy): move staging container lookup into shared library` | `214626d` | `verified=true`, `valid` |
| #176 | `feat(deploy): obtain first edge certificate during first deploy` | `f8acce9` | `verified=true`, `valid` |
| #177 | `chore(deploy): release f8acce9 images to staging` | `e98d287` | `verified=true`, `valid` |
| #178 | `refactor(deploy): move release and ping helpers into shared library` | `202c6b0` | `verified=true`, `valid` |
| #179 | `feat(deploy): add daily renewal of the nginx certificate` | `85f4473` | `verified=true`, `valid` |

Alle von der Projekt-Ownerin per Squash gemergt, überwiegend KI-erzeugt, kein
Auto-Merge. Signaturen über die GitHub-API geprüft. #174 (Bericht 33) war zu
Sitzungsbeginn bereits gemergt (`c067d91`).

Die Ownerin hat **`Image-Scan Drittanbieter (lego)` und `(nginx)` als
Required Checks** ins Ruleset aufgenommen (offener Punkt seit Bericht 30, vor
dem ersten lego-Deploy). Ab #177 laufen sie als Pflicht.

### 1.1 Konzept erstes Zertifikat (E-5-197 bis E-5-199)

- Abgleich mit E-5-65, E-5-66, E-5-73 bis E-5-76, E-5-78, E-5-80, E-5-82,
  E-5-83, E-5-88, ADR-014. Die Empfehlung „Standalone bei gestopptem nginx“
  aus Bericht 24 war nie entschieden. Jetzt ist sie es (E-5-197).
- lego v5.6.0 aus dem Primär-Repo (Tag `v5.6.0`) gelesen:
  - Flags gehören hinter den Unterbefehl `run`.
  - Es gibt **kein** `--http.port`, das Flag heißt `--http.address`, Standard `:80`.
  - `--server` kennt die Kurzcodes `letsencrypt` und `letsencrypt-staging`.
  - `--email` ist optional, Schlüsseltyp Standard EC256.
  - Speicher unter `<path>/accounts` und `<path>/certificates`, Dateien `edge.crt`, `edge.key`, `edge.issuer.crt`, `edge.json`.
  - `lego run` holt ein Zertifikat, wenn keines unter dem Namen liegt, sonst erneuert es nur bei Fälligkeit (`cmd/cmd_run.go:67–101`, `cmd/internal/root/process_renew.go:67–77`).
  - `certificates list` endet auch ohne Zertifikat mit Exit 0.
  - lego v5.7.0 (21.11.2026) enthält laut Release Notes keine Sicherheitskorrektur. Letzte Sicherheitswarnung: GHSA-qqx8-2xmm-jrv8, im Pin behoben.
- Let's Encrypt, Rate Limits (Stand der Seite 05.08.2026):
  - 5 fehlgeschlagene Validierungen je Name und Konto pro Stunde, eine kommt alle 12 Minuten zurück
  - 5 doppelte Zertifikate in 7 Tagen
  - ARI-Erneuerungen von allen Limits ausgenommen
- Let's Encrypt, Staging (Stand 10.04.2026): eigene Konten, Zertifikate **nicht** vertrauenswürdig.

### 1.2 PR #175: Container-Suche in die Bibliothek

- `staging_container_ids [LABEL=WERT …]` in `scripts/lib/staging-runtime.sh`:
  - Das Projekt-Label steht immer dabei.
  - Argumente ohne die Form `LABEL=WERT` werden abgelehnt. Ein nackter Schlüssel wäre fail open, weil `docker ps` dann nur auf das Vorhandensein des Labels filtert.
- `restart-api.sh` nutzt die Funktion mit unveränderten Argumenten für `docker ps`.
- Belege: Restart-Tests unverändert grün (33 ok-Zeilen wie auf `main`), Mutationen 3/3.
- CI: Deploy-Tests 122 Fälle, 0 übersprungen.

### 1.3 PR #176: Erst-Zertifikat im Erst-Deploy

Neuer Schritt 5b in `deploy-staging.sh`, nur bei `decision=first`, nach dem
Pull per Digest und vor `compose up`:

1. Ist das Projekt nicht leer (auch ein gestoppter Container zählt) oder scheitert `docker ps`, folgt **Exit 2**.
2. lego wird gestartet:
   ```
   docker compose -p identity-service-staging … --profile acme run --rm -T --pull never --publish 0.0.0.0:80:8080 lego run --path /data --accept-tos --http --http.address :8080 --cert.name edge --domains <server_name>
   ```
   Zeitgrenze `timeout --kill-after=10 300`.
3. Einmal-Container von lego werden immer entfernt, per Label (`service=lego`, `oneoff=True`), nie per Name.
4. Projekt erneut leer, sonst **Exit 13**.
5. lego ungleich 0 ergibt **Exit 13** (neu, erweitert E-5-185). Gestartet ist dann nichts, und es gibt kein `current`.

Belege:
- Tests: 169 ok-Zeilen, Mutationen 10/10 und 4/4. CI: 169 Fälle, 0 übersprungen.
- Code-Review:
  - Fehler „IPv6 offen“ behoben: `0.0.0.0:80:8080` statt `80:8080` (E-5-73).
  - Fehler „`rm -f` per Name könnte einen fremden Container löschen“ behoben: Aufräumen nur noch per Label, `--name` entfällt.
  - Hinweis „kein `--server`“: bewusst so entschieden (E-5-198).

Lokal laufen die Deploy-Tests mit nativen Links:
`MSYS=winsymlinks:nativestrict bash scripts/test-deploy-staging.sh`. Auf
`main` ergab das zur Gegenprobe 122 Fälle.

### 1.4 Installation Runde 3 am Server (Commit `f8acce9`, E-5-191)

- Paket `identity-service-f8acce9.tar`, SHA-256 `e6e27ec76619348cdaeb1a4e962a4bce294ef73cd0a9a1385aef8a07837a757f` (`deploy-staging.sh`, `restart-api.sh`, `lib/staging-runtime.sh`).
- Am Server:
  - `sha256sum -c` für das Paket und jede Datei: viermal OK.
  - Alte Hashes aus Bericht 33 (6.1): dreimal OK, keine der drei Units aktiv.
  - Ersetzt mit `install`.
  - Neue Hashes am Ziel: dreimal OK. Rechte `755`/`755`/`644 root:root`.
- Aufgeräumt: Wegwerf-Ordner und Paket gelöscht. Der offene Punkt aus Bericht 33 ist geklärt: Von Runde 2 sind weder `~/identity-service-*.tar` noch `/tmp/tmp.*` übrig.
- Gegenprobe der Restart-Unit von Hand: `ExecMainStatus=3`, „gefunden 0“. Die neue Container-Suche läuft unter der echten Unit.

### 1.5 PR #177: erste ausgerollte Freigabe (E-5-201)

`deploy/staging.json` stand auf den Digests von `768bbb4`. Neu (Digests aus
den Zeilen „Veröffentlicht“ und „Prüf-Gate bestanden“ der Läufe):

| Image | Lauf | Commit | Digest |
|---|---|---|---|
| API | Publish `45600588175` | `f8acce9` | `sha256:fd9917565e138b1bab11cab1f7e78fd0d732342c2110e86ce199918baedc32bb` |
| nginx | Publish nginx `45600588293` | `f8acce9` | `sha256:8f0da424e0cc824374edc66950e4f17096e0be6a9e43979c0192a925f913d2d4` |
| lego | Publish lego `45437830528` | `a566d93` | `sha256:beaf918a51cdc374c50234d60e95adc48fd7dba51175893c15b637b383a9512b` |

`verify-release-file.sh` und `test-release-file.sh` liefen lokal nicht, weil
`jq` fehlt. In der CI waren sie grün („Freigabe gueltig“ mit genau diesen drei
Digests). Release Staging `45697326213` signierte das Bundle
`sha256:d2bf2b8bbef4ed8d32ed8dd1b950d4449db9ab15a425be5e288336eb9604b9e3`.

### 1.6 Erster Deploy auf Staging

1. Erst-Schalter `/etc/identity-service/deploy-first` angelegt (`644 root:root`, 0 Bytes). Der Deploy-Timer war weiter `disabled`.
2. **Versuch 1 (20:48 UTC): Exit 13.**
   - Prüf-Gate, Gegenproben und Pull grün.
   - `compose run` legte die Volumes `identity-service-staging_{acme-webroot,tls-certificates,lego-accounts}` und das Netz `…_public` an.
   - lego registrierte ein Konto, dann folgte bei Let's Encrypt „Timeout during connect (likely firewall problem)“.
   - Nichts gestartet. Healthchecks bekam `/fail`.
3. Ursache: Port 80 war in beiden Firewall-Schichten zu (1.7).
4. **Versuch 2 (21:10 UTC): Exit 0.**
   - „The server validated our request“, das Zertifikat kam nach etwa 8 s.
   - `compose up` mit `api-1` und `nginx-1`.
   - **Health grün beim ersten Versuch**, mit TLS gegen den Trust Store des Systems.
   - Ausgerollt: Run `45697326213`, Commit `e98d287d920b83d7bfbf78fb297ac1319738326d`, Bundle `sha256:d2bf2b8b…b9e3`.
5. **E-5-187 gemessen:** Mit `StateDirectoryMode=0700` liest nginx seine Konfiguration. Die Ersatzlösung 0711 ist nicht nötig.
6. Erst-Schalter gelöscht. StateDirectory `700 deploy:deploy`, `current -> releases/e98d287…`, `state` 0644 mit Run, Commit und Bundle.
7. **`noop`-Lauf von Hand:**
   - Exit 0, Entscheidung `noop`, „Health gruen (Versuch 1)“, „Nichts zu tun; Stand gesund“.
   - Kein lego, kein `compose up`, 2,7 s CPU.
   - Healthchecks `staging-deploy`: down → up um 22:10 (Ortszeit), OK-Pings um 22:10 und 22:13.

### 1.7 Ports 80 und 443 geöffnet (E-5-202, E-5-203)

**Befund:** In Bericht 32 stand „Ports 80/443 freigegeben (gemessen)“.
Gemessen war aber nur `net.ipv4.ip_unprivileged_port_start = 80`. Beide
Firewall-Schichten ließen weiter nur TCP 22 herein (Stand Bericht 18, 6.1/6.2).

**Provider-Firewall (Policy `staging-ingress`)**, Endstand nach dem Speichern:

| # | Beschreibung | Protokoll | Aktion | Dst Port |
|---|---|---|---|---|
| 1 | SSH, nur Schlüssel | TCP | ACCEPT | 22 |
| 2 | icmp | ICMP | ACCEPT | beliebig |
| 3 | icmpv6 | ICMPv6 | ACCEPT | beliebig |
| 4 | ntp-antworten | UDP (Src Port 123) | ACCEPT | beliebig |
| 5 | **http-01** | TCP | ACCEPT | **80** |
| 6 | **https** | TCP | ACCEPT | **443** |
| 7 | tcp-drop | TCP | DROP | beliebig |
| 8 | udp-drop | UDP | DROP | beliebig |

Beide neuen Regeln landeten zuerst **hinter** `tcp-drop` und mussten nach
oben gezogen werden. Die Beschreibung der Policy lautet noch „Staging: nur
SSH, ICMP, NTP rein; Rest drop (ADR-011)“.

**Host `/etc/nftables.conf`**, neu hinter `tcp dport 22 ct state new accept`:

```
# HTTP-01 fuer alle, nur IPv4 (E-5-74, E-5-73)
meta nfproto ipv4 tcp dport 80 ct state new accept
# HTTPS fuer alle, nur IPv4, erst mit fertigem nginx (E-5-74, E-5-73)
meta nfproto ipv4 tcp dport 443 ct state new accept
```

Vorgehen je Port (E-5-44, E-5-45, präzisiert durch E-5-203):
1. Ausgangs-Hash prüfen.
2. Kopie per `awk` erzeugen, `diff` zeigt genau 2 Zeilen, `nft -c`.
3. Rücksprung `systemd-run --on-active=10min --unit=nft-rollback /usr/sbin/nft -f /etc/nftables.conf`, der die **alte Datei** lädt.
4. `nft -f` mit der neuen Datei.
5. Zweite SSH-Anmeldung als Test, dann Zeitgeber stoppen (`0 timers listed`).
6. `install` mit dem bisherigen Modus, `.new` löschen, `nft -c`, Hash.

Hash-Verlauf: `50b536ca…3732` → `85268a9f…58a3` (Port 80) →
`b1ff03cb0d2691396fdb2b355af3d463b9f12d707a1fec1b2eeb332f6f7d60f8` (Port 443).
Rechte `644 root:root`. Live-Kette: handle 11 (80), handle 12 (443), handle 13
`counter drop`.

Port 443 wurde erst nach dem erfolgreichen Deploy geöffnet (E-5-74).

### 1.8 Prüfung von außen und Gegenprobe 9

Vom Rechner der Ownerin (`curl.exe`, Schannel):

| Probe | Ergebnis |
|---|---|
| `https://<staging>/health` | `200 OK`, Zertifikat von Windows akzeptiert, `Strict-Transport-Security: max-age=86400`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`, `Cache-Control: no-store, no-cache` |
| `http://<staging>/health` | `308 Permanent Redirect`, `Location: https://<staging>/health` (E-5-83) |
| **Gegenprobe 9**: `https://<staging>:8443/` | `curl: (28) Connection timed out after 10010 ms`, Exit 28 |
| Kontrolle 443, gleiche Optionen | Exit 0 |

Gegenprobe 9 belegt, dass **mindestens eine** Schicht verwirft. Dass beide
einzeln wirken, ist seit den Sitzungen 18 und 22 belegt, und an den
Drop-Regeln hat sich nichts geändert.

### 1.9 CAA verschärft (E-5-200)

- Konto-URI aus dem Volume `lego-accounts`, Feld `accountURL` in
  `acme-v02.api.letsencrypt.org/noemail@example.com/account.json`:
  `https://acme-v02.api.letsencrypt.org/acme/acct/4044174281`.
- Genau eine Kontodatei, Produktion, kein Konto bei LE-Staging.
- Kein Feld `contact`: lego hat keine E-Mail gesendet (E-5-66).
- Neue Einträge an der **Subdomain** von Staging, TTL 3600. Die Wurzel ist unverändert (`0 issue "letsencrypt.org"`, `0 issuewild ";"`):
  ```
  0 issue "letsencrypt.org;accounturi=https://acme-v02.api.letsencrypt.org/acme/acct/4044174281;validationmethods=http-01"
  0 issuewild ";"
  ```
- Beleg direkt beim zuständigen Nameserver (`dig +tcp +norec … @netcup.firstns.cc`): Zone-Serial 9 → 10, beide Einträge vorhanden, Wurzel unverändert.
- Über Cloudflare-DoH lag die Antwort zunächst noch nicht vor (`"AD":true`, nur SOA). Grund: Bereitstellung bei netcup, dazu darf ein Resolver eine negative Antwort 24 h merken (SOA-Minimum 86400).

### 1.10 PR #178: Bausteine für Freigabe und Ping in die Bibliothek

- Aus `deploy-staging.sh` nach `lib/staging-runtime.sh`, Verhalten unverändert:
  - `staging_valid_ref`
  - `staging_read_current` (setzt `STAGING_CURRENT_COMMIT`)
  - `staging_release_ref` (E-5-182)
  - `staging_read_ping_url` (setzt `STAGING_PING_URL`)
  - `staging_ping`
- Einzige Verhaltensänderung: Scheitert `cat` auf die Ping-URL, warnt die Bibliothek nur noch, statt den Aufrufer per `set -e` abzubrechen.
- Mutationen deckten **zwei alte Testlücken** auf: doppelter Schlüssel in `staging.json`, absoluter `current`-Link. Neue Fälle, dazu „Release-Ordner fehlt“. Mutationen 6/6.
- Deploy-Tests: 175 Fälle, in der CI 175, 0 übersprungen.

### 1.11 PR #179: tägliche Erneuerung des nginx-Zertifikats (E-5-205 bis E-5-208)

- `scripts/renew-edge-certificate.sh STATE_DIR [--force]`, Ablauf und Exit-Codes in 6.2.
- `scripts/systemd/identity-service-edge-cert.service` (`User=deploy`, `LoadCredential=ping-url:/etc/credstore/identity-service-edge-cert.ping-url`, `TimeoutStartSec=58min`, Sandbox wie Deploy, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`).
- `scripts/systemd/identity-service-edge-cert.timer` (`OnCalendar=daily`, `RandomizedDelaySec=1h`, `Persistent=true`).
- `staging_remove_lego_oneoffs` in der Bibliothek; der Erst-Deploy nutzt sie.
- `ci.yml`: Schritt „Erneuerung nginx-Zertifikat prüfen (Ersatz)“ im Pflicht-Job `Container & nginx`. Der Branch wurde von der Ownerin per `!` gepusht, weil das Agenten-Token kein Workflow-Recht hat.
- Kommentare in Deploy- und Restart-Unit: `StateDirectoryMode` jetzt in drei Units gleich, Messung 0700 eingetragen.
- Tests: 62 ok-Zeilen, in der CI 62, Mutationen 10/10 und 5/5.
- Code-Review:
  - Fehler „Zeitbudget über `TimeoutStartSec`“ behoben (2700 s).
  - Fehler „HUP belegt kein Neuladen“ behoben (Exit 11).
  - Fehler „Rest nach eigenem Abbruch blockiert täglich“ behoben (Aufräumen vor dem Lauf).
  - Hinweis „`lego run` bestellt täglich“: **kein Fehler**, im Quellcode belegt.
- Nach dem Merge alle Läufe grün: CI `45716881438`, CodeQL `45716881397`, Publish `45716881536`, Publish nginx `45716881574`, **Release Staging `45716881506`**, also eine neue Freigabe mit denselben Image-Digests.

### 1.12 Lehrstoff

- [Lehrstoff: Erstes Zertifikat und Erneuerung](https://claude.ai/artifact/YQoaCGr6xmPegbvk5obEcq)
  (Henne-Ei, eine Prüfkette, blinder Probelauf, „gemessen“, Firewall-Gegenprobe,
  CAA, Erneuerung mit Erfolgsmessung, Umbau vor Erweiterung, Fallen,
  Spickzettel)

---

## 2. Gelernt

- Ein Messwert belegt nur, was gemessen wurde: `ip_unprivileged_port_start = 80` heißt „darf binden“, nicht „ist erreichbar“.
- Eine Firewall, die verwirft, erzeugt beim Client einen Timeout (curl Exit 28). Ohne Firewall lehnt der Host sofort ab (Exit 7). Eine Kontrolle auf einem offenen Port gehört immer dazu.
- In der Provider-Firewall landen neue Regeln am Ende, hinter `tcp-drop`. Ein Screenshot mit offenem Dialog belegt kein Speichern.
- Ohne Host-IP veröffentlicht Docker einen Port auch auf `[::]`.
- Ein Container mit `cap_drop: ALL` und UID ≠ 0 darf im Container keinen Port unter 1024 belegen. Lösung: intern hoher Port, extern 80.
- `lego run` ist idempotent. Ein zweiter Probelauf ohne `--renew-force` validiert nichts.
- Ein Zertifikat aus der Staging-Umgebung von Let's Encrypt besteht keine Health, die gegen den Trust Store des Systems prüft.
- Ein fehlgeschlagener Versuch kostet bei Let's Encrypt höchstens eine Stunde. Doppelte Zertifikate sind auf 5 pro Woche begrenzt.
- CAA wird vom genauen Namen nach oben gesucht. Der erste Name mit Einträgen gilt vollständig.
- Das DNS-Panel von netcup nimmt CAA-Parameter nur ohne Leerzeichen nach `;` an.
- Öffentliche Resolver dürfen „kein Eintrag“ so lange merken, wie das SOA-Minimum erlaubt (hier 24 h). Geprüft wird beim zuständigen Nameserver.
- Vom Server aus erreichen DNS-Anfragen an fremde Nameserver über UDP nichts, über TCP schon. Vermutet: Die Provider-Firewall merkt sich bei UDP keine Verbindungen.
- `Resolve-DnsName` kennt den Typ CAA nicht, SOA schon.
- `docker kill -s HUP` belegt nur die Zustellung. Ob nginx das neue Zertifikat lädt, zeigt erst das ausgelieferte Zertifikat.
- Teilen sich Skripte Code, zuerst ein reiner Umbau als eigener PR, belegt durch unveränderte Tests, dann die Erweiterung.
- Mutationen finden alte Testlücken, auch in Code, der nur verschoben wurde.
- `grep -P` scheitert in Git Bash an der Locale; ein `|| echo OK` dahinter meldet dann fälschlich Erfolg.
- Git Bash schreibt `/dev/null` in Argumenten an Windows-Programme in einen Windows-Pfad um. Eine Mutation per Python wurde dadurch nicht angewandt.
- Bricht ein Python-Skript mit Assertion ab, wurde nichts geschrieben. Ein Testlauf danach prüft den alten Stand.
- In Testskripten mit `set -euo pipefail` braucht `grep … | …` in `$(…)` ein `|| true`, sonst bricht der Test ab, statt zu melden.
- `Read-Host` übernimmt führende Leerzeichen: `(Read-Host '…').Trim()` und eine Kontrollausgabe in Klammern.
- Zu Sitzungsbeginn `main` holen, statt den Stand eines Berichts für den aktuellen zu halten.

---

## 3. Entscheidungen (ADR-Kandidaten)

Vor dem Eintragen mit `/entscheidungen-suchen` abgeglichen (E-5-44, E-5-45,
E-5-65, E-5-66, E-5-73 bis E-5-76, E-5-82, E-5-83, E-5-88, E-5-104, E-5-176,
E-5-182, E-5-185, E-5-187, E-5-189, E-5-190, E-5-196, ADR-014).

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-197** | Das erste nginx-Zertifikat holt der **Erst-Deploy**: lego **standalone** nach dem Pull per Digest und vor `compose up`, nur bei `decision=first`. Kein eigenes Skript, keine zweite Unit mit Token. Entscheidet die offene Empfehlung aus Bericht 24 | Eine Prüfkette, ein Token. Bis zum Ende des lego-Schritts ist nichts gestartet |
| **E-5-198** | **Kein Probelauf** gegen die Staging-Umgebung von Let's Encrypt, direkt Produktion. Ersetzt den Plan aus den Berichten 21 und 22 | `lego run` ist idempotent, ein zweiter Probelauf wäre blind. Ein Staging-Zertifikat bestünde die Health nicht. Ein Fehlschlag kostet höchstens 1 h |
| **E-5-199** | Erst-Modus nur auf **leerem Projekt** (Exit 2, nichts wird entfernt). lego mit `--publish 0.0.0.0:80:8080`, `--http.address :8080`, `--accept-tos` (von der Ownerin nach Lektüre der Bedingungen freigegeben), ohne `--email`, Schlüssel EC256, `--cert.name edge`. Einmal-Container nur per Label entfernen, danach erneut leer. **Exit 13** (erweitert E-5-185) | Melden statt reparieren. IPv4 nur (E-5-73). Kein Container hält danach Port 80 |
| **E-5-200** | **CAA an der Subdomain** von Staging: `issue "letsencrypt.org;accounturi=<Konto>;validationmethods=http-01"` und `issuewild ";"`. Wurzel unverändert. Das Volume `lego-accounts` wird nie gelöscht (`compose down -v` verboten) | Nur unser Konto, nur HTTP-01. Production bleibt frei für ein eigenes Konto. Verlust des Kontos ist fail closed |
| **E-5-201** | Erste ausgerollte Freigabe mit den **aktuellen** Digests (API und nginx von `f8acce9`, lego vom letzten Publish-Lauf), nicht mit `768bbb4` | Der erste öffentliche Stand ist der neueste. Der Merge ist das erste DORA-Ereignis |
| **E-5-202** | Ports 80 und 443 in **beiden** Schichten: Provider-Regeln `http-01`/`https` **vor** `tcp-drop`; Host `meta nfproto ipv4 tcp dport {80,443} ct state new accept`. 443 erst nach erfolgreichem Deploy. Wendet E-5-74 an, präzisiert durch E-5-73 | Let's Encrypt prüft von mehreren Standorten. Nur IPv4 auf Staging. Zero Trust statt IP-Allowlist |
| **E-5-203** | Firewall-Änderung: Der Rücksprung-Zeitgeber lädt die **alte Datei** (`nft -f /etc/nftables.conf`) statt die Tabelle zu löschen. Neue Datei zuerst nur live laden, nach dem SSH-Test per `install` (Modus übernommen) ersetzen, `.new` löschen. Präzisiert E-5-45 | Rücksprung fail closed. Ein Neustart vor dem Ersetzen lädt den alten Stand. Eine Quelle |
| **E-5-204** | `lib/staging-runtime.sh` ist die einzige Quelle auch für Container-Suche, `current`, Referenzen aus `staging.json`, Ping-URL, Ping und das Aufräumen der lego-Einmal-Container. Neue Einstiege übernehmen sie, statt zu kopieren. Präzisiert E-5-196 | Deploy, Neustart und Erneuerung dürfen nicht verschieden urteilen |
| **E-5-205** | Erneuerung `renew-edge-certificate.sh` als Unit mit `User=deploy`: Sperre des Deploys **wartend** (2700 s = `TimeoutStartSec` des Deploys); Compose und Digests aus `current/`, **ohne Token und Pull**; `lego run --http --http.webroot /webroot`; `--force` (zu `--renew-force`) **nur von Hand**; nach jedem erfolgreichen Lauf `docker kill -s HUP` an genau einen nginx-Container; Health. Präzisiert E-5-76 | Kein Neuladen-Zweifel, kein Docker-Socket im Container, Zeitbudget unter 58 min |
| **E-5-206** | Erfolg der Erneuerung wird am **ausgelieferten** Zertifikat gemessen: `openssl s_client` mit SNI an `127.0.0.1:443`, `x509 -checkend 1209600` (14 Tage), sonst **Exit 11**. Neu bewerten, wenn Let's Encrypt die Laufzeit verkürzt | HUP belegt nur die Zustellung. Fängt auch eine wochenlang still scheiternde Erneuerung |
| **E-5-207** | Übrige lego-Einmal-Container **vor** dem Lauf unter der Sperre entfernen, danach leer, sonst Exit 9 | Nur Deploy und Erneuerung starten lego, beide unter der Sperre. Sonst stünde jeder Folgetag nach einem Abbruch auf Exit 9 |
| **E-5-208** | Unit `identity-service-edge-cert`: Sandbox wie der Deploy, Netz nur über Adressfamilien (E-5-176, kein IP-Filter, weil Healthchecks.io keine festen Adressen hat), `TimeoutStartSec=58min`; Timer täglich, `RandomizedDelaySec=1h`, `Persistent=true`; eigener Check `staging-edge-cert` (Periode 1 Tag, Grace 3 h, E-5-104); `StateDirectoryMode=0700` in allen drei Units | Least Privilege im Rahmen des Messbaren; Alarm bei Ausbleiben (ADR-013) |

Bestätigt oder angewendet, ohne neuen Code:
- E-5-74 (Port 443 erst mit fertigem nginx)
- E-5-104 (Rotation, wenn eine Ping-URL bekannt wurde, siehe Offene Punkte)
- E-5-187 (**gemessen**: 0700 reicht)
- E-5-190 (Timer bleibt aus)
- E-5-191 (Installation Runde 3)
- E-5-16 (Phase 5 erst nach Phase 4)

Ablage: E-5-197 bis E-5-208 gehören mit E-5-170 bis E-5-178 und E-5-181 bis
E-5-196 in den **Nachtrag zu ADR-017**. E-5-200 und E-5-202 gehören zusätzlich
ins **ADR zum Schritt DNS/TLS** (mit E-5-65 bis E-5-68, E-5-73 bis E-5-76,
E-5-79 bis E-5-98).

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **#179 nicht installiert.**
  - Am Server fehlen `renew-edge-certificate.sh`, Edge-Unit und Timer.
  - Der neue Stand von `deploy-staging.sh` und `lib/staging-runtime.sh` (aus #178/#179) ist ebenfalls nicht installiert.
  - Die geänderten Kommentare in Deploy- und Restart-Unit sind nicht übernommen.
  - Am Server laufen weiterhin die Stände von `f8acce9` (6.1).
- **Healthchecks-Check `staging-edge-cert`** muss die Ownerin anlegen, die URL kommt per `read -s` nach `/etc/credstore/identity-service-edge-cert.ping-url` (root 0600). Nicht ins Gespräch und nicht als Screenshot.
- **Webroot-Weg, HUP und `openssl s_client` unter der Sandbox nicht belegt.** Beleg ist ein Lauf von Hand mit `--force` nach der Installation (zählt als 1 von 5 doppelten Zertifikaten pro Woche).
- **Ping-URLs rotieren (E-5-104).** Ein Screenshot der Healthchecks-Liste zeigte die vollständigen URLs von `staging-host-2`, `staging-api-cert-2` und `staging-deploy`. Ablageorte:
  - `/etc/credstore/host-health-check.ping-url` (Bericht 20)
  - `/etc/credstore/identity-service-api-cert.ping-url`
  - `/etc/credstore/identity-service-deploy.ping-url`

  Vor künftigen Screenshots in der Liste auf „slug“ umschalten.
- **Healthchecks `staging-deploy`:** Benachrichtigungen pausiert (Glocke durchgestrichen), Status nach dem `noop`-Lauf „Grace“. Ohne Timer folgt „down“. Glocke beim Einschalten des Timers wieder an.
- **Deploy-Timer aus** (E-5-190). Voraussetzungen jetzt erfüllt bis auf Installation #179 und Rotation der Ping-URLs.
- **Neue Freigabe nach #179:** Release Staging `45716881506` (Commit `85f4473`, dieselben Digests). Der nächste Deploy-Lauf entscheidet `deploy` und macht `compose up` mit unveränderten Images. Erwartet: kein Neustart der Container. Beim ersten Lauf ablesen.
- **Beschreibung der Firewall-Policy** `staging-ingress` noch alt („nur SSH, ICMP, NTP rein“). Vorschlag: „Staging: SSH, ICMP, NTP, HTTP (80), HTTPS (443) rein; Rest drop (ADR-011, E-5-74)“.
- **Firewall-Konfiguration nicht im Repository:** `/etc/nftables.conf` (Hash `b1ff03cb…60f8`) und die Provider-Policy stehen nur in den Berichten 18 und 34.
- **DNS über UDP vom Server** zu fremden Nameservern geht nicht (gemessen mit `dig` ohne `+tcp`: Timeout). Ursache nicht belegt (Vermutung: Provider-Firewall ohne Zustand für UDP). Die eigene Namensauflösung des Servers funktioniert.
- **Erzwungener Renew** zählt zu den doppelten Zertifikaten: 1 (Erst-Zertifikat) von 5 in 7 Tagen verbraucht.
- **`gh`-Aufrufe ohne eigenes Timeout** in `scripts/lib/attestation-rules.sh` und `scripts/verify-release.sh` (aus Bericht 33).
- **Nachtrag ADR-017** (E-5-170 bis E-5-178, E-5-181 bis E-5-208) und **ADR zum Schritt DNS/TLS**: nicht geschrieben.
- `.claude/rules/skripte.md` und `lieferkette-und-ci.md`: neue Skripte nachtragen (`deploy-staging.sh`, `restart-api.sh`, `renew-edge-certificate.sh`, `lib/staging-runtime.sh`, alle `test-*.sh` aus den Sitzungen 32 bis 34). Liegt bei der Ownerin.
- **Lokale Branches löschen** (Freigabe nötig): `refactor/staging-container-lookup`, `feat/first-edge-certificate`, `chore/release-staging-f8acce9`, `refactor/staging-release-helpers`, `feat/edge-certificate-renewal`, `docs/sitzung-33` und die Listen aus den Berichten 30 bis 33.
- `jq` fehlt lokal: `verify-release-file.sh` und `test-release-file.sh` laufen nur in der CI.
- Lokale Deploy-Tests brauchen `MSYS=winsymlinks:nativestrict`, sonst werden sie übersprungen.

**Aus Bericht 33 und früher, weiter offen**

- Agenten-Token läuft am 23.12.2026 13:10 UTC ab; Erinnerung ab etwa 16.12.2026.
- GHCR-Token (Maschinenkonto) läuft am 23.01.2027 ab; Erinnerung ab etwa 09.01.2027.
- Lokale Zertifikate laufen am 31.01.2027 12:46 UTC ab.
- Erste Erneuerung des API-Zertifikats spätestens 27.12.2026. Der Stack läuft jetzt, der Neustart sollte also gelingen. Prüfen, ob die API danach das neue Zertifikat zeigt (aus Bericht 31). Ob Kestrel selbst neu lädt (E-5-97), ist offen.
- `ip_unprivileged_port_start = 80`; vor Production eine engere Lösung.
- Aufbewahrungsregel für GHCR fehlt.
- Sicherheitsfunktionen des Repositorys nach dem Sichtbarkeitswechsel nicht einzeln geprüft.
- ADR-015, ADR-016, ADR-017 auf „Akzeptiert“ (Ownerin).
- API-Image: Medium-Lücken in `libc6` (Stand Bericht 31); Bot-PRs vor dem Merge lesen.
- E-5-128 nicht umgesetzt; `dependabot.yml`: SDK-Hauptversionen ignorieren.
- „Manage Actions access“: Write statt Admin nicht belegt.
- Kestrel-Neuladen, nginx und alte TLS-Sitzungen nach Zertifikatswechsel nicht gemessen.
- Server: Wirkung von `unattended-upgrades` nur indirekt belegt, Journal-Frist, NTS, `nft-rollback.service`; `user: "1654:1654"` in `compose.staging.yaml`; Units von host-health-check nicht im Repository; Update-Weg von `gh`.
- Lokales `gh` 2.102.0 unter der Mindestversion 2.103.3.
- Erster automatischer Lauf des API-Zertifikats-Timers nicht im Journal abgelesen.
- Keine Prüfung der Unit-Dateien in der CI (`systemd-analyze verify` nur am Server).
- CA-Wechsel vor dem 28.10.2027.
- Lokal: SSH-Signaturen als `%G? = U` (kein `allowedSignersFile`).
- Option `curl`-Weg für Installationen (Änderung von E-5-56): nicht entschieden.

**Bekannte Grenzen**

- Die Sandbox begrenzt den Docker-Client, nicht den Daemon. Wer den Socket hat, hat die Rechte von `deploy`.
- Gegenprobe 9 von außen zeigt nicht, welche Schicht verwirft.
- Die Edge-Unit hat keinen IP-Filter (E-5-176, E-5-208).
- Domain, IPs, Hostnamen und Benutzernamen stehen bewusst nicht in diesem Bericht (ADR-004). Ausnahme: die öffentliche Konto-URI von Let's Encrypt, die ohnehin im DNS steht.

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). **Staging läuft und ist öffentlich erreichbar.**

| Nr. | Schritt | Stand |
|---|---|---|
| 1 | Staging-Konfiguration | erledigt |
| 2 | Interne CA | erledigt |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer | **erledigt bis auf Installation und Einschalten des lego-Timers** (#179 gemergt) |
| 4 | Maschinenkonto, Leserecht | erledigt (Pull beim ersten Deploy mit dem Token aus dem Credstore) |
| 5 | Pull-Deploy | **erster Deploy und `noop` erledigt**; Timer offen |
| 6 | Freigabe vor dem Deploy, DORA-Ereignisse | Freigabe gelebt (#177); DORA offen |
| 7 | DAST (OWASP ZAP) | fällig mit dem Einschalten des Deploy-Timers |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | keine neue Abhängigkeit; Drittanbieter-Scans jetzt Required Checks; Digests aus den Läufen, nicht aus dem Gedächtnis |
| **A02 / sichere Defaults** | Port 443 erst mit gehärtetem nginx; HSTS 1 Tag; nur IPv4 |
| **A05 / Fehlkonfiguration** | Befund „Ports freigegeben“ war falsch; jetzt in beiden Schichten gemessen |
| **A09 / Alerting** | Deploy pingt; Edge-Check vorbereitet; Ping-URLs müssen rotiert werden |
| **A10 / fail closed** | Exit 13 am Server belegt (nichts gestartet); Exit 11 gegen still gescheitertes Neuladen; CAA bei Kontoverlust |
| **Secrets (6.3.3)** | Ping-URLs durch Screenshot bekannt geworden: Rotation offen |
| **Resilienz-Patterns** | ausgelöst seit Sitzung 7; Timeouts je Schritt, Unit-Grenzen gestaffelt; `gh` noch ohne eigenes Timeout |
| **DAST** | Staging stabil erreichbar; fällig, sobald der Deploy automatisch läuft |
| **LLM-Gate 6.4, Agentic-Gate 6.5** | nicht ausgelöst |
| **mTLS, Contract Testing, Feature Flags, Mutation Testing (Stryker), k6** | nicht fällig |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (25.11.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| `main` | `85f4473` | `git log` |
| Ausgerollt auf Staging | Run `45697326213`, Commit `e98d287d920b83d7bfbf78fb297ac1319738326d`, Bundle `sha256:d2bf2b8bbef4ed8d32ed8dd1b950d4449db9ab15a425be5e288336eb9604b9e3` | `state` am Server |
| Neueste Freigabe (nicht ausgerollt) | Release Staging `45716881506`, Commit `85f4473`, Digests wie oben | Release-Lauf |
| `deploy/staging.json` | API `fd9917…c32bb`, nginx `8f0da4…3d2d4`, lego `beaf91…9512b` (volle Werte in 1.5) | Repository |
| Let's-Encrypt-Konto | `https://acme-v02.api.letsencrypt.org/acme/acct/4044174281` | `account.json` |
| Zertifikat `edge` | ausgestellt 25.11.2026 21:10 UTC, Produktion | Journal |
| `/etc/nftables.conf` | `b1ff03cb0d2691396fdb2b355af3d463b9f12d707a1fec1b2eeb332f6f7d60f8`, `644 root:root` | Server |
| Installationspaket Runde 3 | Commit `f8acce9`, SHA-256 `e6e27ec76619348cdaeb1a4e962a4bce294ef73cd0a9a1385aef8a07837a757f` | lokal |

**Installierte Dateien am Server (Stand nach Runde 3), für den nächsten
Ersatz.** Alle übrigen Dateien unverändert wie in Bericht 33, 6.1.

| Ziel | SHA-256 |
|---|---|
| `/usr/local/lib/identity-service/deploy-staging.sh` | `142f4259501e5298639633c3a74238988f921a82680edce67c544593f600c9ca` |
| `/usr/local/lib/identity-service/restart-api.sh` | `4eeddc557343a8007d09b586ec659684770db2bda11fd976bb2056220844843e` |
| `/usr/local/lib/identity-service/lib/staging-runtime.sh` | `f5f79e45347ba3b226e660d0681eabe9da61ef6c1b35c18a05204168e98aa525` |
| `/usr/local/lib/identity-service/lib/registry-only.sh` | `f2216d93d32433a5a75fe991988db45c3c9c21c32e3372e4e10f32693c78d93b` |
| `/etc/systemd/system/identity-service-deploy.service` | `679004811081272ae4e751e0659722f8ab07bd29c91d349c7a3a02543b737ff7` |
| `/etc/systemd/system/identity-service-api-restart.service` | `705d2976cdb8792ea6e6a5750f9081824c245dc5f69ccb88d013dc88931fe69d` |

**Sollstand für Runde 4 (Commit `85f4473`):**

| Datei im Repository | Ziel | SHA-256 |
|---|---|---|
| `scripts/deploy-staging.sh` | `/usr/local/lib/identity-service/` (0755) | `76c585462cf73c072d5e2ee5a4f5802f7f71d1ab6d71bf9b26ce55bfa5b97acb` |
| `scripts/lib/staging-runtime.sh` | `…/lib/` (0644) | `f6303c476d9b92b8e9ee094da96718ac05fe354e67cb368268913602670293db` |
| `scripts/renew-edge-certificate.sh` | `/usr/local/lib/identity-service/` (0755), **neu** | `e50094fa29b3f95ba97e4820607ef85a0ed65763ecf20ddd3c9c76a9d648b27d` |
| `scripts/lib/registry-only.sh` | unverändert, bereits installiert | `f2216d93d32433a5a75fe991988db45c3c9c21c32e3372e4e10f32693c78d93b` |
| `scripts/restart-api.sh` | unverändert, bereits installiert | `4eeddc557343a8007d09b586ec659684770db2bda11fd976bb2056220844843e` |
| `scripts/systemd/identity-service-deploy.service` | `/etc/systemd/system/` (0644), nur Kommentar | `e6700bc6f93161c29a2d55235dbb161062a9535d8fbc5c225c767e644bf7f0f8` |
| `scripts/systemd/identity-service-api-restart.service` | `/etc/systemd/system/` (0644), nur Kommentar | `b9a2b74af88127db7989570cc92d1c6cdf0b578d4d43b8904509677f36dd0d19` |
| `scripts/systemd/identity-service-edge-cert.service` | `/etc/systemd/system/` (0644), **neu** | `4eb71b138e28633c95cf227c2d98650b6c0044d0dc781af871b5736c562bc6ef` |
| `scripts/systemd/identity-service-edge-cert.timer` | `/etc/systemd/system/` (0644), **neu** | `e46675e7532256ed4e2d2e79d6affea6dd352e11096fff4e6bbe57cf74c32b3a` |

### 6.2 Skripte und Exit-Codes (neu oder geändert)

| Skript | Codes |
|---|---|
| `deploy-staging.sh` | wie Bericht 33, dazu **13**: first, Erst-Zertifikat nicht erhalten oder Einmal-Container nicht entfernt (nichts gestartet); **2** auch: first bei nicht leerem Projekt oder `docker ps` gescheitert |
| `renew-edge-certificate.sh STATE_DIR [--force]` | 0 geprüft, bei Bedarf erneuert, neu geladen, gesund, ausgeliefertes Zertifikat ≥ 14 Tage · 2 Voraussetzung · 3 `current`/Freigabe · 4 nicht genau ein nginx-Container · 5 lego gescheitert · 6 Sperre nicht rechtzeitig · 7 `docker ps` · 8 HUP gescheitert · 9 Einmal-Container nicht entfernbar · 10 Health rot · 11 ausgeliefertes Zertifikat < 14 Tage oder unlesbar |

Ablauf der Erneuerung:
1. Ping-URL, Parameter, Umgebung, Servername, rootless.
2. Sperre wartend 2700 s.
3. `current` und Freigabe lesen.
4. Genau ein nginx-Container; Reste von lego entfernen.
5. `lego run --path /data --accept-tos --http --http.webroot /webroot --cert.name edge --domains <server_name> [--renew-force]` mit `timeout --kill-after=10 300`, `--pull never`.
6. Reste entfernen.
7. `docker kill -s HUP <nginx>`.
8. Health.
9. `openssl s_client -connect 127.0.0.1:443 -servername <server_name> | openssl x509 -noout -checkend 1209600`.
10. Ping bei jedem Ausgang.

Bibliothek `lib/staging-runtime.sh`:
- `staging_require_rootless`
- `staging_read_server_name`
- `staging_health`
- `staging_container_ids`
- `staging_remove_lego_oneoffs`
- `staging_valid_ref`
- `staging_read_current`
- `staging_release_ref`
- `staging_read_ping_url`
- `staging_ping`

### 6.3 Volumes und Pfade

| Volume | lego | nginx |
|---|---|---|
| `identity-service-staging_lego-accounts` | `/data/accounts` (rw) | – |
| `identity-service-staging_tls-certificates` | `/data/certificates` (rw) | `/etc/nginx/acme` (ro) |
| `identity-service-staging_acme-webroot` | `/webroot` (rw) | `/var/www/acme` (ro) |

Auf dem Host liegen die Volumes unter
`/home/deploy/.local/share/docker/volumes/<name>/_data`. Lesen nur als root.
Den Ordner ermittelt `sudo -u deploy -H DOCKER_HOST=unix:///run/user/1001/docker.sock docker volume inspect -f '{{.Mountpoint}}' <name>`.

### 6.4 Läufe als Belege

| Zweck | Lauf |
|---|---|
| CI #175 (Deploy 122 Fälle) | `45592404357` |
| CI #176 (Deploy 169 Fälle) | `45599969304` |
| Nach #176 | Publish `45600588175`, Publish nginx `45600588293`, Release `45600588451` |
| CI #177 (Freigabe gültig) | `45696756019` |
| Release nach #177 (ausgerollt) | `45697326213` |
| CI #178 (Deploy 175 Fälle) | `45712879068` |
| CI #179 (Renew 62, Deploy 175) | `45716521656` |
| Nach #179 | CI `45716881438`, CodeQL `45716881397`, Publish `45716881536`, Publish nginx `45716881574`, Release `45716881506` |

### 6.5 Fallstricke, die Zeit gekostet haben

- Neue Regeln in der Provider-Firewall stehen am Ende, hinter `tcp-drop` (zweimal). Nach oben ziehen, speichern, von außen messen.
- `cat -A` zeigte: `/etc/nftables.conf` ist mit **16 Leerzeichen** eingerückt, nicht mit Tabs. `awk`-Vergleich auf die exakte Zeile.
- `Read-Host` mit führendem Leerzeichen ergab „URL rejected: Malformed input“. `.Trim()` hilft.
- Befehl für den Server versehentlich in PowerShell ausgeführt („Exit True“). Bei jedem Befehl sagen, wo er läuft.
- `dig` ohne `+tcp` vom Server: Timeout an allen Nameservern.
- Cloudflare-DoH zeigte die neuen CAA-Einträge zunächst nicht (Bereitstellung, negatives Caching 24 h). Direkt beim zuständigen Nameserver prüfen.
- CAA-Wert mit Leerzeichen nach `;` lehnte das DNS-Panel ab.
- Python-Heredocs mit Backslashes brachen bei Ersetzungen ab (Assertion, nichts geschrieben). Einzel-Edits verwenden.
- Git Bash wandelt `/dev/null` in Argumenten an Windows-Programme um.
- `grep -P` in Git Bash: „supports only unibyte and UTF-8 locales“. Mit `|| echo OK` dahinter falscher Erfolg. ASCII-Prüfung mit `LC_ALL=C tr -d '\000-\177' | wc -c` und einer Gegenprobe mit Umlaut.
- `tar -tvf C:/…` in Git Bash: „Cannot connect to C:“. `cd` in den Ordner oder `--force-local`.

### 6.6 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Erst-Schalter | `first` erlauben | `sudo install -o root -g root -m 0644 /dev/null /etc/identity-service/deploy-first` | `644 root:root 0` |
| Erster Deploy | Zertifikat und Stack | `sudo systemctl start identity-service-deploy.service`; `journalctl -u … -n 60 -o cat` | Exit 13, dann Exit 0 |
| Firewall Host | E-5-202, E-5-203 | `awk` → `.new`, `nft -c`, `systemd-run … nft -f /etc/nftables.conf`, `nft -f .new`, zweite SSH, `systemctl stop nft-rollback.timer`, `install -m "$(stat -c %a …)"` | handle 11/12, Hash `b1ff03cb…` |
| Von außen | Client-Sicht | `curl.exe -sS -o NUL -D - "https://$d/health"` | 200, Header |
| Gegenprobe 9 | Verwerfen belegen | `curl.exe -sS -m 10 -o NUL "https://${d}:8443/"; "Exit $LASTEXITCODE"` | Exit 28, Kontrolle 0 |
| Konto-URI | CAA | `grep -oE 'https://acme-v02\.api\.letsencrypt\.org/acme/acct/[0-9]+' account.json` | eine URI |
| CAA prüfen | ohne Zwischenspeicher | `dig +tcp +norec +short CAA <name> @netcup.firstns.cc` | zwei Einträge, Serial 10 |

---

# Roadmap Sitzung 35

## 1. #179 am Server installieren und belegen (Runde 4, E-5-191)

Warum zuerst: Die Erneuerung ist gemergt, aber nicht in Betrieb, und die
nächsten Punkte (Timer, Rotation) setzen den neuen Stand voraus. Bausteine,
jeweils einzeln:

1. Bei Healthchecks.io den Check `staging-edge-cert` anlegen (Periode 1 Tag, Grace 3 h), Ansicht vorher auf „slug“.
2. Die URL per `read -rsp` nach `/etc/credstore/identity-service-edge-cert.ping-url` schreiben (root 0600, ohne Zeilenende).
3. Paket per `git archive` aus `85f4473`: `deploy-staging.sh`, `lib/staging-runtime.sh`, `renew-edge-certificate.sh` und vier Unit-Dateien. Dann `scp` und `sha256sum -c`.
4. Alte Hashes nach 6.1 prüfen, neue Ziele dürfen nicht existieren, ersetzen, Hashes am Ziel prüfen, `systemd-analyze verify`, `daemon-reload`.
5. Den Lauf von Hand **mit `--force`** starten. Belegt Webroot-Weg, HUP und `openssl` unter der Sandbox. **Die Form ist vorher als Konzept zu klären**, denn die Unit übergibt `--force` bewusst nie. Kandidaten mit Trade-offs:
   - `systemd-run --wait` mit denselben Eigenschaften wie die Unit (Sandbox und Credential gleich, aber eine zweite Quelle für die Eigenschaften)
   - ein befristeter Drop-in mit geändertem `ExecStart` (exakt die Unit, aber eine Änderung an `/etc/systemd/system`, die danach wieder weg muss)
   - ein Aufruf als `deploy` ohne Unit (einfach, aber ohne Sandbox und ohne Ping, belegt also weniger)
6. Einen Lauf ohne `--force` über die Unit starten: erwartet „Skip renewal“, Reload, Exit 0.
7. Den Timer `identity-service-edge-cert.timer` einschalten.

## 2. Ping-URLs rotieren (E-5-104)

Warum vor dem Timer: Ein dauerhaft laufender Deploy-Timer meldet sonst an eine
URL, die bekannt geworden ist. Wer sie kennt, kann Alarme unterdrücken. Drei
Checks, je: in Healthchecks „Ping URL ändern“, am Server per `read -rsp` in die
jeweilige Datei (Ablageorte unter 4), dann einen Lauf von Hand und den Ping
ablesen.

## 3. Deploy-Timer einschalten (E-5-190)

Warum: macht Staging zum automatischen Pull-Deploy. Glocke bei
`staging-deploy` wieder an, `systemctl enable --now identity-service-deploy.timer`.
Der erste automatische Lauf rollt die Freigabe von `85f4473` aus (dieselben
Images, Entscheidung `deploy`). Danach mindestens einen `noop`-Lauf im Journal
ablesen.

## 4. Timeouts für `gh` in den Prüfskripten

Warum: einzige Netzaufrufe ohne eigenes Timeout (Bericht 33). Mit laufendem
Timer schlägt ein hängendes `gh` alle 5 Minuten bis zu 45 Minuten lang durch.
Eigener PR, löst einen Release-Lauf aus.

## 5. DORA-Ereignisse (Schritt 6) und DAST (Schritt 7)

Warum: letzte Teile von Phase 4. DAST wird mit dem Timer fällig. Staging ist
jetzt von außen erreichbar.

## 6. ADRs

Nachtrag ADR-017 (E-5-170 bis E-5-178, E-5-181 bis E-5-208) und ADR zum
Schritt DNS/TLS. Warum: Diese Entscheidungen stehen nur in den Berichten 21
bis 34.

## 7. Kurze Punkte der Ownerin

- Beschreibung der Firewall-Policy aktualisieren
- ADR-015 bis ADR-017 auf „Akzeptiert“
- `.claude/rules/*.md` nachziehen
- gemergte lokale Branches löschen (Freigabe)

## 8. Danach: Phase 5

Erst wenn Phase 4 abgeschlossen ist (E-5-16). Erster Use Case
**Benutzerregistrierung**, davor STRIDE nach CLAUDE.md Abschnitt 9,
test-first, Testcontainers. Weitere Vorgaben siehe Bericht 33, Roadmap 7.

## 9. Zurückgestellt, nicht aufgehoben

- E-5-128, E-5-129; `dependabot.yml` SDK-Hauptversionen
- Aufbewahrungsregel für GHCR
- Firewall-Konfiguration ins Repository (Vorlage, Prüfung)
- DNS über UDP vom Server klären
- `curl`-Weg für Installationen (Änderung von E-5-56, nur auf Wunsch)
- Unit-Dateien in der CI prüfen
- Vor Production: NTS, IPv6, zweiter Warnkanal, HSTS 1 Jahr, engere Port-Freigabe, CA-Wechsel vor dem 28.10.2027

## 10. Vor oder in der Sitzung zu verstehen (vor Code)

- **Webroot statt Standalone:** Ab jetzt beantwortet nginx die Prüfung von Let's Encrypt aus dem Volume `acme-webroot`. lego schreibt dort nur die Datei und braucht keinen Port. Deshalb läuft die Erneuerung ohne Unterbrechung.
- **ARI:** Let's Encrypt teilt jedem Zertifikat ein Zeitfenster für die Erneuerung mit. lego fragt es täglich ab und erneuert nur darin. Solche Erneuerungen zählen nicht gegen die Rate Limits.
- **Erfolg beim Empfänger messen:** Die Erneuerung gilt erst als gelungen, wenn das Zertifikat, das ein Client bekommt, noch mindestens 14 Tage gilt. HUP allein beweist nichts.
- **Rotation einer Ping-URL:** Die alte URL wird bei Healthchecks ungültig. Wer sie kennt, kann keinen OK-Ping mehr fälschen. Am Server ändert sich nur die Datei im Credstore, die Unit bleibt gleich.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Erstes Zertifikat und Erneuerung](https://claude.ai/artifact/YQoaCGr6xmPegbvk5obEcq)

## 11. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- Check `staging-edge-cert` bei Healthchecks.io anlegen (Ansicht „slug“), URL nicht kopieren, bis wir am Server sind
- Beschreibung der Firewall-Policy anpassen
- Erinnerungen: Agenten-Token vor dem 23.12.2026, API-Zertifikat spätestens 27.12.2026, GHCR-Token vor dem 23.01.2027, lokale Zertifikate vor dem 31.01.2027
