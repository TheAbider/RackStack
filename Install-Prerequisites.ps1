<#
.SYNOPSIS
    RackStack Prerequisites Installer

.DESCRIPTION
    Checks for PowerShell 5.1 and installs Windows Management Framework (WMF) 5.1
    if needed. This script is compatible with PowerShell 2.0+ so it can run on
    Server 2008 R2 SP1, 2012, and 2012 R2 before WMF 5.1 is installed.

    After WMF 5.1 is installed, a reboot is required. Then run RackStack normally.

.NOTES
    Run as Administrator:
    powershell -ExecutionPolicy Bypass -File Install-Prerequisites.ps1

    Supported OS: Windows Server 2008 R2 SP1, 2012, 2012 R2
    Server 2016+ ships with PowerShell 5.1 and does not need this script.
#>

# Require elevation
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  RACKSTACK - PREREQUISITES CHECK" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""

# Check current PowerShell version
$psVer = $PSVersionTable.PSVersion
Write-Host "  PowerShell version: $($psVer.Major).$($psVer.Minor)" -ForegroundColor White

if ($psVer.Major -ge 5 -and $psVer.Minor -ge 1) {
    Write-Host ""
    Write-Host "  PowerShell 5.1 is already installed. No action needed." -ForegroundColor Green
    Write-Host "  You can run RackStack directly." -ForegroundColor Green
    Write-Host ""
    exit 0
}

# Detect OS
$os = Get-WmiObject -Class Win32_OperatingSystem
$caption = $os.Caption
$buildNumber = [int]$os.BuildNumber

Write-Host "  Operating System:   $caption" -ForegroundColor White
Write-Host "  Build Number:       $buildNumber" -ForegroundColor White
Write-Host ""

# Map OS to WMF 5.1 download
$downloadUrl = $null
$fileName = $null
$isZip = $false

if ($buildNumber -eq 7601) {
    # Server 2008 R2 SP1 (or Windows 7 SP1)
    $downloadUrl = "https://download.microsoft.com/download/6/F/5/6F5FF66C-6775-42B0-86C4-47D41F2DA187/Win7AndW2K8R2-KB3191566-x64.zip"
    $fileName = "Win7AndW2K8R2-KB3191566-x64.zip"
    $isZip = $true
    Write-Host "  Detected: Server 2008 R2 SP1" -ForegroundColor Yellow
}
elseif ($buildNumber -eq 9200) {
    # Server 2012
    $downloadUrl = "https://download.microsoft.com/download/6/F/5/6F5FF66C-6775-42B0-86C4-47D41F2DA187/W2K12-KB3191565-x64.msu"
    $fileName = "W2K12-KB3191565-x64.msu"
    Write-Host "  Detected: Server 2012" -ForegroundColor Yellow
}
elseif ($buildNumber -eq 9600) {
    # Server 2012 R2
    $downloadUrl = "https://download.microsoft.com/download/6/F/5/6F5FF66C-6775-42B0-86C4-47D41F2DA187/Win8.1AndW2K12R2-KB3191564-x64.msu"
    $fileName = "Win8.1AndW2K12R2-KB3191564-x64.msu"
    Write-Host "  Detected: Server 2012 R2" -ForegroundColor Yellow
}
else {
    Write-Host "  ERROR: Unsupported OS (build $buildNumber)." -ForegroundColor Red
    Write-Host "  WMF 5.1 supports Server 2008 R2 SP1, 2012, and 2012 R2." -ForegroundColor Red
    Write-Host "  Server 2016+ already includes PowerShell 5.1." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Check .NET Framework version (WMF 5.1 requires .NET 4.5.2+)
Write-Host ""
Write-Host "  Checking .NET Framework..." -ForegroundColor White
$netRelease = 0
try {
    $netKey = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full" -ErrorAction Stop
    $netRelease = $netKey.Release
} catch { }

$netVersion = "Unknown"
if ($netRelease -ge 528040) { $netVersion = "4.8+" }
elseif ($netRelease -ge 461808) { $netVersion = "4.7.2" }
elseif ($netRelease -ge 461308) { $netVersion = "4.7.1" }
elseif ($netRelease -ge 460798) { $netVersion = "4.7" }
elseif ($netRelease -ge 394802) { $netVersion = "4.6.2" }
elseif ($netRelease -ge 394254) { $netVersion = "4.6.1" }
elseif ($netRelease -ge 393295) { $netVersion = "4.6" }
elseif ($netRelease -ge 379893) { $netVersion = "4.5.2" }
elseif ($netRelease -ge 378675) { $netVersion = "4.5.1" }
elseif ($netRelease -ge 378389) { $netVersion = "4.5" }

Write-Host "  .NET Framework:    $netVersion (release $netRelease)" -ForegroundColor White

if ($netRelease -lt 379893) {
    Write-Host ""
    Write-Host "  ERROR: WMF 5.1 requires .NET Framework 4.5.2 or later." -ForegroundColor Red
    Write-Host "  Current version: $netVersion" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please install .NET Framework 4.5.2+ first:" -ForegroundColor Yellow
    Write-Host "  https://dotnet.microsoft.com/download/dotnet-framework" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  After installing .NET, reboot and run this script again." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Host "  .NET Framework OK" -ForegroundColor Green

# Confirm installation
Write-Host ""
Write-Host "  WMF 5.1 will be downloaded and installed." -ForegroundColor White
Write-Host "  A REBOOT IS REQUIRED after installation." -ForegroundColor Yellow
Write-Host ""
$confirm = Read-Host "  Continue? [Y/n]"
if ($confirm -match '^[Nn]') {
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit 0
}

# Download
$tempDir = "C:\Temp"
if (-not (Test-Path $tempDir)) { New-Item -Path $tempDir -ItemType Directory -Force | Out-Null }
$downloadPath = Join-Path $tempDir $fileName

Write-Host ""
Write-Host "  Downloading WMF 5.1..." -ForegroundColor Cyan
Write-Host "  URL:  $downloadUrl" -ForegroundColor DarkGray
Write-Host "  Dest: $downloadPath" -ForegroundColor DarkGray

# Force TLS 1.2 (older systems default to TLS 1.0 which Microsoft CDN rejects)
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
} catch {
    Write-Host "  WARNING: Could not enable TLS 1.2. Download may fail." -ForegroundColor Yellow
}

try {
    $client = New-Object System.Net.WebClient
    $client.DownloadFile($downloadUrl, $downloadPath)
    Write-Host "  Download complete." -ForegroundColor Green
} catch {
    Write-Host "  ERROR: Download failed: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Manual download:" -ForegroundColor Yellow
    Write-Host "  https://www.microsoft.com/en-us/download/details.aspx?id=54616" -ForegroundColor Cyan
    Write-Host "  Download '$fileName' and place it in $tempDir" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# If ZIP (Server 2008 R2), extract the MSU
$msuPath = $downloadPath
if ($isZip) {
    Write-Host "  Extracting ZIP..." -ForegroundColor Cyan
    $extractDir = Join-Path $tempDir "WMF51"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }

    try {
        # Use Shell.Application for PS 2.0 compatibility (no Expand-Archive)
        $shell = New-Object -ComObject Shell.Application
        $zip = $shell.NameSpace($downloadPath)
        $dest = $shell.NameSpace($tempDir)
        if (-not (Test-Path $extractDir)) { New-Item -Path $extractDir -ItemType Directory -Force | Out-Null }
        $dest = $shell.NameSpace($extractDir)
        $dest.CopyHere($zip.Items(), 16)  # 16 = overwrite

        # Find the MSU inside
        $msuFile = Get-ChildItem $extractDir -Filter "*.msu" | Select-Object -First 1
        if ($msuFile) {
            $msuPath = $msuFile.FullName
            Write-Host "  Extracted: $($msuFile.Name)" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: No MSU found in ZIP." -ForegroundColor Red
            exit 1
        }
    } catch {
        Write-Host "  ERROR: Extraction failed: $_" -ForegroundColor Red
        exit 1
    }
}

# Install WMF 5.1
Write-Host ""
Write-Host "  Installing WMF 5.1 (this may take several minutes)..." -ForegroundColor Cyan
Write-Host "  DO NOT close this window or restart the computer." -ForegroundColor Yellow
Write-Host ""

try {
    $process = Start-Process -FilePath "wusa.exe" -ArgumentList "`"$msuPath`" /quiet /norestart" -Wait -PassThru
    $exitCode = $process.ExitCode

    if ($exitCode -eq 0 -or $exitCode -eq 3010) {
        Write-Host "  WMF 5.1 installed successfully!" -ForegroundColor Green
    }
    elseif ($exitCode -eq 2359302) {
        Write-Host "  WMF 5.1 is already installed." -ForegroundColor Green
    }
    else {
        Write-Host "  WARNING: wusa.exe exited with code $exitCode" -ForegroundColor Yellow
        Write-Host "  The installation may have succeeded. Try rebooting." -ForegroundColor Yellow
    }
} catch {
    Write-Host "  ERROR: Installation failed: $_" -ForegroundColor Red
    exit 1
}

# Prompt for reboot
Write-Host ""
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "  INSTALLATION COMPLETE - REBOOT REQUIRED" -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  After rebooting, run RackStack:" -ForegroundColor White
Write-Host "    .\RackStack.exe" -ForegroundColor Green
Write-Host "    -- or --" -ForegroundColor DarkGray
Write-Host "    powershell -ExecutionPolicy Bypass -File RackStack.ps1" -ForegroundColor Green
Write-Host ""

$reboot = Read-Host "  Reboot now? [Y/n]"
if ($reboot -notmatch '^[Nn]') {
    Write-Host "  Rebooting in 10 seconds..." -ForegroundColor Yellow
    shutdown /r /t 10 /c "Rebooting after WMF 5.1 installation for RackStack"
} else {
    Write-Host "  Remember to reboot before running RackStack." -ForegroundColor Yellow
}

Write-Host ""
