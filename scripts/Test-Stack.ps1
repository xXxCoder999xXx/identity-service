<#
.SYNOPSIS
    Smoke-Test fuer den laufenden Container-Stack (nginx -> api).

.DESCRIPTION
    Prueft den bereits gestarteten Stack mit echten Anfragen. Das Skript
    startet und stoppt nichts (melden statt reparieren) - der Aufrufer
    startet den Stack vorher mit "docker compose up --detach".

    Derselbe Aufruf laeuft lokal (Windows PowerShell 5.1 oder PowerShell 7)
    und in der CI (PowerShell 7 unter Linux): lokales Urteil == CI-Urteil.

    Pruefungen:
      1. /health liefert 200 und den Text "Healthy" - ueber die ganze Kette
         Client -> nginx (TLS) -> api (TLS, von nginx verifiziert).
      2. Die Security-Header sind bei 200 UND bei 404 vorhanden
         (jeder add_header mit "always").
      3. Der Server-Header verraet keine nginx-Version (server_tokens off).
      4. Der Dienst api hat keinen veroeffentlichten Port (Zero Trust:
         der einzige Weg zur API fuehrt ueber nginx).

    Sicherheitsgrundsaetze:
      - Die Zertifikatskette wird IMMER geprueft; es gibt keinen Schalter,
        der die Pruefung abschaltet (kein "-k").
      - Fail closed: Kann eine Pruefung nicht laufen, zaehlt sie als Fehler.
      - Es werden keine Dateiinhalte von Schluesseln oder Zertifikaten
        ausgegeben.
      - stderr nativer Programme ist kein Fehlerindikator - nur Exit-Codes.

.PARAMETER BaseUrl
    Adresse des Einstiegspunkts. Umgebungen unterscheiden sich nur ueber
    Parameter, nie ueber Aenderungen am Skript.

.PARAMETER CaFile
    Pfad zum CA-Zertifikat (PEM), dem der Aufruf vertrauen soll. Ohne Angabe
    gilt der Zertifikatsspeicher des Systems (lokal: die importierte
    Entwicklungs-CA).

.PARAMETER ApiService
    Name des Compose-Dienstes, der keinen Port veroeffentlichen darf.

.PARAMETER TimeoutSeconds
    Wie lange auf die Bereitschaft des Stacks gewartet wird.

.EXAMPLE
    .\scripts\Test-Stack.ps1

.EXAMPLE
    ./scripts/Test-Stack.ps1 -CaFile ./ca.crt -TimeoutSeconds 90
#>

[CmdletBinding()]
param(
    [string] $BaseUrl = 'https://localhost:8443',
    [string] $CaFile = '',
    [string] $ApiService = 'api',
    [int] $TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$script:Fehler = 0

# PowerShell 5.1 kennt $IsWindows nicht und laeuft nur unter Windows.
$unterWindows = ($PSVersionTable.PSEdition -ne 'Core') -or $IsWindows

# Unter Windows PowerShell ist "curl" ein Alias fuer Invoke-WebRequest -
# deshalb dort ausdruecklich die native curl.exe.
$curl = 'curl'
if ($unterWindows) { $curl = 'curl.exe' }

$erwarteteHeader = @(
    'Strict-Transport-Security',
    'X-Content-Type-Options',
    'X-Frame-Options',
    'Referrer-Policy',
    'Content-Security-Policy'
)

function Melde {
    param([bool] $Ok, [string] $Text)

    if ($Ok) {
        Write-Host "  [ok]     $Text"
    }
    else {
        Write-Host "  [FEHLER] $Text"
        $script:Fehler++
    }
}

function Invoke-Anfrage {
    param([string] $Pfad)

    $headerDatei = [System.IO.Path]::GetTempFileName()
    $bodyDatei = [System.IO.Path]::GetTempFileName()
    try {
        $argumente = @(
            '--silent', '--show-error',
            '--max-time', '10',
            '--dump-header', $headerDatei,
            '--output', $bodyDatei,
            '--write-out', '%{http_code}'
        )
        if ($CaFile) {
            $argumente += @('--cacert', $CaFile)
        }
        if ($unterWindows) {
            # Schannel prueft Sperrlisten; die lokale Entwicklungs-CA bietet
            # keine an. Die Kettenpruefung selbst bleibt aktiv.
            $argumente += '--ssl-no-revoke'
        }
        $argumente += ($BaseUrl.TrimEnd('/') + $Pfad)

        $status = & $curl @argumente 2>$null
        $exitCode = $LASTEXITCODE

        $header = @{}
        foreach ($zeile in (Get-Content -LiteralPath $headerDatei)) {
            $teile = $zeile -split ':', 2
            if ($teile.Count -eq 2) {
                $header[$teile[0].Trim().ToLowerInvariant()] = $teile[1].Trim()
            }
        }

        return [pscustomobject]@{
            ExitCode = $exitCode
            Status   = [string]$status
            Header   = $header
            Body     = [string](Get-Content -LiteralPath $bodyDatei -Raw)
        }
    }
    finally {
        Remove-Item -LiteralPath $headerDatei, $bodyDatei -Force -ErrorAction SilentlyContinue
    }
}

function Test-Header {
    param([hashtable] $Header, [string] $Kontext)

    foreach ($name in $erwarteteHeader) {
        Melde ($Header.ContainsKey($name.ToLowerInvariant())) "$Kontext - Header vorhanden: $name"
    }

    $server = [string]$Header['server']
    Melde (-not ($server -match '\d')) "$Kontext - Server-Header ohne Versionsangabe"
}

if ($CaFile -and -not (Test-Path -LiteralPath $CaFile -PathType Leaf)) {
    Write-Host "  [FEHLER] CA-Datei nicht gefunden: $CaFile"
    exit 1
}

Write-Host "Smoke-Test gegen $BaseUrl"

# --- Bereitschaft: depends_on ordnet nur den Start und prueft keine
# --- Bereitschaft; das chiseled-Image hat kein Werkzeug fuer einen
# --- Healthcheck im Container. Deshalb wird von aussen gewartet.
Write-Host ''
Write-Host "Bereitschaft (hoechstens $TimeoutSeconds s)"
$frist = (Get-Date).AddSeconds($TimeoutSeconds)
$health = $null
do {
    $health = Invoke-Anfrage '/health'
    if ($health.ExitCode -eq 0 -and $health.Status -eq '200') { break }
    Start-Sleep -Seconds 2
} while ((Get-Date) -lt $frist)

$bereit = ($health.ExitCode -eq 0 -and $health.Status -eq '200')
Melde $bereit "Stack antwortet auf /health (curl-Exit-Code $($health.ExitCode), Status '$($health.Status)')"

if ($bereit) {
    Write-Host ''
    Write-Host 'Health-Endpunkt'
    Melde ($health.Body.Trim() -eq 'Healthy') "Antworttext ist 'Healthy'"
    Test-Header $health.Header 'Status 200'

    Write-Host ''
    Write-Host 'Fehlerpfad'
    $nichtGefunden = Invoke-Anfrage '/smoke-test-pfad-existiert-nicht'
    $istFehlerpfad = ($nichtGefunden.ExitCode -eq 0 -and $nichtGefunden.Status -eq '404')
    Melde $istFehlerpfad "Unbekannter Pfad liefert 404 (curl-Exit-Code $($nichtGefunden.ExitCode), Status '$($nichtGefunden.Status)')"
    if ($istFehlerpfad) {
        Test-Header $nichtGefunden.Header 'Status 404'
    }
}

# --- Zero Trust: nur nginx veroeffentlicht einen Port.
Write-Host ''
Write-Host 'Netzgrenze'
$zeilen = @(& docker compose ps --format json $ApiService 2>$null)
if ($LASTEXITCODE -ne 0 -or $zeilen.Count -eq 0) {
    Melde $false "Dienst '$ApiService' konnte nicht abgefragt werden (fail closed)"
}
else {
    # Je nach Compose-Version eine JSON-Zeile pro Container oder ein Array.
    # Das angehaengte ForEach-Object entpackt ein Array auch unter 5.1.
    $text = ($zeilen -join "`n").Trim()
    if ($text.StartsWith('[')) {
        $container = @($text | ConvertFrom-Json | ForEach-Object { $_ })
    }
    else {
        $container = @(
            $zeilen |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                ForEach-Object { $_ | ConvertFrom-Json }
        )
    }

    $laufend = @($container | Where-Object { $_.State -eq 'running' })
    Melde ($laufend.Count -ge 1) "Dienst '$ApiService' laeuft"

    $veroeffentlicht = @(
        $container |
            ForEach-Object { $_.Publishers } |
            Where-Object { $_ -and $_.PublishedPort -gt 0 }
    )
    Melde ($veroeffentlicht.Count -eq 0) "Dienst '$ApiService' veroeffentlicht keinen Port"
}

Write-Host ''
if ($script:Fehler -gt 0) {
    Write-Host "Ergebnis: $($script:Fehler) Pruefung(en) fehlgeschlagen."
    exit 1
}

Write-Host 'Ergebnis: alle Pruefungen bestanden.'
exit 0
