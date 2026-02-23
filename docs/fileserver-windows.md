# File Server: Windows Server + IIS

Set up a file server for RackStack using Windows Server with IIS. Most natural choice if your infrastructure is already Windows-based.

See [FileServer-Setup.md](FileServer-Setup.md) for architecture overview and alternatives.

## Prerequisites

- Windows Server 2019, 2022, or 2025
- Administrator access
- For Option A: A domain managed by Cloudflare
- For Option B: A public IP and a domain you control (any registrar)

## Step 1: Install IIS

Open an elevated PowerShell prompt:

```powershell
Install-WindowsFeature -Name Web-Server, Web-Dir-Browsing, Web-Static-Content, Web-Default-Doc -IncludeManagementTools
```

Verify IIS is running:

```powershell
Get-Service W3SVC | Select-Object Name, Status
```

## Step 2: Create the file directory structure

```powershell
$root = "C:\FileServer\server-tools"
New-Item -Path "$root\ISOs" -ItemType Directory -Force
New-Item -Path "$root\VirtualHardDrives" -ItemType Directory -Force
New-Item -Path "$root\Agents" -ItemType Directory -Force
```

Copy your files into the appropriate folders:
- `C:\FileServer\server-tools\ISOs\` -- Windows Server installation ISOs
- `C:\FileServer\server-tools\VirtualHardDrives\` -- Sysprepped VHDX files
- `C:\FileServer\server-tools\Agents\` -- agent installer files

## Step 3: Configure IIS site

Remove the default site and create the file server site:

```powershell
Import-Module WebAdministration

# Remove default site
Remove-IISSite -Name "Default Web Site" -Confirm:$false -ErrorAction SilentlyContinue

# Create new site
New-IISSite -Name "FileServer" -PhysicalPath "C:\FileServer" -BindingInformation "*:80:"

# Enable directory browsing
Set-WebConfigurationProperty -Filter /system.webServer/directoryBrowse `
    -Name enabled -Value $true -PSPath "IIS:\Sites\FileServer"
```

### Enable JSON directory listing format

IIS directory browsing outputs HTML by default. RackStack expects JSON. You need a URL Rewrite rule or a custom handler. The simplest approach is to install the IIS URL Rewrite module and use a `web.config`:

Create `C:\FileServer\web.config`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <directoryBrowse enabled="true" showFlags="Date, Time, Size" />
        <staticContent>
            <mimeMap fileExtension=".iso" mimeType="application/octet-stream" />
            <mimeMap fileExtension=".vhdx" mimeType="application/octet-stream" />
            <mimeMap fileExtension=".vhd" mimeType="application/octet-stream" />
            <mimeMap fileExtension=".exe" mimeType="application/octet-stream" />
            <mimeMap fileExtension=".json" mimeType="application/json" />
        </staticContent>
        <security>
            <requestFiltering>
                <!-- Allow large file downloads -->
                <requestLimits maxAllowedContentLength="0" />
            </requestFiltering>
        </security>
    </system.webServer>
</configuration>
```

> **Note on JSON directory listings:** IIS native directory browsing outputs HTML, not JSON. For RackStack compatibility, you have two options:
>
> 1. **Recommended:** Place a small PowerShell/ASP.NET handler that returns JSON directory listings (see the `iis-json-handler` section below).
> 2. **Alternative:** Use nginx for Windows instead of IIS (same config as the Debian guide, runs on Windows).

### IIS JSON Directory Listing Handler

Create `C:\FileServer\iis-directory.ps1` and set up a scheduled task or use a lightweight ASP.NET Core app. The simplest production approach is to run nginx for Windows alongside or instead of IIS:

```powershell
# Download nginx for Windows (alternative to IIS JSON handler)
# https://nginx.org/en/docs/windows.html
Invoke-WebRequest -Uri "https://nginx.org/download/nginx-1.27.4.zip" -OutFile "$env:TEMP\nginx.zip"
Expand-Archive -Path "$env:TEMP\nginx.zip" -DestinationPath "C:\nginx" -Force
```

If using nginx on Windows, use the same `nginx.conf` as the [Debian guide](fileserver-debian.md) with paths adjusted:

```nginx
server {
    listen 80;
    server_name localhost;
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
```

Run nginx:

```powershell
# Start nginx
Start-Process -FilePath "C:\nginx\nginx-1.27.4\nginx.exe" -WorkingDirectory "C:\nginx\nginx-1.27.4"

# To install as a service, use NSSM:
# nssm install nginx "C:\nginx\nginx-1.27.4\nginx.exe"
# nssm set nginx AppDirectory "C:\nginx\nginx-1.27.4"
```

Test locally: Open `http://localhost/server-tools/ISOs/` -- you should see a JSON directory listing.

## Step 4: Firewall rules

If serving on the LAN or directly to the internet:

```powershell
New-NetFirewallRule -DisplayName "FileServer HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName "FileServer HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow
```

## Option A: Cloudflare Tunnel (recommended for internet exposure)

Same tunnel approach as the Debian guide, but using the Windows cloudflared binary.

### Install cloudflared

```powershell
# Download cloudflared for Windows
Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.msi" -OutFile "$env:TEMP\cloudflared.msi"
Start-Process msiexec.exe -ArgumentList "/i", "$env:TEMP\cloudflared.msi", "/quiet" -Wait
```

### Authenticate and create tunnel

```powershell
# Login (opens browser)
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create fileserver
```

### Configure the tunnel

Create `C:\Users\<you>\.cloudflared\config.yml`:

```yaml
tunnel: YOUR-TUNNEL-ID
credentials-file: C:\Users\<you>\.cloudflared\YOUR-TUNNEL-ID.json

ingress:
  - hostname: files.yourdomain.com
    service: http://localhost:80
  - service: http_status:404
```

### Start the tunnel as a service

```powershell
cloudflared service install
Start-Service cloudflared
```

Then set up Cloudflare Access the same way as described in the [Debian guide](fileserver-debian.md#step-8-set-up-cloudflare-access).

## Option B: Direct HTTPS with Let's Encrypt (win-acme)

If you have a public IP and don't want to use Cloudflare Tunnel:

### Install win-acme

```powershell
# Download win-acme
Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1/win-acme.v2.2.9.1.x64.pluggable.zip" -OutFile "$env:TEMP\win-acme.zip"
Expand-Archive -Path "$env:TEMP\win-acme.zip" -DestinationPath "C:\win-acme" -Force
```

### Request a certificate

```powershell
# Run win-acme (interactive)
C:\win-acme\wacs.exe

# Follow prompts:
# 1. Create certificate (default settings)
# 2. Manual input: files.yourdomain.com
# 3. IIS binding
# 4. Pick your validation method (HTTP-01 if port 80 is open)
```

win-acme handles automatic renewal via a scheduled task.

### Add HTTPS binding

If win-acme didn't do it automatically:

```powershell
# Import the certificate and bind to IIS
New-IISSiteBinding -Name "FileServer" -BindingInformation "*:443:" -Protocol https -CertificateThumbPrint (Get-ChildItem Cert:\LocalMachine\My | Where-Object Subject -like "*files.yourdomain.com*").Thumbprint -CertStoreLocation "Cert:\LocalMachine\My"
```

> **Important:** With direct HTTPS (no Cloudflare), you won't have Cloudflare Access service token auth. You'll need another auth mechanism or restrict access by IP/VPN. For the simplest setup, combine this with [Tailscale](fileserver-tailscale.md).

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

For Option B without Cloudflare Access, omit `ClientId` and `ClientSecret`:

```json
{
    "FileServer": {
        "BaseURL": "https://files.yourdomain.com/server-tools",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
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

# Without Cloudflare Access (Option B or LAN)
Invoke-RestMethod -Uri "https://files.yourdomain.com/server-tools/ISOs/"
```

You should see a JSON directory listing of your ISOs.

## Folder Structure Reference

```
C:\FileServer\server-tools\
    ISOs\
        en-us_windows_server_2019_x64.iso
        en-us_windows_server_2022_x64.iso
        en-us_windows_server_2025_x64.iso
    VirtualHardDrives\
        Server2019-Std-Sysprepped.vhdx
        Server2022-Std-Sysprepped.vhdx
        Server2025-Std-Sysprepped.vhdx
    Agents\
        Agent_0451_AcmeHealth.exe
        Agent_0452_AcmeClinic.exe
    version.json
```

## Monitoring

```powershell
# Check IIS site status
Get-IISSite -Name "FileServer"

# Check cloudflared service (Option A)
Get-Service cloudflared

# View IIS logs
Get-Content "C:\inetpub\logs\LogFiles\W3SVC*\*.log" -Tail 20
```
