# RackStack PowerShell module — thin cmdlet wrappers around RackStack.exe.
# The EXE is downloaded separately from https://github.com/TheAbider/RackStack/releases
# or via Install-RackStack.ps1 -Install. This module locates it via (in priority order):
#   1. $env:RACKSTACK_EXE
#   2. HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\RackStack InstallLocation
#   3. Get-Command RackStack on PATH

function Get-RackStackExePath {
    <#
    .SYNOPSIS Locate the installed RackStack.exe.
    .DESCRIPTION Returns the absolute path to RackStack.exe. Throws if none of the discovery
    paths find it, with guidance on how to install or configure the environment variable.
    #>
    [CmdletBinding()] param()
    if ($env:RACKSTACK_EXE -and (Test-Path -LiteralPath $env:RACKSTACK_EXE)) { return $env:RACKSTACK_EXE }
    $regKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\RackStack'
    if (Test-Path -LiteralPath $regKey) {
        $loc = (Get-ItemProperty -Path $regKey -ErrorAction SilentlyContinue).InstallLocation
        if ($loc) {
            $candidate = Join-Path $loc 'RackStack.exe'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    $cmd = Get-Command 'RackStack' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd -and $cmd.Source) { return $cmd.Source }
    throw "RackStack.exe not found. Install via 'irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1 | iex' -Install, set `$env:RACKSTACK_EXE, or add the EXE's directory to PATH."
}

function Test-RackStackInstalled {
    <#
    .SYNOPSIS Returns $true if RackStack.exe is discoverable on this machine.
    #>
    [CmdletBinding()] param()
    try { $null = Get-RackStackExePath; return $true } catch { return $false }
}

function Get-RackStackVersion {
    <#
    .SYNOPSIS Return the installed (or latest published) RackStack version.
    .PARAMETER Remote Query the GitHub Releases API instead of the local EXE.
    #>
    [CmdletBinding()] param([switch]$Remote)
    if ($Remote) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $r = Invoke-RestMethod -Uri 'https://api.github.com/repos/TheAbider/RackStack/releases/latest' -Headers @{ 'User-Agent' = 'RackStack-PSGallery' } -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        return ([string]$r.tag_name -replace '^v', '')
    }
    $exe = Get-RackStackExePath
    $raw = (& $exe -Version 2>$null | Out-String).Trim()
    if ($raw -match '\bv?(\d+\.\d+\.\d+)') { return $Matches[1] }
    return $raw
}

function Get-RackStackActionList {
    <#
    .SYNOPSIS Return the list of CLI actions supported by the installed EXE.
    .DESCRIPTION Calls the EXE with -ListActions -OutputFormat JSON and returns the parsed objects.
    Each entry has an Action and a Description.
    #>
    [CmdletBinding()] param()
    $exe = Get-RackStackExePath
    $raw = (& $exe -ListActions -OutputFormat JSON -Quiet 2>$null | Out-String)
    if ($raw -and $raw.Trim().StartsWith('[')) {
        return (ConvertFrom-Json -InputObject $raw)
    }
    return @()
}

function Invoke-RackStackAction {
    <#
    .SYNOPSIS Run any RackStack CLI action and return its output (parsed to objects when JSON).
    .DESCRIPTION Thin wrapper around RackStack.exe -Action. When OutputFormat is JSON the raw
    stdout is parsed and returned as an object (or an array of objects in Stream mode). Exit
    code is surfaced as the script-level $LASTEXITCODE after the call.
    .PARAMETER Name The action name. Use Get-RackStackActionList to enumerate.
    .PARAMETER Tier Light, Standard, or Aggressive (applies to profile-aware actions like Cleanup).
    .PARAMETER Config Action-specific config value (path, port, index, etc.) — passed through as -Config.
    .PARAMETER OutputFormat Console or JSON.
    .PARAMETER Silent Auto-confirm interactive prompts (headless mode).
    .PARAMETER Quiet Suppress banner / box-drawing output.
    .PARAMETER Stream Emit ndjson event stream instead of a single summary (actions that support it).
    .PARAMETER OutputFile Save stdout to this file in addition to returning it.
    .EXAMPLE
    Invoke-RackStackAction SelfTest -OutputFormat JSON
    .EXAMPLE
    Invoke-RackStackAction Batch -Config C:\configs\prod.json -Silent -OutputFormat JSON -Stream
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [ValidateSet('Light', 'Standard', 'Aggressive')][string]$Tier,
        [string]$Config,
        [ValidateSet('Console', 'JSON')][string]$OutputFormat = 'Console',
        [switch]$Silent,
        [switch]$Quiet,
        [switch]$Stream,
        [string]$OutputFile
    )
    $exe = Get-RackStackExePath
    $exeArgs = @('-Action', $Name)
    if ($Tier) { $exeArgs += @('-Tier', $Tier) }
    if ($Config) { $exeArgs += @('-Config', $Config) }
    if ($OutputFormat) { $exeArgs += @('-OutputFormat', $OutputFormat) }
    if ($Silent) { $exeArgs += '-Silent' }
    if ($Quiet) { $exeArgs += '-Quiet' }
    if ($Stream) { $exeArgs += '-Stream' }
    if ($OutputFile) { $exeArgs += @('-OutputFile', $OutputFile) }

    Write-Verbose "Invoking: $exe $($exeArgs -join ' ')"
    $raw = & $exe @exeArgs
    $rawText = ($raw | Out-String)

    if ($OutputFormat -eq 'JSON') {
        if ($Stream) {
            $events = @()
            foreach ($line in ($rawText -split "`r?`n")) {
                $trimmed = $line.Trim()
                if ($trimmed.StartsWith('{')) {
                    try { $events += (ConvertFrom-Json -InputObject $trimmed -ErrorAction Stop) } catch { }
                }
            }
            return $events
        }
        try {
            return (ConvertFrom-Json -InputObject $rawText -ErrorAction Stop)
        } catch {
            Write-Warning "Could not parse JSON output; returning raw text."
            return $rawText
        }
    }
    return $rawText
}

function Update-RackStack {
    <#
    .SYNOPSIS In-place upgrade of the installed RackStack.exe.
    .DESCRIPTION Wrapper around Invoke-RackStackAction -Name UpdateSelf. Requires a prior
    Install-RackStack.ps1 -Install (the action writes to HKLM so needs that registry key).
    #>
    [CmdletBinding()] param([switch]$Quiet)
    if ($Quiet) { return Invoke-RackStackAction -Name UpdateSelf -OutputFormat JSON -Quiet }
    return Invoke-RackStackAction -Name UpdateSelf -OutputFormat JSON
}

function Test-RackStackUpdate {
    <#
    .SYNOPSIS Check whether a newer RackStack version is available.
    .DESCRIPTION Runs -Action CheckForUpdate and returns the parsed JSON result. Check the
    UpdateAvailable property ($true / $false) or the Status field ('up-to-date',
    'update-available', 'ahead-of-release').
    #>
    [CmdletBinding()] param()
    return Invoke-RackStackAction -Name CheckForUpdate -OutputFormat JSON -Quiet
}

function Invoke-RackStackSelfTest {
    <#
    .SYNOPSIS Run the RackStack internal diagnostic.
    .DESCRIPTION Returns the SelfTest JSON object. Success = $true means every check passed;
    Checks is the per-check breakdown (Name, Passed, Detail).
    #>
    [CmdletBinding()] param()
    return Invoke-RackStackAction -Name SelfTest -OutputFormat JSON -Quiet
}

function Export-RackStackLogs {
    <#
    .SYNOPSIS Bundle transcripts + session state + environment snapshot into a support zip.
    .PARAMETER OutputDirectory Where the zip should land. Defaults to the tool's configured TempPath.
    .OUTPUTS Path to the created zip file.
    #>
    [CmdletBinding()] param([string]$OutputDirectory)
    $result = if ($OutputDirectory) {
        Invoke-RackStackAction -Name ExportLogs -Config $OutputDirectory -OutputFormat JSON -Quiet
    } else {
        Invoke-RackStackAction -Name ExportLogs -OutputFormat JSON -Quiet
    }
    if ($result -and $result.ZipPath) { return $result.ZipPath }
    return $result
}

Export-ModuleMember -Function @(
    'Get-RackStackExePath'
    'Test-RackStackInstalled'
    'Get-RackStackVersion'
    'Test-RackStackUpdate'
    'Invoke-RackStackAction'
    'Update-RackStack'
    'Invoke-RackStackSelfTest'
    'Export-RackStackLogs'
    'Get-RackStackActionList'
)
