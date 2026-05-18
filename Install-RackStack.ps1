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
    [ValidateSet('Cleanup', 'Debloat', 'HealthCheck', 'Batch', 'QuickScan', 'Inventory', 'DriftCheck', 'Snapshot', 'Compliance', 'Harden', 'Remediate', 'Aggregate', 'Compare', 'Export', 'Trend', 'CertCheck', 'ReportHTML', 'ListeningPorts', 'SoftwareList', 'Uptime', 'ServiceAudit', 'EventAudit', 'NetInfo', 'ScheduledExport', 'ValidateConfig', 'Watch', 'Query', 'Diff', 'Baseline', 'Alert', 'FleetScan', 'PatchStatus', 'UserAudit', 'FirewallAudit', 'TaskAudit', 'DiskAudit', 'TLSAudit', 'SMBAudit', 'DriverAudit', 'TimeAudit', 'BootAudit', 'GPOAudit', 'MemoryAudit', 'ProcessAudit', 'BackupAudit', 'ShareAudit', 'DNSAudit', 'PowerAudit', 'RegistryAudit', 'ProfileAudit', 'HyperVAudit', 'NetworkAudit', 'StorageAudit', 'FeatureAudit', 'AutoStartAudit', 'BIOSAudit', 'ClusterAudit', 'AuditPolicyAudit', 'EnvAudit', 'CrashAudit', 'LocalGroupAudit', 'WMIAudit', 'TempAudit', 'UpdatePolicyAudit', 'IISAudit', 'SSHAudit', 'BitLockerAudit', 'PrintAudit', 'CredGuardAudit', 'PortAudit', 'AntivirusAudit', 'DotNetAudit', 'RDPAudit', 'VPNAudit', 'HostsFileAudit', 'NetStatAudit', 'LicenseAudit', 'USBDeviceAudit', 'AppLockerAudit', 'EventSubAudit', 'HotfixAudit', 'SysInfoAudit', 'LogonAudit', 'ACLAudit', 'RecoveryAudit', 'ServiceAccountAudit', 'ProxyAudit', 'PendingRebootAudit', 'PageFileAudit', 'CPUAudit', 'DefenderExclusionAudit', 'KerberosAudit', 'DHCPAudit', 'NUMAAudit', 'SymlinkAudit', 'StartupScriptAudit', 'SecureChannelAudit', 'ComObjectAudit', 'FirewallLogAudit', 'ScheduledRebootAudit', 'PowerShellAudit', 'RouteTableAudit', 'TokenPrivilegeAudit', 'WindowsCapabilityAudit', 'ARPTableAudit', 'LocaleAudit', 'TaskHistoryAudit', 'NTFSAudit', 'Win11Cleanup', 'DarkMode', 'LightMode', 'iSCSIAudit', 'NICTeamAudit', 'SMBSessionAudit', 'WindowsUpdateAudit', 'ClusterQuorumAudit', 'S2DAudit', 'VirtualSwitchAudit', 'MPIOPathAudit', 'ServiceRecoveryAudit', 'VMOvercommitAudit', 'DedupAudit', 'ClusterNetworkAudit', 'ReplicaLagAudit', 'HandleLeakAudit', 'ShadowCopyAudit', 'QoSPolicyAudit', 'LiveMigrationAudit', 'DomainTrustAudit', 'DiskLatencyAudit', 'NICOffloadAudit', 'StorageTimeoutAudit', 'EventLogCapacityAudit', 'TcpSettingsAudit', 'WinRMAudit', 'ClusterHealthScore', 'VMInventoryExport', 'VMSnapshotAudit', 'StorageHealthScore', 'CSVSpaceAudit', 'SMBConnectionAudit', 'VolumeLabelAudit', 'NICErrorAudit', 'VMResourceWaste', 'HealthDashboard', 'SCCMClientAudit', 'SCOMAgentAudit', 'WACConnectivityAudit', 'AzureADAudit', 'ServerScore', 'FleetReport', 'PasswordPolicy', 'FirewallRuleAudit', 'GPResultAudit', 'DNSCacheAudit', 'TPMAudit', 'SecureBootAudit', 'TimeSkewAudit', 'NetworkProfileAudit', 'InsecureServiceAudit', 'Readiness', 'BaselineDiff', 'RotateExports', 'SLAReport', 'Validate', 'NetMap', 'PolicyCheck', 'SelfTest', 'CheckForUpdate', 'ExportLogs', 'UpdateSelf', 'Rollback', 'ScheduleUpdateCheck', 'Dashboard', 'History', 'Replay')]
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
    [switch]$Uninstall,

    # Restore the previous RackStack.exe from RackStack.exe.old. Use this if an UpdateSelf
    # (or a re-run of -Install) produced a broken binary. Works even when the installed EXE
    # is too broken to run — no dependency on the tool itself.
    [switch]$Rollback,

    # Bypass the SHA256 integrity gate. Without this switch the installer refuses to
    # run RackStack.exe unless the release body publishes a hash AND the downloaded
    # asset matches it. Only set this when you knowingly accept the network-path risk.
    [switch]$AllowUnverified
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

# Refuse to run two installer instances simultaneously. The Install / Update path
# renames RackStack.exe → .old to make room for the new binary; two concurrent
# runs both performing that rename would have the second clobber the first's
# backup (demoting it to .pending-delete via a re-rename) and leave the on-disk
# state in a half-updated condition that's hard to recover from automatically.
# Held only while THIS process runs; releases on exit or kill.
$installerMutex = $null
$installerMutexAcquired = $false
try {
    $installerMutex = New-Object System.Threading.Mutex($false, 'Global\TheAbider.RackStack.Installer')
    $installerMutexAcquired = $installerMutex.WaitOne([TimeSpan]::FromSeconds(2))
} catch {
    # If the mutex itself can't be created (e.g., unusual ACL), continue without
    # the guard rather than blocking install entirely. The user is still admin.
    $installerMutex = $null
}
if ($null -ne $installerMutex -and -not $installerMutexAcquired) {
    Write-Host "  ERROR: Another RackStack installer instance is already running." -ForegroundColor Red
    Write-Host "  Wait for it to finish before starting another -Install / -Update / -Uninstall." -ForegroundColor Yellow
    exit 1
}

# Shared paths for -Install / -Uninstall modes
$programDir       = Join-Path $env:ProgramFiles 'RackStack'
$programExe       = Join-Path $programDir 'RackStack.exe'
$startMenuDir     = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
$startMenuLnk     = Join-Path $startMenuDir 'RackStack.lnk'
$uninstallRegKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\RackStack'

# -Rollback: swap RackStack.exe.old back to the primary name. No download needed.
# Works even when the installed tool is too broken to run its own -Action Rollback.
if ($Rollback) {
    Write-Host "  Rolling back RackStack..." -ForegroundColor Cyan
    $backup = "$programExe.old"
    if (-not (Test-Path -LiteralPath $backup)) {
        Write-Host "  No backup found at $backup" -ForegroundColor Yellow
        Write-Host "  Nothing to roll back to — was UpdateSelf ever run?" -ForegroundColor Yellow
        exit 1
    }
    $purged = "$programExe.pending-delete"
    try {
        if (Test-Path -LiteralPath $purged) { Remove-Item -LiteralPath $purged -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $programExe) {
            Rename-Item -LiteralPath $programExe -NewName 'RackStack.exe.pending-delete' -Force -ErrorAction Stop
        }
        Rename-Item -LiteralPath $backup -NewName 'RackStack.exe' -Force -ErrorAction Stop

        # Refresh registry DisplayVersion from the rolled-back EXE so Programs and Features is accurate
        if (Test-Path -LiteralPath $uninstallRegKey) {
            try {
                $rolledVer = (Get-Item -LiteralPath $programExe -ErrorAction Stop).VersionInfo.FileVersion
                if ($rolledVer) { Set-ItemProperty -Path $uninstallRegKey -Name 'DisplayVersion' -Value $rolledVer -ErrorAction SilentlyContinue }
            } catch { }
        }
        Write-Host "  Rolled back. The previous RackStack.exe is now primary." -ForegroundColor Green
        Write-Host "  The superseded binary will be removed on next launch." -ForegroundColor Gray
    } catch {
        Write-Host "  ERROR: Rollback failed: $_" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# -Uninstall: reverse a prior -Install and exit. No GitHub round-trip needed.
if ($Uninstall) {
    Write-Host "  Uninstalling RackStack..." -ForegroundColor Cyan
    $removed = 0

    # Stop any running RackStack process first so the Program Files directory removal
    # below isn't silently blocked by file locks (Remove-Item -SilentlyContinue would
    # otherwise report "removed" while leaving the EXE on disk).
    try {
        $running = @(Get-Process -Name 'RackStack' -ErrorAction SilentlyContinue)
        if ($running.Count -gt 0) {
            Write-Host "  [.] Stopping $($running.Count) running RackStack process(es)..." -ForegroundColor Gray
            $running | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        }
    } catch { }

    if (Test-Path -LiteralPath $startMenuLnk) {
        Remove-Item -LiteralPath $startMenuLnk -Force -ErrorAction SilentlyContinue
        Write-Host "  [x] Start Menu shortcut removed" -ForegroundColor Gray; $removed++
    }
    # Case-insensitive PATH compare with trailing-slash + whitespace normalization
    # so a duplicate that drifted (`...\RackStack\` vs `...\RackStack`) still strips cleanly.
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $normalize = { param($p) ($p -as [string]).Trim().TrimEnd('\','/').ToLowerInvariant() }
    $programDirNorm = & $normalize $programDir
    $pathEntries = @($machinePath -split ';')
    $kept = @($pathEntries | Where-Object { $_ -and ((& $normalize $_) -ne $programDirNorm) })
    if ($kept.Count -lt @($pathEntries | Where-Object { $_ }).Count) {
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'Machine')
        Write-Host "  [x] Removed from system PATH" -ForegroundColor Gray; $removed++
    }
    if (Test-Path -LiteralPath $uninstallRegKey) {
        Remove-Item -LiteralPath $uninstallRegKey -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [x] Programs and Features entry removed" -ForegroundColor Gray; $removed++
    }
    if (Test-Path -LiteralPath $programDir) {
        Remove-Item -LiteralPath $programDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $programDir) {
            Write-Host "  [!] $programDir could not be fully removed (files may still be in use)" -ForegroundColor Yellow
        } else {
            Write-Host "  [x] $programDir removed" -ForegroundColor Gray; $removed++
        }
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

    # Verify SHA256 against the hash published in the release body. Refusal is the default
    # outcome of any verification failure: missing hash in release body, hash mismatch,
    # or Get-FileHash exception. Pass -AllowUnverified to opt out (and own the risk).
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
            if ($AllowUnverified) {
                Write-Host "  WARNING: SHA256 verification raised an error; -AllowUnverified set, continuing: $_" -ForegroundColor Yellow
            } else {
                Write-Host "  ERROR: SHA256 verification failed to run: $_" -ForegroundColor Red
                Write-Host "    Pass -AllowUnverified to override (you own the risk)." -ForegroundColor Yellow
                Remove-Item -LiteralPath $exePath -Force -ErrorAction SilentlyContinue
                exit 1
            }
        }
    } elseif ($AllowUnverified) {
        Write-Host "  NOTE: No SHA256 hash published in release body — proceeding under -AllowUnverified." -ForegroundColor Yellow
    } else {
        Write-Host "  ERROR: No SHA256 hash published in this release body — refusing to run unverified RackStack.exe." -ForegroundColor Red
        Write-Host "    Re-run with -AllowUnverified to bypass (only do this if you trust your network path)." -ForegroundColor Yellow
        Remove-Item -LiteralPath $exePath -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

# -Install: copy to Program Files, add to PATH, Start Menu shortcut, register in Programs and Features, exit.
# The rest of the script (run-with-args) is skipped in install mode — operator will invoke the installed copy.
if ($Install) {
    Write-Host ""
    Write-Host "  Installing to $programDir..." -ForegroundColor Cyan

    # 1. Copy EXE into Program Files.
    # If we're upgrading an existing install, the current RackStack.exe may be running and
    # therefore locked against overwrite/delete. Windows allows *rename* of a running EXE,
    # so we rename the old one aside first; this doubles as the backup for -Action Rollback.
    New-Item -Path $programDir -ItemType Directory -Force | Out-Null
    if (Test-Path -LiteralPath $programExe) {
        $backupName = 'RackStack.exe.old'
        $backup = Join-Path $programDir $backupName
        if (Test-Path -LiteralPath $backup) {
            # Previous backup exists — move it to pending-delete so startup cleans it up
            $pending = Join-Path $programDir 'RackStack.exe.pending-delete'
            if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force -ErrorAction SilentlyContinue }
            try { Rename-Item -LiteralPath $backup -NewName 'RackStack.exe.pending-delete' -Force -ErrorAction Stop } catch { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
        }
        try {
            Rename-Item -LiteralPath $programExe -NewName $backupName -Force -ErrorAction Stop
        } catch {
            Write-Host "  ERROR: Could not rename existing RackStack.exe aside: $_" -ForegroundColor Red
            Write-Host "  Close any running RackStack processes and try again, or use -Rollback." -ForegroundColor Yellow
            exit 1
        }
    }
    Copy-Item -LiteralPath $exePath -Destination $programExe -Force
    Write-Host "  [1/4] Copied RackStack.exe (upgrade-safe rename, prior version saved as .old)" -ForegroundColor Gray

    # 2. Add to system PATH so `RackStack` works from any admin terminal.
    # Also update the current process PATH so the operator can test without opening a new shell.
    # Case-insensitive compare with trailing-slash + whitespace normalization, matching the
    # Uninstall path's normalize logic — without this a previously-installed PATH entry that
    # differs only in case (e.g. `c:\program files\rackstack`) would not be detected and the
    # installer would add a second, duplicate entry.
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $pathNormalize = { param($p) ($p -as [string]).Trim().TrimEnd('\','/').ToLowerInvariant() }
    $programDirNormInstall = & $pathNormalize $programDir
    $hasEntry = @($machinePath -split ';' | Where-Object { $_ -and ((& $pathNormalize $_) -eq $programDirNormInstall) }).Count -gt 0
    if (-not $hasEntry) {
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
    # Windows Settings → Apps → Uninstall executes this string verbatim. Build a self-contained
    # script that mirrors the top-of-file -Uninstall path: stop running processes first, then
    # case-insensitively strip the PATH entry, then remove the directory + shortcut + reg key.
    # Single-quote literals are escaped by doubling so paths with embedded apostrophes survive.
    $progDirEscaped       = $programDir -replace "'", "''"
    $startMenuLnkEscaped  = $startMenuLnk -replace "'", "''"
    $uninstallRegKeyEsc   = $uninstallRegKey -replace "'", "''"
    $inlineUninstall = @(
        "Get-Process -Name 'RackStack' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue"
        "Start-Sleep -Milliseconds 500"
        "`$n={param(`$p) (`$p -as [string]).Trim().TrimEnd('\','/').ToLowerInvariant()}"
        "`$d=& `$n '$progDirEscaped'"
        "`$p=[Environment]::GetEnvironmentVariable('Path','Machine')"
        "[Environment]::SetEnvironmentVariable('Path',((`$p -split ';' | Where-Object { `$_ -and ((& `$n `$_) -ne `$d) }) -join ';'),'Machine')"
        "Remove-Item -LiteralPath '$startMenuLnkEscaped' -Force -ErrorAction SilentlyContinue"
        "Remove-Item -LiteralPath '$uninstallRegKeyEsc' -Recurse -Force -ErrorAction SilentlyContinue"
        "Remove-Item -LiteralPath '$progDirEscaped' -Recurse -Force -ErrorAction SilentlyContinue"
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
    Write-Host "  [4/5] Registered under Programs and Features" -ForegroundColor Gray

    # 5. Generate an opt-in tab completer. User dot-sources it from their PS profile to enable
    # `RackStack -Action <TAB>` autocompletion. We query the freshly installed EXE for its action
    # list so the completer always matches the installed version's supported actions.
    $tabCompletePath = Join-Path $programDir 'RackStack-TabComplete.ps1'
    try {
        $rawJson = & $programExe -ListActions -OutputFormat JSON -Quiet 2>$null | Out-String
        $actionNames = @()
        if ($rawJson -and $rawJson.Trim().StartsWith('[')) {
            $actionNames = @((ConvertFrom-Json -InputObject $rawJson) | ForEach-Object { $_.Action })
        }
        if ($actionNames.Count -gt 0) {
            $actionLiteral = ($actionNames | ForEach-Object { "'$_'" }) -join ','
            # Single-quoted here-string so we don't have to escape the many $ signs inside the completer.
            # Only the action list gets templated in via -replace.
            $tabBody = @'
# RackStack tab completion — opt-in. Dot-source this file from your PowerShell profile to enable:
#   notepad $PROFILE.AllUsersAllHosts
#   . "C:\Program Files\RackStack\RackStack-TabComplete.ps1"
# After reloading your shell, `RackStack -Action <TAB>` will cycle through every available action.
Register-ArgumentCompleter -Native -CommandName RackStack -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $line = $commandAst.ToString()
    $tokens = $line -split '\s+'
    $prev = if ($tokens.Count -ge 2) { $tokens[$tokens.Count - 2] } else { '' }
    if ($prev -ieq '-Action') {
        @(__ACTIONS__) | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    } elseif ($prev -ieq '-Tier') {
        @('Light','Standard','Aggressive') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    } elseif ($prev -ieq '-OutputFormat') {
        @('Console','JSON') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
'@
            $tabContent = $tabBody -replace '__ACTIONS__', $actionLiteral
            [System.IO.File]::WriteAllText($tabCompletePath, $tabContent, (New-Object System.Text.UTF8Encoding $true))
            Write-Host "  [5/5] Generated tab completer ($($actionNames.Count) actions)" -ForegroundColor Gray
        } else {
            Write-Host "  [5/5] Skipped tab completer (action list not available from EXE)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  [5/5] Skipped tab completer: $_" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  RackStack v$versionTag installed." -ForegroundColor Green
    Write-Host "  - Run: " -ForegroundColor Cyan -NoNewline; Write-Host "RackStack" -ForegroundColor White -NoNewline; Write-Host "   (from any admin terminal)" -ForegroundColor Cyan
    Write-Host "  - Check for updates: " -ForegroundColor Cyan -NoNewline; Write-Host "RackStack -Action CheckForUpdate" -ForegroundColor White
    Write-Host "  - Update in place: " -ForegroundColor Cyan -NoNewline; Write-Host "RackStack -Action UpdateSelf" -ForegroundColor White
    Write-Host "  - Weekly update task: " -ForegroundColor Cyan -NoNewline; Write-Host "RackStack -Action ScheduleUpdateCheck" -ForegroundColor White
    Write-Host "  - Tab completion: " -ForegroundColor Cyan -NoNewline; Write-Host ". '$tabCompletePath'" -ForegroundColor White -NoNewline; Write-Host "   (add to `$PROFILE)" -ForegroundColor Cyan
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
