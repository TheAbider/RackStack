# Batch Mode Guide

Batch mode automates server configuration by reading settings from a JSON file and applying them sequentially without user interaction. Instead of stepping through each menu option manually, you define the desired state in `batch_config.json` and RackStack executes every step in a single run.

---

## Table of Contents

- [When to Use Batch Mode](#when-to-use-batch-mode)
- [How It Works](#how-it-works)
- [Config File Detection](#config-file-detection)
- [Config Key Reference](#config-key-reference)
- [HOST vs VM Mode](#host-vs-vm-mode)
- [Step Execution Order](#step-execution-order)
- [Reboot Behavior](#reboot-behavior)
- [Generate from Current State](#generate-from-current-state)
- [Examples](#examples)

---

## When to Use Batch Mode

- **New server deployments** -- Configure a freshly installed Windows Server from scratch with a single script run.
- **Replicating configurations** -- Clone settings from one server to another by generating a config from a known-good host.
- **Scripted builds** -- Integrate RackStack into deployment pipelines or imaging workflows where interactive prompts are impractical.
- **Multi-site rollouts** -- Create a template config, change the hostname and IP per site, and deploy consistently across locations.

---

## How It Works

1. Place a `batch_config.json` file next to the RackStack script or executable.
2. Launch RackStack as Administrator.
3. RackStack detects the config file, displays a summary of what will be applied, and asks for confirmation.
4. Each step executes in order. Steps with `null` or `false` values are skipped.
5. After completion, RackStack shows a summary of changes applied and errors encountered.
6. If any step requires a reboot and `AutoReboot` is `true`, the server reboots automatically with a 10-second countdown.

---

## Config File Detection

RackStack looks for `batch_config.json` in the same directory as the running script or executable. No command-line flags or environment variables are needed.

```
C:\ServerTools\
    RackStack.exe
    batch_config.json    <-- auto-detected on launch
    defaults.json        <-- optional, loaded first for org settings
```

- If the file exists, RackStack enters batch mode automatically.
- If the file does not exist, RackStack starts in normal interactive mode.
- Delete or rename the file after use to return to interactive mode.

---

## Config Key Reference

### Standard Keys (VM and HOST)

These keys apply to both `VM` and `HOST` configurations.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ConfigType` | string | `"VM"` | `"VM"` for virtual machines, `"HOST"` for Hyper-V hosts. HOST mode adds steps 15-19. |
| `Hostname` | string | `null` | NetBIOS computer name, max 15 characters. Set to `null` to skip. |
| `AdapterName` | string | `"Ethernet"` | Network adapter to configure. VMs: usually `"Ethernet"`. Hosts: `"vEthernet (Management)"`. |
| `IPAddress` | string | `null` | Static IPv4 address for the management NIC. |
| `SubnetCIDR` | int (1-32) | `24` | Subnet prefix length in CIDR notation. 24 = 255.255.255.0. |
| `Gateway` | string | `null` | Default gateway IP address. |
| `DNS1` | string | `null` | Primary DNS server IP address. |
| `DNS2` | string | `null` | Secondary DNS server IP address. |
| `DomainName` | string | `null` | Active Directory domain to join. Set to `null` to skip. Prompts for credentials at runtime. |
| `Timezone` | string | `null` | Windows timezone ID (e.g., `"Pacific Standard Time"`, `"Eastern Standard Time"`). |
| `EnableRDP` | bool | `true` | Enable Remote Desktop and add the firewall rule. |
| `EnableWinRM` | bool | `true` | Enable PowerShell Remoting with Kerberos authentication. |
| `ConfigureFirewall` | bool | `true` | Set firewall profiles: Domain=Off, Private=Off, Public=On. |
| `SetPowerPlan` | string | `"High Performance"` | Power plan name: `"High Performance"`, `"Balanced"`, `"Power Saver"`, or `null` to skip. |
| `InstallHyperV` | bool | `false` | Install the Hyper-V role and management tools. Requires reboot. |
| `InstallMPIO` | bool | `false` | Install Multipath I/O for SAN connectivity. Requires reboot. |
| `InstallFailoverClustering` | bool | `false` | Install Failover Clustering role and tools. Requires reboot. |
| `CreateLocalAdmin` | bool | `false` | Create a local administrator account. Prompts for password at runtime. |
| `LocalAdminName` | string | from defaults.json | Username for the local admin account. Only used when `CreateLocalAdmin` is `true`. |
| `DisableBuiltInAdmin` | bool | `false` | Disable the built-in Administrator account. Only do this after confirming other admin access works. |
| `InstallUpdates` | bool | `false` | Install Windows Updates. Takes 10-60+ minutes. Runs last. |
| `AutoReboot` | bool | `true` | Automatically reboot after changes if needed. 10-second countdown before reboot. |

### HOST-Only Keys

These keys are only used when `ConfigType` is `"HOST"`. They are ignored in VM mode.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `CreateSETSwitch` | bool | `false` | Create a Switch Embedded Team (SET) virtual switch. Requires Hyper-V to be installed. |
| `SETSwitchName` | string | `"LAN-SET"` | Name for the SET virtual switch. |
| `SETManagementName` | string | `"Management"` | Name for the management virtual NIC on the SET switch. |
| `SETAdapterMode` | string | `"auto"` | `"auto"` detects internet-connected adapters for the SET team. `"manual"` prompts for adapter selection. |
| `ConfigureiSCSI` | bool | `false` | Configure iSCSI NICs with auto-calculated IPs based on host number. |
| `iSCSIHostNumber` | int (1-24) or null | `null` | Host number for iSCSI IP calculation. `null` auto-detects from hostname (e.g., `123456-HV2` = host 2). |
| `ConfigureMPIO` | bool | `false` | Connect to iSCSI targets and configure MPIO multipath. Requires iSCSI NICs to be configured first. |
| `InitializeHostStorage` | bool | `false` | Select a data drive, create the VM storage directory structure, and set Hyper-V default paths. |
| `HostStorageDrive` | string or null | `null` | Single drive letter for VM storage (e.g., `"D"`). `null` auto-selects the first available non-C fixed NTFS drive. |
| `ConfigureDefenderExclusions` | bool | `false` | Add Windows Defender exclusions for Hyper-V and VM storage paths. Paths are generated dynamically from the selected storage drive. |

### Help and Metadata Keys

Keys prefixed with `_` (e.g., `_ConfigType_Help`, `_README`, `_HOST_SECTION`) are informational and ignored by the script. They exist only to document the config file for human readers.

---

## HOST vs VM Mode

The `ConfigType` field controls which steps are executed.

### VM Mode (`"VM"`)

Runs steps 1-14. Designed for virtual machines where network configuration is straightforward (single adapter, static IP) and no host-level infrastructure is needed.

### HOST Mode (`"HOST"`)

Runs steps 1-19. Adds five host-specific steps after the standard configuration:

- **Step 15:** Initialize host storage (data drive selection, directory creation, Hyper-V default paths)
- **Step 16:** Create SET switch (Switch Embedded Teaming for NIC redundancy)
- **Step 17:** Configure iSCSI NICs (auto-calculate IPs from host number)
- **Step 18:** Configure MPIO (multipath I/O for SAN redundancy)
- **Step 19:** Configure Defender exclusions (auto-generated paths based on storage drive)

In HOST mode, network configuration (step 2) is skipped if no `AdapterName` is specified, since the SET switch is typically built first and then the management vNIC is configured afterward.

---

## Step Execution Order

| Step | Action | Applies To | Notes |
|------|--------|-----------|-------|
| 1 | Set hostname | VM, HOST | Requires reboot |
| 2 | Configure network (IP, subnet, gateway, DNS) | VM, HOST | Skipped in HOST mode if AdapterName is not set |
| 3 | Set timezone | VM, HOST | |
| 4 | Enable RDP | VM, HOST | |
| 5 | Enable WinRM | VM, HOST | |
| 6 | Configure firewall profiles | VM, HOST | |
| 7 | Set power plan | VM, HOST | |
| 8 | Install Hyper-V | VM, HOST | Requires reboot |
| 9 | Install MPIO | VM, HOST | Requires reboot |
| 10 | Install Failover Clustering | VM, HOST | Requires reboot |
| 11 | Create local admin account | VM, HOST | Prompts for password |
| 12 | Disable built-in Administrator | VM, HOST | |
| 13 | Join domain | VM, HOST | Prompts for credentials; requires reboot |
| 14 | Install Windows Updates | VM, HOST | Long-running; always last among standard steps |
| 15 | Initialize host storage | HOST only | Creates directory structure, sets Hyper-V paths |
| 16 | Create SET switch | HOST only | Requires Hyper-V installed |
| 17 | Configure iSCSI NICs | HOST only | Auto-calculates IPs from host number |
| 18 | Configure MPIO multipath | HOST only | Requires iSCSI NICs configured |
| 19 | Configure Defender exclusions | HOST only | Dynamic paths based on storage drive |

Each step checks its corresponding config key. If the key is `false`, `null`, or empty, the step is skipped and logged as "skipped."

---

## Reboot Behavior

Several steps can trigger a reboot requirement:

- Setting hostname (step 1)
- Installing Hyper-V (step 8)
- Installing MPIO (step 9)
- Installing Failover Clustering (step 10)
- Joining a domain (step 13)

When `AutoReboot` is `true` and any of these steps executed successfully, RackStack initiates a reboot with a 10-second countdown after all steps complete. When `AutoReboot` is `false`, RackStack displays a warning that a reboot is needed but does not reboot automatically.

Features that require a reboot (Hyper-V, MPIO, Failover Clustering) are not fully functional until after the reboot. If your batch config includes both feature installation and feature configuration (e.g., `InstallHyperV: true` and `CreateSETSwitch: true`), you may need to run the batch config twice: once to install features and reboot, and again to configure them.

---

## Generate from Current State

Instead of writing a config file from scratch, you can generate one pre-filled with the current server's live settings.

**Menu path:** Settings > Generate Batch Config > Generate from Current Server State

This detects:
- System info (hostname, timezone, domain membership)
- Network configuration (adapter, IP, subnet, gateway, DNS)
- Remote access state (RDP, WinRM)
- Installed features (Hyper-V, MPIO, Failover Clustering)
- Power plan
- HOST-specific state (SET switch, iSCSI sessions, storage drive)

The generated file includes all detected values. To use it on a different server:

1. Copy the file to the target server.
2. Edit `Hostname` and `IPAddress` (and `Gateway` if the subnet differs).
3. Set any unwanted options to `null` or `false`.
4. Save as `batch_config.json` next to the script.
5. Run RackStack.

---

## Examples

### Minimal VM Config

A basic VM configuration that sets the hostname, IP, DNS, timezone, enables remote access, and joins a domain.

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
    "CreateLocalAdmin": false,
    "LocalAdminName": null,
    "DisableBuiltInAdmin": false,
    "InstallUpdates": false,
    "AutoReboot": true
}
```

### Full Host Build Config

A complete Hyper-V host configuration that installs all features, sets up SET networking, iSCSI, MPIO, host storage, and Defender exclusions.

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
    "InstallUpdates": false,
    "AutoReboot": true,

    "CreateSETSwitch": true,
    "SETSwitchName": "LAN-SET",
    "SETManagementName": "Management",
    "SETAdapterMode": "auto",
    "ConfigureiSCSI": true,
    "iSCSIHostNumber": null,
    "ConfigureMPIO": true,
    "InitializeHostStorage": true,
    "HostStorageDrive": "D",
    "ConfigureDefenderExclusions": true
}
```

> **Note:** This config installs Hyper-V, MPIO, and Failover Clustering, all of which require a reboot. The SET switch and iSCSI configuration depend on Hyper-V being functional. You will likely need two runs: the first installs features and reboots, the second configures HOST-specific steps.
