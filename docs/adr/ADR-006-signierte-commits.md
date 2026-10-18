# ADR-006: Signierte Commits auf `main`

- **Status:** Vorgeschlagen
- **Datum:** 2026-10-18

## Kontext

Wer ein Token mit Schreibrecht auf das Repository erbeutet, kann Commits unter
beliebigem Namen und beliebiger E-Mail-Adresse einspielen. Git prüft diese
Angaben nicht. Die Recherche zu Beginn von Sitzung 2 zeigte, dass genau das
2026 in großem Stil geschieht: Der CISA-Alert „Megalodon“ (28.05.2026)
beschreibt massenhafte Injektionen in Workflows, um Secrets zu ernten; bei
`codfish/semantic-release-action` (24.06.2026) wurden Tags per Force-Push
umgeleitet.

Wirkende Kräfte:

- **Lieferkette (A03):** Was auf `main` liegt, wird gebaut, signiert und
  später deployt. Die Herkunft eines Commits muss deshalb belegbar sein.
- **Fail closed:** Ein Commit ohne gültige Signatur soll nicht auf `main`
  gelangen, statt nur markiert zu werden.
- **Solo-Projekt:** Es gibt keine zweite Person für Reviews. Was ein Mensch
  nicht prüfen kann, soll die Plattform erzwingen.
- **Aufwand:** Die Einrichtung soll in wenigen Minuten erledigt sein und den
  Alltag nicht bremsen.

Die Entscheidung fiel in Sitzung 2 als ADR-Kandidat und ist seitdem im
Ruleset umgesetzt (`docs/governance/main-ruleset.json`, Regel
`required_signatures`). Dieses ADR hält sie mit den Erfahrungen bis zum
18.10.2026 fest. Die Nummer 006 war seit Sitzung 2 dafür vorgesehen.

## Entscheidung

Wir verlangen per Ruleset signierte Commits auf `main` und signieren lokal mit
einem SSH-Schlüssel.

Im Einzelnen:

- Das Ruleset für `main` enthält `required_signatures`, ohne Bypass-Akteure.
- Lokal signiert Git jeden Commit mit dem SSH-Schlüssel der Projekt-Ownerin.
  Der öffentliche Schlüssel ist bei GitHub als Signaturschlüssel hinterlegt.
- `main` wird nur per Squash-Merge beschrieben. Den Squash-Commit signiert
  GitHub mit dem eigenen Web-Flow-Schlüssel.
- Signierung und Hooks werden nie umgangen (`--no-gpg-sign`,
  `commit.gpgsign=false`, `--no-verify`), auch nicht vom KI-Agenten
  (CLAUDE.md Abschnitt 6).

## Betrachtete Alternativen

1. **Keine Signaturpflicht:** verworfen. Ohne Pflicht zeigt GitHub einen
   unsignierten Commit nur als „Unverified“ oder gar nicht markiert an; er
   gelangt trotzdem auf `main`. Ein Hinweis, den niemand zum Zeitpunkt der
   Entscheidung sieht, ist kein Gate.
2. **Signaturpflicht ohne Squash-only:** verworfen. Dann müsste jeder
   einzelne Commit eines PR signiert sein, auch Commits von Bots oder aus der
   Weboberfläche. Fehlt eine Signatur, wäre der PR nicht mergebar
   (Lockout-Risiko). Mit Squash-only signiert GitHub den einen neuen Commit
   selbst.
3. **Signieren mit GPG statt SSH:** in den Sitzungen nicht eigens verglichen.
   SSH wurde gewählt, weil ein SSH-Schlüssel ohnehin vorhanden ist und kein
   weiteres Werkzeug nötig ist.

## Begründung

- Die Prüfung findet serverseitig statt: Ein Angreifer mit gestohlenem Token,
  aber ohne den privaten Schlüssel, kann keinen gültig signierten Commit
  erzeugen. Das Ruleset lehnt den Push ab.
- Squash-only macht die Pflicht lockout-frei. Die Signaturen auf den
  Feature-Branches bleiben trotzdem sinnvoll, weil sie zeigen, wer die
  Änderung im PR geliefert hat.
- Seit Sitzung 4 ist die Signierung nachweislich aktiv (Badge „Verified“ auf
  allen Commits). Sitzung 14 hat sie lokal und bei GitHub gegengeprüft
  (Commit `cf1106b`: lokal `%G?` = `U`, GitHub `verified: true, valid`).
- Null neue Abhängigkeiten: Git und GitHub bringen alles mit.

## Konsequenzen

**Positiv**

- Ein eingeschleuster Commit ohne Schlüssel erreicht `main` nicht.
- Die Signatur ist die Grundlage für den Pull-Deploy: Der Staging-Server
  übernimmt Konfiguration nur nach Prüfung der Commit-Signatur (ADR-011,
  E-5-23).

**Negativ**

- Die Signatur beweist den Schlüssel, nicht die Person. Der Schlüssel
  signiert ohne Eingabe (Sitzung 8). Damit kann jedes Programm auf dem
  Rechner der Projekt-Ownerin signieren, auch der KI-Agent. Den KI-Anteil
  macht nur der Attribution-Trailer sichtbar, nicht die Signatur.
- Auf `main` vertrauen wir dem Web-Flow-Schlüssel von GitHub (E-5-25).
  GitHub ist damit Vertrauensanker für alles, was auf `main` liegt.
- Ein Verlust des Schlüssels blockiert neue Commits, bis ein neuer Schlüssel
  bei GitHub hinterlegt ist.

**Neue Pflichten**

- Den privaten Schlüssel schützen; bei Verdacht auf Kompromittierung sofort
  bei GitHub entfernen und ersetzen.
- Bei einem neuen Rechner oder Schlüssel die Signierung mit einem Probe-Commit
  prüfen (`%G?` lokal, Badge bei GitHub).

**Auslöser für eine Neubewertung**

- Eine zweite Person arbeitet mit: dann zusätzlich Approvals und
  CODEOWNERS-Review.
- Der Agent soll ohne Aufsicht committen: dann ein eigener Schlüssel für den
  Agenten, damit Signatur und Person wieder zusammenpassen.
