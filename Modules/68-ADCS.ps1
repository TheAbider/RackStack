#region ===== ACTIVE DIRECTORY CERTIFICATE SERVICES =====
# Bootstraps Active Directory Certificate Services (AD CS) — a Windows
# internal Certification Authority for issuing certificates for
# authentication, code signing, S/MIME, and TLS.
#
# Scope note: this module sets up a SINGLE root CA (Enterprise or
# Standalone). A production two-tier PKI (offline root + issuing
# subordinate) involves decisions — key ceremony, CDP/AIA URLs, CRL
# publication — that should be made deliberately, not automated. This
# module covers the common "one CA for a small environment" case with
# safe defaults, and is explicit about what it does not do.
#
# The CA install is HARD TO REVERSE — removing a CA cleanly is messy and
# any certificates it issued become untrusted. Install-ADCSCertificationAuthority
# therefore requires a typed confirmation.
#
# Config: $script:ADCS (see 00-Initialization.ps1, overridable via
# defaults.json "ADCS").

# Returns $true if a CA common name is configured.
function Test-ADCSConfigured {
    if ($null -eq $script:ADCS) { return $false }
    return (-not [string]::IsNullOrWhiteSpace($script:ADCS.CACommonName))
}

# Returns $true if the AD CS Certification Authority role is installed.
function Test-ADCSRoleInstalled {
    try {
        $feat = Get-WindowsFeature -Name 'ADCS-Cert-Authority' -ErrorAction Stop
        return ($feat -and $feat.InstallState -eq 'Installed')
    }
    catch {
        return $false
    }
}

# Returns $true if a CA has actually been configured (not just the role
# installed). The CertSvc Configuration registry key holds the active CA
# name once Install-AdcsCertificationAuthority has run.
function Test-ADCSCAConfigured {
    try {
        $cfg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' -Name 'Active' -ErrorAction Stop
        return (-not [string]::IsNullOrWhiteSpace($cfg.Active))
    }
    catch {
        return $false
    }
}

# Query AD CS state. Returns role/CA-configured flags plus, when configured,
# the CA common name, CA type, and CertSvc service status.
function Get-ADCSStatus {
    $result = @{
        RoleInstalled = $false
        CAConfigured  = $false
        CAName        = ''
        CAType        = ''
        ServiceStatus = 'Absent'
    }

    $result.RoleInstalled = Test-ADCSRoleInstalled
    if (-not $result.RoleInstalled) { return $result }

    $result.CAConfigured = Test-ADCSCAConfigured
    if ($result.CAConfigured) {
        try {
            $cfg = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration' -Name 'Active' -ErrorAction Stop
            $result.CAName = [string]$cfg.Active
            $caKey = "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration\$($result.CAName)"
            $caCfg = Get-ItemProperty -Path $caKey -Name 'CAType' -ErrorAction SilentlyContinue
            if ($caCfg) {
                # CAType: 0 = Enterprise Root, 1 = Enterprise Sub, 3 = Standalone Root, 4 = Standalone Sub
                switch ([int]$caCfg.CAType) {
                    0 { $result.CAType = 'Enterprise Root' }
                    1 { $result.CAType = 'Enterprise Subordinate' }
                    3 { $result.CAType = 'Standalone Root' }
                    4 { $result.CAType = 'Standalone Subordinate' }
                    default { $result.CAType = 'Unknown' }
                }
            }
        } catch { }
    }

    $svc = Get-Service -Name 'CertSvc' -ErrorAction SilentlyContinue
    if ($svc) { $result.ServiceStatus = [string]$svc.Status }

    return $result
}

# Install the AD CS Certification Authority role plus its management tools.
function Install-ADCSRole {
    if (Test-ADCSRoleInstalled) {
        Write-OutputColor "  The AD CS Certification Authority role is already installed." -color "Info"
        return $true
    }
    if (-not (Test-WindowsServer)) {
        Write-OutputColor "  AD CS is a Windows Server role — this OS is not a server SKU." -color "Error"
        return $false
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        Push-DryRunStep -Label "Install AD CS Certification Authority role" -Category "Roles" -OneWay $false `
            -Preflight {
                if (Test-ADCSRoleInstalled) { "AD CS role already installed" }
                elseif (-not (Test-WindowsServer)) { "Not a Windows Server SKU" }
                else { $true }
            } `
            -Apply { Install-ADCSRole | Out-Null } `
            -Undo  { Uninstall-WindowsFeature -Name 'ADCS-Cert-Authority' -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null }
        Write-OutputColor "  Queued (Dry-Run): install AD CS role." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued AD CS role install"
        return $true
    }

    Write-OutputColor "  Installing the AD CS Certification Authority role..." -color "Info"
    Write-OutputColor "  This can take several minutes." -color "Info"
    $install = Install-WindowsFeatureWithTimeout -FeatureName 'ADCS-Cert-Authority' -DisplayName 'AD CS Certification Authority' -IncludeManagementTools
    if (-not $install.Success) {
        Write-OutputColor "  AD CS role install failed." -color "Error"
        if ($install.Error) { Write-OutputColor "  $($install.Error.Trim())" -color "Error" }
        return $false
    }

    if (Test-ADCSRoleInstalled) {
        Write-OutputColor "  AD CS role installed. Next: configure the Certification Authority." -color "Success"
        Add-SessionChange -Category "Roles" -Description "Installed AD CS Certification Authority role"
        return $true
    }
    Write-OutputColor "  Role install completed but ADCS-Cert-Authority is not reporting installed." -color "Error"
    return $false
}

# Configure the Certification Authority. This is the hard-to-reverse step,
# so it requires the operator to type the CA common name to confirm.
function Install-ADCSCertificationAuthority {
    if (-not (Test-ADCSRoleInstalled)) {
        Write-OutputColor "  Install the AD CS role before configuring a CA." -color "Error"
        return $false
    }
    if (Test-ADCSCAConfigured) {
        Write-OutputColor "  A Certification Authority is already configured on this machine." -color "Warning"
        $cur = Get-ADCSStatus
        Write-OutputColor "  Existing CA: $($cur.CAName) ($($cur.CAType))" -color "Info"
        return $true
    }
    if (-not (Test-ADCSConfigured)) {
        Write-OutputColor "  Set ADCS.CACommonName in defaults.json before configuring the CA." -color "Error"
        return $false
    }

    # Trim the CN so a stray leading/trailing space in defaults.json does not
    # become part of a decade-lived certificate subject (and so the typed
    # confirmation below compares against a clean value).
    $caName    = ([string]$script:ADCS.CACommonName).Trim()
    $caType    = if (-not [string]::IsNullOrWhiteSpace($script:ADCS.CAType)) { $script:ADCS.CAType } else { 'StandaloneRootCA' }
    $keyLength = if ($null -ne $script:ADCS.KeyLength) { [int]$script:ADCS.KeyLength } else { 4096 }
    $hashAlgo  = if (-not [string]::IsNullOrWhiteSpace($script:ADCS.HashAlgorithm)) { $script:ADCS.HashAlgorithm } else { 'SHA256' }
    $validity  = if ($null -ne $script:ADCS.ValidityYears) { [int]$script:ADCS.ValidityYears } else { 10 }

    # Validate the CA common name — it becomes the CN of a long-lived root
    # certificate. Allowlist: letters, digits, spaces, hyphens, underscores.
    if ($caName -notmatch '^[A-Za-z0-9 _-]{1,64}$') {
        Write-OutputColor "  ADCS.CACommonName must be 1-64 chars of letters/digits/space/hyphen/underscore." -color "Error"
        return $false
    }
    $validTypes = @('EnterpriseRootCA', 'StandaloneRootCA')
    if ($caType -notin $validTypes) {
        Write-OutputColor "  ADCS.CAType must be 'EnterpriseRootCA' or 'StandaloneRootCA'." -color "Error"
        Write-OutputColor "  Subordinate CAs need a parent and are out of scope for this module." -color "Warning"
        return $false
    }
    if ($keyLength -notin @(2048, 3072, 4096)) {
        Write-OutputColor "  ADCS.KeyLength must be 2048, 3072, or 4096." -color "Error"
        return $false
    }
    # Validate the hash algorithm against an allowlist — like every other CA
    # parameter, it must never reach the irreversible Install-AdcsCertificationAuthority
    # call unchecked (a typo or a weak value such as SHA1/MD5 would otherwise
    # bake into the root cert for its whole lifetime).
    if ($hashAlgo -notin @('SHA256', 'SHA384', 'SHA512')) {
        Write-OutputColor "  ADCS.HashAlgorithm must be SHA256, SHA384, or SHA512." -color "Error"
        return $false
    }
    if ($validity -lt 1 -or $validity -gt 25) {
        Write-OutputColor "  ADCS.ValidityYears must be between 1 and 25." -color "Error"
        return $false
    }

    # EnterpriseRootCA requires domain membership.
    if ($caType -eq 'EnterpriseRootCA') {
        $isDomainJoined = $false
        try { $isDomainJoined = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
        if (-not $isDomainJoined) {
            Write-OutputColor "  EnterpriseRootCA requires the machine to be domain-joined." -color "Error"
            Write-OutputColor "  Join the domain first, or use 'StandaloneRootCA' in defaults.json." -color "Warning"
            return $false
        }
    }

    # Summarize what's about to happen — this is a long-lived, hard-to-reverse change.
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌─ Certification Authority to be created ────────────────────────────────┐" -color "Warning"
    Write-OutputColor "  │$("  Common name:  $caName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  CA type:      $caType".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Key length:   $keyLength-bit RSA".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Hash:         $hashAlgo".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Validity:     $validity years".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Warning"
    Write-OutputColor "  This is hard to undo. The CA certificate and every certificate it issues" -color "Warning"
    Write-OutputColor "  depend on this configuration for its entire $validity-year lifetime." -color "Warning"
    Write-OutputColor "" -color "Info"

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        # CA configuration is ONE-WAY — removing a configured CA invalidates
        # every certificate it issued. The re-entry Apply path re-runs the
        # typed-CN confirmation prompt at commit time so the safety ritual
        # still fires at the moment of real apply.
        $capCN  = $caName
        $capTyp = $caType
        Push-DryRunStep -Label "Configure CA '$capCN' ($capTyp, $hashAlgo, ${keyLength}b, ${validity}y)" -Category "Roles" -OneWay $true `
            -Params @{ CACommonName = $capCN; CAType = $capTyp; KeyLength = $keyLength; HashAlgorithm = $hashAlgo; ValidityYears = $validity } `
            -Preflight {
                if (Test-ADCSCAConfigured) { "A CA is already configured on this machine" }
                elseif (-not (Test-ADCSRoleInstalled)) { "AD CS role not installed yet" }
                else { $true }
            } `
            -Apply { Install-ADCSCertificationAuthority | Out-Null }
        Write-OutputColor "  Queued (Dry-Run): configure CA '$caName' (typed confirmation deferred to Commit)." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued AD CS CA configuration ($caName)"
        return $true
    }

    # Typed confirmation — operator must enter the CA common name exactly.
    # Case-SENSITIVE (`-cne`): the whole point of the ritual is to prove the
    # operator read the exact CN that will be baked into the root cert.
    $typed = Read-Host "  Type the CA common name '$caName' to proceed (or anything else to cancel)"
    if ($typed.Trim() -cne $caName) {
        Write-OutputColor "  Confirmation did not match (exact, case-sensitive). CA configuration cancelled." -color "Info"
        return $false
    }

    Write-OutputColor "  Configuring the Certification Authority..." -color "Info"
    try {
        Import-Module ADCSDeployment -ErrorAction Stop
        $caParams = @{
            CAType              = $caType
            CACommonName        = $caName
            KeyLength           = $keyLength
            HashAlgorithmName   = $hashAlgo
            CryptoProviderName  = "RSA#Microsoft Software Key Storage Provider"
            ValidityPeriod      = 'Years'
            ValidityPeriodUnits = $validity
            Force               = $true
        }
        $result = Install-AdcsCertificationAuthority @caParams -ErrorAction Stop
        # ErrorId 0 = success; 398 = "already installed" (handled above).
        if ($result -and $result.ErrorId -ne 0) {
            Write-OutputColor "  CA configuration returned error $($result.ErrorId): $($result.ErrorString)" -color "Error"
            return $false
        }
    }
    catch {
        Write-OutputColor "  CA configuration failed: $($_.Exception.Message)" -color "Error"
        Write-StructuredLog -Message "AD CS CA configuration failed" -Level "ERROR" -Category "Security" -Data @{ CAName = $caName; CAType = $caType }
        return $false
    }

    if (Test-ADCSCAConfigured) {
        Write-OutputColor "  Certification Authority '$caName' configured." -color "Success"
        Add-SessionChange -Category "Security" -Description "Configured AD CS Certification Authority '$caName' ($caType)"
        Write-StructuredLog -Message "AD CS CA configured" -Level "SUCCESS" -Category "Security" -Data @{ CAName = $caName; CAType = $caType; KeyLength = $keyLength }
        return $true
    }
    Write-OutputColor "  CA configuration ran but the CA is not reporting as active." -color "Warning"
    return $false
}

# Interactive AD CS management menu.
function Show-ADCSManagement {
    while ($true) {
        if ($script:ReturnToMainMenu) { return }
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                CERTIFICATE SERVICES (AD CS) SETUP").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        $status = Get-ADCSStatus
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if (-not $status.RoleInstalled) {
            Write-OutputColor "  │$("  Role:       not installed".PadRight(72))│" -color "Warning"
        } elseif (-not $status.CAConfigured) {
            Write-OutputColor "  │$("  Role:       installed".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  CA:         not configured (run step 2)".PadRight(72))│" -color "Warning"
        } else {
            Write-OutputColor "  │$("  Role:       installed".PadRight(72))│" -color "Success"
            Write-OutputColor "  │$("  CA:         $($status.CAName)".PadRight(72))│" -color "Success"
            Write-OutputColor "  │$("  Type:       $($status.CAType)".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  CertSvc:    $($status.ServiceStatus)".PadRight(72))│" -color "Info"
        }
        $cfg = if (Test-ADCSConfigured) { "configured" } else { "NOT configured (see defaults.json)" }
        Write-OutputColor "  │$("  Settings:   $cfg".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-MenuItem "[1]  Install AD CS role"
        Write-MenuItem "[2]  Configure Certification Authority"
        Write-MenuItem "[3]  Show CA status"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "  [B] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"
        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ($choice) {
            "1" {
                if (Confirm-UserAction -Message "  Install the AD CS Certification Authority role?") {
                    $null = Install-ADCSRole
                }
                Write-PressEnter
            }
            "2" {
                $null = Install-ADCSCertificationAuthority
                Write-PressEnter
            }
            "3" {
                $s = Get-ADCSStatus
                Write-OutputColor "" -color "Info"
                if ($s.CAConfigured) {
                    Write-OutputColor "  CA '$($s.CAName)' ($($s.CAType)) — CertSvc service $($s.ServiceStatus)." -color "Success"
                } elseif ($s.RoleInstalled) {
                    Write-OutputColor "  AD CS role installed; no CA configured yet." -color "Warning"
                } else {
                    Write-OutputColor "  AD CS role is not installed." -color "Warning"
                }
                Write-PressEnter
            }
            default {
                Write-OutputColor "  Invalid selection. Enter 1-3 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion
