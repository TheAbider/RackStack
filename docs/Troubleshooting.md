# Troubleshooting Guide

Common issues encountered during server configuration with RackStack, organized by category. Each section lists symptoms, likely causes, and resolution steps.

---

## Table of Contents

- [VM Deployment Failures](#vm-deployment-failures)
- [iSCSI / SAN Connectivity](#iscsi--san-connectivity)
- [MPIO Issues](#mpio-issues)
- [Storage Backends](#storage-backends)
- [Cluster Problems](#cluster-problems)
- [Server Role Templates](#server-role-templates)
- [AD DS Promotion](#ad-ds-promotion)
- [Hyper-V Replica](#hyper-v-replica)
- [NIC Auto-Select for SET and iSCSI](#nic-auto-select-for-set-and-iscsi)
- [Common Errors](#common-errors)
- [Network Diagnostics Walkthrough](#network-diagnostics-walkthrough)

---

## VM Deployment Failures

### VHD Copy Fails

**Symptom:** "Failed to prepare OS VHD" or copy operation times out during batch deployment.

**Causes:**
- Insufficient disk space on the target volume.
- Sysprepped base VHD was not downloaded or is corrupted.
- Network interruption when copying to a remote host.

**Resolution:**
1. Check disk space via **Deploy Virtual Machines > [7] Host Storage Setup**.
2. Re-download the base VHD via **[5] Download / Manage Sysprepped VHDs**.
3. RackStack automatically falls back to blank disk creation if the VHD copy fails. You can then attach an ISO manually.

### VM Creation Fails ("Failed to create VM")

**Symptom:** Error during `New-VM` call, VM shell is not created.

**Causes:**
- Hyper-V role is not installed or not functional (reboot pending).
- Target storage path does not exist or is not writable.
- VM name already exists on the host or cluster.

**Resolution:**
1. Verify Hyper-V is installed: **Server Config > Hyper-V Installation**.
2. Run **Host Storage Setup** to initialize folder structure on your data drive.
3. RackStack checks for duplicate VM names and DNS conflicts before deployment. If a duplicate is found, choose a different name or remove the conflicting VM.

### Network Adapter Attach Fails

**Symptom:** VM is created but network connectivity is missing. NIC shows "(Not Connected)".

**Causes:**
- No virtual switch exists on the host.
- The specified virtual switch name does not match an existing switch.
- VLAN configuration mismatch.

**Resolution:**
1. During NIC configuration, RackStack lists available virtual switches. If none exist, it offers to create a SET (Switch Embedded Teaming) switch.
2. If a switch was recently created, a reboot may be required before it becomes functional.
3. Check VLAN IDs match your physical switch port configuration.

### Insufficient Storage ("INSUFFICIENT DISK SPACE")

**Symptom:** Batch deployment shows insufficient disk space warning before starting.

**Causes:**
- Total VHD sizes across all queued VMs exceed available free space (with 10% buffer).
- Storage path points to the wrong drive or a drive that is nearly full.

**Resolution:**
1. The deployment queue screen shows total disk space required for all queued VMs.
2. Use **[7] Host Storage Setup** to select a different data drive.
3. Remove VMs from the queue that are not immediately needed.
4. RackStack checks free space before deploying and calculates a 10% buffer. You can override the warning, but the deployment may fail mid-way.

### Partial VM Creation

**Symptom:** Error occurs after VM shell is created but before all configuration is applied.

**Causes:**
- Disk creation succeeded but NIC attachment or integration services configuration failed.
- Remote host lost connectivity during deployment.

**Resolution:**
1. Check Hyper-V Manager for the partially created VM.
2. You can manually complete the configuration or delete the VM and retry.
3. RackStack logs changes via the session change tracker. Review changes at the end of the session.

---

## iSCSI / SAN Connectivity

> **Note:** As of v1.3.0, iSCSI is one of six supported storage backends. If you are using a different backend (FC, S2D, SMB3, NVMeoF, or Local), see [Storage Backends](#storage-backends) below.

### SAN Targets Not Found

**Symptom:** "No SAN targets responded" during SAN target discovery, or "No fully reachable SAN target pair found" during auto-detect.

**Causes:**
- iSCSI NICs are not configured or have wrong IP addresses.
- Physical cables are not connected to the correct switch ports.
- SAN appliance is offline or not yet configured.

**Resolution:**
1. Navigate to **iSCSI & SAN Management > [1] Configure iSCSI NICs**.
2. Use auto-configuration (recommended) which detects host number from the hostname (e.g., `123456-HV2` = Host #2) and calculates IPs using the formula: `{subnet}.{(host# + 1) * 10 + port#}` (default subnet: `172.16.1`, configurable via `defaults.json`).
3. Use **[2] Identify NICs** to temporarily disable a NIC and watch which switch port light goes out to confirm physical cabling.
4. Use **[3] Discover SAN Targets** to ping-test all known SAN target IPs.

### Auto-Detection: Host Number Not Detected

**Symptom:** "Could not detect host number from hostname" during iSCSI auto-configuration.

**Causes:**
- Hostname does not follow the expected pattern: `XXXXXX-HV#` (e.g., `123456-HV1`).

**Resolution:**
1. Enter the host number manually when prompted (valid range: 1-24).
2. The formula for IP assignment is: Port 1 (A-side) = `subnet.{(host#+1)*10 + 1}`, Port 2 (B-side) = `subnet.{(host#+1)*10 + 2}`.

### Multipath Not Working

**Symptom:** iSCSI disks show single path instead of dual path. Only one path appears in MPIO status.

**Causes:**
- Only one iSCSI NIC is configured (partial configuration).
- MPIO feature is not installed or not configured for iSCSI.
- iSCSI targets were connected without `-IsMultipathEnabled $true`.

**Resolution:**
1. Verify both NICs are configured: **iSCSI & SAN Management > [6] Show iSCSI/MPIO Status**.
2. Check MPIO status in the same screen. If MPIO shows "Not Installed", install it via **[5] Configure MPIO Multipath**.
3. MPIO requires a reboot after initial installation. After reboot, return to **[5] Configure MPIO Multipath** to enable iSCSI automatic claim and set the Round Robin load balance policy.
4. Disconnect and reconnect iSCSI targets after MPIO is configured.

### Partial iSCSI Configuration

**Symptom:** "Warning: Partial configuration" message. One adapter configured successfully, the other failed.

**Causes:**
- IP address conflict on the iSCSI network.
- One physical NIC is down or disconnected.

**Resolution:**
1. Check adapter status in the NIC selection screen. Down adapters are marked `[DOWN]`.
2. Verify physical cable connections.
3. Re-run **[1] Configure iSCSI NICs** to retry the failed adapter.

### SAN Target Retry Order

When auto-detecting SAN targets, RackStack tries target pairs in a specific retry order based on host number:

| Host # | Primary Pair | Retry 1 | Retry 2 | Retry 3 |
|--------|-------------|---------|---------|---------|
| 1 (HV1) | A0/B1 | A2/B3 | A1/B0 | A3/B2 |
| 2 (HV2) | A1/B0 | A3/B2 | A0/B1 | A2/B3 |
| 3 (HV3) | A2/B3 | A0/B1 | A3/B2 | A1/B0 |
| 4 (HV4) | A3/B2 | A1/B0 | A2/B3 | A0/B1 |

Hosts 5-24 cycle through the same pattern (host 5 = same as host 1, etc.).

---

## MPIO Issues

### MPIO Not Installed

**Symptom:** "MPIO (Multipath I/O) is not installed" message when trying to configure multipath.

**Resolution:**
1. Navigate to **iSCSI & SAN Management > [5] Configure MPIO Multipath**.
2. Select `[I] Install MPIO now`.
3. MPIO installation requires a reboot. After reboot, return to configure MPIO for iSCSI.

### MPIO Installation Timed Out

**Symptom:** "MPIO installation timed out" message.

**Causes:**
- Windows Update is running concurrently.
- Server has pending restarts from previous feature installations.

**Resolution:**
1. Reboot the server and retry.
2. Check Windows Update status and wait for any pending updates to complete.

### No Hardware Registered in MPIO

**Symptom:** MPIO status shows "No hardware registered yet."

**Causes:**
- No iSCSI targets have been connected since MPIO was installed.

**Resolution:**
1. This is normal immediately after MPIO installation.
2. Connect to iSCSI targets via **[4] Connect to iSCSI Targets**. Hardware will auto-detect when iSCSI connections are established.

---

## Storage Backends

> See [Storage Backends](Storage-Backends) for full documentation on all six backends.

### Auto-Detect Mismatch

**Symptom:** "Mismatch warning" -- the detected backend differs from the configured backend.

**Causes:**
- The configured backend (e.g., iSCSI) does not match the actual storage in use (e.g., FC).
- Storage was reconfigured outside of RackStack.

**Resolution:**
1. Navigate to **Storage & SAN > `[3]` Detect Storage Backend** to re-run detection.
2. Accept the detected backend or manually change via **`[0]` Change Storage Backend**.
3. The detection order is: iSCSI → S2D → FC → SMB3 → NVMeoF → Local.

### FC HBAs Not Found

**Symptom:** "No Fibre Channel HBA ports found" when selecting the FC backend.

**Causes:**
- Fibre Channel HBA drivers are not installed.
- HBAs are not physically present in the server.
- HBAs are present but not recognized by Windows.

**Resolution:**
1. Verify HBA hardware is installed and seated properly.
2. Install the vendor's HBA driver package (e.g., Emulex, QLogic/Marvell).
3. Check Device Manager for unknown or error-state FC devices.
4. After driver installation, use **Storage & SAN > FC > `[2]` Rescan FC Storage**.

### S2D Enable Fails

**Symptom:** "Enable Storage Spaces Direct" fails or shows prerequisite errors.

**Causes:**
- No active Failover Cluster exists on this server.
- Fewer than 2 eligible physical disks available across cluster nodes.
- S2D is already enabled on the cluster.

**Resolution:**
1. Create a Failover Cluster first via **Cluster Management > `[1]` Create New Cluster**.
2. Ensure each node has local disks available for the S2D pool (not already partitioned or in use).
3. Check S2D status via **Storage & SAN > S2D > `[3]` Show S2D Status**.

### SMB3 Share Access Denied

**Symptom:** "Test SMB Share Path" fails with access denied or path not found.

**Causes:**
- UNC path is incorrect or the file server is offline.
- Share permissions do not allow the current user/computer access.
- Network firewall blocking SMB (TCP 445).

**Resolution:**
1. Verify the UNC path format: `\\server\sharename`.
2. Test from a different machine to confirm the share is accessible.
3. Check share and NTFS permissions on the file server.
4. Use **Network Diagnostics > `[2]` Port Test** on port 445 to verify SMB connectivity.

---

## Cluster Problems

### Cannot Create Cluster

**Symptom:** `New-Cluster` fails during cluster creation wizard.

**Causes:**
- Failover Clustering feature is not installed on all nodes.
- DNS resolution fails between nodes.
- Static IP address is invalid or already in use.
- Nodes do not share compatible storage.

**Resolution:**
1. Install Failover Clustering on all nodes via **Cluster Management > [I] Install Failover Clustering**.
2. Run **[V] Validate cluster configuration** before creating. The validation report identifies blocking issues.
3. Ensure all nodes can resolve each other by hostname.
4. Verify the cluster IP address is on the same subnet and not already assigned.

### Cannot Join Existing Cluster

**Symptom:** `Add-ClusterNode` fails when joining an existing cluster.

**Causes:**
- Server is already part of a different cluster.
- Insufficient permissions (need domain admin or cluster admin rights).
- Failover Clustering feature is not installed on this server.

**Resolution:**
1. Check current cluster membership in the **Cluster Management** screen. If already in a cluster, remove from it first.
2. Verify your domain account has cluster admin rights.
3. Install Failover Clustering if the prerequisite check shows it missing.

### Quorum Issues

**Symptom:** Cluster goes offline after losing a node, or cluster shows degraded state.

**Causes:**
- Quorum configuration does not match the number of nodes.
- Disk witness or file share witness is unreachable.
- Cloud witness (Azure) credentials are expired.

**Resolution:**
1. Navigate to **Cluster Management > [6] Configure Quorum/Witness**.
2. For 2-node clusters, always configure a witness (file share or cloud).
3. Available quorum types:
   - **Node Majority** - No witness, suitable for 3+ odd-numbered node clusters.
   - **Node and Disk Majority** - Uses a shared disk as witness.
   - **Node and File Share Majority** - Uses a network file share (e.g., `\\server\witness`).
   - **Cloud Witness** - Uses an Azure Storage Account.

### CSV Not Mounting

**Symptom:** Cluster Shared Volume shows as offline or does not appear.

**Causes:**
- Underlying disk is not online or not formatted.
- Disk is not added as a cluster resource.
- MPIO/iSCSI session dropped, disk is no longer accessible.

**Resolution:**
1. Check available cluster disks via **Cluster Management > [4] Manage CSVs > [3] Show Available Cluster Disks**.
2. Verify iSCSI sessions are active via **iSCSI & SAN Management > [6] Show iSCSI/MPIO Status**.
3. If the disk shows as a cluster resource but is not in CSV, add it via **[1] Add Disk to CSV**.
4. If the disk shows as offline, check the underlying iSCSI connection and MPIO paths.

### Live Migration Fails

**Symptom:** VMs fail to migrate between cluster nodes.

**Causes:**
- Live Migration is not enabled.
- Authentication type mismatch (CredSSP vs. Kerberos).
- Network not configured for migration traffic.
- Incompatible processor features between nodes.

**Resolution:**
1. Navigate to **Cluster Management > [5] Configure Live Migration**.
2. Verify Live Migration is enabled (`[1] Enable Live Migration`).
3. For domain environments, use Kerberos authentication.
4. Set simultaneous migration count appropriate for your network bandwidth.
5. Configure allowed networks to restrict migration traffic to specific subnets.

---

## Server Role Templates

> See [Server Role Templates](Server-Role-Templates) for full documentation.

### Feature Install Fails

**Symptom:** "Failed to install feature" or `Install-WindowsFeature` returns an error during template installation.

**Causes:**
- Windows Update is running concurrently, locking the component store.
- A pending reboot from a previous feature installation is blocking new installations.
- The feature is not available on this Windows Server edition (e.g., Server Core missing GUI features).

**Resolution:**
1. Reboot the server and retry the template installation.
2. Check for pending Windows Updates and complete them first.
3. Verify the feature is available: run `Get-WindowsFeature <FeatureName>` to check availability.
4. RackStack installs features incrementally -- already-installed features are skipped, so you can safely retry after a partial failure.

### ServerOnly Template on Client OS

**Symptom:** "This template requires Windows Server" error when attempting to install a role template.

**Causes:**
- All 10 built-in templates have `ServerOnly: true` and require Windows Server.
- Running RackStack on Windows 10/11 for testing.

**Resolution:**
1. Role templates are designed for Windows Server deployments. They cannot be installed on client operating systems.
2. To test template functionality on a client, create a custom template in `defaults.json` with `ServerOnly: false` and client-compatible features.

---

## AD DS Promotion

> See [AD DS Promotion](AD-DS-Promotion) for full documentation.

### Static IP Required

**Symptom:** "Static IP address not configured" prerequisite check fails.

**Causes:**
- The server's IP address is assigned via DHCP.
- Domain Controllers require a static IP for DNS reliability.

**Resolution:**
1. Configure a static IP before running the promotion wizard.
2. In RackStack: **Server Config > Network Configuration** or batch mode with `IPAddress` and `Gateway`.
3. After setting a static IP, re-run the promotion wizard.

### Server Is Already a DC

**Symptom:** "Server is already a Domain Controller" prerequisite check fails.

**Causes:**
- The promotion wizard has already been run successfully on this server.
- The server was promoted outside of RackStack.

**Resolution:**
1. If you want to check the current DC status, use **System Configuration > `[3]` > `[4]` Check AD DS Status**.
2. To demote a DC, use Server Manager or `Uninstall-ADDSDomainController` in PowerShell.

### DSRM Password Rejected

**Symptom:** DSRM password entry fails validation or the passwords do not match.

**Causes:**
- Password is shorter than 8 characters.
- The confirmation entry does not match the first entry.

**Resolution:**
1. Enter a password with at least 8 characters.
2. Carefully re-enter the same password when prompted for confirmation.
3. DSRM passwords are entered as secure/masked input -- ensure Caps Lock is not accidentally enabled.

### Domain Name Validation Fails

**Symptom:** "Invalid domain name" error when entering the forest/domain FQDN.

**Causes:**
- The name does not contain a dot (e.g., `contoso` instead of `contoso.com`).
- The name contains invalid characters (spaces, underscores, etc.).
- A label starts or ends with a hyphen.

**Resolution:**
1. Use a fully qualified domain name with at least two labels (e.g., `corp.contoso.com`).
2. Each label must start and end with an alphanumeric character.
3. Only letters, numbers, and hyphens are allowed (hyphens only in the middle of labels).

---

## Hyper-V Replica

> See [Hyper-V Replica](Hyper-V-Replica) for full documentation.

### Connection Test Failed

**Symptom:** `Test-VMReplicationConnection` fails when setting up VM replication.

**Causes:**
- The replica server is not configured to accept incoming replication.
- Authentication type mismatch (Kerberos on one side, Certificate on the other).
- Firewall blocking the replication port (HTTP 80 for Kerberos, HTTPS 443 for Certificate).
- Replica server is unreachable (DNS or network issue).

**Resolution:**
1. Ensure the replica server has been configured via **Hyper-V Replica > `[1]` Enable Replica Server**.
2. Verify both servers use the same authentication type.
3. Check firewall rules on the replica server (RackStack configures these automatically during setup).
4. Test basic connectivity with **Network Diagnostics > `[1]` Ping Host** and **`[2]` Port Test** on port 80 or 443.

### Critical Replication Health

**Symptom:** Replication Status Dashboard shows red/Critical health for a VM.

**Causes:**
- Network connectivity between primary and replica servers has been lost.
- The replica server is offline or overloaded.
- Replication has been suspended or broken for an extended period.

**Resolution:**
1. Check network connectivity between the two hosts.
2. Verify the replica server is running and has sufficient disk space.
3. Check the detailed replication statistics in the dashboard for specific error messages.
4. If replication is severely out of sync, consider removing and re-enabling replication with a fresh initial copy.

### Test Failover VM Stuck

**Symptom:** A test failover VM remains running and cannot be cleaned up normally.

**Causes:**
- The test failover was not cleaned up properly.
- The `Stop-VMFailover` command was not run after testing.

**Resolution:**
1. Run `Stop-VMFailover -VMName '<vmname>'` in PowerShell to clean up the test VM.
2. If the test VM is still running, stop it first (`Stop-VM -VMName '<vmname>' -Force`), then run `Stop-VMFailover`.
3. After cleanup, the test failover option becomes available again for that VM.

### Planned Failover Requires Shutdown

**Symptom:** "VM must be shut down for planned failover" error.

**Causes:**
- Planned failover requires the VM to be in an Off state to ensure zero data loss.
- The VM is currently running on the primary server.

**Resolution:**
1. RackStack offers to shut down the VM automatically when this is detected.
2. Accept the automatic shutdown, or manually shut down the VM first.
3. After shutdown, retry the planned failover.
4. For minimal downtime, use Live Migration (for cluster scenarios) or schedule the planned failover during a maintenance window.

---

## NIC Auto-Select for SET and iSCSI

When setting up a Hyper-V host, you typically have 4+ physical NICs: some connected to the management/production network (with DHCP) and others connected to the iSCSI/SAN network (a separate VLAN without DHCP). RackStack's auto-detect feature identifies which NICs are which so you don't have to figure it out manually.

### How Auto-Detect Works

**Menu path:** Server Config > NIC Configuration > Switch Embedded Teaming > Auto-detect (Recommended)

1. RackStack enumerates all physical NICs that are link-UP (excludes virtual adapters).
2. For each NIC, it checks whether the adapter has an IP address (from DHCP) and can ping an external target (8.8.8.8 by default).
3. **NICs with internet connectivity** (DHCP gave them an IP, ping succeeds) are selected for the SET team. These are your management/production NICs.
4. **NICs without internet** (no IP from DHCP because they're on the iSCSI VLAN) are stored as iSCSI candidates and offered later during iSCSI NIC configuration.

### Typical 4-NIC Server Layout

| NIC | Network | DHCP | Internet | Auto-Detect Result |
|-----|---------|------|----------|--------------------|
| Port 1 | Management VLAN | Yes (e.g., 10.0.1.50) | Yes | **SET member** |
| Port 2 | Management VLAN | Yes (e.g., 10.0.1.51) | Yes | **SET member** |
| Port 3 | iSCSI VLAN | No IP assigned | No | **iSCSI candidate** |
| Port 4 | iSCSI VLAN | No IP assigned | No | **iSCSI candidate** |

### Why This Works

On a freshly installed server connected to a properly configured network:
- The management/production switch ports have a DHCP scope, so those NICs get IP addresses automatically.
- The iSCSI switch ports are on a separate VLAN (e.g., VLAN 16) that has no DHCP scope -- those NICs stay unconfigured with no IP.
- RackStack uses this difference to cleanly separate the two groups.

### When Auto-Detect Fails

**All NICs show "No Internet":**
- DHCP is not available on the management network, or the server hasn't obtained a lease yet.
- Fix: Wait a moment for DHCP, or manually assign an IP to one NIC first, then re-run auto-detect.
- Alternatively, use Manual selection to pick SET members by name/MAC.

**All NICs show "Has Internet":**
- All NICs are on the same VLAN (iSCSI NICs are not yet connected to their dedicated switch ports).
- Fix: Verify cabling -- iSCSI NICs should be connected to iSCSI-only switch ports.
- Use **Identify NICs** (blink/disable) to confirm which physical port corresponds to which NIC in Windows.

**Wrong NICs selected:**
- If auto-detect picks the wrong NICs, decline the selection and choose Manual mode.
- Use **Show Adapters** to view MAC addresses, link speed, and status to help identify NICs.

### iSCSI NIC Configuration After SET

After SET is created, navigate to **iSCSI & SAN Management > [1] Configure iSCSI NICs**:
1. RackStack automatically offers the previously identified iSCSI candidate NICs.
2. Select which NIC connects to the SAN A-side controller and which connects to B-side.
3. Use **[2] Identify NICs** to temporarily disable a NIC and watch which switch port light goes out -- this confirms physical cabling before you assign IPs.
4. Static IPs are calculated from the hostname (e.g., `123456-HV2` = Host #2 -> Port 1 gets `{subnet}.31`, Port 2 gets `{subnet}.32`, where subnet defaults to `172.16.1`).

---

## Common Errors

### Elevation Required

**Symptom:** Operations fail with "Access Denied" or permission errors.

**Resolution:**
1. Right-click the RackStack executable and select "Run as administrator."
2. For domain operations (cluster, remote deployment), ensure your domain account has appropriate permissions.

### WMF 5.1 Missing

**Symptom:** PowerShell cmdlets are not recognized, or module import fails on older servers.

**Resolution:**
1. RackStack detects the OS version at startup and checks for WMF 5.1 compatibility.
2. Download and install WMF 5.1 from Microsoft on Server 2012 R2 systems.

### WinRM Failures (Remote Hosts)

**Symptom:** Cannot connect to remote Hyper-V host or cluster node. Errors mention WinRM or PowerShell Remoting.

**Causes:**
- WinRM service is not running on the remote host.
- Firewall blocking WinRM ports (TCP 5985/5986).
- TrustedHosts not configured for workgroup environments.

**Resolution:**
1. On the remote host, run: `Enable-PSRemoting -Force`.
2. Verify WinRM port is open using **Network Diagnostics > [2] Port Test** targeting port 5985.
3. For workgroup environments, add the remote host to TrustedHosts.

### Feature Installation Timeouts

**Symptom:** "Installation timed out" during MPIO, Failover Clustering, or Hyper-V installation.

**Causes:**
- Windows Update running concurrently.
- Pending reboot from a previous installation.
- Server resources are constrained.

**Resolution:**
1. Reboot the server and retry the installation.
2. Check for pending Windows Updates and complete them first.
3. RackStack uses `Install-WindowsFeatureWithTimeout` which provides a timeout mechanism. If the installation genuinely takes too long, it may need to be completed manually via Server Manager.

---

## Network Diagnostics Walkthrough

RackStack includes a built-in network diagnostics suite accessible from the main menu. These tools help troubleshoot connectivity issues without leaving the RackStack interface.

**Menu path:** Server Config > Network Diagnostics

### Available Tools

| Tool | Menu Option | Use Case |
|------|-------------|----------|
| **Ping Host** | `[1]` | Basic connectivity test (4 pings with latency stats) |
| **Port Test (TCP)** | `[2]` | Verify a specific TCP port is open (e.g., 3389 for RDP, 3260 for iSCSI, 5985 for WinRM) |
| **Trace Route** | `[3]` | Map the network path to a destination with DNS resolution at each hop |
| **Subnet Ping Sweep** | `[4]` | Discover all live hosts on a subnet (parallel ping jobs for speed) |
| **DNS Lookup** | `[5]` | Resolve hostnames to IPs or reverse-lookup IPs to hostnames (A, AAAA, CNAME, MX, PTR records) |
| **Active Connections** | `[6]` | Show established TCP connections with remote addresses and owning processes (top 40) |
| **ARP Table** | `[7]` | View the local ARP cache with MAC addresses, state, and interface mapping |

### Common Diagnostic Scenarios

**"Can I reach the SAN?"**
1. Use **[1] Ping Host** to test each SAN target IP (e.g., `{subnet}.10`, `{subnet}.11` where subnet defaults to `172.16.1`).
2. Use **[2] Port Test** on port 3260 (iSCSI) to verify the iSCSI service is responding.
3. Use **[4] Subnet Ping Sweep** on your iSCSI subnet to find all reachable devices.

**"Is my VM reachable?"**
1. Use **[5] DNS Lookup** to verify the VM name resolves to the expected IP.
2. Use **[1] Ping Host** to test connectivity.
3. Use **[2] Port Test** on the relevant service port (e.g., 445 for file shares, 3389 for RDP).

**"What's connected to this server?"**
1. Use **[6] Active Connections** to see all established TCP connections.
2. Use **[7] ARP Table** to see devices that have recently communicated on the local network.

**"Where is the network bottleneck?"**
1. Use **[3] Trace Route** to map the path. High latency at a specific hop indicates where the bottleneck is.

### Subnet Ping Sweep Details

The sweep tool uses parallel background jobs for speed:
- Auto-detects the local subnet from the primary network adapter.
- Default range: .1 through .254.
- Custom start/end octets can be specified.
- Results show IP, reverse DNS hostname (if available), and total hosts alive.
- 30-second timeout for the entire sweep.
