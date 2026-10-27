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

# ---- Quelle der Programmdatei und der Mountpunkte ----
FROM goacme/lego:v5.5.2@sha256:1944e8c36055beec47c7de6f15202b41128be75eea0ffa257f0c14d93c5155fd AS lego

# Mountpunkte fuer die Volumes (E-5-80). Das Laufzeit-Image hat keine Shell,
# deshalb entstehen Besitz und Rechte vollstaendig hier und werden unten
# unveraendert uebernommen. Ein leeres Volume uebernimmt beim ersten Einbinden
# Besitz und Rechte aus dem Image (gemessen M1 bis M5, Bericht 23).
# Nur die drei Mountpunkte gehoeren dem Prozess (101), nicht ihr Elternordner
# /data. Konten-Schluessel nur fuer den Besitzer (0700); Zertifikate und
# Webroot liest nginx ueber eigene Mounts (0755).
RUN mkdir -p /mounts/data/accounts /mounts/data/certificates /mounts/webroot \
 && chown 101:101 /mounts/data/accounts /mounts/data/certificates /mounts/webroot \
 && chmod 0755 /mounts/data \
 && chmod 0700 /mounts/data/accounts \
 && chmod 0755 /mounts/data/certificates /mounts/webroot

# ---- Laufzeit ----
# static: ohne libc, Shell und Paketmanager; mit CA-Zertifikaten und tzdata.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:18f4cc26c9ffa7f20a359298be7deadac5c607c8e03a02b8119f1a5fc2f82c99

# Bewusst OHNE --chown: Die Datei gehoert root (0755). Der Prozess kann seine
# eigene Programmdatei nicht ueberschreiben.
COPY --from=lego /lego /lego

# Bewusst OHNE --chown: Es wuerde auch den Elternordner /data dem Prozess
# geben, und COPY eines einzelnen Ordners setzt dessen Rechte neu (0755 statt
# 0700). Beides lokal gemessen. Kopiert wird der Inhalt von /mounts, also
# data/ und webroot/ mit Besitz und Rechten aus der Stufe oben.
COPY --from=lego /mounts/ /

# Ausdruecklich und als Zahl: Laufzeitpruefungen wie runAsNonRoot koennen eine
# Zahl ohne /etc/passwd pruefen. 101 statt der 65532 der Basis, damit Image,
# Mountpunkte und nginx-unprivileged (liest die Zertifikate) dieselbe UID
# haben (E-5-75, E-5-80). Compose setzt sie zusaetzlich.
USER 101:101

# Kein EXPOSE und kein CMD: Ports, E-Mail, Domain, Webroot und Befehl kommen
# von aussen (compose). Exec-Form ist Pflicht, das Image hat keine Shell.
ENTRYPOINT ["/lego"]
