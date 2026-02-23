param(
    [switch]$DryRun
)

$modulesDir = Join-Path $PSScriptRoot "Modules"
$utf8Bom = New-Object System.Text.UTF8Encoding $true

# Derive monolithic filename from defaults.json (or fall back to reading version from 00-Initialization.ps1)
$defaultsJsonPath = Join-Path $PSScriptRoot "defaults.json"
$toolFullName = "RackStack"
$scriptVersion = "1.0.0"
if (Test-Path $defaultsJsonPath) {
    try {
        $dj = Get-Content $defaultsJsonPath -Raw | ConvertFrom-Json
        if ($dj.ToolFullName) { $toolFullName = $dj.ToolFullName }
    } catch { }
}
# Read version from 00-Initialization.ps1
$initFile = Join-Path $modulesDir "00-Initialization.ps1"
if (Test-Path $initFile) {
    $initContent = Get-Content $initFile -Raw
    if ($initContent -match '\$script:ScriptVersion\s*=\s*"([^"]+)"') {
        $scriptVersion = $Matches[1]
    }
}
$monoPath = Join-Path (Split-Path $PSScriptRoot) "$toolFullName v$scriptVersion.ps1"

# If monolithic doesn't exist, build from scratch (Header + modules)
if (-not (Test-Path $monoPath)) {
    Write-Host "Monolithic not found - building from scratch..."
    $lines = [System.Collections.Generic.List[string]]::new()

    # Header
    $headerPath = Join-Path $PSScriptRoot "Header.ps1"
    if (Test-Path $headerPath) {
        $lines.AddRange([System.IO.File]::ReadAllLines($headerPath, $utf8Bom))
    }

    # Modules in order
    $initModuleFiles = Get-ChildItem $modulesDir -Filter "*.ps1" | Sort-Object Name
    foreach ($file in $initModuleFiles) {
        if ($file.Name -eq "55-QoLFeatures.ps1") {
            # Start of shared QoL region - omit #endregion (last line)
            $mod = [System.IO.File]::ReadAllLines($file.FullName, $utf8Bom)
            $lines.AddRange([string[]]$mod[0..($mod.Count - 2)])
            continue
        }
        if ($file.Name -eq "56-OperationsMenu.ps1") {
            # Continuation of shared QoL region - omit #region (first line)
            $mod = [System.IO.File]::ReadAllLines($file.FullName, $utf8Bom)
            $lines.Add("")
            $lines.AddRange([string[]]$mod[1..($mod.Count - 1)])
            continue
        }
        $lines.AddRange([System.IO.File]::ReadAllLines($file.FullName, $utf8Bom))
    }

    # Append entry point call (in modular mode this is in RackStack.ps1)
    $lines.Add("")
    $lines.Add("# Start the tool")
    $lines.Add("Assert-Elevation")

    [System.IO.File]::WriteAllLines($monoPath, $lines.ToArray(), $utf8Bom)
    Write-Host "Built monolithic from scratch: $($lines.Count) lines" -ForegroundColor Green

    # Verify parse
    $errors = $null
    [System.Management.Automation.PSParser]::Tokenize(([System.IO.File]::ReadAllText($monoPath, $utf8Bom)), [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        Write-Host "PARSE ERRORS: $($errors.Count)" -ForegroundColor Red
        foreach ($e in $errors | Select-Object -First 5) {
            Write-Host "  Line $($e.Token.StartLine): $($e.Message)" -ForegroundColor Red
        }
        exit 1
    } else {
        Write-Host "Parse check: PASSED (0 errors)" -ForegroundColor Green
    }
    return
}

# Read monolithic as array of lines
$monoLines = [System.IO.File]::ReadAllLines($monoPath, $utf8Bom)
Write-Host "Monolithic: $($monoLines.Count) lines"

# Get all module files in order
$moduleFiles = Get-ChildItem $modulesDir -Filter "*.ps1" | Sort-Object Name

# Special cases: 55-QoLFeatures and 56-OperationsMenu share the QOL region
# Module 55 = first half, Module 56 = second half (gets #region prepended)
# We'll handle these specially

# Build region map from monolithic: region name -> (startLine, endLine) 0-indexed
$regionMap = [ordered]@{}
for ($i = 0; $i -lt $monoLines.Count; $i++) {
    if ($monoLines[$i] -match '^#region\s+(.+)$') {
        $regionName = $Matches[1].Trim()
        # Find matching #endregion
        for ($j = $i + 1; $j -lt $monoLines.Count; $j++) {
            if ($monoLines[$j] -match '^#endregion') {
                $regionMap[$regionName] = @{ Start = $i; End = $j; Name = $regionName }
                break
            }
        }
    }
}

Write-Host "Found $($regionMap.Count) regions in monolithic"

# Build module -> region mapping
$moduleRegionMap = @{}
$skipModules = @()

foreach ($file in $moduleFiles) {
    $firstLine = (Get-Content $file.FullName -First 1).Trim()
    if ($firstLine -match '^#region\s+(.+)$') {
        $regionName = $Matches[1].Trim()
        $moduleRegionMap[$file.Name] = $regionName
    } else {
        Write-Host "SKIP: $($file.Name) - no #region header" -ForegroundColor Yellow
        $skipModules += $file.Name
    }
}

# Special handling for QoL split (55/56)
$qolRegionName = "===== QOL FEATURES (v2.8.0) ====="

# Process replacements from bottom to top (to preserve line numbers)
$replacements = @()

foreach ($file in $moduleFiles) {
    if ($file.Name -in $skipModules) { continue }

    $regionName = $moduleRegionMap[$file.Name]

    # Skip 55 and 56 - handle them together later
    if ($file.Name -eq "55-QoLFeatures.ps1" -or $file.Name -eq "56-OperationsMenu.ps1") {
        continue
    }

    if (-not $regionMap.Contains($regionName)) {
        Write-Host "WARNING: Region '$regionName' from $($file.Name) not found in monolithic!" -ForegroundColor Red
        continue
    }

    $region = $regionMap[$regionName]
    $moduleContent = [System.IO.File]::ReadAllLines($file.FullName, $utf8Bom)

    $replacements += @{
        File = $file.Name
        Region = $regionName
        Start = $region.Start
        End = $region.End
        Content = $moduleContent
    }
}

# Handle QoL split: modules 55 + 56 -> single QOL region
if ($regionMap.Contains($qolRegionName)) {
    $qolRegion = $regionMap[$qolRegionName]
    $mod55Path = Join-Path $modulesDir "55-QoLFeatures.ps1"
    $mod56Path = Join-Path $modulesDir "56-OperationsMenu.ps1"

    if ((Test-Path $mod55Path) -and (Test-Path $mod56Path)) {
        $mod55Content = [System.IO.File]::ReadAllLines($mod55Path, $utf8Bom)
        $mod56Content = [System.IO.File]::ReadAllLines($mod56Path, $utf8Bom)

        # Module 55 has the #region header; module 56 has its own #region header that we strip
        # Combined: mod55 content (including its #region but NOT its #endregion) + blank line + mod56 content (stripping its #region, keeping its #endregion which becomes the combined #endregion)
        $combined = @()
        # Add all of mod55 except the last line (#endregion)
        $combined += $mod55Content[0..($mod55Content.Count - 2)]
        $combined += ""
        # Add all of mod56 except the first line (#region)
        $combined += $mod56Content[1..($mod56Content.Count - 1)]

        $replacements += @{
            File = "55+56 (QoL combined)"
            Region = $qolRegionName
            Start = $qolRegion.Start
            End = $qolRegion.End
            Content = $combined
        }
    }
}

# Sort replacements by start line descending (process from bottom up)
$replacements = $replacements | Sort-Object { $_.Start } -Descending

Write-Host ""
Write-Host "Replacements to apply: $($replacements.Count)" -ForegroundColor Cyan

foreach ($r in $replacements) {
    $oldSize = $r.End - $r.Start + 1
    $newSize = $r.Content.Count
    $diff = $newSize - $oldSize
    $diffStr = if ($diff -gt 0) { "+$diff" } elseif ($diff -lt 0) { "$diff" } else { "0" }
    Write-Host "  $($r.File) -> lines $($r.Start+1)-$($r.End+1) ($oldSize -> $newSize lines, $diffStr)" -ForegroundColor $(if ($diff -eq 0) { "Gray" } else { "Yellow" })
}

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN - no changes made" -ForegroundColor Yellow
    return
}

# Apply replacements (bottom-up so line numbers stay valid)
$result = [System.Collections.Generic.List[string]]::new($monoLines)

foreach ($r in $replacements) {
    # Remove old region
    $result.RemoveRange($r.Start, $r.End - $r.Start + 1)
    # Insert new content
    $result.InsertRange($r.Start, [string[]]$r.Content)
}

# Sync Header.ps1 (everything before the first #region)
$headerPath = Join-Path $PSScriptRoot "Header.ps1"
if (Test-Path $headerPath) {
    $headerContent = [System.IO.File]::ReadAllLines($headerPath, $utf8Bom)
    # Find first #region in result
    $firstRegionLine = -1
    for ($i = 0; $i -lt $result.Count; $i++) {
        if ($result[$i] -match '^#region\s+') {
            $firstRegionLine = $i
            break
        }
    }
    if ($firstRegionLine -gt 0) {
        $oldHeaderSize = $firstRegionLine
        $result.RemoveRange(0, $firstRegionLine)
        $result.InsertRange(0, [string[]]$headerContent)
        $newHeaderSize = $headerContent.Count
        Write-Host "  Header.ps1 -> lines 1-$oldHeaderSize ($oldHeaderSize -> $newHeaderSize lines)" -ForegroundColor $(if ($oldHeaderSize -eq $newHeaderSize) { "Gray" } else { "Yellow" })
    }
}

# Ensure entry point call exists at the end (in modular mode this is in RackStack.ps1)
$lastNonBlank = ""
for ($i = $result.Count - 1; $i -ge 0; $i--) {
    if ($result[$i].Trim()) { $lastNonBlank = $result[$i].Trim(); break }
}
if ($lastNonBlank -ne "Assert-Elevation") {
    $result.Add("")
    $result.Add("# Start the tool")
    $result.Add("Assert-Elevation")
    Write-Host "  Appended missing Assert-Elevation entry point" -ForegroundColor Yellow
}

# Write result
[System.IO.File]::WriteAllLines($monoPath, $result.ToArray(), $utf8Bom)
$finalCount = $result.Count
Write-Host ""
Write-Host "Monolithic updated: $($monoLines.Count) -> $finalCount lines" -ForegroundColor Green

# Verify parse
$errors = $null
[System.Management.Automation.PSParser]::Tokenize(([System.IO.File]::ReadAllText($monoPath, $utf8Bom)), [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    Write-Host "PARSE ERRORS: $($errors.Count)" -ForegroundColor Red
    foreach ($e in $errors | Select-Object -First 5) {
        Write-Host "  Line $($e.Token.StartLine): $($e.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "Parse check: PASSED (0 errors)" -ForegroundColor Green
}
