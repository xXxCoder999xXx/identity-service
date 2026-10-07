# Bewusst KEINE "# syntax="-Zeile: Sie liesse Docker vor jedem Build ein
# Hilfs-Image ueber einen beweglichen Tag ohne Digest nachladen. Dieses
# Dockerfile nutzt nur Anweisungen, die der eingebaute Uebersetzer kennt.
# Wird spaeter eine neuere Funktion gebraucht (z. B. Cache-Mounts): die Zeile
# mit einem per Digest gepinnten Image wieder einfuehren.

# ---- Build-Stage ----
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble@sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317 AS build
WORKDIR /src

# Governance- und Projektdateien zuerst: Layer-Cache bleibt gueltig,
# solange sich weder Paketversionen noch Projektreferenzen aendern.
COPY Directory.Build.props Directory.Packages.props nuget.config global.json .editorconfig ./
COPY src/IdentityService.Api/IdentityService.Api.csproj src/IdentityService.Api/packages.lock.json src/IdentityService.Api/
COPY src/IdentityService.Application/IdentityService.Application.csproj src/IdentityService.Application/packages.lock.json src/IdentityService.Application/
COPY src/IdentityService.Domain/IdentityService.Domain.csproj src/IdentityService.Domain/packages.lock.json src/IdentityService.Domain/
COPY src/IdentityService.Infrastructure/IdentityService.Infrastructure.csproj src/IdentityService.Infrastructure/packages.lock.json src/IdentityService.Infrastructure/

RUN dotnet restore src/IdentityService.Api/IdentityService.Api.csproj --locked-mode

# Erst jetzt der Quellcode - haeufigste Aenderung, kleinster Cache-Verlust
COPY src/IdentityService.Api/ src/IdentityService.Api/
COPY src/IdentityService.Application/ src/IdentityService.Application/
COPY src/IdentityService.Domain/ src/IdentityService.Domain/
COPY src/IdentityService.Infrastructure/ src/IdentityService.Infrastructure/

RUN dotnet publish src/IdentityService.Api/IdentityService.Api.csproj \
    --no-restore \
    -c Release \
    -o /app/publish

# ---- Runtime-Stage ----
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled@sha256:48e51f2f6798897be7ac4e775c049ed8fe60d3190f637e1f9c9dc7513efa659c AS final
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
EXPOSE 8443
ENTRYPOINT ["dotnet", "IdentityService.Api.dll"]
