# File Server: Docker Compose

Set up a file server for RackStack using Docker Compose with nginx and an optional cloudflared sidecar. Works on any OS with Docker installed. Simple to deploy, tear down, and move between hosts.

See [FileServer-Setup.md](FileServer-Setup.md) for architecture overview and alternatives.

## Prerequisites

- Docker and Docker Compose installed (Docker Desktop on Windows/Mac, or `docker-ce` on Linux)
- A domain managed by Cloudflare (for tunnel setup; skip if LAN-only)

## Step 1: Create the directory structure

```bash
mkdir -p fileserver/data/server-tools/{ISOs,VirtualHardDrives,KaseyaAgents}
mkdir -p fileserver/config
cd fileserver
```

On Windows (PowerShell):

```powershell
New-Item -Path "fileserver\data\server-tools\ISOs" -ItemType Directory -Force
New-Item -Path "fileserver\data\server-tools\VirtualHardDrives" -ItemType Directory -Force
New-Item -Path "fileserver\data\server-tools\KaseyaAgents" -ItemType Directory -Force
New-Item -Path "fileserver\config" -ItemType Directory -Force
Set-Location fileserver
```

Copy your ISOs, VHDs, and agent installers into the appropriate `data/server-tools/` subdirectories.

## Step 2: Create nginx config

Create `config/nginx.conf`:

```nginx
server {
    listen 80;
    server_name localhost;

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

    location /version.json {
        default_type application/json;
    }
}
```

## Step 3: Create docker-compose.yml

### With Cloudflare Tunnel (internet-facing)

Create `docker-compose.yml`:

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: fileserver-nginx
    restart: unless-stopped
    volumes:
      - ./data:/srv/files:ro
      - ./config/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "127.0.0.1:8080:80"  # Local access only; tunnel handles external
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/health"]
      interval: 30s
      timeout: 5s
      retries: 3

  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: fileserver-tunnel
    restart: unless-stopped
    depends_on:
      nginx:
        condition: service_healthy
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=${TUNNEL_TOKEN}
```

### LAN-only (no tunnel)

```yaml
services:
  nginx:
    image: nginx:alpine
    container_name: fileserver-nginx
    restart: unless-stopped
    volumes:
      - ./data:/srv/files:ro
      - ./config/nginx.conf:/etc/nginx/conf.d/default.conf:ro
    ports:
      - "80:80"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

## Step 4: Set up Cloudflare Tunnel (if using)

### Create the tunnel

From the Cloudflare Zero Trust dashboard (https://one.dash.cloudflare.com):

1. Go to **Networks > Tunnels**
2. Click **Create a tunnel**
3. Select **Cloudflared** connector
4. Name it `fileserver`
5. Copy the **tunnel token** (a long base64 string)

Or from the CLI:

```bash
cloudflared tunnel login
cloudflared tunnel create fileserver
cloudflared tunnel token fileserver
```

### Save the token

Create a `.env` file in the `fileserver/` directory:

```bash
TUNNEL_TOKEN=eyJhIjoiYWJjZGVmLi4uIiwidCI6ImExYjJjM2Q0Li4uIiwicyI6IkFCQ0RFRi4uLiJ9
```

> **Never commit `.env` to version control.**

### Configure tunnel routing

In the Cloudflare Zero Trust dashboard, configure the tunnel's public hostname:

- **Subdomain**: `files`
- **Domain**: `yourdomain.com`
- **Service**: `http://nginx:80`

### Set up Cloudflare Access

Follow the same Cloudflare Access setup as the [Debian guide](fileserver-debian.md#step-8-set-up-cloudflare-access) to protect the endpoint with service tokens.

## Step 5: Start the stack

```bash
docker compose up -d
```

Check status:

```bash
docker compose ps
docker compose logs -f
```

Test locally:

```bash
curl http://localhost:8080/server-tools/ISOs/
```

## Updating files

Just drop files into `data/server-tools/`. No container restart needed -- nginx serves directly from the mounted volume.

```bash
# Example: copy an ISO into the data directory
cp ~/Downloads/en-us_windows_server_2025_x64.iso data/server-tools/ISOs/
```

## Tearing down

```bash
# Stop and remove containers
docker compose down

# Stop, remove containers, AND remove volumes
docker compose down -v
```

Your files in `data/` are not affected by `docker compose down` since they're bind-mounted, not Docker volumes.

## Configure defaults.json

```json
{
    "FileServer": {
        "BaseURL": "https://files.yourdomain.com/server-tools",
        "ClientId": "your-client-id-here.access",
        "ClientSecret": "your-client-secret-hex-here",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "KaseyaFolder": "KaseyaAgents"
    }
}
```

For LAN-only (no tunnel), point to the host IP:

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

## Verify

```powershell
# With Cloudflare Access
$headers = @{
    "CF-Access-Client-Id" = "your-client-id.access"
    "CF-Access-Client-Secret" = "your-secret"
}
Invoke-RestMethod -Uri "https://files.yourdomain.com/server-tools/ISOs/" -Headers $headers

# LAN-only
Invoke-RestMethod -Uri "http://192.168.1.50/server-tools/ISOs/"
```

You should see a JSON directory listing of your ISOs.

## Folder Structure Reference

```
fileserver/
    docker-compose.yml
    .env                          # Tunnel token (gitignored)
    config/
        nginx.conf
    data/
        server-tools/
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

## Monitoring

```bash
# Container status
docker compose ps

# Follow logs
docker compose logs -f nginx
docker compose logs -f cloudflared

# Resource usage
docker stats fileserver-nginx fileserver-tunnel
```
