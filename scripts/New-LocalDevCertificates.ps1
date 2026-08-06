#Requires -Version 5.1
<#
.SYNOPSIS
    Erzeugt eine lokale Entwicklungs-CA und die davon signierten Server-Zertifikate
    fuer die lokale Container-Umgebung (nginx-Edge und Anwendungsservice).

.DESCRIPTION
    Das Skript trennt bewusst zwei Rollen:

      1. Die CA (Certificate Authority) - der Vertrauensanker. Sie wird EINMAL erzeugt
         und einmalig in den Trust Store des aktuellen Benutzers eingetragen. Ihr
         privater Schluessel ist das schuetzenswerteste Artefakt dieses gesamten
         Setups: Wer ihn besitzt, kann Zertifikate fuer JEDE Domain ausstellen,
         denen dieses System dann ohne Warnung glaubt.

      2. Die Leaf-Zertifikate (Blatt-Zertifikate) - die eigentlichen Server-Zertifikate.
         Sie sind kurzlebig und jederzeit ohne Trust-Store-Aenderung neu erzeugbar.

    Sicherheitsgrundsaetze (Abschnitt 6 des Projektauftrags):
      - 6.1.3 fail closed: Das Skript bricht bei fehlenden Voraussetzungen ab, statt
        mit Ersatzwerten weiterzulaufen. Eine bestehende CA wird NIE stillschweigend
        ueberschrieben (das wuerde jedes ausgestellte Zertifikat ungueltig machen).
      - 6.1.6 sichere Defaults: Kurvenwahl, Signatur-Hash, Gueltigkeitsdauern und
        Zertifikatserweiterungen sind explizit gesetzt, nicht aus openssl-Defaults
        uebernommen.
      - 6.2a minimale Abhaengigkeiten: ausschliesslich openssl, das ueber Git fuer
        Windows oder das Windows-SDK ohnehin vorhanden ist. Keine neue Abhaengigkeit.
      - 5.4 keine Secrets im Image: Die erzeugten Dateien werden zur LAUFZEIT als
        Volume gemountet. Sie gehoeren niemals in ein Container-Image und niemals
        ins Repository - das Skript legt dafuer eine eigene .gitignore an.

    Die CA wird in Cert:\CurrentUser\Root eingetragen, NICHT in LocalMachine\Root:
    Benutzerkontext statt Maschinenkontext, keine Administratorrechte noetig,
    kleinerer Schadensradius (Least Privilege).

.PARAMETER OutputRoot
    Zielverzeichnis. Standard: <Skriptverzeichnis>\..\certs

.PARAMETER CaValidityDays
    Gueltigkeit der CA in Tagen. Laenger als die Leafs, weil eine CA-Erneuerung den
    manuellen Trust-Store-Schritt erzwingt.

.PARAMETER LeafValidityDays
    Gueltigkeit der Server-Zertifikate in Tagen. Bewusst kurz: Kurzlebigkeit ist die
    wirksamere Gegenmassnahme als Geheimhaltung allein - ein kompromittierter
    Schluessel mit begrenzter Restlaufzeit hat ein begrenztes Schadensfenster.

.PARAMETER ForceNewCa
    Erzwingt die Neuerzeugung der CA. Danach ist eine erneute Trust-Store-Eintragung
    noetig und ALLE bisher ausgestellten Zertifikate sind wertlos.

.PARAMETER SkipTrustStore
    Erzeugt die Dateien, ohne die CA in den Trust Store einzutragen.

.EXAMPLE
    .\New-LocalDevCertificates.ps1

.EXAMPLE
    .\New-LocalDevCertificates.ps1 -LeafValidityDays 30
#>
[CmdletBinding()]
param(
    [string] $OutputRoot,
    [ValidateRange(1, 3650)] [int] $CaValidityDays = 730,
    [ValidateRange(1, 825)]  [int] $LeafValidityDays = 90,
    [string] $CaCommonName = 'Local Development CA',
    [switch] $ForceNewCa,
    [switch] $SkipTrustStore
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# KONFIGURATION - die auszustellenden Server-Zertifikate
#
# WICHTIG: 'Dns' muss JEDEN Namen enthalten, unter dem der jeweilige Dienst
# angesprochen wird. Der Grund (siehe Block 3.2): Die TLS-Namenspruefung fuehrt
# immer der Client der jeweiligen Verbindung durch, und es gibt zwei Verbindungen
# mit zwei verschiedenen Erwartungen:
#
#   - Der Browser adressiert 'localhost'          -> Browser prueft 'localhost'
#   - nginx adressiert den Container-Namen        -> nginx prueft den Container-Namen
#
# Fehlt einer der Namen, bricht genau diese eine Verbindung ab.
#
# Die Namen 'edge' und 'api' sind Platzhalter und MUESSEN in 4b mit den
# tatsaechlichen Service-Namen aus der compose.yaml abgeglichen werden.
# ---------------------------------------------------------------------------
$LeafCertificates = @(
    @{
        Name         = 'edge'
        CommonName   = 'edge.local-dev'
        DnsNames     = @('localhost', 'edge')
        IpAddresses  = @('127.0.0.1')
        Purpose      = 'nginx - vom Browser adressiert'
    },
    @{
        Name         = 'api'
        CommonName   = 'api.local-dev'
        DnsNames     = @('api', 'localhost')
        IpAddresses  = @()
        Purpose      = 'Anwendungsservice - von nginx adressiert'
    }
)

# Elliptische Kurve statt RSA: kuerzere Schluessel bei gleichwertiger Sicherheit,
# schnellere Handshakes. KOPPLUNG fuer 4b: Die ssl_ciphers-Liste in der
# nginx.conf muss ECDSA-Suiten enthalten (ECDHE-ECDSA-...), sonst schlaegt der
# TLS-1.2-Handshake fehl. TLS 1.3 ist davon nicht betroffen.
$EllipticCurve = 'prime256v1'
$SignatureHash = 'sha256'

# ---------------------------------------------------------------------------
# Hilfsfunktionen
# ---------------------------------------------------------------------------

function Resolve-OpenSslPath {
    <#
        Sucht openssl.exe. Fail closed: Wird nichts gefunden, bricht das Skript ab,
        statt auf ein anderes Werkzeug auszuweichen.
    #>
    $command = Get-Command -Name 'openssl.exe' -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        "$env:ProgramFiles\Git\usr\bin\openssl.exe"
        "${env:ProgramFiles(x86)}\Git\usr\bin\openssl.exe"
        "$env:ProgramFiles\Git\mingw64\bin\openssl.exe"
        "$env:LOCALAPPDATA\Programs\Git\usr\bin\openssl.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
    }

    throw @'
openssl.exe wurde nicht gefunden.

openssl ist bei "Git fuer Windows" enthalten. Entweder Git installieren oder den
Ordner mit openssl.exe der PATH-Variablen hinzufuegen, dann dieses Skript erneut
ausfuehren.
'@
}

function Assert-OpenSslVersion {
    <#
        Verlangt OpenSSL >= 1.1.1. Aeltere Versionen und LibreSSL unterstuetzen die
        hier genutzten Optionen nicht zuverlaessig - das wuerde zu subtil falschen
        Zertifikaten fuehren statt zu einem klaren Fehler.
    #>
    param([Parameter(Mandatory)][string] $OpenSslPath)

    # Siehe Kommentar in Invoke-OpenSsl: native Programme schreiben auch
    # Erfolgsmeldungen nach stderr. Mit ErrorActionPreference = 'Stop' wuerde
    # PowerShell das als Abbruchfehler werten. Massgeblich ist der Exit-Code.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $versionText = (& $OpenSslPath version) 2>&1 | Out-String
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($LASTEXITCODE -ne 0) {
        throw "openssl konnte nicht ausgefuehrt werden: $versionText"
    }

    if ($versionText -notmatch 'OpenSSL\s+(\d+)\.(\d+)\.(\d+)') {
        throw "Nicht unterstuetzte openssl-Variante (erwartet: OpenSSL 1.1.1 oder neuer). Gemeldet: $($versionText.Trim())"
    }

    $major = [int]$Matches[1]
    $minor = [int]$Matches[2]
    $patch = [int]$Matches[3]

    $isSupported = ($major -gt 1) -or
                   ($major -eq 1 -and $minor -gt 1) -or
                   ($major -eq 1 -and $minor -eq 1 -and $patch -ge 1)

    if (-not $isSupported) {
        throw "openssl $major.$minor.$patch ist zu alt. Benoetigt wird mindestens 1.1.1."
    }

    return $versionText.Trim()
}

function Invoke-OpenSsl {
    <#
        Fuehrt openssl aus und wandelt einen Exit-Code ungleich 0 in eine Exception.
        Ohne diese Pruefung wuerde PowerShell stillschweigend weiterlaufen - genau
        der fail-silent-Zustand, den wir vermeiden.
    #>
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][string]   $Activity
    )

    # WICHTIG: openssl schreibt auch ERFOLGSmeldungen nach stderr, etwa
    # "Certificate request self-signature ok". Durch die Umleitung 2>&1 werden
    # daraus PowerShell-Fehlerobjekte, und bei ErrorActionPreference = 'Stop'
    # wuerde das Skript mitten im Erfolgsfall abbrechen.
    #
    # Der Kanal (stdout/stderr) sagt bei nativen Programmen nichts ueber den
    # Schweregrad aus. Die einzige verlaessliche Erfolgsaussage ist der
    # Exit-Code - deshalb wird nur er ausgewertet.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:OpenSslPath @Arguments 2>&1
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($LASTEXITCODE -ne 0) {
        throw "openssl fehlgeschlagen bei '$Activity' (Exit-Code $LASTEXITCODE):`n$($output -join [Environment]::NewLine)"
    }
    return $output
}

function Protect-PrivateKeyFile {
    <#
        Entfernt die Rechtevererbung und gewaehrt ausschliesslich dem aktuellen
        Benutzerkonto Zugriff. Ohne diesen Schritt erbt der private Schluessel die
        Rechte des uebergeordneten Ordners - typischerweise lesbar fuer weitere
        Konten der Maschine.
    #>
    param([Parameter(Mandatory)][string] $Path)

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $result = & icacls "$Path" /inheritance:r /grant:r "$($identity):(F)" 2>&1
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Dateirechte konnten nicht gesetzt werden fuer '$Path':`n$($result -join [Environment]::NewLine)"
    }
}

function New-SanEntryList {
    param(
        [string[]] $DnsNames,
        [string[]] $IpAddresses
    )
    $entries = @()
    foreach ($dns in $DnsNames)    { $entries += "DNS:$dns" }
    foreach ($ip  in $IpAddresses) { $entries += "IP:$ip" }
    return ($entries -join ', ')
}

function Write-Step {
    param([string] $Message)
    Write-Host "  -> $Message"
}

# ---------------------------------------------------------------------------
# Vorbereitung
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'Lokale Entwicklungs-Zertifikate' -ForegroundColor Cyan
Write-Host '================================'

$script:OpenSslPath = Resolve-OpenSslPath
$opensslVersion = Assert-OpenSslVersion -OpenSslPath $script:OpenSslPath
Write-Step "openssl: $opensslVersion"

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $baseDirectory = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }
    $OutputRoot = Join-Path -Path $baseDirectory -ChildPath '..\certs'
}
$null = New-Item -ItemType Directory -Path $OutputRoot -Force
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
Write-Step "Zielverzeichnis: $OutputRoot"

# Eigene .gitignore im Zertifikatsverzeichnis.
# Bewusst zusaetzlich zur .gitignore im Repository-Wurzelverzeichnis: Diese Datei
# wirkt auch dann, wenn die zentrale .gitignore vergessen oder umgebaut wird.
# Verteidigung in der Tiefe fuer das kritischste Artefakt des Setups.
$gitignorePath = Join-Path $OutputRoot '.gitignore'
@'
# Erzeugte Zertifikate und private Schluessel. Niemals committen.
# Diese Datei wirkt zusaetzlich zur zentralen .gitignore (Verteidigung in der Tiefe).
*
!.gitignore
'@ | Set-Content -LiteralPath $gitignorePath -Encoding ASCII
Write-Step 'Schutz-.gitignore geschrieben'

$caDirectory = Join-Path $OutputRoot 'ca'
$null = New-Item -ItemType Directory -Path $caDirectory -Force

$caKeyPath = Join-Path $caDirectory 'local-dev-ca.key'
$caCrtPath = Join-Path $caDirectory 'local-dev-ca.crt'
$caCnfPath = Join-Path $caDirectory 'local-dev-ca.cnf'

# ---------------------------------------------------------------------------
# Schritt 1 - Certificate Authority
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '[1/3] Certificate Authority' -ForegroundColor Cyan

$caAlreadyExists = (Test-Path -LiteralPath $caKeyPath) -and (Test-Path -LiteralPath $caCrtPath)

if ($caAlreadyExists -and -not $ForceNewCa) {
    Write-Step 'Bestehende CA gefunden - wird wiederverwendet.'
    Write-Step 'Neuerzeugung nur mit -ForceNewCa (macht alle bisherigen Zertifikate ungueltig).'
}
else {
    if ($caAlreadyExists) {
        Write-Warning 'ForceNewCa: Die bestehende CA wird ersetzt. Alle bisher ausgestellten Zertifikate werden damit wertlos, und der Trust-Store-Eintrag muss erneuert werden.'
    }

    # prompt = no + eigener [dn]-Abschnitt: Der Subject-DN steht in der Datei statt
    # als -subj-Argument. Das umgeht zugleich die Pfadumschreibung, die die
    # MSYS-basierte openssl.exe aus Git fuer Windows auf Argumente mit fuehrendem
    # Schraegstrich anwendet.
    @"
[req]
prompt             = no
distinguished_name = dn

[dn]
CN = $CaCommonName
O  = Local development only - not for production use

[v3_ca]
basicConstraints     = critical, CA:TRUE, pathlen:0
keyUsage             = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
"@ | Set-Content -LiteralPath $caCnfPath -Encoding ASCII

    Write-Step 'Privaten CA-Schluessel erzeugen'
    $null = Invoke-OpenSsl -Activity 'CA-Schluessel' -Arguments @(
        'ecparam', '-name', $EllipticCurve, '-genkey', '-noout', '-out', $caKeyPath
    )
    Protect-PrivateKeyFile -Path $caKeyPath

    Write-Step "CA-Zertifikat ausstellen (Gueltigkeit: $CaValidityDays Tage)"
    $null = Invoke-OpenSsl -Activity 'CA-Zertifikat' -Arguments @(
        'req', '-x509', '-new',
        '-key', $caKeyPath,
        "-$SignatureHash",
        '-days', $CaValidityDays,
        '-config', $caCnfPath,
        '-extensions', 'v3_ca',
        '-out', $caCrtPath
    )
}

# ---------------------------------------------------------------------------
# Schritt 2 - Server-Zertifikate
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '[2/3] Server-Zertifikate' -ForegroundColor Cyan

$issuedCertificates = @()

foreach ($leaf in $LeafCertificates) {
    $leafDirectory = Join-Path $OutputRoot $leaf.Name
    $null = New-Item -ItemType Directory -Path $leafDirectory -Force

    $leafKeyPath = Join-Path $leafDirectory "$($leaf.Name).key"
    $leafCsrPath = Join-Path $leafDirectory "$($leaf.Name).csr"
    $leafCrtPath = Join-Path $leafDirectory "$($leaf.Name).crt"
    $leafCnfPath = Join-Path $leafDirectory "$($leaf.Name).cnf"

    $sanEntries = New-SanEntryList -DnsNames $leaf.DnsNames -IpAddresses $leaf.IpAddresses

    Write-Step "$($leaf.Name) - SAN: $sanEntries"

    # Der [req]-Abschnitt beschreibt nur den Subject-DN, NICHT die Erweiterungen.
    # Das ist Absicht: Die Erweiterungen (und damit die SAN-Liste) werden erst beim
    # Signieren aus [v3_leaf] gelesen. Damit entscheidet die CA, was im Zertifikat
    # steht - nicht der Antragsteller. Genau dieselbe Denkfigur wie bei den
    # X-Forwarded-Headern: die verifizierende Instanz bestimmt den Inhalt, nicht
    # die anfragende.
    @"
[req]
prompt             = no
distinguished_name = dn

[dn]
CN = $($leaf.CommonName)
O  = Local development only - not for production use

[v3_leaf]
basicConstraints       = critical, CA:FALSE
keyUsage               = critical, digitalSignature
extendedKeyUsage       = serverAuth
subjectKeyIdentifier   = hash
authorityKeyIdentifier = keyid, issuer
subjectAltName         = $sanEntries
"@ | Set-Content -LiteralPath $leafCnfPath -Encoding ASCII

    $null = Invoke-OpenSsl -Activity "$($leaf.Name): Schluessel" -Arguments @(
        'ecparam', '-name', $EllipticCurve, '-genkey', '-noout', '-out', $leafKeyPath
    )
    Protect-PrivateKeyFile -Path $leafKeyPath

    $null = Invoke-OpenSsl -Activity "$($leaf.Name): CSR" -Arguments @(
        'req', '-new', '-key', $leafKeyPath, '-config', $leafCnfPath, '-out', $leafCsrPath
    )

    $null = Invoke-OpenSsl -Activity "$($leaf.Name): Signatur" -Arguments @(
        'x509', '-req',
        '-in', $leafCsrPath,
        '-CA', $caCrtPath,
        '-CAkey', $caKeyPath,
        '-CAcreateserial',
        '-days', $LeafValidityDays,
        "-$SignatureHash",
        '-extfile', $leafCnfPath,
        '-extensions', 'v3_leaf',
        '-out', $leafCrtPath
    )

    # Der CSR ist ein reines Zwischenprodukt und wird nicht aufbewahrt.
    Remove-Item -LiteralPath $leafCsrPath -Force

    $issuedCertificates += [pscustomobject]@{
        Name            = $leaf.Name
        Purpose         = $leaf.Purpose
        CertificatePath = $leafCrtPath
        KeyPath         = $leafKeyPath
    }
}

# ---------------------------------------------------------------------------
# Schritt 3 - Trust Store
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '[3/3] Trust Store' -ForegroundColor Cyan

if ($SkipTrustStore) {
    Write-Step 'Uebersprungen (-SkipTrustStore).'
}
else {
    $caCertificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $caCrtPath
    $thumbprint = $caCertificate.Thumbprint

    $alreadyTrusted = Get-ChildItem -Path 'Cert:\CurrentUser\Root' |
                      Where-Object { $_.Thumbprint -eq $thumbprint }

    if ($alreadyTrusted) {
        Write-Step "Bereits eingetragen (Thumbprint $thumbprint)."
    }
    else {
        Write-Step 'Eintragung in Cert:\CurrentUser\Root'
        Write-Host ''
        Write-Host '  Windows fragt gleich nach einer Bestaetigung. Das ist kein Fehler,' -ForegroundColor Yellow
        Write-Host '  sondern die Schutzabfrage des Betriebssystems fuer genau diese' -ForegroundColor Yellow
        Write-Host '  Vertrauensentscheidung. Sie ist erwuenscht.' -ForegroundColor Yellow
        Write-Host ''

        $null = Import-Certificate -FilePath $caCrtPath -CertStoreLocation 'Cert:\CurrentUser\Root'
        Write-Step "Eingetragen (Thumbprint $thumbprint)."
    }
}

# ---------------------------------------------------------------------------
# Verifikation - messen statt hoffen
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'Verifikation' -ForegroundColor Cyan
Write-Host '------------'

foreach ($certificate in $issuedCertificates) {
    Write-Host ''
    Write-Host "$($certificate.Name)  ($($certificate.Purpose))" -ForegroundColor White

    $details = Invoke-OpenSsl -Activity "$($certificate.Name): Verifikation" -Arguments @(
        'x509', '-in', $certificate.CertificatePath, '-noout', '-subject', '-issuer', '-dates', '-ext', 'subjectAltName'
    )
    $details | ForEach-Object { Write-Host "  $_" }

    # Prueft, ob das Zertifikat tatsaechlich gegen die erzeugte CA verifizierbar ist.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $verification = & $script:OpenSslPath verify -CAfile $caCrtPath $certificate.CertificatePath 2>&1
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host '  Kettenpruefung: bestanden' -ForegroundColor Green
    }
    else {
        Write-Host "  Kettenpruefung: FEHLGESCHLAGEN - $($verification -join ' ')" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host 'Naechste Schritte' -ForegroundColor Cyan
Write-Host '-----------------'
Write-Host '  - Firefox nutzt einen eigenen Zertifikatsspeicher und ignoriert den'
Write-Host '    Windows Trust Store. Dort muss die CA separat importiert werden.'
Write-Host '  - Die Dateien werden in 4b per Volume in die Container gemountet,'
Write-Host '    nicht ins Image kopiert.'
Write-Host '  - CA wieder entfernen:'
Write-Host '      Get-ChildItem Cert:\CurrentUser\Root | Where-Object Subject -like "*Local Development CA*" | Remove-Item'
Write-Host ''
Write-Host 'Fertig.' -ForegroundColor Green
Write-Host ''
