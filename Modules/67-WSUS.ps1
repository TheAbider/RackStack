#region ===== WSUS SERVER SETUP =====
# Installs and configures Windows Server Update Services (WSUS) — Microsoft's
# on-premises update-distribution role. RackStack already configures update
# *clients*; this module stands up the WSUS *server* they point at.
#
# Flow: install the UpdateServices role -> run the one-time post-install
# (wsusutil.exe postinstall, which provisions the content directory and the
# Windows Internal Database) -> apply a sane default configuration
# (classifications, languages, sync schedule).
#
# Config: $script:WSUS (see 00-Initialization.ps1, overridable via
# defaults.json "WSUS").

# Returns $true if a WSUS content path is configured.
function Test-WSUSConfigured {
    if ($null -eq $script:WSUS) { return $false }
    return (-not [string]::IsNullOrWhiteSpace($script:WSUS.ContentPath))
}

# Returns $true if the UpdateServices role is installed.
function Test-WSUSInstalled {
    try {
        $feat = Get-WindowsFeature -Name 'UpdateServices' -ErrorAction Stop
        return ($feat -and $feat.InstallState -eq 'Installed')
    }
    catch {
        return $false
    }
}

# Returns $true if WSUS post-install has run (Get-WsusServer succeeds).
function Test-WSUSPostInstalled {
    try {
        $null = Get-WsusServer -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# Locate wsusutil.exe — the WSUS post-install / maintenance CLI.
function Get-WSUSUtilPath {
    $candidates = @(
        (Join-Path $env:ProgramW6432 'Update Services\Tools\wsusutil.exe')
        (Join-Path ${env:ProgramFiles} 'Update Services\Tools\wsusutil.exe')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

# Query WSUS state. Returns a hashtable describing role/post-install state
# and, when post-installed, update + computer counts and last sync time.
function Get-WSUSStatus {
    $result = @{
        RoleInstalled = $false
        PostInstalled = $false
        ContentPath   = ''
        UpdateCount   = 0
        ComputerCount = 0
        LastSync      = 'Never'
        SyncStatus    = ''
    }

    $result.RoleInstalled = Test-WSUSInstalled
    if (-not $result.RoleInstalled) { return $result }

    $result.PostInstalled = Test-WSUSPostInstalled
    if (-not $result.PostInstalled) { return $result }

    try {
        $wsus = Get-WsusServer -ErrorAction Stop
        $cfg = $wsus.GetConfiguration()
        $result.ContentPath = [string]$cfg.LocalContentCachePath

        $status = $wsus.GetStatus()
        $result.UpdateCount = [int]$status.UpdateCount
        $result.ComputerCount = [int]$status.ComputerTargetCount

        $sub = $wsus.GetSubscription()
        $lastSync = $sub.GetLastSynchronizationInfo()
        if ($lastSync -and $lastSync.StartTime -and $lastSync.StartTime.Year -gt 2000) {
            $result.LastSync = $lastSync.StartTime.ToString('yyyy-MM-dd HH:mm')
            $result.SyncStatus = [string]$lastSync.Result
        }
    }
    catch {
        # Post-installed but the API call failed — leave counts at defaults.
    }

    return $result
}

# Install the WSUS (UpdateServices) role plus its management tools. Uses the
# shared Install-WindowsFeatureWithTimeout wrapper so the install runs in a
# job with a progress indicator and the 30-minute feature-install timeout.
function Install-WSUSRole {
    if (Test-WSUSInstalled) {
        Write-OutputColor "  The UpdateServices (WSUS) role is already installed." -color "Info"
        return $true
    }
    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  WSUS is a Windows Server role — this OS is not a server SKU." -color "Error"
        return $false
    }

    Write-OutputColor "  Installing the WSUS role (UpdateServices + management tools)..." -color "Info"
    Write-OutputColor "  This can take several minutes." -color "Info"
    $install = Install-WindowsFeatureWithTimeout -FeatureName 'UpdateServices' -DisplayName 'WSUS' -IncludeManagementTools
    if (-not $install.Success) {
        Write-OutputColor "  WSUS role install failed." -color "Error"
        if ($install.Error) { Write-OutputColor "  $($install.Error.Trim())" -color "Error" }
        return $false
    }

    if (Test-WSUSInstalled) {
        Write-OutputColor "  WSUS role installed." -color "Success"
        Add-SessionChange -Category "Roles" -Description "Installed WSUS (UpdateServices) role"
        if ($null -ne $install.Result -and $install.Result.RestartNeeded -eq 'Yes') {
            Write-OutputColor "  A restart is required before post-install can run." -color "Warning"
            $script:RebootNeeded = $true
        }
        return $true
    }
    Write-OutputColor "  Role install completed but UpdateServices is not reporting installed." -color "Error"
    return $false
}

# Run the one-time WSUS post-install. Provisions the content directory and the
# Windows Internal Database. Idempotent-ish: re-running on an already-post-
# installed server is a no-op that wsusutil handles.
function Invoke-WSUSPostInstall {
    if (-not (Test-WSUSInstalled)) {
        Write-OutputColor "  Install the WSUS role before running post-install." -color "Error"
        return $false
    }
    if (Test-WSUSPostInstalled) {
        Write-OutputColor "  WSUS post-install has already run." -color "Info"
        return $true
    }
    if (-not (Test-WSUSConfigured)) {
        Write-OutputColor "  Set WSUS.ContentPath in defaults.json before post-install." -color "Error"
        return $false
    }

    $contentPath = $script:WSUS.ContentPath
    # Validate the content path: no metacharacters (it's passed to wsusutil),
    # must be an absolute local path.
    if ($contentPath -match '["`&|<>^%]' -or $contentPath -match '[\x00-\x1F]') {
        Write-OutputColor "  WSUS.ContentPath contains unsafe characters — refusing." -color "Error"
        return $false
    }
    if ($contentPath -notmatch '^[A-Za-z]:\\') {
        Write-OutputColor "  WSUS.ContentPath must be an absolute local path (e.g. C:\WSUS)." -color "Error"
        return $false
    }

    $wsusUtil = Get-WSUSUtilPath
    if ($null -eq $wsusUtil) {
        Write-OutputColor "  wsusutil.exe not found — is the role fully installed?" -color "Error"
        return $false
    }

    if (-not (Test-Path -LiteralPath $contentPath)) {
        try {
            $null = New-Item -Path $contentPath -ItemType Directory -Force -ErrorAction Stop
        }
        catch {
            Write-OutputColor "  Could not create content directory '$contentPath': $($_.Exception.Message)" -color "Error"
            return $false
        }
    }

    Write-OutputColor "  Running WSUS post-install (content: $contentPath)..." -color "Info"
    Write-OutputColor "  This provisions the Windows Internal Database and can take several minutes." -color "Info"
    try {
        # wsusutil postinstall — array-form ArgumentList; CONTENT_DIR was validated above.
        $proc = Start-Process -FilePath $wsusUtil `
            -ArgumentList @('postinstall', "CONTENT_DIR=$contentPath") `
            -Wait -PassThru -NoNewWindow -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            Write-OutputColor "  wsusutil postinstall exited with code $($proc.ExitCode)." -color "Error"
            Write-OutputColor "  See %ProgramFiles%\Update Services\LogFiles\ for the post-install log." -color "Warning"
            return $false
        }
    }
    catch {
        Write-OutputColor "  WSUS post-install failed: $($_.Exception.Message)" -color "Error"
        return $false
    }

    if (Test-WSUSPostInstalled) {
        Write-OutputColor "  WSUS post-install complete." -color "Success"
        Add-SessionChange -Category "Roles" -Description "Completed WSUS post-install (content: $contentPath)"
        return $true
    }
    Write-OutputColor "  Post-install ran but Get-WsusServer still fails." -color "Warning"
    return $false
}

# Apply a sane default WSUS configuration: update classifications, the
# preferred update language, and a daily synchronization schedule.
function Set-WSUSDefaultConfiguration {
    if (-not (Test-WSUSPostInstalled)) {
        Write-OutputColor "  Run WSUS post-install before configuring." -color "Error"
        return $false
    }

    try {
        $wsus = Get-WsusServer -ErrorAction Stop
    }
    catch {
        Write-OutputColor "  Could not connect to the WSUS server: $($_.Exception.Message)" -color "Error"
        return $false
    }

    Write-OutputColor "  Applying default WSUS configuration..." -color "Info"

    # 1. Update language — restrict to the configured language to keep the
    #    content cache from ballooning with every locale.
    $lang = if (-not [string]::IsNullOrWhiteSpace($script:WSUS.UpdateLanguage)) { $script:WSUS.UpdateLanguage } else { 'en' }
    try {
        $cfg = $wsus.GetConfiguration()
        $cfg.AllUpdateLanguagesEnabled = $false
        $cfg.SetEnabledUpdateLanguages($lang)
        $cfg.Save()
        Write-OutputColor "  Update language set to '$lang'." -color "Success"
    }
    catch {
        Write-OutputColor "  Could not set update language: $($_.Exception.Message)" -color "Warning"
    }

    # 2. Classifications — enable the security-relevant ones by default.
    $wantClassifications = if ($script:WSUS.Classifications -and @($script:WSUS.Classifications).Count -gt 0) {
        $script:WSUS.Classifications
    } else {
        @('Critical Updates', 'Security Updates', 'Definition Updates', 'Update Rollups')
    }
    try {
        $allClass = $wsus.GetUpdateClassifications()
        $selected = $allClass | Where-Object { $_.Title -in $wantClassifications }
        if ($selected) {
            $sub = $wsus.GetSubscription()
            $coll = New-Object Microsoft.UpdateServices.Administration.UpdateClassificationCollection
            foreach ($c in $selected) { [void]$coll.Add($c) }
            $sub.SetUpdateClassifications($coll)
            $sub.Save()
            Write-OutputColor "  Enabled classifications: $(($selected | ForEach-Object { $_.Title }) -join ', ')" -color "Success"
        }
    }
    catch {
        Write-OutputColor "  Could not set update classifications: $($_.Exception.Message)" -color "Warning"
    }

    # 3. Synchronization schedule — one automatic sync per day at the
    #    configured hour (default 03:00).
    $syncHour = if ($null -ne $script:WSUS.SyncHour) { [int]$script:WSUS.SyncHour } else { 3 }
    if ($syncHour -lt 0 -or $syncHour -gt 23) { $syncHour = 3 }
    try {
        $sub = $wsus.GetSubscription()
        $sub.SynchronizeAutomatically = $true
        $sub.SynchronizeAutomaticallyTimeOfDay = (New-TimeSpan -Hours $syncHour)
        $sub.NumberOfSynchronizationsPerDay = 1
        $sub.Save()
        Write-OutputColor "  Daily automatic sync scheduled for $($syncHour.ToString('00')):00." -color "Success"
    }
    catch {
        Write-OutputColor "  Could not set the sync schedule: $($_.Exception.Message)" -color "Warning"
    }

    Add-SessionChange -Category "Roles" -Description "Applied default WSUS configuration (language, classifications, sync schedule)"
    Write-OutputColor "  Default configuration applied. First sync will populate the catalog." -color "Success"
    return $true
}

# Trigger an immediate WSUS catalog synchronization.
function Sync-WSUSCatalog {
    if (-not (Test-WSUSPostInstalled)) {
        Write-OutputColor "  WSUS is not post-installed." -color "Error"
        return $false
    }
    try {
        $wsus = Get-WsusServer -ErrorAction Stop
        $sub = $wsus.GetSubscription()
        if ($sub.GetSynchronizationStatus() -ne 'NotProcessing') {
            Write-OutputColor "  A synchronization is already in progress." -color "Warning"
            return $false
        }
        $sub.StartSynchronization()
        Write-OutputColor "  WSUS synchronization started. The first sync can take a long time." -color "Success"
        Add-SessionChange -Category "Roles" -Description "Started WSUS catalog synchronization"
        return $true
    }
    catch {
        Write-OutputColor "  Could not start synchronization: $($_.Exception.Message)" -color "Error"
        return $false
    }
}

# Interactive WSUS management menu.
function Show-WSUSManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                          WSUS SERVER SETUP").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $status = Get-WSUSStatus
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if (-not $status.RoleInstalled) {
            Write-OutputColor "  │$("  Role:       not installed".PadRight(72))│" -color "Warning"
        } elseif (-not $status.PostInstalled) {
            Write-OutputColor "  │$("  Role:       installed".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Post-inst:  NOT run (run step 2)".PadRight(72))│" -color "Warning"
        } else {
            Write-OutputColor "  │$("  Role:       installed + post-installed".PadRight(72))│" -color "Success"
            Write-OutputColor "  │$("  Content:    $($status.ContentPath)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Updates:    $($status.UpdateCount)   Computers: $($status.ComputerCount)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Last sync:  $($status.LastSync)".PadRight(72))│" -color "Info"
        }
        $cfg = if (Test-WSUSConfigured) { "configured" } else { "NOT configured (see defaults.json)" }
        Write-OutputColor "  │$("  Config:     $cfg".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[1]  Install WSUS role"
        Write-MenuItem "[2]  Run WSUS post-install"
        Write-MenuItem "[3]  Apply default configuration (classifications, language, schedule)"
        Write-MenuItem "[4]  Start catalog synchronization"
        Write-MenuItem "[5]  Show WSUS status"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                if (Confirm-UserAction -Message "  Install the WSUS (UpdateServices) role?") {
                    $null = Install-WSUSRole
                }
                Write-PressEnter
            }
            "2" {
                if (Confirm-UserAction -Message "  Run the one-time WSUS post-install now?") {
                    $null = Invoke-WSUSPostInstall
                }
                Write-PressEnter
            }
            "3" {
                $null = Set-WSUSDefaultConfiguration
                Write-PressEnter
            }
            "4" {
                if (Confirm-UserAction -Message "  Start a WSUS catalog synchronization?") {
                    $null = Sync-WSUSCatalog
                }
                Write-PressEnter
            }
            "5" {
                $s = Get-WSUSStatus
                Write-OutputColor "" -color "Info"
                if ($s.PostInstalled) {
                    Write-OutputColor "  WSUS ready. $($s.UpdateCount) updates, $($s.ComputerCount) computers. Last sync: $($s.LastSync)" -color "Success"
                } elseif ($s.RoleInstalled) {
                    Write-OutputColor "  Role installed; post-install not yet run." -color "Warning"
                } else {
                    Write-OutputColor "  WSUS role is not installed." -color "Warning"
                }
                Write-PressEnter
            }
            default {
                Write-OutputColor "  Invalid selection. Enter 1-5 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
