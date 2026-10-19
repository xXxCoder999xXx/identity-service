# Sitzungsbericht Sitzung 17

**Datum:** 19.10.2026
**Phase:** Schritt 5 (CD): Docker Rootless auf dem Staging-Server installiert
und gemessen (9 von 11 Pflicht-Gegenproben bestanden, 2 warten auf die
Server-Firewall); ADR-006, ADR-008 und ADR-012 geschrieben
**Vorgänger:** sitzung-16.md (abgeschlossen 18.10.2026)

---

## 1. Erledigt

### 1.1 ADRs geschrieben und gemergt

| PR | Inhalt |
|---|---|
| #91 | **ADR-012** Container-Laufzeit auf Staging: E-5-33 bis E-5-35 (E-5-35 angepasst: normaler Benutzer mit gesperrtem Passwort statt Systembenutzer, weil nur normale Benutzer automatisch Unter-IDs erhalten), CVE-Lage, Alternativen, Pflicht-Gegenproben 1–11 |
| #92 | **ADR-006** Signierte Commits (Lücke in der Nummerierung gefüllt): `required_signatures` und lokale SSH-Signatur; die Signatur beweist den Schlüssel, nicht die Person; GPG gegen SSH wurde nicht verglichen |
| #93 | **ADR-008** Exakter SDK-Pin mit `rollForward: disable` (Lücke gefüllt), mit den Vorfällen aus Sitzung 8 und 13 |
| #94 | **Nachtrag zu ADR-012:** Recherche vor der Installation (Fingerprint, Paketliste, Pinning E-5-36, `machinectl` statt `sudo -iu`, Docker-Dienst mit Root maskieren, Client-IP erst mit `userland-proxy: false` und `br_netfilter`) |

Alle vier ADRs stehen auf Status „Vorgeschlagen“.

### 1.2 Aufräumen des Repositorys

30 alte Remote-Branches gelöscht, jeder vorher als Kopf eines gemergten PRs
verifiziert (`headRefOid` stimmt). Auf GitHub und lokal existiert nur noch
`main`. Gelöscht hat die Projekt-Ownerin per `git push origin --delete`;
der Löschversuch des Agenten über die API war nicht berechtigt.

### 1.3 Recherche vor der Installation

Ergebnisse stehen im Nachtrag zu ADR-012. Kurz:

- Die Docker-Doku nennt den Fingerprint des APT-Schlüssels nicht mehr.
  Ersatzweise geprüft: Schlüssel identisch mit `keyserver.ubuntu.com`,
  `InRelease` gültig damit signiert.
- Das Repository liefert auch `cagent`, `docker-model-plugin` und
  `docker-secrets-engine`. Sie sind per Pinning ausgeschlossen.
- Slopsquatting-Prüfung aller Paketnamen gegen den Paketindex des
  Docker-Repositorys und `packages.debian.org`.
- CISA KEV ohne Eintrag 2026 zu Docker, containerd, runc, systemd, shadow.

### 1.4 Installation Docker Rootless (Staging-Server)

Schritt für Schritt: Die Projekt-Ownerin hat jeden Befehl selbst auf dem
Server eingegeben und die Ausgaben zurückgemeldet.

| Block | Inhalt | Verifiziert durch |
|---|---|---|
| Vorprüfung | Kernel 6.12.113, systemd 257.13, cgroup v2, keine Docker-Pakete | Ausgaben |
| Schlüssel | `/etc/apt/keyrings/docker.asc` | SHA-256 identisch mit der lokal geprüften Datei |
| Pinning und Quelle | `docker.pref`, `docker.sources` (deb822, `Signed-By`) | `apt-cache policy` (Gegenprobe 7) |
| A Pakete | nur die geplanten Pakete, `--no-install-recommends` | `/var/log/apt/history.log`, `dpkg -l` |
| B Root-Dienste aus | `docker.service`, `docker.socket`, `containerd.service` maskiert | dreimal `masked`, beide `inactive`, kein `/var/run/docker.sock` |
| C Benutzer `deploy` | Passwort gesperrt (`L`), keine Zusatzgruppe, 65.536 Unter-IDs, kein `.ssh`, Home `0700` | `passwd -S`, `id`, `/etc/subuid`, `ls -la` |
| D System | Delegation, `ip_unprivileged_port_start=80`, `br_netfilter`, Linger | `80`, Modul geladen, `Linger=yes` |
| E Rootless-Setup | `dockerd-rootless-setuptool.sh install`, Kontext `rootless`, `daemon.json` mit `userland-proxy: false` | Controller `cpuset cpu io memory pids`; `name=rootless`; `systemd 2`; 29.9.1; keine Warnungen; `containerd` läuft als `deploy` |
| G Container-Probe | nginx-Image per Digest, `--cpus 0.5`, Port 80 nur an Loopback | `cpu.max` = `50000 100000`; `200 OK` über IPv4 und IPv6 |
| F `unattended-upgrades` | Docker-Quelle zusätzlich zu den Debian-Quellen | `apt-config dump`; Testlauf nennt Docker unter „Allowed origins“ |
| H Neustart | `sudo reboot` | Boot 01:01; Benutzerdienst 01:02:01, Docker 01:02:03 ohne Anmeldung; Sperren, `sysctl` und Modul bestehen |

**Stand der Pflicht-Gegenproben (ADR-012):**

| Nr. | Gegenprobe | Stand |
|---|---|---|
| 1 | `docker info` zeigt `rootless` | bestanden |
| 2 | cgroup-Treiber `systemd`, Version 2 | bestanden |
| 3 | `--cpus`-Limit wirkt | bestanden |
| 4 | Daemon überlebt Neustart | bestanden |
| 5 | `deploy` ohne SSH und ohne `sudo` | bestanden: `sudo` scheitert (gesperrtes Passwort); `sshd -T` zeigt in `AllowUsers` nur den Admin-Benutzer |
| 6 | `unattended-upgrades` erlaubt Docker | bestanden |
| 7 | Pinning per `apt-cache policy` | bestanden |
| 8 | Port < 1024 ohne Root, IPv4 und IPv6 | bestanden (nur an Loopback gemessen) |
| 9 | Host-Firewall blockt veröffentlichten Port | offen, braucht Server-Firewall |
| 10 | Root-Dienste maskiert, kein `/var/run/docker.sock` | bestanden |
| 11 | Echte Client-IP im Container | offen, braucht Zugriff von außen |

---

## 2. Gelernt

- `signed-by` begrenzt nur, wofür ein Schlüssel gilt; die Quelle selbst kann
  trotzdem gleichnamige Pakete liefern. Erst APT-Pinning begrenzt, welche
  Pakete eine Quelle liefern darf (Korrektur der Aussage aus Sitzung 16).
- Nach `sudo -iu` funktioniert `systemctl --user` nicht, weil keine echte
  Anmeldesitzung entsteht; `sudo machinectl shell deploy@` erzeugt eine.
- Rootless-Docker startet sein eigenes `containerd` als Benutzer; ein
  maskierter `containerd.service` stört nicht.
- `ip_unprivileged_port_start` gilt trotz des Namens `ipv4` auch für IPv6
  (gemessen mit `[::1]:80`).
- Rootless-Docker verwaltet die Firewall des Hosts nicht („skipping
  firewalld management for rootless mode“); seine nftables-Tabellen liegen
  im Netz-Namensraum von RootlessKit. Ob die Host-Firewall greift, belegt
  erst Gegenprobe 9.
- `useradd` vergibt Unter-IDs nur an normale Benutzer, nicht an
  Systembenutzer; deshalb ist `deploy` ein normaler Benutzer mit gesperrtem
  Passwort.
- Ein gesperrtes Passwort plus keine sudo-Gruppe bedeutet: Wer als `deploy`
  landet, kommt über `sudo` nicht zu Root (jede Eingabe scheitert).
- Das `runc` aus `containerd.io` (1.5.2) ist neuer als die Fix-Versionen für
  CVE-2026-41579; das `runc` von trixie wird nicht verwendet.
- Ein automatisches Docker-Update tauscht nur die Programme aus. Der
  laufende Daemon von `deploy` bleibt alt, bis er oder der Server neu
  startet; ein Docker-Update allein fordert keinen Neustart an.
- Ein Terminal, das lange Zeilen umbricht, kann eine Konfigurationsdatei
  zerlegen; APT reagierte fail closed („No priority (or zero) specified for
  pin“). Kurze Zeilen mit Shell-Variablen vermeiden das.
- Mehrere Befehle am Stück einfügen kann Zeilen verschmelzen
  (`is-active dockermkdir -p …`); bei `sudo`/`apt` gefährlich.
- `/usr/sbin` steht unter Debian nicht im Suchpfad normaler Benutzer
  (`sysctl`, `lsmod`, `sshd`); mit `sudo` oder vollem Pfad aufrufen.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-35** (angepasst) | `deploy` ist ein normaler Benutzer mit gesperrtem Passwort, ohne `sudo`, nicht in `AllowUsers` (ADR-012) | Nur normale Benutzer erhalten automatisch Unter-IDs; kein Passwort, kein SSH, keine Zusatzrechte |
| **E-5-36** | APT-Pinning: aus `download.docker.com` nur `docker-ce`, `docker-ce-cli`, `docker-ce-rootless-extras`, `containerd.io`, `docker-compose-plugin` (500), alles andere -1 (ADR-012, Nachtrag) | `signed-by` allein verhindert keine fremden Pakete aus der Quelle; `cagent` u. a. berühren Gate 6.4/6.5 |
| **E-5-37** | Verwaltung von `deploy` per `sudo machinectl shell deploy@` (`systemd-container` aus Debian) statt `sudo -iu` (ADR-012, Nachtrag) | `systemctl --user` braucht eine echte Anmeldesitzung; keine neue Vertrauensquelle |
| **E-5-38** | Docker-Dienste mit Root (`docker.service`, `docker.socket`, `containerd.service`) maskiert; `"userland-proxy": false` plus `br_netfilter` (ADR-012, Nachtrag) | Kein Root-Daemon als Nebenwirkung des Pakets; Client-IP ab RootlessKit v3 nur so |
| **E-5-39** | Test-Container ohne Server-Firewall nur an Loopback veröffentlichen (`127.0.0.1`, `[::1]`) | Keine offenen Ports ohne Schutz (6.1.6); Gegenprobe 8 bleibt aussagekräftig |

Kandidat für einen zweiten Nachtrag zu ADR-012: Messergebnisse der
Installation (Abschnitt 1.4, 6), E-5-39 und die Entscheidung zur
Update-Lücke (Roadmap Punkt 3).

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- Gegenprobe 9 (Host-Firewall greift bei Rootless-Ports) und 11 (echte
  Client-IP) nach der Server-Firewall; für 11 ist ein Zugriff von außen nötig,
  die netcup-Firewall lässt derzeit nur TCP 22 herein
- **Update-Lücke:** Automatische Docker-Updates werden erst nach einem
  Neustart des Daemons von `deploy` wirksam; Optionen bewerten
- Zweiter Nachtrag zu ADR-012 (siehe Abschnitt 3)
- ADR-006, ADR-008, ADR-012 stehen auf „Vorgeschlagen“; „Akzeptiert“ setzt
  die Projekt-Ownerin
- Erster echter Lauf von `unattended-upgrades` (19.10.2026 ca. 07:00) nicht
  geprüft
- Image `nginxinc/nginx-unprivileged` (Digest aus `compose.yaml`) liegt im
  Image-Speicher von `deploy`; wird beim Deploy ohnehin gebraucht
- Fingerprint des Docker-Schlüssels nur über Keyserver und
  `InRelease`-Signatur belegt, nicht durch Docker selbst (für Staging
  akzeptiert, ADR-012)
- Dieser Bericht ist noch nicht committet

**Aus Sitzung 16 und früher, weiter offen**

- Server-Firewall (nftables), Plattenplatz, NTS, Nachtrag zu ADR-011
- Restlücke Protokolle außer TCP/UDP/ICMP; TCP 80/443 erst beim TLS-Schritt
  öffnen; DNS/DNSSEC; Maschinenkonto; 2FA für SCP/CCP nicht geprüft
- `compose.yaml` ohne `pids_limit`; Staging-Variante mit Image per Digest
- Nachtrag zu ADR-009 und ADR-005
- Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches“ nicht eingeschaltet
- Übrige Punkte aus `sitzung-16.md`, Abschnitt 4, unverändert

**Bekannte Grenzen**

- Für Staging akzeptierte Risiken nach E-5-24
- Ausgaben vom Server liegen nur als Rückmeldung der Projekt-Ownerin vor,
  nicht als Protokoll im Repository

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Staging-Server: SSH gehärtet, äußere Firewall,
automatische Updates (jetzt inklusive Docker), Docker Rootless installiert
und gemessen. Es fehlen:

- Server-Firewall mit Gegenproben 9 und 11
- Entscheidung zur Update-Lücke, Plattenplatz, NTS
- DNS/TLS, Maschinenkonto, Pull-Deploy mit Gate, Freigabe, DORA-Events

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Bearbeitet: Docker-Repository als Vertrauensquelle aufgenommen (ADR-012), begrenzt per `signed-by` und Pinning; neue Debian-Pakete `uidmap`, `dbus-user-session`, `systemd-container` |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst; `cagent` und `docker-model-plugin` per Pinning vom Server ferngehalten |
| **DAST** (OWASP ZAP) | Rückt näher: fällig mit dem ersten Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant) |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

**Versionen auf dem Server (gemessen 19.10.2026):**

- Docker Engine 29.9.1, `containerd.io` 2.4.2, `docker-compose-plugin` 5.6.0
- RootlessKit 3.3.0, runc 1.5.2 (aus `containerd.io`)
- Netz `gvisor-tap-vsock`, Port-Treiber `builtin`, Storage `overlayfs` mit
  containerd-Snapshotter

**Docker-APT-Schlüssel (18.10.2026):** Hauptschlüssel
`9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`; SHA-256 der Datei
`/etc/apt/keyrings/docker.asc`:
`1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570`.

**Benutzer `deploy`:** UID 1001, Socket `/run/user/1001/docker.sock`,
Daten `~/.local/share/docker`, CLI-Kontext `rootless`. Anmeldung nur per
`sudo machinectl shell deploy@`; Shell-Variablen gehen beim Wechsel verloren.

**Neue Dateien auf dem Server:**

- `/etc/apt/keyrings/docker.asc`
- `/etc/apt/sources.list.d/docker.sources`
- `/etc/apt/preferences.d/docker.pref`
- `/etc/apt/apt.conf.d/53unattended-upgrades-docker`
- `/etc/systemd/system/user@.service.d/delegate.conf`
- `/etc/sysctl.d/50-unprivileged-ports.conf`
- `/etc/modules-load.d/docker.conf`
- `/home/deploy/.config/docker/daemon.json`
- `/home/deploy/.config/systemd/user/docker.service` (vom Setup-Skript)

**Konfiguration, die zusammenwirkt:** `Automatic-Reboot` um 04:00 (E-5-32)
macht Gegenprobe 4 betriebsrelevant; nach jedem automatischen Neustart muss
der Daemon von `deploy` über Linger von selbst starten.

**Unkritische Meldungen im Docker-Journal:** `Deleting nftables … No such
file or directory` (nach frischem Boot), `failed check for fsverity
support`, `git source cannot be enabled` (`git` bewusst nicht installiert).

**Fallstricke, die Zeit gekostet haben:**

- Terminal-Umbruch zerlegte `docker.pref`; abgeschnittener Befehl legte nur
  den Pfad an. Abhilfe: kurze Variablen (`P`, `O`, `S`, `D`, `F`, `L`, `H`,
  `I`)
- Befehlsblöcke am Stück eingefügt, Zeilen verschmolzen; eine Zeile pro
  Einfügen
- `docker` als Admin statt als `deploy` aufgerufen: Fehlermeldung nennt
  `/var/run/docker.sock`; erst `whoami` prüfen
- `sudo` in der `deploy`-Sitzung eingegeben (drei Fehlversuche im Auth-Log)
- Commit-Hook blockiert `git commit -F -`; mehrere `-m` verwenden
- Branch-Löschung per `gh api` für den Agenten nicht freigegeben; löscht die
  Projekt-Ownerin per `!`

---

# Roadmap Sitzung 18

## 1. Einstieg: Restprüfungen

Warum zuerst: kurze Messungen, die offene Punkte schließen, bevor Neues
dazukommt.

- Erster Lauf von `unattended-upgrades`:
  `sudo tail -n 20 /var/log/unattended-upgrades/unattended-upgrades.log`
- `systemctl --user is-active docker` als `deploy` nach den nächtlichen
  Läufen

## 2. Server-Firewall (Schicht 2)

Warum: Der Server hat noch keine Host-Firewall; das ist das größte offene
Risiko und Voraussetzung für Gegenprobe 9 und 11. Bausteine: nftables mit
deny-by-default (nur SSH herein), Restlücke Nicht-TCP/UDP/ICMP schließen;
Gegenprobe 9 mit einem veröffentlichten Test-Port; Plan für Gegenprobe 11
(Zugriff von außen erfordert eine kurzzeitige Regel in der netcup-Firewall
oder wartet auf den TLS-Schritt).

## 3. Update-Lücke bewerten

Warum: Sicherheitsfixes für Docker wirken sonst erst nach dem nächsten
Neustart. Konzept mit Optionen, Zielkonflikt (Neustart unterbricht
Container) und Empfehlung; jede neue Abhängigkeit braucht Freigabe und
Slopsquatting-Prüfung.

## 4. Zweiter Nachtrag zu ADR-012

Warum: Messergebnisse der Installation, E-5-39 und die Entscheidung aus
Punkt 3 gehören zusammen in **einen** PR.

## 5. Plattenplatz (Pflicht), NTS, Nachtrag zu ADR-011

Unverändert aus Sitzung 16: Image-Aufräumen, Log-Rotation je Container,
Füllstandsüberwachung ab 80 %; NTS-Entscheidung; Nachtrag zu ADR-011 in
einem PR.

## 6. Folgende Sitzungen (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 19 | DNS/TLS, Maschinenkonto, Pull-Deploy mit Prüfung von Nachweis und Signatur; Staging-Variante von `compose.yaml`; Missbrauchsfälle aus ADR-011 als Gegentests |
| 20 | Freigabe vor dem Deploy, DORA-Events; DAST wird fällig |
| ab 20/21 | Phase 5: STRIDE, erster Use Case test-first |

## 7. Vor oder in der Sitzung zu verstehen (vor Code)

- **nftables-Grundlagen:** Tabellen enthalten Ketten, Ketten enthalten
  Regeln; eine Kette mit `policy drop` verwirft alles, was keine Regel
  erlaubt. Die Reihenfolge entscheidet, und eine Regel für bestehende
  Verbindungen (`ct state established,related accept`) gehört nach oben.
- **Aussperren vermeiden:** Eine falsche Firewall-Regel trennt die
  SSH-Verbindung. Deshalb neue Regeln mit automatischem Rücksprung testen
  und die SSH-Regel vor `policy drop` setzen.
- **Rootless-Ports und Host-Firewall:** Bei Docker mit Root umgehen dessen
  eigene Regeln die Host-Firewall; bei Rootless lauscht ein Prozess von
  `deploy` normal auf dem Port, also sollte die Host-Firewall greifen. Das
  ist bisher nur eine Erwartung und wird gemessen.

## 8. Optionale Vorbereitung

- 2FA im netcup-Konto (SCP und CCP) prüfen
- ADR-006, ADR-008, ADR-012 lesen und den Status setzen
- „Automatically delete head branches“ einschalten
- Ablauf des Agenten-Tokens (06.11.2026) vormerken
