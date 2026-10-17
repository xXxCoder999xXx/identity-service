# Sitzungsbericht Sitzung 12

**Datum:** 16.10.2026
**Phase:** Schritt 5 (CD), Teil A unverändert – diese Sitzung hat die Anweisungen an den Agenten neu geordnet (Schritt 1 von 3, nicht committet); die Roadmap von Sitzung 11 ist nicht begonnen
**Vorgänger:** sitzung-11.md (abgeschlossen 10.10.2026)

---

## 1. Erledigt

### 1.1 Bestandsaufnahme: Was kann ein Skill werden?

Anlass: `CLAUDE.md` soll kleiner werden; wiederkehrende Abläufe mit festem
Muster sollen als Skill aufrufbar sein.

Gelesen: `CLAUDE.md`, die drei Skills (`adr`, `sitzung-starten`,
`sitzung-beenden`), die drei Regeldateien unter `.claude/rules/`,
`.claude/settings.json` und `sitzung-11.md`.

Grundsatz: Es gibt vier Orte für Anweisungen, unterschieden danach, wann sie
geladen werden:

| Ort | Wann geladen | Passt für |
|---|---|---|
| `CLAUDE.md` | immer | Regeln, die nie fehlen dürfen |
| `.claude/rules/*.md` | wenn eine Datei aus der `paths`-Liste berührt wird | Fachregeln zu bestimmten Dateien |
| `.claude/skills/*/SKILL.md` | bei Aufruf oder wenn die Beschreibung passt | Abläufe mit festen Schritten |
| Hooks und `permissions` | immer, technisch erzwungen | Verbote, die nicht vom Modell abhängen dürfen |

Ein Skill ist fail-open: Lädt er nicht, gilt sein Inhalt still nicht. Harte
Regeln bleiben deshalb in `CLAUDE.md` (E-H-13).

Ermittelte Skill-Kandidaten (aus den Berichten 2 bis 11):

| Skill | Ablauf | Aus `CLAUDE.md` heraus | Bleibt in `CLAUDE.md` |
|---|---|---|---|
| `/bot-pr-pruefen <nr>` | Titel, Release Notes, Lockfile-Diff, Major/Patch, Checks wirklich gelaufen | Detail in §4 | „nie ungelesen, nie Auto-Merge" |
| `/pflichtrecherche` | SDK-Pin, Digests, Action-SHAs neu auflösen; CISA KEV, OWASP, thehackernews | Detail in §1 „Aktualität" | Pflicht und „Pins nur aus Registry" |
| `/abhaengigkeit-pruefen <name>` | Slopsquatting-Prüfung, Aufnahme-Prüfung, danach `/adr` | Prüfliste in §5 | Hinweispflicht, Installationsverbot |
| `/pr-vorbereiten` | Branch-Name, PR-Titel, Sicherheitsregeln im PR-Text, Trailer, Checks nach dem Merge | Detail in §4 | Ruleset, ein Thema pro Branch, keine Pushes ohne Auftrag |
| `/rot-beweis` | Wegwerf-PR als Entwurf, ablesen, schließen | Absatz in §4 | „nur nach Freigabe, nie mergen" |
| `/threat-model <feature>` | STRIDE, Missbrauchsfälle als Testfälle | Absatz in §9 | „vor jedem fachlichen Feature" |
| optional `/nach-merge` | Publish-Lauf prüfen, lokale Branches aufräumen | – | – |

`/rot-beweis` und `/pr-vorbereiten` sollen `disable-model-invocation: true`
bekommen, damit nur die Projekt-Ownerin sie startet (E-H-16).

### 1.2 Schritt 1: Doppelungen aufgelöst (Branch `docs/move-duplicate-rules`, nicht committet)

Nach ausdrücklicher Freigabe der Projekt-Ownerin:

- `CLAUDE.md` §3: Der Satz zu Qualitätsregeln, `Directory.Packages.props`,
  `packages.lock.json` und `global.json` entfällt; er stand inhaltlich schon in
  `rules/dotnet-und-tests.md` und `rules/lieferkette-und-ci.md`.
- `CLAUDE.md` §7: Der YAML-Eintrag entfällt (stand fast wörtlich in
  `rules/lieferkette-und-ci.md`). Vom Skript-Eintrag bleibt nur der Satz zu
  `stderr` und dem Exit-Code, weil er auch für Befehle im Gespräch gilt.
- `rules/lieferkette-und-ci.md`: Die YAML-Regel trägt jetzt den Vorfall als
  Begründung (`groups` unter `schedule`, SAST-Gate rund zwei Wochen aus,
  Config-only-PRs mit 0 Checks gemergt).
- Neu `rules/skripte.md` mit `paths` `scripts/**` und `.claude/hooks/**`:
  ASCII, PowerShell 5.1 lokal / Bash auf dem Runner, `bash -n`, Exit-Code statt
  `stderr`, melden statt reparieren, keine Schlüsselinhalte.

Verifiziert:

- Jede verschobene Regel steht danach in genau einer Datei (Suche über
  `CLAUDE.md` und `.claude/rules/`).
- Alle vier Skripte unter `scripts/` und beide Hooks sind reines ASCII (0 Bytes
  außerhalb von ASCII); Gegenprobe: eine Datei mit „ä" ergibt 2 Bytes.
- `CLAUDE.md` schrumpft von 15 577 auf 14 644 Bytes (rund 6 %). Die frühere
  Schätzung „Hauptgewinn aus den Doppelungen" war zu hoch; der größere Teil
  kommt aus den Skills (Schritte 2 und 3).

### 1.3 Ladetest der Regeldateien (Ergebnis unklar)

Dateien per Read geöffnet und geprüft, ob der Harness die Regeldatei
mitliefert:

| Geöffnete Datei | Erwartete Regel | Geladen |
|---|---|---|
| `nginx.conf` | `container-und-nginx.md` (`**/nginx*.conf`) | ja |
| `src/IdentityService.Domain/packages.lock.json` | `dotnet-und-tests.md` (`src/**`) | ja |
| dieselbe Datei | `lieferkette-und-ci.md` (`**/packages.lock.json`) | nein |
| `Directory.Build.props` | `lieferkette-und-ci.md` | nein |
| `scripts/invoke-image-scan.sh` | `lieferkette-und-ci.md` (`scripts/*.sh`), `skripte.md` (`scripts/**`) | nein |

Ausgeschlossen: Musterform (`src/**` ohne `**/` lädt) und Dateiformat (alle
vier Regeldateien ohne BOM, ohne CRLF, gleicher Kopf). Vermutung, nicht
bewiesen: Genau die zwei Dateien, die in der Sitzung bearbeitet bzw. angelegt
wurden, lädt der Harness nicht erneut, weil er sie für bekannt hält. Prüfung
nur in einer frischen Sitzung möglich (Roadmap 1).

---

## 2. Gelernt

- Ein Skill lädt nur bei Bedarf und ist damit fail-open; harte Regeln gehören
  in die immer geladene `CLAUDE.md` oder in einen Hook, nie in einen Skill
- Die Beschreibung jedes Skills liegt dauerhaft im Kontext; viele Skills mit
  langen Beschreibungen fressen die Ersparnis in `CLAUDE.md` wieder auf
- Pfadgebundene Regeldateien sind der richtige Ort für Regeln, die nur beim
  Bearbeiten bestimmter Dateien zählen; Skills sind der richtige Ort für
  Abläufe
- Ob eine Regeldatei lädt, lässt sich messen: passende Datei öffnen und
  nachsehen, ob sie mitgeliefert wird
- Eine Messung im selben Gespräch, in dem die Regeldatei bearbeitet wurde, ist
  möglicherweise nicht aussagekräftig; der Gegentest gehört in eine frische
  Sitzung
- `grep -P` scheitert unter Git Bash auf diesem Rechner („supports only
  unibyte and UTF-8 locales"); eine Schleife `if grep -q -P …` meldet dann für
  jede Datei das Gutfall-Ergebnis – ein Prüfwerkzeug, das nicht suchen konnte
- Eine Größenschätzung vor dem zeilengenauen Vergleich ist eine Vermutung;
  nach dem Vergleich lag die Ersparnis bei 6 % statt der genannten rund 25 %

---

## 3. Entscheidungen (ADR-Kandidaten)

| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-H-13** | Anweisungen an den Agenten werden nach Ladezeitpunkt verteilt: harte Regeln in `CLAUDE.md` oder Hooks, Dateiregeln in `.claude/rules/`, Abläufe in Skills (**ADR-Kandidat**) | Skills und Regeldateien sind fail-open; nur `CLAUDE.md` und Hooks wirken immer |
| **E-H-14** | Reihenfolge: 1 Doppelungen auflösen, 2 `/pflichtrecherche` und `/bot-pr-pruefen`, 3 übrige Skills bei Bedarf | Kleinstes Risiko zuerst; die zwei Skills betreffen Abläufe jeder Sitzung, die schon Lücken hatten |
| **E-H-15** | Skript-Regeln stehen in einer eigenen Regeldatei `skripte.md` für `scripts/**` und `.claude/hooks/**` | Sie gelten nur beim Bearbeiten von Skripten und Hooks |
| **E-H-16** | `/rot-beweis` und `/pr-vorbereiten` bekommen `disable-model-invocation: true` (geplant) | Beide wirken nach außen; nur die Projekt-Ownerin soll sie auslösen (Least Privilege, 6.3.4) |
| **E-H-17** | Schritt 1 wird erst committet, wenn das Laden von `lieferkette-und-ci.md` und `skripte.md` in einer frischen Sitzung belegt ist | Lädt eine Regel nicht, gilt ihr aus `CLAUDE.md` entfernter Inhalt still nicht |

---

## 4. Offene Punkte

**Aus dieser Sitzung**

- Branch `docs/move-duplicate-rules` mit uncommitteten Änderungen an
  `CLAUDE.md`, `.claude/rules/lieferkette-und-ci.md` und neu
  `.claude/rules/skripte.md`. Geplanter PR-Titel:
  `docs: move duplicated rules from CLAUDE.md to path rules`
- Ladetest unklar: `lieferkette-und-ci.md` und `skripte.md` luden nicht
  (Abschnitt 1.3). Ursache unbewiesen
- Dieser Bericht liegt als unversionierte Datei im Arbeitsverzeichnis auf dem
  Branch `docs/move-duplicate-rules`; er gehört auf einen eigenen Branch
  `docs/sitzung-12` (ein Thema pro Branch) und ist noch nicht committet
- Skill-Schritte 2 und 3 (E-H-14) nicht begonnen
- Ob `disable-model-invocation` in der eingesetzten Claude-Code-Version
  wirkt, ist nicht geprüft

**Weiter offen aus Sitzung 11 (in dieser Sitzung nicht bearbeitet)**

- Pflichtrecherche: Patch Tuesday 13.10.2026, zeitgesteuerte Läufe von CodeQL
  und CI vom 12.10.2026, neue Dependabot-PRs, Läufe von „Publish"
- Grundsatzentscheidung Deploy oder Fachlogik zuerst (E-5-15)
- `xunit.v3` steht auf 3.2.2 (Testplattform v1); Umstellung als eigener PR
- Nachtrag zu ADR-005 (Wartefrist, Lücke bei Container-Images); Bot-Titel
  `chore: Bump …`; ADR-006 und ADR-008 nachschreiben
- Alle übrigen offenen Punkte und bekannten Grenzen aus `sitzung-11.md`
  Abschnitt 4 gelten unverändert

---

## 5. Phasen-Status und Gates

Phase 4, Schritt 5 (CD): unverändert Teil A. Diese Sitzung hat nur die
Anweisungen an den Agenten bearbeitet.

| Thema | Status |
|---|---|
| **Resilienz-Patterns** | Ausgelöst seit Sitzung 7, unbearbeitet |
| **mTLS / Service-Mesh-Bewertung** | Rückt näher, unverändert |
| **DAST** | Wird mit dem ersten Staging-Deploy fällig |
| **Feature Flags** | Wird fällig, falls Phase 5 vor dem Deploy beginnt |
| **Agentic-Gate 6.5** | Nicht ausgelöst; berührt: Die Neuordnung betrifft die Steuerung des Agenten selbst (Least Privilege über `disable-model-invocation`, fail-open von Skills und Regeldateien) |
| **Contract Testing, Mutation Testing, k6, LLM-Gate 6.4** | Nicht ausgelöst |

---

## 6. Technische Referenz (für Folgesitzungen)

Keine Digests oder Versionen in dieser Sitzung aufgelöst; es gelten die Pins
aus `sitzung-11.md` Abschnitt 6 (Stand 10.10.2026).

**ASCII-Prüfung unter Git Bash** (ohne `grep -P`), mit Gegenprobe:

```
LC_ALL=C tr -d '\000-\177' < <Datei> | wc -c
```

Ergebnis 0 bedeutet reines ASCII; eine Probedatei mit „ä" muss 2 ergeben.

**Ladetest für Regeldateien:** Datei mit dem Read-Werkzeug öffnen (nicht per
`cat` in der Shell) und prüfen, ob der Inhalt der Regeldatei mitgeliefert
wird. Testdateien: `scripts/invoke-image-scan.sh` (erwartet
`lieferkette-und-ci.md` und `skripte.md`), `Directory.Build.props` (erwartet
`lieferkette-und-ci.md`).

**Fallstricke, die Zeit gekostet haben:**

- `grep -P` meldet unter Git Bash einen Fehler auf `stderr` und findet nichts;
  in einer `if`-Bedingung wird daraus still der Gutfall (Exit-Code nicht
  einzeln gemessen)
- Ein `cd` in einem Shell-Befehl kann das Arbeitsverzeichnis der Sitzung
  verschieben; danach absolute Pfade verwenden

---

# Roadmap Sitzung 13

## 1. Ladetest der Regeldateien und Abschluss von Schritt 1 (zuerst)

Warum zuerst: Auf dem Branch liegt eine uncommittete Änderung, die Regeln aus
`CLAUDE.md` entfernt. Ob sie an ihrem neuen Ort laden, ist unbewiesen (E-H-17).

1. Auf `docs/move-duplicate-rules` `scripts/invoke-image-scan.sh` und
   `Directory.Build.props` per Read öffnen
2. Laden beide Regeldateien: diesen Bericht auf einen eigenen Branch
   `docs/sitzung-12` bringen, danach Commit und PR für Schritt 1 auf
   Anweisung der Projekt-Ownerin
3. Lädt eine nicht: Änderung an `CLAUDE.md` nicht übernehmen, Ursache suchen
   (Muster, Frontmatter, Verhalten des Harness)

Das Ergebnis klärt auch den offenen Punkt aus Sitzung 11 zu `scripts/*.sh`.

## 2. Pflichtrecherche und Blick auf die Automatik

Warum: Unverändert aus Roadmap 12; Patch Tuesday und die zeitgesteuerten
Läufe liegen inzwischen zurück. Zugleich der natürliche erste Einsatz eines
Skills `/pflichtrecherche` (Schritt 2), falls er vorher entsteht.

## 3. Skills `/pflichtrecherche` und `/bot-pr-pruefen` (Schritt 2)

Warum: Beide Abläufe kommen in jeder Sitzung vor; in Sitzung 11 fehlten bei
der Recherche CISA KEV und OWASP. Entwurf zuerst, Dateien nach Freigabe;
CODEOWNERS-pflichtig, eigener Branch.

## 4. Grundsatzentscheidung Deploy oder Fachlogik zuerst

Warum: Vertagt seit Sitzung 11 (E-5-15), bestimmt alles Weitere.

## 5. xUnit-Umstellung und kleine Nachträge

Wie in Roadmap 12, Punkte 3 und 4.

## 6. Vor oder in der Sitzung zu verstehen (vor Code)

- **Ladezeitpunkt entscheidet:** `CLAUDE.md` ist immer da, Regeldateien nur
  bei passenden Dateien, Skills nur bei Aufruf. Was immer gelten muss, darf
  nicht von einem Ladevorgang abhängen.
- **`disable-model-invocation`:** Ein Feld im Kopf eines Skills, das den
  automatischen Aufruf durch das Modell abschaltet. Dann startet nur ein
  Mensch den Skill per Schrägstrich-Befehl.
- **Weiter aus Roadmap 12:** zwei Testplattformen in .NET, Prüf-Gate vor dem
  Deploy, OIDC gegenüber externen Zielen, Environments, Wartefrist für Updates.

## 7. Optionale Vorbereitung

- Überlegen, welche weiteren wiederkehrenden Abläufe ein Skill werden sollen
- Die Punkte aus Roadmap 12, Abschnitt 6 (Staging-Ziel, Dependabot-Alerts,
  „Automatically delete head branches", Projektauftrag, Ablauf des Tokens
  am 06.11.2026)
