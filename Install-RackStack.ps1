<#
.SYNOPSIS
    RackStack Bootstrap Installer — download + run, or install as a Windows program.

.DESCRIPTION
    Three modes:

    1. Download + run (default): grab RackStack.exe from the latest GitHub Release,
       SHA256-verify it against the release body, and execute it with the supplied
       CLI args. Nothing persisted beyond the staging directory.

    2. -Install: download + verify, then copy to C:\Program Files\RackStack,
       add to the system PATH, create a Start Menu shortcut, and register the
       tool under Programs and Features so Windows Settings > Apps lists it
       with a working Uninstall button. After -Install, `RackStack` works from
       any admin terminal.

    3. -Uninstall: reverse the install (remove Program Files dir, strip PATH
       entry, remove Start Menu shortcut, unregister). No network needed.

    Designed for remote deployment via Ansible, RMM tools, PDQ, or any tool
    that can execute PowerShell.

    One-liner usage (run as Administrator):
        irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1 | iex

    Install as a Windows program:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1))) -Install

    Uninstall later:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1))) -Uninstall

.PARAMETER Action
    CLI action to run after download (ignored with -Install / -Uninstall).

.PARAMETER Tier
    Profile tier: Light, Standard, Aggressive (default: Standard)

.PARAMETER Silent
    Auto-confirm all prompts

.PARAMETER InstallPath
    Staging directory for the downloaded EXE (default: C:\Temp\RackStack).
    Ignored with -Install; install mode always targets C:\Program Files\RackStack.

.PARAMETER NoRun
    Download only, do not execute

.PARAMETER Install
    Install as a Windows program (Program Files + PATH + Start Menu + Programs and Features).

.PARAMETER Uninstall
    Reverse a prior -Install. No download / network needed.

.NOTES
    Requires: PowerShell 5.1+, Administrator privileges, Internet access
#>

param(
    [ValidateSet('Cleanup', 'Debloat', 'HealthCheck', 'Batch', 'QuickScan', 'Inventory', 'DriftCheck', 'Snapshot', 'Compliance', 'Harden', 'Remediate', 'Aggregate', 'Compare', 'Export', 'Trend', 'CertCheck', 'ReportHTML', 'ListeningPorts', 'SoftwareList', 'Uptime', 'ServiceAudit', 'EventAudit', 'NetInfo', 'ScheduledExport', 'ValidateConfig', 'Watch', 'Query', 'Diff', 'Baseline', 'Alert', 'FleetScan', 'PatchStatus', 'UserAudit', 'FirewallAudit', 'TaskAudit', 'DiskAudit', 'TLSAudit', 'SMBAudit', 'DriverAudit', 'TimeAudit', 'BootAudit', 'GPOAudit', 'MemoryAudit', 'ProcessAudit', 'BackupAudit', 'ShareAudit', 'DNSAudit', 'PowerAudit', 'RegistryAudit', 'ProfileAudit', 'HyperVAudit', 'NetworkAudit', 'StorageAudit', 'FeatureAudit', 'AutoStartAudit', 'BIOSAudit', 'ClusterAudit', 'AuditPolicyAudit', 'EnvAudit', 'CrashAudit', 'LocalGroupAudit', 'WMIAudit', 'TempAudit', 'UpdatePolicyAudit', 'IISAudit', 'SSHAudit', 'BitLockerAudit', 'PrintAudit', 'CredGuardAudit', 'PortAudit', 'AntivirusAudit', 'DotNetAudit', 'RDPAudit', 'VPNAudit', 'HostsFileAudit', 'NetStatAudit', 'LicenseAudit', 'USBDeviceAudit', 'AppLockerAudit', 'EventSubAudit', 'HotfixAudit', 'SysInfoAudit', 'LogonAudit', 'ACLAudit', 'RecoveryAudit', 'ServiceAccountAudit', 'ProxyAudit', 'PendingRebootAudit', 'PageFileAudit', 'CPUAudit', 'DefenderExclusionAudit', 'KerberosAudit', 'DHCPAudit', 'NUMAAudit', 'SymlinkAudit', 'StartupScriptAudit', 'SecureChannelAudit', 'ComObjectAudit', 'FirewallLogAudit', 'ScheduledRebootAudit', 'PowerShellAudit', 'RouteTableAudit', 'TokenPrivilegeAudit', 'WindowsCapabilityAudit', 'ARPTableAudit', 'LocaleAudit', 'TaskHistoryAudit', 'NTFSAudit', 'Win11Cleanup', 'DarkMode', 'LightMode', 'iSCSIAudit', 'NICTeamAudit', 'SMBSessionAudit', 'WindowsUpdateAudit', 'ClusterQuorumAudit', 'S2DAudit', 'VirtualSwitchAudit', 'MPIOPathAudit', 'ServiceRecoveryAudit', 'VMOvercommitAudit', 'DedupAudit', 'ClusterNetworkAudit', 'ReplicaLagAudit', 'HandleLeakAudit', 'ShadowCopyAudit', 'QoSPolicyAudit', 'LiveMigrationAudit', 'DomainTrustAudit', 'DiskLatencyAudit', 'NICOffloadAudit', 'StorageTimeoutAudit', 'EventLogCapacityAudit', 'TcpSettingsAudit', 'WinRMAudit', 'ClusterHealthScore', 'VMInventoryExport', 'VMSnapshotAudit', 'StorageHealthScore', 'CSVSpaceAudit', 'SMBConnectionAudit', 'VolumeLabelAudit', 'NICErrorAudit', 'VMResourceWaste', 'HealthDashboard', 'SCCMClientAudit', 'SCOMAgentAudit', 'WACConnectivityAudit', 'AzureADAudit', 'ServerScore', 'FleetReport', 'PasswordPolicy', 'FirewallRuleAudit', 'GPResultAudit', 'DNSCacheAudit', 'TPMAudit', 'SecureBootAudit', 'TimeSkewAudit', 'NetworkProfileAudit', 'InsecureServiceAudit', 'Readiness', 'BaselineDiff', 'RotateExports', 'SLAReport', 'Validate', 'NetMap', 'PolicyCheck', 'SelfTest', 'CheckForUpdate', 'ExportLogs')]
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

    [switch]$NoRun,

    # Install as a proper Windows program: copy EXE to Program Files, add to PATH,
    # create Start Menu shortcut, register under Programs and Features. After -Install,
    # you can type `RackStack` in any admin terminal and Windows Settings → Apps will
    # list it with a working Uninstall button.
    [switch]$Install,

    # Reverse -Install: remove EXE from Program Files, strip PATH entry, remove Start
    # Menu shortcut, unregister from Programs and Features. Safe to run repeatedly.
    [switch]$Uninstall
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

# Shared paths for -Install / -Uninstall modes
$programDir       = Join-Path $env:ProgramFiles 'RackStack'
$programExe       = Join-Path $programDir 'RackStack.exe'
$startMenuDir     = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
$startMenuLnk     = Join-Path $startMenuDir 'RackStack.lnk'
$uninstallRegKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\RackStack'

# -Uninstall: reverse a prior -Install and exit. No GitHub round-trip needed.
if ($Uninstall) {
    Write-Host "  Uninstalling RackStack..." -ForegroundColor Cyan
    $removed = 0
    if (Test-Path -LiteralPath $startMenuLnk) {
        Remove-Item -LiteralPath $startMenuLnk -Force -ErrorAction SilentlyContinue
        Write-Host "  [x] Start Menu shortcut removed" -ForegroundColor Gray; $removed++
    }
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (($machinePath -split ';' | Where-Object { $_ -eq $programDir }).Count -gt 0) {
        $newPath = ($machinePath -split ';' | Where-Object { $_ -and $_ -ne $programDir }) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
        Write-Host "  [x] Removed from system PATH" -ForegroundColor Gray; $removed++
    }
    if (Test-Path -LiteralPath $uninstallRegKey) {
        Remove-Item -LiteralPath $uninstallRegKey -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [x] Programs and Features entry removed" -ForegroundColor Gray; $removed++
    }
    if (Test-Path -LiteralPath $programDir) {
        Remove-Item -LiteralPath $programDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [x] $programDir removed" -ForegroundColor Gray; $removed++
    }
    Write-Host ""
    if ($removed -eq 0) {
        Write-Host "  Nothing to uninstall — RackStack does not appear to be installed." -ForegroundColor Yellow
    } else {
        Write-Host "  RackStack uninstalled ($removed item(s) removed)." -ForegroundColor Green
    }
    Write-Host ""
    exit 0
}

# Create install directory
if (-not (Test-Path -LiteralPath $InstallPath)) {
    Write-Host "  Creating directory: $InstallPath" -ForegroundColor Gray
    New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
}

$exePath = Join-Path $InstallPath "RackStack.exe"

# Retry a web call with exponential backoff. Handles transient failures and HTTP 429 rate-limit.
function Invoke-WithRetry {
    param(
        [Parameter(Mandatory)] [scriptblock]$Script,
        [int]$MaxAttempts = 4,
        [int]$InitialDelaySeconds = 2,
        [string]$OperationName = "request"
    )
    $attempt = 0
    $delay = $InitialDelaySeconds
    while ($true) {
        $attempt++
        try {
            return & $Script
        }
        catch {
            $statusCode = $null
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { }
            $transient = $statusCode -in @(408, 429, 500, 502, 503, 504) -or $statusCode -eq $null
            if ($attempt -ge $MaxAttempts -or -not $transient) {
                throw
            }
            # HTTP 429: respect Retry-After header if present
            $retryAfter = $null
            try { $retryAfter = [int]$_.Exception.Response.Headers['Retry-After'] } catch { }
            $waitSeconds = if ($retryAfter -gt 0) { $retryAfter } else { $delay }
            Write-Host "  $OperationName failed (attempt $attempt/$MaxAttempts): $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  Retrying in $waitSeconds seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds $waitSeconds
            $delay = [math]::Min($delay * 2, 60)
        }
    }
}

# Get latest release URL from GitHub API
Write-Host "  Checking latest release..." -ForegroundColor Gray
try {
    $releaseInfo = Invoke-WithRetry -OperationName "GitHub API" -Script {
        Invoke-RestMethod -Uri "https://api.github.com/repos/TheAbider/RackStack/releases/latest" -UseBasicParsing -TimeoutSec 30
    }
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
    Write-Host "  ERROR: Failed to query GitHub releases after retries: $_" -ForegroundColor Red
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

# Extract SHA256 for RackStack.exe from the release body before we download.
# The release body contains a code-block with lines like:  <64 hex>  RackStack.exe
# This gives us a second trust root (release body, published by the repo owner)
# that survives an intermediary tampering with the asset download.
$expectedHash = $null
if ($releaseInfo.body) {
    $m = [regex]::Match($releaseInfo.body, '(?im)^\s*([a-f0-9]{64})\s+RackStack\.exe\s*$')
    if ($m.Success) { $expectedHash = $m.Groups[1].Value.ToLower() }
}

# Download
if ($needsDownload) {
    Write-Host "  Downloading RackStack.exe ($([math]::Round($exeAsset.size / 1MB, 1)) MB)..." -ForegroundColor Gray
    try {
        Invoke-WithRetry -OperationName "Download" -Script {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $exePath -UseBasicParsing -TimeoutSec 300
        } | Out-Null
        Write-Host "  Downloaded to: $exePath" -ForegroundColor Green
    }
    catch {
        Write-Host "  ERROR: Download failed after retries: $_" -ForegroundColor Red
        exit 1
    }

    # Verify SHA256 against the hash published in the release body (if available)
    if ($expectedHash) {
        try {
            $actualHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLower()
            if ($actualHash -ne $expectedHash) {
                Write-Host "  ERROR: SHA256 mismatch on downloaded RackStack.exe" -ForegroundColor Red
                Write-Host "    Expected: $expectedHash" -ForegroundColor Red
                Write-Host "    Actual:   $actualHash" -ForegroundColor Red
                Remove-Item -LiteralPath $exePath -Force -ErrorAction SilentlyContinue
                exit 1
            }
            Write-Host "  SHA256 verified against release body." -ForegroundColor Green
        } catch {
            Write-Host "  WARNING: SHA256 verification failed to run: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  NOTE: No SHA256 hash published in release body — skipping integrity verification." -ForegroundColor Yellow
    }
}

# -Install: copy to Program Files, add to PATH, Start Menu shortcut, register in Programs and Features, exit.
# The rest of the script (run-with-args) is skipped in install mode — operator will invoke the installed copy.
if ($Install) {
    Write-Host ""
    Write-Host "  Installing to $programDir..." -ForegroundColor Cyan

    # 1. Copy EXE into Program Files
    New-Item -Path $programDir -ItemType Directory -Force | Out-Null
    Copy-Item -LiteralPath $exePath -Destination $programExe -Force
    Write-Host "  [1/4] Copied RackStack.exe" -ForegroundColor Gray

    # 2. Add to system PATH so `RackStack` works from any admin terminal.
    # Also update the current process PATH so the operator can test without opening a new shell.
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (($machinePath -split ';' | Where-Object { $_ -eq $programDir }).Count -eq 0) {
        $newPath = ($machinePath.TrimEnd(';') + ';' + $programDir).TrimStart(';')
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
        $env:Path = $env:Path.TrimEnd(';') + ';' + $programDir
        Write-Host "  [2/4] Added to system PATH" -ForegroundColor Gray
    } else {
        Write-Host "  [2/4] Already on system PATH" -ForegroundColor Gray
    }

    # 3. Start Menu shortcut (All Users)
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $shortcut = $wsh.CreateShortcut($startMenuLnk)
        $shortcut.TargetPath = $programExe
        $shortcut.WorkingDirectory = $programDir
        $shortcut.Description = "RackStack"
        $shortcut.IconLocation = $programExe
        $shortcut.Save()
        Write-Host "  [3/4] Start Menu shortcut created" -ForegroundColor Gray
    } catch {
        Write-Host "  [3/4] WARNING: Start Menu shortcut failed: $_" -ForegroundColor Yellow
    }

    # 4. Register under Programs and Features — Windows Settings → Apps will now list us.
    # UninstallString runs an inline PowerShell command that reverses everything this block did.
    # Inline (vs. a saved script copy) avoids the chicken-and-egg of uninstalling the installer.
    $versionTag = $version -replace '^v', ''
    $inlineUninstall = @(
        "Remove-Item -LiteralPath '$programDir' -Recurse -Force -ErrorAction SilentlyContinue"
        "Remove-Item -LiteralPath '$startMenuLnk' -Force -ErrorAction SilentlyContinue"
        "`$p=[Environment]::GetEnvironmentVariable('Path','Machine')"
        "[Environment]::SetEnvironmentVariable('Path',((`$p -split ';' | Where-Object { `$_ -and `$_ -ne '$programDir' }) -join ';'),'Machine')"
        "Remove-Item -LiteralPath '$uninstallRegKey' -Recurse -Force -ErrorAction SilentlyContinue"
    ) -join '; '
    $uninstallCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command `"$inlineUninstall`""

    New-Item -Path $uninstallRegKey -Force | Out-Null
    Set-ItemProperty -Path $uninstallRegKey -Name 'DisplayName'     -Value 'RackStack'
    Set-ItemProperty -Path $uninstallRegKey -Name 'DisplayVersion'  -Value $versionTag
    Set-ItemProperty -Path $uninstallRegKey -Name 'Publisher'       -Value 'TheAbider'
    Set-ItemProperty -Path $uninstallRegKey -Name 'DisplayIcon'     -Value $programExe
    Set-ItemProperty -Path $uninstallRegKey -Name 'InstallLocation' -Value $programDir
    Set-ItemProperty -Path $uninstallRegKey -Name 'URLInfoAbout'    -Value 'https://github.com/TheAbider/RackStack'
    Set-ItemProperty -Path $uninstallRegKey -Name 'EstimatedSize'   -Value ([int]((Get-Item -LiteralPath $programExe).Length / 1KB)) -Type DWord
    Set-ItemProperty -Path $uninstallRegKey -Name 'NoModify'        -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallRegKey -Name 'NoRepair'        -Value 1 -Type DWord
    Set-ItemProperty -Path $uninstallRegKey -Name 'UninstallString' -Value $uninstallCmd
    Write-Host "  [4/4] Registered under Programs and Features" -ForegroundColor Gray

    Write-Host ""
    Write-Host "  RackStack v$versionTag installed." -ForegroundColor Green
    Write-Host "  - Run: " -ForegroundColor Cyan -NoNewline; Write-Host "RackStack" -ForegroundColor White -NoNewline; Write-Host "   (from any admin terminal)" -ForegroundColor Cyan
    Write-Host "  - Update check: " -ForegroundColor Cyan -NoNewline; Write-Host "RackStack -Action CheckForUpdate" -ForegroundColor White
    Write-Host "  - Uninstall: " -ForegroundColor Cyan -NoNewline; Write-Host "Windows Settings -> Apps -> RackStack -> Uninstall" -ForegroundColor White
    Write-Host ""
    exit 0
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
