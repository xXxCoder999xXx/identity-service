# Bewusst KEINE "# syntax="-Zeile: Sie liesse Docker vor jedem Build ein
# Hilfs-Image ueber einen beweglichen Tag ohne Digest nachladen. Dieses
# Dockerfile nutzt nur Anweisungen, die der eingebaute Uebersetzer kennt.
# Wird spaeter eine neuere Funktion gebraucht (z. B. Cache-Mounts): die Zeile
# mit einem per Digest gepinnten Image wieder einfuehren.

# ---- Build-Stage ----
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble@sha256:de4fe90a98845d75910b9769662465c84de1a934665c431279d1382b2bddc02b AS build
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
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled@sha256:c89a6a61f494f20a5ae302990e814627a8d91b332fd4a8e7c1707c2d4da9555d AS final
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
EXPOSE 8443
ENTRYPOINT ["dotnet", "IdentityService.Api.dll"]
