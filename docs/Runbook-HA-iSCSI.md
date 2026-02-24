# Runbook: High-Availability iSCSI with Dual-Path MPIO

This runbook covers the end-to-end setup of dual-path iSCSI SAN connectivity with MPIO (Multipath I/O) for Hyper-V hosts, including integration with Failover Clustering.

> **Note:** As of v1.3.0, RackStack supports six storage backends: iSCSI, Fibre Channel, S2D, SMB3, NVMe-oF, and Local. This runbook covers the iSCSI backend specifically. For other backends, see [Storage Backends](Storage-Backends).

> **Note:** IP addresses, subnet (default `172.16.1`), and target mappings shown in this guide are defaults. Configure yours in `defaults.json` via `iSCSISubnet` and `SANTargetMappings`.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Step 1: Install MPIO Feature](#step-1-install-mpio-feature)
- [Step 2: Configure iSCSI NICs](#step-2-configure-iscsi-nics)
- [Step 2b: Test iSCSI Cabling](#step-2b-test-iscsi-cabling-v120)
- [Step 3: Verify SAN Target Connectivity](#step-3-verify-san-target-connectivity)
- [Step 4: Enable MPIO for iSCSI](#step-4-enable-mpio-for-iscsi)
- [Step 5: Connect to iSCSI Targets](#step-5-connect-to-iscsi-targets)
- [Step 6: Verify Multipath Connectivity](#step-6-verify-multipath-connectivity)
- [Step 7: Initialize Disks and Create Volumes](#step-7-initialize-disks-and-create-volumes)
- [Integration with Failover Clustering](#integration-with-failover-clustering)
- [Troubleshooting Path Failures](#troubleshooting-path-failures)
- [IP Address Reference](#ip-address-reference)
- [SAN Target Pair Assignments](#san-target-pair-assignments)

---

## Overview

A dual-path iSCSI configuration provides:
- **Redundancy:** If one path fails (NIC failure, cable disconnection, switch failure), the other path continues serving I/O.
- **Performance:** MPIO with Round Robin load balancing distributes I/O across both paths.
- **High Availability:** Required for Failover Clustering with shared storage.

Each Hyper-V host connects to the SAN via two dedicated iSCSI NICs, each on a separate physical path (A-side and B-side). MPIO manages both paths as a single logical connection.

---

## Architecture

```
                        +----------------+
                        |   SAN Array    |
                        |                |
                        |  A-side  B-side|
                        +---+--------+---+
                            |        |
                     +------+        +------+
                     |                      |
               +-----+-----+       +-------+---+
               | Switch A  |       | Switch B   |
               +-----+-----+       +-------+---+
                     |                      |
          +----------+----------------------+----------+
          |          |                      |          |
          |   +------+------+       +-------+-----+   |
          |   | iSCSI NIC 1 |       | iSCSI NIC 2 |   |
          |   | (A-side)    |       | (B-side)     |   |
          |   | Port 1      |       | Port 2       |   |
          |   +-------------+       +--------------+   |
          |                                            |
          |              Hyper-V Host                   |
          +--------------------------------------------+
```

Each host has:
- **iSCSI NIC 1 (A-side):** Connected to Switch A, assigned Port 1 IP.
- **iSCSI NIC 2 (B-side):** Connected to Switch B, assigned Port 2 IP.
- **MPIO:** Manages both paths, provides failover and load balancing.

---

## Prerequisites

- [ ] **Two dedicated physical NICs** for iSCSI traffic (not used for management or VM traffic).
- [ ] **Two separate physical switches** (A-side and B-side) connecting to SAN controllers.
- [ ] **SAN array configured** with iSCSI target portals and LUNs provisioned.
- [ ] **Windows Server** with Hyper-V role installed.
- [ ] **Correct physical cabling:** NIC 1 to Switch A, NIC 2 to Switch B.

---

## Step 1: Install MPIO Feature

**Menu path:** iSCSI & SAN Management > [6] Configure MPIO Multipath

If MPIO is not installed, the screen shows "PREREQUISITE MISSING" and offers to install.

1. Select `[I] Install MPIO now`.
2. RackStack runs `Install-WindowsFeature MultipathIO` with management tools.
3. A **reboot is required** after installation.
4. After reboot, return to this menu to configure MPIO for iSCSI.

**Important:** Do not connect to iSCSI targets before configuring MPIO. If you connect first, the connections will be single-path and you will need to disconnect and reconnect after MPIO is configured.

---

## Step 2: Configure iSCSI NICs

**Menu path:** iSCSI & SAN Management > [1] Configure iSCSI NICs

### Auto-Configuration (Recommended)

Select `[A] Auto-configure`:

1. **Host detection:** RackStack extracts the host number from the hostname (e.g., `123456-HV2` = Host #2). If detection fails, enter the host number manually (1-24).

2. **IP calculation:** IPs are computed using the formula:
   - Port 1 (A-side): `{subnet}.{(host# + 1) * 10 + 1}`
   - Port 2 (B-side): `{subnet}.{(host# + 1) * 10 + 2}`
   - Default subnet: `172.16.1` (configurable via `iSCSISubnet` in `defaults.json`)

   Examples:
   | Host | Port 1 (A-side) | Port 2 (B-side) |
   |------|----------------|----------------|
   | HV1 | 172.16.1.21 | 172.16.1.22 |
   | HV2 | 172.16.1.31 | 172.16.1.32 |
   | HV3 | 172.16.1.41 | 172.16.1.42 |
   | HV4 | 172.16.1.51 | 172.16.1.52 |

3. **Adapter selection:** RackStack lists available physical NICs (filtering out virtual, Hyper-V, and vEthernet adapters). If SET configuration was previously done, it uses the iSCSI candidate adapters identified during that process.
   - Select which adapter connects to the A-side switch.
   - Select which adapter connects to the B-side switch.
   - Cannot select the same adapter for both sides.

4. **Configuration summary:** Review A-side and B-side assignments with IPs. Confirm to apply.

5. **Apply:** For each adapter:
   - Removes existing IP addresses and routes.
   - Assigns the calculated static IP with /24 prefix.
   - Disables IPv6.
   - No default gateway (iSCSI is an isolated network).

6. **SAN connectivity test (optional):** After configuration, RackStack offers to ping-test known SAN target IPs.

### Manual Configuration

Select `[M] Manual configuration`:

1. RackStack lists available adapters (same filtering as auto-config).
2. Select adapters for iSCSI.
3. Enter IP address and subnet manually for each adapter (e.g., `10.0.0.100/24`).
4. Confirm and apply.

### NIC Identification Helper

**Menu path:** iSCSI & SAN Management > [2] Identify NICs

If you are unsure which physical NIC connects to which switch:

1. Select an adapter by number.
2. RackStack disables the adapter temporarily.
3. Watch your switch port LEDs. The port that goes dark corresponds to the disabled NIC.
4. Press Enter to re-enable the NIC.
5. Repeat for other adapters as needed.

---

## Step 2b: Test iSCSI Cabling (v1.2.0)

**Menu path:** iSCSI & SAN Management > [3] Test iSCSI Cabling (A/B side check)

Before connecting to SAN targets, you can verify that each physical NIC is cabled to the correct side:

1. RackStack temporarily assigns test IPs (`.253` / `.254`) to each iSCSI adapter.
2. Pings all known SAN targets from each adapter.
3. Determines which side each adapter can reach.

```
  Testing iSCSI adapter connectivity...

  Adapter              A-Side    B-Side    Result
  ──────────────────   ───────   ───────   ──────
  Ethernet 3           4/4       0/4       A-SIDE
  Ethernet 4           0/4       4/4       B-SIDE
```

**Warnings:**
- **Both adapters same side:** "Both adapters reach the same side. Check cabling -- they should be on different switches."
- **Adapter reaches both sides:** May indicate cross-connected switches or lack of iSCSI network isolation.
- **No connectivity:** Verify adapter is connected and iSCSI subnet is correct.

> **Auto-config integration:** When running auto-configure (Step 2), the cabling check runs automatically. If A/B sides are detected, RackStack offers to skip manual adapter selection.

---

## Step 3: Verify SAN Target Connectivity

**Menu path:** iSCSI & SAN Management > [4] Discover SAN Targets

This performs a ping test against all known SAN target IPs on the iSCSI subnet:

```
Testing 172.16.1.10 (A0)... OK
Testing 172.16.1.11 (B1)... OK
Testing 172.16.1.12 (B0)... OK
Testing 172.16.1.13 (A1)... NO RESPONSE
...
```

**Expected results:** At minimum, the A-side and B-side targets for your host's assigned pair should respond. See [SAN Target Pair Assignments](#san-target-pair-assignments) for which pair your host should use.

**If targets do not respond:**
- Verify iSCSI NIC configuration (Step 2).
- Check physical cable connections.
- Verify SAN is powered on and iSCSI target service is running.
- Use **Network Diagnostics > [2] Port Test** on port 3260 to test the iSCSI service specifically.

---

## Step 4: Enable MPIO for iSCSI

**Menu path:** iSCSI & SAN Management > [6] Configure MPIO Multipath

After MPIO is installed and the server has been rebooted:

1. RackStack verifies MPIO is installed.
2. Enables MPIO automatic claim for iSCSI bus type (`Enable-MSDSMAutomaticClaim -BusType iSCSI`).
3. Sets the global load balance policy to **Round Robin** (`Set-MSDSMGlobalDefaultLoadBalancePolicy -Policy RR`).
4. Displays supported hardware (may be empty until iSCSI targets are connected).

**Load balance policies available:**

| Policy | Abbreviation | Description |
|--------|-------------|-------------|
| Round Robin | RR | Distributes I/O evenly across paths (recommended) |
| Least Queue Depth | LQD | Sends I/O to the path with fewest outstanding requests |
| Failover Only | FOO | Uses one active path, others are standby |
| Least Blocks | LB | Sends I/O to the path with fewest pending blocks |
| Weighted Paths | WP | Uses administrator-assigned weights |

---

## Step 5: Connect to iSCSI Targets

**Menu path:** iSCSI & SAN Management > [5] Connect to iSCSI Targets

### Auto-Detect with Retry

If the host number is detected from hostname:

1. RackStack shows the SAN target priority order for your host (primary pair first, then fallback pairs).
2. Select `[A] Auto-detect`:
   - Pings A-side and B-side of the primary pair.
   - If both respond, offers to connect.
   - If not, tries the next pair in retry order (up to 4 attempts).
3. Confirm to connect.

### Use Primary Pair Without Testing

Select `[P]` to skip the ping test and connect directly to the primary pair.

### Manual Entry

Select `[M]` and enter target portal IPs as a comma-separated list.

### Connection Details

For each target portal:
1. Registers the target portal (if not already registered) on port 3260.
2. Discovers available targets.
3. Connects to each disconnected target with:
   - `-IsPersistent $true` (reconnects automatically after reboot).
   - `-IsMultipathEnabled $true` (enables MPIO for the connection).

---

## Step 6: Verify Multipath Connectivity

**Menu path:** iSCSI & SAN Management > [7] Show iSCSI/MPIO Status

The status screen shows four sections:

### iSCSI Sessions
Lists all active sessions with:
- Target IQN (iSCSI Qualified Name).
- Portal address and port.
- Persistent and connected status.

**Expected:** You should see sessions through both A-side and B-side portals.

### iSCSI Targets
Lists discovered targets with connected/disconnected status.

**Expected:** All targets should show `[CONNECTED]`.

### MPIO Status
- MPIO installed: should show `Installed`.
- Load Balance Policy: should show `Round Robin`.
- iSCSI Auto-Claim: should show `Enabled`.

### Disk Mappings
Lists all iSCSI disks with:
- Disk number.
- Friendly name.
- Size in GB.
- Operational status.

**Expected:** Each LUN from the SAN should appear as a disk. With MPIO, each LUN appears as a single disk (not duplicated) even though it is accessed via two paths.

### Verifying Dual Paths via PowerShell

To confirm both paths are active for a specific disk:

```powershell
# Show MPIO disk details
Get-MSDSMAutomaticClaimSettings
mpclaim -s -d  # Shows all multipath disks and their paths
```

Each MPIO disk should show two paths (one via each iSCSI portal).

---

## Step 7: Initialize Disks and Create Volumes

After iSCSI disks appear:

1. **Initialize disks:** Open Disk Management or use:
   ```powershell
   Initialize-Disk -Number <disk#> -PartitionStyle GPT
   ```

2. **Create partitions and format:**
   ```powershell
   New-Partition -DiskNumber <disk#> -UseMaximumSize -AssignDriveLetter
   Format-Volume -DriveLetter <letter> -FileSystem NTFS -AllocationUnitSize 65536
   ```

3. **For Failover Clustering:** Do not assign drive letters. Instead, add the disk to the cluster and then to CSV. See [Integration with Failover Clustering](#integration-with-failover-clustering).

---

## Integration with Failover Clustering

iSCSI/MPIO storage is the foundation for shared storage in Hyper-V failover clusters. All cluster nodes must connect to the same SAN LUNs via their own dual-path iSCSI connections.

### Setup Order for Clustered Hosts

Perform these steps on **each** cluster node:

1. Configure iSCSI NICs (Step 2).
2. Install and configure MPIO (Steps 1 and 4).
3. Connect to iSCSI targets (Step 5).
4. Verify multipath (Step 6).

Then, on **one** node:

5. Initialize the iSCSI disks.
6. Create the cluster (**Cluster Management > [1] Create New Cluster**).
7. Add iSCSI disks as cluster resources.
8. Add disks to CSV (**Cluster Management > [4] Manage CSVs > [1] Add Disk to CSV**).

### Adding Disks to Cluster Shared Volumes

**Menu path:** Cluster Management > [4] Manage Cluster Shared Volumes

1. View current CSVs with state, free space, and total size.
2. Select `[1] Add Disk to CSV`.
3. Choose from available cluster disks (physical disks not already in CSV).
4. The disk becomes available at `C:\ClusterStorage\Volume{N}\` on all nodes.

### Quorum Disk

If using Node and Disk Majority quorum:
- One small iSCSI LUN (1 GB is sufficient) should be designated as the quorum witness disk.
- Do not add the quorum disk to CSV.
- Configure via **Cluster Management > [6] Configure Quorum/Witness > [2] Node and Disk Majority**.

### Live Migration with iSCSI CSV

When VMs are stored on CSV backed by iSCSI:
- Live Migration moves the VM memory and state between nodes.
- The VHD files remain on the CSV and are accessible from all nodes.
- No storage migration is needed, making migrations fast.

---

## Troubleshooting Path Failures

### One Path Down

**Symptom:** MPIO shows one path as failed. I/O continues on the remaining path.

**Diagnosis:**
1. Check iSCSI session status via **[7] Show iSCSI/MPIO Status**. One portal's session will show disconnected.
2. Ping the SAN target IP for the failed path:
   - **Network Diagnostics > [1] Ping Host** with the A-side or B-side SAN IP.
3. Check the physical NIC link state:
   - **[2] Identify NICs** will show which adapters are `[UP]` vs `[DOWN]`.

**Resolution:**
1. If NIC is DOWN: Check cable connection, switch port, NIC hardware.
2. If NIC is UP but ping fails: Verify IP configuration via **[1] Configure iSCSI NICs**.
3. If ping works but iSCSI session is down: The SAN target service may have restarted. Reconnect via **[5] Connect to iSCSI Targets**.
4. Because sessions are configured as persistent (`-IsPersistent $true`), they should auto-reconnect. If they do not, manually reconnect.

### Both Paths Down

**Symptom:** All iSCSI disks are inaccessible. VMs on iSCSI storage lose disk access.

**This is a critical event.** Investigate immediately:

1. Check if the SAN is powered on and accessible from any other host.
2. Verify both iSCSI NICs have link state UP.
3. Check switch connectivity (both A-side and B-side switches).
4. Use **Network Diagnostics > [4] Subnet Ping Sweep** on the iSCSI subnet to determine what is reachable.

### Path Flapping

**Symptom:** A path repeatedly goes down and comes back up.

**Causes:**
- Failing NIC or cable (intermittent connection).
- Switch port issue.
- SAN controller under heavy load.

**Resolution:**
1. Replace the suspect cable.
2. Try a different switch port.
3. Check SAN controller health and logs.
4. Monitor with `mpclaim -s -d` to watch path state changes.

### Disk Appears Twice (MPIO Not Working)

**Symptom:** Each SAN LUN shows as two separate disks in Disk Management.

**Causes:**
- MPIO is not installed or not configured for iSCSI.
- iSCSI targets were connected before MPIO was configured.

**Resolution:**
1. Disconnect all iSCSI targets via **[8] Disconnect iSCSI Targets > [A] Disconnect ALL**.
2. Configure MPIO via **[6] Configure MPIO Multipath**.
3. Reconnect to iSCSI targets via **[5] Connect to iSCSI Targets**.
4. Each LUN should now appear as a single disk with two paths.

---

## IP Address Reference

### Host iSCSI IPs

Formula: `{subnet}.{(host# + 1) * 10 + port#}`

| Host | Port 1 (A-side) | Port 2 (B-side) |
|------|----------------|----------------|
| HV1 | 172.16.1.21 | 172.16.1.22 |
| HV2 | 172.16.1.31 | 172.16.1.32 |
| HV3 | 172.16.1.41 | 172.16.1.42 |
| HV4 | 172.16.1.51 | 172.16.1.52 |
| HV5 | 172.16.1.61 | 172.16.1.62 |
| ... | ... | ... |
| HV24 | 172.16.1.251 | 172.16.1.252 |

### SAN Target IPs

| IP | Label | Controller |
|----|-------|-----------|
| 172.16.1.10 | A0 | A-side |
| 172.16.1.11 | B1 | B-side |
| 172.16.1.12 | B0 | B-side |
| 172.16.1.13 | A1 | A-side |
| 172.16.1.14 | A2 | A-side |
| 172.16.1.15 | B3 | B-side |
| 172.16.1.16 | B2 | B-side |
| 172.16.1.17 | A3 | A-side |

---

## SAN Target Pair Assignments

Each host connects to a specific A-side/B-side target pair based on its host number. The assignment cycles every 4 hosts:

| Host # (mod 4) | Primary Pair | A-side Target | B-side Target |
|----------------|-------------|---------------|---------------|
| 1 (HV1, HV5, HV9...) | A0/B1 | 172.16.1.10 | 172.16.1.11 |
| 2 (HV2, HV6, HV10...) | A1/B0 | 172.16.1.13 | 172.16.1.12 |
| 3 (HV3, HV7, HV11...) | A2/B3 | 172.16.1.14 | 172.16.1.15 |
| 4 (HV4, HV8, HV12...) | A3/B2 | 172.16.1.17 | 172.16.1.16 |

### Retry Order

If the primary pair is unreachable, RackStack tries alternate pairs:

| Primary | 1st Retry | 2nd Retry | 3rd Retry |
|---------|----------|----------|----------|
| A0/B1 | A2/B3 | A1/B0 | A3/B2 |
| A1/B0 | A3/B2 | A0/B1 | A2/B3 |
| A2/B3 | A0/B1 | A3/B2 | A1/B0 |
| A3/B2 | A1/B0 | A2/B3 | A0/B1 |

The retry pattern places the "opposite" pair second (primary + 2 mod 4), then fills in the remaining two pairs in order.

### Custom SAN Target Pairings (v1.5.0)

The default assignment table above can be fully customized via `SANTargetPairings` in `defaults.json`. This lets you:

- Define custom A/B pairs (different number of controller ports, different IP layouts)
- Override the host-to-pair assignments and retry order
- Change the cycle size (e.g., 2 pairs instead of 4)

Convention: **A side = even suffixes, B side = odd suffixes**. Each pair represents one port on each controller (Pair0 = A0/B0, Pair1 = A1/B1, etc.).

See [Configuration > SANTargetPairings](Configuration#santargetpairings-v150) for the full JSON schema.

---

See also: [Storage Backends](Storage-Backends) | [Storage Manager](Storage-Manager) | [Cluster Management](Cluster-Management) | [Troubleshooting](Troubleshooting)
