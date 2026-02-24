# Cluster Management

RackStack provides cluster-aware operations for Windows Server Failover Clusters with Hyper-V. These features are accessible from the **Storage & Clustering** menu under **Cluster Operations**, **VM Checkpoints**, and **VM Export/Import**.

---

## Cluster Dashboard

The cluster dashboard provides a real-time overview of your failover cluster. It displays:

### Node Status

Each cluster node is shown with its current state and the number of VMs it owns:

| Symbol | State | Meaning |
|--------|-------|---------|
| `[*]` | Up | Node is online and accepting workloads |
| `[~]` | Paused | Node is paused (drained), not accepting new VMs |
| `[o]` | Down | Node is offline or unreachable |

### Cluster Shared Volumes (CSV)

For each CSV, the dashboard shows:

- Volume name and owner node
- Used/total space with percentage
- Visual progress bar (color-coded: green < 70%, yellow < 90%, red >= 90%)
- Redirected I/O warnings (indicates performance degradation)

### Key Resources

Critical cluster resources are listed with online/offline status:

- Network Name resources
- IP Address resources
- File Share Witness / Disk Witness

### Live Migration

Shows whether live migration is enabled and the maximum number of simultaneous migrations configured on the host.

---

## Drain and Resume Operations

### Drain Node

Draining a node gracefully evacuates all VMs to other cluster nodes, then pauses the node. This is used before maintenance (patching, hardware replacement, etc.).

**What happens:**
1. Select an online (Up) node from the list
2. All VMs on that node are live-migrated to other available nodes
3. The node is paused (will not accept new VM placements)
4. The operation waits for all migrations to complete before returning

Uses `Suspend-ClusterNode -Drain -Wait` under the hood, which performs live migration for running VMs.

### Resume Node

Resuming a paused node brings it back into the cluster and optionally fails VMs back to it.

**Options:**
- **Resume without failback:** The node becomes available for new workloads, but existing VMs stay where they are
- **Resume with failback (Immediate):** The node comes back online and VMs that were originally hosted on it are moved back immediately

---

## CSV Health Status

The CSV Health screen provides detailed information for each Cluster Shared Volume:

| Field | Description |
|-------|-------------|
| **State** | Online/Offline status |
| **Owner Node** | Which node currently owns the CSV |
| **Space** | Used and total space with percentage |
| **Free** | Available space in GB |
| **Redirected I/O** | Warning if I/O is being redirected through another node (performance issue) |
| **Low Space** | Warning if usage exceeds 90% |

Space usage is color-coded:
- **Green:** Less than 70% used
- **Yellow:** 70-89% used
- **Red:** 90%+ used

---

## VM Checkpoints

VM Checkpoint Management provides full lifecycle control over Hyper-V checkpoints (snapshots). Access it from **Storage & Clustering > VM Checkpoints**.

### Operations

| Option | Description |
|--------|-------------|
| **List All Checkpoints** | Shows all checkpoints across all VMs with name, creation date, size, and type |
| **Create Checkpoint** | Create a new checkpoint on a selected VM |
| **Restore Checkpoint** | Restore a VM to a previous checkpoint state |
| **Delete Checkpoint** | Delete individual checkpoints or all checkpoints at once |

### Creating Checkpoints

When creating a checkpoint, you choose:

1. **Target VM** -- Select from running or powered-off VMs
2. **Checkpoint name** -- Custom name or auto-generated timestamp (e.g., `Checkpoint_20260223_143052`)
3. **Checkpoint type:**

| Type | Description | Best For |
|------|-------------|----------|
| **Production** (Recommended) | Uses VSS for application-consistent state | Production VMs, databases |
| **Standard** | Saves current memory state (faster) | Dev/test VMs, quick snapshots |

### Restoring Checkpoints

Restoring a checkpoint reverts a VM to the exact state captured at that point. A warning is displayed because all changes made since the checkpoint will be lost.

### Deleting Checkpoints

You can delete checkpoints individually or use the **Delete ALL** option to clean up all checkpoints across all VMs in one operation. Each deletion is confirmed before execution.

### Display

Checkpoints are listed in a table showing:
- VM name
- Checkpoint name
- Creation date/time
- Size (system files)
- Type indicator (green = Production, cyan = Standard)

---

## VM Export / Import

### Export VM

Exports a VM's complete configuration and virtual hard disks to a specified location. This creates a portable copy that can be imported on another host.

**Features:**
- Select from all VMs on the host
- Shows VM state and disk size for each VM
- Live export is supported for running VMs (though shutting down first is recommended)
- Progress tracking with transfer speed and elapsed time
- Default export path: `{VMStoragePath}\Exports`

**Export contents:**
- `.vmcx` configuration file
- Virtual hard disk files
- Checkpoint files (if any)

### Import VM

Imports a previously exported VM from a folder or `.vmcx` file.

**Import modes:**

| Mode | Description | Use Case |
|------|-------------|----------|
| **Copy** (Recommended) | Creates a new VM with a new unique ID, copies all files to the destination | Cloning VMs, importing from another host |
| **Register** | Uses existing files in place, keeps the original VM ID | Reattaching a VM after host rebuild |

**Features:**
- Accepts a folder path or direct `.vmcx` file path
- Drag-and-drop path support
- Auto-discovers `.vmcx` files in the specified directory
- If multiple `.vmcx` files exist, prompts for selection

---

## Cluster-Aware Operations

Several RackStack features are cluster-aware and adapt their behavior when running on a cluster node:

| Feature | Cluster Behavior |
|---------|-----------------|
| **VM Deployment** | Can deploy to Cluster Shared Volumes instead of local storage |
| **VHD Cache** | Uses `ClusterVHDCachePath` (e.g., `C:\ClusterStorage\Volume1\_BaseImages`) |
| **ISO Storage** | Uses `ClusterISOPath` (e.g., `C:\ClusterStorage\Volume1\ISOs`) |
| **Defender Exclusions** | Auto-adds CSV volume paths to exclusion list |
| **Host Storage** | Detects CSV volumes and includes them in path generation |
| **Config Export** | Includes cluster name, node states, and cluster membership in reports |

### Storage Path Configuration

Configure cluster paths in `defaults.json`:

```json
"StoragePaths": {
    "ClusterISOPath": "C:\\ClusterStorage\\Volume1\\ISOs",
    "ClusterVHDCachePath": "C:\\ClusterStorage\\Volume1\\_BaseImages"
}
```

---

See also: [Storage Manager](Storage-Manager) | [Configuration Export](Configuration-Export) | [Runbook: Host Migration](Runbook-Host-Migration)
