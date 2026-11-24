# Sitzungsbericht Sitzung 33

**Datum:** 24.11.2026
**Phase:** Schritt 5 (CD): 4d-3a, 4d-3b und 4d-3c gemergt, am Server
installiert und mit Gegenproben belegt; Deploy-Timer bewusst aus. Neue
Arbeitsregel „erst suchen, dann vorschlagen“ (Skills, CLAUDE.md). Offen in
Phase 4: erstes lego-Zertifikat, erster Deploy, Timer, DORA, DAST
**Vorgänger:** sitzung-32.md (abgeschlossen 24.11.2026)

---

## 1. Erledigt

| PR | Titel | Merge |
|---|---|---|
| #169 | `docs: add session report 32` | `5b315f8` |
| #170 | `feat(deploy): add staging deploy script with rollback` | `bb902ec` |
| #171 | `chore(claude): add decision search and pre-PR review skills` | `05ea045` |
| #172 | `feat(deploy): add systemd unit and timer for staging deploy` | `2e7ca08` |
| #173 | `feat(deploy): add API restart unit for certificate renewal` | `a7314d6` |

Alle von der Projekt-Ownerin per Squash gemergt, überwiegend KI-erzeugt, kein
Auto-Merge. Signatur der Merge-Commits `bb902ec`, `05ea045`, `2e7ca08`,
`a7314d6` über die GitHub-API geprüft: `verified=true`, `valid`.

### 1.1 PR 4d-3a: `scripts/deploy-staging.sh` (#170)

- Aufruf `deploy-staging.sh STATE_DIR SWITCH_FILE INSTALL_NGINX_DOCKERFILE`;
  `releases/`, `current` und `state` liegen unter `STATE_DIR` (E-5-181).
- Ablauf: Ping-URL lesen → Parameter, Umgebung, `server_name` → `flock` auf
  `STATE_DIR/.deploy.lock` → `current` prüfen, `NGINX_DOCKERFILE` nach E-5-177
  → Rootless-Prüfung → Token (Form `ghp_` + 36, CR entfernt) → `docker login
  --password-stdin` in `DOCKER_CONFIG` unter `RUNTIME_DIRECTORY` → vier Pakete
  anonym nicht lesbar → `fetch-release.sh` (neun Ergebniszeilen streng
  geprüft) → bei `noop` nur Health → Prüf-Gate der drei Images → Pull per
  Digest mit Abgleich der `RepoDigests` → Rückweg vorbereiten → **`compose up
  --no-build --pull never --remove-orphans`** (Punkt ohne Wiederkehr) → Health
  über nginx → erst `current`, dann Zustand per `mv -T` → Ping per `trap EXIT`.
- Rückweg (E-5-175, E-5-182) bei rotem `compose up` oder roter Health.
- Exit-Codes siehe 6.2.
- `scripts/test-deploy-staging.sh` im Pflicht-Job `Container & nginx`; nach
  jedem Fall: Token in keiner Ausgabe und keinem Aufruf, `DOCKER_CONFIG`
  entfernt, Ping-URL nicht ausgegeben.
- Gefunden durch die Tests: `valid_ref` überschrieb `BASH_REMATCH`, der
  Rückweg wäre nie gelaufen; behoben.
- Mutations-Gegenprobe: 12 Fehler eingebaut, 11 erkannt; Lücke „Absturz
  zwischen `current` und Zustand“ mit zwei Fällen geschlossen. Die
  CR-Entfernung im Token ist lokal nicht prüfbar (Git Bash entfernt CR in
  `$(...)`); in der CI unter Linux ist der Fall „Token mit CRLF“ grün.
- CI #170: 114 Fälle, 0 übersprungen (Lauf `45453800370`).

### 1.2 Skills und Arbeitsregel (#171)

- `.claude/skills/entscheidungen-suchen/`: Suche über alle ADRs, alle
  Berichte, `docs/governance/`, `.claude/rules/` und das ganze Repository
  nach Codes `E-…`; Treffer bis zum neuesten Stand verfolgen; Tabelle oder
  „keine gefunden“ mit Suchbegriffen; Abweichung heißt „Änderung von E-…“.
- `.claude/skills/pr-pruefen/`: Umfang voll (alles außer `docs/sitzungen/`
  und `docs/adr/`) oder kurz (nur Entscheidungsabgleich); lokale Gates je Art
  der Änderung; `code-review` mit Stufe `high`; `security-review`; Abgleich
  mit Entscheidungen; Korrekturen nur mit Freigabe; höchstens drei Runden;
  Ergebnis im PR-Text.
- `sitzung-starten` (Schritt 7) und `sitzung-beenden` (Bezug zu früheren
  Entscheidungen, Ablageort, kurze Prüfung) nutzen beide.
- `CLAUDE.md` Abschnitt 1: „Erst suchen, dann vorschlagen“ (Freigabe der
  Ownerin in dieser Sitzung).
- Code-Review: 6 Befunde umgesetzt; Security-Review: keine Befunde, ein
  Hinweis umgesetzt.

### 1.3 PR 4d-3b: Deploy-Unit und Timer (#172)

- `scripts/systemd/identity-service-deploy.service`: System-Unit,
  `User=deploy`, `LoadCredential` für `ghcr-token` und `ping-url`,
  `EnvironmentFile=/etc/identity-service/deploy.env` (E-5-186),
  `StateDirectory` mit `releases/` und `StateDirectoryMode=0700` (E-5-187),
  Sandbox E-5-118 plus E-5-188, `TimeoutStartSec=45min` (E-5-189),
  `After=user@1001.service`.
- `scripts/systemd/identity-service-deploy.timer`: `OnCalendar=*:0/5`,
  `RandomizedDelaySec=30`, `AccuracySec=1s` (E-5-173). Bewusst nicht
  eingeschaltet (E-5-190).
- Korrektur in `deploy-staging.sh`: Rootless-Prüfung **vor** `docker login`
  (E-5-112 war verletzt; gefunden im Code-Review).
- Code-Review: 7 Befunde, alle eingeordnet; Security-Review: keine Befunde.
- CI #172: 120 Fälle (Lauf `45473871772` u. a.).

### 1.4 PR 4d-3c: API-Neustart (#173)

- `scripts/restart-api.sh`: Rootless-Prüfung, gemeinsame Sperre wartend
  (`flock -w 3000`), genau ein Container mit den Labels
  `com.docker.compose.project=identity-service-staging`, `service=api`,
  `oneoff=False`, `docker restart`, Health (E-5-192).
- `scripts/systemd/identity-service-api-restart.service`: ohne Credentials,
  Netz nur Loopback, `TimeoutStartSec=58min`, teilt `StateDirectory` mit dem
  Deploy (E-5-193).
- `scripts/renew-api-certificate.sh`: `restart_api` = `systemctl
  --no-ask-password start identity-service-api-restart.service` (E-5-178);
  Merker `api-tls/.restart-pending` vor dem Neustart, Nachholen an
  Folgetagen (E-5-195).
- `scripts/systemd/identity-service-api-cert.service`: `TimeoutStartSec`
  2 min → 60 min; Sandbox unverändert (E-5-194).
- `scripts/lib/staging-runtime.sh`: gemeinsame Quelle für Projektname,
  Rootless-Prüfung, `server_name` und Health (E-5-196); `deploy-staging.sh`
  umgestellt; Sperrdatei nicht anlegbar → Exit 2; Meldung bei belegter
  Sperre neutral.
- Neue Tests im Pflicht-Job: `test-restart-api.sh` (32 Fälle, Mutationen 5/5),
  `test-renew-api-certificate.sh` (16 Fälle, Mutationen 3/3; erster Test
  dieser Hülle).
- Code-Review: 6 Befunde, davon wichtig „kein zweiter Versuch nach
  gescheitertem Neustart“; Security-Review: keine Befunde, drei Laufzeitrisiken
  umgesetzt.
- CI #173 grün; Deploy 122, Neustart 32, Hülle 16 Fälle ohne Abweichung,
  Smoke-Test bestanden.

### 1.5 Installation am Server (E-5-56, E-5-99, E-5-191)

**Runde 1 (Commit `2e7ca08`, Paket-SHA-256 `7ae87487…608b`):** zwölf Dateien
nach `/usr/local/lib/identity-service/` (Skripte 0755, `lib/` und
`nginx.Dockerfile` 0644) und `/etc/systemd/system/` (Units 0644), alle
`root:root`; vorher geprüft, dass kein Ziel existiert; Hashes am Ziel gleich;
`systemd-analyze verify` Exit 0.

**Runde 2 (Commit `a7314d6`, Paket-SHA-256 `9c8b826e…baa1`):** vorher
`sha256sum -c` der vier laufenden Dateien gegen den bekannten Stand (alle OK),
neue Ziele nicht vorhanden, Zertifikats-Dienst nicht aktiv. Ersetzt:
`deploy-staging.sh`, Deploy-Unit, `/usr/local/sbin/renew-api-certificate.sh`,
Zertifikats-Unit. Neu: `restart-api.sh`, `lib/staging-runtime.sh`,
Restart-Unit. Hashes am Ziel gleich, `verify` Exit 0, `daemon-reload`;
`TimeoutStartUSec=1h` (Zertifikat), `58min` (Restart), `LoadState=loaded`.

Wegwerf-Ordner und Pakete beider Runden gelöscht (Runde 1 bestätigt; Runde 2
Befehl gegeben, Ausgabe nicht gesehen).

### 1.6 Konfiguration am Server

| Datei | Stand (gemessen) |
|---|---|
| `/etc/identity-service/deploy.env` | `root:root 0644`, 26 Bytes, genau eine Zeile `GHCR_USERNAME=…` |
| `/etc/credstore/identity-service-deploy.ghcr-token` | **ersetzt** (vorher 41 Bytes, veraltet); jetzt `root:root 0600`, 40 Bytes, ohne Zeilenende |
| `/etc/credstore/identity-service-deploy.ping-url` | neu, `root:root 0600`, 56 Bytes (Healthchecks-Check `staging-deploy`, Period 5 min, Grace 45 min) |
| `/etc/identity-service/server_name.conf` | neu, `root:root 0644`, 32 Bytes, `server_name staging.<domain>;` (E-5-65, E-5-82) |
| `/etc/identity-service/deploy-first` | **nicht angelegt** (Erst-Schalter für den ersten Deploy) |

### 1.7 Gegenproben am Server

| Gegenprobe | Erwartet | Ergebnis |
|---|---|---|
| Deploy-Unit von Hand, ohne Zustand und Schalter | Exit 6 | `ExecMainStatus=6`; Journal: `Sperre erhalten`, `kein Zustand; Dockerfile … aus der Installation`, `docker rootless` vor `angemeldet`, 4× `Gegenprobe anchore/grype: HTTP 200`, `gh 2.103.3`, vier Gegenproben des Freigabe-Nachweises am erwarteten Grund, `Freigabe: run 45437830490, Versuch 1, commit a566d93…, bundle sha256:78efc84c…22cd`, `Erst-Schalter: no`, `Entscheidung: reject`; 3,4 s CPU, 30,9 MB |
| Restart-Unit von Hand, kein Stack | Exit 3 | `ExecMainStatus=3`; `docker rootless`, `Sperre erhalten`, „gefunden 0“ |
| `StateDirectory` nach beiden Läufen | 0700 | `700 deploy:deploy` (Ordner und `releases/`), `.deploy.lock` `600 deploy:deploy` |
| IP-Filter (`systemd-run`, `User=deploy`) | Kontrolle 0, Probe ≠ 0 | ohne Filter Exit 0; mit `IPAddressDeny=any`/`IPAddressAllow=localhost` Exit 28 (Timeout: BPF verwirft still) |

Der Lauf der Deploy-Unit meldete `/fail` an `staging-deploy`; der Check steht
seitdem auf „down“ (eine Mail erwartet).

### 1.8 Aktualität (24.11.2026)

| Quelle | Befund | Am Server gemessen |
|---|---|---|
| CISA KEV (Katalog 2026.11.24) | CVE-2026-123158 OpenSSH, Umgehung der Passwort-Anmeldung (aufgenommen 09.11.) | `usepam yes`, `passwordauthentication no`, `kbdinteractiveauthentication no`, `authenticationmethods publickey`, `permitrootlogin no`, OpenSSH 10.0p2 Debian: **nicht betroffen** |
| CISA KEV | CVE-2026-46300 Linux-Kernel (ESP, aufgenommen 28.10.) | Kernel `6.12.117+deb13`; Debian-Tracker: trixie ab 6.12.90-1 behoben (DSA-6295-1): **behoben** |
| moby GHSA-6jhp-7446-hf7f (< 29.9.3) | Swarm-Overlay mit firewalld | nicht relevant; läuft 29.10.0 |
| runc GHSA-g2c3-j8g3-7gpw (< 1.5.3) | nur bei checkpoint/restore | läuft 1.5.3 |
| containerd (13.10.) | DoS beim Pull | läuft v2.4.2 |
| `cli/cli` | nichts neu seit 2.102.0 | 2.103.3 |
| thehackernews.com | nichts Neues zu Docker, runc, systemd gefunden | – |

Laufende Versionen beim Deploy-Benutzer: Engine 29.10.0, containerd v2.4.2,
runc 1.5.3, docker-init 0.19.0, rootlesskit 3.3.0. Pakete
`docker-ce`/`docker-ce-rootless-extras` 5:29.10.0, `containerd.io` 2.4.2,
`openssh-server` 1:10.0p1-7+deb13u4; Debian 13 (trixie). Die Stände in
Bericht 32 (29.9.2, runc 1.5.2) waren veraltet; die Pakete wurden ohne Zutun
aktualisiert (vermutlich `unattended-upgrades`, nicht direkt gemessen).

### 1.9 Bewertung `context-mode` und Artikel zu Code-Review

- `mksglu/context-mode` gelesen (README, GitHub-Metadaten): hält
  Tool-Ausgaben aus dem Kontext; Hooks auf jedem Tool-Aufruf, die
  umschreiben und „always exit 0“; `ctx_execute` auf dem Host; `npm i -g`;
  ELv2; ein Hauptautor; fünf Releases in zehn Tagen. Löst nicht das Problem
  vergessener Entscheidungen. Nicht aufgenommen (E-5-180).
- Artikel „How the Claude Code team does code review“ (claude.dev,
  15.10.2026): übernommen wurden lokale Reviews vor dem PR und ein
  Rundenlimit (in `pr-pruefen`). Herausgeberschaft durch Anthropic nicht
  belegt; Kennzahlen vom Herausgeber.

### 1.10 Lehrstoff

- [Lehrstoff: Deploy-Units und API-Neustart](https://claude.ai/artifact/HN8pAubWR37WBMcE5dLaYs)
  (erst suchen, Punkt ohne Wiederkehr mit Diagramm, Token nur an den
  richtigen Daemon, Sandbox und IP-Filter, Gegenprobe als Beleg, Merker vor
  dem Neustart mit Diagramm, Installation aus signiertem Commit, Funde der
  Reviews, Fallen, Spickzettel)

---

## 2. Gelernt

- Entscheidungen, die nur in Berichten stehen, werden übersehen, wenn nur der
  neueste Bericht gelesen wird; in dieser Sitzung geschah das dreimal
  (E-5-56/E-5-99, E-5-118, E-5-16).
- Ein Skill lädt nur, wenn seine Beschreibung passend erscheint; verbindlich
  wird eine Regel erst in `CLAUDE.md`.
- Werden zwei Dinge nacheinander geschrieben, zuerst das, dessen Fehlen ein
  harmloses Wiederholen auslöst (`current` vor Zustand).
- `docker login` reicht die Anmeldung an den Daemon hinter `DOCKER_HOST`
  weiter; die Rootless-Prüfung muss davor stehen.
- systemd legt `StateDirectory` selbst an; `UMask=` wirkt darauf nicht, der
  Standardmodus ist 0755.
- Teilen sich zwei Units ein `StateDirectory`, setzt jede beim Start ihren
  `StateDirectoryMode`; der Wert muss in beiden gleich sein.
- Container lesen Bind-Mounts über den Einhängepunkt; die Rechte der Ordner
  darüber auf dem Host prüft dabei niemand mehr (Annahme, beim ersten
  `compose up` zu messen).
- `IPAddressDeny=any` verwirft Pakete still; der Aufrufer sieht einen
  Timeout, keinen Fehler.
- Ein blockierter Systemaufruf beendet einen Prozess per SIGSYS ohne
  EXIT-Trap; `SystemCallErrorNumber=EPERM` lässt ihn scheitern.
- `TimeoutStartSec` muss über der Summe der Timeouts im Skript liegen, und der
  Aufrufer muss länger warten als der Aufgerufene.
- Ein gescheiterter Neustart nach einer Erneuerung geht ohne Merker
  verloren, weil der nächste Lauf „noch gültig“ meldet.
- `docker compose run` erzeugt Container mit demselben Dienst-Label;
  `com.docker.compose.oneoff=False` filtert sie heraus.
- Jedes `[[ =~ ]]` überschreibt `BASH_REMATCH`, auch in einer aufgerufenen
  Funktion.
- Git Bash entfernt CR in `$(...)`, Linux-Bash nicht.
- `exec 9>DATEI || fail` funktioniert in Bash ohne POSIX-Modus auch unter
  `set -e`.
- `git archive` liefert die Bytes des Repositorys (LF), nicht die der
  Arbeitskopie.
- Healthchecks.io alarmiert einmal beim Wechsel auf „down“, nicht bei jedem
  `/fail`.
- Ein Exit-Code nennt die Klasse eines Fehlers; den Grund belegt erst das
  Journal.

---

## 3. Entscheidungen (ADR-Kandidaten)

Vor dem Eintragen mit `/entscheidungen-suchen` abgeglichen.

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-179** | Vor jedem Konzept, jeder Empfehlung und jedem neuen Code `/entscheidungen-suchen`; vor jedem Commit für einen PR `/pr-pruefen`; verbindlich in `CLAUDE.md` Abschnitt 1 | Drei übersehene Entscheidungen in einer Sitzung; Arbeitsweise, kein ADR |
| **E-5-180** | `context-mode` nicht aufnehmen | Anderes Problem; Hooks auf jedem Tool-Aufruf fail open; globales npm; Agentic-Gate 6.5 |
| **E-5-181** | `deploy-staging.sh` mit drei Parametern; `releases/`, `current`, `state` unter `STATE_DIR`; Server-Pfade und Benutzername aus der Umgebung der Unit; Sperre `STATE_DIR/.deploy.lock` (präzisiert E-5-112, E-5-118) | `current` kann nicht nach außen zeigen; ohne root testbar; Läufe von Hand sehen dieselbe Sperre |
| **E-5-182** | Alte Digests für den Rückweg aus `current/deploy/staging.json`, zeilenweise per Regex, Name wörtlich verglichen (präzisiert E-5-175) | Kein zweiter Zustand; kein `jq` auf dem Server |
| **E-5-183** | `noop` prüft die Health; ungesund → Exit 12, ohne Neustart | Ein still gestorbener Stack fällt spätestens nach 5 Minuten auf |
| **E-5-184** | Ping per `trap EXIT` bei jedem Ausgang; Ausnahme: Sperre belegt (Exit 0 ohne Ping) | Eine Stelle für die Abbildung Exit → Ping |
| **E-5-185** | Exit-Codes des Deploys 0, 2 bis 12 (Tabelle 6.2) | Ursache am Code erkennbar; 0 bis 8 und 12: Stand unverändert |
| **E-5-186** | Name des Maschinenkontos per `EnvironmentFile=/etc/identity-service/deploy.env` (root, 0644), nicht im Repository | Wie Domain und Hostnamen (ADR-004) |
| **E-5-187** | `StateDirectoryMode=0700` in Deploy- und Restart-Unit, immer gemeinsam ändern; beim ersten `compose up` messen, ob nginx liest; sonst 0711 (präzisiert E-5-118) | UMask wirkt nicht auf `StateDirectory`; Annahme aus ADR-017 trug nicht |
| **E-5-188** | Sandbox über E-5-118 hinaus: `InaccessiblePaths` für CA-Schlüssel und Credstore, `SystemCallErrorNumber=EPERM`, `RestrictNamespaces`, `ProtectClock`, `ProtectHostname`, `ProtectKernelLogs`, `LockPersonality`, `RestrictRealtime`, `SystemCallArchitectures=native`, `HOME`/`XDG_CONFIG_HOME` im `RuntimeDirectory`, `After=user@1001.service` (präzisiert E-5-118) | Least Privilege; /fail-Ping auch bei gesperrtem Systemaufruf |
| **E-5-189** | `TimeoutStartSec=45min` für den Deploy; Healthchecks-Check `staging-deploy` mit Period 5 min, Grace 45 min | Summe der Timeouts im Skript rund 30 min; kein Abbruch im Rückweg |
| **E-5-190** | Deploy-Timer erst nach Schritt 3 und dem ersten Deploy von Hand einschalten; vorher nur Start von Hand als Gegenprobe (wie Sitzung 19) | Sonst Exit 2 alle 5 Minuten |
| **E-5-191** | Installation: Paket per `git archive` aus dem signierten Merge-Commit, `scp`, `sha256sum -c` für Paket und jede Datei, laufende Dateien nur bei bekanntem Hash ersetzen; für Deploy- und Prüfskripte gilt E-5-99 dauerhaft (präzisiert E-5-56, E-5-99; ersetzt den Plan aus Bericht 26 „Host-Skripte über den Pull-Deploy“) | E-5-117: ein Release darf seinen Prüfer nicht mitbringen |
| **E-5-192** | `restart-api.sh`: gemeinsame Sperre wartend (50 min), genau ein Container über die Labels `project`, `service=api`, `oneoff=False`, `docker restart`, Health; Exit 0, 2 bis 7 (präzisiert E-5-120) | Kein Neustart mitten im Deploy; unabhängig von Compose-Dateien |
| **E-5-193** | Restart-Unit ohne Credentials, Netz nur Loopback (`IPAddressDeny=any`, `IPAddressAllow=localhost`, gemessen), `TimeoutStartSec=58min`, teilt `StateDirectory` mit dem Deploy | Least Privilege; gemeinsame Sperre |
| **E-5-194** | `TimeoutStartSec=60min` für die Zertifikats-Unit; Sandbox unverändert (wendet E-5-178 an) | `systemctl start` wartet auf einen laufenden Deploy |
| **E-5-195** | Merker `api-tls/.restart-pending` vor dem Neustart anlegen, nach Erfolg löschen; jeder Lauf mit Merker holt den Neustart nach und meldet bis dahin `/fail` (präzisiert E-5-101) | Sonst kein zweiter Versuch; der ok-Ping löschte den Alarm |
| **E-5-196** | `scripts/lib/staging-runtime.sh` ist die einzige Quelle für Projektname, Rootless-Prüfung, `server_name` und Health | Deploy und Neustart dürfen nicht verschieden urteilen |

Bestätigt oder angewendet, ohne neuen Code: **E-5-16** (Phase 5 erst nach
Schritt 5; die Ownerin hat das Vorziehen in dieser Sitzung verworfen),
E-5-56, E-5-58, E-5-65, E-5-82, E-5-97, E-5-99, E-5-101, E-5-112 (Korrektur
Login nach Rootless), E-5-117, E-5-118, E-5-120, E-5-134, E-5-168, E-5-173 bis
E-5-178.

ADR-Kandidaten: E-5-181 bis E-5-196 als **weiterer Nachtrag zu ADR-017**,
zusammen mit E-5-170 bis E-5-178 aus Bericht 32. E-5-179 steht in
`CLAUDE.md`. E-5-180 bleibt im Bericht (abgelehnte Abhängigkeit).

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Erstes lego-Zertifikat fehlt** (Rest von Schritt 3). Ohne es startet
  nginx nicht (`edge.crt`), und die Health des Deploys scheitert. Der erste
  echte Deploy würde mit Exit 10 enden (kein Rückweg).
- **Renew-Timer für lego (E-5-76) existiert nicht**: weder Skript noch Unit.
- **Projektname für lego:** Volumes heißen nach dem Compose-Projekt.
  `deploy-staging.sh` nutzt `-p identity-service-staging`; jeder lego-Aufruf
  (erstes Zertifikat, Renew) muss denselben Projektnamen nutzen, sonst landen
  die Zertifikate in anderen Volumes.
- **Erster Deploy von Hand** mit Erst-Schalter `/etc/identity-service/deploy-first`
  (root, 0644, leer), danach Schalter löschen. Dabei messen:
  `StateDirectoryMode=0700` und nginx liest seine Konfiguration (E-5-187).
- **Deploy-Timer aus**; einschalten nach erstem Deploy (E-5-190). Dann wird
  **DAST** fällig.
- Healthchecks-Check `staging-deploy` steht auf „down“; Pause bis zum
  Einschalten des Timers empfohlen, Stand nicht bestätigt.
- **`gh`-Aufrufe ohne eigenes Timeout** in `scripts/lib/attestation-rules.sh`
  (Zeilen um 120 und 154) und `scripts/verify-release.sh` (um 100 und 121);
  begrenzt nur durch `TimeoutStartSec`. Eigener PR (löst den Release-Lauf aus).
- Ausgabe der Freigabe-Prüfung erscheint im Journal nach den Fehlerzeilen
  (gepuffert); kein Fehler, nur beim Lesen beachten.
- Aufräumen der Runde 2 am Server: Befehl gegeben, Ausgabe nicht gesehen.
  Prüfen: `~/identity-service-a7314d6.tar` und `/tmp/tmp.*` fehlen.
- Option `curl`-Weg für Installationen (Server lädt Commit-Archiv per voller
  SHA, Hash-Vergleich): nicht entschieden; wäre eine Änderung von E-5-56.
- Prüfung, ob die laufende API das neue Zertifikat zeigt (aus Bericht 31),
  weiter offen; ebenso, ob Kestrel selbst neu lädt (E-5-97).
- Keine Prüfung der Unit-Dateien in der CI (`systemd-analyze verify` nur am
  Server).
- **Nachtrag ADR-017** für E-5-170 bis E-5-178 und E-5-181 bis E-5-196.
- `.claude/rules/skripte.md` und `lieferkette-und-ci.md`: neue Skripte
  nachtragen (`deploy-staging.sh`, `restart-api.sh`, `lib/staging-runtime.sh`,
  `test-deploy-staging.sh`, `test-restart-api.sh`,
  `test-renew-api-certificate.sh`) sowie die Liste aus Bericht 32 (Ownerin).
- Neuer Freigabe-Stand nach #173 (6.1); ausgerollt ist weiterhin nichts.
- Lokale Branches löschen (Freigabe nötig): `feat/deploy-staging-script`,
  `chore/decision-search-skills`, `feat/deploy-units`, `feat/api-restart-unit`,
  `docs/sitzung-32` und die Listen aus Bericht 30 bis 32.

**Aus Bericht 32 und früher, weiter offen**

- Agenten-Token läuft am 23.12.2026 13:10 UTC ab; Erinnerung ab etwa
  16.12.2026.
- GHCR-Token (Maschinenkonto) läuft am 23.01.2027 ab; Erinnerung ab etwa
  09.01.2027. Im Credstore steht seit heute der aktuelle Wert.
- Lokale Zertifikate laufen am 31.01.2027 12:46 UTC ab.
- Erste Erneuerung des API-Zertifikats spätestens 27.12.2026: Neustart
  eingerichtet; ohne laufenden Stack meldet sie `/fail` und versucht es täglich
  erneut (E-5-195).
- `ip_unprivileged_port_start = 80`; vor Production engere Lösung.
- Aufbewahrungsregel für GHCR fehlt (je Skript-PR drei Images; Bundles ohne
  Nachweis `e48e4ad4…6a8c`, `5a1ae60a…a554`).
- Sicherheitsfunktionen nach dem Sichtbarkeitswechsel (Sitzung 31) nicht
  einzeln geprüft.
- ADR-015, ADR-016, ADR-017 auf „Akzeptiert“ (Ownerin).
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy.
- API-Image: sechs Medium-Lücken in `libc6`; Bot-PRs vor dem Merge lesen.
- E-5-128 nicht umgesetzt; `dependabot.yml`: SDK-Hauptversionen ignorieren.
- „Manage Actions access“: Write statt Admin nicht belegt.
- Kestrel-Neuladen, nginx und alte TLS-Sitzungen nach Zertifikatswechsel
  nicht gemessen.
- Server: `unattended-upgrades`-Wirkung nur indirekt belegt, Journal-Frist,
  NTS, `nft-rollback.service`; `user: "1654:1654"` in `compose.staging.yaml`;
  Units von host-health-check nicht im Repository; Update-Weg von `gh` auf dem
  Server (2.103.3).
- Lokales `gh` 2.102.0 unter der Mindestversion 2.103.3.
- Erster automatischer Lauf des Zertifikats-Timers nicht im Journal
  abgelesen.
- CA-Wechsel vor dem 28.10.2027.
- Lokal: SSH-Signaturen als `%G? = U` (kein `allowedSignersFile`).

**Bekannte Grenzen**

- Die Sandbox begrenzt den Docker-Client, nicht den Daemon; wer den Socket
  hat, hat die Rechte von `deploy`.
- Der erste Deploy vertraut ohne Vergleich (Erst-Schalter).
- Domain, IPs, Hostnamen und Benutzernamen stehen bewusst nicht in diesem
  Bericht (ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Deploy, Units und Neustart gebaut, installiert und
belegt; es läuft noch kein Stack.

| Nr. | Schritt | Stand |
|---|---|---|
| 1 | Staging-Konfiguration | erledigt |
| 2 | Interne CA | erledigt; API-Neustart installiert (4d-3c) |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer | Ports frei; `server_name.conf` fertig; **erstes Zertifikat, lego-Timer, Gegenprobe 9, CAA offen** |
| 4 | Maschinenkonto, Leserecht | erledigt; Token im Credstore aktuell |
| 5 | Pull-Deploy | ~~4a bis 4d-3c~~ erledigt; **erster Deploy und Timer offen** |
| 6 | Freigabe vor dem Deploy, DORA-Ereignisse | Nachweis fertig, DORA offen |
| 7 | DAST (OWASP ZAP) | nach erstem automatischem Deploy |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | keine neue Abhängigkeit; `context-mode` abgelehnt (E-5-180) |
| **Agentic-Gate 6.5** | berührt durch die Bewertung von `context-mode`, nicht ausgelöst (nicht aufgenommen) |
| **A01 / Zugriff** | Restart-Unit für fremde Benutzer gesperrt (Sitzung 32); CA-Schlüssel und Credstore in beiden Units unsichtbar |
| **A10 / fail closed** | Exit 6 und Exit 3 am Server belegt; fehlendes Credential → Unit startet nicht; Merker gegen verlorenen Neustart |
| **Secrets (6.3.3)** | Token und Ping-URL per `read -s` in den Credstore; nie ausgegeben; Token nur an rootless Daemon |
| **Resilienz-Patterns** | ausgelöst seit Sitzung 7; Timeouts je Schritt, Unit-Grenzen gestaffelt; `gh` noch ohne eigenes Timeout |
| **DAST** | fällig mit dem Einschalten des Deploy-Timers |
| **LLM-Gate 6.4** | nicht ausgelöst |
| **mTLS, Contract Testing, Feature Flags, Mutation Testing, k6** | nicht fällig (Feature Flags ruhen, weil E-5-16 bestätigt ist) |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (24.11.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| `main` | `a7314d6` | `git log` |
| `identity-service-release:staging` | `sha256:38f36a6c524f76c3d3b835adecc7ac45102dbfb0368f2f3ce31c052c6f5cdab4` (Run `45487079423`, Commit `a7314d6`) | Release-Lauf |
| Freigabe beim Gegenprobe-Lauf | Run `45437830490`, Commit `a566d93`, Bundle `78efc84c…22cd` | Journal am Server |
| `deploy/staging.json` | unverändert: Digests von `768bbb4` (Bericht 31) | Repository |
| Installationspaket Runde 1 | Commit `2e7ca08`, SHA-256 `7ae874878fd3d332568930a1a280a8eb7b006ca8ad19a4b3cc2fb5c664e3608b` | lokal |
| Installationspaket Runde 2 | Commit `a7314d6`, SHA-256 `9c8b826e29c70ecf01e69d3c7f450a67b42d1b1a64e4fc5e0a656f77089abaa1` | lokal |

**Installierte Dateien und SHA-256 (Stand nach Runde 2, für künftige
Ersetzungen):**

| Ziel | SHA-256 |
|---|---|
| `/usr/local/lib/identity-service/deploy-staging.sh` | `7d8e1092faf70be7be3af4d1be3e0e816c28b9071c4236deb59905b196ae5a99` |
| `/usr/local/lib/identity-service/restart-api.sh` | `6f06ad0ca21e4a21d27ab5f1d35d4163e8287e0541b1fe330badda2b846c33ca` |
| `/usr/local/lib/identity-service/fetch-release.sh` | `dc240deccb2a3545295ca800107a68b55cff5558c070b306438056f0bbbca074` |
| `/usr/local/lib/identity-service/verify-release.sh` | `d8a0fdf6afa672a039f69ab4bf4b962f84a2258757d21fd1370bd9cf9bd4116c` |
| `/usr/local/lib/identity-service/verify-attestations-server.sh` | `577e682d605f85c7f2cf85e69747d948e6817579919d8279ec94e2822cefe5a9` |
| `/usr/local/lib/identity-service/verify-package-private.sh` | `7427e4a84e198a027e208f243bbc1b91acbca97fd29dbbe9b7f8c26a8c226a84` |
| `/usr/local/lib/identity-service/nginx.Dockerfile` | `4f2fb244db32b2757a26fea656348b96419b99efd1268ee9eac8dbc9fc7bb375` |
| `/usr/local/lib/identity-service/lib/release-rules.sh` | `2298761799fbaf2d2d2b4db3690276135e8c64dc1650ee292e4e481d566e776b` |
| `/usr/local/lib/identity-service/lib/release-state.sh` | `50dc54c6d2ba728236359ea75c5527ef2ee30682eedcbf1603cfb01206d18845` |
| `/usr/local/lib/identity-service/lib/registry-only.sh` | `f2216d93d32433a5a75fe991988db45c3c9c21c32e3372e4e10f32693c78d93b` |
| `/usr/local/lib/identity-service/lib/attestation-rules.sh` | `d38982cfc21eac912467716f21d285e9375ac479207eab7d39825aa6827804c5` |
| `/usr/local/lib/identity-service/lib/staging-runtime.sh` | `24760de0dfbbdbc6098a16f30c6b38ca14b374e5d1867687a736d4cc7f45e2b5` |
| `/usr/local/sbin/renew-api-certificate.sh` | `5ddc7e67ee473b87401b4f3f7c9ea836cf7486ba828ee991ea020b1e0b518683` |
| `/etc/systemd/system/identity-service-deploy.service` | `679004811081272ae4e751e0659722f8ab07bd29c91d349c7a3a02543b737ff7` |
| `/etc/systemd/system/identity-service-deploy.timer` | `e2044748e744b5f73666b5a15091be3e42f9f18b1894b7dcbbdfecf6b0de587e` |
| `/etc/systemd/system/identity-service-api-restart.service` | `705d2976cdb8792ea6e6a5750f9081824c245dc5f69ccb88d013dc88931fe69d` |
| `/etc/systemd/system/identity-service-api-cert.service` | `3a3b76171e82d63ca9296085a8df8e68dd2340a7a6a7bc3cef405439704cb87e` |

### 6.2 Skripte und Exit-Codes (neu oder geändert)

| Skript | Codes |
|---|---|
| `deploy-staging.sh STATE_DIR SWITCH_FILE INSTALL_NGINX_DOCKERFILE` | 0 ausgerollt, `noop` gesund oder Sperre belegt · 2 Voraussetzung/Parameter/Umgebung/Token/Sperrdatei · 3 Nachweis/Freigabe · 4 Gegenprobe akzeptiert · 5 Gegenprobe am falschen Grund · 6 Downgrade-Regel · 7 Paket anonym lesbar · 8 Pull/Digest · 9 ungesund, Rückweg gelungen · 10 **kritisch**: Rückweg gescheitert oder unmöglich · 11 gesund, `current`/Zustand nicht geschrieben · 12 `noop`, Stand ungesund |
| `restart-api.sh STATE_DIR` | 0 neu gestartet und gesund · 2 Voraussetzung · 3 nicht genau ein API-Container · 4 `docker restart` · 5 Health rot · 6 Sperre nicht rechtzeitig · 7 `docker ps` |
| `renew-api-certificate.sh` | 0 alles in Ordnung und Ping angekommen · 1 sonst; Merker `api-tls/.restart-pending` |

Umgebung der Deploy-Unit: `GHCR_USERNAME` (aus `deploy.env`),
`STAGING_SERVER_NAME_FILE=/etc/identity-service/server_name.conf`,
`STAGING_CA_DIR=/etc/identity-service/ca`,
`STAGING_API_CERT_DIR=/etc/identity-service/api-tls`,
`DOCKER_HOST=unix:///run/user/1001/docker.sock`; Credentials `ghcr-token`,
`ping-url`; `StateDirectory=/var/lib/identity-service-deploy`.

### 6.3 Läufe als Belege

| Zweck | Lauf |
|---|---|
| CI #170 (114 Fälle) | `45453800370` |
| CI #172 | `45473871772`, `45473871566`, `45473871748` |
| CI #173 | `45486446569`, `45486446627`, `45486446587` |
| Release nach #173 | `45487079423` |
| Nach-Merge-Läufe #170, #171, #172, #173 | alle grün (CI, CodeQL, Publish, Publish nginx; nach #173 zusätzlich Release) |

### 6.4 Server: gemessen

| Gegenstand | Wert |
|---|---|
| Betriebssystem | Debian 13 (trixie), Kernel `6.12.117+deb13-amd64` |
| sshd | `usepam yes`, `permitrootlogin no`, `passwordauthentication no`, `kbdinteractiveauthentication no`, `authenticationmethods publickey` |
| Docker beim Deploy-Benutzer | Engine 29.10.0, containerd v2.4.2, runc 1.5.3, rootlesskit 3.3.0 |
| Units | `identity-service-api-cert.service`/`.timer` (aktiv), `identity-service-deploy.service`/`.timer` (Timer `disabled`), `identity-service-api-restart.service` |
| Healthchecks | `staging-host-2`, `staging-api-cert-2`, neu `staging-deploy` (Period 5 min, Grace 45 min; „down“ nach der Gegenprobe) |
| Container | keine |

### 6.5 Fallstricke, die Zeit gekostet haben

- `scp` ohne `-i`: „Permission denied (publickey)“. Dieselben Optionen wie
  bei `ssh` nehmen (Schlüsseldatei und vollen Hostnamen aus `known_hosts`).
- Der Hostname im Shell-Prompt ist die Kurzform und von außen nicht
  auflösbar.
- `read -p` mit leerer Eingabe: `${VAR:?}` bricht ab (gewollt).
- Python-Heredoc für Ersetzungen mit Backslashes brach ab; Einzel-Edits
  verwenden.
- Test erwartete Text direkt hinter einem Trenner; erst Zeile filtern, dann
  Text suchen.
- `""` als „kein Parameter“ getestet; ein leerer String ist ein Parameter.

### 6.6 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Paket bauen | Bytes des signierten Commits | `git archive --format=tar -o … COMMIT DATEIEN` | LF, Hash je Datei |
| Übertragen | E-5-56 | `scp -i …` | 100 % |
| Prüfen | Unversehrtheit | `echo "HASH  PAKET" \| sha256sum -c`; `printf … \| sha256sum -c` | alle OK |
| Ersetzen | nur bekannter Stand | `printf ALT_HASH ZIEL \| sudo sha256sum -c && … install` | vier OK, dann ersetzt |
| Credstore | Token und Ping-URL | `read -rsp`, `install /dev/null`, `printf %s \| sudo tee` | 40 bzw. 56 Bytes, 0600 |
| Gegenprobe Deploy | Sandbox bis zur Entscheidung | `systemctl start identity-service-deploy.service`; `journalctl -u …` | Exit 6, Grund belegt |
| Gegenprobe Neustart | Sperre, Socket | `systemctl start identity-service-api-restart.service` | Exit 3 „gefunden 0“ |
| IP-Filter | Kommentar belegen | `systemd-run … -p IPAddressDeny=any -p IPAddressAllow=localhost curl …` | Kontrolle 0, Probe 28 |

---

# Roadmap Sitzung 34

## 1. Erstes lego-Zertifikat (Rest von Schritt 3): Konzept, dann Code

Warum zuerst: Ohne Zertifikat startet nginx nicht, die Health des Deploys
scheitert, und es gibt keinen ersten Deploy, keinen Timer und kein DAST. Alles
andere aus Phase 4 hängt daran.

Vor dem Konzept `/entscheidungen-suchen` mit mindestens: E-5-65, E-5-66,
E-5-73 bis E-5-76, E-5-78, E-5-80, E-5-82, E-5-83, E-5-88, ADR-014.

Offene Fragen, zu entscheiden:

- **Henne-Ei:** nginx braucht `edge.crt`, lego braucht für HTTP-01 den
  Webroot hinter nginx. Empfehlung aus Bericht 24 (nicht entschieden): erstes
  Zertifikat mit lego im **Standalone-Modus bei gestopptem nginx**, danach
  sofort ein erzwungener Renew über den Webroot.
- **Erst gegen die Staging-Umgebung von Let's Encrypt**, dann Produktion
  (Bericht 22).
- **Projektname `identity-service-staging`** für jeden lego-Aufruf, damit die
  Volumes zum Deploy passen (6.2, 4).
- **Renew-Timer nach E-5-76** (Skript, Unit, Timer, Healthchecks-Check,
  `nginx -s reload`) mit Tests im Pflicht-Job; Installation nach E-5-191.
- Danach Gegenprobe 9, CAA um `accounturi` und `validationmethods`, ADR zum
  Schritt DNS/TLS.

## 2. Erster Deploy von Hand und Timer

Warum: macht Staging zum ersten Mal lauffähig. Erst-Schalter anlegen,
`systemctl start identity-service-deploy.service`, Journal lesen, Schalter
löschen; `StateDirectoryMode=0700` messen (nginx liest seine Konfiguration);
Health über nginx; Healthchecks `staging-deploy` wieder „up“; dann Timer
einschalten (E-5-190) und einen automatischen Lauf (`noop`) ablesen.

## 3. Timeouts für `gh` in den Prüfskripten

Warum: einzige Netzaufrufe ohne eigenes Timeout; hängt `gh`, endet der Deploy
erst nach 45 Minuten ohne genauen Grund. Eigener PR; löst den Release-Lauf aus.

## 4. Nachtrag ADR-017 (E-5-170 bis E-5-178, E-5-181 bis E-5-196)

Warum: diese Entscheidungen stehen nur in den Berichten 32 und 33.

## 5. DORA-Ereignisse (Schritt 6) und DAST (Schritt 7)

Warum: letzte Teile von Phase 4. DAST wird mit dem Einschalten des Timers
fällig.

## 6. Kurze Punkte der Ownerin

- PR für diesen Bericht (Branch `docs/sitzung-33`) mergen
- Healthchecks `staging-deploy` pausieren bis zum Einschalten des Timers
- ADR-015, ADR-016, ADR-017 auf „Akzeptiert“
- `.claude/rules/*.md` nachziehen (siehe Offene Punkte)
- Sicherheitsfunktionen des Repositorys kontrollieren
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy
- Gemergte lokale Branches löschen

## 7. Danach: Phase 5

Erst wenn Phase 4 abgeschlossen ist (E-5-16, in Sitzung 33 bestätigt).
Gefundene Vorgaben: erster Use Case Kandidat **Benutzerregistrierung**;
Endpoint-Stil als ADR in Phase 5; ArchUnitNET-Bewertung per ADR; Testcontainers;
Netz `data` additiv, Datenbank nie von nginx erreichbar; ICU neu bewerten bei
E-Mail-Normalisierung; keine Entscheidung zu Datenbank, ORM und
Passwort-Hashing. Davor STRIDE nach CLAUDE.md Abschnitt 9. Vorschlag ohne
Entscheidung: Endpunkte erst mappen, wenn der Use Case vollständig ist,
statt Feature Flags.

## 8. Zurückgestellt, nicht aufgehoben

- E-5-128, E-5-129; `dependabot.yml` SDK-Hauptversionen
- Aufbewahrungsregel für GHCR
- Server-Härtung; Update-Weg von `gh`; engere Port-Freigabe vor Production
- Telemetrie von `gh` in der CI abschalten
- „Manage Actions access“: Write statt Admin belegen
- `curl`-Weg für Installationen (Änderung von E-5-56, nur auf Wunsch)
- Unit-Dateien in der CI prüfen
- CA-Wechsel vor dem 28.10.2027; vor Production: NTS, IPv6, zweiter
  Warnkanal, HSTS

## 9. Vor oder in der Sitzung zu verstehen (vor Code)

- **HTTP-01 und Henne-Ei:** Let's Encrypt ruft eine Datei unter
  `/.well-known/acme-challenge/` über Port 80 ab. Läuft nginx noch nicht, kann
  lego im Standalone-Modus selbst auf Port 80 antworten; danach übernimmt der
  Webroot hinter nginx die Erneuerungen.
- **Staging-Umgebung von Let's Encrypt:** gleiche Abläufe, aber nicht
  vertrauenswürdige Zertifikate und großzügige Limits. Fehler kosten dort
  keine Rate Limits der Produktion.
- **Compose-Projekt und Volumes:** Volumes heißen `<projekt>_<name>`. Ein
  lego-Aufruf mit anderem Projektnamen schreibt in andere Volumes, als nginx
  liest.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Deploy-Units und API-Neustart](https://claude.ai/artifact/HN8pAubWR37WBMcE5dLaYs)

## 10. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- SSH: `ssh -i` mit dem Staging-Schlüssel; für `scp` dieselben Optionen
- Bei Healthchecks.io einen Check für den lego-Renew-Timer vorbereiten
  (Period und Grace legen wir im Konzept fest)
- Erinnerungen: Agenten-Token vor dem 23.12.2026, GHCR-Token vor dem
  23.01.2027, lokale Zertifikate vor dem 31.01.2027
