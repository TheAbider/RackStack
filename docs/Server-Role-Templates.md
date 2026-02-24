# Server Role Templates

RackStack includes 10 built-in server role templates for common Windows Server roles, plus support for custom templates defined in `defaults.json`. Templates automate the installation of Windows features and provide post-install guidance where applicable.

> **New in v1.4.0:** Server role templates with built-in and custom template support.

---

## Table of Contents

- [Built-in Templates](#built-in-templates)
- [Installing a Template](#installing-a-template)
- [Custom Templates](#custom-templates)
- [Viewing Installed Roles](#viewing-installed-roles)
- [Post-Install Guidance](#post-install-guidance)
- [Batch Mode](#batch-mode)

---

## Built-in Templates

| Key | Name | Features | Reboot | Post-Install |
|-----|------|----------|:------:|:------------:|
| **DC** | Domain Controller | AD-Domain-Services, DNS, RSAT-AD-Tools, RSAT-DNS-Server, GPMC | Yes | [AD DS Promotion](AD-DS-Promotion) |
| **FS** | File Server | FS-FileServer, FS-Data-Deduplication, FS-DFS-Namespace, FS-DFS-Replication, FS-Resource-Manager | No | -- |
| **WEB** | Web Server (IIS) | Web-Server, Web-Asp-Net45, Web-Mgmt-Console, Web-Scripting-Tools, Web-Security, Web-Filtering | No | -- |
| **DHCP** | DHCP Server | DHCP, RSAT-DHCP | No | DHCP setup steps |
| **DNS** | DNS Server | DNS, RSAT-DNS-Server | No | -- |
| **PRINT** | Print Server | Print-Server, Print-Services | No | -- |
| **WSUS** | WSUS Server | UpdateServices, UpdateServices-RSAT, UpdateServices-UI | Yes | WSUS setup steps |
| **NPS** | Network Policy Server | NPAS, RSAT-NPAS | No | -- |
| **HV** | Hyper-V Host | Hyper-V, Hyper-V-PowerShell, RSAT-Hyper-V-Tools, Multipath-IO | Yes | -- |
| **RDS** | Remote Desktop Services | RDS-RD-Server, RDS-Licensing, RSAT-RDS-Tools | Yes | -- |

All built-in templates have `ServerOnly: true` -- they require Windows Server and cannot be installed on client operating systems (Windows 10/11).

---

## Installing a Template

**Menu path:** Tools & Utilities > `[8]` Server Role Templates

The template selector shows all available templates with their current installation status:

```
  SERVER ROLE TEMPLATES

  BUILT-IN TEMPLATES
  ──────────────────────────────────────────────────────
  [DC]     Domain Controller              Not Installed
  [FS]     File Server                    Installed
  [WEB]    Web Server (IIS)               Partial (2/6)
  [DHCP]   DHCP Server                    Not Installed
  [DNS]    DNS Server                     Installed
  [PRINT]  Print Server                   Not Installed
  [WSUS]   WSUS Server                    Not Installed
  [NPS]    Network Policy Server          Not Installed
  [HV]     Hyper-V Host                   Installed
  [RDS]    Remote Desktop Services        Not Installed

  CUSTOM TEMPLATES
  ──────────────────────────────────────────────────────
  [MYAPP]  Custom App Server              Not Installed

  [R]  Show All Installed Roles
  [B]  Back
```

**Status indicators:**
- **Installed** -- All features in the template are present
- **Partial (x/y)** -- Some features installed, some missing
- **Not Installed** -- No features from the template are present

### Installation Wizard

1. Select a template by typing its key (e.g., `DC`, `FS`, `WEB`)
2. RackStack displays the features that will be installed with their current status
3. Already-installed features are skipped (incremental install)
4. Confirm to begin installation
5. Each feature is installed via `Install-WindowsFeature`
6. If the template requires a reboot, the reboot flag is set
7. If a post-install action exists and no reboot is pending, the post-install guidance is shown

> **Server OS check:** Templates marked `ServerOnly` will not install on client operating systems. RackStack validates this before proceeding.

---

## Custom Templates

Define custom templates in `defaults.json` under `CustomRoleTemplates`. Custom templates appear in the selector alongside built-in templates.

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

### Field Reference

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `FullName` | string | Yes | Display name shown in the selector menu |
| `Description` | string | Yes | Brief description of what the template installs |
| `Features` | array | Yes | Array of Windows feature names (as used by `Install-WindowsFeature`) |
| `PostInstall` | string/null | Yes | Function name to call after installation, or `null` for no post-install action |
| `RequiresReboot` | bool | Yes | Whether the features require a reboot after installation |
| `ServerOnly` | bool | Yes | If `true`, blocks installation on client operating systems |

> **Tip:** Use `Get-WindowsFeature` on a Windows Server to list all available feature names.

Custom templates are merged with built-in templates at runtime. Keys starting with `_` (comments) are ignored during import.

---

## Viewing Installed Roles

Select `[R]` from the template selector to view all currently installed Windows roles and features on the server. The display groups results into three categories:

- **Roles** -- Top-level server roles (e.g., Hyper-V, DNS Server, DHCP Server)
- **Role Services** -- Sub-components of roles (e.g., RDS-RD-Server under Remote Desktop Services)
- **Features** -- Standalone features (e.g., Multipath-IO, Failover-Clustering, GPMC)

Each entry shows the display name and technical feature name.

---

## Post-Install Guidance

Some templates include post-install guidance that is shown after successful feature installation:

### Domain Controller (DC)

After installing AD DS features, the DC template directs you to the **AD DS Promotion** wizard to complete the promotion:

**Menu path:** System Configuration > `[3]` Promote to Domain Controller

Three promotion types are available: New Forest, Additional DC, and RODC. See [AD DS Promotion](AD-DS-Promotion) for the full walkthrough.

### DHCP Server

After DHCP feature installation, guidance covers:
- Authorizing the DHCP server in Active Directory
- Creating scopes with address ranges
- Configuring scope options (gateway, DNS, domain name)

### WSUS Server

After WSUS feature installation, guidance covers:
- Running `wsusutil.exe postinstall` to complete setup
- Configuring the content storage location
- Completing initial configuration in the WSUS console

---

## Batch Mode

Use the `ServerRoleTemplate` key in your batch config to install a role template during automated configuration. This runs as **step 14** in the batch sequence.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `ServerRoleTemplate` | string/null | `null` | Template key to install: `DC`, `FS`, `WEB`, `DHCP`, `DNS`, `PRINT`, `WSUS`, `NPS`, `HV`, `RDS`, or a custom key. `null` to skip. |

```json
{
    "ConfigType": "HOST",
    "ServerRoleTemplate": "HV",
    "InstallHyperV": true
}
```

In batch mode:
- The template key is case-insensitive (converted to uppercase)
- Both built-in and custom templates (from `defaults.json`) are available
- Invalid template keys cause a validation warning
- Features are installed sequentially via `Install-WindowsFeature`
- The reboot flag is set if the template requires it and features were actually installed
- Post-install actions are not executed in batch mode (they require interactive input)

---

See also: [AD DS Promotion](AD-DS-Promotion) | [Configuration Guide](Configuration) | [Batch Mode](Batch-Mode) | [Troubleshooting](Troubleshooting)
