# Changelog

## v1.9.11

- **Bug Fix:** Cluster dashboard node drain/resume used `.Count` on unguarded `Where-Object` results — wrapped in `@()` for consistent array handling.
- **Bug Fix:** Firewall template status display `.Count` on single-rule groups wrapped in `@()`.
- **Bug Fix:** Defender exclusion array wrapping now handles null `ExclusionPath`/`ExclusionProcess` correctly (prevents `@($null)` creating a 1-element array).
- 63 modules, 1854 tests

## v1.9.10

- **Bug Fix:** Firewall readiness check in health report compared strings ("Enabled"/"Disabled") as booleans — always showed incorrect firewall state. Fixed in both health check and batch mode idempotency.
- **Bug Fix:** Defender exclusion count arithmetic failed when only one exclusion path or process was configured (single string has no `.Count`). Wrapped in `@()`.
- 63 modules, 1854 tests

## v1.9.9

- **Bug Fix:** CPU dashboard null-safe when `Measure-Object` returns no average (edge case on inaccessible WMI).
- **Bug Fix:** Ping average in network diagnostics null-safe when `Measure-Object` has no data.
- **Bug Fix:** SET adapter connectivity results wrapped as array for consistent `.Count` behavior.
- 63 modules, 1854 tests

## v1.9.8

- **Bug Fix:** Deduplication status query now passes the volume with drive letter colon (e.g., `D:`) — was silently failing on the status display.
- **Bug Fix:** VM export size display handles null or missing VHD sizes gracefully instead of crashing on divide-by-null.
- **Bug Fix:** VHD cache size mismatch now prompts the user before deleting, instead of silently removing the cached file.
- **Hardened:** Array handling for single-item results in Failover Clustering, Storage Replica, and Hyper-V Replica modules — prevents fragile single-object vs array behavior across PowerShell versions.
- 63 modules, 1854 tests

## v1.9.7

- **Edit Defaults Expanded:** Settings > Edit Environment Defaults now includes Auto-Update toggle [10], Temp Path [11], and Timezone Region selector [12]. Reset also covers the new fields.
- **Release Validation:** Moved `Validate-Release.ps1` from `Tests/` to `local/` (gitignored) — content integrity scan methodology is no longer exposed in the public repo.
- 63 modules, 1856 tests

## v1.9.6

- **Bug Fix:** Disk cleanup now only counts freed space for files that were actually deleted, instead of counting all attempted files regardless of success.
- **Bug Fix:** First-run wizard auto-adopts company defaults without prompting — single company file is auto-loaded, multiple files show a picker then auto-adopt. Only shows the full configuration wizard when no company defaults exist.
- **Transcript Cleanup:** Added size-based safety check — if transcript directory exceeds 500MB, oldest files are removed regardless of age to prevent disk fill.
- 63 modules, 1856 tests

## v1.9.5

- **World Timezones:** Timezone selection expanded from 11 US-only options to 58 curated timezones across 7 continent-based regions (North America, South America, Europe, Africa, Asia, Oceania/Pacific, UTC). Includes a "Show all system timezones" browser with pagination.
- **TimeZoneRegion Default:** New `TimeZoneRegion` setting in `defaults.json` to skip the continent picker and jump straight to a specific region — useful for orgs that always deploy to one region.
- **Bug Fix:** Disk space check in file downloads no longer skips the check when a volume has exactly 0 bytes free.
- **Bug Fix:** Audit log rotation failures are now logged instead of being silently swallowed.
- **Test Coverage:** Added Server Role Templates (Module 60) test section with 35 tests covering function existence, built-in template definitions, template structure, status checking, and install behavior.
- 63 modules, 1856 tests

## v1.9.4

- **Release Validation:** Added documentation integrity checks (vendor-specific filenames in docs, hardcoded version numbers in README) and UTF-8 BOM verification for all module files to pre-release validation pipeline.
- **Bug Fix:** Batch mode agent install no longer hangs on interactive prompts — uses `-Unattended` switch for non-interactive site detection and silent install.
- **Bug Fix:** Searching for "0" in agent installer no longer matches every agent (zero-normalization guard).
- **Null Safety:** Added null checks for CIM queries in health check, IP address state validation, and timezone display to prevent crashes on inaccessible systems.
- **Docs:** Generalized all fileserver guide examples from vendor-specific agent filenames to generic `Agent_org` convention.
- 63 modules, 1821 tests

## v1.9.3

- **Agent Search:** Partial matching for site number searches — searching "39" now finds sites 390, 391, etc. Also searches site names and raw filenames as fallback.
- **Agent Filename Parser:** More flexible regex that works with any prefix format (no longer requires exact `Tool_Org` pattern). Fallback extracts 3+ digit sequences from anywhere in the filename.
- **Agent List Display:** Agents with unparsed names now show the filename instead of "(unknown)". Site number column handles empty values gracefully.
- **Generalized Changelog:** Replaced remaining vendor-specific references in Header.ps1 changelog entries with generic agent terminology.
- **Generalized Tests:** All test mock data and parser test cases now use generic `Agent_org` filenames instead of vendor-specific ones.
- 63 modules, 1821 tests

## v1.9.2

- **Generalized Agent Installer:** Renamed module `57-KaseyaInstaller` to `57-AgentInstaller`; renamed `Install-KaseyaAgent` function to `Install-Agent`; generalized filename parser to support any `<Tool>_<org>.{numbers}-{name}.exe` convention (not just Kaseya format)
- **Feature Availability Guards:** Agent installer menu, readiness checks, quick setup wizard, batch mode, and domain join agent prompt now check `Test-AgentInstallerConfigured` before showing agent-related options. Features show "Not Configured" when FileServer or agent config is missing instead of non-functional menu items.
- **Security:** Replaced personal email in SECURITY.md with GitHub Security Advisories link
- **Vendor Neutral:** Removed all vendor-specific variable names and comments from modules, tests, and menu display code
- 63 modules, 1812 tests, backward compatible with all existing configs

## v1.9.1

- **Bug Fix:** Company defaults prompt no longer appears when `defaults.json` already exists — only prompts on first run or when no personal defaults are configured. Silently reloads previously selected company file via `_companyDefaults` metadata.
- **Agent Installer:** Built-in default agent name changed from vendor-specific to generic "MSP". Override via `AgentInstaller.ToolName` in defaults.json or company defaults.
- 63 modules, 1806 tests

## v1.9.0

- **Company Defaults:** New three-tier configuration system — built-in defaults can be overlaid with a company-wide `<name>.defaults.json` file, then personal `defaults.json` overrides on top. Supports multiple company config files with a startup picker.
- **First-Run Wizard Updated:** Detects available company defaults files and offers to adopt them during initial setup, pre-populating the wizard with company values.
- **Edit Defaults Menu [9]:** New "Company Defaults" option in Settings > Edit Environment Defaults to switch, clear, or browse available company configurations.
- **Export Protection:** `Export-Defaults` never overwrites company files — always writes to personal `defaults.json` only. Tracks active company config via `_companyDefaults` metadata.
- 63 modules, 1806 tests, backward compatible with all existing configs

## v1.8.3

- **Bug Fix Sweep:** Fixed 29 bugs across 18 modules identified during full codebase audit
- **Reboot Detection Fixed:** `Test-RebootPending` now correctly detects pending file renames via registry value lookup (was checking for registry key, always returned false)
- **Property Dedup Fixed:** Profile comparison in Utilities and HTML Reports now correctly deduplicates properties by name (was comparing PSPropertyInfo objects against strings)
- **Scope Fixes:** Virtual switch creation uses explicit `$script:` prefix for switch/management names; config export uses scoped variables for domain, local admin, and display name
- **Windows Update Timeout Fixed:** Timed-out update jobs now properly stopped (was logging "Stopping job" without calling Stop-Job)
- **IPv4-Safe IP Removal:** IP reconfiguration now specifies `-AddressFamily IPv4` to prevent accidental IPv6 removal
- **Empty Domain Guard:** Domain join no longer offers empty default when no domain is configured
- **BitLocker Key Backup Fixed:** Backup to AD now filters for RecoveryPassword key protector type (was using hardcoded index)
- **SecureString Handling:** BSTR pointers now use correct `PtrToStringBSTR` method; cloud witness access key cleared from memory after use
- **Division-by-Zero Guards:** Cluster dashboard CSV percentage calculations protected against zero-size partitions
- **IP Sort Fixed:** Network sweep results sorted by proper octet comparison instead of fragile `[version]` cast
- **Favorite Deletion Fixed:** Uses index-based removal instead of reference equality on deserialized objects
- **Input Validation:** Metric collection interval/duration validated before `[int]` cast
- **Dead Code Removed:** Eliminated no-op branch in update check, unused CSV state query
- **Convention Compliance:** `$matches` → `$regexMatches` in 4 modules (09-SET, 44-VMDeployment, 57-AgentInstaller)
- **UI Fixes:** Hostname help text corrected (digits valid as first char), box border PadRight fixed in Cluster Dashboard, hardcoded retry count now dynamic, undo stack uses RemoveAt(), StorageReplica sync display shows "N/A" instead of "N/A%"
- **Documentation Updated:** README version references, test counts, and line counts updated; CONTRIBUTING.md test count corrected; duplicate JSON key fixed in defaults.example.json; AdditionalAgents help text added; Changelog stats footers added for v1.4.0/v1.4.1; embedded changelog "(Current)" label removed
- 63 modules, 1787 tests, backward compatible with all existing configs

## v1.8.2

- **Pre-release History:** Added detailed changelog entries for 11 pre-release versions (v0.1.0 through v0.10.0) covering the tool's development history before the v1.0.0 open-source release — iSCSI auto-configuration, VM deployment system, storage manager, batch mode, configuration profiles, licensing, and more
- 63 modules, 1787 tests, backward compatible with all existing configs

## v1.8.1

- **Changelog Standardization:** Consistent format across all 30+ version entries — every entry now has a stats footer (modules, tests), flattened bug fix lists, missing v1.5.9 entry added, pre-release origin section added
- **Release Validation Expanded:** `Validate-Release.ps1` now checks changelog format — verifies current version has an entry, is the top entry, has feature bullets, has stats footer, and no empty sections
- 63 modules, 1787 tests, backward compatible with all existing configs

## v1.8.0

- **Multi-Agent Installer Support:** Configure and manage multiple MSP agents from a single menu — `Get-AllAgentConfigs` combines primary and additional agents defined in `defaults.json`; `Show-AgentManagement` displays status of all agents with per-agent install/uninstall; `Test-AgentInstalledByConfig` provides generic service/path detection for any agent; batch mode supports `InstallAgents` array field (backward compatible with `InstallAgent` boolean); 24 total batch steps
- **Cluster CSV Prep Automation:** Pre-flight readiness checks and CSV validation for failover clusters — `Test-ClusterReadiness` verifies all nodes online, quorum healthy, CSVs online (no redirected I/O), and cluster networks up; `Initialize-ClusterCSV` reports on existing CSV space and health; Cluster Operations submenu adds [5] Readiness Check and [6] CSV Validation; batch mode `ValidateCluster` flag runs checks between clustering and local admin steps
- **Updated Documentation:** README refreshed with full feature list, updated architecture, and current test/module counts; CONTRIBUTING.md updated with current pull request checklist and code style guidelines; `defaults.example.json` includes `AdditionalAgents` example
- 63 modules, 1787 tests, backward compatible with all existing configs

## v1.7.1

- **Drift Detection Persistence:** Save and compare configuration baselines over time — `Save-DriftBaseline` captures full server state as JSON; `Compare-DriftHistory` diffs any two baselines; `Show-DriftTrend` shows timeline of changes; Operations menu [12] now opens Drift Detection submenu; auto-saves baseline after batch mode
- **Performance Trend Reports:** Capture performance snapshots and generate trend reports — `Save-PerformanceSnapshot` records CPU, RAM, disk, and network metrics as JSON; `Export-HTMLTrendReport` generates self-contained HTML with CSS bar charts and "days until full" disk estimates; `Start-MetricCollection` for interval-based monitoring; Operations menu adds [13]-[15] metrics items
- 63 modules, 1763 tests, backward compatible with all existing configs

## v1.7.0

- **Expanded Health Dashboard:** 5 new sections in System Health Check — disk I/O latency per physical disk (red >20ms, yellow >10ms), NIC error counters, memory pressure (Pages/sec and Available MBytes), Hyper-V guest health per running VM, and top 5 CPU processes; all sections mirrored in HTML health report
- **Download Resilience:** Large file downloads (>500MB) now retry up to 3 times (configurable via `$script:MaxDownloadRetries`); BITS transfer support flag for future native resume capability
- 63 modules, 1734 tests, backward compatible with all existing configs

## v1.6.1

- **VM Pre-flight Validation:** Expanded resource checks before VM deployment — validates disk space, RAM availability, vCPU ratio (warn >4:1, fail >8:1), VM switch existence, and VHD source accessibility; formatted table with OK/WARN/FAIL status; blocks deployment on FAIL
- **VM Post-Deploy Smoke Tests:** Automated health verification after VM creation — checks VM running state, heartbeat, NIC connectivity, guest IP acquisition (polls up to 120s), ping, and RDP port 3389 reachability; batch deployment offers smoke tests at completion
- 63 modules, 1714 tests, backward compatible with all existing configs

## v1.6.0

- **Batch Mode Idempotency:** All 22 batch steps now check if the target state already exists before making changes — re-running the same config skips completed steps with "already configured" messages; summary shows changed/skipped/failed counts
- **Batch Transaction Rollback:** Reversible batch steps register undo actions — on failure, prompts to roll back all completed changes; 11 reversible steps (hostname, IP, timezone, RDP, WinRM, firewall, power plan, local admin, vSwitch, vNICs, Defender); `Invoke-BatchUndo` executes undo stack in reverse order
- 63 modules, 1693 tests, backward compatible with all existing configs

## v1.5.10

- **Test Fixture Cleanup:** Refactored test values that triggered false-positive secret detection in security scanners (no actual secrets — test fixtures use dummy values)
- 63 modules, 1659 tests, backward compatible with all existing configs

## v1.5.9

- **Test Fixture Cleanup:** Initial pass refactoring test fixture values that triggered false-positive secret detection in security scanners
- 63 modules, 1659 tests, backward compatible with all existing configs

## v1.5.8

- **Line Endings Normalized:** All 73 .ps1 files standardized to UTF-8 BOM + CRLF (45 modules had inconsistent LF-only endings)
- **Docs/Wiki Sync:** 7 file server setup guides (Debian, RHEL, Windows, Docker, LAN, Tailscale, Cloud) added to wiki; diverged pages synced between docs/ and wiki; 4 wiki-only pages (AD DS, Hyper-V Replica, Role Templates, Storage Backends) added to docs/
- **Git Tags:** Created local tags for all releases v1.4.0 through v1.5.7
- **Release Script:** Updated to create git tags, upload monolithic .ps1 to releases, include SHA256 for all 3 assets, normalize line endings, force-add monolithic in work repo
- **Monolithic on GitHub:** `RackStack v{version}.ps1` now included as a release asset alongside the .exe
- 63 modules, 1659 tests, backward compatible with all existing configs

## v1.5.7

- **Documentation Audit Fixes:** README updated with correct test count (1659), current version references, accurate region pair count (62), FileServer StorageType in config example, cloud storage mention in config table
- **CONTRIBUTING.md:** Pull request checklist updated with current test count
- 63 modules, 1659 tests, backward compatible with all existing configs

## v1.5.6

- **Cloud Storage Test Coverage:** 31 new tests for Azure Blob, static index, and cloud storage helper functions (Get-FileServerUrl, Get-FileServerHeaders, Test-FileServerConfigured) — tests cover URL construction, header generation, configuration detection across all 3 storage types
- 63 modules, 1659 tests, backward compatible with all existing configs

## v1.5.5

- **Cloud Storage Support:** FileServer module now natively supports Azure Blob Storage (`StorageType: "azure"`) with SAS token authentication and static JSON index files (`StorageType: "static"`) for S3/CloudFront — no more self-hosted file server required
- **Export-Defaults Completeness:** `Export-Defaults` now saves all 27+ config fields (was missing AutoUpdate, TempPath, SANTargetMappings, StoragePaths, AgentInstaller, VMNaming, DefenderExclusionPaths, DefenderCommonVMPaths, CustomRoleTemplates, SANTargetPairings) — previously saving from the UI silently dropped these settings
- **Batch Validation Hardened:** `Test-BatchConfig` validates StorageBackendType enum, VirtualSwitchType enum, CustomVNICs array structure (Name field, VLAN 1-4094 range), DC promotion prerequisites (ForestName required for NewForest), SMB3SharePath UNC format, and 7 additional boolean fields
- **Fixed:** 5 submenu functions (ServiceManager, EventLogViewer, RoleTemplateSelector, CertificateMenu, StorageManager) now respect `ReturnToMainMenu` flag — pressing M no longer gets stuck in submenu loops
- **Documentation:** Replaced work-specific example filenames across all file server setup guides; README config table and defaults.example.json now document all config fields including SANTargetPairings, CustomVNICs, CustomRoleTemplates, StorageBackendType
- 63 modules, 1628 tests, backward compatible with all existing configs

## v1.5.4

- **Fixed:** SET switch creation now warns about connected VMs before removing an existing switch
- **Fixed:** Drive letter assignment verified after applying — warns if letter is unavailable
- **Fixed:** Disk bring-online verifies read-only flag was cleared — warns about firmware/driver issues
- **Fixed:** vNIC removal verified before recreation — aborts cleanly if old adapter is locked
- **Fixed:** Windows Update timeout message corrected (said "continuing in background" when job was actually stopped)
- 63 modules, 1628 tests, backward compatible with all existing configs

## v1.5.3

- **SHA256 Update Verification:** Auto-update now verifies downloaded files against SHA256 hashes published in GitHub release notes — rejects corrupted or tampered downloads with a clear error
- **Pre-release Validation Expanded:** `Validate-Release.ps1` adds content integrity checks on git-tracked files
- **Stale Reference Fixes:** README monolithic line count corrected, CONTRIBUTING.md test count updated, Run-Tests.ps1 header version corrected
- 63 modules, 1628 tests, backward compatible with all existing configs

## v1.5.1

- **Test Coverage:** 173 new tests across 16 sections (114-129) covering DomainJoin, RDP/WinRM, FirewallTemplates, DiskCleanup, Password, HyperV, PerformanceDashboard, EventLogViewer, ServiceManager, BitLocker, StorageReplica, Utilities, VHDManagement, ISODownload, ActiveDirectory, HyperVReplica — all 63 modules now have dedicated test coverage
- **Generalized SupportContact:** Default `$script:SupportContact` emptied (was `support@abider.org`) — set your own value via `defaults.json`
- **Release Integrity:** SHA256 hashes included in GitHub release notes for all downloadable assets
- 63 modules, 1628 tests (was 1455), backward compatible with all existing configs

## v1.5.0

- **Custom SAN Target Pairings:** New `SANTargetPairings` config key in `defaults.json` — define custom A/B controller pairs with explicit labels (A0/B0, A1/B1, etc.), host-to-pair assignments with retry order, and configurable CycleSize for modulo cycling; A side = even suffixes, B side = odd by convention; when unset, existing mod-4 behavior is unchanged
- **Virtual Switch Management:** New submenu under Host Network for managing all Hyper-V virtual switch types — Create SET, External (single NIC), Internal (host-only), or Private (isolated) switches; `Show-VirtualSwitches` lists all switches with type, team NIC count, and management adapters; `Remove-VirtualSwitch` with VM safety checks and confirmation
- **Expanded vNIC Support:** `Add-CustomVNIC` now works with any External virtual switch (previously SET-only); switch selection menu shows switch type labels
- **VM Deployment Switch Fallback:** When no virtual switch exists during VM deployment, offers SET or External switch creation (previously SET-only)
- **Batch Mode Virtual Switch Types:** New `CreateVirtualSwitch` and `VirtualSwitchType` keys support all 4 switch types in batch mode; `VirtualSwitchName` and `VirtualSwitchAdapter` for customization; `CreateSETSwitch` preserved as backward-compatible alias
- **Batch Mode Custom Pairings:** `SANTargetPairings` available in batch config template for host builds
- **Fixed:** Host Network menu option [2] label updated from "Add Virtual NIC to SET" to "Add Virtual NIC to Switch" to reflect expanded compatibility
- 63 modules, 1628 tests (was 1388), backward compatible with all existing configs

## v1.4.1

- **Fixed:** Undo stack parameter ordering now uses hashtable splatting instead of positional array (params could swap on multi-param undo scripts)
- **Fixed:** Bare `Exit` replaced with `[Environment]::Exit(0)` for ps2exe EXE compatibility (caused "System error" dialog)
- **Fixed:** Per-adapter internet detection on PS 5.x uses `ping.exe -S` for source-bound ping (all adapters reported true if any had internet)
- **Fixed:** NIC disable for identification now checks for default route and warns before disabling management NIC (could disconnect remote sessions)
- 63 modules, 1388 tests, backward compatible with all existing configs

## v1.4.0

- **Server Role Templates (Module 60):** New JSON-driven system for installing common Windows Server roles and features — 10 built-in templates (DC, FS, WEB, DHCP, DNS, PRINT, WSUS, NPS, HV, RDS) with pre/post-install configuration; `Show-RoleTemplateSelector` interactive menu with installed status; `Install-ServerRoleTemplate` handles feature installation, reboot tracking, and post-install guidance; `Show-InstalledRoles` displays all installed roles grouped by type; custom templates via `defaults.json CustomRoleTemplates`
- **AD DS Promotion (Module 61):** Domain Controller promotion wizards — `Install-NewForest` (first DC in new domain), `Install-AdditionalDC` (join existing domain), `Install-ReadOnlyDC` (RODC); interactive prompts for domain name, functional level, DSRM password; prerequisite checks (static IP, DNS, Server OS); `Show-ADDSStatus` displays DC info, FSMO roles, replication health; added to System Configuration menu as option [3]
- **Hyper-V Replica Management (Module 62):** Full replica lifecycle management — `Enable-ReplicaServer` configures host as replica target with Kerberos/Certificate auth; `Enable-VMReplicationWizard` sets up VM replication with frequency and initial replication options; `Show-ReplicationStatus` dashboard with health and sync info; `Start-TestFailover` and `Start-PlannedFailover` for disaster recovery testing; `Set-ReverseReplication` and `Remove-VMReplicationWizard` for cleanup; added to Storage & Clustering menu
- **Batch Mode Expanded:** 2 new batch steps — Server Role Template installation (step 14) and DC Promotion (step 15); new config keys `ServerRoleTemplate`, `PromoteToDC`, `DCPromoType`, `ForestName`, `ForestMode`, `DomainMode`; total batch steps 20 → 22
- **Menu Reorganization:** System Configuration menu gains "Promote to Domain Controller" [3], renumbered [3]-[6] → [4]-[7]; Storage & Clustering menu gains "Hyper-V Replica Management" [6]; Tools & Utilities "Role Templates" [8] now launches full template installer
- **Fixed:** Undo stack corrupted when single item (array slice `[0..-1]` returned item instead of empty)
- **Fixed:** `Install-WindowsFeatureWithTimeout` checking non-existent `$result.Success` instead of `$result.ExitCode`
- **Fixed:** `Get-WindowsVersionInfo` error path returning inconsistent keys
- **Fixed:** Duplicate Defender process exclusion (`vmwp.exe` / `Vmwp.exe` case duplicate)
- **Fixed:** Command history never recording (added `Add-CommandHistory` function)
- **Fixed:** `$localadminaccountname` missing `$script:` prefix in batch mode
- **Fixed:** `Test-Connection -Source` failing on PowerShell < 6 (Server 2012 R2)
- 63 modules (was 60), 1388 tests, backward compatible with all existing configs

## v1.3.0

- **Storage Backend Generalization:** New `StorageBackendType` config key — supports iSCSI (default), Fibre Channel, Storage Spaces Direct (S2D), SMB3, NVMe-oF, and Local-only; all storage menus and batch mode steps adapt to the selected backend
- **New Module 59-StorageBackends:** Unified storage abstraction layer with backend selection, auto-detection from system state, and per-backend management menus (FC adapters/MPIO, S2D pool/virtual disk management, SMB3 share testing, NVMe-oF status)
- **Fibre Channel Support:** Show FC HBAs and WWPNs, rescan FC storage, configure MPIO for FC bus type with Round Robin
- **Storage Spaces Direct:** Enable S2D on clusters, create virtual disks with Mirror/Parity/Simple resiliency, show pool/disk/physical disk status
- **SMB3 File Share:** Test SMB share paths, show SMB client config, active connections, and mapped drives
- **NVMe over Fabrics:** Show NVMe controllers and physical disks, rescan NVMe storage
- **Generalized MPIO:** New `Initialize-MPIOForBackend` dispatches to correct bus type (iSCSI, FC) or skips for backends that handle paths natively (S2D, SMB3, NVMe)
- **Storage & SAN Management Menu:** Renamed from "iSCSI & SAN Management" — shows backend-specific submenu based on active backend; includes backend detection, status display, and backend switching
- **Batch Mode Backend-Aware:** New `StorageBackendType` and `ConfigureSharedStorage` batch keys; steps 18-19 dispatch to correct backend; legacy `ConfigureiSCSI` key still works for backward compatibility
- **Settings Menu:** New option [8] to change storage backend; `StorageBackendType` saved/loaded from defaults.json
- 60 modules (was 59), backward compatible with all existing configs

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
- 59 modules, backward compatible with all existing configs

## v1.1.0

- **Dynamic Defender Paths:** Defender exclusion paths now auto-generate from selected host drive instead of hardcoded D:/E: paths; updated on Host Storage initialization and configurable via `defaults.json`
- **Batch Mode HOST Extensions:** 5 new batch steps (15-19) for full host builds: Host Storage, SET Switch, iSCSI, MPIO, and Defender Exclusions; new HOST-specific batch config keys (`CreateSETSwitch`, `ConfigureiSCSI`, `ConfigureMPIO`, `InitializeHostStorage`, `ConfigureDefenderExclusions`)
- **Batch Config from State:** New "Generate from Current Server State" option in batch config menu — detects live configuration and produces a pre-filled `batch_config.json` for cloning to similar servers
- **Executable Favorites:** Favorites now store and invoke the underlying function directly; selecting a favorite runs the action instead of just showing the menu path
- **Configuration Drift Detection:** New drift check in Operations menu compares live server state against a saved profile and highlights drifted settings (hostname, IP, DNS, domain, timezone, RDP, WinRM, power plan, installed features)
- **Operations Menu:** Added Configuration Drift Check option [12]
- 59 modules, backward compatible with all existing configs

## v1.0.18

- **Maintenance:** Minor refinements and cleanup
- 59 modules, 1187 tests, backward compatible with all existing configs

## v1.0.17

- **Test Coverage:** 123 new tests across 8 sections (94-101) covering Windows Updates, Local Admin, Disable Admin, Host Storage, Exit Cleanup, Config Export, QoL Features, and Operations Menu
- **Repo Cleanup:** Reorganized local-only files into `local/` directory, simplified `.gitignore`, removed tool-identifying entries
- 59 modules, 1187 tests, backward compatible with all existing configs

## v1.0.16

- **Branding Assets:** Added banner, social preview, icon SVG/PNGs, and favicon to `.github/assets/`; README now uses the banner image
- **Self-Hosted CI:** GitHub Actions workflow now uses self-hosted runner for pushes (faster), GitHub-hosted for PRs (safe from forks); PSScriptAnalyzer install skipped if already present
- 59 modules, backward compatible with all existing configs

## v1.0.15

- **Config Documentation:** Rewrote `defaults.example.json` with comprehensive beginner-friendly comments on every field — each setting now has a `_help` explanation, examples, and field references for complex sections (VMNaming, AgentInstaller, CustomVMTemplates)
- **New Icon:** Replaced app icon with server rack design
- 59 modules, backward compatible with all existing configs

## v1.0.14

- **FileServer Rename:** Renamed `AbiderCloud` to `FileServer` across all modules, config keys, functions, tests, and docs for cleaner generic branding
- **Exit Cleanup Fix:** Cleanup now properly targets EXE files, monolithic `v*.ps1` naming, adjacent config files, and the app config directory (session/audit logs)
- 59 modules, backward compatible with all existing configs

## v1.0.13

- **Generic VM Templates:** Replaced work-specific built-in templates with 3 universal ones (DC, FS, WEB); add custom templates via `CustomVMTemplates` in `defaults.json`
- **Configurable VM Naming:** New `VMNaming` config key with token-based patterns (`{Site}-{Prefix}{Seq}`), configurable site ID source, detection regex, and zero-padded sequences
- **Linux VHD Guide:** New cloud-init VHD preparation guide alongside the Windows Sysprep guide in VHD Management menu
- **Dynamic Agent Naming:** All user-facing agent installer text now uses `$script:AgentInstaller.ToolName` instead of hardcoded names
- **Wiki Updates:** New VHD Preparation page; VM deployment runbook updated with generic templates and configurable naming examples; iSCSI docs note configurability of subnet/targets
- 59 modules, backward compatible with all existing configs

## v1.0.12

- **Auto-Update on Startup:** New `AutoUpdate` flag in `defaults.json` — when enabled, automatically downloads and installs updates on startup without prompting; deferred retry if no network at launch (triggers after network is configured)
- 59 modules, backward compatible with all existing configs

## v1.0.11

- **Console Auto-Sizing Fix:** `Initialize-ConsoleWindow` now actually called on startup; maximizes window via Win32 API, expands buffer width to match screen, and resizes console to fill available space — works for both PS1 and EXE
- 59 modules, backward compatible with all existing configs

## v1.0.10

- **Test Coverage Expansion:** 4 new test sections (90-93) covering VM Checkpoint Management, Batch Config Template Structure, FileServer Function Coverage, and Agent Installer Configuration
- 59 modules, 1040+ tests, backward compatible with all existing configs

## v1.0.9

- **Refactor New-DeployedVM:** Split 320-line monolith into 8 focused helpers (`Resolve-VMStoragePaths`, `New-VMDirectories`, `New-VMShell`, `New-VMDisk`, `New-VMDisks`, `Set-VMNetworkConfig`, `Set-VMAdvancedConfig`, `Register-VMInCluster`); orchestrator is now ~60 lines
- **Remote Pre-flight Checks:** New `Test-RemoteReadiness` runs 5-step connectivity check (ping, WinRM port, WSMan, credentials, PS version); `Show-PreflightResults` displays results; integrated into `Invoke-RemoteProfileApply`
- 59 modules, backward compatible with all existing configs

## v1.0.8

- **Configurable Agent Installer:** Generalized Kaseya installer into MSP-agnostic framework; tool name, service name, file pattern, install args, paths, exit codes, and timeout all configurable via `AgentInstaller` in `defaults.json`
- **Extract Hardcoded Values:** SAN target IP mappings, Defender exclusion paths, storage paths, and temp directory now configurable via `defaults.json` (with built-in fallback defaults)
- **Batch Mode Validation:** New `Test-BatchConfig` pre-flight validator catches config errors (invalid IPs, hostnames, CIDR, booleans, power plans, missing gateway) before batch execution starts
- **defaults.example.json:** Added `AgentInstaller`, `SANTargetMappings`, `DefenderExclusionPaths`, `DefenderCommonVMPaths`, `StoragePaths`, `TempPath` examples
- **Tests:** 15 new batch validation tests
- 59 modules, backward compatible with all existing configs

## v1.0.7

- **EXE Fix:** Monolithic build-from-scratch now appends `Assert-Elevation` entry point (fixes exe opening and immediately closing)
- **EXE Icon:** `release.ps1` now passes `-IconFile` to ps2exe for both repo and cross-repo compilation
- **EXE Update:** Self-update uses `[Environment]::Exit(0)` instead of bare `exit` for ps2exe compatibility
- **Error Handling Audit:** Removed 12 redundant `try/catch` blocks around `-ErrorAction SilentlyContinue` calls; added warning messages to 4 silent file I/O catch blocks (favorites, history, session, VM defaults)
- **Inline Docs:** Added `# --- Section: ---` comments to 4 complex functions: `Register-ServerLicense`, `Install-Agent`, `Set-SNMPConfiguration`, `Set-PagefileConfiguration`
- **Troubleshooting Guide:** New `docs/Troubleshooting.md` covering VM deployment, iSCSI/SAN, cluster, and common errors
- **Operations Runbooks:** New `docs/Runbook-VM-Deployment.md`, `docs/Runbook-Host-Migration.md`, `docs/Runbook-HA-iSCSI.md`
- 59 modules, backward compatible with all existing configs

## v1.0.6

- **GitHub Actions CI:** Automated test suite, PSScriptAnalyzer, and monolithic sync on every push and PR
- **Build from Scratch:** `sync-to-monolithic.ps1` now generates the monolithic from scratch when it doesn't exist (enables CI)
- **CI-Safe Tests:** `defaults.json` tests skip gracefully when the file is absent (gitignored in public repo)
- **Dynamic Badge:** README test badge now reflects live CI status
- 59 modules, 949 tests, backward compatible with all existing configs

## v1.0.5

- **Configurable VM Templates:** Override built-in VM template specs (CPU, RAM, disks) or add entirely new templates via `CustomVMTemplates` in `defaults.json`
- **Custom VM Defaults:** Configure default vCPU, RAM, memory type, disk size, and disk type for non-template VMs via `CustomVMDefaults`
- **Partial Overrides:** Change only the fields you want -- unspecified fields keep their built-in values
- **Re-Import Safe:** Built-in templates are snapshotted on first import and restored before each re-merge
- **Disk Conversion:** JSON-parsed disk arrays automatically converted from PSCustomObject to hashtable
- **Tests:** 29 new tests for template merge
- 59 modules, 934 tests across 86 sections, backward compatible with all existing configs

## v1.0.4

- **Fixed:** `$script:ModuleRoot` detection in compiled EXE mode -- `$PSScriptRoot` is empty in ps2exe, now falls back to process executable path
- 59 modules, backward compatible with all existing configs

## v1.0.3

- **Auto-Update Check:** RackStack checks for updates on startup and shows a banner on the main menu when a new version is available
- **[U] Quick Update:** Press U on the main menu to download and install updates
- **Custom Icon:** RackStack.exe now has its own icon
- **Fixed:** Script path detection in compiled EXE mode
- **Deferred Retry:** If no network at startup, update check retries when main menu is displayed (throttled to 60s)
- **Scan Fixes:** Resolved GitHub Actions secret scanner false positives
- 59 modules, backward compatible with all existing configs

## v1.0.2

- **WMF 5.1 Bootstrap:** `Install-Prerequisites.ps1` auto-downloads and installs WMF 5.1 for Server 2008 R2 SP1 / 2012
- **OS Support Expanded:** Now spans Server 2008 R2 SP1 through 2025
- **Bootstrap:** Checks .NET 4.5.2+ requirement, handles TLS, detects OS, downloads correct MSU
- 59 modules, backward compatible with all existing configs

## v1.0.1

- **First-Run Wizard:** Generates `defaults.json` interactively on first launch
- **Auto-Update:** Checks GitHub releases and self-updates (exe and ps1)
- **Server 2012 R2 Support:** SET/StorageReplica/Defender guards for older OS
- **Version Consistency:** All version references dynamically derived
- **Header Sync:** `sync-to-monolithic.ps1` now syncs Header.ps1 into builds
- 59 modules, backward compatible with all existing configs

## v1.0.0

- Initial open source release
- Full feature set: networking, Hyper-V, VM deployment, storage, monitoring, batch mode
- 59 modules, 905 tests, backward compatible with all existing configs

## Pre-release History

Originally developed as an internal Windows Server configuration tool for MSP field deployments. Designed to replace the built-in `sconfig` with a comprehensive, menu-driven alternative. Version numbers below are remapped from the original internal versioning.

### v0.10.0

- **SET Smart Auto-Detection:** `Test-AdapterInternetConnectivity` identifies which NICs have internet; auto-detect mode selects NICs with internet for SET automatically; identifies iSCSI candidate adapters (NICs without internet); option to configure iSCSI immediately after SET creation
- **iSCSI Smart Auto-Configuration:** Extract host number from hostname to calculate iSCSI IPs automatically; `Test-SANTargetConnectivity` pings SAN targets to verify connectivity; auto-configure mode detects host number, calculates IPs, configures A/B sides; `Get-SANTargetsForHost` returns correct SAN targets per host with cycling pairs
- **iSCSI & SAN Management Menu:** New submenu for complete iSCSI/SAN management — disable NICs for physical identification, connect/disconnect iSCSI targets with multipath, initialize MPIO for iSCSI (Round Robin), display session/target/MPIO/disk status
- **Utilities Expansion:** Configuration profile diff with color output, update checker, pre-check computer name in AD, IP conflict detection (ping + DNS + ARP), remote profile application via WinRM, credential manager for stored domain/remote credentials
- Internal pre-release

### v0.9.0

- **Batch Mode Expanded:** Total batch steps increased from 10 to 14 — added MPIO install, Failover Clustering install, local admin creation, and disable built-in admin steps
- **Configuration Profiles Expanded:** Save/load profiles now include MPIO, Failover Clustering, local admin, and disable admin settings; preview shows all flags before applying
- **Export Expanded:** Server configuration export now includes MPIO status, Failover Clustering status, and cluster membership details
- **Help & Documentation:** VHD/ISO management and deployment options added to built-in help system; two new tips for VHD deploy and VM queue
- **Settings Menu:** Added "View Changelog" option; automatic transcript cleanup (removes logs older than 30 days)
- **UI Fixes:** All menu boxes standardized to 72-char inner width; firewall color logic corrected
- Internal pre-release

### v0.8.0

- **Sysprepped VHD Deployment:** Download sysprepped VHDs from file server; VHD caching with reuse prompts; copy cached dynamic VHD per VM and convert to fixed; offline VHD customization before first boot (mount, inject computer name, RDP, timezone, power plan, PS Remoting via registry); SetupComplete.cmd for first-boot firewall and remoting setup; VHD management menu with download status; sysprep VHD creation guide
- **ISO Download:** Download Server ISOs from file server (2019/2022/2025); host ISOs stored on data drive, cluster ISOs on CSV
- **Host Storage Setup:** Data drive validation (rejects optical/small drives); automatic DVD drive remount from D: to free letter; creates VM, ISO, and base image directories; sets Hyper-V default paths
- **Full VM Deployment System:** Deploy VMs on standalone hosts or failover clusters; local, remote, or cluster connection modes; automatic site detection from hostname; standard VM templates for common server roles; OS type support (Windows/Linux) with Secure Boot template selection; multi-disk and multi-NIC templates with VLAN support; VM name collision detection with next-available suggestion; Generation 2 VMs with production checkpoints; cluster CSV path detection; VM-specific subdirectories
- **Storage Manager Improvements:** Better disk health correlation, partition filtering, OS disk protection with extra confirmation warnings, allocation unit size option (4K-64K)
- Internal pre-release

### v0.7.0

- **Storage Manager:** Full disk management with 14 options — view all disks (status, health, size, partition style, bus type), view all volumes (letters, labels, file systems, space usage), view disk partitions, initialize RAW disks (GPT/MBR), set disk online/offline, clear disk with safety confirmations, create/delete partitions, format volumes (NTFS/ReFS/exFAT, quick or full), extend/shrink volumes, change drive letters, change volume labels
- **Helper Functions:** Human-readable byte formatting, disk health retrieval, disk and partition selection helpers
- **Safety Features:** Multiple confirmation prompts for destructive operations, type-to-confirm for dangerous actions, system/boot partition warnings, color-coded health indicators
- Internal pre-release

### v0.6.0

- **Menu Restructure:** New "Configure Server" and "Deploy VMs" layout; System Health Check moved to option 1
- **PowerShell Remoting:** Secure WinRM configuration with Kerberos authentication
- **Agent Installer:** Download and install MSP agent from file server
- **Configuration Profiles:** Save server settings as JSON for cloning; load and apply saved profiles to new servers
- **Undo System:** Undo functionality for network, system, and security changes; consolidated undo action tracking
- **Transcript Logging:** Automatic session logging to timestamped files
- **Security:** Password handling uses `ZeroFreeBSTR` for secure memory cleanup; `Clear-SecureMemory` function; try/finally blocks ensure passwords always cleaned
- **Code Quality:** 13 functions renamed to follow PowerShell verb-noun conventions (`Is-*` → `Test-*`, `Check-*` → `Test-*`/`Get-*`, `Configure-*` → `Set-*`/`New-*`, `Display-*` → `Show-*`, `Ensure-*` → `Assert-*`, `Log-*` → `Write-*`)
- **New Features:** Disable IPv6, network adapter rename, smart status caching, `Write-PressEnter` helper
- Internal pre-release

### v0.5.1

- **Restored Server Licensing:** Full `Register-ServerLicense` with KMS client setup keys (Server 2008–2025), AVMA keys (Server 2012 R2–2025 including Essentials and Azure editions), guided Host vs VM licensing path, Datacenter host detection for AVMA eligibility, retry logic with attempt counter
- **Session Tracking:** Added session change tracking for RDP, local admin, firewall, hostname, domain join, and disable admin operations
- **Navigation:** Navigation command support added to adapter selection and licensing menus
- Internal pre-release

### v0.5.0

- **NIC Link Speed Display:** Adapter tables now show link speed (10Mbps to 10Gbps+) with refresh option
- **Test Network Connectivity:** Ping gateway, DNS, and internet from any menu
- **Power Plan Configuration:** Set power plan (High Performance recommended for servers)
- **Batch Config Templates:** Generate JSON template with all configuration options
- **Color Themes:** 5 built-in themes (Default, Dark, Light, Matrix, Ocean)
- **Help System:** Type `help` at main menu for built-in documentation
- **Undo Framework:** Track and revert configuration changes
- **Settings Menu:** Theme selection, help, undo history
- **DNS Presets:** Expanded with Google, Cloudflare, OpenDNS, Quad9
- Internal pre-release

### v0.4.0

- **Disable IPv6:** New option in Host Network menu
- **Install Hyper-V:** Added as main menu option
- **Backup NIC:** Creation option for SET configurations
- **Navigation Commands:** Universal `back`, `cancel`, `exit` handling throughout all menus
- **DNS Presets:** Quick-select from preconfigured DNS server lists
- **Progress Indicators:** Visual feedback for long-running operations
- **Session Summary:** Exit screen shows runtime and changes made
- **Configuration Export:** Save current server configuration to file
- **Batch Mode:** Apply configurations from JSON config files
- **Bug Fixes:** Timezone function name conflict, Hyper-V client vs server detection, reboot detection, main menu navigation, Windows version detection, VLAN error handling
- Internal pre-release

### v0.3.0

- **UI Consistency:** Clear-Host added before all adapter selection tables; all adapter selections show both UP and DOWN adapters; consistent screen clearing throughout; color-coded adapter status
- Internal pre-release

### v0.2.0

- **Bug Fixes:** iSCSI confirmation logic, parameter typos (`col1umnWidths`, `R ead-Host`), wrong parameter names, invalid `Break 2` syntax, `$null` comparison order, VLAN menu function calls, script path scope, domain join credential handling, duplicate timezone prompts
- **Input Validation:** Hostname, IP address, and VLAN ID validation
- **Windows Update Timeout:** 5-minute timeout protection for update operations
- **VLAN Configuration:** VLAN support for Hyper-V virtual adapters
- **Network Checks:** Connectivity verification
- **Navigation:** `back` command support in menus
- **Improvements:** Global variable initialization, better error messages with hints, 14-character minimum passwords
- Internal pre-release

### v0.1.0

- **iSCSI NIC Configuration:** Dedicated iSCSI network adapter setup with isolation
- **Network Menu Split:** Separate Host Network and VM Network menus for clearer organization
- **Menu Improvements:** Better menu organization and navigation
- Initial internal version
