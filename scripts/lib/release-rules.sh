# shellcheck shell=bash
# =============================================================================
# Pruefregeln fuer die Staging-Freigabe deploy/staging.json (ADR-017,
# E-5-145, E-5-150). Bibliothek: wird von einem Einstieg per "source"
# geladen und setzt beim Laden nur Konstanten.
#
# Warum eine Bibliothek: Dieselben Regeln gelten an drei Stellen:
#   - im Pull Request auf die Datei selbst (jq auf dem Runner, PR 4a),
#   - im Release-Workflow und
#   - auf dem Server auf den Predicate des verifizierten Freigabe-Nachweises
#     (gh ... --jq, also gojq; der Server hat kein jq, E-5-143).
# Sie stehen deshalb als EIN jq-Programm an EINER Stelle.
#
# Gemeinsamer Sprachkern (E-5-150): jq nutzt Oniguruma-Regex, gojq RE2. Das
# Programm verwendet nur, was beide gleich verstehen: einfache Regex ohne
# Rueckverweise und Lookaround, keys, type, error, Zeichenketten-Verkettung.
# Nicht verwenden: input_filename, $__loc__, tostring auf Zahlen (jq 1.7
# behaelt das Zahl-Literal, gojq nicht), "and"/"or" mit Seiteneffekten.
#
# Einstiege:
#   scripts/verify-release-file.sh   Datei im Repository (CI)
#   scripts/test-release-file.sh     Rot-Faelle gegen verify-release-file.sh
#
# Vertrag von RELEASE_RULES:
#   Eingabe  das Freigabe-Objekt (die Datei bzw. der Predicate)
#   Ausgabe  bei Erfolg genau drei Zeilen "<schluessel><TAB><referenz>" in
#            der Reihenfolge api, nginx, lego (mit jq -r bzw. gh --jq)
#   Fehler   error("<grund>"): kein Teilergebnis, Exit ungleich 0
# Der Aufrufer prueft zusaetzlich, dass genau diese drei Zeilen kamen: Eine
# leere Eingabe erzeugt in jq keine Ausgabe und keinen Fehler (fail open).
# =============================================================================

# Paketnamen stehen in Kleinbuchstaben, wie GHCR sie fuehrt, und nur im
# Programm selbst (eine Quelle der Wahrheit).
readonly RELEASE_RULES='
def fail($grund): error("Freigabe ungueltig: " + $grund);
def ref_ok($paket):
  if type == "string"
  then test("^ghcr\\.io/xxxcoder999xxx/" + $paket + "@sha256:[0-9a-f]{64}$")
  else false
  end;
if type != "object" then fail("Wurzel ist kein Objekt")
elif keys != ["environment", "images", "schema"]
  then fail("Wurzel muss genau die Schluessel schema, environment, images haben")
elif (.schema | type) != "number" then fail("schema muss eine Zahl sein")
elif .schema != 1 then fail("schema wird nicht unterstuetzt (erwartet 1)")
elif .environment != "staging" then fail("environment muss staging sein")
elif (.images | type) != "object" then fail("images ist kein Objekt")
elif (.images | keys) != ["api", "lego", "nginx"]
  then fail("images muss genau die Schluessel api, nginx, lego haben")
elif (.images.api | ref_ok("identity-service") | not)
  then fail("images.api ist keine Referenz auf identity-service per Digest")
elif (.images.nginx | ref_ok("identity-service-nginx") | not)
  then fail("images.nginx ist keine Referenz auf identity-service-nginx per Digest")
elif (.images.lego | ref_ok("identity-service-lego") | not)
  then fail("images.lego ist keine Referenz auf identity-service-lego per Digest")
else
  ("api\t" + .images.api),
  ("nginx\t" + .images.nginx),
  ("lego\t" + .images.lego)
end
'
