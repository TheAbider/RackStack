# File Server: Debian + nginx + Cloudflare Tunnel

This is the reference file server setup for RackStack. It uses Debian with nginx for static file serving, a Cloudflare Tunnel for secure internet exposure, and Cloudflare Access for service token authentication.

See [FileServer-Setup.md](FileServer-Setup.md) for architecture overview and alternatives.

## Prerequisites

- A domain managed by Cloudflare (free plan works)
- A Debian-based server (Debian 12+ or Ubuntu 22.04+)
- Root or sudo access on the server

## Step 1: Install nginx

```bash
sudo apt update && sudo apt install -y nginx
```

## Step 2: Create the file directory structure

```bash
sudo mkdir -p /srv/files/server-tools/{ISOs,VirtualHardDrives,Agents}
sudo chown -R www-data:www-data /srv/files
```

Upload your files into the appropriate folders:
- `/srv/files/server-tools/ISOs/` -- Windows Server installation ISOs (e.g., `en-us_windows_server_2025_x64.iso`)
- `/srv/files/server-tools/VirtualHardDrives/` -- Sysprepped VHDX files (e.g., `Server2025-Std-Sysprepped.vhdx`)
- `/srv/files/server-tools/Agents/` -- agent installer files (e.g., `Agent_0451_AcmeHealth.exe`)

## Step 3: Configure nginx

Create `/etc/nginx/sites-available/fileserver`:

```nginx
server {
    listen 80;
    server_name localhost;

    # Root directory for all files
    root /srv/files;

    # Enable directory listings for the tool to enumerate available files
    autoindex on;
    autoindex_format json;

    # Serve files with proper MIME types
    location / {
        try_files $uri $uri/ =404;

        # Large file support
        client_max_body_size 0;

        # Optimize for large file transfers
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
    }

    # Health check endpoint
    location /health {
        return 200 'OK';
        add_header Content-Type text/plain;
    }

    # Version endpoint (optional - for update checking)
    location /version.json {
        default_type application/json;
    }
}
```

Enable the site:

```bash
sudo ln -sf /etc/nginx/sites-available/fileserver /etc/nginx/sites-enabled/fileserver
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Test locally: `curl http://localhost/server-tools/ISOs/` should return a JSON directory listing.

## Step 4: Install cloudflared

```bash
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
rm cloudflared.deb
```

## Step 5: Authenticate and create a tunnel

```bash
# Login to Cloudflare (opens browser)
cloudflared tunnel login

# Create a tunnel
cloudflared tunnel create fileserver

# Note the tunnel ID printed (e.g., a1b2c3d4-e5f6-...)
```

## Step 6: Configure the tunnel

Create `/etc/cloudflared/config.yml`:

```yaml
tunnel: YOUR-TUNNEL-ID
credentials-file: /root/.cloudflared/YOUR-TUNNEL-ID.json

ingress:
  - hostname: files.yourdomain.com
    service: http://localhost:80
  - service: http_status:404
```

Replace `YOUR-TUNNEL-ID` with the actual tunnel ID and `files.yourdomain.com` with your desired subdomain.

## Step 7: Create DNS record and start the tunnel

```bash
# Create DNS record pointing to the tunnel
cloudflared tunnel route dns fileserver files.yourdomain.com

# Install as a system service
sudo cloudflared service install

# Start the service
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
```

Verify: `curl https://files.yourdomain.com/health` should return "OK" (if not yet protected).

## Step 8: Set up Cloudflare Access

1. Go to **Cloudflare Zero Trust** dashboard (https://one.dash.cloudflare.com)
2. Navigate to **Access > Applications**
3. Click **Add an application** > **Self-hosted**
4. Configure:
   - **Application name**: File Server
   - **Session duration**: 24 hours
   - **Application domain**: `files.yourdomain.com`
5. Add a policy:
   - **Policy name**: Service Token
   - **Action**: Allow
   - **Include**: Service Auth > Service Token
6. Save the application

### Create a Service Token

1. Go to **Access > Service Auth**
2. Click **Create Service Token**
3. **Name**: Server Config Tool
4. **Duration**: Non-expiring (or set a rotation schedule)
5. Copy the **Client ID** and **Client Secret** -- you won't see the secret again!

## Configure defaults.json

Add the credentials to your `defaults.json`:

```json
{
    "FileServer": {
        "BaseURL": "https://files.yourdomain.com/server-tools",
        "ClientId": "your-client-id-here.access",
        "ClientSecret": "your-client-secret-hex-here",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

The tool sends these as `CF-Access-Client-Id` and `CF-Access-Client-Secret` headers with every request.

## Verify

Test from PowerShell on a Windows machine:

```powershell
$headers = @{
    "CF-Access-Client-Id" = "your-client-id.access"
    "CF-Access-Client-Secret" = "your-secret"
}
Invoke-RestMethod -Uri "https://files.yourdomain.com/server-tools/ISOs/" -Headers $headers
```

You should see a JSON directory listing of your ISOs.

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
        Agent_0451_AcmeHealth.exe
        Agent_0452_AcmeClinic.exe
    version.json
```

## Monitoring

```bash
# Check tunnel status
sudo systemctl status cloudflared

# Check nginx logs
sudo tail -f /var/log/nginx/access.log

# Check tunnel metrics
cloudflared tunnel info fileserver
```
