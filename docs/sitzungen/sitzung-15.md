# Sitzungsbericht Sitzung 15

**Datum:** 17.10.2026
**Phase:** Schritt 5 (CD): Threat-Modeling für den Staging-Server abgeschlossen, ADR-011 akzeptiert, Server und Domain bestellt und geliefert (Härtung folgt in Sitzung 16)
**Vorgänger:** sitzung-14.md (abgeschlossen 17.10.2026)

---

## 1. Erledigt

### 1.1 Bericht 14 veröffentlicht (PR #87)

Branch `docs/sitzung-14`, alle sechs Pflicht-Checks grün, von der
Projekt-Ownerin gemergt (`e114045`).

### 1.2 Primärquellen zu GHCR und Maschinenkonten (17.10.2026)

- **GitHub-Doku „Working with the Container registry“:** „GitHub Packages
  only supports authentication using a personal access token (classic).“
  Zum Herunterladen genügt der Scope `read:packages`. Fein abgestufte Tokens
  werden nicht genannt.
- **GitHub-Doku „Configuring a package's access control and visibility“:**
  „Once you make a package public, you cannot make it private again.“ Ein
  Paket kann die Zugriffsrechte des verknüpften Repositorys erben;
  Lesezugriff lässt sich je Paket an einzelne Konten vergeben.
- **GitHub Terms of Service, Abschnitt B.3:** „You may maintain no more than
  one free machine account in addition to your free Personal Account.“ Ein
  Maschinenkonto dient ausschließlich automatisierten Aufgaben; die Person,
  die es anlegt, bleibt verantwortlich.
- Folgerung: Ein klassisches Token gilt für das ganze Konto und lässt sich
  nicht auf ein Paket begrenzen. Die Empfehlung aus Sitzung 14 („privat mit
  Lese-Token des Hauptkontos“) war zu breit und wurde geändert (E-5-21).
- Die Abfrage der eigenen Pakete über die API scheiterte mit HTTP 403, weil
  das Token des Agenten nur für das Repository gilt (gewollt). Die
  Projekt-Ownerin hat selbst nachgesehen: Heute gibt es nur das Paket
  `identity-service`. Weitere Microservices sind geplant.

### 1.3 Threat-Modeling Staging-Server (STRIDE) abgeschlossen

Ausgangspunkt war der Entwurf aus Sitzung 14. Beim Überarbeiten kamen vier
Lücken im Systemmodell dazu, von der Projekt-Ownerin bestätigt:

1. Domain-Registrar und DNS als eigene Vertrauensgrenze (wegen E-5-22)
2. Das nginx-Image kommt von Docker Hub, ohne Herkunftsnachweis von uns,
   geschützt nur durch den Digest-Pin in `compose.yaml`
3. Der Weg der Konfiguration (`compose.yaml`, `nginx.conf`) auf den Server
   fehlte ganz; ohne Prüfung könnte er das Prüf-Gate umgehen
4. Die Uhrzeit (NTP) ist Voraussetzung für die Gültigkeit von Zertifikaten
   und Nachweisen

Ergebnis: sieben Vertrauensgrenzen, eine STRIDE-Tabelle mit Maßnahmen und
akzeptierten Risiken, vier Missbrauchsfälle als künftige Testfälle. Neue
Befunde beim Durchgehen:

- Squash-Merges auf `main` signiert GitHub mit dem eigenen
  Web-Flow-Schlüssel, nicht mit dem Schlüssel der Projekt-Ownerin. Eine
  Signaturprüfung auf dem Server muss diesem Schlüssel vertrauen (E-5-25).
- Ein Deploy-Agent in der Gruppe `docker` ist faktisch Root auf dem Host.
  Der Vorschlag „eigener Benutzer ohne Rechte“ wäre Scheinsicherheit
  (E-5-26, offen).
- Fail closed heißt beim Deploy: Kein neues Image startet ungeprüft. Der
  laufende Dienst wird dabei nicht abgeschaltet.

`compose.yaml` wurde gelesen: Beide Container setzen bereits `read_only`,
`no-new-privileges`, `cap_drop`, `mem_limit` und `cpus`.

Alle Details stehen in ADR-011.

### 1.4 ADR-011 akzeptiert (PR #88)

`docs/adr/ADR-011-staging-ziel-und-pull-deploy.md`, Status „Akzeptiert“
(von der Projekt-Ownerin gesetzt). Inhalt: Entscheidung, Teilentscheidungen
E-5-16, E-5-17 und E-5-21 bis E-5-26, Systemmodell, Härtungsliste, vier
Missbrauchsfälle, acht betrachtete Alternativen (davon ehrlich vermerkt:
kein Detailvergleich anderer Anbieter), Konsequenzen, Abschnitt „Staging ist
nicht Production“, Auslöser für eine Neubewertung. Alle sechs Pflicht-Checks
grün, gemergt (`16a0b3d`).

Die Nummern ADR-006 und ADR-008 bleiben für die vorgemerkten ADRs
reserviert.

### 1.5 Lokale Branches aufgeräumt

`docs/sitzung-14` (`d3975ec`) und `docs/adr-011-staging-ziel-und-pull-deploy`
(`84c8921`) entsprachen exakt dem Kopf-Commit ihres gemergten PR (#87, #88)
und wurden gelöscht (E-H-20). Lokal existiert nur `main` (`16a0b3d`).

### 1.6 Server und Domain bestellt und geliefert (17. und 18.10.2026)

Grundlage: aktuelle Angebote auf netcup.com (gelesen am 17.10.2026, Quellen
in Abschnitt 6). Bestellt hat die Projekt-Ownerin:

- **netcup RS 500 G12.5** (Root-Server): AMD EPYC 9645, 2 dedizierte Kerne,
  4 GB RAM, 64 GB NVMe, Snapshots, Remote-Konsole; 1 Monat
  Vertragslaufzeit; 14,99 € pro Monat inkl. 20 % MwSt. (Angabe aus dem
  Bestellvorgang)
- Standortwahl „Keine Präferenz Europa“ (günstiger); zugewiesener Standort
  laut Projekt-Ownerin: **Wien**
- Domain **`waveleg.at`** bei netcup, aktiv; die Registrierungsstelle hat das
  Domain-Zertifikat (Inhaberbestätigung, PDF) an die Inhaber-E-Mail-Adresse
  gesandt
- Keine Zusatzprodukte
- 2FA am netcup-Konto vor der Bestellung eingeschaltet (laut
  Projekt-Ownerin: Empfehlungen befolgt)

Die Bestellung wurde vor der Ausführung von netcup manuell geprüft (übliche
Prüfung neuer Kunden gegen Missbrauch).

Geliefert: **Debian 13 (trixie) minimal**, Kernel `6.12.113+deb13-amd64`
vom 15.10.2026. netcup liefert den Server mit einer vorkonfigurierten
Firewall im Server Control Panel aus, darunter die Policy „netcup Mail
Block“ (sperrt SMTP ein- und ausgehend). Sie bleibt bestehen: Der Server
versendet keine E-Mails.

Erster Login (18.10.2026), von der Projekt-Ownerin selbst ausgeführt:

- `ssh root@<Hostname>`; der angezeigte ED25519-Fingerprint wurde mit dem
  Fingerprint aus der netcup-E-Mail verglichen: **stimmt**
- Startpasswort (kam per E-Mail) sofort mit `passwd` durch ein langes,
  zufälliges Passwort ersetzt: **erfolgreich** (gemeldet, nicht gemessen;
  Gegenprobe steht aus)
- Sonst nichts eingerichtet

Zugangsdaten, IP-Adresse und Fingerprints wurden nicht in die Sitzung
eingefügt.

---

## 2. Gelernt

- GHCR akzeptiert nur klassische Tokens; die einzige Grenze eines klassischen
  Tokens ist das Konto, das es ausstellt. Least Privilege bei GHCR heißt
  deshalb: eigenes Maschinenkonto.
- Ein öffentliches GitHub-Paket lässt sich nicht wieder privat machen.
- Bei mehreren Services wächst die Reichweite eines Tokens des Hauptkontos
  unbemerkt mit; beim Maschinenkonto nur durch eine bewusste Freigabe je
  Paket (deny-by-default auf Infrastrukturebene).
- Ein Threat Model ist nur so gut wie das Systemmodell. Erst beim zweiten
  Durchgang fielen DNS, Docker Hub, der Weg der Konfiguration und die
  Uhrzeit auf.
- Wer den Weg der Konfiguration nicht prüft, kann das Prüf-Gate für Images
  umgehen, etwa mit einem anderen Digest in `compose.yaml`.
- Mitglieder der Gruppe `docker` können sich jederzeit Root-Rechte auf dem
  Host verschaffen. Ein eigener Benutzer schützt dann nicht.
- Squash-Merges auf GitHub tragen die Signatur von GitHub, nicht die der
  Person, die mergt.
- Ein CAA-Eintrag im DNS legt fest, welche Zertifizierungsstelle für eine
  Domain Zertifikate ausstellen darf.
- Staging und Production teilen das Image, nicht den Server: akzeptierte
  Risiken, absichtliche Angriffe (DAST) und das Verbot echter Daten gelten
  nur für Staging.
- Der Commit-Hook prüft den Branch vor dem ganzen Befehl. Branch-Wechsel und
  Commit gehören in getrennte Aufrufe.
- Nicht die Zahl der Container füllt eine Platte, sondern Speicher, der sich
  unbemerkt ansammelt: alte Image-Versionen nach jedem Deploy und Logs, die
  Docker standardmäßig nicht begrenzt.
- Bei netcup ist der Standort eines Servers nach der Bestellung nicht mehr
  änderbar.

---

## 3. Entscheidungen (ADR-Kandidaten)

Alle in **ADR-011** dokumentiert (akzeptiert).

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-21** | GHCR bleibt privat; der Server liest mit einem klassischen Token (nur `read:packages`, Ablaufdatum, Rotation) eines eigenen Maschinenkontos; Lesezugriff je Service-Paket einzeln | Einzige Möglichkeit, das Token auf einzelne Pakete zu begrenzen; öffentlich wäre unumkehrbar |
| **E-5-22** | Eigene Domain, Zertifikat von Let's Encrypt, CAA-Eintrag | Realistische Tests für HSTS und DAST; keine Gewöhnung an Zertifikatswarnungen |
| **E-5-23** | Konfiguration per `git pull` aus dem Repository, Übernahme erst nach Prüfung der Commit-Signatur | „Prüfen, dann übernehmen“ auch für die Konfiguration, ohne zusätzliches Artefakt |
| **E-5-24** | Für Staging akzeptierte Risiken: volumetrischer DoS, Logs nur lokal (bis vor Production), nginx-Image nur per Digest | Staging hat keine echten Daten; Schutz steht in keinem Verhältnis |
| **E-5-25** | Der Web-Flow-Schlüssel von GitHub gilt als vertrauenswürdige Signatur für `main` | Squash-Merges signiert GitHub; das Ruleset setzt GitHub ohnehin als Richter ein |
| **E-5-26** | Docker-Rechte des Deploy-Agenten (Gruppe `docker`, Rootless Docker, Podman) bleiben offen bis Sitzung 16 | Werkzeugwahl mit Pflichtrecherche; Gruppe `docker` wäre faktisch Root |
| **E-5-27** | Staging läuft auf einem RS 500 G12.5 (Root-Server, dedizierte Kerne) statt eines VPS; bestellt mit Standortwahl „Keine Präferenz Europa“, zugewiesen wurde Wien. Vor Production wird der Standort neu bewertet (**Nachtrag zu ADR-011**) | Günstiger; dedizierte Kerne liefern stabilere Messwerte; kein Sicherheitsnachteil (EU-Rechenzentren, keine echten Daten); monatlich kündbar, also praktisch umkehrbar |
| **E-5-28** | Die Vorgabe „≤ 15 € pro Monat“ gilt für den Server; die Domain (rund 1,05 € pro Monat) kommt hinzu (**Nachtrag zu ADR-011**) | Klarstellung der Projekt-Ownerin |

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- Server bestellen und Domain kaufen (Projekt-Ownerin; siehe Roadmap,
  Punkt 1)
- E-5-26: Docker-Rechte des Deploy-Agenten
- Authentifizierte Zeit (NTS) ja oder nein
- Ob das nginx-Image signiert veröffentlicht wird, ist nicht geprüft
- `compose.yaml` setzt kein `pids_limit` (bei der Suche nach den
  Sicherheitseinstellungen aufgefallen, nicht bewertet)
- Staging braucht eine Variante von `compose.yaml`, die das veröffentlichte
  Image per Digest startet statt lokal zu bauen (Erweiterung, Sitzung 17)
- Werkzeug, das den Ablauf des TLS-Zertifikats überwacht, ist offen
- **Nachtrag zu ADR-011 fällig:** ADR-011 nennt „netcup VPS in Wien“; bestellt
  ist ein RS 500 G12.5 (E-5-27), Budget-Klarstellung (E-5-28), Debian 13
  statt des in der Sitzung genannten Ubuntu LTS, Plattenplatz (siehe unten)
- Gegenprobe zum Passwortwechsel: Ein Login mit dem alten Startpasswort muss
  scheitern (nicht gemessen)
- Debian 13 minimal ist vorinstalliert; Eignung (Support-Zeitraum,
  Sicherheitsupdates, Container-Laufzeit ohne Root) nicht geprüft
- Der Server ist online, Root-Login per Passwort ist noch aktiv (Passwort
  geändert, Härtung steht aus)
- Ob die netcup-Firewall im Server Control Panel zusätzlich zur Firewall auf
  dem Server genutzt wird, ist offen
- Ob die DNS-Verwaltung von netcup CAA-Einträge anbietet, ist nicht belegt
  (in der netcup-Dokumentation nicht erwähnt). Fehlt CAA, braucht es einen
  anderen DNS-Dienst (neue Abhängigkeit mit Aufnahme-Prüfung)
- Ob die Domain eine Transfer-Sperre hat, ist nicht geprüft
- **Plattenplatz als DoS-Risiko (Nachtrag zu ADR-011 fällig):** drei Punkte
  ergänzen die Härtungsliste, siehe Roadmap, Punkt 3
- DORA-Events: Token mit Schreibrecht auf dem Server oder nur lokales
  Protokoll (Sitzung 18)
- Recherche: OWASP und thehackernews.com wieder nicht eigens abgefragt

**Aus Sitzung 14, weiter offen**

- Telemetrie der Testplattform (`Microsoft.Testing.Extensions.Telemetry`):
  Was wird gesendet, Abschalten in der CI?
- Test-Explorer von Visual Studio 2026 mit dem neuen Stand nicht
  ausprobiert
- Runtime 10.0.13 nur am lokal gebauten Image gemessen, nicht am Image aus
  der Registry
- Warum `ls docs/sitzungen/` in Sitzung 13 `sitzung-12.md` nicht anzeigte
  (vermutlich Arbeitsverzeichnis auf altem Stand, nicht belegt)

**Aus Sitzung 13 und früher, weiter offen**

- Nachtrag zu ADR-009: Grype meldet den Patch-Stand der .NET-Runtime
- Warum die sechs libc-Funde der Stufe Medium im Scan zu #83 fehlen
- Rot-Beweis für „Publish“ bei fehlschlagendem Smoke-Test
- Der Lauf von „Publish“ zu `a414d8e` (#81) ist rot; für diesen Commit liegt
  gewollt kein Image in der Registry
- Skill-Schritte 2 und 3 (E-H-14), zurückgestellt (E-H-19)
- Ob `disable-model-invocation` in der eingesetzten Claude-Code-Version wirkt
- Warum Dependabot #78 mit „no longer updatable“ schloss; Bot-Titel ohne
  `(deps)` bei #77
- Nachtrag zu ADR-005; ADR-006 und ADR-008 nachschreiben (Nummern
  reserviert)
- „Publish“ ist kein Pflicht-Check; Aufräumregel für die Registry fehlt
- Ob Dependabot den Pin von `actions/attest` pflegt; Version von `gh` auf dem
  Runner nicht festgelegt
- Wegwerf-Zertifikate der Pipeline weichen von den lokalen ab;
  `scripts/invoke-image-scan.sh` läuft lokal nicht (`jq` fehlt)
- `nginx.conf` ohne `limit_req_status` und `proxy_ssl_verify_depth`;
  Gegentest zu `proxy_ssl_verify` fehlt
- Projektauftrag und `Test-RepoState.ps1` nicht im Repository; veralteter
  Kommentar zum Locked Mode in `Directory.Build.props`; `README.md` ohne
  Befehle; `sitzung-01.md` fehlt
- HSTS bewusst auf `max-age=300`
- Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches“ nicht eingeschaltet
- Dieser Bericht ist noch nicht committet

**Bekannte Grenzen**

- Der Herkunftsnachweis liegt in einem öffentlichen, unveränderlichen
  Protokoll
- Bei Container-Images wendet Dependabot keine Wartefrist an
- Für Staging akzeptierte Risiken nach E-5-24

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD): Teil A fertig, Prüf-Gate belegt, Threat-Modeling
und ADR-011 abgeschlossen. Es fehlen:

- Staging-Server (bestellen, einrichten, härten)
- Pull-Deploy mit Gate auf dem Server
- Freigabe vor dem Deploy
- DORA-Events

| Thema | Status |
|---|---|
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet; wird mit dem zweiten Service dringlich |
| **Contract Testing** | Rückt näher: weitere Microservices sind geplant; fällig, sobald zwei Services einen API-Vertrag teilen |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher (gleicher Auslöser) |
| **DAST** (OWASP ZAP) | Wird mit dem ersten Staging-Deploy fällig (Plan: Sitzung 18); die Domain macht ihn realistisch |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Lieferketten-Gate** | Berührt: nginx von Docker Hub ohne eigenen Nachweis, akzeptiert (E-5-24); jedes Werkzeug auf dem Server wird eine Abhängigkeit mit Vetting |
| **Agentic-Gate 6.5** | Nicht ausgelöst |
| **Mutation Testing, k6, LLM-Gate 6.4** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

Keine neuen Pins in dieser Sitzung. Es gelten die Stände aus
`sitzung-14.md` und `sitzung-13.md`.

**Primärquellen dieser Sitzung (gelesen am 17.10.2026):**

- `https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry`
- `https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility`
- `https://docs.github.com/en/site-policy/github-terms/github-terms-of-service`
  (Abschnitt B.3)
- `https://www.netcup.com/de/server/vps` (Produkte, Laufzeiten 1/12/24
  Monate, Standorte VIE/NUE/AMS/MNZ/SIN, Standort nicht nachträglich änderbar)
- `https://www.netcup.com/de/domain/domain-endungen` und
  `https://www.netcup.com/de/domain/zusaetzliche-domain-at` (`.at`: 1,05 €
  pro Monat, 12 Monate Mindestlaufzeit, Sitz in Österreich nötig; CAA nicht
  erwähnt)
- `https://www.netcup.com/en/helpcenter/documentation/domain/dns-settings-cloud-dns`
  (Beispiele für Eintragstypen, CAA nicht erwähnt)

**Läufe dieser Sitzung:**

```
39062990299  CI an #87 (Build & Test, Container & nginx, Image-Scan), grün
39062990315  CodeQL an #87, grün
39062990316  PR-Titel an #87, grün
```

Die Checks an #88 waren alle grün; ihre Lauf-IDs wurden nicht notiert.

**Commits auf `main`:**

```
16a0b3d  docs(adr): add ADR-011 staging target and pull deploy (#88)
e114045  docs: add session report 14 (#87)
```

**Fallstricke, die Zeit gekostet haben:**

- `gh api /user/orgs` in Git Bash: Der führende Schrägstrich wird als
  Dateipfad umgeschrieben (`C:/Program Files/Git/user/orgs`); Endpunkt ohne
  führenden Schrägstrich angeben
- Commit-Hook blockiert `git switch -c … && git commit …` auf `main`;
  getrennte Aufrufe verwenden

---

# Roadmap Sitzung 16

## 1. Härtung beginnen: Server ist online (Einstieg)

Warum zuerst: Der Server (RS 500 G12.5, Debian 13 minimal, Standort Wien)
und die Domain `waveleg.at` sind geliefert (Abschnitt 1.6). Root-Login per
Passwort ist noch aktiv; das Startpasswort ist ersetzt, die Härtung steht
aus. Jeder Tag bis dahin ist ein offenes Fenster für automatisierte
Angriffe. Sitzung 16 sollte deshalb bald stattfinden und mit der Härtung
beginnen.

Zum Einstieg:

- Gegenprobe Passwortwechsel: Login mit dem alten Startpasswort muss
  scheitern
- Nachsehen, ob die DNS-Verwaltung von netcup den Eintragstyp **CAA**
  anbietet, und ob eine Transfer-Sperre für die Domain aktiv ist
- netcup-Firewall im Server Control Panel ansehen (Policy „netcup Mail
  Block“ bleibt); entscheiden, ob sie als äußere Schicht zusätzlich zur
  Firewall auf dem Server genutzt wird (Defense in Depth)
- Das Maschinenkonto erst im Zuge von Punkt 3 anlegen
- Zugangsdaten, Passwörter, Tokens, IP-Adresse und Fingerprints nie in eine
  Sitzung einfügen. Befehle führt die Projekt-Ownerin selbst aus und meldet
  nur das Ergebnis

Ist beides noch nicht erledigt, beginnt die Sitzung mit Punkt 4
(Nachträge) und der Recherche aus Punkt 2.

## 2. Pflichtrecherche und Werkzeugentscheidungen

Warum: Jedes Werkzeug auf dem Server ist eine Abhängigkeit (CLAUDE.md
Abschnitt 5). Vor der Einrichtung CVEs (CISA KEV), OWASP und
thehackernews.com prüfen; Versionen aus Primärquellen.

- **Betriebssystem:** vorinstalliert ist Debian 13 (trixie) minimal.
  Support-Zeitraum, Sicherheitsupdates (`unattended-upgrades`), Quelle des
  netcup-Images; Ziel ist, Debian 13 zu behalten, sofern nichts dagegen
  spricht
- **E-5-26:** Docker-Rechte des Deploy-Agenten. Optionen Gruppe `docker`
  (faktisch Root, akzeptiertes Risiko), Rootless Docker, Podman ohne Root;
  Trade-offs (Kompatibilität mit `compose.yaml`, Port 443/80 ohne Root,
  Pflege). ADR-Kandidat
- **NTS** für die Uhrzeit: ja oder nein (Werkzeug, Aufwand, Nutzen)

## 3. Server einrichten und härten (Härtungsliste aus ADR-011)

Warum: ADR-011 legt fest, was der Server erfüllen muss, bevor er ein Image
startet. Die Projekt-Ownerin führt die Befehle selbst aus und lernt dabei
(Vorgabe aus E-5-17).

- SSH nur mit Schlüssel (ed25519), kein Passwort, kein Root-Login
- Firewall: nur 22, 80, 443
- Automatische Sicherheitsupdates mit Neustart-Fenster
- Zeitsynchronisation
- Container-Laufzeit nach E-5-26
- DNS: A/AAAA-Eintrag auf den Server, CAA-Eintrag für Let's Encrypt
- Maschinenkonto anlegen (eigene E-Mail-Adresse, 2FA), Lesezugriff nur auf
  das Paket `identity-service`
- Jeden Härtungsschritt empirisch prüfen (z. B. Passwort-Login muss
  scheitern, geschlossener Port muss unerreichbar sein)

**Pflicht-Ergänzung: Plattenplatz (von der Projekt-Ownerin ausdrücklich
vorgemerkt, umsetzen):** Eine volle Platte ist Denial of Service (Container
starten nicht, Logs gehen verloren, Datenbanken können beschädigt werden).
Nicht die Zahl der Services füllt die Platte, sondern Speicher, der sich
unbemerkt ansammelt.

1. **Alte Images aufräumen:** nach jedem Deploy alles löschen außer der
   laufenden und der vorherigen Version (Rollback)
2. **Log-Rotation:** Container-Logs je Container auf eine feste Größe
   begrenzen; Docker begrenzt sie standardmäßig nicht
3. **Plattenplatz überwachen:** Warnung ab einem Füllstand (z. B. 80 %)

Messung vom 17.10.2026 (lokal): API-Image 180 MB, nginx-Image 226 bis 239 MB;
`docker system df` auf dem Entwicklungsrechner: 2,4 GB Images, davon 75 %
ungenutzt, dazu 3,5 GB Build-Cache. .NET-Services teilen die Schichten des
Basis-Images; ein weiterer Service kostet nur seine App-Schicht. Auf dem
Server entsteht kein Build-Cache (Pull-Deploy). Mit den drei Punkten reichen
64 GB für Staging mit mehreren Services.

Dazu ein **Nachtrag zu ADR-011** (STRIDE-Zeile D, Härtungsliste), im selben
PR wie E-5-27, E-5-28 und Debian 13.

## 4. Kleine Nachträge (wenn Zeit bleibt)

- Telemetrie der Testplattform prüfen und gegebenenfalls in der CI abschalten
- `pids_limit` in `compose.yaml` bewerten
- Nachtrag zu ADR-009; Nachtrag zu ADR-005; ADR-006 und ADR-008

## 5. Folgende Sitzungen bis Phase 5 (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 17 | Pull-Deploy mit Prüfung von Nachweis und Commit-Signatur; Staging-Variante von `compose.yaml`; Missbrauchsfälle 1 bis 4 aus ADR-011 als Gegentests |
| 18 | Freigabe vor dem Deploy, DORA-Events; DAST wird fällig |
| ab 18/19 | Phase 5: STRIDE, erster Use Case test-first |

## 6. Vor oder in der Sitzung zu verstehen (vor Code)

- **Gruppe `docker` = Root:** Der Docker-Dienst läuft als Root und startet
  Container mit beliebigen Mounts. Wer ihm Befehle geben darf, kann das
  Host-Dateisystem einbinden und sich so Root-Rechte verschaffen. Rootless
  Docker und Podman lassen den Dienst selbst ohne Root laufen.
- **CAA-Eintrag:** Ein DNS-Eintrag, der festlegt, welche
  Zertifizierungsstellen für die Domain Zertifikate ausstellen dürfen. Er
  verhindert nicht die Übernahme des Registrar-Kontos, begrenzt aber, wer
  sonst noch Zertifikate ausstellen darf.
- **Härtung empirisch prüfen:** Eine Einstellung ist erst wirksam, wenn der
  Gegenversuch scheitert. Beispiel: Nach dem Abschalten des Passwort-Logins
  muss ein Login mit Passwort abgewiesen werden. Grün ist nicht gleich
  funktionierend.
- **NTS (Network Time Security):** Authentifizierte Zeitsynchronisation.
  Normales NTP ist unauthentifiziert; wer die Uhr verstellt, kann abgelaufene
  Zertifikate oder Nachweise wieder gültig erscheinen lassen.

## 7. Optionale Vorbereitung

- Bis Sitzung 16 nichts am Server einrichten
- Eine eigene E-Mail-Adresse für das Maschinenkonto bereitlegen
- Einen SSH-Schlüssel (ed25519) für den Server vorbereiten; den privaten
  Schlüssel nie weitergeben
- „Automatically delete head branches“ einschalten
- Das Ablaufdatum des Agenten-Tokens (06.11.2026) vormerken
