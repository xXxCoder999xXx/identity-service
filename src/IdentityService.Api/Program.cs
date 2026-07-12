// Composition Root: der einzige Ort, an dem alle Schichten zusammengesteckt
// werden. Fachlogik hat hier nichts zu suchen - nur Verdrahtung und HTTP.

var builder = WebApplication.CreateBuilder(args);

// Health Checks mit ASP.NET-Core-Bordmitteln - null zusätzliche Abhängigkeit.
// Erweiterungspunkt nach dem Open/Closed-Prinzip: künftige Checks (z. B. für
// die Datenbank) werden hier zusätzlich REGISTRIERT; bestehender Code bleibt
// unverändert.
builder.Services.AddHealthChecks();

var app = builder.Build();

// Antwortet bewusst nur mit dem Status ("Healthy"), niemals mit Systemdetails
// wie Versionen oder Verbindungszielen - Health-Endpunkte sind sonst ein
// klassischer Kanal für Information Disclosure (Sicherheitsregel 6.1.1).
app.MapHealthChecks("/health");

app.Run();
