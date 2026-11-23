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

# --- Freigabe-Bundle und Freigabe-Nachweis (ADR-017, PR 4b) -------------------

# Paket, Tag und signierender Workflow der Freigabe. Der Tag zeigt immer auf
# die neueste Freigabe; der Server prueft per Tag und arbeitet danach nur
# noch mit dem verifizierten Digest (gemessen am 2026-11-23).
readonly RELEASE_IMAGE_NAME="ghcr.io/xxxcoder999xxx/identity-service-release"
readonly RELEASE_TAG="staging"
readonly RELEASE_WORKFLOW="release-staging.yml"
readonly RELEASE_PREDICATE_TYPE="https://github.com/xXxCoder999xXx/identity-service/release/v1"

# Feste Dateiliste des Bundles (E-5-155): nur Daten, keine Skripte. Ein
# Release darf seine eigenen Pruefer nicht mitbringen (E-5-117).
# docker/nginx/Dockerfile ist die Quelle des fremden Images fuer die
# Gegenprobe des Servers (E-5-132). Der Abgleich mit dem Pfadfilter von
# release-staging.yml und mit nginx/snippets/ steht in
# scripts/test-release-file.sh.
readonly -a RELEASE_FILES=(
  "deploy/staging.json"
  "compose.yaml"
  "compose.staging.yaml"
  "nginx.staging.conf"
  "nginx/snippets/http-common.conf"
  "nginx/snippets/limits.conf"
  "nginx/snippets/proxy-api.conf"
  "nginx/snippets/security-headers.conf"
  "nginx/snippets/tls.conf"
  "docker/nginx/Dockerfile"
)

# Liest aus der Ausgabe von "gh attestation verify --format json" (genau ein
# verifizierter Freigabe-Nachweis) die Fakten fuer Aktualitaet und Deploy:
#   subject  sha256:<64 hex>  Digest des Bundles (vom Nachweis gedeckt)
#   run      Run-ID aus runInvocationURI (Fulcio, E-5-146)
#   attempt  Versuch des Laufs
#   commit   sourceRepositoryDigest (Commit auf main)
#   api, nginx, lego  aus dem Predicate, geprueft mit RELEASE_RULES
# Feldnamen gemessen am 2026-11-23 (runInvocationURI) bzw. aus sigstore-go
# (sourceRepositoryDigest). Fehlt ein Feld oder hat es eine andere Form,
# bricht das Programm ab (fail closed). Kein capture(): benannte Gruppen
# schreiben jq und gojq verschieden.
RELEASE_FACTS='
if type != "array" then error("Freigabe-Nachweis: Ausgabe ist keine Liste")
elif length != 1 then error("Freigabe-Nachweis: erwartet genau einen Nachweis, gefunden " + (length | tostring))
else
  .[0].verificationResult as $v
  | ($v.signature.certificate.runInvocationURI // "") as $uri
  | ($v.signature.certificate.sourceRepositoryDigest // "") as $commit
  | ($v.statement.subject // []) as $subject
  | if ($uri | type) != "string"
      or ($uri | test("^https://github\\.com/xXxCoder999xXx/identity-service/actions/runs/[1-9][0-9]*/attempts/[1-9][0-9]*$") | not)
      then error("Freigabe-Nachweis: runInvocationURI fehlt oder hat eine unerwartete Form")
    elif ($commit | type) != "string" or ($commit | test("^[0-9a-f]{40}$") | not)
      then error("Freigabe-Nachweis: sourceRepositoryDigest fehlt oder ist keine Commit-SHA")
    elif ($subject | type) != "array" or ($subject | length) != 1
      then error("Freigabe-Nachweis: erwartet genau ein subject")
    elif ($subject[0].digest.sha256 | type) != "string"
      or ($subject[0].digest.sha256 | test("^[0-9a-f]{64}$") | not)
      then error("Freigabe-Nachweis: subject hat keinen sha256-Digest")
    else
      ("subject\tsha256:" + $subject[0].digest.sha256),
      ("run\t" + ($uri | split("/") | .[-3])),
      ("attempt\t" + ($uri | split("/") | .[-1])),
      ("commit\t" + $commit),
      ($v.statement.predicate | '"${RELEASE_RULES}"')
    end
end
'
readonly RELEASE_FACTS
