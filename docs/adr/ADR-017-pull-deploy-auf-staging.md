# ADR-017: Pull-Deploy auf Staging

- **Status:** Vorgeschlagen
- **Datum:** 2026-11-23

## Kontext

ADR-011 legt fest, dass der Staging-Server per Pull deployt und nur startet,
was die Prüfung besteht. ADR-012 wählt rootless Docker, ADR-013 den
Totmannschalter, ADR-015 `gh attestation verify` als Prüfer und das
Maschinenkonto für GHCR, ADR-016 das eigene nginx-Image. Offen ist der Ablauf
selbst: Woher weiß der Server, **welche** Digests freigegeben sind, wie kommt
die Konfiguration auf den Server, und wie laufen Deploy und API-Neustart als
Units?

Auslöser: Der Pull-Deploy ist fristgebunden. Ohne ihn gibt es keinen
API-Neustart nach der Zertifikatserneuerung (`restart_api` ist ein
Platzhalter); die erste Erneuerung steht spätestens am 27.12.2026 an.

Wirkende Kräfte:

- **Herkunft ist nicht Aktualität:** Ein Herkunftsnachweis beweist „von uns
  gebaut“, nicht „aktuell freigegeben“. Ein älteres, gültig signiertes Image
  darf nicht wieder ausgerollt werden (Downgrade).
- **Freigabe als Commit:** Der Merge eines PR auf `main` ist die Freigabe
  (Schritt 6) und das DORA-Ereignis.
- **Minimale Abhängigkeiten (A03):** Jedes Paket auf dem Server ist
  Angriffsfläche. Gemessen fehlen dort `git`, `jq` und `gpg` (Sitzung 30).
- **Eine Quelle der Wahrheit:** Die Prüfregeln stehen in
  `scripts/lib/attestation-rules.sh` mit zwei Einstiegen (CI und Server) und
  sind am Server rot/grün belegt (Sitzung 30).
- **Least Privilege und fail closed:** Der Deploy-Benutzer darf weder seine
  Prüfer noch seine Freigabe-Regeln ändern; jeder Fehler bricht ab.
- **Netzziele:** Der Prüfer braucht gemessen genau vier Hosts (`ghcr.io`,
  `pkg-containers.githubusercontent.com`, `tuf-repo.github.com`,
  `tuf-repo-cdn.sigstore.dev`), keinen Zugriff auf die GitHub-API.

Recherche vom 23.11.2026 (Debian Security Tracker, CISA KEV vom 20.11.2026,
Herausgeber-Meldungen):

| Paket (trixie) | Version | Befund |
|---|---|---|
| `git` | 2.47.3-0+deb13u1 | sechs Lücken aus dem Git-Release vom 10.11.2026 (u. a. CVE-2026-111760, CVE-2026-113408, CVE-2026-105437) in trixie ungepatcht; CVE-2025-48384 steht im KEV, ist in trixie behoben |
| `gnupg2` | 2.4.7-21+deb13u1 | vier Lücken ohne Debian-Sicherheitsupdate, darunter CVE-2025-68972 (Parsen signierter Nachrichten) |
| `jq` | 1.7.1-6+deb13u4 | keine wichtige offene Lücke |

Messungen am Server vom 23.11.2026 (Deploy-Benutzer, rootless Docker,
temporärer `DOCKER_CONFIG`, Platzhalter in `GH_TOKEN`, Telemetrie aus):

- `gh attestation verify oci://…:<tag> --bundle-from-oci` löst den Tag selbst
  über die Registry auf und nennt den geprüften Digest als `subject` im JSON.
  Gegenprobe: `63a1ae6e…d6a8`, das API-Image von `768bbb4`.
- Das JSON enthält `signature.certificate.runInvocationURI` mit
  `…/actions/runs/<run-id>/attempts/<n>`. Gegenprobe: Run `45177231370` ist
  der `Publish`-Lauf nach #158.
- Mit abgeschalteter Telemetrie legte `gh` keine `device-id` an (ein Lauf,
  keine gezielte Gegenprobe).

## Entscheidung

Wir geben einen Staging-Deploy per PR auf eine Freigabedatei frei, liefern
Digests und Konfiguration als signiertes Freigabe-Image über GHCR aus und
lassen den Server diesen Freigabe-Nachweis mit dem vorhandenen `gh` prüfen,
ohne `git`, `gpg` oder `jq`.

Teilentscheidungen:

| Code | Inhalt |
|---|---|
| E-5-111 | Die Freigabe ist eine Datei im Repository, geändert per PR auf `main`. **Angepasst durch E-5-144/E-5-145:** Transport über das Freigabe-Image statt `git pull` |
| E-5-112 | Deploy als System-Unit in `/etc/systemd/system` mit `User=deploy`; Token per `LoadCredential`; Unit und Skript root-eigen; zu Beginn `docker info` (rootless, fail closed). `restart_api` startet nicht die Deploy-Unit |
| E-5-113 | Ablauf in Schritten, alles vor dem Punkt ohne Wiederkehr ändert nichts. **Angepasst:** neuer Ablauf unten ersetzt die Schritte 1 und 2 (`git fetch`, Web-Flow-Signatur, `merge-base`) |
| E-5-114 | Gegenprobe bei jedem Deploy, sie muss am erwarteten Grund scheitern |
| E-5-115 | Paket anonym lesbar → Abbruch und Alarm; gilt für alle vier Pakete |
| E-5-116 | Prüfregeln in einer Bibliothek mit zwei Einstiegen |
| E-5-117 | Prüfer root-eigen unter `/usr/local/lib/identity-service/`, nie aus dem Release-Ordner |
| E-5-118 | Sandbox der Deploy-Unit (leeres `CapabilityBoundingSet`, `NoNewPrivileges`, `ProtectSystem=strict`, `StateDirectory`, `RuntimeDirectory` 0700, `ProtectHome=tmpfs` plus Socket-`BindPaths`, `RestrictAddressFamilies`, `SystemCallFilter=@system-service`, `PrivateTmp`, `PrivateDevices`, `ProtectKernel*`, `UMask=0077`); Timeouts je Netzaufruf |
| E-5-119 | Kestrel lädt ein getauschtes Zertifikat nicht selbst neu (lokal gemessen) |
| E-5-120 | Eigene Restart-Unit `identity-service-api-restart.service` (`User=deploy`); `restart_api` ruft `systemctl start` auf, Fehler als Exit-Code an `/fail` |
| E-5-134 | TUF-Zwischenspeicher dauerhaft: `CacheDirectory=identity-service-deploy`, `XDG_CACHE_HOME` dorthin; Home bleibt `tmpfs` |
| E-5-135 | Netzziele: IP-Allowlist nicht möglich (CDN); Wahl zwischen nur `RestrictAddressFamilies`, Egress-Proxy oder DNS-befüllten nftables-Sets fällt mit den Units |
| E-5-136 | `gh` erhält einen festen Platzhalter in `GH_TOKEN`; das echte Token nur im temporären `DOCKER_CONFIG` |
| E-5-137 | Server-Einstieg mit fester Zuordnung Paket → Workflow → Gegenprobe-Workflow als Konstante |
| E-5-138 | Der Server verifiziert auch die Stückliste |
| E-5-139 | Der Einstieg setzt Platzhalter, `GH_TELEMETRY=false`, `DO_NOT_TRACK=true` selbst |
| E-5-140 | Mindestversion `gh` 2.103.3 |
| E-5-141 | Server-Einstieg läuft in jedem `publish*.yml` nach dem Prüf-Gate |
| E-5-142 | Paketfrage `git`, `jq`, `gpg`: **gelöst durch E-5-143/E-5-144, kein neues Paket** |
| E-5-143 | `jq` wird nicht installiert; JSON nur über `gh --jq` |
| E-5-144 | Freigabe-Nachweis per Sigstore (`actions/attest`, eigener Predicate-Typ) statt Commit-Signatur |
| E-5-145 | Format `deploy/staging.json` (siehe unten); der Server liest Digests nur aus dem verifizierten Predicate und zieht nur per Digest |
| E-5-146 | Downgrade-Schutz über die Run-ID aus `runInvocationURI` |
| E-5-147 | Erst-Schalter root-eigen, für die Unit nur lesbar; wird ignoriert, sobald Zustand existiert |
| E-5-148 | Umsetzung in fünf PRs (siehe Konsequenzen) |
| E-5-149 | Die Konfiguration fährt im Freigabe-Image mit; ersetzt E-5-23 und E-5-25 aus ADR-011 |

### Freigabe-Bündel

Ein PR ändert `deploy/staging.json`:

```json
{
  "schema": 1,
  "environment": "staging",
  "images": {
    "api":   "ghcr.io/xxxcoder999xxx/identity-service@sha256:<64 hex>",
    "nginx": "ghcr.io/xxxcoder999xxx/identity-service-nginx@sha256:<64 hex>",
    "lego":  "ghcr.io/xxxcoder999xxx/identity-service-lego@sha256:<64 hex>"
  }
}
```

- `schema`: Erweiterungspunkt; unbekannte Nummer → Abbruch.
- `environment`: muss genau `staging` sein; eine Staging-Freigabe gilt nie
  für Production.
- `images`: genau drei Schlüssel, je ein strenger Regex mit dem erwarteten
  Paketnamen. Commit, Zeit und Laufnummer stehen nicht in der Datei, sie
  kommen aus dem Zertifikat.

Nach dem Merge baut der Workflow `release-staging.yml` (nur `push` auf
`main` mit Pfadfilter, kein `workflow_dispatch`) ein Image `FROM scratch`
mit fester Dateiliste: `staging.json`, `compose.yaml`, `compose.staging.yaml`,
`nginx.staging.conf`, `nginx/snippets/**` und `docker/nginx/Dockerfile`
(E-5-160, siehe Nachtrag). Er prüft vorher die drei Images
mit dem bestehenden Gate, lädt das Bündel als
`ghcr.io/xxxcoder999xxx/identity-service-release:staging` hoch und stellt
einen Nachweis mit dem Inhalt von `staging.json` als Predicate aus
(Predicate-Typ eigene URI, z. B.
`https://github.com/xXxCoder999xXx/identity-service/release/v1`).

### Ablauf auf dem Server (ersetzt E-5-113)

0. `flock`, `id -u`, Werkzeuge per `command -v`, `gh`-Mindestversion,
   `docker info` (rootless).
1. Alle vier Pakete anonym nicht lesbar (eindeutig 401/403, E-5-115).
2. Temporärer `DOCKER_CONFIG`; Freigabe-Nachweis per Tag `staging` prüfen:
   Repository, Kennungen, Workflow `release-staging.yml`, `refs/heads/main`,
   Predicate-Typ; Gegenprobe. Geprüften `subject`-Digest festhalten.
3. Predicate prüfen: `schema`, `environment`, drei Referenzen per Regex.
   Run-ID aus `runInvocationURI` (Regex) gegen den Zustand (Downgrade-Regel).
4. Jedes der drei Images mit dem bestehenden Prüf-Gate (Herkunft,
   Stückliste, Gegenproben).
5. Freigabe-Image per **geprüftem Digest** ziehen; genau die feste
   Dateiliste nach `releases/<commit>/` kopieren, jede Abweichung bricht ab.
6. Die drei Images per Digest ziehen, Digest vergleichen.
7. `compose up -d` (Punkt ohne Wiederkehr), Health über nginx; bei Fehler
   Rückweg über den alten Release-Ordner plus Alarm.
8. Symlink `current` atomar umstellen, Zustand schreiben (erst nach
   Erfolg), Status, Ping an den Totmannschalter.

### Downgrade-Regel und Erst-Schalter

Der Zustand (Run-ID, Commit, Digest des Freigabe-Images) liegt im
`StateDirectory` des Deploy-Benutzers. Der Erst-Schalter ist eine root-eigene
Datei unter `/etc/identity-service/`, die die Unit nur lesen kann.

| Lage | Ergebnis |
|---|---|
| Run-ID größer als gespeichert | Deploy |
| gleiche Run-ID, gleicher Commit | nichts zu tun, Exit 0 |
| kleinere Run-ID oder gleiche mit anderem Commit | Abbruch und Alarm |
| kein Zustand, kein Schalter | Abbruch |
| kein Zustand, Schalter vorhanden | einmal ohne Vergleich deployen |
| Zustand vorhanden, Schalter vorhanden | Schalter ignorieren, Warnung; die Ownerin löscht ihn von Hand |

## Betrachtete Alternativen

1. **`git` und `gnupg` aus Debian, Prüfung der Web-Flow-Signatur**
   (ursprünglich E-5-111/E-5-113, E-5-23/E-5-25): verworfen. In trixie sind
   sechs Git-Lücken und vier GnuPG-Lücken offen; `git` bringt Perl und
   `libcurl` mit und braucht `github.com` als fünftes Netzziel. Die
   Web-Flow-Signatur beweist nur „in der GitHub-Oberfläche erzeugt“, für jedes
   Repository; die Bindung an dieses Repository käme erst aus TLS und
   `merge-base`.
2. **`git` mit schlankem Prüfer (`gpgv` oder `sqv`):** verworfen, nicht
   gemessen. `git` ruft den Prüfer mit gpg-Argumenten auf; ein
   Übersetzungs-Wrapper wäre sicherheitskritisch und fragil. Die
   Git-Lücken blieben.
3. **Commit-Archiv über die Commit-SHA ohne `git`:** verworfen. Das Archiv hat
   keine Signatur (Sitzung 30), und die aktuelle SHA von `main` käme nur über
   die API.
4. **Commit-Zeitstempel als Zähler gegen Downgrade:** verworfen. Ihn schreibt
   der Workflow selbst in den Predicate; die Run-ID bindet Fulcio.
5. **Erst-Schalter, den der Server nach Gebrauch löscht:** verworfen. Löschen
   verlangt Schreibrecht, und damit könnte der Deploy-Benutzer den Schalter
   auch selbst anlegen und den Downgrade-Schutz aushebeln.
6. **Zeilenformat statt JSON für die Freigabedatei:** verworfen. JSON ist
   ohne Umwandlung der Predicate und lässt sich in CI (`jq`) und Server
   (`gh --jq`) prüfen; ein eigener Zeilenparser entfällt.
7. **Freigabe-Nachweis an das API-Image hängen statt an ein eigenes
   Bündel:** verworfen. Eine Freigabe betrifft drei Images und die
   Konfiguration; eine reine nginx-Änderung hätte sonst kein Ziel.
8. **Konfiguration von Hand:** bereits in ADR-011 verworfen (Drift).

## Begründung

- Der Server prüft heute schon mit `gh` aus derselben Bibliothek, am Server
  rot/grün belegt. Die Freigabe nutzt denselben Weg, dieselbe Vertrauensbasis
  (Sigstore/TUF) und dieselben vier gemessenen Netzziele. Es kommt kein
  Paket hinzu.
- Der Nachweis bindet die Freigabe direkt an Repository, Workflow und
  `refs/heads/main` (Kennungen statt Namen, E-5-121), nicht nur an einen
  GitHub-weiten Schlüssel.
- Die Run-ID stammt aus dem von Fulcio ausgestellten Zertifikat. Ein Re-run
  eines alten Laufs behält seine alte ID und wird abgelehnt (gemessen am
  23.11.2026, siehe Nachtrag).
- Gemessen: `gh` nennt beim Prüfen per Tag den geprüften Digest. Weil der
  Server danach nur per Digest zieht und die Digests aus dem Predicate liest,
  entsteht kein Zeitfenster zwischen Prüfen und Nutzen.
- Die Konfiguration ist über den Digest des Freigabe-Images vom Nachweis
  gedeckt; eine feste Dateiliste verhindert, dass das Bündel Dateien
  außerhalb des Release-Ordners schreibt.

## Konsequenzen

**Positiv**

- Kein neues Paket auf dem Server; E-5-142 ist ohne Aufnahme erledigt.
- Freigabe, Images und Konfiguration hängen an einem Nachweis.
- DORA-Ereignis bleibt der Merge-Commit; seine SHA steht im Zertifikat.

**Negativ und Risiken**

- `release-staging.yml` signiert Freigaben und ist ein lohnendes Ziel.
  Rechte nur in diesem Job (`id-token: write`, `attestations: write`,
  `packages: write`), CODEOWNERS-Pflicht.
- Das neue Paket `identity-service-release` startet öffentlich (in diesem
  Repository gemessen). Der erste Lauf scheitert absichtlich an
  `verify-package-private.sh`; danach stellt die Ownerin es auf privat und
  gibt es dem Maschinenkonto frei.
- Dass Run-IDs steigen, ist beobachtet, nicht dokumentiert. Bricht das,
  lehnt der Server neue Freigaben ab (fail closed, Verfügbarkeit).
- Der erste Deploy vertraut ohne Vergleich (Erst-Schalter).
- Schlägt Schritt 7 fehl, bleibt der Zustand alt; jeder weitere Lauf
  versucht dieselbe Freigabe erneut und meldet Alarm.
- GitHub und Sigstore sind jetzt auch für die Konfiguration der
  Vertrauensanker (vorher der Web-Flow-Schlüssel von GitHub).

**Abhängigkeiten**

- Keine neue Action: `actions/attest` v4.2.2 ist bereits per SHA gepinnt
  (`publish.yml`). `FROM scratch` ist kein Basis-Image.
- Die verworfenen Debian-Pakete (`git`, `gnupg`, `gpgv`, `sqv`, `jq`) wurden
  auf packages.debian.org in exakter Schreibweise geprüft.

**Neue Pflichten und offene Messungen**

- ~~Re-run eines Freigabe-Laufs: gleiche Run-ID, `attempts/2`~~ gemessen
  am 23.11.2026 (Nachtrag).
- ~~Kopieren der Dateien aus dem Freigabe-Image unter rootless Docker~~
  gemessen am 24.11.2026 (Nachtrag).
- E-5-120: Darf die Deploy-Unit ohne Capabilities `systemctl start` für die
  Restart-Unit aufrufen?
- `.claude/rules/*.md` um den Freigabe-Weg ergänzen (Ownerin).

**Umsetzung (E-5-148)**

| Teil | Branch | Inhalt |
|---|---|---|
| 0 | `docs/adr-017-pull-deploy-staging` | dieses ADR, Verweis in ADR-011 |
| 4a | `feat/staging-release-file` | `deploy/staging.json`, Formatprüfung, Rot-Fälle |
| 4b | `ci/release-staging-workflow` | Workflow, Bündel, Nachweis, Bibliothek um Freigabe-Regeln erweitert |
| 4c | `feat/server-release-verification` | Server-Prüfung der Freigabe, Downgrade-Regel, Erst-Schalter, Rot-Beweis am Server |
| 4d | `feat/staging-deploy-units` | Deploy-Skript, Units, Restart-Unit, Installation |

**Auslöser für eine Neubewertung**

- `gh` ändert das Verhalten mit Platzhalter-Token oder das Format von
  `runInvocationURI`.
- Production soll denselben Weg nutzen (eigenes `environment`, eigener Tag).
- Ein zweiter Service geht in Staging.
- Debian liefert ein `git` ohne offene Lücken und ein Grund für `git` auf
  dem Server entsteht.

## Nachtrag 2026-11-24: Umsetzung 4a bis 4c und Messungen

Die Teile 4a (#161), 4b (#163) und 4c (#165) sowie der Refactor
`push-image.sh` (#162) sind gemergt. Dabei fielen Entscheidungen, die über
den Text oben hinausgehen, und zwei offene Messungen sind erledigt. Die
betroffenen Stellen oben sind angepasst. Der Status bleibt „Vorgeschlagen“,
bis die Ownerin ihn ändert.

### Messungen

**Re-run behält die Run-ID (23.11.2026).** Der Release-Lauf `45202570572`
brauchte drei Versuche (Paket öffentlich, Repository kurzzeitig privat). Der
Nachweis aus Versuch 3 trägt `…/actions/runs/45202570572/attempts/3`: Die
Run-ID bleibt, nur der Versuch steigt. Damit trägt die Annahme aus der
Begründung. Ein Re-run eines alten Laufs scheitert zusätzlich schon in der CI
am Aktualitätsschutz (E-5-156).

**Freigabe am Server (24.11.2026, Deploy-Benutzer, rootless Docker,
temporärer `DOCKER_CONFIG`, Platzhalter in `GH_TOKEN`):**

| Messung | Ergebnis |
|---|---|
| Maschinenkonto zieht `identity-service-release` per Digest | gelingt (Leserecht wirksam) |
| Fein abgestuftes Token des Maschinenkontos | `docker login` meldet Erfolg, `docker pull` scheitert mit `permission_denied: The token provided does not match expected scopes`, auch für das bisher lesbare API-Paket |
| `docker create` auf dem Bundle ohne Befehl | `no command specified` |
| `docker create <digest> /nonexistent`, dann `docker cp` | angelegt, nie gestartet; Datei byte-gleich zum Commit, Rechte 0644 |
| `verify-release.sh …:staging` mit den Dateien von `b5692ac` | Exit 0, Run `45202570572`, Versuch 3, 4/4 Gegenproben am erwarteten Grund |
| `fetch-release.sh`, gespeicherte Run-ID höher als die Freigabe `45428174452` | Exit 6, „kleiner als gespeichert“, nichts angelegt |
| `fetch-release.sh`, gespeicherte Run-ID niedriger | `deploy`, genau zehn Dateien, 0644/0755; zweiter Lauf: „existiert bereits mit gleichem Inhalt“ |

Der zweite Release-Lauf `45428174452` (nach #165, Commit `e5eab9d`) setzte
`staging` auf `sha256:329bdd34…eb88`; die Images sind unverändert die von
`768bbb4`.

### Weitere Teilentscheidungen

| Code | Inhalt |
|---|---|
| E-5-150 | Ein jq-Programm (`RELEASE_RULES`, `RELEASE_FACTS`) für jq in der CI und gojq am Server, nur der gemeinsame Sprachkern; in beiden belegt |
| E-5-151 | Kanonische Form ist Pflicht für `deploy/staging.json` (doppelte Schlüssel, BOM, ruhige Diffs) |
| E-5-152 | Erste Freigabe mit den Digests von `768bbb4` (am Server gemessen) |
| E-5-153 | `/deploy/` ist CODEOWNERS-pflichtig: Eine Änderung dort ist ein Deploy |
| E-5-154 | Der Release-Workflow prüft die drei Images mit dem Server-Einstieg, bevor er signiert |
| E-5-155 | Bundle = feste Dateiliste `RELEASE_FILES` in `scripts/lib/release-rules.sh`; nur Daten, keine Skripte; `FROM scratch` |
| E-5-156 | Nur der aktuelle Stand von `main` darf `staging` setzen (Aktualitätsschutz) |
| E-5-157 | Die CI prüft: Run-ID und Commit im Zertifikat gehören zu diesem Lauf; Prüfung per Digest und per Tag |
| E-5-158 | `scripts/push-image.sh` ist die einzige Push- und Digest-Logik |
| E-5-159 | Pfadfilter von `release-staging.yml` plus automatischer Abgleich mit `RELEASE_FILES` (keine Drift ohne neue Freigabe) |
| E-5-160 | `docker/nginx/Dockerfile` gehört ins Bundle (Quelle der Gegenprobe am Server, E-5-132) |
| E-5-161 | Erwartete Werte, Mindestversion und Platzhalter in `scripts/lib/registry-only.sh` (zwei Server-Einstiege, eine Quelle) |
| E-5-162 | Predicate-Typ der Gegenproben als Erweiterungspunkt; neue Gegenprobe „falscher Predicate-Typ“ |
| E-5-163 | Die Downgrade-Regel ist die reine Funktion `release_decide` in `scripts/lib/release-state.sh` (`deploy`, `first`, `noop`, `reject`); jede Zeile der Tabelle oben ist ein Testfall in `scripts/test-release-state.sh` im Pflicht-Job `Container & nginx` |
| E-5-164 | Eine vorhandene, aber ungültige Zustandsdatei ist `reject`, nie „kein Zustand“. Format: genau drei Zeilen `run`, `commit`, `bundle` mit Tabulator und LF; Lesen und Schreiben nutzen dieselbe Bibliothek |
| E-5-165 | Run-ID per Regex (höchstens 18 Ziffern, ohne führende Null) vor jeder Arithmetik |
| E-5-166 | Dateien aus dem Bundle: `docker create <verifizierter Digest> /nonexistent`, `docker cp` nur für `RELEASE_FILES`; Link, leere Datei, Ordner oder mehr als 256 KiB bricht ab; Rechte 0644/0755 setzt der Server; Kopie in `.incoming.*`, dann atomar umbenennen; ein vorhandener `releases/<commit>/` muss byte-gleich sein |
| E-5-167 | `scripts/fetch-release.sh`: Exit 6 ist der Alarm der Downgrade-Regel; Exit 2 bis 5 von `verify-release.sh` werden unverändert weitergegeben |
| E-5-168 | Das GHCR-Token des Maschinenkontos ist ein klassisches Token nur mit `read:packages` und festem Ablauf. GitHub Packages unterstützt laut Doku nur klassische Tokens; ein fein abgestuftes scheitert erst beim Pull (gemessen) |

### Konsequenzen

- Ein klassisches Token gilt für alles, was das Maschinenkonto lesen darf.
  Die Begrenzung leistet das Konto selbst (Leserecht nur auf die vier
  Pakete); das Token ist nur so eng wie das Konto.
- Erfolgreiches `docker login` beweist bei GHCR kein Leserecht; gemessen wird
  am Pull.
- Änderungen unter `scripts/lib/**` erzeugen über den Pfadfilter eine neue
  Freigabe mit neuer Run-ID, auch ohne geänderte Images (gewollt, DORA zählt
  sie mit).

### Offen für 4d

- `scripts/verify-package-private.sh` liest `compose.scan.yaml` aus der
  Repository-Wurzel; die gibt es am Server nicht. Schritt 1 des Ablaufs
  braucht dort eine andere Quelle für die Gegenprobe.
- Herkunft von `NGINX_DOCKERFILE` beim ersten Deploy, solange es kein
  `current` gibt. Ein falsches Dockerfile kann die Gegenprobe nur rot machen,
  nie grün (fail closed).
- `RELEASES_DIR`: `fetch-release.sh` prüft Eigentümer und Link, nicht aber,
  ob Gruppe oder andere schreiben dürfen. Der Ordner entsteht per
  `StateDirectory` mit `UMask=0077`; eine zusätzliche Prüfung ist vorgemerkt.
- `flock`, Schreiben des Zustands und `current` (Schritte 0, 8) sowie das
  Prüf-Gate der drei Images (Schritt 4) liegen im Deploy-Skript.
