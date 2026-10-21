# Sitzungsbericht Sitzung 18

**Datum:** 21.10.2026 (begonnen 19.10.2026)
**Phase:** Schritt 5 (CD): Host-Firewall (nftables) auf dem Staging-Server
aktiv und dauerhaft; alle 11 Pflicht-Gegenproben aus ADR-012 bestanden
**Vorgänger:** sitzung-17.md (abgeschlossen 19.10.2026)

---

## 1. Erledigt

In dieser Sitzung gab es keine PRs. Alle Arbeiten fanden auf dem
Staging-Server und in der netcup-Firewall statt. Die Projekt-Ownerin hat
jeden Befehl selbst eingegeben und die Ausgaben zurückgemeldet.

### 1.1 Restprüfungen (Roadmap-Punkt 1)

| Prüfung | Ergebnis |
|---|---|
| Läufe von `unattended-upgrades` | Fünf Läufe protokolliert: 18.10. 18:53, 19.10. 00:56, **06:11**, 12:39, 15:15. Der Lauf um 06:11 passt zu `apt-daily-upgrade.timer` (06:00 plus Zufallsverzögerung) und fand nichts zu aktualisieren. Der Lauf um 15:15 lief ohne Installation („dry-run“). |
| Erlaubte Quellen | Docker steht weiter unter „Allowed origins“ (Gegenprobe 6). `trixie-updates` ist nach Debian-Vorgabe nicht erlaubt; Sicherheitsfixes kommen über `trixie-security`. |
| Neustart in der Nacht | Keiner: `uptime -s` = 19.10. 01:01:55 (manueller Neustart aus Sitzung 17), `/var/run/reboot-required` fehlt |
| `docker version` (als `deploy`) | Client und Server beide 29.9.1, gebaut 14.10.2026, also derzeit keine Update-Lücke. Die verschiedenen `Git commit`-Werte sind normal, weil CLI und Engine aus getrennten Repositorys stammen. |

### 1.2 CVE-Prüfung Kernel (Debian Security Tracker, 19.10.2026)

| CVE | Inhalt | Behoben in trixie ab | Kernel 6.12.113 |
|---|---|---|---|
| CVE-2026-53266 | Netfilter ebtables SNAT, Schreiben außerhalb des Puffers (KEV, September 2026) | 6.12.94-1 | behoben |
| CVE-2025-39964 | AF_ALG, Race Condition (KEV, September 2026) | 6.12.57-1 | behoben |
| CVE-2025-39682 | kTLS-Empfangspfad (KEV, September 2026) | 6.12.48-1 (DSA-6008-1) | behoben |

Eine Sekundärquelle hatte CVE-2026-0511 als Netfilter-Lücke geführt. Laut
Debian-Tracker ist es eine SAP-Lücke („NOT-FOR-US: SAP“).

### 1.3 Host-Firewall mit nftables (Roadmap-Punkt 2)

**Ausgangszustand:** `nftables 1.1.3-1` installiert, Dienst `disabled`,
Regelsatz leer. Der Host hat also nichts gefiltert, und der einzige Schutz
war die netcup-Firewall.

**Ablauf:**

1. SSH-Port per `sshd -T` bestätigt (22).
2. Debian-Vorgabe gesichert, die neue Datei als `/etc/nftables.conf.new`
   geschrieben und mit `nft -c` geprüft (Exit-Code 0). Erst danach ersetzte
   sie die echte Datei.
3. Rücksprung-Zeitgeber per `systemd-run`, dann angewendet, dann eine neue
   SSH-Anmeldung in einem zweiten Terminal getestet.
4. **Der erste Versuch löste den Rücksprung aus:** Der Stopp kam nach Ablauf
   der 5 Minuten (`Unit nft-rollback.timer not loaded`). Die Tabelle war
   damit wieder entfernt. Beim zweiten Versuch (10 Minuten) wurde der
   Zeitgeber rechtzeitig gestoppt, `list-timers` zeigte keinen Zeitgeber
   mehr.
5. Messungen: neue SSH-Verbindung, `apt-get update`, `ping -4` und
   `ping -6` (damit auch Neighbor Discovery) ohne Fehler.
6. `systemctl enable nftables`, danach Neustart: `nftables` ist `active`,
   der Regelsatz ist geladen, Docker von `deploy` ist `active` (Gegenprobe 4
   mit Firewall).
7. Sicherung `/etc/nftables.conf.orig` gelöscht. Es bleibt eine einzige
   Quelle der Wahrheit.

### 1.4 Gegenprobe 9 und 11 im Messfenster

Aufbau: Test-Container `fw-probe` (nginx-unprivileged per Digest,
`--cpus 0.5`, `-p 8080:8080`) als `deploy`; eine netcup-Regel für TCP 8080
**nur von der eigenen Quell-IP**; eine Zählregel ohne Urteil oben in der
Host-Kette.

| Schritt | Messung | Ergebnis |
|---|---|---|
| Gegenprobe 9 | curl von außen auf 8080 | `000`. Zählregel 8080: +5 Pakete / +300 Bytes, Drop-Zähler: +5 / +300. Jedes ankommende Paket wurde von der Host-Firewall verworfen. |
| Gegenkontrolle | Host-Regel `ip saddr … tcp dport 8080 counter accept` eingefügt | curl `200`. Der Weg funktioniert, also hat in Gegenprobe 9 nur die Host-Firewall geblockt. |
| Gegenprobe 11 | `docker logs fw-probe` | Der Aufruf von außen erscheint mit der **echten öffentlichen Client-IP**. Lokale Aufrufe erscheinen als `172.17.0.1`. |
| Schließen | Datei neu geladen, Container gestoppt (`--rm`), netcup-Regel gelöscht | Keine Testregel mehr, der Container ist weg, curl von außen meldet `000` |

Hindernisse auf dem Weg (siehe 6.4): In der netcup-Regel stand der Port
im Feld „Ziele“ (Ziel-IP). Die Regel stand hinter `tcp-drop`. Eine leere
Dublette `TCP DROP` war entstanden. curl lief zeitweise über eine andere
Quell-IP (VPN gegen Heimanschluss) als in der Regel eingetragen.

**Stand der Pflicht-Gegenproben (ADR-012): alle 11 bestanden.**

| Nr. | Gegenprobe | Stand |
|---|---|---|
| 1–8, 10 | siehe sitzung-17.md | bestanden (Sitzung 17); 4 zusätzlich mit Firewall wiederholt |
| 9 | Host-Firewall blockt veröffentlichten Port | **bestanden** (21.10.2026) |
| 11 | Echte Client-IP im Container | **bestanden** (21.10.2026) |

---

## 2. Gelernt

- `tail` auf das Log von `unattended-upgrades` kann einen späteren
  Testlauf zeigen statt des geplanten Laufs; `grep "Starting unattended"`
  listet alle Läufe mit Uhrzeit.
- `docker version` zeigt die Datei auf der Platte (Client) und den
  laufenden Daemon (Server). Weichen die Versionen voneinander ab, ist die
  Update-Lücke messbar.
- Ein Rücksprung-Zeitgeber ist ein Sicherheitsnetz, das selbst fail-open
  erzeugt, wenn man ihn nicht rechtzeitig stoppt: Er entfernt die Firewall
  still. Nach dem Stopp muss `list-timers` geprüft werden.
- `nft -f` wendet eine Datei als eine Transaktion an. `destroy table`
  entfernt nur die eigene Tabelle, und zwischen Entfernen und Neuaufbau
  gibt es keinen Moment ohne Firewall. `flush ruleset` würde dagegen alle
  Tabellen löschen.
- Eine fehlerhafte `/etc/nftables.conf` beim Booten bedeutet „keine
  Firewall“ (fail-open). Deshalb wird eine Kopie geprüft, bevor sie die
  echte Datei ersetzt.
- Ein Zähler am Ende der Kette zählt nur Pakete, die das Ende erreichen.
  Erst eine Zählregel ohne Urteil am Anfang trennt „nicht angekommen“ von
  „angekommen und verworfen“.
- Die Größe eines Pakets verrät seinen Typ: 52 Bytes entsprechen einem
  Windows-SYN, 60 Bytes einem SYN mit Zeitstempel (z. B. Linux). Drei
  Pakete in 5 Sekunden sind ein SYN plus zwei Wiederholungen.
- Ports, die Docker Rootless veröffentlicht, laufen durch die
  `input`-Kette des Hosts. Die Host-Firewall greift also (gemessen),
  anders als bei Docker mit Root.
- Mit `userland-proxy: false` und `br_netfilter` sieht der Container bei
  RootlessKit 3.3.0 die echte Client-IP. Lokale Aufrufe erscheinen als
  Gateway `172.17.0.1`.
- In der netcup-Firewall bedeutet „Ziele“ die Ziel-IP, nicht den Port. Die
  Regeln wirken von oben nach unten, und die erste passende Regel
  entscheidet.
- Eine Freigabe für eine einzelne Quell-IP wirkt nur, solange der Client
  im selben Netz bleibt. Ein Wechsel zwischen VPN und Heimanschluss ändert
  die Quell-IP.
- Eine Regel „UDP mit Quellport 123 erlauben“ lässt sich fälschen, weil der
  Absender den Quellport selbst wählt. Die Host-Firewall
  (`established`) fängt das ab.
- Das Zugriffslog von nginx speichert Client-IPs, also personenbezogene
  Daten.
- CVE-Zuordnungen aus Sekundärquellen können falsch sein; maßgeblich ist
  der Debian Security Tracker.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-40** | Host-Firewall mit nftables direkt (`/etc/nftables.conf`, Tabelle `inet host_fw`), `input` und `forward` mit `policy drop` | Bordmittel ohne neue Abhängigkeit, eine lesbare Datei, IPv4 und IPv6 gemeinsam; Alternativen `ufw` und `firewalld` verworfen |
| **E-5-41** | `output` vorerst offen; ein Filter für ausgehenden Verkehr ist ein späterer Ausbauschritt | Ein Egress-Filter braucht eine Pflegeliste (Spiegelserver, Registry, DNS, NTP) |
| **E-5-42** | Eigene Tabelle mit `destroy table` statt `flush ruleset` | Andere Tabellen bleiben unberührt (Open/Closed); das Laden ist atomar |
| **E-5-43** | Verworfene Pakete werden nicht geloggt, nur gezählt | Logzeilen enthielten Quell-IPs, also personenbezogene Daten (6.1.5) |
| **E-5-44** | Syntaxprüfung (`nft -c`) an einer Kopie, bevor die echte Datei ersetzt wird | Eine fehlerhafte Datei beim Booten bedeutet „offen“ |
| **E-5-45** | Firewall-Änderungen nur mit Rücksprung-Zeitgeber (`systemd-run`, 10 Minuten) und Test über eine zweite SSH-Sitzung; danach `list-timers` prüfen | Sich selbst auszusperren wird vermieden, und ein nicht gestoppter Zeitgeber wird erkannt |
| **E-5-46** | Messfenster für Gegenproben: Test-Port nur kurz, doppelt auf die eigene Quell-IP begrenzt (netcup und Host), Schließen durch Neuladen der Datei. Ersetzt die Bedingung „nur Loopback“ aus E-5-39, seit es eine Host-Firewall gibt. | Keine offenen Ports ohne Schutz (6.1.6); die Datei bleibt die Quelle der Wahrheit |

ADR-Kandidaten: E-5-40 bis E-5-45 gehören in einen **Nachtrag zu ADR-011**
(Server-Härtung). E-5-46 und die Messergebnisse aus 1.4 gehören in den
**zweiten Nachtrag zu ADR-012**.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Update-Lücke** (Roadmap-Punkt 3 aus Sitzung 17) nicht bearbeitet. Die
  Messmethode steht fest: `docker version`, Client gegen Server.
- **Überwachung von `nftables.service`:** Schlägt der Dienst beim Booten
  fehl, läuft der Server ohne Host-Firewall. Es gibt noch keine Warnung.
- Ein **automatischer** Neustart (04:00, E-5-32) mit Start über Linger und
  Firewall wurde noch nicht beobachtet, nur manuelle Neustarts.
- Das Journal des ausgelösten Rücksprungs (`nft-rollback.service`) wurde
  nicht ausgewertet. Der Rücksprung ist nur durch „not loaded“ und den
  anschließend nötigen Neuaufbau belegt.
- netcup-Regel `ntp-antworten` (UDP, Quellport 123, Quelle beliebig) lässt
  sich mit gefälschtem Quellport ausnutzen. Die Host-Firewall mildert das.
  Gemeinsam mit der NTS-Entscheidung bewerten.
- **Zugriffslog von nginx** enthält Client-IPs: Für die Staging-Variante
  von `compose.yaml` IP kürzen oder weglassen und eine Aufbewahrungsfrist
  festlegen. Zielkonflikt mit Ratenbegrenzung und Sicherheitsereignissen.
- Im Image-Speicher von `deploy` liegt jetzt das nginx-Image mit Digest
  `sha256:8f18dedf…`, dazu weiterhin das alte `sha256:d715f7a8…`. Das alte
  beim Plattenplatz-Schritt entfernen.
- Zweiter Nachtrag zu ADR-012 und Nachtrag zu ADR-011 (siehe Abschnitt 3)
- Dieser Bericht ist noch nicht committet.

**Aus Sitzung 17 und früher, weiter offen**

- ADR-006, ADR-008, ADR-012 stehen auf „Vorgeschlagen“; „Akzeptiert“ setzt
  die Projekt-Ownerin
- Plattenplatz (Image-Aufräumen, Log-Rotation je Container,
  Füllstandsüberwachung ab 80 %), NTS
- DNS/DNSSEC; TCP 80/443 erst beim TLS-Schritt öffnen; Maschinenkonto; 2FA
  für SCP/CCP nicht geprüft
- `compose.yaml` ohne `pids_limit`; Staging-Variante mit Image per Digest
- Nachtrag zu ADR-009 und ADR-005
- Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches“ nicht eingeschaltet
- Fingerprint des Docker-Schlüssels nur über Keyserver und
  `InRelease`-Signatur belegt (für Staging akzeptiert, ADR-012)

**Bekannte Grenzen**

- Für Staging akzeptierte Risiken nach E-5-24
- Ausgaben vom Server liegen nur als Rückmeldung der Projekt-Ownerin vor,
  nicht als Protokoll im Repository
- Gegenprobe 11 wurde über IPv4 gemessen; IPv6 von außen ist nicht
  gemessen (die netcup-Freigabe galt nur der IPv4-Quelle)

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Staging-Server: SSH gehärtet, äußere Firewall
(netcup), **Host-Firewall (nftables)**, automatische Updates inklusive
Docker, Docker Rootless installiert und mit allen 11 Gegenproben gemessen.
Es fehlen:

- Entscheidung zur Update-Lücke, Plattenplatz, NTS, Überwachung
- DNS/TLS, Maschinenkonto, Pull-Deploy mit Gate, Freigabe, DORA-Events

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Nicht berührt: keine neue Abhängigkeit (`nftables`, `systemd-run` vorhanden). Test-Image per Digest. |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** (OWASP ZAP) | Rückt näher: fällig mit dem ersten Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant) |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Host-Firewall `/etc/nftables.conf` (Stand 19.10.2026)

```
#!/usr/sbin/nft -f

# Host-Firewall Staging (E-5-40)
# Ersetzt nur die eigene Tabelle,
# andere Tabellen bleiben unberuehrt.
destroy table inet host_fw

table inet host_fw {
	chain input {
		type filter hook input priority filter;
		policy drop;

		iif "lo" accept

		ct state established,related accept
		ct state invalid drop

		meta l4proto ipv6-icmp jump icmpv6_in
		meta l4proto icmp jump icmpv4_in

		tcp dport 22 ct state new accept

		counter drop
	}

	chain icmpv6_in {
		icmpv6 type {
			nd-router-advert,
			nd-neighbor-solicit,
			nd-neighbor-advert
		} ip6 hoplimit 255 accept
		icmpv6 type echo-request limit rate 5/second accept
	}

	chain icmpv4_in {
		icmp type echo-request limit rate 5/second accept
	}

	chain forward {
		type filter hook forward priority filter;
		policy drop;
	}
}
```

nftables ergänzt bei `limit` selbst `burst 5 packets`. Der Dienst
`nftables` ist `enabled`.

### 6.2 netcup-Firewall-Policy `staging-ingress` (Endstand 21.10.2026)

| # | Beschreibung | Protokoll | Aktion | Quelle | Src Port | Dst Port |
|---|---|---|---|---|---|---|
| 1 | SSH, nur Schlüssel | TCP | ACCEPT | beliebig | beliebig | 22 |
| 2 | icmp | ICMP | ACCEPT | beliebig | beliebig | beliebig |
| 3 | icmpv6 | ICMPv6 | ACCEPT | beliebig | beliebig | beliebig |
| 4 | ntp-antworten | UDP | ACCEPT | beliebig | 123 | beliebig |
| 5 | tcp-drop | TCP | DROP | beliebig | beliebig | beliebig |
| 6 | udp-drop | UDP | DROP | beliebig | beliebig | beliebig |

Alle Regeln sind eingehend, Ziel jeweils „beliebig“.

### 6.3 Versionen (gemessen 19.10.2026)

- `nftables` 1.1.3-1 (Debian), Kernel 6.12.113+deb13-amd64
- Docker Engine 29.9.1 (Client und Server, gebaut 14.10.2026),
  `containerd` 2.4.2, runc 1.5.2, RootlessKit 3.3.0
- Test-Image: `nginxinc/nginx-unprivileged@sha256:8f18dedfceea3d7feb98792810c8c9925c985890ade257f2ec1b2f492b4eaebb`
  (Digest aus Sitzung 17, gepinnt in `compose.yaml`)

### 6.4 Fallstricke, die Zeit gekostet haben

- Rücksprung-Zeitgeber zu spät gestoppt: Die Firewall wurde still
  entfernt. Abhilfe: 10 Minuten, `stop`-Befehl vorher bereitlegen,
  `list-timers` prüfen.
- In der netcup-Oberfläche stand der Port im Feld „Ziele“ (das ist die
  Ziel-IP).
- Die netcup-Freigabe stand hinter `tcp-drop` und konnte deshalb nie
  greifen.
- „Regel hinzufügen“ erzeugte eine leere Dublette `TCP DROP`.
- curl lief über eine andere Quell-IP als in der Freigabe (Wechsel
  zwischen VPN und Heimanschluss). Der Drop-Zähler blieb gleich, weil
  netcup die Pakete schon verworfen hatte.
- Die Erwartung „beide Zähler 0“ stimmte nicht: Die lokale Probe über
  `127.0.0.1` zählt in der 8080-Zählregel mit (danach von `lo` angenommen).
  Richtig ist: Der Drop-Zähler steht auf 0.

### 6.5 Konzeptprotokoll: Warum, Befehl, Wirkung

**Server-Host**

| Schritt | Warum | Befehl (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Läufe der Updates prüfen | Der erste automatische Lauf war unbelegt | `sudo grep "Starting unattended" /var/log/unattended-upgrades/unattended-upgrades.log` | Lauf um 06:11 belegt |
| Neustart prüfen | Automatischer Neustart um 04:00 nur bei Bedarf | `uptime -s`, `ls /var/run/reboot-required` | Kein Neustart, keiner ausstehend |
| Ist-Zustand Firewall | Erst messen, dann ändern | `dpkg -l nftables`, `systemctl is-enabled nftables`, `sudo nft list ruleset` | Installiert, aus, leer: Der Host war ungefiltert |
| SSH-Port bestätigen | Eine falsche Port-Regel sperrt aus | `sudo sshd -T \| grep -E "^(port\|listenaddress) "` | Port 22 |
| Syntax prüfen | Eine fehlerhafte Datei bedeutet beim Booten „offen“ | `sudo nft -c -f /etc/nftables.conf.new` | Exit-Code 0 |
| Rücksprung | Notausgang beim Aussperren | `sudo systemd-run --on-active=10min --unit=nft-rollback /usr/sbin/nft destroy table inet host_fw` | Einmal echt ausgelöst |
| Anwenden | Atomar, ohne Lücke | `sudo nft -f /etc/nftables.conf` | Regelsatz aktiv |
| Rücksprung abbrechen | Sonst entfernt er die Firewall | `sudo systemctl stop nft-rollback.timer`, `systemctl list-timers nft-rollback.timer` | `0 timers listed` |
| Rückweg messen | `established` muss Antworten durchlassen | `sudo apt-get update`, `ping -4/-6 -c 3 deb.debian.org` | ohne Fehler, IPv6-ND funktioniert |
| Dauerhaft machen | Regeln beim Booten laden | `sudo systemctl enable nftables`, `sudo reboot` | Nach dem Neustart `active` und geladen |

**Docker**

| Schritt | Warum | Befehl (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Update-Lücke messen | Ein Update tauscht nur Dateien, nicht den laufenden Daemon | `docker version` (als `deploy`) | Client = Server 29.9.1, keine Lücke |
| Docker nach Neustart | Linger muss Docker ohne Anmeldung starten, auch mit Firewall | `systemctl --user is-active docker` | `active` |
| Test-Container | Etwas, das auf einem veröffentlichten Port antwortet | `docker run -d --rm --name fw-probe --cpus 0.5 -p 8080:8080 nginxinc/nginx-unprivileged@sha256:…` | Lokal `200` |
| Client-IP prüfen | Ohne echte IP keine Ratenbegrenzung und keine Zuordnung von Sicherheitsereignissen | `docker logs fw-probe` | Echte IP von außen, `172.17.0.1` lokal |
| Aufräumen | Kein Test-Port bleibt offen | `docker stop fw-probe` (`--rm` löscht) | Container weg |

**Sicherheit und Messmethodik**

| Konzept | Warum | Umsetzung | Beleg |
|---|---|---|---|
| Defense in Depth | Die netcup-Firewall kann fehlen, falsch sein oder geöffnet werden | zweite Schicht `policy drop` auf dem Host | Gegenprobe 9 |
| deny-by-default (6.1.6) | Nur Erlaubtes passiert, auch Nicht-TCP/UDP/ICMP | `policy drop` bei `input` und `forward` | Regelsatz |
| Kein Logging von IPs (6.1.5) | IPs sind personenbezogen | nur `counter` | E-5-43 |
| Zählregel ohne Urteil | „nicht angekommen“ von „verworfen“ unterscheiden | `sudo nft insert rule inet host_fw input tcp dport 8080 counter` | +5 oben = +5 unten |
| Gegenkontrolle | Eine Sperre ist nur Beweis, wenn der Weg sonst funktioniert | `… ip saddr <eigene-IP> tcp dport 8080 counter accept` | curl `200` |
| Doppelte IP-Begrenzung | Das Messfenster bleibt klein | netcup-Regel und Host-Regel nur für die eigene IP | E-5-46 |
| Datei als Quelle der Wahrheit | Testregeln sicher entfernen | `sudo nft -f /etc/nftables.conf` | keine Testregel mehr |
| Primärquelle bei CVEs | Sekundärquellen irren | Debian Security Tracker | CVE-2026-0511 korrigiert |

---

# Roadmap Sitzung 19

## 1. Update-Lücke bewerten

Warum zuerst: Das ist der älteste offene Konzeptpunkt. Sicherheitsfixes für
Docker wirken sonst erst nach dem nächsten Neustart des Daemons, und ein
Docker-Update allein fordert keinen Neustart an. Bausteine: Optionen
vergleichen (Neustart bei einem Docker-Update anfordern und damit den
bestehenden `Automatic-Reboot` um 04:00 nutzen; den Benutzerdienst gezielt
neu starten; Werkzeug wie `needrestart`; manuell), Zielkonflikt
Unterbrechung gegen Sicherheit, Empfehlung. Jede neue Abhängigkeit braucht
Freigabe, Slopsquatting-Prüfung und ADR. Messmethode: `docker version`
(Client gegen Server).

## 2. Plattenplatz und Überwachung (Pflicht)

Warum: Volle Platten legen Docker und Logs lahm. Die Überwachung lässt sich
mit der Warnung bei `nftables.service`-Fehlern bündeln (gleicher
Mechanismus). Bausteine: altes nginx-Image entfernen (`sha256:d715f7a8…`),
Log-Rotation je Container, Füllstandswarnung ab 80 %, Warnung bei
`systemctl is-failed nftables`.

## 3. NTS und netcup-Regel `ntp-antworten`

Warum: Beides betrifft NTP; die Regel mit Quellport 123 lässt sich fälschen.
Bausteine: NTS-Entscheidung, danach die netcup-Regel anpassen oder
begründet belassen.

## 4. ADR-Nachträge (je ein PR)

Warum: Die Entscheidungen sind getroffen und gemessen, aber noch nicht
dokumentiert.
- Zweiter Nachtrag zu ADR-012: Messergebnisse der Installation, alle 11
  Gegenproben, E-5-39 und E-5-46, Entscheidung zur Update-Lücke
- Nachtrag zu ADR-011: Host-Firewall E-5-40 bis E-5-45, Überwachung,
  Plattenplatz, NTS

## 5. Folgende Sitzungen (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 20 | DNS/TLS, Maschinenkonto, Pull-Deploy mit Prüfung von Nachweis und Signatur; Staging-Variante von `compose.yaml` (`pids_limit`, Image per Digest, IP im Zugriffslog); Missbrauchsfälle aus ADR-011 als Gegentests |
| 21 | Freigabe vor dem Deploy, DORA-Events; DAST wird fällig |
| ab 21/22 | Phase 5: STRIDE, erster Use Case test-first |

## 6. Vor oder in der Sitzung zu verstehen (vor Code)

- **Datei gegen Prozess:** Ein Paket-Update ersetzt die Programmdateien.
  Ein laufender Prozess behält den alten Code im Speicher, bis er neu
  startet. „Aktualisiert“ heißt also erst nach dem Neustart „geschützt“.
- **Neustart des Daemons gegen Neustart des Servers:** Ein Neustart nur des
  Docker-Benutzerdienstes unterbricht alle Container, aber nicht den
  Server. Ein Server-Neustart erneuert auch den Kernel. Beides kostet
  Verfügbarkeit. Auf Staging zählt Sicherheit vor Verfügbarkeit.
- **Überwachung ohne neue Abhängigkeit:** systemd kann bei einem Fehler
  einer Einheit eine andere Einheit starten (`OnFailure=`), und ein Timer
  kann den Füllstand regelmäßig prüfen. Wohin die Warnung geht, ist eine
  eigene Entscheidung.

## 7. Optionale Vorbereitung

- 2FA im netcup-Konto (SCP und CCP) prüfen
- ADR-006, ADR-008, ADR-012 lesen und den Status setzen
- „Automatically delete head branches“ einschalten
- Ablauf des Agenten-Tokens (06.11.2026) vormerken
