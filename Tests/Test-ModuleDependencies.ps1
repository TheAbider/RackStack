<#
.SYNOPSIS
    Module Dependency Validation for RackStack

.DESCRIPTION
    Parses all module files using PowerShell AST to:
    - Extract function definitions and function calls per module
    - Build a dependency graph between modules
    - Validate that the loader's module order satisfies all dependencies
    - Detect circular dependencies
    - Detect orphan functions (defined but never called)
    - Detect undefined internal calls (called but not defined in any module)

.NOTES
    Uses [System.Management.Automation.Language.Parser]::ParseFile() for AST parsing.
    ASCII output only. No elevation required.

.EXAMPLE
    .\Tests\Test-ModuleDependencies.ps1
    .\Tests\Test-ModuleDependencies.ps1 -Verbose
    .\Tests\Test-ModuleDependencies.ps1 -ShowFullGraph
#>

param(
    [switch]$ShowFullGraph,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -------------------------------------------------------------------
# Paths
# -------------------------------------------------------------------
$scriptDir = Split-Path -Parent $PSScriptRoot          # RackStack root
$modulesDir = Join-Path $scriptDir "Modules"
$loaderPath = Join-Path $scriptDir "RackStack.ps1"

if (-not (Test-Path $modulesDir)) {
    Write-Host "ERROR: Modules directory not found: $modulesDir" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $loaderPath)) {
    Write-Host "ERROR: Loader script not found: $loaderPath" -ForegroundColor Red
    exit 1
}

# -------------------------------------------------------------------
# Step 1: Parse loader to get the declared module load order
# -------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "  RackStack - Module Dependency Validator" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Parsing loader: $loaderPath" -ForegroundColor Gray

$loaderContent = Get-Content -Path $loaderPath -Raw
$loaderTokens = $null
$loaderErrors = $null
$loaderAst = [System.Management.Automation.Language.Parser]::ParseInput(
    $loaderContent,
    [ref]$loaderTokens,
    [ref]$loaderErrors
)

# Extract the $moduleFiles array assignment from the loader AST
# The AST structure for @("a" "b" ...) assigned to $moduleFiles is:
#   AssignmentStatementAst -> CommandExpressionAst -> ArrayExpressionAst
#     -> StatementBlockAst -> PipelineAst[] -> CommandExpressionAst -> StringConstantExpressionAst
# Each string on its own line becomes a separate Statement inside the SubExpression.
$loadOrder = @()

$assignments = $loaderAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst]
}, $true)

foreach ($assignment in $assignments) {
    $varName = $assignment.Left.ToString()
    if ($varName -ne '$moduleFiles') { continue }

    # Right side: CommandExpressionAst wrapping ArrayExpressionAst
    $arrExpr = $null
    $rightExpr = $assignment.Right
    if ($rightExpr -is [System.Management.Automation.Language.CommandExpressionAst]) {
        $inner = $rightExpr.Expression
        if ($inner -is [System.Management.Automation.Language.ArrayExpressionAst]) {
            $arrExpr = $inner
        }
    }
    # Also check if Right itself is an ArrayExpressionAst (alternate parse)
    if ($null -eq $arrExpr -and $rightExpr -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        $arrExpr = $rightExpr
    }

    if ($null -ne $arrExpr) {
        # Each string in the array is a separate statement in the SubExpression block
        $stringElements = $arrExpr.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
        }, $true)
        foreach ($strElem in $stringElements) {
            $loadOrder += $strElem.Value
        }
    }
    break
}

if ($loadOrder.Count -eq 0) {
    Write-Host "ERROR: Could not extract module load order from loader." -ForegroundColor Red
    exit 1
}

Write-Host "  Found $($loadOrder.Count) modules in load order." -ForegroundColor Gray

# -------------------------------------------------------------------
# Step 2: Parse each module file with AST
# -------------------------------------------------------------------
Write-Host "Parsing module files..." -ForegroundColor Gray

# Data structures
# Key = module filename (e.g. "00-Initialization.ps1")
$moduleFunctions  = @{}   # module -> list of function names DEFINED
$moduleCalls      = @{}   # module -> list of function names CALLED
$allDefinitions   = @{}   # functionName -> module that defines it
$allCalls         = @{}   # functionName -> list of modules that call it

# Known PowerShell / Windows built-in commands to exclude from analysis.
# We build this set dynamically from the session, plus a hardcoded fallback list.
$builtinCommands = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

# Add all commands currently available in this PowerShell session
try {
    $sessionCommands = Get-Command -CommandType Cmdlet, Function, Alias -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name
    foreach ($cmd in $sessionCommands) {
        $null = $builtinCommands.Add($cmd)
    }
} catch {
    # Fallback - session enumeration failed
}

# Hardcoded common commands (safety net in case Get-Command misses some)
$hardcodedBuiltins = @(
    # Core cmdlets
    'Write-Host', 'Write-Output', 'Write-Verbose', 'Write-Warning', 'Write-Error', 'Write-Debug',
    'Write-Information', 'Write-Progress',
    'Get-Content', 'Set-Content', 'Add-Content', 'Clear-Content',
    'Get-Item', 'Set-Item', 'New-Item', 'Remove-Item', 'Copy-Item', 'Move-Item', 'Rename-Item',
    'Get-ItemProperty', 'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty',
    'Get-ChildItem', 'Test-Path', 'Resolve-Path', 'Split-Path', 'Join-Path', 'Convert-Path',
    'Get-Location', 'Set-Location', 'Push-Location', 'Pop-Location',
    'Get-Variable', 'Set-Variable', 'New-Variable', 'Remove-Variable', 'Clear-Variable',
    'Get-Process', 'Stop-Process', 'Start-Process', 'Wait-Process',
    'Get-Service', 'Start-Service', 'Stop-Service', 'Restart-Service', 'Set-Service',
    'Get-EventLog', 'Write-EventLog', 'Clear-EventLog',
    'Get-WinEvent',
    'Get-Date', 'Set-Date', 'New-TimeSpan',
    'Get-Random', 'Get-Unique',
    'Get-Host', 'Clear-Host',
    'Read-Host',
    'Get-Command', 'Get-Help', 'Get-Module', 'Import-Module', 'Remove-Module',
    'Get-Member', 'Add-Member',
    'New-Object', 'Select-Object', 'Where-Object', 'ForEach-Object', 'Sort-Object',
    'Group-Object', 'Measure-Object', 'Compare-Object', 'Tee-Object',
    'Format-Table', 'Format-List', 'Format-Wide', 'Format-Custom',
    'Out-Null', 'Out-Host', 'Out-File', 'Out-String', 'Out-Default', 'Out-GridView',
    'ConvertTo-Json', 'ConvertFrom-Json', 'ConvertTo-Csv', 'ConvertFrom-Csv',
    'ConvertTo-Html', 'ConvertTo-Xml', 'ConvertFrom-StringData',
    'Export-Csv', 'Import-Csv', 'Export-Clixml', 'Import-Clixml',
    'Invoke-Command', 'Invoke-Expression', 'Invoke-RestMethod', 'Invoke-WebRequest',
    'Start-Job', 'Stop-Job', 'Wait-Job', 'Receive-Job', 'Get-Job', 'Remove-Job',
    'Start-Sleep', 'Start-Transcript', 'Stop-Transcript',
    'Enter-PSSession', 'Exit-PSSession', 'New-PSSession', 'Remove-PSSession',
    'Get-Credential', 'Get-ExecutionPolicy', 'Set-ExecutionPolicy',
    'Test-Connection', 'Test-NetConnection',
    'Get-CimInstance', 'Get-WmiObject', 'Invoke-CimMethod', 'Invoke-WmiMethod',
    'New-CimSession', 'Remove-CimSession',
    'Get-Disk', 'Get-Partition', 'Get-Volume', 'Get-PhysicalDisk', 'Get-VirtualDisk',
    'Initialize-Disk', 'New-Partition', 'Format-Volume', 'Resize-Partition',
    'Get-StoragePool', 'New-StoragePool',
    'Get-NetAdapter', 'Set-NetAdapter', 'Enable-NetAdapter', 'Disable-NetAdapter',
    'Get-NetAdapterAdvancedProperty', 'Set-NetAdapterAdvancedProperty',
    'New-NetIPAddress', 'Remove-NetIPAddress', 'Get-NetIPAddress', 'Set-NetIPAddress',
    'Get-NetIPConfiguration', 'Set-DnsClientServerAddress', 'Get-DnsClientServerAddress',
    'New-NetLbfoTeam', 'Add-NetLbfoTeamMember', 'Remove-NetLbfoTeam',
    'New-VMSwitch', 'Get-VMSwitch', 'Set-VMSwitch', 'Remove-VMSwitch',
    'Set-VMSwitchTeam', 'Get-VMSwitchTeam', 'Add-VMSwitchTeamMember',
    'New-VM', 'Get-VM', 'Set-VM', 'Start-VM', 'Stop-VM', 'Remove-VM',
    'Get-VMHost', 'Set-VMHost',
    'New-VHD', 'Get-VHD', 'Mount-VHD', 'Dismount-VHD', 'Resize-VHD', 'Optimize-VHD',
    'Get-VMHardDiskDrive', 'Add-VMHardDiskDrive', 'Remove-VMHardDiskDrive', 'Set-VMHardDiskDrive',
    'Get-VMNetworkAdapter', 'Add-VMNetworkAdapter', 'Remove-VMNetworkAdapter', 'Set-VMNetworkAdapter',
    'Connect-VMNetworkAdapter', 'Disconnect-VMNetworkAdapter',
    'Get-VMProcessor', 'Set-VMProcessor',
    'Get-VMMemory', 'Set-VMMemory',
    'Get-VMDvdDrive', 'Add-VMDvdDrive', 'Set-VMDvdDrive', 'Remove-VMDvdDrive',
    'Get-VMSnapshot', 'Checkpoint-VM', 'Restore-VMSnapshot', 'Remove-VMSnapshot', 'Rename-VMSnapshot',
    'Export-VM', 'Import-VM',
    'Enable-VMResourceMetering', 'Disable-VMResourceMetering', 'Measure-VM',
    'Get-VMIntegrationService', 'Enable-VMIntegrationService', 'Disable-VMIntegrationService',
    'Get-VMFirmware', 'Set-VMFirmware',
    'Get-VMSecurity', 'Set-VMSecurity',
    'Move-VMStorage',
    'Get-Cluster', 'New-Cluster', 'Test-Cluster', 'Remove-Cluster',
    'Get-ClusterNode', 'Add-ClusterNode', 'Remove-ClusterNode',
    'Get-ClusterResource', 'Add-ClusterResource', 'Remove-ClusterResource',
    'Get-ClusterGroup', 'Move-ClusterGroup',
    'Get-ClusterSharedVolume', 'Add-ClusterSharedVolume', 'Remove-ClusterSharedVolume',
    'Get-ClusterQuorum', 'Set-ClusterQuorum',
    'Get-ClusterNetwork', 'Get-ClusterNetworkInterface',
    'Add-ClusterVirtualMachineRole',
    'Enable-NetFirewallRule', 'Disable-NetFirewallRule',
    'Get-NetFirewallRule', 'New-NetFirewallRule', 'Remove-NetFirewallRule', 'Set-NetFirewallRule',
    'Get-NetFirewallProfile', 'Set-NetFirewallProfile',
    'Install-WindowsFeature', 'Get-WindowsFeature', 'Uninstall-WindowsFeature',
    'Enable-WindowsOptionalFeature', 'Disable-WindowsOptionalFeature', 'Get-WindowsOptionalFeature',
    'Add-WindowsFeature',
    'Get-MsolDomain', 'Connect-MsolService',
    'Set-MpPreference', 'Get-MpPreference', 'Add-MpPreference', 'Remove-MpPreference',
    'Get-MpComputerStatus', 'Update-MpSignature',
    'Get-BitLockerVolume', 'Enable-BitLocker', 'Disable-BitLocker',
    'Lock-BitLocker', 'Unlock-BitLocker',
    'Add-BitLockerKeyProtector', 'Remove-BitLockerKeyProtector',
    'BackupToAAD-BitLockerKeyProtector', 'Backup-BitLockerKeyProtector',
    'Get-MSDSMGlobalDefaultLoadBalancePolicy', 'Set-MSDSMGlobalDefaultLoadBalancePolicy',
    'Get-MSDSMAutomaticClaimSettings', 'Enable-MSDSMAutomaticClaim',
    'Update-MPIOClaimedHW',
    'Get-IscsiTarget', 'Get-IscsiSession', 'Get-IscsiConnection',
    'Connect-IscsiTarget', 'Disconnect-IscsiTarget',
    'New-IscsiTargetPortal', 'Get-IscsiTargetPortal', 'Remove-IscsiTargetPortal',
    'Register-IscsiSession', 'Unregister-IscsiSession',
    'Get-InitiatorPort',
    'Set-NetIPInterface', 'Get-NetIPInterface',
    'Get-NetRoute', 'New-NetRoute', 'Remove-NetRoute',
    'Rename-Computer', 'Add-Computer', 'Remove-Computer', 'Restart-Computer',
    'Get-TimeZone', 'Set-TimeZone',
    'Get-LocalUser', 'Set-LocalUser', 'New-LocalUser', 'Enable-LocalUser', 'Disable-LocalUser',
    'Get-LocalGroup', 'Add-LocalGroupMember', 'Remove-LocalGroupMember', 'Get-LocalGroupMember',
    'ConvertTo-SecureString', 'ConvertFrom-SecureString',
    'Get-Acl', 'Set-Acl',
    'Get-Counter', 'Get-WUInstall', 'Install-WindowsUpdate',
    'Set-ItemProperty', 'Get-ItemPropertyValue',
    'Register-ScheduledTask', 'Unregister-ScheduledTask', 'Get-ScheduledTask',
    'New-ScheduledTaskTrigger', 'New-ScheduledTaskAction', 'New-ScheduledTaskPrincipal',
    'New-ScheduledTaskSettingsSet',
    'Get-SmbShare', 'New-SmbShare', 'Remove-SmbShare',
    'Get-WindowsUpdate', 'Install-WindowsUpdate',
    'Send-MailMessage',
    'Get-StorageReplicaGroup', 'Get-StorageReplicaPartnership',
    'New-StorageReplicaGroup', 'New-StorageReplicaPartnership',
    'Remove-StorageReplicaGroup', 'Remove-StorageReplicaPartnership',
    'Set-StorageReplicaGroup', 'Sync-StorageReplicaGroup',
    'Enable-DedupVolume', 'Disable-DedupVolume', 'Get-DedupVolume',
    'Get-DedupStatus', 'Set-DedupVolume', 'Start-DedupJob', 'Get-DedupSchedule',
    'Get-DedupJob',
    'Get-WUList', 'Get-WUHistory',
    'w32tm'
)
foreach ($cmd in $hardcodedBuiltins) {
    $null = $builtinCommands.Add($cmd)
}

# Also add common aliases
$commonAliases = @(
    'foreach', 'where', 'select', 'sort', 'measure', 'group', 'ft', 'fl', 'fw',
    'gc', 'sc', 'ac', 'cls', 'cd', 'dir', 'del', 'copy', 'move', 'mkdir',
    'echo', 'cat', 'type', 'ls', 'cp', 'mv', 'rm', 'rmdir', 'man', 'help',
    'sleep', 'kill', 'ps', 'gps', 'gsv', 'sasv', 'spsv',
    'iex', 'icm', 'irm', 'iwr', 'curl', 'wget',
    'tee', 'sls', 'measure', 'ogv',
    '%', '?'
)
foreach ($alias in $commonAliases) {
    $null = $builtinCommands.Add($alias)
}

# Track all module data
$moduleData = [ordered]@{}
$parseErrors = @()

foreach ($moduleFile in $loadOrder) {
    $modulePath = Join-Path $modulesDir $moduleFile

    if (-not (Test-Path $modulePath)) {
        Write-Host "  WARNING: Module not found: $moduleFile" -ForegroundColor Yellow
        $parseErrors += "Module file missing: $moduleFile"
        continue
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $modulePath,
        [ref]$tokens,
        [ref]$errors
    )

    if ($errors.Count -gt 0) {
        foreach ($err in $errors) {
            $parseErrors += "${moduleFile}: $($err.Message)"
        }
    }

    # Find all function definitions (FunctionDefinitionAst)
    $funcDefs = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true)

    $definedFunctions = @()
    foreach ($funcDef in $funcDefs) {
        $funcName = $funcDef.Name
        $definedFunctions += $funcName

        if ($allDefinitions.ContainsKey($funcName)) {
            $parseErrors += "DUPLICATE: Function '$funcName' defined in both '$($allDefinitions[$funcName])' and '$moduleFile'"
        } else {
            $allDefinitions[$funcName] = $moduleFile
        }
    }

    # Find all command invocations (CommandAst)
    $commandAsts = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst]
    }, $true)

    $calledFunctions = @()
    foreach ($cmdAst in $commandAsts) {
        $cmdName = $cmdAst.GetCommandName()
        if ($null -eq $cmdName) { continue }
        if ([string]::IsNullOrWhiteSpace($cmdName)) { continue }

        # Skip if this is a known built-in command
        if ($builtinCommands.Contains($cmdName)) { continue }

        # Skip common operators and simple commands that aren't function calls
        if ($cmdName -match '^\.' -or $cmdName -match '^&' -or $cmdName -match '\\') { continue }

        # Skip external executables (contain dots suggesting file extensions, or paths)
        if ($cmdName -match '\.(exe|cmd|bat|com|msi|msp)$') { continue }

        $calledFunctions += $cmdName
    }

    # Deduplicate calls list for cleaner analysis (wrap in @() to guarantee array)
    $calledFunctions = @($calledFunctions | Select-Object -Unique)

    $moduleData[$moduleFile] = @{
        Defined = @($definedFunctions)
        Called  = @($calledFunctions)
        Path    = $modulePath
    }

    $moduleFunctions[$moduleFile] = @($definedFunctions)
    $moduleCalls[$moduleFile] = @($calledFunctions)

    # Track all calls globally
    foreach ($call in $calledFunctions) {
        if (-not $allCalls.ContainsKey($call)) {
            $allCalls[$call] = @()
        }
        $allCalls[$call] += $moduleFile
    }

    if ($Verbose) {
        Write-Host "  $moduleFile : $(@($definedFunctions).Count) functions defined, $(@($calledFunctions).Count) unique calls" -ForegroundColor Gray
    }
}

# -------------------------------------------------------------------
# Step 3: Build dependency graph
# -------------------------------------------------------------------
Write-Host "Building dependency graph..." -ForegroundColor Gray

# dependencyGraph: moduleFile -> list of modules it depends on
$dependencyGraph = @{}

foreach ($moduleFile in $loadOrder) {
    if (-not $moduleData.Contains($moduleFile)) { continue }

    $deps = @()
    $calls = $moduleData[$moduleFile].Called

    foreach ($call in $calls) {
        # Only track dependencies on functions defined in OUR modules
        if ($allDefinitions.ContainsKey($call)) {
            $defModule = $allDefinitions[$call]
            # Don't count self-dependencies
            if ($defModule -ne $moduleFile) {
                if ($deps -notcontains $defModule) {
                    $deps += $defModule
                }
            }
        }
    }

    $dependencyGraph[$moduleFile] = $deps
}

# -------------------------------------------------------------------
# Step 4: Detect circular dependencies (DFS cycle detection)
# -------------------------------------------------------------------
Write-Host "Checking for circular dependencies..." -ForegroundColor Gray

$circularChains = @()

function Find-Cycles {
    param(
        [string]$StartNode,
        [hashtable]$Graph,
        [System.Collections.Generic.HashSet[string]]$Visited,
        [System.Collections.Generic.HashSet[string]]$InStack,
        [System.Collections.Generic.List[string]]$Path
    )

    $null = $Visited.Add($StartNode)
    $null = $InStack.Add($StartNode)
    $Path.Add($StartNode)

    if ($Graph.ContainsKey($StartNode)) {
        foreach ($neighbor in $Graph[$StartNode]) {
            if (-not $Visited.Contains($neighbor)) {
                Find-Cycles -StartNode $neighbor -Graph $Graph -Visited $Visited -InStack $InStack -Path $Path
            }
            elseif ($InStack.Contains($neighbor)) {
                # Found a cycle - extract it
                $cycleStart = $Path.IndexOf($neighbor)
                $cyclePath = @()
                for ($i = $cycleStart; $i -lt $Path.Count; $i++) {
                    $cyclePath += $Path[$i]
                }
                $cyclePath += $neighbor  # Close the cycle
                $script:circularChains += ,@($cyclePath)
            }
        }
    }

    $null = $InStack.Remove($StartNode)
    $Path.RemoveAt($Path.Count - 1)
}

$visited = [System.Collections.Generic.HashSet[string]]::new()
$inStack = [System.Collections.Generic.HashSet[string]]::new()
$path = [System.Collections.Generic.List[string]]::new()

foreach ($moduleFile in $loadOrder) {
    if (-not $visited.Contains($moduleFile)) {
        Find-Cycles -StartNode $moduleFile -Graph $dependencyGraph `
            -Visited $visited -InStack $inStack -Path $path
    }
}

# -------------------------------------------------------------------
# Step 5: Validate load order
# -------------------------------------------------------------------
Write-Host "Validating load order..." -ForegroundColor Gray

$loadOrderViolations = @()

# Build position index for load order
$loadOrderIndex = @{}
for ($i = 0; $i -lt $loadOrder.Count; $i++) {
    $loadOrderIndex[$loadOrder[$i]] = $i
}

foreach ($moduleFile in $loadOrder) {
    if (-not $dependencyGraph.ContainsKey($moduleFile)) { continue }

    $myIndex = $loadOrderIndex[$moduleFile]
    $deps = $dependencyGraph[$moduleFile]

    foreach ($dep in $deps) {
        if (-not $loadOrderIndex.ContainsKey($dep)) {
            $loadOrderViolations += "  $moduleFile depends on $dep which is NOT in load order"
            continue
        }
        $depIndex = $loadOrderIndex[$dep]
        if ($depIndex -ge $myIndex) {
            # Dependency loaded AFTER this module - violation!
            # Find which functions are involved
            $involvedFunctions = @()
            foreach ($call in $moduleData[$moduleFile].Called) {
                if ($allDefinitions.ContainsKey($call) -and $allDefinitions[$call] -eq $dep) {
                    $involvedFunctions += $call
                }
            }
            $funcList = $involvedFunctions -join ', '
            $loadOrderViolations += "  $moduleFile (position $myIndex) calls [$funcList] from $dep (position $depIndex)"
        }
    }
}

# -------------------------------------------------------------------
# Step 6: Detect orphan functions
# -------------------------------------------------------------------
Write-Host "Detecting orphan functions..." -ForegroundColor Gray

$orphanFunctions = @()

# Entry-point functions that are expected to be called by the loader or
# invoked at top level rather than by other functions in the modules.
$entryPoints = @(
    'Assert-Elevation'
    'Initialize-ConsoleWindow'
)

foreach ($funcName in $allDefinitions.Keys) {
    # Is this function called from any module?
    $isCalled = $false
    foreach ($moduleFile in $loadOrder) {
        if (-not $moduleData.Contains($moduleFile)) { continue }
        if ($moduleData[$moduleFile].Called -contains $funcName) {
            $isCalled = $true
            break
        }
    }

    if (-not $isCalled -and $funcName -notin $entryPoints) {
        $orphanFunctions += [PSCustomObject]@{
            Function = $funcName
            Module   = $allDefinitions[$funcName]
        }
    }
}

$orphanFunctions = $orphanFunctions | Sort-Object Module, Function

# -------------------------------------------------------------------
# Step 7: Detect undefined internal calls
# -------------------------------------------------------------------
Write-Host "Detecting undefined internal calls..." -ForegroundColor Gray

# Approved verb list from PowerShell
$approvedVerbs = @(
    'Add', 'Approve', 'Assert', 'Backup', 'Block', 'Build', 'Checkpoint', 'Clear',
    'Close', 'Compare', 'Complete', 'Compress', 'Confirm', 'Connect', 'Convert',
    'ConvertFrom', 'ConvertTo', 'Copy', 'Debug', 'Deny', 'Disable', 'Disconnect',
    'Dismount', 'Edit', 'Enable', 'Enter', 'Exit', 'Expand', 'Export', 'Find',
    'Format', 'Get', 'Grant', 'Group', 'Hide', 'Import', 'Initialize', 'Install',
    'Invoke', 'Join', 'Limit', 'Lock', 'Measure', 'Merge', 'Mount', 'Move',
    'New', 'Open', 'Optimize', 'Out', 'Ping', 'Pop', 'Protect', 'Publish', 'Push',
    'Read', 'Receive', 'Redo', 'Register', 'Remove', 'Rename', 'Repair', 'Request',
    'Reset', 'Resize', 'Resolve', 'Restart', 'Restore', 'Resume', 'Revoke',
    'Save', 'Search', 'Select', 'Send', 'Set', 'Show', 'Skip', 'Split', 'Start',
    'Step', 'Stop', 'Submit', 'Suspend', 'Switch', 'Sync', 'Test', 'Trace',
    'Unblock', 'Undo', 'Uninstall', 'Unlock', 'Unprotect', 'Unpublish', 'Unregister',
    'Update', 'Use', 'Wait', 'Watch', 'Write'
)

# Build a regex pattern matching Verb-Noun with hyphens
$verbPattern = '^(' + ($approvedVerbs -join '|') + ')-\w+'

$undefinedCalls = @()

foreach ($moduleFile in $loadOrder) {
    if (-not $moduleData.Contains($moduleFile)) { continue }

    foreach ($call in $moduleData[$moduleFile].Called) {
        # Already defined in a module? Skip.
        if ($allDefinitions.ContainsKey($call)) { continue }

        # Already a known built-in? Skip.
        if ($builtinCommands.Contains($call)) { continue }

        # Only flag if it matches Verb-Noun pattern (looks like it SHOULD be a project function)
        if ($call -match $verbPattern) {
            $undefinedCalls += [PSCustomObject]@{
                Call    = $call
                Module  = $moduleFile
            }
        }
    }
}

$undefinedCalls = $undefinedCalls | Sort-Object Call, Module

# -------------------------------------------------------------------
# REPORT
# -------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "  DEPENDENCY VALIDATION REPORT" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# --- Summary ---
$totalFunctions = ($allDefinitions.Keys).Count
$totalModules = ($moduleData.Keys).Count

Write-Host "--- SUMMARY ---" -ForegroundColor White
Write-Host "  Modules parsed:        $totalModules" -ForegroundColor Gray
Write-Host "  Modules in load order: $($loadOrder.Count)" -ForegroundColor Gray
Write-Host "  Total functions:       $totalFunctions" -ForegroundColor Gray
Write-Host "  Parse errors:          $($parseErrors.Count)" -ForegroundColor $(if ($parseErrors.Count -gt 0) { "Yellow" } else { "Gray" })
Write-Host ""

# --- Parse Errors ---
if ($parseErrors.Count -gt 0) {
    Write-Host "--- PARSE ERRORS ---" -ForegroundColor Red
    foreach ($err in $parseErrors) {
        Write-Host "  $err" -ForegroundColor Red
    }
    Write-Host ""
}

# --- Module Function Counts ---
Write-Host "--- MODULE FUNCTION COUNTS ---" -ForegroundColor White
foreach ($moduleFile in $loadOrder) {
    if (-not $moduleData.Contains($moduleFile)) { continue }
    $defCount = @($moduleData[$moduleFile].Defined).Count
    $callCount = @($moduleData[$moduleFile].Called).Count
    $depCount = if ($dependencyGraph.ContainsKey($moduleFile)) { @($dependencyGraph[$moduleFile]).Count } else { 0 }
    $line = "  {0,-38} Defined: {1,3}   Calls: {2,3}   Deps: {3,2}" -f $moduleFile, $defCount, $callCount, $depCount
    Write-Host $line -ForegroundColor Gray
}
Write-Host ""

# --- Dependency Graph ---
if ($ShowFullGraph) {
    Write-Host "--- FULL DEPENDENCY GRAPH ---" -ForegroundColor White
    foreach ($moduleFile in $loadOrder) {
        if (-not $dependencyGraph.ContainsKey($moduleFile)) { continue }
        $deps = $dependencyGraph[$moduleFile]
        if ($deps.Count -eq 0) { continue }

        Write-Host "  $moduleFile" -ForegroundColor White
        foreach ($dep in ($deps | Sort-Object)) {
            # Show which functions create this dependency
            $funcs = @()
            foreach ($call in $moduleData[$moduleFile].Called) {
                if ($allDefinitions.ContainsKey($call) -and $allDefinitions[$call] -eq $dep) {
                    $funcs += $call
                }
            }
            $funcStr = ($funcs | Sort-Object) -join ', '
            Write-Host "    --> $dep  [$funcStr]" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
} else {
    # Compact graph: only modules with dependencies
    $modulesWithDeps = @()
    foreach ($moduleFile in $loadOrder) {
        if ($dependencyGraph.ContainsKey($moduleFile) -and $dependencyGraph[$moduleFile].Count -gt 0) {
            $modulesWithDeps += $moduleFile
        }
    }

    Write-Host "--- DEPENDENCY GRAPH (compact, $($modulesWithDeps.Count) modules with dependencies) ---" -ForegroundColor White
    Write-Host "  (Use -ShowFullGraph to see function-level details)" -ForegroundColor DarkGray
    Write-Host ""
    foreach ($moduleFile in $modulesWithDeps) {
        $deps = $dependencyGraph[$moduleFile] | Sort-Object
        $depStr = $deps -join ', '
        Write-Host "  $moduleFile" -ForegroundColor White -NoNewline
        Write-Host " --> $depStr" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# --- Load Order Violations ---
Write-Host "--- LOAD ORDER VALIDATION ---" -ForegroundColor White
if ($loadOrderViolations.Count -eq 0) {
    Write-Host "  PASS: All dependencies are satisfied by the current load order." -ForegroundColor Green
} else {
    Write-Host "  FAIL: $($loadOrderViolations.Count) load order violation(s) found:" -ForegroundColor Red
    foreach ($violation in $loadOrderViolations) {
        Write-Host $violation -ForegroundColor Red
    }
}
Write-Host ""

# --- Circular Dependencies ---
Write-Host "--- CIRCULAR DEPENDENCY CHECK ---" -ForegroundColor White
if ($circularChains.Count -eq 0) {
    Write-Host "  PASS: No circular dependencies detected." -ForegroundColor Green
} else {
    Write-Host "  FAIL: $($circularChains.Count) circular dependency chain(s) found:" -ForegroundColor Red
    foreach ($chain in $circularChains) {
        $chainStr = $chain -join ' -> '
        Write-Host "  $chainStr" -ForegroundColor Red
    }
}
Write-Host ""

# --- Orphan Functions ---
Write-Host "--- ORPHAN FUNCTIONS (defined but never called from any module) ---" -ForegroundColor White
if ($orphanFunctions.Count -eq 0) {
    Write-Host "  None detected." -ForegroundColor Green
} else {
    Write-Host "  Found $($orphanFunctions.Count) orphan function(s):" -ForegroundColor Yellow
    Write-Host ""

    # Group by module
    $grouped = $orphanFunctions | Group-Object Module | Sort-Object { $loadOrder.IndexOf($_.Name) }
    foreach ($group in $grouped) {
        Write-Host "  [$($group.Name)]" -ForegroundColor Yellow
        foreach ($orphan in ($group.Group | Sort-Object Function)) {
            Write-Host "    $($orphan.Function)" -ForegroundColor DarkYellow
        }
    }
}
Write-Host ""

# --- Undefined Internal Calls ---
Write-Host "--- UNDEFINED INTERNAL CALLS (Verb-Noun pattern, not in any module or built-in list) ---" -ForegroundColor White
if ($undefinedCalls.Count -eq 0) {
    Write-Host "  None detected." -ForegroundColor Green
} else {
    Write-Host "  Found $($undefinedCalls.Count) potentially undefined call(s):" -ForegroundColor Yellow
    Write-Host "  (These may be from modules not yet installed, or from external tools)" -ForegroundColor DarkGray
    Write-Host ""

    # Group by call name
    $grouped = $undefinedCalls | Group-Object Call | Sort-Object Name
    foreach ($group in $grouped) {
        $callers = ($group.Group.Module | Sort-Object -Unique) -join ', '
        Write-Host "  $($group.Name)" -ForegroundColor Yellow -NoNewline
        Write-Host "  <-- called from: $callers" -ForegroundColor DarkGray
    }
}
Write-Host ""

# --- Final Result ---
Write-Host "============================================================================" -ForegroundColor Cyan
$hasFailures = ($loadOrderViolations.Count -gt 0) -or ($circularChains.Count -gt 0) -or ($parseErrors.Count -gt 0)
$hasWarnings = ($orphanFunctions.Count -gt 0) -or ($undefinedCalls.Count -gt 0)

if ($hasFailures) {
    Write-Host "  RESULT: FAILURES DETECTED" -ForegroundColor Red
    if ($loadOrderViolations.Count -gt 0) {
        Write-Host "    - $($loadOrderViolations.Count) load order violation(s)" -ForegroundColor Red
    }
    if ($circularChains.Count -gt 0) {
        Write-Host "    - $($circularChains.Count) circular dependency chain(s)" -ForegroundColor Red
    }
    if ($parseErrors.Count -gt 0) {
        Write-Host "    - $($parseErrors.Count) parse error(s)" -ForegroundColor Red
    }
} elseif ($hasWarnings) {
    Write-Host "  RESULT: PASS (with warnings)" -ForegroundColor Yellow
    if ($orphanFunctions.Count -gt 0) {
        Write-Host "    - $($orphanFunctions.Count) orphan function(s)" -ForegroundColor Yellow
    }
    if ($undefinedCalls.Count -gt 0) {
        Write-Host "    - $($undefinedCalls.Count) potentially undefined call(s)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  RESULT: ALL CHECKS PASSED" -ForegroundColor Green
}
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# Return structured result for programmatic use
[PSCustomObject]@{
    ModuleCount          = $totalModules
    FunctionCount        = $totalFunctions
    ParseErrors          = $parseErrors
    LoadOrderViolations  = $loadOrderViolations
    CircularDependencies = $circularChains
    OrphanFunctions      = $orphanFunctions
    UndefinedCalls       = $undefinedCalls
    DependencyGraph      = $dependencyGraph
    ModuleData           = $moduleData
    HasFailures          = $hasFailures
    HasWarnings          = $hasWarnings
}
