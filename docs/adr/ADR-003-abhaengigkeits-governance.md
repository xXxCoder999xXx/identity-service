# ADR-003: Abhängigkeits-Governance ab der ersten Abhängigkeit (CPM, Lockfiles, Source Mapping)

- **Status:** Akzeptiert
- **Datum:** 2026-07-12

## Kontext

Mit dem Testprojekt entstehen die ersten NuGet-Abhängigkeiten. Die OWASP Top 10:2025
führt Software Supply Chain Failures neu auf Platz 3 (höchste Inzidenzrate aller
Kategorien). Lieferketten-Kontrollen sind am billigsten, bevor es Bestand gibt, den
man migrieren müsste. Der Phasenplan verankert sie in der Pipeline-Phase - die
projektseitigen Grundlagen müssen aber vor dem ersten Restore existieren.

## Entscheidung

Ab der ersten Abhängigkeit gelten drei Mechanismen:

1. **Central Package Management** (`Directory.Packages.props`): genau eine Stelle
   für alle Paketversionen der Solution.
2. **Lockfiles** (`RestorePackagesWithLockFile` in `Directory.Build.props`):
   `packages.lock.json` je Projekt wird versioniert; die CI restauriert im
   Locked Mode (`dotnet restore --locked-mode`, wird in der Pipeline-Sitzung
   verankert).
3. **Package Source Mapping** (`nuget.config`): nuget.org als einzige, explizit
   deklarierte Quelle; jedes Paketmuster ist fest einer Quelle zugeordnet.

## Betrachtete Alternativen

1. Versionen je `.csproj` - führt erfahrungsgemäß zu Versionsdrift zwischen Projekten.
2. Nur NuGetAudit ohne Lockfiles - erkennt bekannte CVEs, verhindert aber nicht,
   dass sich transitive Abhängigkeiten still auf neuere, ungeprüfte Versionen auflösen.
3. Aufschub bis zur Pipeline-Phase - Nachrüsten wäre teurer und lückenhaft
   (bestehende Restores wären nie im Locked Mode gelaufen).

## Begründung

Zusammen schließen die drei Mechanismen drei Angriffs- bzw. Fehlerklassen:
Versionsdrift (CPM), stille Auflösung neuer Versionen inklusive manipulierte
Re-Releases (Lockfiles mit Hashes) und Dependency Confusion (Source Mapping).
Kombiniert mit dem bereits aktiven NuGetAudit (Directory.Build.props) bricht
jede bekannte CVE den Build.

## Konsequenzen

- `packages.lock.json`-Dateien werden committet - sie sind Teil der geprüften Wahrheit.
- Jedes neue Paket bedeutet: Aufnahme-Prüfung (Pflegezustand, transitive Last,
  schlankere Alternative?), Slopsquatting-Verifikation (6.3.2), Eintrag in
  `Directory.Packages.props`.
- Die CI erhält in der Pipeline-Sitzung verbindlich `--locked-mode` beim Restore.
