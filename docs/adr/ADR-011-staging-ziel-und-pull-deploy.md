# ADR-011: Staging-Ziel und Pull-Deploy

- **Status:** Akzeptiert
- **Datum:** 2026-10-17

## Kontext

Schritt 5 (CD) ist zur Hälfte fertig: `publish.yml` baut das Image, scannt es,
lädt es nach GHCR und stellt Herkunftsnachweis und Stückliste aus; ein
Prüf-Gate verifiziert beide mit Gegenproben (ADR-010). Ein Gate schützt aber
erst, wenn ein Ziel es verlangt. Es fehlt eine Staging-Umgebung, die nur
geprüfte Images startet.

Wirkende Kräfte:

- **Plantreue (E-5-16):** Schritt 5 wird vollendet, bevor Phase 5 (erster Use
  Case) beginnt. Fachlogik vor Automatik war das Muster des Vorgängerprojekts.
  Damit ist die vertagte E-5-15 aufgelöst.
- **Vorgaben der Projekt-Ownerin:** Standort Österreich, höchstens 15 € pro
  Monat, jederzeit kündbar, und sie will beim Einrichten lernen.
- **Sicherheit:** keine langlebigen Secrets in der Pipeline (6.2b), Least
  Privilege, fail closed, Zero Trust (Netzzugehörigkeit ist kein
  Vertrauensargument).
- **Ausbau:** Später kommen weitere Microservices hinzu, die auf demselben
  Staging laufen und zusammenarbeiten.

Grundlage ist ein STRIDE-Threat-Modeling vom 17.10.2026.

## Entscheidung

Wir betreiben Staging auf einem netcup VPS in Wien und deployen per Pull: Der
Server holt Image und Konfiguration selbst, prüft Herkunftsnachweis bzw.
Commit-Signatur und startet nur, was die Prüfung besteht.

Teilentscheidungen:

| Code | Inhalt |
|---|---|
| E-5-17 | netcup VPS Wien; Pull-Deploy mit Prüfung des Herkunftsnachweises auf dem Server (Repository, `refs/heads/main`, `publish.yml`); Start per Digest, nie per Tag |
| E-5-21 | GHCR bleibt privat. Der Server liest mit einem klassischen Token (nur `read:packages`, mit Ablaufdatum) eines eigenen Maschinenkontos. Lesezugriff wird je Service-Paket einzeln vergeben |
| E-5-22 | Eigene Domain; Zertifikat von Let's Encrypt (ACME über Port 80); CAA-Eintrag beschränkt die Ausstellung auf Let's Encrypt |
| E-5-23 | Die Konfiguration (`compose.yaml`, `nginx.conf`) kommt per `git pull` aus dem Repository und wird erst nach Prüfung der Commit-Signatur übernommen |
| E-5-24 | Für Staging akzeptierte Risiken (siehe Konsequenzen) |
| E-5-25 | Als Signatur für `main` gilt der Web-Flow-Schlüssel von GitHub, weil Squash-Merges von GitHub signiert werden |
| E-5-26 | Wie der Deploy-Agent Container starten darf (Docker-Gruppe, Rootless Docker, Podman), bleibt offen und wird in Sitzung 16 entschieden |

**Fail closed** bedeutet hier: Kein neues Image und keine neue Konfiguration
startet ungeprüft. Schlägt eine Prüfung fehl (fremdes Image, falscher
Workflow, ungültige Signatur, abgelaufenes Token), bricht der Deploy ab und
die zuletzt geprüfte Version läuft weiter.

### Systemmodell und Vertrauensgrenzen

```
                     ┌───────────── netcup VPS (Wien) ──────────────┐
 [Ownerin] ─SSH:22──►│  Deploy-Agent                                │
 [netcup-Konto] ────►│   ├─ pull ──► GHCR (Token Maschinenkonto)    │
   Konsole/Rescue    │   ├─ pull ──► Docker Hub (nginx, Digest)     │
                     │   ├─ verify ► Sigstore / GitHub              │
                     │   └─ git pull ◄── Repository (Signatur)      │
 [Internet] ─443/80─►│  nginx ──► api        (internes Netz)        │
                     │  OS-Updates ◄── Ubuntu-Mirror                │
                     │  Uhrzeit    ◄── NTP                          │
                     │  (DORA-Events ──► GitHub, offen)             │
                     └──────────────────────────────────────────────┘
 [Registrar/DNS-Konto] ──► Domain zeigt auf den VPS
 [Let's Encrypt] ──ACME über Port 80──► Zertifikat
```

1. Internet → nginx
2. Ownerin → SSH
3. netcup-Konto → Server (Konsole und Rescue-System umgehen SSH)
4. Registrar/DNS-Konto → Domain
5. Registries (GHCR, Docker Hub) und Sigstore → Server
6. Konfiguration (Repository) → Server
7. Server → GitHub (DORA-Events, offen)

### Härtungsliste aus dem STRIDE-Ergebnis

| STRIDE | Maßnahme |
|---|---|
| S | SSH nur mit Schlüssel (ed25519), kein Passwort, kein Root-Login |
| S | 2FA an netcup-Konto, Registrar-Konto und Maschinenkonto; Transfer-Sperre der Domain; CAA-Eintrag |
| S, T | Herkunftsnachweis prüfen, dann per Digest starten |
| T | Commit-Signatur vor Übernahme der Konfiguration prüfen |
| T | Zeitsynchronisation mit mehreren Quellen (authentifizierte Zeit per NTS wird in Sitzung 16 entschieden) |
| R | Lokale Logs für Deploys (Digest, Zeit) und SSH-Anmeldungen |
| I | Token-Datei mit Rechten `600`, Ablaufdatum und Rotationstermin |
| I | Firewall: nur 443, 80 (ACME und Umleitung auf HTTPS) und 22 |
| D | Rate Limit in nginx; Speicher- und CPU-Grenzen in Compose (vorhanden) |
| D | Ablauf des Zertifikats eigenständig überwachen |
| E | Container ohne Root, `read_only`, `no-new-privileges`, `cap_drop` (in `compose.yaml` vorhanden); kein Docker-Socket in einem Container |
| E | Automatische Sicherheitsupdates mit Neustart-Fenster |

### Missbrauchsfälle als Testfälle (Sitzung 17)

1. Fremdes Image oder eigenes Image aus falschem Workflow: Deploy abgelehnt.
2. Unsignierter oder fremd signierter Commit auf `main`: Konfiguration nicht
   übernommen.
3. Manipulierter Digest in `compose.yaml`: Prüfung schlägt fehl.
4. Abgelaufenes Token: Deploy bricht ab, die letzte geprüfte Version läuft
   weiter.

## Betrachtete Alternativen

1. **Phase 5 vorziehen, Deploy später** (Mittelweg, Sitzung 13): verworfen.
   Fachlogik vor Automatik war das Muster des Vorgängers; ohne Ziel bleibt das
   Prüf-Gate ein Beweis ohne Wirkung.
2. **Push-Deploy aus GitHub Actions** (SSH-Zugang für die Pipeline):
   verworfen. GitHub bräuchte einen Schlüssel zum Server, also ein
   langlebiges Secret mit Schreibzugriff auf das Ziel. Beim Pull prüft das
   Ziel selbst, und die Pipeline braucht keinen Zugang.
3. **GHCR mit klassischem Token des Hauptkontos:** verworfen. GHCR akzeptiert
   laut GitHub-Dokumentation nur klassische Tokens, und ein klassisches Token
   lässt sich nicht auf ein Paket begrenzen. Es könnte jedes private Paket des
   Kontos lesen, mit jedem weiteren Service unbemerkt mehr.
4. **GHCR-Paket öffentlich machen:** verworfen. Laut GitHub-Dokumentation
   lässt sich ein öffentliches Paket nicht wieder privat machen. Eine
   unumkehrbare Entscheidung trifft man nicht für Staging.
5. **Ohne Domain, selbstsigniertes Zertifikat für die IP-Adresse:**
   verworfen. Jeder Test bräuchte das Abschalten der Zertifikatsprüfung; HSTS
   und DAST testen dann nicht realistisch.
6. **Konfiguration mit dem Image ausliefern:** zurückgestellt. Sie wäre vom
   Herkunftsnachweis mit abgedeckt, verlangt aber ein zusätzliches Artefakt
   und eine saubere Trennung von Struktur und Werten. Kann in Sitzung 17 neu
   bewertet werden.
7. **Konfiguration von Hand per `scp`:** verworfen. Nicht reproduzierbar,
   führt zu Drift.
8. **Andere Anbieter als netcup:** In den Sitzungen wurde kein weiterer
   Anbieter im Detail verglichen. netcup erfüllt die Vorgaben (Österreich,
   Preis, Kündbarkeit); Preis und Laufzeit prüft die Projekt-Ownerin im
   Bestellvorgang.

## Begründung

- Pull kehrt die Vertrauensrichtung um: Das Ziel prüft und holt, die Pipeline
  besitzt keinen Schlüssel zum Ziel. Das ergänzt OIDC auf der GitHub-Seite
  (`publish.yml`).
- Das Prüf-Gate der CI ist mit Gegenproben belegt (fremdes Image, falscher
  Workflow, falscher Branch werden abgelehnt; Sitzung 13). Dieselbe Prüfung
  wandert an das Ziel.
- Das Maschinenkonto ist die einzige Möglichkeit, den Lesezugriff auf GHCR auf
  einzelne Pakete zu begrenzen. Nach den Nutzungsbedingungen von GitHub
  (Abschnitt B.3) ist ein kostenloses Maschinenkonto pro Person erlaubt; die
  Projekt-Ownerin bleibt für es verantwortlich.
- Deny-by-default auf Infrastrukturebene: Jeder neue Service wird dem
  Maschinenkonto bewusst freigegeben, statt automatisch lesbar zu sein.
- Mit E-5-23 gilt „prüfen, dann übernehmen“ auch für die Konfiguration, die
  sonst das Prüf-Gate umgehen könnte (etwa über einen anderen Digest in
  `compose.yaml`).

## Konsequenzen

**Positiv**

- Ein ungeprüftes Image erreicht Staging nicht; der Gegentest mit fremdem
  Image wird Teil der Abnahme.
- Kein Secret mit Zugriff auf den Server in GitHub.
- Das Modell trägt mehrere Services: je Service ein Paket, je Paket eine
  Freigabe für das Maschinenkonto.

**Negativ und akzeptierte Risiken (E-5-24, nur für Staging)**

- Volumetrische Angriffe (DoS) werden nicht abgewehrt.
- Logs liegen nur lokal; ein Angreifer mit Root kann sie löschen. Spätestens
  vor Production werden sie auf ein zweites System übertragen.
- Das nginx-Image von Docker Hub ist nur per Digest geschützt; ein beim
  Herausgeber kompromittiertes Image erkennen wir nicht.
- Auf dem Server liegt ein langlebiges Token (Lesezugriff auf ausgewählte
  Pakete). Die Begrenzung erfolgt über Maschinenkonto, Ablaufdatum und
  Dateirechte.
- Mit E-5-25 vertraut der Server dem Signaturschlüssel von GitHub. Das passt
  zum Ruleset, das GitHub ohnehin als Richter einsetzt, macht GitHub aber zum
  Vertrauensanker auch für die Konfiguration.
- Weitere laufende Kosten: Server (≤ 15 € pro Monat) und Domain (rund 1 € pro
  Monat).

**Neue Pflichten**

- Token des Maschinenkontos vor Ablauf rotieren; Rotationstermin vermerken.
- Ablauf des TLS-Zertifikats überwachen.
- Jeder neue Service: Paket dem Maschinenkonto einzeln freigeben.
- Die Pflichtrecherche (CVEs, CISA KEV) läuft vor jeder Werkzeugwahl für den
  Server (Betriebssystem-Image, Prüfwerkzeug, Container-Laufzeit).

**Folgeentscheidungen**

- Sitzung 16: Docker-Rechte des Deploy-Agenten (E-5-26), NTS für die Uhrzeit,
  Betriebssystem-Image.
- Sitzung 17: Werkzeug für die Prüfung von Nachweis und Signatur auf dem
  Server; Staging-Variante von `compose.yaml` (die heutige Datei baut das
  Image lokal, Staging startet das veröffentlichte Image per Digest) als
  Erweiterung, nicht als Änderung der bestehenden Datei.
- Sitzung 18: DORA-Events. Meldet der Server an GitHub, braucht er ein Token
  mit Schreibrecht; dann kehrt sich die Vertrauensrichtung teilweise um.
  Alternative: Events nur lokal protokollieren.

**Staging ist nicht Production**

Dasselbe Image läuft später in Production, aber auf einem eigenen Server. Die
akzeptierten Risiken oben gelten dort nicht, Staging wird absichtlich
angegriffen (DAST), und auf Staging liegen nie echte Daten.

**Auslöser für eine Neubewertung**

- Echte Daten oder Production-Verkehr sollen auf diesen Server.
- GitHub unterstützt fein abgestufte Tokens für GHCR.
- Ein zweiter Service geht in Staging (Resilienz, Contract Testing und mTLS
  aus CLAUDE.md Abschnitt 8 werden dann fällig).
- netcup verletzt eine der Vorgaben (Preis, Standort, Kündbarkeit).
