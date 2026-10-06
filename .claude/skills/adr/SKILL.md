---
name: adr
description: Legt im IdentityService-Projekt ein Architecture Decision Record mit der nächsten freien Nummer unter docs/adr/ an. Verwenden, wenn der Nutzer ein ADR schreiben, einen ADR-Kandidaten (Code E-...) ausarbeiten oder eine Entscheidung dokumentieren will.
argument-hint: "<Titel oder Entscheidungscode, z. B. E-4b-2>"
---

# ADR anlegen

Ziel: eine Entscheidung so festhalten, dass sie ohne Sitzungskontext nachvollziehbar ist.

## Ablauf

1. **Gegenstand klären.** Das Argument ist ein Titel oder ein Entscheidungscode (`E-<Schritt>-<n>`). Bei einem Code die Entscheidung im zugehörigen Sitzungsbericht unter „Entscheidungen" nachlesen.
2. **Nummer bestimmen.** In `docs/adr/` die höchste vergebene Nummer suchen; das neue ADR bekommt die nächste. `ADR-000` ist die Vorlage und zählt nicht. Lücken in der Zählung nicht stillschweigend füllen, sondern dem Nutzer nennen.
3. **Dateiname:** `docs/adr/ADR-NNN-kurztitel.md`, ASCII, kleingeschrieben, Wörter mit Bindestrich, Umlaute als ae/oe/ue.
4. **Vorlage lesen.** Den Aufbau aus `docs/adr/ADR-000-vorlage.md` übernehmen, nicht aus dem Gedächtnis. Die Vorlage ist die einzige Quelle für die Struktur.
5. **Entwurf schreiben** und dem Nutzer vorlegen. Status eines neuen ADR ist „Vorgeschlagen"; „Akzeptiert" setzt der Nutzer. Datum im Format `JJJJ-MM-TT`.
6. **Nicht selbst committen.** Vorschlagen: Branch `docs/adr-NNN-kurztitel`, PR-Titel `docs(adr): add ADR-NNN <short english title>`.

## Regeln für den Inhalt

- **Kontext:** die Kräfte nennen, die wirken (Sicherheit, Open/Closed, minimale Abhängigkeiten), und den Auslöser.
- **Entscheidung:** ein Satz, aktiv formuliert („Wir verwenden ...").
- **Betrachtete Alternativen:** mindestens die naheliegende Alternative, je mit dem Grund, warum sie verworfen wurde. Wurde in der Sitzung keine Alternative geprüft, das so schreiben oder den Nutzer fragen. Keine Alternativen oder Messwerte erfinden.
- **Begründung:** belegbar. Empirische Befunde aus der Sitzung nennen (z. B. „Port-Publishing auf internen Netzen funktioniert nicht – ausprobiert").
- **Konsequenzen:** positiv und negativ, dazu neue Pflichten und der Auslöser für eine Neubewertung.
- **Abhängigkeiten:** Betrifft das ADR ein neues Paket, eine Action, ein Image oder ein Pipeline-Werkzeug, gehören die Aufnahme-Prüfung und die Verifikation gegen die offizielle Registry (CLAUDE.md Abschnitt 5, Slopsquatting) in den Text.
- **Ablösung:** Ersetzt das ADR ein älteres, im alten ADR den Status auf „Abgelöst durch ADR-NNN" setzen und das dem Nutzer nennen.
- Sprache Deutsch mit echten Umlauten im Text; Zeilen wie in den bestehenden ADRs umbrechen.
