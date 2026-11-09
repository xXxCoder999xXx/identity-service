# ADR-016: Eigenes nginx-Image mit Debian-Updates

- **Status:** Vorgeschlagen
- **Datum:** 2026-11-09

## Kontext

nginx ist der einzige Einstieg in den Stack. Heute läuft dafür das fremde
Image `nginxinc/nginx-unprivileged:1.30.6`, per Digest gepinnt
(`sha256:ec0f7ecb1fbd84959ac114e65fb36074ffc97d4d51db0f18ee925162d889dcef`)
und über Dependabot (Ökosystem `docker-compose`) bewegt.

Auslöser: Der Job `Image-Scan Drittanbieter (nginx)` (ADR-014, E-5-61) ist
seit Ende Oktober 2026 auf jedem PR und auf `main` rot. Stand 09.11.2026
(Lauf `42649498309`, grype v0.121.2) lösen vier Funde das Gate aus („High“
oder höher mit verfügbarem Fix):

| Paket | CVE | Stufe | Fix in Debian |
|---|---|---|---|
| `libbrotli1` `1.1.0-2+b7` | CVE-2026-111497 | Critical, CISA KEV (Frist 10.11.2026) | `1.1.0-2+deb13u1` |
| `apt`, `libapt-pkg7.0` `3.0.3` | CVE-2026-109518 | High | `3.0.4` |
| `zlib1g` `1:1.3.dfsg+really1.3.1-1+b1` | CVE-2026-76844, CVE-2026-85091 | High | `1:1.3.dfsg+really1.3.1-1+deb13u1` |

Der Herausgeber hat seit dem 19.10.2026 nicht neu gebaut; `1.30` und `1.30.6`
zeigen am 09.11.2026 weiter denselben Digest (Docker Hub). Bericht 28 nannte
noch nur den Brotli-Fund; die übrigen kamen mit einer neueren
Schwachstellen-Datenbank hinzu, ohne dass sich das Image geändert hat.

Wirkende Kräfte:

- **Gate statt Ausnahme (E-5-61):** Jedes Image auf Staging besteht dasselbe
  Gate wie die API; Ausnahmen nur per ADR, mit Begründung und Ablaufdatum.
- **Zero Trust:** „Über nginx nicht erreichbar“ ist kein Freibrief. Wer Code
  im Container ausführt, erreicht jede Bibliothek im Image.
- **Dauerrot stumpft ab:** Ein Check, der immer rot ist, verdeckt den nächsten
  echten Fund, auch wenn er kein Required Check ist.
- **Eine Quelle der Wahrheit (CLAUDE.md 7):** Der nginx-Pin darf nach dem
  Umbau nur an einer Stelle stehen.
- **Dasselbe Image überall (CLAUDE.md 2):** CI, Staging und Production
  starten denselben Digest.

## Entscheidung

Wir bauen nginx als eigenes Image aus dem gepinnten `nginx-unprivileged`, in
das wir beim Bauen die Debian-Updates einspielen, und veröffentlichen es wie
API und lego signiert mit Herkunftsnachweis; eine befristete Ausnahme im Gate
als Brücke gibt es nicht.

| Code | Inhalt |
|---|---|
| E-5-125 | `docker/nginx/Dockerfile`: `FROM nginxinc/nginx-unprivileged:<tag>@sha256:…`, als root `apt-get update` und `apt-get upgrade -y`, Paketlisten löschen, zurück auf `USER 101`; `CMD` und `ENTRYPOINT` erbt das Image von der Basis |
| E-5-126 | Eine Quelle der Wahrheit: `compose.yaml` baut nginx aus `docker/nginx` statt einen fremden Digest zu starten; Dependabot pflegt den Pin im Dockerfile (neuer Eintrag `docker` für `/docker/nginx`). Die Regel „nur Stable-Zweig“ (ignore für minor/major) zieht mit um; der Eintrag `docker-compose` verliert seinen einzigen Inhalt. Alles in **einem** PR |
| E-5-127 | Eigener Workflow `publish-nginx.yml` nach dem Muster von `publish-lego.yml` (ein Workflow je Image, E-5-78): bauen, gehärteter Start mit `nginx -t` und Wegwerf-Zertifikaten, Scan mit Profil `nginx`, hochladen, Nachweise, Prüf-Gate mit Gegenprobe „falscher Workflow“. Paket `identity-service-nginx` privat, Lesezugriff für das Maschinenkonto |
| E-5-128 | Aktualität: Der Wochenlauf von `ci.yml` scannt für nginx den **veröffentlichten** Digest aus der Registry, nicht einen frischen Build. Neu gebaut wird nur per PR auf `main`; kein geplanter Neubau mit Schreibrechten |
| E-5-129 | Pakete entfernen, die nginx nicht braucht (z. B. `curl`, Bild- und Font-Bibliotheken, `libheif`), ist ein eigener, späterer Schritt mit eigener Messung |

## Betrachtete Alternativen

1. **Befristete Ausnahme im Gate als Brücke** (in der Sitzung zuerst
   empfohlen): verworfen. Für Brotli wäre sie belegt (siehe Begründung), für
   apt vertretbar, für zlib nicht: `libz.so.1` ist in das nginx-Programm
   gelinkt, und ob die beiden CVEs ohne `gzip`/`gunzip` erreichbar sind, ist
   nicht gemessen. Eine Ausnahme ohne diesen Beleg schwächt das Gate ab, um es
   grün zu bekommen. Eine Ausnahme nur für Brotli macht das Gate nicht grün.
2. **Abwarten auf einen Neubau des Herausgebers, Gate bleibt rot:** verworfen.
   Kein Termin absehbar; der KEV-Fund bleibt im Image; Dauerrot verdeckt neue
   Funde. Entspricht Alternative 7 in ADR-014.
3. **Flaches Image** (`FROM scratch`, komplettes Dateisystem nach dem Update
   kopieren): verworfen. Entfernt zwar die alten Paketdateien aus den unteren
   Schichten, verliert aber Benutzer, Umgebung, Ports und Startbefehl der
   Basis, die wir dann selbst nachbauen und pflegen müssten.
4. **Snapshot-Spiegel von Debian mit festem Datum** (reproduzierbares
   `apt-get upgrade`): verworfen. Das Datum müsste von Hand angehoben werden,
   Dependabot kennt es nicht. Reproduzierbarkeit des Bauens bringt uns wenig,
   weil der Digest des fertigen Images gepinnt und überall derselbe ist.
5. **Geplanter Neubau mit Veröffentlichung** (z. B. wöchentlich in
   `publish-nginx.yml`): verworfen. Bricht die Regel, dass nur ein Push auf
   `main` Schreibrechte auslöst (`.claude/rules/lieferkette-und-ci.md`), und
   bringt ungeprüfte Änderungen auf Staging. E-5-128 misst stattdessen und
   lässt den Neubau eine sichtbare, geprüfte Änderung bleiben.
6. **Anderes Basis-Image** (Alpine-Variante, anderer Herausgeber): nicht
   geprüft. Der zuletzt aktualisierte Tag von `nginx-unprivileged` (Docker
   Hub, sortiert nach Aktualisierung, 09.11.2026) stammt vom 19.10.2026, auch
   bei den Alpine-Varianten gab es seither keinen Neubau; ein neuer
   Herausgeber wäre eine neue Abhängigkeit mit eigener Aufnahme-Prüfung.

## Begründung

**Messung 1, Brotli im Image (Wegwerf-Container aus dem gepinnten Digest,
`--network none`, `--read-only`, `--cap-drop ALL`):**

| Frage | Ergebnis |
|---|---|
| Brotli in nginx eingebaut? | Nein, `nginx -V` ohne Treffer |
| `libbrotli` in `/usr/sbin/nginx` gelinkt? | Nein; gelinkt sind libcrypt, libpcre2, libssl, libcrypto, **libz**, libc, libzstd |
| Module, die Brotli laden würden | Nur `ngx_http_image_filter_module` (über libgd → libfreetype) |
| Woher kommt `libbrotli1`? | Abhängigkeit von `libcurl4t64`, `libfreetype6`, `libheif1` |
| Gegenprobe | `ldd` auf `libcurl.so.4` findet `libbrotlidec` und `libbrotlicommon` |

Unsere Konfiguration (`nginx.conf`, `nginx/snippets/`) enthält weder
`load_module` noch `image_filter` und ersetzt `/etc/nginx/nginx.conf`
schreibgeschützt.

**Messung 2, laufender Stack (lokal, `/proc/<pid>/maps`):** Master und 16
Worker haben je 8 Bibliotheken geladen, darunter `libssl` (Gegenprobe), aber
kein `brotli` und kein `image_filter`. `/health` über nginx: 200.

Folgerung: Der KEV-Fund ist über nginx nicht erreichbar, liegt aber im Image
(`curl`, `libcurl`). zlib dagegen ist im nginx-Prozess geladen.

**Messung 3, Updates verfügbar (Wegwerf-Container mit Netz, 09.11.2026):**
Das Basis-Image (Debian 13 „trixie“) hat die Quellen `trixie`,
`trixie-updates` und `trixie-security`, alle über
`debian-archive-keyring.pgp` signiert. `apt list --upgradable` bietet für alle
vier Gate-Pakete genau die Fix-Version an, die grype nennt, alle aus
`stable-security`. Zusätzlich aktualisiert würden `ca-certificates`,
`liblzma5`, `tzdata` und drei `libheif`-Pakete.

**Warum diese Option:** Sie behebt alle vier Funde auf einmal, ohne das Gate
abzuschwächen. Sie folgt dem bewährten Muster von lego (ADR-014): eigenes
Image, gepinnte Quelle, Scan, Herkunftsnachweis nach ADR-010, Prüf-Gate. Wir
bestimmen selbst, wann neu gebaut wird, statt auf den Herausgeber zu warten.

**Aufnahme-Prüfung:** Keine neue Abhängigkeit. Basis-Image, Herausgeber,
Scanner (ADR-009), Nachweis (ADR-010) und Prüfregeln
(`scripts/lib/attestation-rules.sh`) sind bereits im Einsatz. Die Pakete
kommen aus dem offiziellen Debian-Archiv, das die Basis bereits nutzt.

## Konsequenzen

**Positiv**

- Das Gate für nginx wird wieder ehrlich grün; ein neuer roter Lauf bedeutet
  wieder einen neuen Fund.
- Debian-Fixes landen ohne Warten auf den Herausgeber im Image.
- nginx bekommt Herkunftsnachweis und Stückliste wie API und lego; der Server
  kann alle drei Images nach denselben Regeln prüfen.
- Grundlage für E-5-129 (Angriffsfläche verkleinern).

**Negativ und Grenzen**

- **Nicht reproduzierbar:** Dasselbe Dockerfile ergibt später andere Pakete.
  Maßgeblich ist der veröffentlichte Digest; welche Pakete er enthält, steht
  in der signierten Stückliste.
- **Alte Dateien in der unteren Schicht:** Die verwundbaren Paketdateien der
  Basis bleiben im Basis-Layer, nur verdeckt. Zur Laufzeit und für grype gilt
  die zusammengesetzte Ansicht. Wer die Schichten einzeln auswertet, sieht sie
  weiter (Alternative 3).
- **`http` beim Bauen:** Die Debian-Quellen nutzen `http`. Echtheit sichert
  die Signatur von `InRelease`; Vertraulichkeit (welche Pakete geladen werden)
  nicht. Beim Bauen auf dem Runner hingenommen.
- **Stilles Veralten:** Debian-Fixes kommen ohne neuen Basis-Digest, also ohne
  Dependabot-PR. Ohne E-5-128 wäre die CI grün (frischer Build), während
  Staging ein veraltetes Image hat.
- Ein drittes eigenes Image in der Pipeline; ein weiteres Paket in der
  Registry, dessen Sichtbarkeit und Rechte gepflegt werden müssen.
- Das Image wird größer als die Basis (zusätzliche Schicht mit den Updates).

**Pflichten und Folgeschritte**

- PR für E-5-125 und E-5-126 atomar: Dockerfile, `.dockerignore` daneben,
  `compose.yaml`, Bereitstellung im Job `Image-Scan Drittanbieter` und
  `Container & nginx` in `ci.yml`, `dependabot.yml`. Danach prüfen, dass der
  nginx-Pin nur noch im Dockerfile steht und die Stable-Regel greift.
- Wegen des `paths`-Filters in `publish-nginx.yml` nach dem Merge den ersten
  Lauf ablesen; Gegenprobe des Prüf-Gates muss „falscher Workflow“ mit
  `publish.yml` bestehen.
- Paket `identity-service-nginx` auf privat prüfen und für das Maschinenkonto
  freigeben (Einstellung der Ownerin, Vorfall 1 aus Sitzung 27).
- Das Deploy-Skript (Roadmap PR 4, E-5-111) rollt mehrere eigene Digests aus;
  die Digest-Datei und die Prüfungen sind darauf auszulegen.
- `.claude/rules/container-und-nginx.md` nennt als Edge-Image noch
  `nginxinc/nginx-unprivileged`; Anpassung durch die Ownerin.
- Scan-Profil `nginx` bleibt unverändert, ebenso sein blinder Fleck „Paket
  von nginx.org“ mit der zweiten Quelle `nginx.org/en/security_advisories.html`.

**Neubewertung**

Auslöser: Der Herausgeber baut wieder regelmäßig mit aktuellen Debian-Paketen
und das Upstream-Image besteht das Gate dauerhaft (dann prüfen, ob das eigene
Image noch nötig ist); E-5-129 entfernt so viel, dass ein anderes Basis-Image
näherliegt; Debian stellt die Quellen auf `https` um oder ändert den
Archivschlüssel.
