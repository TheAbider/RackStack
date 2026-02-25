# File Server: Tailscale / WireGuard Mesh

Serve files over a Tailscale mesh network. No Cloudflare account needed, no tunnels to configure, encrypted by default. Each machine on your tailnet gets a stable `100.x.x.x` IP and optional MagicDNS hostname.

See [FileServer-Setup.md](FileServer-Setup.md) for architecture overview and alternatives.

## Architecture

```
RackStack (workstation) --Tailscale mesh (WireGuard)--> File server (100.x.x.x) --nginx--> files
```

- Traffic is encrypted end-to-end via WireGuard
- No ports opened on your firewall
- No public DNS or certificates needed
- Works across sites, data centers, and cloud

## Prerequisites

- A Tailscale account (free for personal use, up to 100 devices)
- A file server (any OS) with Tailscale installed
- RackStack workstations with Tailscale installed

---

## Step 1: Install Tailscale on the file server

### Linux (Debian/Ubuntu)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Linux (RHEL/Rocky/Alma)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

### Windows

Download from https://tailscale.com/download/windows and install. Or use winget:

```powershell
winget install Tailscale.Tailscale
```

Sign in when prompted.

### Get the Tailscale IP

```bash
tailscale ip -4
# Output: 100.x.x.x
```

Or check the Tailscale admin console at https://login.tailscale.com/admin/machines.

Note the IP (e.g., `100.64.0.5`) or the MagicDNS hostname (e.g., `fileserver.tail1234.ts.net`).

## Step 2: Set up the web server

Use any web server. nginx is shown below. Same setup as the [LAN-Only guide](fileserver-lan.md), just listening on the Tailscale interface.

### Linux (nginx)

```bash
sudo apt update && sudo apt install -y nginx     # Debian/Ubuntu
# or
sudo dnf install -y nginx                        # RHEL/Rocky/Alma
```

Create the directory structure:

```bash
sudo mkdir -p /srv/files/server-tools/{ISOs,VirtualHardDrives,Agents}
sudo chown -R www-data:www-data /srv/files    # nginx:nginx on RHEL
```

Create `/etc/nginx/sites-available/fileserver` (Debian) or `/etc/nginx/conf.d/fileserver.conf` (RHEL):

```nginx
server {
    listen 80;
    server_name _;

    root /srv/files;

    autoindex on;
    autoindex_format json;

    location / {
        try_files $uri $uri/ =404;
        client_max_body_size 0;
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
    }

    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }
}
```

Enable and start:

```bash
# Debian/Ubuntu
sudo ln -sf /etc/nginx/sites-available/fileserver /etc/nginx/sites-enabled/fileserver
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t && sudo systemctl reload nginx
```

### Windows (nginx)

Follow the Windows nginx setup from the [LAN-Only guide](fileserver-lan.md#option-b-windows-nginx-for-windows).

## Step 3: Restrict to Tailscale only (optional)

If you want the file server to ONLY accept connections from the Tailscale network:

### Linux (nginx)

Bind nginx to the Tailscale IP only:

```nginx
server {
    listen 100.64.0.5:80;    # Replace with your Tailscale IP
    # ... rest of config
}
```

### Linux (firewall)

```bash
# UFW: allow only from Tailscale subnet
sudo ufw allow from 100.64.0.0/10 to any port 80

# firewalld: add Tailscale interface to trusted zone
sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0
sudo firewall-cmd --reload
```

### Windows (firewall)

```powershell
New-NetFirewallRule -DisplayName "FileServer HTTP (Tailscale only)" `
    -Direction Inbound -Protocol TCP -LocalPort 80 `
    -RemoteAddress 100.64.0.0/10 -Action Allow
```

## Step 4: Install Tailscale on RackStack workstations

Each Windows machine running RackStack needs Tailscale:

```powershell
winget install Tailscale.Tailscale
```

Sign in with the same Tailscale account (or use shared nodes / ACL tags for org accounts).

Verify connectivity:

```powershell
# Ping the file server via Tailscale
ping 100.64.0.5

# Or use MagicDNS
ping fileserver.tail1234.ts.net
```

## Configure defaults.json

Use the Tailscale IP or MagicDNS hostname. No auth headers needed -- Tailscale handles identity and encryption:

```json
{
    "FileServer": {
        "BaseURL": "http://100.64.0.5/server-tools",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

Or with MagicDNS:

```json
{
    "FileServer": {
        "BaseURL": "http://fileserver.tail1234.ts.net/server-tools",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

## Verify

```powershell
Invoke-RestMethod -Uri "http://100.64.0.5/server-tools/ISOs/"
# or
Invoke-RestMethod -Uri "http://fileserver.tail1234.ts.net/server-tools/ISOs/"
```

You should see a JSON directory listing of your ISOs.

---

## Alternative: WireGuard (manual)

If you prefer raw WireGuard without Tailscale:

### File server

```bash
sudo apt install -y wireguard

# Generate keys
wg genkey | tee /etc/wireguard/server-private.key | wg pubkey > /etc/wireguard/server-public.key
chmod 600 /etc/wireguard/server-private.key
```

Create `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>

[Peer]
# RackStack workstation
PublicKey = <client-public-key>
AllowedIPs = 10.0.0.2/32
```

```bash
sudo systemctl enable --now wg-quick@wg0
```

### RackStack workstation (Windows)

Download WireGuard from https://www.wireguard.com/install/ and create a tunnel:

```ini
[Interface]
Address = 10.0.0.2/24
PrivateKey = <client-private-key>

[Peer]
PublicKey = <server-public-key>
Endpoint = <server-public-ip>:51820
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
```

Then point `defaults.json` at the WireGuard IP:

```json
{
    "FileServer": {
        "BaseURL": "http://10.0.0.1/server-tools",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

> **Note:** Manual WireGuard requires managing keys, endpoints, and routing yourself. Tailscale automates all of this. Use raw WireGuard only if you have a specific reason to avoid Tailscale.

## Folder Structure Reference

```
/srv/files/server-tools/
    ISOs/
        en-us_windows_server_2019_x64.iso
        en-us_windows_server_2022_x64.iso
        en-us_windows_server_2025_x64.iso
    VirtualHardDrives/
        Server2019-Std-Sysprepped.vhdx
        Server2022-Std-Sysprepped.vhdx
        Server2025-Std-Sysprepped.vhdx
    Agents/
        Agent_org.101-mainoffice.exe
        Agent_org.202-westbranch.exe
    version.json
```

## Monitoring

```bash
# Tailscale status
tailscale status

# Check nginx
sudo systemctl status nginx
curl http://localhost/health

# WireGuard status (if using raw WG)
sudo wg show
```
