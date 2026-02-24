# Configuration Guide

RackStack is configured via `defaults.json`, placed alongside the executable or script. On first launch without a config file, the setup wizard walks you through creating one.

Copy `defaults.example.json` to `defaults.json` and customize for your environment.

> `defaults.json` is gitignored -- your secrets never leave your machine.

---

## Example Configuration

```json
{
    "Domain": "corp.acme.com",
    "LocalAdminName": "localadmin",
    "SwitchName": "LAN-SET",
    "DNSPresets": {
        "Corp DC": ["10.0.1.10", "10.0.1.11"]
    },
    "iSCSISubnet": "172.16.1",
    "CustomKMSKeys": {
        "Windows Server 2022": {
            "Standard": "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
        }
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
    }
}
```

---

## Configuration Reference

| Field | What it does |
|---|---|
| `AutoUpdate` | Auto-download and install updates on startup without prompting (default: `false`) |
| `Domain` | Default Active Directory domain for domain join |
| `LocalAdminName` | Local administrator account name |
| `TempPath` | Directory for transcripts, reports, and exports (default: `C:\Temp`) |
| `DNSPresets` | Custom DNS server presets, merged with built-in (Google, Cloudflare, Quad9, OpenDNS) |
| `iSCSISubnet` | First 3 octets of your iSCSI network |
| `SANTargetMappings` | SAN target IP suffix-to-label mappings for iSCSI auto-detect |
| `SANTargetPairings` | Advanced: Custom A/B pair definitions and host-to-pair assignments with retry order |
| `DefenderExclusionPaths` | Windows Defender exclusion paths for Hyper-V hosts |
| `DefenderCommonVMPaths` | Common VM storage paths added to Defender exclusions (auto-generated if not set) |
| `StoragePaths` | Default Hyper-V storage paths (VM storage, ISOs, VHD cache, cluster paths) |
| `AgentInstaller` | MSP agent installer config: tool name, service name, file pattern, install args, paths, exit codes |
| `CustomKMSKeys` / `CustomAVMAKeys` | Org-specific license keys, merged with built-in Microsoft GVLK/AVMA tables |
| `VMNaming` | VM naming pattern, site ID source, and detection regex |
| `CustomVMTemplates` | Override built-in VM template specs or add new templates (partial overrides supported) |
| `CustomVMDefaults` | Default vCPU, RAM, disk size/type for non-template (custom) VMs |
| `StorageBackendType` | Storage backend selection: iSCSI, FC, S2D, SMB3, NVMeoF, or Local (see [Storage Backends](Storage-Backends)) |
| `CustomRoleTemplates` | Custom server role templates, merged with 10 built-in templates (see [Server Role Templates](Server-Role-Templates)) |
| `FileServer` | File server credentials for ISO/VHD downloads (see [File Server Setup](File-Server-Setup)) |

> **New in v1.2.0:** Custom SET vNICs, iSCSI A/B side auto-detect, `AgentFolder` rename. See sections below.

> **New in v1.3.0:** Storage backend selection and auto-detection. Six backends supported: iSCSI, FC, S2D, SMB3, NVMeoF, Local. See [Storage Backends](Storage-Backends).

> **New in v1.4.0:** Server role templates, AD DS promotion, Hyper-V Replica, batch mode expanded to 22 steps. See [Server Role Templates](Server-Role-Templates), [AD DS Promotion](AD-DS-Promotion), [Hyper-V Replica](Hyper-V-Replica).

> **New in v1.5.0:** Custom SAN target pairings (configurable A/B pair assignments per host), flexible virtual switch management (External, Internal, Private switches in addition to SET). See [SANTargetPairings](#santargetpairings-v150) and [Virtual Switch Management](#virtual-switch-management-v150).

> **New in v1.5.5:** Cloud storage support -- FileServer module natively supports Azure Blob Storage (`StorageType: "azure"`) and static JSON index files (`StorageType: "static"`) for S3/CloudFront. See [FileServer](#fileserver-file-server) and [File Server Setup](File-Server-Setup).

---

## Field Details

### AutoUpdate

```json
"AutoUpdate": true
```

When `true`, RackStack automatically downloads and installs updates from GitHub releases on startup without prompting. If the internet is not available at startup, it retries after the network is configured. Default: `false`.

### Domain

```json
"Domain": "corp.acme.com"
```

The default Active Directory domain used for domain join operations. If empty, the domain join menu will prompt for it.

### DNS Presets

```json
"DNSPresets": {
    "Acme DC Primary": ["10.0.1.10", "10.0.1.11"],
    "Acme DC Secondary": ["10.0.2.10", "10.0.2.11"]
}
```

Custom DNS server presets that are **merged** with the built-in presets (Google DNS, Cloudflare, OpenDNS, Quad9). Your custom presets appear at the top of the list when configuring DNS.

### iSCSI Subnet

```json
"iSCSISubnet": "172.16.1"
```

The first 3 octets of your iSCSI network. Used by auto-configuration to calculate host iSCSI IPs and SAN target addresses.

### SAN Target Mappings

```json
"SANTargetMappings": [
    { "Suffix": 10, "Label": "A0" },
    { "Suffix": 11, "Label": "B1" },
    { "Suffix": 12, "Label": "B0" },
    { "Suffix": 13, "Label": "A1" }
]
```

Maps the last octet of SAN target IPs to labels (A-side/B-side controller ports). Used by the iSCSI auto-detect and discovery features.

### SANTargetPairings (v1.5.0)

```json
"SANTargetPairings": {
    "Pairs": [
        { "Name": "Pair0", "A": 10, "B": 11, "ALabel": "A0", "BLabel": "B0" },
        { "Name": "Pair1", "A": 12, "B": 13, "ALabel": "A1", "BLabel": "B1" },
        { "Name": "Pair2", "A": 14, "B": 15, "ALabel": "A2", "BLabel": "B2" },
        { "Name": "Pair3", "A": 16, "B": 17, "ALabel": "A3", "BLabel": "B3" }
    ],
    "HostAssignments": [
        { "HostMod": 1, "PrimaryPair": "Pair0", "RetryOrder": ["Pair2", "Pair1", "Pair3"] },
        { "HostMod": 2, "PrimaryPair": "Pair1", "RetryOrder": ["Pair3", "Pair0", "Pair2"] },
        { "HostMod": 3, "PrimaryPair": "Pair2", "RetryOrder": ["Pair0", "Pair3", "Pair1"] },
        { "HostMod": 4, "PrimaryPair": "Pair3", "RetryOrder": ["Pair1", "Pair2", "Pair0"] }
    ],
    "CycleSize": 4
}
```

Advanced SAN target pair configuration. Overrides the default cycling pattern for users with different SAN topologies.

**Convention:** A side = even suffixes, B side = odd suffixes. Each "Pair" represents one port on each controller (e.g., Pair0 = port 0 on controller A + port 0 on controller B).

| Field | Description |
|-------|-------------|
| `Pairs[].Name` | Label for the pair, referenced by HostAssignments |
| `Pairs[].A` / `Pairs[].B` | Last-octet suffixes for A-side (even) and B-side (odd) targets |
| `Pairs[].ALabel` / `Pairs[].BLabel` | Optional display labels (auto-generated if omitted) |
| `HostAssignments[].HostMod` | Host number mod CycleSize + 1 (host 1 = HostMod 1, host 5 = HostMod 1) |
| `HostAssignments[].PrimaryPair` | Which pair to try first for this host group |
| `HostAssignments[].RetryOrder` | Fallback pairs in order when primary is unreachable |
| `CycleSize` | Pattern repeats every N hosts (usually matches number of pairs) |

**How host assignment works:** `HostMod = ((HostNumber - 1) % CycleSize) + 1`. With CycleSize 4: host 1 maps to HostMod 1, host 2 to 2, ..., host 5 back to 1.

When omitted (`null`), RackStack uses the default mod-4 cycling pattern derived from `SANTargetMappings`.

### Storage Paths

```json
"StoragePaths": {
    "HostVMStoragePath": "D:\\Virtual Machines",
    "HostISOPath": "D:\\ISOs",
    "ClusterISOPath": "C:\\ClusterStorage\\Volume1\\ISOs",
    "VHDCachePath": "D:\\Virtual Machines\\_BaseImages",
    "ClusterVHDCachePath": "C:\\ClusterStorage\\Volume1\\_BaseImages"
}
```

Default storage paths for Hyper-V hosts. Drive letters are updated by Host Storage Setup when you select a different data drive.

### Agent Installer

```json
"AgentInstaller": {
    "ToolName": "Kaseya",
    "FolderName": "Agents",
    "FilePattern": "Kaseya.*\\.exe$",
    "ServiceName": "Kaseya Agent*",
    "InstallArgs": "/s /norestart",
    "InstallPaths": [
        "%ProgramFiles%\\Kaseya",
        "%ProgramFiles(x86)%\\Kaseya",
        "C:\\kworking"
    ],
    "SuccessExitCodes": [0, 1641, 3010],
    "TimeoutSeconds": 300
}
```

Configures the MSP agent installer. Customize for your RMM tool:
- `ToolName` -- Display name in menus and messages
- `FolderName` -- Subfolder name on the file server
- `FilePattern` -- Regex to match installer filenames
- `ServiceName` -- Windows service name pattern to check if already installed
- `InstallArgs` -- Silent install command-line arguments
- `InstallPaths` -- Directories to check for existing installation
- `SuccessExitCodes` -- Exit codes that indicate successful installation
- `TimeoutSeconds` -- Max wait time for installation to complete

### VM Naming

```json
"VMNaming": {
    "SiteId": "",
    "Pattern": "{Site}-{Prefix}{Seq}",
    "SiteIdSource": "hostname",
    "SiteIdRegex": "^(\\d{3,6})-"
}
```

Controls how VM names are generated during deployment:
- `SiteId` -- Static site identifier override. If set (non-empty) with `SiteIdSource: "static"`, skips auto-detection.
- `Pattern` -- Token-based naming pattern. Available tokens: `{Site}`, `{Prefix}`, `{Seq}`. Use `{Seq:00}` for zero-padded sequence numbers.
- `SiteIdSource` -- How to get the site ID: `"hostname"` (extract from `$env:COMPUTERNAME` using regex) or `"static"` (always use `SiteId` value).
- `SiteIdRegex` -- Regex with capture group to extract site ID from hostname.

**Examples:**

| Pattern | SiteId / Regex | Result |
|---------|---------------|--------|
| `{Site}-{Prefix}{Seq}` | Regex `^(\d{6})-` | `123456-FS1` |
| `{Site}-{Prefix}-{Seq:00}` | Static `CRV` | `CRV-DC-01` |
| `{Prefix}{Seq}` | (no site) | `FS1` |
| `{Site}{Prefix}{Seq:00}` | Static `ACME` | `ACMEDC01` |

### Custom KMS Keys

```json
"CustomKMSKeys": {
    "Windows Server 2022": {
        "Standard": "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX",
        "Datacenter": "YYYYY-YYYYY-YYYYY-YYYYY-YYYYY"
    }
}
```

Organization-specific KMS keys, **merged** with the built-in Microsoft GVLK keys (2008-2025). Use these if your KMS server uses custom keys.

### Custom AVMA Keys

```json
"CustomAVMAKeys": {
    "Windows Server 2022": {
        "Standard": "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
    }
}
```

Automatic VM Activation keys for VMs running on licensed Hyper-V hosts. Merged with built-in Microsoft AVMA keys (2012 R2-2025).

### Custom VM Templates

RackStack ships with three generic built-in templates: **DC** (Domain Controller), **FS** (File Server), and **WEB** (Web Server). Use `CustomVMTemplates` to override their specs or add new templates.

```json
"CustomVMTemplates": {
    "FS": {
        "_comment": "Override built-in File Server: bump RAM and data disk",
        "MemoryGB": 16,
        "Disks": [
            { "Name": "OS",   "SizeGB": 150,  "Type": "Fixed" },
            { "Name": "Data", "SizeGB": 500,  "Type": "Fixed" }
        ]
    },
    "SQL": {
        "FullName": "SQL Server", "Prefix": "SQL", "OSType": "Windows", "SortOrder": 10,
        "vCPU": 8, "MemoryGB": 32, "MemoryType": "Static",
        "Disks": [
            { "Name": "OS",   "SizeGB": 150,  "Type": "Fixed" },
            { "Name": "Data", "SizeGB": 500,  "Type": "Fixed" },
            { "Name": "Logs", "SizeGB": 200,  "Type": "Fixed" }
        ],
        "NICs": 1, "Notes": "SQL Server - D: data, E: logs"
    },
    "APP": {
        "FullName": "Application Server", "Prefix": "APP", "OSType": "Linux", "SortOrder": 11,
        "vCPU": 4, "MemoryGB": 8, "MemoryType": "Dynamic",
        "Disks": [{ "Name": "OS", "SizeGB": 100, "Type": "Fixed" }],
        "NICs": 1, "Notes": "Linux App Server (UEFI CA Secure Boot)"
    }
}
```

**Partial overrides** are supported -- specify only the fields you want to change, and all other fields keep their built-in values.

### Custom VM Defaults

```json
"CustomVMDefaults": {
    "vCPU": 4,
    "MemoryGB": 8,
    "MemoryType": "Dynamic",
    "DiskSizeGB": 100,
    "DiskType": "Fixed"
}
```

Default specs for non-template (custom) VMs created via the "Custom VM" option in the deployment menu.

### Defender Exclusion Paths

```json
"DefenderExclusionPaths": [
    "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V",
    "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V\\Snapshots",
    "C:\\Users\\Public\\Documents\\Hyper-V\\Virtual Hard Disks",
    "C:\\ClusterStorage"
],
"DefenderCommonVMPaths": [
    "D:\\Virtual Machines",
    "E:\\Virtual Machines"
]
```

Paths excluded from Windows Defender scanning on Hyper-V hosts to improve VM performance.

- `DefenderExclusionPaths` -- Static system-level paths that are always excluded.
- `DefenderCommonVMPaths` -- VM storage paths. If not set in `defaults.json`, these are **auto-generated dynamically** from the selected host storage drive (see [Dynamic Defender Paths](#dynamic-defender-paths)).

### Dynamic Defender Paths

When `DefenderCommonVMPaths` is **not** specified in `defaults.json`, RackStack auto-generates VM exclusion paths based on the selected host storage drive. For example, if drive D: is selected:

```
D:\Virtual Machines
D:\Hyper-V
D:\ISOs
D:\Virtual Machines\_BaseImages
```

If Cluster Shared Volumes exist, each CSV volume is also added. This ensures Defender exclusions always match the actual storage location without manual configuration.

If `DefenderCommonVMPaths` **is** specified in `defaults.json`, those paths are used as-is and dynamic generation is skipped.

### FileServer (File Server)

```json
"FileServer": {
    "StorageType": "nginx",
    "BaseURL": "https://files.yourdomain.com/server-tools",
    "ClientId": "your-cloudflare-access-client-id.access",
    "ClientSecret": "your-cloudflare-access-client-secret-hex-string",
    "ISOsFolder": "ISOs",
    "VHDsFolder": "VirtualHardDrives",
    "AgentFolder": "Agents"
}
```

File server configuration for downloading ISOs, VHDs, and agent installers. See the [File Server Setup](File-Server-Setup) guide for full setup instructions.

- `StorageType` -- `"nginx"` (default, any web server with JSON directory listing), `"azure"` (Azure Blob Storage), `"static"` (JSON index files, works with S3+CloudFront)
- `BaseURL` -- Full URL to the root directory (for nginx/static types). Empty = cloud features disabled.
- `ClientId` / `ClientSecret` -- Cloudflare Access service token credentials. Omit for LAN/VPN/Azure setups.
- For Azure Blob Storage, use these fields instead of BaseURL:
  - `AzureAccount` -- Storage account name
  - `AzureContainer` -- Container name
  - `AzureSasToken` -- SAS token with read/list permissions
- Folder names must match the actual directories on the file server.

### StorageBackendType (v1.3.0)

```json
"StorageBackendType": "iSCSI"
```

Controls which storage backend is active. This determines which management submenu appears under Storage & SAN and which backend is configured during batch mode.

| Value | Description |
|-------|-------------|
| `"iSCSI"` | iSCSI SAN with dual-path MPIO (default) |
| `"FC"` | Fibre Channel SAN with MPIO |
| `"S2D"` | Storage Spaces Direct (hyperconverged) |
| `"SMB3"` | SMB 3.0 file share (NAS / Scale-Out File Server) |
| `"NVMeoF"` | NVMe over Fabrics |
| `"Local"` | Local disks / Direct-Attached Storage only |

RackStack can also auto-detect the backend from system state. See [Storage Backends](Storage-Backends) for detection logic and backend-specific features.

### Custom Role Templates (v1.4.0)

```json
"CustomRoleTemplates": {
    "MYAPP": {
        "FullName": "Custom App Server",
        "Description": "Features for a custom application stack",
        "Features": ["Web-Server", "NET-Framework-45-Core", "MSMQ"],
        "PostInstall": null,
        "RequiresReboot": false,
        "ServerOnly": true
    }
}
```

Define custom server role templates that appear alongside the 10 built-in templates in the role template selector. Each template specifies a set of Windows features to install.

| Field | Type | Description |
|-------|------|-------------|
| `FullName` | string | Display name in the template selector |
| `Description` | string | Brief description of the template |
| `Features` | array | Windows feature names (as used by `Install-WindowsFeature`) |
| `PostInstall` | string/null | Function to call after install, or `null` |
| `RequiresReboot` | bool | Whether features require a reboot |
| `ServerOnly` | bool | Block installation on client OS if `true` |

See [Server Role Templates](Server-Role-Templates) for the full list of built-in templates and usage details.

---

## Virtual Switch Management (v1.5.0)

RackStack supports creating and managing all Hyper-V virtual switch types:

| Type | Description | Physical NIC? | Host Access? |
|------|-------------|---------------|-------------|
| **SET** | Switch Embedded Teaming -- bonds multiple NICs | Yes (2+) | Yes |
| **External** | Standard external switch -- single NIC | Yes (1) | Yes |
| **Internal** | Host-only networking -- no physical NIC | No | Yes |
| **Private** | Isolated -- VMs only | No | No |

In interactive mode: **Configure Server > Network > Host Network > Virtual Switch Management**.

In batch mode, use these fields:

```json
"CreateVirtualSwitch": true,
"VirtualSwitchType": "SET",
"VirtualSwitchName": "LAN-SET",
"VirtualSwitchAdapter": null
```

`CreateSETSwitch` is still supported as a backward-compatible alias for `CreateVirtualSwitch` + `VirtualSwitchType: "SET"`.

## Custom vNICs (v1.2.0+)

```json
"CustomVNICs": [
    { "Name": "Backup", "VLAN": null },
    { "Name": "Cluster", "VLAN": 100 },
    { "Name": "Live Migration", "VLAN": 200 },
    { "Name": "Storage", "VLAN": 300 }
]
```

Array of virtual NICs to create on the External or SET switch during batch mode (Step 19). Each entry needs:

- `Name` (required) -- Display name for the vNIC (e.g., "Cluster", "Live Migration")
- `VLAN` (optional) -- VLAN ID (1-4094), or `null` for no VLAN tagging

In interactive mode, use **Host Network > Add Virtual NIC to Switch** which offers preset names (Backup, Cluster, Live Migration, Storage) or custom names with optional VLAN and inline IP configuration.

> **Note:** Requires an External or SET switch. In batch mode, `CreateVirtualSwitch` must be `true` or an existing external switch must be present.

---

## Batch Mode HOST Keys

When using batch mode with `ConfigType: "HOST"`, additional keys control Hyper-V host infrastructure setup. These keys are ignored in VM mode.

| Key | Type | Description |
|-----|------|-------------|
| `CreateVirtualSwitch` | bool | Create a Hyper-V virtual switch (see [Virtual Switch Management](#virtual-switch-management-v150)) |
| `VirtualSwitchType` | string | `"SET"` (default), `"External"`, `"Internal"`, or `"Private"` |
| `VirtualSwitchName` | string | Name for the virtual switch (default: `"LAN-SET"`) |
| `VirtualSwitchAdapter` | string/null | Physical adapter name, or `null` for auto-detect |
| `SETManagementName` | string | Name for the management vNIC (default: `"Management"`) |
| `SETAdapterMode` | string | `"auto"` or `"manual"` adapter selection (SET only) |
| `CreateSETSwitch` | bool | Deprecated: alias for `CreateVirtualSwitch` + `VirtualSwitchType: "SET"` |
| `CustomVNICs` | array | Virtual NICs to create on External/SET switch (see [Custom vNICs](#custom-vnics-v120)) |
| `SANTargetPairings` | object/null | Custom SAN pair definitions (see [SANTargetPairings](#santargetpairings-v150)) |
| `ServerRoleTemplate` | string/null | Role template to install: DC, FS, WEB, DHCP, DNS, PRINT, WSUS, NPS, HV, RDS, or custom key |
| `PromoteToDC` | bool | Promote server to Domain Controller (see [AD DS Promotion](AD-DS-Promotion)) |
| `DCPromoType` | string | DC promotion type: `"NewForest"`, `"AdditionalDC"`, or `"RODC"` |
| `ForestName` | string/null | Domain FQDN for New Forest promotion |
| `ForestMode` / `DomainMode` | string | Functional level: `"Win2012R2"`, `"WinThreshold"` (default), `"Win2019"`, `"Win2022"`, `"Win2025"` |
| `StorageBackendType` | string | Storage backend: `"iSCSI"` (default), `"FC"`, `"S2D"`, `"SMB3"`, `"NVMeoF"`, `"Local"` |
| `ConfigureSharedStorage` | bool | Configure the shared storage backend based on `StorageBackendType` |
| `ConfigureiSCSI` | bool | Configure iSCSI NICs with auto-calculated IPs (deprecated -- use `ConfigureSharedStorage`) |
| `iSCSIHostNumber` | int/null | Host number (1-24) for IP calculation, or `null` for auto-detect |
| `ConfigureMPIO` | bool | Configure MPIO multipath for iSCSI or FC backends |
| `SMB3SharePath` | string/null | UNC path to SMB3 share (only when `StorageBackendType` is `"SMB3"`) |
| `InitializeHostStorage` | bool | Create VM storage directories and set Hyper-V paths |
| `HostStorageDrive` | string/null | Drive letter (e.g., `"D"`) or `null` for auto-select |
| `ConfigureDefenderExclusions` | bool | Add Defender exclusions for Hyper-V and VM paths |

For full details, default values, and examples, see the [Batch Mode Guide](Batch-Mode).
