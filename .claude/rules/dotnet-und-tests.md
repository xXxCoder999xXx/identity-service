---
paths:
  - "src/**"
  - "tests/**"
  - "**/*.{cs,csproj}"
---

# .NET-Code und Tests – Regeln für diese Pfade

Gilt zusätzlich zu `CLAUDE.md`.

## Schichten und Code

- Dependency Rule (maschinell geprüft): `Domain` referenziert keine andere Schicht und weder ASP.NET Core, EF Core noch `Microsoft.Extensions*`. `Application` referenziert nur `Domain` und definiert Ports als Interfaces. `Infrastructure` implementiert Ports. `Api` ist Composition Root und HTTP. Einen Schichtverstoß nie dadurch „lösen“, dass der Architekturtest angepasst wird.
- Erweiterung statt Modifikation: Erst fragen „Welcher Port, welche Registrierung, welcher Erweiterungspunkt?“, dann bestehenden Code anfassen. Keine Zusatzbibliothek für eine einzelne Funktion; Bibliotheken wie MediatR oder AutoMapper nur per ADR.
- Compiler-Härtung ist Repo-Regel (`TreatWarningsAsErrors`, Nullable, Analyzer, `EnforceCodeStyleInBuild`). Warnungen nie per `#pragma warning disable`, `NoWarn` oder `[SuppressMessage]` entfernen, ohne dass ich es freigebe; dann mit Begründungskommentar.
- `.csproj` enthält nur projektspezifische Eigenschaften: `TargetFramework`, `Nullable` und `ImplicitUsings` stehen zentral in `Directory.Build.props`. `PackageReference` ohne `Version` (Central Package Management).
- Kommentare und XML-Doku auf Deutsch. Sie erklären das **Warum** und nennen bei Sicherheitsbezug die Regel (Stil der bestehenden Dateien, z. B. „Sicherheitsregel 6.1.1“).
- Fehler: fail closed, keine Stacktraces oder Systeminterna an Clients. `/health` antwortet nur mit dem Status, nie mit Versionen oder Verbindungszielen. Logs strukturiert (kein `Console.WriteLine`); niemals Passwörter, Tokens, Secrets oder personenbezogene Daten.
- Konfiguration: Provider-Reihenfolge `appsettings.json` → `appsettings.{Environment}.json` → User Secrets (nur Development) → Umgebungsvariablen → Kommandozeile, der letzte gewinnt. Default-Environment ist Production. Keine Secrets in `appsettings*.json`; Komfortfunktionen nur an `IsDevelopment()` binden, nie an eigene Flags. Arrays werden index-weise verschmolzen: Allowlists immer vollständig von außen setzen.

## Tests

- xUnit v3 (ADR-002): Testprojekte mit `<OutputType>Exe</OutputType>` und `<IsPackable>false</IsPackable>`. Test-first: Tests vor oder parallel zum Feature.
- Ebenen: Unit (Domäne, keine externen Abhängigkeiten) · Integration (`WebApplicationFactory` plus Testcontainers gegen echte Infrastruktur statt In-Memory-Fakes; ab Phase 5) · Architektur (Reflection, Dependency Rule).
- Missbrauchsfälle aus dem Threat Modeling werden Testfälle; BOLA/BFLA und Fail-closed-Pfade explizit testen. Neue Test-Bibliotheken nur per ADR (minimale Abhängigkeiten).
