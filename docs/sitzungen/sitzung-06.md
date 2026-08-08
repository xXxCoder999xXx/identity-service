# Sitzungsbericht – Sitzung 6 (abgeschlossen 2026-08-08)

Diesen Bericht zu Beginn von Sitzung 7 einfügen; die Arbeit setzt dann nahtlos beim ersten Roadmap-Punkt an. Ablage: `docs/sitzungen/sitzung-06.md` über einen geschützten PR.

> **Charakter dieser Sitzung:** geplant als Sitzung 6 (Block 5 + 4b), tatsächlich zweigeteilt. Der Konzeptteil wurde vollständig geliefert (Block 5 bestanden, 4b Teil 1 erarbeitet), die zweite Hälfte wurde zur **Konfigurations- und Repository-Korrektur**, weil die Bestandsaufnahme vor 4b mehrere Altlasten sichtbar machte. Codegenerierung für 4b fand bewusst **nicht** statt – das Gate ist offen. Erzeugt wurde stattdessen ein Kontrollwerkzeug.

---

## 1. Erledigt

### 1.1 Vorab-Check und Pflichtrecherche (6.0) – drei Befunde

- **.NET:** Der August-Patch-Tuesday (11.08.2026) liegt **drei Tage in der Zukunft**. Der Pin auf SDK 10.0.302 / Runtime 10.0.10 (Juli-Servicing vom 14.07., 17 CVEs) ist damit weiterhin exakt das aktuelle Sicherheitsniveau. **Fixiert:** Erscheint am 11.08. ein neues SDK, ändern sich `global.json` **und** der Build-Stage-Digest gemeinsam in **einem atomaren PR**.
- **nginx:** Keine Veränderung gegenüber Sitzung 5. Stable bleibt **1.30.4** (fixt CVE-2026-42533 map/regex, CVE-2026-60005 Slice-Memory-Disclosure, CVE-2026-56434 SSI Use-after-free), Mainline 1.31.3. **Fixiert:** Digest-Pin auf 1.30.4-Stand.
- **Scanner (Post-Incident-Postur als ADR-Kriterium):** Nachlese zum Trivy-Vorfall bestätigt zwei Punkte. Positiv: Die Maintainer haben alle `trivy-action`-Tags auf die ursprünglichen sicheren Commits zurückgesetzt (neue `v`-Präfix-Konvention) und **Immutable Releases** auf `trivy`, `trivy-action` und `setup-trivy` aktiviert. Verschärfend: Der Angriff lief am 22.03. über **separat kompromittierte Docker-Hub-Zugangsdaten** an allen GitHub-seitigen Kontrollen vorbei. **Fixiert fürs Scanner-ADR:** (a) Immutable Releases sind ein positiver Bewertungspunkt für Trivy; (b) der Docker-Hub-Seitenkanal begründet, das Scanner-**Image** ebenfalls per Digest zu beziehen – Digest-Pin schützt registryunabhängig, dieselbe Logik wie SHA-Pin bei Actions; (c) exakte Versionen von Trivy und Grype erst zum Vetting-Zeitpunkt von den Registries.

### 1.2 Block 5 – .NET-Konfigurationssystem (Konzept + Gate bestanden)

Erarbeitet: **ein** flacher Schlüssel-Wert-Speicher mit `:` als Hierarchietrenner; Provider-Reihenfolge `appsettings.json` → `appsettings.{Environment}.json` → User Secrets (nur Development) → Umgebungsvariablen → Kommandozeile, **letzter gewinnt**; `__` als plattformneutrales Synonym für `:`, das beim Einlesen normalisiert wird; `ASPNETCORE_ENVIRONMENT` als Modusschalter zwischen „gesprächig" und „verschlossen" mit **Default Production** (fail-closed by design); Vergleich zum alten `web.config`/`ConfigurationManager`-Modell (ein Artefakt pro Umgebung ⇒ die Fehlerklasse, die das Provider-Modell eliminiert).

**Gate bestanden.** Alle fünf Antworten korrekt. Drei Präzisierungen ergänzt:

- `appsettings.{Environment}.json` wird bei anderem Environment **nicht überschrieben, sondern gar nicht geladen** – es gibt nur einen Provider-Slot, der Platzhalter löst sich zu genau einer Datei auf. Eine nur dort gesetzte Einstellung fällt in Production ersatzlos auf den Basiswert zurück.
- **Arrays werden index-weise verschmolzen, nicht ersetzt.** Es gibt keine „Liste leeren"-Semantik. Betrifft direkt die ForwardedHeaders-Allowlist: **Listen von Vertrauensankern gehören vollständig von außen, nicht teilweise.**
- **Reparaturfalle bei ForwardedHeaders:** Die naheliegende Korrektur des stillen Fehlers ist, `KnownProxies`/`KnownNetworks` zu leeren – leere Listen bedeuten in ASP.NET Core aber **„alles akzeptieren"**. Der Ein-Zeilen-Fix für ein fail-closed-Problem kippt das Verhalten auf fail-open, und zwar wieder lautlos. **Konsequenz für 4b:** Allowlist wird **gesetzt, nicht geleert**, und beide Zustände werden empirisch per echtem Request verifiziert.

Sicherheitsseitig festgehalten: Secrets nie in `appsettings` (jede Datei im Repository hat die Verbreitungscharakteristik des Codes; Git vergisst nicht ⇒ Rotation statt Löschung); User Secrets liegen außerhalb des Repository-Baums, sind aber **unverschlüsselt** – ihr Versprechen ist „nicht im Repo", nicht „verschlüsselt"; Komfortfunktionen werden an `IsDevelopment()` gebunden, **niemals an eigene Flags** (zweite Wahrheit divergiert still).

### 1.3 Drei Entscheidungen für 4b fixiert

- **Service-Namen: `edge` + `identity-service`** (statt `api`). Begründung: wächst mit weiteren Services, entspricht dem späteren Kubernetes-Namen. Technische Nebenbedingung: **keine Unterstriche** – Docker erlaubt sie, sie sind aber keine gültigen DNS-Labels und brechen je nach Bibliothek die TLS-Namensprüfung.
- **`localhost` wird aus dem App-Zertifikat gestrichen.** Der SAN wäre nur für den Zugriff an nginx vorbei nötig; ohne ihn ist die Abkürzung strukturell versperrt statt disziplinabhängig („kann nicht" statt „darf nicht"). Preis offengelegt: Direkt-Debugging gegen den App-Container entfällt.
- **`proxy_ssl_verify on`** in nginx, mit `proxy_ssl_trusted_certificate`, `proxy_ssl_name` und kleiner `proxy_ssl_verify_depth`.

### 1.4 ⭐ Aktiver Befund: Re-Encryption ohne `proxy_ssl_verify` wäre wertlos

nginx verifiziert Upstream-Zertifikate **per Default nicht** (`proxy_ssl_verify off`). Ein Standard-`proxy_pass https://…` liefert also eine verschlüsselte, aber **nicht authentifizierte** Verbindung – Schutz gegen passives Mitlesen, keiner gegen einen aktiven Angreifer, der sich als Upstream ausgibt. Genau dieser Angreifer war der Grund für Variante 2 aus Sitzung 5. Ohne die Direktive hätten wir eine Maßnahme gebaut, die im Compose-File *aussieht* wie Zero Trust, aber die verworfene Ortsaussage wieder einführt („was auf `edge` antwortet, wird schon der richtige sein"). **Dritte Kopplung zum Zertifikatsskript, bisher nirgends notiert: Das CA-Zertifikat muss in den nginx-Container gemountet werden, nicht nur die Leafs.** Testfall für den empirischen Lauf: Ein Upstream mit falschem oder abgelaufenem Zertifikat muss zu einem Fehler führen, nicht zu einer funktionierenden Verbindung.

### 1.5 Digests von der Registry beschafft und verifiziert

| Image | Digest |
|---|---|
| `mcr.microsoft.com/dotnet/sdk:10.0-noble` | `sha256:72dd743782f2ae7e5476fd64f6a460045e3998dc862218b80e6944cba79a01b0` |
| `mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled` | `sha256:70d6f993bf715a031f027832a19cfb7f894df66c8b5eb40be0aaee820ad5d119` |
| `nginxinc/nginx-unprivileged:1.30.4` | `sha256:6ec1ad68ede4b327a803d62201fbe8bb6a1bb45ddf96f7d91120646dd84d5c75` |

Alle drei sind **Multi-Arch-Listen-Digests** – MCR liefert `manifest.list.v2+json` (Docker-Format), nginx `image.index.v1+json` (OCI-Format); beides ist die Ebene, die wir pinnen wollen, damit der Pin unter Windows/WSL wie in der Linux-CI trägt.

**Zwei Verifikationen statt einer Annahme:**
- `docker run … dotnet --version` im Build-Image meldet **10.0.302** – identisch mit `global.json`. Damit ist gesichert, dass der Container-Build nicht an `rollForward: disable` scheitert.
- Der `docker pull` meldete denselben Digest wie die vorherige Registry-Abfrage. Zwei unabhängige Wege, ein Ergebnis – genau die Eigenschaft, für die ein Digest existiert.

**Nebenbefund mit praktischem Wert:** `docker buildx imagetools inspect` lief **ohne laufenden Docker-Dienst**, `docker run` nicht. Derselbe Befehl, zwei Gegenstellen: `inspect` fragt die Registry über HTTPS, `run` braucht den lokalen Dienst.

### 1.6 Repository-Korrektur: drei PRs, alle über den geschützten Weg

- **PR #22 `fix(scripts):`** – Skript-Dublette entfernt. `New-LocalDevCertificates.ps1` lag nach den PRs #19/#20 **zweimal** im Repository (`docs/scripts/` und `scripts/`), inhaltsgleich. Vierter dokumentierter Fall des Musters „Reparatur-PR ergänzt das Richtige, entfernt aber den Torso nicht" (nach dependabot.yml, PR #9/#15, `.gitignore`). Verschärfend hier: Es geht um ein Skript, das in den Windows Trust Store schreibt – für sicherheitskritische Artefakte gilt genau eine Quelle der Wahrheit.
- **PR #23 `chore(governance):`** – CODEOWNERS: Platzhalter `@DEIN-GITHUB-HANDLE` durch den echten Account ersetzt (die Review-Maschinerie lief bis dahin ins Leere) und `/scripts/` als sicherheitskritischer Pfad ergänzt (offener Punkt aus Sitzung 5), mit ausformulierter Begründung im Kommentar.
- **PR #24 `refactor(build):`** – **Alle vier** `src`-Projekte wiederholten `TargetFramework`, `Nullable` und `ImplicitUsings`, die `Directory.Build.props` bereits zentral setzt. Heute wertgleich, also folgenlos – aber eine zweite Wahrheit, die bei einer Änderung der zentralen Datei still divergiert. Bewusst **von Hand** korrigiert statt per Regex (Textmatching auf XML ist dieselbe Fragilität, die wir beim SQL-Fehlercode-Matching schon verworfen haben). Verifikation: `dotnet restore --locked-mode` und `dotnet build -c Release` liefen durch – der erfolgreiche Build **beweist**, dass die Vererbung greift, denn ohne `TargetFramework` bräche MSBuild ab.

**Prozess-Zwischenfall (lehrreich):** Der Refactor-Commit landete zunächst auf dem CODEOWNERS-Branch. Bei Squash-Merge wären beide Änderungen zu **einem** Commit mit **einem** Titel verschmolzen – der für die andere Hälfte falsch gewesen wäre, und genau diesen Typ liest die automatische Versionsableitung (7.6). Zusätzlich: Ein sicherheitskritischer CODEOWNERS-Diff soll für sich prüfbar sein. Korrektur über Backup-Branch → `reset --hard` auf den gepushten Stand → `cherry-pick` auf einen eigenen Branch.

### 1.7 Werkzeug erzeugt: `Test-RepoState.ps1`

Rein lesende Zustandskontrolle in fünf Gruppen (Git-Zustand, Repository-Hygiene, Build-Governance, Toolchain, Commit-Konvention). Entwurfsentscheidung: **meldet, repariert nicht** – ein Prüfwerkzeug, das nebenbei eingreift, verwischt die Grenze zwischen Befund und Eingriff, und Änderungen gehören durch PRs. 12.2-Prüfung dokumentiert: 6.2d (Hygiene ist der Prüfgegenstand), 6.1.3 fail-closed (Abbruch ohne Git-Repository statt Weiterraten), 6.1.1 (gibt Dateinamen aus, **niemals Dateiinhalte** – ein Diagnosewerkzeug, das Schlüsselinhalte in die Konsole schreibt, ist selbst ein Leck), 6.2a (keine neue Abhängigkeit), plus die stderr-Lektion aus Sitzung 5 (Exit-Code als Erfolgsmaß).

**Wirkung messbar: 10 Befunde beim ersten Lauf → 2 beim letzten.** Die zwei verbliebenen sind die bewusst akzeptierten Commit-Titel aus #20/#21.

**Der wichtigste Einzelbefund war ein grüner:** *Kein privater Schlüssel in der Git-Historie.* Der `.gitignore`-Vorfall aus Sitzung 5 hatte damit **keinen Schadensradius** – die CA muss nicht neu erzeugt werden. Das war die eine Frage, deren Antwort zwischen „nichts zu tun" und „alles neu" entschieden hätte. Geprüft wurde bewusst die Historie (`--diff-filter=A` über `--all`), nicht der aktuelle Stand: Ein späteres Löschen hätte nichts geändert.

### 1.8 Konzept 4b Teil 1 erarbeitet – `.dockerignore` und Dockerfile (**Gate offen**)

- **Build-Kontext:** `docker build .` packt das **gesamte** Verzeichnis und schickt es an den Docker-Dienst – vollständig, vor dem ersten `RUN`, unabhängig davon, was das Dockerfile benutzt. In der Repo-Wurzel liegen `certs/` (private Schlüssel), `.vs/`, `.git/`, `bin/`, `obj/`. **Die `.gitignore` hilft nicht: Docker liest sie nicht.** `certs/` ist vor Git geschützt und vor Docker nackt.
- **Unveränderliche Schichten:** Ein `RUN rm` nach einem `COPY` löscht die Datei aus der *Ansicht*, nicht aus dem Image – strukturell exakt die Git-Blob-Situation, Antwort wäre wieder Rotation.
- **Erlaubnisliste statt Sperrliste** (`*` + gezielte `!`-Ausnahmen). Fehlerverhalten entscheidet: Sperrliste vergisst still, Erlaubnisliste bricht laut ab. Dieselbe Wahl wie `ssl_reject_handshake` und der gestrichene `localhost`-SAN. Preis: jede neue Datei braucht einen Eintrag – fällig im Moment der Änderung, nicht Monate später.
- **Multi-Stage:** Stage 1 `sdk:10.0-noble` (Compiler, MSBuild, NuGet, Shell, Paketmanager), Stage 2 `aspnet:10.0-noble-chiseled` übernimmt **nur** das Publish-Ergebnis. Sicherheitsgewinn ist der Hauptzweck: Nach einer RCE sucht ein Angreifer Shell, Paketmanager, Compiler, Netzwerkwerkzeuge – ein chiseled Image enthält **nichts davon**. „Assume breach" als Bauentscheidung.
- **Trade-offs benannt:** kein `docker exec … bash` (Diagnose läuft über Observability nach 7.2 – unbequem und diszipliniert zugleich); keine ICU-Bibliothek, Invariant-Modus (irrelevant für `/health`, **Auslöser** für Neubewertung von `-extra`: E-Mail-Normalisierung in Phase 5).
- **Non-Root wird explizit gesetzt**, obwohl chiseled bereits als User `app` (UID 1654) läuft: Eine Sicherheitseigenschaft, die nur als unsichtbarer Default existiert, verschwindet bei einem Basisimage-Wechsel lautlos. Sichtbar und auditierbar – dieselbe Regel wie bei der Middleware-Reihenfolge.
- **Schichtenreihenfolge als Cache-Strategie:** Selten Geändertes nach oben. Erst die Restore-steuernden Dateien, dann `dotnet restore`, **dann** der Quellcode.
- **Restore-Layer-Liste steht exakt fest:** `global.json`, `nuget.config`, `Directory.Build.props`, `Directory.Packages.props`, `IdentityService.slnx`, alle **fünf** `.csproj`, alle **fünf** `packages.lock.json`. Fehlt eine, bricht der Restore ab – oder, bei fehlender `packages.lock.json`, löst er **neu** auf und ignoriert still den geprüften Baum. Den zweiten, gefährlicheren Fall schließt `--locked-mode` im Container: Damit wandert die Supply-Chain-Kontrolle aus der CI in den Build selbst.
- **Zertifikate kommen nicht ins Image**, sondern werden zur Laufzeit read-only gemountet (Paritäts-Regel aus Block 5).

---

## 2. Gelernt

- **Die Reihenfolge „Env-Vars überschreiben Dateien" ist die Paritäts-Garantie**, nicht bloß Komfort: Nur so ist der signierte Hash aus der CI derselbe Hash, der in Staging läuft. Pro-Umgebung-Builds entwerten Signatur und Provenance zu Dekoration – Konfigurations-Reihenfolge und Quintett sind dasselbe Prinzip an zwei Enden.
- **Verschlüsselung ohne Authentifizierung ist keine halbe Sicherheit, sondern die falsche.** `proxy_ssl_verify off` hätte die Re-Encryption-Entscheidung in genau die Ortsaussage zurückverwandelt, gegen die sie gewählt wurde.
- **Die Reparatur eines fail-closed-Fehlers kann fail-open erzeugen** (leere `KnownNetworks` = alles akzeptieren). Spiegelbild des openssl-Bugs aus Sitzung 5: dieselbe Fehlerklasse, umgekehrtes Vorzeichen.
- **Ein Prüfwerkzeug muss sagen, welchen Zustand es misst.** Zweimal meldete das Skript scheinbare Rückschritte, weil es Arbeitskopie und `origin/main` gegeneinander las – korrekt gemessen, nur an verschiedenen Objekten.
- **Der erfolgreiche Build ist der Beweis der Vererbung.** Ohne `TargetFramework` bräche MSBuild ab; dass er durchläuft, ist die Messung – nicht die Annahme.
- **Was einmal in einer Schicht liegt, bleibt dort.** Image-Layer verhalten sich wie Git-Blobs: Löschen ändert die Ansicht, nicht den Inhalt.
- **Erlaubnislisten sind fail-closed, Sperrlisten fail-open** – als generelle Entwurfsregel, nicht nur für `.dockerignore`.
- **Ein Digest ist keine Behauptung der Registry, sondern eine Prüfsumme über den Inhalt** – belegt dadurch, dass Registry-Abfrage und tatsächlicher Download denselben Wert liefern.
- **Ein Squash-Merge macht die Branch-Zuordnung zur inhaltlichen Frage:** Zwei Themen auf einem Branch werden zu einem Commit mit einem notwendigerweise halbfalschen Titel.
- Windows-Execution-Policy ist laut Microsoft **keine Sicherheitsgrenze**, sondern Schutz vor versehentlichem Ausführen – eine Stolperschwelle, kein Zaun. Trotzdem: punktuell übersteigen (`-ExecutionPolicy Bypass` für einen Aufruf), nicht global abtragen.

---

## 3. Entscheidungen

### 3.1 ADR-Kandidaten (neu in dieser Sitzung)

- **ADR: `proxy_ssl_verify on` für die Upstream-Verbindung.** Ergänzt und rettet das Re-Encryption-ADR aus Sitzung 5: Ohne Verifikation ist die zweite TLS-Strecke unauthentifiziert. Konsequenz: CA-Mount in den nginx-Container.
- **ADR: Erlaubnisliste als Bauform der `.dockerignore`.** Verworfen: Sperrliste (Standardpraxis, aber fail-open bei Vergessen). Preis dokumentiert.
- **ADR: chiseled Runtime-Image.** Verworfen: `-extra` vorsorglich (YAGNI + größere Angriffsfläche). Auslöser für Neubewertung: kulturabhängige Operationen ab Phase 5.

### 3.2 Fixierungen

- Service-Namen `edge` / `identity-service`; keine Unterstriche in Service-Namen.
- `localhost` raus aus dem App-Zertifikat.
- Digests wie in 1.5; SDK-Pin und Build-Stage-Digest ändern sich künftig **nur gemeinsam**.
- Scanner-ADR: Immutable Releases als positives Kriterium, Scanner-Image ebenfalls per Digest.
- **Vorgemerkt für die 4b-CI-Erweiterungen: PR-Titel-Validierung** gegen das Conventional-Commits-Muster als harter Check. Begründung: Zweimal (#20, #21) hat Disziplin nicht gereicht; wo Disziplin wiederholt versagt, gehört eine Schranke hin – dieselbe Denkfigur wie beim gestrichenen `localhost`-SAN.
- **Bewusst akzeptiert:** Die Commit-Titel von #20 und #21 bleiben unkorrigiert. Historie eines geschützten Branches umzuschreiben, kostet mehr als es einbringt.

---

## 4. Offene Punkte

- **Gate zu 4b Teil 1 offen** – fünf Fragen zu beantworten, bevor `.dockerignore` und Dockerfile entstehen: (1) Warum schützt die `.gitignore` `certs/` nicht vor dem Docker-Build? (2) Warum genügt es nicht, sensible Dateien im Dockerfile nach dem Kopieren zu löschen? (3) Erlaubnisliste vs. Sperrliste – Unterschied im Fehlerfall? (4) Was gewinnt ein Angreifer mit RCE im SDK-Image, das er im chiseled Image nicht hat? (5) Warum kommt `dotnet restore` vor dem Quellcode, und was passiert bei fehlender `packages.lock.json` im Build-Kontext?
- **4b Teile 2–4 noch nicht konzipiert:** `compose.yaml` (Netze `edge`/`data`, Zertifikats-Mounts + Dateirechte für unprivilegierte User, DNS-Bindung von `proxy_pass`), `nginx.conf` (alle 3.3-Direktiven, `ssl_ciphers` **mit ECDSA-Suiten** – Kopplung an den Schlüsseltyp des Skripts, jetzt zusätzlich `proxy_ssl_*`), CI-Erweiterungen (Container-Build, `nginx -t`, Image-Scan mit Vetting+ADR, Dependabot-`docker`-Block, dependabot.yml-Schema-Validierung, Workflow-Trigger für `.github/`, **neu: PR-Titel-Check**).
- **Zertifikatsskript anpassen** (`api` → `identity-service`, `localhost` streichen, `IpAddresses` leeren) und Leafs neu erzeugen – **im selben PR wie die `compose.yaml`**, weil Service-Name und SAN nur gemeinsam stimmen können. Die CA wird wiederverwendet: kein Trust-Store-Schritt, kein Browser-Eingriff. `certs/api/` danach löschen.
- **`Test-RepoState.ps1` versionieren?** Liegt derzeit außerhalb des Repositories (`C:\Projects\tools\`). Empfehlung: nach `scripts/` aufnehmen – es hat sich in dieser Sitzung als Governance-Werkzeug bewährt, fiele unter den neuen CODEOWNERS-Eintrag und würde damit selbst reviewpflichtig. Argument dagegen: eine weitere Datei, die gepflegt werden will. Als Klein-ADR entscheiden.
- **11.08.2026 (in drei Tagen): Patch Tuesday.** Bei neuem SDK ist der Pin-PR (`global.json` + Build-Stage-Digest, atomar) der allererste Arbeitsschritt der nächsten Sitzung – Zustand vor Fortschritt.
- **ADRs ausformulieren und mergen** – weiterhin ausstehend: Fundament-ADR Zero Trust, Re-Encryption, TLS-Strategie, nginx-unprivileged, X-Forwarded-Klein-ADR; ADR-005 (Dependabot), ADR-006 (Signaturen), ADR-008 (rollForward disable); **neu:** `proxy_ssl_verify`, `.dockerignore`-Erlaubnisliste, chiseled.
- **DoD-Kurzbaustein (7.8)** hinter 4b, inkl. Container-Kriterien.
- **Firefox-Nutzung?** Falls ja, CA separat in den Firefox-eigenen Speicher importieren.
- **Aus Sitzung 1 unverändert offen:** Endpoint-Stil der Api (Phase 5, ADR), ArchUnitNET-Bewertung (Phase 5), Dev-Container-ADR (7.7), Zuschnitt des ersten fachlichen Use Case (Kandidat: Benutzerregistrierung).
- Diesen Bericht als `docs/sitzungen/sitzung-06.md` per PR mergen.

---

## 5. Phasen-Status

Fundament-Roadmap: **Schritt 4, Konzept aller fünf Blöcke bestanden.** Block 5 in dieser Sitzung abgeschlossen; damit ist der Konzeptvorrat für 4b vollständig, und 4b Teil 1 (Dockerfile/`.dockerignore`) ist bereits durchdacht – nur das Gate steht aus.

**Repository-Zustand: sauber und gemessen.** Alle Kontrollpunkte grün außer den zwei bewusst akzeptierten Commit-Titeln. Drei PRs über den geschützten Weg gemergt, Toolchain verifiziert (SDK 10.0.302 lokal **und** im Build-Image), alle drei Digests beschafft und doppelt bestätigt.

Keine Gates aus 6.4/6.5 berührt. **Kein Abschnitt-8-Auslöser eingetreten** – `proxy_ssl_verify` ist einseitige Upstream-Verifikation, kein mTLS; der Auslöser „mehrere Services kommunizieren intern" steht weiter aus.

**Recherchepflichten für Sitzung 7 (6.0, vor der Codegenerierung zwingend):** Ergebnis des Patch Tuesday vom 11.08. (neues SDK ⇒ Pin-PR zuerst); nginx-Lage erneut kurz prüfen; Scanner-Kandidaten (Trivy-Post-Incident-Stand, Grype-Stand) zum Vetting-Zeitpunkt; Digest-Stände **zum Pin-Zeitpunkt von der Registry**, nicht aus diesem Bericht, falls seit dem 08.08. neue Releases erschienen sind.

---

## Roadmap für Sitzung 7

1. **Vorab-Check (kurz):** `Test-RepoState.ps1` laufen lassen – erwartet werden genau zwei Befunde (die akzeptierten Commit-Titel). **Ist der August-Patch-Tuesday-Pin-PR nötig?** Wenn ein neues SDK erschienen ist, ist das der allererste Arbeitsschritt.
2. **Pflichtrecherche (6.0):** wie in Abschnitt 5 gelistet, Ergebnisse mit unmittelbaren Konsequenzen fixieren.
3. **Gate zu 4b Teil 1** – die fünf Fragen aus Abschnitt 4 beantworten.
4. **Codegenerierung 4b Teil 1:** `.dockerignore` (Erlaubnisliste) + `Dockerfile` (Multi-Stage, Digest-Pins, Non-Root explizit, `--locked-mode`). Danach **empirischer Verifikationslauf**: Image bauen, Größe und Nutzer prüfen, Build-Kontext-Größe kontrollieren, Container starten und `/health` erreichen.
5. **4b Teil 2:** `compose.yaml` (Netze, Namen, Mounts, Dateirechte) **gemeinsam** mit der Anpassung des Zertifikatsskripts und Neuausstellung der Leafs.
6. **4b Teil 3:** `nginx.conf` inklusive `proxy_ssl_*`. Empirische Verifikation der Security-Header per echtem Request (nicht durch Konfigurationslektüre) und der Upstream-Verifikation per Negativtest (falsches Zertifikat muss scheitern).
7. **4b Teil 4:** CI-Erweiterungen inklusive PR-Titel-Check.
8. **DoD-Kurzbaustein (7.8)** direkt im Anschluss.
9. **Vorher verstehen (Vorbereitung):** Wie sich Build-Kontext, Image-Schichten und Laufzeit-Mounts unterscheiden – also welche Datei wann wo landet. Als Lernkontrolle: die drei Kopplungen zwischen Zertifikatsskript und 4b-Artefakten aus dem Gedächtnis nennen (Konfiguration/Pfade, PKI/SAN, Dateisystem/Rechte) – plus die neue vierte (CA-Mount für nginx).
10. **Optionale Vorbereitung:** OWASP Docker Security Cheat Sheet; Microsoft-Doku zu chiseled Images; die `.dockerignore`-Syntax für Erlaubnislisten (Reihenfolge von `*` und `!`-Ausnahmen).

---

Damit ist Sitzung 6 geschlossen: Block 5 vollständig durch das Gate, drei Entscheidungen für 4b fixiert, ein Befund gefunden, der die Re-Encryption-Entscheidung vor der Wirkungslosigkeit bewahrt hat, alle Digests beschafft und doppelt verifiziert – und ein Repository, das von zehn Befunden auf zwei bewusst akzeptierte geschrumpft ist. Das Kontrollwerkzeug dafür existiert jetzt und ist wiederverwendbar. Der Konzeptvorrat reicht bis in die Codegenerierung von 4b Teil 1; es fehlt nur noch dein Gate. Bis Sitzung 7!
