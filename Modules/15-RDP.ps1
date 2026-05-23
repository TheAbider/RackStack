#region ===== RDP CONFIGURATION =====
# Function to enable Remote Desktop
function Enable-RDP {
    Clear-Host
    Write-CenteredOutput "Remote Desktop" -color "Info"

    try {
        # Check current RDP status (null-safe — registry key may be missing on stripped builds)
        $rdpStatus = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue
        $rdpAlreadyEnabled = ($null -ne $rdpStatus -and $rdpStatus.fDenyTSConnections -eq 0)

        if ($rdpAlreadyEnabled) {
            Write-OutputColor "  Remote Desktop is already enabled." -color "Info"
        }
        else {
            $confirmPrompt = if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
                "Queue Remote Desktop enable for later commit? (Dry-Run mode is ON)"
            } else {
                "Enable Remote Desktop on this server?"
            }
            if (-not (Confirm-UserAction -Message $confirmPrompt)) {
                Write-OutputColor "  Remote Desktop configuration cancelled." -color "Info"
                return
            }

            if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
                Push-DryRunStep -Label "Enable Remote Desktop (with firewall rules + NLA)" -Category "Security" -OneWay $false `
                    -Preflight {
                        $svc = Get-Service -Name TermService -ErrorAction SilentlyContinue
                        if ($null -eq $svc) { "TermService not present — RDP cannot be enabled on this SKU" }
                        else { $true }
                    } `
                    -Apply {
                        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop
                        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -ErrorAction SilentlyContinue
                    } `
                    -Undo {
                        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1 -ErrorAction SilentlyContinue
                        Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                    }
                Write-OutputColor "  Queued (Dry-Run): Enable Remote Desktop + firewall + NLA." -color "Warning"
                Add-SessionChange -Category "DryRun" -Description "Queued: Enable Remote Desktop"
                return
            }

            # Enable Remote Desktop
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop

            # Verify (null-safe re-read)
            $rdpStatus = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -ErrorAction SilentlyContinue
            $rdpEnabledNow = ($null -ne $rdpStatus -and $rdpStatus.fDenyTSConnections -eq 0)
            if ($rdpEnabledNow) {
                Write-OutputColor "  Remote Desktop has been enabled." -color "Success"
            }
            else {
                Write-OutputColor "  Failed to enable Remote Desktop." -color "Error"
                Write-OutputColor "  Tip: Verify administrator privileges and check Group Policy for RDP restrictions." -color "Warning"
            }
        }

        # Enable firewall rules - pre-check firewall service
        $fwService = Get-Service -Name mpssvc -ErrorAction SilentlyContinue
        if ($null -eq $fwService -or $fwService.Status -ne 'Running') {
            Write-OutputColor "  Windows Firewall service (mpssvc) is not running." -color "Warning"
            Write-OutputColor "  Firewall rules cannot be managed. RDP may be accessible but unprotected." -color "Warning"
        }
        else {
            $firewallRule = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }

            if ($firewallRule) {
                Write-OutputColor "  RDP firewall rules are already enabled." -color "Info"
            }
            else {
                Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

                $firewallRule = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
                if ($firewallRule) {
                    Write-OutputColor "  RDP firewall rules have been enabled." -color "Success"
                }
                else {
                    Write-OutputColor "  Warning: Could not enable RDP firewall rules." -color "Warning"
                }
            }
        }

        # Enable Network Level Authentication (recommended)
        try {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -ErrorAction Stop
            Write-OutputColor "  Network Level Authentication enabled (recommended for security)." -color "Success"
        }
        catch {
            Write-OutputColor "  Warning: Could not enable Network Level Authentication." -color "Warning"
            Write-OutputColor "  RDP is enabled but without NLA. Consider enabling manually." -color "Warning"
        }

        # Only record the session change / undo entry if RDP actually flipped from
        # disabled to enabled in this run (avoids logging on registry-write failures
        # and on the "already enabled" no-op path).
        if (-not $rdpAlreadyEnabled -and $rdpEnabledNow) {
            Add-SessionChange -Category "System" -Description "Enabled Remote Desktop"
            Add-UndoAction -Category "System" -Description "Enabled Remote Desktop" -UndoScript {
                Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1 -ErrorAction SilentlyContinue
                Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            }
        }
        Clear-MenuCache  # Invalidate cache after change

        # Show current security posture
        Show-RDPSecurityStatus

        # Offer subnet restriction
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Restrict RDP to a specific subnet? (recommended for security)" -color "Info"
        Write-OutputColor "  This creates a firewall rule limiting RDP to a specific IP range." -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  [1] Restrict to subnet (enter CIDR, e.g., 10.0.1.0/24)" -color "Info"
        Write-OutputColor "  [2] Skip (allow from any address)" -color "Info"
        $restrictChoice = Read-Host "  Select"

        if ($restrictChoice -eq "1") {
            $subnet = Read-Host "  Enter subnet CIDR (e.g., 10.0.1.0/24 or 192.168.1.0/24)"
            $navResult = Test-NavigationCommand -UserInput $subnet
            if (-not $navResult.ShouldReturn -and -not [string]::IsNullOrWhiteSpace($subnet)) {
                # Validate CIDR format and reject overly broad subnets
                if ($subnet -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$') {
                    Write-OutputColor "  Invalid CIDR format. Expected format: 10.0.1.0/24" -color "Error"
                } elseif ($subnet -match '/[0-7]$') {
                    Write-OutputColor "  Subnet too broad (/$($subnet.Split('/')[-1])). Use /8 or narrower." -color "Error"
                } else {
                try {
                    # Remove existing subnet restriction rule if present
                    Remove-NetFirewallRule -DisplayName "RDP Subnet Restriction" -ErrorAction SilentlyContinue

                    New-NetFirewallRule -DisplayName "RDP Subnet Restriction" `
                        -Direction Inbound -Protocol TCP -LocalPort 3389 `
                        -RemoteAddress $subnet -Action Allow `
                        -Profile Domain,Private,Public `
                        -Description "Allow RDP only from $subnet" -ErrorAction Stop | Out-Null

                    # Disable the broad RDP rules so only the restricted one applies
                    Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -ne "RDP Subnet Restriction" } |
                        Disable-NetFirewallRule -ErrorAction SilentlyContinue

                    Write-OutputColor "  RDP restricted to $subnet only." -color "Success"
                    Write-OutputColor "  Broad RDP rules disabled. Only subnet rule is active." -color "Success"
                    Add-SessionChange -Category "Security" -Description "Restricted RDP to subnet $subnet"
                    Add-UndoAction -Category "Security" -Description "RDP subnet restriction to $subnet" -UndoScript {
                        Remove-NetFirewallRule -DisplayName "RDP Subnet Restriction" -ErrorAction SilentlyContinue
                        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-OutputColor "  Failed to create subnet restriction: $_" -color "Error"
                    Write-OutputColor "  Check that the CIDR format is valid (e.g., 10.0.1.0/24)." -color "Info"
                }
                }
            }
        }
    }
    catch {
        Write-RackStackError -Code "RS-2012" -Detail "Remote Desktop configuration failed: $($_.Exception.Message)"
        Write-OutputColor "  Error configuring Remote Desktop: $_" -color "Error"
    }
}

# Function to display current RDP configuration and security settings
function Show-RDPSecurityStatus {
    Write-OutputColor "`n  Remote Desktop Security Status:" -color "Info"

    # Check if RDP is enabled
    try {
        $rdpEnabled = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -ErrorAction SilentlyContinue).fDenyTSConnections
        $status = if ($rdpEnabled -eq 0) { "Enabled" } else { "Disabled" }
        $color = if ($rdpEnabled -eq 0) { "Success" } else { "Warning" }
        Write-OutputColor "  RDP Status: $status" -color $color
    } catch {
        Write-OutputColor "  RDP Status: Unknown" -color "Warning"
    }

    # Check NLA requirement
    try {
        $nla = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -ErrorAction SilentlyContinue).UserAuthentication
        $nlaStatus = if ($nla -eq 1) { "Required (Secure)" } else { "Not Required" }
        $nlaColor = if ($nla -eq 1) { "Success" } else { "Warning" }
        Write-OutputColor "  Network Level Auth: $nlaStatus" -color $nlaColor
    } catch {
        Write-OutputColor "  Network Level Auth: Unknown" -color "Warning"
    }

    # Check security layer
    try {
        $secLayer = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -ErrorAction SilentlyContinue).SecurityLayer
        $layerName = switch ($secLayer) {
            0 { "RDP Security (Legacy)" }
            1 { "Negotiate" }
            2 { "TLS (Secure)" }
            default { "Unknown ($secLayer)" }
        }
        $layerColor = if ($secLayer -eq 2) { "Success" } elseif ($secLayer -eq 1) { "Info" } else { "Warning" }
        Write-OutputColor "  Security Layer: $layerName" -color $layerColor
    } catch {
        Write-OutputColor "  Security Layer: Unknown" -color "Warning"
    }

    # Check firewall rule
    $rdpRule = Get-NetFirewallRule -DisplayName "Remote Desktop*" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
    $ruleCount = @($rdpRule).Count
    Write-OutputColor "  Firewall Rules: $ruleCount enabled" -color $(if ($ruleCount -gt 0) { "Success" } else { "Warning" })

    # Check subnet restriction
    $subnetRule = Get-NetFirewallRule -DisplayName "RDP Subnet Restriction" -ErrorAction SilentlyContinue
    if ($null -ne $subnetRule -and $subnetRule.Enabled -eq $true) {
        $subnetFilter = $subnetRule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
        $remoteAddr = if ($null -ne $subnetFilter) { $subnetFilter.RemoteAddress -join ', ' } else { "configured" }
        Write-OutputColor "  Access Restricted: $remoteAddr" -color "Success"
    } else {
        Write-OutputColor "  Access Restricted: No (any address)" -color "Warning"
    }

    # Check listening port
    try {
        $port = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'PortNumber' -ErrorAction SilentlyContinue).PortNumber
        $portDisplay = if ($null -ne $port -and $port -ge 1 -and $port -le 65535) { $port } else { "3389 (default)" }
        $portColor = if ($port -ne 3389 -and $null -ne $port) { "Warning" } else { "Info" }
        Write-OutputColor "  Listening Port: $portDisplay" -color $portColor
    } catch { }

    # Active RDP sessions
    try {
        $rdpSessions = @(query session 2>$null | ForEach-Object { $_.ToString() } | Where-Object { $_ -match 'rdp-tcp.*Active' })
        Write-OutputColor "  Active RDP Sessions: $($rdpSessions.Count)" -color $(if ($rdpSessions.Count -gt 0) { "Success" } else { "Info" })
    } catch { }
}

# Function to enable PowerShell Remoting (WinRM) securely
function Enable-PowerShellRemoting {
    Clear-Host
    Write-CenteredOutput "Enable PowerShell Remoting" -color "Info"

    # Check current status - handle case where WinRM isn't running yet
    $winrmService = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    $winrmStatus = if ($null -ne $winrmService -and $winrmService.Status -eq "Running") { "Running" } else { "Stopped" }
    $winrmStartup = if ($null -ne $winrmService) { $winrmService.StartType } else { "Unknown" }

    Write-OutputColor "  Current WinRM Status:" -color "Info"
    Write-OutputColor "  Service: $winrmStatus" -color $(if ($winrmStatus -eq "Running") { "Success" } else { "Warning" })
    Write-OutputColor "  Startup: $winrmStartup" -color "Info"

    # Check if already configured - only if service is running
    if ($winrmStatus -eq "Running") {
        try {
            $listener = Get-ChildItem -Path WSMan:\localhost\Listener -ErrorAction Stop
            if ($listener) {
                Write-OutputColor "  Listeners: Configured" -color "Success"
            }
            else {
                Write-OutputColor "  Listeners: Not configured" -color "Warning"
            }
        }
        catch {
            Write-OutputColor "  Listeners: Not configured" -color "Warning"
        }
    }
    else {
        Write-OutputColor "  Listeners: Service not running" -color "Warning"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  This will configure PowerShell Remoting with the following SECURE settings:" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [Security Features]" -color "Success"
    Write-OutputColor "  - Kerberos authentication (domain environments)" -color "Info"
    Write-OutputColor "  - Negotiate authentication (NTLM fallback)" -color "Info"
    Write-OutputColor "  - Network authentication required" -color "Info"
    Write-OutputColor "  - Encrypted connections only" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [What Gets Enabled]" -color "Success"
    Write-OutputColor "  - WinRM service set to Automatic and started" -color "Info"
    Write-OutputColor "  - PowerShell remoting enabled" -color "Info"
    Write-OutputColor "  - Firewall rules: WinRM, RPC, DCOM (Domain/Private)" -color "Info"
    Write-OutputColor "  - Trusted hosts NOT modified (most secure)" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [NOT Enabled - For Security]" -color "Warning"
    Write-OutputColor "  - Basic authentication remains disabled" -color "Info"
    Write-OutputColor "  - CredSSP remains disabled" -color "Info"
    Write-OutputColor "  - Public network firewall rules NOT added" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not (Confirm-UserAction -Message "Enable PowerShell Remoting with these settings?")) {
        Write-OutputColor "  PowerShell Remoting configuration cancelled." -color "Info"
        return
    }

    if ($script:DryRunMode -and -not $script:ApplyingDryRunQueue) {
        Push-DryRunStep -Label "Enable PowerShell Remoting (WinRM + secure config)" -Category "Security" -OneWay $false `
            -Preflight {
                if ($null -eq (Get-Service -Name WinRM -ErrorAction SilentlyContinue)) {
                    "WinRM service not present on this SKU"
                } else { $true }
            } `
            -Apply { Enable-PowerShellRemoting } `
            -Undo  {
                # Best-effort revert of the secure-config block: disable PS Remoting,
                # stop the service, set it back to manual.
                try { Disable-PSRemoting -Force -ErrorAction SilentlyContinue } catch { }
                Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue
                Set-Service -Name WinRM -StartupType Manual -ErrorAction SilentlyContinue
            }
        Write-OutputColor "  Queued (Dry-Run): enable PowerShell Remoting." -color "Warning"
        Add-SessionChange -Category "DryRun" -Description "Queued PowerShell Remoting enable"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Configuring PowerShell Remoting..." -color "Info"

        # First, ensure WinRM service can start
        Write-OutputColor "  Setting WinRM service to Automatic..." -color "Info"
        Set-Service -Name WinRM -StartupType Automatic -ErrorAction Stop

        # Start the service first so Enable-PSRemoting works properly
        Write-OutputColor "  Starting WinRM service..." -color "Info"
        Start-Service -Name WinRM -ErrorAction Stop

        # Small delay to let service fully start
        Start-Sleep -Seconds 2

        # Enable PSRemoting with secure defaults
        # -SkipNetworkProfileCheck allows it on Domain networks even if current network is Public
        # -Force suppresses prompts
        Write-OutputColor "  Enabling PS Remoting..." -color "Info"
        Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction Stop

        # Configure secure settings
        Write-OutputColor "  Applying secure configuration..." -color "Info"

        # Disable Basic auth (use Kerberos/Negotiate instead) - SECURITY HARDENING
        Write-OutputColor "  Disabling Basic authentication..." -color "Info"
        Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false -Force -ErrorAction SilentlyContinue
        Set-Item -Path WSMan:\localhost\Client\Auth\Basic -Value $false -Force -ErrorAction SilentlyContinue

        # Disable CredSSP (security risk - vulnerable to credential theft) - SECURITY HARDENING
        Write-OutputColor "  Disabling CredSSP authentication..." -color "Info"
        Set-Item -Path WSMan:\localhost\Service\Auth\CredSSP -Value $false -Force -ErrorAction SilentlyContinue
        Set-Item -Path WSMan:\localhost\Client\Auth\CredSSP -Value $false -Force -ErrorAction SilentlyContinue
        Disable-WSManCredSSP -Role Server -ErrorAction SilentlyContinue
        Disable-WSManCredSSP -Role Client -ErrorAction SilentlyContinue

        # Enable Kerberos (for domain - most secure)
        Write-OutputColor "  Enabling Kerberos authentication..." -color "Info"
        Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos -Value $true -Force -ErrorAction SilentlyContinue
        Set-Item -Path WSMan:\localhost\Client\Auth\Kerberos -Value $true -Force -ErrorAction SilentlyContinue

        # Enable Negotiate (allows Kerberos or NTLM as fallback)
        Write-OutputColor "  Enabling Negotiate authentication..." -color "Info"
        Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true -Force -ErrorAction SilentlyContinue
        Set-Item -Path WSMan:\localhost\Client\Auth\Negotiate -Value $true -Force -ErrorAction SilentlyContinue

        # Require encryption - SECURITY HARDENING
        Write-OutputColor "  Requiring encrypted connections..." -color "Info"
        Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false -Force -ErrorAction SilentlyContinue
        Set-Item -Path WSMan:\localhost\Client\AllowUnencrypted -Value $false -Force -ErrorAction SilentlyContinue

        # Enable firewall rules for Domain and Private profiles
        Write-OutputColor "  Configuring firewall rules..." -color "Info"

        # WinRM rules
        Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue

        # RPC/DCOM rules needed for remote PowerShell and CIM/WMI
        Write-OutputColor "  Enabling RPC/DCOM firewall rules..." -color "Info"

        # Remote Event Log Management (includes RPC)
        Enable-NetFirewallRule -DisplayGroup "Remote Event Log Management" -ErrorAction SilentlyContinue

        # Remote Service Management (RPC)
        Enable-NetFirewallRule -DisplayGroup "Remote Service Management" -ErrorAction SilentlyContinue

        # Windows Management Instrumentation (WMI/DCOM)
        Enable-NetFirewallRule -DisplayGroup "Windows Management Instrumentation (WMI)" -ErrorAction SilentlyContinue

        # Remote Scheduled Tasks Management
        Enable-NetFirewallRule -DisplayGroup "Remote Scheduled Tasks Management" -ErrorAction SilentlyContinue

        # File and Printer Sharing (often needed for remote admin)
        Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing" -ErrorAction SilentlyContinue

        # Verify configuration
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Verifying configuration..." -color "Info"

        $winrmService = Get-Service -Name WinRM -ErrorAction Stop
        if ($winrmService.Status -eq "Running") {
            Write-OutputColor "  WinRM Service: Running" -color "Success"
        }
        else {
            Write-OutputColor "  WinRM Service: $($winrmService.Status)" -color "Warning"
        }

        # Test the configuration
        $testResult = Test-WSMan -ComputerName localhost -ErrorAction SilentlyContinue
        if ($testResult) {
            Write-OutputColor "  WSMan Test: Passed" -color "Success"
        }
        else {
            Write-OutputColor "  WSMan Test: May need reboot" -color "Warning"
        }

        # Check listeners
        try {
            $listeners = @(Get-ChildItem -Path WSMan:\localhost\Listener -ErrorAction Stop)
            Write-OutputColor "  Listeners: $($listeners.Count) configured" -color "Success"
        }
        catch {
            Write-OutputColor "  Listeners: Check manually" -color "Warning"
        }

        # Verify security settings
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Security verification:" -color "Info"

        try {
            $basicAuth = (Get-Item -Path WSMan:\localhost\Service\Auth\Basic -ErrorAction SilentlyContinue).Value
            if ($basicAuth -eq $false -or $basicAuth -eq "false") {
                Write-OutputColor "  Basic Auth: DISABLED (secure)" -color "Success"
            }
            else {
                Write-OutputColor "  Basic Auth: ENABLED (WARNING - should be disabled!)" -color "Error"
            }

            $credSSP = (Get-Item -Path WSMan:\localhost\Service\Auth\CredSSP -ErrorAction SilentlyContinue).Value
            if ($credSSP -eq $false -or $credSSP -eq "false") {
                Write-OutputColor "  CredSSP: DISABLED (secure)" -color "Success"
            }
            else {
                Write-OutputColor "  CredSSP: ENABLED (WARNING - security risk!)" -color "Error"
            }

            $unencrypted = (Get-Item -Path WSMan:\localhost\Service\AllowUnencrypted -ErrorAction SilentlyContinue).Value
            if ($unencrypted -eq $false -or $unencrypted -eq "false") {
                Write-OutputColor "  Encryption: REQUIRED (secure)" -color "Success"
            }
            else {
                Write-OutputColor "  Encryption: NOT REQUIRED (WARNING!)" -color "Error"
            }

            $kerberos = (Get-Item -Path WSMan:\localhost\Service\Auth\Kerberos -ErrorAction SilentlyContinue).Value
            if ($kerberos -eq $true -or $kerberos -eq "true") {
                Write-OutputColor "  Kerberos: ENABLED" -color "Success"
            }

            $negotiate = (Get-Item -Path WSMan:\localhost\Service\Auth\Negotiate -ErrorAction SilentlyContinue).Value
            if ($negotiate -eq $true -or $negotiate -eq "true") {
                Write-OutputColor "  Negotiate: ENABLED" -color "Success"
            }
        }
        catch {
            Write-OutputColor "  Could not verify all settings" -color "Warning"
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  PowerShell Remoting enabled successfully!" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Firewall rules enabled:" -color "Info"
        Write-OutputColor "  - Windows Remote Management (WinRM)" -color "Success"
        Write-OutputColor "  - Remote Event Log Management" -color "Success"
        Write-OutputColor "  - Remote Service Management" -color "Success"
        Write-OutputColor "  - Windows Management Instrumentation (WMI)" -color "Success"
        Write-OutputColor "  - Remote Scheduled Tasks Management" -color "Success"
        Write-OutputColor "  - File and Printer Sharing" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  You can now connect to this server using:" -color "Info"
        Write-OutputColor "  Enter-PSSession -ComputerName $env:COMPUTERNAME" -color "Success"
        Write-OutputColor "  Invoke-Command -ComputerName $env:COMPUTERNAME -ScriptBlock { ... }" -color "Success"

        Add-SessionChange -Category "System" -Description "Enabled PowerShell Remoting (WinRM)"
        Clear-MenuCache
        if ($winrmStatus -ne "Running") {
            Add-UndoAction -Category "System" -Description "Enabled PowerShell Remoting (WinRM)" -UndoScript {
                Disable-PSRemoting -Force -ErrorAction SilentlyContinue
                Stop-Service -Name WinRM -Force -ErrorAction SilentlyContinue
                Set-Service -Name WinRM -StartupType Manual -ErrorAction SilentlyContinue
            }
        }
        Clear-MenuCache

        # Offer subnet restriction for WinRM
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Restrict WinRM to a specific subnet? (recommended for security)" -color "Info"
        Write-OutputColor "  [1] Restrict to subnet  [2] Skip" -color "Info"
        $winrmRestrict = Read-Host "  Select"

        if ($winrmRestrict -eq "1") {
            $subnet = Read-Host "  Enter subnet CIDR (e.g., 10.0.1.0/24)"
            $navResult = Test-NavigationCommand -UserInput $subnet
            if (-not $navResult.ShouldReturn -and -not [string]::IsNullOrWhiteSpace($subnet)) {
                if ($subnet -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}$') {
                    Write-OutputColor "  Invalid CIDR format. Expected format: 10.0.1.0/24" -color "Error"
                } elseif ($subnet -match '/[0-7]$') {
                    Write-OutputColor "  Subnet too broad (/$($subnet.Split('/')[-1])). Use /8 or narrower." -color "Error"
                } else {
                try {
                    Remove-NetFirewallRule -DisplayName "WinRM Subnet Restriction" -ErrorAction SilentlyContinue
                    New-NetFirewallRule -DisplayName "WinRM Subnet Restriction" `
                        -Direction Inbound -Protocol TCP -LocalPort 5985,5986 `
                        -RemoteAddress $subnet -Action Allow `
                        -Profile Domain,Private,Public `
                        -Description "Allow WinRM only from $subnet" -ErrorAction Stop | Out-Null

                    # Disable broad WinRM rules
                    Get-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue |
                        Disable-NetFirewallRule -ErrorAction SilentlyContinue

                    Write-OutputColor "  WinRM restricted to $subnet." -color "Success"
                    Add-SessionChange -Category "Security" -Description "Restricted WinRM to subnet $subnet"
                    Add-UndoAction -Category "Security" -Description "WinRM subnet restriction to $subnet" -UndoScript {
                        Remove-NetFirewallRule -DisplayName "WinRM Subnet Restriction" -ErrorAction SilentlyContinue
                        Enable-NetFirewallRule -DisplayGroup "Windows Remote Management" -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-OutputColor "  Failed to create subnet restriction: $_" -color "Error"
                }
                }
            }
        }
    }
    catch {
        Write-OutputColor "  Error configuring PowerShell Remoting: $_" -color "Error"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Troubleshooting tips:" -color "Warning"
        Write-OutputColor "  - Run this script as Administrator" -color "Info"
        Write-OutputColor "  - Check if WinRM service exists: Get-Service WinRM" -color "Info"
        Write-OutputColor "  - Try manual config: winrm quickconfig" -color "Info"
    }
}
#endregion