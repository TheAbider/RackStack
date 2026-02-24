# Configuration Export

RackStack provides three complementary features for managing server configurations: exporting detailed reports, saving/loading reusable profiles, and detecting configuration drift.

---

## Export Server Configuration

Generates a comprehensive text report of the current server's configuration. This is useful for documentation, auditing, or troubleshooting.

### What's Included

The export captures the following sections:

| Section | Details |
|---------|---------|
| **System Information** | Hostname, domain membership, OS version/build, timezone, CPU model/cores, total RAM |
| **Licensing** | Windows activation status, product name, license description |
| **Power Plan** | Active power plan name |
| **Network Configuration** | All adapters with status, link speed, MAC, IPv4 address/CIDR, DNS servers, gateway, VLAN ID, IPv6 status |
| **Remote Access** | RDP and WinRM enabled/disabled status |
| **Firewall Status** | Domain, Private, and Public profile states |
| **MPIO** | Installation status and supported hardware list |
| **Failover Clustering** | Installation status, cluster name, node names and states |
| **Local Administrators** | All members of the Administrators group, built-in admin enabled/disabled status |
| **Storage** | All disks (model, size, partition style, status) and volumes (drive letter, label, file system, free/total space, usage percent) |
| **Hyper-V** | Installation status, virtual switches (name, type, SET team members), all VMs (name, state, CPU count, assigned RAM) |
| **Session Changes** | All changes made during the current RackStack session with timestamps |

### Output

- **Format:** Plain text file (UTF-8)
- **Default path:** `%USERPROFILE%\Desktop\{HOSTNAME}_Config_{timestamp}.txt`
- **Custom path:** Enter any path when prompted

---

## Configuration Profiles

Profiles are JSON files that capture a server's configuration in a format that can be applied to other servers. Unlike the text export (read-only report), profiles are actionable -- they can be loaded to configure a new server.

### Save Configuration Profile

Captures the current server's live settings into a JSON profile:

```json
{
    "_ProfileInfo": {
        "CreatedFrom": "123456-HV1",
        "CreatedAt": "2026-02-23 14:30:00",
        "ScriptVersion": "1.1.0",
        "Description": "Configuration profile - edit Hostname, IPAddress, and Gateway before applying"
    },
    "Hostname": null,
    "Network": {
        "AdapterName": "vEthernet (Management)",
        "IPAddress": null,
        "SubnetCIDR": 24,
        "Gateway": null,
        "DNS1": "10.0.1.10",
        "DNS2": "10.0.1.11"
    },
    "Domain": {
        "JoinDomain": true,
        "DomainName": "corp.acme.com"
    },
    "Timezone": "Eastern Standard Time",
    "RDP": { "Enable": true },
    "WinRM": { "Enable": true },
    "Firewall": { "ConfigureRecommended": true },
    "PowerPlan": "High Performance",
    "InstallHyperV": { "Install": true },
    "InstallMPIO": { "Install": true },
    "InstallFailoverClustering": { "Install": true },
    "LocalAdmin": {
        "CreateAccount": false,
        "AccountName": "localadmin"
    },
    "BuiltInAdmin": { "Disable": false },
    "InstallUpdates": { "Install": false }
}
```

**Key design decisions:**
- `Hostname`, `IPAddress`, and `Gateway` are intentionally set to `null` -- you must edit these for each target server
- DNS servers, timezone, domain, and feature selections are captured from the live state
- Role installations (Hyper-V, MPIO, Clustering) reflect what is currently installed
- The `_ProfileInfo` section records where and when the profile was created

**Default path:** `%USERPROFILE%\Desktop\{HOSTNAME}_Profile_{timestamp}.json`

### Load Configuration Profile

Loads a saved profile and applies its settings to the current server. The process:

1. Enter the path to a profile JSON file
2. RackStack displays profile metadata (source server, creation date, version)
3. A preview shows every setting that will be applied, with color coding for items requiring reboot
4. Confirm to proceed
5. Settings are applied in 13 sequential steps:

| Step | Setting |
|------|---------|
| 1 | Hostname |
| 2 | Network (IP, subnet, gateway, DNS) |
| 3 | Timezone |
| 4 | RDP |
| 5 | WinRM |
| 6 | Firewall profiles |
| 7 | Power plan |
| 8 | Hyper-V installation |
| 9 | MPIO installation |
| 10 | Failover Clustering installation |
| 11 | Local admin account creation (prompts for password) |
| 12 | Disable built-in Administrator |
| 13 | Domain join (prompts for credentials) |

After all steps, a summary shows how many succeeded and failed. If Windows Updates are enabled in the profile, you are prompted separately (since updates can take 10-60+ minutes).

**Skipped settings:** Any null, empty, or false value in the profile causes that step to be skipped. Already-installed features are also skipped.

---

## Configuration Drift Detection

Drift detection compares the current server's live state against a saved configuration profile and highlights any settings that have changed since the profile was created.

### What's Checked

| Setting | Comparison |
|---------|------------|
| **Hostname** | `$env:COMPUTERNAME` vs saved hostname |
| **IP Address** | Primary adapter IPv4 vs saved IP |
| **Gateway** | Default route next-hop vs saved gateway |
| **DNS** | DNS server addresses vs saved DNS1/DNS2 |
| **Domain** | Current domain membership and name vs saved domain |
| **Timezone** | Current timezone ID vs saved timezone |
| **RDP** | Current RDP state (Enabled/Disabled) vs saved value |
| **WinRM** | Current WinRM state (Enabled/Disabled) vs saved value |
| **Power Plan** | Active power plan name vs saved plan |
| **Hyper-V** | Installation status vs saved value |
| **MPIO** | Installation status vs saved value |
| **Failover Clustering** | Installation status vs saved value |

### Drift Report

The drift report is displayed as a formatted table:

```
 ┌──────────────────────┬────────────────────────┬────────────────────────┬────────┐
 │ Setting              │ Expected               │ Current                │ Status │
 ├──────────────────────┼────────────────────────┼────────────────────────┼────────┤
 │ Hostname             │ 123456-FS1             │ 123456-FS1             │  OK    │
 │ IPAddress            │ 10.0.1.100             │ 10.0.1.100             │  OK    │
 │ Timezone             │ Eastern Standard Time  │ Pacific Standard Time  │ DRIFT  │
 │ RDP                  │ Enabled                │ Disabled               │ DRIFT  │
 │ PowerPlan            │ High Performance       │ Balanced               │ DRIFT  │
 └──────────────────────┴────────────────────────┴────────────────────────┴────────┘

 Summary: 12 checked, 9 match, 3 drifted
```

- **OK** (green): Setting matches the expected value
- **DRIFT** (red): Setting has changed from the expected value

### Using Drift Detection

1. Navigate to **Settings > Configuration Drift Check**
2. Enter the path to a previously saved profile JSON file
3. RackStack gathers the current live state and compares each setting
4. The drift report shows which settings match and which have drifted
5. If drift is detected, you can fix it by re-applying the profile using **Load Configuration Profile**

### When to Use Drift Detection

- **Post-maintenance check:** Verify a server is still configured correctly after patching or changes
- **Compliance auditing:** Confirm servers match your standard configuration
- **Troubleshooting:** Quickly identify what changed on a server that is misbehaving
- **Multi-server consistency:** Compare each server against the same baseline profile

---

## Profiles vs Batch Config

Both profiles and batch configs are JSON files that configure servers, but they serve different purposes:

| Feature | Configuration Profile | Batch Config |
|---------|----------------------|--------------|
| **Format** | Nested JSON with sections | Flat JSON with help text |
| **Generation** | From live server state | Template or live state |
| **Execution** | Manual (load from menu) | Automatic (auto-detected on launch) |
| **HOST features** | No (common settings only) | Yes (SET, iSCSI, MPIO, storage, Defender) |
| **Drift detection** | Yes | No |
| **Use case** | Cloning common settings, compliance checking | Full unattended server builds |

For full HOST automation including SET switches, iSCSI, and storage setup, use [Batch Mode](Batch-Mode). For day-to-day profile management and drift checks, use Configuration Profiles.

---

See also: [Configuration Guide](Configuration) | [Batch Mode](Batch-Mode) | [Cluster Management](Cluster-Management)
