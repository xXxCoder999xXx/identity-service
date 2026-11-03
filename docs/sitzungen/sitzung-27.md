# Sitzungsbericht Sitzung 27

**Datum:** 30.10.2026 (begonnen 29.10.2026)
**Phase:** Schritt 5 (CD): Prüfwerkzeug `gh` 2.103.3 auf dem Server mit
belegter Herkunft, Maschinenkonto mit genau einem Leserecht, Prüfung des
Herkunftsnachweises auf dem Server bestanden und Gegenprobe abgelehnt;
Deploy-Skript und API-Neustart offen (Frist 27.12.2026); zwei Vorfälle
eingedämmt
**Vorgänger:** sitzung-26.md (abgeschlossen 29.10.2026)

---

## 1. Erledigt

| PR | Titel | Inhalt |
|---|---|---|
| #130 | `docs(adr): add ADR-015 pull deploy verifier and registry access` | ADR-015 (Status „Vorgeschlagen“): E-5-105 bis E-5-108 |

Von der Projekt-Ownerin per Squash gemergt (`2298503`); überwiegend
KI-erzeugt, kein Auto-Merge. Danach lief `Publish` erfolgreich (Lauf
`40883281498`).

### 1.1 Aktualität (Roadmap-Punkt 1, vorab)

- GHCR akzeptiert laut GitHub-Dokumentation weiterhin nur klassische Tokens;
  der Auslöser für eine Neubewertung von ADR-011 ist nicht eingetreten.
- Vier einschlägige Lücken in `gh attestation verify` (Primärquelle
  `cli/cli` Security Advisories, CVE-2026-48501 zusätzlich bei OSV und
  GitLab):

| Hinweis | Inhalt | Behoben ab |
|---|---|---|
| GHSA-8xvp-7hj6-mcj9 / CVE-2026-48501 (CVSS 7.4) | Token an TUF-Spiegel und fremde Hosts gesendet | 2.93.0 |
| GHSA-mm27-mwq9-fr5g / CVE-2026-64655 | Regex-Sonderzeichen in `--signer-repo`/`--signer-workflow` nicht maskiert | 2.97.0 |
| GHSA-wjmr-j3rp-mh2g | `--signer-workflow` nur am Anfang verankert | 2.102.0 |
| GHSA-4mq3-hpgx-9cx8 | `--source-ref` ohne Groß-/Kleinschreibung | 2.102.0 |

- `scripts/verify-attestations.sh` war gegen die drei Prüf-Lücken bereits
  geschützt: Zeilen 106–109 vergleichen `buildSignerURI` und
  `sourceRepositoryRef` exakt (`grep --fixed-strings --line-regexp`).
- Debian trixie liefert `gh` 2.46.0 (betroffen, laut `cli/cli` nicht
  funktionsfähig).
- `gh` sendet Telemetrie; Abschaltung per `GH_TELEMETRY=false` bzw.
  `DO_NOT_TRACK=true`, Umgebungsvariablen haben Vorrang vor der Konfiguration.
- Lokales `gh`: 2.102.0 (nicht betroffen, als Prüfer geeignet).

### 1.2 `gh` auf dem Server installiert (E-5-107)

| Schritt | Ergebnis |
|---|---|
| Release | v2.103.3 vom 26.10.2026, kein Vorab-Release (`gh release view --repo cli/cli`) |
| Architektur Server | `amd64` (`dpkg --print-architecture`) |
| Tag-Commit | `63837fb778d6a39f02be0ce76ff89f2bc8d74bdc` (`git ls-remote`, leichtgewichtiger Tag) |
| Herkunft lokal | Repository `cli/cli`, Workflow `.github/workflows/deployment.yml@refs/heads/trunk`, Runner `github-hosted`; mit `--source-digest` an den Tag-Commit gebunden; Subjekt `gh_2.103.3_linux_amd64.tar.gz` im Nachweis (deckt alle 22 Dateien des Builds ab) |
| Archiv-Hash lokal = Server | `4c806978…dd91d`, `sha256sum -c`: OK |
| Archivinhalt | alle Pfade unter `gh_2.103.3_linux_amd64/`, kein `../`, kein absoluter Pfad; nur `bin/gh` entpackt (als normaler Benutzer, Ordner `0700`) |
| Ziel vorher | weder `/usr/local/bin/gh` noch `/usr/bin/gh` vorhanden |
| Installation | `sudo install -m 0755 -o root -g root` nach `/usr/local/bin/gh` |
| Programm-Hash vor = nach | `b7681845…7ad34d`, 41 070 752 Byte |
| Version | `gh version 2.103.3 (2026-10-26)` |
| Aufgeräumt | Archiv und entpackter Ordner im Home gelöscht |

### 1.3 Maschinenkonto (E-5-21, E-5-110)

- Konto angelegt, 2FA per App/Passkey, E-Mail privat, keine Schlüssel, Apps
  oder Repositories (Benutzername bewusst nicht in diesem Bericht).
- Paket `identity-service`: Vererbung vom Repository abgeschaltet;
  Maschinenkonto unter „Manage access“ mit Rolle **Read** (genau ein
  Mitglied, Name von der Ownerin bestätigt).
- „Manage Actions access“ nach dem Abschalten der Vererbung unverändert:
  `identity-service` mit Rolle Admin (gemessen per Screenshot).
- Token: klassisch, Note `staging-ghcr-read`, nur `read:packages`, 90 Tage.
  Datei `/etc/credstore/identity-service-deploy.ghcr-token` vorab per
  `sudo install -m 0600 -o root -g root /dev/null …` angelegt, Token per
  `sudoedit` eingetragen.

| Messung | Ergebnis |
|---|---|
| Dateirechte, Größe | `root:root 0600`, 41 Byte |
| Format (nur Trefferzahl) | `1` (`^ghp_[A-Za-z0-9]{36}$`) |
| `GET /user` mit dem Token | `HTTP/2 200`, `x-oauth-scopes: read:packages`, Ablauf `2027-01-28 04:31:06 UTC` (nach der Rotation, 1.6) |

### 1.4 Prüfung auf dem Server gemessen (E-5-109)

Temporärer `DOCKER_CONFIG` (`mktemp -d`, `0700`; `config.json` `0600`,
106 Byte) per `sudo sh -c` mit Umleitung **innerhalb** der Shell geschrieben;
`GH_CONFIG_DIR` auf einen leeren Ordner; Image
`ghcr.io/xxxcoder999xxx/identity-service@sha256:d359e7e7…3403967` (Lauf
`40883281498`, Commit `2298503`).

| Lauf | Ergebnis |
|---|---|
| Ohne GitHub-Anmeldung, `--bundle-from-oci` | Abbruch vor jeder Prüfung: „To get started with GitHub CLI, please run: gh auth login“, `exit=4` |
| Mit `GH_TOKEN` = dasselbe Token, Workflow `publish.yml` | „Loaded 2 attestations from OCI registry“, `✓ Verification succeeded!`, 1 Nachweis passt (Herkunft), `exit=0` |
| Gegenprobe Workflow `publish-lego.yml` | „Loaded 2 attestations from OCI registry“, SAN-Regex mit `publish-lego\.yml`, `✗ Sigstore verification failed`, `Error: verifying with issuer "sigstore.dev"`, `exit=1` |

In der Ausgabe sichtbar: SAN-Regex mit `$`-Anker und maskierten Punkten,
`--source-ref` ohne `(?i)`. Temp-Ordner danach gelöscht.

### 1.5 Vorfall 1: Paket `identity-service` war öffentlich

- Screenshot der Package settings: „This package is currently public“.
  Anonyme Gegenprobe: GHCR gab ein anonymes Lese-Token aus, `tags/list`
  HTTP 200. Das lego-Paket bekam kein anonymes Token.
- Laut Bericht 10 war das Paket privat (E-5-8, E-5-21). Eine Entscheidung zur
  Veröffentlichung ist nirgends dokumentiert; die Ownerin erinnert sich an
  keine; im Security Log fand sich nichts (ob es diese Aktion überhaupt
  aufzeichnet, ist unbekannt).
- Auf privat gestellt; anonyme Gegenprobe danach: kein Token mehr. Die
  GitHub-Dokumentation („cannot make it private again“) ist damit widerlegt.
- Agenten-Token geprüft (mit Erlaubnis): fein abgestuft (kein
  `X-OAuth-Scopes`), `user/packages/container/identity-service` → HTTP 403.
  Es konnte die Sichtbarkeit nicht ändern.
- Konto-Check der Ownerin: Sessions, Tokens, Schlüssel unauffällig; die
  GitHub-App „Copilot SWE Agent“ war autorisiert, ungenutzt und nie geprüft
  → widerrufen. Im Repository keine PRs oder Branches von ihr. Autorisiert
  bleiben Git Credential Manager und Visual Studio (bekannt).
- Ursache: **unbekannt**.

### 1.6 Vorfall 2: GHCR-Token im Chat offengelegt

- Ein Befehl sollte die Registry-Anmeldung in eine Datei schreiben; die
  Umleitung stand außerhalb von `sudo` und fehlte beim Abtippen. Die
  Base64-kodierte Anmeldung (enthält das Token) erschien im Terminal und wurde
  in den Chat eingefügt.
- Nach wenigen Minuten rotiert (E-5-104): altes Token gelöscht, neues mit
  gleichen Einstellungen erzeugt und per `sudoedit` eingetragen. Belege: neues
  Ablaufdatum (04:31:06 statt 04:19:38 UTC), in der Token-Liste nur noch das
  neue (von der Ownerin bestätigt). Das offengelegte Token wurde vom Agenten
  nicht benutzt.
- Befehl umgebaut: Umleitung und `chown` innerhalb von `sudo sh -c '…'`,
  Ziel als Parameter; ein Tippfehler bricht ab, statt auszugeben.

### 1.7 Lehrstoff

- [Lehrstoff: Prüfwerkzeug, Maschinenkonto und Registry-Zugang für den Pull-Deploy](https://claude.ai/artifact/5XgboZrv5jmCDsGyidcBNB)
  (Token-Ort, Lücken in `gh` und Defense in Depth, Installationskette mit
  Diagramm, `--source-digest`, Paketrechte und Scope-Hierarchie, Messung und
  Gegenprobe, beide Vorfälle, Fallen, Spickzettel)

---

## 2. Gelernt

- `gh attestation verify` verlangt eine GitHub-Anmeldung auch dann, wenn die
  Nachweise mit `--bundle-from-oci` aus der Registry kommen (Exit 4).
- Ein klassisches Token mit nur `read:packages` genügt `gh` als `GH_TOKEN`
  und GHCR als Registry-Anmeldung.
- Projekte, die Releases per Dispatch von einem Branch starten, tragen im
  Nachweis den Branch, nicht den Tag; erst `--source-digest` mit dem
  Tag-Commit bindet den Nachweis an die Version.
- Ein Nachweis von `cli/cli` deckt alle Dateien eines Builds ab; der
  Dateiname muss im Subjekt stehen.
- Eine Prüfsummen-Datei aus demselben Release belegt keine Herkunft.
- Bei einer Gegenprobe unterscheidet der Exit-Code „abgelehnt“ nicht von
  „Netz weg“ (beide 1); belastbar ist erst die Kombination aus geladenen
  Nachweisen, angewendeter Regel und gescheiterter Signaturprüfung.
- Ein öffentliches GHCR-Paket ließ sich entgegen der Dokumentation wieder
  privat stellen (30.10.2026).
- Bei Paketen eines persönlichen Kontos ist „Nur Lesen“ für eine Person nur
  ohne Vererbung vom Repository möglich; das Abschalten der Vererbung ließ den
  Actions-Zugriff des Repositorys bestehen.
- In der Scope-Liste klassischer Tokens gibt ein Haken an der oberen Zeile
  alle eingerückten Rechte mit frei; `read:packages` steht eingerückt unter
  `write:packages`.
- Die API meldet die tatsächlichen Rechte eines klassischen Tokens im Header
  `X-OAuth-Scopes`, das Ablaufdatum in
  `github-authentication-token-expiration`.
- Eine Umleitung außerhalb von `sudo sh -c` macht aus einem Tippfehler eine
  Offenlegung; Umleitungen für Geheimnisse gehören in die root-Shell.
- In ein Terminal eingefügte Programmausgabe wird Zeile für Zeile als Befehl
  ausgeführt.
- Browser lösen Namen oft per DNS über HTTPS selbst auf; dass Websites gehen,
  beweist nicht, dass der DNS-Server von Windows antwortet.
- Ein leeres Security Log beweist nicht, dass nichts geschah, solange nicht
  belegt ist, dass es die Aktion aufzeichnet.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-105** | GHCR-Token in `/etc/credstore/identity-service-deploy.ghcr-token` (`root:root 0600`), Laden per `LoadCredential`, Anmeldung nur in einem temporären `DOCKER_CONFIG`, kein dauerhaftes `docker login` | Im Ruhezustand nur root-lesbar; Muster wie E-5-104 (ADR-015) |
| **E-5-106** | Prüfwerkzeug auf dem Server ist `gh` über dasselbe `verify-attestations.sh` | Eine Quelle der Wahrheit für die Prüfregeln (ADR-015) |
| **E-5-107** | `gh` als Release-Archiv; Herkunft lokal mit `--source-digest`, Hash vor und nach `install`, `/usr/local/bin` `root:root 0755`; Mindestversion 2.102.0 im Deploy-Skript (fail closed) | Kein dauerhafter root-Zugang für Dritte; veraltetes `gh` blockiert (ADR-015) |
| **E-5-108** | Deploy-Unit setzt `GH_TELEMETRY=false` und `DO_NOT_TRACK=true` | Keine ausgehenden Verbindungen, die die Prüfung nicht braucht (ADR-015) |
| **E-5-109** | Server lädt Nachweise nur aus der Registry (`--bundle-from-oci`); `gh` erhält dasselbe Token als `GH_TOKEN`, übergeben als Shell-Zuweisung vor dem Befehl | Gemessen: `gh` verlangt eine Anmeldung; kein neues Geheimnis, kein neues Recht (ADR-Kandidat, Nachtrag zu ADR-015) |
| **E-5-110** | Paket `identity-service` privat, Vererbung vom Repository aus, Maschinenkonto mit Rolle Read; jedes weitere Paket wird einzeln freigegeben | Stellt E-5-21 wieder her; „nur Lesen“ geht nur ohne Vererbung (ADR-Kandidat, Nachtrag zu ADR-015 bzw. ADR-011) |

ADR-Kandidaten: E-5-109 und E-5-110 als Nachtrag zu ADR-015; ADR-011
Nachtrag zu Alternative 4 (Begründung „unumkehrbar“ widerlegt). E-5-92 bis
E-5-104 weiter für das ADR zum Schritt DNS/TLS.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Deploy-Skript und Unit bis spätestens 27.12.2026** (API-Neustart,
  `restart_api` weiter Platzhalter).
- **Nächster `Publish`-Lauf nach dem Abschalten der Vererbung:** belegt erst,
  dass `publish.yml` weiter pushen kann. Der Lauf `40883281498` lag davor.
- **Ursache der Veröffentlichung des Pakets unbekannt.** Vorschlag: Das
  Deploy-Skript prüft zusätzlich, dass das Paket anonym **nicht** lesbar ist.
- **GHCR-Token läuft am 28.01.2027 04:31 UTC ab;** Rotation vor dem Ablauf,
  Erinnerung ab etwa 14.01.2027.
- `verify-attestations.sh` für den Server: Runner-Umgebung
  (`GITHUB_REPOSITORY`, `GITHUB_SERVER_URL`, `::group::`), nur
  `--bundle-from-oci`, Gegenproben am erwarteten Fehler erkennen.
- Netzfehler **während** der Signaturprüfung (Laden der Sigstore-
  Vertrauensbasis) nicht gemessen; Erscheinungsbild unbekannt.
- „Manage Actions access“: Rolle Admin, wahrscheinlich genügt Write
  (eigener Schritt mit Gegenprobe über einen Publish-Lauf).
- Telemetrie von `gh` in der CI (`ci.yml`, `publish*.yml`) abschalten.
- ADR-015 auf „Akzeptiert“ setzen (Ownerin); Nachträge E-5-109, E-5-110;
  ADR-011 Nachtrag zu Alternative 4.
- lego-Paket: Sichtbarkeit nicht in den Settings angesehen (anonym kein
  Token); Freigabe für das Maschinenkonto erst mit lego live.
- Sicherheitshinweise von `cli/cli` beobachten (Mindestversion anheben).
- DNS-Server des lokalen Rechners antwortete zeitweise nicht (Push,
  `gh api`, Webabrufe scheiterten); bei Wiederholung Router bzw. Verbindung
  prüfen.
- Lokale Branches `docs/adr-015-pull-deploy-verifier-and-registry-access`
  (gemergt) und Ordner `Downloads\gh-2.103.3` löschen.

**Aus Sitzung 26 und früher, weiter offen**

- Erster automatischer Lauf des Erneuerungs-Timers (29.10.2026) nicht
  abgelesen: `systemctl list-timers`, Journal, Ereignis bei Healthchecks.io.
- `user: "1654:1654"` für `api` in `compose.staging.yaml`.
- `.claude/rules/skripte.md`: Bash auf dem Server ausdrücklich erlauben
  (Entscheidung der Projekt-Ownerin).
- Server: `PermitRootLogin` und `unattended-upgrades` prüfen.
- Units von host-health-check nicht im Repository (vgl. E-5-103).
- CI-Job für die Exit-Pfade der Bash-Skripte (berührt `ci.yml`).
- Lokale lego-Images `identity-service-lego:local` und `:publish` veraltet.
- Lokale gemergte Branches `feat/staging-internal-ca`,
  `feat/api-cert-renewal-timer` löschen (Freigabe nötig).
- CA-Wechsel vor dem 28.10.2027 planen.
- Ob Kestrel ein erneuertes Zertifikat ohne Neustart einliest: nicht
  gemessen.
- **lego-Gate rot** bis zu einem Release mit Go ≥ 1.27.3 und `x/net` ≥
  0.60.0; `Publish lego` grün noch nie gelaufen.
- `pids_limit: 256` der API ohne Gegenprobe.
- `scripts/test-staging-config.sh` braucht `jq` (lokal und auf dem Server
  fehlt es; Aufnahme-Prüfung).
- lego ohne `tmpfs`: beim ersten Lauf messen; `--key-type ec256` setzen.
- Herkunft der Pflichtvariablen auf dem Server und Ort von
  `server_name.conf`.
- Catch-all 443 mit passender SNI und fremdem Host: 404 ohne
  Security-Header.
- Prüfskript prüft die Netze der API nicht.
- M1 und M2 unter rootless Docker auf dem Server wiederholen.
- Push- und Digest-Logik doppelt in `publish.yml` und `publish-lego.yml`.
- Paketliste in GHCR für den Agenten nicht abrufbar (fein abgestuftes Token).
- `Test-Stack.ps1` lokal nicht lauffähig (Hook blockiert `-CaFile`).
- Nachträge zu ADR-005, ADR-009, ADR-010, ADR-011, ADR-012, ADR-014;
  ADR-006, ADR-008, ADR-012, ADR-013, ADR-014 auf „Vorgeschlagen“.
- Release Notes von #106 und #108 nicht gemeinsam gelesen.
- Docker 29.9.2 auf dem Server nicht gemessen.
- CVE-2026-111943 bei NVD und CISA KEV nicht geprüft.
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy.
- Arbeitsdateien im ignorierten Ordner `scan/`.
- Signatur der distroless-Basis nicht selbst geprüft.
- CAA um `accounturi` und `validationmethods=http-01`; TTL des A-Eintrags.
- KEV-Einträge vom 16.10.2026 nicht namentlich geprüft.
- Healthchecks.io: zweiter Warnkanal vor Production, IPv4-Erreichbarkeit,
  Gegenprobe „Update-Lücke über 26 Stunden“.
- Frist des Journals ab 18.11.2026; runc 1.5.2 und CVE-2026-41579; NTS und
  netcup-Regel `ntp-antworten`; Journal von `nft-rollback.service`.
- Lokal OpenSSL 3.2.1 (Git für Windows) aktuell halten.
- `git log --show-signature`: „No principal matched“ (lokale
  `allowed_signers`); Commits zeigen `%G? = U`.
- `.claude/hooks/Protect-Secrets.ps1` (alter CA-Dateiname im Kommentar),
  `.claude/rules/container-und-nginx.md` ohne Satz zu `internal-ca.crt`.
- Remote-Branch `test/staging-red-proof`: Stand nicht geprüft.
- **Token des Agenten läuft am 27.11.2026 ab;** Erinnerung ab etwa
  20.11.2026.

**Bekannte Grenzen**

- Auf dem Server läuft noch kein Stack; die Prüfung ist mit einem einzelnen
  `gh`-Aufruf belegt, nicht mit dem Skript.
- Domain, Server-IPs, Hostnamen und Benutzernamen (auch des Maschinenkontos)
  stehen bewusst nicht in diesem Bericht (ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Neu: Prüfwerkzeug und Maschinenkonto auf dem
Server, Prüfung und Gegenprobe dort gemessen.

| Nr. | Schritt | Abhängig von |
|---|---|---|
| 1 | ~~Staging-Konfiguration~~ erledigt | – |
| 2 | Interne CA: erledigt bis auf **API-Neustart** | 5 |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer | **veröffentlichtes lego-Image** |
| 4 | ~~Maschinenkonto~~ erledigt (E-5-110, Token bis 28.01.2027) | – |
| 5 | Pull-Deploy: ~~Prüfwerkzeug~~, ~~Registry-Zugang~~; **Skript und Unit offen**, API-Neustart | – |
| 6 | Freigabe vor dem Deploy, DORA-Events | 5 |
| 7 | DAST (OWASP ZAP) | 5, 6 |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: `gh` 2.103.3 neu auf dem Server (ADR-015, Herkunft belegt) |
| **Secrets (6.3.3)** | Token offengelegt und rotiert (1.6); Befehl gehärtet |
| **Zero Trust / A01** | Paket wieder privat, Maschinenkonto nur Read, Token nur `read:packages` (gemessen) |
| **A10 / fail closed** | Gegenprobe auf dem Server abgelehnt; Mindestversion von `gh` beschlossen |
| **Agentic-Gate 6.5** | Berührt: ungeprüfter KI-Agent (Copilot SWE Agent) am Konto gefunden und widerrufen; kein Agent im Produkt |
| **LLM-Gate 6.4** | Nicht ausgelöst |
| **Image-Gate für fremde Images** | lego rot, nginx grün; noch kein Required Check |
| **DAST** | Fällig mit dem ersten automatischen Staging-Deploy |
| **mTLS** | Rückt näher (dieselbe CA könnte Client-Zertifikate ausstellen) |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing** | Rückt näher (weitere Microservices geplant) |
| **Feature Flags, Mutation Testing, k6** | Nicht fällig |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (29./30.10.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| `gh` neuestes Release | v2.103.3 (26.10.2026) | `gh release view --repo cli/cli` |
| Tag-Commit `v2.103.3` | `63837fb778d6a39f02be0ce76ff89f2bc8d74bdc` | `git ls-remote` |
| `gh_2.103.3_linux_amd64.tar.gz` | SHA-256 `4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d` | `gh attestation verify`, `sha256sum` |
| `bin/gh` aus dem Archiv | SHA-256 `b768184570b12536be4ac1528893f6340d1c6a7b40b56ad45bca9cd0e87ad34d` | `sha256sum` |
| `gh` Mindestversion | 2.102.0 | GHSA-wjmr-j3rp-mh2g, GHSA-4mq3-hpgx-9cx8 |
| `gh` lokal | 2.102.0 | `gh --version` |
| Debian trixie `gh` | 2.46.0 | packages.debian.org |
| Letztes geprüftes Image | `ghcr.io/xxxcoder999xxx/identity-service@sha256:d359e7e7671dc5ee6addb817253023ed1a2bc2eb951d5f83812d18ddc3403967` | Lauf `40883281498` |
| `main` nach der Sitzung | `2298503` | `git log` |

### 6.2 Dateien und Rechte auf dem Server (neu)

| Pfad | Besitz und Rechte | Inhalt |
|---|---|---|
| `/usr/local/bin/gh` | `root:root 0755` | `gh` 2.103.3, SHA-256 `b7681845…7ad34d` |
| `/etc/credstore/identity-service-deploy.ghcr-token` | `root:root 0600`, 41 Byte | GHCR-Token (Maschinenkonto, `read:packages`, Ablauf 28.01.2027 04:31:06 UTC) |

### 6.3 Prüfaufruf auf dem Server (gemessen)

```
GH_TOKEN="$(sudo cat /etc/credstore/identity-service-deploy.ghcr-token)" DOCKER_CONFIG="TEMPORDNER" GH_CONFIG_DIR="TEMPORDNER/gh" GH_TELEMETRY=false DO_NOT_TRACK=true gh attestation verify oci://IMAGE@DIGEST --repo xXxCoder999xXx/identity-service --signer-workflow xXxCoder999xXx/identity-service/.github/workflows/publish.yml --source-ref refs/heads/main --deny-self-hosted-runners --predicate-type https://slsa.dev/provenance/v1 --bundle-from-oci
```

`TEMPORDNER/config.json` wird per `sudo sh -c '… > "$2/config.json" &&
chown "$3" "$2/config.json"'` geschrieben (Umleitung innerhalb der
root-Shell).

### 6.4 Fallstricke, die Zeit gekostet haben

- Umleitung außerhalb von `sudo sh -c` → Token im Terminal (Vorfall 2).
- Eingefügte Programmausgabe wird als Befehle ausgeführt.
- Gegenprobe zuerst versehentlich mit dem alten Workflow-Namen ausgeführt
  (bestand); die geänderte Stelle vor dem Ausführen prüfen.
- `read:packages` steht eingerückt unter `write:packages` und wird leicht
  übersehen.
- Lokaler DNS-Server hing zeitweise; Browser funktionierte weiter (DNS über
  HTTPS). Gegenprobe: `nslookup github.com 9.9.9.9`,
  `Resolve-DnsName github.com`.
- `gh api /pfad` in Git Bash: führender Schrägstrich wird zu einem
  Windows-Pfad umgeschrieben; ohne Schrägstrich aufrufen.
- Commit-Hook liest den Betreff nicht aus `-F -`; Commit mit `-m`.

### 6.5 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Aktualität | Werkzeugwahl sicherheitsrelevant | Advisories `cli/cli`, OSV, GitHub Docs | vier Lücken, Mindestversion 2.102.0 |
| Herkunft `gh` | nur Geprüftes installieren | `gh attestation verify --repo cli/cli --source-digest …` | Repository, Workflow, Commit belegt |
| Übertragung | Unversehrtheit | `scp`, `sha256sum -c` | OK |
| Installation | nur root ändert | `tar -tzf`, `install -m 0755 -o root -g root` | Hash vor = nach, 2.103.3 |
| Paket ansehen | erst messen, dann ändern | Package settings | öffentlich gefunden |
| Paket privat | E-5-21 wiederherstellen | Change visibility, anonyme Gegenprobe | kein anonymes Token |
| Konto-Check | Ursache eingrenzen | Settings: Sessions, Tokens, Keys, Apps | Copilot SWE Agent widerrufen |
| Paketrechte | nur Lesen | Vererbung aus, Invite mit Read | ein Mitglied, Read; Actions-Zugriff erhalten |
| Token | minimales Recht | `install … /dev/null`, `sudoedit`, `grep -c` | `0600`, 41 Byte, Format 1 |
| Scopes messen | Absicht ≠ Wirkung | `curl -K -`, Header `x-oauth-scopes` | nur `read:packages` |
| Rotation | Token im Chat | Token löschen, neu erzeugen | neues Ablaufdatum, Liste bestätigt |
| Prüfung | kann der Server prüfen? | `gh attestation verify … --bundle-from-oci` | ohne `GH_TOKEN` Exit 4; mit Exit 0 |
| Gegenprobe | kann er ablehnen? | `--signer-workflow …/publish-lego.yml` | Sigstore verification failed, Exit 1 |

---

# Roadmap Sitzung 28

## 1. Deploy-Skript und systemd-Unit: Konzept, dann Umsetzung

Warum zuerst: fristgebunden. Ohne Deploy kein API-Neustart; die erste
Erneuerung des API-Zertifikats steht spätestens am 27.12.2026 an. Werkzeug,
Konto und Token sind jetzt vorhanden und gemessen.

Bausteine (erst Konzept, dann Code):

- Ablauf: Konfiguration per `git pull` mit Prüfung der Commit-Signatur
  (E-5-23, E-5-25) → Digest bestimmen (Quelle der Wahrheit für „welches
  Image“ klären) → Nachweis prüfen → Pull per Digest → Start; bei jedem
  Fehler läuft die letzte geprüfte Version weiter.
- Wer führt aus: root-Unit vs. Docker-Benutzer (rootless Docker), Zugriff auf
  den richtigen Daemon; Sandbox der Unit.
- `verify-attestations.sh` für den Server erweitern statt ändern
  (Open/Closed): ohne Runner-Umgebung, nur `--bundle-from-oci`, Gegenproben
  am erwarteten Fehler erkennen (Nachweise geladen + Regel + Sigstore
  verification failed).
- Mindestversion `gh` (E-5-107), Telemetrie aus (E-5-108), `GH_TOKEN` und
  temporärer `DOCKER_CONFIG` (E-5-105, E-5-109); Prüfung „Paket anonym nicht
  lesbar“.
- `restart_api` in `renew-api-certificate.sh` und gezielte Erweiterung der
  Sandbox (E-5-102); Gegenprobe „Neustart scheitert → /fail“.
- `user: "1654:1654"` für `api` in `compose.staging.yaml`; `jq` für
  `test-staging-config.sh` (Aufnahme-Prüfung).
- Missbrauchsfälle aus ADR-011 als Gegentests.

## 2. Kurze Ablesungen zu Beginn

Warum: billig und ohne Abhängigkeit. Erster automatischer Timer-Lauf
(Journal `identity-service-api-cert`, Healthchecks.io); nächster
`Publish`-Lauf nach der Vererbungs-Änderung grün?

## 3. lego-Release prüfen; wenn neu: Ports 80/443 und erstes Zertifikat

Warum: E-5-74. Bei einem Release mit Go ≥ 1.27.3 und `x/net` ≥ 0.60.0 Pin
anheben, `Publish lego` grün, lego-Paket dem Maschinenkonto mit Read
freigeben.

## 4. Server-Härtung prüfen

Warum: `PermitRootLogin`, `unattended-upgrades` und Docker 29.9.2 sind seit
mehreren Berichten offen.

## 5. Kleine Folge-PRs (nach Bedarf)

- ADR-015: Nachtrag E-5-109, E-5-110; ADR-011: Nachtrag zu Alternative 4
- Telemetrie von `gh` in der CI abschalten
- Actions-Zugriff des Pakets von Admin auf Write (mit Publish als Gegenprobe)
- Units von host-health-check unter `scripts/systemd/` (E-5-103)
- CI-Job für die Exit-Pfade der Bash-Skripte
- Regel-Sätze in `.claude/rules/` (Entscheidung der Projekt-Ownerin)
- Push- und Digest-Logik aus `publish.yml` und `publish-lego.yml`
  zusammenführen

## 6. Zurückgestellt, nicht aufgehoben

- **ADR-Nachträge:** ADR-010 (E-5-78), ADR-014 (E-5-70, E-5-71, E-5-77),
  ADR-005 (E-5-72), ADR-009 (`Unknown`), ADR-011, ADR-012
- **ADR zum Schritt DNS/TLS:** E-5-65 bis E-5-68, E-5-73 bis E-5-76,
  E-5-79 bis E-5-104
- **CA-Wechsel** vor dem 28.10.2027
- **Vor Production:** NTS, IPv6, zweiter Warnkanal, HSTS auf ein Jahr,
  E-5-93, Update-Weg von `gh`

## 7. Vor oder in der Sitzung zu verstehen (vor Code)

- **Quelle der Wahrheit für den Digest:** Der Server muss wissen, welches
  Image er starten soll. Ein Tag ist ein Zeiger, der sich ändern kann; ein
  Digest im signierten Repository-Stand wäre prüfbar, verlangt aber einen
  Commit pro Release.
- **Erweitern statt ändern:** Die CI-Prüfung ist belegt. Die Server-Variante
  entsteht als Erweiterung (Parameter oder eigener Einstieg), damit die
  belegte Logik nicht still mitgeändert wird.
- **Fail closed beim Deploy:** Scheitert irgendein Schritt, wird nichts
  ersetzt; die laufende, zuletzt geprüfte Version bleibt. Eine Gegenprobe,
  die aus dem falschen Grund scheitert (Netz), macht den Deploy rot.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Prüfwerkzeug, Maschinenkonto und Registry-Zugang für den Pull-Deploy](https://claude.ai/artifact/5XgboZrv5jmCDsGyidcBNB)

## 8. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- ADR-015 lesen und auf „Akzeptiert“ setzen
- Bei `cli/cli` „Watch → Custom → Security alerts/Releases“ einstellen
- Gemergte lokale Branches löschen; `Downloads\gh-2.103.3` löschen
- Erinnerungen: Agenten-Token vor dem 27.11.2026, GHCR-Token vor dem
  28.01.2027 erneuern
