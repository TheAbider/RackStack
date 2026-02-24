# Hyper-V Replica

RackStack provides an interactive management interface for Hyper-V Replica, enabling asynchronous VM replication between Hyper-V hosts for disaster recovery. Configure replica servers, enable replication for individual VMs, monitor replication health, and perform failover operations -- all from within the RackStack console.

> **New in v1.4.0:** Hyper-V Replica management with replication wizards, status dashboard, and failover operations.

---

## Table of Contents

- [Overview](#overview)
- [Enable Replica Server](#enable-replica-server)
- [Enable VM Replication](#enable-vm-replication)
- [Replication Status Dashboard](#replication-status-dashboard)
- [Test Failover](#test-failover)
- [Planned Failover](#planned-failover)
- [Reverse Replication](#reverse-replication)
- [Remove Replication](#remove-replication)

---

## Overview

**Menu path:** Storage & Clustering > `[6]` Hyper-V Replica

The Hyper-V Replica menu is organized into two groups with seven options:

```
  HYPER-V REPLICA
  ──────────────────────────────────────────

  REPLICA SERVER
  [1]  Enable Replica Server
  [2]  Replication Status Dashboard

  VM REPLICATION
  [3]  Enable Replication for VM
  [4]  Test Failover
  [5]  Planned Failover
  [6]  Reverse Replication
  [7]  Remove Replication

  [B]  Back
```

### How Hyper-V Replica Works

- A **primary server** hosts the production VM
- A **replica server** receives and stores replicated VM data
- Changes on the primary are replicated asynchronously at configurable intervals
- If the primary fails, the replica can be brought online (failover)
- Replication direction can be reversed after failover

---

## Enable Replica Server

Configures the current host to accept incoming replication from other Hyper-V hosts.

### Authentication Types

| Type | Protocol | Port | Use Case |
|------|----------|:----:|----------|
| **Kerberos** | HTTP | 80 | Domain-joined hosts in the same or trusted domains |
| **Certificate** | HTTPS | 443 | Workgroup hosts, untrusted domains, or cross-domain scenarios |

### Wizard Walkthrough

1. **Choose authentication type**
   - Kerberos (recommended for domain environments)
   - Certificate-based (for non-domain or cross-domain setups)

2. **Configure allowed servers**
   - **Any authenticated server** -- accepts replication from any host that can authenticate
   - **Specific servers only** -- restrict to a list of primary server hostnames

3. **Set storage path**
   - Directory where replicated VM files are stored on this host
   - Should have sufficient disk space for all replicated VMs

4. **Firewall rules**
   - RackStack automatically configures Windows Firewall rules for the selected authentication type
   - HTTP (port 80) for Kerberos, HTTPS (port 443) for certificate-based

5. **Apply**
   - Runs `Set-VMReplicationServer` with the selected authentication and authorization settings
   - The host is now ready to receive replicas

---

## Enable VM Replication

Enables replication for a specific VM on the primary server to a remote replica server.

### Wizard Walkthrough

1. **Select VM**
   - Lists all VMs on the host with their current state and replication status
   - VMs already configured for replication are marked

2. **Replication check**
   - If the VM already has replication configured, the wizard warns and exits
   - Remove existing replication first if you want to reconfigure

3. **Replica server**
   - Enter the hostname or IP address of the target replica server

4. **Authentication type**
   - Kerberos or Certificate (must match the replica server's configuration)

5. **Connection test**
   - Runs `Test-VMReplicationConnection` to verify the replica server is reachable and configured
   - Displays success or failure with error details

6. **Replication frequency**

   | Frequency | Description |
   |-----------|-------------|
   | **30 seconds** | Lowest latency, highest bandwidth usage |
   | **5 minutes** | Balanced (default) |
   | **15 minutes** | Lowest bandwidth, higher RPO |

7. **Initial replication method**

   | Method | Description |
   |--------|-------------|
   | **Send over network** | Transfers the initial copy directly over the network (default) |
   | **Send using external media** | Exports VM to external storage for physical transport |
   | **Use existing VM on replica server** | Uses a pre-staged VM already present on the replica (e.g., from a backup restore) |

8. **Confirmation**
   - Review all settings: VM name, replica server, auth type, frequency, initial method
   - Confirm to begin

9. **Execute**
   - Runs `Enable-VMReplication` with the selected parameters
   - Starts initial replication using the chosen method via `Start-VMInitialReplication`
   - Replication status can be monitored from the dashboard

---

## Replication Status Dashboard

Provides a real-time view of all replicated VMs and their replication health.

### VM Replication Table

| Column | Description |
|--------|-------------|
| VM Name | Name of the replicated virtual machine |
| State | Current VM power state (Running, Off, etc.) |
| Health | Replication health indicator (Normal, Warning, Critical) |
| Mode | Primary or Replica |
| Last Sync | Timestamp of the last successful replication cycle |

### Health Color Coding

| Color | Health | Meaning |
|-------|--------|---------|
| Green | Normal | Replication is healthy, all cycles completing on schedule |
| Yellow | Warning | Replication is delayed or experiencing intermittent issues |
| Red | Critical | Replication has failed or is significantly behind schedule |

### Detailed Statistics

For each replicated VM, additional metrics are available via `Measure-VMReplication`:
- Average replication size
- Replication frequency and last replication time
- Pending replication size
- Errors encountered

---

## Test Failover

Performs a non-destructive failover test by starting a copy of the replicated VM on the replica server. The production VM continues running on the primary server -- there is no impact to production.

### Workflow

1. **Select VM**
   - Lists all VMs configured for replication on this host

2. **Recovery point selection**
   - Displays available recovery points (snapshots) via `Get-VMReplicationCheckpoint`
   - Select which point-in-time to test

3. **Start test failover**
   - Creates a test VM from the selected recovery point
   - The test VM runs on an isolated network (no IP conflicts with production)

4. **Testing**
   - Verify the test VM boots and applications are functional
   - Perform any validation checks needed

5. **Cleanup**
   - RackStack offers to clean up the test VM immediately
   - Alternatively, leave it running for manual testing and clean up later
   - Cleanup command: `Stop-VMFailover -VMName '<vmname>'`

> **Important:** Always clean up test failover VMs when done. Leaving them running consumes resources and the test network isolation may not prevent all conflicts.

---

## Planned Failover

A controlled, zero-data-loss migration of a VM from the primary server to the replica server. Unlike an unplanned failover (disaster recovery), a planned failover ensures all pending changes are replicated before the switchover.

### Requirements

- The VM **must be shut down** before a planned failover
- Both primary and replica servers must be reachable
- Replication must be in a healthy state

### Workflow

1. **Select VM**
   - Lists replicated VMs on this host

2. **Shutdown check**
   - If the VM is running, RackStack offers to shut it down automatically
   - Planned failover cannot proceed on a running VM

3. **Execute (varies by server role)**

   **On the PRIMARY server:**
   - Prepares the VM for failover (final replication sync)
   - Displays instructions for the next step to run on the replica server

   **On the REPLICA server:**
   - Runs `Start-VMFailover` to begin the failover
   - Runs `Complete-VMFailover` to finalize
   - Starts the VM on the replica server
   - Offers to set up reverse replication (so the original primary becomes the new replica)

### After Planned Failover

- The VM is now running on the former replica server
- The original primary server holds the old copy
- Set up [Reverse Replication](#reverse-replication) to protect the VM in its new location

---

## Reverse Replication

After a failover (planned or unplanned), reverse replication switches the direction so the original primary server becomes the new replica target. This re-establishes protection for the VM in its new location.

### Workflow

1. **Select VM**
   - Lists VMs in failover states
   - If no VMs are in a failover state, all replicated VMs are shown

2. **Enter original primary server**
   - The hostname of the server that was the original primary (now becomes the new replica target)

3. **Execute**
   - Runs `Set-VMReplication -Reverse` to switch replication direction
   - The VM on the current host (former replica) becomes the new primary
   - Changes begin replicating to the original primary server

---

## Remove Replication

Permanently removes replication configuration from a VM. This stops all replication activity and removes replication metadata.

### Workflow

1. **Select VM**
   - Lists all replicated VMs with health status (color-coded)
   - Displays VM mode (Primary/Replica), state, and health

2. **Confirm removal**
   - This action is irreversible
   - The VM remains intact on both servers, but replication stops
   - To re-enable replication, run the Enable VM Replication wizard again

3. **Execute**
   - Runs `Remove-VMReplication` for the selected VM
   - Replication metadata is cleaned up on the local host

> **Note:** Run `Remove-VMReplication` on both the primary and replica servers to fully clean up replication configuration on both sides.

---

See also: [Cluster Management](Cluster-Management) | [Storage Backends](Storage-Backends) | [Batch Mode](Batch-Mode) | [Troubleshooting](Troubleshooting)
