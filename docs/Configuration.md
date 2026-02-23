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
| `DefenderExclusionPaths` | Windows Defender exclusion paths for Hyper-V hosts |
| `DefenderCommonVMPaths` | Common VM storage paths added to Defender exclusions (auto-generated if not set) |
| `StoragePaths` | Default Hyper-V storage paths (VM storage, ISOs, VHD cache, cluster paths) |
| `AgentInstaller` | MSP agent installer config: tool name, service name, file pattern, install args, paths, exit codes |
| `CustomKMSKeys` / `CustomAVMAKeys` | Org-specific license keys, merged with built-in Microsoft GVLK/AVMA tables |
| `VMNaming` | VM naming pattern, site ID source, and detection regex |
| `CustomVMTemplates` | Override built-in VM template specs or add new templates (partial overrides supported) |
| `CustomVMDefaults` | Default vCPU, RAM, disk size/type for non-template (custom) VMs |
| `FileServer` | File server credentials for ISO/VHD downloads (see [File Server Setup](FileServer-Setup.md)) |

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
    "FolderName": "KaseyaAgents",
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

| Field | Type | Description |
|-------|------|-------------|
| `SiteId` | string | Static site identifier override. If set (non-empty) with `SiteIdSource: "static"`, skips auto-detection. |
| `Pattern` | string | Token-based naming pattern. Available tokens: `{Site}`, `{Prefix}`, `{Seq}`. Use `{Seq:00}` for zero-padded sequence numbers. |
| `SiteIdSource` | string | How to get the site ID: `"hostname"` (extract from `$env:COMPUTERNAME` using regex) or `"static"` (always use `SiteId` value). |
| `SiteIdRegex` | string | Regex with capture group to extract site ID from hostname. |

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

See the [Storage Manager Guide](Storage-Manager.md) for full details.

### FileServer (File Server)

```json
"FileServer": {
    "BaseURL": "https://files.yourdomain.com/server-tools",
    "ClientId": "your-cloudflare-access-client-id.access",
    "ClientSecret": "your-cloudflare-access-client-secret-hex-string",
    "ISOsFolder": "ISOs",
    "VHDsFolder": "VirtualHardDrives",
    "KaseyaFolder": "KaseyaAgents"
}
```

File server configuration for downloading ISOs, VHDs, and agent installers. See the [File Server Setup](FileServer-Setup.md) guide for full setup instructions.

- `BaseURL` -- Full URL to the root directory. Empty = cloud features disabled.
- `ClientId` / `ClientSecret` -- Cloudflare Access service token credentials. Omit for LAN/VPN setups.
- Folder names must match the actual directories on the file server.

---

## Batch Mode HOST Keys

When using batch mode with `ConfigType: "HOST"`, additional keys control Hyper-V host infrastructure setup. These keys are ignored in VM mode.

| Key | Type | Description |
|-----|------|-------------|
| `CreateSETSwitch` | bool | Create a Switch Embedded Team virtual switch |
| `SETSwitchName` | string | Name for the SET switch (default: `"LAN-SET"`) |
| `SETManagementName` | string | Name for the management vNIC (default: `"Management"`) |
| `SETAdapterMode` | string | `"auto"` or `"manual"` adapter selection |
| `ConfigureiSCSI` | bool | Configure iSCSI NICs with auto-calculated IPs |
| `iSCSIHostNumber` | int/null | Host number (1-24) for IP calculation, or `null` for auto-detect |
| `ConfigureMPIO` | bool | Connect to iSCSI targets and configure MPIO |
| `InitializeHostStorage` | bool | Create VM storage directories and set Hyper-V paths |
| `HostStorageDrive` | string/null | Drive letter (e.g., `"D"`) or `null` for auto-select |
| `ConfigureDefenderExclusions` | bool | Add Defender exclusions for Hyper-V and VM paths |

For full details, default values, and examples, see the [Batch Mode Guide](Batch-Mode.md).
