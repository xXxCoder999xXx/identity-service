---
paths:
  - "**/Dockerfile*"
  - "**/.dockerignore"
  - "**/compose*.y*ml"
  - "**/nginx*.conf"
  - "scripts/New-LocalDevCertificates.ps1"
---

# Container, Compose und nginx – Regeln für diese Pfade

Gilt zusätzlich zu `CLAUDE.md`. Dockerfile, `compose.yaml` und `nginx.conf` sind Infrastruktur-Code: CODEOWNERS-pflichtig, Änderung nur per PR.

## Images

- Build: `mcr.microsoft.com/dotnet/sdk:10.0-noble`. Runtime: `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` (kein Shell, kein Paketmanager, Non-Root). Edge: `nginxinc/nginx-unprivileged` (Stable-Zweig 1.30.x). Alle per **Digest** gepinnt, der Tag steht als Kommentar daneben. Die `-extra`-Variante nur bei nachgewiesenem ICU-/tzdata-Bedarf.
- Der Digest wird zum Schreibzeitpunkt aus der Registry aufgelöst (`docker buildx imagetools inspect`), nie aus Doku, Blog oder Gedächtnis. Gepinnt wird der **oberste** Digest (Manifest-Liste/OCI-Index), nicht ein plattformspezifischer, sonst geht Multi-Arch verloren. Einträge `unknown/unknown` mit `vnd.docker.reference.type: attestation-manifest` sind Provenance-Verweise, keine Images.
- Vor dem Anheben eines Tags die Tag-Liste der Registry prüfen (die Doku hinkt hinterher). Quellen nur `mcr.microsoft.com` bzw. Docker Official Images/verifizierte Publisher: Ein Image ist eine Abhängigkeit.

## Dockerfile und .dockerignore

- Multi-Stage: Nur die letzte Stage wird zum Image. Governance- und Projektdateien (`Directory.*.props`, `nuget.config`, `global.json`, `*.csproj`, `packages.lock.json`) vor dem Quellcode kopieren (Layer-Cache). `dotnet restore --locked-mode` gegen `src/IdentityService.Api/IdentityService.Api.csproj` (nicht gegen die `.slnx`), danach `dotnet publish --no-restore`. Tests laufen nicht im Docker-Build; `IdentityService.ArchitectureTests` gehört nicht in den Build-Kontext.
- `USER $APP_UID` (numerisch: Kubernetes `runAsNonRoot` liest die Image-Metadaten, nicht `/etc/passwd`), `EXPOSE 8443`, `ENTRYPOINT` in Exec-Form. Keine Secrets oder Zertifikate per `COPY`, `ENV` oder `ARG`. Was in einem Layer liegt, bleibt dort: Löschen in einer späteren Schicht ändert nur die Ansicht.
- `.dockerignore` ist eine **Erlaubnisliste**: `*`, dann `!src/<Projekt>/**` für die vier ausgelieferten Projekte plus Root-Governance-Dateien, danach `bin/` und `obj/` wieder ausschließen (die letzte treffende Regel gewinnt; Rückeinschluss nur als `verzeichnis/**`). Eine vergessene Datei soll ein Buildfehler sein, kein stilles Leck. `.gitignore` schützt den Build-Kontext nicht.

## Compose

- Baseline auf **jedem** Service: `read_only: true` mit gezielten `tmpfs`-Ausnahmen (`uid`/`gid` passend zum Prozessnutzer – nginx-unprivileged `101`, .NET chiseled `1654` –, sonst sperrt `mode=0700` den Dienst aus), `security_opt: no-new-privileges:true`, `cap_drop: ALL`, Ressourcenlimits über `mem_limit` und `cpus` (**nicht** `deploy.resources`: ohne Swarm wirkungslos und ohne Warnung), `restart: unless-stopped`. Abweichungen nur additiv per begründetem PR.
- Nur `nginx` hat `ports:`, `api` nie. Netze: `edge` mit `internal: true` (nginx und api) und `public` nur für nginx (Port-Publishing funktioniert auf internen Netzen nicht). Ab Phase 5 additiv `data` (api und DB); nginx ist **nicht** Mitglied.
- Zertifikate und nginx-Konfiguration ausschließlich als `:ro`-Bind-Mounts. Konfiguration nur über Umgebungsvariablen und Mounts; `__` ist der Hierarchietrenner (`Kestrel__Certificates__Default__Path`). `depends_on` in Kurzform ordnet nur den Start und prüft keine Bereitschaft.
- Service-Namen ohne Unterstriche (kein gültiges DNS-Label, bricht je nach Bibliothek die TLS-Namensprüfung). Service-Name, Zertifikats-SAN und `proxy_ssl_name` ändern sich nur gemeinsam in einem PR.
- Verifizieren statt lesen: `docker compose config`, `docker stats` (Limits in der Spalte `MEM USAGE / LIMIT`), `https://localhost:8443/health` über die ganze Kette.

## nginx

- Validierung mit `nginx -t` gegen dasselbe gepinnte Image. Die Zertifikatspfade müssen existieren (Wegwerf-Zertifikate in der CI, keine Secrets im Repo).
- Angriffsfläche klein halten: Stable-Zweig, kein HTTP/3/QUIC, kein SSI, kein Slice, kein `proxy_http_version 2`; `server_tokens off`.
- TLS 1.2 und 1.3, ECDHE/AEAD-Suiten **inklusive ECDSA** (Schlüsseltyp des Zertifikatsskripts), Session-Tickets aus, OCSP-Stapling lokal aus. Catch-all-`default_server` mit `ssl_reject_handshake on`.
- Security-Header: jeder `add_header` mit `always` (sonst fehlt er bei 4xx/5xx). `add_header` in einem Kontext **ersetzt** geerbte Header lautlos: bündeln und per echtem Request prüfen. HSTS lokal kurz (`max-age=300`, Anheben erst mit dem ersten Staging-Deploy), nie `preload`; CSP restriktiv.
- Upstream: `proxy_ssl_verify on` mit `proxy_ssl_trusted_certificate`, `proxy_ssl_name` und kleiner Verify-Tiefe (verschlüsselt ist nicht authentifiziert). `resolver 127.0.0.11 valid=10s` und `proxy_pass` über eine **Variable**, sonst bindet nginx die DNS-Auflösung beim Start. `proxy_http_version 1.1` explizit.
- Weitergabe: `Host` aus `$host`, `X-Forwarded-For` aus `$remote_addr` (überschreiben, nicht anhängen), `X-Forwarded-Proto` aus `$scheme`. Die App akzeptiert nur von einer engen Allowlist mit begrenzter `ForwardLimit`; Listen werden **gesetzt, nie geleert** (leere `KnownProxies`/`KnownNetworks` bedeuten „alles akzeptieren“).
- Rate-Limit-Schlüssel `$binary_remote_addr` (nie ein fälschbarer Header), Antwort 429; `client_max_body_size 1m`; Timeouts gegen Slowloris; Log-Format ohne Query-Strings.

## Lokale Zertifikate

- Eigene CA über `scripts/New-LocalDevCertificates.ps1` (openssl, ECDSA P-256): CA 730 Tage, Leafs 90 Tage; die CA wird nur in `Cert:\CurrentUser\Root` eingetragen und nie still überschrieben. `certs/` ist nie versioniert und nie im Image; der CA-Schlüssel ist das sensibelste Artefakt dieses Setups.
