<#
.SYNOPSIS
    RackStack Bootstrap Installer — download and run with one command.

.DESCRIPTION
    Downloads the latest RackStack.exe from GitHub Releases and optionally
    runs it with CLI parameters. Designed for remote deployment via
    Ansible, RMM tools, PDQ, or any tool that can execute PowerShell.

    One-liner usage (run as Administrator):
        irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1 | iex

    With parameters (download + run):
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1)))

    Ansible example:
        ansible windows -m win_shell -a "irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1 | iex"

.PARAMETER Action
    CLI action to run after download: Cleanup, Debloat, HealthCheck, QuickScan, Batch

.PARAMETER Tier
    Profile tier: Light, Standard, Aggressive (default: Standard)

.PARAMETER Silent
    Auto-confirm all prompts

.PARAMETER InstallPath
    Where to save RackStack.exe (default: C:\Temp\RackStack)

.PARAMETER NoRun
    Download only, do not execute

.NOTES
    Requires: PowerShell 5.1+, Administrator privileges, Internet access
#>

param(
    [ValidateSet('Cleanup', 'Debloat', 'HealthCheck', 'Batch', 'QuickScan', 'Inventory', 'DriftCheck', 'Snapshot', 'Compliance', 'Harden', 'Remediate', 'Aggregate', 'Compare', 'Export', 'Trend', 'CertCheck', 'ReportHTML', 'ListeningPorts', 'SoftwareList', 'Uptime', 'ServiceAudit', 'EventAudit', 'NetInfo', 'ScheduledExport', 'ValidateConfig', 'Watch', 'Query', 'Diff', 'Baseline', 'Alert', 'FleetScan', 'PatchStatus', 'UserAudit', 'FirewallAudit', 'TaskAudit', 'DiskAudit', 'TLSAudit', 'SMBAudit', 'DriverAudit', 'TimeAudit', 'BootAudit', 'GPOAudit', 'MemoryAudit', 'ProcessAudit', 'BackupAudit', 'ShareAudit', 'DNSAudit', 'PowerAudit', 'RegistryAudit', 'ProfileAudit', 'HyperVAudit', 'NetworkAudit', 'StorageAudit', 'FeatureAudit', 'AutoStartAudit', 'BIOSAudit', 'ClusterAudit', 'AuditPolicyAudit', 'EnvAudit', 'CrashAudit', 'LocalGroupAudit', 'WMIAudit', 'TempAudit', 'UpdatePolicyAudit', 'IISAudit', 'SSHAudit', 'BitLockerAudit', 'PrintAudit', 'CredGuardAudit', 'PortAudit', 'AntivirusAudit', 'DotNetAudit', 'RDPAudit', 'VPNAudit')]
    [string]$Action = 'QuickScan',

    [ValidateSet('Light', 'Standard', 'Aggressive')]
    [string]$Tier = 'Standard',

    [switch]$Silent,

    [ValidateSet('Console', 'JSON')]
    [string]$OutputFormat = 'Console',

    [switch]$Version,

    [switch]$ListActions,

    [switch]$Quiet,

    [string]$InstallPath = 'C:\Temp\RackStack',

    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'

# Enforce TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Write-Host ""
Write-Host "  RackStack Bootstrap Installer" -ForegroundColor Cyan
Write-Host "  =============================" -ForegroundColor Cyan
Write-Host ""

# Check for admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  ERROR: This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "  Run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

# Create install directory
if (-not (Test-Path -LiteralPath $InstallPath)) {
    Write-Host "  Creating directory: $InstallPath" -ForegroundColor Gray
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
}

$exePath = Join-Path $InstallPath "RackStack.exe"

# Get latest release URL from GitHub API
Write-Host "  Checking latest release..." -ForegroundColor Gray
try {
    $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/TheAbider/RackStack/releases/latest" -UseBasicParsing
    $version = $releaseInfo.tag_name
    $exeAsset = $releaseInfo.assets | Where-Object { $_.name -eq "RackStack.exe" } | Select-Object -First 1

    if (-not $exeAsset) {
        Write-Host "  ERROR: RackStack.exe not found in latest release." -ForegroundColor Red
        exit 1
    }

    $downloadUrl = $exeAsset.browser_download_url
    Write-Host "  Latest version: $version" -ForegroundColor Green
}
catch {
    Write-Host "  ERROR: Failed to query GitHub releases: $_" -ForegroundColor Red
    exit 1
}

# Check if we already have this version
$needsDownload = $true
if (Test-Path -LiteralPath $exePath) {
    try {
        $existingVersion = (Get-Item $exePath).VersionInfo.FileVersion
        if ($existingVersion -and $version -eq "v$existingVersion") {
            Write-Host "  Already up to date ($version)" -ForegroundColor Green
            $needsDownload = $false
        }
        else {
            Write-Host "  Updating from v$existingVersion to $version" -ForegroundColor Yellow
        }
    }
    catch {
        # Can't read version, re-download
    }
}

# Download
if ($needsDownload) {
    Write-Host "  Downloading RackStack.exe ($([math]::Round($exeAsset.size / 1MB, 1)) MB)..." -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $exePath -UseBasicParsing
        Write-Host "  Downloaded to: $exePath" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: Download failed: $_" -ForegroundColor Red
        exit 1
    }
}

if ($NoRun) {
    Write-Host ""
    Write-Host "  Download complete. Run manually:" -ForegroundColor Cyan
    Write-Host "    $exePath -Action $Action -Tier $Tier -Silent" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Run with CLI parameters
Write-Host ""
Write-Host "  Launching RackStack -Action $Action -Tier $Tier$(if ($Silent) { ' -Silent' })$(if ($OutputFormat -ne 'Console') { " -OutputFormat $OutputFormat" })..." -ForegroundColor Cyan
Write-Host ""

$exeArgs = @("-Action", $Action, "-Tier", $Tier)
if ($Silent) { $exeArgs += "-Silent" }
if ($OutputFormat -ne 'Console') { $exeArgs += @("-OutputFormat", $OutputFormat) }

try {
    $process = Start-Process -FilePath $exePath -ArgumentList $exeArgs -Wait -PassThru -NoNewWindow
    exit $process.ExitCode
}
catch {
    Write-Host "  ERROR: Failed to launch RackStack: $_" -ForegroundColor Red
    exit 1
}
