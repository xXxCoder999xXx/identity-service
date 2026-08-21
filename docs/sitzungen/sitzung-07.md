# Sitzungsbericht Sitzung 7

**Datum:** 21.08.2026
**Phase:** Schritt 4b (Container-Einheit), Teile 1-3 abgeschlossen, Teil 4 offen
**Vorgaenger:** sitzung-06.md (abgeschlossen 08.08.2026)

---

## 1. Erledigt

### 1.1 Vorlauf: SDK-Aktualisierung (nicht geplant, sicherheitsgetrieben)

Die Pflichtrecherche nach Abschnitt 6.0 ergab den .NET-Patch vom 11.08.2026 mit
zehn CVEs, darunter **zwei Remote Code Execution** (CVE-2026-70354,
CVE-2026-62897), drei Information Disclosure, ein Security Feature Bypass, ein
Denial of Service und drei Elevation of Privilege. Keine der beiden RCEs ist
laut Recherche aktiv ausgenutzt.

Ursprünglich war ein Patch-Bump innerhalb des 3xx-Bandes vorgesehen
(10.0.302 -> 10.0.303), begründet mit dem bewährten Band ohne zusätzliche
Visual-Studio-Abhängigkeit. Die Abfrage der Live-Tag-Liste bei MCR
(`mcr.microsoft.com/v2/dotnet/sdk/tags/list`) zeigte jedoch: Für 10.0.303
existiert **kein Container-Image**. Die 3xx-Reihe endet dort bei 10.0.302, also
auf dem Juli-Sicherheitsstand ohne die zehn Fixes.

Damit wurde der Wechsel auf das Feature-Band **10.0.400** zur einzigen
tragfähigen Option - nicht zur Komfortentscheidung. Der Bandwechsel war dadurch
zusätzlich risikoarm, weil ein vorangegangenes Visual-Studio-Update den
Entwicklungsrechner ohnehin schon auf 10.0.400 gehoben hatte.

Umgesetzt per PR #31. Host und Container laufen jetzt deckungsgleich auf
10.0.400.

**Nebenbefund:** Die offizielle `dotnet-docker`-Dokumentation auf GitHub nannte
zu diesem Zeitpunkt noch `10.0.301-noble` als aktuellen Tag - sie hinkte der
Registry hinterher. Lehre: Für Digests und Tags gilt die Registry als Quelle,
nicht die Dokumentation.

### 1.2 Teil 1: Dockerfile und .dockerignore

Comprehension Gate mit fünf Fragen bestanden (gitignore vs. dockerignore,
Layer-Persistenz beim Löschen, Erlaubnisliste vs. Sperrliste, RCE-Nutzlast im
SDK- vs. chiseled-Image, Restore-Layering).

Erstellt:

- **Dockerfile** (Repository-Wurzel): Multi-Stage-Build. Build-Stage
  `mcr.microsoft.com/dotnet/sdk:10.0-noble`, Runtime-Stage
  `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`, beide per Digest
  gepinnt. Governance- und Projektdateien werden vor dem Quellcode kopiert
  (Layer-Cache), `dotnet restore --locked-mode` mit Ziel
  `src/IdentityService.Api/IdentityService.Api.csproj` (nicht die `.slnx`),
  `dotnet publish --no-restore`, `USER $APP_UID`, `EXPOSE 8443`,
  `ENTRYPOINT ["dotnet", "IdentityService.Api.dll"]`.

- **.dockerignore** (Repository-Wurzel): Erlaubnisliste. `*` schliesst alles
  aus, danach gezielte `!`-Rückeinschlüsse für die vier ausgelieferten
  Projekte unter `src/` und die Root-Governance-Dateien, danach erneute
  Ausschlüsse für `bin/` und `obj/` (letzte treffende Regel gewinnt).

`IdentityService.ArchitectureTests` ist doppelt ausgeschlossen: kein
`!`-Eintrag in der `.dockerignore` und Restore-Ziel ist das Api-Projekt statt
der Solution.

### 1.3 Teil 2: compose.yaml

Zwei Services (`nginx`, `api`), zwei Netze (`edge` mit `internal: true`,
`public` ohne Optionen).

Härtungs-Baseline auf **beiden** Services identisch: `read_only: true` mit
gezielten tmpfs-Ausnahmen (jeweils mit passendem `uid`/`gid` und `mode=0700`),
`security_opt: no-new-privileges:true`, `cap_drop: ALL`, Ressourcenlimits,
`restart: unless-stopped`.

Zertifikate ausschliesslich per `:ro`-Bind-Mount, nirgends per `COPY` im Image.
`api` hat bewusst **keinen** `ports:`-Block - der einzige Weg dorthin führt
über nginx.

### 1.4 Teil 3: nginx.conf

TLS-Terminierung auf 8443, Catch-all-Server mit `ssl_reject_handshake on`,
Security-Header (HSTS, X-Content-Type-Options, X-Frame-Options,
Referrer-Policy, CSP) sämtlich mit `always`, Rate Limiting über
`$binary_remote_addr`, `client_max_body_size 1m`, Timeouts, eigenes Log-Format
ohne Query-Strings.

Zwei Punkte, die erst beim tatsächlichen Zusammenbau sichtbar wurden:

1. **DNS-Bindung:** Ohne Gegenmassnahme löst nginx den Upstream `api` einmalig
   beim Config-Laden auf und hält die IP fest. Nach einem Neustart des
   api-Containers zeigt nginx dann ins Leere. Gelöst durch
   `resolver 127.0.0.11 valid=10s` plus `proxy_pass` über eine Variable
   (`set $upstream_api https://api:8443;`) - nur über eine Variable wertet
   nginx den Resolver zur Laufzeit neu aus.

2. **Fehlende Verifikation:** `proxy_ssl_verify` ist bei nginx standardmässig
   **aus**. Die Verbindung nginx -> api wäre damit zwar verschlüsselt gewesen,
   hätte aber jedes beliebige Zertifikat akzeptiert. Gesetzt:
   `proxy_ssl_verify on`, `proxy_ssl_trusted_certificate` auf die lokale CA,
   `proxy_ssl_name api`. Erforderte einen zusätzlichen CA-Mount in
   `compose.yaml`.

### 1.5 Ende-zu-Ende verifiziert

`https://localhost:8443/health` liefert `Healthy` über die vollständige Kette
Browser -> nginx (TLS-Terminierung) -> Kestrel (Re-Encryption auf 8443).
Zertifikatskette mit `openssl verify` gegen die lokale CA geprüft, SAN-Einträge
passend zur nginx-Konfiguration.

---

## 2. Gelernt

- `.gitignore` schützt nicht den Docker-Build-Kontext; nur `.dockerignore` tut das
- Eine `.dockerignore` als Erlaubnisliste macht aus einer vergessenen Datei
  einen Buildfehler statt eines stillen Leaks
- Multi-Stage entfernt Build-Layer aus dem finalen Image; das Löschen einer
  Datei innerhalb derselben Stage tut das nicht
- `--locked-mode` verwandelt ein Reproduzierbarkeitsrisiko in einen harten
  Buildfehler (Fail-closed)
- Kubernetes prüft `runAsNonRoot` ausschliesslich anhand der Image-Metadaten und
  liest dafür nicht `/etc/passwd` - deshalb muss `USER` als UID gesetzt sein
- tmpfs-Mounts brauchen `uid`/`gid` passend zum Prozessnutzer im Image, sonst
  sperrt `mode=0700` den Dienst aus
- `deploy.resources` wird ohne Swarm **ignoriert, ohne Warnung** - die
  gefährlichste Form von "funktioniert nicht"
- Der doppelte Unterstrich in `Kestrel__Certificates__Default__Path` bildet
  JSON-Hierarchie flach für Umgebungsvariablen ab
- `depends_on` in Kurzform ordnet nur den Start, prüft keine Bereitschaft
- Rückeinschluss in `.dockerignore` braucht die Form `verzeichnis/**`

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-4b-1** | SDK-Feature-Band 3xx -> 4xx (10.0.400) | Kein 10.0.303-Image bei MCR; 10.0.302 hiesse Juli-Stand ohne zwei RCE-Fixes |
| **E-4b-2** | `.dockerignore` als Erlaubnisliste | Fail-closed: vergessene Datei erzeugt Fehler statt Leak |
| **E-4b-3** | Tests laufen nicht im Docker-Build | Kleinerer Build-Kontext, klarere Fehlerzuordnung, kürzere Builds |
| **E-4b-4** | `USER $APP_UID` explizit trotz Chiseled-Default | Kubernetes-Kompatibilität, auditierbar statt implizit |
| **E-4b-5** | `internal: true` auf `edge` + separates `public`-Netz für nginx | Port-Publishing funktioniert auf internen Netzen nicht - empirisch belegt |
| **E-4b-6** | `mem_limit`/`cpus` statt `deploy.resources` | Letzteres ist ohne Swarm wirkungslos und warnt nicht |
| **E-4b-7** | `proxy_ssl_verify on` + CA-Mount in nginx | Zero Trust: verschlüsselt genügt nicht, verifiziert ist nötig |
| **E-4b-8** | Servicename `nginx` statt `edge` | Kollision mit dem bereits entschiedenen Netznamen `edge` |
| **E-4b-9** | `restart: unless-stopped` auf beiden Services | Neustart bei Absturz, aber kein Wiederbeleben bewusst gestoppter Container |

---

## 4. Offene Punkte

- **4b Teil 4 nicht begonnen** - der gesamte CI-Block steht aus
- **4b noch nicht gemergt** - vier neue Dateien (`Dockerfile`, `.dockerignore`,
  `compose.yaml`, `nginx.conf`) liegen unversioniert im Arbeitsverzeichnis,
  `IdentityService.slnx` ist geändert (Solution Items)
- Ressourcenlimits sind geschätzt, nicht mit `docker stats` verifiziert
- Drei Commit-Titel auf `main` verletzen Conventional Commits (#21 `Doc/sitzung5`,
  #25 `docs:Sitzungsbericht...` ohne Leerzeichen, #31 `change-sdk-version`) -
  bewusst akzeptiert, Historie wird nicht umgeschrieben
- `Test-RepoState.ps1` liegt weiterhin ausserhalb des Repositories unter
  `C:\Projects\tools` - Entscheidung über Aufnahme unter `scripts/` offen
- Feature-Branch `chor/sdk-change-from-10.0.302-to-10.0.400` noch nicht gelöscht
  (lokal und remote)
- HSTS steht bewusst auf `max-age=300` (Entwicklungswert), Kommentar in
  `nginx.conf` gesetzt

---

## 5. Phasen-Status und Gates

Schritt 4b zu drei Vierteln abgeschlossen.

**Drei Auslöser aus Abschnitt 8 sind mit dieser Sitzung aktiv geworden:**

| Thema | Status |
|---|---|
| **Resilienz-Patterns** (Retry, Timeout, Circuit Breaker) | **Ausgelöst** - nginx und api kommunizieren jetzt |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher - derzeit nur einseitige Verifikation (nginx prüft api, nicht umgekehrt) |
| **DAST** (OWASP ZAP gegen Staging) | Rückt näher - Auslöser ist stabiles, automatisch deploytes Staging |

---

## 6. Technische Referenz (für Folgesitzungen)

**Gepinnte Digests (Stand 21.08.2026, aus der Registry verifiziert):**

```
mcr.microsoft.com/dotnet/sdk:10.0-noble
  sha256:e1ffd2a92ae84c1291bc1b6887501f8af98e6331e7af6d4c8d37168c5e87a64c

mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled
  sha256:0839314d08bb65da369135389a5d8291f75ace587fbb0488f469eb92c62eef68

nginxinc/nginx-unprivileged:1.30.4
  sha256:324ae106322ff873e4ef4d48bda2cfd13ba761eca60bceb8e44a67b135f3adc5
```

Gepinnt wird stets der **oberste** Digest (Manifest-Liste / OCI-Index), nicht
ein plattformspezifischer darunter - sonst geht Multi-Arch verloren.
Attestation-Manifeste (`Platform: unknown/unknown` mit
`vnd.docker.reference.type: attestation-manifest`) sind SLSA-Provenance-Verweise,
keine eigenen Images.

**UIDs:**

- nginx-unprivileged: `101`
- .NET chiseled runtime (`app`-User, via `$APP_UID`): `1654`

**Projektstruktur (relevant für COPY-Pfade):**

Die vier Projekte liegen unter `src/`, die Tests unter `tests/`:
`src/IdentityService.Api`, `src/IdentityService.Application`,
`src/IdentityService.Domain`, `src/IdentityService.Infrastructure`.

**Zertifikate (aus `New-LocalDevCertificates.ps1`):**

```
certs/ca/local-dev-ca.{key,crt,cnf}    Trust-Anchor, im Windows-Store importiert
certs/edge/edge.{key,crt,cnf}          fuer nginx  - SAN: localhost, edge, 127.0.0.1
certs/api/api.{key,crt,cnf}            fuer Kestrel - SAN: api, localhost
```

`certs/` ist nicht versioniert (eigene `.gitignore` als Erlaubnisliste).

**nginx-Fallstricke, die Zeit gekostet haben:**

- `read_only: true` erfordert tmpfs für `/tmp`, `/var/cache/nginx`, `/var/run`
  **mit** `uid=101,gid=101`
- Interne Netze (`internal: true`) verhindern Port-Publishing zum Host
- Docker-DNS liegt auf `127.0.0.11`

---

# Roadmap Sitzung 8

## 1. Schritt 4b Teil 4 - CI-Erweiterung (der nächste logische Schritt)

Warum genau dieser: Ein Dockerfile ohne CI-Build ist ungeprüfter Code im
Repository. Die Container-Einheit 4b ist erst vollständig, wenn die Pipeline
das Ergebnis auch validiert.

Vier Bausteine:

1. **Container-Build im Workflow** - das Image wird in der CI gebaut, nicht nur
   lokal
2. **`nginx -t` als Validierungsschritt** - Konfigurationsfehler brechen den
   Build, nicht erst den Start (Abschnitt 5.5: nginx-Konfiguration wird wie
   Code behandelt)
3. **Image-Schwachstellen-Scanner** - der eigentliche Diskussionspunkt dieser
   Sitzung
4. **`dependabot.yml`** additiv um das `docker`-Ökosystem erweitern (OCP:
   bestehende Einträge bleiben unangetastet)

**Der Scanner ist eine Abhängigkeitsentscheidung**, kein blosser Pipeline-Schritt.
Nach 6.2a und 6.3 Punkt 2 gilt: Vetting vor Aufnahme, Pinning auf Commit-SHA,
ADR. Zu bewerten sind mindestens Trivy, Grype und Docker Scout - Kriterien:
Pflegezustand, Datenbankaktualität, Offline-Fähigkeit, Lizenz, Umfang der
transitiven Last, Verhalten bei fehlender Netzverbindung.

## 2. Schritt 4b als Einheit nach `main`

Ein PR mit allen fünf Dateien (`Dockerfile`, `.dockerignore`, `compose.yaml`,
`nginx.conf`, `IdentityService.slnx`) plus den CI-Änderungen. Bündelung, weil
die Teile einzeln unvollständig sind.

Der PR wird CODEOWNERS-pflichtig sein - Dockerfile, Pipeline-Definition und
nginx-Konfiguration sind alle als sicherheitskritische Pfade eingetragen.

## 3. PR-Titel-Validierung als harter CI-Check

Nach drei dokumentierten Vorfällen (#21, #25, #31) überfällig. Gehört in
denselben CI-Block. Prüft den PR-Titel gegen dasselbe Muster wie Gruppe 5 in
`Test-RepoState.ps1`. Zweite Sicherung: Branch-Namen sauber halten, da GitHub
den PR-Titel oft daraus vorschlägt (Wurzel von #31 war der Tippfehler `chor/`
statt `chore/`).

## 4. Vor oder in der Sitzung zu verstehen (vor Code)

- Was ein Image-Scanner tatsächlich prüft: Er vergleicht Paketmetadaten der
  Image-Layer gegen CVE-Datenbanken. Er analysiert **keinen** Anwendungscode -
  das ist die Aufgabe von SAST/CodeQL, das bereits läuft.
- Warum ein Scan zur Build-Zeit allein unvollständig ist: Ein Image, das heute
  sauber gebaut wurde, kann morgen eine bekannte Schwachstelle enthalten, ohne
  dass sich eine Zeile geändert hat. Daraus folgt der Bedarf an regelmässigen
  Rebuilds und einem Scan zur Deploy-Zeit.
- Was ein Schweregrad-Schwellenwert bedeutet, wenn ein Fund den Build hart
  stoppt: Zu streng bedeutet blockierte Arbeit an nicht behebbaren Funden im
  Basis-Image; zu locker bedeutet einen Schalter, den niemand mehr beachtet.
  Zu klären: Was passiert bei einem Fund ohne verfügbaren Fix?

## 5. Optionale Vorbereitung

- `docker stats` bei laufendem Setup ansehen: Bestätigt, dass die
  Ressourcenlimits nach der Umstellung von `deploy.resources` auf
  `mem_limit`/`cpus` tatsächlich greifen (Spalte `MEM USAGE / LIMIT` muss
  `128MiB` bzw. `256MiB` zeigen), und liefert reale Werte statt Schätzungen.
- Feature-Branch `chor/sdk-change-...` löschen (lokal und remote).
- `Test-RepoState.ps1` erneut ausführen - erwartet werden die drei bekannten
  Commit-Titel-Befunde und `.dockerignore` nicht mehr als fehlend.
