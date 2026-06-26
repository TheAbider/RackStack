<p align="center">
  <img src=".github/assets/banner.png" alt="RackStack" width="100%">
</p>
<p align="center">
  <strong>sconfig for the modern era.</strong>
</p>
<p align="center">
  The PowerShell toolkit that turns bare metal into production-ready Windows Servers.
</p>
<p align="center">
  <a href="#features">Features</a> &bull;
  <a href="#quick-start">Quick Start</a> &bull;
  <a href="#configuration">Configuration</a> &bull;
  <a href="#batch-mode">Batch Mode</a> &bull;
  <a href="Changelog.md">Changelog</a> &bull;
  <a href="#contributing">Contributing</a>
</p>
<p align="center">
  <img alt="PowerShell 5.1+" src="https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell&logoColor=white">
  <img alt="Windows Server 2008R2-2025" src="https://img.shields.io/badge/Windows%20Server-2008R2--2025-0078D4?logo=windows&logoColor=white">
  <a href="https://www.powershellgallery.com/packages/RackStack"><img alt="PSGallery" src="https://img.shields.io/powershellgallery/v/RackStack?label=PSGallery&logo=powershell&logoColor=white"></a>
  <img alt="License MIT" src="https://img.shields.io/badge/license-MIT-green">
</p>
<p align="center">
  <a href="https://github.com/TheAbider/RackStack/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/TheAbider/RackStack/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/TheAbider/RackStack/actions/workflows/codeql.yml"><img alt="CodeQL" src="https://github.com/TheAbider/RackStack/actions/workflows/codeql.yml/badge.svg"></a>
  <a href="https://github.com/TheAbider/RackStack/actions/workflows/scorecard.yml"><img alt="OpenSSF Scorecard" src="https://api.securityscorecards.dev/projects/github.com/TheAbider/RackStack/badge"></a>
  <a href="https://www.bestpractices.dev/projects/12921"><img alt="OpenSSF Best Practices" src="https://www.bestpractices.dev/projects/12921/badge"></a>
  <a href="https://codecov.io/gh/TheAbider/RackStack"><img alt="codecov" src="https://codecov.io/gh/TheAbider/RackStack/branch/master/graph/badge.svg"></a>
  <img alt="PSScriptAnalyzer 0 errors" src="https://img.shields.io/badge/PSScriptAnalyzer-0%20errors-brightgreen">
  <img alt="5194 structural tests" src="https://img.shields.io/badge/structural%20tests-5194-brightgreen">
  <img alt="Pester 312 tests" src="https://img.shields.io/badge/Pester-312%20tests-brightgreen">
  <img alt="SLSA Level 3" src="https://slsa.dev/images/gh-badge-level3.svg">
</p>

> Running in production across 300+ Hyper-V hosts spanning multiple isolated Active Directory forests.

---

RackStack is a menu-driven PowerShell tool that automates everything between "Windows is installed" and "server is in production." Where sconfig gives you 15 options, RackStack gives you 201 CLI actions and 60+ interactive menus covering networking, Hyper-V, SAN/iSCSI, clustering, VM deployment, cloud onboarding, and batch automation, all with undo, transaction rollback, and audit logging.

Built for MSPs, sysadmins, and infrastructure teams who build servers repeatedly and want it done right every time.

<!--
<p align="center">
  <img src=".github/assets/screenshots/batch-mode.png" alt="RackStack batch mode running with idempotent step counter, completed step markers, and transaction rollback summary" width="800">
</p>
-->

## Features

**Networking** -- Static IP with rollback, VLAN tagging, Switch Embedded Teaming (auto-detect), custom SET vNICs (Backup, Cluster, Live Migration, Storage, or custom names with VLAN), DNS presets, iSCSI/SAN with A/B side MPIO and cabling auto-detect

**Storage Backends** -- Pluggable storage backend (iSCSI, Fibre Channel, Storage Spaces Direct, SMB3, NVMe-oF, Local); auto-detection from system state; per-backend management menus; generalized MPIO dispatching; all batch mode steps adapt to the selected backend

**Hyper-V** -- Role install, configurable VM templates (override specs or add new via `defaults.json`), batch queue deployment, VHD management, offline registry injection, Secure Boot Gen 2, cluster CSV support

**Server Roles** -- Failover Clustering, MPIO, BitLocker, Deduplication, Storage Replica, 14 disk operations

**Security** -- RDP/NLA, firewall templates, Windows Defender exclusions, local admin with complexity enforcement, Windows licensing (GVLK 2008-2025, AVMA 2012R2-2025)

**Automation** -- JSON-driven batch mode (24 idempotent steps with transaction rollback), Quick Setup Wizard, configuration export/import, HTML reports, JSON audit logging with rotation

**Monitoring** -- 201 CLI actions with JSON output for fleet automation, `ServerScore` (unified 0-100 health grade), `HealthDashboard` (all-in-one monitoring endpoint), `ClusterHealthScore`, `StorageHealthScore`, System Center (SCCM/SCOM/WAC) + Azure AD/Intune integration

**Cloud & Security** -- Azure Arc server onboarding (install the Connected Machine Agent, connect the host to Azure's hybrid management plane via service-principal auth); Microsoft Defender for Endpoint onboarding (activate the built-in EDR sensor against your tenant, with a built-in detection test)

**Security Operations** -- Network Policy Server (RADIUS) for 802.1X / VPN authentication, Always-On VPN (RRAS gateway + device/user-tunnel ProfileXML generation), CIS Windows Server L1 compliance scanning (read-only, severity-weighted score + HTML/JSON report), and SIEM log forwarding (Windows Event Forwarding plus Splunk Universal Forwarder / Elastic Winlogbeat config); plus Group Policy backup/restore/drift and Just Enough Administration (JEA) constrained endpoints

**Windows Admin Center** -- Install and configure the WAC gateway (Authenticode-verified MSI, gateway port + TLS certificate selection, firewall), with status and reversible uninstall

**Monitoring & Diagnostics** -- Health dashboard (disk I/O latency, NIC errors, memory pressure, Hyper-V guest health, top CPU processes), performance snapshots with trend reports and "days until full" estimates, event log viewer, service manager, network diagnostics (ping, traceroute, port test, subnet sweep, DNS, ARP)

**Drift Detection** -- Save configuration baselines, compare snapshots over time, track setting changes across baselines, auto-baseline after batch mode

**VM Deployment Safety** -- Pre-flight validation (disk, RAM, vCPU ratio, switches, VHDs) with OK/WARN/FAIL table, post-deploy smoke tests (heartbeat, NIC, IP, ping, RDP), batch queue with summary

**Multi-Agent Support** -- Configure and manage multiple RMM/MSP agent installers from a single interface, batch install via `InstallAgents` config array

**Remote Ops** -- Remote PowerShell sessions, remote health checks, remote service management

**System Debloat** -- Remove bloatware, disable telemetry, optimize services (Light/Standard/Aggressive profiles), Windows 11 / Server 2025 UI cleanup (classic right-click, left taskbar, no widgets/copilot), OS dark/light theme toggle

**UX** -- 5 color themes, session resume, favorites, command history, undo framework, 72-char box-drawing UI

<!--
<p align="center">
  <img src=".github/assets/screenshots/health-dashboard.png" alt="RackStack HealthDashboard showing disk I/O latency, NIC errors, memory pressure, Hyper-V guest health, and top CPU processes" width="800">
</p>
-->

## Quick Start

### Install via a package manager

RackStack is published to every major Windows package manager. Pick whichever you already use:

```powershell
# winget (Microsoft's official package manager — built into Windows 11 / Server 2025)
winget install TheAbider.RackStack

# Scoop
scoop bucket add rackstack https://github.com/TheAbider/scoop-bucket
scoop install rackstack

# Chocolatey
choco install rackstack

# PowerShell Gallery (installs the cmdlet-wrapper module, not the EXE)
Install-Module RackStack
```

The package-manager installs all pull the same `RackStack.exe` from the GitHub release. Updates come through the package manager (`winget upgrade`, `scoop update`, `choco upgrade`).

> **Channel status:** PowerShell Gallery and Scoop are live now. Chocolatey is submitted and in community moderation review. winget is awaiting its one-time first submission to `microsoft/winget-pkgs`. See [`dist/`](dist/) for per-channel details.

### Download & Run

Grab `RackStack.exe` from the [latest release](https://github.com/TheAbider/RackStack/releases/latest), drop it on your server, and run it as Administrator. That's it.

Every release artifact is signed with [Sigstore](https://www.sigstore.dev/) cosign (keyless) and carries [SLSA Level 3](https://slsa.dev/) build provenance; each release page lists SHA-256 hashes and the verification commands. The EXE is not Authenticode-signed, so Windows SmartScreen may show an "Unknown publisher" prompt on first run.

On first launch, a setup wizard walks you through configuring your environment (domain, DNS, admin account, iSCSI subnet). Your settings are saved to `defaults.json` next to the exe. To pre-configure, download `defaults.example.json` from the release, rename it to `defaults.json`, fill in your values, and place it alongside the exe.

<!--
<p align="center">
  <img src=".github/assets/screenshots/main-menu.png" alt="RackStack main interactive menu showing the 72-char box UI, category breadth, and theme rendering" width="800">
</p>
-->

The exe auto-checks for updates from GitHub releases. Your `defaults.json` is never overwritten by updates.

### From Source (Development)

```powershell
git clone https://github.com/TheAbider/RackStack.git
cd RackStack

# Run it (requires Administrator) -- first-run wizard creates defaults.json
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\RackStack.ps1
```

> **`RackStack.ps1`** is the **modular loader** (~130 lines). It dot-sources all 81 modules from `Modules/` and starts the tool. Use this for development -- edit individual module files, then run.

### Single-File Deployment (Production)

For production use, generate a monolithic single-file script (~66K lines) that you can drop on any server:

```powershell
# Build the monolithic from all modules
.\sync-to-monolithic.ps1
```

The output is **`RackStack v{version}.ps1`** -- a self-contained single file with all 81 modules baked in (version from `00-Initialization.ps1`). This is the file used to compile the `.exe`.

> **Don't confuse the two:** `RackStack.ps1` = modular loader for development. `RackStack v{version}.ps1` = monolithic build for deployment/compilation.

## Requirements

- **PowerShell 5.1+** (ships with Server 2016+; for older servers run `Install-Prerequisites.ps1` to auto-install [WMF 5.1](https://www.microsoft.com/en-us/download/details.aspx?id=54616))
- **Windows Server 2008 R2 SP1, 2012, 2012 R2, 2016, 2019, 2022, or 2025** (also runs on Windows 10/11 for development/testing)
- **Administrator privileges** (auto-elevates if needed)
- **Optional:** PSScriptAnalyzer (for linting), a file server for ISO/VHD downloads (see [File Server Setup](docs/FileServer-Setup.md))

## Documentation

In-depth guides live in [`docs/`](docs/):

| Topic | Guide |
|---|---|
| Full configuration reference | [Configuration](docs/Configuration.md) |
| Batch / headless server builds | [Batch Mode](docs/Batch-Mode.md) |
| Storage backends (iSCSI, FC, S2D, SMB3, NVMe-oF, Local) | [Storage Backends](docs/Storage-Backends.md) |
| Disk and volume management | [Storage Manager](docs/Storage-Manager.md) |
| Failover Clustering workflows | [Cluster Management](docs/Cluster-Management.md) |
| Hyper-V Replica setup | [Hyper-V Replica](docs/Hyper-V-Replica.md) |
| Promoting a server to Domain Controller | [AD DS Promotion](docs/AD-DS-Promotion.md) |
| Custom server role templates | [Server Role Templates](docs/Server-Role-Templates.md) |
| Exporting and diffing configuration profiles | [Configuration Export](docs/Configuration-Export.md) |
| Preparing VHD templates | [VHD Preparation](docs/VHD-Preparation.md) |
| File server for ISO / VHD / agent distribution | [File Server Setup](docs/FileServer-Setup.md) |
| Diagnostics and recovery | [Troubleshooting](docs/Troubleshooting.md) |
| Runbook: HA iSCSI build | [Runbook: HA iSCSI](docs/Runbook-HA-iSCSI.md) |
| Runbook: live host migration | [Runbook: Host Migration](docs/Runbook-Host-Migration.md) |
| Runbook: VM deployment | [Runbook: VM Deployment](docs/Runbook-VM-Deployment.md) |

## Configuration

Copy `defaults.example.json` to `defaults.json` and customize. The example file has every configurable field with comments — here's a quick-start subset:

```json
{
    "Domain": "corp.acme.com",
    "LocalAdminName": "localadmin",
    "LocalAdminFullName": "Local Administrator",
    "SwitchName": "LAN-SET",
    "ManagementName": "Management",
    "BackupName": "Backup",
    "AutoUpdate": false,
    "TempPath": "C:\\Temp",

    "DNSPresets": {
        "Corp DC Primary": ["10.0.1.10", "10.0.1.11"],
        "Corp DC Secondary": ["10.0.2.10", "10.0.2.11"]
    },

    "StorageBackendType": "iSCSI",

    "iSCSISubnet": "172.16.1",
    "SANTargetMappings": [
        { "Suffix": 10, "Label": "A0" },
        { "Suffix": 11, "Label": "B1" }
    ],
    "SANTargetPairings": {
        "Pairs": [
            { "Name": "Pair0", "A": 10, "B": 11 },
            { "Name": "Pair1", "A": 12, "B": 13 }
        ],
        "HostAssignments": [
            { "HostMod": 1, "PrimaryPair": "Pair0", "RetryOrder": ["Pair1"] },
            { "HostMod": 2, "PrimaryPair": "Pair1", "RetryOrder": ["Pair0"] }
        ],
        "CycleSize": 2
    },

    "CustomVNICs": [
        { "Name": "Cluster", "VLAN": 100 },
        { "Name": "Live Migration", "VLAN": 200 }
    ],

    "StoragePaths": {
        "HostVMStoragePath": "D:\\Virtual Machines",
        "HostISOPath": "D:\\ISOs",
        "ClusterISOPath": "C:\\ClusterStorage\\Volume1\\ISOs",
        "VHDCachePath": "D:\\Virtual Machines\\_BaseImages",
        "ClusterVHDCachePath": "C:\\ClusterStorage\\Volume1\\_BaseImages"
    },

    "VMNaming": {
        "SiteId": "",
        "Pattern": "{Site}-{Prefix}{Seq}",
        "SiteIdSource": "hostname",
        "SiteIdRegex": "^(\\d{3,6})-"
    },

    "AgentInstaller": {
        "ToolName": "MyRMM",
        "FolderName": "Agents",
        "FilePattern": "Agent_.*\\.exe$",
        "ServiceName": "MyRMM Agent*",
        "InstallArgs": "/s /norestart",
        "InstallPaths": ["%ProgramFiles%\\MyRMM", "%ProgramFiles(x86)%\\MyRMM"],
        "SuccessExitCodes": [0, 1641, 3010],
        "TimeoutSeconds": 300
    },

    "FileServer": {
        "StorageType": "nginx",
        "BaseURL": "https://files.acme.com/server-tools",
        "ClientId": "your-cloudflare-access-client-id.access",
        "ClientSecret": "your-cloudflare-access-client-secret",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    },

    "DefenderExclusionPaths": [
        "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V",
        "C:\\ClusterStorage"
    ],
    "DefenderCommonVMPaths": [
        "D:\\Virtual Machines",
        "E:\\Virtual Machines"
    ],

    "CustomKMSKeys": {
        "Windows Server 2022": { "Standard": "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" }
    },
    "CustomAVMAKeys": {
        "Windows Server 2022": { "Standard": "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" }
    },

    "CustomVMTemplates": {
        "FS": { "MemoryGB": 16 },
        "SQL": {
            "FullName": "SQL Server", "Prefix": "SQL", "OSType": "Windows",
            "vCPU": 8, "MemoryGB": 32, "MemoryType": "Static",
            "Disks": [{"Name": "OS", "SizeGB": 150, "Type": "Fixed"},
                      {"Name": "Data", "SizeGB": 500, "Type": "Fixed"}],
            "NICs": 1
        }
    },
    "CustomVMDefaults": {
        "vCPU": 4, "MemoryGB": 8, "DiskSizeGB": 100
    },

    "CustomRoleTemplates": {
        "MYAPP": {
            "FullName": "Custom App Server",
            "Description": "Features for a custom application stack",
            "Features": ["Web-Server", "NET-Framework-45-Core"],
            "RequiresReboot": false,
            "ServerOnly": true
        }
    }
}
```

| Field | What it does |
|---|---|
| `Domain` | Default Active Directory domain for domain join |
| `LocalAdminName` / `LocalAdminFullName` | Local administrator account name and display name |
| `SwitchName` / `ManagementName` / `BackupName` | Hyper-V virtual switch and vNIC names |
| `AutoUpdate` | Auto-download and install updates on startup without prompting (default: `false`) |
| `TempPath` | Directory for transcripts, reports, and exports (default: `C:\Temp`) |
| `DNSPresets` | Custom DNS server presets, merged with built-in (Google, Cloudflare, Quad9, OpenDNS) |
| `StorageBackendType` | Shared storage backend: `iSCSI`, `FC`, `S2D`, `SMB3`, `NVMeoF`, or `Local` (default: `iSCSI`) |
| `iSCSISubnet` | First 3 octets of your iSCSI network |
| `SANTargetMappings` | SAN target IP suffix-to-label mappings for iSCSI auto-detect |
| `SANTargetPairings` | Advanced: custom A/B pair definitions, host-to-pair assignments, and retry order for multi-controller SANs |
| `CustomVNICs` | Virtual NICs to create on the virtual switch during batch mode (`Name` + optional `VLAN`) |
| `StoragePaths` | Default Hyper-V storage paths (VM storage, ISOs, VHD cache, cluster paths) |
| `VMNaming` | VM naming pattern with tokens (`{Site}`, `{Prefix}`, `{Seq}`), site ID source and regex |
| `AgentInstaller` | Primary MSP agent installer config: tool name, service name, file pattern, install args, paths, exit codes |
| `AdditionalAgents` | Array of additional agent installer configs (same schema as `AgentInstaller`) for multi-agent environments |
| `FileServer` | File server / cloud storage for ISO/VHD downloads: nginx, Azure Blob, or static JSON (see [File Server Setup](docs/FileServer-Setup.md)) |
| `DefenderExclusionPaths` / `DefenderCommonVMPaths` | Windows Defender exclusion paths for Hyper-V hosts and VM storage |
| `CustomKMSKeys` / `CustomAVMAKeys` | Org-specific license keys, merged with built-in Microsoft GVLK/AVMA tables |
| `CustomVMTemplates` | Override built-in VM template specs or add new templates (partial overrides supported) |
| `CustomVMDefaults` | Default vCPU, RAM, disk size/type for non-template (custom) VMs |
| `CustomRoleTemplates` | Add custom server role templates with Windows features, merged with 10 built-in templates |
| `TimeZoneRegion` | Skip the timezone continent picker and jump to a region (e.g. `"North America"`, `"Europe"`); empty = show picker |
| `MonitoredServices` | List of services the health dashboard alerts on if not running |
| `DryRun` | Global preview mode for batch and CLI actions; `true` reports what would change without making changes |
| `DashboardWarningPercent` / `DashboardCriticalPercent` | CPU/memory/disk thresholds for color-coded warnings on the main menu dashboard (defaults 70 / 90) |
| `Timeouts` | Override per-operation timeouts (CIM queries, DNS resolves, network probes); seconds |
| `CLIDefaults` | Per-action defaults for headless invocations (e.g. default `Tier` for `Cleanup`, default `Config` path) |

> `defaults.json` is gitignored -- your secrets never leave your machine.

## Batch Mode

Automate full server builds with a JSON config file:

```json
{
    "ConfigType": "VM",
    "Hostname": "WEB-01",
    "IPAddress": "10.0.1.100",
    "SubnetCIDR": 24,
    "Gateway": "10.0.1.1",
    "DNS1": "10.0.1.10",
    "DomainName": "corp.example.com",
    "EnableRDP": true,
    "SetPowerPlan": "High Performance",
    "CreateLocalAdmin": true,
    "InstallAgents": ["MyRMM", "ExampleRMM"],
    "ValidateCluster": false,
    "AutoReboot": true
}
```

Place `batch_config.json` next to the script and it runs automatically on launch. Set fields to `null` to skip steps. All steps are idempotent -- re-running the same config safely skips already-completed items. Use `ConfigType: "HOST"` for Hyper-V hosts -- adds extra steps (SET switch, custom vNICs, iSCSI, MPIO, host storage, Defender exclusions, agent install, cluster validation) for a total of 24 automated steps with transaction rollback on failure.

Use `InstallAgents` for multi-agent installs and `ValidateCluster` for pre-deployment cluster readiness checks.

## CLI Headless Mode

Run RackStack non-interactively for automation (Ansible, RMM tools, PDQ, remote scripts):

```powershell
# Quick health + disk + debloat assessment
RackStack.exe -Action QuickScan -Silent

# Disk cleanup (Standard profile)
RackStack.exe -Action Cleanup -Tier Standard -Silent

# System debloat (Aggressive, auto-detects Server vs Workstation)
RackStack.exe -Action Debloat -Tier Aggressive -Silent

# Run a batch config JSON file
RackStack.exe -Action Batch -Config "C:\path\to\config.json" -Silent

# Server inventory for CMDB/asset management
RackStack.exe -Action Inventory -OutputFormat JSON -Silent
```

### One-Liner Remote Deployment

Download and run the latest release in one command:

```powershell
# Download + QuickScan (default)
irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1 | iex

# Download + specific action
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $s = irm https://raw.githubusercontent.com/TheAbider/RackStack/master/Install-RackStack.ps1; $s | Set-Content rs.ps1; .\rs.ps1 -Action Cleanup -Tier Standard -Silent }"
```

### Ansible Example

```yaml
- name: Run RackStack cleanup on Windows hosts
  win_shell: |
    $url = 'https://github.com/TheAbider/RackStack/releases/latest/download/RackStack.exe'
    Invoke-WebRequest -Uri $url -OutFile C:\Temp\RackStack.exe -UseBasicParsing
    C:\Temp\RackStack.exe -Action Cleanup -Tier Standard -Silent
```

### JSON Output Mode

Add `-OutputFormat JSON` to get structured, machine-readable output from HealthCheck and QuickScan actions. Useful for feeding results into monitoring dashboards, alerting pipelines, or Ansible `register`:

```powershell
# JSON health check
RackStack.exe -Action HealthCheck -OutputFormat JSON -Silent

# Parse JSON in PowerShell
$report = (.\RackStack.exe -Action HealthCheck -OutputFormat JSON -Silent | ConvertFrom-Json).Report
$report.Sections.CPU
$report.Issues

# Ansible: capture JSON output
# - name: Health check
#   win_shell: C:\Temp\RackStack.exe -Action HealthCheck -OutputFormat JSON -Silent
#   register: health_result
# - set_fact:
#     health: "{{ health_result.stdout | from_json }}"
```

<!--
<p align="center">
  <img src=".github/assets/screenshots/server-score.png" alt="RackStack ServerScore CLI output showing the unified 0-100 health grade alongside structured JSON output for fleet automation" width="800">
</p>
-->

**Exit codes:** `0` = success, `1` = error. All CLI actions return proper exit codes for CI/CD integration.

**Tiers:** `Light` (minimal, safe for prod), `Standard` (recommended), `Aggressive` (maximum cleanup/debloat).

### 201 CLI Actions

| Category | Actions |
|----------|---------|
| **System Ops** | `Cleanup` `Debloat` `HealthCheck` `QuickScan` `Batch` `Remediate` `Win11Cleanup` `DarkMode` `LightMode` |
| **Inventory** | `Inventory` `Export` `SysInfoAudit` `BIOSAudit` `SoftwareList` `HotfixAudit` `FeatureAudit` `DotNetAudit` `WindowsCapabilityAudit` |
| **Monitoring** | `Snapshot` `Trend` `Watch` `Alert` `Uptime` `SLAReport` `CPUAudit` `MemoryAudit` `DiskAudit` `TempAudit` `EventLogCapacityAudit` |
| **Compliance** | `Compliance` `PolicyCheck` `DriftCheck` `Diff` `Baseline` `BaselineDiff` `Compare` `Aggregate` `Validate` `Readiness` `ReportHTML` |
| **Security** | `Harden` `RegistryAudit` `TLSAudit` `CredGuardAudit` `AuditPolicyAudit` `AppLockerAudit` `DefenderExclusionAudit` `TokenPrivilegeAudit` `PasswordPolicy` `TPMAudit` `SecureBootAudit` `InsecureServiceAudit` |
| **Identity** | `UserAudit` `LocalGroupAudit` `LogonAudit` `ServiceAccountAudit` `KerberosAudit` `ACLAudit` |
| **Network** | `NetInfo` `NetMap` `DNSAudit` `DNSCacheAudit` `NetworkAudit` `NetworkProfileAudit` `ListeningPorts` `NetStatAudit` `PortAudit` `ProxyAudit` `DHCPAudit` `VPNAudit` `ARPTableAudit` `NICTeamAudit` `TcpSettingsAudit` `SMBConnectionAudit` |
| **Firewall** | `FirewallAudit` `FirewallLogAudit` `FirewallRuleAudit` |
| **Storage** | `StorageAudit` `ShareAudit` `SMBAudit` `SMBSessionAudit` `BitLockerAudit` `NTFSAudit` `PageFileAudit` `ProfileAudit` `iSCSIAudit` |
| **Services** | `ServiceAudit` `TaskAudit` `TaskHistoryAudit` `EventAudit` `PrintAudit` `IISAudit` `SSHAudit` `WinRMAudit` |
| **Drivers/HW** | `DriverAudit` `USBDeviceAudit` `PowerAudit` `NUMAAudit` `NICOffloadAudit` `NICErrorAudit` |
| **Time/Boot** | `TimeAudit` `TimeSkewAudit` `BootAudit` `PendingRebootAudit` `ScheduledRebootAudit` `RecoveryAudit` `LocaleAudit` |
| **Patching** | `PatchStatus` `WindowsUpdateAudit` `CertCheck` `UpdatePolicyAudit` `LicenseAudit` `AntivirusAudit` |
| **Infra** | `HyperVAudit` `ClusterAudit` `ClusterQuorumAudit` `ClusterNetworkAudit` `ClusterHealthScore` `BackupAudit` `GPOAudit` `WMIAudit` `PowerShellAudit` `RouteTableAudit` `HealthDashboard` `ServerScore` |
| **System Center** | `SCCMClientAudit` `SCOMAgentAudit` `WACConnectivityAudit` `AzureADAudit` |
| **Hyper-V** | `VMOvercommitAudit` `ReplicaLagAudit` `LiveMigrationAudit` `VirtualSwitchAudit` `VMInventoryExport` `VMSnapshotAudit` `VMResourceWaste` |
| **Storage** (ext) | `S2DAudit` `DedupAudit` `MPIOPathAudit` `ShadowCopyAudit` `QoSPolicyAudit` `DiskLatencyAudit` `StorageTimeoutAudit` `StorageHealthScore` `VolumeLabelAudit` |
| **Services** (ext) | `ServiceRecoveryAudit` `HandleLeakAudit` |
| **Persistence** | `AutoStartAudit` `EventSubAudit` `ComObjectAudit` `SymlinkAudit` `StartupScriptAudit` `HostsFileAudit` |
| **Domain** | `SecureChannelAudit` `DomainTrustAudit` `GPResultAudit` `ScheduledExport` `ValidateConfig` `EnvAudit` `CrashAudit` `ProcessAudit` |
| **Fleet** | `FleetScan` `FleetReport` `Query` `RotateExports` `RDPAudit` |
| **Cloud & Security** | `AzureArcEnroll` `DefenderEndpointOnboard` |
| **Update Server** | `WSUSSetup` |
| **PKI** | `ADCSSetup` |
| **Migration** | `StorageMigrationSetup` |

Run `RackStack.exe -ListActions` or `RackStack.exe -ListActions -OutputFormat JSON` for the full list with descriptions.

## Project Structure

```
RackStack/
├── RackStack.ps1               # Modular loader -- dot-sources 81 modules (dev use)
├── RackStack v{version}.ps1    # Monolithic build -- all modules in one file (deploy/compile)
├── RackStack.exe               # Compiled from the monolithic .ps1 via ps2exe
├── defaults.json               # Your environment config (gitignored)
├── defaults.example.json       # Config template with examples
├── sync-to-monolithic.ps1      # Builds monolithic from Header.ps1 + Modules/
├── Modules/
│   ├── 00-Initialization.ps1   # Constants, variables, config loading
│   ├── 01-Console.ps1          # Console window management
│   ├── ...                     # 75 more modules
│   └── 77-WindowsAdminCenter.ps1
├── Tests/
│   ├── Run-Tests.ps1           # 5,048 automated tests
│   ├── Validate-Release.ps1    # Pre-release validation suite
│   └── ...
└── docs/
    └── FileServer-Setup.md     # Set up your own ISO/VHD file server
```

### Module Architecture

81 modules numbered for load order. Dependencies flow downward.

| Range | Category | Highlights |
|---|---|---|
| 00-05 | **Core** | Variables, console, logging, input validation, navigation, OS detection |
| 06-14 | **Networking** | Adapters, IP config, VLANs, SET, iSCSI, hostname, domain, DNS, NTP |
| 15-24 | **System** | RDP, firewall, Defender, NTP, updates, licensing, passwords, local admin |
| 25-33 | **Roles** | Hyper-V, MPIO, clustering, performance, events, services, BitLocker |
| 34-39 | **Tools** | Help, utilities, batch config, health check, storage manager, cloud |
| 40-44 | **VM Pipeline** | Host storage, VHD management, ISO downloads, offline VHD, VM deployment |
| 45-50 | **Session** | Config export, session summary, cleanup, menus, entry point |
| 51-59 | **Extended** | Cluster dashboard, checkpoints, export/import, HTML reports, QoL, operations, remote, diagnostics, storage backends |
| 60-64 | **Server Roles** | Role templates, AD DS promotion, Hyper-V Replica, scheduled tasks, system debloat |
| 65-66 | **Cloud & Security** | Azure Arc server onboarding, Microsoft Defender for Endpoint onboarding |
| 67    | **Update Server** | WSUS install, post-install, configuration, and sync |
| 68    | **PKI** | AD CS Certificate Authority bootstrap |
| 69    | **Migration** | Storage Migration Service role setup |
| 70    | **Dry Run** | Preview-and-commit mode for batch + CLI actions |
| 71    | **Group Policy** | GPO backup, restore, and drift detection |
| 72    | **JEA** | Just Enough Administration constrained endpoints |
| 73    | **NPS** | Network Policy Server (RADIUS) for 802.1X / VPN auth |
| 74    | **Always-On VPN** | Remote Access (RRAS) VPN gateway + ProfileXML generation |
| 75    | **Compliance** | CIS Windows Server L1 benchmark scanner (read-only, scored) |
| 76    | **SIEM Forwarder** | WEF / Splunk / Winlogbeat log forwarding + Sentinel readiness |
| 77    | **Windows Admin Center** | WAC gateway install (verified MSI) + port / TLS cert config |

## Testing

```powershell
# Full test suite (5,048 tests, ~4 minutes)
powershell -ExecutionPolicy Bypass -File Tests\Run-Tests.ps1

# PSScriptAnalyzer (0 errors on all 81 modules + monolithic)
powershell -ExecutionPolicy Bypass -File Tests\pssa-check.ps1

# Pre-release validation (parse + PSSA + structure + sync + version + tests)
powershell -ExecutionPolicy Bypass -File Tests\Validate-Release.ps1
```

Tests cover parsing, module loading, function existence (615 functions), version consistency, sync verification, input validation, navigation, hostname parsing, color themes, box widths, audit logging, custom vNIC features, iSCSI cabling checks, storage backend functions, and more.

## Development

1. Edit modules in `Modules/`
2. Test with `.\RackStack.ps1` (modular loader -- fast iteration, no build step)
3. Sync: `.\sync-to-monolithic.ps1` (builds `RackStack v{version}.ps1` monolithic)
4. Test: `.\Tests\Run-Tests.ps1`
5. Compile: `Invoke-PS2EXE -InputFile 'RackStack v{ver}.ps1' -OutputFile 'RackStack.exe'`

The sync script matches `#region`/`#endregion` markers between modules and the monolithic file. All 77 region pairs are flat (non-nested). Use `-DryRun` to preview.

> **File summary:** `RackStack.ps1` = modular loader (for dev). `RackStack v{version}.ps1` = monolithic build (for deployment). `RackStack.exe` = compiled from monolithic (for end users).

### Conventions

- 72-char inner width for all menu boxes
- Semantic colors: `Success`, `Warning`, `Error`, `Info`, `Debug`, `Critical`, `Verbose`
- `Write-MenuItem` for menu item rendering (theme-aware, supports status columns)
- `$null -eq $var` form for null checks (PSSA requirement)
- `$regexMatches` instead of `$matches` (reserved automatic variable)
- PowerShell verb-noun naming (`Test-`, `Get-`, `Set-`, `Show-`, `Start-`)

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Acknowledgments

Special thanks to Ravi -- whose existence provided the spite-fueled motivation to build this entire project from scratch. Every feature is a testament to what happens when someone says "you can't automate that."

## License

[MIT](LICENSE) -- use it, fork it, ship it.
