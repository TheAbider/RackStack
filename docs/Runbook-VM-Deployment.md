# Runbook: VM Deployment

This runbook covers the full multi-VM deployment workflow in RackStack, from prerequisites through post-deployment verification.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Deployment Overview](#deployment-overview)
- [Step 1: Connect to Deployment Target](#step-1-connect-to-deployment-target)
- [Step 2: Set Site Number](#step-2-set-site-number)
- [Step 3: Prepare Storage](#step-3-prepare-storage)
- [Step 4: Add VMs to Queue](#step-4-add-vms-to-queue)
- [Step 5: Review and Deploy](#step-5-review-and-deploy)
- [Step 6: Post-Deployment Verification](#step-6-post-deployment-verification)
- [Standard VM Templates](#standard-vm-templates)
- [Naming Conventions](#naming-conventions)
- [Storage Path Behavior](#storage-path-behavior)
- [Troubleshooting Deployment Issues](#troubleshooting-deployment-issues)

---

## Prerequisites

Before deploying VMs, verify the following:

- [ ] **Hyper-V installed and functional** on the target host (reboot completed if recently installed).
- [ ] **Host storage initialized** via Host Storage Setup (data drive selected, folder structure created).
- [ ] **Virtual switch exists** (SET or external switch configured). RackStack will prompt to create one if missing.
- [ ] **Sysprepped VHDs available** (optional) if using pre-installed OS images instead of blank disks.
- [ ] **Sufficient disk space** for all planned VMs. RackStack checks this with a 10% buffer before deploying.
- [ ] **Network connectivity** to remote hosts or cluster (if deploying remotely).

---

## Deployment Overview

RackStack uses a queue-based batch deployment model:

1. Connect to a deployment target (local host, remote host, or cluster).
2. Set the site number for VM naming.
3. Add one or more VMs to the deployment queue (from templates or custom).
4. Review the queue, edit configurations as needed.
5. Deploy all queued VMs in a single batch.

**Menu path:** Main Menu > Deploy Virtual Machines

---

## Step 1: Connect to Deployment Target

When entering the VM Deployment menu, you first select a deployment mode:

### Option 1: Standalone Host

Select `[1] Standalone Host`, then choose:
- **Local (this server):** Tests Hyper-V connectivity on localhost. Requires Hyper-V to be installed.
- **Remote server:** Enter hostname or IP. RackStack attempts connection with current credentials first, then offers alternate credentials if that fails.

### Option 2: Failover Cluster

Select `[2] Failover Cluster`. RackStack discovers available clusters:
- **Local cluster:** Detected if this server is already a cluster member.
- **AD-discovered clusters:** Found via Active Directory service principal name queries.
- **Manual entry:** Enter cluster name directly.

The connection screen displays cluster name, node list, and node count upon successful connection.

**Important:** Your domain account must be a local administrator on ALL cluster nodes to deploy and manage VMs.

### Changing Connection Later

Use **[8] Change Connection** from the VM Deployment menu to switch targets without leaving the deployment workflow.

---

## Step 2: Set Site Number

RackStack auto-detects the site number from the hostname of the connected target:
- Pattern: `XXXXXX-HV#` (e.g., `123456-HV1` extracts site number `123456`).
- For clusters, it reads the hostname of the first cluster node.

If auto-detection fails (non-standard hostname), you are prompted to enter the 6-digit site number manually. Numbers shorter than 6 digits are padded with leading zeros.

Use **[9] Change Site Number** to modify after initial setup.

---

## Step 3: Prepare Storage

Before adding VMs to the queue, ensure storage is ready:

### Host Storage Setup (Menu Option [7])

1. Scans for available data drives (NTFS, not C:, not optical, not under 20GB).
2. If D: is occupied by an optical/DVD drive, offers to reassign it to another letter.
3. Lets you select which drive to use for VM storage.
4. Creates the standard folder structure:
   - `{drive}:\Virtual Machines` - VM configuration files
   - `{drive}:\Virtual Machines\_BaseImages` - Cached sysprepped VHDs
   - `{drive}:\ISOs` - Server installation ISOs
5. Configures Hyper-V default paths to point to the selected drive.

### Sysprepped VHDs (Menu Option [5])

If you plan to use pre-installed OS images:
1. Download sysprepped VHDs for your target Windows Server versions (2019, 2022, 2025).
2. VHDs are cached in `_BaseImages` and reused across all VM deployments.
3. Each VM deployment copies the base VHD to the VM's own storage folder.

---

## Step 4: Add VMs to Queue

### From Standard Template (Menu Option [1])

1. Select a template from the list (see [Standard VM Templates](#standard-vm-templates)).
2. RackStack generates a VM name automatically: `{SiteNumber}-{Prefix}{NextAvailable}`.
   - Checks for existing VMs with the same name on the host/cluster.
   - Checks DNS for name conflicts.
   - Suggests the next available number (e.g., `123456-FS1`, or `123456-FS2` if FS1 exists).
3. Choose OS installation method:
   - **Sysprepped VHD:** Select OS version, RackStack will copy the cached base image. Faster deployment.
   - **Blank disk:** Creates empty VHDs. You install the OS manually from ISO later.
4. Review the configuration summary showing: VM name, OS type, generation, vCPU, memory, disks, NICs, integration services, secure boot settings.
5. Edit any settings (CPU, memory, disks, network, guest services, time sync, OS method).
6. Select `[C] ADD TO QUEUE`.

### Custom VM (Menu Option [2])

1. Enter a VM prefix (e.g., VM, APP, TEST).
2. Configure name, OS method, CPU, memory, disks, and NICs through guided prompts.
3. Custom VMs use defaults from `defaults.json` if configured (`CustomVMDefaults` section), otherwise: 4 vCPU, 8 GB dynamic memory, 100 GB fixed OS disk.
4. Review and add to queue.

### Editing Queued VMs

From the queue management screen (`[3] Manage / Deploy Queue`):
- View all queued VMs with summary (vCPU, RAM, disk, OS source).
- Select a VM number to edit its full configuration.
- Remove individual VMs from the queue.
- Clear the entire queue.

---

## Step 5: Review and Deploy

From the queue management screen, select **Deploy All**:

1. **Disk space check:** RackStack calculates total required disk space across all queued VMs (with 10% buffer) and checks free space on the target volume. You can override the warning but risk mid-deployment failure.

2. **VHD pre-download:** If any VMs use sysprepped VHDs, RackStack downloads all needed base images first. If a download fails, those VMs fall back to blank disk mode automatically.

3. **Final confirmation:** Confirm to begin deployment.

4. **Batch execution:** Each VM is created sequentially:
   - Create VM shell (Gen 2, no VHD).
   - Configure CPU count.
   - Configure memory (dynamic: 25% min, 50% startup, 100% max, 20% buffer; or static).
   - Create and attach VHDs (copy from sysprepped base or create blank).
   - Configure network adapters (remove default, add configured NICs with switch and VLAN).
   - Enable/disable integration services (Guest Service Interface, Time Synchronization).
   - Configure Secure Boot (MicrosoftWindows template for Windows, MicrosoftUEFICertificateAuthority for Linux).
   - Set automatic start/stop actions (StartIfRunning with 30s delay, ShutDown on stop).
   - Disable automatic checkpoints, set checkpoint type to Production.
   - Add VM notes with creation timestamp.
   - For cluster mode: add VM as a cluster virtual machine role.
   - For VHD-based: offer offline customization prompt.

5. **Summary:** Shows success/failure count. Queue is cleared after deployment completes.

---

## Step 6: Post-Deployment Verification

After deployment completes:

1. **View existing VMs** via menu option `[4]`. This shows all VMs with: name, state, CPU count, memory assigned, and uptime.

2. **For VHD-based VMs (pre-installed OS):**
   - Start the VM.
   - Complete Windows mini-setup / OOBE (sysprep out-of-box experience).
   - Configure networking inside the VM.
   - Join domain and install roles/features as needed.

3. **For blank-disk VMs:**
   - Attach installation media (ISO) via Hyper-V Manager.
   - Start the VM.
   - Install the operating system.
   - Configure networking inside the VM.

4. **For clustered VMs:**
   - Verify the VM appears as a cluster resource via **Cluster Management > [7] Show Cluster Status**.
   - Test Live Migration to confirm the VM can move between nodes.

---

## Standard VM Templates

RackStack ships with three generic built-in templates:

| # | Server Type | OS | vCPU | RAM | C: Drive | D: Drive | Notes |
|---|-------------|----|------|-----|----------|----------|-------|
| 1 | Domain Controller (DC) | Windows | 4 | 8 GB Dynamic | 100 GB Fixed | -- | TimeSyncWithHost disabled |
| 2 | File Server (FS) | Windows | 4 | 8 GB Dynamic | 100 GB Fixed | 200 GB Fixed | |
| 3 | Web Server (WEB) | Windows | 4 | 8 GB Dynamic | 100 GB Fixed | -- | IIS |

Add custom templates (SQL, APP, etc.) or override built-in specs via `CustomVMTemplates` in `defaults.json`. See [Configuration Guide](Configuration) for examples.

---

## Naming Conventions

VM names follow a configurable token-based pattern (default: `{Site}-{Prefix}{Seq}`). The pattern, site identifier, and detection regex are all configurable via `VMNaming` in `defaults.json`.

Examples:
- `123456-FS1` — numeric site ID, default pattern
- `CRV-DC-01` — alpha site ID, pattern `{Site}-{Prefix}-{Seq:00}`
- `ACME-WEB1` — static site ID `ACME`
- `FS1` — no site prefix, pattern `{Prefix}{Seq}`

RackStack auto-increments the sequence number by checking for existing VMs and DNS records, trying up to 99.

---

## Storage Path Behavior

### Standalone Host (Local)

VMs are stored under the Hyper-V default paths configured during Host Storage Setup:
- VM config: `{drive}:\Virtual Machines\{VMName}\`
- VHD files: `{drive}:\Virtual Machines\{VMName}\` (in a VM-specific subfolder)

### Failover Cluster

For clusters, RackStack prefers Cluster Shared Volumes (CSV):
- VM config: `C:\ClusterStorage\Volume1\VMs\{VMName}\`
- VHD files: `C:\ClusterStorage\Volume1\VHDs\{VMName}\`

If no CSVs are available, it falls back to the Hyper-V default paths on the node.

### Remote Host

For remote standalone hosts, RackStack uses WinRM/PowerShell Remoting to:
- Create directories on the remote host via `Invoke-Command`.
- Create VHDs using remote `-ComputerName` parameters.
- Note: `New-VM` does not support `-Credential` directly; it uses the WinRM session context.

---

## Troubleshooting Deployment Issues

| Issue | Likely Cause | Quick Fix |
|-------|-------------|-----------|
| "Failed to connect" to local host | Hyper-V not installed | Install Hyper-V role, reboot |
| "No virtual switches found" | SET/vSwitch not created | Create via NIC configuration menu |
| "VM already exists" | Duplicate name on host/cluster | Choose different name or delete old VM |
| VHD copy fails | Disk space or corrupt base image | Check space, re-download VHD |
| "Access Denied" on remote host | WinRM not enabled or wrong credentials | Run `Enable-PSRemoting` on remote host |
| Cluster VM role fails to add | Not a cluster member or insufficient rights | Verify cluster membership |
| Dynamic memory settings error | Min > Startup or Startup > Max | RackStack auto-calculates: 25% min, 50% startup |
| Linux VM boot fails | Wrong Secure Boot template | RackStack sets UEFI CA for Linux automatically |
