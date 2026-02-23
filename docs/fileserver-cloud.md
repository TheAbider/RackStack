# File Server: Cloud Object Storage (Azure / AWS)

Use cloud object storage instead of a self-hosted file server. This approach eliminates server maintenance but requires modifications to RackStack's download logic.

See [FileServer-Setup.md](FileServer-Setup.md) for architecture overview and alternatives.

> **Status: Future Enhancement.** RackStack currently expects nginx-style JSON directory listings and standard HTTP file downloads. Cloud storage APIs use different listing formats and authentication mechanisms. This guide documents the concept and what would need to change in the tool to support it.

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
    Agents/Agent_0451_AcmeHealth.exe
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

This returns XML, not JSON.

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
    Agents/Agent_0451_AcmeHealth.exe
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

---

## What Needs to Change in RackStack

The tool's FileServer module currently assumes:

1. **JSON directory listings** from nginx autoindex (`autoindex_format json`)
2. **Direct HTTP file downloads** with optional Cloudflare Access headers
3. **Static base URL** with folder paths appended

To support cloud storage, the following changes would be needed:

### 1. Directory listing adapter

The file listing logic (in the FileServer module) would need an abstraction layer:

```powershell
# Current: expects nginx JSON autoindex response
$files = Invoke-RestMethod -Uri "$BaseURL/$folder/" -Headers $headers

# Needed: adapter per storage backend
switch ($StorageType) {
    "nginx"   { $files = Get-NginxListing -Url "$BaseURL/$folder/" -Headers $headers }
    "azure"   { $files = Get-AzureBlobListing -Account $Account -Container $Container -Prefix $folder -SasToken $SasToken }
    "s3"      { $files = Get-S3Listing -Bucket $Bucket -Prefix $folder -Region $Region }
}
```

### 2. Download URL construction

```powershell
# Current: simple URL append
$downloadUrl = "$BaseURL/$folder/$filename"

# Azure: append SAS token
$downloadUrl = "https://$Account.blob.core.windows.net/$Container/$folder/$filename?$SasToken"

# S3 presigned: generate per-file
$downloadUrl = Get-S3PresignedUrl -Bucket $Bucket -Key "$folder/$filename"
```

### 3. defaults.json schema extension

```json
{
    "FileServer": {
        "StorageType": "azure",
        "AzureAccount": "rackstackfiles",
        "AzureContainer": "server-tools",
        "AzureSasToken": "sv=2022-11-02&ss=b&...",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

Or for S3:

```json
{
    "FileServer": {
        "StorageType": "s3",
        "S3Bucket": "rackstack-files",
        "S3Region": "us-east-1",
        "S3Prefix": "server-tools",
        "ISOsFolder": "ISOs",
        "VHDsFolder": "VirtualHardDrives",
        "AgentFolder": "Agents"
    }
}
```

### 4. Authentication changes

- Azure: SAS token appended as query parameter (no headers)
- S3: AWS Signature V4 headers, or presigned URLs (no custom headers)
- Neither uses `CF-Access-Client-Id` / `CF-Access-Client-Secret`

### 5. Caching considerations

Cloud API calls may have rate limits or costs. The existing 10-minute cache (`$script:CacheTTLMinutes`) helps, but cloud-specific optimizations may be beneficial (e.g., ETags, conditional requests).

---

## Workaround: Cloud + nginx Proxy

Until the tool natively supports cloud storage, you can put nginx in front of cloud storage to provide the expected JSON directory listing format:

### Azure Blob + nginx proxy

```nginx
server {
    listen 80;

    location / {
        proxy_pass https://rackstackfiles.blob.core.windows.net/server-tools/;
        proxy_set_header Host rackstackfiles.blob.core.windows.net;
    }
}
```

This doesn't solve the directory listing problem (blobs don't return nginx-format JSON), but it does let you use a Cloudflare Tunnel for auth. You'd still need a script that generates index files.

### Static index file approach

Generate JSON index files and upload them alongside your blobs:

```powershell
# Generate index.json for each folder
$isos = Get-ChildItem "C:\FileServer\server-tools\ISOs" | ForEach-Object {
    @{ name = $_.Name; type = "file"; mtime = $_.LastWriteTimeUtc.ToString("o"); size = $_.Length }
}
$isos | ConvertTo-Json | Set-Content "C:\FileServer\server-tools\ISOs\index.json"
```

Upload `index.json` to each folder in blob storage. Then modify `defaults.json` to point to a static hosting URL and adjust the tool to request `index.json` instead of relying on autoindex.

This is the most practical cloud approach without modifying the tool's core download logic.

## Verify

Until native support is added, verification depends on the workaround used. With the static index approach:

```powershell
Invoke-RestMethod -Uri "https://rackstackfiles.blob.core.windows.net/server-tools/ISOs/index.json?<SAS_TOKEN>"
```

You should see a JSON array of file metadata matching the nginx autoindex format.
