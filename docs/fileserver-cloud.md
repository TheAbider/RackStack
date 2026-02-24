# File Server: Cloud Object Storage (Azure / AWS)

Use cloud object storage instead of a self-hosted file server. This approach eliminates server maintenance but requires modifications to RackStack's download logic.

See [FileServer-Setup.md](FileServer-Setup.md) for architecture overview and alternatives.

> **Status: Supported.** RackStack natively supports Azure Blob Storage with SAS tokens (`StorageType: "azure"`) and any CDN/static host via JSON index files (`StorageType: "static"`). See the configuration examples below.

## Architecture

```
RackStack (PowerShell) --HTTPS--> Cloud Storage API --serves--> ISOs, VHDs, Agents
```

No server to manage. Files are stored in a blob container (Azure) or S3 bucket (AWS). Access is controlled by SAS tokens or presigned URLs.

---

## Option A: Azure Blob Storage

### Create the storage account

```powershell
# Azure CLI
az login

az group create --name rackstack-files --location eastus

az storage account create `
    --name rackstackfiles `
    --resource-group rackstack-files `
    --location eastus `
    --sku Standard_LRS `
    --kind StorageV2
```

### Create the container and upload files

```powershell
# Create container
az storage container create `
    --name server-tools `
    --account-name rackstackfiles

# Upload files
az storage blob upload-batch `
    --destination server-tools `
    --source C:\FileServer\server-tools\ `
    --account-name rackstackfiles
```

### Folder structure in blob storage

Blob storage uses virtual directories (flat namespace with `/` separators):

```
server-tools/
    ISOs/en-us_windows_server_2025_x64.iso
    VirtualHardDrives/Server2025-Std-Sysprepped.vhdx
    Agents/KaseyaAgent_Site101.exe
```

### Generate a SAS token

```powershell
$end = (Get-Date).AddYears(1).ToString("yyyy-MM-ddTHH:mmZ")

az storage container generate-sas `
    --name server-tools `
    --account-name rackstackfiles `
    --permissions rl `
    --expiry $end `
    --output tsv
```

This produces a SAS token like: `sv=2022-11-02&ss=b&srt=sco&sp=rl&se=2027-01-01...`

### Access pattern

Files are accessed at:

```
https://rackstackfiles.blob.core.windows.net/server-tools/ISOs/en-us_windows_server_2025_x64.iso?<SAS_TOKEN>
```

Directory listing uses the Azure Blob REST API:

```
GET https://rackstackfiles.blob.core.windows.net/server-tools?restype=container&comp=list&prefix=ISOs/&delimiter=/&<SAS_TOKEN>
```

RackStack handles the XML parsing natively with `StorageType: "azure"`.

### defaults.json configuration

```json
{
    "FileServer": {
        "StorageType": "azure",
        "AzureAccount": "rackstackfiles",
        "AzureContainer": "server-tools",
        "AzureSasToken": "sv=2022-11-02&ss=b&srt=sco&sp=rl&se=2027-01-01...",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

That's it. RackStack will list blobs via the Azure REST API and download files with the SAS token appended as a query parameter.

---

## Option B: AWS S3

### Create the bucket and upload files

```bash
aws s3 mb s3://rackstack-files --region us-east-1

aws s3 sync C:\FileServer\server-tools\ s3://rackstack-files/server-tools/
```

### Folder structure in S3

Same virtual directory convention:

```
server-tools/
    ISOs/en-us_windows_server_2025_x64.iso
    VirtualHardDrives/Server2025-Std-Sysprepped.vhdx
    Agents/KaseyaAgent_Site101.exe
```

### Access pattern: Presigned URLs

```bash
aws s3 presign s3://rackstack-files/server-tools/ISOs/en-us_windows_server_2025_x64.iso --expires-in 3600
```

Produces a URL like:

```
https://rackstack-files.s3.amazonaws.com/server-tools/ISOs/en-us_windows_server_2025_x64.iso?X-Amz-Algorithm=...
```

### Access pattern: CloudFront distribution

For production, put a CloudFront distribution in front of the S3 bucket:

1. Create a CloudFront distribution with the S3 bucket as origin
2. Use Origin Access Control (OAC) to restrict direct S3 access
3. Optionally add signed URLs or signed cookies for authentication

### defaults.json configuration

For S3 with CloudFront, use the `static` storage type with JSON index files:

```json
{
    "FileServer": {
        "StorageType": "static",
        "BaseURL": "https://d123abc.cloudfront.net/server-tools",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

RackStack fetches `index.json` from each folder to get the file listing, then downloads files via standard HTTPS.

### Generating index.json files

Each folder needs an `index.json` file listing its contents. Generate and upload them alongside your files:

```powershell
# Generate index.json for each folder
function New-IndexJson {
    param([string]$LocalPath, [string]$S3Prefix)
    $entries = Get-ChildItem $LocalPath -File | ForEach-Object {
        @{ name = $_.Name; type = "file"; mtime = $_.LastWriteTimeUtc.ToString("o"); size = $_.Length }
    }
    $indexPath = Join-Path $LocalPath "index.json"
    $entries | ConvertTo-Json | Set-Content $indexPath -Encoding UTF8
    aws s3 cp $indexPath "s3://rackstack-files/${S3Prefix}/index.json"
}

New-IndexJson -LocalPath "C:\FileServer\server-tools\ISOs" -S3Prefix "server-tools/ISOs"
New-IndexJson -LocalPath "C:\FileServer\server-tools\VirtualHardDrives" -S3Prefix "server-tools/VirtualHardDrives"
New-IndexJson -LocalPath "C:\FileServer\server-tools\Agents" -S3Prefix "server-tools/Agents"
```

Re-run this whenever you add or remove files.

---

## Caching

Cloud API calls may have rate limits or costs. RackStack caches file listings for 10 minutes (`$script:CacheTTLMinutes` in `defaults.json`), which limits API calls. Azure Blob list operations are cheap (~$0.004 per 10,000 requests).

---

## Verify

### Azure

```powershell
# Test listing (should return XML with your blobs)
$sas = "sv=2022-11-02&ss=b&..."
Invoke-WebRequest -Uri "https://rackstackfiles.blob.core.windows.net/server-tools?restype=container&comp=list&prefix=ISOs/&delimiter=/&$sas" -UseBasicParsing

# Test download (should download the file)
Invoke-WebRequest -Uri "https://rackstackfiles.blob.core.windows.net/server-tools/ISOs/en-us_windows_server_2025_x64.iso?$sas" -OutFile test.iso
```

### S3 + CloudFront (static)

```powershell
# Test index listing (should return JSON array)
Invoke-RestMethod -Uri "https://d123abc.cloudfront.net/server-tools/ISOs/index.json"

# Test download
Invoke-WebRequest -Uri "https://d123abc.cloudfront.net/server-tools/ISOs/en-us_windows_server_2025_x64.iso" -OutFile test.iso
```
