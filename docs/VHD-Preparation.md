# VHD Preparation Guide

This guide covers creating template VHDs for rapid VM deployment. RackStack supports both Windows (sysprep) and Linux (cloud-init) templates.

---

## Table of Contents

- [Windows Sysprep VHD](#windows-sysprep-vhd)
- [Linux cloud-init VHD](#linux-cloud-init-vhd)
- [Naming Convention](#naming-convention)
- [Tips](#tips)

---

## Windows Sysprep VHD

### Step 1: Create a Template VM

1. Create a new **Gen 2** VM in Hyper-V:
   - Name: `TEMPLATE-2025` (or 2022, 2019)
   - Memory: 4 GB (just for the install)
   - Disk: **150 GB Dynamic** (must be dynamic for efficient storage)
   - Network: Connect to a switch with internet access
   - Secure Boot: Microsoft Windows (default)

2. Mount the Windows Server ISO and install:
   - Choose **Desktop Experience** or **Core** as needed
   - Use a temporary password (sysprep will prompt for a new one)

### Step 2: Configure the Template

1. Install all Windows Updates (reboot as needed until clean)
2. Install Hyper-V Guest Services if not already present
3. **Do NOT:**
   - Join a domain
   - Install site-specific agents or software
   - Change the admin password to a production password

### Step 3: Sysprep and Shut Down

Run the sysprep command:

```
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /mode:vm
```

> The `/mode:vm` flag speeds up re-specialization for Hyper-V VMs. The VM will **shut down** automatically after sysprep completes. **Do NOT start it again.**

### Step 4: Export the VHDX

1. Copy the VHDX from the template VM folder (usually `D:\Virtual Machines\TEMPLATE-2025\`)
2. Rename appropriately:
   - `Server2025_Sysprepped.vhdx`
   - `Server2022_Sysprepped.vhdx`
   - `Server2019_Sysprepped.vhdx`
3. Upload to your FileServer VHDs folder (if configured)

---

## Linux cloud-init VHD

### Step 1: Create a Template VM

1. Create a new **Gen 2** VM in Hyper-V:
   - Name: `TEMPLATE-Ubuntu2404` (or `Rocky9`, `Debian12`)
   - Memory: 2-4 GB
   - Disk: **100 GB Dynamic** (must be dynamic)
   - Network: Connect to a switch with internet access
   - Secure Boot: **Microsoft UEFI Certificate Authority** (NOT "Microsoft Windows")

2. Mount the Linux ISO and install (minimal/server install)
   - Install OpenSSH server during setup

### Step 2: Install and Configure cloud-init

**Ubuntu/Debian:**
```bash
sudo apt update && sudo apt install -y cloud-init
```

**Rocky/RHEL:**
```bash
sudo dnf install -y cloud-init
```

**Enable Hyper-V datasource** in `/etc/cloud/cloud.cfg`:
```yaml
datasource_list: [ Azure, None ]
```

**Install Hyper-V guest tools:**
```bash
# Ubuntu
sudo apt install -y linux-tools-virtual

# Rocky/RHEL
sudo dnf install -y hyperv-daemons
```

### Step 3: Clean Up for Templating

```bash
# Clean cloud-init state
sudo cloud-init clean --logs

# Remove SSH host keys (regenerated on first boot)
sudo rm -f /etc/ssh/ssh_host_*

# Truncate machine-id (regenerated on first boot)
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id

# Clear bash history
history -c && cat /dev/null > ~/.bash_history

# Shut down (DO NOT start again!)
sudo shutdown -h now
```

### Step 4: Export the VHDX

1. Copy the VHDX from the template VM folder
2. Rename appropriately:
   - `Ubuntu2404_CloudInit.vhdx`
   - `Rocky9_CloudInit.vhdx`
   - `Debian12_CloudInit.vhdx`
3. Upload to your FileServer VHDs folder (if configured)

---

## Naming Convention

| OS | Template Name |
|----|---------------|
| Windows Server 2025 | `Server2025_Sysprepped.vhdx` |
| Windows Server 2022 | `Server2022_Sysprepped.vhdx` |
| Windows Server 2019 | `Server2019_Sysprepped.vhdx` |
| Ubuntu 24.04 | `Ubuntu2404_CloudInit.vhdx` |
| Rocky Linux 9 | `Rocky9_CloudInit.vhdx` |
| Debian 12 | `Debian12_CloudInit.vhdx` |

---

## Tips

- **Keep VHDs dynamic** for storage efficiency. RackStack converts to fixed when deploying to each VM.
- **Update quarterly** after new OS updates: clone the template, boot, patch, re-sysprep/re-clean, re-upload.
- **Do NOT** join the template to a domain before sysprep/cloud-init cleanup.
- **Do NOT** install site-specific agents or software. Those are installed per-site after deployment.
- For Windows: sysprep will prompt for a new password on first boot (OOBE).
- For Linux: cloud-init handles hostname, network, and SSH key configuration on first boot.
- Linux VMs use **Microsoft UEFI Certificate Authority** for Secure Boot (not "Microsoft Windows").
