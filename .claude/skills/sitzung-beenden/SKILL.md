---
name: sitzung-beenden
description: Beendet eine Arbeitssitzung im IdentityService-Projekt und schreibt den Sitzungsbericht mit Roadmap nach docs/sitzungen/. Verwenden, wenn der Nutzer "Sitzung beenden", "Bericht" oder Ähnliches sagt.
---

# Sitzung beenden

Ziel: ein Bericht, auf dem die nächste Sitzung ohne Rückfragen aufsetzen kann. Dieser Skill ist die einzige Stelle, an der das Berichtsformat beschrieben ist.

## Ablauf

1. **Nummer und Datum.** In `docs/sitzungen/` die höchste vorhandene Nummer bestimmen; der neue Bericht ist `sitzung-NN.md` mit der nächsten Nummer (zweistellig). Datum im Format `TT.MM.JJJJ`.
2. **Fakten sammeln.** Aus dem Gespräch dieser Sitzung und aus `git log` (gemergte PRs, Commits auf dem aktuellen Branch). Nur aufnehmen, was in dieser Sitzung tatsächlich geschehen ist. Nichts schätzen und nichts schöner darstellen: Nicht Geprüftes steht unter „Offene Punkte", nicht unter „Erledigt".
3. **Lehrstoff erstellen.** Vor dem Bericht aus den Konzepten der Sitzung eine HTML-Seite als Artifact veröffentlichen (Artifacts-Connector), Titel `Lehrstoff: <Thema der Sitzung>`. Grundlage ist immer `lehrstoff-vorlage.html` in diesem Ordner: Tokens, Schriften und Bausteine übernehmen; Bausteine weglassen, wiederholen oder neue aus denselben Tokens bauen ist erlaubt, wenn es das Design weiterentwickelt. Keine externen Schriften, Skripte oder Bilder. Die Seite entsteht als Datei im Scratchpad, nie im Repository, und wird von dort veröffentlicht. Den Link dem Nutzer in der Zusammenfassung (Schritt 5) **eigens nennen**; er kommt auch in den Bericht (Abschnitt 1 und „Vor oder in der Sitzung zu verstehen"). Ist kein Artifacts-Connector verfügbar, fragen, wie der Lehrstoff stattdessen geliefert werden soll; nichts eigenmächtig ins Repository legen.
4. **Bericht schreiben** nach dem Aufbau unten, auf Deutsch mit echten Umlauten.
5. **Dem Nutzer zusammenfassen**, was im Bericht steht und was als Erstes in der nächsten Sitzung ansteht.
6. **Nicht selbst committen.** Vorschlagen: Branch `docs/sitzung-NN`, PR-Titel `docs: add session report NN`. Commit und Push nur auf ausdrückliche Aufforderung (CLAUDE.md Abschnitt 6).

## Aufbau des Berichts

```markdown
# Sitzungsbericht Sitzung N

**Datum:** TT.MM.JJJJ
**Phase:** <Schritt und Stand, z. B. "Schritt 4b, Teil 4 abgeschlossen">
**Vorgänger:** sitzung-NN.md (abgeschlossen TT.MM.JJJJ)

---

## 1. Erledigt
<Unterabschnitte 1.1, 1.2, ... je Arbeitspaket; mit PR-Nummern und dem, was verifiziert wurde>

## 2. Gelernt
<Stichpunkte: je ein Satz, der auch ohne Sitzungskontext verständlich ist>

## 3. Entscheidungen (ADR-Kandidaten)
| Code | Entscheidung | Kernbegründung |
|---|---|---|
| **E-<Schritt>-<n>** | ... | ... |

## 4. Offene Punkte
<alles Unfertige, Ungeprüfte, bewusst Akzeptierte; mit Pfaden und Branch-Namen>

## 5. Phasen-Status und Gates
<Stand im Phasenplan; ausgelöste oder näher rückende Themen aus CLAUDE.md Abschnitt 8 als Tabelle>

## 6. Technische Referenz (für Folgesitzungen)
<Digests mit Stand-Datum, UIDs, Pfade, Fallstricke, die Zeit gekostet haben>

---

# Roadmap Sitzung N+1

## 1. <nächster Schritt>
<Warum genau dieser Schritt der nächste ist; Bausteine>

## 2. ... weitere Schritte in Reihenfolge

## <n>. Vor oder in der Sitzung zu verstehen (vor Code)
<Konzepte, je mit zwei bis drei Sätzen>

## <n+1>. Optionale Vorbereitung
```

## Regeln für den Inhalt

- **Entscheidungen** tragen Codes `E-<Schritt>-<n>`, fortlaufend innerhalb des Schritts. ADR-Kandidaten als solche kennzeichnen; für die Ausarbeitung gibt es den Skill `/adr`.
- **Digests, SHAs, Versionen** nur aufnehmen, wenn sie in dieser Sitzung aus Registry bzw. Primär-Repo aufgelöst wurden, mit Datum.
- **Keine Geheimnisse:** keine Schlüssel- oder Zertifikatsinhalte, keine Tokens, keine Connection Strings, keine personenbezogenen Daten.
- **Selbsttragend:** Der Bericht verweist nicht auf „den Chat". Wer nur den Bericht liest, muss den Stand verstehen.
- **Roadmap:** Der erste Punkt ist der Einstieg der nächsten Sitzung (`/sitzung-starten` beginnt dort). Jeder Punkt nennt seine Begründung.
- **Lehrstoff:** gegliedert nach Lernzielen; je Konzept Warum, Funktionsweise, Alternativen mit Trade-offs und ein „Merke"-Satz; echte Fehler und Lehren der Sitzung als Beispiele; am Ende Merksätze und ein Spickzettel der Befehle mit Platzhaltern in Großbuchstaben; Diagramm (Inline-SVG mit den Klassen der Vorlage), wo ein Ablauf erklärt wird; Inhaltsverzeichnis oben; Messergebnisse grün/rot nur, wenn sie gemessen wurden. Keine Quizfragen (CLAUDE.md Abschnitt 1). Dieselben Geheimnis-Regeln wie für den Bericht, zusätzlich keine IP-Adressen, Hostnamen, Benutzernamen und E-Mail-Adressen, weil das Dokument außerhalb des Repositorys liegt.
