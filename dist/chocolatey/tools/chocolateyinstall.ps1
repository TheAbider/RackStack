# Copyright (c) 2026 TheAbider. SPDX-License-Identifier: MIT
#
# Chocolatey install script for RackStack.
# Downloads RackStack.exe from the matching GitHub Release, verifies the
# SHA-256 hash against release-hashes.txt, and installs it under the
# package's `tools` directory (Chocolatey auto-shims so it's on PATH).

$ErrorActionPreference = 'Stop'
$toolsDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)"

$packageArgs = @{
    packageName    = 'rackstack'
    fileType       = 'exe'
    url64bit       = 'https://github.com/TheAbider/RackStack/releases/download/v__VERSION__/RackStack.exe'
    checksum64     = '__CHECKSUM_SHA256__'
    checksumType64 = 'sha256'

    # RackStack.exe is itself the deliverable, not an installer. We don't run
    # it during package install; just place the binary on disk and let
    # Chocolatey's shimgen create the PATH stub.
    silentArgs     = ''
    validExitCodes = @(0)
    # Use unzip-style placement: download the EXE directly to $toolsDir.
    fileFullPath   = Join-Path $toolsDir 'RackStack.exe'
    unzipLocation  = $toolsDir
}

Get-ChocolateyWebFile @packageArgs

# Create the shim explicitly so the binary appears on PATH as 'RackStack'.
# Chocolatey auto-shims .exe files in tools/ by default; this is belt-and-braces.
$exePath = Join-Path $toolsDir 'RackStack.exe'
Install-BinFile -Name 'RackStack' -Path $exePath
