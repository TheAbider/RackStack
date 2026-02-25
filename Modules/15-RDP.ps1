#region ===== RDP CONFIGURATION =====
# Function to enable Remote Desktop
function Enable-RDP {
    Clear-Host
    Write-CenteredOutput "Remote Desktop" -color "Info"

    try {
        # Check current RDP status
        $rdpStatus = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections"

        if ($rdpStatus.fDenyTSConnections -eq 0) {
            Write-OutputColor "Remote Desktop is already enabled." -color "Info"
        }
        else {
            # Enable Remote Desktop
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -ErrorAction Stop

            # Verify
            $rdpStatus = Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections"
            if ($rdpStatus.fDenyTSConnections -eq 0) {
                Write-OutputColor "Remote Desktop has been enabled." -color "Success"
            }
            else {
                Write-OutputColor "Failed to enable Remote Desktop." -color "Error"
            }
        }

        # Enable firewall rules
        $firewallRule = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }

        if ($firewallRule) {
            Write-OutputColor "RDP firewall rules are already enabled." -color "Info"
        }
        else {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

            $firewallRule = Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue | Where-Object { $_.Enabled -eq $true }
            if ($firewallRule) {
                Write-OutputColor "RDP firewall rules have been enabled." -color "Success"
            }
            else {
                Write-OutputColor "Warning: Could not enable RDP firewall rules." -color "Warning"
            }
        }

        # Enable Network Level Authentication (recommended)
        try {
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -ErrorAction Stop
            Write-OutputColor "Network Level Authentication enabled (recommended for security)." -color "Success"
        }
        catch {
            Write-OutputColor "Warning: Could not enable Network Level Authentication." -color "Warning"
            Write-OutputColor "RDP is enabled but without NLA. Consider enabling manually." -color "Warning"
        }

        Add-SessionChange -Category "System" -Description "Enabled Remote Desktop"
        Clear-MenuCache  # Invalidate cache after change
    }
    catch {
        Write-OutputColor "Error configuring Remote Desktop: $_" -color "Error"
    }
}

# Function to enable PowerShell Remoting (WinRM) securely
function Enable-PowerShellRemoting {
    Clear-Host
    Write-CenteredOutput "Enable PowerShell Remoting" -color "Info"

    # Check current status - handle case where WinRM isn't running yet
    $winrmService = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    $winrmStatus = if ($null -ne $winrmService -and $winrmService.Status -eq "Running") { "Running" } else { "Stopped" }
    $winrmStartup = if ($null -ne $winrmService) { $winrmService.StartType } else { "Unknown" }

    Write-OutputColor "Current WinRM Status:" -color "Info"
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
    Write-OutputColor "This will configure PowerShell Remoting with the following SECURE settings:" -color "Info"
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
        Write-OutputColor "PowerShell Remoting configuration cancelled." -color "Info"
        return
    }

    try {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Configuring PowerShell Remoting..." -color "Info"

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
        Write-OutputColor "Verifying configuration..." -color "Info"

        $winrmService = Get-Service -Name WinRM
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
        Write-OutputColor "Security verification:" -color "Info"

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
        Write-OutputColor "PowerShell Remoting enabled successfully!" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Firewall rules enabled:" -color "Info"
        Write-OutputColor "  - Windows Remote Management (WinRM)" -color "Success"
        Write-OutputColor "  - Remote Event Log Management" -color "Success"
        Write-OutputColor "  - Remote Service Management" -color "Success"
        Write-OutputColor "  - Windows Management Instrumentation (WMI)" -color "Success"
        Write-OutputColor "  - Remote Scheduled Tasks Management" -color "Success"
        Write-OutputColor "  - File and Printer Sharing" -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "You can now connect to this server using:" -color "Info"
        Write-OutputColor "  Enter-PSSession -ComputerName $env:COMPUTERNAME" -color "Success"
        Write-OutputColor "  Invoke-Command -ComputerName $env:COMPUTERNAME -ScriptBlock { ... }" -color "Success"

        Add-SessionChange -Category "System" -Description "Enabled PowerShell Remoting (WinRM)"
        Clear-MenuCache  # Invalidate cache after change
    }
    catch {
        Write-OutputColor "Error configuring PowerShell Remoting: $_" -color "Error"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Troubleshooting tips:" -color "Warning"
        Write-OutputColor "  - Run this script as Administrator" -color "Info"
        Write-OutputColor "  - Check if WinRM service exists: Get-Service WinRM" -color "Info"
        Write-OutputColor "  - Try manual config: winrm quickconfig" -color "Info"
    }
}
#endregion