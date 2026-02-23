# Runbook: Host Migration (Cluster Node Drain/Replace)

This runbook covers the workflow for draining a cluster node, migrating its VMs, performing maintenance or replacement, and bringing the node back online. All steps reference RackStack menu paths where applicable.

---

## Table of Contents

- [Overview](#overview)
- [Pre-Migration Checklist](#pre-migration-checklist)
- [Step 1: Verify Cluster Health](#step-1-verify-cluster-health)
- [Step 2: Verify Live Migration Settings](#step-2-verify-live-migration-settings)
- [Step 3: Drain the Cluster Node](#step-3-drain-the-cluster-node)
- [Step 4: Verify All VMs Migrated](#step-4-verify-all-vms-migrated)
- [Step 5: Perform Maintenance or Replacement](#step-5-perform-maintenance-or-replacement)
- [Step 6: Resume the Node](#step-6-resume-the-node)
- [Step 7: Post-Migration Health Check](#step-7-post-migration-health-check)
- [Node Replacement Procedure](#node-replacement-procedure)
- [Rollback: If Migration Fails](#rollback-if-migration-fails)

---

## Overview

In a Hyper-V failover cluster, each node hosts a set of VMs. To perform maintenance on a node (hardware replacement, firmware update, OS patching), you must first move all its VMs to other nodes. This is accomplished by pausing and draining the node, which triggers Live Migration of all VMs to other available cluster members.

**Key principle:** Always verify cluster health before and after any maintenance operation.

---

## Pre-Migration Checklist

Before starting any node migration:

- [ ] **All cluster nodes are Up.** Do not drain a node if another node is already down or paused.
- [ ] **Quorum is healthy.** Losing a node must not drop below quorum. For 2-node clusters, ensure the witness (disk, file share, or cloud) is online.
- [ ] **All CSVs are Online.** Navigate to **Cluster Management > [4] Manage CSVs** to verify.
- [ ] **All VMs are Running** (or in expected state). View via **Deploy Virtual Machines > [4] View Existing VMs**.
- [ ] **Live Migration is enabled and tested.** A test migration should have been performed previously.
- [ ] **Sufficient resources on remaining nodes.** Remaining nodes must have enough CPU and RAM to host all migrated VMs.
- [ ] **iSCSI sessions are active on all nodes.** Verify via **iSCSI & SAN Management > [6] Show iSCSI/MPIO Status**.
- [ ] **Backup current configurations.** Document the current VM placement (which VMs are on which node).
- [ ] **Schedule a maintenance window.** While Live Migration is transparent to users, have a plan if something goes wrong.

---

## Step 1: Verify Cluster Health

**Menu path:** Main Menu > Cluster Management > [7] Show Cluster Status

Review the status screen which shows:
- **Cluster name** and confirmation of connectivity.
- **Nodes** section: All nodes should show `Up` status.
- **Cluster Resources** section: All resources should show `Online` status.

If any node shows a state other than `Up` or any resource is `Offline` or `Failed`, resolve those issues before proceeding with maintenance.

### Check CSV Health

**Menu path:** Cluster Management > [4] Manage Cluster Shared Volumes

Verify all CSVs show:
- State: `Online`
- Free space is reported (not N/A).
- Sufficient free space exists on the target CSVs for any additional VMs that will migrate in.

### Check Quorum

**Menu path:** Cluster Management > [6] Configure Quorum/Witness

The current quorum configuration is displayed at the top:
- Note the quorum type and resource.
- For 2-node clusters: after draining one node, quorum is maintained by the node majority plus the witness. The witness must be reachable.

---

## Step 2: Verify Live Migration Settings

**Menu path:** Cluster Management > [5] Configure Live Migration

Review the settings display:
- **Live Migration Enabled:** Must be `True`.
- **Simultaneous Migrations:** Typically 1-2 for 1GbE networks, up to 4-6 for 10GbE.
- **Authentication:** Kerberos (recommended for domain environments) or CredSSP.
- **Performance Option:** Compression (balanced) or SMB (fastest, requires SMB Direct).

If Live Migration is not enabled, select `[1] Enable Live Migration` before proceeding.

### Test Migration (Recommended)

Before draining, manually live-migrate one small VM to confirm the process works:

1. Open Hyper-V Manager or Failover Cluster Manager.
2. Right-click a VM > Move > Live Migration.
3. Select the target node.
4. Confirm the VM migrates without downtime.

---

## Step 3: Drain the Cluster Node

Draining a node pauses it (preventing new VMs from being placed on it) and live-migrates all running VMs to other available nodes.

### Using Failover Cluster Manager (GUI)

1. Open Failover Cluster Manager.
2. Navigate to Nodes.
3. Right-click the target node > Pause > Drain Roles.
4. Monitor the migration progress. Each VM will show its migration status.

### Using PowerShell

```powershell
# Pause the node and drain all roles
Suspend-ClusterNode -Name "NodeName" -Drain

# Monitor drain progress
Get-ClusterNode -Name "NodeName" | Select-Object Name, State, DrainStatus
```

### What Happens During Drain

1. The node state changes to `Paused`.
2. Each VM on the node is live-migrated to the best available node.
3. Cluster automatically selects target nodes based on resource availability.
4. VMs continue running during migration -- no downtime for end users.
5. The drain completes when all VMs have been moved.
6. Non-VM cluster resources (e.g., cluster name, file share witness) may also move.

### Expected Duration

- Each VM typically takes 10-60 seconds to migrate depending on memory size and network speed.
- A node with 10 VMs at 2 simultaneous migrations takes approximately 5-10 minutes.
- Large-memory VMs (32+ GB) may take longer.

---

## Step 4: Verify All VMs Migrated

After the drain completes:

1. **Check node state:** The drained node should show `Paused` in **Cluster Management > [7] Show Cluster Status**.

2. **Check VM distribution:** Navigate to **Deploy Virtual Machines > [4] View Existing VMs** (connected to the cluster). All VMs should be running and assigned to non-drained nodes.

3. **Test critical services:** Verify key applications (file shares, print queues, databases) are accessible from client workstations.

4. **Check for failed migrations:** If any VMs show as `Off` or `Saved` instead of `Running`, they may have failed to migrate. These need manual attention:
   - Check the VM's event log in Failover Cluster Manager.
   - Common causes: incompatible processor features, VHD on non-shared storage, insufficient resources on target nodes.
   - Manually start the VM on a healthy node if needed.

---

## Step 5: Perform Maintenance or Replacement

With all VMs safely on other nodes, the drained node can now be serviced:

### Routine Maintenance
- Apply Windows Updates and reboot.
- Update firmware (BIOS, NIC, RAID controller, iDRAC/iLO).
- Replace failed hardware components (RAM, disks, power supplies).
- Update drivers.

### Node Replacement

See the [Node Replacement Procedure](#node-replacement-procedure) section below for replacing a node entirely.

### During Maintenance

- The drained node can be powered off safely.
- The cluster continues operating with reduced capacity.
- Do not drain additional nodes unless the remaining capacity is sufficient.

---

## Step 6: Resume the Node

After maintenance is complete and the node is back online:

### Using Failover Cluster Manager (GUI)

1. Open Failover Cluster Manager.
2. Navigate to Nodes.
3. Right-click the paused node > Resume > Fail Roles Back.
4. The node rejoins the cluster and VMs begin migrating back to balance the load.

### Using PowerShell

```powershell
# Resume the node (VMs will auto-balance back)
Resume-ClusterNode -Name "NodeName" -Failback Immediate

# Or resume without automatic failback
Resume-ClusterNode -Name "NodeName" -Failback NoFailback
```

### Failback Options

- **Immediate:** VMs migrate back to the resumed node right away based on preferred owner settings.
- **NoFailback:** Node becomes available for new placements but existing VMs stay where they are. Use this during business hours to avoid unnecessary migrations.

---

## Step 7: Post-Migration Health Check

After the node is resumed:

1. **Verify node state:** **Cluster Management > [7] Show Cluster Status** should show all nodes as `Up`.

2. **Verify all resources are Online:** Check the Cluster Resources section. All resources should show `Online`.

3. **Check VM distribution:** Confirm VMs are balanced across nodes as expected.

4. **Verify iSCSI connectivity on the resumed node:**
   - Navigate to **iSCSI & SAN Management > [6] Show iSCSI/MPIO Status**.
   - Confirm iSCSI sessions are active and persistent.
   - Confirm MPIO is showing expected paths.
   - iSCSI sessions configured as persistent should auto-reconnect after reboot.

5. **Verify CSV access:** **Cluster Management > [4] Manage CSVs** should show all CSVs as Online with correct free space.

6. **Test critical applications:** Verify file shares, databases, and other services are accessible.

7. **Monitor for 15-30 minutes:** Watch for any VM failovers or resource warnings in the cluster event log.

---

## Node Replacement Procedure

When replacing a cluster node entirely (e.g., hardware end-of-life):

### Phase 1: Drain Old Node

Follow Steps 1-4 above to drain all VMs off the old node.

### Phase 2: Evict Old Node

1. In Failover Cluster Manager: right-click the node > More Actions > Evict.
2. Or via PowerShell: `Remove-ClusterNode -Name "OldNodeName" -Force`
3. The node is removed from cluster membership.

### Phase 3: Configure New Node with RackStack

On the new replacement server, run RackStack to configure:

1. **Network Configuration:**
   - Configure management NIC and SET (Switch Embedded Teaming).
   - Configure iSCSI NICs via **iSCSI & SAN Management > [1] Configure iSCSI NICs** (auto-config recommended).

2. **Install Required Features:**
   - Hyper-V role.
   - Failover Clustering: **Cluster Management > [I] Install Failover Clustering**.
   - MPIO: **iSCSI & SAN Management > [5] Configure MPIO Multipath**.
   - Reboot after feature installation.

3. **Configure iSCSI & MPIO:**
   - After reboot, return to **iSCSI & SAN Management > [5] Configure MPIO Multipath** to enable iSCSI auto-claim.
   - Connect to iSCSI targets via **[4] Connect to iSCSI Targets**.

4. **Initialize Host Storage:**
   - **Deploy Virtual Machines > [7] Host Storage Setup** to set up local storage.

### Phase 4: Join Cluster

1. Navigate to **Cluster Management > [2] Join Existing Cluster**.
2. Enter the cluster name.
3. The node is added and validated.

### Phase 5: Rebalance VMs

1. Use Failover Cluster Manager to live-migrate VMs back to the new node as appropriate.
2. Or set preferred owners on VM roles and use failback policies.

---

## Rollback: If Migration Fails

If a drain operation encounters issues:

### Individual VM Migration Fails

1. Check the VM event log in Failover Cluster Manager for the specific error.
2. Common resolutions:
   - **Incompatible processor:** Set VM processor compatibility mode (`Set-VMProcessor -CompatibilityForMigrationEnabled $true`).
   - **VHD on local storage:** Move VHD to CSV first, then retry migration.
   - **Insufficient memory on target:** Stop non-critical VMs or add memory.

### Cancel the Drain

If the drain is taking too long or causing issues:

```powershell
# Resume the node to cancel the drain
Resume-ClusterNode -Name "NodeName" -Failback NoFailback
```

VMs that already migrated will stay on their new nodes. VMs still on the original node will remain there.

### Emergency: Node Went Down During Drain

If the node crashes or loses power during a drain:
1. The cluster automatically fails over running VMs to other nodes.
2. VMs that were mid-migration may restart on the target node (brief downtime).
3. After the node is back, it will rejoin the cluster in a paused state.
4. Resume the node once it is healthy.
