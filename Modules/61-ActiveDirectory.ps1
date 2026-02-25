#region ===== ACTIVE DIRECTORY PROMOTION =====
# Function to check if AD-Domain-Services feature is installed
function Test-ADDSInstalled {
    if (-not (Test-WindowsServer)) { return $false }
    try {
        $feature = Get-WindowsFeature -Name AD-Domain-Services -ErrorAction SilentlyContinue
        return ($null -ne $feature -and $feature.Installed)
    }
    catch {
        return $false
    }
}

# Function to check AD DS prerequisites before promotion
function Test-ADDSPrerequisites {
    $checks = @()

    # Check 1: Server OS
    $isServer = Test-WindowsServer
    $checks += @{
        Name   = "Windows Server OS"
        Passed = $isServer
        Detail = if ($isServer) { "Running Windows Server" } else { "AD DS requires Windows Server" }
    }

    # Check 2: Static IP configured
    $staticIP = $false
    try {
        $adapters = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {
            $null -ne $_.IPv4Address -and $_.IPv4Address.Count -gt 0
        }
        foreach ($adapter in $adapters) {
            $ifIndex = $adapter.InterfaceIndex
            $ipInterface = Get-NetIPInterface -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($null -ne $ipInterface -and $ipInterface.Dhcp -eq "Disabled") {
                $staticIP = $true
                break
            }
        }
    }
    catch {
        # Ignore - will show as failed
    }
    $checks += @{
        Name   = "Static IP Address"
        Passed = $staticIP
        Detail = if ($staticIP) { "Static IP configured" } else { "A static IP is required for a Domain Controller" }
    }

    # Check 3: DNS configured
    $dnsConfigured = $false
    try {
        $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.ServerAddresses.Count -gt 0 }
        if ($null -ne $dnsServers -and @($dnsServers).Count -gt 0) {
            $dnsConfigured = $true
        }
    }
    catch {
        # Ignore
    }
    $checks += @{
        Name   = "DNS Configuration"
        Passed = $dnsConfigured
        Detail = if ($dnsConfigured) { "DNS servers configured" } else { "DNS must be configured" }
    }

    # Check 4: Not already a DC
    $isNotDC = $true
    try {
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $compSys = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($osInfo.ProductType -eq 2 -or $compSys.DomainRole -ge 4) {
            $isNotDC = $false
        }
    }
    catch {
        # Ignore
    }
    $checks += @{
        Name   = "Not Already a DC"
        Passed = $isNotDC
        Detail = if ($isNotDC) { "Server is not a Domain Controller" } else { "Server is already a Domain Controller" }
    }

    $allPassed = @($checks | Where-Object { -not $_.Passed }).Count -eq 0

    return @{
        Passed = $allPassed
        Checks = $checks
    }
}

# Function to display prerequisite check results
function Show-ADDSPrerequisiteResults {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Results
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PREREQUISITE CHECK RESULTS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    foreach ($check in $Results.Checks) {
        $status = if ($check.Passed) { "[PASS]" } else { "[FAIL]" }
        $statusColor = if ($check.Passed) { "Success" } else { "Error" }
        $line = "  $status  $($check.Name): $($check.Detail)"
        if ($line.Length -gt 69) { $line = $line.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($line.PadRight(72))│" -color $statusColor
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($Results.Passed) {
        Write-OutputColor "  All prerequisites passed." -color "Success"
    }
    else {
        Write-OutputColor "  Some prerequisites are not met. Review before proceeding." -color "Warning"
    }
}

# Function to install AD DS role if not present
function Install-ADDSRoleIfNeeded {
    if (Test-ADDSInstalled) {
        Write-OutputColor "  AD DS role is already installed." -color "Success"
        return $true
    }

    Write-OutputColor "  AD DS role is not installed." -color "Warning"
    if (-not (Confirm-UserAction -Message "Install AD-Domain-Services role now?")) {
        Write-OutputColor "  AD DS role installation cancelled." -color "Info"
        return $false
    }

    try {
        Write-OutputColor "`n  Installing AD-Domain-Services... This may take several minutes." -color "Info"
        $installResult = Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -ErrorAction Stop

        if ($installResult.Success) {
            Write-OutputColor "  AD-Domain-Services installed successfully!" -color "Success"
            Add-SessionChange -Category "AD DS" -Description "Installed AD-Domain-Services role"
            return $true
        }
        else {
            Write-OutputColor "  AD-Domain-Services installation did not complete successfully." -color "Error"
            return $false
        }
    }
    catch {
        Write-OutputColor "  Failed to install AD-Domain-Services: $_" -color "Error"
        return $false
    }
}

# Function to validate domain name format
function Test-ValidDomainName {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DomainName
    )

    # Must contain at least one dot and valid DNS characters
    if ($DomainName -notmatch '\.') { return $false }
    if ($DomainName -notmatch '^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)+$') { return $false }
    return $true
}

# Function to extract NetBIOS name from FQDN
function Get-NetBIOSNameFromFQDN {
    param (
        [Parameter(Mandatory=$true)]
        [string]$DomainName
    )

    $parts = $DomainName.Split(".")
    return $parts[0].ToUpper()
}

# Function to show functional level selection menu
function Select-FunctionalLevel {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT FUNCTIONAL LEVEL".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "[1]  Win2012R2    (Server 2012 R2)"
    Write-MenuItem -Text "[2]  WinThreshold (Server 2016) - Default"
    Write-MenuItem -Text "[3]  Win2019      (Server 2019)"
    Write-MenuItem -Text "[4]  Win2022      (Server 2022)"
    Write-MenuItem -Text "[5]  Win2025      (Server 2025)"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $levelChoice = Read-Host "  Select (default: 2)"
    $navResult = Test-NavigationCommand -UserInput $levelChoice
    if ($navResult.ShouldReturn) { return $null }

    switch ($levelChoice) {
        "1" { return @{ Value = "Win2012R2";    Display = "Win2012R2 (Server 2012 R2)" } }
        "3" { return @{ Value = "Win2019";      Display = "Win2019 (Server 2019)" } }
        "4" { return @{ Value = "Win2022";      Display = "Win2022 (Server 2022)" } }
        "5" { return @{ Value = "Win2025";      Display = "Win2025 (Server 2025)" } }
        default { return @{ Value = "WinThreshold"; Display = "WinThreshold (Server 2016)" } }
    }
}

# Function to prompt and confirm DSRM password
function Read-DSRMPassword {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Enter Directory Services Restore Mode (DSRM) password:" -color "Info"
    $dsrmPassword = Read-Host "  DSRM Password" -AsSecureString

    Write-OutputColor "  Confirm DSRM password:" -color "Info"
    $dsrmConfirm = Read-Host "  Confirm Password" -AsSecureString

    # Convert to plaintext for comparison
    $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dsrmPassword)
    $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dsrmConfirm)
    try {
        $plain1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
        $plain2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)

        if ($plain1 -ne $plain2) {
            Write-OutputColor "  Passwords do not match." -color "Error"
            return $null
        }

        if ($plain1.Length -lt 8) {
            Write-OutputColor "  DSRM password must be at least 8 characters." -color "Error"
            return $null
        }
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)
    }

    return $dsrmPassword
}

# Main AD DS Promotion menu
function Show-ADDSPromotionMenu {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("               AD DS DOMAIN CONTROLLER PROMOTION").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PROMOTION OPTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem -Text "[1]  New Forest (First DC in new domain)"
    Write-MenuItem -Text "[2]  Additional Domain Controller (Join existing domain)"
    Write-MenuItem -Text "[3]  Read-Only Domain Controller (RODC)"
    Write-MenuItem -Text "[4]  Check AD DS Status"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" { Install-NewForest }
        "2" { Install-AdditionalDC }
        "3" { Install-ReadOnlyDC }
        "4" { Show-ADDSStatus }
    }
}

# Wizard to promote server as first DC in a new forest
function Install-NewForest {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    NEW FOREST — FIRST DOMAIN CONTROLLER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 1: Prerequisites
    $prereqs = Test-ADDSPrerequisites
    Show-ADDSPrerequisiteResults -Results $prereqs

    if (-not $prereqs.Passed) {
        if (-not (Confirm-UserAction -Message "Continue despite prerequisite failures?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 2: Install AD DS role if needed
    if (-not (Install-ADDSRoleIfNeeded)) {
        Write-PressEnter
        return
    }

    # Step 3: Domain name
    Write-OutputColor "" -color "Info"
    $domainName = Read-Host "  Enter domain name (e.g., corp.contoso.com)"
    $navResult = Test-NavigationCommand -UserInput $domainName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        Write-OutputColor "  Domain name is required." -color "Error"
        Write-PressEnter
        return
    }

    if (-not (Test-ValidDomainName -DomainName $domainName)) {
        Write-OutputColor "  Invalid domain name format. Must contain at least one dot and valid DNS characters." -color "Error"
        Write-PressEnter
        return
    }

    $netbiosName = Get-NetBIOSNameFromFQDN -DomainName $domainName

    # Step 4: Functional level
    $level = Select-FunctionalLevel
    if ($null -eq $level) { return }
    $forestMode = $level.Value
    $domainMode = $level.Value
    $levelDisplay = $level.Display

    # Step 5: DSRM password
    $dsrmPassword = Read-DSRMPassword
    if ($null -eq $dsrmPassword) {
        Write-PressEnter
        return
    }

    # Step 6: Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NEW FOREST CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $lineStr = "  Domain Name:      $domainName"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  NetBIOS Name:     $netbiosName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Forest Mode:      $levelDisplay".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Domain Mode:      $levelDisplay".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Install DNS:      Yes".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Database Path:    C:\Windows\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Log Path:         C:\Windows\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  SYSVOL Path:      C:\Windows\SYSVOL".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 7: Confirm
    if (-not (Confirm-UserAction -Message "Promote this server to Domain Controller?")) {
        Write-OutputColor "  Promotion cancelled." -color "Info"
        Write-PressEnter
        return
    }

    # Step 8: Execute
    try {
        Write-OutputColor "`n  Promoting server to Domain Controller... This will take several minutes." -color "Info"
        Write-OutputColor "  Do NOT close this window." -color "Warning"

        Import-Module ADDSDeployment -ErrorAction Stop

        Install-ADDSForest `
            -DomainName $domainName `
            -ForestMode $forestMode `
            -DomainMode $domainMode `
            -DomainNetbiosName $netbiosName `
            -SafeModeAdministratorPassword $dsrmPassword `
            -InstallDns:$true `
            -CreateDnsDelegation:$false `
            -NoRebootOnCompletion:$true `
            -Force:$true `
            -ErrorAction Stop

        Write-OutputColor "`n  Domain Controller promotion completed successfully!" -color "Success"
        $global:RebootNeeded = $true
        Add-SessionChange -Category "AD DS" -Description "Promoted to DC: New forest $domainName"
        Write-OutputColor "  A reboot is required to complete the promotion." -color "Warning"
    }
    catch {
        Write-OutputColor "  Failed to promote Domain Controller: $_" -color "Error"
        Add-SessionChange -Category "AD DS" -Description "DC promotion failed: New forest $domainName - $_"
    }

    Write-PressEnter
}

# Wizard to add an additional Domain Controller to an existing domain
function Install-AdditionalDC {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("              ADDITIONAL DOMAIN CONTROLLER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 1: Prerequisites
    $prereqs = Test-ADDSPrerequisites
    Show-ADDSPrerequisiteResults -Results $prereqs

    if (-not $prereqs.Passed) {
        if (-not (Confirm-UserAction -Message "Continue despite prerequisite failures?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 2: Install AD DS role if needed
    if (-not (Install-ADDSRoleIfNeeded)) {
        Write-PressEnter
        return
    }

    # Step 3: Domain to join
    Write-OutputColor "" -color "Info"
    $domainName = Read-Host "  Enter domain to join (e.g., corp.contoso.com)"
    $navResult = Test-NavigationCommand -UserInput $domainName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        Write-OutputColor "  Domain name is required." -color "Error"
        Write-PressEnter
        return
    }

    if (-not (Test-ValidDomainName -DomainName $domainName)) {
        Write-OutputColor "  Invalid domain name format." -color "Error"
        Write-PressEnter
        return
    }

    # Step 4: Domain admin credentials
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  You will need domain admin credentials." -color "Info"
    $credential = Get-Credential -Message "Enter domain admin credentials for $domainName"
    if ($null -eq $credential) {
        Write-OutputColor "  Credential entry cancelled." -color "Warning"
        Write-PressEnter
        return
    }

    # Step 5: Site name
    Write-OutputColor "" -color "Info"
    $siteName = Read-Host "  Enter AD site name (default: Default-First-Site-Name)"
    $navResult = Test-NavigationCommand -UserInput $siteName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($siteName)) {
        $siteName = "Default-First-Site-Name"
    }

    # Step 6: DSRM password
    $dsrmPassword = Read-DSRMPassword
    if ($null -eq $dsrmPassword) {
        Write-PressEnter
        return
    }

    # Step 7: Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  ADDITIONAL DC CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Domain:           $domainName".PadRight(72))│" -color "Info"
    $lineStr = "  Credentials:      $($credential.UserName)"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Site:             $siteName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Install DNS:      Yes".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Database Path:    C:\Windows\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Log Path:         C:\Windows\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  SYSVOL Path:      C:\Windows\SYSVOL".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 8: Confirm
    if (-not (Confirm-UserAction -Message "Promote this server as an additional Domain Controller?")) {
        Write-OutputColor "  Promotion cancelled." -color "Info"
        Write-PressEnter
        return
    }

    # Step 9: Execute
    try {
        Write-OutputColor "`n  Promoting server as additional DC... This will take several minutes." -color "Info"
        Write-OutputColor "  Do NOT close this window." -color "Warning"

        Import-Module ADDSDeployment -ErrorAction Stop

        Install-ADDSDomainController `
            -DomainName $domainName `
            -Credential $credential `
            -SiteName $siteName `
            -SafeModeAdministratorPassword $dsrmPassword `
            -InstallDns:$true `
            -NoRebootOnCompletion:$true `
            -Force:$true `
            -ErrorAction Stop

        Write-OutputColor "`n  Additional Domain Controller promotion completed successfully!" -color "Success"
        $global:RebootNeeded = $true
        Add-SessionChange -Category "AD DS" -Description "Promoted to additional DC in domain $domainName"
        Write-OutputColor "  A reboot is required to complete the promotion." -color "Warning"
    }
    catch {
        Write-OutputColor "  Failed to promote additional DC: $_" -color "Error"
        Add-SessionChange -Category "AD DS" -Description "Additional DC promotion failed: $domainName - $_"
    }

    Write-PressEnter
}

# Wizard to install a Read-Only Domain Controller
function Install-ReadOnlyDC {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("              READ-ONLY DOMAIN CONTROLLER (RODC)").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 1: Prerequisites
    $prereqs = Test-ADDSPrerequisites
    Show-ADDSPrerequisiteResults -Results $prereqs

    if (-not $prereqs.Passed) {
        if (-not (Confirm-UserAction -Message "Continue despite prerequisite failures?")) {
            Write-OutputColor "  Promotion cancelled." -color "Info"
            Write-PressEnter
            return
        }
    }

    # Step 2: Install AD DS role if needed
    if (-not (Install-ADDSRoleIfNeeded)) {
        Write-PressEnter
        return
    }

    # Step 3: Domain to join
    Write-OutputColor "" -color "Info"
    $domainName = Read-Host "  Enter domain to join (e.g., corp.contoso.com)"
    $navResult = Test-NavigationCommand -UserInput $domainName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        Write-OutputColor "  Domain name is required." -color "Error"
        Write-PressEnter
        return
    }

    if (-not (Test-ValidDomainName -DomainName $domainName)) {
        Write-OutputColor "  Invalid domain name format." -color "Error"
        Write-PressEnter
        return
    }

    # Step 4: Domain admin credentials
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  You will need domain admin credentials." -color "Info"
    $credential = Get-Credential -Message "Enter domain admin credentials for $domainName"
    if ($null -eq $credential) {
        Write-OutputColor "  Credential entry cancelled." -color "Warning"
        Write-PressEnter
        return
    }

    # Step 5: Site name
    Write-OutputColor "" -color "Info"
    $siteName = Read-Host "  Enter AD site name (default: Default-First-Site-Name)"
    $navResult = Test-NavigationCommand -UserInput $siteName
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($siteName)) {
        $siteName = "Default-First-Site-Name"
    }

    # Step 6: Delegated admin account
    Write-OutputColor "" -color "Info"
    $delegatedAdmin = Read-Host "  Enter delegated RODC admin account (e.g., DOMAIN\RODCAdmin)"
    $navResult = Test-NavigationCommand -UserInput $delegatedAdmin
    if ($navResult.ShouldReturn) { return }

    if ([string]::IsNullOrWhiteSpace($delegatedAdmin)) {
        Write-OutputColor "  No delegated admin specified. Local admin group will be used." -color "Warning"
    }

    # Step 7: DSRM password
    $dsrmPassword = Read-DSRMPassword
    if ($null -eq $dsrmPassword) {
        Write-PressEnter
        return
    }

    # Step 8: Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  READ-ONLY DC CONFIGURATION SUMMARY".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Domain:           $domainName".PadRight(72))│" -color "Info"
    $lineStr = "  Credentials:      $($credential.UserName)"
    if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Site:             $siteName".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Read-Only:        Yes".PadRight(72))│" -color "Info"
    if (-not [string]::IsNullOrWhiteSpace($delegatedAdmin)) {
        Write-OutputColor "  │$("  Delegated Admin:  $delegatedAdmin".PadRight(72))│" -color "Info"
    }
    Write-OutputColor "  │$("  Install DNS:      Yes".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Database Path:    C:\Windows\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Log Path:         C:\Windows\NTDS".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  SYSVOL Path:      C:\Windows\SYSVOL".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Step 9: Confirm
    if (-not (Confirm-UserAction -Message "Promote this server as a Read-Only Domain Controller?")) {
        Write-OutputColor "  Promotion cancelled." -color "Info"
        Write-PressEnter
        return
    }

    # Step 10: Execute
    try {
        Write-OutputColor "`n  Promoting server as RODC... This will take several minutes." -color "Info"
        Write-OutputColor "  Do NOT close this window." -color "Warning"

        Import-Module ADDSDeployment -ErrorAction Stop

        $rodcParams = @{
            DomainName                      = $domainName
            Credential                      = $credential
            SiteName                        = $siteName
            SafeModeAdministratorPassword    = $dsrmPassword
            ReadOnlyReplica                  = $true
            InstallDns                       = $true
            NoRebootOnCompletion             = $true
            Force                            = $true
            ErrorAction                      = "Stop"
        }

        if (-not [string]::IsNullOrWhiteSpace($delegatedAdmin)) {
            $rodcParams["DelegatedAdministratorAccountName"] = $delegatedAdmin
        }

        Install-ADDSDomainController @rodcParams

        Write-OutputColor "`n  Read-Only Domain Controller promotion completed successfully!" -color "Success"
        $global:RebootNeeded = $true
        Add-SessionChange -Category "AD DS" -Description "Promoted to RODC in domain $domainName"
        Write-OutputColor "  A reboot is required to complete the promotion." -color "Warning"
    }
    catch {
        Write-OutputColor "  Failed to promote RODC: $_" -color "Error"
        Add-SessionChange -Category "AD DS" -Description "RODC promotion failed: $domainName - $_"
    }

    Write-PressEnter
}

# Function to display current AD DS status
function Show-ADDSStatus {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        AD DS STATUS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # AD DS Role Status
    $addsInstalled = Test-ADDSInstalled
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  AD DS ROLE STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    if ($addsInstalled) {
        Write-OutputColor "  │$("  AD-Domain-Services:  Installed".PadRight(72))│" -color "Success"
    }
    else {
        Write-OutputColor "  │$("  AD-Domain-Services:  Not Installed".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-PressEnter
        return
    }

    # Check if this server is a Domain Controller
    $isDC = $false
    try {
        $compSys = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        $osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($osInfo.ProductType -eq 2 -or $compSys.DomainRole -ge 4) {
            $isDC = $true
        }
    }
    catch {
        # Ignore
    }

    if ($isDC) {
        Write-OutputColor "  │$("  Domain Controller:   Yes".PadRight(72))│" -color "Success"
    }
    else {
        Write-OutputColor "  │$("  Domain Controller:   No".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  This server has the AD DS role but is not promoted as a DC." -color "Info"
        Write-PressEnter
        return
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Forest and Domain information
    try {
        $forest = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest()
        $domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  FOREST / DOMAIN INFORMATION".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $lineStr = "  Forest Name:       $($forest.Name)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Forest Mode:       $($forest.ForestMode)".PadRight(72))│" -color "Info"
        $lineStr = "  Domain Name:       $($domain.Name)"
        if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("  Domain Mode:       $($domain.DomainMode)".PadRight(72))│" -color "Info"

        $dcList = $domain.DomainControllers | ForEach-Object { $_.Name }
        $dcCount = @($dcList).Count
        Write-OutputColor "  │$("  Domain Controllers: $dcCount".PadRight(72))│" -color "Info"
        foreach ($dc in $dcList) {
            $lineStr = "    - $dc"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }
    catch {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Could not retrieve forest/domain information.".PadRight(72))│" -color "Warning"
        $lineStr = "  Error: $($_.Exception.Message)"
        if ($lineStr.Length -gt 72) { $lineStr = $lineStr.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Error"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # FSMO Roles
    try {
        Import-Module ActiveDirectory -ErrorAction Stop

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  FSMO ROLES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $forestInfo = Get-ADForest -ErrorAction SilentlyContinue
        $domainInfo = Get-ADDomain -ErrorAction SilentlyContinue

        if ($null -ne $forestInfo) {
            $lineStr = "  Schema Master:       $($forestInfo.SchemaMaster)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
            $lineStr = "  Domain Naming:       $($forestInfo.DomainNamingMaster)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        }
        if ($null -ne $domainInfo) {
            $lineStr = "  PDC Emulator:        $($domainInfo.PDCEmulator)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
            $lineStr = "  RID Master:          $($domainInfo.RIDMaster)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
            $lineStr = "  Infrastructure:      $($domainInfo.InfrastructureMaster)"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }
    catch {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  FSMO role information unavailable (AD module not loaded).".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"
    }

    # Replication Status
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $replMetadata = Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -ErrorAction Stop

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  REPLICATION STATUS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        foreach ($partner in $replMetadata) {
            $partnerName = $partner.Partner -replace '^CN=NTDS Settings,CN=', '' -replace ',.*$', ''
            $lastRepl = if ($null -ne $partner.LastReplicationSuccess) {
                $partner.LastReplicationSuccess.ToString("yyyy-MM-dd HH:mm:ss")
            } else {
                "Never"
            }
            $lastResult = if ($partner.LastReplicationResult -eq 0) { "Success" } else { "Error ($($partner.LastReplicationResult))" }
            $resultColor = if ($partner.LastReplicationResult -eq 0) { "Success" } else { "Error" }

            $lineStr = "  Partner: $partnerName"
            if ($lineStr.Length -gt 69) { $lineStr = $lineStr.Substring(0, 69) + "..." }
            Write-OutputColor "  │$($lineStr.PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("    Last Success: $lastRepl  Result: $lastResult".PadRight(72))│" -color $resultColor
        }

        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    catch {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  Replication data unavailable.".PadRight(72))│" -color "Warning"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }

    Write-OutputColor "" -color "Info"
    Write-PressEnter
}
#endregion
