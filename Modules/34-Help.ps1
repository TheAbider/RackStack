#region ===== HELP SYSTEM =====
# Function to display help for the script
function Show-Help {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    $helpTitle = "               $($script:ToolFullName.ToUpper()) v" + $script:ScriptVersion
    if ($helpTitle.Length -gt 72) { $helpTitle = $helpTitle.Substring(0, 69) + "..." }
    Write-OutputColor "  ║$($helpTitle.PadRight(72))║" -color "Info"
    Write-OutputColor "  ║$(("                         Help & Documentation").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Navigation
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NAVIGATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  back / b          Go back one menu".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  home / main / m   Jump to main menu from anywhere".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  exit / quit / q   Exit the script (shows session summary)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  r / refresh       Refresh adapter lists in network menus".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  help              Show this screen | help <keyword> to search".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Main Menu
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  MAIN MENU".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1] Configure Server       All server setup options (see below)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [2] Deploy Virtual Machines Create VMs on local/remote/cluster hosts".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [3] Save Config Profile    Export current settings as JSON for cloning".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [4] Load Config Profile    Apply a saved JSON profile to this server".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [5] Export Configuration   Export full server config to text file".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [6] Batch Config Template  Generate batch_config.json for automation".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [7] Settings               Theme, Undo, Help".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [8] Exit                   Show summary and exit".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Configure Server
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONFIGURE SERVER (7 submenus + diagnostics)".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1] Network Config          Host/VM networking, SET, iSCSI, DNS".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("      > Host Network:  SET, Backup NIC, IP Config, iSCSI, Rename".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("      > VM Network:    IP, DNS, Disable IPv6, Switch Adapter".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [2] System Config           Hostname, Domain, Timezone, Updates".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("      > [1] Set Hostname   [2] Join Domain   [3] Set Timezone".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("      > [4] Windows Updates [5] License       [6] Power Plan".PadRight(72))│" -color "Info"
    $rolesLine = "  [3] Roles & Features        Hyper-V, MPIO, Clustering, $($script:AgentInstaller.ToolName)"
    if ($rolesLine.Length -gt 72) { $rolesLine = $rolesLine.Substring(0, 69) + "..." }
    Write-OutputColor "  │$($rolesLine.PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [4] Security & Access       RDP, PS Remoting, Firewall, Defender".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("      > [1] RDP  [2] PS Remoting  [3] Firewall  [4] FW Templates".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("      > [5] FW Search  [6] Defender Exclusions  [7] Defender Status".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("      > [8] Add Local Admin  [9] Disable Admin  [10] Account Audit".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [5] Tools & Utilities       NTP, Cleanup, Perf, Events, Services".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("      > [6] Network Diagnostics  [7] Server Readiness  [8] Roles".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [6] Storage & Clustering    Disks, BitLocker, Dedup, Replica".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [7] Operations              Remote PS, Health, Services, iSCSI".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  [8]  System Health Check    CPU, RAM, disk, network, services".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [9]  Test Connectivity      Ping gateway, DNS, and internet".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [10] Performance Dashboard  Real-time CPU/RAM/disk/network monitor".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [Q]  Quick Setup Wizard     Guided initial server configuration".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # VM Deployment
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VM DEPLOYMENT".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Connection modes:  Local host, Remote host, Failover Cluster".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Built-in templates (add more via CustomVMTemplates in defaults.json):".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("    DC  (Domain Controller) Win  4 CPU   8GB  C:100GB".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("    FS  (File Server)       Win  4 CPU   8GB  C:100GB  D:200GB".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("    WEB (Web Server)        Win  4 CPU   8GB  C:100GB".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Custom VM: Full config (CPU, RAM, multi-disk, multi-NIC, VLAN)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Deployment options:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - Sysprepped VHD: Pre-built Windows image, offline customization".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Blank disk + ISO: Fresh install from mounted ISO".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Batch queue: Add multiple VMs, edit/remove, deploy all at once".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Features: Name collision check, auto-naming, CSV path detection".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Linux VMs auto-use UEFI Certificate Authority for Secure Boot".PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # VHD & ISO Management
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  VHD & ISO MANAGEMENT".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  VHD Cache: Download sysprepped Windows Server VHDs for fast deploy".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Server 2025, 2022, 2019 images available from FileServer".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Cached locally in Base Images folder for reuse across VMs".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Dynamic-to-fixed conversion, offline registry customization".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  ISO Downloads: Server installation ISOs from FileServer".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Host storage: D:\ISOs  |  Cluster: C:\ClusterStorage\Volume1\ISOs".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Sysprep Guide: Step-by-step instructions for creating custom VHDs".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Storage Manager
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  STORAGE MANAGER".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  View disks, volumes, partitions | Initialize, online/offline disks".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Clear disk data | Create/delete partitions | Format volumes".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Extend/shrink volumes | Change drive letters and labels".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Allocation unit sizes 4K-64K | OS disk protection built in".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # iSCSI & SAN Management (v2.6.0)
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  iSCSI & SAN MANAGEMENT (v2.6.0)".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Smart SET Configuration:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - Auto-detect: NICs with internet -> SET, without -> iSCSI".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Manual: Choose specific adapters for each function".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  Smart iSCSI Configuration:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - Auto-detect host# from hostname (e.g., HV2 = Host 2)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Auto-calculate IPs: {subnet}.{(host+1)*10 + port}".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Identify A-side and B-side NICs (disable for switch ID)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  SAN Target Connection:".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("  - Auto-assign SAN targets per host (A0/B1, A1/B0 cycling)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Ping test to verify SAN connectivity".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - MPIO configuration with Round Robin load balancing".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - View sessions, targets, paths, and disk mappings".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Settings Menu
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  SETTINGS MENU".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1]-[4]  Theme, Undo, Help, Changelog".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [5]-[8]  Compare Profiles, Check Updates, Credentials, Remote Apply".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [9]  Favorites              Save and recall frequently used menus".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [10] Command History         Last 100 operations".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [11] Edit Environment Defaults  Organization values in defaults.json".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [12] Edit Custom Licenses       KMS/AVMA keys in defaults.json".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [13] View Audit Log             JSON audit log with rotation".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Tools & Utilities (Configure Server > [5])
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TOOLS & UTILITIES (Configure Server > [5])".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1] NTP Configuration        [2] Disk Cleanup".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [3] Performance Dashboard    [4] Event Log Viewer".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [5] Service Manager          [6] Network Diagnostics".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [7] Server Readiness         [8] Role Templates".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [9] Pagefile Configuration   [10] SNMP Configuration".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [11] Windows Server Backup   [12] Certificate Management".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [13] Scheduled Task Manager".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Operations (Configure Server > [7])
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OPERATIONS (Configure Server > [7])  — use [/] to search".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  VM:      [1] Checkpoints  [2] Export/Import".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Cluster: [3] Dashboard    [4] Drain/Resume".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Remote:  [5] PS Session   [6] Health Check  [7] Service Mgr".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Reports: [8] Health HTML  [9] Readiness     [10] Profile Compare".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Tools:   [11] Net Diag    [12] Drift        [13] Perf Snapshot".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("           [14] Trend Report [15] Metrics     [16] Task Viewer".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Audit:   [17] SMB Shares  [18] Software     [19] Cert Expiry".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("           [20] VSS Writers  [21] Event Alerts [22] Uptime".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("           [23] Drivers      [24] Disk Space  [25] WU Status".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("           [26] Ports        [27] Sched Tasks [28] FW Rules".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("           [29] Reboot Pending [30] Memory Pressure".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Agent Installer (v2.8.0)
    $agentName = $script:AgentInstaller.ToolName
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$(("  $agentName AGENT INSTALLER").PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  Dynamic Discovery: Agents fetched from FileServer (10-min cache)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Auto-Match:        Hostname site# matched to available agents".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Quick Install:     One-click install when match found".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Search:            Find by site number (451/0451) or name".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  Hostname Check:    Prompts to set hostname if default (WIN-*/DESKTOP-)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(("  Domain Flow:       Install $agentName before domain join for tracking").PadRight(72))│" -color "Success"
    Write-OutputColor "  │$(' '.PadRight(72))│" -color "Info"
    Write-OutputColor "  │$(("  Access: Configure Server > Roles & Features > [4] Install $agentName").PadRight(72))│" -color "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Tips
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  TIPS".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  - IP addresses accept CIDR notation (192.168.1.10/24) or separate".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - DNS presets: Google, Cloudflare, OpenDNS, Quad9 + custom".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - SET (Switch Embedded Teaming) requires Hyper-V installed first".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Hostname format: SITENUMBER-ROLE (e.g., 123456-HV1, 123456-FS1)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Transcript logs saved to $($script:TempPath)\ with timestamps".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Batch mode: place batch_config.json next to script, run script".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Config profiles: Save from one server, load onto another".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - VHD deploy: Pre-built images skip OS install (fastest method)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - VM queue: Add multiple VMs, review all, then batch deploy".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to search help topics by keyword
function Search-HelpTopics {
    param([string]$Keyword)

    if ([string]::IsNullOrWhiteSpace($Keyword)) {
        Write-OutputColor "  Usage: Type 'help <keyword>' to search help topics" -color "Info"
        return
    }

    $Keyword = $Keyword.ToLower()

    # Define searchable help topics
    $topics = @(
        @{ Title = "Network Configuration"; Keywords = @("network", "ip", "dns", "vlan", "set", "teaming", "nic", "adapter"); Description = "Configure IP addresses, DNS servers, VLANs, and NIC teaming via SET (Switch Embedded Teaming)" }
        @{ Title = "iSCSI Storage"; Keywords = @("iscsi", "san", "multipath", "mpio", "target", "initiator", "storage"); Description = "Connect to iSCSI targets, configure multipath I/O, and manage SAN connections" }
        @{ Title = "Hyper-V"; Keywords = @("hyperv", "hyper-v", "vm", "virtual", "machine", "vhd", "switch"); Description = "Install Hyper-V, create VMs, manage virtual switches, and deploy from templates" }
        @{ Title = "Clustering"; Keywords = @("cluster", "failover", "csv", "quorum", "node", "drain"); Description = "Create failover clusters, manage CSV, configure quorum, and perform node maintenance" }
        @{ Title = "Active Directory"; Keywords = @("ad", "domain", "dc", "forest", "promotion", "dns", "ldap"); Description = "Promote domain controllers, join domains, and manage AD infrastructure" }
        @{ Title = "Batch Mode"; Keywords = @("batch", "automation", "unattended", "json", "config", "template", "dry-run", "dryrun"); Description = "Run unattended configuration from JSON templates. Supports DryRun mode for simulation." }
        @{ Title = "Health Checks"; Keywords = @("health", "check", "certificate", "cert", "secure", "boot", "tpm", "smb", "numa", "speed"); Description = "System health checks including certificates, Secure Boot, adapter speed, SMB dialect, and NUMA topology" }
        @{ Title = "Network Diagnostics"; Keywords = @("ping", "port", "scan", "trace", "mtu", "udp", "sweep", "diagnostic"); Description = "Ping, port scan (TCP/UDP), traceroute, MTU discovery, and subnet sweep" }
        @{ Title = "Reports"; Keywords = @("report", "html", "export", "dark", "mode", "section"); Description = "Generate HTML reports with dark mode support and selective section export" }
        @{ Title = "Configuration Export"; Keywords = @("export", "drift", "baseline", "compare", "config", "bitlocker", "firewall"); Description = "Export server configuration, save baselines, and detect drift" }
        @{ Title = "Replication"; Keywords = @("replica", "replication", "failover", "rpo", "hyper-v", "health"); Description = "Hyper-V Replica setup, health monitoring, RPO validation, and failover operations" }
        @{ Title = "Session Management"; Keywords = @("session", "favorite", "history", "resume", "undo", "theme", "color"); Description = "Favorites, command history, session resume, color themes, and undo operations" }
        @{ Title = "Navigation"; Keywords = @("back", "exit", "home", "cancel", "menu", "refresh", "navigate"); Description = "Use 'back/b', 'exit/quit/q', 'home/main/m', or 'r' to refresh the dashboard" }
        @{ Title = "Storage"; Keywords = @("disk", "partition", "format", "volume", "storage", "backend", "s2d", "fc", "smb3"); Description = "Disk management, storage backends (iSCSI/FC/S2D/SMB3/NVMe-oF), and system disk protection" }
        @{ Title = "Security"; Keywords = @("bitlocker", "defender", "firewall", "rdp", "nla", "audit", "password", "admin"); Description = "BitLocker management, Defender exclusions, firewall templates/audit, RDP security, and local accounts" }
        @{ Title = "Services & Tasks"; Keywords = @("service", "dependency", "scheduled", "task", "agent", "install"); Description = "Service manager with dependency view, scheduled task health monitoring, and agent installation" }
        @{ Title = "Event Logs"; Keywords = @("event", "log", "critical", "error", "viewer", "search", "export"); Description = "View system/application/security/Hyper-V events, custom search, critical event summary" }
        @{ Title = "Performance"; Keywords = @("performance", "cpu", "memory", "disk", "io", "bandwidth", "dashboard", "process"); Description = "Live performance dashboard with CPU, memory, disk I/O, and network bandwidth monitoring" }
        @{ Title = "Licensing & NTP"; Keywords = @("license", "activation", "kms", "avma", "ntp", "time", "timezone", "clock"); Description = "Windows licensing status (KMS/AVMA/Retail), NTP configuration, time sync, and timezone setup" }
        @{ Title = "VM Management"; Keywords = @("checkpoint", "snapshot", "export", "import", "migration", "vhd", "iso"); Description = "VM checkpoints, export/import, migration readiness, VHD health, and ISO inventory" }
        @{ Title = "CLI Actions"; Keywords = @("cli", "action", "headless", "automation", "fleet", "json", "audit", "scan"); Description = "132 CLI actions for headless automation. Run -ListActions to see all. JSON output via -OutputFormat JSON." }
    )

    $found = @()
    foreach ($topic in $topics) {
        if ($topic.Title.ToLower().Contains($Keyword) -or ($topic.Keywords | Where-Object { $_ -eq $Keyword -or $_ -like "*$Keyword*" })) {
            $found += $topic
        }
    }

    if ($found.Count -eq 0) {
        Write-OutputColor "  No help topics found for '$Keyword'" -color "Warning"
        Write-OutputColor "  Try: network, iscsi, hyperv, cluster, batch, health, storage, security, event, service" -color "Info"
    } else {
        Write-OutputColor "`n  Help topics matching '$Keyword':" -color "Info"
        foreach ($topic in $found) {
            Write-OutputColor "`n  $($topic.Title)" -color "Success"
            Write-OutputColor "  $($topic.Description)" -color "Info"
        }
    }
}

# Function to change color theme
function Set-ColorTheme {
    Clear-Host
    Write-CenteredOutput "Color Theme Settings" -color "Info"

    Write-OutputColor "  Current Theme: $($script:ColorTheme)" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  Available Themes:" -color "Info"
    $themeNum = 1
    $themeMap = @{}
    foreach ($themeName in ($script:ColorThemes.Keys | Sort-Object)) {
        $marker = if ($themeName -eq $script:ColorTheme) { " <-- Current" } else { "" }
        Write-OutputColor "  $themeNum. $themeName$marker" -color "Info"
        $themeMap["$themeNum"] = $themeName
        $themeNum++
    }
    Write-OutputColor "  $themeNum. Cancel" -color "Info"

    Write-OutputColor "" -color "Info"
    $choice = Read-Host "  Select theme"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) { return }

    if ($themeMap.ContainsKey($choice)) {
        $prevTheme = $script:ColorTheme
        $script:ColorTheme = $themeMap[$choice]
        Write-OutputColor "  Theme changed to: $($script:ColorTheme)" -color "Success"
        Add-SessionChange -Category "System" -Description "Changed color theme to $($script:ColorTheme)"
        Clear-MenuCache
        Add-UndoAction -Category "System" -Description "Changed color theme to $($script:ColorTheme)" -UndoScript {
            param($OldTheme)
            $script:ColorTheme = $OldTheme
        }.GetNewClosure() -UndoParams @{ OldTheme = $prevTheme }
    }
    else {
        Write-OutputColor "  Theme not changed." -color "Info"
    }
}

# Function to display changelog
function Show-Changelog {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                    CHANGELOG - Version " + $script:ScriptVersion).PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Load changelog from file (source of truth is Changelog.md)
    $changelogPath = Join-Path $PSScriptRoot "Changelog.md"
    if (-not (Test-Path -LiteralPath $changelogPath)) {
        # Monolithic/EXE mode: try relative to script location
        $changelogPath = Join-Path (Split-Path $PSCommandPath) "Changelog.md"
    }
    if (Test-Path -LiteralPath $changelogPath) {
        $changelog = Get-Content -LiteralPath $changelogPath -Raw -Encoding UTF8
        # Strip markdown headers for cleaner display
        $changelog = $changelog -replace '^# Changelog\s*\n', ''
        $changelog = $changelog -replace '(?m)^## ', ''
    } else {
        $changelog = "(Changelog file not found. See GitHub releases for version history.)"
    }

    # Display with pagination
    $lines = $changelog -split "`n"
    $linesPerPage = 25
    $totalLines = $lines.Count
    $currentLine = 0

    while ($currentLine -lt $totalLines) {
        $endLine = [Math]::Min($currentLine + $linesPerPage, $totalLines)

        for ($i = $currentLine; $i -lt $endLine; $i++) {
            $line = $lines[$i]
            if ($line -match "^v\d+\.\d+\.\d+") {
                Write-OutputColor "  $line" -color "Success"
            } elseif ($line -match "^=+$") {
                Write-OutputColor "  $line" -color "Info"
            } else {
                Write-OutputColor "  $line" -color "Info"
            }
        }

        $currentLine = $endLine

        if ($currentLine -lt $totalLines) {
            Write-OutputColor "" -color "Info"
            Write-OutputColor "  -- Press Enter for more, or 'q' to quit --" -color "Debug"
            $userResponse = Read-Host
            if ($userResponse -eq 'q') { break }
            Clear-Host
        }
    }
}

# Function to show settings menu
function Show-SettingsMenu {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("                              SETTINGS").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  APPEARANCE & SESSION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[1]  Change Color Theme" -Status ("Current: " + $script:ColorTheme) -StatusColor "Info"
    Write-MenuItem "[2]  Undo Last Change" -Status ("Available: " + $script:UndoStack.Count) -StatusColor "Info"
    Write-MenuItem "[3]  View Help"
    Write-MenuItem "[4]  View Changelog" -Status ("Version: " + $script:ScriptVersion) -StatusColor "Info"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  UTILITIES".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[5]  Compare Configuration Profiles"
    Write-MenuItem "[6]  Check for Script Updates"
    Write-MenuItem "[7]  Manage Stored Credentials"
    Write-MenuItem "[8]  Remote Profile Application"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  PERSONALIZATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[9]  Favorites"
    Write-MenuItem "[10] Command History"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  CONFIGURATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-MenuItem "[11] Edit Environment Defaults" -Status "File: defaults.json" -StatusColor "Info"
    Write-MenuItem "[12] Edit Custom Licenses" -Status "In: defaults.json" -StatusColor "Info"
    Write-MenuItem "[13] View Audit Log"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "  [B] ◄ Back to Main Menu" -color "Info"
    Write-OutputColor "" -color "Info"

    $choice = Read-Host "  Select"

    $navResult = Test-NavigationCommand -UserInput $choice
    if ($navResult.ShouldReturn) {
        if ($navResult.Action -eq "exit") { return "EXIT" }
        return "B"
    }

    return $choice
}

# Function to run settings menu
function Start-Show-SettingsMenu {
    while ($true) {
        if ($global:ReturnToMainMenu) { return }
        $choice = Show-SettingsMenu

        switch ($choice) {
            "1" {
                Set-ColorTheme
                Write-PressEnter
            }
            "2" {
                Undo-LastChange
                Write-PressEnter
            }
            "3" {
                Show-Help
                Write-PressEnter
            }
            "4" {
                Show-Changelog
                Write-PressEnter
            }
            "5" {
                Compare-ConfigurationProfiles
                Write-PressEnter
            }
            "6" {
                Test-ScriptUpdate
            }
            "7" {
                Show-CredentialManager
                Write-PressEnter
            }
            "8" {
                Invoke-RemoteProfileApply
                Write-PressEnter
            }
            "9" {
                Show-Favorites
            }
            "10" {
                Show-CommandHistory
            }
            "11" {
                Show-EditDefaults
            }
            "12" {
                Show-EditLicenses
            }
            "13" {
                Show-AuditLog
                Write-PressEnter
            }
            "EXIT" {
                Exit-Script
            }
            "B" {
                return
            }
            "back" {
                return
            }
            default {
                Write-OutputColor "  Invalid choice. Enter 1-13 or B." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion