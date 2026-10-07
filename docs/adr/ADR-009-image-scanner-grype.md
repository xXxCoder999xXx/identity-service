# ADR-009: Image-Schwachstellen-Scanner Grype als per Digest gepinntes Container-Image

- **Status:** Akzeptiert
- **Datum:** 2026-10-07

## Kontext

Seit Schritt 4b baut die Pipeline das Container-Image und prüft den Stack mit
einem Smoke-Test. Ob die Systempakete im Image bekannte Schwachstellen
enthalten, prüft bisher nichts. Am 06.10.2026 waren alle drei Image-Pins
veraltet, ohne dass es jemand bemerkt hatte; das Runtime-Image vom August
enthielt eine als „High" eingestufte Lücke in OpenSSL (CVE-2026-84782).

Kräfte:

- **Lieferkette (6.2a):** Ein Scanner ist eine neue Abhängigkeit, die in der
  Pipeline läuft und bei jedem Lauf Daten vom Herausgeber nachlädt. Im März
  2026 wurde mit Trivy genau ein solches Werkzeug kompromittiert; die
  Versions-Tags der zugehörigen Action zeigten danach auf Schadcode.
- **Keine langlebigen Secrets (6.2b):** Der Scanner darf kein Zugangsgeheimnis
  in der CI verlangen.
- **Fail closed (6.1.3):** Ein Scanner, der nicht suchen kann, muss rot melden.
- **Chiseled Runtime-Image:** Es hat keinen Paketmanager und legt seine
  Paketliste anders ab als ein übliches Ubuntu-Image. Zu beiden näher
  betrachteten Scannern gab es Berichte, dass sie solche Images nicht lesen.
- **Minimale Abhängigkeiten:** kein zusätzliches Werkzeug ohne Nachweis, dass
  es den Zweck erfüllt.

## Entscheidung

Wir verwenden Grype (Anchore) als Image-Schwachstellen-Scanner, eingebunden als
per Digest gepinntes Container-Image und nicht als GitHub Action; der Build
bricht ab, wenn ein Fund der Stufe „High" oder höher einen verfügbaren Fix hat,
und ein zeitgesteuerter Lauf scannt zusätzlich wöchentlich den Stand von
`main`.

## Betrachtete Alternativen

- **Trivy (Aqua Security):** technisch gleichwertig – in der Messung bestand es
  dieselben fünf Prüfpunkte und war deutlich schneller (erster Lauf 31 s statt
  338 s, weitere Läufe 3–9 s statt 40 s). Verworfen wegen des Vorfalls vom März
  2026: Der Angriff lief über gestohlene Zugangsdaten des Herausgebers und
  betraf Releases, Images und die Tags der Action. Die Datenbanken sind laut
  Projekt wiederhergestellt. Trivy bleibt die Rückfalloption.
- **Docker Scout:** verworfen, weil es eine Docker-Hub-Anmeldung verlangt, also
  ein langlebiges Zugangsgeheimnis in der CI; außerdem proprietär.
- **Einbindung als GitHub Action (`anchore/scan-action`):** verworfen. Ein
  Action-SHA pinnt nur den Wrapper, nicht das Werkzeug, das die Action zur
  Laufzeit nachlädt. Der Trivy-Vorfall hat diese Schwäche praktisch gezeigt.
- **Kein Scanner, nur Dependabot und Digest-Pins:** verworfen. Dependabot
  meldet neue Versionen, nicht bekannte Lücken im gepinnten Stand, und die
  Wartezeit vor Vorschlägen greift bei Images nach heutigem Stand nicht.

## Begründung

Die Wahl beruht auf einer Messung vom 07.10.2026, nicht auf Dokumentation.
Beide Kandidaten liefen als gehärtete Container (ohne Zugriff auf Docker, mit
schreibgeschütztem Dateisystem und ohne Capabilities) gegen exportierte
Image-Dateien: das Anwendungs-Image, das Runtime-Image vom August und das
aktuelle Runtime-Image.

| Prüfpunkt | Grype v0.120.1 | Trivy 0.75.0 |
|---|---|---|
| Betriebssystem erkannt | Ubuntu 24.04 | Ubuntu 24.04 |
| Systempakete erkannt | 9 | 8 |
| .NET-Runtime erkannt | ja (10.0.12) | ja (10.0.12) |
| Funde im August-Image | 35, davon 2 High, 28 mit Fix | 30, davon 2 High, 28 mit Fix |
| Funde im aktuellen Image | 7, keiner mit Fix | 2, keiner mit Fix |
| Ohne Netz und ohne Datenbank | Abbruch mit Fehler | Abbruch mit Fehler |
| Abbruch ab High: August-Image | rot | rot |
| Abbruch ab High: aktuelles Image | grün | grün |

Damit ist belegt: Grype liest das chiseled Image in dieser Version, findet eine
bekannte Lücke im alten Stand, meldet sie im aktuellen Stand nicht mehr und
bricht ohne Datenbank mit Fehler ab. Der ältere Bericht, Grype erkenne
chiseled Images nicht, hat sich für dieses Image nicht bestätigt.

Bei technischem Gleichstand entscheidet das Vertrauen in die Lieferkette des
Herausgebers. Für Anchore wurde kein vergleichbarer Vorfall gefunden.

Aufnahme-Prüfung (6.2a, 6.3.2), Stand 07.10.2026, aus dem Primär-Repository
und den Registries gelesen:

- Projekt `anchore/grype`, Lizenz Apache-2.0, nicht archiviert, letzter Push am
  06.10.2026, Release `v0.120.1` vom 06.10.2026; vier Releases in sechs Wochen.
- Image `ghcr.io/anchore/grype:v0.120.1` mit dem Digest
  `sha256:e4a44ef45d285b829ce6efe2642980329661bd2d18eab5fc539138d4adaebbbe`;
  `anchore/grype:v0.120.1` bei Docker Hub trägt denselben Digest.
- Kein Zugangsgeheimnis nötig. Die Schwachstellen-Datenbank lädt Grype zur
  Laufzeit von `grype.anchore.io`.

Der Schwellenwert „High mit verfügbarem Fix" trennt in der Messung genau
richtig: Das August-Image wird rot, das aktuelle grün. Funde ohne Fix
blockieren nicht, weil sie im Basis-Image liegen und nicht behebbar sind; sie
werden weiter gemeldet.

## Konsequenzen

Positiv:

- Bekannte Lücken in den Systempaketen des Images werden bei jedem Lauf und
  zusätzlich wöchentlich geprüft; ein veralteter Pin fällt damit auch ohne
  Codeänderung auf.
- Kein neues Secret, keine neue Action.
- Der Scanner ist fail closed: ohne Datenbank oder ohne Netz wird der Lauf rot.

Negativ und neue Pflichten:

- **Bekannte Grenze:** Für die .NET-Runtime 10.0.11 im August-Image meldete
  keiner der beiden Scanner etwas, obwohl das September-Update acht CVEs für
  .NET 10 behob. Die Advisory-Datenbank von GitHub lieferte für die beiden
  Runtime-Pakete in dieser Version keinen Eintrag; ob die Lücke in den Daten
  oder in der Abfrage liegt, ist nicht geklärt. Den Patch-Stand der Runtime
  sichern weiterhin Dependabot, der Digest-Pin und die Release Notes.
- **Laufzeit:** Der Datenbank-Download hat lokal gut fünf Minuten gedauert. Ein
  Cache ist ausgeschlossen (6.2b); die Dauer in der CI ist noch nicht gemessen.
- **Externe Abhängigkeit zur Laufzeit:** Ist `grype.anchore.io` nicht
  erreichbar, wird der Lauf rot, ohne dass sich im Repository etwas geändert
  hat. Das ist gewollt, kann aber Merges vorübergehend blockieren.
- **Pin-Pflege:** Dependabot sieht keine Image-Angaben in `run:`-Schritten. Die
  Einbindung muss so gestaltet werden, dass der Digest an einer Stelle steht,
  die Dependabot liest; sonst wird der Scanner-Pin von Hand gepflegt.
- **Das Scanner-Image läuft ohne festgelegten Nutzer**, also als root im
  Container. Es wird deshalb gehärtet gestartet (schreibgeschützt, ohne
  Capabilities, ohne Zugriff auf Docker) und bekommt das Image nur als Datei.
- **Ausnahmen** brauchen eine Liste mit Begründung und Ablaufdatum; sie wird
  erst angelegt, wenn der erste Fall eintritt.
- **Vor dem Scharfschalten** in der CI sind zwei Beweise zu wiederholen: Der
  Scan des aktuellen Images zeigt Pakete, und ein Scan des August-Images wird
  rot.

Auslöser für eine Neubewertung: ein Sicherheitsvorfall beim Herausgeber; ein
Scan ohne erkannte Pakete oder ohne erkanntes Betriebssystem; eine Laufzeit,
die die Arbeit spürbar behindert; der Bedarf, auch den Patch-Stand der
.NET-Runtime per Scanner abzudecken.
