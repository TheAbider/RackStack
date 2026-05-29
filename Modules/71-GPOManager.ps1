#region ===== GROUP POLICY MANAGER =====
# Group Policy backup, restore, and drift detection. Wraps the RSAT
# GroupPolicy module (Backup-GPO / Restore-GPO / Get-GPO / Get-GPOReport)
# into guided operations:
#   * Back up all GPOs to a timestamped folder, with per-GPO HTML + XML
#     reports and a manifest.json so the set can be diffed later.
#   * Restore a single GPO from a backup. The current GPO is backed up
#     first (pre-restore snapshot) so the change can be reverted — via the
#     interactive Undo stack, or via a Dry-Run Undo when the restore was
#     queued.
#   * Drift detection: compare the live GPOs against a baseline backup and
#     report which GPOs were added, removed, or changed since.
#
# Requires the GroupPolicy module (RSAT-GPMC / GPMC feature) and a domain
# environment. Backup + drift need GP read access; restore needs GP edit
# rights.

# Returns $true when the GroupPolicy module is importable (and imports it).
function Test-GPOAvailable {
    if (Get-Module -Name GroupPolicy) { return $true }
    if (Get-Module -ListAvailable -Name GroupPolicy -ErrorAction SilentlyContinue) {
        try { Import-Module GroupPolicy -ErrorAction Stop; return $true } catch { return $false }
    }
    return $false
}

# Status object for the Roles & Features menu line.
function Get-GPOManagerStatus {
    return [PSCustomObject]@{ Available = (Test-GPOAvailable) }
}

# Emit the "GroupPolicy not available" guidance.
function Show-GPOUnavailable {
    Write-OutputColor "  The GroupPolicy module is not available on this server." -color "Error"
    Write-OutputColor "  Install RSAT Group Policy Management, e.g.:" -color "Info"
    Write-OutputColor "    Add-WindowsFeature GPMC          (on a server)" -color "Info"
    Write-OutputColor "  GPO backup/restore/drift also requires a domain environment." -color "Info"
}

# Normalize a GPO XML report for comparison: collapse whitespace and strip
# the volatile timestamp elements so only real setting changes register as
# drift (the report stamps a fresh read/created/modified time every run).
function Get-NormalizedGPOXml {
    param([string]$Xml)
    if ([string]::IsNullOrWhiteSpace($Xml)) { return $null }
    $n = $Xml -replace '<(ReadTime|CreatedTime|ModifiedTime)>[^<]*</\1>', ''
    $n = $n -replace '\s+', ' '
    return $n.Trim()
}

# Resolve (and create) a backup root folder. Returns the path or $null.
function Resolve-GPOBackupRoot {
    param([string]$Requested = "")
    $root = $Requested
    if ([string]::IsNullOrWhiteSpace($root)) {
        $default = Join-Path $script:TempPath "GPOBackups"
        Write-OutputColor "  Backup root folder (Enter for default: $default):" -color "Info"
        $root = Read-Host "  "
        $navResult = Test-NavigationCommand -UserInput $root
        if ($navResult.ShouldReturn) { return $null }
        if ([string]::IsNullOrWhiteSpace($root)) { $root = $default }
    }
    $root = $root.Trim('"')
    if (-not (Test-Path -LiteralPath $root)) {
        try { $null = New-Item -LiteralPath $root -ItemType Directory -Force -ErrorAction Stop }
        catch { Write-OutputColor "  Could not create '$root': $($_.Exception.Message)" -color "Error"; return $null }
    }
    return $root
}

# Core backup worker. Backs up all GPOs to a timestamped folder under
# $Root, writes per-GPO HTML + XML reports and a manifest.json, and returns
# the backup folder path (or $null on failure). Non-interactive — used by
# both the menu and the CLI action.
function Invoke-GPOBackupAll {
    param([Parameter(Mandatory = $true)][string]$Root)
    if (-not (Test-GPOAvailable)) { Show-GPOUnavailable; return $null }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $folder = Join-Path $Root "GPOBackup-$stamp"
    try { $null = New-Item -LiteralPath $folder -ItemType Directory -Force -ErrorAction Stop }
    catch { Write-OutputColor "  Could not create backup folder: $($_.Exception.Message)" -color "Error"; return $null }

    $allGpos = @()
    try { $allGpos = @(Get-GPO -All -ErrorAction Stop | Sort-Object DisplayName) }
    catch { Write-OutputColor "  Could not enumerate GPOs: $($_.Exception.Message)" -color "Error"; return $null }
    if ($allGpos.Count -eq 0) {
        Write-OutputColor "  No GPOs found in this domain." -color "Warning"
        return $null
    }

    Write-OutputColor "  Backing up $($allGpos.Count) GPO(s) to:" -color "Info"
    Write-OutputColor "    $folder" -color "Info"

    $reportDir = Join-Path $folder "Reports"
    $null = New-Item -LiteralPath $reportDir -ItemType Directory -Force -ErrorAction SilentlyContinue

    $manifest = [System.Collections.Generic.List[object]]::new()
    $ok = 0; $fail = 0
    foreach ($gpo in $allGpos) {
        try {
            $bk = Backup-GPO -Guid $gpo.Id -Path $folder -Comment "RackStack backup $stamp" -ErrorAction Stop
            $safeName = ($gpo.DisplayName -replace '[^\w\-. ]', '_')
            $xmlPath = Join-Path $reportDir "$safeName.xml"
            $htmlPath = Join-Path $reportDir "$safeName.html"
            Get-GPOReport -Guid $gpo.Id -ReportType Xml -Path $xmlPath -ErrorAction SilentlyContinue
            Get-GPOReport -Guid $gpo.Id -ReportType Html -Path $htmlPath -ErrorAction SilentlyContinue
            $manifest.Add([PSCustomObject]@{
                DisplayName = $gpo.DisplayName
                Id = $gpo.Id.ToString()
                BackupId = $bk.Id.ToString()
                ReportXml = "Reports\$safeName.xml"
            })
            $ok++
        }
        catch {
            Write-OutputColor "    Failed to back up '$($gpo.DisplayName)': $($_.Exception.Message)" -color "Error"
            $fail++
        }
    }

    $manifestObj = [PSCustomObject]@{
        Tool = $script:ToolFullName
        Version = $script:ScriptVersion
        Created = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
        Domain = $env:USERDNSDOMAIN
        GpoCount = $manifest.Count
        Gpos = $manifest
    }
    try {
        $mPath = Join-Path $folder "manifest.json"
        $tmp = "$mPath.tmp"
        $manifestObj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding utf8
        Move-Item -LiteralPath $tmp -Destination $mPath -Force
    }
    catch {
        Write-OutputColor "    Warning: could not write manifest: $($_.Exception.Message)" -color "Warning"
    }

    $resultColor = if ($fail -eq 0) { "Success" } else { "Warning" }
    Write-OutputColor "  Backup complete: $ok succeeded, $fail failed." -color $resultColor
    Add-SessionChange -Category "GroupPolicy" -Description "Backed up $ok GPO(s) to $folder"
    return $folder
}

# Interactive: back up all GPOs.
function Backup-AllGPOs {
    Clear-Host
    Write-CenteredOutput "Back Up All GPOs" -color "Info"
    if (-not (Test-GPOAvailable)) { Show-GPOUnavailable; return }
    $root = Resolve-GPOBackupRoot
    if ($null -eq $root) { return }
    [void](Invoke-GPOBackupAll -Root $root)
}

# CLI entry: GPOBackup. -Config (if provided) is the backup root folder.
function Start-GPOBackup {
    param([string]$ConfigPath = "")
    $root = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) { $ConfigPath.Trim('"') } else { Join-Path $script:TempPath "GPOBackups" }
    if (-not (Test-Path -LiteralPath $root)) {
        try { $null = New-Item -LiteralPath $root -ItemType Directory -Force -ErrorAction Stop }
        catch { Write-OutputColor "  Could not create backup root '$root': $($_.Exception.Message)" -color "Error"; return $false }
    }
    $folder = Invoke-GPOBackupAll -Root $root
    return ($null -ne $folder)
}

# Compare live GPOs against a baseline backup folder (a GPOBackup-* folder
# with manifest.json + per-GPO XML reports). Returns a drift summary object.
function Compare-GPODriftAgainst {
    param([Parameter(Mandatory = $true)][string]$BaselineFolder)
    if (-not (Test-GPOAvailable)) { Show-GPOUnavailable; return $null }

    $manifestPath = Join-Path $BaselineFolder "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        Write-OutputColor "  No manifest.json in '$BaselineFolder' — not a RackStack GPO backup." -color "Error"
        return $null
    }
    $baseline = $null
    try { $baseline = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
    catch { Write-OutputColor "  Could not read baseline manifest: $($_.Exception.Message)" -color "Error"; return $null }
    $baseGpos = @($baseline.Gpos)

    $live = @()
    try { $live = @(Get-GPO -All -ErrorAction Stop) }
    catch { Write-OutputColor "  Could not enumerate live GPOs: $($_.Exception.Message)" -color "Error"; return $null }

    $liveById = @{}
    foreach ($g in $live) { $liveById[$g.Id.ToString()] = $g }
    $baseById = @{}
    foreach ($b in $baseGpos) { $baseById[$b.Id] = $b }

    $added = @(); $removed = @(); $changed = @(); $unchanged = 0

    foreach ($b in $baseGpos) {
        if (-not $liveById.ContainsKey($b.Id)) { $removed += $b.DisplayName }
    }
    foreach ($g in $live) {
        $id = $g.Id.ToString()
        if (-not $baseById.ContainsKey($id)) { $added += $g.DisplayName; continue }
        $b = $baseById[$id]
        $baseXmlPath = Join-Path $BaselineFolder $b.ReportXml
        $baseXml = if (Test-Path -LiteralPath $baseXmlPath) { Get-NormalizedGPOXml (Get-Content -LiteralPath $baseXmlPath -Raw) } else { $null }
        $liveXml = Get-NormalizedGPOXml (Get-GPOReport -Guid $g.Id -ReportType Xml -ErrorAction SilentlyContinue)
        if ($null -ne $baseXml -and $null -ne $liveXml) {
            if ($baseXml -ne $liveXml) { $changed += $g.DisplayName } else { $unchanged++ }
        }
        else {
            # Settings XML unavailable for a reliable compare — count as unchanged
            # rather than raising a false drift.
            $unchanged++
        }
    }

    return [PSCustomObject]@{
        Baseline = $BaselineFolder
        BaselineAt = $baseline.Created
        Added = $added
        Removed = $removed
        Changed = $changed
        Unchanged = $unchanged
    }
}

# Render a drift summary.
function Show-GPODriftResult {
    param([Parameter(Mandatory = $true)][PSCustomObject]$Drift)
    $addedC = @($Drift.Added).Count
    $removedC = @($Drift.Removed).Count
    $changedC = @($Drift.Changed).Count
    $total = $addedC + $removedC + $changedC
    $driftColor = if ($total -eq 0) { "Success" } else { "Warning" }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Drift vs baseline ($($Drift.BaselineAt)):" -color "Info"
    Write-OutputColor "    Unchanged: $($Drift.Unchanged)" -color "Success"
    Write-OutputColor "    Added:     $addedC" -color $driftColor
    foreach ($n in $Drift.Added) { Write-OutputColor "      + $n" -color "Warning" }
    Write-OutputColor "    Removed:   $removedC" -color $driftColor
    foreach ($n in $Drift.Removed) { Write-OutputColor "      - $n" -color "Warning" }
    Write-OutputColor "    Changed:   $changedC" -color $driftColor
    foreach ($n in $Drift.Changed) { Write-OutputColor "      ~ $n" -color "Warning" }
    Write-OutputColor "" -color "Info"
    if ($total -eq 0) {
        Write-OutputColor "  No drift — live GPOs match the baseline." -color "Success"
    }
    else {
        Write-OutputColor "  Drift detected: $total GPO(s) differ from the baseline." -color "Warning"
    }
    Add-SessionChange -Category "GroupPolicy" -Description "GPO drift check: +$addedC -$removedC ~$changedC vs baseline"
}

# Interactive: drift detection.
function Compare-GPODrift {
    Clear-Host
    Write-CenteredOutput "GPO Drift Detection" -color "Info"
    if (-not (Test-GPOAvailable)) { Show-GPOUnavailable; return }
    Write-OutputColor "  Baseline backup folder (a GPOBackup-* folder with manifest.json):" -color "Info"
    $folder = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $folder
    if ($navResult.ShouldReturn) { return }
    $folder = $folder.Trim('"')
    if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder)) {
        Write-OutputColor "  Folder not found." -color "Error"; return
    }
    $drift = Compare-GPODriftAgainst -BaselineFolder $folder
    if ($null -eq $drift) { return }
    Show-GPODriftResult -Drift $drift
}

# CLI entry: GPODrift. -Config is the baseline backup folder (required).
function Start-GPODrift {
    param([string]$ConfigPath = "")
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        Write-OutputColor "  GPODrift requires -Config <baseline-backup-folder>." -color "Error"
        return $false
    }
    $folder = $ConfigPath.Trim('"')
    if (-not (Test-Path -LiteralPath $folder)) {
        Write-OutputColor "  Baseline folder not found: $folder" -color "Error"
        return $false
    }
    $drift = Compare-GPODriftAgainst -BaselineFolder $folder
    if ($null -eq $drift) { return $false }
    Show-GPODriftResult -Drift $drift
    return $true
}

# Interactive: restore a single GPO from a backup. Captures a pre-restore
# snapshot of the current GPO so the change can be undone.
function Restore-GPOInteractive {
    Clear-Host
    Write-CenteredOutput "Restore GPO from Backup" -color "Info"
    if (-not (Test-GPOAvailable)) { Show-GPOUnavailable; return }

    Write-OutputColor "  Backup folder (a GPOBackup-* folder):" -color "Info"
    $folder = Read-Host "  "
    $navResult = Test-NavigationCommand -UserInput $folder
    if ($navResult.ShouldReturn) { return }
    $folder = $folder.Trim('"')
    if ([string]::IsNullOrWhiteSpace($folder) -or -not (Test-Path -LiteralPath $folder)) {
        Write-OutputColor "  Folder not found." -color "Error"; return
    }

    $names = @()
    try { $names = @(Get-GPOBackup -Path $folder -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName -Unique) } catch { }
    if ($names.Count -eq 0) {
        $manifestPath = Join-Path $folder "manifest.json"
        if (Test-Path -LiteralPath $manifestPath) {
            try {
                $m = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                $names = @($m.Gpos | Select-Object -ExpandProperty DisplayName -Unique)
            }
            catch { }
        }
    }
    if ($names.Count -eq 0) {
        Write-OutputColor "  No GPO backups found in that folder." -color "Error"; return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  GPOs in this backup:" -color "Info"
    $i = 1
    foreach ($n in $names) { Write-OutputColor "  [$i] $n" -color "Info"; $i++ }
    Write-OutputColor "" -color "Info"
    $sel = Read-Host "  Select GPO to restore (1-$($names.Count))"
    $navResult = Test-NavigationCommand -UserInput $sel
    if ($navResult.ShouldReturn) { return }
    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $names.Count) {
        Write-OutputColor "  Invalid selection." -color "Error"; return
    }
    $target = $names[[int]$sel - 1]

    Write-OutputColor "" -color "Warning"
    Write-OutputColor "  Restoring '$target' OVERWRITES its current settings with the backup copy." -color "Warning"
    if (-not (Confirm-UserAction -Message "Restore GPO '$target' from this backup?")) {
        Write-OutputColor "  Restore cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capName = $target
        $capFolder = $folder
        $capPre = Join-Path $script:TempPath "GPO-PreRestore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Push-DryRunStep -Label "Restore GPO '$capName' from backup" -Category "GroupPolicy" -OneWay $false `
            -Params @{ GPO = $capName; Backup = $capFolder } `
            -Preflight {
                if (-not (Get-GPO -Name $capName -ErrorAction SilentlyContinue)) { "GPO '$capName' does not currently exist (restore will recreate it)" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                # Snapshot the current GPO first so Undo can put it back.
                $existing = Get-GPO -Name $capName -ErrorAction SilentlyContinue
                if ($existing) {
                    $null = New-Item -LiteralPath $capPre -ItemType Directory -Force -ErrorAction SilentlyContinue
                    Backup-GPO -Guid $existing.Id -Path $capPre -Comment "RackStack pre-restore" -ErrorAction SilentlyContinue | Out-Null
                }
                Restore-GPO -Name $capName -Path $capFolder -ErrorAction Stop | Out-Null
            }.GetNewClosure() `
            -Undo {
                if (Test-Path -LiteralPath $capPre) {
                    Restore-GPO -Name $capName -Path $capPre -ErrorAction SilentlyContinue | Out-Null
                }
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): restore GPO '$capName'." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued GPO restore: $capName"
        return
    }

    $preFolder = Join-Path $script:TempPath "GPO-PreRestore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    try {
        $existing = Get-GPO -Name $target -ErrorAction SilentlyContinue
        if ($existing) {
            $null = New-Item -LiteralPath $preFolder -ItemType Directory -Force -ErrorAction SilentlyContinue
            Backup-GPO -Guid $existing.Id -Path $preFolder -Comment "RackStack pre-restore" -ErrorAction SilentlyContinue | Out-Null
        }
        Restore-GPO -Name $target -Path $folder -ErrorAction Stop | Out-Null
        Write-OutputColor "  Restored GPO '$target'." -color "Success"
        Add-SessionChange -Category "GroupPolicy" -Description "Restored GPO '$target' from backup"
        if ($existing) {
            Add-UndoAction -Category "GroupPolicy" -Description "Restored GPO '$target'" -UndoScript {
                param($Name, $PrePath)
                if (Test-Path -LiteralPath $PrePath) { Restore-GPO -Name $Name -Path $PrePath -ErrorAction SilentlyContinue | Out-Null }
            } -UndoParams @{ Name = $target; PrePath = $preFolder }
        }
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Restore failed: $($_.Exception.Message)" -color "Error"
    }
}

# Group Policy Manager submenu (Roles & Features > [8]).
function Show-GPOManagerManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                          GROUP POLICY MANAGER").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $available = Test-GPOAvailable
        $availText = if ($available) { "Available" } else { "Unavailable (needs RSAT GPMC + domain)" }
        $availColor = if ($available) { "Success" } else { "Warning" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "  GroupPolicy module" -Status $availText -StatusColor $availColor
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Back Up All GPOs" -Status "Export every GPO + reports + manifest" -StatusColor "Info"
        Write-MenuItem "[2]  Restore GPO from Backup" -Status "Snapshots current GPO first (undoable)" -StatusColor "Info"
        Write-MenuItem "[3]  Drift Detection" -Status "Compare live GPOs to a baseline backup" -StatusColor "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) {
            if (Invoke-NavigationAction -NavResult $navResult) { return }
            return
        }
        switch ("$choice".ToUpper()) {
            "1" { Backup-AllGPOs; Write-PressEnter }
            "2" { Restore-GPOInteractive; Write-PressEnter }
            "3" { Compare-GPODrift; Write-PressEnter }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-3 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
