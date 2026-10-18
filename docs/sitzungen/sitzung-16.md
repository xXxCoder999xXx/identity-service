# Sitzungsbericht Sitzung 16

**Datum:** 18.10.2026
**Phase:** Schritt 5 (CD): Härtung des Staging-Servers begonnen. SSH, äußere Firewall und automatische Sicherheitsupdates umgesetzt und geprüft; Container-Laufzeit entschieden (E-5-26 → E-5-33), ADR-012 und Installation folgen
**Vorgänger:** sitzung-15.md (abgeschlossen 18.10.2026)

---

## 1. Erledigt

Alle Befehle auf dem Server hat die Projekt-Ownerin selbst ausgeführt und
nur Ergebnisse gemeldet. Rechnername, IP-Adressen und Benutzername stehen
bewusst nicht in diesem Bericht.

### 1.1 Einstiegsprüfungen

- **Passwortwechsel gegengeprüft:** Ein Login mit dem alten Startpasswort
  wird abgelehnt.
- **Kernel:** Die sieben Kernel-Einträge im CISA-KEV-Katalog seit April 2026
  sind in `6.12.113-1` behoben; das ist der laufende Kernel. Hinweis: Der
  KEV-Filter muss auf Hersteller und Produkt gemeinsam filtern (Produktfeld
  heißt „Kernel“, nicht „Linux Kernel“), sonst ist er teilweise blind.
- **netcup-Oberflächen:** Server und Firewall verwaltet das Server Control
  Panel (SCP, `servercontrolpanel.de`), Domain und DNS das Customer Control
  Panel (CCP).
- **DNS (CCP, CloudDNS):** Der Eintragstyp **CAA** ist verfügbar. DNSSEC ist
  aus. Der A-Eintrag `@` zeigt auf eine netcup-Vorgabe-Adresse, nicht auf den
  Server.
- **Transfer-Sperre:** Im CCP gibt es keine. Der Reiter „Verwaltung“ gilt nur
  für Webhosting-Tarife. Der Schutz der Domain hängt damit an der
  Kontosicherheit (2FA) bei netcup (siehe Offene Punkte).

### 1.2 Administrationsbenutzer und SSH-Härtung

- Eigener Benutzer mit `sudo` angelegt (`id` zeigt die Gruppe `sudo`).
- Lokales Schlüsselpaar auf Windows: `%USERPROFILE%\.ssh\waveleg_staging`
  (ed25519, mit Passphrase, Kommentar `waveleg-staging`).
- Öffentlicher Schlüssel in `~/.ssh/authorized_keys`. Er stand nach
  dreifachem Kopieren zweimal darin; Fingerprints verglichen, auf eine Zeile
  bereinigt (`sort -u`).
- Drop-in `/etc/ssh/sshd_config.d/10-hardening.conf` (root:root,
  `-rw-r--r--`) mit `PermitRootLogin no`, `PasswordAuthentication no`,
  `KbdInteractiveAuthentication no`, `PubkeyAuthentication yes`,
  `AuthenticationMethods publickey`, `AllowUsers <Admin-Benutzer>`,
  `X11Forwarding no`, `MaxAuthTries 3`. `Include` steht in Zeile 12 von
  `sshd_config`, also vor allen eigenen Werten.
- Vorher laut `sshd -T`: `maxauthtries 6`, `permitrootlogin yes`,
  `passwordauthentication yes`, `x11forwarding yes`,
  `authenticationmethods any`. Nachher: alle Zielwerte wirksam.
- **Gegenproben bestanden:** Login mit Schlüssel klappt; Passwort-Login
  endet mit `Permission denied (publickey)` ohne Passwortabfrage; Root mit
  Schlüssel wird abgewiesen.
- Login ab jetzt: `ssh -i "$env:USERPROFILE\.ssh\waveleg_staging"
  <Benutzer>@<Rechnername>`. Das Root-Passwort dient nur noch der
  SCP-Konsole.

### 1.3 netcup-Firewall als äußere Schicht (E-5-29, E-5-30)

Recherche (netcup-Doku): zustandsbehaftet nur für TCP; UDP braucht
Regeln für beide Richtungen; DNS zu den netcup-Resolvern ist immer erlaubt;
Auswertung von oben nach unten, die erste passende Regel greift; bestehende
Verbindungen werden nicht neu geprüft; DROP verwirft still, REJECT gibt es
nicht; Regeln gelten erst nach **Speichern**.

Messungen vor dem Entwurf:

- Netzwerk-Konfiguration `static` (kein DHCP, also kein Risiko beim
  Erneuern der Adresse)
- Zeit: `systemd-timesyncd`, Server `2.debian.pool.ntp.org`, synchron
- DNS-Resolver: die von netcup
- `ss -ulpn`: kein lauschender UDP-Dienst; `ss -tlnp`: nur `sshd` auf 22

Policy `staging-ingress` (zugewiesen unter „netcup Mail block“ und „netcup
Ping allow“, über den impliziten „Accept all“-Regeln):

| # | Beschreibung | Protokoll | Quelle/Src Port | Dst Port | Aktion |
|---|---|---|---|---|---|
| 1 | SSH, nur Schlüssel | TCP | beliebig | 22 | ACCEPT |
| 2 | icmp | ICMP | beliebig | beliebig | ACCEPT |
| 3 | icmpv6 | ICMPv6 | beliebig | beliebig | ACCEPT |
| 4 | ntp-antworten | UDP | Src Port 123 | beliebig | ACCEPT |
| 5 | tcp-drop | TCP | beliebig | beliebig | DROP |
| 6 | udp-drop | UDP | beliebig | beliebig | DROP |

Alle Regeln eingehend. Ausgehend gibt es keine eigene Regel.

Zwei Fehler wurden vor dem Zuweisen anhand von Screenshots gefunden: DROP
als Menü-Vorgabe bei Regel 1 und fehlender Ziel-Port 22. In diesem Zustand
hätte jeder neue SSH-Login geblockt.

**Gegenproben (ohne VPN):**

| Probe | Vorher | Nachher |
|---|---|---|
| fremder Port 47123 | `Connection refused` | `Connection timed out` |
| neuer SSH-Login | klappt | klappt, auch mit VPN |
| `sudo apt update` | klappt | klappt |
| NTP nach Neustart von `systemd-timesyncd` | – | `PacketCount=1`, Zeitstempel nach dem Neustart |

Die erste Nachher-Probe zeigte noch `refused`: Die Policy war zugewiesen,
aber nicht gespeichert. Erst die Gegenprobe deckte das auf.

### 1.4 Automatische Sicherheitsupdates (E-5-31, E-5-32)

- `unattended-upgrades` 2.12 war nicht installiert. Installiert aus
  `trixie/main` (Spiegel `debian.anexia.at`, Debian-signiert), dazu 11
  Abhängigkeiten (u. a. `python3-apt`, `python3-gi`, `xz-utils`
  5.8.1-1+deb13u2 von `security.debian.org`), 29,2 MB. Python 3 war schon
  vorhanden. Aktualitätscheck: kein CVE zu `unattended-upgrades` in trixie.
- Die Installation legte nur `50unattended-upgrades` an, **kein**
  `20auto-upgrades`. Ohne eigene Datei wäre die Automatik aus geblieben.
- Eigene Datei `/etc/apt/apt.conf.d/52unattended-upgrades-local`:
  `APT::Periodic::Update-Package-Lists "1"`,
  `APT::Periodic::Unattended-Upgrade "1"`,
  `APT::Periodic::AutocleanInterval "7"`,
  `Unattended-Upgrade::Automatic-Reboot "true"`,
  `Unattended-Upgrade::Automatic-Reboot-Time "04:00"`,
  `Unattended-Upgrade::Remove-Unused-Kernel-Packages "true"`.
  Die Quellen (Origins) bleiben bei der Debian-Vorgabe.
- **Gegenproben:** `apt-config dump` zeigt alle sechs Werte wirksam. Beide
  Timer sind geplant (`apt-daily-upgrade` nächster Lauf 19.10.2026 06:55).
  Probelauf: erlaubt sind `trixie` und `trixie-security`; `trixie-updates`
  wird ausdrücklich gesperrt („Marking not allowed“). Keine ausstehenden
  Updates.
- **Nicht geprüft:** der erste echte Lauf (siehe Roadmap, Punkt 1).

### 1.5 Pflichtrecherche Container-Laufzeit (E-5-26 entschieden als E-5-33)

Stand 18.10.2026, Primärquellen siehe Abschnitt 6:

| Kandidat | Version | Offene CVEs in trixie | Wichtigster Befund |
|---|---|---|---|
| `docker.io` (Debian) | 26.1.5+dfsg1-9+deb13u1 | 3 | CVE-2026-92543: manipulierte DNS-Antworten können die TLS-Prüfung zur Registry abschalten oder auf HTTP zurückfallen lassen; upstream behoben in 29.8.2, in trixie ohne Fix |
| Docker (offizielles Repo) | 29.9.1 (14.10.2026) | – | behebt CVE-2026-92543, -92542 (29.8.2) und -34040 (29.3.1) |
| `podman` (Debian) | 5.4.2+ds1-2 | 6 | CVE-2026-94603 (kritisch, `--cap-drop=ALL` aushebelbar); betrifft nur Podman mit Root; upstream behoben in 5.8.8/6.1.3, in trixie ohne Fix |

- CISA KEV: kein Eintrag für Docker, runc, containerd oder Podman 2026
  gefunden. Die Angaben dazu stammen aus Sekundärquellen.
- Docker-Doku: Bei Docker mit Root gehen veröffentlichte Ports an den
  Firewall-Regeln des Hosts vorbei (`nat`-Tabelle vor `INPUT`).
- Docker-Doku Rootless: `uidmap` und 65.536 Unter-IDs nötig;
  `dockerd-rootless-setuptool.sh install` (Paket
  `docker-ce-rootless-extras`); Autostart per `loginctl enable-linger`.
  Ohne cgroup-Delegation werden `--cpus` usw. **still ignoriert**;
  standardmäßig sind nur `memory` und `pids` delegiert. Ports unter 1024
  per `setcap` auf `rootlesskit` oder per
  `net.ipv4.ip_unprivileged_port_start`.

---

## 2. Gelernt

- Bei sshd gewinnt der **erste** gelesene Wert, bei apt der **letzte**;
  deshalb steht ein sshd-Drop-in vorne (`10-…`) und eine apt-Datei hinter
  der Paketdatei (`52-…` nach `50-…`).
- `sshd -T` und `apt-config dump` zeigen den wirksamen Wert; eine Datei auf
  der Platte beweist nichts.
- Ein Heredoc kann auf dem Server still nichts schreiben; ein
  `printf … | sudo tee` nach `sudo -v` war zuverlässig.
- Die netcup-Firewall prüft UDP nicht zustandsbehaftet; ohne eigene Regel
  für die Antworten bricht die Zeitsynchronisation still.
- „Policy zugewiesen“ ist bei netcup nicht „aktiv“: Erst Speichern macht sie
  wirksam.
- DROP und „geschlossen“ unterscheiden sich messbar: `timed out` statt
  `refused`. Erst dieser Wechsel beweist, dass die Firewall greift.
- Ein VPN kann Port-Messungen blind machen: Proton VPN meldet für jeden
  abgelehnten Port `reset`. Firewall-Proben nur ohne VPN.
- Unter Windows meldet OpenSSH einen abgelehnten Verbindungsaufbau als
  `banner exchange: Connection to UNKNOWN port -1: Connection refused`.
- `ss -ulpn` zeigt nur Sockets, die auf fremde Anfragen warten; ein
  NTP-Client erscheint dort nicht.
- Ein installiertes Paket ist nicht dasselbe wie eine eingeschaltete
  Automatik (`unattended-upgrades` ohne `20auto-upgrades` tut nichts).
- Automatische Updates helfen nur, wenn es einen Fix gibt: Debian stable
  trägt für Docker und Podman aktuell ungefixte CVEs.
- Ein Kernel-Update wirkt erst nach dem Neustart; ohne Neustart ist das
  System nur scheinbar aktuell.
- Passphrase und `sudo`-Passwort sind zwei Schichten: Die Passphrase
  schützt die Schlüsseldatei lokal, das `sudo`-Passwort den Schritt zu root
  auf dem Server.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-29** | Firewall in zwei Schichten: netcup-Firewall (außen) plus Firewall auf dem Server; die Server-Firewall erst nach der Wahl der Container-Laufzeit (**Nachtrag zu ADR-011**) | Defense in Depth; die netcup-Firewall endete mit „Accept all“ und schützte nicht; Docker mit Root würde Host-Regeln umgehen |
| **E-5-30** | Policy `staging-ingress` wie in 1.3; TCP 80/443 erst beim TLS-Schritt öffnen; die doppelten ICMP-Regeln bleiben | deny-by-default (6.1.6); keine offenen Ports ohne Dienst; die eigene Policy soll nicht von netcups Vorgabe-Policy abhängen |
| **E-5-31** | `unattended-upgrades` mit der Debian-Vorgabe: Sicherheitsupdates und Punkt-Releases, ohne `trixie-updates` | Punkt-Releases sind von Debian geprüfte Fehlerkorrekturen; geringes Risiko |
| **E-5-32** | Automatischer Neustart um 04:00, nur wenn nötig; der Upgrade-Timer bleibt bei ca. 06:55 (Lücke bis ~21 h akzeptiert, für Production neu bewerten) | Ein Hinweis per E-Mail käme nicht an (Mail gesperrt, noch kein Monitoring); Kernel-Fixes müssen aktiv werden |
| **E-5-33** | Löst E-5-26: Docker **Rootless** aus dem offiziellen Docker-Repository (**ADR-012**, ADR-Kandidat) | keine Root-Äquivalenz; Host-Firewall wird nicht umgangen; zeitnahe Fixes (CVE-2026-92543 trifft den Pull-Deploy); Compose identisch zu lokal und CI |
| **E-5-34** | Ports 80/443 ohne Root per `sysctl net.ipv4.ip_unprivileged_port_start=80`, nicht per `setcap` | `setcap` auf `rootlesskit` geht bei jedem Docker-Update still verloren; nur ein Login-Benutzer, die äußere Firewall lässt nur 22 (später 80/443) herein |
| **E-5-35** | Eigener Systembenutzer `deploy` betreibt das rootless Docker, ohne `sudo` und ohne SSH-Login | Least Privilege; ein Container-Ausbruch endet bei einem Benutzer ohne weitere Rechte |

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **ADR-012 „Container-Laufzeit auf Staging“** schreiben (`/adr`), vor der
  Installation
- Docker-Repository als neue Vertrauensquelle: Fingerprint des
  APT-Schlüssels gegen die Docker-Doku prüfen, nur für dieses Repository
  zulassen (`signed-by`); Paketnamen gegen das Repository prüfen
  (Slopsquatting)
- **Fallstrick:** Das Docker-Repository muss in die erlaubten Quellen von
  `unattended-upgrades`, sonst wird Docker nie automatisch aktualisiert
- cgroup-Delegation (`Delegate=cpu cpuset io memory pids`), sonst wirkt
  `cpus` aus `compose.yaml` nicht; mit einer Gegenprobe messen
- Ob die Host-Firewall bei Rootless greift, ist laut Doku nicht belegt;
  empirisch prüfen
- Ob Rootless die echte Client-IP an nginx weitergibt, ist nicht belegt
  (relevant für Logs und Rate-Limits); beim nginx-Schritt messen
- Ob `ip_unprivileged_port_start` auch für IPv6 gilt, ist nicht belegt;
  messen
- Erster echter Lauf von `unattended-upgrades` (19.10.2026 ca. 07:00) nicht
  geprüft
- Regel `ntp-antworten` ist nur sicher, solange kein UDP-Dienst lauscht;
  bei HTTP/3 bzw. QUIC (UDP 443) neu bewerten
- Restlücke: Protokolle außer TCP/UDP/ICMP (z. B. GRE, ESP) fallen auf das
  implizite „Accept all“; die Server-Firewall soll sie schließen
- TCP 80/443 in der netcup-Firewall erst beim TLS-Schritt öffnen
- Keine Transfer-Sperre für die Domain verfügbar; Schutz nur über netcup-2FA
  (akzeptiertes Risiko, **Nachtrag zu ADR-011**)
- 2FA für SCP und CCP: Ob sie angeboten und aktiv ist, ist nicht geprüft
- DNS: A/AAAA und CAA beim TLS-Schritt setzen; DNSSEC erst danach
  einschalten und extern prüfen
- NTS für die Uhrzeit: weiter offen; ändert die netcup-Regel
  `ntp-antworten`
- Maschinenkonto (eigene E-Mail, 2FA, Lesezugriff nur auf
  `identity-service`) noch nicht angelegt
- Plattenplatz: Image-Aufräumen, Log-Rotation, Füllstandsüberwachung
  (Pflicht, siehe Roadmap)
- **Nachtrag zu ADR-011 fällig**, ein PR: RS 500 (E-5-27), Budget (E-5-28),
  Debian 13, Plattenplatz, keine Transfer-Sperre, Firewall in zwei Schichten
  (E-5-29/30), Updates (E-5-31/32), DNSSEC-Plan
- Die Health-Check-Anleitung nannte einmal `curl -k`; richtig ist nur
  `--ssl-no-revoke`
- Lokaler Branch `docs/sitzung-15` ist noch nicht gelöscht (nur auf Zuruf)
- Recherche: OWASP nicht eigens abgefragt; thehackernews.com lieferte für
  2026 keinen Treffer zu Container-Ausbrüchen

**Aus Sitzung 15 und früher, weiter offen**

- `compose.yaml` ohne `pids_limit`; Staging-Variante mit Image per Digest
  (Sitzung 17)
- Ob das nginx-Image signiert veröffentlicht wird; Werkzeug für den Ablauf
  des TLS-Zertifikats
- DORA-Events: Token auf dem Server oder lokales Protokoll
- Telemetrie der Testplattform; Test-Explorer von Visual Studio 2026; Runtime
  10.0.13 am Registry-Image nicht gemessen
- Nachtrag zu ADR-009; Nachtrag zu ADR-005; ADR-006 und ADR-008
  nachschreiben
- Rot-Beweis für „Publish“ bei fehlschlagendem Smoke-Test; „Publish“ kein
  Pflicht-Check; Aufräumregel für die Registry
- `nginx.conf` ohne `limit_req_status` und `proxy_ssl_verify_depth`;
  Gegentest zu `proxy_ssl_verify`
- Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches“ nicht eingeschaltet
- Übrige Punkte aus `sitzung-15.md`, Abschnitt 4, unverändert
- Dieser Bericht ist noch nicht committet

**Bekannte Grenzen**

- Für Staging akzeptierte Risiken nach E-5-24
- Der Herkunftsnachweis liegt in einem öffentlichen, unveränderlichen
  Protokoll

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Staging-Server: SSH gehärtet, äußere Firewall
aktiv, automatische Updates eingerichtet, Container-Laufzeit entschieden.
Es fehlen:

- ADR-012 und die Installation von Docker Rootless
- Server-Firewall, Zeit (NTS), Plattenplatz-Maßnahmen, DNS/TLS,
  Maschinenkonto
- Pull-Deploy mit Gate, Freigabe, DORA-Events

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Ausgelöst: Das Docker-Repository wird eine neue Vertrauensquelle (ADR-012); `unattended-upgrades` aus Debian ist aufgenommen (Härtungsliste ADR-011) |
| **DAST** (OWASP ZAP) | Rückt näher: fällig mit dem ersten Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant) |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Agentic-Gate 6.5, LLM-Gate 6.4, Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

**Server (Stand 18.10.2026):** Debian 13 (trixie), Kernel 6.12.113,
Zeitzone Europe/Berlin, statische Netzwerk-Konfiguration, NTP über
`systemd-timesyncd` mit `2.debian.pool.ntp.org`, Paket-Spiegel
`debian.anexia.at`.

**Dateien auf dem Server:**

- `/etc/ssh/sshd_config.d/10-hardening.conf`
- `/etc/apt/apt.conf.d/52unattended-upgrades-local`
- Log der Updates: `/var/log/unattended-upgrades/unattended-upgrades.log`

**Versionen (aus Primärquellen, 18.10.2026):**

- `unattended-upgrades` 2.12 (trixie)
- `docker.io` 26.1.5+dfsg1-9+deb13u1 (trixie), `podman` 5.4.2+ds1-2 (trixie)
- Docker Engine 29.9.1 (14.10.2026)

**Primärquellen dieser Sitzung:**

- `https://www.netcup.com/en/helpcenter/documentation/server/firewall`
- `https://tracker.debian.org/pkg/unattended-upgrades`
- `https://packages.debian.org/trixie/docker.io`,
  `https://packages.debian.org/trixie/podman`
- `https://security-tracker.debian.org/tracker/source-package/docker.io`,
  `https://security-tracker.debian.org/tracker/source-package/podman`,
  `https://security-tracker.debian.org/tracker/CVE-2026-92543`,
  `…/CVE-2026-92542`, `…/CVE-2026-94603`
- `https://docs.docker.com/engine/release-notes/`
- `https://docs.docker.com/engine/security/rootless/` und `…/rootless/tips/`
- `https://docs.docker.com/engine/network/packet-filtering-firewalls/`

**Fallstricke, die Zeit gekostet haben:**

- Heredoc für das sshd-Drop-in schrieb still nichts; erkannt an
  unveränderten Werten in `sshd -T`
- Gegenproben vor `systemctl reload ssh` sind wertlos; Reihenfolge `sshd -t`
  → `sshd -T` → reload → Gegenproben
- Menü-Vorgabe DROP bei neuen netcup-Regeln; jede Regel vor dem Speichern
  prüfen
- netcup-Policy ohne Speichern unwirksam
- Proton VPN verfälscht Port-Messungen

---

# Roadmap Sitzung 17

## 1. Einstieg: Erklärung des Vorgehens zur Container-Laufzeit

Warum zuerst: Die Projekt-Ownerin hat Option B (Docker Rootless aus dem
offiziellen Repository), `sysctl` ab Port 80 und den Benutzer `deploy`
nach Empfehlung entschieden und möchte vor jedem Schritt das Vorgehen
verstehen. Inhalt der Erklärung:

- Reihenfolge: erst ADR-012 (neue Vertrauensquelle entscheiden und
  dokumentieren), dann installieren, dann messen
- Was „rootless“ technisch heißt (User Namespaces, Unter-IDs in
  `/etc/subuid`), warum ein Ausbruch beim Benutzer `deploy` endet
- Der Weg vom APT-Schlüssel zum Paket: Fingerprint, `signed-by`, und warum
  das Docker-Repository in `unattended-upgrades` aufgenommen werden muss
- Was `enable-linger`, cgroup-Delegation und `ip_unprivileged_port_start`
  bewirken
- Wie die Projekt-Ownerin den Benutzer `deploy` ohne SSH-Login verwaltet

Davor kurz: Erster Lauf von `unattended-upgrades` prüfen
(`sudo tail -n 20 /var/log/unattended-upgrades/unattended-upgrades.log`,
Eintrag vom 19.10.2026 ca. 07:00 erwartet).

## 2. ADR-012 schreiben (`/adr`)

Warum: Das Docker-Repository ist eine neue Abhängigkeit mit eigenem
Signaturschlüssel (CLAUDE.md Abschnitt 5, 6.2a). Inhalt: E-5-33 bis E-5-35,
Rechercheergebnisse (1.5), betrachtete Alternativen (A Docker mit Root,
C Podman Rootless aus Debian), Pflicht-Gegenproben.

## 3. Docker Rootless installieren und messen

Warum: Voraussetzung für Server-Firewall, Plattenplatz-Maßnahmen und den
Pull-Deploy. Bausteine: Schlüssel und Repository; Pakete (vor dem „Ja“ die
Liste prüfen); Benutzer `deploy`; `uidmap` und Unter-IDs; Rootless-Setup;
`enable-linger`; Delegation; `sysctl`; Docker-Repository in
`unattended-upgrades`. Gegenproben: `docker info` zeigt `rootless`,
`docker info` zeigt einen cgroup-Treiber (nicht `none`), ein Container mit
`--cpus` wird tatsächlich begrenzt, Neustart überlebt.

## 4. Server-Firewall (Schicht 2)

Warum: erst jetzt sinnvoll, weil die Laufzeit feststeht. nftables mit
deny-by-default; Gegenprobe, dass Rootless-Ports die Regeln nicht umgehen.

## 5. Plattenplatz (Pflicht) und weitere Härtung

- Image-Aufräumen (aktuelle und vorherige Version behalten), Log-Rotation
  je Container, Füllstandsüberwachung ab 80 %
- NTS-Entscheidung
- Nachtrag zu ADR-011 (ein PR, siehe Offene Punkte)

## 6. Folgende Sitzungen (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 18 | DNS/TLS, Maschinenkonto, Pull-Deploy mit Prüfung von Nachweis und Signatur; Staging-Variante von `compose.yaml`; Missbrauchsfälle aus ADR-011 als Gegentests |
| 19 | Freigabe vor dem Deploy, DORA-Events; DAST wird fällig |
| ab 19/20 | Phase 5: STRIDE, erster Use Case test-first |

## 7. Vor oder in der Sitzung zu verstehen (vor Code)

- **User Namespaces:** Der Kernel bildet „root im Container“ auf eine
  unprivilegierte Benutzer-ID auf dem Host ab. Bricht ein Prozess aus,
  hat er auf dem Host nur die Rechte dieser ID.
- **Vertrauensquelle `signed-by`:** Ein APT-Schlüssel wird nur für ein
  Repository zugelassen. So kann der Docker-Schlüssel keine Debian-Pakete
  ersetzen.
- **cgroup-Delegation:** Ressourcenlimits setzt der Kernel über cgroups.
  Ein normaler Benutzer darf nur die Teile steuern, die systemd ihm
  übergibt; was nicht übergeben ist, wird still ignoriert.

## 8. Optionale Vorbereitung

- 2FA im netcup-Konto (SCP und CCP) prüfen
- Eine eigene E-Mail-Adresse für das Maschinenkonto bereitlegen
- „Automatically delete head branches“ einschalten
- Ablauf des Agenten-Tokens (06.11.2026) vormerken
