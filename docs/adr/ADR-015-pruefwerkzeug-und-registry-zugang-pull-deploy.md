# ADR-015: Prüfwerkzeug und Registry-Zugang für den Pull-Deploy

- **Status:** Vorgeschlagen
- **Datum:** 2026-10-29

## Kontext

ADR-011 legt fest, dass der Staging-Server Images selbst zieht und nur startet,
was die Prüfung des Herkunftsnachweises besteht (E-5-17), und dass er GHCR mit
einem klassischen Token eines eigenen Maschinenkontos liest (E-5-21). Offen
blieben zwei Folgeentscheidungen: mit welchem Werkzeug der Server die
Nachweise prüft und wo das Token auf dem Server liegt.

Auslöser: Der Pull-Deploy ist fristgebunden. Ohne ihn gibt es keinen
API-Neustart nach der Zertifikatserneuerung (`restart_api` in
`scripts/renew-api-certificate.sh` ist ein Platzhalter), und die erste
Erneuerung steht spätestens am 27.12.2026 an.

Wirkende Kräfte:

- **Eine Quelle der Wahrheit:** Die Prüfregeln stehen heute in
  `scripts/verify-attestations.sh` und sind in der CI mit Gegenproben belegt
  (ADR-010). Eine zweite Implementierung auf dem Server könnte von ihnen
  abweichen.
- **Lieferkette (A03):** Das Prüfwerkzeug ist selbst eine Abhängigkeit, und
  zwar eine sicherheitskritische: Ein fehlerhafter Prüfer lässt fremde Images
  durch.
- **Least Privilege:** Kein Dritter soll dauerhaft Code als root auf dem
  Server ausführen dürfen; das Token soll im Ruhezustand nur für root lesbar
  sein.
- **Fail closed:** Ein veralteter Prüfer darf nicht unbemerkt weiterprüfen.
- **Kein Mithören:** Ein Prüfwerkzeug auf dem Server soll keine ausgehenden
  Verbindungen aufbauen, die für die Prüfung nicht nötig sind.

Recherche vom 29.10.2026:

- GHCR akzeptiert laut GitHub-Dokumentation weiterhin nur klassische Tokens.
  Der Auslöser für eine Neubewertung von ADR-011 („fein abgestufte Tokens für
  GHCR“) ist nicht eingetreten.
- `gh attestation verify` hatte 2026 vier einschlägige Lücken:

| Hinweis | Inhalt | Behoben ab |
|---|---|---|
| GHSA-8xvp-7hj6-mcj9 (CVE-2026-48501, CVSS 7.4) | Token wurde an TUF-Spiegel und fremde Hosts gesendet | 2.93.0 |
| GHSA-mm27-mwq9-fr5g (CVE-2026-64655) | Regex-Sonderzeichen in `--signer-repo` und `--signer-workflow` nicht maskiert | 2.97.0 |
| GHSA-wjmr-j3rp-mh2g | `--signer-workflow` nur am Anfang verankert (Präfix genügte) | 2.102.0 |
| GHSA-4mq3-hpgx-9cx8 | `--source-ref` ohne Beachtung der Groß- und Kleinschreibung | 2.102.0 |

- `scripts/verify-attestations.sh` war gegen die drei Prüf-Lücken bereits
  geschützt: Es vergleicht `buildSignerURI` und `sourceRepositoryRef` aus dem
  verifizierten Nachweis zusätzlich exakt (`grep --fixed-strings
  --line-regexp`, groß-/kleinschreibungsgenau) mit den erwarteten Werten.
- Debian trixie liefert `gh` 2.46.0. Diese Version ist von allen vier Lücken
  betroffen und laut `cli/cli` wegen abgekündigter APIs nicht funktionsfähig;
  das Projekt führt das Debian-Paket als inoffiziell.
- `gh` sendet Telemetrie an GitHub (Befehl, Flags, Betriebssystem,
  `device_id` u. a.). Abschaltbar per `GH_TELEMETRY=false` oder
  `DO_NOT_TRACK=true`; laut Dokumentation haben die Umgebungsvariablen Vorrang
  vor der Konfiguration.

## Entscheidung

Wir prüfen die Nachweise auf dem Server mit `gh` (mindestens 2.102.0) und
demselben `scripts/verify-attestations.sh` wie in der CI, installieren `gh`
als geprüftes Release-Archiv aus `cli/cli` und halten das GHCR-Token in einer
nur für root lesbaren Credential-Datei, die nur während des Pulls genutzt
wird.

Teilentscheidungen:

| Code | Inhalt |
|---|---|
| E-5-105 | GHCR-Token in `/etc/credstore/…` (`root:root 0600`); die Deploy-Unit lädt es per `LoadCredential`, meldet sich mit `docker login --password-stdin` in einem temporären `DOCKER_CONFIG`-Ordner an, zieht per Digest und löscht den Ordner danach. Kein dauerhaftes `docker login` |
| E-5-106 | Prüfwerkzeug auf dem Server ist `gh attestation verify` über `scripts/verify-attestations.sh`; die Prüfregeln bleiben an einer Stelle |
| E-5-107 | Installation von `gh` als Release-Archiv: Herkunft lokal mit `gh attestation verify --repo cli/cli --deny-self-hosted-runners --source-digest <Tag-Commit>` belegen, Hash auf dem Server vergleichen, nur `bin/gh` entpacken, `install -m 0755 -o root -g root` nach `/usr/local/bin`, Hash vor und nach `install` vergleichen. Das Deploy-Skript lehnt jede Version unter der eingetragenen Mindestversion ab (heute 2.102.0) |
| E-5-108 | Die Deploy-Unit setzt `GH_TELEMETRY=false` und `DO_NOT_TRACK=true` |

## Betrachtete Alternativen

1. **`cosign` statt `gh`:** verworfen. Eigenständiges Sigstore-Werkzeug, aber
   eine zweite Implementierung derselben Prüfregeln neben
   `verify-attestations.sh`. Beide könnten auseinanderlaufen; die Gegenproben
   der CI würden den Server nicht mehr abdecken.
2. **Debian-Paket `gh`:** verworfen. Version 2.46.0, von allen vier Lücken
   betroffen und laut Herausgeber nicht funktionsfähig.
3. **Offizielle apt-Quelle `cli.github.com/packages`:** verworfen, aber
   zweitbeste Option. Updates kämen bequem per `apt`, doch jedes Paket dieser
   Quelle führt bei der Installation Maintainer-Skripte als root aus. Der
   Paketschlüssel von GitHub erhielte damit dauerhaft root-Rechte auf dem
   Server.
4. **Dauerhaftes `docker login` des Docker-Benutzers:** verworfen. Docker legt
   das Token in `~/.docker/config.json` nur Base64-kodiert ab; jeder Prozess,
   der als Docker-Benutzer läuft, könnte es lesen, auch zwischen den Deploys.
5. **Prüfsummen-Datei des Releases statt Herkunftsnachweis:** verworfen. Sie
   stammt aus derselben Quelle wie das Archiv und belegt deshalb keine
   Herkunft.
6. **Herkunftsprüfung nur mit `--repo`:** verworfen. Gemessen: `cli/cli`
   startet Releases per Dispatch vom Branch `trunk`; der Nachweis trägt
   `refs/heads/trunk`, nicht den Tag. Ohne `--source-digest` hätte jedes
   ältere Archiv aus demselben Workflow die Prüfung bestanden, auch eines mit
   bekannter Lücke.

## Begründung

- **Eine Quelle der Wahrheit:** Server und CI prüfen mit demselben Skript. Die
  in der CI belegten Gegenproben (fremdes Image, falscher Workflow, falscher
  Branch) gelten damit auch für das Ziel.
- **Defense in Depth belegt:** Die exakte Nachprüfung im Skript hätte die drei
  Prüf-Lücken von `gh` abgefangen. Die Mindestversion schließt sie zusätzlich
  im Werkzeug selbst.
- **Herkunft vollständig belegt (gemessen am 29.10.2026):**

| Prüfung | Ergebnis |
|---|---|
| Version | v2.103.3 (26.10.2026), neuestes Release laut `gh release view --repo cli/cli` |
| Tag-Commit | `63837fb778d6a39f02be0ce76ff89f2bc8d74bdc` (`git ls-remote`, leichtgewichtiger Tag) |
| Nachweis | Repository `cli/cli`, Workflow `.github/workflows/deployment.yml@refs/heads/trunk`, Runner `github-hosted`, Build-Commit gleich Tag-Commit (`--source-digest`), Subjekt `gh_2.103.3_linux_amd64.tar.gz` enthalten |
| Archiv lokal und auf dem Server | SHA-256 `4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d` (`sha256sum -c`: OK) |
| Archivinhalt | alle Pfade unter `gh_2.103.3_linux_amd64/`, kein absoluter Pfad, kein `../` |
| Programmdatei vor und nach `install` | SHA-256 `b768184570b12536be4ac1528893f6340d1c6a7b40b56ad45bca9cd0e87ad34d` |
| Installiert | `/usr/local/bin/gh`, `root:root 0755`, `gh version 2.103.3`; kein weiteres `gh` in `/usr/bin` |

- **Slopsquatting:** Quelle ist das Primär-Repository `cli/cli` der
  Organisation `cli` (GitHub); Name, Herausgeber und Release wurden dort
  geprüft, nicht über Dritte. Das lokale Prüfwerkzeug war `gh` 2.102.0, also
  selbst nicht von den Lücken betroffen.
- **Least Privilege:** Beim Release-Archiv erhält kein Dritter dauerhaft
  root-Rechte; nur root kann `/usr/local/bin/gh` ändern. Das Token liegt im
  Ruhezustand nur root-lesbar, wie die Ping-URL des Totmannschalters
  (E-5-104).
- **Fail closed:** Mit der Mindestversion blockiert ein veraltetes `gh` den
  Deploy, statt ihn still zu erlauben.

## Konsequenzen

**Positiv**

- Server und CI teilen eine Prüflogik; Änderungen wirken an beiden Stellen.
- Neue Lücken in `gh` lassen sich durch Anheben der Mindestversion sofort
  wirksam machen.
- Das GHCR-Token ist nur während des Pulls außerhalb einer root-Datei
  vorhanden.

**Negativ und akzeptierte Risiken**

- Updates von `gh` sind Handarbeit (Archiv laden, Herkunft prüfen,
  installieren). Ohne Pflege blockiert die Mindestversion erst, wenn sie
  angehoben wird; zwischen Bekanntwerden einer Lücke und dem Anheben läuft die
  alte Version.
- `gh` ist ein großes Werkzeug (rund 41 MB) mit vielen Befehlen, von denen der
  Server nur `attestation verify` braucht.
- Während des Pulls liegt das Token im temporären `DOCKER_CONFIG`-Ordner;
  dessen Rechte und Ort legt die Deploy-Unit fest.

**Neue Pflichten**

- Sicherheitshinweise von `cli/cli` beobachten; bei einer Lücke in
  `gh attestation` die Mindestversion anheben und `gh` nach E-5-107 erneuern.
- Die Mindestversion steht an genau einer Stelle (im Deploy-Skript).
- Lokales `gh` (Prüfer für die Installation) ebenfalls mindestens auf der
  Mindestversion halten.

**Folgeentscheidungen**

- Ob `gh attestation verify` auf dem Server ein GitHub-Token braucht und
  welche Rechte; davon hängen die Einstellungen des Maschinenkontos ab.
- `verify-attestations.sh` erwartet die Umgebung eines Runners
  (`GITHUB_REPOSITORY`, `GITHUB_SERVER_URL`, `::group::`) und akzeptiert in
  den Gegenproben jeden Fehler, auch einen Netzfehler. Für den Server muss
  eine Gegenprobe am erwarteten Fehler erkannt werden, sonst ist sie
  fail-open-nah.
- Telemetrie von `gh` in der CI (`ci.yml`, `publish*.yml`) ebenfalls
  abschalten: eigener PR.

**Auslöser für eine Neubewertung**

- GHCR unterstützt fein abgestufte Tokens (dann ADR-011 E-5-21 und E-5-105).
- `cli/cli` bietet ein schlankes, eigenständiges Prüfwerkzeug oder ein per
  Digest gepinntes Image an.
- Eine weitere Lücke in `gh attestation`, die die exakte Nachprüfung im
  Skript nicht abfängt.
- Production: Update-Weg von `gh` (Handarbeit) neu bewerten.
