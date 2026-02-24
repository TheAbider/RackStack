# File Server: Rocky Linux / AlmaLinux / RHEL

Set up a file server for RackStack on RHEL-family distributions using nginx with SELinux and firewalld properly configured.

See [FileServer-Setup.md](FileServer-Setup.md) for architecture overview and alternatives.

## Prerequisites

- Rocky Linux 8/9, AlmaLinux 8/9, or RHEL 8/9
- Root or sudo access
- A domain managed by Cloudflare (for tunnel setup)

## Step 1: Install nginx

### Rocky/Alma 9 (module stream)

```bash
sudo dnf install -y nginx
```

### Rocky/Alma 8 (EPEL or module)

```bash
# Option 1: module stream
sudo dnf module enable nginx:1.24 -y
sudo dnf install -y nginx

# Option 2: EPEL (if module not available)
sudo dnf install -y epel-release
sudo dnf install -y nginx
```

Enable and start nginx:

```bash
sudo systemctl enable --now nginx
```

## Step 2: Create the file directory structure

```bash
sudo mkdir -p /srv/files/server-tools/{ISOs,VirtualHardDrives,Agents}
sudo chown -R nginx:nginx /srv/files
```

Upload your files into the appropriate folders:
- `/srv/files/server-tools/ISOs/` -- Windows Server installation ISOs
- `/srv/files/server-tools/VirtualHardDrives/` -- Sysprepped VHDX files
- `/srv/files/server-tools/Agents/` -- agent installer files

## Step 3: SELinux context

SELinux is enforcing by default on RHEL-family systems. The served files need the correct context:

```bash
# Set the SELinux context for the file directory
sudo semanage fcontext -a -t httpd_sys_content_t "/srv/files(/.*)?"
sudo restorecon -Rv /srv/files

# Verify
ls -Z /srv/files/
```

If `semanage` is not found:

```bash
sudo dnf install -y policycoreutils-python-utils
```

### SELinux: Allow nginx to serve from /srv

On some RHEL installs, nginx is restricted from reading `/srv`. If you get 403 errors:

```bash
# Check for AVC denials
sudo ausearch -m avc -ts recent

# If needed, allow nginx to read /srv
sudo setsebool -P httpd_read_user_content on
```

## Step 4: Configure nginx

Create `/etc/nginx/conf.d/fileserver.conf`:

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

    # Version endpoint (optional)
    location /version.json {
        default_type application/json;
    }
}
```

Remove or rename the default server block if present:

```bash
# RHEL-family uses conf.d, but check for default config
sudo mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak 2>/dev/null
```

Test and reload:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Test locally: `curl http://localhost/server-tools/ISOs/` should return a JSON directory listing.

## Step 5: Configure firewalld

```bash
# Allow HTTP (for tunnel or direct access)
sudo firewall-cmd --permanent --add-service=http

# If using direct HTTPS (not tunnel)
sudo firewall-cmd --permanent --add-service=https

# Reload firewall
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --list-services
```

## Step 6: Install cloudflared

```bash
# Add the cloudflared repo
curl -fsSL https://pkg.cloudflare.com/cloudflared-ascii.repo | sudo tee /etc/yum.repos.d/cloudflared.repo

# Install
sudo dnf install -y cloudflared
```

Alternative (direct RPM):

```bash
curl -L --output cloudflared.rpm https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm
sudo dnf install -y ./cloudflared.rpm
rm cloudflared.rpm
```

## Step 7: Authenticate and create a tunnel

```bash
# Login to Cloudflare (opens browser)
cloudflared tunnel login

# Create a tunnel
cloudflared tunnel create fileserver

# Note the tunnel ID printed (e.g., a1b2c3d4-e5f6-...)
```

## Step 8: Configure the tunnel

Create `/etc/cloudflared/config.yml`:

```yaml
tunnel: YOUR-TUNNEL-ID
credentials-file: /root/.cloudflared/YOUR-TUNNEL-ID.json

ingress:
  - hostname: files.yourdomain.com
    service: http://localhost:80
  - service: http_status:404
```

Replace `YOUR-TUNNEL-ID` and `files.yourdomain.com` with your values.

## Step 9: Start the tunnel service

```bash
# Create DNS record
cloudflared tunnel route dns fileserver files.yourdomain.com

# Install as a systemd service
sudo cloudflared service install

# Start and enable
sudo systemctl start cloudflared
sudo systemctl enable cloudflared
```

Verify: `curl https://files.yourdomain.com/health` should return "OK" (if not yet protected).

## Step 10: Set up Cloudflare Access

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
        KaseyaAgent_Site101.exe
        KaseyaAgent_Site202.exe
    version.json
```

## Monitoring

```bash
# Check nginx status
sudo systemctl status nginx

# Check tunnel status
sudo systemctl status cloudflared

# Check nginx logs
sudo tail -f /var/log/nginx/access.log

# Check SELinux denials
sudo ausearch -m avc -ts recent

# Check tunnel metrics
cloudflared tunnel info fileserver
```
