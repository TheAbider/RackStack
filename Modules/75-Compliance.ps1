#region ===== CIS BENCHMARK COMPLIANCE SCANNER (READ-ONLY) =====
# Score this server against a subset of the CIS Microsoft Windows Server
# Level 1 benchmark and emit a graded HTML + JSON report. This module is
# strictly READ-ONLY: it probes current state (registry, secedit, auditpol,
# firewall, SMB, BitLocker, Defender, Secure Boot) and scores it — it never
# changes a setting. Remediation stays in the existing Harden / Remediate
# path; each failing control names the setting that fixes it.
#
# The control set is DATA-DRIVEN: Get-CISControlTable returns one row per
# control (Id, Title, Section, Severity, Expected, RemediationHint, and a
# Check scriptblock). Adding or retuning a control is a table edit — no
# control logic lives in the orchestrator. Expensive external probes
# (secedit /export, auditpol /get) run ONCE into a shared probe cache that
# every Check reads from, so 30+ controls don't re-shell-out per row.
#
# Scoring is severity-weighted (Critical=4 / High=3 / Medium=2 / Low=1):
# percent = passedWeight / evaluableWeight * 100, where "evaluable" is
# Pass+Fail only. Manual (needs human judgement) and Unavailable (SKU/feature
# absent or probe blocked) controls are reported separately and excluded from
# the denominator, so a server isn't penalised for a control it can't run.
# The percent maps to the same A+/A/B/C/D/F ladder as ServerScore.
#
# Scope is a labelled SUBSET of CIS L1 — never claim full benchmark coverage.

# Map a 0-100 percent to the tool's standard letter grade (identical ladder to
# ServerScore / *HealthScore).
function Get-CISGrade {
    param([int]$Percent)
    if ($Percent -ge 95) { "A+" } elseif ($Percent -ge 90) { "A" } elseif ($Percent -ge 80) { "B" }
    elseif ($Percent -ge 70) { "C" } elseif ($Percent -ge 60) { "D" } else { "F" }
}

# Severity -> weight.
function Get-CISSeverityWeight {
    param([string]$Severity)
    switch ($Severity) { "Critical" { 4 } "High" { 3 } "Medium" { 2 } "Low" { 1 } default { 1 } }
}

# Read a single registry value; $null if the path/value is absent.
function Get-CISRegValue {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Name)
    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    }
    catch { return $null }
}

# Export and parse the local security policy ([System Access]) via secedit.
# Returns a hashtable of policy name -> value, or $null if the export fails.
function Get-CISSecurityPolicy {
    $tmp = Join-Path $env:TEMP ("rs-secpol-" + [System.Guid]::NewGuid().ToString("N") + ".inf")
    try {
        # Full System32 path so a PATH-order plant can't substitute secedit.
        $seceditExe = Join-Path $env:SystemRoot 'System32\secedit.exe'
        $null = & $seceditExe /export /areas SECURITYPOLICY /cfg $tmp /quiet 2>&1
        if (-not (Test-Path -LiteralPath $tmp)) { return $null }
        $result = @{}
        $inSection = $false
        foreach ($line in (Get-Content -LiteralPath $tmp -ErrorAction Stop)) {
            $t = $line.Trim()
            if ($t -match '^\[(.+)\]$') { $regexMatches = $matches; $inSection = ($regexMatches[1] -eq 'System Access'); continue }
            if ($inSection -and $t -match '^([^=]+)=(.*)$') {
                $regexMatches = $matches
                $result[$regexMatches[1].Trim()] = $regexMatches[2].Trim()
            }
        }
        return $result
    }
    catch { return $null }
    finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
}

# Get the audit-policy subcategory settings via auditpol (CSV). Returns a
# hashtable of subcategory -> inclusion setting, or $null on failure.
function Get-CISAuditPolicy {
    try {
        $auditpolExe = Join-Path $env:SystemRoot 'System32\auditpol.exe'
        $csv = & $auditpolExe /get /category:* /r 2>$null
        if (-not $csv) { return $null }
        $parsed = $csv | ConvertFrom-Csv
        $result = @{}
        foreach ($row in $parsed) {
            $sub = $row.Subcategory
            $set = $row.'Inclusion Setting'
            if (-not [string]::IsNullOrWhiteSpace($sub)) { $result[$sub.Trim()] = "$set".Trim() }
        }
        return $result
    }
    catch { return $null }
}

# Gather all shared probe state ONCE. Each probe is independent and failure-
# tolerant — a blocked probe leaves its slot $null and the controls that read
# it report Unavailable.
function Get-CISProbeData {
    $p = @{}
    $p.SecPol = Get-CISSecurityPolicy
    $p.Audit = Get-CISAuditPolicy
    try {
        $p.Firewall = @{}
        foreach ($f in (Get-NetFirewallProfile -ErrorAction Stop)) { $p.Firewall["$($f.Name)"] = $f }
    }
    catch { $p.Firewall = $null }
    try { $p.Smb = Get-SmbServerConfiguration -ErrorAction Stop } catch { $p.Smb = $null }
    try { $p.Defender = Get-MpComputerStatus -ErrorAction Stop } catch { $p.Defender = $null }
    try { $p.SecureBoot = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) } catch { $p.SecureBoot = $null }
    try { $p.BitLocker = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop } catch { $p.BitLocker = $null }
    return $p
}

# Helper for control Check blocks: build a result given a current value and a
# pass condition. $null current -> Unavailable.
function New-CISResult {
    param($Current, [bool]$Pass, [string]$Display)
    if ($null -eq $Current) { return @{ Status = "Unavailable"; Current = "(could not read)" } }
    return @{ Status = $(if ($Pass) { "Pass" } else { "Fail" }); Current = $(if ($Display) { $Display } else { "$Current" }) }
}

# Read a [System Access] policy value as an int, or $null if the probe failed
# or the key is absent. The explicit ContainsKey guard matters: indexing a
# missing key returns $null and `[int]$null` is 0, which would silently score a
# missing/unreadable policy as a real Fail instead of Unavailable.
function Get-CISSecPolInt {
    param($SecPol, [string]$Key)
    if ($null -eq $SecPol -or -not $SecPol.ContainsKey($Key)) { return $null }
    $out = 0
    if ([int]::TryParse("$($SecPol[$Key])", [ref]$out)) { return $out } else { return $null }
}

# Read a [System Access] policy value as a string, or $null if absent.
function Get-CISSecPolStr {
    param($SecPol, [string]$Key)
    if ($null -eq $SecPol -or -not $SecPol.ContainsKey($Key)) { return $null }
    return "$($SecPol[$Key])"
}

# The data-driven CIS L1 (subset) control catalog. Each row's Check is a
# scriptblock taking the shared probe cache ($p) and returning
# @{ Status = Pass|Fail|Manual|Unavailable; Current = <display string> }.
function Get-CISControlTable {
    # Registry paths are inlined as literals in each Check below — the Check
    # scriptblocks are invoked locally via `& $c.Check $probe`, where `$using:`
    # does NOT resolve (it is a remoting/job-scope feature only), and closing
    # over loop/function variables is fragile under PS 5.1 + ps2exe.
    return @(
        # ---- 1.1 Password Policy (secedit [System Access]) ----
        [ordered]@{ Id = "CIS-1.1.1"; Title = "Minimum password length >= 14"; Section = "1.1 Password Policy"; Severity = "High"
            Expected = ">= 14"; RemediationHint = "secpol.msc > Password Policy > Minimum password length"
            Check = { param($p) $v = Get-CISSecPolInt $p.SecPol 'MinimumPasswordLength'; New-CISResult $v ($null -ne $v -and $v -ge 14) }
        }
        [ordered]@{ Id = "CIS-1.1.2"; Title = "Password complexity enabled"; Section = "1.1 Password Policy"; Severity = "High"
            Expected = "Enabled (1)"; RemediationHint = "secpol.msc > Password Policy > Password must meet complexity requirements"
            Check = { param($p) $v = Get-CISSecPolStr $p.SecPol 'PasswordComplexity'; New-CISResult $v ("$v" -eq "1") ($(if ("$v" -eq "1") { "Enabled" } else { "Disabled" })) }
        }
        [ordered]@{ Id = "CIS-1.1.3"; Title = "Maximum password age 1-365 days"; Section = "1.1 Password Policy"; Severity = "Medium"
            Expected = "1-365"; RemediationHint = "secpol.msc > Password Policy > Maximum password age"
            Check = { param($p) $v = Get-CISSecPolInt $p.SecPol 'MaximumPasswordAge'; New-CISResult $v ($null -ne $v -and $v -ge 1 -and $v -le 365) "$v days" }
        }
        [ordered]@{ Id = "CIS-1.1.4"; Title = "Minimum password age >= 1 day"; Section = "1.1 Password Policy"; Severity = "Low"
            Expected = ">= 1"; RemediationHint = "secpol.msc > Password Policy > Minimum password age"
            Check = { param($p) $v = Get-CISSecPolInt $p.SecPol 'MinimumPasswordAge'; New-CISResult $v ($null -ne $v -and $v -ge 1) "$v days" }
        }
        [ordered]@{ Id = "CIS-1.1.5"; Title = "Password history >= 24"; Section = "1.1 Password Policy"; Severity = "Medium"
            Expected = ">= 24"; RemediationHint = "secpol.msc > Password Policy > Enforce password history"
            Check = { param($p) $v = Get-CISSecPolInt $p.SecPol 'PasswordHistorySize'; New-CISResult $v ($null -ne $v -and $v -ge 24) }
        }
        [ordered]@{ Id = "CIS-1.1.6"; Title = "Reversible-encryption password storage disabled"; Section = "1.1 Password Policy"; Severity = "High"
            Expected = "Disabled (0)"; RemediationHint = "secpol.msc > Password Policy > Store passwords using reversible encryption"
            Check = { param($p) $v = Get-CISSecPolStr $p.SecPol 'ClearTextPassword'; New-CISResult $v ("$v" -eq "0") ($(if ("$v" -eq "0") { "Disabled" } else { "Enabled" })) }
        }
        # ---- 1.2 Account Lockout Policy ----
        [ordered]@{ Id = "CIS-1.2.1"; Title = "Account lockout duration >= 15 min"; Section = "1.2 Account Lockout"; Severity = "Medium"
            Expected = ">= 15"; RemediationHint = "secpol.msc > Account Lockout Policy > Account lockout duration"
            Check = { param($p) $v = Get-CISSecPolInt $p.SecPol 'LockoutDuration'; New-CISResult $v ($null -ne $v -and $v -ge 15) "$v min" }
        }
        [ordered]@{ Id = "CIS-1.2.2"; Title = "Account lockout threshold 1-5"; Section = "1.2 Account Lockout"; Severity = "High"
            Expected = "1-5"; RemediationHint = "secpol.msc > Account Lockout Policy > Account lockout threshold"
            Check = { param($p) $v = Get-CISSecPolInt $p.SecPol 'LockoutBadCount'; New-CISResult $v ($null -ne $v -and $v -ge 1 -and $v -le 5) "$v attempts" }
        }
        [ordered]@{ Id = "CIS-1.2.3"; Title = "Reset lockout counter >= 15 min"; Section = "1.2 Account Lockout"; Severity = "Low"
            Expected = ">= 15"; RemediationHint = "secpol.msc > Account Lockout Policy > Reset account lockout counter after"
            Check = { param($p) $v = Get-CISSecPolInt $p.SecPol 'ResetLockoutCount'; New-CISResult $v ($null -ne $v -and $v -ge 15) "$v min" }
        }
        # ---- 2.3 Security Options ----
        [ordered]@{ Id = "CIS-2.3.1.1"; Title = "Guest account disabled"; Section = "2.3 Security Options"; Severity = "High"
            Expected = "Disabled (0)"; RemediationHint = "secpol.msc > Security Options > Accounts: Guest account status"
            Check = { param($p) $v = Get-CISSecPolStr $p.SecPol 'EnableGuestAccount'; New-CISResult $v ("$v" -eq "0") ($(if ("$v" -eq "0") { "Disabled" } else { "Enabled" })) }
        }
        [ordered]@{ Id = "CIS-2.3.1.5"; Title = "Built-in Administrator account renamed"; Section = "2.3 Security Options"; Severity = "Medium"
            Expected = "not 'Administrator'"; RemediationHint = "secpol.msc > Security Options > Accounts: Rename administrator account"
            Check = { param($p) $nv = Get-CISSecPolStr $p.SecPol 'NewAdministratorName'; $v = if ($nv) { $nv.Trim('"') } else { $null }; New-CISResult $v ($v -and $v -ne "Administrator") "$v" }
        }
        [ordered]@{ Id = "CIS-2.3.7.1"; Title = "UAC: EnableLUA = 1"; Section = "2.3 Security Options"; Severity = "High"
            Expected = "1"; RemediationHint = "Registry HKLM\...\Policies\System\EnableLUA = 1"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'EnableLUA'; New-CISResult $v ($v -eq 1) }
        }
        [ordered]@{ Id = "CIS-2.3.7.2"; Title = "UAC: ConsentPromptBehaviorAdmin = 2 (consent on secure desktop)"; Section = "2.3 Security Options"; Severity = "Medium"
            Expected = "2"; RemediationHint = "Registry HKLM\...\Policies\System\ConsentPromptBehaviorAdmin = 2"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin'; New-CISResult $v ($v -eq 2) }
        }
        [ordered]@{ Id = "CIS-2.3.7.3"; Title = "UAC: PromptOnSecureDesktop = 1"; Section = "2.3 Security Options"; Severity = "Medium"
            Expected = "1"; RemediationHint = "Registry HKLM\...\Policies\System\PromptOnSecureDesktop = 1"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'PromptOnSecureDesktop'; New-CISResult $v ($v -eq 1) }
        }
        [ordered]@{ Id = "CIS-2.3.10.1"; Title = "LSA: RestrictAnonymous = 1"; Section = "2.3 Security Options"; Severity = "Medium"
            Expected = "1"; RemediationHint = "Registry HKLM\SYSTEM\...\Lsa\RestrictAnonymous = 1"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RestrictAnonymous'; New-CISResult $v ($v -eq 1) }
        }
        [ordered]@{ Id = "CIS-2.3.10.2"; Title = "LSA: RestrictAnonymousSAM = 1"; Section = "2.3 Security Options"; Severity = "Medium"
            Expected = "1"; RemediationHint = "Registry HKLM\SYSTEM\...\Lsa\RestrictAnonymousSAM = 1"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RestrictAnonymousSAM'; New-CISResult $v ($v -eq 1) }
        }
        [ordered]@{ Id = "CIS-2.3.10.3"; Title = "LSA: EveryoneIncludesAnonymous = 0"; Section = "2.3 Security Options"; Severity = "Medium"
            Expected = "0"; RemediationHint = "Registry HKLM\SYSTEM\...\Lsa\EveryoneIncludesAnonymous = 0"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'EveryoneIncludesAnonymous'; New-CISResult $v ($v -eq 0) }
        }
        [ordered]@{ Id = "CIS-2.3.11.7"; Title = "LSA: LmCompatibilityLevel >= 3 (NTLMv2 only)"; Section = "2.3 Security Options"; Severity = "High"
            Expected = ">= 3"; RemediationHint = "Registry HKLM\SYSTEM\...\Lsa\LmCompatibilityLevel = 5"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel'; New-CISResult $v ($null -ne $v -and [int]$v -ge 3) }
        }
        # ---- 9.x Windows Firewall ----
        [ordered]@{ Id = "CIS-9.1.1"; Title = "Domain firewall profile enabled"; Section = "9 Windows Firewall"; Severity = "High"
            Expected = "Enabled"; RemediationHint = "Enable the Domain firewall profile"
            Check = { param($p) if (-not $p.Firewall -or -not $p.Firewall['Domain']) { return (New-CISResult $null $false) } $e = [bool]$p.Firewall['Domain'].Enabled; New-CISResult $e $e ($(if ($e) { "Enabled" } else { "Disabled" })) }
        }
        [ordered]@{ Id = "CIS-9.2.1"; Title = "Private firewall profile enabled"; Section = "9 Windows Firewall"; Severity = "High"
            Expected = "Enabled"; RemediationHint = "Enable the Private firewall profile"
            Check = { param($p) if (-not $p.Firewall -or -not $p.Firewall['Private']) { return (New-CISResult $null $false) } $e = [bool]$p.Firewall['Private'].Enabled; New-CISResult $e $e ($(if ($e) { "Enabled" } else { "Disabled" })) }
        }
        [ordered]@{ Id = "CIS-9.3.1"; Title = "Public firewall profile enabled"; Section = "9 Windows Firewall"; Severity = "High"
            Expected = "Enabled"; RemediationHint = "Enable the Public firewall profile"
            Check = { param($p) if (-not $p.Firewall -or -not $p.Firewall['Public']) { return (New-CISResult $null $false) } $e = [bool]$p.Firewall['Public'].Enabled; New-CISResult $e $e ($(if ($e) { "Enabled" } else { "Disabled" })) }
        }
        [ordered]@{ Id = "CIS-9.x.2"; Title = "Default inbound action = Block (all profiles)"; Section = "9 Windows Firewall"; Severity = "Medium"
            Expected = "Block"; RemediationHint = "Set DefaultInboundAction = Block on each firewall profile"
            Check = { param($p)
                if (-not $p.Firewall) { return (New-CISResult $null $false) }
                $names = @('Domain', 'Private', 'Public'); $bad = @()
                foreach ($n in $names) { if ($p.Firewall[$n] -and "$($p.Firewall[$n].DefaultInboundAction)" -ne 'Block') { $bad += $n } }
                New-CISResult "x" ($bad.Count -eq 0) ($(if ($bad.Count -eq 0) { "Block (all)" } else { "Not Block: $($bad -join ',')" }))
            }
        }
        # ---- RDP ----
        [ordered]@{ Id = "CIS-RDP.1"; Title = "RDP Network Level Authentication required"; Section = "Remote Desktop"; Severity = "High"
            Expected = "UserAuthentication = 1"; RemediationHint = "Enable NLA (Harden / RDP menu sets UserAuthentication=1)"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication'; New-CISResult $v ($v -eq 1) }
        }
        [ordered]@{ Id = "CIS-RDP.2"; Title = "RDP minimum encryption level high (>= 3)"; Section = "Remote Desktop"; Severity = "Medium"
            Expected = ">= 3"; RemediationHint = "Set MinEncryptionLevel = 3 on RDP-Tcp"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'MinEncryptionLevel'; New-CISResult $v ($null -ne $v -and [int]$v -ge 3) }
        }
        # ---- 17.x Audit Policy ----
        [ordered]@{ Id = "CIS-17.5.x"; Title = "Audit Logon = Success and Failure"; Section = "17 Audit Policy"; Severity = "Medium"
            Expected = "Success and Failure"; RemediationHint = "auditpol /set /subcategory:Logon /success:enable /failure:enable"
            Check = { param($p) $v = if ($p.Audit) { $p.Audit['Logon'] } else { $null }; New-CISResult $v ("$v" -eq "Success and Failure") "$v" }
        }
        [ordered]@{ Id = "CIS-17.1.x"; Title = "Audit Credential Validation = Success and Failure"; Section = "17 Audit Policy"; Severity = "Medium"
            Expected = "Success and Failure"; RemediationHint = "auditpol /set /subcategory:'Credential Validation' /success:enable /failure:enable"
            Check = { param($p) $v = if ($p.Audit) { $p.Audit['Credential Validation'] } else { $null }; New-CISResult $v ("$v" -eq "Success and Failure") "$v" }
        }
        # ---- 18.x System Hardening ----
        [ordered]@{ Id = "CIS-18.x.1"; Title = "SMBv1 server protocol disabled"; Section = "18 System Hardening"; Severity = "High"
            Expected = "Disabled"; RemediationHint = "Disable-WindowsOptionalFeature SMB1Protocol (or Set-SmbServerConfiguration -EnableSMB1Protocol $false)"
            Check = { param($p) if (-not $p.Smb) { return (New-CISResult $null $false) } $on = [bool]$p.Smb.EnableSMB1Protocol; New-CISResult (-not $on) (-not $on) ($(if ($on) { "Enabled" } else { "Disabled" })) }
        }
        [ordered]@{ Id = "CIS-18.x.2"; Title = "SMB server signing required"; Section = "18 System Hardening"; Severity = "Medium"
            Expected = "Required"; RemediationHint = "Set-SmbServerConfiguration -RequireSecuritySignature $true"
            Check = { param($p) if (-not $p.Smb) { return (New-CISResult $null $false) } $req = [bool]$p.Smb.RequireSecuritySignature; New-CISResult $req $req ($(if ($req) { "Required" } else { "Not required" })) }
        }
        [ordered]@{ Id = "CIS-18.x.3"; Title = "TLS 1.0 disabled (SCHANNEL)"; Section = "18 System Hardening"; Severity = "High"
            Expected = "Disabled"; RemediationHint = "SCHANNEL\Protocols\TLS 1.0\Server\Enabled = 0, DisabledByDefault = 1"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server' -Name 'Enabled'; if ($null -eq $v) { return @{ Status = "Manual"; Current = "key absent (default-enabled)" } }; New-CISResult $v ($v -eq 0) ($(if ($v -eq 0) { "Disabled" } else { "Enabled" })) }
        }
        [ordered]@{ Id = "CIS-18.x.4"; Title = "TLS 1.1 disabled (SCHANNEL)"; Section = "18 System Hardening"; Severity = "Medium"
            Expected = "Disabled"; RemediationHint = "SCHANNEL\Protocols\TLS 1.1\Server\Enabled = 0, DisabledByDefault = 1"
            Check = { param($p) $v = Get-CISRegValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server' -Name 'Enabled'; if ($null -eq $v) { return @{ Status = "Manual"; Current = "key absent (default-enabled)" } }; New-CISResult $v ($v -eq 0) ($(if ($v -eq 0) { "Disabled" } else { "Enabled" })) }
        }
        [ordered]@{ Id = "CIS-18.x.5"; Title = "Secure Boot enabled (UEFI)"; Section = "18 System Hardening"; Severity = "Medium"
            Expected = "Enabled"; RemediationHint = "Enable Secure Boot in UEFI firmware (requires UEFI/GPT)"
            Check = { param($p) if ($null -eq $p.SecureBoot) { return @{ Status = "Manual"; Current = "non-UEFI or not determinable" } } New-CISResult $p.SecureBoot ([bool]$p.SecureBoot) ($(if ($p.SecureBoot) { "Enabled" } else { "Disabled" })) }
        }
        [ordered]@{ Id = "CIS-18.x.6"; Title = "BitLocker on system drive"; Section = "18 System Hardening"; Severity = "Medium"
            Expected = "Protection On"; RemediationHint = "Enable BitLocker on the OS volume (BitLocker menu)"
            Check = { param($p) if ($null -eq $p.BitLocker) { return (New-CISResult $null $false) } $on = ("$($p.BitLocker.ProtectionStatus)" -eq 'On'); New-CISResult $on $on "$($p.BitLocker.ProtectionStatus)" }
        }
        [ordered]@{ Id = "CIS-18.x.7"; Title = "Microsoft Defender real-time protection on"; Section = "18 System Hardening"; Severity = "High"
            Expected = "On"; RemediationHint = "Enable Defender real-time protection (or confirm a 3rd-party AV manages it)"
            Check = { param($p) if ($null -eq $p.Defender) { return @{ Status = "Manual"; Current = "Defender status unavailable (3rd-party AV?)" } } $on = [bool]$p.Defender.RealTimeProtectionEnabled; New-CISResult $on $on ($(if ($on) { "On" } else { "Off" })) }
        }
    )
}

# Orchestrator: run the probes, evaluate every control, compute the severity-
# weighted score, and return the full scored result object. PURE SCAN — no
# writes to system state.
function Invoke-CISComplianceScan {
    $probe = Get-CISProbeData
    $controls = Get-CISControlTable
    $results = @()
    foreach ($c in $controls) {
        $status = "Unavailable"; $current = "(error)"
        try {
            $r = & $c.Check $probe
            if ($r -and $r.Status) { $status = $r.Status; $current = $r.Current }
        }
        catch { $status = "Unavailable"; $current = "probe error" }
        $results += [PSCustomObject]@{
            Id = $c.Id; Title = $c.Title; Section = $c.Section; Severity = $c.Severity
            Status = $status; Expected = $c.Expected; Current = $current; RemediationHint = $c.RemediationHint
            Weight = (Get-CISSeverityWeight -Severity $c.Severity)
        }
    }

    $passWeight = ($results | Where-Object { $_.Status -eq 'Pass' } | Measure-Object -Property Weight -Sum).Sum
    $failWeight = ($results | Where-Object { $_.Status -eq 'Fail' } | Measure-Object -Property Weight -Sum).Sum
    if ($null -eq $passWeight) { $passWeight = 0 }
    if ($null -eq $failWeight) { $failWeight = 0 }
    $evalWeight = $passWeight + $failWeight
    $pct = if ($evalWeight -gt 0) { [math]::Round(($passWeight / $evalWeight) * 100) } else { 0 }

    $counts = @{
        Pass        = @($results | Where-Object { $_.Status -eq 'Pass' }).Count
        Fail        = @($results | Where-Object { $_.Status -eq 'Fail' }).Count
        Manual      = @($results | Where-Object { $_.Status -eq 'Manual' }).Count
        Unavailable = @($results | Where-Object { $_.Status -eq 'Unavailable' }).Count
        Total       = $results.Count
    }

    # Per-section roll-up (evaluable controls only).
    $sections = @()
    foreach ($sec in ($results | Select-Object -ExpandProperty Section -Unique)) {
        $secCtrls = @($results | Where-Object { $_.Section -eq $sec })
        $sp = @($secCtrls | Where-Object { $_.Status -eq 'Pass' }).Count
        $sf = @($secCtrls | Where-Object { $_.Status -eq 'Fail' }).Count
        $sPct = if (($sp + $sf) -gt 0) { [math]::Round(($sp / ($sp + $sf)) * 100) } else { 0 }
        $sm = @($secCtrls | Where-Object { $_.Status -eq 'Manual' }).Count
        $su = @($secCtrls | Where-Object { $_.Status -eq 'Unavailable' }).Count
        $sections += [PSCustomObject]@{ Section = $sec; Percent = $sPct; Pass = $sp; Fail = $sf; Manual = $sm; Unavailable = $su; Total = $secCtrls.Count }
    }

    # When nothing could be evaluated (e.g. run without admin, all probes blocked)
    # the score is meaningless — surface "N/A" rather than a misleading 0% / F.
    $grade = if ($evalWeight -gt 0) { Get-CISGrade -Percent ([int]$pct) } else { "N/A" }

    return [PSCustomObject]@{
        Tier = "L1"
        Percent = [int]$pct
        Grade = $grade
        PassedWeight = [int]$passWeight
        EvaluableWeight = [int]$evalWeight
        Counts = $counts
        Sections = $sections
        Controls = $results
    }
}

# Resolve the hardened directory for compliance report output.
function Get-CISReportDir {
    $secure = Get-RackStackSecureStateDir
    if ([string]::IsNullOrWhiteSpace($secure)) {
        Write-OutputColor "  Warning: could not use the protected state directory; the report will go to" -color "Warning"
        Write-OutputColor "  a non-hardened path. A compliance report enumerates this host's security gaps —" -color "Warning"
        Write-OutputColor "  restrict its ACL before sharing it." -color "Warning"
        $secure = $script:TempPath
    }
    $dir = Join-Path $secure "compliance"
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -LiteralPath $dir -ItemType Directory -Force -ErrorAction SilentlyContinue }
    return $dir
}

# Write the scored result to an HTML report (atomic: build -> .tmp -> Move).
function Export-CISComplianceHTML {
    param([Parameter(Mandatory = $true)]$Result)
    $dir = Get-CISReportDir
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $file = Join-Path $dir "CIS_Compliance_$($env:COMPUTERNAME)_$stamp.html"

    $gradeClass = if ($Result.Percent -ge 80) { "status-good" } elseif ($Result.Percent -ge 60) { "status-warn" } else { "status-bad" }
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">')
    [void]$sb.AppendLine('<title>CIS Compliance Report</title><style>')
    [void]$sb.AppendLine('body{font-family:Segoe UI,Arial,sans-serif;margin:24px;background:#1e1e1e;color:#ddd}')
    [void]$sb.AppendLine('h1,h2{color:#fff} table{border-collapse:collapse;width:100%;margin:12px 0}')
    [void]$sb.AppendLine('th,td{border:1px solid #444;padding:6px 10px;text-align:left;font-size:13px}')
    [void]$sb.AppendLine('th{background:#2d2d2d} .status-good{color:#4ec94e} .status-warn{color:#e6b800} .status-bad{color:#e05555}')
    [void]$sb.AppendLine('.bar{height:18px;background:#333;border-radius:3px;overflow:hidden} .bar>span{display:block;height:100%;background:#4ec94e}')
    [void]$sb.AppendLine('.banner{font-size:28px;font-weight:bold;padding:16px;border-radius:6px;background:#2d2d2d;margin:8px 0}')
    [void]$sb.AppendLine('.muted{color:#999;font-size:12px}</style></head><body>')
    [void]$sb.AppendLine("<h1>CIS Windows Server L1 Compliance (subset)</h1>")
    [void]$sb.AppendLine("<p class='muted'>Host: $(ConvertTo-HtmlSafe $env:COMPUTERNAME) &middot; Generated: $(ConvertTo-HtmlSafe (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) &middot; $(ConvertTo-HtmlSafe $script:ToolFullName) v$(ConvertTo-HtmlSafe $script:ScriptVersion)</p>")
    [void]$sb.AppendLine("<div class='banner $gradeClass'>Score: $($Result.Percent)% &mdash; Grade: $(ConvertTo-HtmlSafe $Result.Grade)</div>")
    [void]$sb.AppendLine("<p>Pass: $($Result.Counts.Pass) &middot; Fail: $($Result.Counts.Fail) &middot; Manual: $($Result.Counts.Manual) &middot; Unavailable: $($Result.Counts.Unavailable) &middot; Total: $($Result.Counts.Total) &nbsp; <span class='muted'>(Manual + Unavailable excluded from the score)</span></p>")

    [void]$sb.AppendLine("<h2>By Section</h2><table><tr><th>Section</th><th>Score</th><th>Pass/Fail</th><th></th></tr>")
    foreach ($s in $Result.Sections) {
        $w = [math]::Max(0, [math]::Min(100, [int]$s.Percent))
        [void]$sb.AppendLine("<tr><td>$(ConvertTo-HtmlSafe $s.Section)</td><td>$($s.Percent)%</td><td>$($s.Pass)/$($s.Pass + $s.Fail)</td><td><div class='bar'><span style='width:$w%'></span></div></td></tr>")
    }
    [void]$sb.AppendLine("</table>")

    [void]$sb.AppendLine("<h2>Controls</h2><table><tr><th>ID</th><th>Title</th><th>Severity</th><th>Status</th><th>Current</th><th>Expected</th><th>Remediation</th></tr>")
    foreach ($c in $Result.Controls) {
        $cls = switch ($c.Status) { "Pass" { "status-good" } "Fail" { "status-bad" } default { "status-warn" } }
        [void]$sb.AppendLine("<tr><td>$(ConvertTo-HtmlSafe $c.Id)</td><td>$(ConvertTo-HtmlSafe $c.Title)</td><td>$(ConvertTo-HtmlSafe $c.Severity)</td><td class='$cls'>$(ConvertTo-HtmlSafe $c.Status)</td><td>$(ConvertTo-HtmlSafe ([string]$c.Current))</td><td>$(ConvertTo-HtmlSafe ([string]$c.Expected))</td><td class='muted'>$(ConvertTo-HtmlSafe $c.RemediationHint)</td></tr>")
    }
    [void]$sb.AppendLine("</table><p class='muted'>CIS L1 subset ($($Result.Counts.Total) controls) — not full benchmark coverage. Remediation stays in the Harden / Remediate workflow.</p></body></html>")

    $tmp = "$file.tmp"
    try {
        Set-Content -LiteralPath $tmp -Value $sb.ToString() -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $tmp -Destination $file -Force -ErrorAction Stop
        return $file
    }
    catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        Write-OutputColor "  Failed to write HTML report: $($_.Exception.Message)" -color "Error"
        return $null
    }
}

# Render the scored result to the console (box style consistent with ServerScore).
function Show-CISComplianceReport {
    param([Parameter(Mandatory = $true)]$Result)
    $color = if ($Result.Percent -ge 90) { "Success" } elseif ($Result.Percent -ge 70) { "Warning" } else { "Error" }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color $color
    Write-OutputColor "  ║$("    CIS L1 COMPLIANCE: $($Result.Percent)% — Grade: $($Result.Grade)".PadRight(72))║" -color $color
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color $color
    Write-OutputColor "  Pass: $($Result.Counts.Pass)  Fail: $($Result.Counts.Fail)  Manual: $($Result.Counts.Manual)  Unavailable: $($Result.Counts.Unavailable)  (of $($Result.Counts.Total))" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  By section:" -color "Info"
    foreach ($s in $Result.Sections) {
        $sc = if ($s.Percent -ge 90) { "Success" } elseif ($s.Percent -ge 70) { "Warning" } else { "Error" }
        Write-OutputColor ("    {0,-28} {1,3}%  ({2}/{3})" -f $s.Section, $s.Percent, $s.Pass, ($s.Pass + $s.Fail)) -color $sc
    }
    $failed = @($Result.Controls | Where-Object { $_.Status -eq 'Fail' })
    if ($failed.Count -gt 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Failed controls:" -color "Error"
        foreach ($f in $failed) {
            Write-OutputColor ("    [{0}] {1}  (current: {2}; expected: {3})" -f $f.Id, $f.Title, $f.Current, $f.Expected) -color "Warning"
        }
    }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  CIS L1 subset ($($Result.Counts.Total) controls) — not full benchmark coverage." -color "Debug"
}

# CLI entry: CISScan — run the scan, render/emit, write reports. Returns the
# integer percent so the dispatcher can set the exit code.
function Start-CISScan {
    $result = Invoke-CISComplianceScan
    $htmlPath = Export-CISComplianceHTML -Result $result

    if ($script:CLIOutputFormat -eq 'JSON') {
        $jsonResult = @{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'CISScan'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
            Tier = $result.Tier; OverallPercent = $result.Percent; Grade = $result.Grade
            Weighted = @{ PassedWeight = $result.PassedWeight; EvaluableWeight = $result.EvaluableWeight }
            Counts = $result.Counts
            Sections = @($result.Sections | ForEach-Object { @{ Section = $_.Section; Percent = $_.Percent; Pass = $_.Pass; Fail = $_.Fail } })
            Controls = @($result.Controls | ForEach-Object { @{ Id = $_.Id; Title = $_.Title; Section = $_.Section; Severity = $_.Severity; Status = $_.Status; Expected = $_.Expected; Current = "$($_.Current)"; RemediationHint = $_.RemediationHint } })
            ReportPath = "$htmlPath"
        }
        Write-Output ($jsonResult | ConvertTo-Json -Depth 10)
    }
    else {
        Show-CISComplianceReport -Result $result
        if ($htmlPath) { Write-OutputColor "  HTML report: $htmlPath" -color "Info" }
    }
    return [int]$result.Percent
}

# Interactive menu entry (Operations > CIS Compliance Scan).
function Invoke-CISScanInteractive {
    Clear-Host
    Write-CenteredOutput "CIS L1 Compliance Scan" -color "Info"
    Write-OutputColor "  Read-only scan against a subset of the CIS Windows Server L1 benchmark." -color "Info"
    Write-OutputColor "  Probing security policy, firewall, RDP, audit policy, SMB, and hardening..." -color "Info"
    $result = Invoke-CISComplianceScan
    Show-CISComplianceReport -Result $result
    $htmlPath = Export-CISComplianceHTML -Result $result
    if ($htmlPath) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  HTML report written to:" -color "Success"
        Write-OutputColor "    $htmlPath" -color "Info"
    }
}
#endregion
