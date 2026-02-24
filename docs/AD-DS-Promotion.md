# AD DS Promotion

RackStack includes an interactive wizard for promoting a Windows Server to a Domain Controller. Three promotion types are supported: creating a new forest, joining an existing domain as an additional DC, or deploying a Read-Only Domain Controller (RODC).

> **New in v1.4.0:** AD DS promotion wizards with prerequisite validation, functional level selection, and batch mode support.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Promotion Menu](#promotion-menu)
- [New Forest](#new-forest)
- [Additional Domain Controller](#additional-domain-controller)
- [Read-Only Domain Controller (RODC)](#read-only-domain-controller-rodc)
- [Functional Levels](#functional-levels)
- [AD DS Status Dashboard](#ad-ds-status-dashboard)
- [Batch Mode](#batch-mode)

---

## Prerequisites

Before any promotion type, RackStack validates four prerequisites:

| Check | Requirement | Details |
|-------|-------------|---------|
| **Windows Server OS** | Must be running Windows Server | Client OS (Windows 10/11) cannot be a DC |
| **Static IP Address** | IP must be manually configured | DHCP-assigned addresses are not suitable for DCs |
| **DNS Configuration** | DNS servers must be configured | Required for AD DS name resolution |
| **Not Already a DC** | Server must not already be a Domain Controller | Promotion cannot run on an existing DC |

Each check displays a pass/fail indicator:

```
  AD DS PREREQUISITES
  ──────────────────────────────────────────
  [PASS]  Windows Server OS detected
  [PASS]  Static IP address configured
  [PASS]  DNS servers configured
  [PASS]  Not already a Domain Controller

  All prerequisites met. Ready for promotion.
```

If any prerequisite fails, the wizard explains the issue and blocks promotion until it is resolved.

---

## Promotion Menu

**Menu path:** System Configuration > `[3]` Promote to Domain Controller

```
  AD DS PROMOTION
  ──────────────────────────────────────────
  [1]  New Forest
  [2]  Additional Domain Controller
  [3]  Read-Only Domain Controller (RODC)
  [4]  Check AD DS Status
  [B]  Back
```

> **Tip:** Install AD DS features first using the DC role template (Tools & Utilities > `[8]` Server Role Templates > `DC`) before running the promotion wizard. The features include AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server, and GPMC.

---

## New Forest

Creates the first domain controller in a brand new Active Directory forest. Use this when setting up AD from scratch.

### Wizard Walkthrough

1. **Domain Name**
   - Enter the fully qualified domain name (e.g., `corp.contoso.com`)
   - Validation rules: must contain at least one dot, each label must start and end with an alphanumeric character, hyphens allowed in the middle
   - Example valid names: `corp.contoso.com`, `ad.example.local`, `mycompany.net`

2. **NetBIOS Name**
   - Auto-extracted from the first label of the FQDN (e.g., `corp.contoso.com` → `CORP`)
   - Converted to uppercase automatically
   - Can be accepted or overridden

3. **Forest Functional Level**
   - Select from available levels (see [Functional Levels](#functional-levels))
   - Default: WinThreshold (Server 2016)

4. **Domain Functional Level**
   - Must be equal to or lower than the forest functional level
   - Default: matches forest level

5. **DSRM Password**
   - Directory Services Restore Mode password (required for recovery scenarios)
   - Entered as a secure/masked input, must be entered twice to confirm
   - Minimum 8 characters
   - **Never stored** in configuration files

6. **Summary**
   - Review all settings before proceeding
   - Domain name, NetBIOS name, forest/domain levels displayed

7. **Execute**
   - Runs `Install-ADDSForest` with DNS installation
   - Reboot is required after successful promotion
   - Server becomes the first DC and all FSMO roles are assigned to it

---

## Additional Domain Controller

Adds this server as a domain controller to an existing Active Directory domain. Use this for redundancy, load distribution, or site-level DC placement.

### Wizard Walkthrough

1. **Domain Name**
   - Enter the FQDN of the existing domain to join (e.g., `corp.contoso.com`)
   - Same validation rules as New Forest

2. **Domain Credentials**
   - Prompted for domain administrator credentials
   - Requires Domain Admin or equivalent permissions
   - Credentials are used for the promotion operation only

3. **Site Name**
   - AD site for the new DC (e.g., `Default-First-Site-Name`)
   - Used for replication topology and client DC location

4. **DSRM Password**
   - Same requirements as New Forest (8+ characters, entered twice, secure input)

5. **Summary and Execute**
   - Runs `Install-ADDSDomainController` with DNS installation
   - Reboot required after promotion
   - Replication begins automatically from existing DCs

---

## Read-Only Domain Controller (RODC)

Deploys a Read-Only Domain Controller, typically for branch office or edge locations where physical security is limited. An RODC holds a read-only copy of the AD database and does not allow direct write operations.

### Wizard Walkthrough

1. **Domain Name**
   - FQDN of the existing domain

2. **Domain Credentials**
   - Domain Admin credentials required

3. **Site Name**
   - AD site for the RODC

4. **Delegated Admin Account**
   - Optional: specify a user or group that can manage this RODC without being a Domain Admin
   - Useful for branch office IT staff

5. **DSRM Password**
   - Same requirements as other promotion types

6. **Summary and Execute**
   - Runs `Install-ADDSDomainController` with `-ReadOnlyReplica:$true`
   - Reboot required
   - Password caching policies can be configured after promotion

---

## Functional Levels

Both forest and domain functional levels control which AD DS features are available and set the minimum Windows Server version for domain controllers.

| Level | Windows Server Version | Key |
|-------|----------------------|-----|
| Win2012R2 | Server 2012 R2 | `Win2012R2` |
| WinThreshold | Server 2016 **(default)** | `WinThreshold` |
| Win2019 | Server 2019 | `Win2019` |
| Win2022 | Server 2022 | `Win2022` |
| Win2025 | Server 2025 | `Win2025` |

> **Important:** The functional level cannot be lowered after promotion. All DCs in the domain must run a Windows Server version at or above the functional level.

---

## AD DS Status Dashboard

**Menu path:** System Configuration > `[3]` Promote to Domain Controller > `[4]` Check AD DS Status

The dashboard displays four sections when the server is a domain controller:

### AD DS Role Status
- AD-Domain-Services feature installation status
- Whether the server is currently a Domain Controller

### Forest and Domain Information
- Forest name and functional level
- Domain name and functional level
- Number of domain controllers in the domain
- DC names

### FSMO Roles
Shows which DC holds each Flexible Single Master Operation role:

| Role | Scope | Description |
|------|-------|-------------|
| Schema Master | Forest-wide | Controls AD schema modifications |
| Domain Naming Master | Forest-wide | Controls adding/removing domains |
| PDC Emulator | Domain-wide | Time sync source, password changes, GPO |
| RID Master | Domain-wide | Allocates RID pools for new objects |
| Infrastructure Master | Domain-wide | Cross-domain object reference updates |

### Replication Status
- Replication partners (inbound and outbound)
- Last successful replication timestamp
- Last replication result (success or error code)

---

## Batch Mode

Use the following keys in your batch config to automate DC promotion. This runs as **step 15** in the batch sequence, after role template installation (step 14).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `PromoteToDC` | bool | `false` | Promote the server to a Domain Controller |
| `DCPromoType` | string | `"NewForest"` | Promotion type: `"NewForest"`, `"AdditionalDC"`, or `"RODC"` |
| `ForestName` | string | `null` | Domain FQDN (e.g., `"corp.contoso.com"`). Used with `NewForest`; other types use `DomainName` |
| `ForestMode` | string | `"WinThreshold"` | Forest functional level (New Forest only) |
| `DomainMode` | string | `"WinThreshold"` | Domain functional level (New Forest only) |

> **Note:** The DSRM password is always prompted interactively, even in batch mode. This is a security requirement -- DSRM passwords are never stored in configuration files.

### Example: New Forest

```json
{
    "ConfigType": "HOST",
    "ServerRoleTemplate": "DC",
    "PromoteToDC": true,
    "DCPromoType": "NewForest",
    "ForestName": "corp.contoso.com",
    "ForestMode": "WinThreshold",
    "DomainMode": "WinThreshold"
}
```

### Example: Additional DC

```json
{
    "ConfigType": "HOST",
    "ServerRoleTemplate": "DC",
    "PromoteToDC": true,
    "DCPromoType": "AdditionalDC",
    "DomainName": "corp.contoso.com"
}
```

### Example: RODC

```json
{
    "ConfigType": "HOST",
    "PromoteToDC": true,
    "DCPromoType": "RODC",
    "DomainName": "corp.contoso.com"
}
```

### Batch Promotion Behavior

- **NewForest:** Runs `Install-ADDSForest` with the specified forest/domain modes and DNS
- **AdditionalDC:** Runs `Install-ADDSDomainController` using `ForestName` or `DomainName`
- **RODC:** Runs `Install-ADDSDomainController` with `-ReadOnlyReplica:$true`

All variants:
- Install DNS automatically (`-InstallDns:$true`)
- Suppress the automatic reboot (`-NoRebootOnCompletion:$true`) -- RackStack manages reboots via `AutoReboot`
- Set the `RebootNeeded` flag for the post-configuration reboot
- Prompt for DSRM password interactively
- Prompt for domain credentials interactively (AdditionalDC and RODC)

---

See also: [Server Role Templates](Server-Role-Templates) | [Configuration Guide](Configuration) | [Batch Mode](Batch-Mode) | [Troubleshooting](Troubleshooting)
