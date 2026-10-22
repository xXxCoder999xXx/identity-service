# Sitzungsbericht Sitzung 20

**Datum:** 22.10.2026
**Phase:** Schritt 5 (CD): Kanal für Warnungen (A09) für den Staging-Host
umgesetzt und mit vier Gegenproben belegt; externer Totmannschalter aktiv
**Vorgänger:** sitzung-19.md (abgeschlossen 22.10.2026)

---

## 1. Erledigt

In dieser Sitzung gab es keine PRs und keine Commits. Alle Arbeiten fanden
auf dem Staging-Server und bei Healthchecks.io statt. Die Projekt-Ownerin
hat jeden Befehl selbst eingegeben und die Ausgaben zurückgemeldet.

### 1.1 Nachkontrolle des Timers (Roadmap-Punkt 1, Einstieg)

| Messung | Ergebnis |
|---|---|
| `journalctl -t host-health-check --since 2026-10-22`, gruppiert nach letztem Wort | 83 × `ok`, je 1 × `fehlt`, `nicht`, `Prozent` |
| Erwartung bei Serverzeit 21:33:57 | 79 Timer-Läufe (02:00 bis 21:30) + 1 Lauf beim Einschalten + 2 Negativtests = 82 |
| Warnungen mit Zeitstempel (`-p warning`) | 01:44:56, 01:46:26, 01:48:12: die drei Gegenproben aus Sitzung 19, alle vor dem Einschalten (01:49:53) |

Der Timer lief lückenlos. Das eine zusätzliche `ok` ist ein nicht
protokollierter Lauf von Hand während der Gegenproben in Sitzung 19 (ein
Mehr kann keinen Ausfall anzeigen).

### 1.2 Recherche und Aufnahme-Prüfung (Aktualität nach CLAUDE.md 1)

| Gegenstand | Ergebnis |
|---|---|
| CISA KEV | Neueste auffindbare Einträge vom September 2026 (Zyxel, Fortinet, Citrix, Cisco, MikroTik, Chromium); keiner betrifft den Stack. Einträge vom Oktober waren noch nicht indexiert. |
| ntfy | CVE-2026-39087 (CVSS 9.8), Fix laut GitLab-Advisory in v2.22.0; Quellen widersprechen sich bei der Ursache. Option verworfen, daher nicht weiter verfolgt. |
| Healthchecks.io: Betreiber | SIA Monkey See Monkey Do, Riga (EU); laut eigener Angabe eine Person, auch im Betrieb |
| Healthchecks.io: Hosting | Hetzner (Bare Metal, Land nicht genannt), verschlüsselte Backups bei AWS (Region nicht genannt) |
| Healthchecks.io: Subunternehmer | Hetzner, AWS, Twilio, Braintree, Fastmail |
| Healthchecks.io: Datenschutz | DSGVO-Rechte beschrieben; kein AVV/DPA erwähnt; keine Frist für Ping-Daten; Backups bis 2 Monate |
| Healthchecks.io: Software | BSD-3-Clause, selbst betreibbar; v5.0.1 vom 22.10.2026 (GitHub-API), Commits am selben Tag |
| Healthchecks.io: Advisories | GHSA-frxj-v529-jv6w (medium, 2023, E-Mail-Enumeration im Login), betrifft nicht die Pings |
| Healthchecks.io: Vorfälle | CodeShip-Vorfall (Secrets offen über Dienstleister, zurückgesetzt, keine Hinweise auf Missbrauch); 2026 mehrere Ausfälle durch das Netz von Hetzner |
| Ping-API | `https://hc-ping.com/<uuid>` und `/fail`, HEAD/GET/POST, Body bis 100 kB gespeichert, höchstens 5 Pings pro Minute |
| Lieferkette auf dem Server | Kein neues Paket (`curl` vorhanden), keine Prüfung auf Slopsquatting nötig |

Die drei Restrisiken (eine Person im Betrieb, kein AVV, URL als Secret) hat
die Projekt-Ownerin für Staging akzeptiert.

### 1.3 Konto und Check bei Healthchecks.io

- Konto mit Zwei-Faktor-Anmeldung, Status-Seite per E-Mail abonniert,
  Test-Mail angekommen
- Check: Simple, Periode 15 Minuten, Grace 10 Minuten, E-Mail-Integration
- Nach der Rotation (1.7) ist nur noch `staging-host-2` aktiv.

### 1.4 Ablage der Ping-URL auf dem Server

| Schritt | Befehl (Auszug) | Ergebnis |
|---|---|---|
| Bestandsaufnahme | `ls -ld /etc/credstore` | Vorhanden aus dem systemd-Paket, `drwx------ root root` |
| Leere Datei mit Rechten | `test ! -e … && install -m 0600 -o root -g root /dev/null …` | `-rw------- root root 0` |
| Eintragen | `sudoedit /etc/credstore/host-health-check.ping-url` | gespeichert |
| Prüfen ohne Anzeige | `ls -l`, `grep -cxE '<UUID-Muster>'`, `wc -l` | 57 Bytes, `1`, `1` |
| Erreichbarkeit | `curl -sS -o /dev/null -w "%{http_code} %{remote_ip}" https://hc-ping.com/` | `301` über IPv6 |

### 1.5 Skript und Unit erweitert

**Übertragung:** Beide Dateien lokal erzeugt (nur LF, `sh -n` ohne
Fehler), per `scp` als `.neu` ins Home-Verzeichnis kopiert und dort per
SHA-256 verglichen.

| Datei | Größe | SHA-256 (neu) |
|---|---|---|
| `/usr/local/sbin/host-health-check` | 2121 Bytes | `afcc5dd7c58d1d2c549e4cf41748777aa4d67378b72bf505ac30540f06044559` |
| `/etc/systemd/system/host-health-check.service` | 316 Bytes | `6eede988a2799c08e37d5239b7dc20576eee9a4f11d2d490044f53165d4d8eb7` |

**Unit (zuerst eingebaut):** `diff` zeigte genau zwei neue Zeilen
(`LoadCredential=`, `TimeoutStartSec=2min`). `systemd-analyze verify` unter
dem echten Dateinamen: Exit-Code 0. Eingebaut mit `install -m 0644`, danach
`daemon-reload`. `systemctl show` belegte `LoadCredential` und
`TimeoutStartUSec=2min`.

**Skript (danach eingebaut):** Ersetzt nur bei passendem Hash des
Zielstands (`sha256sum -c && install`). Der erste Versuch endete mit
`FAILED`, ohne Ersatz. Ursache laut `diff | cat -A`: Das aktive Skript hatte
8 Leerzeichen statt Tabs (1572 statt 1460 Bytes, 16 Tabs × 7 Bytes). Mit
dem Hash der per `expand` umgewandelten Bericht-Fassung
(`8cb9f80e705891d99f9680447163bb97ed3f0b27ebf71fbf68b9b137f9fe1af0`) lief
der Einbau. Inhaltlich wich das alte Skript nicht vom Bericht ab.

Arbeitskopien danach gelöscht (`rm -v` einzeln, `rmdir -v ~/verify`).

### 1.6 Gegenproben

| Nr. | Frage | Auslöser | Beleg |
|---|---|---|---|
| 1 | Kommt `ok` vom Server an? | Timer 23:00; `systemctl start` 23:10 | Events OK von der IPv6 des Servers mit `curl/8.1…`; Status up; UP-Mail |
| 2 | Alarmiert `/fail` allein? | `systemd-run` mit Credential und `SCHWELLE=1`, 23:13:52 | Mail „received a failure signal“ in derselben Minute, Body „Plattenplatz bei 3 Prozent“; Exit-Code 1 |
| 3 | Credential fehlt? | `systemd-run -p LoadCredential=ping-url:/etc/credstore/gibt-es-nicht` | `status=243/CREDENTIALS`, 27 ms, Journal ab 23:16 leer |
| 4 | Alarmiert Stille? | kein Ping zwischen 22:00 und 22:25 (altes Skript noch aktiv) | Mail „grace time passed“, Status down um 22:25:12 |

Laufzeit eines Laufs mit Ping: etwa 150 ms.

### 1.7 Ungeklärter Ping und Rotation der URL

- 22:00: Erster Ping an die erste URL kam vom Anschluss der
  Projekt-Ownerin mit einem Windows-User-Agent, nicht vom Server. Auf
  Nachfrage zunächst als „nicht ausgeführt“ beantwortet; im
  PowerShell-Verlauf (`ConsoleHost_history.txt`) 0 Treffer für `hc-ping`.
- Bewertung nach fail-closed: Secret mit ungeklärter Nutzung gilt als
  kompromittiert.
- Rotation: neuer Check `staging-host-2`, neue URL per `sudoedit`, Prüfung
  ohne Anzeige (57 Bytes, `1`, `1`), Beleg über Event am neuen Check
  (23:10, Server, `curl/…`), alter Check gelöscht.
- Zum Sitzungsende klärte die Projekt-Ownerin: Der Ping um 22:00 war ein
  eigener manueller Test. Kein Sicherheitsvorfall.

### 1.8 Lehrstoff

Konzept als Lehrstoff dokumentiert:
[Lehrstoff: Totmannschalter und Secrets auf dem Host](https://claude.ai/artifact/VG5QsZjZtuXozLzjkUbxeh)
(Logging gegen Alerting, Secrets auf Linux, Prüfen ohne Ansehen,
geschütztes Ersetzen, systemd-Details, Gegenproben, Rotation, Spickzettel).

---

## 2. Gelernt

- Logging schreibt auf, Alerting weckt jemanden; eine Warnung im Journal
  ohne Kanal erfüllt A09 nicht.
- Ein Totmannschalter alarmiert über ausbleibende Meldungen und erkennt
  damit auch einen toten Server; während eines Ausfalls des Dienstes selbst
  ist man allerdings blind.
- Die Kommandozeile jedes Prozesses ist für alle lokalen Benutzer lesbar
  (`/proc/<pid>/cmdline`); ein Secret gehört nie in ein Argument.
- `curl -K -` liest die Konfiguration, auch die URL, von der
  Standardeingabe.
- `LoadCredential=` stellt ein Secret nur für die Laufzeit in
  `$CREDENTIALS_DIRECTORY` bereit; fehlt die Datei, startet systemd den
  Dienst nicht (`243/CREDENTIALS`).
- `Type=oneshot` hat ohne `TimeoutStartSec=` kein Zeitlimit.
- `systemd-analyze verify` braucht die Endung des Unit-Typs im Dateinamen,
  sonst `Invalid argument`.
- `install -m -o -g` setzt Rechte und Besitzer in einem Schritt; mit
  `/dev/null` als Quelle entsteht eine leere Datei mit festen Rechten.
- `sudoedit` lässt den Editor ohne root-Rechte laufen und hält das Secret
  aus dem Bash-Verlauf.
- Ein Secret prüft man über Format, Größe und Rechte (`grep -cx`, `wc`,
  `ls -l`), nicht durch Ansehen.
- `scp` plus SHA-256-Vergleich ersetzt fehleranfälliges Einfügen in nano;
  `sha256sum -c && install` ersetzt nur einen bekannten Zielstand.
- `diff | cat -A` macht Tabs (`^I`), Zeilenenden (`$`) und `\r` (`^M`)
  sichtbar.
- Ein grüner Status beweist nichts ohne Herkunft: Absender-IP, User-Agent
  und Zeit gehören zur Prüfung.
- Healthchecks.io benachrichtigt nur bei Statuswechsel; eine Probe auf
  `/fail` braucht vorher den Status up.
- `logger` wartet nicht auf journald; `journalctl` im selben Befehl kann die
  Zeile noch nicht sehen.
- systemd-Timer laufen standardmäßig mit bis zu 1 Minute Versatz
  (`AccuracySec=1min`).
- Ein Secret mit ungeklärter Nutzung wird rotiert; Löschen statt Pausieren
  macht die alte URL wertlos.
- Unangekündigte manuelle Tests sehen von außen aus wie ein Angriff; sie
  gehören sofort ins Protokoll.
- Platzhalter in Befehlen führen zu Fehlausführungen (`<ssh-ziel>` wurde in
  bash als Umleitung gelesen); Befehle müssen vollständig sein und den Ort
  der Ausführung nennen.

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-5-54** | Kanal für Warnungen: externer Totmannschalter Healthchecks.io, E-Mail, Periode 15 min, Grace 10 min; `ok`-Ping als Lebenszeichen, `/fail` mit festen Warntexten im Body. E-Mail vom Server und Push (ntfy) verworfen. | Nur der Totmannschalter erkennt einen toten Server (fail-closed). Kein neues Paket. Restrisiken akzeptiert für Staging: Betrieb durch eine Person, kein AVV, URL als Secret; vor Production neu bewerten. |
| **E-5-55** | Ping-URL in `/etc/credstore/host-health-check.ping-url` (`0600`, root), Übergabe per `LoadCredential=`, an curl per `-K -`; `TimeoutStartSec=2min` | Secret weder in Unit, Umgebung, Skript noch Kommandozeile (Least Privilege, 6.3.3); fehlende Credential verhindert den Start (fail-closed) |
| **E-5-49** | Verworfen: `Automatic-Reboot-Time` bleibt 04:00 (E-5-32) | Die Prüfung nach 26 Stunden alarmiert jetzt wirklich; ein ungeplanter Neustart am Vormittag bringt mehr Unruhe als Sicherheit |
| **E-5-56** | Änderungen an Host-Dateien: lokal erzeugen, `scp`, SHA-256 vergleichen, `diff` gegen Ziel, Ersatz nur per `sha256sum -c && install` | Byte-genaue Übertragung; nichts wird überschrieben, dessen Stand unbekannt ist |
| **E-5-57** | Secret mit ungeklärter Nutzung wird sofort rotiert (neuer Check, alter gelöscht) | fail-closed; Kosten Minuten, Schaden eines überdeckten Ausfalls hoch |
| **E-5-58** | Gegenproben mit Credential über `systemd-run --wait -p LoadCredential=…`; Journal als eigener Schritt danach lesen | Gleiche Bedingungen wie im Betrieb; vermeidet den Wettlauf zwischen `logger` und `journalctl` |
| **E-5-59** | Roadmap-Abkürzung: nach dem ADR zum Warnkanal direkt der kritische Pfad von CD (DNS/TLS, Maschinenkonto, Pull-Deploy, Freigabe, DORA); NTS und ADR-Nachträge zurückgestellt | Schnellerer Weg zu Phase 5 ohne Verletzung der Phasenreihenfolge; NTS spätestens vor Production, DAST bleibt an den ersten automatischen Deploy gebunden |
| **E-5-60** | Zu jedem Sitzungsende ein Lehrstoff als Claude Doc (Skill `sitzung-beenden`, Schritt 3) | Lernen ist oberstes Ziel (CLAUDE.md 1); strengere Datenregel, weil das Dokument außerhalb des Repositorys liegt |

ADR-Kandidaten: E-5-54, E-5-55, E-5-57 und die Messwerte aus 1.6 gehören in
den **Nachtrag zu ADR-011** (zusammen mit E-5-40 bis E-5-45 und E-5-50 bis
E-5-53). E-5-56 und E-5-58 als Arbeitsweise dort mit aufnehmen. Wegen der
neuen externen Abhängigkeit ist für E-5-54 alternativ ein eigenes ADR zu
prüfen.

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- **ADR zum Kanal fehlt** (Lieferketten-Gate: neue externe Abhängigkeit
  Healthchecks.io). Die Aufnahme-Prüfung aus 1.2 ist die Grundlage.
- Beschreibung des Checks nennt `docs/sitzungen/sitzung-19.md Abschnitt
  6.2` als Runbook; Kürzung auf einen ADR-Verweis ist der Projekt-Ownerin
  freigestellt. Der Hinweis „Abschnitt 6.2“ ist mit diesem Bericht
  veraltet (aktueller Stand in 6.2 unten).
- Eintrag der Ping-URL im Verlauf der Zwischenablage (`Win+V`) löschen,
  falls der Verlauf aktiv ist (nicht bestätigt).
- Bericht 19, Abschnitt 6.2, gab das Skript nur inhaltlich wieder, nicht
  byte-genau (Tabs statt Leerzeichen). Ab jetzt gilt die Fassung mit Tabs
  (Hash in 1.5).
- Bericht 19 ist gemergt (#100). Der lokale Branch `docs/sitzung-19` kann
  gelöscht werden.
- IPv4-Erreichbarkeit von `hc-ping.com` nicht getestet (nur IPv6); `curl`
  weicht bei Bedarf aus.
- Restrisiko Ausfall von Healthchecks.io: Während eines Ausfalls keine
  Alarmierung. Vor Production: zweiter Kanal oder eigene Instanz auf einem
  anderen Host bewerten.

**Aus Sitzung 19 und früher, weiter offen**

- Automatischer Weg (Hook, `unattended-upgrades`, Neustart 04:00) beim
  nächsten echten Docker-Update beobachten (`uptime -s`,
  `journalctl -b -1 -t docker-restart-check`)
- Gegenprobe „Update-Lücke über 26 Stunden“ nicht gemessen; jetzt würde sie
  per Mail sichtbar
- Frist des Journals ab 18.11.2026 prüfen (keine Einträge älter als 30 Tage)
- runc 1.5.2 und CVE-2026-41579: Fix im GitHub-Advisory nachsehen
- CVE-2026-111943: Eintrag bei NVD und CISA KEV nicht geprüft
- NTS und die netcup-Regel `ntp-antworten`
- Zugriffslog von nginx mit Client-IPs (Staging-Variante von `compose.yaml`)
- Journal des Rücksprungs (`nft-rollback.service`) aus Sitzung 18 nicht
  ausgewertet
- ADR-006, ADR-008, ADR-012 auf „Vorgeschlagen“; Nachträge zu ADR-012
  (zweiter), ADR-011, ADR-009, ADR-005
- DNS/DNSSEC; TCP 80/443 erst beim TLS-Schritt; Maschinenkonto; 2FA für
  SCP/CCP
- `compose.yaml` ohne `pids_limit`; Staging-Variante mit Image per Digest
- Token des Agenten läuft am 06.11.2026 ab; „Automatically delete head
  branches“ nicht eingeschaltet; lokaler Branch `docs/sitzung-18` kann weg

**Bekannte Grenzen**

- Ausgaben vom Server liegen nur als Rückmeldung der Projekt-Ownerin vor,
  nicht als Protokoll im Repository
- Für Staging akzeptierte Risiken nach E-5-24 und E-5-54

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD). Staging-Server: SSH gehärtet, äußere Firewall
(netcup), Host-Firewall (nftables), automatische Updates inklusive Docker
mit Neustart-Anforderung, Docker Rootless mit Log-Rotation, Journal
begrenzt, Host-Überwachung **mit Alarmierung per Totmannschalter**. Es
fehlen: NTS, DNS/TLS, Maschinenkonto, Pull-Deploy mit Gate, Freigabe,
DORA-Events.

| Thema | Status |
|---|---|
| **A09 (Alerting)** | Für den Staging-Host erfüllt, durch vier Gegenproben belegt |
| **Lieferketten-Gate** | Berührt: Healthchecks.io als externe Abhängigkeit; Aufnahme-Prüfung erledigt, ADR offen |
| **Agentic-Gate 6.5, LLM-Gate 6.4** | Nicht ausgelöst |
| **DAST** (OWASP ZAP) | Rückt näher: fällig mit dem ersten Staging-Deploy |
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet. Der Ping ist ein ausgehender Aufruf des Hosts (nicht der Anwendung) und hat Timeout und Retry. |
| **Contract Testing, mTLS** | Rücken näher (weitere Microservices geplant) |
| **Feature Flags** | Nicht fällig (E-5-16) |
| **Mutation Testing, k6** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

### 6.1 Healthchecks.io (Stand 22.10.2026)

- Check `staging-host-2`, Simple, Periode 15 min, Grace 10 min,
  Integration E-Mail; alter Check `staging-host` gelöscht
- Ping-URL (UUID-Form) nur in `/etc/credstore/host-health-check.ping-url`,
  `0600`, root, 57 Bytes, eine Zeile
- Software: Healthchecks v5.0.1 (22.10.2026, GitHub-API)

### 6.2 `/usr/local/sbin/host-health-check` (Stand 22.10.2026)

2121 Bytes, SHA-256
`afcc5dd7c58d1d2c549e4cf41748777aa4d67378b72bf505ac30540f06044559`,
Einrückung mit Tabs:

```
#!/bin/sh
# Host-Pruefung Staging (E-5-50, E-5-51, Kanal E-5-54, E-5-55)
# Probleme gehen mit Prioritaet warning ins Journal, sonst eine ok-Zeile.
# Exit 1 bei mindestens einem Problem, damit die Unit als failed erscheint.
# Was nicht pruefbar ist, zaehlt als Problem (fail closed).
# Ergebnis geht als Ping an den Totmannschalter. Die URL kommt per
# LoadCredential und steht nie in einer Kommandozeile (curl -K -).
set -u
schwelle=${SCHWELLE:-80}
zustand=${STATE_DIRECTORY:-/var/lib/host-health-check}
probleme=0
meldungen=""

warnen() {
	logger -p user.warning -t host-health-check "$1"
	probleme=$((probleme + 1))
	meldungen="$meldungen$1
"
}

pingen() {
	printf 'url = "%s"\n' "$1" \
		| curl -fsS -m 10 --retry 3 --retry-max-time 30 -o /dev/null -K - --data-binary "$2" \
		|| logger -p user.warning -t host-health-check "Ping fehlgeschlagen"
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

url=""
if [ -n "${CREDENTIALS_DIRECTORY:-}" ] && [ -r "$CREDENTIALS_DIRECTORY/ping-url" ]; then
	url=$(cat "$CREDENTIALS_DIRECTORY/ping-url")
fi
[ -n "$url" ] || warnen "Ping-URL nicht lesbar"

if [ "$probleme" -eq 0 ]; then
	logger -p user.info -t host-health-check "ok"
	pingen "$url" ""
	exit 0
fi
[ -z "$url" ] || pingen "$url/fail" "$meldungen"
exit 1
```

Ein Aufruf von Hand ohne Credential meldet „Ping-URL nicht lesbar“ und
sendet nichts. Tests deshalb über `systemd-run` (6.4).

### 6.3 `/etc/systemd/system/host-health-check.service` (Stand 22.10.2026)

316 Bytes, SHA-256
`6eede988a2799c08e37d5239b7dc20576eee9a4f11d2d490044f53165d4d8eb7`:

```
[Unit]
Description=Host-Pruefung Staging (E-5-50)

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/host-health-check
LoadCredential=ping-url:/etc/credstore/host-health-check.ping-url
TimeoutStartSec=2min
StateDirectory=host-health-check
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
PrivateTmp=yes
```

Timer `host-health-check.timer` unverändert (Bericht 19, 6.3).

### 6.4 Befehle für Gegenproben

```
sudo systemctl start host-health-check.service
sudo systemd-run --wait -p LoadCredential=ping-url:/etc/credstore/host-health-check.ping-url -E SCHWELLE=1 /usr/local/sbin/host-health-check
sudo systemd-run --wait -p LoadCredential=ping-url:/etc/credstore/gibt-es-nicht /usr/local/sbin/host-health-check
sudo journalctl -t host-health-check --since "<Zeit>" --no-pager
```

Erwartet: `inactive` bzw. Event OK; Exit 1 und Mail „received a failure
signal“; `243/CREDENTIALS`. Das Journal im eigenen Schritt lesen.

### 6.5 Fallstricke, die Zeit gekostet haben

- Ein Befehl mit Platzhalter `<ssh-ziel>` für PowerShell wurde in der
  SSH-Sitzung ausgeführt; bash las `<` als Umleitung. Nichts entstanden
  (geprüft). Befehle für Windows tragen jetzt Ort und vollständiges Ziel.
- `systemd-analyze verify` auf `*.service.neu` scheiterte am Dateinamen,
  nicht am Inhalt.
- `sha256sum -c` gegen den Hash aus dem Bericht scheiterte wegen
  Leerzeichen statt Tabs auf dem Server; der Schutz hat korrekt nichts
  ersetzt.
- „Check ist up“ um 22:00 kam nicht vom Server; erst der Screenshot der
  Events zeigte die Herkunft.
- Die DOWN-Mail um 22:25 kam aus der Grace, nicht aus dem `/fail` um 22:53;
  `/fail` aus dem Zustand down löst keine Mail aus.
- `journalctl` direkt nach `systemd-run` zeigte die neue Zeile noch nicht.

### 6.6 Konzeptprotokoll: Warum, Befehl, Wirkung

| Schritt | Warum | Befehl (Auszug) | Wirkung und Beleg |
|---|---|---|---|
| Timer zählen | Kanal nur an eine verlässliche Quelle hängen | `journalctl … \| awk '{print $NF}' \| sort \| uniq -c` | 83 `ok`, 3 Warnungen |
| Secret-Datei anlegen | Rechte vor Inhalt | `test ! -e … && install -m 0600 … /dev/null …` | `0600`, 0 Bytes |
| Secret eintragen | Kein root-Editor, kein Verlauf | `sudoedit …` | gespeichert |
| Secret prüfen | Ohne Anzeige | `ls -l; grep -cxE …; wc -l` | 57, 1, 1 |
| Erreichbarkeit | Firewall `policy drop` | `curl … https://hc-ping.com/` | 301 über IPv6 |
| Übertragen | Tabs und `\r` beim Einfügen | `scp …`, `sha256sum` | Hash gleich |
| Unit prüfen | Vor dem Ersetzen | `diff`, `systemd-analyze verify` | 2 Zeilen, Exit 0 |
| Unit übernehmen | Aktiv heißt nicht übernommen | `install`, `daemon-reload`, `systemctl show` | LoadCredential geladen |
| Skript ersetzen | Nur bekannter Zielstand | `sha256sum -c && install` | erst FAILED, nach Klärung OK |
| Gegenproben | Grün muss scheitern können | `systemctl start`, `systemd-run …` | 4 bestanden |
| Rotation | Ungeklärte Nutzung | neuer Check, `sudoedit`, alter gelöscht | Event am neuen Check vom Server |

---

# Roadmap Sitzung 21

## 1. ADR zum Kanal für Warnungen

Warum zuerst: Healthchecks.io ist eine neue externe Abhängigkeit, und nach
CLAUDE.md 5 (A03) braucht jede Abhängigkeit ein ADR. Die Fakten sind
frisch und vollständig (1.2, 1.6).

Bausteine:
- Entscheiden: eigenes ADR für E-5-54/E-5-55/E-5-57 oder Teil des
  Nachtrags zu ADR-011
- Inhalt: Optionen, Aufnahme-Prüfung, Restrisiken, Messwerte der
  Gegenproben, Bedingungen für die Neubewertung vor Production
- Mit `/adr`, Branch `docs/<kurzname>`, ein PR

## 2. Direkt weiter mit dem kritischen Pfad von CD: DNS/TLS

Warum: Entscheidung der Projekt-Ownerin am 22.10.2026 (E-5-59): Der
kritische Pfad zu Phase 5 hat Vorrang. DNS/TLS ist die Voraussetzung für
den Pull-Deploy und für das Öffnen von TCP 80/443. Bausteine: DNS/DNSSEC,
Zertifikat, TCP 80/443 erst in diesem Schritt öffnen.

## 3. Zurückgestellt, nicht aufgehoben

Diese Punkte blockieren CD nicht und werden nebenbei oder nach Phase 4
erledigt:

- **NTS und netcup-Regel `ntp-antworten`:** Die Regel mit Quellport 123
  lässt sich fälschen; eine falsche Uhrzeit bricht TLS, Token-Laufzeiten
  und die Einordnung im Log. Spätestens vor Production erledigen.
- **ADR-Nachträge** (je ein PR): zweiter Nachtrag zu ADR-012 (Messergebnisse
  der Installation, alle 11 Gegenproben, E-5-39, E-5-46, E-5-47, E-5-48);
  Nachtrag zu ADR-011 (E-5-40 bis E-5-45, E-5-50 bis E-5-53, E-5-56,
  E-5-58, NTS).

## 4. Folgende Sitzungen (Plan)

| Sitzung (ca.) | Schritt |
|---|---|
| 21 | ADR zum Warnkanal; Beginn DNS/TLS |
| 22 | DNS/TLS abschließen, Maschinenkonto, Pull-Deploy mit Prüfung von Nachweis und Signatur; Staging-Variante von `compose.yaml` (`pids_limit`, Image per Digest, IP im Zugriffslog); Missbrauchsfälle aus ADR-011 als Gegentests |
| 23 | Freigabe vor dem Deploy, DORA-Events; DAST wird mit dem ersten automatischen Staging-Deploy fällig |
| ab 24 | Phase 5: STRIDE, erster Use Case test-first |

Schätzung: Phase 5 nach etwa 3 Sitzungen, realistisch 3 bis 4; der Plan
ist in Sitzung 20 bereits um eine Sitzung gerutscht.

## 5. Vor oder in der Sitzung zu verstehen (vor Code)

- **ADR für eine externe Abhängigkeit:** Ein Dienst ist eine Abhängigkeit
  wie ein Paket. Das ADR hält fest, warum er gewählt wurde, welche Risiken
  bewusst akzeptiert sind und wann neu bewertet wird.
- **NTS (Network Time Security):** Schützt NTP-Antworten per TLS-basiertem
  Schlüsselaustausch gegen Fälschung. Ohne NTS kann ein Angreifer im Netz
  die Uhr verstellen.
- Lehrstoff zu dieser Sitzung:
  [Totmannschalter und Secrets auf dem Host](https://claude.ai/artifact/VG5QsZjZtuXozLzjkUbxeh)

## 6. Optionale Vorbereitung

- Lehrstoff durcharbeiten
- Beschreibung des Checks bei Healthchecks.io auf einen ADR-Verweis kürzen
- `Win+V` prüfen und den Eintrag der URL löschen
- 2FA im netcup-Konto (SCP und CCP) prüfen
- ADR-006, ADR-008, ADR-012 lesen und den Status setzen
- „Automatically delete head branches“ einschalten
- Ablauf des Agenten-Tokens (06.11.2026) vormerken
