# ADR-010: Image-Veröffentlichung in GHCR mit Herkunftsnachweis und Stückliste

- **Status:** Akzeptiert
- **Datum:** 2026-10-07

## Kontext

Schritt 4 ist abgeschlossen: Die Pipeline baut das Container-Image, prüft den
Stack im Production-Modus und scannt das Image (ADR-009). Das Image verlässt
den Runner aber nie. Schritt 5 (Auslieferung) beginnt damit, es an einem Ort
abzulegen, von dem ein späteres Staging es beziehen kann.

Kräfte:

- **Dasselbe Image überall:** Gebaut wird einmal; jede Umgebung erhält
  denselben Digest. Getestet sein muss genau das Image, das ausgeliefert wird.
- **Herkunft muss prüfbar sein (A03):** Wer ein Image aus der Registry startet,
  muss nachweisen können, aus welchem Repository, welchem Commit und welchem
  Lauf es stammt. Provenance beweist Herkunft, nicht Gutartigkeit.
- **Keine langlebigen Secrets (6.2b):** weder für die Registry noch für die
  Signatur.
- **Minimale Rechte je Job:** Bisher hat kein Job der Pipeline Schreibrechte.
- **Minimale Abhängigkeiten (6.2a):** jede neue Action ist eine
  Sicherheitsentscheidung.
- Ein Ziel für Staging ist noch nicht entschieden (eigener Server oder
  Cloud-Dienst).

## Entscheidung

Wir veröffentlichen das Image bei jedem Merge nach `main` in der GitHub
Container Registry und versehen es mit einem signierten Herkunftsnachweis und
einer Stückliste über GitHub Artifact Attestations (`actions/attest`); ein
Prüf-Gate im selben Lauf verifiziert beides, und ein Deploy findet noch nicht
statt.

Im Einzelnen:

- Ein eigener Workflow, ausgelöst nur durch Pushes nach `main`, nie durch Pull
  Requests.
- Ein einziger Job mit genau diesen Rechten: `contents: read`,
  `packages: write`, `id-token: write`, `attestations: write`.
- Reihenfolge im Job: bauen, Smoke-Test, Image-Scan, veröffentlichen,
  Herkunftsnachweis, Stückliste, Prüf-Gate. Veröffentlicht wird das Image, das
  Smoke-Test und Scan bestanden hat.
- Das Image wird über seinen Digest und den Commit bezeichnet, nie über
  `latest`.
- Anmeldung an der Registry mit dem Token des Laufs; Veröffentlichen und
  Verifizieren mit Werkzeugen des Runners (`docker`, `gh`).

## Betrachtete Alternativen

- **cosign (Sigstore) statt GitHub Artifact Attestations:** unabhängig von
  GitHub und weit verbreitet, darunter dieselbe Signaturtechnik. Verworfen,
  weil es ein weiteres Werkzeug in die Pipeline bringt, das zur Laufzeit
  geladen wird, während die Attestations vom Plattformbetreiber selbst stammen
  (ADR-001) und sich mit dem vorhandenen `gh` prüfen lassen.
- **Die Actions `actions/attest-build-provenance` und `actions/attest-sbom`:**
  Die Prüfung ihrer Definitionen ergab, dass beide zusammengesetzte Actions
  sind, die intern `actions/attest` aufrufen, jeweils über einen eigenen SHA.
  `actions/attest` nimmt selbst eine Stückliste entgegen. Verworfen zugunsten
  der einen Action: eine Abhängigkeit statt zweier Hüllen mit zwei
  mitgeschleppten Pins.
- **Image zwischen Jobs weiterreichen** (in der CI bauen, in einem zweiten Job
  veröffentlichen): verworfen, weil es eine weitere Action für das Hoch- und
  Herunterladen bräuchte. Stattdessen laufen Prüfung und Veröffentlichung in
  einem Job.
- **Nach erfolgreicher CI neu bauen und veröffentlichen:** verworfen, weil
  dann ein Image in die Registry ginge, das selbst nie getestet wurde.
- **Zuerst ein Staging-Ziel wählen** (eigener Server oder Cloud-Dienst):
  zurückgestellt. Registry, Nachweis und Prüf-Gate werden für beide Wege
  gleichermaßen gebraucht.

## Begründung

Die Veröffentlichung mit Nachweis ist der Teil der Auslieferung, der vom Ziel
unabhängig ist. Sie macht aus dem Grundsatz „dasselbe Image überall" eine
prüfbare Eigenschaft: Ein späterer Deploy kann den Digest verlangen und den
Nachweis verifizieren, statt einem Namen zu vertrauen.

Aufnahme-Prüfung (6.2a, 6.3.2), Stand 07.10.2026, aus dem Primär-Repository
gelesen:

- `actions/attest`, Besitzer ist die GitHub-Organisation `actions`, Lizenz MIT,
  angelegt am 20.02.2024, nicht archiviert, letzter Push am 06.10.2026.
- Release `v4.2.2` vom 04.08.2026; der Tag zeigt auf den Commit
  `1e69f48acb82d1966a394da916b4c1698aa569d6` (per `git ls-remote` gegen das
  offizielle Repository aufgelöst).
- Die Action läuft als JavaScript auf dem Runner (`node24`) und ruft selbst
  keine weitere Action auf.
- Eine Recherche nach Sicherheitsvorfällen bei den Attest-Actions und bei
  Sigstore ergab für 2026 keinen Treffer.

Die Signatur braucht keinen gespeicherten Schlüssel: Der Lauf weist sich mit
einem kurzlebigen Identitätsnachweis von GitHub aus und erhält dafür ein
Zertifikat, das nach Minuten verfällt.

## Konsequenzen

Positiv:

- Jedes Image in der Registry ist auf Commit und Lauf zurückführbar.
- Kein gespeichertes Geheimnis für Registry oder Signatur.
- Was veröffentlicht wird, hat Smoke-Test und Scan bestanden.
- Die Stückliste, die der Scanner ohnehin erzeugt, wird zum ausgelieferten
  Artefakt.

Negativ und neue Pflichten:

- **Der erste Job mit Schreibrechten.** Er darf nie durch einen Pull Request
  auslösbar werden und führt keinen vom Einreicher kontrollierten Text aus.
- **Das Image und sein Nachweis werden öffentlich.** Für öffentliche
  Repositories landet der Nachweis laut Recherche in einem öffentlichen,
  unveränderlichen Protokoll (Sigstore). Repository, Workflow und Commit sind
  dort dauerhaft einsehbar. Das Image darf deshalb nie ein Geheimnis
  enthalten; die Konfiguration kommt von außen.
- **Noch nicht belegt** und erst durch den ersten Lauf zu klären: ob GHCR das
  Paket beim ersten Push öffentlich oder privat anlegt, und ob das Prüf-Gate
  mit `gh` auf dem Runner wie geplant arbeitet.
- **Der Nachweis ist nur so viel wert wie seine Prüfung.** Solange kein Deploy
  ihn verlangt, schützt er niemanden. Das Prüf-Gate im Lauf enthält deshalb
  eine Gegenprobe: Die Verifikation eines fremden Images ohne Nachweis aus
  diesem Repository muss scheitern, sonst wird der Lauf rot.
- **Der Workflow läuft nicht bei Pull Requests.** Fehler zeigen sich erst nach
  dem Merge; ein fehlerhaftes Image gelangt wegen der Reihenfolge trotzdem
  nicht in die Registry.
- **Doppelte Schritte vermeiden:** Die Erzeugung der Wegwerf-Zertifikate wird
  vorab aus `ci.yml` in ein Skript ausgelagert, das CI und Veröffentlichung
  gemeinsam nutzen.
- **Jeder Merge erzeugt ein Image.** Eine Aufräumregel für die Registry ist
  später zu entscheiden.
- **Pin-Pflege:** Die Action wird per SHA gepinnt; Dependabot pflegt sie im
  Ökosystem `github-actions`.
- Der Name in der Registry wird kleingeschrieben.

Auslöser für eine Neubewertung: ein Wechsel der Plattform oder ein Staging-Ziel
außerhalb von GitHub, das die Attestations nicht verifizieren kann (dann
cosign); ein Sicherheitsvorfall bei der Action oder bei Sigstore; der Bedarf,
das Repository privat zu führen (ADR-004).
