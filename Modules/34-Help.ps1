#region ===== HELP SYSTEM =====
# Function to display help for the script
function Show-Help {
    Clear-Host

    Write-OutputColor "" -color "Info"
    Write-OutputColor "  ╔════════════════════════════════════════════════════════════════════════╗" -color "Info"
    Write-OutputColor "  ║$(("               $($script:ToolFullName.ToUpper()) v" + $script:ScriptVersion).PadRight(72))║" -color "Info"
    Write-OutputColor "  ║$(("                         Help & Documentation").PadRight(72))║" -color "Info"
    Write-OutputColor "  ╚════════════════════════════════════════════════════════════════════════╝" -color "Info"
    Write-OutputColor "" -color "Info"

    # Navigation
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  NAVIGATION".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  back / b          Go back one menu".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  exit / quit / q   Exit the script (shows session summary)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  r / refresh       Refresh adapter lists in network menus".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  help              Show this screen (from Settings menu)".PadRight(72))│" -color "Success"
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
    Write-OutputColor "  │$(("  [3] Roles & Features        Hyper-V, MPIO, Clustering, $($script:AgentInstaller.ToolName)").PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [4] Security & Access       RDP, PS Remoting, Firewall, Defender".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("      > [1] RDP  [2] PS Remoting  [3] Firewall  [4] FW Templates".PadRight(72))│" -color "Info"
    Write-OutputColor "  │$("      > [5] Defender Exclusions  [6] Add Local Admin  [7] Disable".PadRight(72))│" -color "Info"
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
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
    Write-OutputColor "" -color "Info"

    # Operations (Configure Server > [7])
    Write-OutputColor "  ┌────────────────────────────────────────────────────────────────────────┐" -color "Info"
    Write-OutputColor "  │$("  OPERATIONS (Configure Server > [7])".PadRight(72))│" -color "Info"
    Write-OutputColor "  ├────────────────────────────────────────────────────────────────────────┤" -color "Info"
    Write-OutputColor "  │$("  [1] VM Checkpoints    [2] VM Export/Import".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [3] Cluster Dashboard [4] Cluster Drain/Resume".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [5] Remote PowerShell Session".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [6] Remote Server Health Check".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [7] Remote Service Manager".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [8]-[10] HTML Reports: Health, Readiness, Profile Comparison".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  [11] Network Diagnostics".PadRight(72))│" -color "Success"
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
    Write-OutputColor "  │$("  - Transcript logs saved to C:\Temp\ with timestamps".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Batch mode: place batch_config.json next to script, run script".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - Config profiles: Save from one server, load onto another".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - VHD deploy: Pre-built images skip OS install (fastest method)".PadRight(72))│" -color "Success"
    Write-OutputColor "  │$("  - VM queue: Add multiple VMs, review all, then batch deploy".PadRight(72))│" -color "Success"
    Write-OutputColor "  └────────────────────────────────────────────────────────────────────────┘" -color "Info"
}

# Function to change color theme
function Set-ColorTheme {
    Clear-Host
    Write-CenteredOutput "Color Theme Settings" -color "Info"

    Write-OutputColor "Current Theme: $($script:ColorTheme)" -color "Info"
    Write-OutputColor "" -color "Info"

    Write-OutputColor "Available Themes:" -color "Info"
    $themeNum = 1
    $themeMap = @{}
    foreach ($themeName in $script:ColorThemes.Keys) {
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
        $script:ColorTheme = $themeMap[$choice]
        Write-OutputColor "Theme changed to: $($script:ColorTheme)" -color "Success"
        Add-SessionChange -Category "System" -Description "Changed color theme to $($script:ColorTheme)"
    }
    else {
        Write-OutputColor "Theme not changed." -color "Info"
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

    # Changelog content (extracted from script header comments)
    $changelog = @"
v1.0.0
======
RackStack - White-Label & Open Source:
- Configurable tool identity via defaults.json (ToolName, ToolFullName, SupportContact)
- All UI banners, filenames, scheduled tasks, and reports use configurable names
- defaults.example.json template for new deployments
- File server setup guide (docs/FileServer-Setup.md)
- Removed all hardcoded organization references from code
- All paths use relative references (no hardcoded user paths)
- Git repository with .gitignore (defaults.json excluded from tracking)

v2.9.0
======
Agent Installer:
- Hostname without site number now prompts to set hostname first
- Pending hostname change detected via registry - blocks install until reboot
- Agent list paginated (25 per page) with [N]ext/[P]rev navigation
- Agent list sorted numerically by site number (smallest to largest)
- Inline [S]earch within paginated list to filter by name or number
- Blank site names now display as (unknown)

Compatibility:
- Added Test-WindowsServer helper function
- Get-WindowsFeature calls guarded by server OS check
- Eliminates TerminatingError on Windows client (MPIO, Clustering, BitLocker, Dedup, Storage Replica)

Network & Remote Management:
- Network Diagnostics: ping, traceroute, port test, subnet sweep, DNS lookup, ARP table, active connections
- Operations Menu: Remote PS Session, Remote Health Check, Remote Service Manager

Infrastructure:
- FileServer file server integration (replaced Nextcloud WebDAV)
- Pre-flight validation checks before feature installations (Hyper-V, MPIO, Clustering)
- Disk space validation before large file downloads
- IP configuration rollback on failure
- Batch mode: Test-WindowsServer guard for feature installs

New Features:
- Server Readiness dashboard with scored checklist
- Quick Setup Wizard: guided 6-step initial configuration
- Role Templates: Hyper-V Host, Standalone Server, Cluster Node profiles with auto-configure
- JSON audit logging with 10MB rotation and viewer in Settings
- Menu status indicators showing live install/config state in submenus
- Health dashboard on main menu (hostname, OS, uptime, CPU, RAM, disk)
- HTML Readiness Report export
- Session log persistence across restarts
- Centralized constants for power plan GUIDs and licensing AppId

v2.8.0
======
VM Operations:
- VM Checkpoint Management (list, create, restore, delete)
- VM Export with progress tracking (background jobs)
- VM Import with copy/register options

Cluster Operations:
- Enhanced Cluster Dashboard with node status, CSV health
- Drain Node (suspend and migrate VMs)
- Resume Node from Drain with optional failback
- CSV Health monitoring with redirected I/O warnings

HTML Reporting:
- Professional HTML Health Report with embedded CSS
- HTML Profile Comparison with color highlighting
- Auto-open in browser option

Quality of Life:
- Favorites system to save frequently used menus
- Command History tracking (last 100 operations)
- Session Resume for VM queue and state

Menu Changes:
- New [7] Operations submenu in Configure Server
- New [9] Favorites and [10] History in Settings

v2.7.0
======
Security:
- Windows Defender Exclusions for Hyper-V
- Firewall Rule Templates (Hyper-V, Cluster, etc.)
- BitLocker Management

System Utilities:
- NTP Configuration
- Disk Cleanup utility
- Performance Dashboard
- Event Log Viewer
- Service Manager

Storage Features:
- Data Deduplication
- Storage Replica

Cluster Management:
- Create/Join Cluster, Validation
- CSV Management, Live Migration
- Quorum Configuration

v2.6.0
======
SET Smart Auto-Detection:
- Auto-detect NICs with internet connectivity for SET
- Remaining NICs identified as iSCSI candidates
- Option to configure iSCSI immediately after SET creation

iSCSI Smart Auto-Configuration:
- Detects host number from hostname (e.g., HV2 = Host 2)
- Calculates IPs: {iSCSI subnet}.{(host+1)*10 + port}
- A-side/B-side NIC identification with disable/enable helper
- SAN target auto-assignment per host (cycling A0/B1, A1/B0)

iSCSI & SAN Management Menu:
- Configure iSCSI NICs (auto or manual)
- Identify NICs (disable for switch identification)
- Discover and ping SAN targets
- Connect to iSCSI targets with multipath
- Configure MPIO (Round Robin)
- View iSCSI/MPIO status and disk mappings
- Disconnect iSCSI sessions

Utilities (Settings Menu):
- Compare Configuration Profiles (color diff)
- Check for Script Updates
- Manage Stored Credentials
- Remote Profile Application via WinRM

v2.5.0
======
- Help & Documentation: Configure Server renumbered, added VHD/ISO section
- Configuration Profiles: Added MPIO, Clustering, LocalAdmin, BuiltInAdmin
- Batch Configuration: 14 steps, added MPIO/Clustering/Admin fields
- Export: Added MPIO and Clustering status sections
- Settings: Added View Changelog option
- Maintenance: Auto-cleanup transcripts older than 30 days
- UI: All menus standardized to 72-char width, firewall color logic fixed

v2.4.0
======
- Sysprepped VHD deployment from Nextcloud (Server 2019/2022/2025)
- VHD caching, copy and convert, offline customization
- ISO download system for Server installation media
- Host storage setup (D: drive validation, folder creation)
- Full VM Deployment system for Standalone and Failover Clusters
- Standard templates: FS, PS, PACS, EVP, APP, COMM, REPT
- Custom VM with multi-disk, multi-NIC, VLAN support
- VM name collision detection (Hyper-V + DNS)
- Batch VM deployment queue

v2.3.0
======
- Full Storage Manager with 14 disk management options
- View disks, volumes, partitions
- Initialize, online/offline, clear disk
- Create/delete partitions, format volumes
- Extend/shrink volumes, change drive letters

v2.2.0
======
- MPIO installation for SAN connectivity
- Failover Clustering installation
- Improved cluster connection with AD discovery
- Profile system improvements

v2.1.0
======
- Configuration profiles (save/load)
- Batch configuration templates
- Export server configuration to text
- Session change tracking

v2.0.0
======
- Complete rewrite with modular architecture
- Color theme system
- Undo system for reversible changes
- Navigation commands (back, exit, help)
"@

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
                Write-PressEnter
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
                Write-OutputColor "Invalid choice." -color "Error"
                Start-Sleep -Seconds 1
            }
        }
    }
}
#endregion