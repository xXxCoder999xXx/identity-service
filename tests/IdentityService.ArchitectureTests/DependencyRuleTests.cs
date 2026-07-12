using System.Reflection;
using Xunit;

namespace IdentityService.ArchitectureTests;

/// <summary>
/// Erzwingt die Abhängigkeitsregel der Clean Architecture maschinell - mit
/// Bordmitteln (Reflection), ohne Zusatzbibliothek. Bekannte Grenze: Der
/// Compiler entfernt UNGENUTZTE Referenzen aus den Assembly-Metadaten; der
/// Test schlägt also erst an, sobald eine verbotene Referenz tatsächlich
/// verwendet wird - genau dann, wenn es zählt. Die vollwertige Bibliothek
/// (ArchUnitNET) wird in Phase 5 als ADR bewertet.
/// </summary>
public sealed class DependencyRuleTests
{
    [Fact]
    public void DomainReferencesNoOuterLayerAndNoFramework()
    {
        // Die innerste Schicht kennt niemanden: keine anderen Schichten,
        // kein ASP.NET Core, kein EF Core, keine Microsoft.Extensions-Pakete.
        AssertForbiddenReferences(
            typeof(Domain.AssemblyMarker).Assembly,
            "IdentityService.Application",
            "IdentityService.Infrastructure",
            "IdentityService.Api",
            "Microsoft.AspNetCore",
            "Microsoft.EntityFrameworkCore",
            "Microsoft.Extensions");
    }

    [Fact]
    public void ApplicationReferencesOnlyDomain()
    {
        // Anwendungsfälle und Ports dürfen weder Adapter (Infrastructure)
        // noch Transport (Api) noch konkrete Technologie kennen.
        AssertForbiddenReferences(
            typeof(Application.AssemblyMarker).Assembly,
            "IdentityService.Infrastructure",
            "IdentityService.Api",
            "Microsoft.AspNetCore",
            "Microsoft.EntityFrameworkCore");
    }

    private static void AssertForbiddenReferences(Assembly assembly, params string[] forbiddenPrefixes)
    {
        var referencedAssemblies = assembly
            .GetReferencedAssemblies()
            .Select(reference => reference.Name ?? string.Empty)
            .ToArray();

        foreach (var prefix in forbiddenPrefixes)
        {
            Assert.DoesNotContain(
                referencedAssemblies,
                name => name.StartsWith(prefix, StringComparison.Ordinal));
        }
    }
}
