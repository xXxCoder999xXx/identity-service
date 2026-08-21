# syntax=docker/dockerfile:1

# ---- Build-Stage ----
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble@sha256:e1ffd2a92ae84c1291bc1b6887501f8af98e6331e7af6d4c8d37168c5e87a64c AS build
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
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled@sha256:0839314d08bb65da369135389a5d8291f75ace587fbb0488f469eb92c62eef68 AS final
WORKDIR /app
COPY --from=build /app/publish .
USER $APP_UID
EXPOSE 8443
ENTRYPOINT ["dotnet", "IdentityService.Api.dll"]
