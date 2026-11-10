# Sitzungsbericht Sitzung 29

**Datum:** 10.11.2026 (begonnen 09.11.2026)
**Phase:** Schritt 5 (CD): KEV-Fund im nginx-Image ohne Ausnahme im Gate
behoben (ADR-016, eigenes nginx-Image mit Debian-Updates), drittes eigenes
Image mit Herkunftsnachweis veröffentlicht, Sichtbarkeit aller Pakete wird bei
jeder Veröffentlichung geprüft; Server-Messungen, Server-Einstieg (3b),
Deploy-Skript und API-Neustart offen (Frist 27.12.2026)
**Vorgänger:** sitzung-28.md (abgeschlossen 03.11.2026)

---

## 1. Erledigt

| PR | Titel | Merge |
|---|---|---|
| #145 | `docs(adr): add ADR-016 own nginx image with debian updates` | `23f311b` |
| #146 | `build(nginx): build own image with debian security updates` | `b8afedc` |
| #147 | `chore(deps): Bump anchore/grype from v0.121.2 to v0.121.3` | `ae0ee2a` |
| #148 | `fix(ci): build nginx and pick foreign image from dockerfile in publish` | `03252a7` |
| #149 | `ci(publish): publish own nginx image with provenance` | `39eb83f` |
| #150 | `ci(publish): verify packages are not anonymously readable` | `2edc9e6` |

Alle von der Projekt-Ownerin per Squash gemergt; #145, #146, #148 bis #150
überwiegend KI-erzeugt, kein Auto-Merge. Zwischen Sitzung 28 und dieser
Sitzung gemergt (in dieser Sitzung nicht geprüft): #137, #138 (Berichte 27
und 28), #139 bis #144 (Bot-PRs: codeql-action, setup-dotnet 6.1.0, xunit.v3
4.0.3, dotnet/sdk- und aspnet-Digest, grype v0.121.2).

### 1.1 Aktualität (09.11.2026)

- `gh` v2.103.3 weiter neuestes Release (26.10.2026). Neueste Advisories von
  `cli/cli` vom 30.09.2026, darunter GHSA-wjmr-j3rp-mh2g (`--signer-workflow`
  als Präfix) und GHSA-4mq3-hpgx-9cx8 (`--source-ref` ohne Groß-/Kleinschreibung),
  beide low, durch Mindestversion 2.102.0 abgedeckt.
- `nginxinc/nginx-unprivileged`: `1.30` und `1.30.6` am 09.11.2026 weiter
  Stand 19.10.2026, Digest unverändert; zuletzt aktualisierter Tag insgesamt
  ebenfalls vom 19.10.2026 (Docker Hub).

### 1.2 nginx-Gate: vier Funde statt einem

`Image-Scan Drittanbieter (nginx)` auf `main` (Lauf `42649498309`, grype
v0.121.2) war rot mit **vier** Funden „High oder höher mit Fix“, nicht nur
dem in Bericht 28 genannten: `libbrotli1` CVE-2026-111497 (Critical, KEV),
`apt`/`libapt-pkg7.0` CVE-2026-109518 (High), `zlib1g` CVE-2026-76844 und
CVE-2026-85091 (High). Ursache der Abweichung: neuere Schwachstellen-Datenbank,
Image unverändert.

### 1.3 Messungen zur Erreichbarkeit (Wegwerf-Container, gepinnter Digest)

| Frage | Ergebnis |
|---|---|
| Brotli in `nginx -V` | nein |
| `ldd /usr/sbin/nginx` | libcrypt, libpcre2, libssl, libcrypto, **libz**, libc, libzstd; kein Brotli |
| Module mit Brotli | nur `ngx_http_image_filter_module` (über libgd → libfreetype) |
| Herkunft `libbrotli1` | Abhängigkeit von `libcurl4t64`, `libfreetype6`, `libheif1` |
| Gegenprobe `ldd libcurl.so.4` | `libbrotlidec`, `libbrotlicommon` gefunden |
| Laufender Stack, `/proc/<pid>/maps` | Master + 16 Worker: je 8 Bibliotheken, `libssl` 5 Treffer (Gegenprobe), Brotli 0, image_filter 0 |
| `nginx.conf`, `nginx/snippets/` | kein `load_module`, kein `image_filter`, kein `gzip` |
| Paketquellen im Image | `trixie`, `trixie-updates`, `trixie-security` (deb.debian.org, signiert über `debian-archive-keyring.pgp`); nginx.org nicht enthalten |
| `apt list --upgradable` | Fix-Versionen aller vier Gate-Pakete aus `stable-security`; dazu `ca-certificates`, `liblzma5`, `tzdata`, drei `libheif`-Pakete |

Folge: KEV-Fund über nginx nicht erreichbar, aber im Image (`curl`); zlib in
nginx gelinkt → keine belegbare Ausnahme. Die zuerst empfohlene „Brücke“
(befristete Ausnahme) wurde deshalb verworfen.

### 1.4 ADR-016 (#145)

`docs/adr/ADR-016-eigenes-nginx-image.md`, Status „Vorgeschlagen“:
Entscheidung, Alternativen (Brücke, Abwarten, flaches Image, Snapshot-Spiegel,
geplanter Neubau, anderes Basis-Image nicht geprüft), Grenzen (nicht
reproduzierbar, alte Dateien im Basis-Layer, `http` ohne Vertraulichkeit,
stilles Veralten). E-5-125 bis E-5-129.

### 1.5 Eigenes nginx-Image (#146)

- `docker/nginx/Dockerfile` (Basis per Digest, `USER 0` nur für
  `apt-get update && apt-get upgrade --yes`, Listen gelöscht, `USER 101`),
  `docker/nginx/.dockerignore` (`*`).
- `compose.yaml`: `build: docker/nginx` + `image: identity-service-nginx:local`;
  `compose.staging.yaml`: `build: !reset null` + `${NGINX_IMAGE:?…}`.
- `test-staging-config.sh`: Gegenprobe für `API_IMAGE` und `NGINX_IMAGE`.
- `ci.yml`: nginx bauen, UID-Prüfung für API und nginx, Platzhalter
  `NGINX_IMAGE`, Staging-`nginx -t` mit Image-ID und `--pull never`;
  Drittanbieter-Scan baut nginx.
- `dependabot.yml`: neuer Eintrag `docker` `/docker/nginx` mit Stable-Regel;
  Eintrag `docker-compose` bleibt (grype), nginx-Regel dort entfernt (bewusste
  Abweichung von „nur additiv“, CLAUDE.md 7).
- Vorab gemessen: Compose akzeptiert Image-ID als `image:`; ohne
  `--pull never` Pull-Versuch eines Repositorys `sha256`, mit Option nicht.
- Belegt im PR-Lauf `42780094158`: Debian-Updates beim Bauen, Blindheits-Schutz
  (`debian`, `pkg:deb/=150`, `name:nginx=1`), Gate `No vulnerabilities found`,
  `Config.User=101`, `--pull never` auf dem Runner unterstützt, Staging-Skript
  inklusive beider Gegenproben, Smoke-Test.

### 1.6 Folgefehler aus #146 und Reparatur (#148)

- `Publish` auf `b8afedc` rot (Lauf `42780593968`): `No such image:
  identity-service-nginx:local` (nur API gebaut, Start mit `--no-build`).
  Nichts veröffentlicht (fail closed).
- Zweite, vorhersehbare Ursache: `attest_find_foreign_image` suchte in
  `docker compose config --images` nach `^nginxinc/…`; seit #146 leer.
- Reparatur: `publish.yml` baut `api nginx`; fremdes Image aus der `FROM`-Zeile
  von `docker/nginx/Dockerfile` (`^FROM nginxinc/[^@ ]+@sha256:[0-9a-f]{64}`);
  Voraussetzung `docker` aus `verify-attestations.sh` entfernt.
- Lokal: echtes Dockerfile → Basis-Digest; ohne Digest, kurzer Digest, anderer
  Präfix, fehlende Datei → Exit 2.
- Nach dem Merge: `Publish` `42782256920` und `Publish lego` `42782256895`
  grün, je 6/6 Gegenproben „abgelehnt aus dem erwarteten Grund“, fremdes Image
  = nginxinc-Basis. CI `42782256578` grün inklusive nginx-Scan.

### 1.7 grype v0.121.3 (#147, nachträglich geprüft)

Bei Prüfung bereits gemergt. Digest `sha256:13113eec…2887` gleich der Registry
(Manifest-Liste amd64/arm64, 10.11.2026); Release 09.11.2026, kein
Vorab-Release; Inhalt: Abhängigkeits-Updates (8 Lücken in grype selbst) und
„further CPE to more precise package identifier mappings“ (#3886, kann Funde
verschieben). CI auf `03252a7` mit v0.121.3: Blindheits-Schutz und Gegenproben
bestanden.

### 1.8 `publish-nginx.yml` (#149)

Ohne Pfadfilter; bauen → UID/Version → `nginx -t` → Stack mit Vergleich der
Image-IDs → `Test-Stack.ps1` → Scan → Hochladen → Nachweise → Prüf-Gate
(`publish-nginx.yml`, Gegenprobe `publish.yml`) → Sichtbarkeit. Action-Pins am
10.11.2026 per `git ls-remote` aufgelöst (gleich den bestehenden, neueste).
Erster Lauf `42785919441`: Versuch 1 Schritte 1–5 grün, Sichtbarkeit rot
(HTTP 200, Paket öffentlich angelegt); nach Umstellung durch die Ownerin
Versuch 2 komplett grün (401).

### 1.9 Paket-Sichtbarkeit und Rechte

- Gemessen (Token-Endpunkt ohne Anmeldung): API 401, **lego 200 (öffentlich)**,
  nginx (noch nicht vorhanden) 403, Gegenprobe `anchore/grype` 200.
- Laut Ownerin hat niemand lego umgestellt; nginx war beim ersten Lauf ebenso
  öffentlich. Mit Vorfall 1 (Sitzung 27) dritter Fall: **Neue Pakete aus
  diesem Repository starten öffentlich**, entgegen der GitHub-Doku („default
  private“, gelesen in `github/docs`).
- Ownerin: lego und nginx auf privat, Vererbung vom Repository aus,
  Maschinenkonto unter „Manage access“ mit Read. „Manage Actions access“
  unverändert gelassen. Danach alle drei Pakete 401.

### 1.10 Sichtbarkeits-Prüfung in allen Workflows (#150)

`scripts/verify-package-private.sh` (Exit 0/2/3/4, Gegenprobe gegen das
öffentliche Scanner-Image aus `compose.scan.yaml`); letzter Schritt in
`publish.yml`, `publish-lego.yml` (auch im Pfadfilter), `publish-nginx.yml`
(ersetzt den Inline-Block). Lokal alle Exit-Pfade außer „Registry nicht
erreichbar“ belegt. Nach dem Merge: `Publish`, `Publish lego`, `Publish nginx`
und CI auf `2edc9e6` grün, alle drei Pakete 401.

### 1.11 Lehrstoff

- [Lehrstoff: Eigenes nginx-Image und Paket-Sichtbarkeit](https://claude.ai/artifact/Xcr3vL3PHMEXjAw4Mqa2Br)
  (Erreichbarkeit messen, eigenes Image statt Ausnahme, eine Quelle der
  Wahrheit, Leser einer Datei, Sichtbarkeit mit Gegenprobe, Ablauf als
  Diagramm, Fallen, Spickzettel)

---

## 2. Gelernt

- Ein Image-Scanner meldet, was im Image liegt; ob ein Dienst es nutzt, zeigen
  erst `ldd` und `/proc/<pid>/maps` des laufenden Prozesses.
- Neue Gate-Funde können ohne Änderung am Image entstehen, weil die
  Schwachstellen-Datenbank wächst; ein Bericht ist dafür kein aktueller Stand.
- `apt-get upgrade` installiert keine neuen Pakete; im nginx-unprivileged-Image
  kann es nginx nicht anheben, weil die Quelle von nginx.org fehlt.
- Dasselbe Dockerfile mit `apt-get upgrade` ergab im selben Commit zwei
  verschiedene Digests; maßgeblich ist der veröffentlichte Digest.
- Compose akzeptiert eine lokale Image-ID als `image:`; ohne `--pull never`
  versucht es bei unbekannter ID einen Pull aus dem Netz.
- Veröffentlichungs-Workflows laufen nicht bei PRs; eine Änderung an
  `compose.yaml` kann sie brechen, ohne dass ein Check rot wird.
- Neue GHCR-Pakete aus Workflows dieses öffentlichen Repositorys sind
  öffentlich, obwohl die Doku „privat“ sagt (dreimal beobachtet).
- Der Token-Endpunkt von GHCR unterscheidet ohne Anmeldung: privat 401, nicht
  vorhanden 403, öffentlich 200.
- Bei Paketen eines persönlichen Kontos erscheint „Manage access“ erst, wenn
  die Vererbung vom Repository abgeschaltet ist.
- Ein Scanner-Update kann über geänderte CPE-Zuordnungen das Urteil des Gates
  verschieben; der Blindheits-Schutz fängt nur fehlende Erkennung ab, nicht
  weniger Funde in erkannten Paketen.
- Ohne PyYAML lässt sich YAML mit Docker Compose parsen, wenn die Datei als
  `x-`-Feld eingebettet und `$` zu `$$` maskiert wird.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-125** | nginx als eigenes Image: gepinnte Basis + `apt-get upgrade` als root, zurück auf `USER 101` (ADR-016) | Behebt alle vier Funde ohne Gate-Ausnahme; zlib ist in nginx gelinkt |
| **E-5-126** | Eine Quelle der Wahrheit: Pin nur im Dockerfile, Staging per `NGINX_IMAGE`-Digest, Stable-Regel zieht mit um, ein atomarer PR (ADR-016) | Prüfskript verlangt Digest und kein `build`; toter Rest vermeiden |
| **E-5-127** | Eigener Workflow `publish-nginx.yml` mit vollem Smoke-Test (ADR-016) | Ein Workflow je Image (E-5-78); `nginx -t` beweist nur Lesbarkeit |
| **E-5-128** | Wochenlauf scannt den veröffentlichten nginx-Digest, kein geplanter Neubau mit Schreibrechten (ADR-016) | Frischer Build in der CI wäre „zu grün“; noch nicht umgesetzt |
| **E-5-129** | Ungenutzte Pakete (z. B. `curl`, Bild-/Font-Bibliotheken, `libheif`) später entfernen, eigener Schritt (ADR-016) | Ein Thema pro PR; braucht eigene Messung |
| **E-5-130** | `publish-nginx.yml` ohne Pfadfilter | Selten laufende Veröffentlichung bricht still (Vorfall #146); jedes Merge baut mit aktuellen Updates; neues Image ist kein Deploy |
| **E-5-131** | Nach dem Prüf-Gate: Paket anonym nicht lesbar (nur 401), mit Gegenprobe gegen ein öffentliches Paket | Drei Pakete starteten öffentlich; Doku widerspricht der Messung |
| **E-5-132** | Fremdes Image der Gegenprobe aus der gepinnten `FROM`-Zeile von `docker/nginx/Dockerfile` | `compose.yaml` enthält kein fremdes Image mehr; eine Quelle, auch im Release-Ordner auf dem Server; kein `docker` mehr nötig |
| **E-5-133** | Sichtbarkeits-Prüfung als geteiltes Skript `scripts/verify-package-private.sh` in allen `publish*.yml` | Regel an einer Stelle; Risiko bei allen drei Paketen belegt |

ADR-Kandidaten: E-5-125 bis E-5-129 stehen in ADR-016 (Status
„Vorgeschlagen“); Nachtrag zu ADR-016 für E-5-130 und E-5-132; Nachtrag zu
ADR-010 (oder ADR-015) für E-5-131, E-5-133 und den Befund „neue Pakete
öffentlich“.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Server-Messungen für PR 3b (zwei statt drei):** Netzziele von
  `gh attestation verify --bundle-from-oci` (spricht es `api.github.com` an?
  TUF?) und Ort des TUF-Zwischenspeichers bei leerem Home. Die dritte Messung
  (`docker compose config --images` im Release-Ordner) ist durch E-5-132
  entfallen. Für den Mitschnitt vorher prüfen, ob `strace` auf dem Server
  installiert ist (sonst Paketentscheidung).
- **E-5-128 nicht umgesetzt:** Der Wochenlauf scannt nginx als frischen Build;
  Kommentar im Job `Image-Scan Drittanbieter` nennt die Lücke.
- **Push- und Digest-Logik dreifach** in `publish.yml`, `publish-lego.yml`,
  `publish-nginx.yml`; geplant `scripts/push-image.sh` als refactor-PR mit
  Beleg „Ausgabe vorher = nachher“.
- **Deploy-Skript muss drei eigene Digests ausrollen** (API, nginx, lego);
  Digest-Datei und Prüfungen in PR 4 darauf auslegen (E-5-111).
- `verify-package-private.sh`: Pfad „Registry nicht erreichbar“ (Exit 2) nicht
  gemessen. Die Prüfung verhindert nichts, sie meldet nur.
- Leserecht des Maschinenkontos auf lego und nginx eingerichtet, Pull mit
  seinem Token noch nicht gemessen (Server).
- „Manage Actions access“: Rolle des Repositorys an den drei Paketen nicht
  angepasst; ob Write statt Admin genügt, weiter offen (mit einem Lauf belegen).
- Jedes Merge erzeugt neue API- und nginx-Versionen in GHCR; Aufbewahrungsregel
  fehlt.
- ADR-016 auf „Akzeptiert“ (Ownerin).
- `.claude/rules/container-und-nginx.md` (Edge-Image jetzt `docker/nginx`) und
  `.claude/rules/lieferkette-und-ci.md` (Workflow `publish-nginx.yml`,
  geteiltes Skript `verify-package-private.sh`, Bibliothek und Exit 5 aus
  Sitzung 28) anpassen (Ownerin).
- `Image-Scan Drittanbieter` als Required Check: nginx und lego jetzt grün;
  Aufnahme vor dem ersten lego-Deploy (Ruleset, Ownerin).
- Bot-PRs #139 bis #144 zwischen den Sitzungen gemergt, Release Notes in
  dieser Sitzung nicht gelesen; #147 erst nach dem Merge geprüft.
- Lokale gemergte Branches löschen (Freigabe nötig): `build/own-nginx-image`,
  `ci/publish-nginx-image`, `ci/verify-package-private`,
  `docs/adr-016-own-nginx-image`, `fix/publish-after-own-nginx-image`,
  `docs/sitzung-27`, `docs/sitzung-28`, dazu aus Bericht 28
  `refactor/attestation-rules-library`, `fix/attestation-counterproof-reasons`,
  `fix/attestation-verify-repository-ids`,
  `feat/attestation-counterproofs-from-registry`,
  `docs/adr-015-pull-deploy-verifier-and-registry-access`.
- DNS-Aussetzer beim Push („Could not resolve host: github.com“), kurz danach
  wieder erreichbar; zweiter Fall nach Sitzung 27.
- Lokales Image `identity-service-nginx:local` und Stack laufen mit dem neuen
  Image; ältere lokale Images nicht aufgeräumt.

**Aus Sitzung 28 und früher, weiter offen**

- **Deploy-Skript und Unit bis spätestens 27.12.2026** (`restart_api`
  Platzhalter, Restart-Unit E-5-120).
- Server-Einstieg PR 3b (E-5-116, E-5-122).
- **Token des Agenten läuft am 27.11.2026 ab;** Erinnerung ab etwa 20.11.2026.
- **GHCR-Token läuft am 28.01.2027 04:31 UTC ab;** Erinnerung ab etwa 14.01.2027.
- Lokale Zertifikate laufen am 31.01.2027 12:46 UTC ab; Erinnerung ab etwa
  24.01.2027.
- Kestrel-Neuladen auf dem Linux-Server nicht gemessen; `dotnet/aspnetcore`
  #70027 beobachten. nginx und alte TLS-Sitzungen nach Zertifikatswechsel
  nicht gemessen.
- `unknown blob` (Sitzung 28) einmalig; bei Wiederholung untersuchen.
- Erster automatischer Lauf des Erneuerungs-Timers nicht abgelesen.
- ADR-015 auf „Akzeptiert“; Nachträge E-5-109, E-5-110, E-5-121 bis E-5-123;
  ADR „Pull-Deploy auf Staging“ (E-5-111 bis E-5-120); ADR-011 Nachtrag zu
  Alternative 4; weitere Nachträge zu ADR-005, ADR-009 bis ADR-014; ADR-006,
  ADR-008, ADR-012, ADR-013, ADR-014 auf „Vorgeschlagen“.
- Telemetrie von `gh` in der CI weiter an.
- Sicherheitshinweise von `cli/cli` beobachten.
- `user: "1654:1654"` für `api` in `compose.staging.yaml`; `jq` für
  `test-staging-config.sh` auf dem Server (Aufnahme-Prüfung).
- `.claude/rules/skripte.md`: Bash auf dem Server ausdrücklich erlauben.
- Server: `PermitRootLogin`, `unattended-upgrades`, Docker 29.9.2; runc 1.5.2
  und CVE-2026-41579; Frist des Journals ab 18.11.2026; NTS und netcup-Regel
  `ntp-antworten`; Journal von `nft-rollback.service`.
- Units von host-health-check nicht im Repository (E-5-103).
- CI-Job für die Exit-Pfade der Bash-Skripte.
- CA-Wechsel vor dem 28.10.2027.
- `pids_limit: 256` der API ohne Gegenprobe; lego ohne `tmpfs` beim ersten
  Lauf messen; `--key-type ec256`.
- Herkunft der Pflichtvariablen auf dem Server, Ort von `server_name.conf`.
- Catch-all 443 mit passender SNI und fremdem Host: 404 ohne Security-Header.
- Prüfskript prüft die Netze der API nicht.
- M1 und M2 unter rootless Docker auf dem Server wiederholen.
- `Test-Stack.ps1` lokal nicht lauffähig (Hook blockiert `-CaFile`).
- CVE-2026-111943 bei NVD und CISA KEV nicht geprüft.
- Signatur der distroless-Basis nicht selbst geprüft.
- CAA um `accounturi` und `validationmethods=http-01`; TTL des A-Eintrags.
- Healthchecks.io: zweiter Warnkanal vor Production, IPv4-Erreichbarkeit,
  Gegenprobe „Update-Lücke über 26 Stunden“.
- `git log --show-signature`: „No principal matched“ (lokale
  `allowed_signers`); Commits zeigen `%G? = U`.
- `.claude/hooks/Protect-Secrets.ps1` (alter CA-Dateiname im Kommentar),
  `.claude/rules/container-und-nginx.md` ohne Satz zu `internal-ca.crt`.
- Remote-Branch `test/staging-red-proof`: Stand nicht geprüft.

**Bekannte Grenzen**

- Das veröffentlichte nginx-Image veraltet still, bis ein Merge neu baut oder
  E-5-128 misst.
- Die alten Paketdateien der Basis liegen verdeckt im Basis-Layer des
  nginx-Images.
- Domain, Server-IPs, Hostnamen und Benutzernamen stehen bewusst nicht in
  diesem Bericht (ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Neu: drei eigene Images (API, nginx, lego) mit
Scan, Herkunftsnachweis, Prüf-Gate und Sichtbarkeits-Prüfung; `main`
vollständig grün, auch `Image-Scan Drittanbieter (nginx)`.

| Nr. | Schritt | Abhängig von |
|---|---|---|
| 1 | ~~Staging-Konfiguration~~ erledigt (jetzt mit `NGINX_IMAGE`) | – |
| 2 | Interne CA: erledigt bis auf **API-Neustart** (E-5-120) | 5 |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer | ~~lego-Image~~, ~~Freigabe lego-Paket~~; Required Check |
| 4 | ~~Maschinenkonto~~ erledigt; Leserecht auf allen drei Paketen | – |
| 5 | Pull-Deploy: ~~Ablauf~~, ~~Prüfregeln~~ (PR 1, 2, 3a); **Messungen, 3b, Skript, Units offen** | Messungen am Server |
| 6 | Freigabe vor dem Deploy (Digest-Commit, E-5-111), DORA-Events | 5 |
| 7 | DAST (OWASP ZAP) | 5, 6 |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: KEV-Fund behoben ohne Ausnahme; eigenes nginx-Image; grype v0.121.3 (nachträglich geprüft); Action-Pins neu aufgelöst |
| **A01 / Zugriff** | Pakete starteten öffentlich (dreimal); jetzt bei jeder Veröffentlichung geprüft; Vererbung aus, Maschinenkonto nur Read |
| **A10 / fail closed** | Folgefehler aus #146 hat nichts veröffentlicht; neue Prüfungen werten 403 und Netzfehler als rot |
| **Image-Gate für fremde Images** | nginx und lego grün; kein Required Check |
| **Secrets (6.3.3)** | Keine neuen Geheimnisse; Messungen ohne Anmeldung |
| **Agentic-Gate 6.5** | Nicht im Produkt |
| **LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7; Timeouts je Netzaufruf (`curl --max-time 20` in der Sichtbarkeits-Prüfung) |
| **mTLS, Contract Testing** | Rücken näher, nicht fällig |
| **Feature Flags, Mutation Testing, k6** | Nicht fällig |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (09./10.11.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| `nginxinc/nginx-unprivileged:1.30.6` (Basis) | `sha256:ec0f7ecb1fbd84959ac114e65fb36074ffc97d4d51db0f18ee925162d889dcef`, Stand 19.10.2026 | Docker Hub |
| `ghcr.io/anchore/grype:v0.121.3` | `sha256:13113eeceab017260370cf540e1d25442c59665fd07d1b09b66d63bb0c282887` | Registry, #147 |
| `actions/checkout` v7.0.1 / `actions/attest` v4.2.2 | `3d3c42e5aac5ba805825da76410c181273ba90b1` / `1e69f48acb82d1966a394da916b4c1698aa569d6` (je neueste) | `git ls-remote`, 10.11.2026 |
| nginx-Image (Publish nginx) | `sha256:c475f3e995c9d2981e07766c5589a9ac15fbf3a706ffda96a992db538701a5c8` (`39eb83f`, Versuch 1), `sha256:7e14fb085edb604fd1b1f48507d2a13f0c64add5fc85c4bb31c068e3a1702f20` (`39eb83f`, Versuch 2), `sha256:9c8829e17a6622b8f5680ae65b9c36adcdfac7709f03466778b850b0ae0f2de6` (`2edc9e6`) | Läufe |
| API-Image | `sha256:c16c0cc94c922098a061eaf23d442fe05e8c179c4ab22ac18131445192403b01` (`2edc9e6`) | `Publish` |
| lego-Image | `sha256:eab3b585e0d276f9f2a1a47608796036c1ec73e1013a42c5a4120318b80defa0` (`2edc9e6`) | `Publish lego` |
| Debian-Pakete im nginx-Image | `libbrotli1 1.1.0-2+deb13u1`, `zlib1g 1:1.3.dfsg+really1.3.1-1+deb13u1`, `apt 3.0.4`, nginx `1.30.6-1~trixie` | Messung |
| nginx UID / Port | 101 / 8080 (Basis), StopSignal `SIGQUIT` | `docker image inspect` |
| `main` nach der Sitzung | `2edc9e6` | `git log` |

### 6.2 Exit-Codes von `scripts/verify-package-private.sh`

| Code | Bedeutung |
|---|---|
| 0 | anonym 401, Gegenprobe 200 |
| 2 | Parameter ungültig (nicht `ghcr.io/<owner>/<name>` ohne Tag), `curl` fehlt, keine Gegenprobe-Quelle, Registry nicht erreichbar |
| 3 | eigenes Paket nicht 401 (200 öffentlich, 403 nicht vorhanden) |
| 4 | Gegenprobe nicht 200 |

### 6.3 Läufe als Belege

| Zweck | Lauf |
|---|---|
| nginx-Gate rot, vier Funde (vorher) | CI `42649498309` |
| #146 im PR (Gate grün, `--pull never`) | CI `42780094158` |
| Folgefehler nach #146 | Publish `42780593968` |
| nach #148 | Publish `42782256920`, Publish lego `42782256895`, CI `42782256578` |
| erster Lauf `publish-nginx.yml` | Publish nginx `42785919441` (Versuch 1 rot 200, Versuch 2 grün 401) |

### 6.4 Fallstricke, die Zeit gekostet haben

- Annahme aus dem Vorbericht („nur Brotli löst aus“) statt aktueller
  Gate-Ausgabe → Empfehlung „Brücke“ musste zurückgenommen werden.
- Leser von `compose.yaml` nicht gesucht → #148. Vorher:
  `git grep -nE 'compose (up|build|run|config)|compose\.yaml|nginxinc' -- .github scripts`.
- ASCII-Prüfung mit `grep -P` lief nicht, `||` meldete „ok“; richtig:
  `LC_ALL=C grep -c $'[\x80-\xff]' DATEI` plus Gegenprobe.
- PR-Nummer angenommen (#147 statt #148) → falsche Checks gelesen.
- `gh run list --commit` braucht die volle SHA (`$(git rev-parse HEAD)`).
- Git Bash schreibt `-v …:/pfad` um → `MSYS_NO_PATHCONV=1`.
- Push vor dem Commit → leerer Branch auf dem Server (harmlos ohne PR).
- PyYAML fehlt: YAML über `docker compose config` parsen (`x-doc:` einbetten,
  `$` → `$$`).

### 6.5 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Erreichbarkeit | Ausnahme nur mit Beleg | `nginx -V`, `ldd`, `/proc/<pid>/maps` | Brotli unerreichbar, zlib gelinkt |
| Updates verfügbar | trägt Option A? | `apt list --upgradable` | alle vier Fixes in `stable-security` |
| #146 | eigenes Image, eine Quelle | Dockerfile, Compose, CI, Dependabot | nginx-Gate grün |
| #148 | Folgefehler | `build api nginx`, `FROM`-Zeile | Publish grün, 6/6 |
| #149 | Veröffentlichung nginx | `publish-nginx.yml` | Digest mit Nachweis |
| Sichtbarkeit | Doku ≠ Messung | Token-Endpunkt anonym | lego/nginx 200 → privat → 401 |
| #150 | Regel für alle | `verify-package-private.sh` | drei Pakete 401 bei jedem Lauf |

---

# Roadmap Sitzung 30

## 1. Server-Messungen für PR 3b

Warum zuerst: Server-Einstieg und Sandbox der Deploy-Unit (E-5-118) hängen
davon ab, was `gh` beim Prüfen über die Registry tut. Die Muster der
Gegenproben sind in der CI belegt.

- Netzziele von `gh attestation verify --bundle-from-oci` (spricht es
  `api.github.com` an? TUF-Ziele?). Vorher prüfen, ob `strace` vorhanden ist.
- Ort des TUF-Zwischenspeichers und Verhalten mit leerem `HOME`
  (`ProtectHome=tmpfs`).
- Pull mit dem Token des Maschinenkontos für alle drei Pakete (Leserecht
  belegen). Token nur über einen temporären `DOCKER_CONFIG`, nie in Ausgabe
  oder Verlauf.
- Entfallen: `docker compose config --images` (E-5-132). Nicht erneut messen:
  dass ein `GH_TOKEN` nötig ist (E-5-109).

## 2. PR 3b: Server-Einstieg

Warum: letzter Teil von E-5-116; Voraussetzung für das Deploy-Skript.
Konstanten nach E-5-122, `attest_verify_ok … --bundle-from-oci`, drei
Gegenproben mit Quelle `oci`, fremdes Image aus `docker/nginx/Dockerfile` im
Release-Ordner (E-5-132), Exit-Codes 0/2/3/4/5; Rot-Beweis mit Platzhalter,
dann echter Lauf am Server.

## 3. PR 4: Deploy-Skript, Units, Digest-Datei

Warum: fristgebunden (27.12.2026). E-5-111 bis E-5-120, jetzt mit **drei**
Digests (API, nginx, lego); Restart-Unit, `restart_api`, Gegenprobe „Neustart
scheitert → /fail“; ADR „Pull-Deploy auf Staging“.

## 4. E-5-128: Wochenlauf scannt den veröffentlichten nginx-Digest

Warum: Ohne ihn veraltet das veröffentlichte Image still, während die CI
einen frischen Build prüft. Spätestens vor dem ersten Staging-Deploy.

## 5. refactor: `scripts/push-image.sh`

Warum: dritte Kopie der Push- und Digest-Logik. Beleg „Ausgabe vorher =
nachher“ wie beim Umbau der Prüfregeln.

## 6. Kurze Punkte der Ownerin

- ADR-016 auf „Akzeptiert“; ADR-015 auf „Akzeptiert“
- `.claude/rules/container-und-nginx.md` und `.claude/rules/lieferkette-und-ci.md`
  nachziehen
- `Image-Scan Drittanbieter` als Required Check vor dem ersten lego-Deploy
- Gemergte lokale Branches löschen
- Bericht 29 ins Repository (Branch `docs/sitzung-29`)

## 7. Zurückgestellt, nicht aufgehoben

- E-5-129: ungenutzte Pakete aus dem nginx-Image entfernen
- Aufbewahrungsregel für Image-Versionen in GHCR
- Ports 80/443 und erstes Zertifikat
- Server-Härtung (`PermitRootLogin`, `unattended-upgrades`, Docker 29.9.2)
- Telemetrie von `gh` in der CI abschalten
- ADR-Nachträge (siehe Offene Punkte), ADR zum Schritt DNS/TLS
- „Manage Actions access“: Write statt Admin mit einem Lauf belegen
- CA-Wechsel vor dem 28.10.2027; vor Production: NTS, IPv6, zweiter
  Warnkanal, HSTS, Update-Weg von `gh`

## 8. Vor oder in der Sitzung zu verstehen (vor Code)

- **Erreichbarkeit vs. Vorhandensein:** Ein Scanner zählt Dateien im Image.
  Ob ein Dienst eine Bibliothek nutzt, zeigen `ldd` und die Speicherkarte des
  laufenden Prozesses; jede Suche braucht eine Gegenprobe.
- **Digest ist die Wahrheit:** Ein Image, das beim Bauen Updates zieht, ist
  nicht reproduzierbar. Ausgerollt wird nur der Digest aus der Digest-Datei,
  die Stückliste sagt, was drin ist.
- **Sichtbarkeit mit Gegenprobe:** Der Token-Endpunkt antwortet ohne Anmeldung
  mit 401 (privat), 403 (fehlt) oder 200 (öffentlich). Erst ein bekannt
  öffentliches Paket mit 200 macht „401“ beim eigenen Paket aussagekräftig.
- **Token auf dem Server:** Für die Messungen braucht `gh` eine Anmeldung an
  GHCR. Das Token des Maschinenkontos geht nur über einen temporären
  `DOCKER_CONFIG` in den Aufruf und wird nie ausgegeben.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Eigenes nginx-Image und Paket-Sichtbarkeit](https://claude.ai/artifact/Xcr3vL3PHMEXjAw4Mqa2Br)

## 9. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- SSH-Zugang zum Server bereithalten (Punkt 1)
- Auf dem Server nachsehen, ob `strace` installiert ist
- Erinnerungen: Agenten-Token vor dem 27.11.2026, GHCR-Token vor dem
  28.01.2027, lokale Zertifikate vor dem 31.01.2027 erneuern
