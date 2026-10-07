# ADR-004: Öffentliches Repository für native Sicherheitsfunktionen

- **Status:** Akzeptiert
- **Datum:** 2026-07-16

> Nachträglich niedergeschrieben am 2026-10-07. Die Entscheidung fiel in
> Sitzung 2 und ist dort als „geschrieben, akzeptiert" vermerkt; die
> ursprüngliche Datei wurde nie ins Repository aufgenommen. Grundlage dieser
> Fassung sind `docs/sitzungen/sitzung-02.md` und der Kopf von
> `.github/workflows/codeql.yml`. Was dort nicht steht, ist unten als nicht
> überliefert gekennzeichnet.

## Kontext

Phase 2 verlangt statische Sicherheitsanalyse (SAST) und Schutz vor
versehentlich eingecheckten Geheimnissen, bevor Fachlogik entsteht. GitHub
bietet dafür CodeQL, Secret Scanning und Push Protection. Für private
Repositories setzen diese Funktionen eine Lizenz (GitHub Code Security)
voraus; ohne sie schlägt der Ergebnis-Upload von CodeQL fehl, und die Nutzung
wäre lizenzwidrig. Für öffentliche Repositories sind sie kostenlos.

Kräfte:

- **Minimale Abhängigkeiten (6.2a):** Jedes zusätzliche Sicherheitswerkzeug ist
  selbst eine Abhängigkeit mit Aufnahme-Prüfung und Pflege.
- **Sicherheit ab Tag 1:** Die Prüfungen sollen laufen, bevor es Bestand gibt.
- **Offenlegung:** Ein öffentliches Repository zeigt Code, Historie,
  Pipeline-Definitionen, Entscheidungen und Sitzungsberichte jedem.

## Entscheidung

Wir führen das Repository öffentlich und nutzen CodeQL, Secret Scanning und
Push Protection als native, kostenlose Funktionen der Plattform.

## Betrachtete Alternativen

- **Privates Repository mit Kompensationswerkzeugen:** verworfen, weil es neue
  Abhängigkeiten bedeutet hätte. Welche Werkzeuge im Einzelnen verglichen
  wurden, ist nicht überliefert.
- **Privates Repository mit Lizenz (GitHub Code Security):** in `codeql.yml`
  als zulässiger Weg genannt. Eine Bewertung der Kosten ist nicht überliefert.

## Begründung

Die öffentliche Sichtbarkeit liefert alle drei Funktionen ohne ein einziges
zusätzliches Werkzeug und ohne Lizenzkosten. Das folgt dem Projektprinzip
minimaler Abhängigkeiten und der Plattformwahl aus ADR-001.

Die Offenlegung ist vertretbar, weil das Projekt keine Geheimnisse im
Repository führt (6.3.3) und die Sicherheit nicht auf Unkenntnis des Aufbaus
beruht: Härtung, Pins und Regeln sind so angelegt, dass sie auch dann tragen,
wenn ein Angreifer sie lesen kann.

## Konsequenzen

Positiv:

- CodeQL läuft seit dem 16.07.2026 als Advanced Setup
  (`.github/workflows/codeql.yml`) bei jedem Push, jedem Pull Request und
  wöchentlich; der Job `Analyse (C#)` ist Pflicht-Check im Ruleset.
- Keine zusätzliche Abhängigkeit für SAST.

Negativ und neue Pflichten:

- **Alles im Repository ist öffentlich und bleibt es:** Code, Git-Historie,
  Pull Requests, Workflow-Protokolle, ADRs und Sitzungsberichte. Die Historie
  gilt als für immer veröffentlicht; bei einem versehentlich eingecheckten
  Geheimnis wird zuerst rotiert, dann aufgeräumt.
- **Fremde können Pull Requests aus Forks öffnen.** Daraus folgen die Regeln:
  `pull_request` statt `pull_request_target`, keine Secrets für Fork-PRs,
  minimale Rechte je Job, vom Einreicher kontrollierter Text nie in ein
  `run:`.
- **Aktivierungs-Gate:** `codeql.yml` darf nur in einem öffentlichen oder
  lizenzierten Repository liegen. Wird das Repository privat gestellt, entfällt
  die Grundlage dieser Entscheidung.
- **Die Funktionen müssen eingeschaltet sein, nicht nur verfügbar.** Secret
  Scanning und Push Protection waren bis zum 07.10.2026 in den
  Repository-Einstellungen nicht aktiviert, obwohl Sitzung 2 die Aktivierung
  vorsah; zwei der drei Funktionen, mit denen diese Entscheidung begründet
  wurde, liefen also knapp drei Monate nicht. Seit dem 07.10.2026 sind Secret
  Scanning, Push Protection, Dependabot-Alerts und Dependabot Security Updates
  aktiv (über die API geprüft). Der Stand dieser Einstellungen steht in keiner
  Datei des Repositories und ist nach Änderungen an den Einstellungen erneut zu
  prüfen.

Auslöser für eine Neubewertung: Das Projekt soll Inhalte aufnehmen, die nicht
öffentlich sein dürfen (zum Beispiel kundenspezifische Logik oder
vertrauliche Betriebsdetails); dann ist zwischen Lizenz und
Kompensationswerkzeugen neu zu entscheiden.
