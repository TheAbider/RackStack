#region ===== CERTIFICATE BINDING AUDIT =====
# Read-only audit of the certificates bound to this host's service listeners.
# Unlike the generic certificate-expiry check, this is binding-aware: it reports
# WHICH certificate is actually presented by the RDP-Tcp listener and the WinRM
# HTTPS listener, with subject and days-to-expiry, so you can spot a binding that
# is about to expire before clients start seeing TLS warnings or failures.
#
# Automated rotation is intentionally NOT performed here. Re-binding the RDP
# listener safely requires the target certificate's private key to be readable by
# the RDP service account (NETWORK SERVICE) — a freshly generated self-signed cert
# is not, by default, which would break RDP TLS and can lock an administrator out
# of the only remote-access path. Doing that correctly (private-key ACL grant +
# the documented WMI set path) needs validation on a live, elevated, RDP-enabled
# server, so rotation is deferred to a future release rather than shipped untested.
# For now this module surfaces the bindings so you know exactly what to rotate
# manually (Remote Desktop Session Host Configuration, or certlm.msc + the RDP
# WMI method) and when.

# A SHA-1 certificate thumbprint is exactly 40 hex characters. Thumbprints read
# from the listeners are validated against this before being used as a cert-store
# path, so a malformed value can never reach a provider path.
function Test-CertThumbprint {
    param([string]$Thumbprint)
    return ($Thumbprint -and $Thumbprint -match '^[0-9A-Fa-f]{40}$')
}

# Resolve a thumbprint to a friendly one-line summary from LocalMachine\My.
function Get-CertSummaryByThumbprint {
    param([string]$Thumbprint)
    if (-not (Test-CertThumbprint -Thumbprint $Thumbprint)) { return $null }
    $cert = Get-Item -Path ("Cert:\LocalMachine\My\{0}" -f $Thumbprint.ToUpper()) -ErrorAction SilentlyContinue
    if (-not $cert) { return $null }
    $days = [int]([math]::Floor(($cert.NotAfter - (Get-Date)).TotalDays))
    return [PSCustomObject]@{
        Thumbprint    = $cert.Thumbprint
        Subject       = $cert.Subject
        NotAfter      = $cert.NotAfter
        DaysLeft      = $days
        HasPrivateKey = [bool]$cert.HasPrivateKey
    }
}

# Read-only: which certificate is bound to the RDP-Tcp listener and to the WinRM
# HTTPS listener, with expiry. Makes no changes.
function Get-ServiceCertificateBindings {
    $result = [PSCustomObject]@{
        Available       = $true
        RDPThumbprint   = $null
        RDPCert         = $null
        WinRMThumbprint = $null
        WinRMCert       = $null
    }
    # RDP-Tcp listener certificate (TerminalServices CIM).
    try {
        $ts = Get-CimInstance -Namespace 'root\cimv2\TerminalServices' -ClassName Win32_TSGeneralSetting -Filter "TerminalName='RDP-Tcp'" -ErrorAction Stop
        if ($ts -and $ts.SSLCertificateSHA1Hash) {
            $result.RDPThumbprint = "$($ts.SSLCertificateSHA1Hash)"
            $result.RDPCert = Get-CertSummaryByThumbprint -Thumbprint $result.RDPThumbprint
        }
    } catch {}
    # WinRM HTTPS listener certificate (WSMan provider) — read-only.
    try {
        $listeners = Get-ChildItem -Path 'WSMan:\localhost\Listener\*' -ErrorAction SilentlyContinue
        foreach ($l in $listeners) {
            $props = Get-ChildItem -Path $l.PSPath -ErrorAction SilentlyContinue
            $transport = ($props | Where-Object { $_.Name -eq 'Transport' }).Value
            if ($transport -eq 'HTTPS') {
                $tp = ($props | Where-Object { $_.Name -eq 'CertificateThumbprint' }).Value
                if ($tp) { $result.WinRMThumbprint = "$tp"; $result.WinRMCert = Get-CertSummaryByThumbprint -Thumbprint "$tp" }
            }
        }
    } catch {}
    return $result
}

# Render a one-line binding row with expiry colouring.
function Write-CertBindingRow {
    param([string]$Label, $Cert, [string]$RawThumbprint)
    if ($Cert) {
        $c = if ($Cert.DaysLeft -lt 0) { "Error" } elseif ($Cert.DaysLeft -lt 30) { "Warning" } else { "Success" }
        $pk = if ($Cert.HasPrivateKey) { "" } else { " [no private key]" }
        Write-OutputColor "  │$("  $Label : $($Cert.Subject) ($($Cert.DaysLeft)d left)$pk".PadRight(72))│" -color $c
    } elseif ($RawThumbprint) {
        Write-OutputColor "  │$("  $Label : bound to $RawThumbprint (cert not in store)".PadRight(72))│" -color "Warning"
    } else {
        Write-OutputColor "  │$("  $Label : no certificate bound".PadRight(72))│" -color "Info"
    }
}

# Read-only display of the service certificate bindings.
function Show-CertificateBindings {
    Clear-Host
    Write-CenteredOutput "Certificate Binding Audit" -color "Info"
    $b = Get-ServiceCertificateBindings
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SERVICE CERTIFICATE BINDINGS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-CertBindingRow -Label "RDP-Tcp" -Cert $b.RDPCert -RawThumbprint $b.RDPThumbprint
    Write-CertBindingRow -Label "WinRM  " -Cert $b.WinRMCert -RawThumbprint $b.WinRMThumbprint
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Read-only audit. To rotate a binding, replace the certificate manually and" -color "Info"
    Write-OutputColor "  re-point the listener (RDS Session Host config / certlm.msc). Automated" -color "Info"
    Write-OutputColor "  rotation is deferred until it can be validated against a live RDP server" -color "Info"
    Write-OutputColor "  without risking lock-out from private-key permissions." -color "Info"
    Write-PressEnter
}

# CLI: CertBindingAudit — read-only service-certificate binding posture (JSON-aware).
function Start-CertBindingAudit {
    $b = Get-ServiceCertificateBindings
    if ($script:CLIOutputFormat -eq 'JSON') {
        Write-Output (@{
            Tool = $script:ToolFullName; Version = $script:ScriptVersion; Action = 'CertBindingAudit'
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss"); Hostname = $env:COMPUTERNAME
            RDPThumbprint = $b.RDPThumbprint
            RDPSubject = $(if ($b.RDPCert) { $b.RDPCert.Subject } else { $null })
            RDPDaysLeft = $(if ($b.RDPCert) { $b.RDPCert.DaysLeft } else { $null })
            RDPHasPrivateKey = $(if ($b.RDPCert) { $b.RDPCert.HasPrivateKey } else { $null })
            WinRMThumbprint = $b.WinRMThumbprint
            WinRMSubject = $(if ($b.WinRMCert) { $b.WinRMCert.Subject } else { $null })
            WinRMDaysLeft = $(if ($b.WinRMCert) { $b.WinRMCert.DaysLeft } else { $null })
        } | ConvertTo-Json)
    }
    else { Show-CertificateBindings }
    return $true
}
#endregion
