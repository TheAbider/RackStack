# Batch Mode

Batch mode allows you to configure a server automatically from a JSON file, with no interactive prompts (except for passwords and domain credentials). Place a `batch_config.json` file next to the executable or script, and RackStack will detect and execute it on launch.

This is ideal for deploying multiple servers with identical or similar configurations, or for standardizing builds across sites.

---

## How It Works

1. Create a `batch_config.json` file (generate a template or export from a live server)
2. Edit the file with your target server's settings
3. Place it in the same folder as `RackStack.exe` or the `.ps1` script
4. Run RackStack as Administrator -- it auto-detects the file and runs in batch mode
5. After completion, delete or rename the file to return to interactive mode

RackStack validates the config before executing. If there are errors (invalid IPs, out-of-range values, missing required fields), batch mode aborts with a clear error list. Warnings (e.g., missing hostname) are displayed but don't block execution.

---

## Generating a Batch Config

From the main menu, navigate to **Settings > Batch Config Generator**. You have two options:

| Option | Description |
|--------|-------------|
| **Generate Blank Template** | Creates a template with example values and help text for every field |
| **Generate from Current Server State** | Scans the running server and pre-fills all values from its live configuration |

The "Generate from Current State" option is particularly useful for cloning -- configure one server interactively, export its state, then edit only the hostname and IP for each additional server.

Both options save to `%USERPROFILE%\Desktop\batch_config.json` by default, with an option to specify a custom path.

---

## ConfigType: HOST vs VM

The `ConfigType` field controls which steps are executed:

| ConfigType | Use Case | Network Behavior | Extra Steps |
|------------|----------|-------------------|-------------|
| `VM` | Virtual machines | Configures IP/DNS/gateway on the specified adapter | Steps 1-16 only |
| `HOST` | Hyper-V hosts | Skips network config unless `AdapterName` is specified (build SET via GUI first) | Steps 1-22, including role templates, DC promotion, SET, storage, MPIO, Defender |

Set `ConfigType` to `HOST` when configuring a bare-metal Hyper-V server. The host-specific steps (17-22) are only executed in HOST mode.

---

## All 22 Batch Steps

Batch mode processes steps sequentially. Set a value to `null` or `false` to skip that step.

| Step | Field | Description |
|------|-------|-------------|
| 1 | `Hostname` | Rename the computer (requires reboot) |
| 2 | `IPAddress`, `Gateway`, `SubnetCIDR`, `DNS1`, `DNS2` | Configure static IP, gateway, and DNS on the adapter |
| 3 | `Timezone` | Set the system timezone |
| 4 | `EnableRDP` | Enable Remote Desktop and firewall rule |
| 5 | `EnableWinRM` | Enable PowerShell Remoting with Kerberos auth |
| 6 | `ConfigureFirewall` | Set firewall profiles (Domain=Off, Private=Off, Public=On) |
| 7 | `SetPowerPlan` | Set the active power plan |
| 8 | `InstallHyperV` | Install Hyper-V role and management tools |
| 9 | `InstallMPIO` | Install Multipath I/O feature |
| 10 | `InstallFailoverClustering` | Install Failover Clustering role and tools |
| 11 | `CreateLocalAdmin` | Create a local admin account (prompts for password) |
| 12 | `DisableBuiltInAdmin` | Disable the built-in Administrator account |
| 13 | `DomainName` | Join an Active Directory domain (prompts for credentials) |
| 14 | `ServerRoleTemplate` | Install a server role template (see [Server Role Templates](Server-Role-Templates)) |
| 15 | `PromoteToDC` | Promote to Domain Controller (see [AD DS Promotion](AD-DS-Promotion)) |
| 16 | `InstallUpdates` | Install Windows Updates (can take 10-60+ minutes) |
| 17 | `InitializeHostStorage` | Create VM storage directories and set Hyper-V default paths (HOST only) |
| 18 | `CreateVirtualSwitch` | Create a virtual switch: SET, External, Internal, or Private (HOST only) |
| 19 | `CustomVNICs` | Create custom virtual NICs on the External/SET switch (HOST only) |
| 20 | `ConfigureSharedStorage` | Configure the storage backend: iSCSI NICs, FC scan, S2D, SMB3, or NVMe (HOST only) |
| 21 | `ConfigureMPIO` | Configure MPIO multipath for iSCSI or FC backends (HOST only) |
| 22 | `ConfigureDefenderExclusions` | Add Defender exclusions for Hyper-V paths (HOST only) |

---

## JSON Template Structure

Every field has a corresponding `_Help` field that explains its purpose. Help fields (any key starting with `_`) are ignored by the script.

```json
{
    "_README": "RackStack - Batch Config Template v1.1.0",
    "_INSTRUCTIONS": ["..."],

    "ConfigType": "VM",
    "_ConfigType_Help": "'VM' for virtual machines, 'HOST' for Hyper-V hosts.",

    "Hostname": "123456-FS1",
    "AdapterName": "Ethernet",
    "IPAddress": "10.0.1.100",
    "SubnetCIDR": 24,
    "Gateway": "10.0.1.1",
    "DNS1": "8.8.8.8",
    "DNS2": "8.8.4.4",
    "DomainName": "corp.acme.com",
    "Timezone": "Pacific Standard Time",
    "EnableRDP": true,
    "EnableWinRM": true,
    "ConfigureFirewall": true,
    "SetPowerPlan": "High Performance",
    "InstallHyperV": false,
    "InstallMPIO": false,
    "InstallFailoverClustering": false,
    "CreateLocalAdmin": false,
    "LocalAdminName": "localadmin",
    "DisableBuiltInAdmin": false,
    "ServerRoleTemplate": null,
    "PromoteToDC": false,
    "DCPromoType": "NewForest",
    "ForestName": null,
    "ForestMode": "WinThreshold",
    "DomainMode": "WinThreshold",
    "InstallUpdates": false,
    "AutoReboot": true
}
```

### HOST-Specific Fields

These fields are only processed when `ConfigType` is `HOST`:

```json
{
    "InitializeHostStorage": false,
    "HostStorageDrive": null,
    "CreateSETSwitch": false,
    "SETSwitchName": "LAN-SET",
    "SETManagementName": "Management",
    "SETAdapterMode": "auto",
    "CustomVNICs": [
        {"Name": "Backup"},
        {"Name": "Cluster", "VLAN": 100},
        {"Name": "Live Migration", "VLAN": 200}
    ],
    "StorageBackendType": "iSCSI",
    "ConfigureSharedStorage": false,
    "ConfigureiSCSI": false,
    "iSCSIHostNumber": null,
    "SMB3SharePath": null,
    "ConfigureMPIO": false,
    "ConfigureDefenderExclusions": false
}
```

---

## Field Reference

### Common Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `ConfigType` | string | `"VM"` | `"VM"` or `"HOST"` |
| `Hostname` | string | null | NetBIOS name, max 15 characters |
| `AdapterName` | string | `"Ethernet"` | Network adapter name. VMs: `"Ethernet"`. Hosts: `"vEthernet (Management)"` |
| `IPAddress` | string | null | Static IPv4 address. Both `IPAddress` and `Gateway` are required together |
| `SubnetCIDR` | int | `24` | Subnet prefix length (1-32) |
| `Gateway` | string | null | Default gateway IPv4 address |
| `DNS1` / `DNS2` | string | null | Primary and secondary DNS servers |
| `DomainName` | string | null | AD domain to join. Will prompt for credentials at runtime |
| `Timezone` | string | null | Timezone ID (e.g., `"Pacific Standard Time"`, `"Eastern Standard Time"`) |
| `EnableRDP` | bool | false | Enable Remote Desktop |
| `EnableWinRM` | bool | false | Enable PowerShell Remoting |
| `ConfigureFirewall` | bool | false | Set recommended firewall profiles |
| `SetPowerPlan` | string | null | `"High Performance"`, `"Balanced"`, or `"Power Saver"` |
| `InstallHyperV` | bool | false | Install Hyper-V role (requires reboot) |
| `InstallMPIO` | bool | false | Install Multipath I/O (requires reboot) |
| `InstallFailoverClustering` | bool | false | Install Failover Clustering (requires reboot) |
| `CreateLocalAdmin` | bool | false | Create a local admin account (prompts for password) |
| `LocalAdminName` | string | from defaults | Username for the local admin account |
| `DisableBuiltInAdmin` | bool | false | Disable the built-in Administrator account |
| `ServerRoleTemplate` | string/null | null | Role template key: `DC`, `FS`, `WEB`, `DHCP`, `DNS`, `PRINT`, `WSUS`, `NPS`, `HV`, `RDS`, or custom. `null` to skip |
| `PromoteToDC` | bool | false | Promote to Domain Controller after domain join |
| `DCPromoType` | string | `"NewForest"` | `"NewForest"`, `"AdditionalDC"`, or `"RODC"` |
| `ForestName` | string/null | null | Domain FQDN for New Forest (e.g., `"corp.contoso.com"`) |
| `ForestMode` | string | `"WinThreshold"` | Forest functional level (New Forest only). See [AD DS Promotion](AD-DS-Promotion) |
| `DomainMode` | string | `"WinThreshold"` | Domain functional level (New Forest only) |
| `InstallUpdates` | bool | false | Install Windows Updates (10-60+ minutes) |
| `AutoReboot` | bool | true | Auto-reboot after changes (10-second countdown) |

### HOST-Only Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `InitializeHostStorage` | bool | false | Create VM directories and set Hyper-V default paths |
| `HostStorageDrive` | string/null | null | Drive letter (e.g., `"D"`). `null` = auto-select first non-C fixed NTFS drive |
| `CreateVirtualSwitch` | bool | false | Create a virtual switch (replaces `CreateSETSwitch`) |
| `VirtualSwitchType` | string | `"SET"` | `"SET"`, `"External"`, `"Internal"`, or `"Private"` |
| `VirtualSwitchName` | string | `"LAN-SET"` | Name for the virtual switch |
| `VirtualSwitchAdapter` | string/null | null | Physical adapter name. `null` = auto-detect |
| `SETManagementName` | string | `"Management"` | Name for the management vNIC (SET/External) |
| `SETAdapterMode` | string | `"auto"` | `"auto"` detects internet adapters, `"manual"` prompts (SET only) |
| `CreateSETSwitch` | bool | false | Deprecated: alias for `CreateVirtualSwitch` + `VirtualSwitchType: "SET"` |
| `CustomVNICs` | array | `[]` | Virtual NICs to create on External/SET. Each needs `Name` (required) and optional `VLAN` (1-4094) |
| `StorageBackendType` | string | `"iSCSI"` | Storage backend: `"iSCSI"`, `"FC"`, `"S2D"`, `"SMB3"`, `"NVMeoF"`, or `"Local"` |
| `ConfigureSharedStorage` | bool | false | Configure the storage backend (iSCSI NICs, FC scan, S2D enable, SMB test, NVMe scan) |
| `ConfigureiSCSI` | bool | false | Configure iSCSI NICs (deprecated -- use `ConfigureSharedStorage` with `StorageBackendType: "iSCSI"`) |
| `iSCSIHostNumber` | int/null | null | Host number (1-24) for IP calculation. `null` = auto-detect from hostname |
| `SMB3SharePath` | string/null | null | UNC path to SMB3 share (e.g., `"\\\\server\\share"`). Only used with `StorageBackendType: "SMB3"` |
| `ConfigureMPIO` | bool | false | Configure MPIO multipath for iSCSI or FC backends |
| `ConfigureDefenderExclusions` | bool | false | Add Defender exclusions for Hyper-V and VM storage paths |

---

## Validation and Error Handling

Before executing any steps, batch mode runs a full validation pass:

**Errors (block execution):**
- Invalid `ConfigType` (must be `VM` or `HOST`)
- Invalid hostname format (must be 1-15 alphanumeric characters, hyphens allowed)
- Invalid IPv4 addresses in `IPAddress`, `Gateway`, `DNS1`, `DNS2`
- `SubnetCIDR` out of range (must be 1-32)
- `IPAddress` set without `Gateway` (or vice versa)
- Boolean fields with non-boolean values
- Invalid `SetPowerPlan` value
- Invalid `SETAdapterMode` (must be `auto` or `manual`)
- `iSCSIHostNumber` out of range (must be 1-24 or null)
- `HostStorageDrive` is `C` or not a single letter
- Invalid `StorageBackendType` (must be one of: iSCSI, FC, S2D, SMB3, NVMeoF, Local)
- Invalid `DCPromoType` (must be NewForest, AdditionalDC, or RODC)
- `ForestName` missing when `PromoteToDC` is `true` and `DCPromoType` is `NewForest`

**Warnings (display but continue):**
- Hostname not set (server keeps its current name)
- HOST mode without `InstallHyperV`
- `DisableBuiltInAdmin` without `CreateLocalAdmin`
- HOST mode with IP config but no `AdapterName`
- `CreateSETSwitch` without `InstallHyperV`
- Invalid `ServerRoleTemplate` key (template not found in built-in or custom)
- `PromoteToDC` without `ServerRoleTemplate: "DC"` (AD DS features may not be installed)

---

## Example: Full VM Config

```json
{
    "ConfigType": "VM",
    "Hostname": "123456-FS1",
    "AdapterName": "Ethernet",
    "IPAddress": "10.0.1.100",
    "SubnetCIDR": 24,
    "Gateway": "10.0.1.1",
    "DNS1": "10.0.1.10",
    "DNS2": "10.0.1.11",
    "DomainName": "corp.acme.com",
    "Timezone": "Eastern Standard Time",
    "EnableRDP": true,
    "EnableWinRM": true,
    "ConfigureFirewall": true,
    "SetPowerPlan": "High Performance",
    "InstallHyperV": false,
    "InstallMPIO": false,
    "InstallFailoverClustering": false,
    "CreateLocalAdmin": true,
    "LocalAdminName": "localadmin",
    "DisableBuiltInAdmin": false,
    "InstallUpdates": true,
    "AutoReboot": true
}
```

## Example: Full HOST Config

```json
{
    "ConfigType": "HOST",
    "Hostname": "123456-HV1",
    "AdapterName": "vEthernet (Management)",
    "IPAddress": "10.0.1.50",
    "SubnetCIDR": 24,
    "Gateway": "10.0.1.1",
    "DNS1": "10.0.1.10",
    "DNS2": "10.0.1.11",
    "DomainName": "corp.acme.com",
    "Timezone": "Eastern Standard Time",
    "EnableRDP": true,
    "EnableWinRM": true,
    "ConfigureFirewall": true,
    "SetPowerPlan": "High Performance",
    "InstallHyperV": true,
    "InstallMPIO": true,
    "InstallFailoverClustering": true,
    "CreateLocalAdmin": true,
    "LocalAdminName": "localadmin",
    "DisableBuiltInAdmin": false,
    "ServerRoleTemplate": "HV",
    "PromoteToDC": false,
    "InstallUpdates": false,
    "AutoReboot": true,
    "InitializeHostStorage": true,
    "HostStorageDrive": "D",
    "CreateSETSwitch": true,
    "SETSwitchName": "LAN-SET",
    "SETManagementName": "Management",
    "SETAdapterMode": "auto",
    "CustomVNICs": [
        {"Name": "Cluster", "VLAN": 100},
        {"Name": "Live Migration", "VLAN": 200}
    ],
    "StorageBackendType": "iSCSI",
    "ConfigureSharedStorage": true,
    "iSCSIHostNumber": null,
    "ConfigureMPIO": true,
    "ConfigureDefenderExclusions": true
}
```

---

## Tips

- **Clone servers fast:** Configure one server interactively, use "Generate from Current State" to export, then change only `Hostname` and `IPAddress` for each clone.
- **Skip with null:** Set any value to `null` to skip that step entirely.
- **Order matters:** Steps run in order 1-22. Domain join (step 13) runs before role templates and DC promotion (steps 14-15) so the server is domain-joined first. Updates (step 16) run after role installation.
- **Credentials:** `CreateLocalAdmin`, `DomainName`, and `PromoteToDC` will pause for interactive password/credential entry even in batch mode. All other steps are fully automated.
- **Auto-reboot:** When `AutoReboot` is `true` and changes require a reboot, there is a 10-second countdown. Press Ctrl+C to cancel.
- **Transcript logging:** Batch mode creates a transcript log in the configured temp directory for audit purposes.

---

See also: [Configuration Guide](Configuration) | [Storage Manager](Storage-Manager) | [Storage Backends](Storage-Backends) | [Server Role Templates](Server-Role-Templates) | [AD DS Promotion](AD-DS-Promotion)
