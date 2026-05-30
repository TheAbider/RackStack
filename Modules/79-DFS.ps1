#region ===== DFS (NAMESPACES & REPLICATION) =====
# Read-only audit of DFS Namespaces (DFS-N) and DFS Replication (DFS-R), plus a
# reversible one-step install of the DFS server roles. The audit reports the
# installed role state, the namespaces this server knows, and the DFS-R
# replication groups and replicated-folder count. It makes no changes.
#
# Backlog measurement (Get-DfsrBacklog) is intentionally NOT run during the audit:
# it requires naming a specific sending/receiving member plus a replicated folder
# and can be slow, so it is left for targeted use in the DFS Management console.

# Report whether the DFS role features are installed and whether the DFS
# PowerShell tooling is present at all.
function Test-DFSRoleInstalled {
    $r = @{ Namespace = $false; Replication = $false; ToolsAvailable = $false }
    $r.ToolsAvailable = [bool](Get-Command Get-DfsnRoot -ErrorAction SilentlyContinue)
    try {
        if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
            $ns  = Get-WindowsFeature -Name 'FS-DFS-Namespace' -ErrorAction SilentlyContinue
            $rep = Get-WindowsFeature -Name 'FS-DFS-Replication' -ErrorAction SilentlyContinue
            if ($ns)  { $r.Namespace   = ($ns.InstallState  -eq 'Installed') }
            if ($rep) { $r.Replication = ($rep.InstallState -eq 'Installed') }
        }
    } catch {}
    return $r
}

# Read-only DFS posture: role state, namespaces, replication groups + folder count.
function Get-DFSStatus {
    $result = [PSCustomObject]@{
        Available                = $false
        NamespaceRoleInstalled   = $false
        ReplicationRoleInstalled = $false
        Namespaces               = @()
        ReplicationGroups        = @()
        ReplicatedFolderCount    = 0
    }
    $roles = Test-DFSRoleInstalled
    if (-not $roles.ToolsAvailable) { return $result }
    $result.Available = $true
    $result.NamespaceRoleInstalled   = $roles.Namespace
    $result.ReplicationRoleInstalled = $roles.Replication
    try { $result.Namespaces = @(Get-DfsnRoot -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Path)" } | Where-Object { $_ }) } catch {}
    try {
        $rgs = @(Get-DfsReplicationGroup -ErrorAction SilentlyContinue)
        $result.ReplicationGroups = @($rgs | ForEach-Object { "$($_.GroupName)" } | Where-Object { $_ })
        $result.ReplicatedFolderCount = @(Get-DfsReplicatedFolder -ErrorAction SilentlyContinue).Count
    } catch {}
    return $result
}

# Reversible: install the DFS Namespace + Replication server roles (and their
# management tools). Captures which features were already present so the undo
# removes only the ones this action added.
function Install-DFSRoles {
    $roles = Test-DFSRoleInstalled
    if ($roles.Namespace -and $roles.Replication) {
        Write-OutputColor "  Both DFS roles (Namespace + Replication) are already installed." -color "Info"
        return $true
    }
    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  DFS is a Windows Server role — this OS is not a server SKU." -color "Error"
        return $false
    }
    $needNs  = -not $roles.Namespace
    $needRep = -not $roles.Replication

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        $addNs = $needNs; $addRep = $needRep
        Push-DryRunStep -Label "Install DFS roles (Namespace + Replication)" -Category "Roles" -OneWay $false `
            -Preflight { if (-not (Test-WindowsServer)) { "Not a Windows Server SKU" } else { $true } }.GetNewClosure() `
            -Apply { Install-DFSRoles | Out-Null }.GetNewClosure() `
            -Undo {
                if ($addRep) { Uninstall-WindowsFeature -Name 'FS-DFS-Replication' -ErrorAction SilentlyContinue | Out-Null }
                if ($addNs)  { Uninstall-WindowsFeature -Name 'FS-DFS-Namespace'  -ErrorAction SilentlyContinue | Out-Null }
            }.GetNewClosure()
        Write-OutputColor "  Queued (Dry-Run): install DFS roles." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued DFS role install"
        return $true
    }

    $ok = $true
    if ($needNs) {
        Write-OutputColor "  Installing DFS Namespaces (FS-DFS-Namespace)..." -color "Info"
        $r1 = Install-WindowsFeatureWithTimeout -FeatureName 'FS-DFS-Namespace' -DisplayName 'DFS Namespaces' -IncludeManagementTools
        if (-not $r1.Success) { $ok = $false; Write-OutputColor "  DFS Namespaces install failed." -color "Error"; if ($r1.Error) { Write-OutputColor "  $($r1.Error.Trim())" -color "Error" } }
    }
    if ($needRep -and $ok) {
        Write-OutputColor "  Installing DFS Replication (FS-DFS-Replication)..." -color "Info"
        $r2 = Install-WindowsFeatureWithTimeout -FeatureName 'FS-DFS-Replication' -DisplayName 'DFS Replication' -IncludeManagementTools
        if (-not $r2.Success) { $ok = $false; Write-OutputColor "  DFS Replication install failed." -color "Error"; if ($r2.Error) { Write-OutputColor "  $($r2.Error.Trim())" -color "Error" } }
    }

    if ($ok) {
        Write-OutputColor "  DFS roles installed." -color "Success"
        Add-SessionChange -Category "Roles" -Description "Installed DFS roles (Namespace + Replication)"
        Clear-MenuCache
        # When invoked as part of a Dry-Run queue apply, the queue owns the undo —
        # don't also register a session undo (it would double-remove on rollback).
        if (-not $script:ApplyingDryRunQueue) {
            $undoNs = $needNs; $undoRep = $needRep
            Add-UndoAction -Category "Roles" -Description "Installed DFS roles" -UndoScript {
                param($RemoveNs, $RemoveRep)
                if ($RemoveRep) { Uninstall-WindowsFeature -Name 'FS-DFS-Replication' -ErrorAction SilentlyContinue | Out-Null }
                if ($RemoveNs)  { Uninstall-WindowsFeature -Name 'FS-DFS-Namespace'  -ErrorAction SilentlyContinue | Out-Null }
            } -UndoParams @{ RemoveNs = $undoNs; RemoveRep = $undoRep }
        }
    }
    return $ok
}

# Interactive: DFS audit + optional role install.
function Show-DFSManagement {
    Clear-Host
    Write-CenteredOutput "DFS Namespaces & Replication" -color "Info"
    $s = Get-DFSStatus
    if (-not $s.Available) {
        Write-OutputColor "  DFS management tools are not available on this host." -color "Error"
        Write-OutputColor "  Install the DFS roles / RSAT DFS management tools to use this feature." -color "Info"
        Write-PressEnter; return
    }
    $nsColor  = if ($s.NamespaceRoleInstalled) { "Success" } else { "Warning" }
    $repColor = if ($s.ReplicationRoleInstalled) { "Success" } else { "Warning" }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DFS STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Namespace role   : $(if ($s.NamespaceRoleInstalled) { 'Installed' } else { 'Not installed' })".PadRight(72))│" -color $nsColor
    Write-OutputColor "  │$("  Replication role : $(if ($s.ReplicationRoleInstalled) { 'Installed' } else { 'Not installed' })".PadRight(72))│" -color $repColor
    Write-OutputColor "  │$("  Namespaces       : $($s.Namespaces.Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Replication groups: $($s.ReplicationGroups.Count)".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Replicated folders: $($s.ReplicatedFolderCount)".PadRight(72))│" -color "Info"
    if ($s.Namespaces.Count -gt 0) {
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($n in ($s.Namespaces | Select-Object -First 6)) {
            $line = "  NS:  $n"
            if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
        }
    }
    if ($s.ReplicationGroups.Count -gt 0) {
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($g in ($s.ReplicationGroups | Select-Object -First 6)) {
            $line = "  RG:  $g"
            if ($line.Length -gt 72) { $line = $line.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($line.PadRight(72))│" -color "Info"
        }
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not ($s.NamespaceRoleInstalled -and $s.ReplicationRoleInstalled)) {
        if (Confirm-UserAction -Message "Install the missing DFS server role(s)?") { Install-DFSRoles }
    } else {
        Write-OutputColor "  Both DFS roles are installed. Manage namespaces and replication groups in" -color "Info"
        Write-OutputColor "  the DFS Management console (dfsmgmt.msc)." -color "Info"
    }
    Write-PressEnter
}

# CLI: DFSAudit — read-only DFS posture (JSON-aware).
function Start-DFSAudit {
    $s = Get-DFSStatus
    if ($script:CLIOutputFormat -eq 'JSON') {
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'DFSAudit'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
            Available = $s.Available
            NamespaceRoleInstalled = $s.NamespaceRoleInstalled
            ReplicationRoleInstalled = $s.ReplicationRoleInstalled
            Namespaces = $s.Namespaces
            ReplicationGroups = $s.ReplicationGroups
            ReplicatedFolderCount = $s.ReplicatedFolderCount
        } | ConvertTo-Json -Depth 4)
    }
    else { Show-DFSManagement }
    return $true
}
#endregion
