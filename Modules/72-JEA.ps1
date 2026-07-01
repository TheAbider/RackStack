#region ===== JEA (JUST ENOUGH ADMINISTRATION) =====
# Create and manage JEA constrained-endpoint session configurations, so a
# delegated group (help desk, operators) can run a curated set of commands
# over PowerShell remoting WITHOUT being local administrators. The commands
# run as a temporary, audited virtual account; everything else is blocked.
#
# Built entirely on the in-box JEA cmdlets — New-PSRoleCapabilityFile,
# New-PSSessionConfigurationFile, Register/Unregister/Get-PSSessionConfiguration
# and Test-PSSessionConfigurationFile — so the .psrc / .pssc files are
# generated + validated by Windows rather than hand-written.
#
# Everything is created under the ADMIN-ONLY module root (Program Files —
# standard users have read/execute only), keyed by ENDPOINT name so endpoints
# never collide. Putting the .pssc/transcripts here (not a world-writable temp
# dir) prevents a non-admin from swapping a privileged config before Register
# reads it, or forging/deleting the audit transcript.
#   %ProgramFiles%\WindowsPowerShell\Modules\<ToolName>JEA\
#       <ToolName>JEA.psd1
#       RoleCapabilities\<Endpoint>.psrc    (VisibleCmdlets whitelist)
#       SessionConfigs\<Endpoint>.pssc      (RestrictedRemoteServer, RunAsVirtualAccount)
#       Transcripts\<Endpoint>\             (session audit transcripts)
#   Register-PSSessionConfiguration -Name <Endpoint> -Path <pssc>
#
# Registering restarts the WinRM service — it can drop an in-flight remote
# session — so it's confirmed and Dry-Run-gated. Removal unregisters the
# endpoint and cleans up the generated files.

# JEA needs WMF 5.0+ and the session-configuration cmdlets (present on
# Windows Server 2016+/Win10+). Returns $true when usable.
function Test-JEAAvailable {
    if ($PSVersionTable.PSVersion.Major -lt 5) { return $false }
    if (-not (Get-Command Register-PSSessionConfiguration -ErrorAction SilentlyContinue)) { return $false }
    if (-not (Get-Command New-PSRoleCapabilityFile -ErrorAction SilentlyContinue)) { return $false }
    return $true
}

function Get-JEAManagerStatus {
    return [PSCustomObject]@{ Available = (Test-JEAAvailable) }
}

function Show-JEAUnavailable {
    Write-OutputColor "  JEA is not available on this host." -color "Error"
    Write-OutputColor "  It requires WMF 5.0+ (Windows Server 2016 / Windows 10 or later)" -color "Info"
    Write-OutputColor "  and the PSSessionConfiguration cmdlets, with WinRM enabled." -color "Info"
}

# The shared JEA module folder that holds all RackStack-managed role
# capabilities. ToolName-branded so it reads naturally in the operator's env.
function Get-JEAModuleName { return "$($script:ToolName)JEA" }
function Get-JEAModuleRoot {
    return (Join-Path "$env:ProgramFiles\WindowsPowerShell\Modules" (Get-JEAModuleName))
}

# Curated, conservative command whitelists. Kept narrow on purpose — JEA's
# value is least-privilege, so presets grant only what the role name implies.
function Get-JEARolePreset {
    param([Parameter(Mandatory = $true)][string]$Preset)
    $readOnly = @(
        'Get-Service', 'Get-Process', 'Get-EventLog', 'Get-WinEvent', 'Get-ComputerInfo',
        'Get-Disk', 'Get-Volume', 'Get-NetIPAddress', 'Get-NetAdapter', 'Get-ScheduledTask', 'Get-Hotfix'
    )
    switch ($Preset) {
        'ReadOnly' { return $readOnly }
        'HelpDesk' { return @($readOnly + @('Start-Service', 'Stop-Service', 'Restart-Service')) }
        'ServiceOperator' { return @('Get-Service', 'Start-Service', 'Stop-Service', 'Restart-Service') }
        default { return @() }
    }
}

# Ensure the shared JEA module scaffold exists (folder + manifest +
# RoleCapabilities subfolder). Idempotent. Returns the module root.
function Initialize-JEAModule {
    $root = Get-JEAModuleRoot
    $rolesDir = Join-Path $root "RoleCapabilities"
    if (-not (Test-Path -LiteralPath $rolesDir)) {
        $null = New-Item -LiteralPath $rolesDir -ItemType Directory -Force -ErrorAction Stop
    }
    $manifest = Join-Path $root "$(Get-JEAModuleName).psd1"
    if (-not (Test-Path -LiteralPath $manifest)) {
        New-ModuleManifest -Path $manifest -Description "RackStack-managed JEA role capabilities" -ErrorAction Stop
    }
    return $root
}

# Build worker: scaffolds the module, writes the role-capability (.psrc) and
# the session-config (.pssc), and registers the endpoint. Used by both the
# interactive path and the Dry-Run Apply closure. Returns $true on success.
function Invoke-JEAEndpointBuild {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$Group,
        [Parameter(Mandatory = $true)][string[]]$VisibleCmdlets
    )
    $root = Initialize-JEAModule
    # The role-capability + session-config + transcripts ALL live under the
    # admin-only module root (Program Files — standard users have read/execute
    # only). They must NOT go under an operator-writable temp dir: a non-admin
    # could otherwise swap the .pssc in the window before Register reads it
    # (privilege escalation to an unconstrained virtual-admin endpoint), or
    # forge/delete the audit transcripts.
    #
    # The .psrc is named per-ENDPOINT (endpoint names are unique + already
    # collision-checked), so two endpoints never share or overwrite one
    # capability file, and removing one never orphans another.
    $psrc = Join-Path (Join-Path $root "RoleCapabilities") "$Endpoint.psrc"
    $configDir = Join-Path $root "SessionConfigs"
    if (-not (Test-Path -LiteralPath $configDir)) { $null = New-Item -LiteralPath $configDir -ItemType Directory -Force -ErrorAction Stop }
    $transcriptDir = Join-Path (Join-Path $root "Transcripts") $Endpoint
    if (-not (Test-Path -LiteralPath $transcriptDir)) { $null = New-Item -LiteralPath $transcriptDir -ItemType Directory -Force -ErrorAction Stop }
    $pssc = Join-Path $configDir "$Endpoint.pssc"

    New-PSRoleCapabilityFile -Path $psrc -VisibleCmdlets $VisibleCmdlets -ErrorAction Stop
    try {
        New-PSSessionConfigurationFile -Path $pssc `
            -SessionType RestrictedRemoteServer `
            -RunAsVirtualAccount `
            -TranscriptDirectory $transcriptDir `
            -RoleDefinitions @{ $Group = @{ RoleCapabilities = $Endpoint } } `
            -ErrorAction Stop

        # Validate before registering — a bad .pssc would otherwise leave a
        # broken endpoint behind.
        if (-not (Test-PSSessionConfigurationFile -Path $pssc)) {
            Write-OutputColor "  Generated session-config file failed validation; not registering." -color "Error"
            Remove-Item -LiteralPath $psrc -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $pssc -Force -ErrorAction SilentlyContinue
            return $false
        }

        Register-PSSessionConfiguration -Name $Endpoint -Path $pssc -Force -ErrorAction Stop | Out-Null
    }
    catch {
        # Roll back the orphaned role-capability + config on any failure so a
        # half-built endpoint isn't left behind.
        Remove-Item -LiteralPath $psrc -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $pssc -Force -ErrorAction SilentlyContinue
        throw
    }
    return $true
}

# Interactive: create a JEA endpoint.
function New-JEAEndpoint {
    Clear-Host
    Write-CenteredOutput "Create JEA Endpoint" -color "Info"
    if (-not (Test-JEAAvailable)) { Show-JEAUnavailable; return }

    Write-OutputColor "  JEA lets a group run a curated command set over PS Remoting as an" -color "Info"
    Write-OutputColor "  audited virtual account — without being local admins." -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Endpoint (session configuration) name, e.g. HelpDeskJEA:" -color "Info"
    $endpoint = (Read-Host).Trim()
    $navResult = Test-NavigationCommand -UserInput $endpoint
    if ($navResult.ShouldReturn) { return }
    if ($endpoint -notmatch '^[A-Za-z0-9._-]{1,64}$') {
        Write-OutputColor "  Invalid name (letters, digits, dot, dash, underscore only)." -color "Error"; return
    }
    if (Get-PSSessionConfiguration -Name $endpoint -ErrorAction SilentlyContinue) {
        Write-OutputColor "  A session configuration named '$endpoint' already exists." -color "Error"; return
    }

    Write-OutputColor "  Role name, e.g. HelpDesk:" -color "Info"
    $role = (Read-Host).Trim()
    if ($role -notmatch '^[A-Za-z0-9._-]{1,64}$') {
        Write-OutputColor "  Invalid role name." -color "Error"; return
    }

    Write-OutputColor "  Allowed group (DOMAIN\Group or BUILTIN\Group), members get this role:" -color "Info"
    $group = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($group) -or $group -notmatch '\\') {
        Write-OutputColor "  Enter a group as DOMAIN\Group (e.g. CONTOSO\HelpDesk)." -color "Error"; return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Command set:" -color "Info"
    Write-MenuItem "[1]  ReadOnly        — service/process/event/hardware/network 'Get-' cmdlets"
    Write-MenuItem "[2]  HelpDesk        — ReadOnly + start/stop/restart services"
    Write-MenuItem "[3]  ServiceOperator — start/stop/restart/get services only"
    Write-MenuItem "[4]  Custom          — enter your own comma-separated cmdlet list"
    Write-OutputColor "" -color "Info"
    $presetChoice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $presetChoice
    if ($navResult.ShouldReturn) { return }

    $visibleCmdlets = @()
    switch ("$presetChoice".Trim()) {
        "1" { $visibleCmdlets = @(Get-JEARolePreset -Preset 'ReadOnly') }
        "2" { $visibleCmdlets = @(Get-JEARolePreset -Preset 'HelpDesk') }
        "3" { $visibleCmdlets = @(Get-JEARolePreset -Preset 'ServiceOperator') }
        "4" {
            Write-OutputColor "  Enter cmdlets, comma-separated (e.g. Get-Service, Restart-Service):" -color "Info"
            $raw = Read-Host
            $tokens = @($raw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            # The cmdlet list IS the security boundary — validate it. Reject
            # wildcards (e.g. '*' would expose every cmdlet and defeat the
            # constraint entirely) and anything that isn't an exact Verb-Noun
            # name (blocks wildcard / parameter smuggling).
            $badTokens = @($tokens | Where-Object { $_ -notmatch '^[A-Za-z]+-[A-Za-z0-9]+$' })
            if ($badTokens.Count -gt 0) {
                Write-OutputColor "  Rejected — use exact Verb-Noun cmdlet names, no wildcards: $($badTokens -join ', ')" -color "Error"; return
            }
            # Known breakout cmdlets: run as a virtual admin these grant arbitrary
            # code / file access and break least privilege. Warn + require an
            # explicit confirmation.
            $denyList = @('Invoke-Expression', 'Invoke-Command', 'Start-Process', 'New-Object', 'Add-Type', 'Set-Content', 'Add-Content', 'Clear-Content', 'Out-File', 'New-Item', 'Remove-Item', 'Set-Item', 'Get-Content', 'Start-Job', 'Register-ScheduledTask')
            $risky = @($tokens | Where-Object { $_ -in $denyList })
            if ($risky.Count -gt 0) {
                Write-OutputColor "  WARNING: these run as a virtual ADMINISTRATOR and can execute arbitrary" -color "Warning"
                Write-OutputColor "  code / write files — they defeat JEA's least-privilege guarantee:" -color "Warning"
                Write-OutputColor "    $($risky -join ', ')" -color "Warning"
                if (-not (Confirm-UserAction -Message "Include these high-risk cmdlets anyway?")) {
                    Write-OutputColor "  Cancelled." -color "Info"; return
                }
            }
            $visibleCmdlets = $tokens
        }
        default { Write-OutputColor "  Invalid selection." -color "Error"; return }
    }
    if ($visibleCmdlets.Count -eq 0) {
        Write-OutputColor "  No cmdlets selected — nothing to grant." -color "Error"; return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Endpoint : $endpoint" -color "Info"
    Write-OutputColor "  Role     : $role  (group $group)" -color "Info"
    Write-OutputColor "  Commands : $($visibleCmdlets -join ', ')" -color "Info"
    Write-OutputColor "  Connect with: Enter-PSSession -ComputerName <host> -ConfigurationName $endpoint" -color "Info"
    Write-OutputColor "" -color "Warning"
    Write-OutputColor "  NOTE: the allowed commands run as a temporary LOCAL ADMINISTRATOR virtual" -color "Warning"
    Write-OutputColor "  account — e.g. Stop/Restart-Service can target ANY service (including" -color "Warning"
    Write-OutputColor "  security services). Scope the allowed group accordingly." -color "Warning"
    Write-OutputColor "  Registering also RESTARTS WinRM and may drop active remote sessions." -color "Warning"
    if (-not (Confirm-UserAction -Message "Create + register JEA endpoint '$endpoint'?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capEndpoint = $endpoint; $capRole = $role; $capGroup = $group
        $capCmdlets = $visibleCmdlets
        $capRoot = Get-JEAModuleRoot
        Push-DryRunStep -Label "Register JEA endpoint '$capEndpoint' (role $capRole)" -Category "Security" -OneWay $false `
            -Params @{ Endpoint = $capEndpoint; Role = $capRole; Group = $capGroup; Cmdlets = ($capCmdlets -join ', ') } `
            -Preflight {
                if (Get-PSSessionConfiguration -Name $capEndpoint -ErrorAction SilentlyContinue) { "Endpoint '$capEndpoint' already exists" }
                else { $true }
            }.GetNewClosure() `
            -Apply {
                # Invoke-JEAEndpointBuild returns $false WITHOUT throwing when the generated .pssc
                # fails Test-PSSessionConfigurationFile (it cleans up and returns). The dry-run
                # engine treats a non-throwing Apply as success, so a validation failure would be
                # reported as a registered security endpoint. Throw to surface it as a real failure
                # (and trigger rollback).
                if (-not (Invoke-JEAEndpointBuild -Endpoint $capEndpoint -Group $capGroup -VisibleCmdlets $capCmdlets)) {
                    throw "JEA endpoint '$capEndpoint' failed validation and was not registered."
                }
            }.GetNewClosure() `
            -Undo {
                Unregister-PSSessionConfiguration -Name $capEndpoint -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path (Join-Path $capRoot "RoleCapabilities") "$capEndpoint.psrc") -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path (Join-Path $capRoot "SessionConfigs") "$capEndpoint.pssc") -Force -ErrorAction SilentlyContinue
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): register JEA endpoint '$capEndpoint'." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued JEA endpoint: $capEndpoint"
        return
    }

    try {
        if (Invoke-JEAEndpointBuild -Endpoint $endpoint -Group $group -VisibleCmdlets $visibleCmdlets) {
            Write-OutputColor "  JEA endpoint '$endpoint' registered." -color "Success"
            Add-SessionChange -Category "Security" -Description "Registered JEA endpoint '$endpoint' (role $role)"
            $capRoot = Get-JEAModuleRoot
            Add-UndoAction -Category "Security" -Description "Registered JEA endpoint '$endpoint'" -UndoScript {
                param($Name, $ModRoot)
                Unregister-PSSessionConfiguration -Name $Name -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path (Join-Path $ModRoot "RoleCapabilities") "$Name.psrc") -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath (Join-Path (Join-Path $ModRoot "SessionConfigs") "$Name.pssc") -Force -ErrorAction SilentlyContinue
            } -UndoParams @{ Name = $endpoint; ModRoot = $capRoot }
            Clear-MenuCache
        }
    }
    catch {
        Write-OutputColor "  Failed to create JEA endpoint: $($_.Exception.Message)" -color "Error"
    }
}

# Return the custom (non-built-in) session configurations on this host — the
# JEA endpoints registered by RackStack or an operator. The built-in
# microsoft.* / PowerShell.* endpoints are excluded. We identify by excluding
# the well-known built-ins rather than trusting RunAsVirtualAccount, which
# Get-PSSessionConfiguration does not reliably surface as a typed property.
function Get-JEAEndpointList {
    if (-not (Test-JEAAvailable)) { return @() }
    $all = @()
    try { $all = @(Get-PSSessionConfiguration -ErrorAction SilentlyContinue) } catch { return @() }
    return @($all | Where-Object { $_.Name -notlike 'microsoft.*' -and $_.Name -notlike 'PowerShell.*' })
}

# Interactive: list JEA endpoints.
function Show-JEAEndpoints {
    Clear-Host
    Write-CenteredOutput "JEA Endpoints" -color "Info"
    if (-not (Test-JEAAvailable)) { Show-JEAUnavailable; return }
    $eps = Get-JEAEndpointList
    if ($eps.Count -eq 0) {
        Write-OutputColor "  No JEA endpoints are registered on this host." -color "Info"
        return
    }
    Write-OutputColor "" -color "Info"
    foreach ($e in $eps) {
        Write-OutputColor "  $($e.Name)" -color "Success"
        if ($e.Permission) {
            $perm = $e.Permission
            if ($perm.Length -gt 70) { $perm = $perm.Substring(0, 67) + "..." }
            Write-OutputColor "      access: $perm" -color "Info"
        }
    }
}

# CLI entry: JEAList. Lists registered JEA endpoints (JSON-aware).
function Start-JEAList {
    if (-not (Test-JEAAvailable)) {
        if ($script:CLIOutputFormat -eq 'JSON') { Write-Output (@{ Available = $false; Endpoints = @() } | ConvertTo-Json) }
        else { Show-JEAUnavailable }
        return $false
    }
    $eps = Get-JEAEndpointList
    if ($script:CLIOutputFormat -eq 'JSON') {
        $obj = @{
            Tool      = $script:ToolFullName
            Version   = $script:ScriptVersion
            Action    = 'JEAList'
            Hostname  = $env:COMPUTERNAME
            Endpoints = @($eps | ForEach-Object { @{ Name = $_.Name; Permission = "$($_.Permission)" } })
        }
        Write-Output ($obj | ConvertTo-Json -Depth 5)
    }
    else {
        Show-JEAEndpoints
    }
    return $true
}

# Interactive: remove a JEA endpoint (unregister + clean up generated files).
function Remove-JEAEndpointInteractive {
    Clear-Host
    Write-CenteredOutput "Remove JEA Endpoint" -color "Info"
    if (-not (Test-JEAAvailable)) { Show-JEAUnavailable; return }
    $eps = Get-JEAEndpointList
    if ($eps.Count -eq 0) {
        Write-OutputColor "  No JEA endpoints to remove." -color "Info"; return
    }
    Write-OutputColor "" -color "Info"
    $i = 1
    foreach ($e in $eps) { Write-OutputColor "  [$i] $($e.Name)" -color "Info"; $i++ }
    Write-OutputColor "" -color "Info"
    $sel = Read-Host "  Select endpoint to remove (1-$($eps.Count))"
    $navResult = Test-NavigationCommand -UserInput $sel
    if ($navResult.ShouldReturn) { return }
    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $eps.Count) {
        Write-OutputColor "  Invalid selection." -color "Error"; return
    }
    $target = $eps[[int]$sel - 1].Name

    Write-OutputColor "" -color "Warning"
    Write-OutputColor "  Unregistering '$target' RESTARTS WinRM and removes the delegated access." -color "Warning"
    if (-not (Confirm-UserAction -Message "Remove JEA endpoint '$target'?")) {
        Write-OutputColor "  Cancelled." -color "Info"; return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $capTarget = $target
        Push-DryRunStep -Label "Remove JEA endpoint '$capTarget'" -Category "Security" -OneWay $true `
            -Params @{ Endpoint = $capTarget } `
            -Preflight {
                if (Get-PSSessionConfiguration -Name $capTarget -ErrorAction SilentlyContinue) { $true }
                else { "Endpoint '$capTarget' no longer exists" }
            }.GetNewClosure() `
            -Apply {
                Unregister-PSSessionConfiguration -Name $capTarget -Force -ErrorAction Stop | Out-Null
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): remove JEA endpoint '$capTarget' (ONE-WAY)." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued JEA endpoint removal: $capTarget"
        return
    }

    try {
        Unregister-PSSessionConfiguration -Name $target -Force -ErrorAction Stop | Out-Null
        Write-OutputColor "  Removed JEA endpoint '$target'." -color "Success"
        Add-SessionChange -Category "Security" -Description "Removed JEA endpoint '$target'"
        Clear-MenuCache
    }
    catch {
        Write-OutputColor "  Failed to remove endpoint: $($_.Exception.Message)" -color "Error"
    }
}

# Interactive: validate a session-config (.pssc) file.
function Test-JEAConfigFile {
    Clear-Host
    Write-CenteredOutput "Validate JEA Config File" -color "Info"
    if (-not (Test-JEAAvailable)) { Show-JEAUnavailable; return }
    Write-OutputColor "  Path to a .pssc session-configuration file:" -color "Info"
    $path = (Read-Host).Trim().Trim('"')
    $navResult = Test-NavigationCommand -UserInput $path
    if ($navResult.ShouldReturn) { return }
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        Write-OutputColor "  File not found." -color "Error"; return
    }
    try {
        $valid = Test-PSSessionConfigurationFile -Path $path -ErrorAction Stop
        if ($valid) { Write-OutputColor "  Valid session-configuration file." -color "Success" }
        else { Write-OutputColor "  INVALID session-configuration file." -color "Error" }
    }
    catch {
        Write-OutputColor "  Validation error: $($_.Exception.Message)" -color "Error"
    }
}

# JEA submenu (Roles & Features > [9]).
function Show-JEAManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                   JUST ENOUGH ADMINISTRATION (JEA)").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $available = Test-JEAAvailable
        $availText = if ($available) { "Available" } else { "Unavailable (needs WMF 5+ / WinRM)" }
        $availColor = if ($available) { "Success" } else { "Warning" }

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "  JEA support" -Status $availText -StatusColor $availColor
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Create JEA Endpoint" -Status "Delegate a command set to a group" -StatusColor "Info"
        Write-MenuItem "[2]  List JEA Endpoints" -Status "Show registered constrained endpoints" -StatusColor "Info"
        Write-MenuItem "[3]  Remove JEA Endpoint" -Status "Unregister + clean up" -StatusColor "Info"
        Write-MenuItem "[4]  Validate a .pssc File" -Status "Test-PSSessionConfigurationFile" -StatusColor "Info"
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
            "1" { New-JEAEndpoint; Write-PressEnter }
            "2" { Show-JEAEndpoints; Write-PressEnter }
            "3" { Remove-JEAEndpointInteractive; Write-PressEnter }
            "4" { Test-JEAConfigFile; Write-PressEnter }
            "B" { return }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-4 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
