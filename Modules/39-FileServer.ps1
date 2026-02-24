#region ===== FILESERVER DOWNLOAD =====
# Build the download URL for a file based on the FileServer storage type
# Returns the full URL with authentication tokens/parameters included
function Get-FileServerUrl {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )

    $storageType = if ($script:FileServer.StorageType) { $script:FileServer.StorageType } else { "nginx" }

    switch ($storageType) {
        "azure" {
            $account = $script:FileServer.AzureAccount
            $container = $script:FileServer.AzureContainer
            $sas = $script:FileServer.AzureSasToken
            $encodedPath = ($FilePath -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
            return "https://${account}.blob.core.windows.net/${container}/${encodedPath}?${sas}"
        }
        default {
            # nginx / static — use BaseURL + path
            $encodedPath = ($FilePath -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
            return "$($script:FileServer.BaseURL)/$encodedPath"
        }
    }
}

# Get auth headers for the configured storage type
# Returns empty hashtable for token-based auth (Azure SAS, S3 presigned)
function Get-FileServerHeaders {
    $storageType = if ($script:FileServer.StorageType) { $script:FileServer.StorageType } else { "nginx" }

    switch ($storageType) {
        "azure" {
            # Azure SAS uses query parameters, no special headers
            return @{}
        }
        default {
            # nginx — Cloudflare Access headers
            $headers = @{}
            if ($script:FileServer.ClientId) {
                $headers["CF-Access-Client-Id"] = $script:FileServer.ClientId
            }
            if ($script:FileServer.ClientSecret) {
                $headers["CF-Access-Client-Secret"] = $script:FileServer.ClientSecret
            }
            return $headers
        }
    }
}

# Check if the FileServer has a valid configuration for its storage type
function Test-FileServerConfigured {
    $storageType = if ($script:FileServer.StorageType) { $script:FileServer.StorageType } else { "nginx" }

    switch ($storageType) {
        "azure" {
            return (-not [string]::IsNullOrWhiteSpace($script:FileServer.AzureAccount) -and
                    -not [string]::IsNullOrWhiteSpace($script:FileServer.AzureContainer))
        }
        default {
            return (-not [string]::IsNullOrWhiteSpace($script:FileServer.BaseURL))
        }
    }
}

# Browse a FileServer folder via HTTP GET and parse the listing response
# Supports nginx autoindex HTML, Azure Blob XML, and static index.json
# Results are cached per folder path with a configurable TTL
function Get-FileServerFiles {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderPath,
        [switch]$ForceRefresh
    )

    # Check cache
    if (-not $ForceRefresh -and $script:FileCache.ContainsKey($FolderPath)) {
        $cached = $script:FileCache[$FolderPath]
        $cacheAge = (Get-Date) - $cached.CacheTime
        if ($cacheAge.TotalMinutes -lt $script:CacheTTLMinutes) {
            return $cached.Files
        }
    }

    # Validate FileServer is configured
    if (-not (Test-FileServerConfigured)) {
        Write-OutputColor "  FileServer not configured. Update settings in defaults.json." -color "Error"
        return @()
    }

    $storageType = if ($script:FileServer.StorageType) { $script:FileServer.StorageType } else { "nginx" }

    try {
        $files = @()
        $headers = Get-FileServerHeaders

        switch ($storageType) {
            "azure" {
                # Azure Blob Storage — list blobs with prefix and delimiter
                $account = $script:FileServer.AzureAccount
                $container = $script:FileServer.AzureContainer
                $sas = $script:FileServer.AzureSasToken
                $encodedFolder = [System.Uri]::EscapeDataString("$FolderPath/")
                $url = "https://${account}.blob.core.windows.net/${container}?restype=container&comp=list&prefix=${encodedFolder}&delimiter=/&${sas}"

                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
                [xml]$xml = $response.Content

                $blobs = $xml.EnumerationResults.Blobs.Blob
                if ($blobs) {
                    foreach ($blob in $blobs) {
                        $blobName = $blob.Name
                        # Extract filename from full path (remove prefix)
                        $fileName = $blobName
                        if ($blobName.Contains('/')) {
                            $fileName = $blobName.Substring($blobName.LastIndexOf('/') + 1)
                        }
                        if ([string]::IsNullOrWhiteSpace($fileName)) { continue }

                        $fileSize = 0
                        if ($blob.Properties.'Content-Length') {
                            $fileSize = [long]$blob.Properties.'Content-Length'
                        }

                        $files += @{
                            FileName = $fileName
                            FilePath = "$FolderPath/$fileName"
                            Size     = $fileSize
                        }
                    }
                }
            }
            "static" {
                # Static index.json — fetch index.json from the folder
                $encodedFolder = [System.Uri]::EscapeDataString($FolderPath)
                $url = "$($script:FileServer.BaseURL)/$encodedFolder/index.json"

                $requestParams = @{ Uri = $url; UseBasicParsing = $true; ErrorAction = "Stop" }
                if ($headers.Count -gt 0) { $requestParams.Headers = $headers }

                $response = Invoke-WebRequest @requestParams
                $entries = $response.Content | ConvertFrom-Json

                foreach ($entry in $entries) {
                    $fileName = $entry.name
                    if ([string]::IsNullOrWhiteSpace($fileName)) { continue }
                    if ($entry.type -eq 'directory') { continue }

                    $fileSize = 0
                    if ($entry.size) { $fileSize = [long]$entry.size }

                    $files += @{
                        FileName = $fileName
                        FilePath = "$FolderPath/$fileName"
                        Size     = $fileSize
                    }
                }
            }
            default {
                # nginx — parse HTML autoindex response
                $encodedFolder = [System.Uri]::EscapeDataString($FolderPath)
                $url = "$($script:FileServer.BaseURL)/$encodedFolder/"

                $requestParams = @{ Uri = $url; UseBasicParsing = $true; ErrorAction = "Stop" }
                if ($headers.Count -gt 0) { $requestParams.Headers = $headers }

                $response = Invoke-WebRequest @requestParams
                $html = $response.Content

                # Parse nginx autoindex HTML: <a href="filename">display</a>  date  size
                $regexMatches = [regex]::Matches($html, '<a href="([^"]+)">([^<]+)</a>\s+(\d{2}-\w{3}-\d{4}\s+\d{2}:\d{2})\s+(\d+|-)')

                foreach ($m in $regexMatches) {
                    $href = $m.Groups[1].Value
                    $sizeStr = $m.Groups[4].Value

                    if ($href -eq '../' -or $href.EndsWith('/')) { continue }

                    $fileName = [System.Uri]::UnescapeDataString($href)
                    $fileSize = 0
                    if ($sizeStr -ne '-' -and $sizeStr -match '^\d+$') {
                        $fileSize = [long]$sizeStr
                    }

                    $files += @{
                        FileName = $fileName
                        FilePath = "$FolderPath/$fileName"
                        Size     = $fileSize
                    }
                }
            }
        }

        # Update cache
        $script:FileCache[$FolderPath] = @{
            Files     = $files
            CacheTime = Get-Date
        }

        return $files
    }
    catch {
        Write-OutputColor "  Failed to browse FileServer folder: $($_.Exception.Message)" -color "Error"
        return @()
    }
}

# Find a file in an FileServer folder by matching a keyword in the filename
# Returns the first match as @{ FileName; FilePath; Size } or $null if no match
function Find-FileServerFile {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FolderPath,
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Keyword,
        [string]$Extension
    )

    $files = Get-FileServerFiles -FolderPath $FolderPath
    if (-not $files -or $files.Count -eq 0) { return $null }

    $keywordMatch = $null
    foreach ($file in $files) {
        if ($file.FileName -match [regex]::Escape($Keyword)) {
            if ($Extension -and $file.FileName -match "\.$Extension$") {
                return $file  # Exact keyword + extension match
            }
            if (-not $keywordMatch) { $keywordMatch = $file }
        }
    }
    return $keywordMatch  # Fall back to keyword-only match (no extension)
}

# Reusable function to download files from FileServer via HTTP GET
# Uses WebClient.DownloadFile() to avoid Invoke-WebRequest keep-alive hang.
# Shows rich progress bar with speed/ETA, retries once on failure, and
# verifies integrity via size check + SHA256 hash.
function Get-FileServerFile {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,

        [string]$FileName = "download",

        [int]$TimeoutSeconds = 0  # 0 = use $script:DefaultDownloadTimeoutSeconds
    )

    # Apply default timeout if not specified
    if ($TimeoutSeconds -eq 0) { $TimeoutSeconds = $script:DefaultDownloadTimeoutSeconds }

    # Check if FileServer is configured
    if (-not (Test-FileServerConfigured)) {
        return @{
            Success = $false
            Error = "FileServer not configured. Update the settings in defaults.json."
            FilePath = $null
        }
    }

    $destFile = Join-Path $DestinationPath $FileName

    # Ensure destination directory exists
    if (-not (Test-Path $DestinationPath)) {
        try {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }
        catch {
            return @{
                Success = $false
                Error = "Failed to create directory: $DestinationPath - $_"
                FilePath = $null
            }
        }
    }

    try {
        # Build download URL and auth headers based on storage type
        $downloadUrl = Get-FileServerUrl -FilePath $FilePath
        $downloadHeaders = Get-FileServerHeaders

        # Get expected size via HEAD request before download
        $expectedSize = Get-FileServerFileSize -FilePath $FilePath

        Write-OutputColor "  Initiating download from FileServer..." -color "Info"
        Write-OutputColor "  File: $FileName" -color "Info"
        if ($expectedSize -gt 0) {
            Write-OutputColor "  Size: $(Format-TransferSize $expectedSize)" -color "Info"
        }
        Write-OutputColor "  Destination: $destFile" -color "Info"
        Write-OutputColor "" -color "Info"

        # Disk space check before download
        if ($expectedSize -gt 0) {
            $destDrive = Split-Path -Qualifier $destFile -ErrorAction SilentlyContinue
            if ($destDrive) {
                $driveLetter = $destDrive.TrimEnd(':')
                $vol = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
                if ($vol -and $vol.SizeRemaining -gt 0) {
                    $requiredSpace = [long]($expectedSize * 1.1)  # 10% buffer
                    if ($vol.SizeRemaining -lt $requiredSpace) {
                        $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
                        $needGB = [math]::Round($requiredSpace / 1GB, 1)
                        Write-OutputColor "  Insufficient disk space on ${destDrive}\" -color "Error"
                        Write-OutputColor "  Available: ${freeGB} GB  |  Required: ${needGB} GB" -color "Error"
                        return @{ Success = $false; FilePath = $destFile; Error = "Insufficient disk space" }
                    }
                }
            }
        }

        # Consolidated download loop with retry
        $maxAttempts = if ($expectedSize -gt 500MB -and $script:MaxDownloadRetries) { $script:MaxDownloadRetries } else { 2 }
        $attempt = 0
        $downloadSuccess = $false
        $totalElapsed = 0

        while ($attempt -lt $maxAttempts -and -not $downloadSuccess) {
            $attempt++
            if ($attempt -gt 1) {
                Write-OutputColor "  Retrying download (attempt $attempt of $maxAttempts)..." -color "Warning"
                Remove-Item $destFile -Force -ErrorAction SilentlyContinue
            }

            # Background job using WebClient (closes connection immediately, no hang)
            $downloadJob = Start-Job -ScriptBlock {
                param($url, $headersJson, $destPath)
                try {
                    $webClient = New-Object System.Net.WebClient
                    if ($headersJson) {
                        $hdrs = $headersJson | ConvertFrom-Json
                        foreach ($prop in $hdrs.PSObject.Properties) {
                            $webClient.Headers.Add($prop.Name, $prop.Value)
                        }
                    }
                    $webClient.DownloadFile($url, $destPath)
                    $webClient.Dispose()
                    return @{ Success = $true; Error = $null }
                }
                catch {
                    return @{ Success = $false; Error = $_.Exception.Message }
                }
            } -ArgumentList $downloadUrl, ($downloadHeaders | ConvertTo-Json -Compress), $destFile

            # Monitor with progress bar and speed tracking
            $elapsed = 0
            $lastSize = 0
            $lastSpeedCheck = 0
            $speedBps = 0
            $staleSeconds = 0
            $spinChars = @('|', '/', '-', '\')
            $spinIndex = 0

            while ($downloadJob.State -eq "Running") {
                $currentSize = 0
                if (Test-Path $destFile) {
                    try { $currentSize = (Get-Item $destFile -ErrorAction SilentlyContinue).Length } catch { $currentSize = 0 }
                }

                # Update speed every 3 seconds
                if ($elapsed -gt 0 -and ($elapsed - $lastSpeedCheck) -ge 3) {
                    $bytesInInterval = $currentSize - $lastSize
                    $intervalSecs = $elapsed - $lastSpeedCheck
                    if ($intervalSecs -gt 0 -and $bytesInInterval -ge 0) {
                        $speedBps = $bytesInInterval / $intervalSecs
                    }
                    $lastSize = $currentSize
                    $lastSpeedCheck = $elapsed
                }

                # Hang detection: if file size >= expected for 5+ consecutive seconds, force-stop
                if ($expectedSize -gt 0 -and $currentSize -ge $expectedSize) {
                    $staleSeconds++
                    if ($staleSeconds -ge 5) {
                        Stop-Job $downloadJob -ErrorAction SilentlyContinue
                        Remove-Job $downloadJob -Force -ErrorAction SilentlyContinue
                        break
                    }
                } else {
                    $staleSeconds = 0
                }

                # Render progress bar
                if ($expectedSize -gt 0) {
                    Write-ProgressBar -CurrentBytes $currentSize -TotalBytes $expectedSize -SpeedBytesPerSec $speedBps -ElapsedSeconds $elapsed
                } else {
                    $spin = $spinChars[$spinIndex % 4]
                    $spinIndex++
                    Write-ProgressBar -CurrentBytes $currentSize -Activity "Downloading" -SpeedBytesPerSec $speedBps -ElapsedSeconds $elapsed -SpinChar $spin
                }

                Start-Sleep -Seconds 1
                $elapsed++

                if ($elapsed -gt $TimeoutSeconds) {
                    Stop-Job $downloadJob -ErrorAction SilentlyContinue
                    Remove-Job $downloadJob -Force -ErrorAction SilentlyContinue
                    Write-Host ""
                    return @{
                        Success = $false
                        Error = "Download timed out after $([math]::Floor($TimeoutSeconds / 60)) minutes."
                        FilePath = $null
                    }
                }
            }
            Write-Host ""
            $totalElapsed = $elapsed

            # Check job result (if not force-stopped due to hang detection)
            if ($downloadJob.Id) {
                $jobResult = Receive-Job $downloadJob -ErrorAction SilentlyContinue
                Remove-Job $downloadJob -Force -ErrorAction SilentlyContinue

                if ($jobResult -and -not $jobResult.Success) {
                    if ($attempt -ge $maxAttempts) {
                        return @{ Success = $false; Error = "Download failed: $($jobResult.Error)"; FilePath = $null }
                    }
                    continue
                }
            }

            # Verify file exists
            if (-not (Test-Path $destFile)) {
                if ($attempt -ge $maxAttempts) {
                    return @{ Success = $false; Error = "File not found after download."; FilePath = $null }
                }
                continue
            }

            # Check for error page (tiny file = likely HTML error)
            $fileSize = (Get-Item $destFile).Length
            if ($fileSize -lt 1000) {
                $content = Get-Content $destFile -Raw -ErrorAction SilentlyContinue
                if ($content -match "html|error|not found|denied|exception") {
                    Remove-Item $destFile -Force -ErrorAction SilentlyContinue
                    if ($attempt -ge $maxAttempts) {
                        return @{ Success = $false; Error = "Downloaded file appears to be an error response."; FilePath = $null }
                    }
                    continue
                }
            }

            # Size check against expected
            if ($expectedSize -gt 0 -and $fileSize -ne $expectedSize) {
                Write-OutputColor "  Size mismatch (local: $fileSize, expected: $expectedSize)." -color "Warning"
                if ($attempt -ge $maxAttempts) {
                    Remove-Item $destFile -Force -ErrorAction SilentlyContinue
                    return @{ Success = $false; Error = "File size mismatch after $maxAttempts attempts."; FilePath = $null }
                }
                continue
            }

            $downloadSuccess = $true
        }

        if (-not $downloadSuccess) {
            return @{ Success = $false; Error = "Download failed after $maxAttempts attempts."; FilePath = $null }
        }

        $fileSize = (Get-Item $destFile).Length

        # SHA256 integrity verification
        $integrity = Test-FileIntegrity -FilePath $destFile -ExpectedSize $expectedSize -RemoteFilePath $FilePath

        if (-not $integrity.Valid) {
            Write-OutputColor "  Integrity check failed: $($integrity.Error)" -color "Error"
            Remove-Item $destFile -Force -ErrorAction SilentlyContinue
            return @{ Success = $false; Error = "Integrity check failed: $($integrity.Error)"; FilePath = $null }
        }

        # Display completion summary
        Write-TransferComplete -TotalBytes $fileSize -ElapsedSeconds $totalElapsed -Hash $integrity.Hash -HashMatch $integrity.HashMatch

        return @{
            Success  = $true
            Error    = $null
            FilePath = $destFile
            FileSize = $fileSize
            Hash     = $integrity.Hash
        }
    }
    catch {
        return @{
            Success = $false
            Error = "Unexpected error: $_"
            FilePath = $null
        }
    }
}

# Get remote file size via HEAD request (for integrity checking)
function Get-FileServerFileSize {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    if (-not (Test-FileServerConfigured)) { return -1 }

    try {
        $url = Get-FileServerUrl -FilePath $FilePath

        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "HEAD"
        $request.Timeout = 15000

        $headers = Get-FileServerHeaders
        foreach ($key in $headers.Keys) {
            $request.Headers.Add($key, $headers[$key])
        }

        $response = $request.GetResponse()
        $size = $response.ContentLength
        $response.Close()
        return $size
    }
    catch {
        return -1
    }
}

# Download .sha256 companion file from FileServer (if it exists)
function Get-FileServerHashFile {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath
    )

    if (-not (Test-FileServerConfigured)) { return $null }

    try {
        $hashFilePath = "$FilePath.sha256"
        $url = Get-FileServerUrl -FilePath $hashFilePath

        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "GET"
        $request.Timeout = 10000

        $headers = Get-FileServerHeaders
        foreach ($key in $headers.Keys) {
            $request.Headers.Add($key, $headers[$key])
        }

        $response = $request.GetResponse()
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        $content = $reader.ReadToEnd().Trim()
        $reader.Close()
        $response.Close()

        # SHA256 file format: "hash  filename" or just "hash"
        $hash = ($content -split '\s+')[0].ToUpper()
        if ($hash -match '^[A-F0-9]{64}$') {
            return $hash
        }
        return $null
    }
    catch {
        return $null
    }
}

# Unified integrity verification: size check + SHA256 hash + remote hash comparison
# Saves a local .sha256 file for future re-verification
function Test-FileIntegrity {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$FilePath,

        [long]$ExpectedSize = 0,

        [string]$RemoteFilePath = ""
    )

    $result = @{
        Valid     = $true
        Hash      = $null
        RemoteHash = $null
        HashMatch = $null
        SizeMatch = $null
        Error     = $null
    }

    $localFile = Get-Item $FilePath -ErrorAction SilentlyContinue
    if (-not $localFile) {
        $result.Valid = $false
        $result.Error = "File not found"
        return $result
    }

    # Size check
    if ($ExpectedSize -gt 0) {
        if ($localFile.Length -ne $ExpectedSize) {
            $result.Valid = $false
            $result.SizeMatch = $false
            $result.Error = "Size mismatch (local: $($localFile.Length), expected: $ExpectedSize)"
            return $result
        }
        $result.SizeMatch = $true
    }

    # Compute SHA256 hash in background
    Write-OutputColor "  Verifying file integrity..." -color "Info"
    $result.Hash = Get-FileHashBackground -FilePath $FilePath

    # Try to get remote .sha256 hash file
    if ($RemoteFilePath) {
        $result.RemoteHash = Get-FileServerHashFile -FilePath $RemoteFilePath
    }

    # Compare hashes if remote hash was found
    if ($result.RemoteHash) {
        if ($result.Hash -eq $result.RemoteHash) {
            $result.HashMatch = $true
        } else {
            $result.HashMatch = $false
            $result.Valid = $false
            $result.Error = "SHA256 mismatch (local: $($result.Hash.Substring(0,16))..., remote: $($result.RemoteHash.Substring(0,16))...)"
        }
    }

    # Save local .sha256 file for future re-verification
    $hashFilePath = "$FilePath.sha256"
    try {
        "$($result.Hash)  $(Split-Path $FilePath -Leaf)" | Set-Content -Path $hashFilePath -Force -ErrorAction SilentlyContinue
    }
    catch {
        # Non-fatal: just skip saving hash file
    }

    return $result
}
#endregion
