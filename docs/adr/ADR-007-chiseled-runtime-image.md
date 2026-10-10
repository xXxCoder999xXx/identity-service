# ADR-007: Chiseled Runtime-Image für die Anwendung

- **Status:** Akzeptiert
- **Datum:** 2026-10-10

## Kontext

Die Anwendung läuft als Container, und dasselbe Image geht von der CI über
Staging bis in die Produktion. Alles, was im Image liegt, ist damit dauerhafte
Angriffsfläche – auch das, was die Anwendung nie benutzt.

Kräfte:

- **Assume breach:** Nach einer erfolgreichen Codeausführung sucht ein
  Angreifer Shell, Paketmanager und Netzwerkwerkzeuge, um Befehle auszuführen
  und etwas nachzuladen. Was im Image fehlt, steht ihm nicht zur Verfügung.
- **Jede Abhängigkeit ist eine Sicherheitsentscheidung (A03):** Ein
  Basis-Image ist eine Abhängigkeit; jedes Paket darin kann eine Schwachstelle
  mitbringen, die gepatcht werden muss.
- **Sichere Defaults (A02):** Der Prozess soll nicht als root laufen.
- **Prüfbarkeit:** Das Image muss für einen Schwachstellen-Scanner lesbar
  bleiben (ADR-009). Ein Image, das der Scanner nicht versteht, meldet
  fälschlich „keine Funde".

Der Build ist zweistufig: Compiler, MSBuild und NuGet bleiben in der
Build-Stage (`sdk:10.0-noble`); in die Runtime-Stage gelangt nur das
Publish-Ergebnis. Die Entscheidung für das Runtime-Image fiel in Sitzung 6;
dieses ADR hält sie mit den Messungen aus Sitzung 9 und vom 10.10.2026 fest.

## Entscheidung

Wir verwenden `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` als
Runtime-Image, per Digest gepinnt, und setzen den Nicht-Root-Nutzer im
Dockerfile zusätzlich ausdrücklich (`USER $APP_UID`).

## Betrachtete Alternativen

- **Das volle Image `aspnet:10.0-noble`:** vertraut und mit Shell zur
  Fehlersuche. Verworfen, weil es genau die Werkzeuge mitbringt, die ein
  Angreifer nach einem Einbruch braucht, ohne weitere Angabe als root läuft
  und komprimiert rund drei Viertel größer ist (siehe Begründung).
- **Die Variante `-chiseled-extra`** (zusätzlich ICU und Zeitzonendaten):
  vorsorglich verworfen. Größere Fläche ohne belegten Bedarf; die Anwendung
  führt bisher keine kulturabhängigen Operationen aus.
- **Health-Prüfung im Container** (`HEALTHCHECK` mit `curl` oder einem eigenen
  Werkzeug): ohne Shell und ohne `curl` nicht möglich, und ein dafür
  nachgerüstetes Werkzeug wäre wieder Angriffsfläche. Entschieden wurde in
  Sitzung 3 die Prüfung von außen durch nginx hindurch; der Smoke-Test der
  Pipeline nutzt denselben Weg.
- **Auf den Nicht-Root-Default des Images vertrauen:** verworfen. Eine
  Sicherheitseigenschaft, die nur als unsichtbarer Default existiert,
  verschwindet bei einem Wechsel des Basis-Images lautlos.

## Begründung

„Chiseled" bedeutet, dass aus Ubuntu nur die Dateien herausgeschnitten werden,
die die .NET-Runtime braucht.

Messungen:

- **Shell und Paketmanager (10.10.2026, lokal, beide Images per Digest):** Im
  vollen Image `10.0-noble` startet `/bin/sh`, `apt-get` ist vorhanden,
  `dpkg-query` zählt 97 Pakete, und der Prozess läuft als root (UID 0, kein
  Nutzer in den Image-Metadaten). Im chiseled Image scheitert der Start von
  `/bin/sh` und von `/usr/bin/apt-get` mit „no such file or directory"; die
  Image-Metadaten nennen den Nutzer `1654`. Gegenprobe: `dotnet
  --list-runtimes` startet im chiseled Image und meldet die Runtime 10.0.12 –
  der Startversuch scheitert also an der fehlenden Datei, nicht am Aufruf.

- **Größe (10.10.2026, aus den Manifesten der Registry, `linux/amd64`,
  komprimiert):** volles Image `10.0-noble` 91,4 MiB in 6 Schichten; unser
  gepinntes chiseled Image 52,6 MiB in 5 Schichten.
- **Inhalt (Sitzung 9, Scanner auf dem Runner):** Im chiseled Image erkennt
  Grype Ubuntu, 9 Systempakete und die .NET-Runtime
  (`Betriebssystem=ubuntu Systempakete=9 Runtime-Paket=1`). Zum Vergleich: Das
  nginx-Image des Stacks hat 150 Systempakete.
- **Lesbarkeit für Scanner (Sitzung 9):** Berichte, Scanner könnten chiseled
  Images nicht lesen, haben sich nicht bestätigt. Grype v0.120.1 und Trivy
  0.75.0 erkennen Betriebssystem, Systempakete und Runtime.
- **Der Scan wirkt (Sitzung 9, PR #61):** Mit dem Runtime-Digest vom August
  meldet der Scan eine Lücke der Stufe High in OpenSSL und der Check
  `Image-Scan` wird rot.

Die Zahlen 97 und 9 stammen aus zwei verschiedenen Zählungen (`dpkg-query` im
laufenden Container, Scanner auf der Image-Datei) und sind deshalb als
Größenordnung zu lesen, nicht als exakter Vergleich. Im chiseled Image gibt es
kein `dpkg-query`, mit dem sich dieselbe Zählung wiederholen ließe.

## Konsequenzen

Positiv:

- Nach einem Einbruch in den Prozess fehlen Shell, Paketmanager und
  Netzwerkwerkzeuge.
- Weniger Pakete bedeuten weniger Schwachstellen, die gepatcht werden müssen,
  und kürzere Scan-Berichte.
- Das Image ist kleiner und damit schneller übertragen.

Negativ und neue Pflichten:

- **Keine Fehlersuche per Shell im Container.** `docker exec` mit einer Shell
  gibt es nicht; Diagnose läuft über Logs und über Prüfungen von außen.
- **Keine Health-Prüfung im Container.** `depends_on` kann deshalb nicht auf
  `service_healthy` warten.
- **Schreibbare Verzeichnisse brauchen die richtige Kennung:** `tmpfs`-Mounts
  mit `uid`/`gid` 1654, sonst sperrt sich der Dienst selbst aus.
- **Der Blindheits-Schutz bleibt Pflicht.** Dass Scanner das Image lesen, ist
  für die gemessenen Versionen belegt, nicht für künftige; das Skript bricht
  ab, wenn Betriebssystem, Systempakete oder Runtime nicht erkannt werden.
- **Bekannte Grenze:** Keiner der gemessenen Scanner meldet etwas zum
  Patch-Stand der .NET-Runtime selbst (ADR-009). Diesen deckt die Pflege des
  Digests ab (ADR-005).
- **Der Digest wandert mit jedem Patch-Release.** Dependabot schlägt das
  Update vor (Ökosystem `docker`).

Auslöser für eine Neubewertung: kulturabhängige Operationen ab Phase 5 (dann
`-chiseled-extra` prüfen); der Bedarf an `depends_on` mit
`condition: service_healthy`; ein Scanner, der das Image nicht mehr lesen
kann; das Ende der Pflege der chiseled Images durch den Herausgeber.
