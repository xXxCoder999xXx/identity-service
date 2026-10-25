# ADR-013: Kanal für Warnungen per externem Totmannschalter

- **Status:** Vorgeschlagen
- **Datum:** 2026-10-25

## Kontext

Der Staging-Host prüft sich seit Sitzung 19 alle 15 Minuten selbst
(`host-health-check`: Plattenplatz, nftables, Tabelle `host_fw`, `dockerd`
des Benutzers `deploy`, veraltete Programmdateien). Probleme landeten bisher
nur mit Priorität `warning` im Journal (E-5-51). Logging schreibt auf,
Alerting weckt jemanden: Eine Warnung, die niemand liest, erfüllt A09 nicht.

Wirkende Kräfte:

- **Fail closed:** Ein Server, der abgestürzt ist, keine Verbindung hat oder
  dessen Platte voll ist, kann keine Warnung senden. Der Kanal muss auch
  diesen Fall melden.
- **Minimale Abhängigkeiten:** Kein neues Paket auf dem Host, wenn ein
  vorhandenes Werkzeug reicht.
- **Secrets (6.3.3):** Das Zugangsmerkmal des Kanals darf weder in Unit,
  Umgebung, Skript noch Kommandozeile stehen. Die Kommandozeile jedes
  Prozesses ist für alle lokalen Benutzer lesbar (`/proc/<pid>/cmdline`).
- **Lieferkette (A03):** Ein externer Dienst ist eine Abhängigkeit wie ein
  Paket, lässt sich aber nicht per Hash auf einen Stand pinnen. Das ADR
  ersetzt den Pin durch Aufnahme-Prüfung, akzeptierte Restrisiken und einen
  Auslöser für die Neubewertung.

Die Entscheidung fiel am 22.10.2026 (Sitzung 20) und ist dort umgesetzt und
mit Gegenproben belegt.

## Entscheidung

Wir alarmieren über den externen Totmannschalter Healthchecks.io: Der Host
pingt nach jeder Prüfung, meldet Probleme über `/fail`, und bleibt der Ping
aus, verschickt Healthchecks.io nach Periode und Grace eine E-Mail.

| Code | Inhalt |
|---|---|
| E-5-54 | Healthchecks.io, Check `staging-host-2` (Simple), Periode 15 min, Grace 10 min, Integration E-Mail. Ohne Problem `ok`-Ping als Lebenszeichen, sonst Ping auf `/fail` mit den festen Warntexten im Body |
| E-5-55 | Ping-URL in `/etc/credstore/host-health-check.ping-url` (`0600`, root). Übergabe per `LoadCredential=` an `$CREDENTIALS_DIRECTORY`, an curl per `-K -` über die Standardeingabe. `TimeoutStartSec=2min`, weil `Type=oneshot` sonst kein Zeitlimit hat |
| E-5-57 | Eine Ping-URL mit ungeklärter Nutzung gilt als kompromittiert und wird sofort rotiert: neuer Check, neue URL, alter Check gelöscht (nicht pausiert) |

Ablauf eines Laufs:

```
 Timer (15 min) ──► host-health-check
                     ├─ keine Probleme ──► GET  hc-ping.com/<uuid>
                     └─ Probleme       ──► POST hc-ping.com/<uuid>/fail (Warntexte)
 Healthchecks.io: /fail            ──► E-Mail sofort
                  kein Ping 15+10 min ──► E-Mail (Grace abgelaufen)
```

Healthchecks.io benachrichtigt nur bei einem Statuswechsel. Ein `/fail` im
Zustand down löst keine weitere Mail aus.

## Betrachtete Alternativen

1. **E-Mail direkt vom Server:** verworfen. Ein toter oder vom Netz
   getrennter Server sendet nichts, der wichtigste Fall bliebe stumm. Dazu
   bräuchte der Host ein Mailprogramm, also ein neues Paket mit eigener
   Konfiguration und eigener Angriffsfläche.
2. **Push über ntfy:** verworfen. Ein Push vom Server hat dieselbe Lücke wie
   die E-Mail (kein Alarm bei totem Server). Für ntfy war zudem
   CVE-2026-39087 (CVSS 9.8) bekannt, Fix laut GitLab-Advisory in v2.22.0;
   die Quellen widersprachen sich bei der Ursache. Nach dem Verwerfen nicht
   weiter verfolgt.
3. **Eigene Healthchecks-Instanz:** nicht geprüft. Auf dem Staging-Host
   selbst wäre sie wertlos, weil sie mit dem Host ausfällt. Sinnvoll nur auf
   einem zweiten Host, mit eigenem Betrieb und eigenen Kosten. Bleibt Option
   für die Neubewertung (siehe Konsequenzen).
4. **Andere gehostete Totmannschalter:** In der Sitzung wurde kein weiterer
   Anbieter im Detail verglichen.

## Begründung

**Nur der Totmannschalter erkennt einen toten Server.** Er alarmiert über
das Ausbleiben einer Meldung, nicht über ihr Eintreffen. Damit ist er die
einzige der betrachteten Optionen, die fail closed ist.

**Kein neues Paket.** Der Ping nutzt das vorhandene `curl`. Eine Prüfung auf
Slopsquatting war nicht nötig, weil nichts installiert wurde.

**Aufnahme-Prüfung (22.10.2026, nachgeprüft am 25.10.2026):**

| Gegenstand | Ergebnis |
|---|---|
| Betreiber | SIA Monkey See Monkey Do, Riga (EU); laut eigener Angabe eine Person, auch im Betrieb |
| Hosting | Hetzner (Bare Metal, Land nicht genannt), verschlüsselte Backups bei AWS (Region nicht genannt) |
| Subunternehmer | Hetzner, AWS, Twilio, Braintree, Fastmail |
| Datenschutz | DSGVO-Rechte beschrieben; kein AVV/DPA erwähnt; keine Frist für Ping-Daten; Backups bis 2 Monate |
| Software | BSD-3-Clause, selbst betreibbar; v5.0.1 vom 22.10.2026 (GitHub-API, am 25.10.2026 weiter neueste Version) |
| Advisories | Nur GHSA-frxj-v529-jv6w (medium, 2023, E-Mail-Enumeration in Signup und Login), betrifft nicht die Pings; am 25.10.2026 kein neues |
| Vorfälle | CodeShip-Vorfall (Secrets offen über Dienstleister, zurückgesetzt, keine Hinweise auf Missbrauch); 2026 mehrere Ausfälle durch das Netz von Hetzner |
| Ping-API | `https://hc-ping.com/<uuid>` und `/fail`, HEAD/GET/POST, Body bis 100 kB gespeichert, höchstens 5 Pings pro Minute |
| Konto | Zwei-Faktor-Anmeldung, Status-Seite per E-Mail abonniert |

Die Ping-Daten enthalten keine personenbezogenen Daten: nur feste Warntexte
wie „Plattenplatz bei 3 Prozent“, die Absender-IP des Servers und den
User-Agent von curl.

**Gegenproben (22.10.2026):**

| Nr. | Frage | Auslöser | Beleg |
|---|---|---|---|
| 1 | Kommt `ok` vom Server an? | Timer; `systemctl start` | Event OK von der IPv6 des Servers mit `curl/…`; Status up; UP-Mail |
| 2 | Alarmiert `/fail` allein? | `systemd-run` mit Credential und `SCHWELLE=1` | Mail „received a failure signal“ in derselben Minute, Body „Plattenplatz bei 3 Prozent“; Exit-Code 1 |
| 3 | Credential fehlt? | `systemd-run -p LoadCredential=ping-url:/etc/credstore/gibt-es-nicht` | `status=243/CREDENTIALS` nach 27 ms, kein Lauf des Skripts |
| 4 | Alarmiert Stille? | 25 Minuten kein Ping | Mail „grace time passed“, Status down |

Ein Lauf mit Ping dauert etwa 150 ms. Ein grüner Status zählt nur mit
Herkunft: Absender-IP, User-Agent und Zeit gehören zur Prüfung. Der erste
Ping an die erste URL kam nicht vom Server; erst die Events zeigten das.

**Secret außerhalb jeder Kommandozeile.** `LoadCredential=` stellt die URL
nur für die Laufzeit des Dienstes bereit, `curl -K -` liest sie von der
Standardeingabe. Fehlt die Datei, startet systemd den Dienst nicht (Probe 3);
ruft man das Skript ohne Credential auf, meldet es „Ping-URL nicht lesbar“
und sendet nichts. Die Stille löst dann über die Grace den Alarm aus.

## Konsequenzen

**Positiv**

- A09 ist für den Staging-Host erfüllt und durch vier Gegenproben belegt.
- Auch ein toter, abgeschnittener oder voller Server fällt nach etwa
  25 Minuten auf (Periode plus Grace, dazu bis zu 1 Minute Versatz des
  Timers).
- Keine neue Software auf dem Host; der Ping hat Timeout (`-m 10`) und
  Retry (`--retry 3 --retry-max-time 30`).

**Negativ, für Staging akzeptiert (Projekt-Ownerin, 22.10.2026)**

- Betrieb durch eine einzelne Person beim Anbieter.
- Kein Vertrag zur Auftragsverarbeitung (AVV/DPA).
- Die Ping-URL ist ein Secret: Wer sie kennt, kann Lebenszeichen fälschen
  und damit einen Ausfall überdecken.
- Fällt Healthchecks.io aus, kommt kein Alarm. 2026 gab es mehrere Ausfälle
  durch das Netz von Hetzner.

**Pflichten**

- Rotation nach E-5-57 bei jeder ungeklärten Nutzung der URL.
- Manuelle Tests vorher ankündigen und sofort protokollieren; von außen
  sehen sie aus wie ein Angriff.
- Die Status-Seite von Healthchecks.io bleibt abonniert, damit ein Ausfall
  des Dienstes selbst auffällt.
- Die Ping-URL nie in Zwischenablage, Verlauf, Prompt oder Repository
  ablegen; prüfen nur über Format, Größe und Rechte, nicht durch Ansehen.

**Neubewertung**

Auslöser: vor Production, bei einem Wechsel von Betreiber, Hosting oder
Subunternehmern, oder bei einem Advisory, das die Ping-API betrifft. Dann zu
bewerten: zweiter, unabhängiger Kanal oder eigene Instanz auf einem anderen
Host (Alternative 3), AVV und Frist für Ping-Daten.

Arbeitsweisen aus derselben Sitzung (E-5-56, E-5-58) gelten für alle
Host-Dateien und gehören in den geplanten Nachtrag zu ADR-011.
