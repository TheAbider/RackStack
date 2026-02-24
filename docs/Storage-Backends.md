# Storage Backends

RackStack supports six storage backends for Hyper-V hosts, providing unified management regardless of the underlying storage technology. The default backend is **iSCSI**, but you can switch at any time based on your environment.

> **New in v1.3.0:** Storage backend selection, auto-detection, and backend-specific management menus.

---

## Table of Contents

- [Supported Backends](#supported-backends)
- [Selecting a Backend](#selecting-a-backend)
- [Auto-Detection](#auto-detection)
- [iSCSI](#iscsi)
- [Fibre Channel](#fibre-channel)
- [Storage Spaces Direct](#storage-spaces-direct)
- [SMB3](#smb3)
- [NVMe over Fabrics](#nvme-over-fabrics)
- [Local / DAS](#local--das)
- [Unified Status Dashboard](#unified-status-dashboard)
- [Batch Mode Configuration](#batch-mode-configuration)

---

## Supported Backends

| Backend | Description | Requires MPIO | Shared Storage |
|---------|-------------|:-------------:|:--------------:|
| **iSCSI** | iSCSI SAN with dual-path MPIO (A/B side) | Yes | Yes |
| **FC** | Fibre Channel SAN with MPIO | Yes | Yes |
| **S2D** | Storage Spaces Direct (hyperconverged) | No (native) | Yes |
| **SMB3** | SMB 3.0 file share (NAS / Scale-Out File Server) | No (native) | Yes |
| **NVMeoF** | NVMe over Fabrics | No (native) | Yes |
| **Local** | Local disks / Direct-Attached Storage only | No | No |

---

## Selecting a Backend

You can change the active backend in two places:

- **Settings menu:** Settings > `[8]` Storage Backend
- **Storage & SAN menu:** Storage & SAN > `[0]` Change Storage Backend

The backend selector shows all six options with the current selection marked:

```
  SELECT STORAGE BACKEND

  [1]  iSCSI           iSCSI SAN with MPIO (dual-path A/B)
  [2]  FC              Fibre Channel SAN with MPIO
  [3]  S2D             Storage Spaces Direct (hyperconverged)
  [4]  SMB3            SMB 3.0 file share (NAS/SOFS)
  [5]  NVMeoF          NVMe over Fabrics
  [6]  Local           Local/DAS only (no shared storage)

  Current: iSCSI  ◄
```

Changing the backend updates the **Storage & SAN** menu to show backend-specific options.

---

## Auto-Detection

RackStack can automatically detect which storage backend is active by inspecting the current system state. Use **Storage & SAN > `[3]` Detect Storage Backend** to run auto-detection.

**Detection order:**

| Priority | Check | Backend |
|:--------:|-------|---------|
| 1 | Active iSCSI sessions found (`Get-IscsiSession`) | iSCSI |
| 2 | Cluster S2D state is "Enabled" (`Get-ClusterS2D`) | S2D |
| 3 | Fibre Channel HBA ports found with FC disks (`Get-InitiatorPort`, `Get-Disk`) | FC |
| 4 | SMB file share witness or SMB mappings present (`Get-ClusterResource`, `Get-SmbMapping`) | SMB3 |
| 5 | NVMe bus-type disks found (`Get-Disk -BusType NVMe`) | NVMeoF |
| 6 | None of the above detected | Local |

If the detected backend differs from the currently configured backend, RackStack displays a mismatch warning and offers to switch.

---

## iSCSI

The default backend. When iSCSI is selected, the **Storage & SAN** menu shows the full iSCSI & SAN Management submenu:

- `[1]` Configure iSCSI NICs
- `[2]` Identify NICs
- `[3]` Test iSCSI Cabling (A/B side check)
- `[4]` Discover SAN Targets
- `[5]` Connect to iSCSI Targets
- `[6]` Configure MPIO Multipath
- `[7]` Show iSCSI/MPIO Status
- `[8]` Disconnect iSCSI Targets

iSCSI supports dual-path connectivity with A-side/B-side SAN controllers and MPIO Round Robin load balancing.

**New in v1.5.0:** Custom SAN target pairings allow you to define your own A/B pair assignments and host-to-pair retry order. Convention: A side = even suffixes, B side = odd. See [Configuration > SANTargetPairings](Configuration#santargetpairings-v150).

> For a complete step-by-step guide, see [HA iSCSI with MPIO](Runbook-HA-iSCSI).

---

## Fibre Channel

When FC is selected, the **Storage & SAN** menu shows the Fibre Channel management submenu:

- `[1]` Show FC Adapters & Disks
- `[2]` Rescan FC Storage
- `[3]` Configure MPIO for FC
- `[4]` Show FC/MPIO Status

### FC Adapters & Disks

Displays all Fibre Channel HBA ports with:
- World Wide Port Name (WWPN)
- Operational status
- Node address
- FC disk mappings

### FC MPIO

MPIO for Fibre Channel works the same as iSCSI MPIO:
- Enables automatic claim for the FC bus type
- Sets the load balance policy to Round Robin
- Each LUN appears as a single disk with multiple paths

### Rescan

Triggers `Update-HostStorageCache` to discover newly provisioned LUNs or detect changes on the SAN.

---

## Storage Spaces Direct

When S2D is selected, the **Storage & SAN** menu shows the Storage Spaces Direct submenu:

- `[1]` Enable Storage Spaces Direct
- `[2]` Create Virtual Disk
- `[3]` Show S2D Status
- `[4]` Show Storage Backend Status

### Prerequisites

- An active Failover Cluster is required
- At least 2 eligible physical disks across cluster nodes
- S2D is a hyperconverged solution -- local disks on each node are pooled into shared storage

### Enable S2D

The enable wizard:
1. Validates a failover cluster exists
2. Checks for eligible disks (minimum 2)
3. Runs `Enable-ClusterS2D` to create the storage pool
4. Displays the result

### Create Virtual Disk

Creates a virtual disk from the S2D pool with configurable resiliency:

| Resiliency Type | Description | Minimum Disks | Capacity Efficiency |
|----------------|-------------|:-------------:|:-------------------:|
| **Mirror** | Two-way or three-way mirror | 2 or 3 | 50% or 33% |
| **Parity** | Single or dual parity (erasure coding) | 3 or 7 | 67% or 86% |
| **Simple** | No resiliency (striped) | 1 | 100% |

### S2D Status

Displays:
- Cluster name and S2D state
- Storage pool health and capacity
- Virtual disks with resiliency type and operational status
- Physical disks with media type, health, and usage

---

## SMB3

When SMB3 is selected, the **Storage & SAN** menu shows the SMB3 submenu:

- `[1]` Test SMB Share Path
- `[2]` Show SMB3 Status
- `[3]` Show Storage Backend Status

### Test Share Path

Tests a UNC path (e.g., `\\server\share`) for accessibility. Validates the path can be reached and lists available contents.

### SMB3 Status

Displays:
- SMB client configuration
- Active SMB connections
- Mapped drives

> **Note:** SMB Multichannel is supported natively by SMB3 for bandwidth aggregation and failover across multiple NICs, without requiring MPIO.

---

## NVMe over Fabrics

When NVMeoF is selected, the **Storage & SAN** menu shows the NVMe-oF submenu:

- `[1]` Show NVMe-oF Status
- `[2]` Rescan NVMe Storage
- `[3]` Show Storage Backend Status

### NVMe-oF Status

Displays:
- NVMe controllers with model, firmware revision, and transport type
- NVMe physical disks with health status, size, and media type

### Rescan

Triggers `Update-HostStorageCache` to discover newly connected NVMe-oF targets.

---

## Local / DAS

The Local backend indicates no shared storage is configured. Selecting Local disables shared-storage-specific features in the Storage & SAN menu.

This is appropriate for:
- Standalone Hyper-V hosts with local disks only
- Direct-Attached Storage (DAS) configurations
- Development and testing environments

---

## Unified Status Dashboard

Access via **Storage & SAN > `[2]` Show Storage Backend Status** (available regardless of backend selection).

The dashboard shows:

- **Active backend** name
- **MPIO status:** Installed / Not Installed, load balance policy
- **Backend-specific metrics:**

| Backend | Metrics Shown |
|---------|--------------|
| iSCSI | Active session count, iSCSI disk count |
| FC | HBA port count, FC disk count |
| S2D | Cluster S2D state |
| SMB3 | Active connection count |
| NVMeoF | NVMe disk count |
| Local | "No shared storage configured" |

If the detected backend does not match the configured backend, a **mismatch warning** is displayed.

---

## Batch Mode Configuration

When using batch mode with `ConfigType: "HOST"`, the following keys control storage backend behavior:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `StorageBackendType` | string | `"iSCSI"` | Storage backend: `"iSCSI"`, `"FC"`, `"S2D"`, `"SMB3"`, `"NVMeoF"`, or `"Local"` |
| `ConfigureSharedStorage` | bool | `false` | Configure the shared storage backend (iSCSI NICs, FC scan, S2D enable, SMB test, NVMe scan) |
| `ConfigureiSCSI` | bool | `false` | **Deprecated** -- use `ConfigureSharedStorage` with `StorageBackendType: "iSCSI"` instead |
| `ConfigureMPIO` | bool | `false` | Configure MPIO multipath (iSCSI and FC only; S2D/SMB3/NVMe handle paths natively) |
| `SMB3SharePath` | string | `null` | UNC path to SMB3 share. Only used when `StorageBackendType` is `"SMB3"` |

### Backend-Specific Batch Behavior

| Backend | ConfigureSharedStorage Action |
|---------|-------------------------------|
| iSCSI | Configures iSCSI NICs with auto-calculated IPs (existing step 18 behavior) |
| FC | Rescans FC storage, validates FC disks are present |
| S2D | Enables S2D on cluster, validates eligible disk count |
| SMB3 | Tests share path accessibility (requires `SMB3SharePath`) |
| NVMeoF | Rescans NVMe storage via `Update-HostStorageCache` |
| Local | No action (informational message) |

```json
{
    "ConfigType": "HOST",
    "StorageBackendType": "FC",
    "ConfigureSharedStorage": true,
    "ConfigureMPIO": true
}
```

---

See also: [HA iSCSI with MPIO](Runbook-HA-iSCSI) | [Configuration Guide](Configuration) | [Batch Mode](Batch-Mode) | [Troubleshooting](Troubleshooting)
