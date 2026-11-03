# Sitzungsbericht Sitzung 28

**Datum:** 03.11.2026 (begonnen 02.11.2026)
**Phase:** Schritt 5 (CD): Ablauf des Pull-Deploys entschieden (E-5-111 bis
E-5-120), Prüfregeln als Bibliothek mit zwei Einstiegen vorbereitet (PR 1,
PR 2, E-5-121, PR 3a gemergt und auf dem Runner belegt); erstes lego-Image
veröffentlicht; Server-Einstieg (3b), Deploy-Skript und API-Neustart offen
(Frist 27.12.2026)
**Vorgänger:** sitzung-27.md (abgeschlossen 30.10.2026; Bericht liegt noch
unversioniert im Arbeitsverzeichnis, siehe Offene Punkte)

---

## 1. Erledigt

| PR | Titel | Merge |
|---|---|---|
| #132 | `chore(deps): Bump goacme/lego from v5.5.2 to v5.6.0 in /docker/lego` | `b61a011` |
| #131 | `chore(deps): Bump distroless/static-debian13 from 18f4cc2 to 25ac8f0 in /docker/lego` | `2747eba` |
| #133 | `refactor(scripts): extract attestation rules into library` | `4ec5e6d` |
| #134 | `fix(scripts): require expected reason for attestation counterproofs` | `e053ec2` |
| #135 | `fix(scripts): verify repository and owner ids in attestations` | `9157441` |
| #136 | `feat(scripts): run attestation counterproofs from registry too` | `1723453` |

Alle von der Projekt-Ownerin per Squash gemergt; #133 bis #136 überwiegend
KI-erzeugt, kein Auto-Merge. In allen sechs PRs waren die fünf Pflicht-Checks
grün; rot war nur der nicht verpflichtende Check
`Image-Scan Drittanbieter (nginx)` (1.3).

### 1.1 Aktualität

- `gh` v2.103.3 weiter neuestes Release; keine neuen Advisories in `cli/cli`
  seit dem 30.10.2026; Mindestversion bleibt 2.102.0.
- Neu im Hilfetext von v2.103.3 (Quellcode `pkg/cmd/attestation/verify/verify.go`):
  Mit `--bundle`/`--bundle-from-oci` vergleicht `gh` `--repo` nur mit dem
  Namen im Zertifikat und erkennt Umbenennung oder Neuvergabe nicht. Daraus
  folgte E-5-121 (1.7).
- Offen in `dotnet/aspnetcore`: #70027 (Deadlock beim Registrieren der
  Dateiüberwachung für `Kestrel:Certificates:Default:Path`, betrifft
  10.0.13), beobachten.

### 1.2 Pull-Deploy: Ablauf entschieden (Konzept, kein Code)

E-5-111 bis E-5-120 (Tabelle in Abschnitt 3): Digest als Datei im signierten
Repository, System-Unit mit `User=deploy`, Ablauf in acht Schritten mit
Punkt ohne Wiederkehr bei `compose up -d`, Gegenprobe bei jedem Deploy,
Abbruch bei anonym lesbarem Paket, Prüfregeln als Bibliothek in drei PRs,
root-eigener Prüfer, Sandbox der Unit, Restart-Unit für die API.

### 1.3 Dependabot-PRs und nginx-Fund

- **#132 (lego v5.6.0):** Digest
  `sha256:6f1583fc026a455ea46a7a5858c576105bb69c2e2de69db391cab7f14750350c`
  gleich der Registry (02.11.2026); Release vom 28.10.2026, kein
  Vorab-Release; Inhalt überwiegend neue DNS-Anbieter (ungenutzt, HTTP-01)
  und CLI-Korrekturen; keine Sicherheitshinweise gesehen. Damit erstmals
  `Image-Scan Drittanbieter (lego)` grün.
- **Erstes lego-Image veröffentlicht:** `Publish lego` Lauf `41458560831`
  (Commit `b61a011`) grün, inklusive Prüf-Gate mit Gegenproben. Seither alle
  lego-Läufe grün.
- **#131 (distroless in `docker/lego/`):** Digest
  `sha256:25ac8f0c3b2334a9eb05452266bd4697864a8c8ef0ef71e5e6480d7f92868329`
  gleich der Registry; nach `@dependabot rebase` lego-Scan grün.
- **nginx rot auf jedem PR und auf `main`:** `nginxinc/nginx-unprivileged:1.30.6@sha256:ec0f7ecb…`
  enthält `libbrotli1 1.1.0-2+b7` mit **CVE-2026-111497** (Critical, CISA
  KEV seit 27.10.2026, Frist 10.11.2026; Fix in Debian `1.1.0-2+deb13u1`).
  Einziger Fund mit verfügbarem Fix, der das Gate auslöst (Protokoll gelesen).
  Kein neueres Image beim Herausgeber (1.30.6 und 1.30 vom 19.10.2026,
  identischer Digest).
- Vor dem Merge von #131 mit `Publish` Lauf `41632429372` belegt:
  `publish.yml` kann nach dem Abschalten der Paket-Vererbung (Sitzung 27)
  weiter pushen.

### 1.4 Messung: Kestrel lädt ein getauschtes Zertifikat lokal nicht selbst neu (E-5-119)

Lokal unter Docker Desktop, Zertifikate einer Wegwerf-CA
(`New-LocalDevCertificates.ps1 -OutputRoot … -SkipTrustStore -LeafValidityDays 1`):

| Schritt | Ergebnis |
|---|---|
| Basis | 200 |
| Dateien im Ordner-Mount getauscht (`mv` in einem Hilfscontainer, `--network none`) | weiter 200 |
| nur nginx neu gestartet | weiter 200 |
| API neu gestartet | 502, „upstream SSL certificate verify error: (21:unable to verify the first certificate)“ |
| Rückweg (Originale zurück, API-Neustart) | 200 |

Folge: Option A (eigene Restart-Unit, E-5-120). Lokal nicht repräsentativ
(Dateiereignisse über die Windows-Freigabe); auf dem Linux-Server nicht
gemessen. Danach lokale Zertifikate erneuert (CA wiederverwendet), Stack
wieder 200, Wegwerf-Ordner gelöscht.

### 1.5 PR 1 (#133): Prüfregeln als Bibliothek

- Neu `scripts/lib/attestation-rules.sh` (Konstanten, `attest_init`,
  `attest_verify_ok`, `attest_verify_must_fail`, `attest_find_foreign_image`,
  drei Gegenproben); `scripts/verify-attestations.sh` nur noch Einstieg für
  Actions; Bibliothek über den Pfad neben dem Skript geladen, nie über eine
  Umgebungsvariable; fehlt sie oder eine Funktion des Einstiegs → Exit 2.
- `publish-lego.yml`: Bibliothek im `paths`-Filter.
- Belege vorab: 6 Eingabe-Fehlerpfade, Erfolgspfad, akzeptierte Gegenprobe,
  falsche Angaben – alter und neuer Stand gleiche Exit-Codes und
  byte-gleiche Ausgabe (mit mitschreibendem `gh`-Platzhalter).
- Beleg nach dem Merge: Prüfschritt von `Publish` (`41633671098`) und
  `Publish lego` (`41633670940`) normalisiert Zeile für Zeile gleich den
  Referenzläufen `40883281498` und `41458560831` (je 42 Zeilen).

### 1.6 PR 2 (#134): Gegenproben verlangen den erwarteten Grund (E-5-114)

- `attest_verify_must_fail TITEL GRUND AUFRUF…`: Exit-Code entscheidet über
  „gescheitert“, die Meldung (ganze Zeile, erweiterter regulärer Ausdruck)
  über „aus dem richtigen Grund“. Akzeptiert → Exit 4; falscher Grund →
  **neuer Exit 5**. Hilfsfunktion `attest_ere_literal`.
- Erwartete Gründe aus dem Quellcode von `gh` (v2.102.0 und v2.103.3 gleich):
  fremdes Image `HTTP 404 … /repos/<repo>/attestations/<digest>?…`, falscher
  Workflow `verifying with issuer "…"` (schwächste Probe, belastbar durch die
  Kontrollpaarung mit `attest_verify_ok`), falscher Branch
  `expected SourceRepositoryRef to be refs/heads/not-main, got refs/heads/main`.
- Matrix gegen die echten Meldungen: nur die Diagonale besteht.
- Rot-Beweis (Platzhalter): Netzfehler, HTTP 401, TUF-Fehler bei der
  Workflow-Probe – alt Exit 0, neu Exit 5; akzeptiert 4/4.
- Nach dem Merge: `Publish` `41636900858` und `Publish lego` `41636901708`
  grün, alle Gegenproben „abgelehnt aus dem erwarteten Grund“.

### 1.7 #135: feste Kennungen von Repository und Besitzer (E-5-121)

- `ATTEST_FACTS` um `sourceRepositoryIdentifier` und
  `sourceRepositoryOwnerIdentifier` erweitert; `attest_init` nimmt 8
  Parameter (`REPO_ID`, `OWNER_ID`, nur `^[1-9][0-9]*$`); Einstieg liest
  `GITHUB_REPOSITORY_ID` und `GITHUB_REPOSITORY_OWNER_ID` (Standardvariablen
  laut GitHub-Doku `content/actions/reference/workflows-and-actions/variables.md`).
- Gemessen: Feldnamen aus `sigstore-go` v1.3.0 (`omitempty`), von `gh`
  2.102.0 und 2.103.3 verwendet. Zertifikat des Nachweises zu
  `identity-service@sha256:e99a654f5f83452991afeb9811ceea5ea5c252002d9dc50c14609ab8d374e24f`:
  OID `…57264.1.15` = `1296648545`, `.17` = `291064355`, gleich den Werten
  der API.
- Rot-Beweis: gleicher Name mit anderer Repository- bzw. Besitzer-Kennung
  und Zertifikat ohne Kennungen – alt Exit 0, neu Exit 3; leere oder anders
  geschriebene erwartete Kennung → Exit 2.
- Nach dem Merge: `Publish lego` `41639780771` grün mit beiden Kennungen in
  allen drei Nachweisen. `Publish` `41639780735` Versuch 1 rot beim Upload
  (`unknown blob` nach allen `Pushed`), Prüfschritt nicht erreicht; von der
  Ownerin über die Oberfläche neu gestartet, Versuch 2 grün mit beiden
  Kennungen, auch beim Laden aus der Registry.

### 1.8 PR 3a (#136): Gegenproben über beide Quellen

- `attest_select_source api|oci` (unbekannt → Exit 2); Gegenproben nehmen die
  Quelle statt `"$@"` und hängen `--bundle-from-oci` selbst an; eigener Grund
  „fremdes Image“ aus der Registry. CI-Einstieg: `for source in api oci`,
  sechs Gegenproben.
- Gemessen lokal (`gh` 2.102.0, nginx von Docker Hub): `Error: no attestations
  found in the OCI registry. Retry the command without the --bundle-from-oci
  flag to check GitHub for the attestation`. Laut Quellcode
  (`verification/attestation.go`, `artifact/oci/client.go`) nur, wenn die
  Registry geantwortet und nichts geliefert hat.
- Rot-Beweis (Platzhalter): Registry 503, Anmeldung fehlt, Docker Hub nicht
  erreichbar → Exit 5; akzeptierte Workflow-Probe über die Registry → Exit 4.
  9 Aufrufe, genau 4 mit `--bundle-from-oci`.
- Nach dem Merge: `Publish` `41642798000` und `Publish lego` `41642797867`
  grün; über die Registry meldet `gh` bei „falscher Workflow“ und „falscher
  Branch“ dieselben Texte wie über die API (jetzt gemessen).

### 1.9 Commit-Adresse: Push-Sperre GH007

Der erste Push von PR 1 wurde abgelehnt („push would publish a private email
address“). Die globale Git-Adresse war privat; für #130 ging derselbe Push
noch durch. Gelöst mit E-5-124: Noreply-Adresse nur für dieses Repository
(`git config --local`), ungepushten Commit mit `--amend --reset-author` neu
geschrieben und signiert.

### 1.10 Lehrstoff

- [Lehrstoff: Ein Prüf-Gate für CI und Server](https://claude.ai/artifact/HK774FFh8WAkYnpMMSXywu)
  (Bibliothek mit zwei Einstiegen, Gegenproben mit Grund und Rot-Beweis,
  feste Kennungen, zwei Quellen, Ablauf des Deploys mit Diagramm,
  Kestrel-Messung, Lieferkette im Alltag, Fallen, Spickzettel)

---

## 2. Gelernt

- `gh attestation verify` meldet „abgelehnt“ und „Netz weg“ mit demselben
  Exit-Code 1; erst die Meldung zeigt, ob eine Gegenprobe etwas beweist.
- Die Bedingung „signiert von Workflow X“ prüft `gh` nicht selbst, sondern
  Sigstore; die Meldung nennt deshalb nur „verifying with issuer“, nicht den
  Workflow.
- Mit `--bundle-from-oci` vergleicht `gh` nur Namen; Repository- und
  Besitzer-Kennung stehen im Zertifikat und lassen sich aus dem verifizierten
  Ergebnis lesen.
- „no attestations found in the OCI registry“ setzt voraus, dass die Registry
  geantwortet hat; Abruf- und Anmeldefehler haben eigene Meldungen.
- Über API und Registry meldet `gh` bei falschem Workflow und falschem Branch
  dieselben Texte.
- Ein Längen-Byte 10 im Zertifikat erscheint in `openssl -text` als
  Zeilenumbruch; der Wert steht dann eine Zeile tiefer.
- PowerShell kann Binärdaten zwischen zwei Programmen beschädigen; Text (PEM)
  ist der sichere Weg durch eine Pipe.
- In Git Bash zerschneidet ein Pfad mit `C:` die `PATH`-Variable am
  Doppelpunkt; Platzhalter-Programme werden dann still übergangen.
- GitHub sperrt Pushes mit privater Commit-Adresse (GH007); eine
  Noreply-Adresse pro Repository löst das ohne den Schutz abzuschalten.
- `unknown blob` beim Manifest-Upload nach vollständigem Schichten-Upload ist
  ein Fehler der Registry; der Schritt bricht korrekt ab, ein neuer Versuch
  baut alles neu.
- Das fein abgestufte Token des Agenten darf keine Workflow-Läufe neu starten.
- Direkt nach einem Merge kann `gh run list` noch ältere Läufe zuerst
  liefern; Läufe über `--commit` auswählen.
- Ein KEV-Fund in einem gepinnten Fremd-Image macht den Scan auf jedem PR rot,
  auch wenn der PR das Image nicht berührt.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-111** | Digest als Datei im signierten Repository (z. B. `deploy/staging.digest`), Änderung per PR auf `main`; Server holt per `git pull`, prüft Commit-Signatur, dann Herkunftsnachweis | Herkunft ist nicht Aktualität (Downgrade-Schutz); der Commit ist Freigabe (Schritt 6) und DORA-Ereignis |
| **E-5-112** | Deploy als System-Unit in `/etc/systemd/system` mit `User=deploy` (rootless Docker, ADR-012); Token per `LoadCredential`; Unit und Skript root-eigen, für `deploy` nicht beschreibbar; zu Beginn `docker info` prüfen (rootless, fail closed). `restart_api` startet **nicht** die Deploy-Unit | `compose up -d` ohne Änderung startet nicht neu; Least Privilege |
| **E-5-113** | Ablauf: 0 `flock` und Vorbedingungen → 1 `git fetch`, Web-Flow-Signatur (eigener Keyring, Schlüssel aus `github.com/web-flow.gpg`, Fingerabdruck abgleichen), `merge-base --is-ancestor` → 2 neuer Ordner `releases/<commit>/`, Digest per Regex `^ghcr\.io/xxxcoder999xxx/identity-service@sha256:[0-9a-f]{64}$` → 3 Paket anonym nicht lesbar (eindeutig 401/403) → 4 temporärer `DOCKER_CONFIG`, Nachweis plus Gegenprobe → 5 Pull per Digest, Digest vergleichen → 6 `compose up -d` (Punkt ohne Wiederkehr), Health über nginx, Rückweg über alten Ordner plus Alarm → 7 Symlink `current` atomar, Status, Ping | Alles vor Schritt 6 ändert nichts; kurze Lücke beim Austausch für Staging akzeptiert |
| **E-5-114** | Gegenprobe bei jedem Deploy; sie muss am erwarteten Fehler scheitern (umgesetzt in #134 als Exit 5) | Sonst beweist ein Zufallsfehler die Prüfung (fail open) |
| **E-5-115** | Paket anonym lesbar → Deploy abbrechen und Alarm | Vorfall 1 aus Sitzung 27, Ursache unbekannt |
| **E-5-116** | Prüfregeln in eine Bibliothek mit zwei Einstiegen; PR 1 Umbau, PR 2 erwarteter Grund, PR 3 Server-Einstieg (nur `--bundle-from-oci`) | Eine Quelle der Wahrheit für CI und Server |
| **E-5-117** | Prüfer root-eigen unter `/usr/local/lib/identity-service/`, nie aus dem Release-Ordner | Ein Release könnte sonst seinen eigenen Prüfer mitbringen |
| **E-5-118** | Sandbox der Deploy-Unit: `CapabilityBoundingSet=` leer, `NoNewPrivileges`, `ProtectSystem=strict`, `StateDirectory=identity-service-deploy`, `RuntimeDirectory` 0700 (für `DOCKER_CONFIG`), `ProtectHome=tmpfs` plus `BindPaths=/run/user/<UID>/docker.sock`, `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`, `SystemCallFilter=@system-service`, `PrivateTmp`, `PrivateDevices`, `ProtectKernel*`, `UMask=0077`; Timeouts je Netzaufruf | Begrenzt den Client; Grenze: nicht den Daemon |
| **E-5-119** | Erst messen, ob Kestrel selbst neu lädt (Option C), sonst A | Gemessen (lokal): lädt nicht neu → A |
| **E-5-120** | Option A: eigene Restart-Unit `identity-service-api-restart.service` (`User=deploy`); `restart_api` ruft `systemctl start` auf, Fehler als Exit-Code an `/fail` | Neustart nur, wenn nötig; Fehler landet im Totmannschalter. Zu messen: darf root ohne Capabilities `systemctl start`? |
| **E-5-121** | Prüfregeln vergleichen zusätzlich Repository- und Besitzer-Kennung aus dem verifizierten Zertifikat (CI: Runner-Variablen; Server: root-eigen, siehe E-5-122) | `--bundle-from-oci` vergleicht nur Namen; Namen sind neu vergebbar, Kennungen nicht. Server bleibt ohne API-Zugriff |
| **E-5-122** | Erwartete Werte des Server-Einstiegs (Repository, Kennungen, Workflow, Server-URL) als Konstanten im Einstieg selbst, root-eigen installiert (E-5-117) | Nicht geheim, per PR mit CODEOWNERS geprüft; keine Konfigurationsdatei zu parsen, keine Umgebungsvariablen |
| **E-5-123** | PR 3 geteilt: 3a Gegenproben mit Quelle als Parameter, CI führt sie über API **und** Registry aus; 3b Server-Einstieg nach Messungen am Server | Jeder `Publish`-Lauf belegt die Muster des Servers mit dem echten `gh` |
| **E-5-124** | Commit-Adresse in diesem Repository ist die Noreply-Adresse (`git config --local`) | Datenschutz; GH007-Schutz bleibt aktiv |

ADR-Kandidaten: ein ADR „Pull-Deploy auf Staging“ für E-5-111 bis E-5-120;
Nachtrag zu ADR-015 für E-5-109, E-5-110 (Sitzung 27), E-5-121 bis
E-5-123. E-5-124 ist Arbeitsweise, kein ADR.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **PR 3b Server-Einstieg:** vorher am Server messen:
  - Ob `gh` mit `--bundle-from-oci` trotzdem `api.github.com` anspricht
    (Netzregeln, E-5-118). Dass ein `GH_TOKEN` nötig ist, ist **bereits**
    gemessen (Sitzung 27: ohne Anmeldung Exit 4) und entschieden (E-5-109);
    in dieser Sitzung irrtümlich erneut als offen vorgeschlagen.
  - Wohin `gh` den TUF-Zwischenspeicher schreibt und welche Ziele es lädt
    (`ProtectHome=tmpfs`, `StateDirectory`).
  - Wie `attest_find_foreign_image` im Release-Ordner mit rootless Docker
    arbeitet (`docker compose config --images`).
- **nginx-Fund CVE-2026-111497:** täglich auf ein neu gebautes
  `nginx-unprivileged` prüfen; ohne Neubau bis etwa **09.11.2026** per ADR
  entscheiden: eigenes Image mit Updates oder befristete Ausnahme im Gate.
  Ungeprüft: ob nginx Brotli überhaupt lädt.
- **lego-Paket für das Maschinenkonto freigeben** (Read, Roadmap-Punkt 3 aus
  Sitzung 27; Einstellung der Ownerin) und Sichtbarkeit des lego-Pakets
  ansehen.
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy
  (Ruleset, Ownerin).
- `unknown blob` bei `Publish` `41639780735` Versuch 1: einmalig; bei
  Wiederholung GHCR-Status und Paketrechte untersuchen.
- **Bericht Sitzung 27 unversioniert:** `docs/sitzungen/sitzung-27.md` liegt
  ungetrackt im Arbeitsverzeichnis; lokaler Branch `docs/sitzung-27` ohne
  Commit (hinter `main`).
- Lokale gemergte Branches löschen (Freigabe nötig):
  `refactor/attestation-rules-library`, `fix/attestation-counterproof-reasons`,
  `fix/attestation-verify-repository-ids`,
  `feat/attestation-counterproofs-from-registry`,
  `docs/adr-015-pull-deploy-verifier-and-registry-access`.
- Lokale Zertifikate laufen am **31.01.2027 12:46 UTC** ab (lokal kein
  Totmannschalter); Erinnerung ab etwa 24.01.2027.
- Kestrel-Neuladen auf dem Linux-Server nicht gemessen; `dotnet/aspnetcore`
  #70027 beobachten.
- nginx könnte nach einem Zertifikatswechsel alte TLS-Sitzungen weiterführen
  (nicht gemessen).
- `.claude/rules/lieferkette-und-ci.md` nennt die Bibliothek
  `scripts/lib/attestation-rules.sh` und Exit 5 noch nicht (Entscheidung der
  Ownerin).
- Lokal kann `gh attestation verify` das private Paket nicht lesen; Belege
  über den Registry-Weg nur in der CI oder auf dem Server.
- Telemetrie von `gh` in der CI weiter an (E-5-108 gilt nur für den Server).
- Scratchpad-Reste der Sitzung (Platzhalter für `gh`, `kev.json`) liegen
  außerhalb des Repositorys.

**Aus Sitzung 27 und früher, weiter offen**

- **Deploy-Skript und Unit bis spätestens 27.12.2026** (`restart_api`
  Platzhalter).
- Erster automatischer Lauf des Erneuerungs-Timers nicht abgelesen.
- **GHCR-Token läuft am 28.01.2027 04:31 UTC ab;** Erinnerung ab etwa
  14.01.2027.
- **Token des Agenten läuft am 27.11.2026 ab;** Erinnerung ab etwa
  20.11.2026.
- Ursache der Veröffentlichung des Pakets (Sitzung 27) unbekannt.
- „Manage Actions access“: Admin → Write prüfen.
- ADR-015 auf „Akzeptiert“; Nachträge E-5-109, E-5-110; ADR-011 Nachtrag zu
  Alternative 4.
- Sicherheitshinweise von `cli/cli` beobachten.
- `user: "1654:1654"` für `api` in `compose.staging.yaml`; `jq` für
  `test-staging-config.sh` (Aufnahme-Prüfung).
- `.claude/rules/skripte.md`: Bash auf dem Server ausdrücklich erlauben.
- Server: `PermitRootLogin`, `unattended-upgrades`, Docker 29.9.2.
- Units von host-health-check nicht im Repository (E-5-103).
- CI-Job für die Exit-Pfade der Bash-Skripte.
- Lokale lego-Images `identity-service-lego:local` und `:publish` veraltet.
- CA-Wechsel vor dem 28.10.2027.
- `pids_limit: 256` der API ohne Gegenprobe.
- lego ohne `tmpfs` beim ersten Lauf messen; `--key-type ec256`.
- Herkunft der Pflichtvariablen auf dem Server, Ort von `server_name.conf`.
- Catch-all 443 mit passender SNI und fremdem Host: 404 ohne Security-Header.
- Prüfskript prüft die Netze der API nicht.
- M1 und M2 unter rootless Docker auf dem Server wiederholen.
- Push- und Digest-Logik doppelt in `publish.yml` und `publish-lego.yml`.
- `Test-Stack.ps1` lokal nicht lauffähig (Hook blockiert `-CaFile`).
- Nachträge zu ADR-005, ADR-009, ADR-010, ADR-011, ADR-012, ADR-014;
  ADR-006, ADR-008, ADR-012, ADR-013, ADR-014 auf „Vorgeschlagen“.
- CVE-2026-111943 bei NVD und CISA KEV nicht geprüft.
- Signatur der distroless-Basis nicht selbst geprüft.
- CAA um `accounturi` und `validationmethods=http-01`; TTL des A-Eintrags.
- Healthchecks.io: zweiter Warnkanal vor Production, IPv4-Erreichbarkeit,
  Gegenprobe „Update-Lücke über 26 Stunden“.
- Frist des Journals ab 18.11.2026; runc 1.5.2 und CVE-2026-41579; NTS und
  netcup-Regel `ntp-antworten`; Journal von `nft-rollback.service`.
- `git log --show-signature`: „No principal matched“ (lokale
  `allowed_signers`); Commits zeigen `%G? = U`.
- `.claude/hooks/Protect-Secrets.ps1` (alter CA-Dateiname im Kommentar),
  `.claude/rules/container-und-nginx.md` ohne Satz zu `internal-ca.crt`.
- Remote-Branch `test/staging-red-proof`: Stand nicht geprüft.
- Lokaler DNS-Server hing zeitweise (Sitzung 27).

**Bekannte Grenzen**

- Der Server-Einstieg existiert noch nicht; die Registry-Muster sind nur in
  der CI belegt.
- Domain, Server-IPs, Hostnamen und Benutzernamen stehen bewusst nicht in
  diesem Bericht (ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Neu: Deploy-Ablauf entschieden, Prüfregeln für den
Server vorbereitet und in jedem `Publish`-Lauf belegt, erstes lego-Image
veröffentlicht.

| Nr. | Schritt | Abhängig von |
|---|---|---|
| 1 | ~~Staging-Konfiguration~~ erledigt | – |
| 2 | Interne CA: erledigt bis auf **API-Neustart** (E-5-120) | 5 |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer | ~~veröffentlichtes lego-Image~~ (erledigt); Freigabe lego-Paket, Required Check |
| 4 | ~~Maschinenkonto~~ erledigt | – |
| 5 | Pull-Deploy: ~~Ablauf~~, ~~Prüfregeln-Bibliothek~~ (PR 1, 2, 3a); **3b, Skript, Units offen** | Messungen am Server |
| 6 | Freigabe vor dem Deploy (Digest-Commit, E-5-111), DORA-Events | 5 |
| 7 | DAST (OWASP ZAP) | 5, 6 |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: lego v5.6.0 und distroless-Digest gemergt (Release Notes gelesen); Prüf-Gate verschärft (Exit 5, Kennungen, Registry-Gegenproben) |
| **A10 / fail closed** | Zufallsfehler bei Gegenproben jetzt rot statt grün; leere Kennung → Exit 2 |
| **Image-Gate für fremde Images** | lego grün; nginx rot (CVE-2026-111497, KEV, Frist 10.11.2026); kein Required Check |
| **Secrets (6.3.3)** | Keine neuen Geheimnisse; Commit-Adresse jetzt Noreply |
| **Agentic-Gate 6.5** | Nicht im Produkt; Berechtigungsprüfung des Agenten hat das Auslesen eines Zertifikats blockiert, Ownerin führte es selbst aus |
| **LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7; Timeouts je Netzaufruf im Deploy (E-5-118) |
| **mTLS, Contract Testing** | Rücken näher, nicht fällig |
| **Feature Flags, Mutation Testing, k6** | Nicht fällig |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (02./03.11.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| `goacme/lego` | v5.6.0, `sha256:6f1583fc026a455ea46a7a5858c576105bb69c2e2de69db391cab7f14750350c` | Registry, #132 |
| `distroless/static-debian13` (lego) | `sha256:25ac8f0c3b2334a9eb05452266bd4697864a8c8ef0ef71e5e6480d7f92868329` | Registry, #131 |
| `nginxinc/nginx-unprivileged:1.30.6` | `sha256:ec0f7ecb1fbd84959ac114e65fb36074ffc97d4d51db0f18ee925162d889dcef` (= `1.30`, 19.10.2026, kein neueres Tag) | Registry |
| `gh` neuestes Release / lokal | v2.103.3 / 2.102.0 | `cli/cli` |
| `sigstore-go` in `gh` 2.102.0 und 2.103.3 | v1.3.0 | `go.mod` |
| Repository-Kennung / Besitzer-Kennung | `1296648545` / `291064355` | API und Zertifikat |
| API-Image mit gemessenem Zertifikat | `ghcr.io/xxxcoder999xxx/identity-service@sha256:e99a654f5f83452991afeb9811ceea5ea5c252002d9dc50c14609ab8d374e24f` | `Publish` `41636900858` (`e053ec2`) |
| `main` nach der Sitzung | `1723453` | `git log` |

### 6.2 Exit-Codes von `scripts/verify-attestations.sh`

| Code | Bedeutung |
|---|---|
| 0 | alle Nachweise verifiziert, alle Gegenproben aus dem erwarteten Grund abgelehnt |
| 2 | Voraussetzung oder Parameter fehlt/ungültig (auch Bibliothek, Hook, Kennung, Quelle) |
| 3 | Nachweis fehlt, ungültig oder Angaben weichen ab (auch Kennungen) |
| 4 | Gegenprobe akzeptiert |
| 5 | Gegenprobe nicht am erwarteten Grund gescheitert |

### 6.3 Erwartete Meldungen von `gh` (gemessen auf dem Runner)

| Gegenprobe | API | Registry (`--bundle-from-oci`) |
|---|---|---|
| fremdes Image | `Error: HTTP 404: Not Found (https://api.github.com/repos/<repo>/attestations/<digest>?…)` | `Error: no attestations found in the OCI registry. Retry the command without the --bundle-from-oci flag to check GitHub for the attestation` |
| falscher Workflow | `Error: verifying with issuer "sigstore.dev"` | gleich |
| falscher Branch | `Error: expected SourceRepositoryRef to be refs/heads/not-main, got refs/heads/main` | gleich |

### 6.4 Läufe als Belege

| PR | `Publish` | `Publish lego` |
|---|---|---|
| #132 | – | `41458560831` (erstes grünes lego) |
| #131 | `41632429372` | `41632429448` |
| #133 | `41633671098` | `41633670940` |
| #134 | `41636900858` | `41636901708` |
| #135 | `41639780735` (Versuch 2) | `41639780771` |
| #136 | `41642798000` | `41642797867` |

### 6.5 Fallstricke, die Zeit gekostet haben

- `PATH` mit `C:/…` in Git Bash: Platzhalter-`gh` übergangen, Test lief
  gegen das echte `gh`. Pfade als `/c/…`, vorher `command -v gh`.
- `base64 -d | openssl` über `!` (PowerShell) beschädigte DER; mit `jq` ein
  PEM bauen und nur Text weiterreichen.
- Längen-Byte 10 = Zeilenumbruch in `openssl -text`; `grep -A2`.
- `gh run list` direkt nach dem Merge: alte Läufe; `--commit <sha>`.
- `gh api` mit `?predicate_type=https://…` im Pfad: „unsupported protocol
  scheme“; stattdessen `-X GET … -f predicate_type=…`.
- Commit-Hook liest den Betreff nur aus `-m` (bekannt aus Sitzung 27).
- Die Berechtigungsprüfung des Agenten blockierte `gh api …/attestations/…`
  mit Zertifikats-Auswertung zweimal, auch nach Freigabe; die Ownerin führte
  den Befehl per `!` aus.
- GH007 beim Push wegen privater Commit-Adresse (E-5-124).

### 6.6 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Kestrel messen | C vor A | Wegwerf-CA, `mv` im Mount, Neustarts | erst API-Neustart → 502 |
| Bot-PRs | Release Notes lesen | Digest gegen Registry | lego-Gate grün, erstes lego-Image |
| PR 1 | eine Quelle der Wahrheit | Bibliothek + Einstieg | Ausgabe vorher = nachher |
| PR 2 | Gegenprobe beweist sonst nichts | Muster je Probe, Exit 5 | Matrix diagonal, Rot-Beweis 0 → 5 |
| E-5-121 | Namen neu vergebbar | Zertifikat lesen, `ATTEST_FACTS` + 2 Spalten | Kennungen gemessen, 0 → 3 |
| PR 3a | Server nutzt nur Registry | Quelle als Parameter, 6 Gegenproben | Registry-Meldungen auf dem Runner gemessen |

---

# Roadmap Sitzung 29

## 1. Messungen am Server für PR 3b

Warum zuerst: Der Server-Einstieg und die Sandbox der Deploy-Unit (E-5-118)
hängen davon ab, was `gh` beim Prüfen über die Registry tatsächlich tut. Die
Muster der Gegenproben sind in der CI belegt; offen ist das Verhalten auf dem
Server.

- Netzziele von `gh attestation verify --bundle-from-oci` (spricht es
  `api.github.com` an? TUF-Ziele?) – mit dem Aufruf aus Sitzung 27, 6.3.
- Ort des TUF-Zwischenspeichers und Verhalten mit leerem Home
  (`ProtectHome=tmpfs`).
- `docker compose config --images` im künftigen Release-Ordner unter
  rootless Docker.
- Nicht erneut messen: dass ein `GH_TOKEN` nötig ist (E-5-109).

## 2. PR 3b: Server-Einstieg

Warum: letzter Teil von E-5-116; Voraussetzung für das Deploy-Skript.
Bausteine: Konstanten nach E-5-122, Darstellung fürs Journal,
`attest_verify_ok … --bundle-from-oci`, drei Gegenproben mit Quelle `oci`,
fremdes Image aus dem Release-Ordner, Exit-Codes 0/2/3/4/5; Rot-Beweis mit
Platzhalter, dann echter Lauf am Server.

## 3. PR 4: Deploy-Skript, Units, Digest-Datei

Warum: fristgebunden (27.12.2026). E-5-111 bis E-5-120; Restart-Unit
(Option A), `restart_api`, Gegenprobe „Neustart scheitert → /fail“; ADR
„Pull-Deploy auf Staging“.

## 4. nginx-Fund CVE-2026-111497

Warum: KEV, Frist 10.11.2026. Neubau des Herausgebers prüfen; wenn da: PR mit
neuem Digest. Wenn nicht bis etwa 09.11.: messen, ob nginx Brotli lädt, dann
ADR (eigenes Image vs. befristete Ausnahme).

## 5. Kurze Punkte der Ownerin

- Bericht Sitzung 27 und dieser Bericht ins Repository (eigene PRs)
- lego-Paket für das Maschinenkonto freigeben; `Image-Scan Drittanbieter`
  als Required Check vor dem ersten lego-Deploy
- ADR-015 auf „Akzeptiert“
- Gemergte lokale Branches löschen

## 6. Zurückgestellt, nicht aufgehoben

- Ports 80/443 und erstes Zertifikat (nach Freigabe des lego-Pakets)
- Server-Härtung (`PermitRootLogin`, `unattended-upgrades`, Docker 29.9.2)
- Telemetrie von `gh` in der CI abschalten
- ADR-Nachträge (siehe Offene Punkte), ADR zum Schritt DNS/TLS
- CA-Wechsel vor dem 28.10.2027; vor Production: NTS, IPv6, zweiter
  Warnkanal, HSTS, Update-Weg von `gh`

## 7. Vor oder in der Sitzung zu verstehen (vor Code)

- **Gegenprobe mit Grund:** Der Exit-Code sagt, ob `gh` abgelehnt hat; erst
  die erwartete Meldung zeigt, dass die Ablehnung aus der geprüften Bedingung
  kam. Ein falscher Grund ist Exit 5 und macht den Lauf rot.
- **Namen und Kennungen:** Mit `--bundle-from-oci` vergleicht `gh` nur
  Namen. Die Bibliothek vergleicht zusätzlich die festen Kennungen aus dem
  Zertifikat; der Server-Einstieg bringt sie als Konstanten mit (E-5-122).
- **Client-Sandbox vs. Daemon:** Die Sandbox der Deploy-Unit begrenzt nur
  das Skript und `gh`; der rootless Docker-Daemon läuft außerhalb. Was er
  darf, bestimmt ADR-012.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Ein Prüf-Gate für CI und Server](https://claude.ai/artifact/HK774FFh8WAkYnpMMSXywu)

## 8. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- SSH-Zugang zum Server bereithalten (Messungen in Punkt 1)
- Status von `nginxinc/nginx-unprivileged` auf Docker Hub ansehen
- Erinnerungen: Agenten-Token vor dem 27.11.2026, lokale Zertifikate vor dem
  31.01.2027, GHCR-Token vor dem 28.01.2027 erneuern
