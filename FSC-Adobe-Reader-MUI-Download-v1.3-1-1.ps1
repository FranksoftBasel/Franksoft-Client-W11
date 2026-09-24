# ==================================================================================================
# Franksoft - FSC Adobe Acrobat Reader MUI Update Downloader
#
# Version : 1.3
#
# Zweck:
#   Prueft zuerst die installierte Adobe Acrobat Reader Version gegen den aktuellsten
#   Adobe Continuous Release. Nur wenn die installierte Version aelter ist, wird die
#   x64 MUI MSP-Datei gesucht, heruntergeladen und mit msiexec /qb- installiert.
#
# Log:
#   C:\ProgramData\Franksoft\Logs\AdobeReaderUpdate.log
#
# Changelog:
#   v1.3 - 24.09.2026
#          - Versionsvergleich vor Download und Installation
#          - Wenn installierte Version >= aktuelle Adobe Version: kein Download, Exit 0
#          - Nur bei veralteter Installation wird die MUI MSP geladen und installiert
#          - Versionsvergleich erfolgt numerisch ueber System.Version
#          - Update erforderlich JA/NEIN wird geloggt
#
#   v1.2 - 24.09.2026
#          - MSP wird nach erfolgreichem Download automatisch installiert
#          - Installation mit msiexec.exe /p "<MSP>" /qb- /norestart
#          - MSI Exit Code wird im FSC Log protokolliert
#          - Script beendet sich unabhaengig vom Ergebnis immer mit Exit Code 0
#
#   v1.1 - 24.09.2026
#          - FSC Logging hinzugefuegt
#          - Installierte Adobe Version vor dem Update wird geloggt
#          - Neue Adobe Version wird aus dem MSP-Dateinamen ermittelt und geloggt
#          - Download-URL, MSP-Datei, Zielpfad und Dateigroesse werden geloggt
#
#   v1.0 - 24.09.2026
#          - Erste Version
#          - Aktuellsten Release ueber Adobe Release Notes Index ermitteln
#          - x64 MUI MSP auf der Release-Seite suchen
#          - MSP nach C:\Temp\Adobe herunterladen
#
# Franksoft Client Deployment
# Copyright (c) Franksoft 1997-2027
# ==================================================================================================

$ErrorActionPreference = "Stop"

$IndexUrl    = "https://www.adobe.com/devnet-docs/acrobatetk/tools/ReleaseNotesDC/index.html"
$DownloadDir = "C:\Temp\Adobe"
$LogDir      = "C:\ProgramData\Franksoft\Logs"
$LogFile     = Join-Path $LogDir "AdobeReaderUpdate.log"

try {
    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
}
catch {}

function Write-Log {
    param([Parameter(Mandatory=$true)][string]$Message)
    try {
        $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -LiteralPath $LogFile -Value "[$Timestamp] $Message" -Encoding UTF8
    }
    catch {}
}

Write-Host ""
Write-Host "Franksoft - Adobe Acrobat Reader MUI Update Downloader"
Write-Host "======================================================"
Write-Host "Version 1.3"
Write-Host ""

Write-Log "======================================================================"
Write-Log "Franksoft Adobe Acrobat Reader MUI Update Downloader v1.3 gestartet"
Write-Log "======================================================================"

try {
    # ==================================================================================================
# FUNCTION: Installierte Adobe Acrobat Reader Version ermitteln
# ==================================================================================================
    Write-Host "Installierte Adobe Version wird ermittelt..."

    $AdobeInstall = Get-ItemProperty `
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" ,
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
        -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.DisplayName -match '^Adobe Acrobat Reader' -or $_.DisplayName -match '^Adobe Acrobat') -and
            $_.DisplayVersion
        } |
        Select-Object -First 1

    if ($AdobeInstall) {
        $InstalledVersion = $AdobeInstall.DisplayVersion.Trim()
        Write-Host "Installiert : $InstalledVersion"
        Write-Log "Version installiert : $InstalledVersion"
        Write-Log "Installation        : $($AdobeInstall.DisplayName)"
    }
    else {
        $InstalledVersion = $null
        Write-Host "Installiert : Nicht gefunden" -ForegroundColor Yellow
        Write-Log "Version installiert : Nicht gefunden"
    }

    # ==================================================================================================
# FUNCTION: Aktuellsten Adobe Release ermitteln
# ==================================================================================================
    Write-Host ""
    Write-Host "Adobe Release Notes werden gelesen..."
    Write-Log "Adobe Release Notes Index wird gelesen: $IndexUrl"

    $Index = Invoke-WebRequest -Uri $IndexUrl -UseBasicParsing

    $ReleaseLink = $Index.Links |
        Where-Object { $_.innerText -match '^\s*\d{2}\.\d{3}\.\d+' } |
        Select-Object -First 1

    if (-not $ReleaseLink) {
        throw "Kein aktueller Adobe Release-Link gefunden."
    }

    $ReleaseVersion = [regex]::Match(
        $ReleaseLink.innerText,
        '\d{2}\.\d{3}\.\d+'
    ).Value

    $ReleaseUrl = (
        [System.Uri]::new([System.Uri]$IndexUrl, $ReleaseLink.href)
    ).AbsoluteUri

    Write-Host "Aktuell     : $ReleaseVersion"
    Write-Log "Version aktuell     : $ReleaseVersion"
    Write-Log "Release Notes       : $ReleaseUrl"

    # ==================================================================================================
# FUNCTION: Installierte und aktuelle Adobe Version vergleichen
# ==================================================================================================
    $UpdateRequired = $true

    if ($InstalledVersion) {
        try {
            $InstalledVersionObject = [System.Version]$InstalledVersion
            $ReleaseVersionObject   = [System.Version]$ReleaseVersion

            if ($InstalledVersionObject -ge $ReleaseVersionObject) {
                $UpdateRequired = $false
            }
        }
        catch {
            Write-Log "Versionsvergleich konnte nicht eindeutig ausgefuehrt werden: $($_.Exception.Message)"
            Write-Log "Sicherheitsverhalten: Update wird ausgefuehrt"
            $UpdateRequired = $true
        }
    }
    else {
        Write-Log "Keine installierte Version gefunden - Update wird versucht"
    }

    if (-not $UpdateRequired) {
        Write-Host ""
        Write-Host "Adobe Reader ist aktuell." -ForegroundColor Green
        Write-Host "Kein Download und keine Installation erforderlich."
        Write-Host ""

        Write-Log "Update erforderlich  : NEIN"
        Write-Log "Kein Download / keine Installation"
        Write-Log "Script Exit Code     : 0"
        Write-Log "======================================================================"
        exit 0
    }

    Write-Host ""
    Write-Host "Update erforderlich." -ForegroundColor Yellow
    Write-Log "Update erforderlich  : JA"

    # ==================================================================================================
# FUNCTION: Adobe Release-Seite laden
# ==================================================================================================
    Write-Host "Release-Seite wird gelesen..."
    $ReleasePage = Invoke-WebRequest -Uri $ReleaseUrl -UseBasicParsing

    # ==================================================================================================
# FUNCTION: Adobe Acrobat Reader x64 MUI MSP suchen
# ==================================================================================================
    $MspLink = $ReleasePage.Links |
        Where-Object { $_.href -match '(?i)AcroRdrDCx64.*MUI\.msp(?:$|\?)' } |
        Select-Object -First 1

    if (-not $MspLink) {
        throw "Keine Adobe Acrobat Reader x64 MUI MSP-Datei gefunden."
    }

    $MspUrl = (
        [System.Uri]::new([System.Uri]$ReleaseUrl, $MspLink.href)
    ).AbsoluteUri

    $MspFile = [System.IO.Path]::GetFileName(
        ([System.Uri]$MspUrl).AbsolutePath
    )

    # ==================================================================================================
# FUNCTION: Adobe Version aus MSP-Dateinamen ermitteln
# ==================================================================================================
    $MspVersionMatch = [regex]::Match(
        $MspFile,
        '(?i)Upd(\d{2})(\d{3})(\d{5})'
    )

    if ($MspVersionMatch.Success) {
        $NewVersion = "{0}.{1}.{2}" -f `
            $MspVersionMatch.Groups[1].Value,
            $MspVersionMatch.Groups[2].Value,
            $MspVersionMatch.Groups[3].Value
    }
    else {
        $NewVersion = $ReleaseVersion
    }

    Write-Host ""
    Write-Host "MUI MSP gefunden:" -ForegroundColor Green
    Write-Host "  Datei    : $MspFile"
    Write-Host "  Version  : $NewVersion"
    Write-Host "  Download : $MspUrl"

    Write-Log "MSP-Datei           : $MspFile"
    Write-Log "Version nachher     : $NewVersion"
    Write-Log "Download URL        : $MspUrl"

    # ==================================================================================================
# FUNCTION: Adobe MUI MSP herunterladen
# ==================================================================================================
    if (-not (Test-Path -LiteralPath $DownloadDir)) {
        New-Item -Path $DownloadDir -ItemType Directory -Force | Out-Null
    }

    $DestinationFile = Join-Path $DownloadDir $MspFile
    Write-Log "Zielpfad            : $DestinationFile"

    if (Test-Path -LiteralPath $DestinationFile) {
        Write-Host ""
        Write-Host "MSP bereits vorhanden - Download wird uebersprungen." -ForegroundColor Yellow
        Write-Log "MSP bereits vorhanden - Download uebersprungen"
    }
    else {
        Write-Host ""
        Write-Host "MSP wird heruntergeladen..."
        Write-Log "MSP Download gestartet"

        Invoke-WebRequest -Uri $MspUrl -OutFile $DestinationFile -UseBasicParsing

        Write-Host "Download erfolgreich." -ForegroundColor Green
        Write-Log "MSP Download erfolgreich"
    }

    if (-not (Test-Path -LiteralPath $DestinationFile)) {
        throw "Die MSP-Datei ist nach dem Download nicht vorhanden."
    }

    $File = Get-Item -LiteralPath $DestinationFile
    $SizeMB = [math]::Round($File.Length / 1MB, 2)
    Write-Log "Dateigroesse        : $SizeMB MB"

    # ==================================================================================================
# FUNCTION: Adobe MUI MSP installieren
# ==================================================================================================
    Write-Host ""
    Write-Host "Adobe Reader MSP wird installiert..."
    Write-Log "MSP Installation gestartet"
    Write-Log "Befehl: msiexec.exe /p `"$DestinationFile`" /qb- /norestart"

    $MsiProcess = Start-Process `
        -FilePath "msiexec.exe" `
        -ArgumentList "/p `"$DestinationFile`" /qb- /norestart" `
        -Wait `
        -PassThru

    $MsiExitCode = $MsiProcess.ExitCode

    Write-Host "MSI Exit Code : $MsiExitCode"
    Write-Log "MSI Exit Code       : $MsiExitCode"

    switch ($MsiExitCode) {
        0    { Write-Log "MSI Ergebnis        : Erfolgreich" }
        1641 { Write-Log "MSI Ergebnis        : Erfolgreich - Neustart initiiert" }
        3010 { Write-Log "MSI Ergebnis        : Erfolgreich - Neustart erforderlich" }
        default { Write-Log "MSI Ergebnis        : Installation beendet mit Exit Code $MsiExitCode" }
    }

    # ==================================================================================================
    # FUNCTION: Ergebnis und Logging
    # ==================================================================================================

    Write-Host ""
    Write-Host "======================================================"
    Write-Host "Franksoft - Adobe Reader Update"
    Write-Host "======================================================"
    Write-Host "Version vorher  : $(if ($InstalledVersion) {$InstalledVersion} else {'Nicht gefunden'})"
    Write-Host "Version nachher : $NewVersion"
    Write-Host "MSP-Datei       : $MspFile"
    Write-Host "Groesse         : $SizeMB MB"
    Write-Host "MSI Exit Code   : $MsiExitCode"
    Write-Host ""

    Write-Log "Version vorher      : $(if ($InstalledVersion) {$InstalledVersion} else {'Nicht gefunden'})"
    Write-Log "Version nachher     : $NewVersion"
    Write-Log "Vorgang beendet"
    Write-Log "Script Exit Code    : 0"
    Write-Log "======================================================================"
}
catch {
    $ErrorMessage = $_.Exception.Message

    Write-Host ""
    Write-Host "FEHLER:" -ForegroundColor Red
    Write-Host $ErrorMessage -ForegroundColor Red
    Write-Host ""
    Write-Host "FSC wird fortgesetzt (Exit Code 0)." -ForegroundColor Yellow

    Write-Log "FEHLER: $ErrorMessage"
    Write-Log "Vorgang mit Fehler beendet"
    Write-Log "Script Exit Code    : 0"
    Write-Log "======================================================================"
}

# ==================================================================================================
# FUNCTION: FSC Exit - unabhaengig vom Ergebnis immer Exit Code 0
# ==================================================================================================

exit 0
