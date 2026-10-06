<#
.SYNOPSIS
    PreToolUse-Hook fuer Claude Code: blockiert Shell-Befehle, die auf
    lokale Geheimnisse zugreifen.

.DESCRIPTION
    Schliesst die Luecke der Berechtigungsregeln in .claude/settings.json:
    Read(...)-Sperren gelten nur fuer die Datei-Werkzeuge, nicht fuer
    Shell-Befehle wie "Get-Content certs\ca\local-dev-ca.key".

    Eingabe:  JSON des Harness auf stdin (tool_input.command).
    Ausgabe:  Exit 0 = erlaubt, Exit 2 = blockiert (Grund auf stderr).

    Sicherheitsgrundsaetze (CLAUDE.md Abschnitt 5 und 7):
      - Fail closed: Kann die Pruefung nicht laufen, wird blockiert.
      - Melden statt reparieren: Der Hook aendert nichts.
      - Der Hook gibt nie Dateiinhalte aus.

    Bekannte Grenze: Die Pruefung arbeitet auf dem Befehlstext. Sie erkennt
    keine Pfade, die erst zur Laufzeit zusammengesetzt werden.
#>

$ErrorActionPreference = 'Stop'

try {
    $roh = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($roh)) {
        throw 'Keine Eingabe vom Harness erhalten.'
    }

    $eingabe = $roh | ConvertFrom-Json
    $befehl = [string]$eingabe.tool_input.command
    if ([string]::IsNullOrWhiteSpace($befehl)) {
        throw 'Eingabe enthaelt kein tool_input.command.'
    }

    # Wortgrenzen ueber Lookaround statt \b: "-" und "_" zaehlen als Teil
    # eines Namens, damit z. B. "New-LocalDevCertificates" nicht anschlaegt.
    $verboten = [ordered]@{
        'certs/ (lokale CA und private Schluessel)' = '(?i)(?<![\w-])certs(?![\w-])'
        '.env-Dateien'                              = '(?i)(?<![\w-])\.env(?![\w-])'
        'User Secrets'                              = '(?i)user-?secrets'
    }

    foreach ($eintrag in $verboten.GetEnumerator()) {
        if ($befehl -match $eintrag.Value) {
            [Console]::Error.WriteLine("Protect-Secrets: blockiert - der Befehl beruehrt $($eintrag.Key). CLAUDE.md Abschnitt 5 verbietet Lesen, Kopieren und Ausgeben.")
            exit 2
        }
    }

    exit 0
}
catch {
    [Console]::Error.WriteLine("Protect-Secrets: Pruefung nicht moeglich, daher blockiert (fail closed). $($_.Exception.Message)")
    exit 2
}
