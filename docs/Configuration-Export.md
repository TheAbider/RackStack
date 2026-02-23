# Configuration Export and Drift Detection Guide

RackStack provides tools to export server configurations, save reusable profiles, and detect configuration drift. These features help document infrastructure state, replicate configurations across servers, and audit servers against a known-good baseline.

---

## Table of Contents

- [Export-ServerConfiguration](#export-serverconfiguration)
- [Save-ConfigurationProfile](#save-configurationprofile)
- [Import-ConfigurationProfile](#import-configurationprofile)
- [Export-BatchConfigFromState](#export-batchconfigfromstate)
- [Configuration Drift Detection](#configuration-drift-detection)

---

## Export-ServerConfiguration

**Menu path:** Settings > Export Configuration

Generates a human-readable text report of the current server's complete configuration. This is a documentation tool -- the output is a text file, not an importable config.

### What It Captures

| Section | Details |
|---------|---------|
| System Information | Hostname, domain, OS, build, timezone, CPU, RAM |
| Licensing | Activation status, product name |
| Power Plan | Active power plan name |
| Network Configuration | All adapters with IP, DNS, gateway, VLAN, IPv6 state, MAC, link speed |
| Remote Access | RDP and WinRM status |
| Firewall | Domain, Private, and Public profile state |
| MPIO | Installation status, supported hardware |
| Failover Clustering | Installation status, cluster name, node list and state |
| Local Administrators | All members of the Administrators group, built-in admin state |
| Storage | Physical disks, volumes with free/total space and usage percentage |
| Hyper-V | Installation status, virtual switches (with SET team members), all VMs with state/CPU/RAM |
| Session Changes | All changes made during the current RackStack session |

### Output

The report is saved as a timestamped text file:

```
C:\Users\{user}\Desktop\{HOSTNAME}_Config_20260222_143000.txt
```

You can specify a custom path when prompted. The file is plain text with section headers, suitable for documentation, audits, or comparison with previous exports.

---

## Save-ConfigurationProfile

**Menu path:** Settings > Save Configuration Profile

Saves the current server's configuration as a structured JSON profile. Unlike the text export, this profile is designed to be loaded onto other servers to replicate settings.

### What It Captures

The profile includes:

- **Network:** Adapter name, subnet CIDR, DNS servers (IP and gateway are set to `null` -- you must fill these in for the target server)
- **Domain:** Whether the server is domain-joined, domain name
- **Timezone**
- **RDP and WinRM** state
- **Firewall** recommended configuration flag
- **Power plan** name
- **Feature installation** state: Hyper-V, MPIO, Failover Clustering
- **Local admin** account settings
- **Built-in Administrator** disable flag

### Intentionally Null Fields

The profile intentionally sets `Hostname`, `IPAddress`, and `Gateway` to `null`. These are server-specific values that must be set before applying the profile to a new server.

### Output

```
C:\Users\{user}\Desktop\{HOSTNAME}_Profile_20260222_143000.json
```

### Usage

1. Save a profile from a known-good server.
2. Copy the JSON file to the target server.
3. Edit the file: set `Hostname`, `Network.IPAddress`, and `Network.Gateway`.
4. Load it via **Import-ConfigurationProfile**.

---

## Import-ConfigurationProfile

**Menu path:** Settings > Load Configuration Profile

Reads a previously saved JSON profile and applies its settings to the current server. This is the counterpart to Save-ConfigurationProfile.

### How It Works

1. Enter the path to the profile JSON file.
2. RackStack displays a preview of the profile source, creation date, and all settings that will be applied.
3. Review the preview. Settings with `null` values are shown as "will skip."
4. Confirm to apply.

### Application Order

The profile is applied in 13 sequential steps:

| Step | Action | Notes |
|------|--------|-------|
| 1 | Set hostname | Requires reboot |
| 2 | Configure network | IP, subnet, gateway, DNS |
| 3 | Set timezone | |
| 4 | Enable RDP | |
| 5 | Enable WinRM | Kerberos authentication |
| 6 | Configure firewall | Domain:Off, Private:Off, Public:On |
| 7 | Set power plan | |
| 8 | Install Hyper-V | Requires reboot; skipped if already installed |
| 9 | Install MPIO | Requires reboot; skipped if already installed |
| 10 | Install Failover Clustering | Requires reboot; skipped if already installed |
| 11 | Create local admin | Prompts for password |
| 12 | Disable built-in Administrator | |
| 13 | Join domain | Prompts for credentials; requires reboot |

After all steps, a summary shows the count of successful changes and errors. If any step triggered a reboot requirement, a warning is displayed. Windows Updates, if enabled in the profile, are offered as an optional last step.

### Idempotency

Steps check current state before applying changes:

- Hostname is only changed if it differs from the current name.
- Features are only installed if not already present.
- Domain join is only attempted if the server is not already domain-joined.

---

## Export-BatchConfigFromState

**Menu path:** Settings > Generate Batch Config > Generate from Current Server State

Generates a `batch_config.json` pre-filled with the current server's live configuration. This is different from Save-ConfigurationProfile in that the output is a flat batch config (all keys at the top level) ready for batch mode execution.

### What It Detects

| Setting | Detection Method |
|---------|-----------------|
| ConfigType | `HOST` if Hyper-V is installed, otherwise `VM` |
| Hostname | `$env:COMPUTERNAME` |
| Adapter/IP/Subnet/Gateway/DNS | Primary UP adapter with IPv4 address |
| Domain | `Win32_ComputerSystem.Domain` if domain-joined |
| Timezone | `Get-TimeZone` |
| RDP/WinRM | Current enabled state |
| Power plan | Active power plan name |
| Hyper-V/MPIO/Clustering | Whether each feature is installed |
| SET switch | Detects existing SET switches by name and management NIC |
| iSCSI | Whether active iSCSI sessions exist |
| Storage drive | First non-C fixed NTFS drive |

### Output

The generated file includes all standard and HOST-specific keys with help text. A detected configuration summary is displayed before saving:

```
  DETECTED CONFIGURATION
  Config Type:  HOST
  Hostname:     123456-HV1
  Adapter:      vEthernet (Management)
  IP Address:   10.0.1.50/24
  Gateway:      10.0.1.1
  DNS:          10.0.1.10, 10.0.1.11
  ...
```

See the [Batch Mode Guide](Batch-Mode.md) for full details on batch config keys and execution.

---

## Configuration Drift Detection

**Menu path:** Settings > Configuration Drift Check

Drift detection compares the current server's live state against a saved configuration profile and highlights any settings that have changed from the expected values.

### How It Works

1. Enter the path to a previously saved configuration profile (JSON).
2. RackStack reads the profile and queries the current server state for each setting.
3. A drift report is displayed as a table.

### Drift Report

The report shows each setting with its expected value, current value, and match status:

```
  ╔════════════════════════════════════════════════════════════════════════╗
  ║                     CONFIGURATION DRIFT REPORT                       ║
  ╚════════════════════════════════════════════════════════════════════════╝

  ┌──────────────────────┬────────────────────────┬────────────────────────┬────────┐
  │ Setting              │ Expected               │ Current                │ Status │
  ├──────────────────────┼────────────────────────┼────────────────────────┼────────┤
  │ Hostname             │ 123456-FS1             │ 123456-FS1             │  OK    │
  │ IPAddress            │ 10.0.1.100             │ 10.0.1.100             │  OK    │
  │ Gateway              │ 10.0.1.1               │ 10.0.1.1               │  OK    │
  │ DNS                  │ 10.0.1.10, 10.0.1.11   │ 8.8.8.8, 8.8.4.4      │ DRIFT  │
  │ Timezone             │ Eastern Standard Time   │ Eastern Standard Time  │  OK    │
  │ RDP                  │ Enabled                │ Enabled                │  OK    │
  │ PowerPlan            │ High Performance        │ Balanced               │ DRIFT  │
  └──────────────────────┴────────────────────────┴────────────────────────┴────────┘

  Summary: 7 checked, 5 match, 2 drifted
```

### What Is Compared

| Setting | Expected Source | Current Source |
|---------|---------------|---------------|
| Hostname | Profile `Hostname` | `$env:COMPUTERNAME` |
| IP Address | Profile `Network.IPAddress` | Primary adapter IPv4 |
| Gateway | Profile `Network.Gateway` | Default route next hop |
| DNS | Profile `Network.DNS1/DNS2` | Adapter DNS servers |
| Domain | Profile `Domain.DomainName` | `Win32_ComputerSystem.Domain` |
| Timezone | Profile `Timezone` | `Get-TimeZone` |
| RDP | Profile `RDP.Enable` | Registry-based RDP state check |
| WinRM | Profile `WinRM.Enable` | WinRM service state check |
| Power Plan | Profile `PowerPlan` | Active power plan name |
| Hyper-V | Profile `InstallHyperV.Install` | Feature installation check |
| MPIO | Profile `InstallMPIO.Install` | Feature installation check |
| Failover Clustering | Profile `InstallFailoverClustering.Install` | Feature installation check |

### Fixing Drift

When drift is detected, the report lists the drifted settings. To correct them:

1. Note which settings have drifted.
2. Navigate to **Settings > Load Configuration Profile** and re-apply the profile.
3. Or fix individual settings manually through the interactive menus.

The drift check is read-only -- it does not make any changes to the server.

### Typical Use Cases

- **Post-deployment verification:** After applying a profile, run a drift check to confirm all settings took effect.
- **Periodic audits:** Schedule drift checks to catch unauthorized changes (DNS, power plan, firewall modifications).
- **Troubleshooting:** When a server behaves differently from its peers, compare against a known-good profile to identify what changed.
