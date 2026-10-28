# Sitzungsbericht Sitzung 25

**Datum:** 28.10.2026
**Phase:** Schritt 5 (CD): Dateiname der internen CA neutral (#123); Konzept
der Staging-CA auf dem Server entschieden (E-5-92 bis E-5-98), noch kein Code
dafür; lego-Gate weiterhin rot
**Vorgänger:** sitzung-24.md (abgeschlossen 27.10.2026)

---

## 1. Erledigt

| PR | Titel | Inhalt |
|---|---|---|
| #123 | `refactor(tls): rename internal ca file to a neutral name` | `internal-ca.crt` statt `local-dev-ca.crt` in `proxy-api.conf`, beiden Zertifikatsskripten, `ci.yml`, `publish.yml`; Abbruchprüfung in `New-LocalDevCertificates.ps1` |

#123 von der Projekt-Ownerin per Squash gemergt (`15a3f7e`); überwiegend
KI-erzeugt, kein Auto-Merge.

### 1.1 Aktualität vor der Werkzeugentscheidung (openssl)

- CISA KEV (Katalog 2026.10.27, per JSON-Feed gefiltert): zu OpenSSL nur
  CVE-2014-0160 (Heartbleed). Kein neuer ausgenutzter Eintrag.
- OpenSSL-Advisories 29.09.2026: CVE-2026-84782 (High, DTLS-Handshake),
  CVE-2026-84783 (Moderate, nur 4.0.0, X.509-Erweiterungs-Cache), mehrere Low
  (QUIC, CRLDP, Seitenkanäle); 25.08.2026: CVE-2026-63072 (Moderate, CMS).
  Laut Advisory betrifft keiner `ecparam`, `req` oder `x509`. Behobene
  Versionen: 4.0.3, 3.6.5, 3.5.9, 3.4.8, 3.0.23.

### 1.2 Neutraler Dateiname der CA (Roadmap-Punkt 1, Teil 1, #123)

- Fünf Dateien in einem PR (gekoppelt: bleibt eine beim alten Namen, findet
  nginx die CA nicht).
- Gefundene Falle: `New-LocalDevCertificates.ps1` erkennt eine vorhandene CA
  nur am Dateinamen. Nach der Umbenennung hätte es auf einem bestehenden
  Rechner still eine zweite CA erzeugt; die alte wäre in
  `Cert:\CurrentUser\Root` vertrauenswürdig geblieben. Jetzt: Abbruch, sobald
  eine Datei `local-dev-ca.{key,crt,cnf}` im Ordner liegt, mit zwei genannten
  Wegen (umbenennen oder neu beginnen).
- Lokal gemessen (Windows PowerShell 5.1, Ordner unter `%TEMP%`, ohne Trust
  Store):

| Messung | Ergebnis |
|---|---|
| alte Datei `local-dev-ca.crt` im Ordner | Abbruch mit Meldung; danach nur die alte Datei im Ordner |
| leerer Ordner | `internal-ca.{cnf,crt,key,srl}` erzeugt; Kettenprüfung edge und api bestanden |
| `bash -n`, PowerShell-Parser, Bytes > 0x7F | ohne Befund |
| restore, build, format, test | Exit 0; 2/2 Tests |
| `docker compose up --build`, `/health` über nginx | 200 |

- Die echten lokalen CA-Dateien hat die Projekt-Ownerin umbenannt
  (`internal-ca.{cnf,crt,key,srl}`); der Trust-Store-Eintrag bleibt gültig.
  Testordner danach gelöscht (Gegenprobe `ls`: nicht vorhanden).
- PR-Checks: fünf Pflicht-Checks grün, CodeQL und `Image-Scan Drittanbieter
  (nginx)` grün, `Image-Scan Drittanbieter (lego)` rot (bekannt, nur Schritt
  „Image scannen“). Im Log von `Container & nginx`: `nginx -t` zweimal
  erfolgreich, Smoke-Test mit `-CaFile certs/ca/internal-ca.crt`, `/health`
  200 „Healthy“, Security-Header vorhanden.
- Kein Rot-Beweis: keine Prüfung geändert, nur ein Name; ein falscher Pfad
  scheitert an `nginx -t` bzw. am Start von nginx.

### 1.3 Konzept Staging-CA (Roadmap-Punkt 1, Teil 2)

Entschieden, noch nicht umgesetzt: E-5-92 bis E-5-98 (Abschnitt 3). Das
vollständige Konzept steht als Roadmap-Punkt 1 unten.

### 1.4 Lehrstoff

- [Lehrstoff: Neutraler CA-Dateiname und Konzept der Staging-CA](https://claude.ai/artifact/FKUgBLSWgc6ThahxMiuZq9)
  (zwei TLS-Strecken, gekoppelte Umbenennung und stille Falle, Ort von CA und
  Schlüssel, UID-Abbildung unter rootless Docker, `pathlen`/`nameConstraints`,
  Erneuerung mit Diagramm, Fehler der Sitzung, Spickzettel)

---

## 2. Gelernt

- Ein Skript, das einen Zustand am Dateinamen erkennt, wird durch eine
  Umbenennung still blind; den Fall „alt vorhanden“ fängt man per Abbruch ab.
- Eine Abbruchprüfung ist erst belegt, wenn beide Zustände gemessen sind
  (alt vorhanden: Abbruch; leer: erzeugt).
- Die Seriennummern-Datei von openssl (`*.srl`) trägt den Namen der CA-Datei.
- nginx lädt `proxy_ssl_trusted_certificate` beim Start; fehlt die Datei,
  startet der Container nicht.
- Unter rootless Docker ist die UID im Container nicht die UID auf dem Host;
  die Abbildung steht in `/etc/subuid`.
- `pathlen:0` verbietet Unter-CAs; `nameConstraints` beschränkt die Namen, für
  die eine CA ausstellen darf, geprüft vom Client.
- `openssl x509 -checkend SEKUNDEN` endet mit Exit 0, wenn das Zertifikat nach
  dieser Zeit noch gilt; damit wird eine Erneuerung idempotent.
- Das Präfix `!` im Agenten-Prompt startet Bash, nicht PowerShell.
- Der Hook `Test-CommitConvention` liest den Betreff nur aus `-m`; mehrere
  Absätze werden als mehrere `-m` übergeben.
- „No principal matched“ bei `git log --show-signature` heißt: die lokale
  `allowed_signers` kennt den Schlüssel nicht; die Signatur selbst ist gültig.
- Der KEV-Katalog lässt sich über den JSON-Feed zuverlässig filtern; die
  Webseite zeigt nur die erste Ergebnisseite.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-92** | Staging-CA entsteht auf dem Server mit dem openssl des Systems | Schlüssel reist nie; keine neue Abhängigkeit; lokal und Staging bleiben getrennte Vertrauensbereiche |
| **E-5-93** | CA-Schlüssel auf dem Server, `root:root 0400`, außerhalb aller Compose-Mounts | rootless Docker kann ihn nicht lesen; Erneuerung per root-Timer möglich; vor Production neu bewerten |
| **E-5-94** | Zwei Skripte: `new-internal-ca.sh` (nur von Hand, bricht ab, wenn eine CA existiert) und `issue-api-certificate.sh` (Timer, bricht ab, wenn die CA fehlt) | kein Automatismus kann je eine CA erzeugen |
| **E-5-95** | API-Schlüssel gehört der per `/etc/subuid` abgebildeten UID 1654, Rechte `0400` | nur der API-Prozess liest ihn; Gegenprobe mit anderer UID nötig |
| **E-5-96** | CA: ECDSA P-256, 365 Tage, `basicConstraints critical, CA:TRUE, pathlen:0`, `nameConstraints critical, permitted;DNS:api`; API-Zertifikat 90 Tage, SAN nur `DNS:api` | gestohlener CA-Schlüssel taugt nur für `api`; kurze Laufzeiten; nur benutzte Namen |
| **E-5-97** | Täglicher systemd-Timer (root), Neuausstellung bei weniger als 30 Tagen Restlaufzeit (`-checkend`), Ping an Healthchecks.io nach jedem erfolgreichen Lauf, API-Neustart, bis das Neuladen durch Kestrel gemessen ist | idempotent; Schweigen löst Alarm aus (A09, ADR-013) |
| **E-5-98** | Dateiorte: CA-Schlüssel `/etc/identity-service/ca-private/internal-ca.key` (Ordner `0700`); CA-Zertifikat `STAGING_CA_DIR/internal-ca.crt` (`0644`); API `STAGING_API_CERT_DIR/api.{key,crt}`; Ziel-Ordner als Argumente der Skripte | konkrete Pfade erst mit dem Pull-Deploy; keine festen Werte im Skript |

Umgesetzt in dieser Sitzung (Teil von #123, kein eigener Code): neutraler
Dateiname `internal-ca.crt` und Abbruch bei alten Dateien (Option „Melden
statt reparieren“).

ADR-Kandidaten: E-5-92 bis E-5-98 gehören mit E-5-65 bis E-5-68, E-5-73 bis
E-5-76 und E-5-79 bis E-5-91 in das ADR zum Schritt DNS/TLS.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- openssl-Version auf dem Server nicht gemessen; Abgleich mit 3.0.23, 3.4.8,
  3.5.9, 3.6.5, 4.0.3 vor der ersten CA.
- `/etc/subuid` auf dem Server nicht gelesen; UID-Formel (`SUBUID_START +
  1653`) unbelegt.
- Ob Kestrel ein erneuertes Zertifikat ohne Neustart einliest: nicht gemessen.
- CA-Wechsel nach 365 Tagen: nginx muss eine Zeit lang alter und neuer CA
  vertrauen (Bündel in einer Datei); eigener Schritt, Erinnerung rund zehn
  Monate nach Erzeugung der CA.
- Lokal OpenSSL 3.2.1 (Git für Windows); der 3.2-Zweig steht nicht unter den
  behobenen Versionen der Advisories vom 29.09.2026. Für Zertifikatserzeugung
  laut Advisory ohne Belang; Git für Windows aktuell halten.
- `git log --show-signature`: „No principal matched“; lokale
  `allowed_signers` kennt den Signaturschlüssel nicht.
- `.claude/hooks/Protect-Secrets.ps1` nennt im Kommentar noch
  `local-dev-ca.key` als Beispiel (wirkungslos; Änderung nur durch die
  Projekt-Ownerin).
- `.claude/rules/container-und-nginx.md` nennt keinen CA-Dateinamen; ein Satz
  zu `internal-ca.crt` und den getrennten Vertrauensbereichen wäre sinnvoll
  (Entscheidung der Projekt-Ownerin).
- Ausführen von Skripten mit `-ExecutionPolicy Bypass` ist für den Agenten
  gesperrt; Skripttests führt die Projekt-Ownerin aus.
- Lokale gemergte Branches löschen (Freigabe nötig): Liste aus Bericht 24 plus
  `refactor/neutral-ca-filename`.
- Remote-Branch `test/staging-red-proof` (aus Bericht 24): Stand nicht geprüft.

**Aus Sitzung 24 und früher, weiter offen**

- **lego-Gate rot** bis zu einem lego-Release mit Go ≥ 1.27.3 und `x/net` ≥
  0.60.0. Release-Stand in dieser Sitzung nicht geprüft. Jeder CI-Lauf auf
  `main` ist rot; bei #123 nur durch `Image-Scan Drittanbieter (lego)`.
  CI-Lauf zu `15a3f7e` auf `main` nicht einzeln geprüft.
- `Publish lego` grün noch nie gelaufen.
- `worker_processes auto` gegen `pids_limit: 64`: Kernzahl des Servers prüfen.
- `pids_limit: 256` der API ohne Gegenprobe.
- `scripts/test-staging-config.sh` lokal nicht lauffähig (`jq` fehlt); auf dem
  Server muss `jq` vorhanden sein.
- lego ohne `tmpfs`: beim ersten Lauf messen.
- Herkunft der Pflichtvariablen auf dem Server und Ort von
  `server_name.conf`: beim Pull-Deploy.
- `--key-type ec256` im lego-Timer ausdrücklich setzen.
- Catch-all 443 mit passender SNI und fremdem Host: generisches 404 ohne
  Security-Header.
- Prüfskript prüft die Netze der API nicht.
- M1 und M2 unter rootless Docker auf dem Server wiederholen.
- Push- und Digest-Logik doppelt in `publish.yml` und `publish-lego.yml`.
- Gegenproben in `verify-attestations.sh` akzeptieren jeden Fehler.
- Paketliste in GHCR nicht abrufbar (Token ohne `read:packages`).
- `Test-Stack.ps1` lokal nicht lauffähig (Hook blockiert `-CaFile`).
- Nachträge zu ADR-005, ADR-009, ADR-010, ADR-011, ADR-012, ADR-014.
- Release Notes von #106 und #108 nicht gemeinsam gelesen.
- Docker 29.9.2 auf dem Server nicht gemessen.
- CVE-2026-111943 bei NVD und CISA KEV nicht geprüft.
- `Image-Scan Drittanbieter` als Required Check: fällig vor dem ersten Deploy
  von lego.
- ADR-006, ADR-008, ADR-012, ADR-013, ADR-014 auf „Vorgeschlagen“.
- Arbeitsdateien im ignorierten Ordner `scan/`.
- Signatur der distroless-Basis nicht selbst geprüft.
- CAA um `accounturi` und `validationmethods=http-01`; TTL des A-Eintrags.
- KEV-Einträge vom 16.10.2026 nicht namentlich geprüft.
- Healthchecks.io: Beschreibung kürzen (freigestellt), Ping-URL im Verlauf der
  Zwischenablage, IPv4-Erreichbarkeit von `hc-ping.com`, zweiter Warnkanal vor
  Production, Gegenprobe „Update-Lücke über 26 Stunden“.
- Frist des Journals ab 18.11.2026; runc 1.5.2 und CVE-2026-41579; NTS und
  netcup-Regel `ntp-antworten`; Journal von `nft-rollback.service`;
  Maschinenkonto.
- **Token des Agenten läuft am 06.11.2026 ab** (in 9 Tagen).

**Bekannte Grenzen**

- Alle Messungen dieser Sitzung lokal (Windows, Docker Desktop) und in der
  CI; nichts auf dem Server.
- Domain, Server-IPs, Hostnamen und Benutzernamen stehen bewusst nicht in
  diesem Bericht (öffentliches Repository, ADR-004).

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Neu: neutraler CA-Dateiname auf `main`; Konzept der
Staging-CA entschieden.

Bis zum Beginn von Phase 5 fehlen:

| Nr. | Schritt | Abhängig von |
|---|---|---|
| 1 | ~~Staging-Konfiguration~~ erledigt (#118, #119, #121) | – |
| 2 | Interne CA auf dem Server: ~~Dateiname~~ (#123), ~~Konzept~~ (E-5-92 bis E-5-98), Messungen, Skripte, Timer | – |
| 3 | Ports 80/443, erstes Zertifikat, Gegenprobe 9, CAA, Timer (E-5-76) | 2, **veröffentlichtes lego-Image** |
| 4 | Maschinenkonto (ADR-011) | – |
| 5 | Pull-Deploy mit Prüfung von Nachweis, Signatur und Staging-Konfiguration | 2, 4 |
| 6 | Freigabe vor dem Deploy, DORA-Events | 5 |
| 7 | DAST (OWASP ZAP) | 5, 6 |

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Berührt: keine neue Abhängigkeit (openssl des Systems, E-5-92) |
| **Zero Trust / A01** | `proxy_ssl_verify on` unverändert; Staging-CA mit `nameConstraints` geplant |
| **A09 (Alerting)** | Ping nach jeder Erneuerung geplant (E-5-97) |
| **A10 / fail closed** | Abbruch bei alten CA-Dateien; Skripte brechen bei fehlender bzw. vorhandener CA ab |
| **Image-Gate für fremde Images** | lego rot, nginx grün; noch kein Required Check |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **mTLS** | Rückt näher: dieselbe CA könnte Client-Zertifikate ausstellen (dann `nameConstraints` erweitern, eigene Entscheidung) |
| **DAST** (OWASP ZAP) | Fällig mit dem ersten automatischen Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing** | Rückt näher (weitere Microservices geplant) |
| **Feature Flags, Mutation Testing, k6** | Nicht fällig |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Stände (28.10.2026)

| Gegenstand | Wert | Quelle |
|---|---|---|
| CISA KEV, Katalog | 2026.10.27; OpenSSL nur CVE-2014-0160 | JSON-Feed `known_exploited_vulnerabilities.json` |
| OpenSSL, behobene Versionen (Advisory 29.09.2026) | 4.0.3, 3.6.5, 3.5.9, 3.4.8, 3.0.23 | openssl-library.org/news/vulnerabilities |
| openssl lokal | 3.2.1 (Git für Windows) | Ausgabe von `New-LocalDevCertificates.ps1` |
| `main` nach der Sitzung | `15a3f7e` | `git log` |

Keine neuen Digests oder Action-Pins in dieser Sitzung.

### 6.2 CA-Dateien

| Umgebung | Ort | Erzeugt von |
|---|---|---|
| lokal | `certs/ca/internal-ca.{key,crt,cnf,srl}` | `scripts/New-LocalDevCertificates.ps1` |
| CI | `certs/ca/internal-ca.crt` (Schlüssel nach dem Signieren gelöscht) | `scripts/new-throwaway-certificates.sh` |
| Staging (geplant) | Schlüssel `/etc/identity-service/ca-private/internal-ca.key`; Zertifikat `STAGING_CA_DIR/internal-ca.crt` | `new-internal-ca.sh` (geplant) |
| in nginx | `/etc/nginx/ca/internal-ca.crt` | Mount, `nginx/snippets/proxy-api.conf` |

### 6.3 Fallstricke, die Zeit gekostet haben

- `!` im Prompt startet Bash: `Remove-Item` scheitert mit `command not found`.
- `git commit -F DATEI` wird vom Hook `Test-CommitConvention` abgewiesen
  („Betreff nicht lesbar“); stattdessen mehrere `-m`.
- `powershell.exe -ExecutionPolicy Bypass -File ...` ist für den Agenten
  gesperrt (Klassifikator „Security Weaken“); die Projekt-Ownerin führt den
  Befehl ohne `-ExecutionPolicy` aus.
- Die KEV-Webseite mit Suchparameter zeigt nicht gefilterte erste
  Ergebnisse; der JSON-Feed ist verlässlich.

### 6.4 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl oder Ort (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| KEV filtern | Aktualität vor Werkzeugentscheidung | `Invoke-RestMethod` auf den JSON-Feed, Filter `openssl` | nur CVE-2014-0160 |
| Abbruch bei alter CA | stille zweite CA verhindern | Skript gegen Ordner mit `local-dev-ca.crt` | Abbruch, keine neue Datei |
| Gegenprobe | Pfad „neu“ funktioniert | Skript gegen leeren Ordner | `internal-ca.*`, Kette bestanden |
| Umbenennen lokal | nginx findet sonst die CA nicht | `mv -n` je Endung | vier Dateien umbenannt |
| Stack lokal | Pfad im Container wirksam | `docker compose up --build`, `curl.exe --ssl-no-revoke` | `/health` 200 |
| CI-Log | Grün ist nicht funktionierend | `gh run view --log --job` | Smoke-Test mit `internal-ca.crt`, `nginx -t` erfolgreich |

---

# Roadmap Sitzung 26

## 1. Staging-CA auf dem Server

Warum zuerst: nginx prüft auf Staging das Zertifikat der API
(`proxy_ssl_verify on`); `STAGING_CA_DIR` und `STAGING_API_CERT_DIR` sind
Pflicht, aber noch leer. Hängt nicht von lego ab. Das Konzept ist entschieden
(E-5-92 bis E-5-98); jetzt messen, dann Skripte.

**Konzept (entschieden):**

1. **Zwei Skripte (E-5-94).** `new-internal-ca.sh` legt die CA an, nur von
   Hand, und bricht ab, wenn schon eine existiert. `issue-api-certificate.sh`
   stellt das API-Zertifikat aus, aufgerufen vom Timer, und bricht ab, wenn die
   CA fehlt. Kein Automatismus kann eine CA erzeugen.
2. **Rechte unter rootless Docker (E-5-95).** Container-UID 1654 entspricht
   auf dem Host `SUBUID_START + 1653` (`/etc/subuid`). Der API-Schlüssel gehört
   dieser UID, Rechte `0400`. Gegenprobe: Ein Container mit anderer UID kann
   ihn nicht lesen. Das CA-Zertifikat für nginx ist öffentlich, `0644`.
3. **CA-Parameter (E-5-96).** ECDSA P-256; CA 365 Tage;
   `basicConstraints = critical, CA:TRUE, pathlen:0`;
   `nameConstraints = critical, permitted;DNS:api`; `keyUsage = critical,
   keyCertSign, cRLSign`. API-Zertifikat 90 Tage, SAN nur `DNS:api`,
   `extendedKeyUsage = serverAuth`. CA-Wechsel nach einem Jahr braucht eine
   Übergangszeit mit beiden CAs (späterer Schritt).
4. **Erneuerung und Warnung (E-5-97).** Täglicher systemd-Timer als root;
   `openssl x509 -checkend` mit 30 Tagen; nur bei Bedarf neu ausstellen; Ping
   an Healthchecks.io nach jedem erfolgreichen Lauf (ADR-013), fehlender Ping
   = Alarm. API-Neustart nach dem Ausstellen, bis gemessen ist, ob Kestrel das
   Zertifikat selbst neu einliest.
5. **Dateiorte (E-5-98).** CA-Schlüssel
   `/etc/identity-service/ca-private/internal-ca.key`, `root:root 0400`,
   Ordner `0700`. CA-Zertifikat `STAGING_CA_DIR/internal-ca.crt`, `0644`. API
   `STAGING_API_CERT_DIR/api.key` und `api.crt`, abgebildete UID 1654,
   Schlüssel `0400`. Ziel-Ordner sind Argumente der Skripte.

**Reihenfolge:**

- Messung auf dem Server: `openssl version` (Abgleich mit 3.0.23, 3.4.8,
  3.5.9, 3.6.5, 4.0.3).
- Messung auf dem Server: Eintrag des Docker-Benutzers in `/etc/subuid`.
- Messung: Anzahl Kerne (`nproc`) für `worker_processes` gegen
  `pids_limit: 64` (offen seit Bericht 24; beim selben Besuch).
- Skripte schreiben (Bash, ASCII, unterscheidbare Exit-Codes, `bash -n`), in
  CODEOWNERS-Pfad `scripts/`; Rot-Beweis für die Abbrüche (CA vorhanden bzw.
  fehlt).
- CA auf dem Server erzeugen; API-Zertifikat ausstellen; Rechte mit `stat`
  und Gegenprobe prüfen.
- Timer und Ping einrichten; Gegenprobe „Ping bleibt aus“.
- Vor sicherheitsrelevanten Werkzeugentscheidungen: Aktualität nach CLAUDE.md
  Abschnitt 1.

## 2. lego-Release prüfen; wenn neu: Ports 80/443 und erstes Zertifikat

Warum: E-5-74. In dieser Sitzung nicht geprüft. Wenn es ein Release mit
Go ≥ 1.27.3 und `x/net` ≥ 0.60.0 gibt: Pin anheben, `Publish lego` grün, erstes
Zertifikat (Empfehlung Standalone + sofortiger Webroot-Renew), M1/M2 unter
rootless Docker. Wenn nein: Punkt 3 vorziehen.

## 3. Maschinenkonto und Pull-Deploy mit Gate

Warum: braucht kein öffentliches Zertifikat. Der Server prüft vor dem Start
Nachweise (`verify-attestations.sh`) und die Konfiguration
(`test-staging-config.sh`, `jq` auf dem Server). Festlegen, wo die
Pflichtvariablen und `STAGING_CA_DIR`/`STAGING_API_CERT_DIR` liegen.

## 4. Server: Docker-Update beobachten

Warum: Docker 29.9.2 ist der Auslöser „nächstes echtes Docker-Update“; offen
seit Bericht 22.

## 5. Kleine Folge-PRs (nach Bedarf)

- `worker_processes` fest setzen, falls die Kernzahl es nahelegt
- Regel-Satz in `.claude/rules/container-und-nginx.md` zu `internal-ca.crt`,
  Staging-Dateien und Snippets (Entscheidung der Projekt-Ownerin)
- Push- und Digest-Logik aus `publish.yml` und `publish-lego.yml`
  zusammenführen
- Gegenproben in `verify-attestations.sh` auf den erwarteten Fehler eingrenzen

## 6. Zurückgestellt, nicht aufgehoben

- **ADR-Nachträge:** ADR-010 (E-5-78), ADR-014 (E-5-70, E-5-71, E-5-77),
  ADR-005 (E-5-72, Cooldown), ADR-009 (`Unknown`), ADR-011, ADR-012
- **ADR zum Schritt DNS/TLS:** E-5-65 bis E-5-68, E-5-73 bis E-5-76,
  E-5-79 bis E-5-98
- **Vor Production:** NTS, IPv6, zweiter Warnkanal, HSTS auf ein Jahr,
  Neubewertung von E-5-93 (CA-Schlüssel offline?)

## 7. Vor oder in der Sitzung zu verstehen (vor Code)

- **User Namespace bei rootless Docker:** Jede UID im Container wird auf eine
  andere UID auf dem Host abgebildet; der Bereich steht in `/etc/subuid`.
  Dateirechte für Bind-Mounts gelten für die Host-UID, deshalb wird die UID
  der API umgerechnet.
- **`nameConstraints` und `pathlen:0`:** Sie begrenzen, was die CA ausstellen
  kann. Ein gestohlener Schlüssel taugt dann nur für Endzertifikate mit dem
  Namen `api`; die Prüfung macht der Client (nginx).
- **Idempotente Erneuerung mit Lebenszeichen:** Der Timer prüft täglich und
  handelt nur bei Bedarf; jeder erfolgreiche Lauf pingt. Nicht der Fehler löst
  den Alarm aus, sondern das Ausbleiben des Pings.
- Lehrstoff zu dieser Sitzung:
  [Lehrstoff: Neutraler CA-Dateiname und Konzept der Staging-CA](https://claude.ai/artifact/FKUgBLSWgc6ThahxMiuZq9)

## 8. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- **Erneuerung des Agenten-Tokens vor dem 06.11.2026**
- Gemergte lokale Branches und Remote-Branch `test/staging-red-proof` löschen
- Git für Windows aktualisieren (openssl 3.2.1)
- Unter Profil → Packages prüfen, dass es kein Paket `identity-service-lego`
  gibt
