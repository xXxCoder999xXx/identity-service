# ADR-012: Container-Laufzeit auf Staging

- **Status:** Vorgeschlagen
- **Datum:** 2026-10-18

## Kontext

ADR-011 hat Staging auf einem netcup VPS mit Pull-Deploy festgelegt und die
Frage offen gelassen, wie der Deploy-Agent Container starten darf (E-5-26).
Ohne Container-Laufzeit gibt es keinen Deploy. Außerdem hängen die
Server-Firewall (E-5-29) und die Plattenplatz-Maßnahmen von dieser Wahl ab.

Wirkende Kräfte:

- **Least Privilege und Zero Trust:** Ein Ausbruch aus einem Container darf
  nicht zu root auf dem Server führen. Wer die Laufzeit steuert, soll nur die
  Rechte haben, die er dafür braucht.
- **Defense in Depth (E-5-29):** Die Firewall auf dem Server ist die zweite
  Schicht hinter der netcup-Firewall. Die Laufzeit darf sie nicht umgehen.
- **Lieferkette (6.2a):** Die Laufzeit zieht Images aus GHCR und Docker Hub.
  Eine Schwachstelle in diesem Pfad trifft genau den Pull-Deploy. Fixes
  müssen zeitnah ankommen; automatische Updates (E-5-31) helfen nur, wenn die
  Quelle einen Fix liefert.
- **Lokal == CI == Staging:** `compose.yaml` und die Compose-Befehle sollen
  überall gleich funktionieren.
- **Minimale Abhängigkeiten:** Jede neue Paketquelle ist eine neue
  Vertrauensquelle mit eigenem Signaturschlüssel.

Server: Debian 13 (trixie), Kernel 6.12.113. Recherche vom 18.10.2026
(Sitzung 16, Abschnitt 1.5), nur aus Primärquellen:

| Kandidat | Version | Offene CVEs in trixie | Wichtigster Befund |
|---|---|---|---|
| `docker.io` (Debian) | 26.1.5+dfsg1-9+deb13u1 | 3 | CVE-2026-92543: manipulierte DNS-Antworten können die TLS-Prüfung zur Registry abschalten oder auf HTTP zurückfallen lassen; upstream behoben in 29.8.2, in trixie ohne Fix |
| Docker (offizielles Repository) | 29.9.1 (14.10.2026) | – | behebt CVE-2026-92543, -92542 (29.8.2) und -34040 (29.3.1) |
| `podman` (Debian) | 5.4.2+ds1-2 | 6 | CVE-2026-94603 (kritisch, `--cap-drop=ALL` aushebelbar), betrifft nur Podman mit Root; upstream behoben in 5.8.8/6.1.3, in trixie ohne Fix |

Im CISA-KEV-Katalog steht für 2026 kein Eintrag zu Docker, runc, containerd
oder Podman.

## Entscheidung

Wir betreiben Docker Engine aus dem offiziellen Docker-Repository im
Rootless-Modus unter einem eigenen Benutzer `deploy`, der weder `sudo` noch
einen SSH-Login hat.

Teilentscheidungen:

| Code | Inhalt |
|---|---|
| E-5-33 | Löst E-5-26: Docker **Rootless** aus dem offiziellen Docker-Repository |
| E-5-34 | Ports 80/443 ohne Root per `net.ipv4.ip_unprivileged_port_start=80` (dauerhaft in `/etc/sysctl.d/`), nicht per `setcap` |
| E-5-35 | Der Benutzer `deploy` betreibt das rootless Docker, ohne `sudo` und ohne SSH-Login. Umsetzung (angepasst am 18.10.2026): normaler Benutzer mit Home-Verzeichnis, gesperrtem Passwort, ohne `authorized_keys`, nicht in `AllowUsers`; **kein** Systembenutzer (`adduser --system`) |
| E-5-36 | Das Docker-Repository wird per APT-Pinning auf die Docker-Pakete beschränkt; alle anderen Paketnamen aus dieser Quelle werden nie installiert (**neu, zur Entscheidung**) |

### Vertrauensquelle Docker-Repository

- Der APT-Schlüssel wird heruntergeladen und sein Fingerprint mit dem in
  diesem ADR festgehaltenen Wert verglichen (siehe Nachtrag). Bei
  Abweichung wird abgebrochen.
- Der Schlüssel gilt nur für die Quellen-Zeile des Docker-Repositorys
  (`signed-by`). Er kann damit keine Pakete aus den Debian-Quellen
  beglaubigen.
- `signed-by` hindert das Docker-Repository aber nicht daran, selbst ein
  Paket mit einem Debian-Namen in höherer Version anzubieten. Das schließt
  erst das APT-Pinning aus E-5-36.
- Paketnamen werden vor der Installation gegen den Paketindex des
  Repositorys geprüft (Slopsquatting, 6.3.2). Vor dem „Ja“ von `apt` wird die
  angezeigte Paketliste gelesen. Installiert wird mit
  `--no-install-recommends` und einer ausdrücklichen Liste (siehe Nachtrag).
- Das Docker-Repository wird in die erlaubten Quellen von
  `unattended-upgrades` aufgenommen. Die genaue Herkunftsangabe wird aus
  `apt-cache policy` abgelesen, nicht geraten.

### Bausteine des Rootless-Betriebs

- `uidmap` und 65.536 Unter-IDs für `deploy` in `/etc/subuid` und
  `/etc/subgid`
- Einrichtung mit `dockerd-rootless-setuptool.sh install` als `deploy`
- `loginctl enable-linger deploy`, damit der Daemon ohne Anmeldung läuft
- cgroup-Delegation per Drop-in für `user@.service` mit
  `Delegate=cpu cpuset io memory pids`
- Der systemweite Docker-Dienst mit Root (`docker.service`,
  `docker.socket`), den das Paket `docker-ce` startet, wird abgeschaltet und
  maskiert
- `"userland-proxy": false` in `~/.config/docker/daemon.json` von `deploy`
  und das Kernel-Modul `br_netfilter`, damit nginx die echte Client-IP sieht
- Verwaltung durch die Projekt-Ownerin per `sudo machinectl shell deploy@`
  vom Admin-Benutzer aus (Paket `systemd-container`)

### Pflicht-Gegenproben

Die Installation gilt erst als abgeschlossen, wenn alle Proben bestanden
sind:

1. `docker info` zeigt `rootless` unter den Sicherheitsoptionen.
2. `docker info` zeigt einen cgroup-Treiber (nicht `none`).
3. Ein Container mit `--cpus` wird messbar begrenzt.
4. Nach einem Neustart des Servers läuft der Daemon von `deploy` ohne
   Anmeldung.
5. `deploy` kann sich per SSH nicht anmelden und hat kein `sudo`.
6. Der Probelauf von `unattended-upgrades` nennt das Docker-Repository als
   erlaubte Quelle.
7. `apt-cache policy` zeigt, dass ein Paket außerhalb der Docker-Pakete aus
   dem Docker-Repository nicht installiert würde (E-5-36).
8. Ein veröffentlichter Port unter 1024 lässt sich als `deploy` öffnen, über
   IPv4 und IPv6 getrennt gemessen.
9. Mit der Server-Firewall (Roadmap-Schritt danach): Ein von einem Container
   veröffentlichter Port wird von der Host-Firewall tatsächlich blockiert.
10. `systemctl is-enabled docker.service docker.socket` meldet `masked`, und
    `/var/run/docker.sock` existiert nicht.
11. Ein Container hinter einem veröffentlichten Port sieht die echte
    Quell-IP eines externen Aufrufs (beim nginx-Schritt).

## Betrachtete Alternativen

1. **A: Docker mit Root, Deploy-Agent in der Gruppe `docker`:** verworfen.
   Die Gruppe `docker` ist gleichwertig zu root: Wer den Socket erreicht,
   startet einen Container mit dem Host-Dateisystem. Laut Docker-Dokumentation
   gehen veröffentlichte Ports bei Docker mit Root an den Firewall-Regeln des
   Hosts vorbei (`nat`-Tabelle vor `INPUT`); das hebelt E-5-29 aus.
2. **`docker.io` aus Debian:** verworfen. In trixie sind drei CVEs ohne Fix
   offen, darunter CVE-2026-92543, das den Pull aus der Registry betrifft.
   Automatische Updates liefern hier nichts nach.
3. **C: Podman Rootless aus Debian:** verworfen. Das kritische
   CVE-2026-94603 betrifft nur Podman mit Root, in trixie sind aber sechs
   CVEs ohne Fix offen; Fixes kommen erst mit einer neueren Version.
   Außerdem wären Compose-Ablauf und Befehle nicht mehr identisch zu lokal
   und CI.
4. **Ports unter 1024 per `setcap` auf `rootlesskit`:** verworfen. Die
   Fähigkeit hängt an der Programmdatei und geht bei jedem Docker-Update
   still verloren; nach einem automatischen Update startete nginx nicht mehr.
5. **Rootless Docker unter dem Admin-Benutzer:** verworfen. Ein Ausbruch
   endete bei einem Benutzer mit `sudo` und SSH-Zugang; zwischen Container und
   root stünde nur noch das `sudo`-Passwort. Diese Alternative ergibt sich aus
   der Begründung von E-5-35 und wurde nicht eigens diskutiert.
6. **`deploy` als Systembenutzer (`adduser --system`):** verworfen am
   18.10.2026. Ein Systembenutzer bekommt keine Unter-IDs und standardmäßig
   kein Home-Verzeichnis und die Shell `nologin`. Rootless funktioniert damit
   nicht ohne Nacharbeit, und `sudo -iu deploy` scheitert.
7. **Verwaltung per `sudo -iu deploy`:** verworfen (Nachtrag 18.10.2026,
   ursprünglich empfohlen). Laut Docker-Dokumentation scheitert danach
   `systemctl --user` mit „Failed to connect to bus“, weil keine Sitzung über
   `pam_systemd` entsteht; `rootlesskit` erkennt systemd nach `sudo su` nicht.
   Für Benutzer ohne Login nennt die Dokumentation `machinectl shell`.
8. **`docker-buildx-plugin` mitinstallieren:** verworfen. Der Server baut
   keine Images, er startet das in der CI gebaute Image per Digest.

## Begründung

- **Keine Root-Äquivalenz:** Der Daemon läuft als `deploy`. Über User
  Namespaces ist root im Container auf dem Host eine unprivilegierte
  Unter-ID von `deploy`. Ein Ausbruch endet bei einem Benutzer ohne `sudo`
  und ohne SSH-Login.
- **Firewall bleibt wirksam:** Rootless-Docker schreibt keine Regeln in die
  `nat`-Tabelle des Hosts. Laut Dokumentation ist das nicht ausdrücklich
  belegt, deshalb ist es Gegenprobe 9.
- **Zeitnahe Fixes:** Das offizielle Repository liefert 29.9.1 mit den Fixes
  für alle drei recherchierten CVEs. Über `unattended-upgrades` kommen
  künftige Fixes automatisch an.
- **Gleiche Werkzeuge:** Docker Engine und Compose-Plugin sind dieselben wie
  lokal und in der CI; `compose.yaml` muss nicht übersetzt werden.
- **`sysctl` statt `setcap`:** Der Wert ist eine Kernel-Einstellung und
  übersteht Updates. Das Risiko (jeder lokale Benutzer darf Ports ab 80
  öffnen) ist klein, weil es nur einen Login-Benutzer gibt und die äußere
  Firewall nur 22 (später 80/443) hereinlässt.
- **Pinning:** `signed-by` begrenzt, wofür der Schlüssel gilt; erst das
  Pinning begrenzt, welche Pakete die Quelle liefern darf. Beides zusammen
  hält die neue Vertrauensquelle so klein wie möglich.

## Konsequenzen

**Positiv**

- Ein Container-Ausbruch führt nicht zu root.
- Die Host-Firewall kann als zweite Schicht wirken.
- Docker-Fixes kommen automatisch auf den Server.

**Negativ**

- Neue Vertrauensquelle: Docker Inc. kann über das Repository Software mit
  Root-Installation auf den Server bringen. Pinning und `signed-by`
  begrenzen das auf die Docker-Pakete, verhindern es aber nicht.
- Ein automatisches Docker-Update startet den Daemon und damit alle
  Container neu. Für Staging akzeptiert, für Production neu bewerten.
- Netzwerk im Rootless-Modus läuft über einen Helfer im Benutzerraum: etwas
  langsamer, und ob nginx die echte Client-IP sieht, ist nicht belegt
  (relevant für Logs und Rate Limits).
- Ohne cgroup-Delegation würden Limits aus `compose.yaml` still ignoriert;
  das Drop-in ist Pflicht und muss bestehen bleiben.

**Neue Pflichten**

- Bei einem Schlüsselwechsel durch Docker abbrechen und den neuen Schlüssel
  über mindestens zwei Wege prüfen, bevor er zugelassen wird.
- Bei jedem neuen Docker-Paket die Pinning-Liste erweitern, sonst wird es
  nicht installiert (fail closed).
- Gegenproben 3 und 4 nach größeren Docker- oder systemd-Updates
  wiederholen.
- Nachtrag zu ADR-011: E-5-26 ist durch diese Entscheidung erledigt.

**Folgeentscheidungen**

- Server-Firewall mit nftables und deny-by-default, inklusive Gegenprobe 9.
- Messung der Client-IP an nginx beim TLS-Schritt.
- Plattenplatz: Image-Aufräumen und Log-Rotation im Kontext von `deploy`.

**Auslöser für eine Neubewertung**

- Debian liefert Fixes für Docker oder Podman zeitnah in stable.
- Eine Gegenprobe schlägt fehl (z. B. die Host-Firewall greift nicht).
- Production-Betrieb oder echte Daten auf einem Server mit dieser Laufzeit.
- Eine Schwachstelle in `rootlesskit`, im Netzwerk-Helfer oder in User
  Namespaces wird im CISA-KEV-Katalog geführt.

## Nachtrag 2026-10-18: Recherche vor der Installation

Die Recherche vor der Installation (Primärquellen, Stand 18.10.2026) hat drei
Annahmen dieses ADR widerlegt und zwei Lücken gefunden. Die betroffenen
Stellen oben sind angepasst.

**Fingerprint ohne Quelle in der Dokumentation.** Die Docker-Dokumentation
nennt den Fingerprint des APT-Schlüssels nicht mehr (Seiten für Debian,
Ubuntu und Rootless geprüft). Ersatzweise geprüft:

- Der Schlüssel von `https://download.docker.com/linux/debian/gpg` ist
  identisch mit dem Schlüssel auf `keyserver.ubuntu.com`.
- `dists/trixie/InRelease` (14.10.2026) ist mit diesem Schlüssel gültig
  signiert.

Ein Keyserver nimmt Schlüssel von jedem an; beide Prüfungen belegen
Übereinstimmung, keine unabhängige Bestätigung durch Docker. Für Staging
akzeptiert.

| Angabe | Wert |
|---|---|
| Hauptschlüssel | `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` |
| Unterschlüssel (signiert) | `D330 6A01 8370 199E 527A E799 7EA0 A9C3 F273 FCD8` |
| Kennung | `Docker Release (CE deb) <docker@docker.com>`, rsa4096, 2017-02-22 |
| `Origin` / `Label` | `Docker` / `Docker CE` |

**Paketliste.** Das Repository enthält für trixie neben der Engine auch
`cagent` (KI-Agent), `docker-model-plugin` (Modelle) und
`docker-secrets-engine`. Sie berühren das Agentic- bzw. LLM-Gate (6.4, 6.5)
und werden nie installiert; das Pinning (E-5-36) lässt nur diese Pakete zu:

| Paket | Version 18.10.2026 | Quelle |
|---|---|---|
| `docker-ce`, `docker-ce-cli`, `docker-ce-rootless-extras` | 5:29.9.1-1~debian.13~trixie | Docker |
| `containerd.io` | 2.4.2-2~debian.13~trixie | Docker |
| `docker-compose-plugin` | 5.6.0-1~debian.13~trixie | Docker |
| `uidmap` | 1:4.17.4-2 | Debian |
| `dbus-user-session` (Abhängigkeit von `docker-ce-rootless-extras`) | 1.16.2-2 | Debian |
| `systemd-container` (Quellpaket `systemd`) | 257.13-1~deb13u1 | Debian |

`docker-ce` empfiehlt `apparmor`, `git`, `pigz` und `procps`. Installiert
wird mit `--no-install-recommends`; AppArmor wirkt im Rootless-Modus laut
Dokumentation ohnehin nicht.

**Widerlegt bzw. ergänzt:**

1. `sudo -iu deploy` taugt nicht zur Verwaltung (Alternative 7). Ersatz:
   `sudo machinectl shell deploy@` mit `systemd-container` aus Debian, keine
   neue Vertrauensquelle.
2. Das Paket `docker-ce` startet sofort einen Docker-Dienst mit Root. Er wird
   abgeschaltet und maskiert (Gegenprobe 10).
3. Die echte Client-IP kommt ab RootlessKit v3.0 nur mit
   `"userland-proxy": false` und `br_netfilter` an (Gegenprobe 11). Die
   mitgelieferte RootlessKit-Version wird bei der Installation gemessen.

**CVE-Lage:** CISA KEV (Katalog vom 16.10.2026) ohne Eintrag 2026 zu Docker,
containerd, runc, systemd oder shadow. Im `runc` von trixie ist
CVE-2026-41579 offen (behoben in 1.3.6, 1.4.3, 1.5.0); laut Beschreibung unter
Docker nicht ausnutzbar. `containerd.io` bringt ein eigenes `runc` mit, dessen
Version bei der Installation gemessen wird.
