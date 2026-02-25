<p align="center">
  <img src=".github/assets/banner.png" alt="RackStack" width="100%">
</p>
<p align="center">
  <strong>The PowerShell toolkit that turns bare metal into production-ready Windows Servers.</strong>
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
  <img alt="CI" src="https://github.com/TheAbider/RackStack/actions/workflows/ci.yml/badge.svg">
  <img alt="License MIT" src="https://img.shields.io/badge/license-MIT-green">
  <img alt="PSScriptAnalyzer 0 errors" src="https://img.shields.io/badge/PSScriptAnalyzer-0%20errors-brightgreen">
</p>

---

RackStack is a menu-driven PowerShell tool that automates everything between "Windows is installed" and "server is in production." Think of it as **sconfig for the modern era** -- but instead of 15 options, you get 60+ automated tasks covering network configuration, Hyper-V deployment, SAN/iSCSI setup, domain join, licensing, VM creation, health monitoring, drift detection, and batch automation -- all through an interactive console UI with undo support, transaction rollback, and audit logging.

Built for MSPs, sysadmins, and infrastructure teams who build servers repeatedly and want it done right every time.

## Features

**Networking** -- Static IP with rollback, VLAN tagging, Switch Embedded Teaming (auto-detect), custom SET vNICs (Backup, Cluster, Live Migration, Storage, or custom names with VLAN), DNS presets, iSCSI/SAN with A/B side MPIO and cabling auto-detect

**Storage Backends** -- Pluggable storage backend (iSCSI, Fibre Channel, Storage Spaces Direct, SMB3, NVMe-oF, Local); auto-detection from system state; per-backend management menus; generalized MPIO dispatching; all batch mode steps adapt to the selected backend

**Hyper-V** -- Role install, configurable VM templates (override specs or add new via `defaults.json`), batch queue deployment, VHD management, offline registry injection, Secure Boot Gen 2, cluster CSV support

**Server Roles** -- Failover Clustering, MPIO, BitLocker, Deduplication, Storage Replica, 14 disk operations

**Security** -- RDP/NLA, firewall templates, Windows Defender exclusions, local admin with complexity enforcement, Windows licensing (GVLK 2008-2025, AVMA 2012R2-2025)

**Automation** -- JSON-driven batch mode (24 idempotent steps with transaction rollback), Quick Setup Wizard, configuration export/import, HTML reports, JSON audit logging with rotation

**Monitoring & Diagnostics** -- Health dashboard (disk I/O latency, NIC errors, memory pressure, Hyper-V guest health, top CPU processes), performance snapshots with trend reports and "days until full" estimates, event log viewer, service manager, network diagnostics (ping, traceroute, port test, subnet sweep, DNS, ARP)

**Drift Detection** -- Save configuration baselines, compare snapshots over time, track setting changes across baselines, auto-baseline after batch mode

**VM Deployment Safety** -- Pre-flight validation (disk, RAM, vCPU ratio, switches, VHDs) with OK/WARN/FAIL table, post-deploy smoke tests (heartbeat, NIC, IP, ping, RDP), batch queue with summary

**Multi-Agent Support** -- Configure and manage multiple RMM/MSP agent installers from a single interface, batch install via `InstallAgents` config array

**Remote Ops** -- Remote PowerShell sessions, remote health checks, remote service management

**UX** -- 5 color themes, session resume, favorites, command history, undo framework, 72-char box-drawing UI

## Quick Start

### Download & Run (recommended)

Grab `RackStack.exe` from the [latest release](https://github.com/TheAbider/RackStack/releases/latest), drop it on your server, and run it as Administrator. That's it.

On first launch, a setup wizard walks you through configuring your environment (domain, DNS, admin account, iSCSI subnet). Your settings are saved to `defaults.json` next to the exe. To pre-configure, download `defaults.example.json` from the release, rename it to `defaults.json`, fill in your values, and place it alongside the exe.

The exe auto-checks for updates from GitHub releases. Your `defaults.json` is never overwritten by updates.

### From Source (Development)

```powershell
git clone https://github.com/TheAbider/RackStack.git
cd RackStack

# Run it (requires Administrator) -- first-run wizard creates defaults.json
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\RackStack.ps1
```

> **`RackStack.ps1`** is the **modular loader** (~130 lines). It dot-sources all 63 modules from `Modules/` and starts the tool. Use this for development -- edit individual module files, then run.

### Single-File Deployment (Production)

For production use, generate a monolithic single-file script (~32K lines) that you can drop on any server:

```powershell
# Build the monolithic from all modules
.\sync-to-monolithic.ps1
```

The output is **`RackStack v{version}.ps1`** -- a self-contained single file with all 63 modules baked in (version from `00-Initialization.ps1`). This is the file used to compile the `.exe`.

> **Don't confuse the two:** `RackStack.ps1` = modular loader for development. `RackStack v1.5.6.ps1` = monolithic build for deployment/compilation.

## Requirements

- **PowerShell 5.1+** (ships with Server 2016+; for older servers run `Install-Prerequisites.ps1` to auto-install [WMF 5.1](https://www.microsoft.com/en-us/download/details.aspx?id=54616))
- **Windows Server 2008 R2 SP1, 2012, 2012 R2, 2016, 2019, 2022, or 2025** (also runs on Windows 10/11 for development/testing)
- **Administrator privileges** (auto-elevates if needed)
- **Optional:** PSScriptAnalyzer (for linting), a file server for ISO/VHD downloads (see [File Server Setup](docs/FileServer-Setup.md))

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
        "ToolName": "Kaseya",
        "FolderName": "Agents",
        "FilePattern": "Kaseya.*\\.exe$",
        "ServiceName": "Kaseya Agent*",
        "InstallArgs": "/s /norestart",
        "InstallPaths": ["%ProgramFiles%\\Kaseya", "%ProgramFiles(x86)%\\Kaseya"],
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
    "InstallAgents": ["Kaseya", "ExampleRMM"],
    "ValidateCluster": false,
    "AutoReboot": true
}
```

Place `batch_config.json` next to the script and it runs automatically on launch. Set fields to `null` to skip steps. All steps are idempotent -- re-running the same config safely skips already-completed items. Use `ConfigType: "HOST"` for Hyper-V hosts -- adds extra steps (SET switch, custom vNICs, iSCSI, MPIO, host storage, Defender exclusions, agent install, cluster validation) for a total of 24 automated steps with transaction rollback on failure.

New in v1.8.0: `InstallAgents` array for multi-agent installs, `ValidateCluster` for cluster readiness checks.

## Project Structure

```
RackStack/
├── RackStack.ps1               # Modular loader -- dot-sources 63 modules (dev use)
├── RackStack v1.5.6.ps1        # Monolithic build -- all modules in one file (deploy/compile)
├── RackStack.exe               # Compiled from the monolithic .ps1 via ps2exe
├── defaults.json               # Your environment config (gitignored)
├── defaults.example.json       # Config template with examples
├── sync-to-monolithic.ps1      # Builds monolithic from Header.ps1 + Modules/
├── Modules/
│   ├── 00-Initialization.ps1   # Constants, variables, config loading
│   ├── 01-Console.ps1          # Console window management
│   ├── ...                     # 61 more modules
│   └── 62-HyperVReplica.ps1
├── Tests/
│   ├── Run-Tests.ps1           # 1659 automated tests
│   ├── Validate-Release.ps1    # Pre-release validation suite
│   └── ...
└── docs/
    └── FileServer-Setup.md     # Set up your own ISO/VHD file server
```

### Module Architecture

63 modules numbered for load order. Dependencies flow downward.

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
| 60-62 | **Server Roles** | Role templates, AD DS promotion, Hyper-V Replica management |

## Testing

```powershell
# Full test suite (~1,834 tests, ~2 minutes)
powershell -ExecutionPolicy Bypass -File Tests\Run-Tests.ps1

# PSScriptAnalyzer (0 errors on all 63 modules + monolithic)
powershell -ExecutionPolicy Bypass -File Tests\pssa-check.ps1

# Pre-release validation (parse + PSSA + structure + sync + version + tests)
powershell -ExecutionPolicy Bypass -File Tests\Validate-Release.ps1
```

Tests cover parsing, module loading, function existence (300+), version consistency, sync verification, input validation, navigation, hostname parsing, color themes, box widths, audit logging, custom vNIC features, iSCSI cabling checks, storage backend functions, and more.

## Development

1. Edit modules in `Modules/`
2. Test with `.\RackStack.ps1` (modular loader -- fast iteration, no build step)
3. Sync: `.\sync-to-monolithic.ps1` (builds `RackStack v{version}.ps1` monolithic)
4. Test: `.\Tests\Run-Tests.ps1`
5. Compile: `Invoke-PS2EXE -InputFile 'RackStack v{ver}.ps1' -OutputFile 'RackStack.exe'`

The sync script matches `#region`/`#endregion` markers between modules and the monolithic file. All 62 region pairs are flat (non-nested). Use `-DryRun` to preview.

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
