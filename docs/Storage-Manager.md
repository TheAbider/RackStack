# Storage Manager Guide

This guide covers RackStack's host storage initialization, dynamic Defender exclusion paths, and VHD management features.

---

## Table of Contents

- [Host Storage Initialization](#host-storage-initialization)
- [Dynamic Defender Exclusion Paths](#dynamic-defender-exclusion-paths)
- [VHD Management](#vhd-management)
- [VHD Preparation](#vhd-preparation)

---

## Host Storage Initialization

**Menu path:** Deploy Virtual Machines > [7] Host Storage Setup

Host Storage Setup configures the data drive and directory structure used by Hyper-V for VM storage, ISOs, and base images.

### Drive Selection

RackStack scans for eligible data drives using these criteria:

- NTFS file system
- Fixed drive (not removable or optical)
- Not the C: drive
- Greater than 20 GB capacity

If the D: drive letter is occupied by an optical/DVD drive, RackStack offers to reassign it to free up D: for data storage.

When multiple eligible drives exist, you select which one to use. In batch mode, set `HostStorageDrive` to a specific drive letter (e.g., `"D"`) or `null` to auto-select the first available.

### Directory Structure

After selecting a drive, RackStack creates the standard folder structure:

```
D:\
    Virtual Machines\           VM configuration and VHD files
    Virtual Machines\_BaseImages\   Cached sysprepped VHDs for deployment
    ISOs\                       Server installation ISOs
```

### Hyper-V Default Paths

If Hyper-V is installed, RackStack sets the host's default paths to point to the selected drive:

- **Virtual Machine Path:** `D:\Virtual Machines`
- **Virtual Hard Disk Path:** `D:\Virtual Machines`

These defaults apply to all new VMs created on the host unless overridden during VM creation.

### Storage Paths in defaults.json

Storage paths can be customized via `defaults.json`:

```json
"StoragePaths": {
    "HostVMStoragePath": "D:\\Virtual Machines",
    "HostISOPath": "D:\\ISOs",
    "ClusterISOPath": "C:\\ClusterStorage\\Volume1\\ISOs",
    "VHDCachePath": "D:\\Virtual Machines\\_BaseImages",
    "ClusterVHDCachePath": "C:\\ClusterStorage\\Volume1\\_BaseImages"
}
```

Drive letters in these paths are updated automatically when you select a different data drive during Host Storage Setup.

---

## Dynamic Defender Exclusion Paths

Windows Defender real-time scanning can significantly impact Hyper-V performance. RackStack maintains two sets of exclusion paths and generates them dynamically based on the selected storage drive.

### Static Exclusion Paths

These paths are always excluded regardless of which data drive is selected:

```
C:\ProgramData\Microsoft\Windows\Hyper-V
C:\ProgramData\Microsoft\Windows\Hyper-V\Snapshots
C:\Users\Public\Documents\Hyper-V\Virtual Hard Disks
C:\ClusterStorage
```

These can be overridden via `DefenderExclusionPaths` in `defaults.json`.

### Dynamic VM Paths

When a host storage drive is selected (interactively or via batch mode), RackStack generates VM-specific exclusion paths automatically:

```
{drive}:\Virtual Machines
{drive}:\Hyper-V
{drive}:\ISOs
{drive}:\Virtual Machines\_BaseImages
```

For example, selecting drive E: generates:

```
E:\Virtual Machines
E:\Hyper-V
E:\ISOs
E:\Virtual Machines\_BaseImages
```

If Cluster Shared Volumes exist (`C:\ClusterStorage`), each CSV volume is also added to the dynamic list.

### How Paths Are Applied

- **Host Storage Setup:** After selecting a drive, dynamic paths are regenerated automatically.
- **Batch mode:** When `ConfigureDefenderExclusions` is `true`, Step 19 applies both static and dynamic paths.
- **defaults.json override:** If `DefenderCommonVMPaths` is set in `defaults.json`, those paths are used instead of the auto-generated ones.

**Menu path:** Server Config > Defender Exclusions

---

## VHD Management

**Menu path:** Deploy Virtual Machines > [5] Download / Manage Sysprepped VHDs

RackStack uses a local VHD cache (`_BaseImages` directory) to store sysprepped template VHDs. When deploying a VM with a pre-installed OS, the base VHD is copied from this cache to the VM's storage folder.

### Downloading VHDs from File Server

If a file server is configured in `defaults.json` (see [File Server Setup](FileServer-Setup.md)):

1. RackStack lists available VHDs from the remote `VirtualHardDrives` folder.
2. Select the VHDs to download (e.g., `Server2025_Sysprepped.vhdx`).
3. Files are downloaded to the local `_BaseImages` cache.
4. Downloaded VHDs are reused across all subsequent VM deployments.

The file server connection supports Cloudflare Access authentication for internet-facing setups and plain HTTP for LAN-only deployments.

### Local VHD Cache

The cache directory is located at:

- **Standalone host:** `{drive}:\Virtual Machines\_BaseImages\`
- **Cluster:** `C:\ClusterStorage\Volume1\_BaseImages\` (configurable via `StoragePaths.ClusterVHDCachePath`)

Cached VHDs persist between RackStack sessions. You only need to download a VHD once per host. During VM deployment, the base VHD is copied to the VM's own directory and optionally converted from dynamic to fixed.

### Managing the Cache

The VHD management screen shows:

- Available VHDs on the file server (if connected)
- Locally cached VHDs with file sizes
- Download status for each VHD

You can download new VHDs or delete cached ones that are no longer needed.

---

## VHD Preparation

Template VHDs must be prepared before they can be used for rapid VM deployment. RackStack supports two preparation methods:

- **Windows:** Sysprep generalizes the OS and triggers OOBE (Out-Of-Box Experience) on first boot.
- **Linux:** cloud-init handles first-boot configuration (hostname, network, SSH keys).

For detailed instructions on creating template VHDs, see the [VHD Preparation Guide](VHD-Preparation.md).

### Naming Convention

| OS | Template Name |
|----|---------------|
| Windows Server 2025 | `Server2025_Sysprepped.vhdx` |
| Windows Server 2022 | `Server2022_Sysprepped.vhdx` |
| Windows Server 2019 | `Server2019_Sysprepped.vhdx` |
| Ubuntu 24.04 | `Ubuntu2404_CloudInit.vhdx` |
| Rocky Linux 9 | `Rocky9_CloudInit.vhdx` |
| Debian 12 | `Debian12_CloudInit.vhdx` |
