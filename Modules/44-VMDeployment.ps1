#region ===== VM DEPLOYMENT =====
# Global VM deployment session variables
$script:VMDeploymentMode = $null        # "Standalone" or "Cluster"
$script:VMDeploymentTarget = $null       # Computer name or cluster name
$script:VMDeploymentCredential = $null   # Credentials if needed
$script:VMDeploymentSiteNumber = $null   # Site number (e.g., "123456")
$script:VMDeploymentConnected = $false   # Connection status

# Standard VM templates (generic built-ins; override or add more via CustomVMTemplates in defaults.json)
$script:StandardVMTemplates = @{
    "DC" = @{
        FullName = "Domain Controller"
        Prefix = "DC"
        OSType = "Windows"
        SortOrder = 1
        vCPU = 4
        MemoryGB = 8
        MemoryType = "Dynamic"
        Disks = @(
            @{ Name = "OS"; SizeGB = 100; Type = "Fixed" }
        )
        NICs = 1
        GuestServices = $true
        TimeSyncWithHost = $false
        Notes = "Domain Controller"
    }
    "FS" = @{
        FullName = "File Server"
        Prefix = "FS"
        OSType = "Windows"
        SortOrder = 2
        vCPU = 4
        MemoryGB = 8
        MemoryType = "Dynamic"
        Disks = @(
            @{ Name = "OS";   SizeGB = 100; Type = "Fixed" }
            @{ Name = "Data"; SizeGB = 200; Type = "Fixed" }
        )
        NICs = 1
        GuestServices = $true
        TimeSyncWithHost = $true
        Notes = "File Server"
    }
    "WEB" = @{
        FullName = "Web Server"
        Prefix = "WEB"
        OSType = "Windows"
        SortOrder = 3
        vCPU = 4
        MemoryGB = 8
        MemoryType = "Dynamic"
        Disks = @(
            @{ Name = "OS"; SizeGB = 100; Type = "Fixed" }
        )
        NICs = 1
        GuestServices = $true
        TimeSyncWithHost = $true
        Notes = "Web Server (IIS)"
    }
}

# Function to extract site identifier from hostname using configurable regex ($script:VMNaming.SiteIdRegex)
# NOTE: Primary definition is in Agent Installer section - this is kept for backward compatibility
# with callers that pass a hostname explicitly
function Get-SiteNumberFromHostnameParam {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname
    )

    # Use configurable regex from VMNaming settings
    $pattern = $script:VMNaming.SiteIdRegex
    if ($Hostname -match $pattern) {
        $regexMatches = $matches
        return $regexMatches[1]
    }
    # Fallback: any sequence of 3+ digits
    if ($Hostname -match '(\d{3,})') {
        $regexMatches = $matches
        return $regexMatches[1]
    }

    return $null
}

# Function to test Hyper-V connectivity
function Test-HyperVConnection {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [PSCredential]$Credential = $null
    )

    try {
        $params = @{
            ComputerName = $ComputerName
            ErrorAction = "Stop"
        }

        if ($Credential) {
            $params.Credential = $Credential
        }

        # Try to get VM host info
        $vmHost = Get-VMHost @params

        if ($vmHost) {
            return @{
                Success = $true
                HostName = $vmHost.ComputerName
                VirtualHardDiskPath = $vmHost.VirtualHardDiskPath
                VirtualMachinePath = $vmHost.VirtualMachinePath
                Message = "Connected successfully"
            }
        }
    }
    catch {
        return @{
            Success = $false
            HostName = $null
            Message = $_.Exception.Message
        }
    }

    return @{
        Success = $false
        HostName = $null
        Message = "Unknown error"
    }
}

# Function to test Failover Cluster connectivity
function Test-ClusterConnection {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$ClusterName
    )

    try {
        $params = @{
            Name = $ClusterName
            ErrorAction = "Stop"
        }

        # Note: Get-Cluster doesn't support -Credential directly, uses current session
        $cluster = Get-Cluster @params

        if ($cluster) {
            # Get cluster nodes
            $nodes = @(Get-ClusterNode -Cluster $cluster.Name -ErrorAction SilentlyContinue)

            return @{
                Success = $true
                ClusterName = $cluster.Name
                Nodes = $nodes.Name
                NodeCount = $nodes.Count
                Message = "Connected successfully"
            }
        }
    }
    catch {
        return @{
            Success = $false
            ClusterName = $null
            Message = $_.Exception.Message
        }
    }

    return @{
        Success = $false
        ClusterName = $null
        Message = "Unknown error"
    }
}

# Function to detect local cluster
function Find-LocalCluster {
    try {
        # Check if this machine is part of a cluster
        $cluster = Get-Cluster -ErrorAction SilentlyContinue

        if ($cluster) {
            return @{
                Found = $true
                ClusterName = $cluster.Name
            }
        }
    }
    catch {
        # Not in a cluster
    }

    return @{
        Found = $false
        ClusterName = $null
    }
}

# Function to check if VM name exists
function Test-VMNameExists {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName,

        [string]$ComputerName = $null,

        [string]$ClusterName = $null,

        [PSCredential]$Credential = $null
    )

    try {
        if ($ClusterName) {
            # Check across all cluster nodes
            $clusterNodes = Get-ClusterNode -Cluster $ClusterName -ErrorAction SilentlyContinue
            foreach ($node in $clusterNodes) {
                $params = @{
                    ComputerName = $node.Name
                    Name = $VMName
                    ErrorAction = "SilentlyContinue"
                }
                if ($Credential) { $params.Credential = $Credential }

                $vm = Get-VM @params
                if ($vm) {
                    return @{
                        Exists = $true
                        Location = $node.Name
                        VM = $vm
                    }
                }
            }
        }
        else {
            $params = @{
                Name = $VMName
                ErrorAction = "SilentlyContinue"
            }
            if ($ComputerName) { $params.ComputerName = $ComputerName }
            if ($Credential) { $params.Credential = $Credential }

            $vm = Get-VM @params
            if ($vm) {
                return @{
                    Exists = $true
                    Location = if ($ComputerName) { $ComputerName } else { $env:COMPUTERNAME }
                    VM = $vm
                }
            }
        }
    }
    catch {
        # Error checking - assume doesn't exist
    }

    return @{
        Exists = $false
        Location = $null
        VM = $null
    }
}

# Function to check DNS for VM name
function Test-VMNameInDNS {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$VMName
    )

    try {
        $dnsResult = Resolve-DnsName -Name $VMName -ErrorAction SilentlyContinue
        if ($dnsResult) {
            return @{
                Exists = $true
                IPAddress = ($dnsResult | Where-Object { $_.Type -eq "A" }).IPAddress
            }
        }
    }
    catch {
        # DNS lookup failed - name doesn't exist
    }

    return @{
        Exists = $false
        IPAddress = $null
    }
}

# Function to suggest next available VM name
function Get-NextAvailableVMName {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$SiteNumber,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix,

        [string]$ComputerName = $null,

        [string]$ClusterName = $null,

        [PSCredential]$Credential = $null
    )

    $counter = 1
    $maxAttempts = 99

    # Resolve naming pattern from VMNaming config
    $namePattern = $script:VMNaming.Pattern
    $seqFormat = ""
    # Extract Seq format if specified: {Seq:00} -> "00" format string
    if ($namePattern -match '\{Seq:([^}]+)\}') {
        $regexMatches = $matches
        $seqFormat = $regexMatches[1]
        $namePattern = $namePattern -replace '\{Seq:[^}]+\}', '{Seq}'
    }

    while ($counter -le $maxAttempts) {
        $seqStr = if ($seqFormat) { $counter.ToString($seqFormat) } else { "$counter" }
        $proposedName = $namePattern -replace '\{Site\}', $SiteNumber `
                                     -replace '\{Prefix\}', $Prefix `
                                     -replace '\{Seq\}', $seqStr

        # Check if VM exists on host/cluster
        $vmCheck = Test-VMNameExists -VMName $proposedName -ComputerName $ComputerName -ClusterName $ClusterName -Credential $Credential

        if (-not $vmCheck.Exists) {
            # Also check DNS
            $dnsCheck = Test-VMNameInDNS -VMName $proposedName

            if (-not $dnsCheck.Exists) {
                return @{
                    Name = $proposedName
                    Number = $counter
                    Available = $true
                }
            }
        }

        $counter++
    }

    # Build final fallback name using same pattern
    $seqStr = if ($seqFormat) { $maxAttempts.ToString($seqFormat) } else { "$maxAttempts" }
    $fallbackName = $namePattern -replace '\{Site\}', $SiteNumber `
                                 -replace '\{Prefix\}', $Prefix `
                                 -replace '\{Seq\}', $seqStr
    return @{
        Name = $fallbackName
        Number = $maxAttempts
        Available = $false
    }
}

# Function to get available virtual switches
function Get-AvailableVirtualSwitches {
    param (
        [string]$ComputerName = $null,
        [PSCredential]$Credential = $null
    )

    try {
        $params = @{
            ErrorAction = "Stop"
        }
        if ($ComputerName) { $params.ComputerName = $ComputerName }
        if ($Credential) { $params.Credential = $Credential }

        $switches = Get-VMSwitch @params
        return $switches
    }
    catch {
        return @()
    }
}

# Function to get available storage paths
function Get-AvailableVMStoragePaths {
    param (
        [string]$ComputerName = $null,
        [PSCredential]$Credential = $null
    )

    try {
        $params = @{
            ErrorAction = "Stop"
        }
        if ($ComputerName) { $params.ComputerName = $ComputerName }
        if ($Credential) { $params.Credential = $Credential }

        $vmHost = Get-VMHost @params

        $paths = @{
            DefaultVHDPath = $vmHost.VirtualHardDiskPath
            DefaultVMPath = $vmHost.VirtualMachinePath
        }

        # For clusters, also check for Cluster Shared Volumes
        if ($script:VMDeploymentMode -eq "Cluster") {
            $csvs = Get-ClusterSharedVolume -Cluster $script:VMDeploymentTarget -ErrorAction SilentlyContinue
            if ($csvs) {
                $paths.CSVPaths = $csvs | ForEach-Object {
                    $_.SharedVolumeInfo.FriendlyVolumeName
                }
            }
        }

        return $paths
    }
    catch {
        return @{
            DefaultVHDPath = "C:\Hyper-V\Virtual Hard Disks"
            DefaultVMPath = "C:\Hyper-V"
        }
    }
}

# Function to show deployment mode selection
function Show-VMDeploymentModeMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      DEPLOY VIRTUAL MACHINES").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SELECT DEPLOYMENT MODE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │                                                                        │" -color "Info"
    Write-OutputColor "  │   [1]  Standalone Host                                                 │" -color "Success"
    Write-OutputColor "  │        Deploy VMs to a single Hyper-V host                             │" -color "Info"
    Write-OutputColor "  │                                                                        │" -color "Info"
    Write-OutputColor "  │   [2]  Failover Cluster                                                │" -color "Success"
    Write-OutputColor "  │        Deploy VMs to a Hyper-V failover cluster                        │" -color "Info"
    Write-OutputColor "  │                                                                        │" -color "Info"
    Write-OutputColor "  │   [3]  ◄ Back                                                          │" -color "Info"
    Write-OutputColor "  │                                                                        │" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return "3" }

    return $choice
}

# Function to connect to standalone host
function Connect-StandaloneHost {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     CONNECT TO HYPER-V HOST").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │   [1]  Local (this server)                                             │" -color "Success"
    Write-OutputColor "  │   [2]  Remote server                                                   │" -color "Success"
    Write-OutputColor "  │   [3]  ◄ Back                                                          │" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    switch ($choice) {
        "1" {
            # Local connection
            Write-OutputColor "" -color "Info"
            Write-OutputColor "Testing local Hyper-V connection..." -color "Info"

            $result = Test-HyperVConnection -ComputerName "localhost"

            if ($result.Success) {
                $script:VMDeploymentMode = "Standalone"
                $script:VMDeploymentTarget = $env:COMPUTERNAME
                $script:VMDeploymentCredential = $null
                $script:VMDeploymentConnected = $true

                Write-OutputColor "Connected to local Hyper-V host: $env:COMPUTERNAME" -color "Success"
                Write-OutputColor "Default VHD Path: $($result.VirtualHardDiskPath)" -color "Info"
                Write-OutputColor "Default VM Path: $($result.VirtualMachinePath)" -color "Info"
                return $true
            }
            else {
                Write-OutputColor "Failed to connect: $($result.Message)" -color "Error"
                Write-OutputColor "" -color "Info"
                Write-OutputColor "Make sure Hyper-V is installed on this server." -color "Warning"
                return $false
            }
        }
        "2" {
            # Remote connection
            Write-OutputColor "" -color "Info"
            $remoteHost = Read-Host "Enter remote server name or IP"

            if ([string]::IsNullOrWhiteSpace($remoteHost)) {
                Write-OutputColor "No server specified." -color "Warning"
                return $false
            }

            Write-OutputColor "" -color "Info"
            Write-OutputColor "Attempting connection with current credentials..." -color "Info"

            $result = Test-HyperVConnection -ComputerName $remoteHost

            if ($result.Success) {
                $script:VMDeploymentMode = "Standalone"
                $script:VMDeploymentTarget = $result.HostName
                $script:VMDeploymentCredential = $null
                $script:VMDeploymentConnected = $true

                Write-OutputColor "Connected to: $($result.HostName)" -color "Success"
                return $true
            }
            else {
                Write-OutputColor "Connection failed with current credentials." -color "Warning"
                Write-OutputColor "Error: $($result.Message)" -color "Info"
                Write-OutputColor "" -color "Info"

                if (Confirm-UserAction -Message "Try with different credentials?") {
                    Write-OutputColor "" -color "Info"
                    Write-OutputColor "Enter credentials for remote server:" -color "Info"

                    try {
                        $cred = Get-Credential -Message "Enter credentials for $remoteHost"

                        if ($cred) {
                            $result = Test-HyperVConnection -ComputerName $remoteHost -Credential $cred

                            if ($result.Success) {
                                $script:VMDeploymentMode = "Standalone"
                                $script:VMDeploymentTarget = $result.HostName
                                $script:VMDeploymentCredential = $cred
                                $script:VMDeploymentConnected = $true

                                Write-OutputColor "Connected to: $($result.HostName)" -color "Success"
                                return $true
                            }
                            else {
                                Write-OutputColor "Connection failed: $($result.Message)" -color "Error"
                            }
                        }
                    }
                    catch {
                        Write-OutputColor "Credential error: $_" -color "Error"
                    }
                }

                return $false
            }
        }
        "3" {
            return $false
        }
        default {
            Write-OutputColor "Invalid choice." -color "Error"
            return $false
        }
    }
}

# Function to connect to cluster
function Connect-FailoverCluster {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     CONNECT TO FAILOVER CLUSTER").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  NOTE: Your domain account must be a local administrator on ALL" -color "Warning"
    Write-OutputColor "        cluster nodes to deploy and manage VMs." -color "Warning"
    Write-OutputColor "" -color "Info"

    # Build list of discovered clusters
    $clusterOptions = @()

    # Check if this server is part of a cluster
    $localCluster = Find-LocalCluster
    if ($localCluster.Found) {
        $clusterOptions += @{
            Name = $localCluster.ClusterName
            Source = "Local (this server is a member)"
        }
    }

    # Try to discover clusters in the domain via AD
    try {
        $clusterCNOs = Get-ADComputer -Filter 'ServicePrincipalName -like "MSClusterVirtualServer/*"' -Properties ServicePrincipalName -ErrorAction SilentlyContinue
        if ($clusterCNOs) {
            foreach ($cno in $clusterCNOs) {
                $cnoName = $cno.Name
                # Skip if already in list (local cluster)
                if ($clusterOptions | Where-Object { $_.Name -eq $cnoName }) { continue }
                $clusterOptions += @{
                    Name = $cnoName
                    Source = "Discovered via Active Directory"
                }
            }
        }
    }
    catch {
        # AD query failed - not on domain or no permissions, that's fine
    }

    # Display discovered clusters
    if ($clusterOptions.Count -gt 0) {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DISCOVERED CLUSTERS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $index = 1
        foreach ($cluster in $clusterOptions) {
            $clusterLine = "  │   [$index]  $($cluster.Name)  ($($cluster.Source))"
            Write-OutputColor "$($clusterLine.PadRight(75))│" -color "Success"
            $index++
        }

        Write-OutputColor "  │                                                                        │" -color "Info"
        $manualIndex = $index
        $manualLine = "  │   [$manualIndex]  Enter cluster name manually"
        Write-OutputColor "$($manualLine.PadRight(75))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "   [0] ◄ Back" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        if ($choice -eq "0") {
            return $false
        }

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return $false }

        if ($choice -match '^\d+$') {
            $choiceNum = [int]$choice
            if ($choiceNum -ge 1 -and $choiceNum -le $clusterOptions.Count) {
                $clusterName = $clusterOptions[$choiceNum - 1].Name
            }
            elseif ($choiceNum -eq $manualIndex) {
                # Fall through to manual entry below
                $clusterName = $null
            }
            else {
                Write-OutputColor "  Invalid choice." -color "Error"
                return $false
            }
        }
        else {
            Write-OutputColor "  Invalid choice." -color "Error"
            return $false
        }
    }
    else {
        # No clusters discovered
        $clusterName = $null
    }

    # Manual entry if needed
    if (-not $clusterName) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Enter cluster name (or 'back' to cancel):" -color "Info"
        $clusterName = Read-Host "  "

        $navResult = Test-NavigationCommand -UserInput $clusterName
        if ($navResult.ShouldReturn) {
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($clusterName)) {
            Write-OutputColor "  No cluster specified." -color "Warning"
            return $false
        }
    }

    # Attempt connection
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Connecting to cluster '$clusterName'..." -color "Info"

    $result = Test-ClusterConnection -ClusterName $clusterName

    if ($result.Success) {
        $script:VMDeploymentMode = "Cluster"
        $script:VMDeploymentTarget = $result.ClusterName
        $script:VMDeploymentCredential = $null
        $script:VMDeploymentConnected = $true

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  Connected to cluster: $($result.ClusterName)" -color "Success"
        Write-OutputColor "  Cluster nodes ($($result.NodeCount)):" -color "Info"
        foreach ($node in $result.Nodes) {
            Write-OutputColor "    - $node" -color "Info"
        }
        return $true
    }
    else {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Error"
        Write-OutputColor "  │$("  CONNECTION FAILED".PadRight(72))│" -color "Error"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $errorLine = "  │  $($result.Message)"
        if ($errorLine.Length -gt 74) { $errorLine = $errorLine.Substring(0, 71) + "..." }
        Write-OutputColor "$($errorLine.PadRight(75))│" -color "Warning"
        Write-OutputColor "  │                                                                        │" -color "Info"
        Write-OutputColor "  │  Troubleshooting:                                                      │" -color "Info"
        Write-OutputColor "  │$("   - Verify the cluster name is correct".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("   - Ensure you have domain admin or cluster admin rights".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("   - Check that Failover Clustering feature is installed".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        return $false
    }
}

# Function to confirm/set site number
function Set-DeploymentSiteNumber {
    Clear-Host
    Write-CenteredOutput "Site Configuration" -color "Info"

    Write-OutputColor "" -color "Info"

    # If VMNaming has a static SiteId configured, use it directly
    if ($script:VMNaming.SiteIdSource -eq "static" -and $script:VMNaming.SiteId -ne "") {
        $script:VMDeploymentSiteNumber = $script:VMNaming.SiteId
        Write-OutputColor "Site identifier set from configuration: $($script:VMNaming.SiteId)" -color "Success"
        return $true
    }

    # Try to detect site identifier from hostname
    $detectedSite = $null

    if ($script:VMDeploymentMode -eq "Standalone") {
        $detectedSite = Get-SiteNumberFromHostnameParam -Hostname $script:VMDeploymentTarget
    }
    elseif ($script:VMDeploymentMode -eq "Cluster") {
        # Try first node
        $nodes = @(Get-ClusterNode -Cluster $script:VMDeploymentTarget -ErrorAction SilentlyContinue)
        if ($nodes.Count -gt 0) {
            $detectedSite = Get-SiteNumberFromHostnameParam -Hostname $nodes[0].Name
        }
    }

    if ($detectedSite) {
        Write-OutputColor "Detected site identifier from hostname: $detectedSite" -color "Success"
        Write-OutputColor "" -color "Info"

        if (Confirm-UserAction -Message "Is this your site identifier?") {
            $script:VMDeploymentSiteNumber = $detectedSite
            Write-OutputColor "Site identifier set to: $detectedSite" -color "Success"
            return $true
        }
    }
    else {
        Write-OutputColor "Could not detect site identifier from hostname." -color "Warning"
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter site identifier (e.g., 123456, CRV, ACME):" -color "Info"
    $siteInput = Read-Host

    $navResult = Test-NavigationCommand -UserInput $siteInput
    if ($navResult.ShouldReturn) {
        return $false
    }

    # Accept any alphanumeric string (letters, digits, hyphens)
    if ($siteInput -match '^[A-Za-z0-9\-]+$') {
        $script:VMDeploymentSiteNumber = $siteInput
        Write-OutputColor "Site identifier set to: $siteInput" -color "Success"
        return $true
    }
    else {
        Write-OutputColor "Invalid site identifier. Use letters, digits, or hyphens." -color "Error"
    }

    return $false
}

# Function to show VM deployment main menu
function Show-VMDeploymentMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                      DEPLOY VIRTUAL MACHINES").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Show current connection status
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONNECTION STATUS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    if ($script:VMDeploymentConnected) {
        Write-OutputColor "  │  ● Connected to: $($script:VMDeploymentTarget.PadRight(54))│" -color "Success"
        Write-OutputColor "  │    Mode: $($script:VMDeploymentMode.PadRight(62))│" -color "Info"
        if ($script:VMDeploymentSiteNumber) {
            Write-OutputColor "  │    Site: $($script:VMDeploymentSiteNumber.PadRight(62))│" -color "Info"
        }
    }
    else {
        Write-OutputColor "  │$("  ○ Not connected".PadRight(72))│" -color "Warning"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  DEPLOYMENT OPTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("   [1]  Add Standard VM to Queue (from template)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [2]  Add Custom VM to Queue".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Deployment Queue section
    $queueCount = $script:VMDeploymentQueue.Count
    if ($queueCount -gt 0) {
        $queueLabel = "  │  DEPLOYMENT QUEUE ($queueCount VM(s) ready)"
        $queueLabel = $queueLabel.PadRight(75) + "│"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor $queueLabel -color "Warning"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        foreach ($qvm in $script:VMDeploymentQueue) {
            $osSource = if ($qvm.UseVHD) { "VHD $($qvm.VHDOSVersion)" } else { "Blank" }
            $vmLine = "  │    $($qvm.VMName)  ($($qvm.vCPU)vCPU, $($qvm.MemoryGB)GB RAM, $osSource)"
            Write-OutputColor "$($vmLine.PadRight(75))│" -color "Info"
        }
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("   [3]  ★ Manage / Deploy Queue".PadRight(72))│" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    else {
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  DEPLOYMENT QUEUE (empty)".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("   Add VMs using options [1] or [2] above, then deploy them together.".PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("   [3]  Manage Queue".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  MANAGE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("   [4]  View Existing VMs".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [5]  Download / Manage Sysprepped VHDs".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [6]  Download Server ISOs".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("   [7]  Host Storage Setup (folders, Hyper-V defaults)".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SETTINGS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $connLabel = "  │   [8]  Change Connection  ◄ $($script:VMDeploymentTarget)"
    Write-OutputColor "$($connLabel.PadRight(75))│" -color "Success"
    Write-OutputColor "  │$("   [9]  Change Site Number".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "   [0] ◄ Back to Main Menu" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"
    return $choice
}

# Function to show standard VM templates
function Show-StandardVMTemplates {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║                       STANDARD VM TEMPLATES                            ║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Column headers
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-Host "  │  " -NoNewline -ForegroundColor Cyan
    Write-Host "#  " -NoNewline -ForegroundColor White
    Write-Host "Server Type            " -NoNewline -ForegroundColor White
    Write-Host "OS   " -NoNewline -ForegroundColor White
    Write-Host "CPU " -NoNewline -ForegroundColor White
    Write-Host "RAM   " -NoNewline -ForegroundColor White
    Write-Host "C Drive  " -NoNewline -ForegroundColor White
    Write-Host "D Drive     " -NoNewline -ForegroundColor White
    Write-Host "│" -ForegroundColor Cyan
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    $index = 1
    $templateKeys = @()

    foreach ($key in $script:StandardVMTemplates.Keys | Sort-Object { $script:StandardVMTemplates[$_].SortOrder }) {
        $template = $script:StandardVMTemplates[$key]
        $templateKeys += $key

        $osDisplay = if ($template.OSType -eq "Linux") { "Lin" } else { "Win" }
        $osColor = if ($template.OSType -eq "Linux") { "Yellow" } else { "Cyan" }

        # Build disk display
        $cDrive = "N/A"
        $dDrive = "N/A"
        foreach ($disk in $template.Disks) {
            if ($disk.Name -eq "OS") {
                $cDrive = if ($disk.SizeGB -ge 1024) { "$([math]::Round($disk.SizeGB / 1024, 1))TB" } else { "$($disk.SizeGB)GB" }
            }
            elseif ($disk.Name -eq "Data") {
                $dDrive = if ($disk.SizeGB -ge 1024) { "$([math]::Round($disk.SizeGB / 1024, 1))TB" } else { "$($disk.SizeGB)GB" }
            }
        }

        $num = "[$($index.ToString().PadLeft(2))]"

        Write-Host "  │  " -NoNewline -ForegroundColor Cyan
        Write-Host "$num " -NoNewline -ForegroundColor Green
        Write-Host $template.FullName.PadRight(23) -NoNewline -ForegroundColor Green
        Write-Host $osDisplay.PadRight(5) -NoNewline -ForegroundColor $osColor
        Write-Host $template.vCPU.ToString().PadRight(4) -NoNewline -ForegroundColor White
        Write-Host "$($template.MemoryGB)GB".PadRight(6) -NoNewline -ForegroundColor White
        Write-Host $cDrive.PadRight(9) -NoNewline -ForegroundColor White
        Write-Host $dDrive.PadRight(12) -NoNewline -ForegroundColor White
        Write-Host "│" -ForegroundColor Cyan

        $index++
    }

    Write-OutputColor "  │                                                                        │" -color "Info"
    $backLabel = "   [$index] ◄ Back"
    Write-OutputColor "  │$($backLabel.PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Note: Linux VMs use UEFI Certificate Authority for Secure Boot" -color "Debug"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) {
        return $null
    }

    if ($choice -match '^\d+$') {
        $choiceNum = [int]$choice
        if ($choiceNum -ge 1 -and $choiceNum -le $templateKeys.Count) {
            return $templateKeys[$choiceNum - 1]
        }
        elseif ($choiceNum -eq $index) {
            return $null
        }
    }

    Write-OutputColor "Invalid choice." -color "Error"
    return $null
}

# Function to configure VM settings
function New-VMConfiguration {
    param (
        [string]$TemplateKey = $null
    )

    # Start with template defaults or empty config
    if ($TemplateKey -and $script:StandardVMTemplates.ContainsKey($TemplateKey)) {
        $template = $script:StandardVMTemplates[$TemplateKey]

        # Build disk list from template's Disks array
        $diskList = @()
        foreach ($d in $template.Disks) {
            $diskList += @{
                SizeGB = $d.SizeGB
                Type   = $d.Type
                Name   = $d.Name
            }
        }

        $config = @{
            VMName = ""
            Prefix = $template.Prefix
            OSType = if ($template.OSType) { $template.OSType } else { "Windows" }
            vCPU = $template.vCPU
            MemoryGB = $template.MemoryGB
            MemoryType = $template.MemoryType
            Disks = $diskList
            NICs = @()
            GuestServices = $template.GuestServices
            TimeSyncWithHost = $template.TimeSyncWithHost
            Notes = $template.Notes
            Generation = 2
            SecureBoot = $true
            UseVHD = $false          # Use sysprepped VHD instead of blank disk
            VHDOSVersion = $null     # "2025", "2022", or "2019"
            VHDSourcePath = $null    # Path to cached sysprepped VHD
        }

        # Add default NIC
        for ($i = 0; $i -lt $template.NICs; $i++) {
            $config.NICs += @{
                SwitchName = ""
                VLAN = $null
            }
        }
    }
    else {
        # Custom VM defaults (overridable via CustomVMDefaults in defaults.json)
        $cvd = $script:CustomVMDefaults
        $config = @{
            VMName = ""
            Prefix = "VM"
            OSType = "Windows"
            vCPU = if ($cvd.ContainsKey('vCPU')) { $cvd['vCPU'] } else { 4 }
            MemoryGB = if ($cvd.ContainsKey('MemoryGB')) { $cvd['MemoryGB'] } else { 8 }
            MemoryType = if ($cvd.ContainsKey('MemoryType')) { $cvd['MemoryType'] } else { "Dynamic" }
            Disks = @(
                @{
                    SizeGB = if ($cvd.ContainsKey('DiskSizeGB')) { $cvd['DiskSizeGB'] } else { 100 }
                    Type = if ($cvd.ContainsKey('DiskType')) { $cvd['DiskType'] } else { "Fixed" }
                    Name = "OS"
                }
            )
            NICs = @(
                @{
                    SwitchName = ""
                    VLAN = $null
                }
            )
            GuestServices = $true
            TimeSyncWithHost = $true
            Notes = ""
            Generation = 2
            SecureBoot = $true
            UseVHD = $false
            VHDOSVersion = $null
            VHDSourcePath = $null
        }
    }

    return $config
}

# Function to configure VM name
function Set-VMConfigName {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    Clear-Host
    Write-CenteredOutput "VM Name Configuration" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Site Number: $($script:VMDeploymentSiteNumber)" -color "Info"
    Write-OutputColor "VM Type: $($Config.Prefix)" -color "Info"
    Write-OutputColor "" -color "Info"

    # Suggest next available name
    Write-OutputColor "Checking for existing VMs..." -color "Info"

    $suggested = Get-NextAvailableVMName -SiteNumber $script:VMDeploymentSiteNumber `
                                          -Prefix $Config.Prefix `
                                          -ComputerName $(if ($script:VMDeploymentMode -eq "Standalone") { $script:VMDeploymentTarget } else { $null }) `
                                          -ClusterName $(if ($script:VMDeploymentMode -eq "Cluster") { $script:VMDeploymentTarget } else { $null }) `
                                          -Credential $script:VMDeploymentCredential

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Suggested name: $($suggested.Name)" -color "Success"

    if (-not $suggested.Available) {
        Write-OutputColor "Warning: Could not find an available name up to 99. Please enter manually." -color "Warning"
    }

    Write-OutputColor "" -color "Info"
    if (Confirm-UserAction -Message "Use suggested name '$($suggested.Name)'?") {
        $Config.VMName = $suggested.Name
        return $true
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter custom VM name (or 'back' to cancel):" -color "Info"
    $customName = Read-Host

    $navResult = Test-NavigationCommand -UserInput $customName
    if ($navResult.ShouldReturn) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($customName)) {
        Write-OutputColor "No name entered." -color "Warning"
        return $false
    }

    # Validate custom name
    $vmCheck = Test-VMNameExists -VMName $customName `
                                  -ComputerName $(if ($script:VMDeploymentMode -eq "Standalone") { $script:VMDeploymentTarget } else { $null }) `
                                  -ClusterName $(if ($script:VMDeploymentMode -eq "Cluster") { $script:VMDeploymentTarget } else { $null }) `
                                  -Credential $script:VMDeploymentCredential

    if ($vmCheck.Exists) {
        Write-OutputColor "VM '$customName' already exists on $($vmCheck.Location)!" -color "Error"
        return $false
    }

    $dnsCheck = Test-VMNameInDNS -VMName $customName
    if ($dnsCheck.Exists) {
        Write-OutputColor "Warning: '$customName' exists in DNS ($($dnsCheck.IPAddress))" -color "Warning"
        if (-not (Confirm-UserAction -Message "Use this name anyway?")) {
            return $false
        }
    }

    $Config.VMName = $customName
    return $true
}

# Function to configure CPU
function Set-VMConfigCPU {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    Clear-Host
    Write-CenteredOutput "CPU Configuration" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Current setting: $($Config.vCPU) vCPU(s)" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter number of virtual CPUs (1-64):" -color "Info"
    Write-OutputColor "(Press Enter to keep current value)" -color "Info"
    Write-OutputColor "" -color "Info"

    $userResponse = Read-Host "vCPUs"

    $navResult = Test-NavigationCommand -UserInput $userResponse
    if ($navResult.ShouldReturn) { return $false }

    if ([string]::IsNullOrWhiteSpace($userResponse)) {
        Write-OutputColor "Keeping current value: $($Config.vCPU)" -color "Info"
        return $true
    }

    if ($userResponse -match '^\d+$') {
        $cpuCount = [int]$userResponse
        if ($cpuCount -ge 1 -and $cpuCount -le 64) {
            $Config.vCPU = $cpuCount
            Write-OutputColor "CPU set to: $cpuCount" -color "Success"
            return $true
        }
    }

    Write-OutputColor "Invalid value. Must be between 1 and 64." -color "Error"
    return $false
}

# Function to configure memory
function Set-VMConfigMemory {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    Clear-Host
    Write-CenteredOutput "Memory Configuration" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Current setting: $($Config.MemoryGB) GB ($($Config.MemoryType))" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Memory Type:" -color "Info"
    Write-OutputColor "  [1] Static (fixed amount, always allocated)" -color "Success"
    Write-OutputColor "  [2] Dynamic (adjusts based on demand)" -color "Success"
    Write-OutputColor "" -color "Info"

    $typeChoice = Read-Host "  Select memory type (1-2, Enter to keep current)"

    $navResult = Test-NavigationCommand -UserInput $typeChoice
    if ($navResult.ShouldReturn) { return $false }

    if (-not [string]::IsNullOrWhiteSpace($typeChoice)) {
        switch ($typeChoice) {
            "1" { $Config.MemoryType = "Static" }
            "2" { $Config.MemoryType = "Dynamic" }
        }
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter memory size in GB (1-1024):" -color "Info"
    Write-OutputColor "(Press Enter to keep current value: $($Config.MemoryGB) GB)" -color "Info"
    Write-OutputColor "" -color "Info"

    $memInput = Read-Host "Memory (GB)"

    $navResult = Test-NavigationCommand -UserInput $memInput
    if ($navResult.ShouldReturn) { return $false }

    if (-not [string]::IsNullOrWhiteSpace($memInput)) {
        if ($memInput -match '^\d+$') {
            $memSize = [int]$memInput
            if ($memSize -ge 1 -and $memSize -le 1024) {
                $Config.MemoryGB = $memSize
            }
            else {
                Write-OutputColor "Invalid value. Must be between 1 and 1024 GB." -color "Error"
                return $false
            }
        }
        else {
            Write-OutputColor "Invalid input." -color "Error"
            return $false
        }
    }

    Write-OutputColor "Memory set to: $($Config.MemoryGB) GB ($($Config.MemoryType))" -color "Success"
    return $true
}

# Function to configure disks
function Set-VMConfigDisks {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    while ($true) {
        Clear-Host
        Write-CenteredOutput "Disk Configuration" -color "Info"

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Current disks:" -color "Info"
        Write-OutputColor "" -color "Info"

        $index = 1
        foreach ($disk in $Config.Disks) {
            Write-OutputColor ("  [{0}] {1}: {2} GB ({3})" -f $index, $disk.Name, $disk.SizeGB, $disk.Type) -color "Info"
            $index++
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Options:" -color "Info"
        Write-OutputColor "  [A] Add disk" -color "Success"
        Write-OutputColor "  [E] Edit disk" -color "Success"
        Write-OutputColor "  [D] Delete disk" -color "Warning"
        Write-OutputColor "  [C] Continue (done configuring disks)" -color "Success"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "Enter choice"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return $false }

        switch ("$choice".ToUpper()) {
            "A" {
                # Add disk
                Write-OutputColor "" -color "Info"
                Write-OutputColor "Disk name (e.g., Data, Logs, TempDB):" -color "Info"
                $diskName = Read-Host
                if ([string]::IsNullOrWhiteSpace($diskName)) { $diskName = "Disk$($Config.Disks.Count + 1)" }

                Write-OutputColor "Disk size in GB:" -color "Info"
                $diskSize = Read-Host
                $diskSizeInt = 0
                if ($diskSize -notmatch '^\d+$' -or -not [int]::TryParse($diskSize, [ref]$diskSizeInt) -or $diskSizeInt -lt 1) {
                    Write-OutputColor "Invalid size." -color "Error"
                    Start-Sleep -Seconds 2
                    continue
                }

                Write-OutputColor "Disk type: [1] Fixed (Recommended) [2] Dynamic" -color "Info"
                $diskTypeChoice = Read-Host
                $diskType = if ($diskTypeChoice -eq "2") { "Dynamic" } else { "Fixed" }

                $Config.Disks += @{
                    SizeGB = $diskSizeInt
                    Type = $diskType
                    Name = $diskName
                }

                Write-OutputColor "Disk added: $diskName ($diskSize GB, $diskType)" -color "Success"
                Start-Sleep -Seconds 1
            }
            "E" {
                # Edit disk
                Write-OutputColor "" -color "Info"
                $editIndex = Read-Host "Enter disk number to edit"
                if ($editIndex -match '^\d+$') {
                    $idx = [int]$editIndex - 1
                    if ($idx -ge 0 -and $idx -lt $Config.Disks.Count) {
                        $disk = $Config.Disks[$idx]

                        Write-OutputColor "Current size: $($disk.SizeGB) GB. New size (Enter to keep):" -color "Info"
                        $newSize = Read-Host
                        if ($newSize -match '^\d+$' -and [int]$newSize -ge 1) {
                            $disk.SizeGB = [int]$newSize
                        }

                        Write-OutputColor "Current type: $($disk.Type). [1] Fixed [2] Dynamic (Enter to keep):" -color "Info"
                        $newType = Read-Host
                        if ($newType -eq "1") { $disk.Type = "Fixed" }
                        elseif ($newType -eq "2") { $disk.Type = "Dynamic" }

                        Write-OutputColor "Disk updated." -color "Success"
                        Start-Sleep -Seconds 1
                    }
                }
            }
            "D" {
                # Delete disk
                if ($Config.Disks.Count -le 1) {
                    Write-OutputColor "Cannot delete the last disk. VM must have at least one disk." -color "Warning"
                    Start-Sleep -Seconds 2
                    continue
                }

                Write-OutputColor "" -color "Info"
                $deleteIndex = Read-Host "Enter disk number to delete"
                if ($deleteIndex -match '^\d+$') {
                    $idx = [int]$deleteIndex - 1
                    if ($idx -ge 0 -and $idx -lt $Config.Disks.Count) {
                        $diskName = $Config.Disks[$idx].Name
                        $Config.Disks = @(for ($j = 0; $j -lt $Config.Disks.Count; $j++) { if ($j -ne $idx) { $Config.Disks[$j] } })
                        Write-OutputColor "Deleted disk: $diskName" -color "Success"
                        Start-Sleep -Seconds 1
                    }
                }
            }
            "C" {
                return $true
            }
            default {
                $navResult = Test-NavigationCommand -UserInput $choice
                if ($navResult.ShouldReturn) {
                    return $false
                }
            }
        }
    }
}

# Function to configure NICs
function Set-VMConfigNICs {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    # Get available switches
    $switches = @(Get-AvailableVirtualSwitches -ComputerName $(if ($script:VMDeploymentMode -eq "Standalone") { $script:VMDeploymentTarget } else { $null }) `
                                              -Credential $script:VMDeploymentCredential)

    if ($switches.Count -eq 0) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  No virtual switches found." -color "Warning"
        Write-OutputColor "  A virtual switch is required for VM network connectivity." -color "Info"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  CREATE A VIRTUAL SWITCH".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-MenuItem "[1]  Switch Embedded Team (SET)" -Status "Multi-NIC, recommended" -StatusColor "Success"
        Write-MenuItem "[2]  External Virtual Switch" -Status "Single NIC" -StatusColor "Info"
        Write-MenuItem "[3]  Skip (no network)"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        $swCreateChoice = Read-Host "  Select"
        switch ($swCreateChoice) {
            "1" {
                New-SwitchEmbeddedTeam -SwitchName $script:SwitchName -ManagementName $script:ManagementName
            }
            "2" {
                New-StandardVSwitch -SwitchType "External"
            }
            default {
                Write-OutputColor "  Continuing without network configuration." -color "Warning"
                Write-PressEnter
            }
        }

        if ($swCreateChoice -eq "1" -or $swCreateChoice -eq "2") {
            # Re-check switches after creation
            $switches = Get-AvailableVirtualSwitches -ComputerName $(if ($script:VMDeploymentMode -eq "Standalone") { $script:VMDeploymentTarget } else { $null }) `
                                                      -Credential $script:VMDeploymentCredential
            if ($switches.Count -eq 0) {
                Write-OutputColor "  Still no virtual switches available. A reboot may be required." -color "Warning"
                Write-PressEnter
            }
        }
    }

    while ($true) {
        Clear-Host
        Write-CenteredOutput "Network Adapter Configuration" -color "Info"

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Current NICs:" -color "Info"
        Write-OutputColor "" -color "Info"

        $index = 1
        foreach ($nic in $Config.NICs) {
            $switchDisplay = if ($nic.SwitchName) { $nic.SwitchName } else { "(Not Connected)" }
            $vlanDisplay = if ($nic.VLAN) { "VLAN $($nic.VLAN)" } else { "No VLAN" }
            Write-OutputColor ("  [{0}] {1} - {2}" -f $index, $switchDisplay, $vlanDisplay) -color "Info"
            $index++
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Available Virtual Switches:" -color "Info"
        foreach ($sw in $switches) {
            $typeLabel = $sw.SwitchType.ToString()
            if ($sw.SwitchType -eq "External" -and $sw.EmbeddedTeamingEnabled) { $typeLabel = "SET" }
            Write-OutputColor "  - $($sw.Name) ($typeLabel)" -color "Success"
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Options:" -color "Info"
        Write-OutputColor "  [A] Add NIC" -color "Success"
        Write-OutputColor "  [E] Edit NIC" -color "Success"
        Write-OutputColor "  [D] Delete NIC" -color "Warning"
        Write-OutputColor "  [C] Continue (done configuring NICs)" -color "Success"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "Enter choice"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return $false }

        switch ("$choice".ToUpper()) {
            "A" {
                # Add NIC
                Write-OutputColor "" -color "Info"
                Write-OutputColor "Select virtual switch (or Enter for not connected):" -color "Info"

                $swIndex = 1
                foreach ($sw in $switches) {
                    Write-OutputColor "  [$swIndex] $($sw.Name)" -color "Info"
                    $swIndex++
                }

                $swChoice = Read-Host "Switch number"
                $switchName = ""

                if ($swChoice -match '^\d+$') {
                    $swIdx = [int]$swChoice - 1
                    if ($swIdx -ge 0 -and $swIdx -lt $switches.Count) {
                        $switchName = $switches[$swIdx].Name
                    }
                }

                Write-OutputColor "VLAN ID (Enter for none, 1-4094):" -color "Info"
                $vlanInput = Read-Host
                $vlanId = $null
                if ($vlanInput -match '^\d+$') {
                    $vlan = [int]$vlanInput
                    if ($vlan -ge 1 -and $vlan -le 4094) {
                        $vlanId = $vlan
                    }
                }

                $Config.NICs += @{
                    SwitchName = $switchName
                    VLAN = $vlanId
                }

                Write-OutputColor "NIC added." -color "Success"
                Start-Sleep -Seconds 1
            }
            "E" {
                # Edit NIC
                Write-OutputColor "" -color "Info"
                $editIndex = Read-Host "Enter NIC number to edit"
                if ($editIndex -match '^\d+$') {
                    $idx = [int]$editIndex - 1
                    if ($idx -ge 0 -and $idx -lt $Config.NICs.Count) {
                        $nic = $Config.NICs[$idx]

                        Write-OutputColor "Select new virtual switch:" -color "Info"
                        $swIndex = 1
                        foreach ($sw in $switches) {
                            Write-OutputColor "  [$swIndex] $($sw.Name)" -color "Info"
                            $swIndex++
                        }
                        Write-OutputColor "  [0] Not Connected" -color "Info"

                        $swChoice = Read-Host "Switch number (Enter to keep current)"
                        if ($swChoice -match '^\d+$') {
                            if ($swChoice -eq "0") {
                                $nic.SwitchName = ""
                            }
                            else {
                                $swIdx = [int]$swChoice - 1
                                if ($swIdx -ge 0 -and $swIdx -lt $switches.Count) {
                                    $nic.SwitchName = $switches[$swIdx].Name
                                }
                            }
                        }

                        Write-OutputColor "VLAN ID (Enter for none, current: $(if ($nic.VLAN) { $nic.VLAN } else { 'None' })):" -color "Info"
                        $vlanInput = Read-Host
                        if ($vlanInput -eq "0" -or $vlanInput -eq "") {
                            $nic.VLAN = $null
                        }
                        elseif ($vlanInput -match '^\d+$') {
                            $vlan = [int]$vlanInput
                            if ($vlan -ge 1 -and $vlan -le 4094) {
                                $nic.VLAN = $vlan
                            }
                        }

                        Write-OutputColor "NIC updated." -color "Success"
                        Start-Sleep -Seconds 1
                    }
                }
            }
            "D" {
                # Delete NIC
                if ($Config.NICs.Count -le 1) {
                    Write-OutputColor "Cannot delete the last NIC. VM must have at least one NIC." -color "Warning"
                    Start-Sleep -Seconds 2
                    continue
                }

                Write-OutputColor "" -color "Info"
                $deleteIndex = Read-Host "Enter NIC number to delete"
                if ($deleteIndex -match '^\d+$') {
                    $idx = [int]$deleteIndex - 1
                    if ($idx -ge 0 -and $idx -lt $Config.NICs.Count) {
                        $Config.NICs = @($Config.NICs | Where-Object { $_ -ne $Config.NICs[$idx] })
                        Write-OutputColor "NIC deleted." -color "Success"
                        Start-Sleep -Seconds 1
                    }
                }
            }
            "C" {
                return $true
            }
            default {
                $navResult = Test-NavigationCommand -UserInput $choice
                if ($navResult.ShouldReturn) {
                    return $false
                }
            }
        }
    }
}

# Function to show VM configuration summary
function Show-VMConfigSummary {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                     VM CONFIGURATION SUMMARY").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VIRTUAL MACHINE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │  Name:        $($Config.VMName.PadRight(57))│" -color "Success"
    $osDisplay = if ($Config.OSType -eq "Linux") { "Linux" } else { "Windows" }
    Write-OutputColor "  │  OS Type:     $($osDisplay.PadRight(57))│" -color "Info"
    if ($Config.UseVHD) {
        $vhdDisplay = "Sysprepped VHD (Server $($Config.VHDOSVersion))"
        Write-OutputColor "  │  OS Source:   $($vhdDisplay.PadRight(57))│" -color "Success"
    }
    else {
        Write-OutputColor "  │  OS Source:   $("Blank disk (manual install)".PadRight(57))│" -color "Info"
    }
    Write-OutputColor "  │  Generation:  $($Config.Generation.ToString().PadRight(57))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  COMPUTE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │  vCPUs:       $($Config.vCPU.ToString().PadRight(57))│" -color "Info"
    Write-OutputColor "  │  Memory:      $("$($Config.MemoryGB) GB ($($Config.MemoryType))".PadRight(57))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STORAGE".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    foreach ($disk in $Config.Disks) {
        $diskInfo = "$($disk.SizeGB) GB ($($disk.Type))"
        Write-OutputColor "  │  $($disk.Name.PadRight(12)) $($diskInfo.PadRight(57))│" -color "Info"
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NETWORK".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $nicNum = 1
    foreach ($nic in $Config.NICs) {
        $switchDisplay = if ($nic.SwitchName) { $nic.SwitchName } else { "(Not Connected)" }
        $vlanDisplay = if ($nic.VLAN) { " [VLAN $($nic.VLAN)]" } else { "" }
        $nicInfo = "$switchDisplay$vlanDisplay"
        Write-OutputColor "  │  NIC $nicNum`:       $($nicInfo.PadRight(57))│" -color "Info"
        $nicNum++
    }
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OPTIONS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    $guestSvc = if ($Config.GuestServices) { "Enabled" } else { "Disabled" }
    $timeSync = if ($Config.TimeSyncWithHost) { "Enabled" } else { "DISABLED (DC mode)" }
    $sbTemplate = if ($Config.OSType -eq "Linux") { "UEFI CA" } else { "Windows" }
    $secureBoot = if ($Config.SecureBoot) { "Enabled ($sbTemplate)" } else { "Disabled" }
    Write-OutputColor "  │  Guest Services:    $($guestSvc.PadRight(51))│" -color "Info"
    if ($Config.TimeSyncWithHost) {
        Write-OutputColor "  │  Time Sync:         $($timeSync.PadRight(51))│" -color "Info"
    } else {
        Write-OutputColor "  │  Time Sync:         $($timeSync.PadRight(51))│" -color "Warning"
    }
    Write-OutputColor "  │  Secure Boot:       $($secureBoot.PadRight(51))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

    if ($Config.Notes) {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  NOTES".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $noteText = if ($Config.Notes.Length -gt 70) { $Config.Notes.Substring(0,67) + "..." } else { $Config.Notes }
        Write-OutputColor "  │  $($noteText.PadRight(70))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    }
    Write-OutputColor "" -color "Info"
}

# Resolve VM and VHD storage paths based on deployment mode
function Resolve-VMStoragePaths {
    param([hashtable]$Config)

    $computerParam = if ($script:VMDeploymentMode -eq "Standalone" -and $script:VMDeploymentTarget -ne $env:COMPUTERNAME) {
        $script:VMDeploymentTarget
    } else { $null }

    $storagePaths = Get-AvailableVMStoragePaths -ComputerName $computerParam -Credential $script:VMDeploymentCredential
    $vmPath = $storagePaths.DefaultVMPath
    $vhdPath = $storagePaths.DefaultVHDPath

    if ($script:VMDeploymentMode -eq "Cluster" -and $storagePaths.CSVPaths -and $storagePaths.CSVPaths.Count -gt 0) {
        $vmPath = Join-Path $storagePaths.CSVPaths[0] "VMs"
        $vhdPath = Join-Path $storagePaths.CSVPaths[0] "VHDs"
    }

    return @{
        VMPath = $vmPath
        VHDPath = $vhdPath
        VMSpecificPath = Join-Path $vmPath $Config.VMName
        VHDSpecificPath = Join-Path $vhdPath $Config.VMName
        ComputerName = $computerParam
    }
}

# Create VM-specific directories (local or remote)
function New-VMDirectories {
    param(
        [string]$VMSpecificPath,
        [string]$VHDSpecificPath,
        [string]$ComputerName
    )

    if ($ComputerName) {
        $scriptBlock = {
            param($vmPath, $vhdPath)
            if (-not (Test-Path $vmPath)) { New-Item -Path $vmPath -ItemType Directory -Force | Out-Null }
            if (-not (Test-Path $vhdPath)) { New-Item -Path $vhdPath -ItemType Directory -Force | Out-Null }
        }
        $invokeParams = @{
            ComputerName = $ComputerName
            ScriptBlock = $scriptBlock
            ArgumentList = @($VMSpecificPath, $VHDSpecificPath)
            ErrorAction = "SilentlyContinue"
        }
        if ($script:VMDeploymentCredential) { $invokeParams.Credential = $script:VMDeploymentCredential }
        Invoke-Command @invokeParams
    }
    else {
        if (-not (Test-Path $VMSpecificPath)) { New-Item -Path $VMSpecificPath -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path $VHDSpecificPath)) { New-Item -Path $VHDSpecificPath -ItemType Directory -Force | Out-Null }
    }
}

# Create the base VM object with CPU and memory
function New-VMShell {
    param([hashtable]$Config, [string]$VMPath, [string]$ComputerName)

    $vmParams = @{
        Name = $Config.VMName
        Generation = $Config.Generation
        MemoryStartupBytes = $Config.MemoryGB * 1GB
        Path = $VMPath
        NoVHD = $true
        ErrorAction = "Stop"
    }
    if ($ComputerName) { $vmParams.ComputerName = $ComputerName }

    Write-OutputColor "  Creating VM shell..." -color "Info"
    $vm = New-VM @vmParams
    if (-not $vm) { throw "Failed to create VM" }
    Write-OutputColor "  VM created successfully" -color "Success"

    Write-OutputColor "  Configuring CPU ($($Config.vCPU) vCPUs)..." -color "Info"
    Set-VMProcessor -VM $vm -Count $Config.vCPU -ErrorAction SilentlyContinue

    Write-OutputColor "  Configuring memory ($($Config.MemoryGB) GB $($Config.MemoryType))..." -color "Info"
    if ($Config.MemoryType -eq "Dynamic") {
        $minMemoryMB = [math]::Max(512, [math]::Floor($Config.MemoryGB * 1024 * 0.25))
        $startupMemoryMB = [math]::Floor($Config.MemoryGB * 1024 * 0.5)
        Set-VMMemory -VM $vm -DynamicMemoryEnabled $true `
            -MinimumBytes ($minMemoryMB * 1MB) `
            -StartupBytes ($startupMemoryMB * 1MB) `
            -MaximumBytes ($Config.MemoryGB * 1GB) `
            -Buffer 20 `
            -ErrorAction SilentlyContinue
    }
    else {
        Set-VMMemory -VM $vm -DynamicMemoryEnabled $false -StartupBytes ($Config.MemoryGB * 1GB) -ErrorAction SilentlyContinue
    }

    return $vm
}

# Create a single VHD and attach to VM
function New-VMDisk {
    param($VM, [hashtable]$Disk, [string]$VHDSpecificPath)

    Write-OutputColor "  Creating disk: $($Disk.Name) ($($Disk.SizeGB) GB, $($Disk.Type))..." -color "Info"

    $vhdFileName = "$($VM.Name)_$($Disk.Name).vhdx"
    $vhdFullPath = Join-Path $VHDSpecificPath $vhdFileName

    $vhdParams = @{
        Path = $vhdFullPath
        SizeBytes = $Disk.SizeGB * 1GB
        ErrorAction = "Stop"
    }
    if ($Disk.Type -eq "Fixed") { $vhdParams.Fixed = $true }
    else { $vhdParams.Dynamic = $true }

    if ($script:VMDeploymentMode -eq "Standalone" -and $script:VMDeploymentTarget -ne $env:COMPUTERNAME) {
        $vhdParams.ComputerName = $script:VMDeploymentTarget
        if ($script:VMDeploymentCredential) { $vhdParams.Credential = $script:VMDeploymentCredential }
    }

    $null = New-VHD @vhdParams
    Add-VMHardDiskDrive -VM $VM -Path $vhdFullPath -ErrorAction SilentlyContinue
}

# Create and attach all VM disks (VHD-based or blank)
function New-VMDisks {
    param($VM, [hashtable]$Config, [string]$VHDSpecificPath)

    $osVhdPath = $null

    if ($Config.UseVHD -and $Config.VHDSourcePath) {
        Write-OutputColor "  Using sysprepped VHD for OS disk..." -color "Info"

        $osVhdPath = Copy-VHDForVM -SourceVHDPath $Config.VHDSourcePath `
            -DestinationFolder $VHDSpecificPath `
            -VMName $Config.VMName `
            -DiskLabel "OS"

        if ($osVhdPath) {
            Add-VMHardDiskDrive -VM $VM -Path $osVhdPath -ErrorAction SilentlyContinue
            Write-OutputColor "  OS disk attached from sysprepped VHD." -color "Success"
        }
        else {
            Write-OutputColor "  Failed to prepare OS VHD. Falling back to blank disk." -color "Warning"
            $osDisk = $Config.Disks | Where-Object { $_.Name -eq "OS" } | Select-Object -First 1
            if ($osDisk) {
                $vhdFullPath = Join-Path $VHDSpecificPath "$($Config.VMName)_OS.vhdx"
                $null = New-VHD -Path $vhdFullPath -SizeBytes ($osDisk.SizeGB * 1GB) -Fixed -ErrorAction Stop
                Add-VMHardDiskDrive -VM $VM -Path $vhdFullPath -ErrorAction SilentlyContinue
            }
        }

        foreach ($disk in ($Config.Disks | Where-Object { $_.Name -ne "OS" })) {
            New-VMDisk -VM $VM -Disk $disk -VHDSpecificPath $VHDSpecificPath
        }
    }
    else {
        foreach ($disk in $Config.Disks) {
            New-VMDisk -VM $VM -Disk $disk -VHDSpecificPath $VHDSpecificPath
        }
    }

    return $osVhdPath
}

# Configure VM network adapters
function Set-VMNetworkConfig {
    param($VM, [hashtable]$Config)

    Write-OutputColor "  Configuring network adapters..." -color "Info"
    Get-VMNetworkAdapter -VM $VM | Remove-VMNetworkAdapter -ErrorAction SilentlyContinue

    $nicIndex = 1
    foreach ($nic in $Config.NICs) {
        $adapterName = "Network Adapter $nicIndex"
        Add-VMNetworkAdapter -VM $VM -Name $adapterName -ErrorAction SilentlyContinue
        if ($nic.SwitchName) {
            Connect-VMNetworkAdapter -VMName $VM.Name -Name $adapterName -SwitchName $nic.SwitchName -ErrorAction SilentlyContinue
        }
        if ($nic.VLAN) {
            Set-VMNetworkAdapterVlan -VMName $VM.Name -VMNetworkAdapterName $adapterName -Access -VlanId $nic.VLAN -ErrorAction SilentlyContinue
        }
        $nicIndex++
    }
}

# Configure integration services, firmware, checkpoints, and auto-actions
function Set-VMAdvancedConfig {
    param($VM, [hashtable]$Config)

    Write-OutputColor "  Configuring integration services..." -color "Info"
    if ($Config.GuestServices) {
        Enable-VMIntegrationService -VM $VM -Name "Guest Service Interface" -ErrorAction SilentlyContinue
    }
    if (-not $Config.TimeSyncWithHost) {
        Write-OutputColor "  Disabling time synchronization (DC mode)..." -color "Warning"
        Disable-VMIntegrationService -VM $VM -Name "Time Synchronization" -ErrorAction SilentlyContinue
    }

    if ($Config.Generation -eq 2) {
        if ($Config.SecureBoot) {
            if ($Config.OSType -eq "Linux") {
                Write-OutputColor "  Configuring Secure Boot (UEFI CA template for Linux)..." -color "Info"
                Set-VMFirmware -VM $VM -EnableSecureBoot On -SecureBootTemplate "MicrosoftUEFICertificateAuthority" -ErrorAction SilentlyContinue
            }
            else {
                Set-VMFirmware -VM $VM -EnableSecureBoot On -SecureBootTemplate "MicrosoftWindows" -ErrorAction SilentlyContinue
            }
        }
        else {
            Set-VMFirmware -VM $VM -EnableSecureBoot Off -ErrorAction SilentlyContinue
        }
    }

    Write-OutputColor "  Configuring automatic start/stop actions..." -color "Info"
    Set-VM -VM $VM -AutomaticStartAction StartIfRunning -AutomaticStartDelay 30 -ErrorAction SilentlyContinue
    Set-VM -VM $VM -AutomaticStopAction ShutDown -ErrorAction SilentlyContinue
    Set-VM -VM $VM -AutomaticCheckpointsEnabled $false -ErrorAction SilentlyContinue
    Set-VM -VM $VM -CheckpointType Production -ErrorAction SilentlyContinue

    $notes = $Config.Notes
    if (-not $notes) { $notes = "" }
    $notes += "`nCreated by $($script:ToolName) Tool v$($script:ScriptVersion) on $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    Set-VM -VM $VM -Notes $notes -ErrorAction SilentlyContinue
}

# Register VM in failover cluster
function Register-VMInCluster {
    param([string]$VMName)

    if ($script:VMDeploymentMode -eq "Cluster") {
        Write-OutputColor "  Adding VM to cluster..." -color "Info"
        Add-ClusterVirtualMachineRole -VMName $VMName -Cluster $script:VMDeploymentTarget -ErrorAction SilentlyContinue
    }
}

# Function to create the VM (orchestrator)
function New-DeployedVM {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    Clear-Host
    Write-CenteredOutput "Creating Virtual Machine" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Creating VM: $($Config.VMName)..." -color "Info"
    Write-OutputColor "" -color "Info"

    try {
        $paths = Resolve-VMStoragePaths -Config $Config

        Write-OutputColor "  Storage Paths:" -color "Info"
        Write-OutputColor "    VM Config: $($paths.VMSpecificPath)" -color "Info"
        Write-OutputColor "    VHD Files: $($paths.VHDSpecificPath)" -color "Info"
        Write-OutputColor "" -color "Info"

        New-VMDirectories -VMSpecificPath $paths.VMSpecificPath -VHDSpecificPath $paths.VHDSpecificPath -ComputerName $paths.ComputerName

        $vm = New-VMShell -Config $Config -VMPath $paths.VMPath -ComputerName $paths.ComputerName

        $osVhdPath = New-VMDisks -VM $vm -Config $Config -VHDSpecificPath $paths.VHDSpecificPath

        Set-VMNetworkConfig -VM $vm -Config $Config

        Set-VMAdvancedConfig -VM $vm -Config $Config

        Register-VMInCluster -VMName $Config.VMName

        # Offer offline VHD customization if sysprepped VHD was used
        if ($Config.UseVHD -and $osVhdPath -and (Test-Path $osVhdPath)) {
            Write-OutputColor "" -color "Info"
            $customized = Show-OfflineCustomizationPrompt -VHDPath $osVhdPath -VMName $Config.VMName
            if ($customized) {
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  Pre-boot customization applied successfully!" -color "Success"
            }
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor ("=" * 55) -color "Success"
        Write-OutputColor "  VM '$($Config.VMName)' created successfully!" -color "Success"
        Write-OutputColor ("=" * 55) -color "Success"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "VM Location: $($paths.VMSpecificPath)" -color "Info"
        Write-OutputColor "VHD Location: $($paths.VHDSpecificPath)" -color "Info"
        Write-OutputColor "" -color "Info"

        if ($Config.UseVHD) {
            Write-OutputColor "Next steps:" -color "Info"
            Write-OutputColor "  1. Start the VM (OS is pre-installed from sysprepped VHD)" -color "Info"
            Write-OutputColor "  2. Complete Windows mini-setup/OOBE" -color "Info"
            Write-OutputColor "  3. Configure networking inside the VM" -color "Info"
            Write-OutputColor "  4. Join domain, install roles/features as needed" -color "Info"
        }
        else {
            Write-OutputColor "Next steps:" -color "Info"
            Write-OutputColor "  1. Attach installation media (ISO) via Hyper-V Manager" -color "Info"
            Write-OutputColor "  2. Start the VM" -color "Info"
            Write-OutputColor "  3. Install the operating system" -color "Info"
            Write-OutputColor "  4. Configure networking inside the VM" -color "Info"
        }

        Add-SessionChange -Category "VM Deployment" -Description "Created VM: $($Config.VMName) $(if ($Config.UseVHD) { '(from sysprepped VHD)' })"

        return $true
    }
    catch {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "ERROR creating VM: $_" -color "Error"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "The VM may have been partially created. Check Hyper-V Manager." -color "Warning"
        Write-OutputColor "" -color "Info"
        Write-OutputColor "Troubleshooting tips:" -color "Info"
        Write-OutputColor "  - Verify Hyper-V is installed and running" -color "Info"
        Write-OutputColor "  - Check that storage paths exist and are writable" -color "Info"
        Write-OutputColor "  - Ensure sufficient disk space for VHD files" -color "Info"
        Write-OutputColor "  - For remote hosts, verify WinRM/PowerShell Remoting is enabled" -color "Info"

        return $false
    }
}

# Function to view existing VMs
function Show-ExistingVMs {
    Clear-Host
    Write-CenteredOutput "Existing Virtual Machines" -color "Info"

    Write-OutputColor "" -color "Info"
    Write-OutputColor "Retrieving VMs from $($script:VMDeploymentTarget)..." -color "Info"

    try {
        $params = @{
            ErrorAction = "Stop"
        }

        if ($script:VMDeploymentMode -eq "Standalone" -and $script:VMDeploymentTarget -ne $env:COMPUTERNAME) {
            $params.ComputerName = $script:VMDeploymentTarget
            if ($script:VMDeploymentCredential) {
                $params.Credential = $script:VMDeploymentCredential
            }
        }

        $vms = @(Get-VM @params | Sort-Object Name)

        if ($vms.Count -eq 0) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "No VMs found on $($script:VMDeploymentTarget)." -color "Warning"
            return
        }

        Write-OutputColor "" -color "Info"
        Write-OutputColor ("{0,-30} {1,-12} {2,-8} {3,-10} {4}" -f "Name", "State", "CPU", "Memory", "Uptime") -color "Info"
        Write-OutputColor ("=" * 80) -color "Info"

        foreach ($vm in $vms) {
            $stateColor = switch ($vm.State) {
                "Running" { "Success" }
                "Off" { "Warning" }
                "Saved" { "Info" }
                "Paused" { "Warning" }
                default { "Info" }
            }

            $memoryDisplay = if ($vm.MemoryAssigned -gt 0) {
                "{0:N0} MB" -f ($vm.MemoryAssigned / 1MB)
            } else {
                "-"
            }

            $uptimeDisplay = if ($vm.Uptime.TotalMinutes -gt 0) {
                if ($vm.Uptime.TotalDays -ge 1) {
                    "{0:N0}d {1:N0}h" -f $vm.Uptime.Days, $vm.Uptime.Hours
                }
                else {
                    "{0:N0}h {1:N0}m" -f $vm.Uptime.Hours, $vm.Uptime.Minutes
                }
            }
            else {
                "-"
            }

            Write-OutputColor ("{0,-30} " -f $vm.Name) -color "Info" -NoNewline
            Write-OutputColor ("{0,-12} " -f $vm.State) -color $stateColor -NoNewline
            Write-OutputColor ("{0,-8} {1,-10} {2}" -f $vm.ProcessorCount, $memoryDisplay, $uptimeDisplay) -color "Info"
        }

        Write-OutputColor ("=" * 80) -color "Info"
        Write-OutputColor "Total VMs: $($vms.Count)" -color "Info"
    }
    catch {
        Write-OutputColor "Error retrieving VMs: $_" -color "Error"
    }
}

# Shared handler for VM config edit actions (CPU, Memory, Disks, Network, GuestServices, TimeSync, OS method)
# Returns $true if the choice was handled (1-7), $false otherwise
function Invoke-VMConfigEditAction {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,

        [Parameter(Mandatory=$true)]
        [string]$Choice
    )

    switch ("$Choice".ToUpper()) {
        "1" { Set-VMConfigCPU -Config $Config; Write-PressEnter }
        "2" { Set-VMConfigMemory -Config $Config; Write-PressEnter }
        "3" { Set-VMConfigDisks -Config $Config }
        "4" { Set-VMConfigNICs -Config $Config }
        "5" {
            $Config.GuestServices = -not $Config.GuestServices
            Write-OutputColor "  Guest Services: $(if ($Config.GuestServices) { 'Enabled' } else { 'Disabled' })" -color "Info"
            Start-Sleep -Seconds 1
        }
        "6" {
            $Config.TimeSyncWithHost = -not $Config.TimeSyncWithHost
            Write-OutputColor "  Time Sync with Host: $(if ($Config.TimeSyncWithHost) { 'Enabled' } else { 'Disabled' })" -color "Info"
            Start-Sleep -Seconds 1
        }
        "7" {
            if ($Config.OSType -eq "Windows") {
                if ($Config.UseVHD) {
                    $Config.UseVHD = $false
                    $Config.VHDOSVersion = $null
                    $Config.VHDSourcePath = $null
                    Write-OutputColor "  Switched to blank disk mode." -color "Info"
                    Start-Sleep -Seconds 1
                }
                else {
                    $osVersion = Show-OSVersionMenu -Title "SELECT OS VERSION FOR VHD"
                    if ($osVersion) {
                        $vhdPath = Get-SyspreppedVHD -OSVersion $osVersion
                        if ($vhdPath) {
                            $Config.UseVHD = $true
                            $Config.VHDOSVersion = $osVersion
                            $Config.VHDSourcePath = $vhdPath
                            Write-OutputColor "  Using Server $osVersion sysprepped VHD." -color "Success"
                        }
                    }
                    Write-PressEnter
                }
            }
        }
        default { return $false }
    }
    return $true
}

# Function to deploy a standard VM
function Publish-StandardVM {
    $templateKey = Show-StandardVMTemplates

    if (-not $templateKey) {
        return
    }

    $config = New-VMConfiguration -TemplateKey $templateKey

    # Step through configuration
    if (-not (Set-VMConfigName -Config $config)) {
        Write-OutputColor "VM deployment cancelled." -color "Warning"
        Write-PressEnter
        return
    }

    # Ask if user wants to use a sysprepped VHD (only for Windows VMs)
    if ($config.OSType -eq "Windows") {
        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  OS INSTALLATION METHOD".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │   [1]  Use Sysprepped VHD (pre-installed OS, faster deployment)        │" -color "Success"
        Write-OutputColor "  │   [2]  Blank disk (install OS manually from ISO)                       │" -color "Success"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        $vhdChoice = Read-Host "  Select method"

        if ($vhdChoice -eq "1") {
            $osVersion = Show-OSVersionMenu -Title "SELECT OS VERSION FOR VHD"
            if ($osVersion) {
                $vhdPath = Get-SyspreppedVHD -OSVersion $osVersion
                if ($vhdPath) {
                    $config.UseVHD = $true
                    $config.VHDOSVersion = $osVersion
                    $config.VHDSourcePath = $vhdPath
                    Write-OutputColor "  Using Server $osVersion sysprepped VHD." -color "Success"
                }
                else {
                    Write-OutputColor "  VHD not available. Will create blank disks instead." -color "Warning"
                }
            }
            Write-PressEnter
        }
    }

    # Show summary and allow editing
    while ($true) {
        Show-VMConfigSummary -Config $config

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Options:" -color "Info"
        Write-OutputColor "  [1] Edit CPU" -color "Success"
        Write-OutputColor "  [2] Edit Memory" -color "Success"
        Write-OutputColor "  [3] Edit Disks" -color "Success"
        Write-OutputColor "  [4] Edit Network" -color "Success"
        Write-OutputColor "  [5] Toggle Guest Services" -color "Success"
        Write-OutputColor "  [6] Toggle Time Sync" -color "Success"
        if ($config.OSType -eq "Windows") {
            $vhdStatus = if ($config.UseVHD) { "VHD: Server $($config.VHDOSVersion)" } else { "Blank Disk" }
            Write-OutputColor "  [7] Change OS Install Method ($vhdStatus)" -color "Success"
        }
        Write-OutputColor "  [C] ADD TO QUEUE" -color "Success"
        Write-OutputColor "  [X] Cancel" -color "Warning"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "Enter choice"

        if (-not (Invoke-VMConfigEditAction -Config $config -Choice $choice)) {
            switch ("$choice".ToUpper()) {
                "C" {
                    Show-VMConfigSummary -Config $config
                    Write-OutputColor "" -color "Info"
                    if (Confirm-UserAction -Message "Add this VM to the deployment queue?") {
                        Add-VMToQueue -Config $config
                        Show-DeploymentQueue
                        Write-PressEnter
                        return
                    }
                }
                "X" {
                    Write-OutputColor "VM deployment cancelled." -color "Warning"
                    Write-PressEnter
                    return
                }
            }
        }
    }
}

# Function to deploy a custom VM
function Publish-CustomVM {
    $config = New-VMConfiguration

    # Start with name
    Clear-Host
    Write-CenteredOutput "Custom VM Deployment" -color "Info"
    Write-OutputColor "" -color "Info"
    Write-OutputColor "Enter VM prefix (e.g., VM, APP, TEST):" -color "Info"
    $prefix = Read-Host
    if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = "VM" }
    $config.Prefix = $prefix.ToUpper()

    if (-not (Set-VMConfigName -Config $config)) {
        Write-OutputColor "VM deployment cancelled." -color "Warning"
        Write-PressEnter
        return
    }

    # Ask about OS install method
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OS INSTALLATION METHOD".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │   [1]  Use Sysprepped VHD (pre-installed Windows, faster)              │" -color "Success"
    Write-OutputColor "  │   [2]  Blank disk (install OS manually from ISO)                       │" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    $vhdChoice = Read-Host "  Select method"
    if ($vhdChoice -eq "1") {
        $osVersion = Show-OSVersionMenu -Title "SELECT OS VERSION FOR VHD"
        if ($osVersion) {
            $vhdPath = Get-SyspreppedVHD -OSVersion $osVersion
            if ($vhdPath) {
                $config.UseVHD = $true
                $config.VHDOSVersion = $osVersion
                $config.VHDSourcePath = $vhdPath
                Write-OutputColor "  Using Server $osVersion sysprepped VHD." -color "Success"
            }
            else {
                Write-OutputColor "  VHD not available. Will create blank disks instead." -color "Warning"
            }
        }
        Write-PressEnter
    }

    # Configure each component
    if (-not (Set-VMConfigCPU -Config $config)) { return }
    if (-not (Set-VMConfigMemory -Config $config)) { return }
    if (-not (Set-VMConfigDisks -Config $config)) { return }
    if (-not (Set-VMConfigNICs -Config $config)) { return }

    # Final review and create
    while ($true) {
        Show-VMConfigSummary -Config $config

        Write-OutputColor "" -color "Info"
        Write-OutputColor "Options:" -color "Info"
        Write-OutputColor "  [1] Edit CPU" -color "Success"
        Write-OutputColor "  [2] Edit Memory" -color "Success"
        Write-OutputColor "  [3] Edit Disks" -color "Success"
        Write-OutputColor "  [4] Edit Network" -color "Success"
        Write-OutputColor "  [5] Toggle Guest Services" -color "Success"
        Write-OutputColor "  [6] Toggle Time Sync" -color "Success"
        $vhdStatus = if ($config.UseVHD) { "VHD: Server $($config.VHDOSVersion)" } else { "Blank Disk" }
        Write-OutputColor "  [7] Change OS Install Method ($vhdStatus)" -color "Success"
        Write-OutputColor "  [C] ADD TO QUEUE" -color "Success"
        Write-OutputColor "  [X] Cancel" -color "Warning"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "Enter choice"

        if (-not (Invoke-VMConfigEditAction -Config $config -Choice $choice)) {
            switch ("$choice".ToUpper()) {
                "C" {
                    Show-VMConfigSummary -Config $config
                    Write-OutputColor "" -color "Info"
                    if (Confirm-UserAction -Message "Add this VM to the deployment queue?") {
                        Add-VMToQueue -Config $config
                        Show-DeploymentQueue
                        Write-PressEnter
                        return
                    }
                }
                "X" {
                    Write-OutputColor "VM deployment cancelled." -color "Warning"
                    Write-PressEnter
                    return
                }
            }
        }
    }
}

# Deployment queue for batch VM creation
$script:VMDeploymentQueue = @()

# Function to calculate total disk space needed for a list of VM configs
function Get-RequiredDiskSpace {
    param (
        [Parameter(Mandatory=$true)]
        [array]$VMConfigs
    )

    $totalBytes = 0
    foreach ($config in $VMConfigs) {
        foreach ($disk in $config.Disks) {
            # For VHD-based OS disks, the fixed size = template's OS disk size
            # For blank disks, it's the configured size
            $totalBytes += $disk.SizeGB * 1GB
        }
    }
    return $totalBytes
}

# Function to check if there's enough disk space for planned deployments
function Test-DeploymentDiskSpace {
    param (
        [Parameter(Mandatory=$true)]
        [array]$VMConfigs,

        [string]$StoragePath = $null
    )

    if (-not $StoragePath) {
        if ($script:VMDeploymentMode -eq "Cluster") {
            $csvs = Get-ClusterSharedVolume -Cluster $script:VMDeploymentTarget -ErrorAction SilentlyContinue
            if ($csvs) {
                $StoragePath = ($csvs | Select-Object -First 1).SharedVolumeInfo.FriendlyVolumeName
            }
            if (-not $StoragePath) { $StoragePath = "C:\ClusterStorage\Volume1" }
        }
        else {
            $StoragePath = $script:HostVMStoragePath
        }
    }

    if (-not $StoragePath) {
        return @{
            HasSpace = $false
            RequiredGB = 0
            FreeGB = 0
            Message = "Storage path not configured. Run 'Host Storage Setup' first."
        }
    }

    $requiredBytes = Get-RequiredDiskSpace -VMConfigs $VMConfigs
    $requiredGB = [math]::Round($requiredBytes / 1GB, 1)

    # Get free space on the target volume
    $freeBytes = $null
    $driveLetter = $null
    if ($StoragePath -like "*ClusterStorage*") {
        # CSV paths (e.g., C:\ClusterStorage\Volume1) — drive letter points to OS drive, not CSV
        try {
            $csvs = Get-ClusterSharedVolume -ErrorAction SilentlyContinue
            foreach ($csv in $csvs) {
                if ($null -ne $csv.SharedVolumeInfo -and $null -ne $csv.SharedVolumeInfo.FriendlyVolumeName) {
                    if ($StoragePath -like "$($csv.SharedVolumeInfo.FriendlyVolumeName)*") {
                        $freeBytes = $csv.SharedVolumeInfo.Partition.FreeSpace
                        break
                    }
                }
            }
        } catch { }
    }
    if ($null -eq $freeBytes) {
        $driveLetter = $StoragePath.Substring(0, 1)
        $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
        if ($volume) { $freeBytes = $volume.SizeRemaining }
    }

    if ($null -eq $freeBytes) {
        return @{
            HasSpace = $false
            RequiredGB = $requiredGB
            FreeGB = 0
            Message = "Could not determine free space on storage path"
        }
    }

    $freeGB = [math]::Round($freeBytes / 1GB, 1)
    # Add 10% buffer
    $requiredWithBuffer = $requiredGB * 1.1

    return @{
        HasSpace = ($freeGB -ge $requiredWithBuffer)
        RequiredGB = $requiredGB
        FreeGB = $freeGB
        DriveLetter = $driveLetter
        Message = if ($freeGB -ge $requiredWithBuffer) {
            "Sufficient space: ${freeGB} GB free, ${requiredGB} GB needed"
        }
        else {
            "NOT ENOUGH SPACE: ${freeGB} GB free, ${requiredGB} GB needed (plus 10% buffer)"
        }
    }
}

# Function to show the deployment queue
function Show-DeploymentQueue {
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    $queueTitle = "  │  DEPLOYMENT QUEUE ($($script:VMDeploymentQueue.Count) VM(s))"
    Write-OutputColor "$($queueTitle.PadRight(75))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

    if ($script:VMDeploymentQueue.Count -eq 0) {
        Write-OutputColor "  │$("  (empty)".PadRight(72))│" -color "Info"
    }
    else {
        $num = 1
        $totalDiskGB = 0
        foreach ($config in $script:VMDeploymentQueue) {
            $osSource = if ($config.UseVHD) { "VHD $($config.VHDOSVersion)" } else { "Blank" }
            $diskTotal = 0
            foreach ($disk in $config.Disks) { if ($disk.SizeGB) { $diskTotal += $disk.SizeGB } }
            $totalDiskGB += $diskTotal
            $vmLine = "  [$num] $($config.VMName)  |  $($config.vCPU)vCPU  $($config.MemoryGB)GB RAM  |  ${diskTotal}GB disk  |  $osSource"
            Write-OutputColor "  │$($vmLine.PadRight(72))│" -color "Success"
            $num++
        }

        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │  Total disk space required: $("${totalDiskGB} GB".PadRight(43))│" -color "Info"
    }

    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to deploy all VMs in the queue
function Start-BatchDeployment {
    if ($script:VMDeploymentQueue.Count -eq 0) {
        Write-OutputColor "  No VMs in the deployment queue." -color "Warning"
        return
    }

    Clear-Host
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                        BATCH VM DEPLOYMENT").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"

    Show-DeploymentQueue

    # Pre-flight validation (v1.6.1)
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  Running pre-flight validation..." -color "Info"

    $preFlight = Test-VMDeploymentPreFlight -VMConfigs $script:VMDeploymentQueue
    Show-PreFlightTable -PreFlightResult $preFlight

    if ($preFlight.HasFailure) {
        Write-OutputColor "" -color "Info"
        if (-not (Confirm-UserAction -Message "Pre-flight FAILED. Deploy anyway? (NOT RECOMMENDED)")) {
            return
        }
    }
    elseif ($preFlight.HasWarning) {
        Write-OutputColor "" -color "Info"
        if (-not (Confirm-UserAction -Message "Pre-flight has warnings. Continue?")) {
            return
        }
    }

    Write-OutputColor "" -color "Info"

    # Download any needed sysprepped VHDs FIRST so they're cached for all VMs
    $neededVHDVersions = @()
    foreach ($config in $script:VMDeploymentQueue) {
        if ($config.UseVHD -and $config.VHDOSVersion -and $config.VHDOSVersion -notin $neededVHDVersions) {
            $cached = Test-CachedVHD -OSVersion $config.VHDOSVersion
            if (-not $cached.Exists) {
                $neededVHDVersions += $config.VHDOSVersion
            }
        }
    }

    if ($neededVHDVersions.Count -gt 0) {
        Write-OutputColor "  Downloading required base VHDs first..." -color "Info"
        Write-OutputColor "" -color "Info"
        foreach ($ver in $neededVHDVersions) {
            Write-OutputColor "  --- Downloading Server $ver base VHD ---" -color "Info"
            $vhdPath = Get-SyspreppedVHD -OSVersion $ver
            if (-not $vhdPath) {
                Write-OutputColor "  FAILED to download Server $ver VHD." -color "Error"
                Write-OutputColor "  VMs requiring this VHD will fall back to blank disk." -color "Warning"
                # Actually set UseVHD to false so New-DeployedVM creates blank disks
                foreach ($config in $script:VMDeploymentQueue) {
                    if ($config.UseVHD -and $config.VHDOSVersion -eq $ver) {
                        $config.UseVHD = $false
                        $config.VHDSourcePath = $null
                    }
                }
            }
            else {
                # Update all configs in queue that need this version
                foreach ($config in $script:VMDeploymentQueue) {
                    if ($config.UseVHD -and $config.VHDOSVersion -eq $ver) {
                        $config.VHDSourcePath = $vhdPath
                    }
                }
            }
            Write-OutputColor "" -color "Info"
        }
    }

    # Final confirmation
    if (-not (Confirm-UserAction -Message "Deploy $($script:VMDeploymentQueue.Count) VM(s) now?")) {
        Write-OutputColor "  Batch deployment cancelled. VMs are still in the queue." -color "Info"
        return
    }

    Write-OutputColor "" -color "Info"
    Write-OutputColor ("=" * 72) -color "Info"
    Write-OutputColor "  Starting batch deployment of $($script:VMDeploymentQueue.Count) VM(s)..." -color "Info"
    Write-OutputColor ("=" * 72) -color "Info"
    Write-OutputColor "" -color "Info"

    $successCount = 0
    $failCount = 0
    $totalVMs = $script:VMDeploymentQueue.Count
    $deployedVMs = @()

    for ($i = 0; $i -lt $totalVMs; $i++) {
        $config = $script:VMDeploymentQueue[$i]
        $vmNum = $i + 1

        Write-OutputColor "" -color "Info"
        $vmProgressLine = "  VM $vmNum of ${totalVMs}: $($config.VMName)"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$($vmProgressLine.PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"

        try {
            $result = New-DeployedVM -Config $config

            if ($result) {
                $successCount++
                $deployedVMs += $config
                Write-OutputColor "  [$vmNum/$totalVMs] $($config.VMName) - SUCCESS" -color "Success"
            }
            else {
                $failCount++
                Write-OutputColor "  [$vmNum/$totalVMs] $($config.VMName) - FAILED" -color "Error"
            }
        }
        catch {
            $failCount++
            Write-OutputColor "  [$vmNum/$totalVMs] $($config.VMName) - ERROR: $_" -color "Error"
        }
    }

    # Summary
    Write-OutputColor "" -color "Info"
    Write-OutputColor ("=" * 72) -color "Info"
    if ($failCount -eq 0) {
        Write-OutputColor "  BATCH DEPLOYMENT COMPLETE" -color "Success"
    }
    else {
        Write-OutputColor "  BATCH DEPLOYMENT COMPLETE (with errors)" -color "Warning"
    }
    Write-OutputColor ("=" * 72) -color "Info"
    $successColor = if ($successCount -gt 0) { "Success" } else { "Error" }
    Write-OutputColor "  Successful: $successCount" -color $successColor
    if ($failCount -gt 0) {
        Write-OutputColor "  Failed:     $failCount" -color "Error"
    }
    Write-OutputColor "" -color "Info"

    # Post-deployment smoke tests (v1.6.1)
    if ($successCount -gt 0) {
        Write-OutputColor "" -color "Info"
        if (Confirm-UserAction -Message "Run post-deployment smoke tests?") {
            Write-OutputColor "  Running smoke tests on deployed VMs..." -color "Info"
            $smokeResults = @()
            foreach ($config in $deployedVMs) {
                Write-OutputColor "  Testing $($config.VMName)..." -color "Info"
                $result = Test-VMPostDeployment -VMName $config.VMName
                $smokeResults += $result
            }
            Show-SmokeSummary -SmokeResults $smokeResults
        }
    }

    # Clear the queue
    $script:VMDeploymentQueue = @()
}

# Function to add a VM config to the queue (used by Publish-StandardVM/Publish-CustomVM)
function Add-VMToQueue {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    $script:VMDeploymentQueue += $Config
    Write-OutputColor "" -color "Info"
    Write-OutputColor "  VM '$($Config.VMName)' added to deployment queue." -color "Success"
    Write-OutputColor "  Queue now has $($script:VMDeploymentQueue.Count) VM(s)." -color "Info"
}

# Function to edit a VM that's already in the deployment queue
function Edit-QueuedVM {
    param (
        [Parameter(Mandatory=$true)]
        [int]$QueueIndex
    )

    if ($QueueIndex -lt 0 -or $QueueIndex -ge $script:VMDeploymentQueue.Count) {
        Write-OutputColor "  Invalid VM index." -color "Error"
        return "DONE"
    }

    $config = $script:VMDeploymentQueue[$QueueIndex]

    while ($true) {
        Clear-Host

        $titleText = "EDIT QUEUED VM: $($config.VMName)"
        $paddedTitle = ("                    " + $titleText).PadRight(72)

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$paddedTitle║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"

        Show-VMConfigSummary -Config $config

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  EDIT OPTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  [1]  Edit CPU".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("  [2]  Edit Memory".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("  [3]  Edit Disks".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("  [4]  Edit Network".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("  [5]  Toggle Guest Services".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("  [6]  Toggle Time Sync".PadRight(72))│" -color "Success"
        if ($config.OSType -eq "Windows") {
            $vhdStatus = if ($config.UseVHD) { "VHD: Server $($config.VHDOSVersion)" } else { "Blank Disk" }
            $methodLine = "  [7]  Change OS Install Method ($vhdStatus)"
            Write-OutputColor "  │$($methodLine.PadRight(72))│" -color "Success"
        }
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        Write-OutputColor "  │$("  [R]  Remove from Queue".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("  [0]  Done Editing".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Enter choice"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        if (-not (Invoke-VMConfigEditAction -Config $config -Choice $choice)) {
            switch ("$choice".ToUpper()) {
                "R" {
                    Write-OutputColor "" -color "Info"
                    if (Confirm-UserAction -Message "Remove '$($config.VMName)' from the queue?") {
                        $removeTarget = $config
                        $newQueue = @()
                        $removed = $false
                        foreach ($item in $script:VMDeploymentQueue) {
                            if (-not $removed -and [object]::ReferenceEquals($item, $removeTarget)) {
                                $removed = $true
                                continue
                            }
                            $newQueue += $item
                        }
                        $script:VMDeploymentQueue = $newQueue
                        Write-OutputColor "  '$($config.VMName)' removed from queue." -color "Success"
                        Write-PressEnter
                        return "REMOVED"
                    }
                }
                "0" {
                    return "DONE"
                }
            }
        }
    }
}

# Function to manage the deployment queue (view, edit, remove, deploy, clear)
function Show-VMQueueManagement {
    while ($true) {
        Clear-Host
        $queueCount = $script:VMDeploymentQueue.Count

        $queueTitle = "DEPLOYMENT QUEUE ($queueCount VM(s))"
        $paddedTitle = ("                    " + $queueTitle).PadRight(72)

        Write-OutputColor "" -color "Info"
        Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
        Write-OutputColor "  ║$paddedTitle║" -color "Info"
        Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
        Write-OutputColor "" -color "Info"

        if ($queueCount -eq 0) {
            Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
            Write-OutputColor "  │$("  Queue is empty.".PadRight(72))│" -color "Info"
            Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
            Write-OutputColor "  │$("  Use options [1] or [2] from the deployment menu to add VMs first.".PadRight(72))│" -color "Info"
            Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
            Write-OutputColor "" -color "Info"
            Write-PressEnter
            return
        }

        # Table header - columns must total 71 chars (72 inner - 1 leading space in prefix)
        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-Host "  │ " -NoNewline -ForegroundColor Cyan
        Write-Host " #   " -NoNewline -ForegroundColor White
        Write-Host "VM Name              " -NoNewline -ForegroundColor White
        Write-Host "CPU  " -NoNewline -ForegroundColor White
        Write-Host "RAM      " -NoNewline -ForegroundColor White
        Write-Host "Disk     " -NoNewline -ForegroundColor White
        Write-Host "OS Source             " -NoNewline -ForegroundColor White
        Write-Host "│" -ForegroundColor Cyan
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"

        $totalDiskGB = 0
        for ($i = 0; $i -lt $queueCount; $i++) {
            $vm = $script:VMDeploymentQueue[$i]
            $num = $i + 1
            $osSource = if ($vm.UseVHD) { "VHD $($vm.VHDOSVersion)" } else { "Blank" }
            $diskTotal = 0
            foreach ($disk in $vm.Disks) { if ($disk.SizeGB) { $diskTotal += $disk.SizeGB } }
            $totalDiskGB += $diskTotal

            $numCol = "[$num]".PadRight(5)
            $nameCol = $vm.VMName
            if ($nameCol.Length -gt 21) { $nameCol = $nameCol.Substring(0, 18) + "..." }
            $nameCol = $nameCol.PadRight(21)
            $cpuCol = "$($vm.vCPU)".PadRight(5)
            $ramCol = "$($vm.MemoryGB) GB".PadRight(9)
            $diskCol = "${diskTotal} GB".PadRight(9)
            $osCol = $osSource.PadRight(22)

            Write-Host "  │ " -NoNewline -ForegroundColor Cyan
            Write-Host "$numCol" -NoNewline -ForegroundColor Green
            Write-Host "$nameCol" -NoNewline -ForegroundColor White
            Write-Host "$cpuCol" -NoNewline -ForegroundColor White
            Write-Host "$ramCol" -NoNewline -ForegroundColor White
            Write-Host "$diskCol" -NoNewline -ForegroundColor White
            Write-Host "$osCol" -NoNewline -ForegroundColor White
            Write-Host "│" -ForegroundColor Cyan
        }

        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $totalLine = "  │  Total disk space required: ${totalDiskGB} GB"
        Write-OutputColor "$($totalLine.PadRight(75))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
        Write-OutputColor "  │$("  ACTIONS".PadRight(72))│" -color "Info"
        Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
        $selectLabel = "   [1-$queueCount]  Select a VM to Edit or Remove"
        Write-OutputColor "  │$($selectLabel.PadRight(72))│" -color "Success"
        Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
        Write-OutputColor "  │$("   [D]   ★ Deploy All Queued VMs".PadRight(72))│" -color "Success"
        Write-OutputColor "  │$("   [C]   Clear Entire Queue".PadRight(72))│" -color "Warning"
        Write-OutputColor "  │$("   [0]   Back to Deployment Menu".PadRight(72))│" -color "Info"
        Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
        Write-OutputColor "" -color "Info"

        $choice = Read-Host "  Select"

        $navResult = Test-NavigationCommand -UserInput $choice
        if ($navResult.ShouldReturn) { return }

        switch ("$choice".ToUpper()) {
            "D" {
                Start-BatchDeployment
                Write-PressEnter
                # After deployment, queue is cleared - go back to menu
                if ($script:VMDeploymentQueue.Count -eq 0) {
                    return
                }
            }
            "C" {
                Write-OutputColor "" -color "Info"
                if (Confirm-UserAction -Message "Clear all $queueCount VM(s) from the queue?") {
                    $script:VMDeploymentQueue = @()
                    Write-OutputColor "  Queue cleared." -color "Success"
                    Start-Sleep -Seconds 1
                    return
                }
            }
            "0" {
                return
            }
            default {
                if ($choice -match '^\d+$') {
                    $vmIndex = [int]$choice - 1
                    if ($vmIndex -ge 0 -and $vmIndex -lt $queueCount) {
                        Edit-QueuedVM -QueueIndex $vmIndex
                        # Loop continues to refresh the queue display
                    }
                    else {
                        Write-OutputColor "  Invalid choice. Enter 1-$queueCount to select a VM." -color "Error"
                        Start-Sleep -Seconds 1
                    }
                }
                else {
                    $navResult = Test-NavigationCommand -UserInput $choice
                    if ($navResult.ShouldReturn) { return }
                }
            }
        }
    }
}

# Function to run VM Deployment menu
function Start-VMDeployment {
    while ($true) {
        # First, select deployment mode if not connected
        if (-not $script:VMDeploymentConnected) {
            $modeChoice = Show-VMDeploymentModeMenu

            switch ($modeChoice) {
                "1" {
                    if (Connect-StandaloneHost) {
                        Write-PressEnter
                    }
                    else {
                        Write-PressEnter
                        continue
                    }
                }
                "2" {
                    if (Connect-FailoverCluster) {
                        Write-PressEnter
                    }
                    else {
                        Write-PressEnter
                        continue
                    }
                }
                "3" {
                    return
                }
                default {
                    $navResult = Test-NavigationCommand -UserInput $modeChoice
                    if ($navResult.ShouldReturn) {
                        return
                    }
                    continue
                }
            }
        }

        # If connected, ensure site number is set
        if ($script:VMDeploymentConnected -and -not $script:VMDeploymentSiteNumber) {
            if (-not (Set-DeploymentSiteNumber)) {
                Write-PressEnter
                continue
            }
            Write-PressEnter
        }

        # Ensure host storage is initialized before VM operations
        if ($script:VMDeploymentConnected -and -not $script:StorageInitialized) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  Host storage must be configured before VM operations." -color "Warning"
            Write-OutputColor "  This sets up VM folders and Hyper-V default paths." -color "Info"
            Write-OutputColor "" -color "Info"
            if (Initialize-HostStorage) {
                Write-PressEnter
            } else {
                Write-OutputColor "  Storage setup is required. Returning to connection menu." -color "Warning"
                Write-PressEnter
                $script:VMDeploymentConnected = $false
                continue
            }
        }

        # Show main deployment menu
        $choice = Show-VMDeploymentMenu

        switch ($choice) {
            "1" {
                Publish-StandardVM
            }
            "2" {
                Publish-CustomVM
            }
            "3" {
                # Queue management - edit, remove, deploy, clear
                Show-VMQueueManagement
            }
            "4" {
                Show-ExistingVMs
                Write-PressEnter
            }
            "5" {
                Start-VHDManagement
            }
            "6" {
                Start-ISODownload
            }
            "7" {
                Initialize-HostStorage
                Write-PressEnter
            }
            "8" {
                # Change connection - show current info, confirm, warn about queue
                Clear-Host
                Write-OutputColor "" -color "Info"
                Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
                Write-OutputColor "  │$("  CHANGE CONNECTION".PadRight(72))│" -color "Info"
                Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
                $connLine = "  │  Current: $($script:VMDeploymentTarget) ($($script:VMDeploymentMode))"
                Write-OutputColor "$($connLine.PadRight(75))│" -color "Info"
                if ($script:VMDeploymentQueue.Count -gt 0) {
                    $warnLine = "  │  ⚠ Queue has $($script:VMDeploymentQueue.Count) VM(s) - queue will be CLEARED"
                    Write-OutputColor "$($warnLine.PadRight(75))│" -color "Warning"
                }
                Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
                Write-OutputColor "" -color "Info"
                if (Confirm-UserAction -Message "Disconnect and choose a new target?") {
                    $script:VMDeploymentConnected = $false
                    $script:VMDeploymentTarget = $null
                    $script:VMDeploymentCredential = $null
                    $script:VMDeploymentMode = $null
                    $script:VMDeploymentQueue = @()
                    $script:SelectedHostDrive = $null
                    $script:HostVMStoragePath = $null
                    $script:HostISOPath = $null
                    $script:StorageInitialized = $false
                    Write-OutputColor "  Connection reset. Select a new deployment target." -color "Success"
                    Start-Sleep -Seconds 1
                }
            }
            "9" {
                Set-DeploymentSiteNumber
                Write-PressEnter
            }
            "0" {
                return
            }
            default {
                $navResult = Test-NavigationCommand -UserInput $choice
                if ($navResult.ShouldReturn) {
                    return
                }
            }
        }
    }
}

# Pre-flight validation for VM deployments (v1.6.1)
# Checks disk space, RAM, vCPU ratio, VM switches, and VHD sources
function Test-VMDeploymentPreFlight {
    param(
        [Parameter(Mandatory=$true)]
        [array]$VMConfigs,
        [string]$StoragePath = $null
    )

    $results = @()

    # 1. Disk space check (reuse existing)
    $spaceCheck = Test-DeploymentDiskSpace -VMConfigs $VMConfigs -StoragePath $StoragePath
    $results += @{
        Resource = "Disk Space"
        Required = "$($spaceCheck.RequiredGB) GB"
        Available = "$($spaceCheck.FreeGB) GB"
        Status = if ($spaceCheck.HasSpace) { "OK" } else { "FAIL" }
    }

    # 2. RAM check
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    $totalRAMGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeRAMGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $requiredRAMGB = 0
    foreach ($vm in $VMConfigs) {
        if ($vm.MemoryGB) { $requiredRAMGB += $vm.MemoryGB }
    }
    $runningVMs = @()
    try { $runningVMs = @(Get-VM -ErrorAction SilentlyContinue | Where-Object { $_.State -eq "Running" }) } catch {}
    $existingRAMGB = 0
    foreach ($rv in $runningVMs) { $existingRAMGB += [math]::Round($rv.MemoryAssigned / 1GB, 1) }
    $ramStatus = if (($requiredRAMGB + $existingRAMGB) -gt ($totalRAMGB * 0.95)) { "FAIL" }
                 elseif (($requiredRAMGB + $existingRAMGB) -gt ($totalRAMGB * 0.8)) { "WARN" }
                 else { "OK" }
    $results += @{
        Resource = "RAM"
        Required = "$requiredRAMGB GB (new) + $existingRAMGB GB (running)"
        Available = "$totalRAMGB GB total ($freeRAMGB GB free)"
        Status = $ramStatus
    }

    # 3. vCPU ratio check
    $logicalProcs = (Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $newvCPUs = 0
    foreach ($vm in $VMConfigs) { if ($vm.vCPU) { $newvCPUs += $vm.vCPU } }
    $existingvCPUs = 0
    foreach ($rv in $runningVMs) { $existingvCPUs += $rv.ProcessorCount }
    $totalvCPUs = $newvCPUs + $existingvCPUs
    $ratio = if ($logicalProcs -gt 0) { [math]::Round($totalvCPUs / $logicalProcs, 1) } else { 0 }
    $cpuStatus = if ($ratio -gt 8) { "FAIL" } elseif ($ratio -gt 4) { "WARN" } else { "OK" }
    $results += @{
        Resource = "vCPU Ratio"
        Required = "$newvCPUs (new) + $existingvCPUs (running) = $totalvCPUs"
        Available = "$logicalProcs logical processors (${ratio}:1 ratio)"
        Status = $cpuStatus
    }

    # 4. VM switch check
    $existingSwitches = @()
    try { $existingSwitches = @((Get-VMSwitch -ErrorAction SilentlyContinue).Name) } catch {}
    $switchNames = @($VMConfigs | ForEach-Object { $_.NICs } | ForEach-Object { $_.SwitchName } | Where-Object { $_ } | Select-Object -Unique)
    $missingSwitches = @($switchNames | Where-Object { $_ -notin $existingSwitches })
    $switchStatus = if ($missingSwitches.Count -gt 0) { "FAIL" } else { "OK" }
    $results += @{
        Resource = "VM Switches"
        Required = ($switchNames -join ", ")
        Available = if ($missingSwitches.Count -gt 0) { "Missing: $($missingSwitches -join ', ')" } else { "All present" }
        Status = $switchStatus
    }

    # 5. VHD source check
    $vhdVMs = @($VMConfigs | Where-Object { $_.UseVHD -and $_.VHDSourcePath })
    $vhdMissing = @()
    foreach ($vm in $vhdVMs) {
        if (-not (Test-Path $vm.VHDSourcePath -ErrorAction SilentlyContinue)) {
            $vhdMissing += $vm.VHDSourcePath
        }
    }
    $vhdStatus = if ($vhdMissing.Count -gt 0) { "WARN" } else { "OK" }
    $results += @{
        Resource = "VHD Sources"
        Required = "$($vhdVMs.Count) VHD-based VMs"
        Available = if ($vhdMissing.Count -gt 0) { "$($vhdMissing.Count) VHD(s) not found (will download)" } else { "All accessible" }
        Status = $vhdStatus
    }

    $hasFail = @($results | Where-Object { $_.Status -eq "FAIL" }).Count -gt 0
    $hasWarn = @($results | Where-Object { $_.Status -eq "WARN" }).Count -gt 0

    return @{
        Results = $results
        HasFailure = $hasFail
        HasWarning = $hasWarn
        PassedAll = (-not $hasFail -and -not $hasWarn)
    }
}

# Display pre-flight results as a formatted table
function Show-PreFlightTable {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$PreFlightResult
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PRE-FLIGHT VALIDATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├──────────────┬───────────────────────────┬───────────────────────┬──────┤" -color "Info"
    Write-OutputColor "  │ Resource     │ Required                  │ Available             │ Stat │" -color "Info"
    Write-OutputColor "  ├──────────────┼───────────────────────────┼───────────────────────┼──────┤" -color "Info"

    foreach ($r in $PreFlightResult.Results) {
        $color = switch ($r.Status) { "OK" { "Success" }; "WARN" { "Warning" }; "FAIL" { "Error" }; default { "Info" } }
        $resCol = $r.Resource.PadRight(12).Substring(0, 12)
        $reqCol = $r.Required
        if ($reqCol.Length -gt 25) { $reqCol = $reqCol.Substring(0, 22) + "..." }
        $reqCol = $reqCol.PadRight(25)
        $availCol = $r.Available
        if ($availCol.Length -gt 21) { $availCol = $availCol.Substring(0, 18) + "..." }
        $availCol = $availCol.PadRight(21)
        $statCol = $r.Status.PadRight(4)
        Write-OutputColor "  │ $resCol │ $reqCol │ $availCol │ $statCol │" -color $color
    }

    Write-OutputColor "  └──────────────┴───────────────────────────┴───────────────────────┴──────┘" -color "Info"

    if ($PreFlightResult.HasFailure) {
        Write-OutputColor "  FAIL: One or more checks failed. Deployment may not succeed." -color "Error"
    }
    elseif ($PreFlightResult.HasWarning) {
        Write-OutputColor "  WARNING: Review warnings above before proceeding." -color "Warning"
    }
    else {
        Write-OutputColor "  All pre-flight checks passed." -color "Success"
    }
}

# Post-deployment smoke tests for a single VM (v1.6.1)
function Test-VMPostDeployment {
    param(
        [Parameter(Mandatory=$true)]
        [string]$VMName,
        [int]$IPTimeoutSeconds = 120
    )

    $results = @()

    # 1. VM state check
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    $stateOK = $null -ne $vm -and $vm.State -eq "Running"
    $results += @{ Check = "VM Running"; Status = if ($stateOK) { "PASS" } else { "FAIL" }; Detail = if ($vm) { "$($vm.State)" } else { "VM not found" } }

    if (-not $vm) { return @{ VMName = $VMName; Results = $results; Passed = 0; Failed = $results.Count } }

    # 2. Heartbeat integration service
    $hb = Get-VMIntegrationService -VM $vm -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "Heartbeat" }
    $hbOK = $null -ne $hb -and $hb.PrimaryStatusDescription -eq "OK"
    $results += @{ Check = "Heartbeat"; Status = if ($hbOK) { "PASS" } elseif ($hb) { "WARN" } else { "FAIL" }; Detail = if ($hb) { $hb.PrimaryStatusDescription } else { "Not available" } }

    # 3. NIC connected
    $nics = Get-VMNetworkAdapter -VM $vm -ErrorAction SilentlyContinue
    $nicConnected = $null -ne $nics -and ($nics | Where-Object { $_.Status -eq "Ok" -or $_.Connected })
    $results += @{ Check = "NIC Connected"; Status = if ($nicConnected) { "PASS" } else { "WARN" }; Detail = if ($nics) { "$($nics.Count) NIC(s)" } else { "No NICs" } }

    # 4. Guest IP acquired (poll)
    $guestIP = $null
    $elapsed = 0
    $pollInterval = 5
    while ($elapsed -lt $IPTimeoutSeconds) {
        $vmNics = Get-VMNetworkAdapter -VM $vm -ErrorAction SilentlyContinue
        $ips = @($vmNics | ForEach-Object { $_.IPAddresses } | Where-Object { $_ -and $_ -notmatch ':' -and $_ -ne '127.0.0.1' })
        if ($ips.Count -gt 0) {
            $guestIP = $ips[0]
            break
        }
        Start-Sleep -Seconds $pollInterval
        $elapsed += $pollInterval
    }
    $results += @{ Check = "Guest IP"; Status = if ($guestIP) { "PASS" } else { "WARN" }; Detail = if ($guestIP) { $guestIP } else { "No IP after ${IPTimeoutSeconds}s" } }

    # 5. Ping response
    if ($guestIP) {
        $ping = Test-Connection -ComputerName $guestIP -Count 2 -Quiet -ErrorAction SilentlyContinue
        $results += @{ Check = "Ping"; Status = if ($ping) { "PASS" } else { "WARN" }; Detail = if ($ping) { "Responding" } else { "No response (firewall?)" } }
    }
    else {
        $results += @{ Check = "Ping"; Status = "SKIP"; Detail = "No IP available" }
    }

    # 6. RDP port 3389
    if ($guestIP) {
        $rdp = $false
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $connect = $tcp.BeginConnect($guestIP, 3389, $null, $null)
            $rdp = $connect.AsyncWaitHandle.WaitOne(3000, $false)
            $tcp.Close()
        } catch {}
        $results += @{ Check = "RDP (3389)"; Status = if ($rdp) { "PASS" } else { "WARN" }; Detail = if ($rdp) { "Port open" } else { "Port closed/filtered" } }
    }
    else {
        $results += @{ Check = "RDP (3389)"; Status = "SKIP"; Detail = "No IP available" }
    }

    $passed = @($results | Where-Object { $_.Status -eq "PASS" }).Count
    $failed = @($results | Where-Object { $_.Status -eq "FAIL" }).Count

    return @{
        VMName = $VMName
        Results = $results
        Passed = $passed
        Failed = $failed
        Total = $results.Count
    }
}

# Display smoke test summary for batch deployments
function Show-SmokeSummary {
    param(
        [Parameter(Mandatory=$true)]
        [array]$SmokeResults
    )

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  POST-DEPLOYMENT SMOKE TEST RESULTS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├──────────────────────┬──────────┬──────────┬──────────┬────────────────┤" -color "Info"
    Write-OutputColor "  │ VM Name              │ Running  │ Heart    │ NIC      │ IP / RDP       │" -color "Info"
    Write-OutputColor "  ├──────────────────────┼──────────┼──────────┼──────────┼────────────────┤" -color "Info"

    foreach ($sr in $SmokeResults) {
        $vmCol = $sr.VMName
        if ($vmCol.Length -gt 20) { $vmCol = $vmCol.Substring(0, 17) + "..." }
        $vmCol = $vmCol.PadRight(20)

        $getCheck = { param($name) $sr.Results | Where-Object { $_.Check -eq $name } | Select-Object -First 1 }
        $running = & $getCheck "VM Running"
        $heartbeat = & $getCheck "Heartbeat"
        $nic = & $getCheck "NIC Connected"
        $rdp = & $getCheck "RDP (3389)"

        $fmtStatus = { param($r) if (-not $r) { "N/A".PadRight(8) } else { $r.Status.PadRight(8) } }
        $fmtColor = { param($r) if (-not $r) { "Debug" } elseif ($r.Status -eq "PASS") { "Success" } elseif ($r.Status -eq "FAIL") { "Error" } else { "Warning" } }

        $runStr = & $fmtStatus $running
        $hbStr = & $fmtStatus $heartbeat
        $nicStr = & $fmtStatus $nic
        $ipCheck = $sr.Results | Where-Object { $_.Check -eq "Guest IP" } | Select-Object -First 1
        $rdpStr = if ($ipCheck -and $ipCheck.Status -eq "PASS" -and $rdp) { "$($ipCheck.Detail)" } else { "No IP" }
        if ($rdpStr.Length -gt 14) { $rdpStr = $rdpStr.Substring(0, 11) + "..." }
        $rdpStr = $rdpStr.PadRight(14)

        $lineColor = if ($sr.Failed -gt 0) { "Error" } elseif ($sr.Passed -eq $sr.Total) { "Success" } else { "Warning" }
        Write-OutputColor "  │ $vmCol │ $runStr │ $hbStr │ $nicStr │ $rdpStr │" -color $lineColor
    }

    Write-OutputColor "  └──────────────────────┴──────────┴──────────┴──────────┴────────────────┘" -color "Info"

    $allPassed = @($SmokeResults | Where-Object { $_.Failed -gt 0 }).Count -eq 0
    if ($allPassed) {
        Write-OutputColor "  All VMs passed smoke tests." -color "Success"
    }
    else {
        $failCount = @($SmokeResults | Where-Object { $_.Failed -gt 0 }).Count
        Write-OutputColor "  $failCount VM(s) have failed checks. Review above." -color "Warning"
    }
}
#endregion