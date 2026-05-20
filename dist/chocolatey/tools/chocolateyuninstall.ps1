# Copyright (c) 2026 TheAbider. SPDX-License-Identifier: MIT
#
# Chocolatey uninstall script — removes the shimmed RackStack PATH entry.
# The EXE itself is removed by Chocolatey's package-cleanup pass after this
# script returns.

$ErrorActionPreference = 'Stop'

# Remove the explicit shim created by Install-BinFile in chocolateyinstall.ps1.
# Chocolatey's auto-shim cleanup handles the default case, but the explicit
# remove keeps things tidy.
Uninstall-BinFile -Name 'RackStack' -ErrorAction SilentlyContinue
