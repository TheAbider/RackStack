#region ===== LICENSING =====
# Function to check Windows version
function Get-WindowsVersionInfo {
    try {
        $ntVersion = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
        $buildNumber = $ntVersion.CurrentBuildNumber
        $displayVersion = $ntVersion.DisplayVersion  # Like "23H2", "24H2", "25H2"
        $edition = $ntVersion.EditionID
        $productName = $ntVersion.ProductName

        # Check if this is Server or Client
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 8 -ErrorAction Stop
        $isServer = $osInfo.ProductType -ne 1

        # Determine Windows version based on build number
        # Windows 11 starts at build 22000
        $build = [int]$buildNumber

        if ($isServer) {
            # Windows Server versions
            if ($build -gt 26100) {
                # Future Server OS — use registry ProductName as primary
                $regProduct = try { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).ProductName } catch { $null }
                $windowsVersion = if ($regProduct -and $regProduct -match 'Windows Server') { $regProduct } else { "Windows Server (Build $build)" }
            }
            elseif ($build -ge 26100) { $windowsVersion = "Windows Server 2025" }
            elseif ($build -ge 20348) { $windowsVersion = "Windows Server 2022" }
            elseif ($build -ge 17763) { $windowsVersion = "Windows Server 2019" }
            elseif ($build -ge 14393) { $windowsVersion = "Windows Server 2016" }
            elseif ($build -ge 9600) { $windowsVersion = "Windows Server 2012 R2" }
            elseif ($build -ge 9200) { $windowsVersion = "Windows Server 2012" }
            else { $windowsVersion = "Windows Server" }
        }
        else {
            # Windows Client versions (10/11)
            # Windows 11 = build 22000+
            if ($build -ge 22000) {
                $windowsVersion = "Windows 11"
            }
            else {
                $windowsVersion = "Windows 10"
            }

            # Append display version if available (like 24H2, 25H2)
            if ($displayVersion) {
                $windowsVersion = "$windowsVersion $displayVersion"
            }
        }

        # Fallback to product name if we couldn't determine
        if (-not $windowsVersion) {
            $windowsVersion = $productName
        }

        $editions = @{
            # Server editions
            "ServerDatacenter"     = "Datacenter"
            "ServerStandard"       = "Standard"
            "ServerAzure"          = "Azure"
            "ServerEssentials"     = "Essentials"
            "ServerStandardEval"   = "Standard Evaluation"
            "ServerDatacenterEval" = "Datacenter Evaluation"
            "ServerAzureEval"      = "Azure Evaluation"
            "ServerEssentialsEval" = "Essentials Evaluation"
            # Client editions
            "Professional"         = "Pro"
            "Enterprise"           = "Enterprise"
            "Education"            = "Education"
            "Core"                 = "Home"
            "ProfessionalWorkstation" = "Pro for Workstations"
            "ProfessionalEducation" = "Pro Education"
            "EnterpriseS"          = "Enterprise LTSC"
            "EnterpriseSN"         = "Enterprise N LTSC"
            "IoTEnterprise"        = "IoT Enterprise"
        }

        $windowsEdition = $editions[$edition]
        if (-not $windowsEdition) {
            $windowsEdition = $edition
        }

        return @{
            "WindowsVersion" = $windowsVersion
            "WindowsEdition" = $windowsEdition
            "IsServer" = $isServer
            "BuildNumber" = $buildNumber
            "DisplayVersion" = $displayVersion
        }
    }
    catch {
        return @{
            WindowsVersion = "Unknown"
            WindowsEdition = "Unknown"
            IsServer       = $false
            BuildNumber    = "Unknown"
            DisplayVersion = "Unknown"
        }
    }
}

# Function to check if server is activated
function Test-ServerActivated {
    try {
        $result = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>&1
        $resultText = $result -join "`n"

        if ($resultText -match "License Status: Licensed") {
            if ($resultText -match "TIMEBASED_EVAL|Evaluation") {
                return $false  # Evaluation mode
            }
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Function to validate license key format
function Test-ValidLicenseKey {
    param ([string]$licenseKey)
    return $licenseKey -match "^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$"
}

# Function to activate server with a key
function Enable-ServerActivation {
    param ([string]$productKey)

    try {
        # Pre-flight: check Software Protection service
        $sppsvc = Get-Service -Name sppsvc -ErrorAction SilentlyContinue
        if ($null -ne $sppsvc -and $sppsvc.Status -ne "Running") {
            Write-OutputColor "  Starting Software Protection service..." -color "Info"
            Start-Service sppsvc -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        Write-OutputColor "  Installing product key..." -color "Info"
        $ipkResult = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /ipk "$productKey" 2>&1
        $ipkText = $ipkResult -join ' '

        if ($ipkText -notmatch "(?i)success") {
            Write-OutputColor "  Product key installation failed." -color "Error"
            # Parse common error codes for user-friendly messages
            if ($ipkText -match "0xC004F050") {
                Write-OutputColor "  The key is not valid for this edition of Windows." -color "Error"
                Write-OutputColor "  Verify the key matches your OS edition (Standard/Datacenter/etc.)." -color "Warning"
            } elseif ($ipkText -match "0xC004F069") {
                Write-OutputColor "  The Software Licensing Service reports that the product SKU is not found." -color "Error"
                Write-OutputColor "  Verify the key type matches your Windows Server edition." -color "Warning"
            } elseif ($ipkText -match "0x80070005") {
                Write-OutputColor "  Access denied. Ensure you are running as Administrator." -color "Error"
                Write-OutputColor "  Tip: Right-click the script and select 'Run as Administrator'." -color "Warning"
            } elseif ($ipkText -match "0xC004E002") {
                Write-OutputColor "  Activation timeout — network or KMS server unreachable." -color "Error"
                Write-OutputColor "  Check network connectivity and KMS server availability." -color "Warning"
            } elseif ($ipkText -match "0xC004C003") {
                Write-OutputColor "  This product key has been blocked by Microsoft." -color "Error"
                Write-OutputColor "  Contact your volume license administrator for a replacement key." -color "Warning"
            } elseif ($ipkText -match "0xC004D307") {
                Write-OutputColor "  KMS host could not be reached." -color "Error"
                Write-OutputColor "  Verify KMS server is configured: slmgr /skms <server>:<port>" -color "Warning"
            } else {
                Write-OutputColor "  Detail: $ipkText" -color "Debug"
            }
            return
        }

        Write-OutputColor "  Key installed. Activating..." -color "Info"
        Start-Sleep -Seconds 5
        $activateResult = cscript.exe //NoLogo "$env:SystemRoot\System32\slmgr.vbs" /ato 2>&1
        $atoText = $activateResult -join ' '

        if ($atoText -match "(?i)success") {
            Write-OutputColor "  Server activated successfully!" -color "Success"
            Add-SessionChange -Category "System" -Description "Activated Windows license with product key"
            Clear-MenuCache
        }
        else {
            if ($atoText -match "0xC004F074") {
                Write-OutputColor "  KMS server not reachable. Check network/DNS or use a different activation method." -color "Warning"
            } elseif ($atoText -match "0xC004C003") {
                Write-OutputColor "  The activation server determined the key is blocked." -color "Error"
            } else {
                Write-OutputColor "  Activation result: $atoText" -color "Warning"
            }
        }
    }
    catch {
        Write-OutputColor "  Activation failed: $_" -color "Error"
    }
}

# Function to display detailed license status
function Show-LicenseStatus {
    Write-OutputColor "`n  Windows License Status:" -color "Info"

    try {
        $licenseInfo = Get-CimInstance -ClassName SoftwareLicensingProduct -OperationTimeoutSec 10 -ErrorAction Stop |
            Where-Object { $_.PartialProductKey -and $_.ApplicationId -eq '55c92734-d682-4d71-983e-d6ec3f16059f' } |
            Select-Object -First 1

        if ($null -eq $licenseInfo) {
            Write-OutputColor "  No Windows license information found" -color "Warning"
            return
        }

        $status = switch ($licenseInfo.LicenseStatus) {
            0 { "Unlicensed" }
            1 { "Licensed" }
            2 { "Out-of-Box Grace" }
            3 { "Out-of-Tolerance Grace" }
            4 { "Non-Genuine Grace" }
            5 { "Notification" }
            6 { "Extended Grace" }
            default { "Unknown ($($licenseInfo.LicenseStatus))" }
        }

        $statusColor = if ($licenseInfo.LicenseStatus -eq 1) { "Success" } else { "Warning" }

        Write-OutputColor "  Product: $($licenseInfo.Name)" -color "Info"
        Write-OutputColor "  Status: $status" -color $statusColor
        Write-OutputColor "  Partial Key: *****-$($licenseInfo.PartialProductKey)" -color "Info"

        if ($licenseInfo.LicenseStatus -eq 1) {
            # Check if KMS or AVMA
            if ($licenseInfo.KeyManagementServiceMachine) {
                Write-OutputColor "  Activation: KMS ($($licenseInfo.KeyManagementServiceMachine))" -color "Info"
            } elseif ($licenseInfo.Description -match 'AVMA') {
                Write-OutputColor "  Activation: AVMA (Automatic VM Activation)" -color "Info"
            } else {
                Write-OutputColor "  Activation: Retail/MAK" -color "Info"
            }
        }

        # Grace period remaining / expiry date
        if ($licenseInfo.GracePeriodRemaining -gt 0) {
            $daysLeft = [math]::Round($licenseInfo.GracePeriodRemaining / 1440, 0)
            $graceColor = if ($daysLeft -gt 30) { "Info" } elseif ($daysLeft -gt 7) { "Warning" } else { "Error" }
            Write-OutputColor "  Grace Period: $daysLeft days remaining" -color $graceColor
            $expiryDate = (Get-Date).AddMinutes($licenseInfo.GracePeriodRemaining).ToString('yyyy-MM-dd')
            Write-OutputColor "  Expires: $expiryDate" -color $graceColor
        }

        # KMS renewal info
        if ($licenseInfo.VLRenewalInterval -gt 0) {
            $renewalDays = [math]::Round($licenseInfo.VLRenewalInterval / 1440, 0)
            Write-OutputColor "  KMS Renewal: Every $renewalDays days" -color "Info"
        }
    } catch {
        Write-OutputColor "  License check failed: $($_.Exception.Message)" -color "Warning"
    }
}

# Function to license the server
function Register-ServerLicense {
    # --- Section: Initialization & Status Display ---
    Clear-Host
    Write-CenteredOutput "Server Licensing" -color "Info"

    # Check current status
    $windowsInfo = Get-WindowsVersionInfo
    Write-OutputColor "  Windows Version: $($windowsInfo.WindowsVersion)" -color "Info"
    Write-OutputColor "  Windows Edition: $($windowsInfo.WindowsEdition)" -color "Info"
    Write-OutputColor "  Build Number: $($windowsInfo.BuildNumber)" -color "Info"

    # Check if this is Windows Client
    if (-not $windowsInfo.IsServer) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  This is a Windows Client operating system." -color "Warning"
        Write-OutputColor "  Server licensing options (AVMA) are not available for client OS." -color "Warning"

        if (Test-ServerActivated) {
            Write-OutputColor "  Windows is already licensed and activated." -color "Success"
        }
        else {
            Write-OutputColor "  Windows is NOT activated." -color "Warning"
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  To activate Windows Client:" -color "Info"
            Write-OutputColor "  1. Go to Settings > System > Activation" -color "Info"
            Write-OutputColor "  2. Or use: slmgr.vbs /ipk <product-key>" -color "Info"
        }
        return
    }

    if (Test-ServerActivated) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Server is already licensed and activated with Microsoft." -color "Success"
        if (-not (Confirm-UserAction -Message "Re-license anyway?")) {
            return
        }
    }
    else {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Server is NOT licensed or in evaluation mode." -color "Warning"
    }

    # --- Section: Built-in License Key Definitions (KMS + AVMA) ---
    # Default volume license keys (KMS client setup keys)
    $keys = @{
        "Windows Server 2008" = @{
            "Datacenter" = "7M67G-PC374-GR742-YH8V4-TCBY3"
            "Standard" = "TM24T-X9RMF-VWXK6-X8JC9-BFGM2"
            "Datacenter Evaluation" = "7M67G-PC374-GR742-YH8V4-TCBY3"
            "Standard Evaluation" = "TM24T-X9RMF-VWXK6-X8JC9-BFGM2"
        }
        "Windows Server 2008 R2" = @{
            "Datacenter" = "74YFP-3QFB3-KQT8W-PMXWJ-7M648"
            "Standard" = "YC6KT-GKW9T-YTKYR-T4X34-R7VHC"
            "Datacenter Evaluation" = "74YFP-3QFB3-KQT8W-PMXWJ-7M648"
            "Standard Evaluation" = "YC6KT-GKW9T-YTKYR-T4X34-R7VHC"
        }
        "Windows Server 2012" = @{
            "Datacenter" = "48HP8-DN98B-MYWDG-T2DCC-8W83P"
            "Standard" = "XC9B7-NBPP2-83J2H-RHMBY-92BT4"
            "Datacenter Evaluation" = "48HP8-DN98B-MYWDG-T2DCC-8W83P"
            "Standard Evaluation" = "XC9B7-NBPP2-83J2H-RHMBY-92BT4"
        }
        "Windows Server 2012 R2" = @{
            "Datacenter" = "W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9"
            "Standard" = "D2N9P-3P6X9-2R39C-7RTCD-MDVJX"
            "Datacenter Evaluation" = "W3GGN-FT8W3-Y4M27-J84CP-Q3VJ9"
            "Standard Evaluation" = "D2N9P-3P6X9-2R39C-7RTCD-MDVJX"
        }
        "Windows Server 2016" = @{
            "Datacenter" = "CB7KF-BWN84-R7R2Y-793K2-8XDDG"
            "Standard" = "WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY"
            "Datacenter Evaluation" = "CB7KF-BWN84-R7R2Y-793K2-8XDDG"
            "Standard Evaluation" = "WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY"
        }
        "Windows Server 2019" = @{
            "Datacenter" = "WMDGN-G9PQG-XVVXX-R3X43-63DFG"
            "Standard" = "N69G4-B89J2-4G8F4-WWYCC-J464C"
            "Datacenter Evaluation" = "WMDGN-G9PQG-XVVXX-R3X43-63DFG"
            "Standard Evaluation" = "N69G4-B89J2-4G8F4-WWYCC-J464C"
        }
        "Windows Server 2022" = @{
            "Datacenter" = "WX4NM-KYWYW-QJJR4-XV3QB-6VM33"
            "Standard" = "VDYBN-27WPP-V4HQT-9VMD4-VMK7H"
            "Datacenter Evaluation" = "WX4NM-KYWYW-QJJR4-XV3QB-6VM33"
            "Standard Evaluation" = "VDYBN-27WPP-V4HQT-9VMD4-VMK7H"
        }
        "Windows Server 2025" = @{
            "Datacenter" = "D764K-2NDRG-47T6Q-P8T8W-YP6DF"
            "Standard" = "TVRH6-WHNXV-R9WG3-9XRFY-MY832"
            "Datacenter Evaluation" = "D764K-2NDRG-47T6Q-P8T8W-YP6DF"
            "Standard Evaluation" = "TVRH6-WHNXV-R9WG3-9XRFY-MY832"
        }
    }

    # AVMA keys for VMs running on Datacenter hosts
    $avmaKeys = @{
        "Windows Server 2012 R2" = @{
            "Datacenter" = "Y4TGP-NPTV9-HTC2H-7MGQ3-DV4TW"
            "Standard" = "DBGBW-NPF86-BJVTX-K3WKJ-MTB6V"
            "Datacenter Evaluation" = "Y4TGP-NPTV9-HTC2H-7MGQ3-DV4TW"
            "Standard Evaluation" = "DBGBW-NPF86-BJVTX-K3WKJ-MTB6V"
            "Essentials" = "K2XGM-NMBT3-2R6Q8-WF2FK-P36R2"
            "Essentials Evaluation" = "K2XGM-NMBT3-2R6Q8-WF2FK-P36R2"
        }
        "Windows Server 2016" = @{
            "Datacenter" = "TMJ3Y-NTRTM-FJYXT-T22BY-CWG3J"
            "Standard" = "C3RCX-M6NRP-6CXC9-TW2F2-4RHYD"
            "Datacenter Evaluation" = "TMJ3Y-NTRTM-FJYXT-T22BY-CWG3J"
            "Standard Evaluation" = "C3RCX-M6NRP-6CXC9-TW2F2-4RHYD"
            "Essentials" = "B4YNW-62DX9-W8V6M-82649-MHBKQ"
            "Essentials Evaluation" = "B4YNW-62DX9-W8V6M-82649-MHBKQ"
        }
        "Windows Server 2019" = @{
            "Datacenter" = "H3RNG-8C32Q-Q8FRX-6TDXV-WMBMW"
            "Standard" = "TNK62-RXVTB-4P47B-2D623-4GF74"
            "Datacenter Evaluation" = "H3RNG-8C32Q-Q8FRX-6TDXV-WMBMW"
            "Standard Evaluation" = "TNK62-RXVTB-4P47B-2D623-4GF74"
            "Essentials" = "2CTP7-NHT64-BP62M-FV6GG-HFV28"
            "Essentials Evaluation" = "2CTP7-NHT64-BP62M-FV6GG-HFV28"
        }
        "Windows Server 2022" = @{
            "Datacenter" = "W3GNR-8DDXR-2TFRP-H8P33-DV9BG"
            "Standard" = "YDFWN-MJ9JR-3DYRK-FXXRW-78VHK"
            "Datacenter Evaluation" = "W3GNR-8DDXR-2TFRP-H8P33-DV9BG"
            "Standard Evaluation" = "YDFWN-MJ9JR-3DYRK-FXXRW-78VHK"
            "Datacenter: Azure Edition" = "NTBV8-9K7Q8-V27C6-M2BTV-KHMXV"
            "Datacenter: Azure Edition Evaluation" = "NTBV8-9K7Q8-V27C6-M2BTV-KHMXV"
        }
        "Windows Server 2025" = @{
            "Datacenter" = "YQB4H-NKHHJ-Q6K4R-4VMY6-VCH67"
            "Standard" = "WWVGQ-PNHV9-B89P4-8GGM9-9HPQ4"
            "Datacenter Evaluation" = "YQB4H-NKHHJ-Q6K4R-4VMY6-VCH67"
            "Standard Evaluation" = "WWVGQ-PNHV9-B89P4-8GGM9-9HPQ4"
            "Datacenter: Azure Edition" = "6NMQ9-T38WF-6MFGM-QYGYM-88J4F"
            "Datacenter: Azure Edition Evaluation" = "6NMQ9-T38WF-6MFGM-QYGYM-88J4F"
        }
    }

    # Merge custom license keys (custom overrides built-in for same version/edition)
    foreach ($ver in $script:CustomKMSKeys.Keys) {
        if (-not $keys.ContainsKey($ver)) { $keys[$ver] = @{} }
        foreach ($ed in $script:CustomKMSKeys[$ver].Keys) {
            $keys[$ver][$ed] = $script:CustomKMSKeys[$ver][$ed]
        }
    }
    foreach ($ver in $script:CustomAVMAKeys.Keys) {
        if (-not $avmaKeys.ContainsKey($ver)) { $avmaKeys[$ver] = @{} }
        foreach ($ed in $script:CustomAVMAKeys[$ver].Keys) {
            $avmaKeys[$ver][$ed] = $script:CustomAVMAKeys[$ver][$ed]
        }
    }

    # --- Section: Helper Function - Manual Key Entry ---
    # Helper function for manual key entry with retry logic
    function Enter-ManualKey {
        $attempts = 0
        while ($attempts -lt $script:MaxRetryAttempts) {
            Write-OutputColor "  Enter product key (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX):" -color "Info"
            $productKey = Read-Host

            # Check for navigation commands
            $navResult = Test-NavigationCommand -UserInput $productKey
            if ($navResult.ShouldReturn) {
                return $null
            }

            if (-not [string]::IsNullOrWhiteSpace($productKey) -and (Test-ValidLicenseKey -licenseKey $productKey.ToUpper())) {
                return $productKey.ToUpper()
            }
            else {
                Write-OutputColor "  Invalid product key format. Enter a valid 25-character key." -color "Error"
                $attempts++
                if ($attempts -lt $script:MaxRetryAttempts) {
                    Write-OutputColor "  Attempts remaining: $($script:MaxRetryAttempts - $attempts)" -color "Warning"
                }
            }
        }
        Write-OutputColor "  Maximum attempts reached." -color "Error"
        return $null
    }

    # --- Section: Main Menu - Host vs VM Selection ---
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Are you licensing a Host or a Virtual Machine?" -color "Info"
    Write-OutputColor "1. Host (physical server or Hyper-V host)" -color "Info"
    Write-OutputColor "2. Virtual Machine" -color "Info"
    Write-OutputColor "3. Enter product key manually" -color "Info"
    Write-OutputColor "4. View License Status" -color "Info"
    Write-OutputColor "5. Cancel" -color "Info"

    $licensingType = Read-Host "  Select"

    # Check for navigation
    $navResult = Test-NavigationCommand -UserInput $licensingType
    if ($navResult.ShouldReturn) {
        if (Invoke-NavigationAction -NavResult $navResult) { return }
    }

    # --- Section: Licensing Path Dispatch ---
    switch ($licensingType) {
        "1" {
            # HOST licensing path
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Host Licensing Options:" -color "Info"
            Write-OutputColor "  [1] Use default KMS client key (requires KMS server)" -color "Info"
            Write-OutputColor "  [2] Enter volume license key manually" -color "Info"
            Write-OutputColor "  [B] ◄ Back" -color "Info"

            $hostChoice = Read-Host "  Select"

            $navResult = Test-NavigationCommand -UserInput $hostChoice
            if ($navResult.ShouldReturn) {
                if (Invoke-NavigationAction -NavResult $navResult) { return }
            }

            switch ($hostChoice) {
                "1" {
                    # Use default KMS key
                    if ($keys.ContainsKey($windowsInfo.WindowsVersion)) {
                        $versionKeys = $keys[$windowsInfo.WindowsVersion]
                        if ($versionKeys.ContainsKey($windowsInfo.WindowsEdition)) {
                            $productKey = $versionKeys[$windowsInfo.WindowsEdition]
                            Write-OutputColor "  Using KMS client key for $($windowsInfo.WindowsVersion) $($windowsInfo.WindowsEdition)..." -color "Info"
                            Enable-ServerActivation -productKey $productKey
                        }
                        else {
                            Write-OutputColor "  No default key available for $($windowsInfo.WindowsEdition)" -color "Error"
                            Write-OutputColor "  Available editions: $($versionKeys.Keys -join ', ')" -color "Info"
                            $productKey = Enter-ManualKey
                            if ($null -ne $productKey) {
                                Enable-ServerActivation -productKey $productKey
                            }
                        }
                    }
                    else {
                        Write-OutputColor "  No default keys available for $($windowsInfo.WindowsVersion)" -color "Error"
                        $productKey = Enter-ManualKey
                        if ($null -ne $productKey) {
                            Enable-ServerActivation -productKey $productKey
                        }
                    }
                }
                "2" {
                    # Manual key entry
                    $productKey = Enter-ManualKey
                    if ($null -ne $productKey) {
                        Enable-ServerActivation -productKey $productKey
                    }
                }
                default {
                    Write-OutputColor "  Returning to main menu." -color "Info"
                    return
                }
            }
        }
        "2" {
            # VIRTUAL MACHINE licensing path
            # Try AVMA first (auto-activates if host is Datacenter, harmless if not)
            $avmaKey = $null
            if ($avmaKeys.ContainsKey($windowsInfo.WindowsVersion)) {
                $versionKeys = $avmaKeys[$windowsInfo.WindowsVersion]
                if ($versionKeys.ContainsKey($windowsInfo.WindowsEdition)) {
                    $avmaKey = $versionKeys[$windowsInfo.WindowsEdition]
                }
            }

            if ($avmaKey) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  AVMA key found for $($windowsInfo.WindowsVersion) $($windowsInfo.WindowsEdition)" -color "Success"
                Write-OutputColor "  AVMA auto-activates VMs running on Datacenter hosts." -color "Info"
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  [1] Apply AVMA key (recommended for Datacenter hosts)" -color "Info"
                Write-OutputColor "  [2] Use KMS client key instead (requires KMS server)" -color "Info"
                Write-OutputColor "  [3] Enter product key manually" -color "Info"
                Write-OutputColor "  [B] ◄ Back" -color "Info"

                $vmChoice = Read-Host "  Select"

                $navResult = Test-NavigationCommand -UserInput $vmChoice
                if ($navResult.ShouldReturn) {
                    if (Invoke-NavigationAction -NavResult $navResult) { return }
                }

                switch ($vmChoice) {
                    "1" {
                        Enable-ServerActivation -productKey $avmaKey
                    }
                    "2" {
                        if ($keys.ContainsKey($windowsInfo.WindowsVersion)) {
                            $versionKeys = $keys[$windowsInfo.WindowsVersion]
                            if ($versionKeys.ContainsKey($windowsInfo.WindowsEdition)) {
                                $productKey = $versionKeys[$windowsInfo.WindowsEdition]
                                Write-OutputColor "  Using KMS client key for $($windowsInfo.WindowsVersion) $($windowsInfo.WindowsEdition)..." -color "Info"
                                Enable-ServerActivation -productKey $productKey
                            } else {
                                Write-OutputColor "  No KMS key for $($windowsInfo.WindowsEdition). Enter manually." -color "Warning"
                                $productKey = Enter-ManualKey
                                if ($null -ne $productKey) { Enable-ServerActivation -productKey $productKey }
                            }
                        } else {
                            Write-OutputColor "  No KMS keys for $($windowsInfo.WindowsVersion). Enter manually." -color "Warning"
                            $productKey = Enter-ManualKey
                            if ($null -ne $productKey) { Enable-ServerActivation -productKey $productKey }
                        }
                    }
                    "3" {
                        $productKey = Enter-ManualKey
                        if ($null -ne $productKey) { Enable-ServerActivation -productKey $productKey }
                    }
                    default {
                        Write-OutputColor "  Returning to main menu." -color "Info"
                        return
                    }
                }
            }
            else {
                # No AVMA key available — offer KMS/manual
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  No AVMA key available for $($windowsInfo.WindowsVersion) $($windowsInfo.WindowsEdition)." -color "Warning"
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  VM Licensing Options:" -color "Info"
                Write-OutputColor "  [1] Use default KMS client key (requires KMS server)" -color "Info"
                Write-OutputColor "  [2] Enter product key manually" -color "Info"
                Write-OutputColor "  [B] ◄ Back" -color "Info"

                $vmChoice = Read-Host "  Select"

                $navResult = Test-NavigationCommand -UserInput $vmChoice
                if ($navResult.ShouldReturn) {
                    if (Invoke-NavigationAction -NavResult $navResult) { return }
                }

                switch ($vmChoice) {
                    "1" {
                        if ($keys.ContainsKey($windowsInfo.WindowsVersion)) {
                            $versionKeys = $keys[$windowsInfo.WindowsVersion]
                            if ($versionKeys.ContainsKey($windowsInfo.WindowsEdition)) {
                                $productKey = $versionKeys[$windowsInfo.WindowsEdition]
                                Write-OutputColor "  Using KMS client key for $($windowsInfo.WindowsVersion) $($windowsInfo.WindowsEdition)..." -color "Info"
                                Enable-ServerActivation -productKey $productKey
                            }
                            else {
                                Write-OutputColor "  No default key for $($windowsInfo.WindowsEdition)" -color "Error"
                                $productKey = Enter-ManualKey
                                if ($null -ne $productKey) { Enable-ServerActivation -productKey $productKey }
                            }
                        }
                        else {
                            Write-OutputColor "  No default keys for $($windowsInfo.WindowsVersion)" -color "Error"
                            $productKey = Enter-ManualKey
                            if ($null -ne $productKey) { Enable-ServerActivation -productKey $productKey }
                        }
                    }
                    "2" {
                        $productKey = Enter-ManualKey
                        if ($null -ne $productKey) { Enable-ServerActivation -productKey $productKey }
                    }
                    default {
                        Write-OutputColor "  Returning to main menu." -color "Info"
                        return
                    }
                }
            }
        }
        "3" {
            # Direct manual key entry
            $productKey = Enter-ManualKey
            if ($null -ne $productKey) {
                Enable-ServerActivation -productKey $productKey
            }
        }
        "4" {
            # View detailed license status
            Show-LicenseStatus
        }
        default {
            Write-OutputColor "  Licensing cancelled." -color "Info"
        }
    }
    Write-PressEnter
}

#endregion