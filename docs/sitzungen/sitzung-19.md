# Sitzungsbericht Sitzung 19

**Datum:** 22.10.2026 (begonnen 21.10.2026)
**Phase:** Schritt 5 (CD): Update-Lücke bei Docker Rootless gemessen und
geschlossen; Plattenplatz begrenzt; Host-Überwachung per Prüfskript und
Timer aktiv (Warnung bisher nur im Journal)
**Vorgänger:** sitzung-18.md (abgeschlossen 21.10.2026)

---

## 1. Erledigt

In dieser Sitzung gab es außer diesem Bericht keine PRs und keine Commits. Alle Arbeiten fanden
auf dem Staging-Server statt. Die Projekt-Ownerin hat jeden Befehl selbst
eingegeben und die Ausgaben zurückgemeldet.

### 1.1 Recherche vor der Entscheidung zur Update-Lücke (21.10.2026)

| Gegenstand | Ergebnis |
|---|---|
| `needrestart` | Debian trixie: 3.11-1 (Debian Package Tracker). Vorgeschichte: mehrere Lücken zur Rechteausweitung durch lokale Benutzer (CVE-2024-48990 ff., Gentoo GLSA 202608-22 vom August 2026). Benutzerdienste meldet es nur, es startet sie nicht neu. |
| runc CVE-2026-41579 | Symlink-Lücke beim Einrichten des rootfs, CVSS 3.3 bzw. 4.8. Fix-Commit `864db80` im runc-Repo. **Ob runc 1.5.2 aus `containerd.io` den Fix enthält, wurde nicht geprüft.** |
| Docker Engine 29.9.2 (Release-Seite `moby/moby`, `docker-v29.9.2`) | Go 1.26.10 wegen CVE-2026-111943: Go lehnt acht Zwischenzertifikate von eMudhra mit kompromittierten Schlüsseln ab. Relevant, weil der Daemon die Images lädt. Die CVE-Nummer wurde nicht gegen NVD oder CISA KEV geprüft. |

### 1.2 Update-Lücke: Hook installiert und an echtem Update gemessen (Roadmap-Punkt 1)

**Umsetzung (Option A, E-5-47, E-5-48):**

- `/usr/local/sbin/docker-restart-check` (root, `0755`): Prüft, ob ein
  Prozess von `deploy` eine Programmdatei unter `/usr/bin` oder `/usr/sbin`
  ausführt, die als `(deleted)` markiert ist. Wenn ja, legt es
  `/var/run/reboot-required` an, trägt `docker-rootless` in
  `/var/run/reboot-required.pkgs` ein und schreibt eine Zeile ins Journal
  (Tag `docker-restart-check`). Es endet immer mit Exit-Code 0.
- `/etc/apt/apt.conf.d/99docker-restart-check` (root, `0644`):
  `DPkg::Post-Invoke` mit `|| true`.
- Beide Dateien wurden vorher als Kopie geprüft (`sh -n`,
  `apt-config -c … dump`, danach `apt-get check`).

**Ungeplantes echtes Update:** Die als „gleiche Version“ gedachte
Gegenprobe `apt-get install --reinstall docker-ce-rootless-extras`
(21.10.2026, 18:27) hat die neueste verfügbare Version installiert und
wegen der exakten Abhängigkeit `docker-ce` und `docker-ce-cli` gleich mit
aktualisiert: 29.9.1 auf **29.9.2**. Das hätte `unattended-upgrades` am
nächsten Morgen ohnehin getan.

| Messung | Ergebnis |
|---|---|
| `readlink /proc/<pid>/exe` (Prozesse von `deploy`) | `dockerd (deleted)`, `rootlesskit (deleted)` |
| `docker version` als `deploy` | Client 29.9.2, Server **29.9.1** |
| `/var/log/apt/history.log` | Upgrade durch den Reinstall-Befehl, kein Lauf von `unattended-upgrades` |
| Hook | Laut Rückmeldung wie erwartet: genau eine Zeile im Journal des vorherigen Starts (`journalctl -b -1 -t docker-restart-check`). Die Datei `reboot-required` selbst wurde vor dem Neustart nicht angesehen. |
| Neustart | Von Hand (Sicherheit vor Beobachtung). Die Prüfungen vor dem Neustart wurden übersprungen und danach nachgeholt. |
| Nach dem Neustart | Laut Rückmeldung wie erwartet: kein `(deleted)`, `reboot-required` fehlt, Client = Server 29.9.2, `docker.service` und `docker.socket` mit Root `disabled`/`inactive`, Docker von `deploy` startet automatisch |

Die Update-Lücke ist damit zweifach gemessen (gelöschte Datei,
Versionsvergleich) und geschlossen.

### 1.3 Plattenplatz (Roadmap-Punkt 2)

| Schritt | Messung | Ergebnis |
|---|---|---|
| Ist-Zustand | `df -h / /var /home` | Eine Partition `/dev/vda4`, 62 GB, 4 % belegt |
| Journal | `sudo journalctl --disk-usage`, `ls -ld /var/log/journal` | 40 MB, dauerhaft gespeichert. Ohne `sudo` wurden nur 8 MB angezeigt (nur eigene Einträge). |
| Log-Treiber | `daemon.json` von `deploy` ergänzt (Kopie, `dockerd --validate` = `configuration OK`, Exit-Code 0, `mv`, Neustart des Benutzerdienstes) | `docker info`: `local`; neuer Test-Container `log-probe`: `local` |
| `userland-proxy` | `pgrep -u deploy -a docker-proxy` mit veröffentlichtem Port; Gegenkontrolle `pgrep -u deploy -a dockerd` | Kein `docker-proxy` (Exit-Code 1), `dockerd` sichtbar: Einstellung gilt weiter |
| Test-Container | Port nur an `127.0.0.1`, `--rm`, danach `docker stop` | Container weg, `docker ps -a` leer |
| Altes Image | `docker image rm nginxinc/nginx-unprivileged@sha256:d715f7a8…` | Gelöscht; nur `sha256:8f18dedf…` bleibt |
| Journal begrenzt | Drop-in `/etc/systemd/journald.conf.d/50-aufbewahrung.conf`, Neustart von `systemd-journald` | Startmeldung: `is 41.8M, max 1G, 982.1M free`, keine Warnung zu unbekannten Schlüsseln |

### 1.4 Host-Überwachung: Prüfskript und Timer (Roadmap-Punkt 2)

**Dateien (alle root):**

- `/usr/local/sbin/host-health-check` (`0755`)
- `/etc/systemd/system/host-health-check.service` (`0644`, 229 Bytes)
- `/etc/systemd/system/host-health-check.timer` (`0644`, 142 Bytes),
  `enabled`

Die Unit-Dateien waren schon um 00:53 installiert, aus einer früheren,
zu langen Anleitung mit vielen Schritten auf einmal. Ihre Größen stimmten
auf das Byte mit dem geplanten Inhalt überein. Das Skript wurde danach in
der vereinfachten Fassung (nur `/`) ersetzt.

| Test | Ergebnis |
|---|---|
| Negativtest von Hand (01:39) | Exit-Code 0, Journal `ok` |
| Negativtest unter systemd mit Einschränkungen (01:44) | Journal `ok`: Die Einschränkungen blockieren keine Prüfung |
| Gegenprobe Plattenplatz (`SCHWELLE=1`) | Exit-Code 1, `Plattenplatz bei 3 Prozent` |
| Gegenprobe Firewall (`nft destroy table` und sofortiges Neuladen in einer Zeile) | `Tabelle host_fw fehlt`, **ohne** `nftables nicht aktiv`; Tabelle danach wieder geladen (`policy drop`) |
| Gegenprobe Docker (Benutzerdienst gestoppt, danach gestartet) | Exit-Code 1, `dockerd von deploy laeuft nicht`; Docker danach `active` |
| Gegenprobe Update-Lücke über 26 Stunden | **Nicht gemessen** |
| Timer eingeschaltet | Sofortiger Lauf 01:49:53 mit `ok`; nächster Lauf 02:00 angezeigt |

---

## 2. Gelernt

- Ein Paket-Update eines Benutzerdienstes von Docker Rootless startet den
  Daemon nicht neu. Datei und Prozess laufen auseinander, ohne dass
  jemand gewarnt wird.
- `readlink /proc/<pid>/exe` zeigt `(deleted)`, wenn ein Prozess eine
  inzwischen ersetzte Programmdatei ausführt. Das erkennt auch Neubauten
  mit gleicher Versionsnummer, ein Versionsvergleich nicht.
- `apt-get install --reinstall <paket>` installiert die neueste verfügbare
  Version, nicht die vorhandene, und zieht exakte Abhängigkeiten mit. Vor
  so einem Test gehört `apt-cache policy <paket>` dazu, oder die Version
  wird mit `paket=version` festgelegt.
- `Automatic-Reboot-Time` ist kein eigener Timer: `unattended-upgrades`
  plant den Neustart erst am Ende seines Laufs (gegen 06:00) für die
  eingestellte Uhrzeit. Ein Update aus dem Lauf am Morgen wird erst um
  04:00 in der folgenden Nacht wirksam, nach etwa 22 Stunden.
- `/var/run/reboot-required` liegt im Arbeitsspeicher und verschwindet
  beim Neustart. Ein Beleg danach ist nur noch über das dauerhaft
  gespeicherte Journal möglich (`journalctl -b -1`).
- `journalctl` ohne `sudo` zeigt nur die eigenen Einträge. Größen und
  Suchergebnisse sind dann unvollständig, ohne dass ein Fehler erscheint.
- Der Log-Treiber `json-file` hat keine Größengrenze. `local` rotiert und
  komprimiert von selbst (5 Dateien zu je 20 MB pro Container). Die
  Vorgabe im Daemon gilt nur für neu erstellte Container.
- Die Konfiguration des Daemons wirkt erst nach dessen Neustart.
  `dockerd --validate --config-file` prüft eine Kopie, ohne den laufenden
  Daemon zu berühren.
- Bei `userland-proxy: true` gäbe es pro veröffentlichtem Port einen
  Prozess `docker-proxy`. Dass er fehlt, ist ein einfacher Beleg für die
  Einstellung, aber nur zusammen mit einer Gegenkontrolle, die zeigt, dass
  `pgrep` die Prozesse überhaupt sieht.
- Docker 29 mit dem Image-Speicher von containerd verwendet den Digest
  als Image-ID.
- Das Journal enthält über die Logs von `sshd` IP-Adressen. Eine
  Größengrenze ist keine Aufbewahrungsfrist. `MaxRetentionSec` löscht nur
  ganze Dateien, deshalb gehört `MaxFileSec` dazu.
- `nftables.service` bleibt `active`, auch wenn die Tabelle fehlt. Eine
  Prüfung nur des Dienstes hätte den Fall aus Sitzung 18 nicht erkannt.
- Ein Timer mit `OnBootSec`, der nach Ablauf dieser Zeit eingeschaltet
  wird, löst sofort einmal aus.
- Eine `ok`-Zeile pro Lauf ist ein Lebenszeichen: Fehlt sie, ist die
  Prüfung selbst ausgefallen.
- Ein Server, der abgestürzt ist oder dessen Platte voll ist, kann keine
  Warnung senden. Nur ein externer Totmannschalter deckt das ab.
- Anleitungen mit vielen Schritten auf einmal führen zu unvollständigen
  Rückmeldungen und übersprungenen Prüfungen. Ein Schritt pro Antwort hält
  beide Seiten auf demselben Stand.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-47** | Update-Lücke über einen Hook `DPkg::Post-Invoke`, der `reboot-required` setzt und den bestehenden `Automatic-Reboot` um 04:00 nutzt; der Hook endet immer mit 0. `needrestart` verworfen, ebenso ein gezielter Neustart des Benutzerdienstes und das manuelle Vorgehen. | Keine neue Abhängigkeit, ein Mechanismus, der Kernel wird mit erneuert. Ein Hook darf apt nie blockieren, das Auffangen übernimmt die Überwachung. `needrestart` würde ein Werkzeug mit root-Rechten und einer Vorgeschichte von Rechteausweitungen bringen und Benutzerdienste ohnehin nicht neu starten. |
| **E-5-48** | Messung über „Prozess mit gelöschter Programmdatei“ statt Versionsvergleich | Erkennt alle Prozesse von `deploy` und Neubauten mit gleicher Version |
| **E-5-49** | *Kandidat, offen:* `Automatic-Reboot-Time "now"` | Verkürzt das Zeitfenster von etwa 22 Stunden auf Minuten, widerspricht aber E-5-32 |
| **E-5-50** | Ein Prüfskript plus Timer (`OnCalendar=*:0/15`, `OnBootSec=2min`), kein `OnFailure=`; neue Prüfungen kommen als Erweiterung im Skript dazu. Unit mit `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome=read-only`, `PrivateTmp`, `StateDirectory`. | Ein Mechanismus, eine Quelle der Wahrheit (Open/Closed), Least Privilege |
| **E-5-51** | Warnung vorerst nur ins Journal (`user.warning`, Tag `host-health-check`), plus `ok` als Lebenszeichen; Exit-Code 1 bei Problemen; was nicht prüfbar ist, zählt als Problem. Kanal später per ADR. | Grundlage für jeden späteren Kanal. A09 ist damit **noch nicht** erfüllt. |
| **E-5-52** | Journal: `MaxRetentionSec=30day`, `MaxFileSec=1day`, `SystemMaxUse=1G` als Drop-in | IP-Adressen sind personenbezogen (6.1.5); 30 Tage als Kompromiss zur Aufklärung von Vorfällen; vor Production neu bewerten |
| **E-5-53** | Log-Treiber `local` als Vorgabe im Daemon von `deploy` | Rotation und Grenze ohne Zusatzwerte (sicherer Default, 6.1.6); `docker logs` funktioniert weiter |

ADR-Kandidaten: E-5-47, E-5-48 und die Messergebnisse aus 1.2 gehören in
den **zweiten Nachtrag zu ADR-012**. E-5-50 bis E-5-53 gehören zusammen mit
E-5-40 bis E-5-45 in den **Nachtrag zu ADR-011**. E-5-49 wird bei der
Kanal-Entscheidung mitbewertet.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **Kanal für Warnungen fehlt** (A09): Warnungen stehen nur im Journal.
  Favorit ist ein externer Totmannschalter. Er braucht Aufnahme-Prüfung,
  Prüfung auf Slopsquatting und ein ADR. Die URL ist ein Secret und gehört
  nur auf den Server (`0600`).
- **Regelmäßige Läufe des Timers** sind nicht belegt, nur der erste Lauf
  beim Einschalten (01:49:53). Prüfen:
  `sudo journalctl -t host-health-check --since today`.
- **Gegenprobe „Update-Lücke über 26 Stunden“** ist nicht gemessen.
- **Automatischer Weg** (Hook, dann `unattended-upgrades`, dann Neustart um
  04:00) wurde noch nicht beobachtet. Beim nächsten echten Docker-Update
  mit `uptime -s` und `journalctl -b -1 -t docker-restart-check` prüfen.
  Unklar ist auch, ob `unattended-upgrades` ohne eigene Installation
  neu startet.
- **Frist des Journals** ab 18.11.2026 prüfen: Es darf keine Einträge
  geben, die älter als 30 Tage sind.
- **runc 1.5.2 und CVE-2026-41579:** Den Fix im GitHub-Advisory von runc
  nachsehen.
- **CVE-2026-111943:** Eintrag bei NVD und CISA KEV ist nicht geprüft.
- E-5-49 (`Automatic-Reboot-Time "now"`) ist offen.
- Das Prüfskript kennt keine Warnung für `docker-restart-check` selbst.
  Ein Ausfall des Hooks wird erst nach 26 Stunden über die Prüfung auf
  `(deleted)` sichtbar (so gewollt, siehe E-5-47).
- Bericht 18 ist gemergt (#99). Der lokale Branch `docs/sitzung-18` kann
  gelöscht werden („Automatically delete head branches“ ist nicht
  eingeschaltet, siehe unten).

**Aus Sitzung 18 und früher, weiter offen**

- NTS und die netcup-Regel `ntp-antworten` (Quellport lässt sich fälschen)
- Zugriffslog von nginx enthält Client-IPs: in der Staging-Variante von
  `compose.yaml` kürzen oder weglassen, Aufbewahrungsfrist festlegen
- Journal des ausgelösten Rücksprungs (`nft-rollback.service`) aus Sitzung
  18 nicht ausgewertet
- ADR-006, ADR-008, ADR-012 stehen auf „Vorgeschlagen“; „Akzeptiert“ setzt
  die Projekt-Ownerin
- Zweiter Nachtrag zu ADR-012, Nachtrag zu ADR-011, Nachtrag zu ADR-009 und
  ADR-005
- DNS/DNSSEC; TCP 80/443 erst beim TLS-Schritt öffnen; Maschinenkonto; 2FA
  für SCP/CCP nicht geprüft
- `compose.yaml` ohne `pids_limit`; Staging-Variante mit Image per Digest
- Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches“ nicht eingeschaltet
- Fingerprint des Docker-Schlüssels nur über Keyserver und
  `InRelease`-Signatur belegt (für Staging akzeptiert, ADR-012)

**Bekannte Grenzen**

- Für Staging akzeptierte Risiken nach E-5-24
- Ausgaben vom Server liegen nur als Rückmeldung der Projekt-Ownerin vor,
  teilweise nur zusammengefasst („wie erwartet“), nicht als Protokoll im
  Repository
- Gegenprobe 11 (echte Client-IP) wurde nach der Änderung von
  `daemon.json` nicht von außen wiederholt; belegt ist nur, dass es keinen
  `docker-proxy` gibt
- Die Gegenprobe Firewall hat die Host-Firewall für weniger als eine
  Sekunde entfernt; die netcup-Firewall war in dieser Zeit aktiv

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Staging-Server: SSH gehärtet, äußere Firewall
(netcup), Host-Firewall (nftables), automatische Updates inklusive Docker
**mit Neustart-Anforderung bei einer Update-Lücke**, Docker Rootless mit
**Log-Rotation**, Journal begrenzt, **Host-Überwachung aktiv** (ohne
Kanal). Es fehlen:

- Kanal für Warnungen, NTS
- DNS/TLS, Maschinenkonto, Pull-Deploy mit Gate, Freigabe, DORA-Events

| Thema | Status |
|---|---|
| **Lieferketten-Gate** | Nicht berührt: keine neue Abhängigkeit, `needrestart` bewusst verworfen. Der Kanal für Warnungen wird es berühren. |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** (OWASP ZAP) | Rückt näher: fällig mit dem ersten Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant) |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 `/usr/local/sbin/docker-restart-check` (Stand 21.10.2026)

```
#!/bin/sh
# Update-Luecke Docker Rootless (E-5-47, E-5-48)
# Laeuft ein Prozess von deploy mit einer ersetzten Programmdatei,
# wird ein Neustart angefordert (Automatic-Reboot 04:00, E-5-32).
# Endet immer mit 0, damit apt nie blockiert wird.
set -u
for pid in $(pgrep -u deploy); do
	exe=$(readlink "/proc/$pid/exe" 2>/dev/null) || continue
	case "$exe" in
		/usr/bin/*" (deleted)"|/usr/sbin/*" (deleted)")
			touch /var/run/reboot-required
			grep -qx docker-rootless /var/run/reboot-required.pkgs 2>/dev/null \
				|| echo docker-rootless >> /var/run/reboot-required.pkgs
			logger -t docker-restart-check "veraltete Programmdatei aktiv, Neustart angefordert"
			exit 0
			;;
	esac
done
exit 0
```

`/etc/apt/apt.conf.d/99docker-restart-check`:

```
// Update-Luecke Docker Rootless (E-5-47)
DPkg::Post-Invoke { "/usr/local/sbin/docker-restart-check || true"; };
```

### 6.2 `/usr/local/sbin/host-health-check` (Stand 22.10.2026)

```
#!/bin/sh
# Host-Pruefung Staging (E-5-50, E-5-51)
# Probleme gehen mit Prioritaet warning ins Journal, sonst eine ok-Zeile.
# Exit 1 bei mindestens einem Problem, damit die Unit als failed erscheint.
# Was nicht pruefbar ist, zaehlt als Problem (fail closed).
set -u
schwelle=${SCHWELLE:-80}
zustand=${STATE_DIRECTORY:-/var/lib/host-health-check}
probleme=0

warnen() {
	logger -p user.warning -t host-health-check "$1"
	probleme=$((probleme + 1))
}

belegt=$(df --output=pcent / 2>/dev/null | tail -n 1 | tr -dc '0-9')
if [ -z "$belegt" ]; then
	warnen "Plattenplatz nicht pruefbar"
elif [ "$belegt" -ge "$schwelle" ]; then
	warnen "Plattenplatz bei $belegt Prozent"
fi

systemctl is-active --quiet nftables || warnen "nftables nicht aktiv"
nft list table inet host_fw > /dev/null 2>&1 || warnen "Tabelle host_fw fehlt"

pgrep -u deploy -x dockerd > /dev/null || warnen "dockerd von deploy laeuft nicht"

alt=0
for pid in $(pgrep -u deploy); do
	case "$(readlink "/proc/$pid/exe" 2>/dev/null)" in
		/usr/bin/*" (deleted)"|/usr/sbin/*" (deleted)") alt=1; break ;;
	esac
done
mkdir -p "$zustand"
if [ "$alt" -eq 1 ]; then
	[ -e "$zustand/veraltet-seit" ] || touch "$zustand/veraltet-seit"
	if [ -n "$(find "$zustand/veraltet-seit" -mmin +1560)" ]; then
		warnen "veraltete Programmdatei seit mehr als 26 Stunden aktiv"
	fi
else
	rm -f "$zustand/veraltet-seit"
fi

if [ "$probleme" -eq 0 ]; then
	logger -p user.info -t host-health-check "ok"
	exit 0
fi
exit 1
```

`SCHWELLE` ist eine Testschraube (nur root, der Timer setzt sie nie).
Die Grenze von 26 Stunden liegt über dem normalen Zeitfenster von etwa
22 Stunden zwischen Update und Neustart um 04:00.

### 6.3 Units

`/etc/systemd/system/host-health-check.service`:

```
[Unit]
Description=Host-Pruefung Staging (E-5-50)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/host-health-check
StateDirectory=host-health-check
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
```

`/etc/systemd/system/host-health-check.timer` (`enabled`):

```
[Unit]
Description=Host-Pruefung Staging alle 15 Minuten (E-5-50)

[Timer]
OnBootSec=2min
OnCalendar=*:0/15

[Install]
WantedBy=timers.target
```

### 6.4 Weitere Konfiguration

`/home/deploy/.config/docker/daemon.json` (Besitzer `deploy`):

```
{
  "userland-proxy": false,
  "log-driver": "local"
}
```

`/etc/systemd/journald.conf.d/50-aufbewahrung.conf` (root, `0644`):

```
# Aufbewahrung Journal Staging (E-5-52)
# Journal enthaelt IP-Adressen (sshd), also personenbezogene Daten (6.1.5).
# MaxFileSec=1day, damit die 30-Tage-Frist tagesgenau greift.
[Journal]
MaxRetentionSec=30day
MaxFileSec=1day
SystemMaxUse=1G
```

### 6.5 Versionen und Messwerte (Stand 22.10.2026)

- Docker Engine **29.9.2** (Client und Server, gebaut 20.10.2026, Go
  1.26.10), `containerd` 2.4.2, runc 1.5.2, RootlessKit 3.3.0,
  docker-init 0.19.0
- Image im Speicher von `deploy`: nur noch
  `nginxinc/nginx-unprivileged@sha256:8f18dedfceea3d7feb98792810c8c9925c985890ade257f2ec1b2f492b4eaebb`
  (Digest aus Sitzung 17, gepinnt in `compose.yaml`)
- Partition `/dev/vda4`: 62 GB, nach dem Aufräumen 3 % belegt
- Journal: 41,8 MB, Obergrenze 1 GB, ältester Eintrag 18.10.2026
- `needrestart` in Debian trixie: 3.11-1 (nicht installiert)

### 6.6 Fallstricke, die Zeit gekostet haben

- `--reinstall` als Gegenprobe hat ein echtes Update eingespielt (siehe
  1.2).
- Die Annahme, `unattended-upgrades` habe das Update eingespielt, war
  falsch. Erst `/var/log/apt/history.log` zeigte die Ursache.
- Ein Neustart vor den Prüfungen hat den direkten Beleg
  (`reboot-required`) gelöscht. Was einen Neustart nicht übersteht, muss
  vorher abgelesen werden.
- Eine Anleitung mit Teil A bis D in einer Nachricht führte dazu, dass
  Units schon installiert waren, bevor das Skript feststand. Die
  Bestandsaufnahme (`ls -l /etc/systemd/system/ | grep host-health`, Größe
  der Dateien) hat das aufgeklärt.
- `journalctl --disk-usage` ohne `sudo` lieferte 8 MB statt 40 MB.

### 6.7 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Update-Lücke messen | Datei und Prozess können auseinanderlaufen | `sudo sh -c 'for p in $(pgrep -u deploy); do readlink /proc/$p/exe; done' \| sort -u` | `(deleted)` bei `dockerd` und `rootlesskit` |
| Ursache finden | Erst verstehen, dann handeln | `grep -B1 -A4 "docker-ce" /var/log/apt/history.log` | Upgrade durch den Reinstall |
| Hook-Beleg nach Neustart | `/run` ist flüchtig | `sudo journalctl -b -1 -t docker-restart-check` | Eine Zeile |
| Docker-Konfiguration prüfen | Fehlerhafte Datei verhindert den Start | `dockerd --validate --config-file ~/.config/docker/daemon.json.new` | `configuration OK`, Exit-Code 0 |
| Wirkung prüfen | `active` heißt nicht „übernommen“ | `docker info --format "{{.LoggingDriver}}"`, `docker inspect --format "{{.HostConfig.LogConfig.Type}}" log-probe` | `local`, `local` |
| `userland-proxy` prüfen | Echte Client-IP hängt davon ab | `pgrep -u deploy -a docker-proxy` plus Gegenkontrolle mit `dockerd` | Kein Proxy, `pgrep` sieht `deploy` |
| Image löschen | Platz und keine alten startbaren Images | `docker image rm …@sha256:d715f7a8…` | Nur `8f18dedf…` bleibt |
| Journal begrenzen | Personenbezogene Daten, Plattenplatz | Drop-in, `sudo systemctl restart systemd-journald` | `max 1G` in der Startmeldung |
| Negativtests | Ursachen trennen (Skript gegen Einschränkungen) | Skript von Hand, danach `systemctl start host-health-check.service` | Zweimal `ok` |
| Gegenproben | Ein `ok` beweist nur etwas, wenn die Prüfung auch warnen kann | `SCHWELLE=1`; `nft destroy table …; …; nft -f /etc/nftables.conf`; Docker gestoppt | Drei Warnungen |
| Scharf schalten | Erst nach bestandenen Gegenproben | `sudo systemctl enable --now host-health-check.timer` | `ok` um 01:49:53 |

---

# Roadmap Sitzung 20

## 1. Kanal für Warnungen (A09) und Nachkontrolle des Timers

Warum zuerst: Die Überwachung läuft, aber eine Warnung erreicht niemanden.
Ohne Alerting ist A09 nicht erfüllt, und alle bisherigen Prüfungen bleiben
stumm. Das ist sicherheitlich wichtiger als NTS.

Bausteine:
- Zum Einstieg kurz die Läufe des Timers seit dem 22.10. prüfen
  (`sudo journalctl -t host-health-check --since "2026-10-22"`). Dort
  sollen `ok`-Zeilen alle 15 Minuten stehen.
- Optionen vergleichen: E-Mail, Push über HTTPS, externer Totmannschalter.
  Favorit ist der Totmannschalter, weil er auch einen toten Server
  erkennt.
- Aktualität nach CLAUDE.md 1 prüfen. Jeder Dienst und jedes Paket
  braucht die Aufnahme-Prüfung, die Prüfung auf Slopsquatting und ein ADR.
- Das Secret (URL oder Zugangsdaten) liegt nur auf dem Server, nie im
  Repo oder im Chat.
- E-5-49 (`Automatic-Reboot-Time "now"`) mitbewerten.

## 2. NTS und netcup-Regel `ntp-antworten`

Warum: Beides betrifft NTP, und die Regel mit Quellport 123 lässt sich
fälschen. Bausteine: NTS-Entscheidung, danach die netcup-Regel anpassen
oder begründet belassen.

## 3. ADR-Nachträge (je ein PR)

Warum: Die Entscheidungen sind getroffen und gemessen, aber noch nicht
dokumentiert.
- Zweiter Nachtrag zu ADR-012: Messergebnisse der Installation, alle 11
  Gegenproben, E-5-39, E-5-46, E-5-47, E-5-48
- Nachtrag zu ADR-011: E-5-40 bis E-5-45, E-5-50 bis E-5-53, Kanal, NTS

## 4. Folgende Sitzungen (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 21 | DNS/TLS, Maschinenkonto, Pull-Deploy mit Prüfung von Nachweis und Signatur; Staging-Variante von `compose.yaml` (`pids_limit`, Image per Digest, IP im Zugriffslog); Missbrauchsfälle aus ADR-011 als Gegentests |
| 22 | Freigabe vor dem Deploy, DORA-Events; DAST wird fällig |
| ab 22/23 | Phase 5: STRIDE, erster Use Case test-first |

## 5. Vor oder in der Sitzung zu verstehen (vor Code)

- **Logging gegen Alerting:** Logging schreibt auf, Alerting weckt
  jemanden. Eine Warnung im Journal, die niemand liest, schützt nicht.
- **Totmannschalter:** Der Server meldet sich regelmäßig mit „Ich lebe“
  bei einem externen Dienst. Bleibt die Meldung aus, warnt der Dienst. So
  werden auch ein abgestürzter Server, eine volle Platte und ein
  ausgefallenes Prüfskript sichtbar. Der Preis ist eine externe
  Abhängigkeit und eine URL, die geheim bleiben muss.
- **NTS (Network Time Security):** Schützt Zeitangaben per TLS gegen
  Fälschung. Eine falsche Uhrzeit bricht Zertifikatsprüfungen, Token-
  Laufzeiten und die zeitliche Einordnung im Log.

## 6. Optionale Vorbereitung

- Überlegen, auf welchem Gerät Warnungen ankommen sollen (Handy, E-Mail)
- 2FA im netcup-Konto (SCP und CCP) prüfen
- ADR-006, ADR-008, ADR-012 lesen und den Status setzen
- „Automatically delete head branches“ einschalten
- Ablauf des Agenten-Tokens (06.11.2026) vormerken
