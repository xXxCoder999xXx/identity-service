<#
.SYNOPSIS
    PreToolUse-Hook fuer Claude Code: prueft "git commit" vor der Ausfuehrung.

.DESCRIPTION
    Zwei Pruefungen (CLAUDE.md Abschnitt 4 und 6):
      1. Kein Commit auf main - Integration nur ueber Feature-Branches.
      2. Der Commit-Betreff folgt Conventional Commits.

    Das Betreff-Muster ist identisch mit Gruppe 5 in Test-RepoState.ps1
    (eine Quelle der Wahrheit). Abweichung: Vergleich mit -cmatch, also
    Gross-/Kleinschreibung beachtet ("Chore: x" faellt durch).

    Eingabe:  JSON des Harness auf stdin (tool_input.command, cwd).
    Ausgabe:  Exit 0 = erlaubt, Exit 2 = blockiert (Grund auf stderr).

    Fail closed: Kann die Pruefung nicht laufen oder der Betreff nicht
    gelesen werden, wird blockiert. Andere Befehle als "git commit" laesst
    der Hook unveraendert durch.
#>

$ErrorActionPreference = 'Stop'

$betreffMuster = '^(feat|fix|docs|chore|refactor|test|build|ci|perf|style|revert)(\([^)]+\))?!?: .'

function Get-ErsteZeile {
    param([string] $Text)

    foreach ($zeile in ($Text -split '\r?\n')) {
        if (-not [string]::IsNullOrWhiteSpace($zeile)) {
            return $zeile.Trim()
        }
    }
    return $null
}

function Get-CommitBetreff {
    param([string] $Befehl)

    # Erfasst -m, kombinierte Kurzschalter wie -am/-qm und --message[=].
    $treffer = [regex]::Match($Befehl, '(?s)\s(?:-[a-zA-Z]*m|--message)[\s=]+(.*)$')
    if (-not $treffer.Success) {
        return $null
    }
    $rest = $treffer.Groups[1].Value

    # PowerShell-Here-String: -m @'<Zeilenumbruch>Betreff ...
    if ($rest -match '^@["'']\s*\r?\n') {
        return Get-ErsteZeile ($rest -replace '^@["'']\s*\r?\n', '')
    }

    # Bash-Heredoc: -m "$(cat <<'EOF'<Zeilenumbruch>Betreff ...
    if ($rest -match '^"\$\(cat\s+<<[^\r\n]*\r?\n') {
        return Get-ErsteZeile ($rest -replace '^"\$\(cat\s+<<[^\r\n]*\r?\n', '')
    }

    # In Anfuehrungszeichen: bis zum schliessenden Zeichen oder Zeilenende.
    $zitat = [regex]::Match($rest, '^(["''])([^\r\n]*?)(?:\1|\r?\n|$)')
    if ($zitat.Success) {
        return $zitat.Groups[2].Value.Trim()
    }

    return Get-ErsteZeile $rest
}

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

    # "git commit" als Unterbefehl, auch mit globalen Optionen (git -C pfad commit).
    # "git commit-tree" und "git log --grep commit" treffen nicht.
    $istCommit = $befehl -match '(?<![\w-])git(\.exe)?\s+(?:-\S+\s+(?:[^-\s]\S*\s+)?)*commit(?![\w-])'
    if (-not $istCommit) {
        exit 0
    }

    $arbeitsverzeichnis = [string]$eingabe.cwd
    if ([string]::IsNullOrWhiteSpace($arbeitsverzeichnis)) {
        $arbeitsverzeichnis = (Get-Location).Path
    }

    # stderr ist bei git kein Fehlerindikator - nur der Exit-Code zaehlt.
    # "branch --show-current" funktioniert auch ohne ersten Commit und liefert
    # bei losgeloestem HEAD einen leeren Namen (dann greift nur Pruefung 2).
    $branch = & git -C $arbeitsverzeichnis branch --show-current 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'Aktueller Branch konnte nicht ermittelt werden.'
    }
    if ($branch -eq 'main') {
        [Console]::Error.WriteLine('Test-CommitConvention: blockiert - Commit auf main. Erst einen Feature-Branch <type>/<kebab-case> anlegen.')
        exit 2
    }

    # Uebernommene Nachrichten (--amend --no-edit, -C, --fixup) haben keinen
    # neuen Betreff, der geprueft werden koennte.
    if ($befehl -match '(?<![\w-])(--no-edit|--fixup|--reuse-message|-C)(?![\w-])') {
        exit 0
    }

    $betreff = Get-CommitBetreff $befehl
    if ([string]::IsNullOrWhiteSpace($betreff)) {
        [Console]::Error.WriteLine('Test-CommitConvention: blockiert - Betreff nicht lesbar. Commit mit -m "<type>(<scope>): <subject>" angeben.')
        exit 2
    }

    if ($betreff -cnotmatch $betreffMuster) {
        [Console]::Error.WriteLine("Test-CommitConvention: blockiert - Betreff ist kein Conventional Commit: '$betreff'. Erwartet: <type>(<scope>): <subject> mit type aus feat|fix|docs|chore|refactor|test|build|ci|perf|style|revert.")
        exit 2
    }

    exit 0
}
catch {
    [Console]::Error.WriteLine("Test-CommitConvention: Pruefung nicht moeglich, daher blockiert (fail closed). $($_.Exception.Message)")
    exit 2
}
