# Sitzungsbericht Sitzung 32

**Datum:** 24.11.2026
**Phase:** Schritt 5 (CD): PR 4c (Server prüft die Freigabe, Downgrade-Regel)
gemergt und am Server rot/grün belegt; Nachtrag ADR-017; 4d in 4d-1, 4d-2,
4d-3 aufgeteilt, 4d-1 und 4d-2 gemergt; E-5-120 gemessen. Offen: 4d-3
(Deploy-Skript, Units, Restart-Unit), Frist 27.12.2026
**Vorgänger:** sitzung-31.md (abgeschlossen 23.11.2026)

---

## 1. Erledigt

| PR | Titel | Merge |
|---|---|---|
| #164 | `docs: add session report 31` | `b2d0d04` |
| #165 | `feat(deploy): add server release verification with downgrade rule` | `e5eab9d` |
| #166 | `docs(adr): add addendum to ADR-017 for parts 4a to 4c` | `86d7b3b` |
| #167 | `fix(deploy): reject group or world writable releases dir` | `fba8454` |
| #168 | `feat(scripts): allow explicit public package for visibility check` | `a566d93` |

Alle von der Projekt-Ownerin per Squash gemergt, überwiegend KI-erzeugt, kein
Auto-Merge.

### 1.1 Aktualität (24.11.2026)

- GitHub-Sicherheitshinweise `cli/cli`: GHSA-wjmr-j3rp-mh2g
  (`--signer-workflow` als Präfix verglichen), GHSA-4mq3-hpgx-9cx8
  (`--source-ref` ohne Groß-/Kleinschreibung), GHSA-39wj-f2f4-978v
  (Symlinks): betroffen bis 2.101.0, behoben ab 2.102.0. Server 2.103.3 und
  lokal 2.102.0 nicht betroffen. Neuestes Release 2.105.0 (18.11.2026).
- CISA KEV in dieser Sitzung **nicht** erneut durchsucht.
- GitHub-Doku: „GitHub Packages only supports authentication using a
  personal access token (classic)“; Pull privater Images braucht
  `read:packages`.

### 1.2 Messungen am Server vor 4c (Deploy-Benutzer, rootless Docker, temporärer `DOCKER_CONFIG`)

| Messung | Ergebnis |
|---|---|
| `docker info` | `name=rootless` |
| Fein abgestuftes Token des Maschinenkontos (neu erzeugt) | `docker login` „Succeeded“, Pull scheitert: `permission_denied: The token provided does not match expected scopes`, auch für das API-Paket |
| Klassisches Token (per „Regenerate“ erneuert, nur `read:packages`, Ablauf 23.01.2027) | Pull `identity-service-release@sha256:4f6bcfb5…` gelingt: Leserecht belegt |
| `docker create` auf dem scratch-Bundle ohne Befehl | `no command specified`, Exit 1 |
| `docker create … /nonexistent`, `docker cp` | Container-ID 64 Zeichen; `deploy/staging.json` 456 Bytes, SHA-256 `8bf2ac23…4304` = Commit `b5692ac`, Rechte 0644 |
| `verify-release.sh …:staging` (Dateien von `b5692ac`, Prüfsummen verglichen) | Exit 0, Run `45202570572`, Versuch 3, 4/4 Gegenproben am erwarteten Grund |

Das fein abgestufte Token ist im Maschinenkonto gelöscht. Aufgeräumt:
temporäre Ordner, Registry-Anmeldung, gezogenes Bundle.

### 1.3 PR 4c (#165)

- `scripts/lib/release-state.sh`: `release_decide` (Tabelle aus ADR-017 als
  reine Funktion: `deploy`, `first`, `noop`, `reject`),
  `release_state_render`/`release_state_parse` (drei Zeilen `run`, `commit`,
  `bundle`, Tabulator, LF).
- `scripts/fetch-release.sh`: Schritte 0, 2, 3, 5 des Server-Ablaufs; Exit 6
  = Alarm der Downgrade-Regel, Exit 2 bis 5 von `verify-release.sh`
  durchgereicht. Ändert keinen Zustand und keinen Dienst.
- `scripts/test-release-state.sh` im Pflicht-Job `Container & nginx`.
- Lokal 67 ok, 5 übersprungen (Windows); CI 79 ok, 0 übersprungen
  (Lauf `45427585109`).
- Mutations-Gegenprobe mit drei eingebauten Fehlern: alle erkannt; dabei ein
  zu schwacher erwarteter Grund gefunden und verschärft.
- Nach dem Merge: Release-Lauf `45428174452`, 13/13 Schritte, Versuch 1,
  Commit `e5eab9d`, `staging` → `329bdd34…eb88`.

### 1.4 Rot-Beweis und Gegenprobe am Server (Dateien von `e5eab9d`, Prüfsummen verglichen)

| Fall | Ergebnis |
|---|---|
| gespeicherte Run-ID `45428174453` > Freigabe `45428174452` | `Run-ID 45428174452 ist kleiner als gespeichert (45428174453) - Downgrade`, Exit 6, Releases-Ordner leer |
| gespeicherte Run-ID `45202570572` (Stand 23.11.) | `deploy`, Exit 0, genau zehn Dateien, Dateien 0644, Ordner 0755, `staging.json` = `8bf2ac23…` |
| zweiter Lauf, Ordner existiert | „existiert bereits mit gleichem Inhalt“, Exit 0 |

Alles in Wegwerf-Ordnern unter `/tmp`; aufgeräumt.

### 1.5 Nachtrag ADR-017 (#166)

Re-run-Messung, Server-Messungen vom 24.11.2026, Teilentscheidungen
E-5-150 bis E-5-168, offene Punkte für 4d. Oben korrigiert: Dateiliste des
Bundles um `docker/nginx/Dockerfile` ergänzt, zwei Stellen „nicht gemessen“
auf „gemessen“. Status bleibt „Vorgeschlagen“.

### 1.6 PR 4d-1 (#167)

`fetch-release.sh` bricht mit Exit 2 ab, wenn `RELEASES_DIR` für Gruppe oder
andere schreibbar ist (E-5-170). CI: 83 ok, die Fälle 0775, 0757, 1777 und
0755 einzeln belegt (Lauf `45434696424`).

### 1.7 PR 4d-2 (#168)

- `verify-package-private.sh IMAGE_NAME [PUBLIC_PACKAGE]`; kein `cd` mehr;
  Abbruch bei gleichen Paketen. CI-Aufrufer unverändert.
- `PUBLIC_COUNTER_PACKAGE="ghcr.io/anchore/grype"` in
  `scripts/lib/registry-only.sh` (E-5-171).
- `scripts/test-package-private.sh` (curl-Ersatz) im Pflicht-Job: 23 ok in
  der CI (Lauf `45437206613`). Erstmals belegt: „Registry nicht erreichbar“
  → Exit 2.
- Anonym gemessen: `anchore/grype` 200, `identity-service-release` 401,
  nicht vorhandenes Paket 403. Echtes Skript gegen GHCR mit und ohne zweiten
  Parameter: Exit 0.
- Mutations-Gegenprobe: zwei Fehler erkannt; Testlücke (CI und Server
  nutzen dasselbe Vergleichspaket) durch einen Fall mit anderem Paket
  geschlossen.
- Nach dem Merge sechs Läufe grün: Release `45437830490` (`staging` →
  `78efc84c…22cd`), Publish, Publish nginx, Publish lego, CI, CodeQL.

### 1.8 Lesender Blick auf den Server

| Gegenstand | Befund |
|---|---|
| Units | nur `identity-service-api-cert.service` (inactive) und `.timer` (letzter Lauf 24.11.2026 00:48) |
| `net.ipv4.ip_unprivileged_port_start` | 80 |
| Container des Deploy-Benutzers | keine |
| `/etc/identity-service/` | `api-tls`, `ca`, `ca-private` (0700); keine Datei mit `server_name` |
| `/etc/credstore/` | u. a. `identity-service-deploy.ghcr-token` (41 Bytes, 30.10.2026): enthält das **vor dem Regenerate** gültige Token, jetzt ungültig |

### 1.9 Messung E-5-120

Flüchtige Ziel-Unit unter `/run/systemd/system/` (`/bin/true`), Aufrufer per
`systemd-run` mit der Sandbox der Zertifikats-Unit (`NoNewPrivileges`,
`ProtectSystem=strict`, `CapabilityBoundingSet=CAP_CHOWN CAP_FOWNER
CAP_DAC_OVERRIDE` u. a.):

| Messung | Ergebnis |
|---|---|
| `systemctl start` aus der Sandbox | Exit 0 |
| `ExecMainExitTimestamp` | leer (kein Beleg in beide Richtungen) |
| Gegenprobe als Deploy-Benutzer | `Access denied`, Exit 4 |
| Journal der Ziel-Unit | genau ein `Starting`/`Finished` (17:43:02/03) |

Ergebnis: Die Zertifikats-Unit darf die Restart-Unit starten, ohne dass ihre
Sandbox wächst. Ziel-Unit entfernt (`LoadState=not-found`).

### 1.10 Lehrstoff

- [Lehrstoff: Server prüft Freigabe](https://claude.ai/artifact/RRxxnqgjG4HpNVckhrYSyK)
  (Herkunft ist nicht Aktualität, kaputt ist nicht fehlend, Regex vor
  Arithmetik, Bundle auspacken mit Diagramm, ACL-Maske, Login ist nicht
  Leserecht, Exit-Code ist kein Beleg, Mutations-Gegenprobe, Fallen,
  Spickzettel)

---

## 2. Gelernt

- Ein gültiger Freigabe-Nachweis kann alt sein; nur der Vergleich der Run-ID
  mit dem gespeicherten Zustand verhindert einen Downgrade.
- Wird eine kaputte Zustandsdatei wie eine fehlende behandelt, schaltet ein
  vorhandener Erst-Schalter den Downgrade-Schutz ab.
- Bash wertet in `$(( ))` Array-Indizes aus; ein Wert wie `a[$(befehl)]`
  führt einen Befehl aus. Vor Arithmetik per Regex auf Ziffern beschränken.
- GHCR akzeptiert nur klassische Tokens; ein fein abgestuftes Token wird
  beim Login angenommen und erst beim Pull abgelehnt.
- `docker create` auf einem Image ohne Startbefehl scheitert mit
  `no command specified`; ein nie ausgeführter Befehl wie `/nonexistent`
  löst das.
- `docker cp` setzt den aufrufenden Benutzer als Eigentümer und übernimmt
  die Änderungszeit aus dem Image.
- `docker create` zieht ein fehlendes Image selbst (per Digest).
- Mit ACL zeigen die Gruppen-Bits von `stat` die Maske; eine Prüfung auf
  `020` deckt deshalb auch ACL-Schreibrechte ab.
- Ein root-Prozess mit wenigen Capabilities und `NoNewPrivileges` darf per
  `systemctl start` andere Units starten; systemd entscheidet nach der UID.
- `ExecMainExitTimestamp` kann nach einem Lauf leer sein; das Journal ist
  der verlässliche Beleg.
- `cmd | head -n N` beendet ein Skript mit `pipefail` mit Exit 141, wenn
  `cmd` danach noch schreibt.
- Unter Git Bash auf NTFS scheitert `mkdir -m`, und `chmod` wirkt auf Ordner
  nicht; kopierte MSYS-Programme finden ihre DLLs nicht.
- Änderungen unter `scripts/` starten neben dem Release-Lauf auch die drei
  Publish-Workflows.
- Ein erwarteter Fehlergrund, der auch in einer allgemeinen Zeile steht,
  lässt einen Test trotz entferntem Schutz grün.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-163** | Downgrade-Regel als reine Funktion `release_decide` in `scripts/lib/release-state.sh`; jede Tabellenzeile ein Testfall | testbar ohne Netz und Docker; Open/Closed |
| **E-5-164** | Vorhandener, ungültiger Zustand = `reject`, nie „kein Zustand“; ein Format für Lesen und Schreiben | sonst fail open über den Erst-Schalter |
| **E-5-165** | Run-ID (höchstens 18 Ziffern, ohne führende Null) und Dateimodus per Regex vor jeder Arithmetik | Einschleusung über `$(( ))` |
| **E-5-166** | Bundle: `docker create <Digest> /nonexistent`, `docker cp` nur `RELEASE_FILES`, Prüfungen je Datei, Rechte selbst, `.incoming` + `mv -T`, vorhandener Ordner byte-gleich | nur Signiertes lesen, atomar, wiederholbar |
| **E-5-167** | `fetch-release.sh`: Exit 6 = Alarm der Downgrade-Regel; 2 bis 5 durchgereicht | unterscheidbare Ursachen |
| **E-5-168** | GHCR-Token des Maschinenkontos: klassisch, nur `read:packages`, festes Ablaufdatum | nur klassische Tokens unterstützt (gemessen) |
| **E-5-169** | Server-Handbefehle prüfen ihre Voraussetzungen selbst (`${VAR:?}`, `test "$(id -u)" = …`) | Hinweise werden beim Abtippen übersehen; Arbeitsweise, kein ADR |
| **E-5-170** | `RELEASES_DIR` für Gruppe und andere nicht schreibbar (auch per ACL), sonst Exit 2 | untergeschobener Release-Ordner |
| **E-5-171** | Server übergibt `PUBLIC_COUNTER_PACKAGE` an `verify-package-private.sh`; CI bleibt bei `compose.scan.yaml` | Server hat keine Repository-Wurzel; fail closed bei Wegfall |
| **E-5-172** | 4d-3 in drei PRs: 3a Deploy-Skript mit Tests, 3b Units/Timer/Installation, 3c Restart-Unit und `restart_api` | ein Thema pro Branch |
| **E-5-173** | Deploy-Timer alle 5 Minuten, `RandomizedDelaySec=30` | DORA-Vorlaufzeit gegen Registry-Last |
| **E-5-174** | GHCR-Token per `LoadCredential` aus `/etc/credstore`; `config.json` nur im `RuntimeDirectory` (0700) | Token nie dauerhaft auf der Platte außerhalb des Credstore |
| **E-5-175** | Rückweg bei gescheiterter Health: `compose up` mit altem `current` und alten Digests, Alarm; Zustand und `current` bleiben alt; ohne altes `current` nur Alarm | Verfügbarkeit ohne Zustandsverlust |
| **E-5-176** | Netzziele (E-5-135): vorerst nur `RestrictAddressFamilies`; Egress-Proxy oder nftables-Sets später per ADR | Zeit bis zur Frist; Segmentierung ist kein Ausweis |
| **E-5-177** | Normalfall `NGINX_DOCKERFILE` aus `current/`; nur ohne Zustand eine root-eigene Kopie aus der Installation | E-5-160 bleibt wirksam; manipuliertes Dockerfile kann nur rot machen |
| **E-5-178** | `restart_api` ruft `systemctl start identity-service-api-restart.service`; Sandbox der Zertifikats-Unit bleibt unverändert | E-5-120 gemessen |

ADR-Kandidaten: E-5-163 bis E-5-168 stehen im Nachtrag zu ADR-017.
**E-5-170 bis E-5-178 als weiterer Nachtrag zu ADR-017** (mit dem PR 4d-3b
oder davor). E-5-169 ist eine Arbeitsweise und bleibt im Bericht.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **4d-3a, 4d-3b, 4d-3c offen; Frist 27.12.2026.** Ohne laufende API meldet
  der Zertifikats-Timer bei der ersten Erneuerung „API-Neustart nicht
  eingerichtet oder gescheitert“ als Problem.
- **Erster echter `compose up` braucht noch:** Datei mit `server_name`
  (`STAGING_SERVER_NAME_FILE`) und das erste lego-Zertifikat (Rest von
  Schritt 3). Ports 80/443 sind bereits freigegeben.
- **`/etc/credstore/identity-service-deploy.ghcr-token` ist veraltet**
  (Wert vor dem Regenerate). Bei 4d-3b als root per `read -s` überschreiben;
  das Skript muss das Zeilenende entfernen.
- `ip_unprivileged_port_start = 80` erlaubt jedem Prozess ohne root Ports ab
  80. Für Staging akzeptiert; vor Production engere Lösung (z. B. nftables
  443 → hoher Port).
- Server hat noch keinen Zustand und keinen Erst-Schalter; der erste Deploy
  braucht den Schalter (root-eigen, `/etc/identity-service/`), danach von
  Hand löschen.
- Übergeordneter Ordner von `RELEASES_DIR` wird nicht geprüft; Schutz über
  `StateDirectory` unter `/var/lib` (4d-3b).
- Jede Skript-Änderung erzeugt drei neue Image-Versionen und eine Freigabe;
  verschärft den Bedarf an einer Aufbewahrungsregel für GHCR.
- Veröffentlicht, nicht ausgerollt (Stand 24.11.2026): Images von `a566d93`
  (siehe 6.1); `deploy/staging.json` zeigt weiter auf `768bbb4`.
- Nachtrag ADR-017 für E-5-170 bis E-5-178; ADR-015, ADR-016, ADR-017 auf
  „Akzeptiert“ (Ownerin).
- `.claude/rules/lieferkette-und-ci.md` und `skripte.md`: zusätzlich
  `fetch-release.sh`, `lib/release-state.sh`, `test-release-state.sh`,
  `test-package-private.sh` nachtragen (Ownerin).
- Lokale Branches löschen (Freigabe nötig): `feat/server-release-verification`,
  `docs/adr-017-addendum`, `fix/releases-dir-permissions`,
  `feat/package-private-check-server`, `docs/sitzung-31` und die Listen aus
  Bericht 30 und 31.
- Lokal: SSH-Signaturen erscheinen als `%G? = U` (kein `allowedSignersFile`);
  GitHub prüft gegen den hinterlegten Schlüssel.
- Erster automatischer Lauf des Zertifikats-Timers (24.11.2026 00:48) nicht
  im Journal abgelesen.

**Aus Sitzung 31 und früher, weiter offen**

- Agenten-Token läuft am 23.12.2026 13:10 UTC ab; Erinnerung ab etwa
  16.12.2026.
- **GHCR-Token (Maschinenkonto) läuft jetzt am 23.01.2027 ab** (vorher
  28.01.2027); Erinnerung ab etwa 09.01.2027.
- Lokale Zertifikate laufen am 31.01.2027 12:46 UTC ab; Erinnerung ab etwa
  24.01.2027.
- Repository-Sichtbarkeit war in Sitzung 31 kurz privat:
  Sicherheitsfunktionen (Secret Scanning, Push Protection, Dependabot
  Alerts, Code Scanning) nicht einzeln geprüft.
- Bundles ohne Nachweis (`e48e4ad4…6a8c`, `5a1ae60a…a554`); Aufbewahrungsregel
  für GHCR fehlt.
- Erneuerungs-Timer alarmiert nur einmal; in 4d das Zertifikat der laufenden
  API prüfen.
- API-Image: sechs Medium-Lücken in `libc6` (unter der Gate-Schwelle);
  Bot-PRs (aspnet-Digest, distroless) vor dem Merge lesen.
- Entscheidung zum Beginn von Phase 5 offen.
- E-5-128 nicht umgesetzt; `dependabot.yml`: SDK-Hauptversionen ignorieren.
- „Manage Actions access“: Write statt Admin nicht belegt.
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy.
- Kestrel-Neuladen auf dem Server, nginx und alte TLS-Sitzungen nach
  Zertifikatswechsel nicht gemessen.
- Server: `PermitRootLogin`, `unattended-upgrades`, Docker 29.9.2, runc
  1.5.2, Journal-Frist, NTS, `nft-rollback.service`; `user: "1654:1654"` in
  `compose.staging.yaml`; Units von host-health-check nicht im Repository;
  Update-Weg von `gh` auf dem Server (2.103.3, neuestes 2.105.0).
- Lokales `gh` 2.102.0 unter der Mindestversion 2.103.3.
- Lokal installierte SDKs 10.0.303 und 11.0.100 unbenutzt.
- CI-Job für Exit-Pfade der übrigen Bash-Skripte (jetzt vorhanden für
  `push-image.sh`, `verify-release-file.sh`, `fetch-release.sh`,
  `verify-package-private.sh`).
- CA-Wechsel vor dem 28.10.2027.

**Bekannte Grenzen**

- Dass Run-IDs steigen, ist beobachtet, nicht dokumentiert; bräche das,
  lehnt der Server neue Freigaben ab (fail closed).
- Der erste Deploy vertraut ohne Vergleich (Erst-Schalter).
- Ein klassisches Token gilt für alles, was das Maschinenkonto lesen darf;
  die Begrenzung liegt im Konto.
- Domain, Server-IPs, Hostnamen und Benutzernamen stehen bewusst nicht in
  diesem Bericht (ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Freigabe vom PR bis zum Server geprüft und am
Server belegt; Deploy selbst und Units fehlen.

| Nr. | Schritt | Stand |
|---|---|---|
| 1 | Staging-Konfiguration | erledigt |
| 2 | Interne CA | erledigt bis auf API-Neustart (E-5-120 gemessen, Umsetzung 4d-3c) |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer | Ports freigegeben (gemessen); `server_name`-Datei und erstes Zertifikat offen |
| 4 | Maschinenkonto, Leserecht | erledigt; Leserecht auf `identity-service-release` gemessen |
| 5 | Pull-Deploy: ~~4a, 4b, 4c, 4d-1, 4d-2~~; **4d-3a, 4d-3b, 4d-3c offen** | Frist 27.12.2026 |
| 6 | Freigabe vor dem Deploy, DORA-Ereignisse | Nachweis fertig, DORA offen |
| 7 | DAST (OWASP ZAP) | nach 5 und 6 |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: keine neue Abhängigkeit; Token-Typ klassisch mit kleinstem Scope (E-5-168) |
| **A01 / Zugriff** | Erst-Schalter root-eigen und nicht schreibbar; `RELEASES_DIR` ohne Fremd-Schreibrecht; Restart-Unit für fremde Benutzer gesperrt (gemessen) |
| **A10 / fail closed** | kaputter Zustand, Downgrade, schreibbarer Ordner, fehlendes Vergleichspaket: jeweils Abbruch |
| **Secrets (6.3.3)** | Token nur per `read -s` und temporärem `DOCKER_CONFIG`; veraltetes Token im Credstore gefunden |
| **Image-Gate** | grün für API, nginx, lego |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | nicht ausgelöst |
| **DAST** | fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | ausgelöst seit Sitzung 7; Timeouts je Netzaufruf in `fetch-release.sh` |
| **mTLS, Contract Testing, Feature Flags, Mutation Testing, k6** | nicht fällig (Mutations-Gegenproben von Hand, kein Stryker) |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (24.11.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| `identity-service-release:staging` | `sha256:78efc84c044c8aea4daa58de994d0ceacfe94f6b204f2f7a316f8cc4a85c22cd` (Run `45437830490`, Commit `a566d93`) | Release-Lauf |
| Bundle nach #165 | `sha256:329bdd341c6d91b93dad56f68799be375b711184a3c5c6db059b6152c6adeb88` (Run `45428174452`, Commit `e5eab9d`) | Release-Lauf |
| Freigabe `deploy/staging.json` | unverändert: Digests von `768bbb4` (siehe Bericht 31) | Fakten der Release-Läufe |
| Images nach #168 (veröffentlicht, nicht ausgerollt) | API `dc2ce2535433dfd8f843f965d32319fe97d69619b128cf7369979daa6209ff5a`, nginx `822f74e1927182cb460bdc6b0ac43f43e072ba9b292a3361b11dbb8e85c634e4`, lego `beaf918a51cdc374c50234d60e95adc48fd7dba51175893c15b637b383a9512b` | Publish-Läufe |
| `PUBLIC_COUNTER_PACKAGE` | `ghcr.io/anchore/grype` (anonym 200) | Token-Endpunkt |
| GHCR-Token Maschinenkonto | klassisch, `read:packages`, Ablauf 23.01.2027 | Ownerin |
| `main` nach der Sitzung | `a566d93` | `git log` |

### 6.2 Skripte und Exit-Codes (neu oder geändert)

| Skript | 0 | 2 | 3 | 4 / 5 | 6 |
|---|---|---|---|---|---|
| `fetch-release.sh STATE SWITCH RELEASES_DIR NGINX_DOCKERFILE` | `release<TAB>…` mit `decision` deploy/first/noop | Voraussetzung, Parameter, Schalter, Rechte von `RELEASES_DIR` | Nachweis/Fakten, Bundle-Inhalt | von `verify-release.sh` | Downgrade-Regel lehnt ab |
| `verify-package-private.sh IMAGE [PUBLIC]` | 401, Gegenprobe 200 | Parameter, curl, Registry nicht erreichbar | nicht 401 | 4: Gegenprobe nicht 200 | – |

Ausgabe von `fetch-release.sh`: `decision`, `dir`, `run`, `attempt`,
`commit`, `subject`, `api`, `nginx`, `lego` (in dieser Reihenfolge).

### 6.3 Läufe als Belege

| Zweck | Lauf |
|---|---|
| CI #165 (79 Fälle) | `45427585109` |
| Release nach #165 | `45428174452` |
| CI #167 (83 Fälle) | `45434696424` |
| CI #168 (23 Fälle) | `45437206613` |
| Release nach #168 | `45437830490` |

### 6.4 Server: gemessen

| Gegenstand | Wert |
|---|---|
| Deploy-Benutzer | UID 1001, rootless Docker, `/run/user/1001/docker.sock` |
| Admin-Benutzer | UID 1000, kein `~/.docker`, kein Docker |
| Port-Grenze | `ip_unprivileged_port_start = 80` |
| Units | nur Zertifikats-Service und -Timer |
| Container | keine |

### 6.5 Fallstricke, die Zeit gekostet haben

- Fein abgestuftes Token für GHCR: Login grün, Pull rot.
- Shell unbemerkt geschlossen: `id -u` = 1000, `docker logout` lief gegen
  die Konfiguration des Admin-Benutzers (harmlos, leer). Seitdem Bedingungen
  im Befehl.
- `facts | head -n 6` → Exit 141 unter `pipefail`.
- `mkdir -m 0700` scheitert unter Git Bash; `chmod` wirkt dort nicht.
- Kopierte MSYS-Programme in einem leeren `PATH` finden ihre DLLs nicht.
- Erwarteter Grund „Downgrade“ zu ungenau (stand auch in der ALARM-Zeile).
- `ExecMainExitTimestamp` leer trotz Lauf.

### 6.6 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Leserecht | offener Punkt aus 31 | `docker pull …release@sha256:…` | gelingt mit klassischem Token |
| Bundle | scratch ohne Befehl | `docker create … /nonexistent`, `docker cp` | byte-gleich, 0644 |
| 4c | Downgrade-Schutz | `fetch-release.sh` | Exit 6 / `deploy` am Server |
| 4d-1 | untergeschobener Ordner | `stat -c '%a'`, `8#022` | 4 Fälle in der CI |
| 4d-2 | Server ohne `compose.scan.yaml` | `verify-package-private.sh IMAGE PUBLIC` | 23 Fälle, echter Lauf |
| E-5-120 | Neustart aus der Zertifikats-Unit | `systemd-run … systemctl start`, `journalctl -u` | erlaubt; fremder Benutzer abgelehnt |

---

# Roadmap Sitzung 33

## 1. PR 4d-3a: Deploy-Skript (Vorschau, dann Code)

Warum zuerst: fristgebunden (27.12.2026), alle Bausteine darunter sind
gemergt und gemessen (`fetch-release.sh`, `verify-package-private.sh` mit
`PUBLIC_COUNTER_PACKAGE`, `verify-attestations-server.sh`, E-5-120).
Bausteine:

- `scripts/deploy-staging.sh`: `flock`; vier Pakete auf Sichtbarkeit;
  `fetch-release.sh` (bei `noop` Ping und Ende); `NGINX_DOCKERFILE` nach
  E-5-177; Prüf-Gate der drei Images; Pull per Digest mit Vergleich;
  `compose up -d` mit den Umgebungsvariablen aus `compose.staging.yaml`;
  Health über nginx; Rückweg nach E-5-175; `current` atomar; Zustand per
  `release_state_render` atomar; Ping.
- Token aus `LoadCredential` → `config.json` im `RuntimeDirectory`
  (E-5-174), Zeilenende entfernen.
- Test mit Ersatz für docker, compose, curl und die Prüfskripte; Fälle für
  jeden Exit-Pfad, Rückweg, `noop`, `first`.
- Zuerst Vorschau (Aufruf, Schritte, Exit-Codes, Testfälle), Code erst nach
  Freigabe.

## 2. PR 4d-3b: Units, Timer, Installation

Warum: macht 3a lauffähig. Deploy-Unit nach E-5-112, E-5-118, E-5-134,
E-5-176; Timer nach E-5-173; Installationsanleitung mit Gegenproben
(root-eigen unter `/usr/local/lib/identity-service/`, Credstore-Token
ersetzen, Erst-Schalter, `StateDirectory`).

## 3. PR 4d-3c: Restart-Unit und `restart_api`

Warum: schließt E-5-120/E-5-178; `restart_api` in
`scripts/renew-api-certificate.sh` ist noch ein Platzhalter (`return 1`).

## 4. Rest von Schritt 3

Datei mit `server_name`, erstes lego-Zertifikat; Voraussetzung für den
ersten echten `compose up`.

## 5. Nachtrag ADR-017 (E-5-170 bis E-5-178)

Warum: die Entscheidungen zu 4d sollen festgehalten sein, bevor 3b sie
installiert.

## 6. Entscheidung zum Beginn von Phase 5

Optionen aus Bericht 31: Plan einhalten (4d, Schritt 3, DORA), Phase 5 nach
4d mit ADR-Nachtrag, oder STRIDE-Konzeptarbeit parallel.

## 7. Kurze Punkte der Ownerin

- ADR-015, ADR-016, ADR-017 auf „Akzeptiert“
- `.claude/rules/*.md` nachziehen (siehe Offene Punkte)
- Sicherheitsfunktionen des Repositorys nach dem Sichtbarkeitswechsel
  kontrollieren
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy
- Gemergte lokale Branches löschen
- Bericht 32 ins Repository (Branch `docs/sitzung-32`)

## 8. Zurückgestellt, nicht aufgehoben

- E-5-128, E-5-129; `dependabot.yml` SDK-Hauptversionen
- Aufbewahrungsregel für GHCR (jetzt drei Images je Skript-PR)
- Server-Härtung; Update-Weg von `gh`; engere Port-Freigabe vor Production
- Telemetrie von `gh` in der CI abschalten
- „Manage Actions access“: Write statt Admin belegen
- CA-Wechsel vor dem 28.10.2027; vor Production: NTS, IPv6, zweiter
  Warnkanal, HSTS

## 9. Vor oder in der Sitzung zu verstehen (vor Code)

- **Punkt ohne Wiederkehr:** Alles vor `compose up` ändert nichts am
  laufenden Stand. Erst danach gibt es einen Rückweg, und Zustand und
  `current` werden erst nach erfolgreicher Health-Prüfung geschrieben.
- **Atomar schreiben:** Zustand und `current` entstehen als temporäre Datei
  bzw. temporärer Link im selben Ordner und werden per `mv -T` ersetzt; ein
  Absturz hinterlässt nie eine halbe Datei.
- **Token nur zur Laufzeit:** `LoadCredential` legt das Token in einen nur
  für die Unit sichtbaren Ordner; `config.json` im `RuntimeDirectory`
  verschwindet mit dem Ende der Unit.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Server prüft Freigabe](https://claude.ai/artifact/RRxxnqgjG4HpNVckhrYSyK)

## 10. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- SSH-Zugang zum Server bereithalten; Server-Befehle in einer Root-Shell
  (`sudo -i`, dann `id -u`)
- Neues klassisches GHCR-Token für das Überschreiben des Credstore griffbereit
  im Passwort-Manager
- Erinnerungen: Agenten-Token vor dem 23.12.2026, GHCR-Token vor dem
  23.01.2027, lokale Zertifikate vor dem 31.01.2027
