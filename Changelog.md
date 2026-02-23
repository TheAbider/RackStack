# Changelog

## v1.2.0

- **Custom SET vNICs:** New `Add-CustomVNIC` function replaces hardcoded Backup NIC — create any named virtual NIC on the SET switch with optional VLAN (1-4094) and inline IP configuration; preset names (Backup, Cluster, Live Migration, Storage) or custom; `Add-MultipleVNICs` wrapper for creating several in one session; `Add-BackupNIC` preserved as backward-compatible wrapper
- **iSCSI A/B Side Ping Check:** New `Test-iSCSICabling` function auto-detects which physical adapter connects to A-side vs B-side SAN switches by temporarily assigning IPs and pinging all SAN targets; displays results table with per-adapter A/B side hit counts; warns on same-side cabling, both-sides-reachable, or no-connectivity scenarios
- **iSCSI Auto-Config Integration:** `Set-iSCSIAutoConfiguration` now runs the cabling ping check before manual A/B selection — if auto-detect succeeds, offers to skip manual selection; batch mode iSCSI step also uses auto-detection with fallback to adapter order
- **Batch Mode Custom vNICs:** New `CustomVNICs` batch config key (array of `{Name, VLAN}` objects) creates virtual NICs on SET during batch mode; new Step 17 between SET creation and iSCSI configuration; total batch steps increased from 19 to 20
- **Batch Config from State:** `Export-BatchConfigFromState` now detects existing non-Management vNICs on the SET switch and populates `CustomVNICs` array
- **iSCSI Menu Expanded:** New option [3] "Test iSCSI Cabling (A/B side check)" in iSCSI & SAN Management menu; existing options renumbered [3]-[7] → [4]-[8]
- **Menu Rename:** Host Network menu option [2] renamed from "Add Backup NIC to SET" to "Add Virtual NIC to SET"
- **Agent Folder Rename:** `FileServer.KaseyaFolder` config key renamed to `FileServer.AgentFolder` with default `"Agents"` (was `"KaseyaAgents"`); `AgentInstaller.FolderName` default updated to match; backward-compatible — existing `defaults.json` files with `KaseyaFolder` are auto-migrated on import
- **defaults.example.json:** Added `CustomVNICs` section; renamed `KaseyaFolder` to `AgentFolder`

## v1.1.0

- **Dynamic Defender Paths:** Defender exclusion paths now auto-generate from selected host drive instead of hardcoded D:/E: paths; updated on Host Storage initialization and configurable via `defaults.json`
- **Batch Mode HOST Extensions:** 5 new batch steps (15-19) for full host builds: Host Storage, SET Switch, iSCSI, MPIO, and Defender Exclusions; new HOST-specific batch config keys (`CreateSETSwitch`, `ConfigureiSCSI`, `ConfigureMPIO`, `InitializeHostStorage`, `ConfigureDefenderExclusions`)
- **Batch Config from State:** New "Generate from Current Server State" option in batch config menu — detects live configuration and produces a pre-filled `batch_config.json` for cloning to similar servers
- **Executable Favorites:** Favorites now store and invoke the underlying function directly; selecting a favorite runs the action instead of just showing the menu path
- **Configuration Drift Detection:** New drift check in Operations menu compares live server state against a saved profile and highlights drifted settings (hostname, IP, DNS, domain, timezone, RDP, WinRM, power plan, installed features)
- **Operations Menu:** Added Configuration Drift Check option [12]

## v1.0.18

- **Maintenance:** Minor refinements and cleanup

## v1.0.17

- **Test Coverage:** 123 new tests across 8 sections (94-101) covering Windows Updates, Local Admin, Disable Admin, Host Storage, Exit Cleanup, Config Export, QoL Features, and Operations Menu — total now 1187
- **Repo Cleanup:** Reorganized local-only files into `local/` directory, simplified `.gitignore`, removed tool-identifying entries

## v1.0.16

- **Branding Assets:** Added banner, social preview, icon SVG/PNGs, and favicon to `.github/assets/`; README now uses the banner image
- **Self-Hosted CI:** GitHub Actions workflow now uses self-hosted runner for pushes (faster), GitHub-hosted for PRs (safe from forks); PSScriptAnalyzer install skipped if already present

## v1.0.15

- **Config Documentation:** Rewrote `defaults.example.json` with comprehensive beginner-friendly comments on every field — each setting now has a `_help` explanation, examples, and field references for complex sections (VMNaming, AgentInstaller, CustomVMTemplates)
- **New Icon:** Replaced app icon with server rack design

## v1.0.14

- **FileServer Rename:** Renamed `AbiderCloud` to `FileServer` across all modules, config keys, functions, tests, and docs for cleaner generic branding
- **Exit Cleanup Fix:** Cleanup now properly targets EXE files, monolithic `v*.ps1` naming, adjacent config files, and the app config directory (session/audit logs)

## v1.0.13

- **Generic VM Templates:** Replaced work-specific built-in templates with 3 universal ones (DC, FS, WEB); add custom templates via `CustomVMTemplates` in `defaults.json`
- **Configurable VM Naming:** New `VMNaming` config key with token-based patterns (`{Site}-{Prefix}{Seq}`), configurable site ID source, detection regex, and zero-padded sequences
- **Linux VHD Guide:** New cloud-init VHD preparation guide alongside the Windows Sysprep guide in VHD Management menu
- **Dynamic Agent Naming:** All user-facing agent installer text now uses `$script:AgentInstaller.ToolName` instead of hardcoded names
- **Wiki Updates:** New VHD Preparation page; VM deployment runbook updated with generic templates and configurable naming examples; iSCSI docs note configurability of subnet/targets

## v1.0.12

- **Auto-Update on Startup:** New `AutoUpdate` flag in `defaults.json` — when enabled, automatically downloads and installs updates on startup without prompting; deferred retry if no network at launch (triggers after network is configured)

## v1.0.11

- **Console Auto-Sizing Fix:** `Initialize-ConsoleWindow` now actually called on startup; maximizes window via Win32 API, expands buffer width to match screen, and resizes console to fill available space — works for both PS1 and EXE

## v1.0.10

- **Test Coverage Expansion:** 4 new test sections (90-93) covering VM Checkpoint Management, Batch Config Template Structure, FileServer Function Coverage, and Agent Installer Configuration — ~50 new tests, total 1040+

## v1.0.9

- **Refactor New-DeployedVM:** Split 320-line monolith into 8 focused helpers (`Resolve-VMStoragePaths`, `New-VMDirectories`, `New-VMShell`, `New-VMDisk`, `New-VMDisks`, `Set-VMNetworkConfig`, `Set-VMAdvancedConfig`, `Register-VMInCluster`); orchestrator is now ~60 lines
- **Remote Pre-flight Checks:** New `Test-RemoteReadiness` runs 5-step connectivity check (ping, WinRM port, WSMan, credentials, PS version); `Show-PreflightResults` displays results; integrated into `Invoke-RemoteProfileApply`

## v1.0.8

- **Configurable Agent Installer:** Generalized Kaseya installer into MSP-agnostic framework; tool name, service name, file pattern, install args, paths, exit codes, and timeout all configurable via `AgentInstaller` in `defaults.json`
- **Extract Hardcoded Values:** SAN target IP mappings, Defender exclusion paths, storage paths, and temp directory now configurable via `defaults.json` (with built-in fallback defaults)
- **Batch Mode Validation:** New `Test-BatchConfig` pre-flight validator catches config errors (invalid IPs, hostnames, CIDR, booleans, power plans, missing gateway) before batch execution starts
- **defaults.example.json:** Added `AgentInstaller`, `SANTargetMappings`, `DefenderExclusionPaths`, `DefenderCommonVMPaths`, `StoragePaths`, `TempPath` examples
- **Tests:** 15 new batch validation tests (Section 87)

## v1.0.7

- **EXE Fix:** Monolithic build-from-scratch now appends `Assert-Elevation` entry point (fixes exe opening and immediately closing)
- **EXE Icon:** `release.ps1` now passes `-IconFile` to ps2exe for both repo and cross-repo compilation
- **EXE Update:** Self-update uses `[Environment]::Exit(0)` instead of bare `exit` for ps2exe compatibility
- **Error Handling Audit:** Removed 12 redundant `try/catch` blocks around `-ErrorAction SilentlyContinue` calls; added warning messages to 4 silent file I/O catch blocks (favorites, history, session, VM defaults)
- **Inline Docs:** Added `# --- Section: ---` comments to 4 complex functions: `Register-ServerLicense`, `Install-KaseyaAgent`, `Set-SNMPConfiguration`, `Set-PagefileConfiguration`
- **Troubleshooting Guide:** New `docs/Troubleshooting.md` covering VM deployment, iSCSI/SAN, cluster, and common errors
- **Operations Runbooks:** New `docs/Runbook-VM-Deployment.md`, `docs/Runbook-Host-Migration.md`, `docs/Runbook-HA-iSCSI.md`

## v1.0.6

- **GitHub Actions CI:** Automated test suite (949 tests), PSScriptAnalyzer, and monolithic sync on every push and PR
- **Build from Scratch:** `sync-to-monolithic.ps1` now generates the monolithic from scratch when it doesn't exist (enables CI)
- **CI-Safe Tests:** `defaults.json` tests skip gracefully when the file is absent (gitignored in public repo)
- **Dynamic Badge:** README test badge now reflects live CI status

## v1.0.5

- **Configurable VM Templates:** Override built-in VM template specs (CPU, RAM, disks) or add entirely new templates via `CustomVMTemplates` in `defaults.json`
- **Custom VM Defaults:** Configure default vCPU, RAM, memory type, disk size, and disk type for non-template VMs via `CustomVMDefaults`
- **Partial Overrides:** Change only the fields you want -- unspecified fields keep their built-in values
- **Re-Import Safe:** Built-in templates are snapshotted on first import and restored before each re-merge
- **Disk Conversion:** JSON-parsed disk arrays automatically converted from PSCustomObject to hashtable
- **Tests:** 934 tests across 86 sections (29 new for template merge)

## v1.0.4

- **Fix:** `$script:ModuleRoot` detection in compiled EXE mode -- `$PSScriptRoot` is empty in ps2exe, now falls back to process executable path

## v1.0.3

- **Auto-Update Check:** RackStack checks for updates on startup and shows a banner on the main menu when a new version is available
- **[U] Quick Update:** Press U on the main menu to download and install updates
- **Custom Icon:** RackStack.exe now has its own icon
- **EXE Self-Update Fix:** Fixed script path detection in compiled EXE mode
- **Deferred Retry:** If no network at startup, update check retries when main menu is displayed (throttled to 60s)
- **Scan Fixes:** Resolved GitHub Actions secret scanner false positives

## v1.0.2

- **WMF 5.1 Bootstrap:** `Install-Prerequisites.ps1` auto-downloads and installs WMF 5.1 for Server 2008 R2 SP1 / 2012
- **OS Support Expanded:** Now spans Server 2008 R2 SP1 through 2025
- **Bootstrap:** Checks .NET 4.5.2+ requirement, handles TLS, detects OS, downloads correct MSU

## v1.0.1

- **First-Run Wizard:** Generates `defaults.json` interactively on first launch
- **Auto-Update:** Checks GitHub releases and self-updates (exe and ps1)
- **Server 2012 R2 Support:** SET/StorageReplica/Defender guards for older OS
- **Version Consistency:** All version references dynamically derived
- **Header Sync:** `sync-to-monolithic.ps1` now syncs Header.ps1 into builds

## v1.0.0

- Initial open source release
- 59 modules, 905 tests, 0 PSSA errors
- Full feature set: networking, Hyper-V, VM deployment, storage, monitoring, batch mode
