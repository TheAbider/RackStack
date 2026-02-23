# Cluster Management Guide

This guide covers RackStack's Failover Clustering features: cluster creation, the cluster dashboard, drain and resume operations, VM checkpoint management, and Cluster Shared Volume management.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Cluster Creation Wizard](#cluster-creation-wizard)
- [Cluster Dashboard](#cluster-dashboard)
- [Drain and Resume Operations](#drain-and-resume-operations)
- [VM Checkpoint Management](#vm-checkpoint-management)
- [CSV Management](#csv-management)

---

## Prerequisites

Before using cluster management features:

- **Failover Clustering** must be installed on all participating nodes. Install via **Cluster Management > [I] Install Failover Clustering** or set `InstallFailoverClustering: true` in batch mode.
- All nodes must be **domain-joined** to the same Active Directory domain.
- All nodes should have **identical storage connectivity** (iSCSI targets connected, MPIO configured).
- Your domain account must have **cluster admin permissions** on all nodes.
- A reboot is required after installing Failover Clustering before cluster operations are available.

---

## Cluster Creation Wizard

**Menu path:** Cluster Management > [1] Create New Cluster

The wizard walks through creating a new Hyper-V failover cluster.

### Step 1: Cluster Name

Enter a NetBIOS name for the cluster (max 15 characters). This becomes the cluster's virtual computer object in Active Directory.

### Step 2: Cluster IP Address

Enter a static IP address for the cluster. This IP must be:

- On the same subnet as the management network.
- Not already assigned to any device.
- Reachable from all cluster nodes.

### Step 3: Add Nodes

The wizard starts with the local server as the first node. Add additional nodes by hostname. Each node is validated for:

- Reachability (ping test)
- Failover Clustering feature installed
- Domain membership

### Step 4: Validation

RackStack offers to run the cluster validation wizard before creation. Validation tests hardware compatibility, network configuration, and storage access across all nodes. The validation report identifies blocking issues that would prevent cluster creation.

> **Recommendation:** Always run validation before creating a production cluster.

### Step 5: Create

After validation passes, RackStack calls `New-Cluster` with the specified name, IP, and node list. The cluster is created and the local node becomes the first member.

### Joining an Existing Cluster

**Menu path:** Cluster Management > [2] Join Existing Cluster

To add the current server to an existing cluster:

1. Enter the cluster name.
2. RackStack validates that Failover Clustering is installed locally.
3. The node is added via `Add-ClusterNode`.

---

## Cluster Dashboard

**Menu path:** Cluster Management > Cluster Dashboard

The dashboard provides a real-time overview of cluster health. It displays:

### Node Status

| Column | Description |
|--------|-------------|
| Name | Node hostname |
| State | `Up`, `Down`, `Paused`, or `Joining` |
| Drain Status | Shows drain progress when a node is being evacuated |

### Cluster Shared Volumes

| Column | Description |
|--------|-------------|
| Name | CSV friendly name |
| Path | Mount point (e.g., `C:\ClusterStorage\Volume1`) |
| State | `Online` or `Offline` |
| Free Space | Available space in GB |
| Total Size | Total capacity in GB |

### Cluster Roles

Lists all cluster virtual machine roles with their current state and owner node.

### Quick Actions

From the dashboard, you can jump directly to:

- Drain a node
- Resume a node
- View detailed CSV health
- Open the full cluster operations menu

---

## Drain and Resume Operations

Draining a cluster node live-migrates all VMs to other available nodes, allowing you to perform maintenance without VM downtime.

### Draining a Node

**Menu path:** Cluster Dashboard > Drain Node

1. Select the node to drain from the list of cluster members.
2. RackStack confirms the action and checks that other nodes have sufficient capacity.
3. The node is paused (`Suspend-ClusterNode -Drain`), triggering Live Migration of all hosted VMs.
4. Progress is displayed as each VM migrates.
5. The drain completes when all VMs have moved.

**Expected duration:** 10-60 seconds per VM depending on memory size and network speed. A node with 10 VMs at 2 simultaneous migrations typically takes 5-10 minutes.

### Resuming a Node

**Menu path:** Cluster Dashboard > Resume Node

After maintenance:

1. Select the paused node.
2. Choose a failback option:
   - **Immediate:** VMs migrate back to the resumed node based on preferred owner settings.
   - **No failback:** Node becomes available for new placements but existing VMs stay where they are.
3. The node state changes from `Paused` back to `Up`.

### Best Practices

- Always verify cluster health before draining. Do not drain a node if another node is already down or paused.
- For 2-node clusters, ensure the quorum witness is online before draining.
- Use "No failback" during business hours to avoid unnecessary VM migrations.
- See the [Host Migration Runbook](Runbook-Host-Migration.md) for the complete step-by-step procedure.

---

## VM Checkpoint Management

**Menu path:** Storage & Clustering > VM Checkpoint Management

RackStack provides a centralized interface for managing VM checkpoints (snapshots) across standalone hosts and clusters.

### Viewing Checkpoints

Lists all checkpoints for all VMs with:

- VM name
- Checkpoint name
- Creation time
- Checkpoint type (Standard or Production)

For clustered environments, checkpoints are listed across all cluster nodes.

### Creating Checkpoints

1. Select one or more VMs from the list.
2. Enter a checkpoint name (or accept the default timestamped name).
3. RackStack creates production checkpoints by default (application-consistent via VSS).
4. Checkpoint creation is confirmed with the resulting checkpoint name and timestamp.

### Restoring Checkpoints

1. Select a VM.
2. View its checkpoint tree.
3. Select the checkpoint to restore.
4. Confirm the restore operation.
5. The VM reverts to the selected checkpoint state.

> **Warning:** Restoring a checkpoint discards all changes made after that checkpoint was created.

### Removing Checkpoints

1. Select a VM.
2. View its checkpoint tree.
3. Select one or more checkpoints to remove.
4. Confirm deletion.
5. The checkpoint files are merged back into the parent VHD.

Checkpoint removal triggers a merge operation that can take several minutes for large VMs. The VM continues running during the merge.

---

## CSV Management

**Menu path:** Cluster Management > [4] Manage Cluster Shared Volumes

Cluster Shared Volumes (CSVs) provide shared storage accessible from all cluster nodes simultaneously. VMs stored on CSVs can be live-migrated without storage migration.

### Viewing CSVs

The CSV management screen shows all current volumes with:

| Column | Description |
|--------|-------------|
| Name | Volume friendly name |
| State | `Online` or `Offline` |
| Path | Mount path (e.g., `C:\ClusterStorage\Volume1`) |
| Free Space | Available space in GB |
| Total Size | Total capacity in GB |
| Used % | Percentage of capacity consumed |

### Adding a Disk to CSV

**Menu option:** [1] Add Disk to CSV

1. RackStack lists available cluster disks (physical disks added as cluster resources but not yet in CSV).
2. Select a disk to add.
3. The disk becomes a CSV, accessible at `C:\ClusterStorage\Volume{N}\` on all nodes.

### Removing a Disk from CSV

**Menu option:** [2] Remove Disk from CSV

1. Select the CSV to remove.
2. Confirm the operation.
3. The disk is removed from CSV but remains a cluster resource.

> **Important:** Ensure no VMs are stored on the CSV before removing it. Move or shut down VMs first.

### Showing Available Cluster Disks

**Menu option:** [3] Show Available Cluster Disks

Lists all physical disks that are cluster resources but not yet added to CSV. These are candidates for CSV addition.

### CSV Health Check

The cluster dashboard includes a CSV health view that shows:

- Volume state and redundancy status
- Disk I/O statistics
- Ownership (which node currently coordinates I/O for each CSV)
- Redirect mode status (direct I/O vs. redirected I/O)

### Troubleshooting CSVs

| Issue | Likely Cause | Resolution |
|-------|-------------|------------|
| CSV shows Offline | Underlying iSCSI disk lost | Check iSCSI sessions via iSCSI & SAN Management |
| CSV not appearing | Disk not added as cluster resource | Add via Failover Cluster Manager, then add to CSV |
| CSV in redirected mode | Direct I/O path failed | Check storage connectivity on the owner node |
| Insufficient space | VMs consuming too much storage | Expand the underlying LUN or migrate VMs |
