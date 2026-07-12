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
