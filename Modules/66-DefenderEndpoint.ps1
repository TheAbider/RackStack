#region ===== MICROSOFT DEFENDER FOR ENDPOINT ONBOARDING =====
# Onboards a Windows Server into Microsoft Defender for Endpoint (MDE) —
# Microsoft's enterprise EDR. On modern Windows Server (2019+, 2022, 2025)
# and Windows 10/11 the MDE sensor (the "Sense" service) ships with the OS;
# onboarding activates it and points it at the operator's tenant.
#
# Onboarding is performed by running the per-tenant onboarding package
# downloaded from the Microsoft Defender portal (security.microsoft.com →
# Settings → Endpoints → Onboarding). RackStack just runs that operator-
# supplied script idempotently and verifies the result. There is no secret
# to handle — the tenant binding is inside the Microsoft-signed package.
#
# Config: $script:DefenderEndpoint (see 00-Initialization.ps1, overridable
# via defaults.json "DefenderEndpoint").

# Registry locations MDE writes its onboarding state to.
$script:MDEStatusKey = 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status'
$script:MDERootKey   = 'HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection'

# Returns $true if an onboarding script path is configured.
function Test-DefenderEndpointConfigured {
    if ($null -eq $script:DefenderEndpoint) { return $false }
    return (-not [string]::IsNullOrWhiteSpace($script:DefenderEndpoint.OnboardingScriptPath))
}

# Returns $true if MDE reports an onboarded state in the registry.
function Test-DefenderEndpointOnboarded {
    try {
        $state = Get-ItemProperty -Path $script:MDEStatusKey -Name 'OnboardingState' -ErrorAction Stop
        return ([int]$state.OnboardingState -eq 1)
    }
    catch {
        return $false
    }
}

# Query MDE state. Returns a hashtable: Onboarded (bool), SenseService
# (Running/Stopped/Absent), OrgId (tenant org GUID when available),
# SenseVersion. Safe to call on a machine that has never been onboarded.
function Get-DefenderEndpointStatus {
    $result = @{
        Onboarded     = $false
        SenseService  = 'Absent'
        OrgId         = ''
        SenseVersion  = ''
    }

    $result.Onboarded = Test-DefenderEndpointOnboarded

    $sense = Get-Service -Name 'Sense' -ErrorAction SilentlyContinue
    if ($sense) {
        $result.SenseService = [string]$sense.Status
    }

    try {
        $org = Get-ItemProperty -Path $script:MDERootKey -Name 'OrgId' -ErrorAction Stop
        if ($org -and $org.OrgId) { $result.OrgId = [string]$org.OrgId }
    } catch { }

    try {
        $senseExe = Join-Path $env:ProgramFiles 'Windows Defender Advanced Threat Protection\MsSense.exe'
        if (Test-Path -LiteralPath $senseExe) {
            $result.SenseVersion = (Get-Item -LiteralPath $senseExe).VersionInfo.ProductVersion
        }
    } catch { }

    return $result
}

# Validate that a configured onboarding/offboarding script path is safe to
# run. On success it returns the CANONICAL resolved path (the exact path
# that should be executed); on any failure it returns $null. Returning the
# resolved path closes the validate-here / run-there gap — the caller runs
# exactly what was checked.
function Test-MDEScriptPath {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ($Path -match '["`&|<>^%]' -or $Path -match '\.\.[\\/]' -or $Path -match '[\x00-\x1F]') {
        Write-OutputColor "  Script path contains unsafe characters — refusing to run it." -color "Error"
        return $null
    }
    if ($Path -notmatch '\.cmd$') {
        Write-OutputColor "  Onboarding scripts from the Defender portal are .cmd files. '$Path' is not." -color "Error"
        return $null
    }
    # Canonicalize — Resolve-Path collapses any . / .. / mixed separators so
    # the validated path and the executed path are byte-identical.
    $resolved = $null
    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    }
    catch {
        Write-OutputColor "  Onboarding script not found at: $Path" -color "Error"
        return $null
    }
    if ($resolved -notmatch '\.cmd$') {
        Write-OutputColor "  Resolved path is not a .cmd file: $resolved" -color "Error"
        return $null
    }
    return $resolved
}

# Run the operator-supplied MDE onboarding .cmd. Returns $true on a
# confirmed onboarded state.
function Invoke-DefenderEndpointOnboard {
    if (-not (Test-DefenderEndpointConfigured)) {
        Write-OutputColor "  Defender for Endpoint is not configured. Set OnboardingScriptPath" -color "Error"
        Write-OutputColor "  in defaults.json (DefenderEndpoint) to the .cmd downloaded from" -color "Warning"
        Write-OutputColor "  security.microsoft.com > Settings > Endpoints > Onboarding." -color "Warning"
        return $false
    }

    $scriptPath = Test-MDEScriptPath -Path $script:DefenderEndpoint.OnboardingScriptPath
    if (-not $scriptPath) { return $false }

    if (Test-DefenderEndpointOnboarded) {
        Write-OutputColor "  This machine is already onboarded to Defender for Endpoint." -color "Warning"
        $cur = Get-DefenderEndpointStatus
        if ($cur.OrgId) { Write-OutputColor "  Org ID: $($cur.OrgId)" -color "Info" }
        return $true
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        # MDE onboarding is ONE-WAY: offboarding requires a separate .cmd
        # downloaded from the Defender portal which expires ~30 days after
        # generation. Reversal isn't a captured scriptblock; mark the step
        # one-way and re-enter the function at apply time.
        $capScript = $scriptPath
        Push-DryRunStep -Label "Onboard to Microsoft Defender for Endpoint" -Category "Security" -OneWay $true `
            -Params @{ ScriptPath = $capScript } `
            -Preflight {
                if (Test-DefenderEndpointOnboarded) { "Already onboarded to MDE" }
                elseif (-not (Test-Path -LiteralPath $capScript)) { "Onboarding script not found at '$capScript'" }
                else { $true }
            }.GetNewClosure() `
            -Apply { Invoke-DefenderEndpointOnboard | Out-Null }
        Write-OutputColor "  Queued (Dry-Run): MDE onboarding." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued MDE onboarding"
        return $true
    }

    Write-OutputColor "  Running Defender for Endpoint onboarding script..." -color "Info"
    try {
        # The onboarding .cmd writes a registry blob and starts the Sense
        # service. Launch the .cmd directly via -FilePath (Windows runs it
        # through cmd.exe). -FilePath takes the full path as a single value,
        # so paths with spaces work and there is no cmd.exe argument
        # re-tokenization / unquoted-path-search to exploit.
        $proc = Start-Process -FilePath $scriptPath `
            -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            Write-OutputColor "  Onboarding script exited with code $($proc.ExitCode)." -color "Error"
            Write-StructuredLog -Message "Defender for Endpoint onboarding script failed" -Level "ERROR" -Category "Security" -Data @{ ExitCode = $proc.ExitCode }
            return $false
        }
    }
    catch {
        Write-OutputColor "  Onboarding failed: $($_.Exception.Message)" -color "Error"
        return $false
    }

    # The Sense service can take a few seconds to flip the registry state.
    # Check up front, then up to 5 more times at 5s intervals (~25s total).
    $onboarded = $false
    for ($i = 0; $i -lt 6; $i++) {
        if (Test-DefenderEndpointOnboarded) { $onboarded = $true; break }
        if ($i -lt 5) { Start-Sleep -Seconds 5 }
    }

    if ($onboarded) {
        $post = Get-DefenderEndpointStatus
        Write-OutputColor "  Defender for Endpoint onboarding succeeded." -color "Success"
        if ($post.OrgId) { Write-OutputColor "  Org ID: $($post.OrgId)" -color "Info" }
        Add-SessionChange -Category "Security" -Description "Onboarded to Microsoft Defender for Endpoint"
        Write-StructuredLog -Message "Defender for Endpoint onboarding succeeded" -Level "SUCCESS" -Category "Security" -Data @{ OrgId = $post.OrgId }
        return $true
    }

    Write-OutputColor "  Onboarding script ran but the registry state is not yet 'onboarded'." -color "Warning"
    Write-OutputColor "  The Sense service can take a few minutes — re-check status shortly." -color "Info"
    return $false
}

# Run the operator-supplied MDE offboarding .cmd. Offboarding packages
# expire ~30 days after generation; the operator must download a current
# one from the Defender portal.
function Invoke-DefenderEndpointOffboard {
    if ($null -eq $script:DefenderEndpoint -or [string]::IsNullOrWhiteSpace($script:DefenderEndpoint.OffboardingScriptPath)) {
        Write-OutputColor "  No offboarding script configured. Set OffboardingScriptPath in" -color "Error"
        Write-OutputColor "  defaults.json (DefenderEndpoint). Offboarding packages expire ~30 days" -color "Warning"
        Write-OutputColor "  after generation — download a current one from the Defender portal." -color "Warning"
        return $false
    }
    if (-not (Test-DefenderEndpointOnboarded)) {
        Write-OutputColor "  This machine is not onboarded — nothing to offboard." -color "Info"
        return $false
    }

    $scriptPath = Test-MDEScriptPath -Path $script:DefenderEndpoint.OffboardingScriptPath
    if (-not $scriptPath) { return $false }

    if (-not (Confirm-UserAction -Message "  Offboard this machine from Defender for Endpoint?")) {
        Write-OutputColor "  Cancelled." -color "Info"
        return $false
    }

    Write-OutputColor "  Running Defender for Endpoint offboarding script..." -color "Info"
    try {
        # Launch the .cmd directly — see the note in Invoke-DefenderEndpointOnboard.
        $proc = Start-Process -FilePath $scriptPath `
            -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            Write-OutputColor "  Offboarding script exited with code $($proc.ExitCode)." -color "Error"
            return $false
        }
    }
    catch {
        Write-OutputColor "  Offboarding failed: $($_.Exception.Message)" -color "Error"
        return $false
    }

    Write-OutputColor "  Offboarding script completed. Full deregistration can take a few minutes." -color "Success"
    Add-SessionChange -Category "Security" -Description "Offboarded from Microsoft Defender for Endpoint"
    return $true
}

# Trigger the Microsoft-documented EDR detection test. This creates a
# benign test artifact that, on a correctly-onboarded machine, generates
# a "test alert" in the Defender portal within ~10 minutes. It does NOT
# run real malware.
function Test-DefenderEndpointSensor {
    if (-not (Test-DefenderEndpointOnboarded)) {
        Write-OutputColor "  Machine is not onboarded — onboard before running the detection test." -color "Warning"
        return $false
    }
    Write-OutputColor "  Running the Defender for Endpoint detection test..." -color "Info"
    Write-OutputColor "  (creates a benign test file; expect a test alert in the portal within ~10 min)" -color "Info"
    $testDir = $null
    try {
        $testDir = Join-Path $env:TEMP ("mde-test-" + [guid]::NewGuid().ToString('N'))
        $null = New-Item -LiteralPath $testDir -ItemType Directory -Force -ErrorAction Stop
        $testFile = Join-Path $testDir 'mde-detection-test.txt'
        # A powershell.exe child process the sensor observes. No payload, no
        # real malware. The test-file path is GUID-based under %TEMP%, but
        # double any single-quote defensively before it is interpolated into
        # the single-quoted literal in the child -Command.
        $testFileLit = $testFile -replace "'", "''"
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-Command', "Start-Sleep -Seconds 1; Set-Content -LiteralPath '$testFileLit' -Value 'MDE detection test'") `
            -Wait -WindowStyle Hidden -ErrorAction Stop
        Write-OutputColor "  Detection test fired. Check the Defender portal Device timeline shortly." -color "Success"
        return $true
    }
    catch {
        Write-OutputColor "  Detection test failed to run: $($_.Exception.Message)" -color "Error"
        return $false
    }
    finally {
        # Clean up the temp dir even if Start-Process threw.
        if ($testDir -and (Test-Path -LiteralPath $testDir)) {
            Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Interactive Defender for Endpoint management menu.
function Show-DefenderEndpointManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                  DEFENDER FOR ENDPOINT ONBOARDING").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $status = Get-DefenderEndpointStatus
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if ($status.Onboarded) {
            Write-OutputColor "  │$("  State:      ONBOARDED".PadRight(72))│" -color "Success"
        } else {
            Write-OutputColor "  │$("  State:      not onboarded".PadRight(72))│" -color "Warning"
        }
        $svcColor = if ($status.SenseService -eq 'Running') { "Success" } else { "Warning" }
        Write-OutputColor "  │$("  Sensor:     Sense service $($status.SenseService)".PadRight(72))│" -color $svcColor
        if ($status.SenseVersion) {
            Write-OutputColor "  │$("  Version:    $($status.SenseVersion)".PadRight(72))│" -color "Info"
        }
        if ($status.OrgId) {
            Write-OutputColor "  │$("  Org ID:     $($status.OrgId)".PadRight(72))│" -color "Info"
        }
        $cfg = if (Test-DefenderEndpointConfigured) { "configured" } else { "NOT configured (see defaults.json)" }
        Write-OutputColor "  │$("  Config:     $cfg".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[1]  Onboard this server to Defender for Endpoint"
        Write-MenuItem "[2]  Show current onboarding status"
        Write-MenuItem "[3]  Run EDR detection test"
        Write-MenuItem "[4]  Offboard from Defender for Endpoint"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                if (Confirm-UserAction -Message "  Run the Defender for Endpoint onboarding script now?") {
                    $null = Invoke-DefenderEndpointOnboard
                }
                Write-PressEnter
            }
            "2" {
                $s = Get-DefenderEndpointStatus
                Write-OutputColor "" -color "Info"
                if ($s.Onboarded) {
                    Write-OutputColor "  Onboarded. Sense service: $($s.SenseService). Org ID: $($s.OrgId)" -color "Success"
                } else {
                    Write-OutputColor "  Not onboarded. Sense service: $($s.SenseService)." -color "Warning"
                }
                Write-PressEnter
            }
            "3" {
                $null = Test-DefenderEndpointSensor
                Write-PressEnter
            }
            "4" {
                $null = Invoke-DefenderEndpointOffboard
                Write-PressEnter
            }
            default {
                Write-OutputColor "  Invalid selection. Enter 1-4 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
