# File Server Setup Guide

RackStack downloads ISOs, VHDs, and agent installers from a file server over HTTP(S). This page covers the architecture, requirements, and helps you choose the right setup for your environment.

## Architecture

```
RackStack (PowerShell) --HTTP(S)--> File Server --serves--> ISOs, VHDs, Agents
```

The tool expects:
- A web server that serves static files with **JSON directory listings** (nginx `autoindex_format json` or IIS directory browsing in JSON mode)
- Files organized in a consistent folder structure
- Optional authentication via Cloudflare Access service tokens (`CF-Access-Client-Id` / `CF-Access-Client-Secret` headers)

## Folder Structure

All setups use the same layout. The `BaseURL` in `defaults.json` points to the root (e.g., `server-tools/`).

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
    Agents/
        KaseyaAgent_Site101.exe
        KaseyaAgent_Site202.exe
    version.json
```

**Windows:**
```
C:\FileServer\server-tools\
    ISOs\
    VirtualHardDrives\
    Agents\
    version.json
```

## Requirements

| Requirement | Details |
|---|---|
| Web server | Any HTTP server with directory listing support (nginx, IIS, Apache, caddy) |
| Directory listing format | JSON (the tool parses JSON autoindex responses) |
| Protocol | HTTP for LAN-only; HTTPS for internet-facing |
| Authentication (optional) | Cloudflare Access service tokens, or none for LAN/VPN setups |
| Storage | Enough disk for your ISOs and VHDs (~5-20 GB typical) |

## Which Setup Should I Choose?

| Setup | Best For | Complexity | Internet Exposed | Auth |
|---|---|---|---|---|
| [Debian + Cloudflare Tunnel](fileserver-debian.md) | Production, multi-site orgs | Medium | Yes (via tunnel) | Cloudflare Access |
| [Windows Server + IIS](fileserver-windows.md) | Windows-only shops | Medium | Optional | Cloudflare Access or Let's Encrypt |
| [Rocky/Alma/RHEL](fileserver-rhel.md) | Enterprise Linux environments | Medium | Yes (via tunnel) | Cloudflare Access |
| [Docker Compose](fileserver-docker.md) | Quick deploy, any OS | Low | Yes (via tunnel) | Cloudflare Access |
| [LAN-Only](fileserver-lan.md) | Single-site, air-gapped | Low | No | None |
| [Tailscale / WireGuard](fileserver-tailscale.md) | Multi-site without Cloudflare | Low | No (mesh VPN) | Encrypted by default |
| [Cloud Storage](fileserver-cloud.md) | Azure/AWS native orgs | High | Yes | SAS tokens / presigned URLs |

**Quick recommendations:**
- **Single office, no remote sites** -- [LAN-Only](fileserver-lan.md) is simplest.
- **Multiple sites, already use Cloudflare** -- [Debian + Cloudflare Tunnel](fileserver-debian.md) is the reference setup.
- **Multiple sites, no Cloudflare** -- [Tailscale](fileserver-tailscale.md) gets you encrypted mesh with zero firewall config.
- **Want it running in 5 minutes** -- [Docker Compose](fileserver-docker.md) on any machine with Docker.
- **Windows-only environment** -- [Windows Server + IIS](fileserver-windows.md).
- **Enterprise Linux policy** -- [Rocky/Alma/RHEL](fileserver-rhel.md).
- **Already in Azure/AWS** -- [Cloud Storage](fileserver-cloud.md) (Azure Blob native, S3 via CloudFront + index.json).

## defaults.json Reference

All setups end with the same `defaults.json` configuration:

```json
{
    "FileServer": {
        "StorageType": "nginx",
        "BaseURL": "https://files.yourdomain.com/server-tools",
        "ClientId": "your-client-id-here.access",
        "ClientSecret": "your-client-secret-hex-here",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

- `StorageType` -- `nginx` (default, any web server), `azure` (Azure Blob Storage), `static` (JSON index files, works with S3+CloudFront)
- `BaseURL` -- Full URL to the `server-tools` directory (for nginx/static types; not used for azure)
- `ClientId` / `ClientSecret` -- Cloudflare Access service token credentials (omit for LAN/Tailscale/azure setups)
- For Azure: set `AzureAccount`, `AzureContainer`, `AzureSasToken` instead of BaseURL
- Folder names must match the actual directories on the file server

## Maintenance

### Adding new files

Drop files into the appropriate directory. The tool caches file listings for 10 minutes (`$script:CacheTTLMinutes`), so new files appear after the cache expires.

### Rotating service tokens

1. Create a new token in Cloudflare Zero Trust
2. Update `defaults.json` with the new `ClientId` / `ClientSecret`
3. Delete the old token

## Setup Guides

- [Debian + nginx + Cloudflare Tunnel](fileserver-debian.md) -- Reference setup
- [Windows Server + IIS](fileserver-windows.md)
- [Rocky Linux / AlmaLinux / RHEL](fileserver-rhel.md)
- [Docker Compose](fileserver-docker.md)
- [LAN-Only (no internet)](fileserver-lan.md)
- [Tailscale / WireGuard Mesh](fileserver-tailscale.md)
- [Cloud Object Storage (Azure/AWS)](fileserver-cloud.md)
