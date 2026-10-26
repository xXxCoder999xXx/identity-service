# ADR-014: Gate für fremde Images und ACME-Client lego als eigenes Image

- **Status:** Vorgeschlagen
- **Datum:** 2026-10-26

## Kontext

Für TLS auf Staging (Roadmap DNS/TLS, E-5-22) braucht der Server einen
ACME-Client, der Zertifikate von Let's Encrypt über HTTP-01 holt und selbst
erneuert. Das ist eine neue Abhängigkeit (A03, 6.2a).

Wirkende Kräfte:

- **Kürzere Laufzeiten:** Let's Encrypt stellt ab 10.02.2027 nur noch
  64-Tage-Zertifikate aus, ab 16.02.2028 45 Tage. Erneuern von Hand oder zu
  einem fest eingestellten Tag scheidet aus; der Client soll ARI (ACME Renewal
  Information, RFC 9773) beherrschen.
- **Pins per Inhalt (6.2a):** Was auf dem Server läuft, ist per Digest gepinnt
  und wird über Dependabot als PR bewegt.
- **Least Privilege:** Kein Root auf dem Host; nur der Client sieht den
  Kontoschlüssel bei Let's Encrypt.
- **Fail closed:** Ein Prüfwerkzeug, das nicht suchen kann, darf nicht als
  Erfolg zählen (CLAUDE.md 7).

Beim Vergleich der Kandidaten zeigte sich eine Lücke, die über den ACME-Client
hinausgeht: Das Gate aus ADR-009 (kein Fund „High" oder höher mit verfügbarem
Fix) gilt nur für unser API-Image. Fremde Images, heute nginx, prüft niemand.
`nginx-unprivileged:1.30.5` hätte das Gate mit 13 Funden nicht bestanden und
läuft trotzdem im Stack.

## Entscheidung

Wir prüfen jedes Image, das auf Staging läuft, mit demselben Gate wie die API,
und wir betreiben den ACME-Client lego als eigenes, minimales Image, das die
lego-Programmdatei aus dem offiziellen Image auf eine distroless-Basis kopiert.

| Code | Inhalt |
|---|---|
| E-5-61 | Gate für alle Images auf Staging (siehe unten) |
| E-5-62 | ACME-Client lego, als Container mit Digest-Pin, nicht auf dem Host |
| E-5-63 | Eigenes Image: Programmdatei per `COPY --from` aus `goacme/lego` (per Digest gepinnt), Basis `gcr.io/distroless/static-debian13:nonroot` (per Digest gepinnt), fester Benutzer ohne Root |

**E-5-61 im Einzelnen:**

| Teil | Regel |
|---|---|
| Geltung | Jedes Image, das auf Staging läuft, eigenes wie fremdes, besteht das Gate aus ADR-009 |
| Ort | In der CI, im PR und im wöchentlichen Lauf. Der Server startet nur Digests, die dort bestanden haben; kein Scanner auf dem Server (die Datenbank allein hat rund 3,2 GB) |
| Scan-Profil | Je Image festgehalten: erwartetes Betriebssystem, Paket-Ökosysteme, bekannte blinde Flecken. Der Blindheits-Schutz prüft gegen dieses Profil |
| Blinde Flecken | Was der Scanner nicht sieht, deckt eine zweite Quelle ab: Patch-PRs von Dependabot und die Advisory-Seite des Herausgebers |
| Ausnahmen | Nur per ADR, mit Begründung und Ablaufdatum |

Entwurf des Images (die Umsetzung folgt in einem eigenen PR):

```
FROM goacme/lego:<tag>@sha256:…  AS lego        ← nur Quelle der Programmdatei
FROM gcr.io/distroless/static-debian13:nonroot@sha256:…
COPY --from=lego /lego /lego
USER <feste UID>
ENTRYPOINT ["/lego"]
```

Alpine, `git`, busybox und die Bibliotheken des Upstream-Images bleiben in der
Zwischenstufe und gelangen nicht ins fertige Image. Dependabot (Ökosystem
`docker`) pflegt beide `FROM`-Zeilen.

## Betrachtete Alternativen

**ACME-Client**

1. **nginx-Modul `ngx_http_acme_module`** (`nginx/nginx-acme`, Apache-2.0,
   seit 07/2025, v0.4.1, ARI ja): verworfen. Das Modul ist nicht in unserem
   Image; die Stable-Images von `nginx-unprivileged` enthalten nur xslt,
   geoip, image-filter und njs. Wir müssten ein eigenes nginx-Image mit einem
   in Rust gebauten Modul pflegen.
2. **certbot auf dem Host:** verworfen. Ubuntu liefert das Paket aus
   `universe` ohne Sicherheitsupdates (noble 2.9.0, resolute 4.0.0), beide
   ohne ARI (ab certbot 4.1.0). Der Snap ist aktuell, aktualisiert sich aber
   selbst und ungepinnt.
3. **acme.sh** (GPL-3.0, 3.1.6): verworfen. Übliche Installation per
   `curl | sh` (CLAUDE.md 6); ARI nur teilweise (PRs zum Teil offen); 2023
   eine RCE-Lücke über einen bösartigen ACME-Server (CVE-2023-38198).
4. **certbot als Container** (`certbot/certbot:v5.8.0`): technisch möglich,
   unterlegen in der Messung (siehe Begründung): doppelt so groß, Python- und
   Rust-Stack mit über 1000 Komponenten.
5. **DNS-01 statt HTTP-01:** verworfen. Der Server bräuchte einen API-Schlüssel
   für das DNS bei netcup, mit dem sich alle Einträge ändern lassen,
   einschließlich CAA.

**Form des lego-Images**

6. **Upstream-Image `goacme/lego` mit Ausnahme vom Gate:** verworfen. Bricht
   die eigene Regel; das Upstream-Image wird nur bei einem Release neu gebaut,
   dazwischen sammeln sich Funde im Basis-Image.
7. **Warten auf das nächste Release, dann Upstream-Image:** verworfen aus
   demselben Grund; der Befund im Basis-Image kehrt nach jedem Release wieder.
8. **lego aus dem Quellcode bauen:** verworfen. Bringt eine Go-Toolchain in
   die Lieferkette.

**Basis des eigenen Images**

9. **`scratch` plus CA-Datei aus der lego-Stufe:** verworfen. Die
   CA-Zertifikate wären nur so frisch wie das letzte lego-Release; Benutzer
   und Verzeichnisse wären Eigenbau.
10. **Chiseled-Image von Microsoft** (Herausgeber bereits im Einsatz):
    verworfen. Enthält glibc, OpenSSL und weitere Bibliotheken für .NET, die
    eine statische Go-Datei nicht braucht.

## Begründung

**Aufnahme-Prüfung (25. und 26.10.2026, gegen GitHub-API, Docker Hub und
Registry):**

| Gegenstand | Ergebnis |
|---|---|
| lego, Repository | `go-acme/lego`, Organisation, seit 2015, MIT, v5.5.2 vom 23.09.2026, ARI unterstützt |
| lego, Advisories | GHSA-qqx8-2xmm-jrv8 / CVE-2026-40611 (high, Path Traversal im Webroot-Provider für HTTP-01, behoben in 4.34.0); GHSA-q82r-2j7m-9rv4 / CVE-2025-54799 (low) |
| lego, Image | `goacme/lego`, seit 2019, rund 10 Mio. Pulls; Index-Digest `v5.5.2` = `sha256:1944e8c36055beec47c7de6f15202b41128be75eea0ffa257f0c14d93c5155fd`; Basis `alpine:3` plus `git`, `ca-certificates`, `tzdata`; nicht signiert |
| distroless, Repository | `GoogleContainerTools/distroless`, Organisation, aktiv (letzter Push 24.10.2026) |
| distroless, Image | `gcr.io/distroless/static-debian13:nonroot`, Index-Digest `sha256:18f4cc26c9ffa7f20a359298be7deadac5c607c8e03a02b8119f1a5fc2f82c99`; laut README rund 2 MiB, mit CA-Zertifikaten, tzdata und Benutzer `nonroot` |
| distroless, Signatur | cosign keyless; Aussteller `https://accounts.google.com`, Identität `keyless@distroless.iam.gserviceaccount.com` (laut README; nicht selbst geprüft, siehe Konsequenzen) |
| Slopsquatting | Alle Namen direkt im offiziellen Repository und in der Registry verifiziert (Organisation als Besitzer, Alter, Releases, Pulls); kein Doppelgänger |

**Messung mit Grype v0.120.1 (`compose.scan.yaml`):**

| Image | Basis | Größe | Benutzer | Funde gesamt (Critical/High) | High+ mit Fix |
|---|---|---|---|---|---|
| `certbot/certbot:v5.8.0` | Alpine 3.23.5 | 293 MB | root | 3 / 27 | 13 |
| `goacme/lego:v5.5.2` | Alpine 3.24.2 | 125 MB | root | 4 / 24 | 20 |
| `nginx-unprivileged:1.30.5` (im Einsatz) | Debian 13.7 | – | 101 | 18 / 101 | 13 |
| `nginx-unprivileged:1.30.6` | Debian 13.7 | – | 101 | 14 / 92 | **0** |

Der Blindheits-Schutz bestand bei allen vier Images: Grype erkannte
Betriebssystem und Ökosysteme (certbot: 36 apk, 36 PyPI, 1038 Rust-Crates;
lego: 30 apk, 203 Go-Module).

Bei lego stammen die behebbaren Funde aus zwei Quellen: dem Alpine-Basis-Image
(brotli, expat, pcre2, zlib) und der Programmdatei selbst (Go-stdlib 1.27.1,
`golang.org/x/net` 0.59.0). Das eigene Image beseitigt die erste Quelle. Die
zweite verschwindet erst mit einem lego-Release, das mit neuerem Go gebaut ist;
auf `main` von lego steht `x/net` bereits auf 0.61.0.

**Blinder Fleck bei nginx, gemessen:** Grype meldet für `nginx 1.30.5-1~trixie`
keinen der fünf CVEs, die 1.30.6 behebt (CVE-2026-15176, CVE-2026-93479,
CVE-2026-95101, CVE-2026-97629, CVE-2026-97205). Vermutete Ursache: Das Paket
stammt aus dem Repository von nginx.org, nicht von Debian, und taucht deshalb
in Debians Liste der Sicherheitslücken nicht auf. Der Scan allein schützt
nginx also nicht; deshalb das Scan-Profil mit blinden Flecken und die zweite
Quelle in E-5-61.

**Warum lego:** eine statische Programmdatei statt eines Python-Stacks, halb so
groß, weniger Ökosysteme in der Pflege, ARI. Gegen lego spricht die High-Lücke
von 2026 im Webroot-Provider, genau dem Pfad für HTTP-01. Sie ist behoben, und
das eigene Image ändert nichts daran, dass Updates von lego zügig übernommen
werden müssen.

**Warum ein eigenes Image:** Es ist die einzige Variante, die das Gate einhält,
statt es zu umgehen. Wir bestimmen selbst, wann neu gebaut wird, und das Image
folgt demselben Muster wie die API (Digest, Scan, Herkunftsnachweis nach
ADR-010).

## Konsequenzen

**Positiv**

- Ein Maßstab für alle Images auf Staging statt nur für das eigene.
- Das lego-Image enthält nur die Programmdatei, CA-Zertifikate, tzdata und
  einen Benutzer ohne Root; ohne Shell kann ein Angreifer nach einer Übernahme
  wenig nachladen.
- Lego-Updates kommen als Dependabot-PR und durchlaufen dieselben Gates.

**Negativ**

- Ein zweites eigenes Image in der Pipeline (Build, Scan, Veröffentlichung).
- Das Gate für das lego-Image wird erst grün, wenn lego mit neuerem Go
  veröffentlicht. Bis dahin kein Deploy des Clients.
- Neuer Herausgeber Google (distroless) in der Lieferkette.

**Pflichten und Folgeschritte**

- nginx auf 1.30.6 heben, bevor Port 443 geöffnet wird (Gate für den
  TLS-Schritt).
- `invoke-image-scan.sh` additiv um Scan-Profile erweitern; das Profil der API
  bleibt unverändert und muss weiter mit Exit 3 scheitern, wenn Grype blind
  ist (Rot-Beweis).
- CI-Job, der jedes Image aus `compose.yaml` und das lego-Image scannt;
  Aufnahme als Required Check ist eine eigene Entscheidung.
- Scan-Profil nginx: blinder Fleck „Paket von nginx.org“, zweite Quelle
  `nginx.org/en/security_advisories.html`.
- Folgeentscheidung: Signatur der distroless-Basis vor dem Build prüfen
  (cosign wäre ein neues Werkzeug, eigene Aufnahme-Prüfung).
- Wie lego und nginx Challenge-Dateien und Zertifikat teilen (Volumes, UID,
  Rechte) und wie rootless Docker Port 80 und 443 erreicht, wird beim
  TLS-Schritt entschieden.

**Neubewertung**

Auslöser: Die offiziellen nginx-Images enthalten `ngx_http_acme_module`
(dann entfällt ein Image); lego wird nicht mehr gepflegt oder veröffentlicht
über längere Zeit kein Release mit aktuellem Go; distroless ändert Herausgeber
oder Signatur.
