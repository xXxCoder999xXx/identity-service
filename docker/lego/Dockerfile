# ACME-Client lego als eigenes, minimales Image (ADR-014, E-5-62, E-5-63).
#
# Das offizielle Image goacme/lego dient nur als Quelle der Programmdatei.
# Alpine, git, busybox und dessen Bibliotheken bleiben in der Zwischenstufe
# und gelangen nicht ins fertige Image. Dependabot pflegt beide FROM-Zeilen
# (Eintrag "/docker/lego" in .github/dependabot.yml).
#
# Build-Kontext ist dieser Ordner; die .dockerignore daneben schliesst alles
# aus. Das Image braucht keine Datei aus dem Repository.
#
# Bewusst KEINE "# syntax="-Zeile (Begruendung im Dockerfile der API).

# ---- Quelle der Programmdatei ----
FROM goacme/lego:v5.5.2@sha256:1944e8c36055beec47c7de6f15202b41128be75eea0ffa257f0c14d93c5155fd AS lego

# ---- Laufzeit ----
# static: ohne libc, Shell und Paketmanager; mit CA-Zertifikaten und tzdata.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:18f4cc26c9ffa7f20a359298be7deadac5c607c8e03a02b8119f1a5fc2f82c99

# Bewusst OHNE --chown: Die Datei gehoert root (0755). Der Prozess kann seine
# eigene Programmdatei nicht ueberschreiben.
COPY --from=lego /lego /lego

# Ausdruecklich und als Zahl, obwohl die Basis schon 65532 setzt: Die
# Sicherheit haengt nicht am Tag ":nonroot", und Laufzeitpruefungen wie
# runAsNonRoot koennen eine Zahl ohne /etc/passwd pruefen.
USER 65532:65532

# Kein EXPOSE und kein CMD: Ports, E-Mail, Domain, Webroot und Befehl kommen
# von aussen (compose). Exec-Form ist Pflicht, das Image hat keine Shell.
ENTRYPOINT ["/lego"]
