# nginx als eigenes Image mit Debian-Updates (ADR-016, E-5-125).
#
# Basis ist das gepinnte nginx-unprivileged. Beim Bauen spielt apt die
# Sicherheits- und Punkt-Updates von Debian ein, damit Fixes nicht erst mit
# einem Neubau des Herausgebers ins Image kommen. Dependabot pflegt die
# FROM-Zeile (Eintrag "/docker/nginx" in .github/dependabot.yml) und bleibt
# dort auf dem Stable-Zweig.
#
# Grenzen (ADR-016): Das Ergebnis haengt vom Bauzeitpunkt ab; massgeblich ist
# der veroeffentlichte Digest mit seiner signierten Stueckliste. Die alten
# Paketdateien bleiben verdeckt im Basis-Layer.
#
# Build-Kontext ist dieser Ordner; die .dockerignore daneben schliesst alles
# aus. Das Image braucht keine Datei aus dem Repository: nginx.conf,
# Snippets und Zertifikate kommen zur Laufzeit als schreibgeschuetzte Mounts.
#
# Bewusst KEINE "# syntax="-Zeile (Begruendung im Dockerfile der API).

FROM nginxinc/nginx-unprivileged:1.30.6@sha256:ec0f7ecb1fbd84959ac114e65fb36074ffc97d4d51db0f18ee925162d889dcef

# apt braucht root, nur fuer diesen einen Schritt.
USER 0

# Ein RUN, damit die Paketlisten nie in einem Layer landen.
# - "upgrade" statt "dist-upgrade": nur vorhandene Pakete werden neuer, keines
#   kommt hinzu oder faellt weg.
# - nginx selbst stammt von nginx.org; diese Quelle steht nicht in den
#   Paketquellen des Images (gemessen). Die nginx-Version bestimmt deshalb
#   allein der FROM-Pin.
# - DEBIAN_FRONTEND nur fuer diesen Aufruf, nicht als ENV: sonst bliebe es im
#   Image und erbte sich in jeden Container.
# - Die Echtheit der Pakete prueft apt ueber die signierte InRelease-Datei der
#   Debian-Quellen (debian-archive-keyring), auch ueber http.
RUN DEBIAN_FRONTEND=noninteractive apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get upgrade --yes \
 && rm -rf /var/lib/apt/lists/*

# Zurueck auf den Benutzer der Basis, numerisch: Laufzeitpruefungen wie
# runAsNonRoot lesen die Zahl aus den Image-Metadaten.
USER 101

# Entrypoint, Cmd, Port 8080 und StopSignal erbt das Image unveraendert von
# der Basis.
