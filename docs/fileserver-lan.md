# File Server: LAN-Only (No Internet Exposure)

The simplest file server setup for RackStack. Serve files on your local network with no tunnel, no auth, and no certificates. Good for single-site deployments and air-gapped environments.

See [FileServer-Setup.md](FileServer-Setup.md) for architecture overview and alternatives.

## Architecture

```
RackStack (workstation) --HTTP--> File server (LAN IP) --serves--> ISOs, VHDs, Agents
```

No internet exposure. No authentication. Just a web server on your LAN serving static files. Point `defaults.json` at the server's LAN IP and you're done.

## Prerequisites

- A machine on the same network as your RackStack workstations
- Static IP or DHCP reservation for the file server

---

## Option A: Linux (nginx)

Works on any Linux distribution. Using Debian/Ubuntu commands below; adapt for your distro.

### Install nginx

```bash
sudo apt update && sudo apt install -y nginx
```

### Create directory structure

```bash
sudo mkdir -p /srv/files/server-tools/{ISOs,VirtualHardDrives,KaseyaAgents}
sudo chown -R www-data:www-data /srv/files
```

### Configure nginx

Create `/etc/nginx/sites-available/fileserver`:

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
sudo ln -sf /etc/nginx/sites-available/fileserver /etc/nginx/sites-enabled/fileserver
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### Allow through firewall

```bash
# UFW (Debian/Ubuntu)
sudo ufw allow 80/tcp

# firewalld (RHEL/Rocky/Alma)
sudo firewall-cmd --permanent --add-service=http && sudo firewall-cmd --reload

# iptables (manual)
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
```

### Test

```bash
curl http://localhost/server-tools/ISOs/
```

From another machine on the LAN:

```bash
curl http://192.168.1.50/server-tools/ISOs/
```

---

## Option B: Windows (nginx for Windows)

IIS directory browsing outputs HTML, not JSON. The simplest way to get JSON directory listings on Windows is nginx.

### Download and extract nginx

```powershell
$nginxVersion = "1.27.4"
Invoke-WebRequest -Uri "https://nginx.org/download/nginx-$nginxVersion.zip" -OutFile "$env:TEMP\nginx.zip"
Expand-Archive -Path "$env:TEMP\nginx.zip" -DestinationPath "C:\nginx" -Force
```

### Create directory structure

```powershell
$root = "C:\FileServer\server-tools"
New-Item -Path "$root\ISOs" -ItemType Directory -Force
New-Item -Path "$root\VirtualHardDrives" -ItemType Directory -Force
New-Item -Path "$root\KaseyaAgents" -ItemType Directory -Force
```

### Configure nginx

Replace the contents of `C:\nginx\nginx-1.27.4\conf\nginx.conf`:

```nginx
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    tcp_nopush    on;
    tcp_nodelay   on;

    server {
        listen 80;
        server_name _;

        root C:/FileServer;

        autoindex on;
        autoindex_format json;

        location / {
            try_files $uri $uri/ =404;
        }

        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
    }
}
```

### Start nginx

```powershell
# Start directly
Start-Process -FilePath "C:\nginx\nginx-1.27.4\nginx.exe" -WorkingDirectory "C:\nginx\nginx-1.27.4"
```

To run as a Windows service, use NSSM:

```powershell
# Download NSSM (https://nssm.cc/download)
nssm install nginx "C:\nginx\nginx-1.27.4\nginx.exe"
nssm set nginx AppDirectory "C:\nginx\nginx-1.27.4"
nssm start nginx
```

### Firewall rule

```powershell
New-NetFirewallRule -DisplayName "FileServer HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
```

### Test

```powershell
Invoke-RestMethod -Uri "http://localhost/server-tools/ISOs/"
```

---

## Configure defaults.json

No `ClientId` or `ClientSecret` needed for LAN-only setups:

```json
{
    "FileServer": {
        "BaseURL": "http://192.168.1.50/server-tools",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "KaseyaFolder": "KaseyaAgents"
    }
}
```

Replace `192.168.1.50` with your file server's actual LAN IP.

> **Tip:** You can also use a hostname if your network has DNS (e.g., `http://fileserver.local/server-tools`).

## Verify

From any RackStack workstation on the LAN:

```powershell
Invoke-RestMethod -Uri "http://192.168.1.50/server-tools/ISOs/"
```

You should see a JSON directory listing of your ISOs.

## Folder Structure Reference

**Linux:**
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
    KaseyaAgents/
        Kaseya_0451_AcmeHealth.exe
        Kaseya_0452_AcmeClinic.exe
    version.json
```

**Windows:**
```
C:\FileServer\server-tools\
    ISOs\
    VirtualHardDrives\
    KaseyaAgents\
    version.json
```

## Security Note

This setup has no authentication. Anyone on the LAN can access the files. This is acceptable for:
- Isolated lab networks
- Air-gapped environments
- Single-site offices with trusted network segments

If you need access control without internet exposure, consider the [Tailscale](fileserver-tailscale.md) setup instead.
