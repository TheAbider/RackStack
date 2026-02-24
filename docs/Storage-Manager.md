# Storage Manager

The Storage Manager provides disk and volume management for Windows servers, plus Hyper-V host storage initialization. It is accessible from the **Storage & Clustering** menu.

---

## Storage Manager Menu

The Storage Manager is organized into three sections:

### View

| Option | Description |
|--------|-------------|
| **View All Disks** | Shows all physical disks with status, health, size, partition style, and bus type |
| **View All Volumes** | Shows all volumes with drive letter, label, file system, total/free space, and health |
| **View Disk Partitions** | Shows partitions on a specific disk with sizes, types, and drive letters |

### Disk Operations

| Option | Description |
|--------|-------------|
| **Set Disk Online/Offline** | Bring offline disks online or take online disks offline |
| **Initialize Disk** | Initialize a RAW (uninitialized) disk as GPT or MBR |
| **Clear Disk** | Remove all partitions and data from a disk (destructive, requires `YES` confirmation) |

### Partition and Volume Operations

| Option | Description |
|--------|-------------|
| **Create Partition** | Create a new partition with specified size or MAX, assign drive letter |
| **Delete Partition** | Remove a partition (destructive, requires `DELETE` confirmation) |
| **Format Volume** | Format a partition as NTFS, ReFS, or exFAT with configurable allocation unit size |
| **Extend Volume** | Extend a volume into adjacent unallocated space |
| **Shrink Volume** | Shrink a volume to create unallocated space |
| **Change Drive Letter** | Assign, change, or remove drive letters (including CD/DVD drives) |
| **Change Volume Label** | Set or clear the label on a volume |

---

## Safety Features

The Storage Manager includes multiple safety checks to prevent accidental data loss:

- **OS disk protection:** The system disk is identified and excluded from destructive operations (clear, delete). Selecting it requires an explicit warning acknowledgment.
- **System partition protection:** System, Reserved, Recovery, EFI, and Microsoft Reserved partitions are filtered out of partition selection by default.
- **Multi-step confirmation:** Destructive operations require typing `YES`, `DELETE`, or `FORMAT` in all caps, plus a second confirmation prompt.
- **Drive letter map:** A color-coded map shows which letters are available (green), in use (red), or assigned to CD/DVD (yellow, can be moved).

---

## Drive Letter Management

The smart drive letter picker shows a visual map of all letters C-Z with their current assignments:

- **Green** = Available
- **Red** = In use by a disk volume
- **Yellow** = CD/DVD drive (can be automatically relocated)

If you select a letter occupied by a CD/DVD drive, RackStack offers to automatically move the optical drive to a high letter (Z, Y, X...) to free up your chosen letter.

---

## Host Storage Setup

Host Storage Setup (`Initialize-HostStorage`) prepares a Hyper-V host's data drive for VM storage. This is accessed from the **Storage & Clustering** menu or runs as batch step 15 in HOST mode.

### What It Does

1. **Scans for data drives** -- Finds all non-C, fixed, NTFS drives larger than 20 GB
2. **Handles optical drive conflicts** -- If D: is occupied by a CD/DVD drive, offers to relocate it automatically
3. **Lets you select a drive** -- Lists valid data drives with size and free space (D: is marked as recommended)
4. **Creates directory structure** on the selected drive:

```
D:\Virtual Machines\           # VM configuration and VHDs
D:\Virtual Machines\_BaseImages\  # Sysprepped VHD template cache
D:\ISOs\                       # ISO image storage
```

5. **Sets Hyper-V default paths** -- Configures `VirtualMachinePath` and `VirtualHardDiskPath` via `Set-VMHost`
6. **Updates Defender exclusion paths** -- Auto-generates paths for the selected drive (see below)

### Dynamic Path Generation

All storage paths are dynamically generated based on the selected drive letter. If you choose E: instead of D:, all paths update accordingly:

| Variable | Example (E: selected) |
|----------|-----------------------|
| `HostVMStoragePath` | `E:\Virtual Machines` |
| `VHDCachePath` | `E:\Virtual Machines\_BaseImages` |
| `HostISOPath` | `E:\ISOs` |

You can also pre-configure storage paths in `defaults.json`:

```json
"StoragePaths": {
    "HostVMStoragePath": "D:\\Virtual Machines",
    "HostISOPath": "D:\\ISOs",
    "VHDCachePath": "D:\\Virtual Machines\\_BaseImages",
    "ClusterISOPath": "C:\\ClusterStorage\\Volume1\\ISOs",
    "ClusterVHDCachePath": "C:\\ClusterStorage\\Volume1\\_BaseImages"
}
```

### Batch Mode

In batch mode (HOST config), set:

```json
"InitializeHostStorage": true,
"HostStorageDrive": "D"
```

Set `HostStorageDrive` to `null` to auto-select the first available non-C fixed NTFS drive.

---

## VHD Management

RackStack manages sysprepped VHD templates used for VM deployment. VHDs are cached locally in the `_BaseImages` directory to avoid re-downloading for each VM.

### Base Image Cache

- Location: `{Drive}:\Virtual Machines\_BaseImages\` (standalone) or `C:\ClusterStorage\Volume1\_BaseImages\` (cluster)
- VHDs are matched by OS version keyword in the filename (e.g., `Server2022.vhdx`)
- Integrity checking: file size is compared against the remote source; mismatched files are silently re-downloaded
- Filename mismatch detection: if a newer version exists on the file server, you are prompted to update

### VHD Download Flow

1. User selects an OS version (Server 2019, 2022, or 2025)
2. RackStack checks the local cache for an existing VHD
3. If not cached, discovers the file on the configured file server
4. Downloads with progress tracking (speed, ETA)
5. Caches the VHD for future deployments

### File Server Configuration

VHD downloads require a file server configured in `defaults.json`:

```json
"FileServer": {
    "BaseURL": "https://files.yourdomain.com/server-tools",
    "VHDsFolder": "VirtualHardDrives"
}
```

See [File Server Setup](File-Server-Setup) for full configuration details.

---

## ISO Management

ISOs are managed similarly to VHDs, stored in the `ISOs` directory on the host storage drive.

- Location: `{Drive}:\ISOs\` (standalone) or `C:\ClusterStorage\Volume1\ISOs\` (cluster)
- Download source: file server's ISOs folder
- Cache behavior: checks for existing files, validates size integrity, detects newer versions
- Used by VM deployment when creating VMs from ISO rather than sysprepped VHD

---

## Defender Exclusion Setup

When host storage is initialized, RackStack auto-generates Windows Defender exclusion paths based on the selected drive. This prevents Defender from scanning VM files, which significantly improves Hyper-V performance.

### Auto-Generated Path Exclusions

For a host using drive D:, the following paths are excluded:

```
D:\Virtual Machines
D:\Hyper-V
D:\ISOs
D:\Virtual Machines\_BaseImages
```

If Cluster Shared Volumes exist under `C:\ClusterStorage`, each CSV volume's `Virtual Machines` directory is also added.

### Process Exclusions

These Hyper-V processes are excluded from Defender scanning:

- `vmms.exe` (Virtual Machine Management Service)
- `vmwp.exe` (Virtual Machine Worker Process)
- `vmcompute.exe` (Hyper-V Host Compute Service)

### Static Exclusions

Additional static paths can be configured in `defaults.json`:

```json
"DefenderExclusionPaths": [
    "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V",
    "C:\\ProgramData\\Microsoft\\Windows\\Hyper-V\\Snapshots",
    "C:\\Users\\Public\\Documents\\Hyper-V\\Virtual Hard Disks",
    "C:\\ClusterStorage"
]
```

If `DefenderCommonVMPaths` is specified in `defaults.json`, those paths are used as-is and dynamic path generation is skipped.

### Interactive Defender Management

From the **Configure Server** menu, **Defender Exclusions** provides:

- Add path and process exclusions manually
- Bulk-add all recommended Hyper-V exclusions
- View all current exclusions
- Remove individual exclusions

---

See also: [Configuration Guide](Configuration) | [Batch Mode](Batch-Mode) | [File Server Setup](File-Server-Setup)
