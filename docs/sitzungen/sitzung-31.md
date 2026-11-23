# Sitzungsbericht Sitzung 31

**Datum:** 23.11.2026
**Phase:** Schritt 5 (CD): Pull-Deploy neu entschieden (ADR-017, Freigabe-
Nachweis per Sigstore statt git/gpg); Freigabe-Datei (4a), Refactor
`push-image.sh` und Release-Workflow (4b) gemergt und belegt; `staging` zeigt
auf die erste signierte Freigabe. Offen: 4c (Server-Prüfung der Freigabe) und
4d (Deploy-Skript, Units), Frist 27.12.2026
**Vorgänger:** sitzung-30.md (abgeschlossen 23.11.2026)

---

## 1. Erledigt

| PR | Titel | Merge |
|---|---|---|
| #159 | `docs(adr): add ADR-017 pull deploy to staging` | `1e8de8c` |
| #160 | `docs(sitzungen): add session 30 report` | `a4836e5` |
| #161 | `feat(deploy): add staging release file with format check` | `0821d4f` |
| #162 | `refactor(scripts): extract image push into push-image.sh` | `dd43300` |
| #163 | `ci(release): add staging release workflow with release attestation` | `b5692ac` |

Alle von der Projekt-Ownerin per Squash gemergt, überwiegend KI-erzeugt, kein
Auto-Merge.

### 1.1 Agenten-Token erneuert (Roadmap-Punkt 1)

Fein abgestuftes Token per „Regenerate“ erneuert, Rechte unverändert, Eingabe
in eigenem Fenster. Gemessen über den Antwort-Header
`github-authentication-token-expiration`: Ablauf **23.12.2026 13:10 UTC**
(30 Tage), also **vor** der Frist 27.12.2026.

### 1.2 Aktualität (23.11.2026)

- Debian trixie: `git` 1:2.47.3-0+deb13u1 mit sechs offenen Lücken aus dem
  Git-Release vom 10.11.2026 (CVE-2026-111760, -113408, -114467, -114469,
  -105437, -114466), ohne Debian-Fix; `gnupg2` 2.4.7-21+deb13u1 mit vier
  offenen Lücken ohne DSA (darunter CVE-2025-68972, signierte Nachrichten);
  `gpgme1.0` CVE-2026-129975 in trixie behoben; `jq` 1.7.1-6+deb13u4 ohne
  wichtige offene Lücke.
- CISA KEV (Katalog 2026.11.20, 1790 Einträge): für git nur CVE-2025-48384
  (in trixie behoben), für gnupg und jq nichts.
- Quellcode `cli/cli` (v2.103.3 und v2.105.0 gleich): Meldung bei falschem
  Predicate-Typ `no attestations found with predicate type: <typ>`
  (`pkg/cmd/attestation/api/attestation.go`).
- `actions/attest` am gepinnten SHA `1e69f48…` kennt `predicate-type` und
  `predicate-path` (Primär-Repo).

### 1.3 Entscheidung Option C: Freigabe-Nachweis statt git/gpg (E-5-142 bis E-5-149)

Statt `git` und `gpg` auf dem Server (E-5-111/E-5-113 alt) bringt ein
signiertes Bundle aus GHCR Freigabe und Konfiguration auf den Server. Der
Server prüft mit dem vorhandenen `gh`. Begründung: zehn offene Lücken in
git/gnupg2, fünftes Netzziel `github.com`, und die Web-Flow-Signatur bindet
an kein bestimmtes Repository. Festgehalten in **ADR-017** (#159, Status
„Vorgeschlagen“); ADR-011 verweist für E-5-23 und E-5-25 auf ADR-017.

### 1.4 Server-Messungen (Deploy-Benutzer, rootless Docker, temporärer `DOCKER_CONFIG`, Platzhalter-Token)

| Messung | Ergebnis | Gegenprobe |
|---|---|---|
| `gh attestation verify oci://…:<tag> --bundle-from-oci` | löst den Tag selbst auf, nennt den geprüften Digest als `subject` | `63a1ae6e…d6a8` = API-Image von `768bbb4` (Bericht 30) |
| `runInvocationURI` im JSON | `…/actions/runs/45177231370/attempts/1` | Run = `Publish` nach #158 (Bericht 30) |
| Telemetrie aus | keine `device-id` angelegt | nur ein Lauf, keine gezielte Gegenprobe |
| Docker-Socket des Deploy-Benutzers | vorhanden seit 19.11.2026 04:00 | erst als root sichtbar (siehe 6.5) |

Aufgeräumt: Arbeitsordner und temporäre Registry-Anmeldung gelöscht.

### 1.5 PR 4a: Freigabe-Datei und Formatprüfung (#161)

- `deploy/staging.json` mit den Digests von `768bbb4`, gegengeprüft gegen die
  Zeile `Veröffentlicht:` der drei Publish-Läufe (`45177231370`,
  `45177231435`, `45177231313`).
- `scripts/lib/release-rules.sh` (`RELEASE_RULES`),
  `scripts/verify-release-file.sh` (Exit 0/2/3), `scripts/test-release-file.sh`
  (33 Fälle), Schritte im Pflicht-Job `Container & nginx`, `/deploy/` in
  CODEOWNERS.
- CI: alle 33 Fälle `ok`. `Image-Scan` war zunächst rot (Download der
  Grype-Datenbank: `unexpected EOF`, Exit 2, fail closed); nach „Re-run
  failed jobs“ grün, Blindheits-Schutz und Gate bestanden (Lauf
  `45192149363`).

### 1.6 Refactor `push-image.sh` (#162)

- Eine Quelle statt drei Kopien in `publish*.yml`; strengerer Digest-Regex,
  exakter Namensvergleich, Tag `latest` verboten, Exit 2/3.
- `scripts/test-push-image.sh` mit docker-Ersatz (20 Fälle), lokal und in CI
  grün; Gegenprobe mit eingebauten Fehlern: 4 bzw. 1 Fall rot.
- Nach dem Merge: `Publish` `45198313610`, `Publish nginx` `45198313772`,
  `Publish lego` `45198313869` in jedem Schritt grün; der Digest aus
  `docker push` gleicht in allen drei Läufen dem Digest aus `push-image.sh`;
  CI-Gate 6/6 und Server-Prüfung 3/3 Gegenproben, Pakete privat (401).

### 1.7 PR 4b: Release-Workflow (#163)

- `.github/workflows/release-staging.yml`, `scripts/verify-release.sh`
  (Server-Bedingungen, 4 Gegenproben), `scripts/build-release-bundle.sh`,
  `scripts/lib/registry-only.sh` (aus dem Server-Einstieg herausgezogen),
  Erweiterungspunkt Predicate-Typ für Gegenproben in
  `scripts/lib/attestation-rules.sh`, Abgleich Dateiliste ↔ Pfadfilter ↔
  Snippets ↔ Workflow-Werte in `test-release-file.sh`.
- Vor dem Merge: `RELEASE_FACTS` lokal mit gojq (`gh api rate_limit --jq`):
  Gutfall 7 Zeilen, 8 Rot-Fälle mit erwartetem Grund; der Test fand einen
  verlorenen Backslash im Regex. Bundle lokal gebaut (10 Dateien). In der CI
  33 + 27 Abgleich- + 9 Fakten-Fälle `ok`.
- Release-Lauf `45202570572` auf `b5692ac`:
  - Versuch 1: Abbruch an „Paket anonym nicht lesbar“ (HTTP 200, neues Paket
    öffentlich), nichts signiert. Ownerin stellte das Paket auf privat und gab
    dem Maschinenkonto Leserecht.
  - Versuch 2: Nachweis nicht speicherbar („Feature not available for
    user-owned private repositories“): Das **Repository** war versehentlich
    privat geworden. Ownerin stellte es wieder öffentlich; gemessen: `public`,
    Ruleset `main-protection` `active`, 0 Bypass, Regeln unverändert.
  - Versuch 3: alle 13 Schritte grün. Bundle
    `identity-service-release@sha256:4f6bcfb5…edf7`, Fakten Run
    `45202570572`, Versuch 3, Commit `b5692ac…`, drei Referenzen von
    `768bbb4`; 4 Gegenproben je per Digest und per Tag am erwarteten Grund
    abgelehnt; Aktualitätsschutz `main = b5692ac`; `staging` →
    `4f6bcfb5…`.
- **Gemessen:** Ein Re-run behält die Run-ID und erhöht nur den Versuch
  (Annahme aus ADR-017 belegt).

### 1.8 Lehrstoff

- [Lehrstoff: Signierte Freigabe statt git auf dem Server](https://claude.ai/artifact/L7tfc8ZPCCsLvGfNx3yfW6)
  (Paket als Angriffsfläche, Bindung von Signaturen, doppelte Schlüssel,
  Release-Ablauf mit Diagramm, Downgrade über Run-ID, jq/gojq, Gegenproben,
  Fallen, Spickzettel)

---

## 2. Gelernt

- Die Web-Flow-Signatur von GitHub bindet an kein Repository; ein
  Sigstore-Nachweis aus einem Workflow bindet an Repository, Kennungen,
  Workflow, Branch, Commit und Lauf.
- `gh attestation verify` löst einen Tag selbst über die Registry auf und
  nennt den geprüften Digest als `subject`; ab dann darf nur noch dieser
  Digest verwendet werden.
- Ein Re-run eines GitHub-Workflows behält die Run-ID; nur `attempts/<n>`
  steigt.
- jq nimmt bei doppelten JSON-Schlüsseln still den letzten Wert; eine
  kanonische Form (Datei = `jq .`) macht das sichtbar.
- jq gibt bei leerer Eingabe weder Ausgabe noch Fehler aus (Exit 0).
- gojq (in `gh`) versteht `def` nach einer Pipe; lokal testbar mit
  `gh api rate_limit --jq 'EINGABE | PROGRAMM'`.
- Bei einem Fehler in einem jq-Programm können vorher schon Zeilen ausgegeben
  sein; Ausgabe nur bei Exit 0 verwenden.
- `gh` schreibt seine Meldungen („Loaded digest …“) nach stderr; mit `2>&1`
  geraten sie in eingefangene Daten.
- Neue GHCR-Pakete aus diesem Repository starten öffentlich (zum vierten Mal
  gemessen); `verify-package-private.sh` fängt es vor dem Signieren.
- Artifact Attestations funktionieren nicht in privaten Repositorys eines
  persönlichen Kontos ohne bezahlten Plan.
- Ein Glob-Pfad in einem fremden Verzeichnis mit 0700 meldet „No such file“,
  nicht „Permission denied“.
- In der Bash ist `<wort>` eine Umleitung; großgeschriebene Platzhalter werden
  wörtlich übernommen. `read -r -p` vermeidet beides.
- Docker Desktop unter Windows überträgt Dateirechte aus dem Build-Kontext
  nicht (lokal `rwxr-xr-x` statt `0644`).
- `docker create` plus `docker export` enthält Laufzeit-Dateien
  (`.dockerenv`, `dev/`, `etc/`, `proc/`, `sys/`), die nicht im Image stehen.
- Der Download der Grype-Datenbank kann abbrechen; das Skript endet dann
  korrekt mit Exit 2.
- Ein Heredoc kann beim Weiterreichen durch Werkzeuge Backslashes verlieren;
  danach die geschriebene Datei prüfen.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-142** | Paketfrage `git`, `jq`, `gpg`: kein neues Paket auf dem Server | gelöst durch E-5-143/E-5-144 |
| **E-5-143** | `jq` wird auf dem Server nicht installiert; JSON nur über `gh --jq` | Bibliothek nutzt bereits `gh --jq` |
| **E-5-144** | Freigabe-Nachweis per Sigstore statt Commit-Signatur; ersetzt den git/gpg-Teil von E-5-113 | 10 offene Lücken, fünftes Netzziel, schwache Bindung der Web-Flow-Signatur |
| **E-5-145** | Format `deploy/staging.json` (`schema`, `environment`, drei Referenzen); eigener Predicate-Typ; Server liest Digests nur aus dem verifizierten Predicate | eine Quelle, kein unsigniertes Lesen |
| **E-5-146** | Downgrade-Schutz über die Run-ID aus `runInvocationURI` | von Fulcio gebunden; Re-run behält ID (gemessen) |
| **E-5-147** | Erst-Schalter root-eigen, für die Unit nur lesbar; ignoriert, sobald Zustand existiert | Löschrecht wäre Anlegerecht |
| **E-5-148** | PR 4 aufgeteilt: ADR, 4a, Refactor, 4b, 4c, 4d | ein Thema pro Branch |
| **E-5-149** | Konfiguration fährt im Bundle mit; ersetzt E-5-23 und E-5-25 aus ADR-011 | ohne git kein anderer signierter Weg |
| **E-5-150** | Ein jq-Programm für jq (CI) und gojq (Server), nur gemeinsamer Sprachkern | eine Quelle der Wahrheit; belegt in beiden |
| **E-5-151** | Kanonische Form als Pflicht für die Freigabe-Datei | doppelte Schlüssel, BOM, ruhige Diffs |
| **E-5-152** | Erste Freigabe mit den Digests von `768bbb4` | geprüft und am Server gemessen |
| **E-5-153** | `/deploy/` ist CODEOWNERS-pflichtig | Änderung dort ist ein Deploy |
| **E-5-154** | Release-Workflow prüft die drei Images mit dem Server-Einstieg, bevor er signiert | nur Eigenes wird freigegeben |
| **E-5-155** | Bundle = feste Dateiliste `RELEASE_FILES`; nur Daten, keine Skripte; `FROM scratch` | Release bringt keinen eigenen Prüfer mit |
| **E-5-156** | Nur der aktuelle Stand von `main` darf `staging` setzen | Re-run alter Läufe |
| **E-5-157** | CI prüft: Run-ID und Commit im Zertifikat = dieser Lauf; Prüfung per Digest und per Tag | Weg des Servers wird bei jedem Release belegt |
| **E-5-158** | `scripts/push-image.sh` als einzige Push- und Digest-Logik | vierte Kopie vermieden |
| **E-5-159** | Pfadfilter des Release-Workflows plus automatischer Abgleich mit `RELEASE_FILES` | keine Drift ohne neue Freigabe |
| **E-5-160** | `docker/nginx/Dockerfile` gehört ins Bundle | Quelle der Gegenprobe am Server (E-5-132) |
| **E-5-161** | Erwartete Werte, Mindestversion und Platzhalter in `scripts/lib/registry-only.sh` | zwei Server-Einstiege, eine Quelle |
| **E-5-162** | Predicate-Typ für Gegenproben als Erweiterungspunkt; neue Gegenprobe „falscher Predicate-Typ“ | Gegenproben sonst am falschen Grund |

ADR-Kandidaten: E-5-142 bis E-5-149 stehen in ADR-017; **E-5-150 bis
E-5-162 als Nachtrag zu ADR-017** (dazu die Messung zum Re-run und die
erweiterte Dateiliste).

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Nachtrag ADR-017** (E-5-150 bis E-5-162, Re-run-Messung,
  `docker/nginx/Dockerfile` im Bundle); ADR-017 auf „Akzeptiert“ (Ownerin).
- **Agenten-Token läuft am 23.12.2026 ab**, also vor der Frist 27.12.2026;
  Erinnerung ab etwa 16.12.2026.
- **Repository-Sichtbarkeit war kurz privat:** Squash-only, Auto-Merge aus,
  Sicherheitsfunktionen (Secret Scanning, Push Protection, Dependabot Alerts,
  Code Scanning) nach dem Zurückstellen nicht einzeln geprüft.
- Leserecht des Maschinenkontos auf `identity-service-release` gesetzt
  (Ownerin), aber noch nicht vom Server aus gemessen (Teil von 4c).
- Bundles ohne Nachweis im Paket: `e48e4ad4…6a8c` (Versuch 1),
  `5a1ae60a…a554` (Versuch 2); fallen unter die fehlende Aufbewahrungsregel.
- Dateirechte im Bundle auf dem Linux-Runner (`0644`) nicht abgelesen; der
  Server setzt sie in 4c selbst.
- Erneuerungs-Timer alarmiert nur einmal: Am Tag nach einer Erneuerung meldet
  er „noch gültig“, obwohl die laufende API das alte Zertifikat nutzt. In 4d
  das Zertifikat der laufenden API prüfen.
- Release-Läufe entstehen auch, wenn Dependabot `docker/nginx/Dockerfile`
  ändert (Pfadfilter); bewusst akzeptiert, DORA zählt sie mit.
- `.claude/rules/lieferkette-und-ci.md` und `skripte.md`: `push-image.sh`,
  `release-staging.yml`, `verify-release.sh`, `build-release-bundle.sh`,
  `lib/registry-only.sh`, `lib/release-rules.sh` nachtragen (Ownerin).
- API-Image enthält sechs Medium-Lücken in `libc6` 2.39-0ubuntu8.9 mit Fix
  2.39-0ubuntu8.12 (unter der Gate-Schwelle); neuer aspnet-Digest erwartet,
  Bot-PR vor dem Merge lesen.
- Frage der Ownerin, wann Phase 5 beginnt: Optionen vorgelegt (Plan halten,
  Phase 5 nach 4d, STRIDE-Konzeptarbeit parallel); Entscheidung offen.
- Lokale Branches löschen (Freigabe nötig): `docs/adr-017-pull-deploy-staging`,
  `docs/sitzung-30`, `feat/staging-release-file`, `refactor/push-image-script`,
  `ci/release-staging-workflow` und die Liste aus Bericht 30.

**Aus Sitzung 30 und früher, weiter offen**

- **Deploy-Skript und Units bis spätestens 27.12.2026** (jetzt 4c und 4d).
- GHCR-Token läuft am 28.01.2027 04:31 UTC ab; Erinnerung ab etwa 14.01.2027.
- Lokale Zertifikate laufen am 31.01.2027 12:46 UTC ab; Erinnerung ab etwa
  24.01.2027.
- E-5-128 nicht umgesetzt (Wochenlauf scannt nginx als frischen Build).
- `dependabot.yml`: SDK-Hauptversionen ignorieren.
- `verify-package-private.sh`: Pfad „Registry nicht erreichbar“ nicht gemessen.
- „Manage Actions access“: Write statt Admin nicht belegt.
- Aufbewahrungsregel für Image-Versionen in GHCR fehlt.
- ADR-015 und ADR-016 auf „Akzeptiert“; Nachträge zu ADR-015, ADR-016,
  ADR-010 (siehe Bericht 30).
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy.
- Kestrel-Neuladen auf dem Server, nginx und alte TLS-Sitzungen nach
  Zertifikatswechsel nicht gemessen.
- Erster automatischer Lauf des Erneuerungs-Timers nicht abgelesen.
- Server: `PermitRootLogin`, `unattended-upgrades`, Docker 29.9.2, runc 1.5.2,
  Journal-Frist, NTS, `nft-rollback.service`; `user: "1654:1654"` in
  `compose.staging.yaml`; Units von host-health-check nicht im Repository;
  Update-Weg von `gh` auf dem Server (2.103.3, neuestes 2.105.0).
- Lokales `gh` 2.102.0 unter der Mindestversion 2.103.3.
- Lokal installierte SDKs 10.0.303 und 11.0.100 unbenutzt.
- CI-Job für Exit-Pfade der übrigen Bash-Skripte (für `push-image.sh` und
  `verify-release-file.sh` jetzt vorhanden).
- CA-Wechsel vor dem 28.10.2027.

**Bekannte Grenzen**

- Dass Run-IDs steigen, ist beobachtet, nicht dokumentiert; bräche das,
  lehnt der Server neue Freigaben ab (fail closed).
- Zwischen Aktualitätsschutz und Tag `staging` bleibt ein Zeitfenster von
  Sekunden; dafür gilt die Downgrade-Regel am Server.
- Der erste Deploy vertraut ohne Vergleich (Erst-Schalter).
- Der Platzhalter für `gh` beruht auf nicht dokumentiertem Verhalten.
- Domain, Server-IPs, Hostnamen und Benutzernamen stehen bewusst nicht in
  diesem Bericht (ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Freigabe-Weg von PR bis Tag `staging` belegt;
Server-Seite fehlt.

| Nr. | Schritt | Stand |
|---|---|---|
| 1 | Staging-Konfiguration | erledigt |
| 2 | Interne CA | erledigt bis auf API-Neustart (E-5-120, 4d) |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer | offen |
| 4 | Maschinenkonto, Leserecht | erledigt; Leserecht auf `identity-service-release` gesetzt, nicht gemessen |
| 5 | Pull-Deploy: ~~Ablauf, Prüfregeln, Messungen, 3b, ADR-017, 4a, 4b~~; **4c, 4d offen** | Frist 27.12.2026 |
| 6 | Freigabe vor dem Deploy (jetzt Freigabe-Nachweis), DORA-Ereignisse | Nachweis fertig, DORA offen |
| 7 | DAST (OWASP ZAP) | nach 5 und 6 |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: keine neue Abhängigkeit (Pakete verworfen, `actions/attest` bereits gepinnt, `FROM scratch`); Release-Workflow signiert nur geprüfte eigene Images |
| **A01 / Zugriff** | Pakete privat (401, auch `identity-service-release`); Repository kurz privat, Ruleset danach `active`, 0 Bypass |
| **A10 / fail closed** | öffentliches Paket, privates Repository, fehlende Scanner-Datenbank: jeweils harter Abbruch, nichts signiert |
| **Secrets (6.3.3)** | Token nur über stdin und temporären `DOCKER_CONFIG`; `gh` in Prüfschritten nur mit Platzhalter; Agenten-Token im Chat nie sichtbar |
| **Image-Gate** | grün für API, nginx, lego |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | nicht ausgelöst |
| **DAST** | fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | ausgelöst seit Sitzung 7; Timeouts je Netzaufruf |
| **mTLS, Contract Testing, Feature Flags, Mutation Testing, k6** | nicht fällig |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (23.11.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| Freigabe `deploy/staging.json` | API `63a1ae6e173e43cd5a2ff9a9ab817d7da0efa4f1700d36c2dcfe0a94887ed6a8`, nginx `df0163508f6836f314c81014234f54b69385b4148735c48417e99b76d9c7e629`, lego `55b687f90172014478983f66591ee62b634cf36d081ccb9205348ef6dadcf612` (alle `768bbb4`) | Publish-Läufe |
| `identity-service-release:staging` | `sha256:4f6bcfb5a44c3d1467a3609168e11a015ccfcb9668cde0df25aa2eb732c8edf7` (Run `45202570572`, Versuch 3, Commit `b5692ac`) | Release-Lauf |
| Predicate-Typ der Freigabe | `https://github.com/xXxCoder999xXx/identity-service/release/v1` | `release-rules.sh` |
| Images nach #162 (`dd43300`) | API `b77af10f20da988da3032271d7d5a19035b6274c7392e13b258db1123ebfc51c`, nginx `e885f5fbbdecfe6b9d13ef54efcf57d2dcc72a383a62f2b340b3b248be19ff61`, lego `fe2fbea6ed6c0632c9b5d3f57d19e0aff02ca619c00febd768753dd9e5587436` | Publish-Läufe |
| `actions/attest` | `1e69f48acb82d1966a394da916b4c1698aa569d6` (v4.2.2) | bestehender Pin, Eingaben im Primär-Repo gelesen |
| Agenten-Token | Ablauf 2026-12-23 13:10:46 UTC | Antwort-Header |
| Repository-ID / Besitzer-ID | `1296648545` / `291064355` | unverändert |
| Ruleset | `main-protection` (ID `19061452`), `active`, 0 Bypass | API |
| `main` nach der Sitzung | `b5692ac` | `git log` |

### 6.2 Neue Skripte und Exit-Codes

| Skript | 0 | 2 | 3 | 4 / 5 |
|---|---|---|---|---|
| `verify-release-file.sh DATEI` | gültig, drei Referenzen auf stdout | Parameter, Datei, jq | Inhalt ungültig | – |
| `push-image.sh LOCAL NAME TAG` | Digest auf stdout | Parameter, docker, lokales Image | Push, Digest | – |
| `build-release-bundle.sh LOCAL` | gebaut | Parameter, docker, Bibliothek | Datei fehlt/Link, Build | – |
| `verify-release.sh REF DOCKERFILE` | verifiziert, Fakten `freigabe<TAB>schluessel<TAB>wert` | Parameter, gh, Bibliothek | Nachweis/Fakten | Gegenprobe akzeptiert / falscher Grund |

`RELEASE_FILES`: `deploy/staging.json`, `compose.yaml`, `compose.staging.yaml`,
`nginx.staging.conf`, `nginx/snippets/{http-common,limits,proxy-api,security-headers,tls}.conf`,
`docker/nginx/Dockerfile`.

### 6.3 Läufe als Belege

| Zweck | Lauf |
|---|---|
| #161, Image-Scan nach Re-run | `45192149363` |
| nach #162 | Publish `45198313610`, Publish nginx `45198313772`, Publish lego `45198313869` |
| Release Staging (Versuche 1–3) | `45202570572` |

### 6.4 Server: gemessen

| Gegenstand | Wert |
|---|---|
| Deploy-Benutzer | UID 1001, Linger aktiv, Socket `/run/user/1001/docker.sock` seit 19.11.2026 04:00 |
| Prüfung per Tag | `gh` 2.103.3 löst auf, `subject` = geprüfter Digest |

### 6.5 Fallstricke, die Zeit gekostet haben

- Shell lief nicht als root: Glob in `/run/user/*/` meldete „No such file“,
  daraus voreilig „Daemon läuft nicht“ geschlossen. Jeder Server-Block
  beginnt mit `id -u`.
- Platzhalter `<deploy>` und `DEPLOYNAME` in Server-Befehlen: Umleitung bzw.
  wörtlich übernommen. Stattdessen `read -r -p`.
- Git Credential Manager hielt das Agenten-Token: Push mit Workflow-Änderung
  abgelehnt; `git credential-manager github logout` und `login --browser`.
- Repository versehentlich privat beim Umstellen der Paket-Sichtbarkeit.
- Heredoc verlor einen Backslash im jq-Regex; nur der gojq-Test fand es.
- `python -` ohne Eingabe hängt bis zum Zeitlimit.
- Eine Mutations-Gegenprobe veränderte wegen eines `sed`-Fehlers nichts und
  war grün; leerer Diff als Warnsignal.

### 6.6 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Token | Agent braucht Lesezugriff | Regenerate, `gh auth login` | Ablauf 23.12.2026 |
| Recherche | Paketentscheidung | Debian-Tracker, KEV | git 6, gnupg2 4 offene Lücken |
| Messung | Option C tragfähig? | `gh attestation verify oci://…:TAG --bundle-from-oci` | Tag aufgelöst, Run-ID im JSON |
| 4a | Freigabe vor dem Merge prüfen | `verify-release-file.sh` | 33 Fälle |
| Refactor | eine Push-Logik | `push-image.sh` | 3 Publish-Läufe grün, Digests gleich |
| 4b | Freigabe signieren | `release-staging.yml` | `staging` → `4f6bcfb5…`, 4 Gegenproben |

---

# Roadmap Sitzung 32

## 1. PR 4c: Server prüft die Freigabe (Konzept, dann Code)

Warum zuerst: fristgebunden (27.12.2026), und `verify-release.sh` ist schon
unter Server-Bedingungen belegt; 4c ergänzt nur Zustand, Downgrade-Regel und
Erst-Schalter. Bausteine:

- Messen am Server: Maschinenkonto zieht `identity-service-release` per
  Digest; `verify-release.sh …:staging` mit Platzhalter-Token.
- Zustand im `StateDirectory` (Run-ID, Commit, Bundle-Digest), Regeln aus
  ADR-017, Erst-Schalter root-eigen unter `/etc/identity-service/`.
- Dateien aus dem Bundle: nur `RELEASE_FILES`, per `docker create` und
  `docker cp`, Rechte selbst setzen, jede Abweichung bricht ab.
- Rot-Beweis am Server: gespeicherte Run-ID höher als die Freigabe →
  Abbruch.

## 2. PR 4d: Deploy-Skript, Units, Restart-Unit

Warum: schließt den Pull-Deploy und `restart_api` vor der ersten
Zertifikatserneuerung. Bausteine: Ablauf E-5-113 (neu), Sandbox E-5-118 mit
E-5-134 und E-5-135, Restart-Unit E-5-120, Installation unter
`/usr/local/lib/identity-service/` (E-5-117), Prüfung des Zertifikats der
laufenden API statt nur der Datei.

## 3. Nachtrag ADR-017 (kleiner Doku-PR)

Warum: E-5-150 bis E-5-162 und die Re-run-Messung sollen festgehalten sein,
bevor 4c darauf aufbaut.

## 4. Entscheidung zum Beginn von Phase 5

Warum: von der Ownerin gefragt. Optionen: Plan einhalten (4c, 4d, Ports,
DORA), Phase 5 nach 4d mit ADR-Nachtrag, oder STRIDE-Konzeptarbeit für den
ersten Use Case schon jetzt parallel (ohne Code).

## 5. Kleinere Punkte

- E-5-128: Wochenlauf scannt den veröffentlichten nginx-Digest
- `dependabot.yml`: SDK-Hauptversionen ignorieren

## 6. Kurze Punkte der Ownerin

- ADR-015, ADR-016, ADR-017 auf „Akzeptiert“
- `.claude/rules/*.md` nachziehen (siehe Offene Punkte)
- Sicherheitsfunktionen des Repositorys nach dem Sichtbarkeitswechsel
  kontrollieren
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy
- Gemergte lokale Branches löschen
- Bericht 31 ins Repository (Branch `docs/sitzung-31`)
- Bot-PRs (aspnet-Digest, distroless) vor dem Merge lesen lassen

## 7. Zurückgestellt, nicht aufgehoben

- E-5-129: ungenutzte Pakete aus dem nginx-Image entfernen
- Aufbewahrungsregel für Image-Versionen in GHCR (jetzt auch Bundles ohne
  Nachweis)
- Ports 80/443 und erstes Zertifikat
- Server-Härtung; Update-Weg von `gh` auf dem Server
- Telemetrie von `gh` in der CI abschalten
- „Manage Actions access“: Write statt Admin belegen
- CA-Wechsel vor dem 28.10.2027; vor Production: NTS, IPv6, zweiter
  Warnkanal, HSTS

## 8. Vor oder in der Sitzung zu verstehen (vor Code)

- **Herkunft ist nicht Aktualität:** Ein gültiger Nachweis kann alt sein. Der
  Server vergleicht die Run-ID aus dem Zertifikat mit dem gespeicherten
  Zustand und lehnt kleinere ab; ein Re-run behält seine ID.
- **Wer löschen darf, darf anlegen:** Der Erst-Schalter gehört root und ist
  für die Unit nur lesbar. Sobald Zustand existiert, wird er ignoriert.
- **Nur Signiertes lesen:** Digests kommen aus dem verifizierten Predicate,
  Dateien nur aus dem Bundle mit geprüftem Digest und fester Liste. Eine
  zweite, unsignierte Kopie wird nie gelesen.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Signierte Freigabe statt git auf dem Server](https://claude.ai/artifact/L7tfc8ZPCCsLvGfNx3yfW6)

## 9. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- SSH-Zugang zum Server bereithalten; Server-Befehle in einer Root-Shell
  (`sudo -i`, dann `id -u`)
- Erinnerungen: Agenten-Token vor dem 23.12.2026, GHCR-Token vor dem
  28.01.2027, lokale Zertifikate vor dem 31.01.2027
