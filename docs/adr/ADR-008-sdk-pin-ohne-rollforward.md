# ADR-008: Exakter SDK-Pin mit `rollForward: disable`

- **Status:** Vorgeschlagen
- **Datum:** 2026-10-18

## Kontext

`global.json` legt fest, mit welchem .NET-SDK das Repository gebaut wird. Mit
`rollForward: latestPatch` nimmt `dotnet` stattdessen den neuesten
installierten Patch derselben Familie. Zwei Rechner können so mit
unterschiedlichen SDKs bauen, ohne dass es jemand bemerkt: kein Fehler, nur
eine stille Abweichung.

Wichtig für das Verständnis: `global.json` **fordert** eine Version, sie
installiert und verteilt nichts. Das SDK kommt aus drei Quellen:

- **Lokal:** von Hand oder über Visual Studio bzw. Microsoft Update
- **CI:** `setup-dotnet` liest `global.json` und installiert genau diese
  Version
- **Container:** die Build-Stage im Dockerfile, per Digest gepinnt; sie kennt
  `global.json` nicht

Wirkende Kräfte:

- **Inhalt statt Zeiger (ADR-003):** Actions per SHA, NuGet per Lockfile,
  Images per Digest. `latestPatch` war die letzte bewusste Zeiger-Stelle.
- **Fail closed (6.1.3):** Eine Abweichung soll laut abbrechen, statt still
  durchzulaufen.
- **Lokal == CI:** Der Build auf dem Rechner der Projekt-Ownerin soll mit
  demselben SDK laufen wie in der CI.

Die Entscheidung fiel in Sitzung 4 als ADR-Kandidat und wurde im selben
Zeitraum umgesetzt (`chore(build): pin SDK exactly via rollForward disable`,
Merge in Sitzung 5 bestätigt). Dieses ADR hält sie mit den Erfahrungen bis zum
18.10.2026 fest. Die Nummer 008 war seit Sitzung 4 dafür vorgesehen.

## Entscheidung

Wir pinnen das SDK in `global.json` auf eine exakte Version mit
`rollForward: disable`.

Stand 18.10.2026: `"version": "10.0.402"`, `"rollForward": "disable"`.

Ein SDK-Update ist eine gekoppelte Änderung: `global.json` und der Digest der
Build-Stage im Dockerfile werden in **einem** PR angehoben.

## Betrachtete Alternativen

1. **`rollForward: latestPatch`** (Ausgangszustand): verworfen. Die
   Abweichung bliebe still. Als vertretbare Gegenposition festgehalten: Für
   ein Ein-Personen-Projekt ist `latestPatch` bequemer, weil ein lokales
   SDK-Update den Build nie bricht.
2. **Andere Werte wie `latestFeature` oder `latestMajor`:** nicht eigens
   geprüft. Sie erlauben noch größere Abweichungen als `latestPatch` und
   widersprechen damit derselben Begründung.

## Begründung

- Der Pin ersetzt eine Zusicherung („sollte passen“) durch eine Prüfung („ist
  es, oder Abbruch“). Das ist dasselbe Prinzip wie SHA, Lockfile-Hash, Digest
  und Signatur.
- CI und Container bauen ohnehin mit festen Versionen. Eine Abweichung kann
  nur lokal entstehen, und genau dort soll sie laut werden.
- Gemessen: Das Build-Image meldete bei der Einführung des Dockerfiles
  dieselbe Version wie `global.json` (Sitzung 6: `10.0.302`), die CI löste
  ebenfalls `10.0.302` auf (Sitzung 5).

## Konsequenzen

**Positiv**

- Lokal, CI und Container bauen nachweislich mit demselben SDK.
- Ein veraltetes oder fremdes SDK fällt sofort auf, nicht erst bei einem
  schwer erklärbaren Unterschied im Build.

**Negativ**

- Jede SDK-Abweichung bricht jeden `dotnet`-Befehl im Repository ab. Ein
  SDK-Update wird zum blockierenden PR.
- Visual Studio bzw. Microsoft Update ersetzt ein SDK innerhalb des
  Feature-Bands. Danach baut der alte Pin lokal nicht mehr. Das ist zweimal
  passiert:
  - Sitzung 8: Lokal waren nur `10.0.303` und `10.0.401` installiert, gepinnt
    war `10.0.400`; `dotnet` meldete „A compatible .NET SDK was not found“.
    Die CI war nicht betroffen. Behoben mit PR #40 (`10.0.401` samt
    Dockerfile-Digests).
  - Sitzung 13: dieselbe Wirkung nach einem Update durch Microsoft Update.

**Neue Pflichten**

- Reihenfolge beim Anheben: erst das SDK lokal installieren, dann den Pin
  anheben, sonst sperrt man sich selbst aus.
- Diagnose bei einem Abbruch: `dotnet --list-sdks` gegen `global.json`
  vergleichen.
- Nach jedem Patch Tuesday prüfen, ob die Pins veraltet sind. Bei einem
  Sicherheits-Release nicht auf Dependabot warten: Sein wöchentlicher Lauf
  kann vor dem Release liegen, und gekoppelte Pins hebt er getrennt an.

**Auslöser für eine Neubewertung**

- Ein lokaler Abbruch durch automatische SDK-Updates wird häufiger als die
  Patch-Zyklen und kostet spürbar Zeit.
- Ein Werkzeug installiert das gepinnte SDK lokal automatisch (dann entfällt
  der Hauptnachteil).
