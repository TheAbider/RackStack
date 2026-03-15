#region ===== SYSTEM HEALTH CHECK =====

# Check certificates in LocalMachine\My for expiration within 30 days
function Test-CertificateExpiration {
    Write-OutputColor "=== CERTIFICATE EXPIRATION CHECK ===" -color "Success"
    $certIssues = @()
    try {
        $now = Get-Date
        $allCerts = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue)
        if ($allCerts.Count -eq 0) {
            Write-OutputColor "  No certificates in LocalMachine\My store." -color "Info"
        } else {
            $expiringSoon = @($allCerts | Where-Object { $_.NotAfter -lt $now.AddDays(30) } | Sort-Object NotAfter)
            if ($expiringSoon.Count -eq 0) {
                Write-OutputColor "  All $($allCerts.Count) certificate(s) valid for 30+ days." -color "Success"
            } else {
                foreach ($cert in $expiringSoon) {
                    $subject = if ($cert.Subject) { $cert.Subject } else { "(no subject)" }
                    if ($subject.Length -gt 40) { $subject = $subject.Substring(0, 37) + "..." }
                    $daysLeft = [math]::Floor(($cert.NotAfter - $now).TotalDays)
                    $thumbShort = if ($cert.Thumbprint -and $cert.Thumbprint.Length -ge 8) { $cert.Thumbprint.Substring(0, 8) + "..." } else { "N/A" }
                    $expiryStr = $cert.NotAfter.ToString('yyyy-MM-dd')

                    $certColor = if ($daysLeft -lt 0) { "Error" }
                                 elseif ($daysLeft -lt 3) { "Error" }
                                 elseif ($daysLeft -lt 7) { "Error" }
                                 elseif ($daysLeft -le 30) { "Warning" }
                                 else { "Success" }

                    $statusTag = if ($daysLeft -lt 0) { "EXPIRED" }
                                 elseif ($daysLeft -lt 3) { "CRITICAL" }
                                 elseif ($daysLeft -lt 7) { "URGENT" }
                                 else { "EXPIRING" }

                    Write-OutputColor "  [$statusTag] $subject" -color $certColor
                    Write-OutputColor "           Thumbprint: $thumbShort  Expires: $expiryStr  Days: $daysLeft" -color $certColor

                    if ($daysLeft -lt 0) {
                        $certIssues += "Expired certificate: $subject"
                    } elseif ($daysLeft -lt 7) {
                        $certIssues += "Certificate expiring in ${daysLeft}d: $subject"
                    }
                }
            }
        }
    } catch {
        Write-OutputColor "  Certificate expiration check unavailable: $_" -color "Debug"
    }
    Write-OutputColor "" -color "Info"
    return $certIssues
}

# Check Secure Boot and TPM status
function Test-SecureBootStatus {
    Write-OutputColor "=== SECURE BOOT / TPM STATUS ===" -color "Success"
    $securityIssues = @()

    # Secure Boot
    try {
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
        if ($secureBoot) {
            Write-OutputColor "  Secure Boot: Enabled" -color "Success"
        } else {
            Write-OutputColor "  Secure Boot: Disabled" -color "Warning"
            $securityIssues += "Secure Boot is disabled"
        }
    } catch {
        Write-OutputColor "  Secure Boot: Not available (non-UEFI or unsupported)" -color "Info"
    }

    # TPM
    try {
        $tpm = Get-Tpm -ErrorAction Stop
        if ($null -ne $tpm -and $tpm.TpmPresent) {
            $tpmColor = if ($tpm.TpmReady) { "Success" } else { "Warning" }
            Write-OutputColor "  TPM Present: Yes (Ready: $($tpm.TpmReady))" -color $tpmColor
            # Get TPM version from WMI
            try {
                $tpmWmi = Get-CimInstance -Namespace 'root\cimv2\security\microsofttpm' -ClassName Win32_Tpm -ErrorAction SilentlyContinue
                $tpmVersion = if ($null -ne $tpmWmi -and $null -ne $tpmWmi.SpecVersion) {
                    ($tpmWmi.SpecVersion -split ',')[0].Trim()
                } else { "Unknown" }
                Write-OutputColor "  TPM Version: $tpmVersion" -color "Info"
            } catch {
                Write-OutputColor "  TPM Version: Unable to determine" -color "Debug"
            }
            if (-not $tpm.TpmReady) {
                $securityIssues += "TPM is present but not ready"
            }
        } else {
            Write-OutputColor "  TPM Present: No" -color "Warning"
            $securityIssues += "No TPM detected"
        }
    } catch {
        Write-OutputColor "  TPM: Check unavailable ($_)" -color "Debug"
    }
    Write-OutputColor "" -color "Info"
    return $securityIssues
}

# Check network adapter speed negotiation for physical adapters
function Test-AdapterSpeedNegotiation {
    Write-OutputColor "=== ADAPTER SPEED NEGOTIATION ===" -color "Success"
    $adapterIssues = @()
    try {
        $physAdapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
        if ($physAdapters.Count -eq 0) {
            Write-OutputColor "  No physical network adapters found." -color "Info"
        } else {
            foreach ($adapter in $physAdapters) {
                $name = $adapter.Name
                $status = $adapter.Status
                $linkSpeed = if ($adapter.LinkSpeed) { $adapter.LinkSpeed } else { "N/A" }
                $mediaType = if ($adapter.MediaType) { $adapter.MediaType } else { "Unknown" }

                if ($status -ne "Up") {
                    Write-OutputColor "  $($name.PadRight(25)) Status: DOWN   Speed: N/A   Media: $mediaType" -color "Error"
                    $adapterIssues += "Adapter '$name' is down"
                    continue
                }

                # Parse speed value for comparison
                $speedMbps = 0
                if ($linkSpeed -match '(\d+(?:\.\d+)?)\s*Gbps') {
                    $regexMatches = $matches
                    $speedMbps = [double]$regexMatches[1] * 1000
                } elseif ($linkSpeed -match '(\d+(?:\.\d+)?)\s*Mbps') {
                    $regexMatches = $matches
                    $speedMbps = [double]$regexMatches[1]
                }

                $speedColor = if ($speedMbps -ge 10000) { "Success" }
                              elseif ($speedMbps -ge 1000) { "Success" }
                              elseif ($speedMbps -ge 100) { "Warning" }
                              else { "Error" }

                Write-OutputColor "  $($name.PadRight(25)) Status: Up     Speed: $($linkSpeed.PadRight(12)) Media: $mediaType" -color $speedColor

                if ($speedMbps -gt 0 -and $speedMbps -lt 1000) {
                    Write-OutputColor "    ^ Negotiated below 1 Gbps — check cable or switch port" -color "Warning"
                    $adapterIssues += "Adapter '$name' running at $linkSpeed (below 1 Gbps)"
                }
            }
        }
    } catch {
        Write-OutputColor "  Adapter speed check unavailable: $_" -color "Debug"
    }
    Write-OutputColor "" -color "Info"
    return $adapterIssues
}

# Check SMB connection dialects and flag non-3.x connections
function Test-SMBDialect {
    Write-OutputColor "=== SMB DIALECT CHECK ===" -color "Success"
    $smbIssues = @()
    try {
        $smbConnections = @(Get-SmbConnection -ErrorAction Stop)
        if ($smbConnections.Count -eq 0) {
            Write-OutputColor "  No active SMB connections." -color "Info"
        } else {
            foreach ($conn in $smbConnections) {
                $server = if ($conn.ServerName) { $conn.ServerName } else { "Unknown" }
                $share = if ($conn.ShareName) { $conn.ShareName } else { "Unknown" }
                $dialect = if ($conn.Dialect) { $conn.Dialect.ToString() } else { "Unknown" }
                $encrypted = if ($conn.Encrypted) { "Yes" } else { "No" }

                # Truncate server and share for display
                if ($server.Length -gt 20) { $server = $server.Substring(0, 17) + "..." }
                if ($share.Length -gt 20) { $share = $share.Substring(0, 17) + "..." }

                $dialectColor = if ($dialect -match '^3\.') { "Success" }
                                elseif ($dialect -match '^2\.') { "Warning" }
                                else { "Error" }

                Write-OutputColor "  $($server.PadRight(22)) Share: $($share.PadRight(22)) Dialect: $($dialect.PadRight(8)) Encrypted: $encrypted" -color $dialectColor

                if ($dialect -notmatch '^3\.' -and $dialect -ne "Unknown") {
                    $smbIssues += "SMB connection to \\$server\$share using dialect $dialect (not SMB 3.x)"
                }
            }
        }
    } catch {
        if ($_.Exception.Message -match 'not recognized|CommandNotFoundException') {
            Write-OutputColor "  SMB cmdlets not available on this edition." -color "Debug"
        } else {
            Write-OutputColor "  SMB dialect check unavailable: $_" -color "Debug"
        }
    }
    Write-OutputColor "" -color "Info"
    return $smbIssues
}

# Check NUMA topology and VM memory allocation on Hyper-V hosts
function Test-NUMATopology {
    Write-OutputColor "=== NUMA TOPOLOGY ===" -color "Success"
    $numaIssues = @()

    if (-not (Test-HyperVInstalled)) {
        Write-OutputColor "  Hyper-V not installed — NUMA check skipped." -color "Info"
        Write-OutputColor "" -color "Info"
        return $numaIssues
    }

    try {
        # Get NUMA node info
        $numaNodes = @(Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_HyperVHypervisorLogicalProcessor -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^NUMA Node \d+ Total$' })

        if ($numaNodes.Count -eq 0) {
            # Fall back to processor NUMA info
            $cpuResult = Invoke-WithTimeout -ScriptBlock {
                Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
            } -TimeoutSeconds 10 -Activity "Querying NUMA info"
            $cpus = if ($cpuResult.TimedOut) { @() } else { @($cpuResult.Result) }
            $numaCount = if ($cpus.Count -gt 0) { $cpus.Count } else { 1 }
            Write-OutputColor "  NUMA Nodes: $numaCount (based on physical processor count)" -color "Info"
        } else {
            $numaCount = $numaNodes.Count
            Write-OutputColor "  NUMA Nodes: $numaCount" -color "Info"
        }

        # Get per-node memory from CIM
        $numaNodeMemory = @(Get-CimInstance -ClassName Win32_PerfFormattedData_Counters_HyperVHypervisorNUMANode -ErrorAction SilentlyContinue)
        if ($numaNodeMemory.Count -gt 0) {
            foreach ($node in $numaNodeMemory) {
                $nodeName = if ($node.Name) { $node.Name } else { "Node" }
                $totalPagesMB = if ($null -ne $node.TotalPagesMByte) { $node.TotalPagesMByte } else { 0 }
                Write-OutputColor "  $nodeName`: ${totalPagesMB} MB" -color "Info"
            }
        }

        # Check running VMs for cross-NUMA allocation
        $runningVMs = @(Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" })
        if ($runningVMs.Count -eq 0) {
            Write-OutputColor "  No running VMs to check." -color "Info"
        } else {
            # Determine per-node memory capacity (approximate from total/nodes)
            $osResult = Invoke-WithTimeout -ScriptBlock {
                Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            } -TimeoutSeconds 10 -Activity "Querying memory for NUMA"
            $osInfo = if ($osResult.TimedOut) { $null } else { $osResult.Result }
            $totalMemGB = if ($null -ne $osInfo) { [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 1) } else { 0 }
            $perNodeGB = if ($numaCount -gt 0 -and $totalMemGB -gt 0) { [math]::Round($totalMemGB / $numaCount, 1) } else { 0 }

            if ($perNodeGB -gt 0) {
                Write-OutputColor "  Estimated per-node memory: ${perNodeGB} GB" -color "Info"
            }

            foreach ($vm in $runningVMs) {
                try {
                    $vmMemory = Get-VMMemory -VM $vm -ErrorAction SilentlyContinue
                    $vmProc = Get-VMProcessor -VM $vm -ErrorAction SilentlyContinue
                    $vmMemGB = if ($null -ne $vmMemory -and $null -ne $vmMemory.Startup) {
                        [math]::Round($vmMemory.Startup / 1GB, 1)
                    } else {
                        [math]::Round($vm.MemoryAssigned / 1GB, 1)
                    }
                    $vmCPU = if ($null -ne $vmProc) { $vmProc.Count } else { $vm.ProcessorCount }
                    $numaSpan = if ($null -ne $vmProc -and $null -ne $vmProc.MaximumCountPerNumaNode) {
                        if ($vmCPU -gt $vmProc.MaximumCountPerNumaNode) { "Yes" } else { "No" }
                    } else { "Unknown" }

                    $vmColor = "Success"
                    $crossNuma = $false
                    if ($perNodeGB -gt 0 -and $vmMemGB -gt $perNodeGB) {
                        $vmColor = "Warning"
                        $crossNuma = $true
                    }

                    $vmName = $vm.Name
                    if ($vmName.Length -gt 25) { $vmName = $vmName.Substring(0, 22) + "..." }
                    Write-OutputColor "  $($vmName.PadRight(27)) RAM: ${vmMemGB}GB  vCPU: $vmCPU  NUMA Spanning: $numaSpan" -color $vmColor

                    if ($crossNuma) {
                        Write-OutputColor "    ^ VM memory (${vmMemGB}GB) exceeds single NUMA node capacity (${perNodeGB}GB)" -color "Warning"
                        $numaIssues += "VM '$($vm.Name)' may span NUMA nodes (${vmMemGB}GB > ${perNodeGB}GB/node)"
                    }
                } catch {
                    Write-OutputColor "  $($vm.Name): Unable to check ($_)" -color "Debug"
                }
            }
        }
    } catch {
        Write-OutputColor "  NUMA topology check unavailable: $_" -color "Debug"
    }
    Write-OutputColor "" -color "Info"
    return $numaIssues
}

# CIS-lite security hardening audit — returns structured check results
function Get-SecurityHardeningChecks {
    <#
    .SYNOPSIS
        Returns structured security hardening check results as an array of hashtables.
        CIS-lite audit of security settings. Reusable by CLI Harden action and reports.
    #>
    $checks = [System.Collections.Generic.List[object]]::new()

    # ── PROTOCOL SECURITY ──

    # SMBv1 Disabled
    try {
        $smbConfig = Get-SmbServerConfiguration -ErrorAction Stop
        if ($smbConfig.EnableSMB1Protocol) {
            $checks.Add(@{ Category = "Protocol"; Name = "SMBv1"; Value = "Enabled (insecure)"; Status = "Fail" })
        } else {
            $checks.Add(@{ Category = "Protocol"; Name = "SMBv1"; Value = "Disabled"; Status = "Pass" })
        }
    } catch {
        $checks.Add(@{ Category = "Protocol"; Name = "SMBv1"; Value = "Unable to check"; Status = "Warn" })
    }

    # NTLMv1 Disabled (LmCompatibilityLevel >= 3 means NTLMv2 only)
    try {
        $lsa = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name LmCompatibilityLevel -ErrorAction Stop
        $lmLevel = $lsa.LmCompatibilityLevel
        if ($lmLevel -ge 3) {
            $checks.Add(@{ Category = "Protocol"; Name = "NTLMv1"; Value = "Disabled (Level $lmLevel)"; Status = "Pass" })
        } else {
            $checks.Add(@{ Category = "Protocol"; Name = "NTLMv1"; Value = "Allowed (Level $lmLevel)"; Status = "Fail" })
        }
    } catch {
        $checks.Add(@{ Category = "Protocol"; Name = "NTLMv1"; Value = "Default (key absent)"; Status = "Warn" })
    }

    # TLS 1.0 Disabled
    try {
        $tls10Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'
        if (Test-Path -LiteralPath $tls10Path) {
            $tls10 = Get-ItemProperty -Path $tls10Path -Name Enabled -ErrorAction SilentlyContinue
            if ($null -ne $tls10 -and $tls10.Enabled -eq 0) {
                $checks.Add(@{ Category = "Protocol"; Name = "TLS 1.0"; Value = "Disabled"; Status = "Pass" })
            } else {
                $checks.Add(@{ Category = "Protocol"; Name = "TLS 1.0"; Value = "Enabled"; Status = "Fail" })
            }
        } else {
            $checks.Add(@{ Category = "Protocol"; Name = "TLS 1.0"; Value = "Not explicitly disabled"; Status = "Warn" })
        }
    } catch {
        $checks.Add(@{ Category = "Protocol"; Name = "TLS 1.0"; Value = "Unable to check"; Status = "Warn" })
    }

    # TLS 1.1 Disabled
    try {
        $tls11Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server'
        if (Test-Path -LiteralPath $tls11Path) {
            $tls11 = Get-ItemProperty -Path $tls11Path -Name Enabled -ErrorAction SilentlyContinue
            if ($null -ne $tls11 -and $tls11.Enabled -eq 0) {
                $checks.Add(@{ Category = "Protocol"; Name = "TLS 1.1"; Value = "Disabled"; Status = "Pass" })
            } else {
                $checks.Add(@{ Category = "Protocol"; Name = "TLS 1.1"; Value = "Enabled"; Status = "Fail" })
            }
        } else {
            $checks.Add(@{ Category = "Protocol"; Name = "TLS 1.1"; Value = "Not explicitly disabled"; Status = "Warn" })
        }
    } catch {
        $checks.Add(@{ Category = "Protocol"; Name = "TLS 1.1"; Value = "Unable to check"; Status = "Warn" })
    }

    # ── ACCOUNT SECURITY ──

    # Guest Account Disabled
    try {
        $guest = Get-LocalUser -Name "Guest" -ErrorAction Stop
        if ($guest.Enabled) {
            $checks.Add(@{ Category = "Account"; Name = "Guest Account"; Value = "Enabled"; Status = "Fail" })
        } else {
            $checks.Add(@{ Category = "Account"; Name = "Guest Account"; Value = "Disabled"; Status = "Pass" })
        }
    } catch {
        $checks.Add(@{ Category = "Account"; Name = "Guest Account"; Value = "Not found"; Status = "Pass" })
    }

    # Built-in Administrator Account
    try {
        $adminAcct = Get-LocalUser -Name "Administrator" -ErrorAction Stop
        if ($adminAcct.Enabled) {
            $checks.Add(@{ Category = "Account"; Name = "Built-in Admin"; Value = "Enabled"; Status = "Warn" })
        } else {
            $checks.Add(@{ Category = "Account"; Name = "Built-in Admin"; Value = "Disabled"; Status = "Pass" })
        }
    } catch {
        $checks.Add(@{ Category = "Account"; Name = "Built-in Admin"; Value = "Check failed"; Status = "Warn" })
    }

    # ── NETWORK SECURITY ──

    # Windows Firewall (all profiles)
    try {
        $fw = Get-FirewallState
        $fwAllEnabled = ($fw.Domain -eq "Enabled" -and $fw.Private -eq "Enabled" -and $fw.Public -eq "Enabled")
        if ($fwAllEnabled) {
            $checks.Add(@{ Category = "Network"; Name = "Windows Firewall"; Value = "All profiles enabled"; Status = "Pass" })
        } else {
            $fwDisabled = @()
            if ($fw.Domain -ne "Enabled") { $fwDisabled += "Domain" }
            if ($fw.Private -ne "Enabled") { $fwDisabled += "Private" }
            if ($fw.Public -ne "Enabled") { $fwDisabled += "Public" }
            $checks.Add(@{ Category = "Network"; Name = "Windows Firewall"; Value = "Disabled: $($fwDisabled -join ', ')"; Status = "Fail" })
        }
    } catch {
        $checks.Add(@{ Category = "Network"; Name = "Windows Firewall"; Value = "Unable to check"; Status = "Warn" })
    }

    # Admin Shares (AutoShareServer / AutoShareWks)
    try {
        $lanmanPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        $autoShareServer = Get-ItemProperty -Path $lanmanPath -Name AutoShareServer -ErrorAction SilentlyContinue
        $autoShareWks = Get-ItemProperty -Path $lanmanPath -Name AutoShareWks -ErrorAction SilentlyContinue
        $serverDisabled = ($null -ne $autoShareServer -and $autoShareServer.AutoShareServer -eq 0)
        $wksDisabled = ($null -ne $autoShareWks -and $autoShareWks.AutoShareWks -eq 0)
        if ($serverDisabled -or $wksDisabled) {
            $checks.Add(@{ Category = "Network"; Name = "Admin Shares"; Value = "Disabled"; Status = "Pass" })
        } else {
            $checks.Add(@{ Category = "Network"; Name = "Admin Shares"; Value = "Enabled (default)"; Status = "Info" })
        }
    } catch {
        $checks.Add(@{ Category = "Network"; Name = "Admin Shares"; Value = "Unable to check"; Status = "Warn" })
    }

    # WinRM Encryption
    try {
        $winrmSvc = Get-Service -Name WinRM -ErrorAction SilentlyContinue
        if ($null -ne $winrmSvc -and $winrmSvc.Status -eq "Running") {
            $wsmanPath = 'WSMan:\localhost\Service\AllowUnencrypted'
            $allowUnencrypted = $null
            try { $allowUnencrypted = (Get-Item -LiteralPath $wsmanPath -ErrorAction Stop).Value } catch {}
            if ($null -ne $allowUnencrypted -and $allowUnencrypted -eq 'false') {
                $checks.Add(@{ Category = "Network"; Name = "WinRM Encryption"; Value = "Enforced"; Status = "Pass" })
            } elseif ($null -ne $allowUnencrypted -and $allowUnencrypted -eq 'true') {
                $checks.Add(@{ Category = "Network"; Name = "WinRM Encryption"; Value = "Unencrypted allowed"; Status = "Fail" })
            } else {
                $checks.Add(@{ Category = "Network"; Name = "WinRM Encryption"; Value = "Could not determine"; Status = "Warn" })
            }
        } else {
            $checks.Add(@{ Category = "Network"; Name = "WinRM Encryption"; Value = "WinRM not running"; Status = "Info" })
        }
    } catch {
        $checks.Add(@{ Category = "Network"; Name = "WinRM Encryption"; Value = "Unable to check"; Status = "Warn" })
    }

    # ── REMOTE ACCESS ──

    # RDP NLA Required
    try {
        $nla = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -ErrorAction Stop).UserAuthentication
        if ($nla -eq 1) {
            $checks.Add(@{ Category = "Remote Access"; Name = "RDP NLA"; Value = "Required"; Status = "Pass" })
        } else {
            $checks.Add(@{ Category = "Remote Access"; Name = "RDP NLA"; Value = "Not required"; Status = "Fail" })
        }
    } catch {
        $checks.Add(@{ Category = "Remote Access"; Name = "RDP NLA"; Value = "Unable to check"; Status = "Warn" })
    }

    # ── SYSTEM SECURITY ──

    # UAC Enabled
    try {
        $uacKey = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction Stop
        if ($uacKey.EnableLUA -eq 1) {
            $checks.Add(@{ Category = "System"; Name = "UAC"; Value = "Enabled"; Status = "Pass" })
        } else {
            $checks.Add(@{ Category = "System"; Name = "UAC"; Value = "Disabled"; Status = "Fail" })
        }
    } catch {
        $checks.Add(@{ Category = "System"; Name = "UAC"; Value = "Unable to check"; Status = "Warn" })
    }

    # Screen Lock Timeout
    try {
        $ssTimeout = Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name ScreenSaveTimeOut -ErrorAction SilentlyContinue
        $ssActive = Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name ScreenSaveActive -ErrorAction SilentlyContinue
        $ssSecure = Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name ScreenSaverIsSecure -ErrorAction SilentlyContinue
        $timeoutSec = if ($null -ne $ssTimeout -and $ssTimeout.ScreenSaveTimeOut) { [int]$ssTimeout.ScreenSaveTimeOut } else { 0 }
        $isActive = ($null -ne $ssActive -and $ssActive.ScreenSaveActive -eq '1')
        $isSecure = ($null -ne $ssSecure -and $ssSecure.ScreenSaverIsSecure -eq '1')

        if ($isActive -and $isSecure -and $timeoutSec -gt 0 -and $timeoutSec -le 900) {
            $checks.Add(@{ Category = "System"; Name = "Screen Lock"; Value = "${timeoutSec}s timeout, password required"; Status = "Pass" })
        } elseif ($isActive -and $timeoutSec -gt 0) {
            $pwdNote = if (-not $isSecure) { ', no password' } else { '' }
            $checks.Add(@{ Category = "System"; Name = "Screen Lock"; Value = "${timeoutSec}s timeout${pwdNote}"; Status = "Warn" })
        } else {
            $checks.Add(@{ Category = "System"; Name = "Screen Lock"; Value = "Not configured"; Status = "Warn" })
        }
    } catch {
        $checks.Add(@{ Category = "System"; Name = "Screen Lock"; Value = "Unable to check"; Status = "Warn" })
    }

    # ── AUDIT & LOGGING ──

    # PowerShell Script Block Logging
    try {
        $sblPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
        if (Test-Path -LiteralPath $sblPath) {
            $sbl = Get-ItemProperty -Path $sblPath -Name EnableScriptBlockLogging -ErrorAction SilentlyContinue
            if ($null -ne $sbl -and $sbl.EnableScriptBlockLogging -eq 1) {
                $checks.Add(@{ Category = "Audit"; Name = "Script Block Logging"; Value = "Enabled"; Status = "Pass" })
            } else {
                $checks.Add(@{ Category = "Audit"; Name = "Script Block Logging"; Value = "Disabled"; Status = "Fail" })
            }
        } else {
            $checks.Add(@{ Category = "Audit"; Name = "Script Block Logging"; Value = "Not configured"; Status = "Fail" })
        }
    } catch {
        $checks.Add(@{ Category = "Audit"; Name = "Script Block Logging"; Value = "Unable to check"; Status = "Warn" })
    }

    # Command Line in Process Audit Events
    try {
        $auditPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
        if (Test-Path -LiteralPath $auditPath) {
            $procAudit = Get-ItemProperty -Path $auditPath -Name ProcessCreationIncludeCmdLine_Enabled -ErrorAction SilentlyContinue
            if ($null -ne $procAudit -and $procAudit.ProcessCreationIncludeCmdLine_Enabled -eq 1) {
                $checks.Add(@{ Category = "Audit"; Name = "Command Line Auditing"; Value = "Enabled"; Status = "Pass" })
            } else {
                $checks.Add(@{ Category = "Audit"; Name = "Command Line Auditing"; Value = "Disabled"; Status = "Warn" })
            }
        } else {
            $checks.Add(@{ Category = "Audit"; Name = "Command Line Auditing"; Value = "Not configured"; Status = "Warn" })
        }
    } catch {
        $checks.Add(@{ Category = "Audit"; Name = "Command Line Auditing"; Value = "Unable to check"; Status = "Warn" })
    }

    # ── ENDPOINT PROTECTION ──

    # Antivirus / Defender Status
    try {
        $mpStat = Get-MpComputerStatus -ErrorAction Stop
        if ($mpStat.RealTimeProtectionEnabled) {
            $checks.Add(@{ Category = "Endpoint"; Name = "Antivirus Real-Time"; Value = "Enabled"; Status = "Pass" })
        } else {
            $checks.Add(@{ Category = "Endpoint"; Name = "Antivirus Real-Time"; Value = "DISABLED"; Status = "Fail" })
        }
    } catch {
        $checks.Add(@{ Category = "Endpoint"; Name = "Antivirus Real-Time"; Value = "Defender unavailable"; Status = "Warn" })
    }

    # BitLocker Status (C: drive)
    try {
        $blVolume = Get-BitLockerVolume -MountPoint "C:" -ErrorAction Stop
        if ($null -ne $blVolume -and $blVolume.ProtectionStatus -eq 'On') {
            $checks.Add(@{ Category = "Endpoint"; Name = "BitLocker (C:)"; Value = "Protected ($($blVolume.EncryptionMethod))"; Status = "Pass" })
        } elseif ($null -ne $blVolume) {
            $checks.Add(@{ Category = "Endpoint"; Name = "BitLocker (C:)"; Value = "$($blVolume.VolumeStatus)"; Status = "Fail" })
        } else {
            $checks.Add(@{ Category = "Endpoint"; Name = "BitLocker (C:)"; Value = "Not available"; Status = "Warn" })
        }
    } catch {
        $checks.Add(@{ Category = "Endpoint"; Name = "BitLocker (C:)"; Value = "Not available"; Status = "Info" })
    }

    # Windows Update Service Running
    try {
        $wuSvc = Get-Service -Name wuauserv -ErrorAction Stop
        if ($wuSvc.Status -eq "Running") {
            $checks.Add(@{ Category = "Endpoint"; Name = "Windows Update Svc"; Value = "Running"; Status = "Pass" })
        } else {
            $checks.Add(@{ Category = "Endpoint"; Name = "Windows Update Svc"; Value = $wuSvc.Status.ToString(); Status = "Warn" })
        }
    } catch {
        $checks.Add(@{ Category = "Endpoint"; Name = "Windows Update Svc"; Value = "Unable to check"; Status = "Warn" })
    }

    # ── UNNECESSARY SERVICES ──

    $riskyServices = @(
        @{ Name = "RemoteRegistry"; Display = "Remote Registry" }
        @{ Name = "Fax"; Display = "Fax Service" }
        @{ Name = "TapiSrv"; Display = "Telephony" }
    )
    foreach ($riskySvc in $riskyServices) {
        try {
            $svc = Get-Service -Name $riskySvc.Name -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                if ($svc.Status -eq "Running") {
                    $checks.Add(@{ Category = "Services"; Name = $riskySvc.Display; Value = "Running"; Status = "Warn" })
                } else {
                    $checks.Add(@{ Category = "Services"; Name = $riskySvc.Display; Value = "Stopped"; Status = "Pass" })
                }
            }
        } catch {
            # Service doesn't exist — fine
        }
    }

    return @($checks)
}

# Display security hardening audit with color-coded results
function Show-SecurityHardeningReport {
    <#
    .SYNOPSIS
        Runs security hardening checks and displays categorized results.
        Returns structured data for JSON output.
    #>
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Auditing security hardening settings..." -color "Info"
    Write-OutputColor "" -color "Info"

    $checks = Get-SecurityHardeningChecks
    $passCount = @($checks | Where-Object { $_.Status -eq 'Pass' }).Count
    $failCount = @($checks | Where-Object { $_.Status -eq 'Fail' }).Count
    $warnCount = @($checks | Where-Object { $_.Status -eq 'Warn' }).Count
    $infoCount = @($checks | Where-Object { $_.Status -eq 'Info' }).Count
    $totalChecks = $checks.Count

    # Group by category and display
    $categories = $checks | Group-Object -Property Category
    foreach ($cat in $categories) {
        Write-OutputColor "  === $($cat.Name.ToUpper()) ===" -color "Info"
        foreach ($check in $cat.Group) {
            $icon = switch ($check.Status) {
                'Pass' { '[PASS]' }
                'Fail' { '[FAIL]' }
                'Warn' { '[WARN]' }
                'Info' { '[INFO]' }
                default { '[----]' }
            }
            $statusColor = switch ($check.Status) {
                'Pass' { 'Success' }
                'Fail' { 'Error' }
                'Warn' { 'Warning' }
                'Info' { 'Info' }
                default { 'Info' }
            }
            Write-OutputColor "  $icon $($check.Name.PadRight(28)) $($check.Value)" -color $statusColor
        }
        Write-OutputColor "" -color "Info"
    }

    # Score
    $score = if ($totalChecks -gt 0) { [math]::Round(($passCount / $totalChecks) * 100) } else { 0 }
    $scoreColor = if ($score -ge 80) { 'Success' } elseif ($score -ge 50) { 'Warning' } else { 'Error' }

    Write-OutputColor "  ── Hardening Summary ──" -color "Info"
    Write-OutputColor "  Score: $score% ($passCount passed, $failCount failed, $warnCount warnings, $infoCount info)" -color $scoreColor
    Write-OutputColor "" -color "Info"

    if ($failCount -gt 0) {
        Write-OutputColor "  Failed checks:" -color "Error"
        foreach ($failed in @($checks | Where-Object { $_.Status -eq 'Fail' })) {
            Write-OutputColor "    - $($failed.Name): $($failed.Value)" -color "Error"
        }
        Write-OutputColor "" -color "Info"
    }

    Add-SessionChange -Category "Security" -Description "Ran security hardening audit (score: ${score}%, $failCount failed)"

    return @{
        Timestamp  = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Hostname   = $env:COMPUTERNAME
        Score      = $score
        Total      = $totalChecks
        Passed     = $passCount
        Failed     = $failCount
        Warnings   = $warnCount
        Info       = $infoCount
        Checks     = @($checks)
    }
}

# Function to display system health information
function Show-SystemHealthCheck {
    $report = @{
        Timestamp = (Get-Date).ToString('o')
        Hostname  = $env:COMPUTERNAME
        Sections  = [ordered]@{}
        Issues    = @()
    }
    Clear-Host
    Write-CenteredOutput "System Health Check" -color "Info"

    Write-OutputColor "  Gathering system information..." -color "Info"
    Write-OutputColor "" -color "Info"

    # System Info (CIM with timeout — immune to WMI hangs)
    Write-OutputColor "=== SYSTEM INFORMATION ===" -color "Success"
    $cimResult = Invoke-WithTimeout -ScriptBlock {
        @{
            OS  = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
            CS  = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
            CPU = Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue
        }
    } -TimeoutSeconds 15 -Activity "Querying system info"

    if ($cimResult.TimedOut) {
        Write-OutputColor "  WMI/CIM query timed out — system may be under heavy load." -color "Warning"
        $os = $null; $cs = $null; $cpuAll = $null
    } else {
        $os = $cimResult.Result.OS
        $cs = $cimResult.Result.CS
        $cpuAll = $cimResult.Result.CPU
    }

    Write-OutputColor "  Computer Name: $(if ($cs) { $cs.Name } else { $env:COMPUTERNAME })" -color "Info"
    Write-OutputColor "  OS: $(if ($os) { $os.Caption } else { 'Unknown' })" -color "Info"
    Write-OutputColor "  Version: $(if ($os) { $os.Version } else { 'Unknown' })" -color "Info"
    Write-OutputColor "  Last Boot: $(if ($os) { $os.LastBootUpTime } else { 'Unknown' })" -color "Info"

    if ($os -and $os.LastBootUpTime) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeStr = "{0} days, {1} hours, {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    } else { $uptimeStr = "Unknown" }
    Write-OutputColor "  Uptime: $uptimeStr" -color "Info"
    $report.Sections['System'] = @{
        ComputerName = if ($cs) { $cs.Name } else { $env:COMPUTERNAME }
        OS           = if ($os) { $os.Caption } else { 'Unknown' }
        Version      = if ($os) { $os.Version } else { 'Unknown' }
        LastBoot     = if ($os) { $os.LastBootUpTime.ToString('o') } else { $null }
        UptimeDays   = if ($os -and $os.LastBootUpTime) { [math]::Floor(((Get-Date) - $os.LastBootUpTime).TotalDays) } else { $null }
    }
    Write-OutputColor "" -color "Info"

    # CPU
    Write-OutputColor "=== CPU ===" -color "Success"
    $cpu = $cpuAll | Select-Object -First 1
    $cpuName = if ($cpu) { $cpu.Name } else { "Unknown" }
    $cpuCores = if ($cpu) { $cpu.NumberOfCores } else { "?" }
    $cpuLogical = if ($cpu) { $cpu.NumberOfLogicalProcessors } else { "?" }
    Write-OutputColor "  Processor: $cpuName" -color "Info"
    Write-OutputColor "  Cores: $cpuCores | Logical: $cpuLogical" -color "Info"

    $cpuMeasure = $cpuAll | Measure-Object -Property LoadPercentage -Average
    $cpuLoad = if ($null -ne $cpuMeasure -and $null -ne $cpuMeasure.Average) { $cpuMeasure.Average } else { 0 }
    $cpuColor = if ($cpuLoad -gt 80) { "Error" } elseif ($cpuLoad -gt 50) { "Warning" } else { "Success" }
    Write-OutputColor "  Current Load: $([math]::Round($cpuLoad, 1))%" -color $cpuColor
    $report.Sections['CPU'] = @{
        Name           = $cpuName
        Cores          = $cpuCores
        LogicalCores   = $cpuLogical
        LoadPercent    = [math]::Round($cpuLoad, 1)
    }
    Write-OutputColor "" -color "Info"

    # Memory
    Write-OutputColor "=== MEMORY ===" -color "Success"
    if ($os) {
        $totalMemGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    } else {
        $totalMemGB = 0
        $freeMemGB = 0
    }
    $usedMemGB = $totalMemGB - $freeMemGB
    $memPercent = if ($totalMemGB -gt 0) { [math]::Round(($usedMemGB / $totalMemGB) * 100, 1) } else { 0 }
    $memColor = if ($memPercent -gt 90) { "Error" } elseif ($memPercent -gt 75) { "Warning" } else { "Success" }
    Write-OutputColor "  Total: $totalMemGB GB" -color "Info"
    Write-OutputColor "  Used: $usedMemGB GB ($memPercent%)" -color $memColor
    Write-OutputColor "  Free: $freeMemGB GB" -color "Info"
    $report.Sections['Memory'] = @{
        TotalGB     = $totalMemGB
        UsedGB      = $usedMemGB
        FreeGB      = $freeMemGB
        UsedPercent = $memPercent
    }
    Write-OutputColor "" -color "Info"

    # Disk Space
    Write-OutputColor "=== DISK SPACE ===" -color "Success"
    $diskResult = Invoke-WithTimeout -ScriptBlock {
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
    } -TimeoutSeconds 10 -Activity "Querying disk info"
    $disks = if ($diskResult.TimedOut) { $null } else { $diskResult.Result }
    if ($diskResult.TimedOut) {
        Write-OutputColor "  Disk query timed out." -color "Warning"
    }
    foreach ($disk in $disks) {
        $totalGB = [math]::Round($disk.Size / 1GB, 2)
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
        $usedPercent = if ($disk.Size -gt 0) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 0 }
        $diskColor = if ($usedPercent -gt 90) { "Error" } elseif ($usedPercent -gt 75) { "Warning" } else { "Success" }
        Write-OutputColor "  $($disk.DeviceID) - Total: $totalGB GB | Free: $freeGB GB | Used: $usedPercent%" -color $diskColor
    }
    $report.Sections['Disks'] = @(foreach ($disk in $disks) {
        @{
            Drive       = $disk.DeviceID
            TotalGB     = [math]::Round($disk.Size / 1GB, 2)
            FreeGB      = [math]::Round($disk.FreeSpace / 1GB, 2)
            UsedPercent = if ($disk.Size -gt 0) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 0 }
        }
    })
    Write-OutputColor "" -color "Info"

    # Network Adapters
    Write-OutputColor "=== NETWORK ADAPTERS ===" -color "Success"
    $allAdapters = Get-NetAdapter -ErrorAction SilentlyContinue
    $allIPv4 = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
    foreach ($adapter in ($allAdapters | Where-Object { $_.Status -eq "Up" })) {
        $ip = $allIPv4 | Where-Object { $_.InterfaceAlias -eq $adapter.Name } | Select-Object -First 1
        $ipStr = if ($ip) { $ip.IPAddress } else { "No IP" }
        Write-OutputColor "  $($adapter.Name): $ipStr ($($adapter.LinkSpeed))" -color "Success"
    }

    foreach ($adapter in ($allAdapters | Where-Object { $_.Status -ne "Up" })) {
        Write-OutputColor "  $($adapter.Name): DOWN" -color "Warning"
    }
    $report.Sections['NetworkAdapters'] = @(foreach ($adapter in $allAdapters) {
        $ip = $allIPv4 | Where-Object { $_.InterfaceAlias -eq $adapter.Name } | Select-Object -First 1
        @{
            Name   = $adapter.Name
            Status = $adapter.Status.ToString()
            IP     = if ($ip) { $ip.IPAddress } else { $null }
            Speed  = $adapter.LinkSpeed
        }
    })
    Write-OutputColor "" -color "Info"

    # Pending Updates
    Write-OutputColor "=== WINDOWS UPDATE STATUS ===" -color "Success"
    if (Test-RebootPending) {
        Write-OutputColor "  Reboot Pending: YES" -color "Warning"
    }
    else {
        Write-OutputColor "  Reboot Pending: No" -color "Success"
    }

    # Try to check for updates (may require PSWindowsUpdate module)
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session -ErrorAction Stop
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        $pendingUpdates = $updateSearcher.Search("IsInstalled=0").Updates.Count
        $updateColor = if ($pendingUpdates -gt 10) { "Warning" } elseif ($pendingUpdates -gt 0) { "Info" } else { "Success" }
        Write-OutputColor "  Pending Updates: $pendingUpdates" -color $updateColor
    }
    catch {
        Write-OutputColor "  Pending Updates: Unable to check" -color "Info"
    }
    Write-OutputColor "" -color "Info"

    # Key Services
    Write-OutputColor "=== KEY SERVICES ===" -color "Success"
    $keyServices = @(
        @{ Name = "wuauserv"; Display = "Windows Update" },
        @{ Name = "WinRM"; Display = "WinRM" },
        @{ Name = "vmms"; Display = "Hyper-V Management" },
        @{ Name = "TermService"; Display = "Remote Desktop" },
        @{ Name = "DNS"; Display = "DNS Server" },
        @{ Name = "DFSR"; Display = "DFS Replication" }
    )

    foreach ($svc in $keyServices) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            $svcColor = if ($service.Status -eq "Running") { "Success" } else { "Warning" }
            $statusStr = $service.Status.ToString()
            Write-OutputColor "  $($svc.Display): $statusStr" -color $svcColor
        }
    }
    $report.Sections['Services'] = @(foreach ($svc in $keyServices) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            @{ Name = $svc.Display; Status = $service.Status.ToString() }
        }
    })
    Write-OutputColor "" -color "Info"

    # Certificates
    Write-OutputColor "=== CERTIFICATES ===" -color "Success"
    try {
        $now = Get-Date
        $allCerts = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue)
        if ($allCerts.Count -eq 0) {
            Write-OutputColor "  No certificates in LocalMachine\My store." -color "Info"
        } else {
            foreach ($cert in ($allCerts | Sort-Object NotAfter)) {
                $subject = if ($cert.Subject) { $cert.Subject } else { "(no subject)" }
                if ($subject.Length -gt 40) { $subject = $subject.Substring(0, 37) + "..." }
                $daysLeft = [math]::Floor(($cert.NotAfter - $now).TotalDays)
                $expiryStr = "$($cert.NotAfter.ToString('yyyy-MM-dd')) (${daysLeft}d)"
                $certColor = if ($daysLeft -lt 0) { "Error" } elseif ($daysLeft -lt 30) { "Warning" } else { "Success" }
                $statusTag = if ($daysLeft -lt 0) { "EXPIRED" } elseif ($daysLeft -lt 30) { "EXPIRING" } else { "OK" }
                Write-OutputColor "  [$statusTag] $subject" -color $certColor
                $thumbShort = if ($cert.Thumbprint -and $cert.Thumbprint.Length -ge 8) { $cert.Thumbprint.Substring(0,8) + "..." } else { "N/A" }
                Write-OutputColor "           Expires: $expiryStr  Thumbprint: $thumbShort" -color $certColor
            }
        }
    } catch {
        Write-OutputColor "  Certificate check unavailable: $_" -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # Collect issues for end-of-check summary (captures all checks, not just early ones)
    $issues = @()
    if ($cpuLoad -gt 80) { $issues += "High CPU usage ($([math]::Round($cpuLoad, 0))%)" }
    if ($memPercent -gt 90) { $issues += "High memory usage ($memPercent%)" }
    foreach ($disk in $disks) {
        $usedPercent = if ($disk.Size -gt 0) { [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1) } else { 0 }
        if ($usedPercent -gt 90) { $issues += "Low disk space on $($disk.DeviceID) ($usedPercent%)" }
    }
    if (Test-RebootPending) { $issues += "Reboot pending" }
    $expiredCertCount = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.NotAfter -le (Get-Date) }).Count
    $expiringCertCount = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.NotAfter -lt (Get-Date).AddDays(30) -and $_.NotAfter -gt (Get-Date) }).Count
    if ($expiredCertCount -gt 0) { $issues += "$expiredCertCount expired certificate(s)" }
    if ($expiringCertCount -gt 0) { $issues += "$expiringCertCount certificate(s) expiring within 30 days" }

    # Disk I/O Latency (v1.7.0, enhanced v1.9.46)
    Write-OutputColor "=== DISK I/O LATENCY ===" -color "Success"
    try {
        $diskCounters = Get-Counter '\PhysicalDisk(*)\Avg. Disk sec/Read', '\PhysicalDisk(*)\Avg. Disk sec/Write' -ErrorAction SilentlyContinue
        if ($diskCounters) {
            # Group by disk instance
            $diskData = @{}
            foreach ($sample in $diskCounters.CounterSamples) {
                $instanceName = $sample.InstanceName
                if ($instanceName -eq '_total') { continue }
                if (-not $diskData.ContainsKey($instanceName)) { $diskData[$instanceName] = @{} }
                $metricName = if ($sample.Path -match 'Read') { "Read" } else { "Write" }
                $diskData[$instanceName][$metricName] = [math]::Round($sample.CookedValue * 1000, 2)
            }

            $degradedDisks = @()
            foreach ($diskName in $diskData.Keys) {
                $readMs = if ($diskData[$diskName].ContainsKey("Read")) { $diskData[$diskName]["Read"] } else { 0 }
                $writeMs = if ($diskData[$diskName].ContainsKey("Write")) { $diskData[$diskName]["Write"] } else { 0 }
                $readColor = if ($readMs -gt 20) { "Error" } elseif ($readMs -gt 10) { "Warning" } else { "Success" }
                $writeColor = if ($writeMs -gt 20) { "Error" } elseif ($writeMs -gt 10) { "Warning" } else { "Success" }
                Write-OutputColor "  Disk $diskName  Read: ${readMs}ms ($readColor)  Write: ${writeMs}ms ($writeColor)" -color "Info"
                if ($readMs -gt 20 -or $writeMs -gt 20) {
                    $degradedDisks += $diskName
                    if ($writeMs -gt 20 -and $readMs -le 20) {
                        Write-OutputColor "    ^ Write latency high — check for background scans or disk utilities" -color "Warning"
                    }
                }
            }

            if ($degradedDisks.Count -gt 0) {
                Write-OutputColor "  Disk Performance: DEGRADED ($($degradedDisks.Count) disk(s) above threshold)" -color "Error"
                $issues += "High disk I/O latency on $($degradedDisks.Count) disk(s)"
            } elseif (@($diskData.Values | ForEach-Object { $_.Values } | Where-Object { $_ -gt 10 }).Count -gt 0) {
                Write-OutputColor "  Disk Performance: FAIR (some latency above 10ms)" -color "Warning"
            } else {
                Write-OutputColor "  Disk Performance: GOOD (all latencies under 10ms)" -color "Success"
            }
        }
        else {
            Write-OutputColor "  Unable to read disk performance counters." -color "Debug"
        }
    }
    catch {
        Write-OutputColor "  Disk I/O check unavailable: $_" -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # NIC Error Counters (v1.7.0)
    Write-OutputColor "=== NIC ERROR COUNTERS ===" -color "Success"
    try {
        $nicStats = Get-NetAdapterStatistics -ErrorAction SilentlyContinue
        foreach ($nic in $nicStats) {
            $inErrors = $nic.InErrors
            $outErrors = $nic.OutErrors
            $inDiscards = $nic.InDiscards
            $totalErrors = $inErrors + $outErrors + $inDiscards
            $nicColor = if ($totalErrors -gt 0) { "Warning" } else { "Success" }
            Write-OutputColor "  $($nic.Name): InErrors=$inErrors OutErrors=$outErrors InDiscards=$inDiscards" -color $nicColor
        }
    }
    catch {
        Write-OutputColor "  NIC statistics unavailable." -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # Memory Pressure (v1.7.0)
    Write-OutputColor "=== MEMORY PRESSURE ===" -color "Success"
    try {
        $memCounters = Get-Counter '\Memory\Pages/sec', '\Memory\Available MBytes' -ErrorAction SilentlyContinue
        if ($memCounters) {
            foreach ($sample in $memCounters.CounterSamples) {
                $counterName = if ($sample.Path -match 'Pages') { "Pages/sec" } else { "Available MB" }
                $value = [math]::Round($sample.CookedValue, 1)
                $pressureColor = "Success"
                if ($counterName -eq "Pages/sec" -and $value -gt 1000) { $pressureColor = "Warning" }
                if ($counterName -eq "Available MB" -and $value -lt 500) { $pressureColor = "Error" }
                elseif ($counterName -eq "Available MB" -and $value -lt 2000) { $pressureColor = "Warning" }
                Write-OutputColor "  $counterName`: $value" -color $pressureColor
            }
        }
    }
    catch {
        Write-OutputColor "  Memory pressure counters unavailable." -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # Hyper-V Guest Health (v1.7.0)
    if (Test-HyperVInstalled) {
        Write-OutputColor "=== HYPER-V GUEST HEALTH ===" -color "Success"
        try {
            $runningVMs = Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }
            if ($runningVMs) {
                foreach ($vm in $runningVMs) {
                    $hb = Get-VMIntegrationService -VM $vm -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Heartbeat" }
                    $hbStatus = if ($hb -and $hb.PrimaryStatusDescription -eq "OK") { "OK" } elseif ($hb) { $hb.PrimaryStatusDescription } else { "N/A" }
                    $vmColor = if ($hbStatus -eq "OK") { "Success" } else { "Warning" }
                    Write-OutputColor "  $($vm.Name): Heartbeat=$hbStatus  CPU=$($vm.ProcessorCount)  RAM=$([math]::Round($vm.MemoryAssigned/1GB,1))GB" -color $vmColor
                }
            }
            else {
                Write-OutputColor "  No running VMs." -color "Info"
            }
        }
        catch {
            Write-OutputColor "  Hyper-V guest health unavailable." -color "Debug"
        }
        Write-OutputColor "" -color "Info"
    }

    # Top 5 CPU Processes (v1.7.0)
    Write-OutputColor "=== TOP 5 CPU PROCESSES ===" -color "Success"
    try {
        $topProcs = Get-Process -ErrorAction SilentlyContinue | Sort-Object CPU -Descending | Select-Object -First 5
        foreach ($proc in $topProcs) {
            $cpuSec = if ($null -ne $proc.CPU) { [math]::Round($proc.CPU, 1) } else { 0 }
            $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
            Write-OutputColor "  $($proc.ProcessName.PadRight(30)) CPU: ${cpuSec}s  RAM: ${memMB}MB" -color "Info"
        }
    }
    catch {
        Write-OutputColor "  Process information unavailable." -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # Time Sync Status
    Write-OutputColor "=== TIME SYNC ===" -color "Success"
    try {
        $w32tmStatus = w32tm /query /status 2>&1
        $timeSource = "Unknown"
        $timeOffset = $null
        foreach ($statusLine in $w32tmStatus) {
            $lineText = $statusLine.ToString()
            if ($lineText -match 'Source:\s*(.+)') {
                $regexMatches = $matches
                $timeSource = $regexMatches[1].Trim()
            }
            if ($lineText -match 'Phase Offset:\s*([\-\d\.]+)s') {
                $regexMatches = $matches
                $timeOffset = [double]$regexMatches[1]
            }
        }
        $sourceDisplay = if ($timeSource.Length -gt 50) { $timeSource.Substring(0, 47) + "..." } else { $timeSource }
        Write-OutputColor "  Source: $sourceDisplay" -color "Info"
        if ($null -ne $timeOffset) {
            $absOffset = [math]::Abs($timeOffset)
            $offsetColor = if ($absOffset -gt 30) { "Error" } elseif ($absOffset -gt 1) { "Warning" } else { "Success" }
            Write-OutputColor "  Offset: $([math]::Round($absOffset * 1000, 1))ms" -color $offsetColor
            if ($absOffset -gt 30) { $issues += "Critical time skew (${timeOffset}s)" }
            elseif ($absOffset -gt 5) { $issues += "Time skew detected (${timeOffset}s)" }
        }
        if ($timeSource -eq "Free-Running System Clock" -or $timeSource -eq "Local CMOS Clock") {
            Write-OutputColor "  No external time source configured" -color "Warning"
            $issues += "No NTP time source configured"
        }
    }
    catch {
        Write-OutputColor "  Time sync check unavailable." -color "Debug"
    }
    Write-OutputColor "" -color "Info"

    # Recent Critical Events (last 24h)
    Write-OutputColor "=== RECENT CRITICAL EVENTS (24h) ===" -color "Success"
    try {
        $critEvents = @(Get-WinEvent -FilterHashtable @{LogName='System','Application'; Level=1,2; StartTime=(Get-Date).AddHours(-24)} -MaxEvents 10 -ErrorAction SilentlyContinue)
        if ($critEvents.Count -eq 0) {
            Write-OutputColor "  No critical or error events in the last 24 hours." -color "Success"
        }
        else {
            $eventColor = if ($critEvents.Count -ge 5) { "Error" } else { "Warning" }
            Write-OutputColor "  Found $($critEvents.Count)+ critical/error event(s):" -color $eventColor
            foreach ($evt in $critEvents | Select-Object -First 5) {
                $evtMsg = if ($evt.Message -and $evt.Message.Length -gt 55) { $evt.Message.Substring(0, 52) + "..." } elseif ($evt.Message) { $evt.Message } else { "(no message)" }
                $evtMsg = $evtMsg -replace "`r`n|`n", " "
                $evtTime = if ($evt.TimeCreated) { $evt.TimeCreated.ToString("MM-dd HH:mm") } else { "N/A" }
                Write-OutputColor "  [$evtTime] $evtMsg" -color $eventColor
            }
            if ($critEvents.Count -ge 5) { $issues += "$($critEvents.Count)+ critical/error events in last 24h" }
        }
    }
    catch {
        if ($_.Exception.Message -notlike "*No events were found*") {
            Write-OutputColor "  Event log check unavailable: $_" -color "Debug"
        } else {
            Write-OutputColor "  No critical or error events in the last 24 hours." -color "Success"
        }
    }
    Write-OutputColor "" -color "Info"

    # Firewall Status (uses registry-first approach via Get-FirewallState)
    Write-OutputColor "=== FIREWALL STATUS ===" -color "Success"
    try {
        $fwState = Get-FirewallState
        foreach ($profileName in @('Domain', 'Private', 'Public')) {
            $fwStatus = $fwState[$profileName]
            $fwColor = if ($fwStatus -eq "Enabled") { "Success" } elseif ($fwStatus -eq "Unknown") { "Debug" } else { "Warning" }
            Write-OutputColor "  ${profileName}: $fwStatus" -color $fwColor
            if ($fwStatus -eq "Disabled") { $issues += "Firewall $profileName profile disabled" }
        }
    }
    catch {
        Write-OutputColor "  Firewall status unavailable." -color "Debug"
    }
    $report.Sections['Firewall'] = @{
        Domain  = $fwState['Domain']
        Private = $fwState['Private']
        Public  = $fwState['Public']
    }
    Write-OutputColor "" -color "Info"

    # Certificate Expiration Check
    $certIssues = Test-CertificateExpiration
    if ($null -ne $certIssues) { $issues += $certIssues }

    # Secure Boot / TPM Status
    $securityIssues = Test-SecureBootStatus
    if ($null -ne $securityIssues) { $issues += $securityIssues }

    # Adapter Speed Negotiation
    $adapterIssues = Test-AdapterSpeedNegotiation
    if ($null -ne $adapterIssues) { $issues += $adapterIssues }

    # SMB Dialect Check
    $smbIssues = Test-SMBDialect
    if ($null -ne $smbIssues) { $issues += $smbIssues }

    # NUMA Topology (Hyper-V hosts only)
    $numaIssues = Test-NUMATopology
    if ($null -ne $numaIssues) { $issues += $numaIssues }

    # Final Summary (at end, captures all issues from all checks)
    Write-OutputColor "=== HEALTH SUMMARY ===" -color "Success"
    if ($issues.Count -eq 0) {
        Write-OutputColor "  System health: GOOD - No issues detected" -color "Success"
    }
    else {
        Write-OutputColor "  System health: ATTENTION NEEDED ($($issues.Count) issue(s))" -color "Warning"
        foreach ($issue in $issues) {
            Write-OutputColor "    - $issue" -color "Warning"
        }
    }
    Write-OutputColor "" -color "Info"

    Add-SessionChange -Category "System" -Description "Ran system health check ($($issues.Count) issue(s))"

    # Return structured report for JSON output mode
    $report.Issues = $issues
    $report.IssueCount = $issues.Count
    $report.Health = if ($issues.Count -eq 0) { 'GOOD' } elseif ($issues.Count -le 3) { 'ATTENTION' } else { 'CRITICAL' }
    return $report
}

# Function to display server configuration readiness at a glance
function Show-ServerReadiness {
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     SERVER READINESS DASHBOARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Checking configuration status..." -color "Info"
    Write-OutputColor "" -color "Info"

    $ready = 0
    $total = 0
    $items = @()

    # --- IDENTITY ---
    $hostname = $env:COMPUTERNAME
    $isDefaultName = $hostname -match '^WIN-|^DESKTOP-|^YOURSERVERNAME'
    $total++
    if (-not $isDefaultName) {
        $ready++
        $items += @{ Category = "IDENTITY"; Name = "Hostname"; Value = $hostname; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "IDENTITY"; Name = "Hostname"; Value = "$hostname (default)"; Color = "Error"; Symbol = "[!!]" }
    }

    $total++
    $csResult = Invoke-WithTimeout -ScriptBlock { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue } -TimeoutSeconds 10 -Activity "Checking domain"
    $cs = if ($csResult.TimedOut) { $null } else { $csResult.Result }
    if ($null -ne $cs -and $cs.PartOfDomain) {
        $ready++
        $items += @{ Category = "IDENTITY"; Name = "Domain"; Value = $cs.Domain; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "IDENTITY"; Name = "Domain"; Value = "WORKGROUP (not joined)"; Color = "Warning"; Symbol = "[--]" }
    }

    $total++
    $siteNum = Get-SiteNumberFromHostname
    if ($siteNum) {
        $ready++
        $items += @{ Category = "IDENTITY"; Name = "Site Number"; Value = $siteNum; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "IDENTITY"; Name = "Site Number"; Value = "Not detected in hostname"; Color = "Warning"; Symbol = "[--]" }
    }

    # --- REMOTE ACCESS ---
    $total++
    $rdpState = Get-RDPState
    if ($rdpState -eq "Enabled") {
        $ready++
        $items += @{ Category = "REMOTE ACCESS"; Name = "RDP"; Value = "Enabled"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "REMOTE ACCESS"; Name = "RDP"; Value = "Disabled"; Color = "Warning"; Symbol = "[--]" }
    }

    $total++
    $winrmState = Get-WinRMState
    if ($winrmState -eq "Enabled") {
        $ready++
        $items += @{ Category = "REMOTE ACCESS"; Name = "WinRM"; Value = "Enabled"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "REMOTE ACCESS"; Name = "WinRM"; Value = $winrmState; Color = "Warning"; Symbol = "[--]" }
    }

    # --- SOFTWARE ---
    if (Test-AgentInstallerConfigured) {
        $total++
        $agentStatus = Test-AgentInstalled
        if ($agentStatus.Installed) {
            $ready++
            $agentVal = if ($agentStatus.Status -eq "Running") { "Installed & Running" } else { "Installed ($($agentStatus.Status))" }
            $agentColor = if ($agentStatus.Status -eq "Running") { "Success" } else { "Warning" }
            $items += @{ Category = "SOFTWARE"; Name = "$($script:AgentInstaller.ToolName) Agent"; Value = $agentVal; Color = $agentColor; Symbol = "[OK]" }
        } else {
            $items += @{ Category = "SOFTWARE"; Name = "$($script:AgentInstaller.ToolName) Agent"; Value = "Not Installed"; Color = "Error"; Symbol = "[!!]" }
        }
    }

    # --- ROLES & FEATURES ---
    $total++
    if (Test-HyperVInstalled) {
        $ready++
        $items += @{ Category = "ROLES"; Name = "Hyper-V"; Value = "Installed"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "ROLES"; Name = "Hyper-V"; Value = "Not Installed"; Color = "Info"; Symbol = "[--]" }
    }

    if (Test-WindowsServer) {
        $total++
        if (Test-MPIOInstalled) {
            $ready++
            $items += @{ Category = "ROLES"; Name = "MPIO"; Value = "Installed"; Color = "Success"; Symbol = "[OK]" }
        } else {
            $items += @{ Category = "ROLES"; Name = "MPIO"; Value = "Not Installed"; Color = "Info"; Symbol = "[--]" }
        }

        $total++
        if (Test-FailoverClusteringInstalled) {
            $ready++
            $items += @{ Category = "ROLES"; Name = "Failover Clustering"; Value = "Installed"; Color = "Success"; Symbol = "[OK]" }
        } else {
            $items += @{ Category = "ROLES"; Name = "Failover Clustering"; Value = "Not Installed"; Color = "Info"; Symbol = "[--]" }
        }
    }

    # --- NETWORK ---
    $total++
    $fwState = Get-FirewallState
    $fwCorrect = ($fwState.Domain -eq "Disabled" -and $fwState.Private -eq "Disabled" -and $fwState.Public -eq "Enabled")
    if ($fwCorrect) {
        $ready++
        $items += @{ Category = "NETWORK"; Name = "Firewall"; Value = "Domain=Off Private=Off Public=On"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $status = "Domain=$(if($fwState.Domain -eq 'Enabled'){'On'}else{'Off'}) Private=$(if($fwState.Private -eq 'Enabled'){'On'}else{'Off'}) Public=$(if($fwState.Public -eq 'Enabled'){'On'}else{'Off'})"
        $items += @{ Category = "NETWORK"; Name = "Firewall"; Value = $status; Color = "Warning"; Symbol = "[--]" }
    }

    $total++
    $adaptersUp = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq "Up" })
    if ($adaptersUp.Count -gt 0) {
        $ready++
        # Check for adapters at <1Gbps (potential cable/negotiation issue)
        $slowCount = 0
        foreach ($adp in $adaptersUp) {
            if ($adp.LinkSpeed -match '(\d+)\s*Mbps') {
                $regexMatches = $matches
                if ([int]$regexMatches[1] -lt 1000) { $slowCount++ }
            }
        }
        if ($slowCount -gt 0) {
            $items += @{ Category = "NETWORK"; Name = "Network Adapters"; Value = "$($adaptersUp.Count) up, $slowCount below 1Gbps"; Color = "Warning"; Symbol = "[--]" }
        } else {
            $items += @{ Category = "NETWORK"; Name = "Network Adapters"; Value = "$($adaptersUp.Count) adapter(s) up"; Color = "Success"; Symbol = "[OK]" }
        }
    } else {
        $items += @{ Category = "NETWORK"; Name = "Network Adapters"; Value = "No adapters up"; Color = "Error"; Symbol = "[!!]" }
    }

    # --- SYSTEM ---
    $total++
    $powerPlan = Get-CurrentPowerPlan
    if ($powerPlan.Name -eq "High performance") {
        $ready++
        $items += @{ Category = "SYSTEM"; Name = "Power Plan"; Value = "High Performance"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "SYSTEM"; Name = "Power Plan"; Value = $powerPlan.Name; Color = "Warning"; Symbol = "[--]" }
    }

    $total++
    if (Test-RebootPending) {
        $items += @{ Category = "SYSTEM"; Name = "Reboot Pending"; Value = "YES - reboot needed"; Color = "Error"; Symbol = "[!!]" }
    } else {
        $ready++
        $items += @{ Category = "SYSTEM"; Name = "Reboot Pending"; Value = "No"; Color = "Success"; Symbol = "[OK]" }
    }

    $total++
    $activated = Test-WindowsActivated
    if ($activated) {
        $ready++
        $items += @{ Category = "SYSTEM"; Name = "Windows License"; Value = "Activated"; Color = "Success"; Symbol = "[OK]" }
    } else {
        $items += @{ Category = "SYSTEM"; Name = "Windows License"; Value = "Not Activated"; Color = "Warning"; Symbol = "[--]" }
    }

    # Uptime check - warn if server hasn't rebooted in 30+ days
    $total++
    try {
        $osResult = Invoke-WithTimeout -ScriptBlock { Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue } -TimeoutSeconds 10 -Activity "Checking uptime"
        $osInfo = if ($osResult.TimedOut) { $null } else { $osResult.Result }
        if ($null -ne $osInfo -and $null -ne $osInfo.LastBootUpTime) {
            $uptime = (Get-Date) - $osInfo.LastBootUpTime
            $uptimeDays = [math]::Floor($uptime.TotalDays)
            if ($uptimeDays -gt 60) {
                $items += @{ Category = "SYSTEM"; Name = "Uptime"; Value = "$uptimeDays days (reboot recommended)"; Color = "Error"; Symbol = "[!!]" }
            } elseif ($uptimeDays -gt 30) {
                $items += @{ Category = "SYSTEM"; Name = "Uptime"; Value = "$uptimeDays days"; Color = "Warning"; Symbol = "[--]" }
            } else {
                $ready++
                $items += @{ Category = "SYSTEM"; Name = "Uptime"; Value = "$uptimeDays days"; Color = "Success"; Symbol = "[OK]" }
            }
        } else {
            $ready++
            $items += @{ Category = "SYSTEM"; Name = "Uptime"; Value = "Unknown"; Color = "Info"; Symbol = "[--]" }
        }
    } catch {
        $items += @{ Category = "SYSTEM"; Name = "Uptime"; Value = "Check failed: $_"; Color = "Warning"; Symbol = "[--]" }
    }

    # --- HARDWARE ---
    # Physical disk health check via storage reliability counters
    $total++
    try {
        $physDisks = @(Get-PhysicalDisk -ErrorAction Stop)
        if ($physDisks.Count -eq 0) {
            $items += @{ Category = "HARDWARE"; Name = "Disk Health"; Value = "No physical disks found"; Color = "Warning"; Symbol = "[--]" }
        } else {
            $unhealthy = @($physDisks | Where-Object { $_.HealthStatus -ne "Healthy" })
            $warnDisks = @($physDisks | Where-Object { $_.OperationalStatus -eq "Predictive Failure" })
            if ($unhealthy.Count -gt 0) {
                $items += @{ Category = "HARDWARE"; Name = "Disk Health"; Value = "$($unhealthy.Count)/$($physDisks.Count) disk(s) unhealthy"; Color = "Error"; Symbol = "[!!]" }
            } elseif ($warnDisks.Count -gt 0) {
                $items += @{ Category = "HARDWARE"; Name = "Disk Health"; Value = "$($warnDisks.Count) predictive failure warning(s)"; Color = "Warning"; Symbol = "[--]" }
            } else {
                $ready++
                $items += @{ Category = "HARDWARE"; Name = "Disk Health"; Value = "$($physDisks.Count) disk(s) healthy"; Color = "Success"; Symbol = "[OK]" }
            }
        }
    } catch {
        $items += @{ Category = "HARDWARE"; Name = "Disk Health"; Value = "Check failed: $_"; Color = "Warning"; Symbol = "[--]" }
    }

    # Disk temperature check (Server 2016+ with Get-StorageReliabilityCounter)
    if ($script:IsServer2016OrLater) {
        $total++
        try {
            $hotDisks = @()
            foreach ($pd in @(Get-PhysicalDisk -ErrorAction Stop)) {
                $rel = Get-StorageReliabilityCounter -PhysicalDisk $pd -ErrorAction SilentlyContinue
                if ($null -ne $rel -and $null -ne $rel.Temperature -and $rel.Temperature -gt 55) {
                    $hotDisks += @{ Disk = $pd.FriendlyName; Temp = $rel.Temperature }
                }
            }
            if ($hotDisks.Count -gt 0) {
                $hottest = ($hotDisks | Sort-Object { $_.Temp } -Descending | Select-Object -First 1)
                $items += @{ Category = "HARDWARE"; Name = "Disk Temperature"; Value = "$($hotDisks.Count) disk(s) above 55C (max: $($hottest.Temp)C)"; Color = "Warning"; Symbol = "[--]" }
            } else {
                $ready++
                $items += @{ Category = "HARDWARE"; Name = "Disk Temperature"; Value = "All within normal range"; Color = "Success"; Symbol = "[OK]" }
            }
        } catch {
            $items += @{ Category = "HARDWARE"; Name = "Disk Temperature"; Value = "Check failed: $_"; Color = "Warning"; Symbol = "[--]" }
        }
    }

    # --- SECURITY ---
    # Certificate expiration check - scan LocalMachine\My for certs expiring within 30 days
    $total++
    try {
        $now = Get-Date
        $warnDate = $now.AddDays(30)
        $certs = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.NotAfter -lt $warnDate -and $_.NotAfter -gt $now })
        $expiredCerts = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.NotAfter -le $now })
        if ($expiredCerts.Count -gt 0) {
            $items += @{ Category = "SECURITY"; Name = "Certificates"; Value = "$($expiredCerts.Count) EXPIRED"; Color = "Error"; Symbol = "[!!]" }
        } elseif ($certs.Count -gt 0) {
            $soonest = ($certs | Sort-Object NotAfter | Select-Object -First 1).NotAfter
            $daysLeft = [math]::Floor(($soonest - $now).TotalDays)
            $items += @{ Category = "SECURITY"; Name = "Certificates"; Value = "$($certs.Count) expiring within 30d (next: ${daysLeft}d)"; Color = "Warning"; Symbol = "[--]" }
        } else {
            $ready++
            $allCerts = @(Get-ChildItem -Path Cert:\LocalMachine\My -ErrorAction SilentlyContinue)
            $items += @{ Category = "SECURITY"; Name = "Certificates"; Value = "$($allCerts.Count) cert(s), none expiring soon"; Color = "Success"; Symbol = "[OK]" }
        }
    } catch {
        $items += @{ Category = "SECURITY"; Name = "Certificates"; Value = "Check failed"; Color = "Warning"; Symbol = "[--]" }
    }

    # --- STORAGE ---
    $total++
    try {
        $cVol = Get-Volume -DriveLetter C -ErrorAction Stop
        if ($null -ne $cVol -and $cVol.Size -gt 0) {
            $freeGB = [math]::Round($cVol.SizeRemaining / 1GB, 1)
            $totalGB = [math]::Round($cVol.Size / 1GB, 1)
            $usedPct = [math]::Round((($cVol.Size - $cVol.SizeRemaining) / $cVol.Size) * 100)
            if ($freeGB -lt 5) {
                $items += @{ Category = "STORAGE"; Name = "C: Drive Space"; Value = "${freeGB}GB free of ${totalGB}GB ($usedPct% used)"; Color = "Error"; Symbol = "[!!]" }
            } elseif ($freeGB -lt 20) {
                $items += @{ Category = "STORAGE"; Name = "C: Drive Space"; Value = "${freeGB}GB free of ${totalGB}GB ($usedPct% used)"; Color = "Warning"; Symbol = "[--]" }
            } else {
                $ready++
                $items += @{ Category = "STORAGE"; Name = "C: Drive Space"; Value = "${freeGB}GB free of ${totalGB}GB"; Color = "Success"; Symbol = "[OK]" }
            }
        } else {
            $items += @{ Category = "STORAGE"; Name = "C: Drive Space"; Value = "Unable to read"; Color = "Warning"; Symbol = "[--]" }
        }
    } catch {
        $items += @{ Category = "STORAGE"; Name = "C: Drive Space"; Value = "Check failed: $_"; Color = "Warning"; Symbol = "[--]" }
    }

    # --- DNS RESOLUTION ---
    $total++
    try {
        $dnsResult = Resolve-DnsName -Name "dns.msftncsi.com" -Type A -DnsOnly -ErrorAction Stop
        if ($dnsResult) {
            $ready++
            $items += @{ Category = "NETWORK"; Name = "DNS Resolution"; Value = "Working"; Color = "Success"; Symbol = "[OK]" }
        } else {
            $items += @{ Category = "NETWORK"; Name = "DNS Resolution"; Value = "No response"; Color = "Warning"; Symbol = "[--]" }
        }
    } catch {
        $items += @{ Category = "NETWORK"; Name = "DNS Resolution"; Value = "Failed"; Color = "Error"; Symbol = "[!!]" }
    }

    # --- TIME SYNC ---
    $total++
    try {
        $w32tmOut = w32tm /query /status 2>&1
        $tsSource = "Unknown"
        foreach ($tsLine in $w32tmOut) {
            $tsText = $tsLine.ToString()
            if ($tsText -match 'Source:\s*(.+)') { $regexMatches = $matches; $tsSource = $regexMatches[1].Trim() }
        }
        if ($tsSource -match 'Free-Running|Local CMOS') {
            $items += @{ Category = "SYSTEM"; Name = "Time Sync"; Value = "No external source"; Color = "Warning"; Symbol = "[--]" }
        } else {
            $ready++
            $displaySource = if ($tsSource.Length -gt 35) { $tsSource.Substring(0, 32) + "..." } else { $tsSource }
            $items += @{ Category = "SYSTEM"; Name = "Time Sync"; Value = $displaySource; Color = "Success"; Symbol = "[OK]" }
        }
    } catch {
        $items += @{ Category = "SYSTEM"; Name = "Time Sync"; Value = "Check failed"; Color = "Warning"; Symbol = "[--]" }
    }

    # --- DEFENDER ---
    $total++
    try {
        $mpStat = Get-MpComputerStatus -ErrorAction Stop
        if ($mpStat.RealTimeProtectionEnabled) {
            $ready++
            $items += @{ Category = "SECURITY"; Name = "Defender Real-Time"; Value = "Enabled"; Color = "Success"; Symbol = "[OK]" }
        } else {
            $items += @{ Category = "SECURITY"; Name = "Defender Real-Time"; Value = "DISABLED"; Color = "Error"; Symbol = "[!!]" }
        }
    } catch {
        $items += @{ Category = "SECURITY"; Name = "Defender Real-Time"; Value = "Unavailable"; Color = "Warning"; Symbol = "[--]" }
    }

    # --- RENDER ---
    $currentCategory = ""
    foreach ($item in $items) {
        if ($item.Category -ne $currentCategory) {
            if ($currentCategory -ne "") {
                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                Write-OutputColor "" -color "Info"
            }
            $currentCategory = $item.Category
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  $currentCategory".PadRight(72))│" -color "Info"
            Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        }
        $valStr = $item.Value
        if ($valStr.Length -gt 44) { $valStr = $valStr.Substring(0, 41) + "..." }
        $line = "  $($item.Symbol) $($item.Name):".PadRight(28) + $valStr
        Write-OutputColor "  │$($line.PadRight(72))│" -color $item.Color
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Score
    $pct = if ($total -gt 0) { [math]::Round(($ready / $total) * 100) } else { 0 }
    $scoreColor = if ($pct -ge 80) { "Success" } elseif ($pct -ge 50) { "Warning" } else { "Error" }
    $scoreBar = ("█" * [math]::Floor($pct / 5)).PadRight(20, "░")

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  READINESS SCORE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  $scoreBar  $pct% ($ready/$total checks passed)".PadRight(72))│" -color $scoreColor
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    Add-SessionChange -Category "System" -Description "Ran server readiness check ($ready/$total passed)"
}

# Guided Quick Setup Wizard - walks through essential server configuration steps
function Show-QuickSetupWizard {
    $steps = @(
        @{ Name = "Hostname";  Num = 1; Total = 6 }
        @{ Name = "Domain";    Num = 2; Total = 6 }
        @{ Name = "Agent";     Num = 3; Total = 6 }
        @{ Name = "RDP";       Num = 4; Total = 6 }
        @{ Name = "Power";     Num = 5; Total = 6 }
        @{ Name = "License";   Num = 6; Total = 6 }
    )
    $completed = 0
    $skipped = 0

    Add-SessionChange -Category "System" -Description "Started Quick Setup Wizard"

    # === STEP 1: HOSTNAME ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 1 of 6: HOSTNAME" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $hostname = $env:COMPUTERNAME
    $isDefault = $hostname -match '^WIN-|^DESKTOP-|^YOURSERVERNAME'

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($isDefault) {
        $hostLine = "  Current:  $hostname (DEFAULT - needs configuration)"
        if ($hostLine.Length -gt 72) { $hostLine = $hostLine.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($hostLine.PadRight(72))│" -color "Error"
    } else {
        $hostLine = "  Current:  $hostname"
        if ($hostLine.Length -gt 72) { $hostLine = $hostLine.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($hostLine.PadRight(72))│" -color "Success"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($isDefault) {
        if (Confirm-UserAction -Message "Set hostname now? (Required before agent install)" -DefaultYes) {
            Set-HostName
            $completed++
            if ($global:RebootNeeded) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Hostname change requires a reboot before continuing." -color "Warning"
                Write-OutputColor "  Please reboot and re-run the Quick Setup Wizard." -color "Warning"
                Write-PressEnter
                return
            }
        } else { $skipped++ }
    } else {
        Write-OutputColor "  Hostname is set. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === STEP 2: DOMAIN JOIN ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 2 of 6: DOMAIN JOIN" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $csResult2 = Invoke-WithTimeout -ScriptBlock { Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue } -TimeoutSeconds 10 -Activity "Checking domain"
    $cs = if ($csResult2.TimedOut) { $null } else { $csResult2.Result }
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($cs -and $cs.PartOfDomain) {
        $domLine = "  Current:  Joined to $($cs.Domain)"
        if ($domLine.Length -gt 72) { $domLine = $domLine.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($domLine.PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  Current:  WORKGROUP (not domain-joined)".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not $cs -or -not $cs.PartOfDomain) {
        if (Confirm-UserAction -Message "Join a domain now?") {
            Join-Domain
            $completed++
            if ($global:RebootNeeded) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Domain join requires a reboot before continuing." -color "Warning"
                Write-OutputColor "  Please reboot and re-run the Quick Setup Wizard." -color "Warning"
                Write-PressEnter
                return
            }
        } else { $skipped++ }
    } else {
        Write-OutputColor "  Already domain-joined. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === STEP 3: AGENT ===
    if (Test-AgentInstallerConfigured) {
        Clear-Host
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Step 3 of 6: $($script:AgentInstaller.ToolName.ToUpper()) AGENT" -color "Info"
        Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
        Write-OutputColor "" -color "Info"

        $agentStatus = Test-AgentInstalled
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        if ($agentStatus.Installed) {
            $kVal = if ($agentStatus.Status -eq "Running") { "Installed & Running" } else { "Installed ($($agentStatus.Status))" }
            Write-OutputColor "  │$("  Current:  $kVal".PadRight(72))│" -color "Success"
        } else {
            Write-OutputColor "  │$("  Current:  Not Installed".PadRight(72))│" -color "Warning"
        }
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        if (-not $agentStatus.Installed) {
            if (Confirm-UserAction -Message "Install $($script:AgentInstaller.ToolName) Agent now?") {
                Install-Agent -ReturnAfterInstall
                $completed++
            } else { $skipped++ }
        } else {
            Write-OutputColor "  $($script:AgentInstaller.ToolName) is installed. Skipping." -color "Success"
            $completed++
            Start-Sleep -Milliseconds 500
        }
    } else { $skipped++ }

    # === STEP 4: RDP ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 4 of 6: REMOTE DESKTOP (RDP)" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $rdpState = Get-RDPState
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($rdpState -eq "Enabled") {
        Write-OutputColor "  │$("  Current:  RDP Enabled".PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  Current:  RDP Disabled".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($rdpState -ne "Enabled") {
        if (Confirm-UserAction -Message "Enable RDP now?" -DefaultYes) {
            Enable-RDP
            $completed++
        } else { $skipped++ }
    } else {
        Write-OutputColor "  RDP is enabled. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === STEP 5: POWER PLAN ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 5 of 6: POWER PLAN" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $powerPlan = Get-CurrentPowerPlan
    $powerPlanName = if ($null -ne $powerPlan) { $powerPlan.Name } else { "Unknown" }
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($powerPlanName -eq "High performance") {
        Write-OutputColor "  │$("  Current:  High Performance".PadRight(72))│" -color "Success"
    } else {
        $ppLine = "  Current:  $powerPlanName"
        if ($ppLine.Length -gt 72) { $ppLine = $ppLine.Substring(0, 69) + "..." }
        Write-OutputColor "  │$($ppLine.PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($powerPlanName -ne "High performance") {
        if (Confirm-UserAction -Message "Set power plan to High Performance?" -DefaultYes) {
            Set-ServerPowerPlan
            $completed++
        } else { $skipped++ }
    } else {
        Write-OutputColor "  Power plan is High Performance. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === STEP 6: LICENSING ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        QUICK SETUP WIZARD").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Step 6 of 6: WINDOWS LICENSING" -color "Info"
    Write-OutputColor "  ────────────────────────────────────────────" -color "Info"
    Write-OutputColor "" -color "Info"

    $activated = Test-WindowsActivated
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    if ($activated) {
        Write-OutputColor "  │$("  Current:  Windows is Activated".PadRight(72))│" -color "Success"
    } else {
        Write-OutputColor "  │$("  Current:  Not Activated".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if (-not $activated) {
        if (Confirm-UserAction -Message "Configure Windows licensing now?") {
            Register-ServerLicense
            $completed++
        } else { $skipped++ }
    } else {
        Write-OutputColor "  Windows is activated. Skipping." -color "Success"
        $completed++
        Start-Sleep -Milliseconds 500
    }

    # === SUMMARY ===
    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     QUICK SETUP - COMPLETE").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  RESULTS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Completed:  $completed of 6 steps".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Skipped:    $skipped of 6 steps".PadRight(72))│" -color $(if ($skipped -gt 0) { "Warning" } else { "Success" })
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    if ($global:RebootNeeded) {
        Write-OutputColor "  A reboot is required to finalize changes." -color "Warning"
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Reboot now?") {
            Add-SessionChange -Category "System" -Description "Quick Setup Wizard rebooting ($completed completed, $skipped skipped)"
            Restart-Computer -Force
        }
    }

    Add-SessionChange -Category "System" -Description "Quick Setup Wizard finished ($completed completed, $skipped skipped)"
    Clear-MenuCache
}

# Server Role Templates - guided checklists for common server configurations
function Show-RoleTemplates {
    Clear-Host
    Write-CenteredOutput "Server Role Templates" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Select a server role to see its configuration checklist:" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [1] Hyper-V Host" -color "Success"
    Write-OutputColor "      Hyper-V, MPIO, iSCSI, SET Teaming, High Performance" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [2] Standalone Server" -color "Success"
    Write-OutputColor "      Hostname, Domain, RDP, $($script:AgentInstaller.ToolName), License, Power Plan" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [3] Cluster Node" -color "Success"
    Write-OutputColor "      All of Hyper-V Host + Failover Clustering + Domain" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) {
        if (Invoke-NavigationAction -NavResult $navResult) { return }
    }

    $templateName = $null
    $checks = @()

    switch ($choice) {
        "1" {
            $templateName = "HYPER-V HOST"
            $checks = @(
                @{ Name = "Hostname Set";              Test = { $env:COMPUTERNAME -notmatch '^WIN-|^DESKTOP-|^YOURSERVERNAME' }; Action = "Set-HostName"; Category = "Identity" }
                @{ Name = "Domain Joined";             Test = { (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain }; Action = "Join-Domain"; Category = "Identity" }
                @{ Name = "RDP Enabled";               Test = { (Get-RDPState) -eq "Enabled" }; Action = "Enable-RDP"; Category = "Access" }
                @{ Name = "High Performance Power";    Test = { (Get-CurrentPowerPlan).Name -match "High" }; Action = "Set-ServerPowerPlan"; Category = "System" }
                @{ Name = "Hyper-V Installed";         Test = { Test-HyperVInstalled }; Action = "Install-HyperVRole"; Category = "Roles" }
                @{ Name = "MPIO Installed";            Test = { Test-MPIOInstalled }; Action = "Install-MPIOFeature"; Category = "Roles" }
                @{ Name = "Windows Licensed";          Test = { Test-WindowsActivated }; Action = "Register-ServerLicense"; Category = "System" }
            )
            if (Test-AgentInstallerConfigured) { $checks += @{ Name = "$($script:AgentInstaller.ToolName) Agent"; Test = { (Test-AgentInstalled).Installed }; Action = "Install-Agent"; Category = "Software" } }
        }
        "2" {
            $templateName = "STANDALONE SERVER"
            $checks = @(
                @{ Name = "Hostname Set";              Test = { $env:COMPUTERNAME -notmatch '^WIN-|^DESKTOP-|^YOURSERVERNAME' }; Action = "Set-HostName"; Category = "Identity" }
                @{ Name = "Domain Joined";             Test = { (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain }; Action = "Join-Domain"; Category = "Identity" }
                @{ Name = "RDP Enabled";               Test = { (Get-RDPState) -eq "Enabled" }; Action = "Enable-RDP"; Category = "Access" }
                @{ Name = "WinRM Enabled";             Test = { (Get-WinRMState) -match "Enabled|Running" }; Action = "Enable-PSRemoting"; Category = "Access" }
                @{ Name = "High Performance Power";    Test = { (Get-CurrentPowerPlan).Name -match "High" }; Action = "Set-ServerPowerPlan"; Category = "System" }
                @{ Name = "Windows Licensed";          Test = { Test-WindowsActivated }; Action = "Register-ServerLicense"; Category = "System" }
            )
            if (Test-AgentInstallerConfigured) { $checks += @{ Name = "$($script:AgentInstaller.ToolName) Agent"; Test = { (Test-AgentInstalled).Installed }; Action = "Install-Agent"; Category = "Software" } }
        }
        "3" {
            $templateName = "CLUSTER NODE"
            $checks = @(
                @{ Name = "Hostname Set";              Test = { $env:COMPUTERNAME -notmatch '^WIN-|^DESKTOP-|^YOURSERVERNAME' }; Action = "Set-HostName"; Category = "Identity" }
                @{ Name = "Domain Joined";             Test = { (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).PartOfDomain }; Action = "Join-Domain"; Category = "Identity" }
                @{ Name = "RDP Enabled";               Test = { (Get-RDPState) -eq "Enabled" }; Action = "Enable-RDP"; Category = "Access" }
                @{ Name = "High Performance Power";    Test = { (Get-CurrentPowerPlan).Name -match "High" }; Action = "Set-ServerPowerPlan"; Category = "System" }
                @{ Name = "Hyper-V Installed";         Test = { Test-HyperVInstalled }; Action = "Install-HyperVRole"; Category = "Roles" }
                @{ Name = "MPIO Installed";            Test = { Test-MPIOInstalled }; Action = "Install-MPIOFeature"; Category = "Roles" }
                @{ Name = "Failover Clustering";       Test = { Test-FailoverClusteringInstalled }; Action = "Install-FailoverClusteringFeature"; Category = "Roles" }
                @{ Name = "Windows Licensed";          Test = { Test-WindowsActivated }; Action = "Register-ServerLicense"; Category = "System" }
            )
            if (Test-AgentInstallerConfigured) { $checks += @{ Name = "$($script:AgentInstaller.ToolName) Agent"; Test = { (Test-AgentInstalled).Installed }; Action = "Install-Agent"; Category = "Software" } }
        }
        default {
            Write-OutputColor "  Invalid selection. Enter 1-3 or B." -color "Warning"
            return
        }
    }

    # Display checklist with live status
    Clear-Host
    Write-CenteredOutput "Role Template: $templateName" -color "Info"
    Write-OutputColor "" -color "Info"

    $passed = 0
    $total = $checks.Count
    $results = @()

    foreach ($check in $checks) {
        $status = $false
        try { $status = & $check.Test } catch { Write-OutputColor "  [!!] $($check.Name): check failed ($_)" -color "Debug" }
        $icon = if ($status) { "[OK]" } else { "[--]" }
        $color = if ($status) { "Success" } else { "Warning" }
        if ($status) { $passed++ }
        Write-OutputColor "  $icon $($check.Name)" -color $color
        $results += @{ Check = $check; Passed = $status }
    }

    $pct = if ($total -gt 0) { [math]::Round(($passed / $total) * 100) } else { 0 }
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Score: $passed/$total ($pct%)" -color $(if ($pct -ge 80) { "Success" } elseif ($pct -ge 50) { "Warning" } else { "Error" })
    Write-OutputColor "" -color "Info"

    # Offer to configure missing items
    $missing = @($results | Where-Object { -not $_.Passed })
    if ($missing.Count -eq 0) {
        Write-OutputColor "  All checks passed! Server is fully configured for $templateName." -color "Success"
        return
    }

    Write-OutputColor "  $($missing.Count) item(s) need attention." -color "Warning"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  [A] Auto-configure all missing items (guided)" -color "Success"
    Write-OutputColor "  [B] ◄ Back" -color "Info"
    Write-OutputColor "" -color "Info"

    $action = Read-Host "  Select"
    $navResult = Test-NavigationCommand -UserInput $action
    if ($navResult.ShouldReturn) { return }

    if ($action -ne "A" -and $action -ne "a") { return }

    # Run guided setup for missing items
    $stepNum = 0
    foreach ($item in $missing) {
        $stepNum++
        $check = $item.Check
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  --- Step $stepNum of $($missing.Count): $($check.Name) ---" -color "Info"

        if (Confirm-UserAction -Message "Configure $($check.Name) now?") {
            try {
                & $check.Action
                Write-PressEnter

                # Recheck
                $nowPassed = $false
                try { $nowPassed = & $check.Test } catch { Write-OutputColor "  [!!] $($check.Name): recheck failed ($_)" -color "Debug" }
                if ($nowPassed) {
                    Write-OutputColor "  $($check.Name): Configured successfully!" -color "Success"
                }
                else {
                    Write-OutputColor "  $($check.Name): May need a reboot or manual verification." -color "Warning"
                }

                # If reboot needed, offer to stop
                if ($global:RebootNeeded) {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "  A reboot is needed. Remaining items will be available after restart." -color "Warning"
                    Add-SessionChange -Category "System" -Description "Role template $templateName paused at step $stepNum (reboot needed)"
                    Clear-MenuCache
                    return
                }
            }
            catch {
                Write-OutputColor "  Error configuring $($check.Name): $_" -color "Error"
            }
        }
        else {
            Write-OutputColor "  Skipped: $($check.Name)" -color "Info"
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Role template $templateName setup complete!" -color "Success"
    Add-SessionChange -Category "System" -Description "Completed role template: $templateName"
    Clear-MenuCache
    Write-PressEnter
}
#endregion