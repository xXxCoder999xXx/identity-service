# ADR-002: xUnit v3 als Test-Framework

- **Status:** Akzeptiert
- **Datum:** 2026-07-12

## Kontext

Das Walking Skeleton braucht ein erstes Testprojekt (Architekturtests). Die Wahl des
Test-Frameworks prägt alle künftigen Testebenen (Unit, Integration mit Testcontainers,
Architektur). Kriterien: minimale Abhängigkeiten, Ökosystem-Reife für
ASP.NET-Core-Integrationstests, sauberes Isolationsmodell.

## Entscheidung

Wir verwenden **xUnit v3** (Pakete `xunit.v3`, `xunit.runner.visualstudio`,
`Microsoft.NET.Test.Sdk`).

## Betrachtete Alternativen

1. **NUnit** – bewährt und vollwertig; attributreicheres Modell, Testklassen-Instanz
   wird per Default über Tests hinweg geteilt (Zustandsrisiko).
2. **MSTest** – solide, Microsoft-eigen; kleineres Community-Ökosystem, historisch
   der Nachzügler bei modernen Features.

## Begründung

xUnit ist der De-facto-Standard der .NET-Community und wird vom ASP.NET-Core-Team
selbst eingesetzt; die Dokumentationslage für Testcontainers und
WebApplicationFactory-Integrationstests (Phase 5) ist die beste. Das Isolationsmodell -
jede Testmethode erhält eine frische Klasseninstanz - erzwingt unabhängige Tests by
design. v3 ist die aktuelle Generation (Testprojekte als eigenständige Executables,
verbesserte Parallelisierung).

## Konsequenzen

- Testprojekte setzen `<OutputType>Exe</OutputType>`.
- Alle drei Pakete wurden gemäß Regel 6.3.2 (Slopsquatting) vor der Aufnahme auf
  nuget.org verifiziert: exakte Schreibweise, Herausgeber, Downloadzahlen,
  Pflegezustand.
- Versionen werden ausschließlich zentral in `Directory.Packages.props` gepflegt
  (ADR-003).

## Nachtrag vom 17.10.2026

`xunit.v3` 3.2.2 lief auf der Microsoft Testing Platform (MTP) v1, die der
Herausgeber ab 4.0.0 nicht mehr unterstützt. Mit dem Update auf 4.0.2 wird die
Testplattform gewechselt (E-5-20). Der Text oberhalb bleibt als Stand der
Entscheidung vom 12.07.2026 unverändert.

- **Nur noch MTP v2:** Das Testprojekt ist selbst das Testprogramm. Der
  VSTest-Weg entfällt, und mit ihm die Pakete `xunit.runner.visualstudio` und
  `Microsoft.NET.Test.Sdk`. Übrig bleibt ein direktes Paket, `xunit.v3`.
  Transitiv fallen `Microsoft.TestPlatform.ObjectModel`,
  `Microsoft.TestPlatform.TestHost` und `Microsoft.CodeCoverage` weg. Neu kommt
  `System.Security.AccessControl` 6.0.1 hinzu (über
  `xunit.v3.runner.common`, Herausgeber Microsoft, keine Advisories am
  17.10.2026).
- **Modus von `dotnet test`:** Ab SDK 10 lässt sich MTP v2 nicht mehr im
  VSTest-Modus von `dotnet test` ausführen. `global.json` schaltet deshalb mit
  `"test": { "runner": "Microsoft.Testing.Platform" }` den MTP-Modus ein. Der
  Befehl der Urteils-Hierarchie, `dotnet test --configuration Release
  --no-build`, bleibt unverändert.
- **Fail closed:** MTP beendet einen Lauf ohne einen einzigen ausgeführten Test
  mit Exit-Code 8. Ein Testprojekt, das versehentlich nichts findet, wird damit
  rot statt grün. Lokal am 17.10.2026 mit einem Filter belegt, der keinen Test
  trifft.
- **Betrachtete Alternative:** die beiden VSTest-Pakete als Rückfallweg
  behalten. Verworfen, weil das zwei Testwege und zwei Pakete ohne Aufgabe in
  der CI bedeutet. Visual Studio 2026 nutzt für xUnit-v3-Projekte automatisch
  den MTP-Test-Explorer.
- **Bewusst nicht genutzt:** Das Define `XUNIT_GENERATED_DISABLE_WARNINGS`
  (ab 4.0.1) schaltet Warnungen im generierten Code pauschal ab. Schlägt dort
  ein Analyzer an, wird gezielt und begründet unterdrückt, nie pauschal.
