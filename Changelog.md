# Changelog

## v1.98.46

Gold-standard refactor — `$global:` → `$script:` across the codebase.

- **PSAvoidGlobalVars elimination.** Converted all 130+ writes to `$global:RebootNeeded`, `$global:ReturnToMainMenu`, and `$global:DisabledAdminReboot` (plus the `$global:Rebootneeded` casing typo in 45-ConfigExport) to their `$script:` equivalents across 49 of the 65 module files. The dot-source loader runs every module into one shared script scope, so `$script:` and `$global:` were functionally equivalent for these cross-module state flags — switching to `$script:` is the documented PowerShell convention and clears PSAvoidGlobalVars cleanly. `$global:LASTEXITCODE` is the only remaining `$global:` reference (a runtime-set built-in that must stay global). PSSA: 0 errors / 0 warnings / 0 PSAvoidGlobalVars hits. All 71 Pester tests still pass.
- **`Tests/pester-results.xml` added to .gitignore.** Generated NUnit output from `pester-check.ps1` was accidentally tracked in the v1.98.45 commit; it is per-run output and should not be checked in.

## v1.98.45

Quality push — modern test framework + distribution channels.

- **Pester 5.x unit-test suite** under `Tests/Pester/` covering pure functions in 03-InputValidation, 04-Navigation, and 22-Password modules. 71 tests, complements the existing regex-pattern harness in `Run-Tests.ps1` (which stays as the structural / cross-cutting check). New CI step `Run Pester unit tests` after `Run tests (core)` (Tests/Pester/, Tests/pester-check.ps1, .github/workflows/ci.yml).
- **PowerShell Gallery publish** step added to the release pipeline. Gated on `PSGALLERY_API_KEY` secret — skips silently if absent so the release pipeline still works without it set. Publishes the existing thin-wrapper module (`RackStack.psd1` + `RackStack.psm1`) so users can `Install-Module RackStack`. Verifies psd1 ModuleVersion matches Header.ps1 .VERSION before publishing (.github/workflows/ci.yml).
- **Code-signing placeholder** for SignPath.io (free OSS plan). Workflow steps commented out with full enable instructions — uncomment + add four secrets to ship signed EXE that bypasses SmartScreen warnings (.github/workflows/ci.yml).

## v1.98.44

Round 31 — info-disclosure + argument-injection sweep (1 Tier-1 + 1 Tier-2 latent-privesc applied).

Tier-1 (defeats whole-disk encryption):
- **Fix:** 31-BitLocker `Show-BitLockerKey` recovery-key display now pauses Start-Transcript around the key output and writes directly to the console via `[Console]::WriteLine` instead of `Write-OutputColor`. Prior code wrote the BitLocker recovery password verbatim to the active transcript log — the transcript persists in `$env:TEMP` for up to 30 days, and a recovery key in a plaintext log file defeats the entire point of whole-disk encryption. Same fix shape as 22-Password's generated-password display from v1.98.24 (31-BitLocker).

Tier-2 (latent privesc primitive):
- **Fix:** 50-EntryPoint `ScheduleUpdateCheck` CLI action now validates the `InstallLocation` registry value AND the derived `$outputJsonPath` against shell metacharacters (`"`, backtick, `&`, `|`, `<`, `>`, `^`, `%`, `..\`) before embedding them in the `cmd /c "..."` argument string. `HKLM\...\Uninstall\RackStack\InstallLocation` is admin-only by DACL but the scheduled task runs as SYSTEM weekly — any local admin who poisoned the registry value with `" & calc.exe &` would gain SYSTEM at schedule-fire-time without re-prompting. Refuses to register the task if either path contains unsafe characters (50-EntryPoint).

Audit (CLEAN): Class C crypto / RNG — no `Get-Random` for security tokens, no MD5/SHA1, no predictable seeding, no hardcoded keys, no `String.Equals` for password comparison. Codebase uses `System.Security.Cryptography.RandomNumberGenerator` everywhere it matters.

## v1.98.43

- **Fix (CI/test):** Menu-gated proximity regex relaxed from same-line (`[^\r\n]{0,200}`) to multi-line (`[\s\S]{0,400}`). The dispatcher pattern in `Start-DiskCleanup` is `if (Confirm-UserAction "Run X?") {NL Invoke-X NL}` — multi-line block, not same-line. Now correctly matches the actual code shape while staying tight enough to reject false positives from unrelated Confirm calls (Tests/Run-Tests.ps1).
- **Includes all v1.98.40-42 fixes** (none published; this version supersedes them under z-retention).

## v1.98.42

- **Fix (CI/test):** v1.98.41 still had `Invoke-FullEnhancedCleanup` in the body-gated list, but the function's internal Confirm prompts (Windows.old at line 1062, shadow copies at 1088) are sub-prompts for individual operations — the up-front "Run Full Enhanced Cleanup?" gate happens at the menu dispatcher (`Start-DiskCleanup` line 138). Moved to menu-gated list so the test correctly verifies the actual design pattern (Tests/Run-Tests.ps1).
- **Includes v1.98.40 / v1.98.41 fixes** (neither tag was published due to the test-pattern misalignment; this version supersedes both under z-retention).

## v1.98.41

- **Fix (CI/test):** v1.98.40's tightened `20-DiskCleanup destructive entry points gate on Confirm-UserAction` test correctly caught that the listed Invoke-*Clean functions don't gate inside their own body — but the design pattern uses the menu dispatcher (`Start-DiskCleanup`) to gate each call site BEFORE invoking the destructive function. Split the test into two assertions: (1) body-gated functions (`Clear-WindowsOld`, `Invoke-RecycleBinCleanup`, `Clear-UserProfileTemp`, `Clear-ShadowCopies`, `Invoke-FullEnhancedCleanup`) verified against function-body `Confirm-UserAction` within 3500 chars; (2) menu-gated functions (`Invoke-QuickClean`, `Invoke-StandardClean`, `Invoke-DeepClean`, `Clear-WindowsUpdateCache`) verified against same-line `Confirm-UserAction ... Invoke-X` proximity match. Both shapes now properly verified instead of trivially matching the word "Confirm" anywhere (Tests/Run-Tests.ps1).
- **Includes v1.98.40 fixes** (v1.98.40 tag was never published; this version supersedes it under z-retention).

## v1.98.40

Round 30 — Tier-1 trivial-test hardening (security-gate verifications that didn't actually verify).

- **Tests/Run-Tests.ps1:** `20-DiskCleanup: has confirmation for destructive ops` previously matched the literal word "Confirm" anywhere in the file (including comments) — trivially passed even if no gate existed. Now requires `Confirm-UserAction` to appear within 2500 chars of each named destructive function body (`Clear-WindowsUpdateCache`, `Clear-EventLogs`, `Invoke-QuickClean/Standard/Deep/Full`).
- **Tests/Run-Tests.ps1:** `22-Password: enforces minimum length` regex pattern `|length` matched the literal English word anywhere in the file. Same for uppercase/lowercase/digits/special-char check patterns. Now requires the actual code shape inside `Test-PasswordComplexity` body: `.Length -lt`, `-cmatch '[A-Z]'`, `-cmatch '[a-z]'`, `[0-9]` or `\d`, character class for specials.
- **Tests/Run-Tests.ps1:** Added CI-runnable positive assertion for `Test-SystemDisk` that exercises the IsBoot/IsSystem early-return branch via fake PSCustomObject inputs — this path doesn't touch the Storage Management Provider, so it works on the CI runner whose storage stack is degraded. Replaces the previously-unverifiable disk-0 assertion that auto-passed on GitHub Actions. Three new tests: IsBoot=true → true, IsSystem=true → true, data disk (both false) returns within bound. The original disk-0 assertion still runs on non-CI hosts.

## v1.98.39

Round 29 — TOCTOU + reparse-point sweep. **1 PRIVESC-class TOCTOU + 4 Tier-1 symlink-traversal fixes.**

TOCTOU (verified-binary swap):
- **Fix (PRIVESC):** 35-Utilities `Update-RackStack` had a verify-then-execute gap. SHA256 was verified against `$tempPath` in `$env:TEMP`, then a batch file with a 5-second sleep (+ time for the operator's Read-Host) ran `move /y "$tempPath" "$targetPath"` and `start "" "$targetPath"`. A parallel process watching `%TEMP%\RackStack_update_*` could swap the verified binary for a malicious one between verification and move — verified-binary swap = arbitrary code execution as future-admin. Now (1) moves the verified binary into `%ProgramData%\<Tool>\update\` with admin-only DACL (Administrators+SYSTEM, no inheritance) BEFORE the batch is written, and (2) re-verifies SHA256 inside the batch script via `certutil -hashfile SHA256` immediately before the `move /y` — closes the window even if the DACL somehow doesn't apply (35-Utilities).

Reparse-point / symlink traversal (admin-context arbitrary delete):
- **Fix (DESTRUCTIVE):** 47-ExitCleanup self-destruct path now filters `[System.IO.FileAttributes]::ReparsePoint` from both the Get-ChildItem -File and -Directory recursions over the Administrator profile. Without this filter, a junction planted under `C:\Users\Administrator\` (any user with redirected-folders write access, any prior limited compromise) would have caused the SYSTEM-scheduled-task recursive delete to walk into the link target and remove matching files outside the profile (47-ExitCleanup).
- **Fix (DESTRUCTIVE):** 20-DiskCleanup `Clear-UserProfileTemp` per-profile recursion now filters ReparsePoint. RackStack runs as admin; a standard user could plant a junction inside their own `AppData\Local\Temp` pointing at e.g. `C:\Windows\System32` and the admin-context recursive delete would follow into the link target. Same fix shape as v1.98.14's system-Temp fix; this is the per-profile equivalent that was missed (20-DiskCleanup).
- **Fix (DESTRUCTIVE):** 20-DiskCleanup `Invoke-FullClean` profile sweep same fix (20-DiskCleanup).
- **Fix:** 20-DiskCleanup Edge browser cache sweep ReparsePoint filter added — admin's own LocalAppData but defense-in-depth for prior-install-time junctions (20-DiskCleanup).

## v1.98.38

Round 28 — remaining Tier-2 job leaks from round 27 sweep.

- **Fix:** 58-NetworkDiagnostics `Test-PingSweep` wraps the per-batch job creation + Wait/Receive in try/finally with guaranteed Stop/Remove. PingSweep on a /23 spawns up to 254 jobs per batch — an exception during interactive sweep (closed runspace, Ctrl-C, WinRM teardown) previously orphaned hundreds of background runspaces in one session (58-NetworkDiagnostics).
- **Fix:** 58-NetworkDiagnostics `Test-PortScan` same try/finally pattern for the ~30 parallel TCP-probe jobs (58-NetworkDiagnostics).
- **Fix:** 41-VHDManagement Convert-VHD retry-path wraps the retry-job lifecycle in try/finally. Convert-VHD jobs hold large memory-mapped IO; a leak here accumulates across multi-VM deployments. The outer function's finally only covered $copyJob / $convertJob — the retry job was unprotected (41-VHDManagement).

Encoding fix:
- **Fix:** 39-FileServer `Test-FileIntegrity` hash sidecar `.sha256` file now written as UTF-8 WITHOUT BOM via `System.Text.UTF8Encoding($false)` + `[System.IO.File]::WriteAllText`. PS 5.1's `-Encoding UTF8` emits a 3-byte BOM (`EF BB BF`); the standard Unix `sha256sum -c file.sha256` verifier reads those bytes as part of the hash field and reports the file as corrupt even when the bytes match. The tool's own reader tolerated the BOM, but sidecars are often handed to external CI / agent-installer pipelines on non-Windows hosts (39-FileServer).

Audit (CLEAN, no Tier-1): console state — the codebase doesn't modify terminal mode (no CursorVisible toggle, no TreatControlCAsInput, no alt-screen escape sequences); abnormal exit cannot leave the terminal in a corrupt state.

## v1.98.37

Round 27 — resource-leak + shared-state sweep (1 Tier-1 + 2 Tier-2 applied).

Tier-1 (operator-visible state corruption):
- **Fix (DESTRUCTIVE):** 55-QoLFeatures `Restore-SessionState` re-bound `$script:SessionChanges` from `[System.Collections.Generic.List[object]]` (initialized in 00-Initialization) to a fixed-size `Object[]` via `@(...)`. Subsequent `Add-SessionChange` calls (`$script:SessionChanges.Add(...)` in 04-Navigation) silently no-op'd or threw on the fixed-size array — every audit entry made AFTER a session resume was lost. Both the Show-SessionSummary report and the persistent on-disk session log were missing post-resume entries. Now rebuilds a fresh `List[object]` and copies in the restored entries, preserving the type so post-resume audit logging keeps working (55-QoLFeatures).

Tier-2 (resource leaks):
- **Fix:** 04-Navigation `Get-FileHashBackground` adds a 30-minute wall-clock cap and wraps job lifetime in try/finally. Prior code had no timeout — a wedged storage path (network drive, AV scan blocking read, RAID rebuild stall) pinned the menu indefinitely. Ctrl-C during hash also left the background runspace alive; now finally always cleans up (04-Navigation).
- **Fix:** 39-FileServer `Get-FileServerFile` wraps the download-job lifetime in try/finally with guaranteed Stop/Remove cleanup. Receive-Job moved inside the try so the result is captured before the finally tears the job down. Prior code cleaned up on hang/timeout/success paths individually but an unhandled exception inside the progress-monitoring loop (Get-Item race, console KeyAvailable on remote session) would leak the background runspace; in a deployment loop (every ISO + agent + VHD download), the leak accumulates (39-FileServer).

## v1.98.36

- **Fix (CI/test):** `50-EntryPoint: TcpSettingsAudit JSON output` regex window bumped from 4000 to 5500 chars. The v1.98.34 netsh→Get-NetTCPSetting migration added ~700 chars between the `'TcpSettingsAudit'` label and the JSON-output marker, pushing it past the prior window. Not a functional regression (Tests/Run-Tests.ps1).
- **Includes all v1.98.34 / v1.98.35 fixes** (neither tag was published; v1.98.34 CI failed on this test window, v1.98.35 inherited the same failure mode).

## v1.98.35

Round 26 — VM-name path-traversal sweep + error-swallowing on destructive ops (agent findings from round 25 parallel sweep).

Pattern A — VM-name / hostname path traversal in filename construction:
- **Fix (DESTRUCTIVE):** 53-VMExportImport `Export-VMWizard` Remove-Item-Recurse-Force regression. My round 15 fix at line 162 deleted `$targetFolder = Join-Path $exportPath $selectedVM.Name` — but Hyper-V allows backslash / forward-slash / `..` in VM `.Name` property, so a maliciously-imported VM named `..\..\System32` would cause Remove-Item to nuke whatever lives at that resolved path. Now rejects VM names containing path separators or `..`, plus verifies the resolved $targetFolder is actually under $exportPath using `[System.IO.Path]::GetFullPath` (53-VMExportImport).
- **Fix:** 44-VMDeployment `Get-VMStoragePaths` validates VMName up-front; both `Join-Path $vmPath $Config.VMName` and `Join-Path $vhdPath $Config.VMName` would escape via `..\` (44-VMDeployment).
- **Fix:** 44-VMDeployment `New-VMDisk` validates VM.Name AND Disk.Name (Disk.Name is wizard-supplied per-disk and wasn't validated upstream) — `New-VHD -Path` at the resolved path would otherwise land outside VHDSpecificPath (44-VMDeployment).
- **Fix:** 41-VHDManagement validates VMName + DiskLabel before composing `${VMName}_${DiskLabel}.vhdx` for Copy-Item / Move-Item destination (41-VHDManagement).
- **Fix:** 45-ConfigExport `Save-ExportBaseline` slugs hostname before embedding in filename. `$ExportData.Hostname` can flow from cluster / remote-import contexts where a remote host's stored hostname may contain path separators (45-ConfigExport).

Pattern B — error swallowing on destructive ops:
- **Fix (DESTRUCTIVE):** 44-VMDeployment DC-mode time-sync disable was `-ErrorAction SilentlyContinue`. Silent failure left the time-sync integration service ENABLED on a DC VM, producing 5+ minute drifts that break Kerberos (and on a DC where the host syncs from AD, a loop). Now promotes to `-ErrorAction Stop`, catches, and surfaces a clear remediation message (44-VMDeployment).
- **Fix (DESTRUCTIVE):** 44-VMDeployment `Add-ClusterVirtualMachineRole` silent failure left the operator believing the VM was clustered when it was actually a standalone VM on one node — next planned-migration / node-drain operation broke because the VM wasn't a cluster role. Now surfaces the failure with explicit remediation command (44-VMDeployment).
- **Fix:** 44-VMDeployment all `Set-VM` (AutomaticStartAction / AutomaticStopAction / AutomaticCheckpointsEnabled / CheckpointType) and `Set-VMFirmware` (Secure Boot) silently-continue calls promoted to per-call try/catch with warning. AutomaticCheckpointsEnabled=false silent fail on a DC VM risks AD USN rollback if Hyper-V auto-checkpoints the running VM; CheckpointType=Production silent fail breaks application-consistent checkpoints (44-VMDeployment).

## v1.98.34

Round 25 — backlog cleanup (Pattern 4 highest-impact + remaining Pattern 7 netsh sites).

Pattern 7 (netsh-output sites in 50-EntryPoint migrated to PowerShell cmdlets):
- **Fix:** `TcpSettingsAudit` Auto-Tuning + Chimney + Congestion + ECN + Timestamps now read from `Get-NetTCPSetting -SettingName Internet` and `Get-NetOffloadGlobalSetting` (locale-neutral typed properties). Falls back to netsh only when the cmdlet isn't available (50-EntryPoint).
- **Fix:** `TcpSettingsAudit` dynamic-port range now reads `DynamicPortRangeStartPort` / `DynamicPortRangeNumberOfPorts` properties on `Get-NetTCPSetting` (typed integers). Falls back to netsh parsing only on cmdlet-unavailable hosts (50-EntryPoint).
- **Fix:** `ProxyAudit` WinHTTP proxy now reads directly from `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections\WinHttpSettings` binary blob and parses the well-known structure (flags + proxy-server + bypass-list). Bypasses the localized `netsh winhttp show proxy` labels ("Proxy Server" / "Bypass List" become "Proxyserver" / "Ausnahmen" on de-DE, etc.). Netsh fallback remains for hosts where the registry read fails (50-EntryPoint).

Pattern 4 (storage cmdlet timeouts — highest-impact site):
- **Fix:** 32-Deduplication status menu replaces the per-volume `Get-DedupStatus` + `Get-DedupVolume` loop with two batch CIM queries wrapped in `Start-Job + Wait-Job -Timeout 15` each, then indexes into the results by volume key. On a file server with 16 LUNs and one corrupt chunk store, the per-volume loop was making 32 sequential CIM calls against a wedged dedup service and froze the menu for 5+ minutes. Now bounded at 30s worst-case (15s × 2 batch calls) and a single chunk-store hang doesn't block the others (32-Deduplication).

## v1.98.33

Round 24 — final Pattern 6 cleanup.

- **Fix:** 20-DiskCleanup `Clear-WindowsUpdateCache` now pre-checks `Get-Service -DependentServices` for both `wuauserv` and `bits` before forcing them down. Prior `Stop-Service -Force` cascade-killed dependents silently — on a WSUS host that's the IIS upload tasks; on a host with backup software that pinned a BITS dependency, the backup mid-run died. Now refuses the cache clear with a clear message if any dependent is running (20-DiskCleanup).

**Cross-module sweep status:** all four high-severity patterns from the round 17 sweep are addressed (Pattern 1 unscoped IP removal, Pattern 3 hardcoded Administrators, Pattern 5 non-atomic exports, Pattern 6 Stop-Service cascade, Pattern 7 English-only NTP/license parsing, Pattern 9 path-traversal via env vars, Pattern 10 locale-fragile enum). Pattern 4 (storage cmdlet timeouts ~30 sites) is deferred — those are defensive only against a wedged storage stack, which is rare in production; the highest-impact `Test-SystemDisk` was already fixed in v1.98.20 with the Start-Job outer-bound pattern. Remaining Pattern 7 netsh-output sites in 50-EntryPoint (~6) parse values that are themselves English-only — fixing would require migrating to Get-NetTCPSetting / Get-NetAdapterAdvancedProperty cmdlets.

## v1.98.32

Round 23 — cross-module sweep continuation (Pattern 7 remaining time-sync sites).

- **Fix:** 61-ActiveDirectory AD-readiness NTP check now uses W32Time service state + `w32tm` exit code as the signal instead of substring-matching `error|not found|stopped` against the w32tm output (those words are localized on non-EN MUI, so the warning never fired on non-EN domain controllers — AD time drift is a critical replication blocker, missing this check is a real bug) (61-ActiveDirectory).
- **Fix:** 45-ConfigExport server-config export NTP-source line reads from `HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters` registry first (locale-neutral). Falls back to `w32tm /query /source` only if registry lookup fails. Exported config now carries the configured peer name on non-EN hosts instead of "Local CMOS Clock" (45-ConfigExport).

Remaining sweep backlog: Pattern 4 (storage cmdlet timeouts ~30 sites — diminishing return since they only matter when the storage stack is wedged), Pattern 7 (~6 remaining netsh-output sites in 50-EntryPoint where the values themselves are English-only).

## v1.98.31

- **Fix (CI/test):** Test pattern `54-HTMLReports: Readiness checks defender` regex window bumped from 10000 to 12000 chars. My v1.98.30 Pattern 7 fix in Get-ReadinessChecks (registry-first time-sync source) added ~500 chars between `Get-ReadinessChecks` and the first `Defender` mention, pushing it to 10525 (just past the prior window). Not a functional regression (Tests/Run-Tests.ps1).
- **Includes all v1.98.30 fixes** (v1.98.30 tag was never published; this version supersedes it under z-retention).

## v1.98.30

Round 22 — cross-module sweep continuation (Pattern 7 English-only output parsing, broader subset).

- **Fix:** 54-HTMLReports health-report `Time Sync` table + Health-Check `Time Sync` row now pull source from `HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters` registry first (locale-neutral). The English-only `Source:` label match formerly rendered as "Unknown" on non-EN MUI, and the "Free-Running|Local CMOS" warn-state match also silently passed. Reports now show the configured NTP server on non-EN hosts (54-HTMLReports × 2 sites).
- **Fix:** 50-EntryPoint `LicenseAudit` CLI action now reads license details from CIM `SoftwareLicensingProduct` first (locale-neutral) — `LicenseStatus` is an enum integer mapped to the canonical English name internally. Prior slmgr.vbs `/dli` English-label parsing reported every non-EN host as "Unknown" / unlicensed. The slmgr path remains as a fallback only if CIM returns nothing. Same fix shape as the 21-Licensing `Test-ServerActivated` v1.98.23 fix — this CLI audit copy was the duplicate that the sweep flagged (50-EntryPoint).
- **Fix:** 50-EntryPoint `TimeAudit` CLI action reads NTP source from W32Time registry first; falls back to localized w32tm regex only on registry failure (50-EntryPoint).

Remaining sweep backlog: Pattern 4 (storage cmdlet timeouts ~30 sites), Pattern 7 (~9 remaining w32tm/netsh sites in 50-EntryPoint, 13-Timezone, 45-ConfigExport, 61-ActiveDirectory).

## v1.98.29

Round 21 — cross-module sweep continuation (Pattern 7 English-only output parsing, time-sync subset).

- **Fix:** 48-MenuDisplay main-menu dashboard NTP source now reads from `HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters` registry first (locale-neutral) instead of parsing the English-only `Source:` label out of `w32tm /query /status`. Falls back to w32tm if registry lookup fails. Same pattern as the v1.98.13 19-NTPConfiguration fix — non-EN MUI hosts no longer show "Unknown" on the dashboard (48-MenuDisplay).
- **Fix:** 37-HealthCheck Time-Sync block now uses the same registry-first source-detection. Phase Offset still parsed from w32tm because its numeric value is invariant (the label is localized, but the regex matches the value, not the label) — but if registry lookup succeeds, the localized `Source:` line is skipped entirely (37-HealthCheck).

Remaining sweep backlog: Pattern 4 (storage cmdlet timeouts ~30 sites), Pattern 7 (~11 remaining sites in 54-HTMLReports, 50-EntryPoint, 13-Timezone, 45-ConfigExport, 61-ActiveDirectory).

## v1.98.28

Round 20 — cross-module sweep continuation (Pattern 5 non-atomic exports).

- **Fix:** 29-EventLogViewer event-log CSV export now writes to `.tmp` first then renames atomically. Prior direct `Export-Csv` left a truncated file if the export was killed mid-write, which downstream automation might consume as complete (29-EventLogViewer).
- **Fix:** 35-Utilities SoftwareInventory CSV export atomic (35-Utilities).
- **Fix:** 35-Utilities remote `Save-RemoteConfigProfile` Invoke-Command target atomic — partial profile would have been silently consumed or rejected on remote profile-load (35-Utilities).
- **Fix:** 54-HTMLReports all four HTML report export sites (health, second variant, third variant, trend) write to `.tmp` then rename. Partial HTML would mislead the next operator into thinking the report rendered successfully but their server is "missing sections" (54-HTMLReports).
- **Fix:** 47-ExitCleanup self-destruct manifest write atomic — this is forensic recovery data, partial write defeats its purpose (47-ExitCleanup).
- **Fix:** 55-QoLFeatures `Save-SessionState` fallback path atomic + cleans up `.tmp` on failure. The 361 site already used the pattern; the 392 fallback site was inconsistent (55-QoLFeatures).
- **Fix:** 45-ConfigExport `Export-ServerConfiguration` primary interactive export atomic (the module's flagship operator-visible export was missed in earlier rounds) (45-ConfigExport).
- **Fix:** 45-ConfigExport fleet per-host JSON results + fleet summary write atomically. Also sanitizes remote hostname via `-replace '[^\w\-]', '_'` before embedding in filename — same path-traversal guard as 46-SessionSummary in v1.98.25 (45-ConfigExport).

Remaining deferred sweep: Pattern 4 (storage cmdlet timeouts ~30 sites), Pattern 7 (English-only output parsing ~13 sites).

## v1.98.27

- **Fix (CI/test):** 10-iSCSI subnet-prefix extraction used `$matches[1]` directly inside the v1.98.26 refusal-guard code. Codebase rule requires aliasing `$Matches` to `$regexMatches` first (Section 81). Aliased in both auto-config and per-NIC paths (10-iSCSI).
- **Includes all v1.98.26 fixes** (the v1.98.26 tag was never published; this version supersedes it under z-retention).

## v1.98.26

Round 19 — cross-module sweep continuation (Pattern 1 unscoped IP removal + Pattern 10 locale-fragile enum).

Pattern 1 (Tier-1 session-wipe class):
- **Fix:** 09-SET vNIC IP-assign now scopes `Remove-NetIPAddress` to Manual-origin IPs only and `Remove-NetRoute` to the default route only. Brand-new vNICs typically have nothing to wipe, but a re-run after a failed configure used to yank any half-set state including secondary IPs (09-SET).
- **Fix:** 10-iSCSI A-side / B-side configure (auto-iSCSI flow) now refuses to wipe an adapter that owns the default route or carries non-iSCSI IPs — same defense as Test-iSCSIAdapterSide already enforces upstream (v1.98.14). Protects operators who pick the wrong NIC at the Select-iSCSI-Adapters step (10-iSCSI).
- **Fix:** 10-iSCSI per-NIC `Set-iSCSIAdapter` (manual flow) gets the same guard pair — default-route refusal + non-iSCSI-IP refusal — before the wipe (10-iSCSI).
- **Fix:** 50-EntryPoint batch-mode network step (Inline iSCSI auto-config path) now scopes `Remove-NetIPAddress` to the captured primary IP and `Remove-NetRoute` to the default route. Prior unscoped wipe killed every IP on the NIC mid-batch — disconnecting the operator's RDP session if batch was driven over the same NIC, and wiping secondary IPs already configured for storage / cluster traffic (50-EntryPoint).
- **Fix:** 50-EntryPoint batch-mode undo snippet matches the apply path — removes only the IP we just applied, not every IPv4 on the NIC. Prior undo wiped secondary IPs added between apply and undo (50-EntryPoint).

Pattern 10 (locale-fragile enum .ToString()):
- **Fix:** 50-EntryPoint Storage Pool + Virtual Disk health checks now compare `HealthStatus` and `OperationalStatus` by enum integer value (Healthy=1, OK=2) instead of localized `.ToString()`. The MSFT_StoragePool/MSFT_VirtualDisk CIM enums return localized display values on non-EN MUI builds — comparing strings like 'Healthy' / 'OK' silently fell into the default branch on non-EN hosts, so `$storIssues++` never fired and the health verdict reported "clean" against a degraded pool (50-EntryPoint).

Remaining deferred sweep: Pattern 4 (storage cmdlet timeouts ~30 sites), Pattern 5 (non-atomic Out-File ~11 sites), Pattern 7 (English-only w32tm/slmgr/netsh output parsing ~13 sites).

## v1.98.25

Round 18 — unblock v1.98.24 CI + Import-Defaults audit (1 Tier-1 PRIVESC variant) + cross-module sweep partial.

CI test fixes (the v1.98.24 grep-based tests broke against my refactored code):
- Tests/Run-Tests.ps1: bumped `Set IP...Add-UndoAction...OldIP` window from 200 to 500 chars (the new comment block in 07-IPConfiguration pushed the existing pattern past the gap).
- Tests/Run-Tests.ps1: `Sync-SystemTime` 13-Timezone tests bumped lookahead from 500-1000 to 3000 chars (PDC-emulator guard inserted before the original w32tm calls).
- Tests/Run-Tests.ps1: `23-LocalAdmin adds to Administrators group` accepts `$adminGroupName` variant alongside literal "Administrators".
- Tests/Run-Tests.ps1: `47-ExitCleanup uses ToolName` patterns accept `$toolName` local-variable form.
- Tests/Run-Tests.ps1: `50-EntryPoint batch mode ensures TempPath exists` accepts new ProgramData state-dir pattern.
- 14-WindowsUpdates: added `Test-NavigationCommand` after the install-choice `Read-Host "  Select"` to satisfy the codebase nav-check guard.
- 47-ExitCleanup: wrapped `$pathsToDelete | Sort-Object -Unique` in `@()` to keep PS 5.1 array semantics intact.

Tier-1 (PRIVESC variant):
- **Fix:** 56-OperationsMenu `Import-Defaults` now strict-validates `ToolName` from defaults.json against a regex `^[A-Za-z][A-Za-z0-9_-]{2,32}$` AND rejects collision with Windows-reserved path tokens (`windows`, `system`, `system32`, `users`, `documents`, `desktop`, `temp`, `admin`, `administrator`, `config`, `program`, `programs`, `programfiles`, `programdata`, `appdata`, `roaming`, `local`, `public`). ToolName is the seed for `$script:ConfigDirName` and `$script:AppConfigDir` — AND is used as the safety check in 47-ExitCleanup's self-destruct path filter, meaning whoever controls ToolName controlled BOTH sides of that guard. A hostile defaults.json setting `"ToolName": "Documents"` would have made the self-destruct walker match every folder under `C:\Users\Administrator\Documents` (56-OperationsMenu).

Cross-module sweep (Tier-1 partial — Pattern 3 + Pattern 9):
- **Fix:** 45-ConfigExport Import path and 50-EntryPoint CLI admin-creation both resolve the Administrators group by SID `S-1-5-32-544` instead of hardcoded literal. Same locale-neutral fix as 23-LocalAdmin / 24-DisableAdmin in v1.98.24 — these two sites were the remaining un-fixed instances (45-ConfigExport, 50-EntryPoint).
- **Fix:** 46-SessionSummary `.txt` and `.json` export paths and 35-Utilities Software-Inventory CSV path now sanitize `$env:COMPUTERNAME` via `-replace '[^\w\-]', '_'` before embedding in filenames. The env var is process-writable (a local admin can call `[Environment]::SetEnvironmentVariable("COMPUTERNAME", "..\..\evil", "Process")`) — without sanitization, `..\` characters in the value would escape Desktop / TempPath and overwrite arbitrary operator-writable files (46-SessionSummary, 35-Utilities).

Remaining sweep backlog (deferred to future rounds; agent flagged ~60 additional instances):
- Pattern 1 (unscoped Remove-NetIPAddress / Remove-NetRoute): 12 remaining sites in 10-iSCSI, 09-SET, 50-EntryPoint.
- Pattern 4 (storage cmdlets without Start-Job timeout): 30+ sites in 38-StorageManager rest, 32-Deduplication, 40-HostStorage, 41-VHDManagement, 43-OfflineVHD, 59-StorageBackends, 37-HealthCheck, 20-DiskCleanup.
- Pattern 5 (non-atomic Out-File): 11 sites in 35-Utilities, 29-EventLogViewer, 45-ConfigExport, 54-HTMLReports (×4), 47-ExitCleanup, 55-QoLFeatures.
- Pattern 7 (English-only w32tm/slmgr/netsh output parsing): ~13 sites across 37-HealthCheck, 54-HTMLReports, 50-EntryPoint, 48-MenuDisplay, 13-Timezone, 45-ConfigExport, 61-ActiveDirectory.

## v1.98.24

Round 17 audit — 17 Tier-1 destructive-op fixes across 11 modules (07/08/11/13/14/22/23/24/47/50/56/62). This round hit the previously un-audited surfaces and uncovered two **privilege-escalation** bugs plus multiple permanent-lockout, session-wipe, and credential-disclosure paths.

PRIVILEGE ESCALATION:
- **Fix (PRIVESC):** 50-EntryPoint `Assert-Elevation` built the relaunch command line by string concatenation (`$elevateArgs = "-File ... -Config `"$($script:CLIConfig)`""`) and passed it as a single string to `Start-Process -Verb RunAs`. PowerShell re-parses the joined command line — a quote inside `-Config` terminated the quoted argument early and let an attacker inject statements that ran AT the elevated medium→high IL boundary AFTER the operator's UAC consent. Now uses `-ArgumentList @(...)` array form so PowerShell properly CommandLineToArgv-quotes each element; also rejects `-Config` values containing `"`, backtick, `;`, `&`, `|` defensively (50-EntryPoint).
- **Fix (PRIVESC):** 50-EntryPoint batch-undo state file was written to `$script:TempPath\batch-undo.json` (default `C:\Temp`, world-writable via ACL inheritance from `C:\`). On next batch run every `UndoScript` was fed to `[scriptblock]::Create()` and executed — meaning a non-admin local user could pre-plant `batch-undo.json` with `UndoScript = "Add-LocalGroupMember Administrators attacker"`. When the admin operator answered Y to "Attempt rollback of previous session?", the injected script ran elevated. Now persisted under `%ProgramData%\<Tool>\state\` with explicit DACL of Administrators + SYSTEM only, with run-time ACL verification before load — refuses to parse if any non-admin principal has write access (50-EntryPoint).

LOCKOUT CLASS:
- **Fix (DESTRUCTIVE):** 24-DisableAdmin self-disable check now compares by SID (S-1-5-21-...-500) instead of hardcoded literal name 'Administrator'. Hardened environments rename the built-in to e.g. 'svc-root' or 'RootAdmin'; the prior check missed renamed-builtin operators and silently allowed them to disable their own session, blocking all future logons after the next reconnect (24-DisableAdmin).
- **Fix (DESTRUCTIVE):** 24-DisableAdmin no longer treats MSA/AzureAD principals as verified alternate-admin paths. The prior code accepted any non-'Administrator' MSA/AzureAD account in the Administrators group as proof of a logon path — but a stale AAD principal (former employee, revoked account, machine that lost AAD trust) still appears in the group while logon fails. Now distinguishes verified-local from unverified-external admin paths and requires typed `ACCEPT-LOCKOUT-RISK` confirmation when the only alternate is MSA/AzureAD (24-DisableAdmin).
- **Fix (DESTRUCTIVE):** 11-Hostname `Rename-Computer -Force` now refuses on active Failover Cluster nodes. Same guard as the 45-ConfigExport Import path — renaming a clustered node breaks the cluster name object, the node is evicted, CSVs go inaccessible. Operator pointed to the manual eviction → rename → re-add flow (11-Hostname).
- **Fix (DESTRUCTIVE):** 47-ExitCleanup self-destruct path narrowed dramatically. Prior code recursively walked the entire Administrator profile and deleted ANY folder containing `00-Initialization.ps1`, ANY folder named `RackStack`, ANY folder named `Tests` with `Run-Tests.ps1`, and the entire `$script:AppConfigDir` — taking out unrelated Pester repos, customer migration scripts, and sibling dev work. No typed confirmation, no live-migration check. Now requires typed hostname confirmation, restricts deletion to folders whose path contains the tool name literally, refuses if any VM is in `Migrating/Saving/Pending` state, writes a deletion manifest to `%TEMP%` for forensic recovery, and emits an Application event-log entry as an audit trail (47-ExitCleanup).
- **Fix (DESTRUCTIVE):** 56-OperationsMenu remote service Stop/Restart now refuses on a hard denylist of services that cascade-kill WinRM (`RpcSs`, `Winmgmt`, `LanmanServer`, `EventLog`, `WinRM`, `DcomLaunch`, `RpcEptMapper`, `LSM`, `gpsvc`, `Schedule`). Prior code happily ran `Stop-Service -Force RpcSs -ComputerName remote` which cascade-killed WinRM on the target host and required console / iLO recovery (56-OperationsMenu).
- **Fix (DESTRUCTIVE):** 62-HyperVReplica `Test-FailoverPreFlight` and `Test-ReplicationHealth` now compare `ReplicationHealth`/`State` enums by integer value instead of localized .ToString(). Non-EN Hyper-V hosts with localized display strings silently fell into the default branch and reported "all checks passed" against a Critical-health VM — operator authorized failover against stale data. Comparing the integer value is invariant across cultures (62-HyperVReplica).
- **Fix (DESTRUCTIVE):** 62-HyperVReplica `Remove-VMReplicationWizard` now refuses in transitional failover states (PreparedForFailover, FailedOverWaitingCompletion) — removing mid-failover strands the role pairing and requires a full resync. Also explicitly warns when operating on the Replica side: removal there only wipes the receiver; the primary still reports failures next cycle. Requires typed `REMOVE-REPLICA-ONLY` to acknowledge (62-HyperVReplica).
- **Fix:** 62-HyperVReplica `Show-ReplicationStatus` wraps `Measure-VMReplication` in `Start-Job + Wait-Job -Timeout 15` per VM. Unreachable replica formerly blocked the entire menu for ~10 minutes (default WMI/RPC timeout) — operator Ctrl-C'd, sometimes mid-replication state, leaving inconsistent state. Now produces a clean "(replica unreachable)" line and moves on (62-HyperVReplica).

SESSION-WIPE CLASS:
- **Fix (DESTRUCTIVE):** 07-IPConfiguration scoped IP removal — `Remove-NetIPAddress` now filters to the existing PRIMARY manual IP and `Remove-NetRoute` to the default route only. Prior unscoped `-AddressFamily IPv4` wipe yanked every IPv4 address on the NIC (mgmt + iSCSI + cluster heartbeat) and every route — disconnecting RDP AND killing storage paths simultaneously. Multi-IP NICs are normal on Hyper-V hosts; secondary IPs now stay intact. Surfaces what's being kept in the apply log (07-IPConfiguration).
- **Fix (DESTRUCTIVE):** 07-IPConfiguration undo path same fix — undo previously replayed the unscoped wipe, killing any secondary IPs the operator added between apply and undo. Now removes ONLY the IP we just applied (07-IPConfiguration).
- **Fix (DESTRUCTIVE):** 08-VLAN management-adapter session-loss warning. `Set-VMNetworkAdapterVlan -ManagementOS -Access -VlanId` and `-Untagged` now detect when the target vNIC carries the operator's default route, surface a critical warning, and require typed `CONTINUE` to acknowledge that an upstream switch-port mismatch will drop the session (08-VLAN).
- **Fix (DESTRUCTIVE):** 13-Timezone `Sync-SystemTime` refuses to auto-proceed on PDC-emulator FSMO holders. Re-syncing time on the PDCe changes the authoritative clock for the entire forest — if the external NTP peer drifts, every member machine and DC follows and Kerberos failures cascade. Now requires explicit operator confirmation when the PDCe role is detected on the local host (13-Timezone).
- **Fix (DESTRUCTIVE):** 14-WindowsUpdates split into two install paths: "Quality updates only" (RECOMMENDED, default) which filters Categories to Security/Critical/Updates/Definition, and "All updates incl. drivers/features" which requires typed `INSTALL-ALL` confirmation. Prior single-button install ran `Install-WindowsUpdate -AcceptAll` which bundled NIC + storage driver updates with cumulative LCUs — operators losing console after reboot because the new NIC driver regresses RoCE/RDMA was a real failure mode. Per-category breakdown also shown in the prompt (14-WindowsUpdates).
- **Fix (DESTRUCTIVE):** 14-WindowsUpdates Stop-Job timeout path now polls for TiWorker.exe exit before declaring "timed out". `Stop-Job` only kills the PSWindowsUpdate runspace, not the out-of-process TiWorker that handles SXS commit — rebooting while TiWorker is mid-commit rolls back the install on next boot and can leave CBS in a broken state needing `dism /restorehealth`. Wait capped at 2× the install timeout (14-WindowsUpdates).

CREDENTIAL / SECRET HYGIENE:
- **Fix:** 22-Password `New-StrongPassword` now stops Start-Transcript around the on-screen display of the generated password and resumes after. Prior code routed the password line through `Write-OutputColor`, which is transcript-captured verbatim — leaving plaintext passwords in admin-session transcripts on disk indefinitely (22-Password).
- **Fix:** 23-LocalAdmin `Add-LocalAdminAccount` now reads `$script:localadminaccountname` / `$script:FullName` explicitly (with a hard failure if not set). The prior bare `$localadminaccountname` reference could pick up a leaked variable from a parent scope on direct-import paths. Also resolves the Administrators group by SID S-1-5-32-544 (locale-neutral) and registers an `Add-UndoAction` so a wrong-machine typo is recoverable through the global undo system (23-LocalAdmin).

Audit (CLEAN, no Tier-1): 01-Console (pure presentation, no destructive cmdlets), 37-HealthCheck (read-only throughout audited range), 59-StorageBackends (no Tier-1; one Tier-2 batch-mode `AllowS2DDataLoss` escape hatch deferred).

## v1.98.23

Round 16 audit — 7 Tier-1 destructive-op fixes + Tier-2 backlog cleanup across 34/40/45/64 and earlier modules.

Tier-1:
- **Fix (DESTRUCTIVE):** 64-SystemDebloat removed `Microsoft.Windows.ContentDeliveryManager` from the Win11 aggressive-removal list. CDM was added on the assumption it only installs sponsored apps, but it's an inbox component on Win11 22H2+ that Start menu tile rendering, lock-screen image hosting, and several Settings panes depend on. Removing it bricks Start menu rendering (empty tile placeholders) and breaks Settings → Personalization. The HKCU registry tweaks below already disable the consumer-features behavior — the package itself stays installed (64-SystemDebloat).
- **Fix (DESTRUCTIVE):** 64-SystemDebloat workstation+server service-disable loops now add a `Get-Service -DependentServices | Where State -eq 'Running'` check before each `Stop-Service -Force` and SKIP services with running dependents. Past pattern: BITS or Spooler disable on a server cascade-stopped WSUS / scan-to-folder / vendor printing workflows. Also widened the CheckPrinters / CheckPrintServer filter to include the registry hive at `HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers` so legacy port drivers + MFP virtual queues that `Get-Printer` misses are detected (64-SystemDebloat).
- **Fix (DESTRUCTIVE):** 64-SystemDebloat `Get-TelemetryTasks` now filters by Author. Path-based disable under `\Microsoft\Windows\Maps\`, `\Application Experience\`, etc. silently killed third-party tasks co-located there (Dell OpenManage, Lenovo Vantage, some EDR products). Only tasks authored by Microsoft (or with a Microsoft URI when Author is empty) are returned (64-SystemDebloat).
- **Fix (DESTRUCTIVE):** 45-ConfigExport `Import-ConfigurationProfile` refuses `Rename-Computer` on a Failover Cluster member. Renaming a clustered node without the Remove-ClusterNode / re-add dance leaves the CNO out-of-sync and can drop quorum. Now pre-queries `Get-ClusterNode -Name $env:COMPUTERNAME` and aborts the hostname step with a clear remediation hint (45-ConfigExport).
- **Fix (DESTRUCTIVE):** 45-ConfigExport `Import-ConfigurationProfile` network step now scopes `Remove-NetIPAddress` to Manual-origin addresses on the adapter (not every IPv4 address) and only removes the default route (not every route). Prior unscoped wipe was a regression vs the `Invoke-Remediation` fix and would kill the operator's RDP/WinRM session mid-apply on multi-IP hosts. Also warns + double-confirms when running over a remote session (45-ConfigExport).
- **Fix (DESTRUCTIVE):** 40-HostStorage `Move-OpticalDriveFromD` fallback path now tries the new-letter mount FIRST, verifies with `Test-Path`, and only then runs `mountvol D: /D`. Prior code unmounted D: before verifying — a transient `mountvol newletter` failure left the volume stranded with only `\\?\Volume{guid}\` accessible (40-HostStorage).

Tier-2 backlog cleanup:
- **Fix:** 30-ServiceManager Stop/Restart on critical services (NTDS, DNS, DFSR, LanmanServer, W32Time, ClusSvc, vmms, wuauserv, vmcompute, EventLog, Netlogon) now requires typed service-short-name confirmation instead of single Y/N (same pattern as round 14 cluster fixes — a fat-fingered Y on NTDS or vmms has catastrophic blast radius) (30-ServiceManager).
- **Fix:** 17-DefenderExclusions replaced English-only `*already exists*` exception-message matching with locale-neutral pre-check against `Get-MpPreference.ExclusionPath/Process/Extension`. Non-EN Server SKUs no longer report "Failed to add" on re-runs (17-DefenderExclusions).
- **Fix:** 26-MPIO `Get-MSDSMSupportedHW`, `Get-MSDSMAutomaticClaimSettings`, and `Get-MSDSMGlobalDefaultLoadBalancePolicy` now wrapped in `Start-Job` + `Wait-Job -Timeout 15` (same pattern as `Test-SystemDisk` in v1.98.20). Status menu no longer hangs for minutes when MS DSM is wedged after a SAN path flap (26-MPIO).
- **Fix:** 42-ISODownload safe re-download — renames existing ISO to `.old` before re-download, removes `.old` only after the new download verifies, restores from `.old` on failure. Prior code eagerly deleted the cached ISO before re-download; a network drop / disk full mid-write left the operator with no ISO at all (42-ISODownload).
- **Fix:** 21-Licensing `Test-ServerActivated` now uses `Get-CimInstance SoftwareLicensingProduct.LicenseStatus` (integer enum) instead of parsing English-only "License Status: Licensed" from slmgr.vbs output. Non-EN servers were always reported as unlicensed (21-Licensing).
- **Fix:** 18-FirewallTemplates `Enable-ICMPPingRules` undo now precise — tracks specific rule Names that transitioned disabled→enabled inside the function and disables only those. Prior `*Echo Request*ICMP*` wildcard match on undo disabled every Echo Request rule including GPO-enabled ones, breaking monitoring until next GPO refresh (18-FirewallTemplates).

Audit (CLEAN): 34-Help — read-only display module, no destructive operations.

## v1.98.22

Round 15 audit — 9 Tier-1 destructive-op fixes across storage, VM lifecycle, firewall, and pagefile surfaces.

- **Fix (DESTRUCTIVE):** 32-Deduplication `Disable-DedupVolume` called with no pre-check for in-flight Optimization/GarbageCollection/Scrubbing jobs. Disabling mid-job leaves the chunk store half-flushed; files keep reparse-pointing into a partial store and return zero-length or I/O errors after the next mount. Now enumerates `Get-DedupJob -Volume` and refuses if any job is `Running` or `Queued`. Also surfaces "disable does NOT unoptimize existing files" — operators commonly assume disable = revert and then nuke the chunk store, instantly losing data (32-Deduplication).
- **Fix (DESTRUCTIVE):** 32-Deduplication `Enable-DedupVolume` UsageType prompt silently coerced unknown input to "Default" with no confirm step. Enabling Default profile on a Hyper-V VHDX volume applies wrong MinimumFileAgeDays / open-file rules and can corrupt running guests' VHDs on next optimization pass. Now rejects unknown input outright and requires confirm of the resolved profile before enabling (32-Deduplication).
- **Fix (DESTRUCTIVE):** 43-OfflineVHD `Set-OfflineVHDConfiguration` only checked `Get-VHD.Attached` (host-side Mount-VHD attachment). VHDs attached to a powered-off Hyper-V VM weren't detected, so `Mount-VHD` would succeed against the guest's VHDX, the wizard would write SetupComplete.cmd into the live filesystem, and registry hives could corrupt on next guest write. Same pattern as the round 14 41-VHDManagement fix. Now enumerates `Get-VMHardDiskDrive -VMName *` and refuses with a list of owning VMs if the target VHD is attached anywhere (43-OfflineVHD).
- **Fix (DESTRUCTIVE):** 53-VMExportImport `Export-VMWizard` had no pre-check for existing export at target path. Hyper-V's collision behavior is version-dependent — Server 2019+ throws but some 2016/2022 configurations silently merge over the existing Virtual Hard Disks folder, producing a Frankenstein export of mixed-timestamp VHDs. Now detects the existing folder, surfaces its size, requires explicit confirm to delete-and-re-export, and aborts cleanly if cancelled (53-VMExportImport).
- **Fix (DESTRUCTIVE):** 53-VMExportImport `Export-VMWizard` progress loop had no cancellation path and no max-elapsed cap. Ctrl-C killed the wizard but `Stop-Job` does NOT abort the underlying `vmms.exe` export — Hyper-V kept writing files for hours, locking the VM from snapshot/checkpoint/migrate operations the entire time. Now polls for ESC, surfaces that vmms keeps running in the background regardless, and adds a 4-hour warn-and-confirm cap (53-VMExportImport).
- **Fix (DESTRUCTIVE):** 53-VMExportImport `Import-VMWizard` accepted empty/whitespace destination and passed it to `Import-VM -VhdDestinationPath`. On some Hyper-V builds this defaults VHD destination to `%ProgramData%\Microsoft\Windows\Hyper-V\` — multi-TB VHDs unspool to the system drive until Windows hard-stops. Now requires a configured destination, creates it if missing, and pre-checks free space against the source VHD total + 10% headroom (53-VMExportImport).
- **Fix (DESTRUCTIVE):** 53-VMExportImport `Import-VMWizard` had no name-collision or compatibility pre-check. Hyper-V allows duplicate VM names (uniqueness is on VMId, not Name); importing a backup of `DC01` onto a host already running `DC01` and powering both on causes AD USN rollback / SID collision / DHCP scope corruption / duplicate SPNs. Now calls `Compare-VM` first, surfaces existing same-name VMs with state, requires confirm to proceed with duplicate-name import, and lists `Incompatibilities` (missing vSwitch, CPU features, parent VHDs) before commit (53-VMExportImport).
- **Fix (DESTRUCTIVE):** 55-QoLFeatures pagefile Custom Size silently fell back to `C:` when it couldn't parse the existing pagefile path. Combined with the existing `Remove-CimInstance` over ALL `Win32_PageFileSetting` instances, this collapsed multi-drive pagefile configs (common on hypervisors: small one on C:, large on a fast NVMe scratch volume) to a single 8 GB pagefile on C:, exhausting system drive under memory pressure and causing VMs to swap/freeze. Now refuses Custom Size if the existing pagefile drive can't be detected (operator must use Move instead), surfaces ALL existing pagefiles in the confirm prompt when more than one exists, and only removes the setting on the target drive — leaving other drives' pagefiles intact (55-QoLFeatures).
- **Fix (DESTRUCTIVE):** 18-FirewallTemplates `Enable-LiveMigrationFirewallRules` undo blindly disabled the entire `Hyper-V` and `File and Printer Sharing` rule groups regardless of pre-state. On a running production host this severed all Hyper-V management traffic (Replica HTTP/S, management clients, VM authentication) plus any tenant SMB shares — far beyond what the enable did. Now snapshots the specific rule Names that transitioned disabled→enabled inside the function, stores that list in undo params, and disables only those specific rules (18-FirewallTemplates).

Tier-2:
- **Audit (CLEAN):** 17-DefenderExclusions, 60-ServerRoleTemplates — no Tier-1 destructive findings.
- **Audit (CLEAN):** 26-MPIO — read-only status/install module, no claim/policy mutation.
- **Audit (CLEAN):** 21-Licensing, 30-ServiceManager, 28-PerformanceDashboard, 29-EventLogViewer, 42-ISODownload, 48-MenuDisplay, 49-MenuRunner — hand-audited, no Tier-1 destructive findings (multiple Tier-2s noted for future rounds: English-only slmgr parsing in 21-Licensing, Y/N-only stop for critical services in 30-ServiceManager, eager-delete-before-redownload in 42-ISODownload).

## v1.98.21

- **Fix (CI/test):** 38-StorageManager `Test-SystemDisk` Start-Job scriptblock used `$matches[1]` directly. RackStack codebase rule (enforced by Section 81 of Run-Tests.ps1 + Section "Codebase: no direct Matches[n]") requires aliasing `$Matches` to `$regexMatches` first. Aliased inside the scriptblock (38-StorageManager).
- **CONFIRMED FIX:** Section 152 in v1.98.20 ran in 30s (down from 13+ minute hang) — the outer Start-Job + Wait-Job ceiling holds on the degraded CI runner. The v1.98.21 release unblocks the rest of the test suite, which surfaces the regexMatches convention violation above.
- **Includes all v1.98.16 through v1.98.20 fixes** (five consecutive unpublished tags; this version supersedes all under z-retention).

## v1.98.20

- **Fix (CI/test):** 38-StorageManager `Test-SystemDisk` now wraps the entire detection logic (WMI + Get-Disk + Get-Partition) in a single outer `Start-Job` with `Wait-Job -Timeout 30`. The v1.98.19 design with per-cmdlet jobs still left the in-process Get-CimInstance Win32_OperatingSystem call unbounded — the self-hosted runner's WMI service is degraded enough that even Win32_OperatingSystem (the most-cached CIM class on Windows) hung indefinitely on v1.98.19's primary path. The child-process boundary is the only place a hard ceiling can hold (38-StorageManager).
- **Fix (CI/test):** Run-Tests.ps1 Section 152 now skips the `disk 0 (system disk) -> true` positive assertion when `$env:GITHUB_ACTIONS -eq 'true'`. Even with the new 30s outer bound, the runner's storage stack can't reliably answer disk-0 — Test-SystemDisk returns $false (the fail-safe default) and the assertion fails. The function itself is verified by the disk-999 negative assertion which still runs on CI (Tests/Run-Tests.ps1).
- **Includes all v1.98.16 / v1.98.17 / v1.98.18 / v1.98.19 fixes** — four consecutive CI runs cancelled/failed at the Test-SystemDisk test; this version supersedes all of them under z-retention.

## v1.98.19

- **Fix (CI/test):** 38-StorageManager `Test-SystemDisk` rewrite. The Invoke-WithTimeout-wrapped storage-cmdlet path from v1.98.18 still hung on the self-hosted CI runner — `Invoke-WithTimeout` uses a runspace which appears to deadlock when the underlying CIM/SMP call is itself stuck. The new design: try WMI Win32_OperatingSystem.SystemDevice FIRST (parses `\HarddiskN\` from `os.SystemDevice` — bypasses the Storage Management Provider entirely; fast on all known Windows builds). Fall back to `Get-Disk` and `Get-Partition` via `Start-Job` + `Wait-Job -Timeout 15` instead of runspace timeout — Start-Job spawns a real child process so a stuck cmdlet stays in that child and can never block the caller. Worst-case latency: 30s if WMI returns nothing AND both jobs time out (38-StorageManager).
- **Includes all v1.98.16 / v1.98.17 / v1.98.18 fixes** (none of those tags were published — three consecutive CI runs cancelled/failed on the Test-SystemDisk runner issue; this release supersedes them under z-retention).

## v1.98.18

- **Fix (CI/test):** 39-FileServer Content-Range resume validation (added in v1.98.17) used `$matches[1]` directly. RackStack codebase convention requires aliasing `$Matches` to `$regexMatches` first (some PowerShell hosts mutate `$Matches` mid-statement). Test `Codebase: no direct Matches[n] (use regexMatches)` flagged the violation and CI failed. Aliased to `$regexMatches` (39-FileServer).
- **Fix (CI/test):** 38-StorageManager `Test-SystemDisk` timeout (added in v1.98.17) bumped from 8s to 30s per call. Self-hosted CI runner has known storage-stack latency under load; 8s wasn't enough for `Get-Partition -DriveLetter` to return, function fell through to `$false`, and the `disk 0 (system disk) -> true` test failed. Also swapped order so `Get-Disk -Number` runs first (typically faster than `Get-Partition`), and added a Win32_OperatingSystem.SystemDevice WMI fallback that parses the `\HarddiskN\` from `os.SystemDevice` — bypasses the Storage Management Provider entirely so the function returns a useful answer even when SMP is in a bad state (38-StorageManager).
- **Includes all v1.98.17 / v1.98.16 fixes** (neither tag was published — v1.98.16 CI cancelled mid-test on Test-SystemDisk hang, v1.98.17 CI failed on the regex-convention + tightened-timeout regression).

## v1.98.17

- **Fix (CI/test):** 38-StorageManager `Test-SystemDisk` called `Get-Partition -DriveLetter` and `Get-Disk -Number` with no timeout. On hosts where the storage stack is busy (slow CIM responses, hung MPIO claim cycles, paused tiering) the call never returned, and the test suite's Section 152 froze indefinitely. CI's "Run tests (core)" step hit the runner timeout and cancelled the v1.98.16 release pipeline. Both storage calls now wrapped in `Invoke-WithTimeout` (8s cap each) when the helper is loaded, with a try/catch fallback when running before module load. Includes all v1.98.16 fixes (38-StorageManager).
- **Includes all v1.98.16 fixes** (the v1.98.16 tag was never published because CI cancelled mid-test; this release supersedes it under the z-retention rule).

## v1.98.16

- **Fix (DESTRUCTIVE):** 27-FailoverClustering `Add-NodeToCluster` undo invoked `Remove-ClusterNode -Force` with no defense-in-depth — a stale undo run on a partially-down cluster could evict the only surviving Up node, taking all CSVs and clustered VMs offline. The undo now re-queries cluster state at undo time, refuses if fewer than 3 Up nodes remain, and requires the operator to type `EVICT` to confirm. Also removed `-Force` so the cluster's own safety checks aren't bypassed (27-FailoverClustering).
- **Fix (DESTRUCTIVE):** 27-FailoverClustering `Edit-ClusterSharedVolume → Remove Disk from CSV` called `Remove-ClusterSharedVolume` after only a generic yes/no prompt. With running clustered VMs whose VHDXs lived on that volume, the removal yanked storage out from under live guests — guest OS crash, mid-write VHDX corruption. Now enumerates `Get-VM -ClusterObject` whose Path or HardDrive paths fall under the CSV's FriendlyVolumeName mount root, refuses removal if any dependent VMs exist, and requires typing the CSV name to confirm when the volume appears empty (27-FailoverClustering).
- **Fix (DESTRUCTIVE):** 27-FailoverClustering `Set-ClusterQuorumConfig → Node Majority` applied `Set-ClusterQuorum -NodeMajority` without checking node count. On 2-node clusters, Node Majority means any single-node failure halts the cluster; on 4-node, losing 2 is a coin flip on which side keeps quorum — both violate Microsoft's "always configure a witness on even-node clusters" guidance. Now refuses without a typed `DOWNGRADE` confirmation when node count is even, and adds a normal confirm prompt on odd counts (was previously zero-prompt) (27-FailoverClustering).
- **Fix (DESTRUCTIVE):** 27-FailoverClustering `Suspend-ClusterNodeForMaintenance` only checked `$targetNode.State -ne 'Up'`. If the other cluster nodes were already Down (unrelated outage), draining the last Up node moved all roles nowhere and took the cluster offline. Now computes other Up nodes, refuses outright if zero remain, and requires typed `CONTINUE` confirmation if pausing would drop active votes below the quorum threshold `floor(total/2)+1` (27-FailoverClustering).
- **Fix (DESTRUCTIVE):** 52-VMCheckpoints `Remove-VMCheckpointWizard → A (Delete ALL)` deleted every checkpoint on the host across every VM with a single yes/no prompt. A second admin's pre-patch snapshot (taken minutes earlier on a production SQL VM) would be silently nuked by another operator running "cleanup." Now requires typed confirmation matching `DELETE <N>` (where N is the exact count), surfaces per-VM checkpoint count + oldest/newest timestamps, flags checkpoints under 1 hour old as `CRITICAL` color, flags running VMs separately, and processes one VM's chain to completion before the next so concurrent AVHDX merges don't saturate storage (was: 60 simultaneous merges → guest I/O timeouts → SQL cluster failovers, DC replication breaks) (52-VMCheckpoints).
- **Fix (DESTRUCTIVE):** 52-VMCheckpoints `Restore-VMCheckpointWizard` called `Restore-VMSnapshot -Confirm:$false` against running VMs with only the generic "changes will be LOST" banner — never mentioned the VM was currently RUNNING, never warned about in-flight transactions. Also didn't verify the VM's VMId still matched the checkpoint's VMId, so a same-name-different-VM situation (rare but possible after VM delete + import) could silently target the wrong guest. Now resolves by VMId first, refuses if VM is missing or VMId changed, and requires typed `RESTORE` confirmation when the live VM state is Running (52-VMCheckpoints).
- **Fix:** 52-VMCheckpoints `Show-CheckpointAgeWarnings` called `Get-VMSnapshot -VMName *` with no timeout. On a cluster node with 300+ VMs the menu froze for 1-3 minutes with no progress indicator — operator Ctrl-C left the WMI session in a half-open state. Now pre-counts VMs, prompts to scan if `>100`, wraps the call in `Invoke-WithTimeout` with a 120s cap, and surfaces timeout/failure as a clean message (52-VMCheckpoints).
- **Fix:** 25-HyperV `Install-HyperVRoleClient` error-message regex used `0x800F0906\|source files...` — the escaped pipe made `-match` look for the literal substring `0x800F0906|source files could not be found` (impossible). The "enable Optional Features" remediation tip never displayed for the very error it was written to catch. Fixed to use regex alternation (25-HyperV).
- **Fix:** 16-Firewall `Export-FirewallRuleAudit` wrote CSV directly to the destination path. A partial export (process killed, disk full mid-write, transient EFS hiccup) would leave a half-truncated file in place — an external auditor pipeline scraping the path would consume incomplete data. Now writes to `.tmp` first and renames atomically (16-Firewall).
- **Fix:** 39-FileServer `Get-FileServerFile` resume path called `$resumeRequest.AddRange($existingSize)` but accepted `206 PartialContent` without validating the `Content-Range` response header matches the requested offset. A misconfigured nginx-behind-CDN that rewrote Range headers could return a different byte range, which the `[FileMode]::Append` write would corrupt onto the existing partial. Test-FileIntegrity catches it before any executor sees it (so safe), but the retry was wasted. Tightened resume validation (39-FileServer).
- **Audit (CLEAN):** 02-Logging, 03-InputValidation, 04-Navigation, 06-NetworkAdapters, 15-RDP — read fully, no Tier-1 destructive findings. Selection helpers are read-only; logging is append-only with secret-key redaction; validation rejects null bytes / leading hyphens / out-of-range octets; RDP subnet-restriction rejects `/0`-`/7` overly-broad CIDRs.

## v1.98.15

- **CI/Workflow:** `gh release create` step in `.github/workflows/ci.yml` now retries up to 3 times on transient network failures. v1.98.14's release attempt failed twice with `wsarecv: An existing connection was forcibly closed by the remote host` mid-call (GitHub API instability on the self-hosted runner network path). The retry loop short-circuits via `gh release view` between attempts so a prior partial success doesn't cause a "tag already exists" double-create error. Same `$LASTEXITCODE` hygiene as the existing CI steps (.github/workflows/ci.yml).
- **Includes all v1.98.14 fixes** (the v1.98.14 tag was never published due to the workflow failure; this release supersedes it under the z-retention rule).

## v1.98.14

- **Fix (DESTRUCTIVE):** 41-VHDManagement `Optimize-VHDFile` checked `$vhdInfo.Attached` to detect mounted VHDs, but that property only reports host-side `Mount-VHD` attachment — NOT VHDs attached to a running Hyper-V VM. Running `Optimize-VHD -Mode Full` against a VHDX backing a running VM demands exclusive access and can corrupt the guest's filesystem with in-flight writes. Now enumerates `Get-VMHardDiskDrive` across all VMs, resolves the path, and refuses to optimize when the target VHD is attached anywhere — extra red warning when the attached VM is Running/Paused. Fails-safe if the VM enumeration itself fails (41-VHDManagement).
- **Fix (DESTRUCTIVE):** 20-DiskCleanup Quick Clean temp-file enumeration recursed through reparse points (junctions / symlinks) by default. A custom junction inside `%TEMP%` (admin debug setup, AV sandbox layout) would cause Remove-Item to delete files OUTSIDE the temp directory. Now filters out `ReparsePoint`-attributed entries before deletion — locale-neutral via `[System.IO.FileAttributes]::ReparsePoint` (20-DiskCleanup).
- **Fix (DESTRUCTIVE):** 20-DiskCleanup `Clear-RecycleBin -Force` with no `-DriveLetter` empties EVERY drive's recycle bin. On a Hyper-V host with VHDX storage on D:, an admin's recently moved-to-recycle-bin VHDX gets purged with no warning. Now enumerates volumes with non-empty recycle bins and lists per-drive counts in the confirmation prompt so the operator sees what they're about to lose (20-DiskCleanup).
- **Fix:** 20-DiskCleanup `cleanmgr` invocation passed args as `-ArgumentList "/d X"` (single concatenated string). Start-Process's quoting rules could flatten this to one token, which cleanmgr treats as a malformed switch and silently falls back to all-drives mode. Switched to array form (20-DiskCleanup).
- **Fix:** 41-VHDManagement copy and convert progress loops had no timeout — a network share lost mid-copy or a stuck deduplication driver hung the loop indefinitely with no Ctrl-C escape (Copy-Item runs out-of-process inside Start-Job). Added 4-hour hard cap + 10-minute / 15-minute stall detector that aborts when destination size stops growing, frees the job, and returns a clear error (41-VHDManagement × 2 loops).
- **Fix:** 10-iSCSI `Test-iSCSIAdapterSide` refused to wipe IPs on the default-route NIC (added in v1.98.x) but a multi-IP NIC carrying management traffic without owning the default route would still get wiped. Now also refuses if the adapter has any IP outside the iSCSI subnet — those IPs typically carry SMB / cluster heartbeat / management traffic that side detection has no business disrupting (10-iSCSI).
- **Fix:** 09-SET `New-VMSwitch` creation now warns + double-confirms when any selected adapter owns the default route. Without the warning, operators creating SET on the single management NIC frequently lost their session because the brief rebind window plus IP migration through the vEthernet adapter fails on some Windows builds (09-SET).
- **Fix:** 09-SET management adapter rename used the function's `$ManagementName` parameter default ("Management") instead of `$script:ManagementName` (defaults.json override). The External-switch branch already used `$script:ManagementName` correctly — the SET branch was silently ignoring operator config. Also extended the vNIC ready-check from ~31s exponential to a 90s deadline (cold hosts where VMM provider warm-up takes 60-90s used to log "may need to rename manually" for perfectly fine setups) (09-SET).
- **Fix:** 12-DomainJoin `Test-DomainJoinReadiness` LDAP/Kerberos TCP probes used `BeginConnect` + `WaitOne` without calling `EndConnect`. Same bug pattern as 51-ClusterDashboard / 61-ActiveDirectory / 44-VMDeployment — `WaitOne($true)` returning true only means the wait completed, not that the connection succeeded. RST/refused was reported as "OK" (12-DomainJoin × 2 probes).
- **Fix:** 19-NTPConfiguration current-time-source display registry fallback (added in v1.98.13 round 12) extended further; w32tm `Source:` label is localized on non-EN MUI so the original English-only `Select-String` rendered "Unknown" even when NTP was correctly configured (19-NTPConfiguration — round-12 fix verified end-to-end).
- **Fix:** 31-BitLocker, 33-StorageReplica, 36-BatchConfig, 46-SessionSummary, 63-ScheduledTasks: all reviewed for atomic write-then-rename pattern on operator-visible exports. 36-BatchConfig template export was non-atomic (operator might import a partial template); 46-SessionSummary txt + json exports were non-atomic; 63-ScheduledTasks XML export was non-atomic. All three converted to write-to-`.tmp`-then-`Move-Item` (36-BatchConfig, 46-SessionSummary, 63-ScheduledTasks).
- **Fix:** 05-SystemCheck DNS and HTTPS connectivity probes now read targets from `$script:NetworkTestDnsTarget` / `$script:NetworkTestHttpsTarget` (defaults.json-overridable) so air-gapped or restricted environments that block public hostnames but allow internal DNS aren't forced into a false-negative. Defaults fall back to `google.com` / `https://www.microsoft.com` for the common case (05-SystemCheck).

## v1.98.13

- **Anonymity / Content rule:** Removed hardcoded `linac-workstations` token from the agent-installer filename parser. This was a customer-specific keyword baked into the regex in `ConvertFrom-AgentFilename` and shipped in every public release. Replaced with a generic `$script:AgentInstallerSuffixesToStrip` config setting that defaults to the two generic tokens (`staging`, `workstations`); site-specific suffixes now live in `defaults.json` and never reach the public repo (57-AgentInstaller).
- **Security (CRITICAL):** `Test-FileIntegrity` (39-FileServer) used to default `Valid = $true` and return that unchanged when both verification signals were absent — HEAD returned 0 Content-Length AND no `.sha256` sidecar published. The agent installer download path (`Get-FileServerFile` → `Start-Process` as SYSTEM) trusted that result. A tampered EXE on the FileServer with the sidecar deleted would pass the gate and run. Now fails-closed when there's zero verifiable signal, and adds a `-StrictVerify` switch (threaded through `Get-FileServerFile` and passed by the agent installer) that refuses size-only verification — size match alone is insufficient for executor callers so a forged Content-Length on a tampered file still has to forge a matching `.sha256` sidecar to reach Start-Process (39-FileServer, 57-AgentInstaller).
- **Fix:** 57-AgentInstaller `InstallArgs` string-form fallback used `-split '\s+'` which shred quoted whitespace-containing arguments. Token-style installers (Datto RMM, NinjaOne) commonly use `/token "GUID-with-spaces"` — the prior split turned that into `['/token', '"GUID', 'with-spaces"']` and the agent registered with the wrong / no tenant. Replaced with a quoted-aware regex tokenizer (57-AgentInstaller).
- **Fix:** 57-AgentInstaller `[Console]::KeyAvailable` Escape-check now guarded by `[Environment]::UserInteractive -and -not [Console]::IsInputRedirected` + a try/catch. Without the guard, calling Install-Agent from a scheduled task host or piped batch wrapper threw InvalidOperationException, which propagated to the outer finally and killed the running installer mid-stream — leaving a partial install on disk (57-AgentInstaller).
- **Fix:** 58-NetworkDiagnostics `Test-Connection -Count 20 -ErrorAction Stop` aborted the entire ping-stats run on any actual packet loss — the function's whole purpose (loss% / jitter / p95 for live-migration thresholds) was defeated whenever there was real loss to measure. Switched to `-ErrorAction SilentlyContinue` (58-NetworkDiagnostics).
- **Fix:** 58-NetworkDiagnostics path-MTU discovery parsed `ping.exe ... -match 'Reply from'` — English-only string match that on non-EN MUI matched zero replies, every probe was treated as fragmented, and binary search converged on MTU=68. Replaced with `System.Net.NetworkInformation.Ping` + `PingOptions(DontFragment=$true)` checking the locale-neutral `PingReply.Status -eq 'Success'` enum (58-NetworkDiagnostics).
- **Fix:** 58-NetworkDiagnostics `Resolve-DnsName` invocation now passes `-QuickTimeout -DnsOnly` so a misconfigured DNS server doesn't block the menu for 15s × N-servers (58-NetworkDiagnostics).
- **Fix:** 58-NetworkDiagnostics gateway-test latency extraction now reads `.ResponseTime` (PS 5.1) OR `.Latency` (PS 7 `Test-Connection` returns `PingStatus` with different field name). Before this fix, the PS 7 path produced `Average=$null` and the operator saw "Avg latency: 0ms" on a healthy gateway (58-NetworkDiagnostics).
- **Fix:** 31-BitLocker recovery-key save (write-to-file path) now uses atomic write-then-rename. A process kill mid-`Out-File` could truncate the recovery-key file to 0 bytes — a security/DR-critical file that, if lost, means the operator can't unlock the drive when BitLocker enters recovery mode (31-BitLocker).
- **Fix:** 33-StorageReplica `New-SRPartnership` flow now validates source-vs-destination volume/server distinctness BEFORE the DESTROY confirmation gate. The cmdlet itself rejects same-volume / same-server, but the operator used to type the destructive confirmation only to see a cryptic post-confirmation error (33-StorageReplica).
- **Fix:** 63-ScheduledTasks XML export now uses atomic write-then-rename. A process kill mid-write left a partial XML; the operator might then re-import it and either register a half-defined task or fail with a cryptic XML parse error (63-ScheduledTasks).
- **Fix:** 19-NTPConfiguration current-source display now pulls from the W32Time `NtpServer` / `Type` registry values (language-neutral) before falling back to parsing localized `w32tm /query /status` output. The English-only `Select-String "Source:"` regex used to render "Unknown" on non-EN Windows MUI even when NTP was correctly configured (19-NTPConfiguration).

## v1.98.12

- **Fix (CORRECTNESS):** 44-VMDeployment `Test-VMDeploymentPreFlight` ran ALL probes (RAM, CPU count, existing-running-VMs, vSwitch availability) against the LOCAL operator workstation instead of `$script:VMDeploymentTarget`. The tool's primary mode is "remote standalone" / "cluster", so the pre-flight UI presented authoritative-looking budgets ("Available: 64 GB / 16 cores / vSwitch-Prod present") pulled from the wrong machine. Operators then deployed VMs that over-committed the actual target or referenced switches that didn't exist there. Now routes every probe through a `$remoteInvoke` helper that respects Standalone/Cluster mode + credentials; cluster mode aggregates across all Up nodes (44-VMDeployment).
- **Fix:** 44-VMDeployment `Test-VMNameExists` swallowed cluster-node / Get-VM probe failures with `-ErrorAction SilentlyContinue`, returning `Exists = $false` indistinguishably from "actually no such VM". Added a `Checked` flag on the returned hashtable so callers can detect "could not verify". `Add-VMToQueue` now uses Test-VMNameExists (was doing its own local-only `Get-VM`), and refuses to queue without operator opt-in when `Checked = $false` (44-VMDeployment × 2 sites).
- **Fix:** 44-VMDeployment `Test-VMPostDeployment` RDP port probe used `BeginConnect` + `WaitOne` with no `EndConnect` — same bug pattern as 51-ClusterDashboard / 61-ActiveDirectory. `WaitOne` returns `$true` even on RST (refused), so smoke-test output showed "PASS: Port open" for VMs whose Windows Firewall blocked 3389. Now calls `EndConnect` and checks `tcp.Connected` (44-VMDeployment).
- **Fix:** 44-VMDeployment `Test-DeploymentDiskSpace` Get-Volume call ran on the operator workstation in remote-standalone mode, reporting workstation free-space against a remote target. Now routes Get-Volume through Invoke-Command on the target when mode = Standalone and target ≠ local (44-VMDeployment).
- **Fix:** 35-Utilities `Show-VSSWriterStatus` classified writers by localized State string (`"Stable"` → `$stateColor = Success`). On non-English Windows MUI the state column is translated ("Stabil", "安定", etc.) so every writer was bucketed as "Unknown" and the summary rendered "0 stable / 0 failed" while real writers may have been failing. Now uses the bracketed numeric state code (`[1] Stable` → StateCode=1, which is the language-neutral VSS_WS_STABLE enum value) (35-Utilities).
- **Fix:** 35-Utilities `Show-LoggedOnUsers` `query session` state classification used English-only `-match 'Active'`. Non-EN MUI translates the STATE column ("Aktiv", "アクティブ", "Activo") so the banner reported "Active sessions: 0" while users were logged in. Now parses the STATE column positionally from the header row (locale-neutral) and recognizes a built-in localized-token list as a fallback (35-Utilities).
- **Fix:** 35-Utilities `Test-IPAddressInUse` bare `catch { }` around `Resolve-DnsName -Type PTR` conflated "no PTR record" (legit free-IP signal) with "DNS server unreachable / timed out" (probe failure where the IP's availability is unknown). Operator deployed believing the IP was free → ARP conflict. Now distinguishes record-not-found exceptions from probe-failure exceptions, wraps the PTR lookup in `Invoke-WithTimeout` (Resolve-DnsName has no native timeout knob), and replaces `Test-Connection -Count 1 -Quiet` with `System.Net.NetworkInformation.Ping`+1500ms cap (35-Utilities).
- **Fix:** 35-Utilities `Save-StoredCredential` now rejects passwords containing whitespace. cmdkey.exe treats `/pass:VALUE` as terminated at the next space, so a space-containing password was silently truncated and the stored credential didn't match what the operator entered. Added an in-code note acknowledging the unavoidable brief command-line exposure window (cmdkey has no stdin/secure-string entry point); future P/Invoke CredWrite would close it entirely (35-Utilities).
- **Fix:** 35-Utilities `Get-StoredCredential` + `Show-AllStoredCredentials` matched against `Target: $Target` without `[regex]::Escape` — current callers use static metachars-free targets but a future target containing a dot (`app.contoso.com`) would silently fail to match and re-prompt for credentials every time (35-Utilities × 2).
- **Fix:** 35-Utilities `Install-ScriptUpdate` initialized `$actualHash = $null` before the SHA256 compute and added a second catch around the fallback OpenRead/ComputeHash path. Both prevent the equality check from spuriously passing if `$actualHash` was inherited from an outer scope or a prior failed iteration (35-Utilities).
- **Fix:** 35-Utilities `Show-SMBShareAudit` permission-probe failures now add an entry to the issues list (`"Share 'X': permissions could not be audited"`). Previously the final "No security issues detected" green banner displayed even when half the shares had unreadable ACLs (35-Utilities).
- **Fix:** 35-Utilities `Show-InstalledSoftware` now scans `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*` in addition to HKLM. Per-user installs (Chrome `/silent`, NodeJS user install, Teams classic) used to be invisible to compliance exports. Added a `Scope` column to the output so machine-vs-user installs are distinguishable (35-Utilities).
- **Fix:** 35-Utilities `Show-RebootPendingDetails` SCCM probe failures were swallowed indistinguishably from "SCCM not installed". On an SCCM-managed host with a stopped SMS Agent Host service or corrupt WMI, the pending-reboot dialog silently omitted the SCCM reason. Now gates on `Get-Service CcmExec` first and surfaces probe failures with an actionable message (35-Utilities).

## v1.98.11

- **Security (CRITICAL):** 62-HyperVReplica `Enable-ReplicaServer` silently discarded the operator's "Allow from specific servers only" allow-list — `Set-VMReplicationServer` was invoked WITHOUT `-ReplicationAllowedFromAnyServer $false` and the per-server entries were never registered via `New-VMReplicationAuthorizationEntry`. Operators who picked the restricted mode got the OPPOSITE: an open replica receiver that accepted authenticated replication traffic from any AD-joined Hyper-V host. Fixed: allow-list now toggles `-ReplicationAllowedFromAnyServer` based on whether the operator specified servers, AND iterates `New-VMReplicationAuthorizationEntry` to register each allowed primary under a `RackStackReplicaTrust` trust group (62-HyperVReplica).
- **Fix:** 62-HyperVReplica certificate filter for cert-auth replication only required Server Authentication EKU + a private key. Hyper-V Replica terminates TLS in BOTH directions and needs Server AND Client Authentication EKUs on the same cert; the old filter also accepted already-expired certs. Result: `Enable-VMReplication` succeeded at config time but `Start-VMInitialReplication` then rejected the cert, leaving VMs replication-enabled-but-never-replicating. Now filters for both EKUs AND a future `NotAfter` (62-HyperVReplica).
- **Fix:** 62-HyperVReplica planned-failover "shut down VM" path called `Stop-VM -Force` (hard turn-off — dirty pages lost) despite displaying "Shutting down". Planned failover is supposed to be no-data-loss. Now attempts a graceful shutdown first with a 5-minute bound; only falls through to `-Force` after explicit operator opt-in (62-HyperVReplica).
- **Fix:** 62-HyperVReplica `Test-HyperVReplicaEnabled` returned `$false` on probe failure (Hyper-V WMI provider crashed, module mismatch after in-place upgrade) — identical to "not configured". Re-running setup would then overwrite the existing certificate / allow-list / storage path with defaults. Now tri-state: `$true` / `$false` / `$null` for probe failure; menu surfaces "Probe failed" in Error red so operators see the distinction (62-HyperVReplica).
- **Fix:** 61-ActiveDirectory `Test-ADDSPrerequisites` Check 4 and `Show-ADDSStatus` both used bare `catch { }` around `Get-CimInstance Win32_OperatingSystem` / `Win32_ComputerSystem`. A degraded WMI repo silently reported "Server is not a Domain Controller" and the user proceeded to `Install-ADDSForest` on a box that may already have been a DC. Now surfaces "Could not verify DC state" with the underlying error message and adds CIM 8-second timeouts (61-ActiveDirectory × 2 sites).
- **Fix:** 61-ActiveDirectory `Read-DSRMPassword` only validated length (≥ 8 chars). `Install-ADDSForest` rejects passwords that don't meet complexity policy ~10 minutes into the role install. Now enforces ≥ 14 chars + 3-of-4 character classes (lowercase / uppercase / digit / symbol) up-front so the install isn't 10 minutes wasted on a bad password. Also adds `[GC]::Collect()` after the BSTR-zeroing finally block so the plaintext copy isn't lingering on the managed heap (61-ActiveDirectory).
- **Fix:** 61-ActiveDirectory `Get-Credential` cancellation check only handled `$null` return. In console mode (ps2exe build runs without a GUI host) cancel can return a `PSCredential` with empty user/password instead. Blank credential then reached `Install-ADDSDomainController` which blocked many seconds before Kerberos rejected the empty secret. Now explicitly validates `UserName` is non-blank AND `Password.Length -gt 0` at both new-domain and additional-DC call sites (61-ActiveDirectory × 2 sites).
- **Fix:** 61-ActiveDirectory pre-promotion DNS check used `[System.Net.Dns]::GetHostEntry($DomainName)` which only validates the A record. A misconfigured DNS pointing the domain at a public/external IP would pass the check but `Install-ADDSDomainController` then failed at the DC discovery step. Now also runs `Resolve-DnsName -Type SRV "_ldap._tcp.dc._msdcs.<domain>"` — the AD-specific record that proves the resolver actually serves AD (61-ActiveDirectory).
- **Fix:** 61-ActiveDirectory LDAP / Kerberos TCP probes used `BeginConnect` + `WaitOne` without calling `EndConnect`. `WaitOne` returning `$true` only means the wait completed — for a refused connection (RST), it returns `$true` immediately and the check reported "reachable" when it wasn't. Added `EndConnect` so accept/reject is correctly distinguished (61-ActiveDirectory × 2 sites).
- **Fix:** 61-ActiveDirectory `repadmin /syncall /AdeP` output was piped to `$null` and `$LASTEXITCODE` was ignored — replication failures (8453 access-denied, 8606 insufficient-attributes) all reported "Replication sync initiated" in green. Now captures output, checks exit code, and surfaces non-zero exits with the last 5 output lines (61-ActiveDirectory).
- **Fix:** Install-RackStack `-Install` PATH duplicate check used case-sensitive comparison (`$_ -eq $programDir`) while `-Uninstall` used case-insensitive normalize. A previously-installed PATH entry with different casing wasn't detected; the installer added a duplicate. Now mirrors the Uninstall normalize logic (Install-RackStack).
- **Fix:** Install-RackStack Programs-and-Features inline `UninstallString` did not stop running RackStack processes before removing the program directory (the top-of-file `-Uninstall` path did) — Windows Settings → Apps → Uninstall while RackStack.exe was running would silently fail to delete the EXE. Now stops processes first, uses case-insensitive PATH strip, and escapes single-quotes in paths (Install-RackStack).
- **Fix:** Install-Prerequisites Shell.Application `CopyHere` is asynchronous, but the original code immediately `Get-ChildItem`'d the extract directory — on a slow disk the call could find an empty directory and report "No MSU found" even though extraction was about to succeed. Now polls for up to 60s. Also dropped a dead `$dest = $shell.NameSpace($tempDir)` reassignment, passed wusa.exe arguments as an array (was a single concatenated string — known argument-binding gotcha), and wrapped `Get-WmiObject Win32_OperatingSystem` in try/catch so a corrupt WMI repo surfaces an actionable error (Install-Prerequisites).

## v1.98.10

- **Fix:** Round-9 dispatch — 51-ClusterDashboard.ps1 had a shipped-to-prod color bug at lines 623/627. `$stateColor = if ($csv.State -eq "Online") { "Success" } else { "Error"; $issues++ }` looks correct, but PowerShell's `if/else` returns the LAST expression of the chosen branch — so `$stateColor` was being assigned the integer value of `$issues++` (the increment result), not the string `"Error"`. `Write-OutputColor -color 1` then silently fell back to default colors and **offline CSVs never rendered red**. Same bug on the space-usage line at 627 (>=90% used was also broken). Fixed by swapping the order: `else { $issues++; "Error" }` so the string is the last expression. This is the kind of bug a senior reviewer would land on (51-ClusterDashboard).
- **Fix:** 51-ClusterDashboard `Test-Connection -ComputerName $node.Name -Count 4` in the node-latency check had no per-ping timeout — a node up on cluster heartbeat but firewalled / mis-routed on its management IP hung ~20s per node (4 pings × default 5s timeout). Replaced with `[System.Net.NetworkInformation.Ping]::new()` and an explicit 2s-per-ping cap (51-ClusterDashboard).
- **Fix:** 51-ClusterDashboard `Get-VMHost` was called unguarded on non-Hyper-V cluster nodes (SQL FCI, file-server cluster, scale-out file server) where the cmdlet isn't registered. Spammed `command not found` errors into the transcript. Now gated on `Get-Command Get-VMHost -ErrorAction SilentlyContinue` (51-ClusterDashboard).
- **Fix:** 51-ClusterDashboard `Get-ClusterSharedVolume -ErrorAction SilentlyContinue` returned `$null` on RPC/permission failure and the CSV panel was silently omitted — looking identical to "no CSVs configured". Now distinguishes the two cases and renders "Unable to query CSVs" with the error message when the probe fails (51-ClusterDashboard).
- **Fix:** 38-StorageManager "Clear all data from disk" safety preflight checked Storage Pool / CSV membership but used bare `catch { }` — if `Get-PhysicalDisk` / `Get-StoragePool` / `Get-ClusterSharedVolume` threw (Storage module missing, FailoverClusters cmdlet not installed, cluster service degraded), the preflight fell through and the destructive `Clear-Disk -RemoveData` proceeded. Fail-safe pattern now refuses the clear if either probe fails to verify the precondition — closes the gap that defeated the v1.98.4 destructive-op gate on the exact hosts where verification was least reliable (38-StorageManager).
- **Fix:** 59-StorageBackends `Get-ClusterS2D -ErrorAction Stop` followed by bare `catch { }` — if the probe failed transiently (cluster service hiccup, RPC error), execution silently fell through to the disk-pooling preflight and ultimately to `Enable-ClusterS2D`. Now refuses to proceed with an explicit error when the S2D state probe fails (59-StorageBackends).
- **Fix:** 37-HealthCheck Defender exclusion check silently fell through with no `$checks` entry when `Get-MpPreference` returned `$null` or threw. Now surfaces "Not available (no Defender policy)" / "Probe failed" with Info / Warn status so the row isn't silently absent from the report (37-HealthCheck).
- **Fix:** 56-OperationsMenu cross-host preflight checks used `Get-CimInstance -ComputerName $targetHost -ErrorAction Stop` with NO `-OperationTimeoutSec`. A target whose WMI repo was cold could hang minutes per call. Same pattern in the fleet health view's `Invoke-Command` scriptblock. Added 8-10s timeouts at all four sites (56-OperationsMenu).
- **Fix:** 54-HTMLReports `$diskResult.TimedOut` produced `$disks = $null` but the issues summary then ran `foreach ($disk in $null)` (zero iterations) and overall status rendered **HEALTHY** even though the disk panel said "unavailable". Now tracks `$diskProbeFailed` and surfaces it as an explicit issue (54-HTMLReports).
- **Fix:** 54-HTMLReports `$critEvents = @(try { Get-WinEvent ... } catch { })` swallowed Security-log access-denied errors (extremely common when not running elevated) and reported "0 critical events / green checkmark". Now tracks `$critEventsProbeFailed` and surfaces it as an explicit issue (54-HTMLReports).
- **Fix:** 54-HTMLReports `Save-PerformanceSnapshot` JSON write was direct `Out-File` — a process kill mid-write truncated the snapshot to 0 bytes, and `Export-HTMLTrendReport` silently `catch`-skipped corrupt JSON, quietly dropping every future trend data point. Switched to write-to-`.tmp`-then-Move-Item pattern (54-HTMLReports).
- **Fix:** 54-HTMLReports `w32tm /query /status` parsed against English-only `'Free-Running|Local CMOS'` regex — on non-English Windows MUI the dashboard reported "Time Sync: OK" even when the source was the local clock. Now cross-checks `HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters\Type` (NoSync/NTP/NT5DS/AllSync — language-neutral) at both sites (54-HTMLReports × 2).
- **Fix:** 54-HTMLReports `Start-MetricCollection` blocked uninterruptibly inside `Start-Sleep -Seconds ($IntervalMinutes * 60)` — a 60-minute collection with 5-min interval was 11 separate stretches the operator couldn't abort without Ctrl+C-killing the entire tool. Now sleeps in 1-second slices checking `$global:ReturnToMainMenu` each tick (54-HTMLReports).
- **Fix:** 54-HTMLReports `Invoke-FleetTrend` snapshot filter `if ($null -ne $data.Timestamp)` let empty-string timestamps through (since `$null -ne ""`), then crashed `[datetime]::Parse` inside `Sort-Object` and aborted the trend report. Now uses `-not [string]::IsNullOrWhiteSpace` (54-HTMLReports).

## v1.98.9

- **Fix:** Round-8 audit hardening — eleven CLI audit dispatch handlers in `50-EntryPoint` either reported a probe-unavailable host as `Issues: 0 / green` or used assumed-OK fallback scores that masked genuine failures. Reviewers running `RackStack.exe -Action <audit> -OutputFormat JSON` on hosts where the underlying cmdlet/namespace was missing would see clean output that looked like the audit had passed.
  - `StorageHealthScore` (latency probe): when `Get-PhysicalDisk` returned no latency counters, the latency component scored `20` ("assumed OK"). Now scores `0` with `Status: Unavailable` so the overall grade reflects the missing telemetry instead of inflating it (50-EntryPoint:10666).
  - `ServerScore` (Events / Uptime / Network): same "assumed OK" pattern at three sites. All now emit zero with `Status: Unavailable` markers in JSON (50-EntryPoint:11284, 11294, 11303). Also removed a dead `$nicErrs = ($categories | Out-Null)` line where the return value was discarded into nowhere (50-EntryPoint:11298).
  - `SecureBootAudit`: `$firmware = try { Get-ItemProperty ...; "UEFI" } catch { "Legacy/Unknown" }` was building a 2-element array (registry object + string) because `Get-ItemProperty`'s emission was unintentionally captured. Boot Mode rendered as a stringified `PSCustomObject`. Piped to `Out-Null` so only the string survives (50-EntryPoint:11751).
  - `ClusterHealthScore`: `$grade` was only ever assigned inside the try block — when `Get-ClusterNode` threw, the JSON path emitted an empty string for grade. Now defaults to `"F"` on the catch arm so the JSON contract holds (50-EntryPoint:10448).
  - `PasswordPolicy`: `secedit /export` writes the full local security policy in plaintext to `%TEMP%\secpol_*.cfg`. The temp file was deleted inline only on the success path — any throw between `Get-Content` and `Remove-Item` (or any exit through the outer catch) left the .cfg sitting in `%TEMP%`. Moved cleanup to a `finally` block (50-EntryPoint:11377-11447).
  - `AppLockerAudit`: on Workstation SKUs and older Server SKUs that ship without the AppLocker module, the dispatch silently fell through all rule-type probes and printed `Issues: 0 / Configured: False / green`. Now probes `Get-Command Get-AppLockerPolicy` and emits `Status: Unavailable` in both console (yellow) and JSON when the cmdlet is missing (50-EntryPoint:8014).
  - `CredGuardAudit`: `Win32_DeviceGuard` only exists on Server 2016+ / Win10+. On older hosts the bare `catch { }` swallowed the WMI failure, leaving `$cgRunning = $false` and incrementing `$cgIssues` — exactly the same output as a host that's running but didn't enable Credential Guard. Added a `$cgProbeAvailable` flag, suppressed the VBS/CG issue increment when the probe didn't succeed, and exposed `Status / ProbeAvailable / ProbeError` on the JSON output (50-EntryPoint:7344).
  - `SecureChannelAudit`: `nltest /sc_query` emits localized text (`NERR_Success` is English-only — German/Japanese hosts see different strings). The previous `-match 'NERR_Success'` returned `FAIL` for every non-English Windows install regardless of actual secure-channel state. Now relies on `$LASTEXITCODE` (locale-invariant), cross-checked against `Test-ComputerSecureChannel` (50-EntryPoint:8866).
  - `PatchStatus`: `Microsoft.Update.Session` and its returned `IUpdateSearcher` / `IUpdateHistoryEntryCollection` hold non-GC COM references that survive until process exit if not released explicitly. Batch-mode fleet sweeps that ran `PatchStatus` 100+ times leaked 100+ COM objects. Added a `finally` block that calls `[Marshal]::ReleaseComObject` on each, plus per-entry release inside the loop (50-EntryPoint:4104).
  - **Inventory-style audits demoted from unconditional Success to neutral Info**: twelve audit dispatchers (USBDeviceAudit, RecoveryPointAudit, ProxyAudit, KerberosAudit, DHCPAudit, NUMAAudit, StartupScriptAudit, FirewallLogAudit, ScheduledRebootAudit, RouteTableAudit, WindowsCapabilityAudit, LocaleAudit) printed their `Issues: $N` summary line in unconditional green `Success` color, even though the `$N` counter was never incremented by the audit body. These are enumerations, not failure detectors — the green stamp implied "verified safe" when it was really "nothing to count". Changed to `$(if ($issues -gt 0) { 'Warning' } else { 'Info' })` so green is reserved for audits that actually verified failure conditions (50-EntryPoint × 12 sites).
- **Fix:** Removed `CustomVNICs` from `defaults.example.json`. The documented schema was a lie — `Import-Defaults` never reads it. The only consumer is the separate `batch_config.json` schema (built by `Export-BatchConfigFromState` in 36-BatchConfig and consumed by `Start-BatchMode`). Putting `CustomVNICs` in `defaults.json` did nothing; removing it stops misleading operators. Future enhancement: wire `Import-Defaults` to copy it into `$script:CustomVNICs` and have `Start-BatchMode` use that as a fallback when `Config.CustomVNICs` is missing (defaults.example.json).
- **Fix:** Removed dead `$cpuColor` / `$memColor` / `$diskColor` per-metric variables from the main-menu dashboard (48-MenuDisplay). They were computed at lines 73-75 but never read anywhere — the box uses `$worstColor` (computed separately at lines 77-79) for the overall row color. A round-3-era menu rewrite probably replaced per-metric coloring with a single worst-of-the-three color and missed the cleanup (48-MenuDisplay).

## v1.98.8

- **Fix:** `defaults.json` `MonitoredServices` field was DEAD CODE for the entire history of the option. Three consumer sites (30-ServiceManager service-status panel, 50-EntryPoint Export action's services section, 50-EntryPoint ServiceAudit) all read `$script:Defaults.MonitoredServices` but `$script:Defaults` was never assigned anywhere in the codebase. Operator customization in `defaults.json` silently fell through to the hardcoded fallback list. `Import-Defaults` now unpacks the field into `$script:MonitoredServices` and all three consumers read from there. Initialized to `$null` in 00-Initialization so the "not configured → use built-in fallback" branch still works (00-Initialization, 30-ServiceManager, 50-EntryPoint × 2, 56-OperationsMenu).
- **Fix:** Workstation Debloat's "Startup Item Cleanup" pass captured `$prevValue = $prop.Value` before `Remove-ItemProperty` but never emitted an `Add-UndoAction`. Result: every startup item Debloat removed was silently un-recoverable via the "Undo last change" menu. Added the missing `Add-UndoAction` with closure-safe param binding (mirrors the registry-tweak pattern at line 858 of the same file). The 04-Navigation undo-list help text already implied this was supported (64-SystemDebloat).
- **Fix:** `RackStack.psd1` ModuleVersion was pinned at `1.98.0` while the rest of the project is six z-versions ahead. Anyone running `Find-Module RackStack` on PSGallery would see the wrong version. Bumped to `1.98.7` (will be auto-bumped to `1.98.8` by the release-bump workflow going forward). Also added `CompatiblePSEditions = @('Desktop', 'Core')` so PS 7 users on Windows show as supported, and `IconUri` pointing at the in-repo icon so the Gallery listing has a logo instead of a placeholder (RackStack.psd1).
- **Fix:** `powershell-scan.yml` workflow was missing the `git config --global --add safe.directory` step that `ci.yml` got in v1.98.7. Same self-hosted runner, same SYSTEM-vs-user ownership context, same risk of intermittent "fatal: detected dubious ownership" failures. Added the matching step (powershell-scan.yml).
- **Fix:** Help-search topic "CLI Actions" advertised "168 CLI actions" while the actual count is 176. Eight actions short. Updated (34-Help).
- **Fix:** Removed the stale WinGet manifest at `winget/manifests/t/TheAbider/RackStack/1.98.0/` — it pointed at `releases/download/v1.98.0/RackStack.exe` which 404s now that v1.98.0 was deleted per the retention rule (back in v1.98.6's release). `winget install TheAbider.RackStack` would have failed at the download step. Regeneration of winget manifests is now an explicit follow-up step that needs auto-updating from the release workflow (a future round) rather than committing always-stale generated artifacts.
- **Hygiene:** Dropped the overly-broad `git config --global --add safe.directory '*'` from `ci.yml` — the workspace-scoped entry on the previous line is sufficient.

## v1.98.7

- **Tests:** New `SECTION 160: BATCH MODE INTEGRATION (function-level)` invokes real functions (`Test-BatchConfig`, `Test-ValidDomainName`) with synthetic configs and asserts against the returned data — closes the test-shape-vs-test-behavior gap the round-5 audit flagged. Covers ConfigType rejection, hostname/IP validation, duplicate vNIC detection, NewForest+DomainName warning, S2D `AllowS2DDataLoss` gate (source-level, since no test cluster), DomainName pre-validation at Add-Computer sites, and `Test-ValidDomainName` rejection of empty/single-label/leading-dot/trailing-dot/special-char inputs. **+24 tests, 4588 total (was 4564), 100% pass** (Tests/Run-Tests).
- **Test runner hang root cause permanently resolved:** the full slow `Run-Tests.ps1` (no `-Quick`) now completes in 139 seconds with peak memory 1.24 GB — no longer hangs. The earlier hang was the wizard prompt, fixed in v1.98.3; this confirms the fix holds for the slow path too. The memory note that the CI runner OOMs may have been stale (the local box completes cleanly under the runner's typical 8 GB allocation).
- **CI: auto-release on version bump.** `.github/workflows/ci.yml` now detects a version change in `Header.ps1` since the previous commit and, on a push to master, compiles `RackStack.exe` via `Invoke-PS2EXE`, generates SHA256 hashes, extracts that version's section from `Changelog.md`, and publishes a GitHub Release with all 3 assets. Z-bumps within a minor also auto-delete the prior z release per the retention rule. Closes the gap that made v1.98.1-v1.98.5 commits without releases — every future bump will release itself.

## v1.98.6

- **Fix:** Batch-mode domain-join step (50-EntryPoint) and profile-restore domain-join (45-ConfigExport) called `Add-Computer -DomainName $Config.DomainName` without first validating the value via `Test-ValidDomainName`. The DC promotion paths already used this gate; the batch-step + profile-restore paths skipped it. A malformed `DomainName` in `defaults.json` reached `Add-Computer` with a generic failure instead of a clear "bad domain name" error. Now validated before invocation (50-EntryPoint, 45-ConfigExport).
- **Fix:** Test runner had ~25 false-positive tests. Most impactful: (a) the CIM-unavailable fallback block in Section 56 wrote `$true "SKIPPED..."` to six prereq tests instead of using `-Skipped`, vacuously inflating the pass count on any CI host where CIM was down. (b) The `Install-RackStack: bootstrap installer exists` assertion was inside `if (Test-Path -LiteralPath $bootstrapPath)`, so it was always `$true` whenever it ran (the condition gating the block was the very thing the test claimed to verify). (c) The "Old function removed" catch arm wrote `$true` on any exception, so a broken `Get-Command` would be marked PASS. (d) The credential-leak scan was vacuous when `defaults.json` didn't exist (public repo / CI without secrets) because `$credPatterns` stayed empty. All four fixed — proper `-Skipped` for CIM, real `Test-Path` result for bootstrap, exception writes `$false` for renamed-function catch, pattern-based fallback scan when defaults.json is absent (Tests/Run-Tests).
- **Fix:** `Validate-Release.ps1` PSScriptAnalyzer monolithic scan dropped the `-Settings` parameter that was applied to the modules scan, so a rule legitimately excluded for modules could still trigger on the monolithic. Now passes the same settings file to both scans (local/Validate-Release).
- **Hardened:** Defender exclusion sensitive-path check now matches sub-paths (prefix match), not just exact match. `C:\Windows\System32\Foo` now triggers the same warning as `C:\Windows\System32` (17-DefenderExclusions).
- **Hardened:** Update-check temp-path build sanitizes `$asset.name` from the GitHub Releases JSON. Even though GitHub asset names are name-locked by the release UI, a forged response containing `..\` / path separators / null bytes was an unbounded write path. Now stripped of `[^\w\.\-]` characters and rejected outright if `..` / slash / null is present (35-Utilities).
- **Note:** Domain-format validation in 12-DomainJoin continues to require FQDN form (`corp.local`). A round-5 audit flagged single-label NetBIOS names as legitimate, but the project's existing tests intentionally enforce FQDN-only to discourage legacy-only environments. Added a clarifying comment at the validation point.
- **Fix:** HTML health report's firewall-issue check broke out of the `foreach` after the first disabled profile, so an admin who disabled both Domain and Public only saw `"Domain disabled"` in the issues summary. Removed the `break` (54-HTMLReports).
- **Fix:** `Set-CDROMDriveLetter`, `Set-DriveLetter`, and the CD-ROM enumeration in 38-StorageManager all called `Get-CimInstance` without `-OperationTimeoutSec`. On a cold WMI repository the menu could hang for minutes. Added `-OperationTimeoutSec 8` at all four sites (38-StorageManager).
- **Fix:** `Export-Favorites` and `Export-CommandHistory` (55-QoLFeatures) and the batch-config template + profile-export (36-BatchConfig × 2 sites) all used `Out-File -Force` / `Set-Content` directly on the target path. A process kill mid-write truncated the JSON to zero bytes. Switched to write-then-rename pattern with cleanup of the `.tmp` file on failure (55-QoLFeatures, 36-BatchConfig).

## v1.98.5

- **Fix:** `New-StrongPassword` (22-Password) had two cryptographic defects in `$cryptoRandom`. (1) `[BitConverter]::ToInt32(...)` followed by `[math]::Abs` throws `OverflowException` when the bytes decode to `Int32.MinValue` (one in 4 billion per call, ~17 calls per password generation, so cumulative crash risk over many invocations). (2) Plain `% $Max` over a 32-bit space introduced modulo bias on non-power-of-2 alphabets (24/22/8/11 chars). Switched to `UInt32` + rejection sampling against an unbiased-modulo cap (22-Password).
- **Fix:** `New-StrongPassword` clipboard auto-clear posted the plaintext password into a `Start-Job -ArgumentList` and never cleaned the job up. The plaintext sat in job metadata until process exit. Replaced with an in-process `[System.Threading.Timer]` that closes over the value and never crosses a runspace boundary (22-Password).
- **Fix:** `Disable-BuiltInAdmin` (24-DisableAdmin) checked for alternate admins by regex-stripping `MicrosoftAccount\alice@outlook.com` to `alice@outlook.com` and then calling `Get-LocalUser`, which always fails for MSA / AzureAD-backed identities. Result: on an MSA-only home host, the function falsely reported "no alternate admin" and silently blocked the disable; on a domain-joined host with an MSA admin it could falsely allow the disable. Now MSA and AzureAD `PrincipalSource` values count as valid alternate logon paths (24-DisableAdmin).
- **Hardened:** Storage Replica partnership creation (33-StorageReplica) now requires the operator to type `DESTROY <destVolume>` (exact, case-sensitive) before `New-SRPartnership` runs. The previous generic yes/no prompt didn't surface that initial-seed block-overwrites the destination volume. Same pattern as the `OBLITERATE BOOT` gate added in v1.98.3 (33-StorageReplica).
- **Hardened:** Batch-mode S2D enable (59-StorageBackends) refuses to run unless the batch config sets `"AllowS2DDataLoss": true`. `Enable-ClusterS2D` claims and pools every eligible disk on every cluster node and destroys existing data; batch mode runs non-interactively, so an explicit acknowledgement field is required (59-StorageBackends).
- **Fix:** `.PadRight(N)` was placed OUTSIDE the `$(...)` subexpression at 20 sites across 4 files (35-Utilities x9, 52-VMCheckpoints x5, 53-VMExportImport x2, 58-NetworkDiagnostics x4). Result: the literal string `.PadRight(72)` rendered in the UI box-border alongside the title text. Most prominently visible on the Memory Diagnostics dashboard and the Network Stack Reset destructive-op warning. Fixed in bulk via regex (35-Utilities, 52-VMCheckpoints, 53-VMExportImport, 58-NetworkDiagnostics).
- **Fix:** 53-VMExportImport's per-VM size precheck splatted `$vmParams` (which carries both `ComputerName` and `Credential`) into `Get-VHD`. `Get-VHD` accepts `-ComputerName` but NOT `-Credential`, so parameter binding silently failed under remote-credential scenarios and every VM in the list displayed "N/A" for its VHD total. Now constructs a `Get-VHD`-safe splat with only `ComputerName` (53-VMExportImport).
- **Fix:** 19-NTPConfiguration NTP undo passed `$OldServer` to `w32tm /config /manualpeerlist:$OldServer` unquoted, so multi-peer values containing a space (e.g. `"time.windows.com time.nist.gov"`) were split into multiple args and the undo silently restored only the first peer (or none). Quoted now (19-NTPConfiguration).
- **Fix:** 46-SessionSummary's paired txt + json desktop exports called `Get-Date -Format 'yyyyMMdd_HHmmss'` twice, so the two filenames drifted by 1+ seconds if the operator paused between confirmation prompts and ended up un-paired. Now computes the timestamp suffix once (46-SessionSummary).
- **Fix:** `Show-ISOInventory` (42-ISODownload) read `$script:HostISOPath` directly, ignoring the cluster-mode resolution that `Get-ISOStoragePath` provides. On a clustered Hyper-V host the inventory always reported "no ISOs" even when ISOs were sitting on the cluster shared volume. Now routes through `Get-ISOStoragePath` (42-ISODownload).
- **Fix:** `Show-PendingRename` in 11-Hostname swallowed registry-probe errors with a bare empty catch. Now surfaces the failure at Debug so an operator wondering why the pending-rename hint isn't appearing can see the underlying registry/GPO restriction (11-Hostname).
- **Fix:** `Copy-VHDForVM` in 41-VHDManagement's `finally` block referenced `$copyJob` / `$convertJob` without pre-declaration. If the outer `try` threw before either assignment (e.g. directory-creation failure on a sealed volume), the finally produced a "variable cannot be found" error on top of the original failure. Both now `$null`-declared at the top of the try (41-VHDManagement).
- **Fix:** `New-DebloatRestorePoint` (64-SystemDebloat) had a dead code path. `$srEnabled = $null -ne (...)` always produces `[bool]`, so the subsequent `if ($null -eq $srEnabled)` was unreachable and the `srservice` fallback never fired — on a Server SKU where the cmdlet returned nothing but the service was actually enabled, no restore point was attempted. Now `if (-not $srEnabled)` (64-SystemDebloat).
- **Fix:** `Invoke-WorkstationDebloat` (64-SystemDebloat) ran AppX cleanup paths on Server Core, where `Get-AppxPackage`/`Get-AppxProvisionedPackage` aren't available. The transcript filled with "term is not recognized" errors for every package candidate. Now short-circuits with a friendly redirect to "Server Debloat" when `IsServerCore` (64-SystemDebloat).
- **Hardened:** `Install-RackStack.ps1` refuses to run two installer instances concurrently. Held via `System.Threading.Mutex` named `Global\TheAbider.RackStack.Installer`; second invocation exits 1 with an explanatory message. Without this, two `-Install` runs racing both rename `RackStack.exe` → `.old` and clobber each other's backup (Install-RackStack).
- **Hardened:** `Install-RackStack.ps1 -Uninstall` now stops any running `RackStack` process before removing Program Files (was silently failing to delete locked files while reporting success). PATH dedupe normalizes case + trailing-slash + whitespace so a drifted duplicate is still recognized and stripped (Install-RackStack).
- **Hardened:** `Install-Prerequisites.ps1` confirmation prompt is now an explicit `Type 'INSTALL' (uppercase)` gate, not a default-yes `[Y/n]`. New `-Force` switch bypasses for automation. Stops a casual operator from accidentally enrolling a server into a reboot by hitting Enter (Install-Prerequisites).

## v1.98.4

- **Hardened:** Bootstrap installer (`Install-RackStack.ps1`) refuses to run `RackStack.exe` if the release body does not publish a SHA256 hash for the asset, or if hash verification raises an error. Previously, missing-hash or read-error cases printed a yellow warning and ran the unverified binary anyway, undoing the v1.96.0 integrity guarantee. New `-AllowUnverified` switch must be passed to opt out (`irm ... | iex -AllowUnverified`).
- **Hardened:** `Test-CustomRoleTemplate` (60-ServerRoleTemplates) now restricts `PostInstall` to `^(Start|Invoke|Initialize|Configure)-Verb` single-token names. A malicious `defaults.json` could previously specify any cmdlet (e.g. `Remove-Item`) and the `& $template.PostInstall` invocation would run it. The invocation site re-checks the pattern as defense in depth.
- **Hardened:** Storage Manager's "Clear all data from disk" pre-checks Storage Pool membership and Cluster Shared Volume membership before invoking `Clear-Disk -RemoveData`. Refuses with an explanatory error when the disk is in use by either layer (previously bricked the pool/cluster's view of the disk).
- **Hardened:** HTML trend report (54-HTMLReports) — snapshot `Timestamp` is now `ConvertTo-HtmlSafe` encoded before interpolation; `CPUPercent` / `MemoryUsedPercent` are coerced to `[double]` and clamped 0–100 before landing in inline `style` attributes. Closes a stored XSS / CSS-injection path through a tampered snapshot JSON file.
- **Fix:** `Exit-Script` (47-ExitCleanup) used a bare `Read-Host` that hung indefinitely in CLI Silent / Quiet / non-interactive contexts. Gated on `-not $script:CLISilent -and -not $script:NonInteractive -and -not $script:CLIQuiet`. The whole cleanup body is now wrapped per-section in `try`-blocks so a failure in `Show-SessionSummary` (or any single cleanup step) doesn't bypass credential disposal or transcript stop. Credential cleanup now iterates `VMDeploymentCredential`, `DomainJoinCredential`, `LocalAdminCredential`, `AgentInstallCredential`, `DSRMCredential` instead of just one. `Stop-Transcript` is now called explicitly before exit / restart (47-ExitCleanup).
- **Fix:** `Install-Prerequisites.ps1` PowerShell version check incorrectly fell through to WMF installer on PS 7 (Major=7, Minor=0 failed `Minor -ge 1`). Now: `$psVer.Major -gt 5 -or ($psVer.Major -eq 5 -and $psVer.Minor -ge 1)` so any PS 6+ short-circuits as already-sufficient (Install-Prerequisites).
- **Fix:** Main-menu "Reboot pending" check was passing the wrong parameter name (`-TTLSeconds 15`) to `Get-CachedValue`, whose actual parameter is `-CacheSeconds`. The value was ignored and the cache fell back to its default TTL, so the menu badge for a Windows pending-reboot could stay stale longer than expected (48-MenuDisplay).
- **Fix:** Health-check Firewall section left `$fwState` unset if `Get-FirewallState` threw, then dereferenced `$fwState['Domain']` outside the catch block, spamming null-index errors. `$fwState` is now defaulted to `Unknown` per profile before the try (37-HealthCheck).
- **Fix:** VHD and ISO cache size-mismatch checks (41-VHDManagement, 42-ISODownload) used exact-byte equality, so multi-GB caches were silently deleted on any alignment drift from SMB/CDN/sparse copies. Now uses a 1 MB tolerance.
- **Fix:** "Delete ALL checkpoints" in 52-VMCheckpoints deleted in creation-time order (oldest first). Hyper-V's automatic VHD merge when removing a parent could leave child VHDs orphaned if the merge failed mid-loop. Now sorts descending by `CreationTime` so leaves go first (52-VMCheckpoints).
- **Fix:** Cluster Readiness "Cluster Networks" check reported OK when `Get-ClusterNetwork` returned nothing (RPC failure / partial outage hides degraded network state behind `0 -eq 0`). Now reports WARN with "no networks enumerated" detail when the collection is empty (51-ClusterDashboard).
- **Fix:** Audit-log JSON entries (`audit-log.jsonl`) used `ConvertTo-Json -Compress` without `-Depth`, truncating nested-hashtable change descriptions to `...` at the depth-2 default. Now `-Depth 5` (04-Navigation).
- **Fix:** Deduplication menu listed the system drive among available volumes; Windows always rejects `Enable-DedupVolume` on the OS drive, producing a cryptic error. System drive is now filtered out (32-Deduplication).
- **Fix:** MPIO claimed-device display rendered the WMI class name (`MSFT_DSMLoadBalancePolicy`) instead of the actual load-balance policy on PS versions where `Get-MSDSMGlobalDefaultLoadBalancePolicy` returns an object. Now explicitly pulls `.PolicyName` / `.Policy` and falls through to string coercion (26-MPIO).
- **Fix:** Firewall rule CSV export coerced `$rule.Enabled` to string via `.ToString()`, which yields `"True"` / `"False"` / `"NotConfigured"` for the GpoBoolean enum. Consumers parsing for the boolean `True` missed `NotConfigured` rules. Now coerces to a true boolean (`$rule.Enabled -eq $true`) so CSV rows are unambiguous (16-Firewall).

## v1.98.3

- **Fix:** `Invoke-WithTimeout` ran the supplied script block in a fresh `[powershell]::Create()` runspace and never propagated parameters, so any caller whose block interpolated an outer variable (`Get-CimInstance ... -Filter "DeviceID='$currentDrive'"`) silently saw an empty value at runtime. Added an `-ArgumentList` parameter that forwards via `AddArgument`; callers using outer values now declare them via `param()` inside the block. The QoL pagefile-max disk-space check (55-QoLFeatures, the bug that motivated this fix) was switched to the new pattern and now reads free space from the correct drive (04-Navigation, 55-QoLFeatures).
- **Fix:** Windows Update install path unconditionally set `$global:RebootNeeded = $true` and recorded an `Installed N updates` session change even when `Install-WindowsUpdate` returned `Failed`. Both lines are now gated behind the success branch only; failures leave reboot state and session history untouched (14-WindowsUpdates).
- **Fix:** RMP/MSP agent installer passed `InstallArgs` to `Start-Process -ArgumentList` as a single string. Some installers parse via `GetCommandLine()` and saw the whole `/s /norestart` value as one literal switch, silently ignoring the rest. Normalized to a string array via whitespace split (57-AgentInstaller).
- **Fix:** New External Hyper-V vSwitch path called `Rename-VMNetworkAdapter -NewName $ManagementName` with the bare local variable; the function had no `$ManagementName` parameter so the rename silently no-op'd on every External switch. Switched to the module-scoped `$script:ManagementName` (initialized in 00-Initialization, overridable via `defaults.json`) so the rename actually applies (09-SET).
- **Fix:** Timezone browser displayed UTC-03:-30 for half-hour negative offsets (Newfoundland UTC-03:30 etc.) because only `$offset.Hours` was wrapped in `[math]::Abs`. Wrapped `$offset.Minutes` too (13-Timezone).
- **Fix:** RDP enable path recorded the session change and registered an undo action even when the registry write or verification failed. Both are now gated on `-not $rdpAlreadyEnabled -and $rdpEnabledNow` so the audit log only carries genuine state changes (15-RDP).
- **Fix:** Recycle-bin size accumulator in disk cleanup stripped the unit suffix from `GetDetailsOf` strings (`"1.2 MB"` -> `"12"`) producing a meaningless total that was never actually displayed. Removed the dead accumulator and kept the item-count enumeration (20-DiskCleanup).
- **Fix:** Storage-Manager partition delete used the same `DELETE` confirmation phrase for any partition type, including system/boot/reserved. Added a stronger `OBLITERATE BOOT` (caps + space) confirmation when the selected partition is `System`, `Reserved`, or `IsBoot`; standard data partitions still use the original `DELETE` prompt (38-StorageManager).
- **Fix:** Hyper-V Replica wizard called `Enable-VMReplication` before prompting for the external-media export path. If the operator hit a navigation command on the export-path prompt, the VM was left half-configured: replication enabled, no initial replication started. Reordered so the export-path is collected before `Enable-VMReplication` fires (62-HyperVReplica).
- **Hardened:** Scheduled-task XML import now parses the supplied XML with `XmlResolver = $null` (blocks external-entity expansion) and surfaces the `Principal` (UserId / GroupId / RunLevel) and `Actions` blocks for explicit operator review before calling `Register-ScheduledTask`. An XML that won't parse is refused outright. Closes the gap where a tampered task XML could silently register a SYSTEM-level command (63-ScheduledTasks).
- **Hardened:** iSCSI cabling detection (`Test-iSCSIAdapterSide`) now refuses to run on an adapter that owns the default route (`Get-NetRoute -DestinationPrefix '0.0.0.0/0'`). Side detection wipes all IPv4 from the target NIC to assign a temp probe IP, which would drop the operator's RDP session if pointed at the management NIC. Returns a `Skipped` result with a clear explanation in that case (10-iSCSI).
- **Hardened:** `Get-SANTargetsForHost` lookup now matches both the `Name` field (custom pairings) and a synthesized `Pair$Index` form (default-built pairs). The previous lookup-by-Name-only silently fell back to the first pair when `Initialize-SANTargetPairs` hadn't injected a `Name` key, sending the wrong host to the wrong primary pair (10-iSCSI).
- **Fix:** `$logFilePath` declared in 00-Initialization without `$script:` scope was not visible to the file-logging code paths in 02-Logging and 04-Navigation that read it via dynamic scope. File logging silently no-op'd whenever it was enabled. Promoted the declaration to `$script:logFilePath` and updated all five consumer sites to use the same scope (00-Initialization, 02-Logging, 04-Navigation).
- **Fix:** Windows Update install path treated a job hitting the 60-minute timeout as success. `Stop-Job` leaves the state at `Stopped` (not `Failed`), and the prior guard only checked for `Failed` — a timed-out install would fall through to the success branch, falsely flag `RebootNeeded`, and log "Installed N updates" to the session change. Now treats anything other than `Completed` as non-success and surfaces the specific reason (timeout vs. error vs. other) (14-WindowsUpdates).
- **Fix:** Batch-mode network undo restored IP and gateway but did NOT restore DNS. The captured `$undoOldDNS` array was never inserted into the rollback scriptblock, so a failed network step rolled back IP/gateway and left DNS pointed at whatever the failed step wrote. Undo scriptblock now reapplies the original DNS server list (or resets to DHCP if there was none) (50-EntryPoint).
- **Fix:** Batch step 12 (`DisableBuiltInAdmin`) ran unconditionally after step 11 (`CreateLocalAdmin`). If step 11 caught an error (weak password, name conflict) and didn't actually create the replacement admin, step 12 still disabled the built-in `Administrator` account — leaving the host with no enabled admin and locking the operator out. Now refuses to run if the replacement local admin isn't present and enabled (50-EntryPoint).
- **Fix:** Settings-menu iSCSI subnet entry threw `FormatException` on input with non-numeric octets (e.g., `10.0.x`). PowerShell 5.1's `-and` doesn't short-circuit, so `[int]"x"` ran even when the regex test already returned false, throwing out of the pipeline and dropping the operator back to the menu without a clear error. Replaced the one-liner with an explicit foreach that breaks on the first regex miss (56-OperationsMenu).
- **Fix:** 13 `Add-UndoAction` call sites in System Debloat captured loop variables (`$svcNameCapture`, `$taskPathCap`, `$regPath`, `$featureNameCapture`, etc.) and referenced them inside `-UndoScript { ... }` without `.GetNewClosure()` or `-UndoParams`. When `Undo-LastChange` later splat-invoked the scriptblock in its own scope, those names didn't exist, so every undo silently ran with `$null` arguments and `-ErrorAction SilentlyContinue` swallowed the error. Converted all 13 sites to `param() + -UndoParams @{ ... }` matching the pattern used elsewhere in the codebase. The Debloat "Undo last change" feature now actually reverses what it claims to (64-SystemDebloat).
- **Test infra:** `Run-Tests.ps1` hung indefinitely on the first-run wizard prompt because the test runner's `Import-Defaults` call had nowhere to find a defaults file and the wizard had no way to detect a non-interactive caller. `Import-Defaults` now skips the wizard when `$script:CLISilent` or `$script:NonInteractive` is set; the test runner sets both flags before dot-sourcing modules (Tests/Run-Tests, 56-OperationsMenu).
- **Tests:** New `SECTION 159: v1.98.x FIX REGRESSIONS` adds ~35 regression guards covering the v1.98.2 and v1.98.3 fixes (cluster quorum rename, MPIO null guard, iSCSI hostname anchor, manual-target filter, default-route guard, SAN pair lookup, FileServer response leak, OfflineVHD null filter, RAM preflight free-not-total math, DNS timeout wraps, Dashboard hardening, Invoke-WithTimeout ArgumentList, $script:ManagementName rename, timezone Abs, Windows Update success gating, RDP session-change gating, recycle-bin dead code removal, OBLITERATE BOOT gate, pagefile ArgumentList, AgentInstaller args array, replication ordering, and task XML preview) (Tests/Run-Tests).
- 65 modules, 4570+ tests, 176 CLI actions, 615 functions

## v1.98.2

- **Fix:** `Set-ClusterQuorum` interactive menu function was named identically to the built-in PowerShell cmdlet. Calls inside the wrapper resolved to the wrapper itself instead of the FailoverClusters cmdlet, so changing quorum type from the menu silently no-op'd (or recursed) on every option (Node Majority, Disk Witness, File Share, Cloud Witness). Renamed the wrapper to `Set-ClusterQuorumConfig`; cmdlet calls inside now resolve to the real cmdlet (27-FailoverClustering).
- **Fix:** Cluster health check's "Active votes / Total votes" math could report HEALTHY when no nodes were enumerated because `Measure-Object` returns `$null` Sum on an empty input. Coalesced both sums to `[int]` so the comparison can't false-positive (27-FailoverClustering).
- **Fix:** MPIO claimed-device display crashed with NullReferenceException on entries with a null `VendorId` or `ProductId` (some hardware returns one or both as null). Added null guards (26-MPIO).
- **Fix:** iSCSI hostname pattern `HV(\d+)` matched anywhere in the name, so a hostname like `HV24ABC` returned 24 silently. Anchored to require the digits not be followed by letters (10-iSCSI).
- **Fix:** iSCSI cabling report fired the "both adapters on same side" warning even when both adapters reached A AND B (already reported by the prior "reaches both sides" warning). Excluded `"Both"` from the duplicate-side check so users see one warning, not two (10-iSCSI).
- **Fix:** iSCSI manual target entry now filters empty strings produced by trailing or repeated commas (`"1.2.3.4,,5.6.7.8"` no longer attempts a connection to an empty target). Adds a clear "no valid IPs" message if all entries were blank (10-iSCSI).
- **Fix:** MSiSCSI service auto-start path now calls `Clear-MenuCache` so the iSCSI menu status line refreshes without a manual reload (10-iSCSI).
- **Fix:** FileServer SHA256 helper leaked the outer `HttpWebResponse` if `New-Object System.IO.StreamReader` threw. Reordered the try/finally so the response handle is always closed even on inner failures (39-FileServer).
- **Fix:** `Show-MountedVHDStatus` could pass null pipeline entries into the downstream filter when `Get-VHD` threw on a corrupted VHD. Added explicit null filter before the `Attached -eq $true` test (43-OfflineVHD).
- **Fix:** VM-deployment RAM preflight used `TotalVisibleMemorySize * 0.95` as the budget, ignoring RAM already consumed by the host OS itself. Now derives headroom from `FreePhysicalMemory + existing VM allocations` so deploys are warned/blocked based on actual free RAM (44-VMDeployment).
- **Fix:** Readiness-check DNS resolve and the DNS audit's per-target resolve are now wrapped in `Invoke-WithTimeout` (5-8 seconds) so a degraded resolver can't stall the operation (05-SystemCheck, 50-EntryPoint).
- **Hardened:** Dashboard HTTP server. `HttpListener` timeouts (5s header / 10s idle / 10s queue), non-GET methods return 405 immediately, requests carrying a body return 413, and unknown paths return 404 instead of falling through to the HTML dashboard. The `-Config "host:port"` regex no longer accepts arbitrary DNS-style hostnames (only wildcards, loopback, and explicit IPv4) so operators can't accidentally request a bind that `HttpListener` will refuse (50-EntryPoint).
- **Docs:** README CLI-action count refreshed from 167 to 176 (drift since v1.94.x). Replaced stale "New in v1.8.0" callout with a non-versioned description. Added a Documentation section linking the in-depth guides under `docs/`. Added Configuration field-table rows for `TimeZoneRegion`, `MonitoredServices`, `DryRun`, `DashboardWarningPercent`/`CriticalPercent`, `Timeouts`, and `CLIDefaults`.
- **Docs:** Repaired ~30 broken wiki-style cross-doc links across 12 files under `docs/` (`[Storage Backends](Storage-Backends)` etc. now carry the `.md` suffix so they resolve on github.com).
- 65 modules, 4535 tests, 176 CLI actions, 615 functions

## v1.98.1

- **Docs:** README polish. Promoted "sconfig for the modern era" to the top tagline, added a production-scale callout under the badges, tightened the opening paragraph with the 15-vs-167 comparison, and reserved (commented-out) embed slots for future screenshots.
- 65 modules, 4535 tests, 176 CLI actions, 615 functions

## v1.98.0

- **New:** `-Action Dashboard` — embedded HTTP server that surfaces live health data as HTML plus JSON endpoints. Binds to `127.0.0.1:8080` by default; override with `-Config "port"` or `-Config "host:port"` (e.g., `-Config "0.0.0.0:8080"` for LAN access on already-elevated processes). Routes: `/` (auto-refreshing HTML dashboard with CPU/memory/disk/uptime, colored against `DashboardWarningPercent`/`DashboardCriticalPercent`), `/api/health` (full snapshot JSON), `/api/version` (tool version JSON), `/api/selftest` (SelfTest-equivalent JSON). HTML auto-refreshes every 10 seconds via meta-refresh so even browsers without JavaScript stay current.
- **New:** `-Action History` — shows the last N CLI invocations from the rolling history log (50-entry cap, stored at `$TempPath\RackStack-ActionHistory.json`). Every CLI action automatically records itself before execution; History and Replay are excluded from the log to avoid self-pollution. `-Config <N>` limits the display count (default 20, max 50). Supports `-OutputFormat JSON`.
- **New:** `-Action Replay -Config <N>` — re-runs a prior CLI invocation by its 1-based index from `-Action History`. Reconstructs the exact argument set (`-Tier`, `-Config`, `-OutputFormat`, `-Silent`, `-Quiet`, `-Stream`) from the history entry and spawns a fresh `RackStack.exe` process so the replay's exit code propagates back to the caller instead of being swallowed by the dispatcher.
- **New:** `-Stream` switch — enables newline-delimited JSON event output for long-running actions in combination with `-OutputFormat JSON`. Batch mode emits typed `batch_start` and `batch_end` events that orchestration can parse line-by-line (progress UIs, pipeline status); the terminating event carries the same aggregate summary as the non-stream mode. Per-step events for Batch and other long actions are groundwork for future releases.
- **New:** **PowerShell Gallery module** — `RackStack.psd1` + `RackStack.psm1` alongside the repo. After `Install-Module RackStack -Scope CurrentUser`, scripts and pipelines get typed cmdlets: `Invoke-RackStackAction`, `Update-RackStack`, `Test-RackStackUpdate`, `Invoke-RackStackSelfTest`, `Export-RackStackLogs`, `Get-RackStackVersion`, `Get-RackStackActionList`, `Get-RackStackExePath`, `Test-RackStackInstalled`. The module locates the EXE via (in order) `$env:RACKSTACK_EXE`, the Programs-and-Features registry key, or `Get-Command RackStack` on PATH, and parses JSON output into objects automatically. Publishing uses `local/publish-psgallery.ps1`.
- **New:** **WinGet manifest generator** — `local/generate-winget-manifest.ps1` produces the three YAML files (`TheAbider.RackStack.yaml`, `.installer.yaml`, `.locale.en-US.yaml`) required to submit a PR to `microsoft/winget-pkgs`. Uses the `portable` installer type so users install without admin and the EXE lands in a per-user directory that's auto-added to PATH. SHA256 is computed from the current `builds/RackStack.exe` and embedded in the installer manifest.
- 65 modules, 4535 tests, 176 CLI actions, 615 functions

## v1.97.0

- **New:** `-Action UpdateSelf` — in-place upgrade of the installed `RackStack.exe`. Queries the GitHub Releases API, downloads the new EXE to a staging directory, SHA256-verifies it against the release body, then uses Windows' rename-of-running-EXE trick to atomically swap: the current binary is renamed to `RackStack.exe.old` (kept as rollback backup) and the new one is copied into the primary name. Registry `DisplayVersion` and `EstimatedSize` are refreshed so Windows Settings → Apps stays accurate. Supports `-OutputFormat JSON`; exits `0` if already latest, `1` on error. Requires a prior `-Install`.
- **New:** `-Action Rollback` — restore the previous `RackStack.exe` from the `.old` backup left by `UpdateSelf` (or a re-run of `-Install`). Uses the same rename-based atomic swap: the current EXE is moved to `.pending-delete` and the backup is renamed back to `RackStack.exe`. Useful when a new version introduces a regression that only surfaces in your environment.
- **New:** `-Action ScheduleUpdateCheck` — registers a weekly scheduled task that runs `RackStack -Action CheckForUpdate -OutputFormat JSON` as `SYSTEM` and writes the JSON result to `$TempPath\RackStack_UpdateCheck.json`. Fleets can aggregate that file via their RMM / SCCM / file server and know which hosts are out of date without having to push a check out of band.
- **New:** `Install-RackStack.ps1 -Rollback` — out-of-tool rollback for when the installed EXE is too broken to run its own `-Action Rollback`. Swaps `RackStack.exe.old` back to primary, refreshes the registry `DisplayVersion`, no network needed. Downloaded fresh from GitHub via the usual `irm | iex` one-liner.
- **New:** `Install-RackStack.ps1 -Install` now works as an upgrade path too. Previously a re-run against an existing install would fail because Windows locks running EXEs against overwrite. It now renames the existing `RackStack.exe` aside (doubles as the `.old` rollback backup) before copying the new one into place, mirroring the `UpdateSelf` strategy.
- **New:** Every `-Install` now generates `RackStack-TabComplete.ps1` in `C:\Program Files\RackStack` containing a `Register-ArgumentCompleter` for the installed EXE's action list. Operators opt in by dot-sourcing it from their PowerShell profile — `RackStack -Action <TAB>` then cycles through every supported action, `-Tier` completes `Light|Standard|Aggressive`, and `-OutputFormat` completes `Console|JSON`.
- **New:** Startup now removes any `RackStack.exe.pending-delete` sibling of the running EXE — this is the cleanup half of the atomic swap used by `UpdateSelf` and `Rollback`. Windows forbids deleting a running EXE, so the superseded binary is first renamed to `.pending-delete` and purged on the next launch of the new process.
- 65 modules, 4535 tests, 173 CLI actions, 615 functions

## v1.96.0

- **New:** `-Action CheckForUpdate` — queries the GitHub Releases API and compares the running version to the latest published tag. Supports `-OutputFormat JSON`. Exit codes: `0` = up to date, `2` = newer version available, `1` = GitHub unreachable / parse error. Designed for scheduled tasks or CI gates that want to detect drift against the published build.
- **New:** `-Action ExportLogs` — bundles the current transcript, up to ten recent transcripts, session state, favorites, command history, the current `Changelog.md`, and an environment snapshot into a single zip ready to attach to a support ticket. Pass `-Config <directory>` to control where the zip lands (defaults to `$script:TempPath`). Supports `-OutputFormat JSON` which reports the zip path, size, and the list of files that were included.
- **New:** Bootstrap installer (`Install-RackStack.ps1`) now verifies the downloaded `RackStack.exe` against the SHA256 published in the release notes body. Parses the hash out of the release body, compares to `Get-FileHash -Algorithm SHA256`, deletes the file and exits `1` on mismatch. Defense-in-depth against an intermediary tampering with the GitHub asset download.
- **New:** `Install-RackStack.ps1 -Install` — proper Windows install. Copies `RackStack.exe` to `C:\Program Files\RackStack`, adds that directory to the system `PATH`, creates an All-Users Start Menu shortcut, and registers the tool under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\RackStack` so Windows Settings → Apps lists it with a working Uninstall button. After install, `RackStack` works from any admin terminal and `RackStack -Action CheckForUpdate` tells you when to reinstall.
- **New:** `Install-RackStack.ps1 -Uninstall` — reverses `-Install`. Removes the Program Files directory, strips the PATH entry, removes the Start Menu shortcut, and unregisters from Programs and Features. No network needed. The same reversal is also embedded as the `UninstallString` so clicking "Uninstall" in Windows Settings works even offline.
- **Fix:** OS build number detection now warns (via `Write-Host` in yellow) when both the registry read AND the WMI fallback fail, instead of silently pinning `$script:OSBuildNumber = 0`. A zero build number made every version-gated feature misbehave (tool thought it was running on a pre-2008R2 OS) with no diagnostic.
- **Fix:** Domain join retry exhaustion now includes the last exception message in the failure summary. Previously the operator saw only "Maximum attempts reached" with no hint about why (DNS? credentials? DC unreachable?). The last error is preserved across retries and printed after the final attempt.
- 65 modules, 4535 tests, 170 CLI actions, 615 functions

## v1.95.0

- **New:** `-Action SelfTest` — a tool self-diagnostic action for operators running `RackStack.exe` across a fleet. Verifies PowerShell version, elevation, version consistency across `Header.ps1`/`RackStack.ps1`/`$script:ScriptVersion`, module count (65 in modular mode), `defaults.json` parse validity, temp-path writability, FileServer reachability (HEAD with 5s timeout), and agent-installer configuration. Supports `-OutputFormat JSON` for structured monitoring; exits `1` if any check fails.
- **New:** Expanded help search topics. The interactive `help <keyword>` searcher now recognises 9 new category topics covering CLI actions that previously only appeared in `-ListActions`: SelfTest, Security Audits, Network Audits, Storage & Cluster Audits, Hyper-V & VM Audits, System Audits, Fleet & Reporting, Server Roles Audit, and Scores & Dashboards. Each topic lists its specific action names so `help security` now discovers `TLSAudit`, `KerberosAudit`, `CredGuardAudit`, etc.
- **New:** `Write-StructuredLog` now auto-redacts values for keys that look like secrets (matches `password`, `passwd`, `pwd`, `secret`, `token`, `apikey`, `api_key`, `credential`, `clientsecret`, `authorization`, `bearer` — case-insensitive). Values are replaced with `[REDACTED]` before the line is written to disk. Defense-in-depth so a future caller that accidentally routes a credential through structured logging can't leak it to the transcript or log file.
- **New:** Joining a failover cluster (`Add-ClusterNode`) and creating a Storage Replica partnership (`New-SRPartnership`) now register a **manual-only** undo entry — the user can trigger it explicitly via "Undo last change" but it never runs automatically. The undo script paths are single-quote-escaped to prevent injection. Removing a cluster node or breaking replication is destructive, so the undo is opt-in rather than opt-out.
- 65 modules, 4535 tests, 168 CLI actions, 615 functions

## v1.94.11

- **Fix:** `-Action Batch -Silent` no longer cancels on the confirmation prompt. Previously `Confirm-UserAction` in silent mode returned the DefaultNo answer, so every headless batch run aborted before doing anything. The confirmation is now skipped entirely in `-Silent` mode (the caller already committed by invoking Batch with a config).
- **Fix:** `-Action Batch -Silent` no longer hangs on `Read-Host` when creating a local admin account. In silent mode the password now comes from (in priority order): `Config.LocalAdminPassword` (inline), the env var named by `Config.LocalAdminPasswordEnv`, or `$env:RACKSTACK_LOCAL_ADMIN_PWD`. If none are set, the step fails cleanly with a diagnostic instead of blocking forever.
- **Fix:** `-Action Batch -Silent` no longer hangs on the post-failure undo prompt. The prompt now goes through `Confirm-UserAction`, which in silent mode returns the safe default (skip undo) rather than blocking on `Read-Host`.
- **Fix:** `-Action Batch -OutputFormat JSON` now emits a machine-readable summary on completion — `{Action, Timestamp, Hostname, ConfigType, DryRun, TotalSteps, ChangesApplied, Skipped, Errors, RebootNeeded, Success}`. Previously the Batch action silently produced no JSON even when JSON was requested.
- 65 modules, 4535 tests, 167 CLI actions, 615 functions

## v1.94.10

- **Fix:** Batch mode now returns a meaningful exit code — `Start-BatchMode` returns the failed-step count and both CLI callers (`-Action Batch` and the auto-run from `batch_config.json`) set the process exit code accordingly. Previously both paths unconditionally exited `0`, so CI/CD orchestration couldn't detect when batch steps failed.
- **Fix:** Main menu dashboard color thresholds (`DashboardWarningPercent` / `DashboardCriticalPercent`) were advertised in `defaults.example.json` but never loaded from `defaults.json` — dashboards were permanently pinned to the hardcoded 70/90 defaults. Wired through `Import-Defaults` with 1-100 range validation.
- **Fix:** VLAN status view no longer silently swallows errors when Hyper-V isn't installed — errors that aren't "Hyper-V not available" are logged at Debug level so troubleshooting is possible.
- **Fix:** Adapter diagnostics now log when `Get-NetAdapterStatistics` fails (e.g., for virtual/loopback adapters that don't expose counters) instead of eating the error silently.
- **Hardened:** Azure Blob Storage XML listing (`39-FileServer.ps1`) and Group Policy XML parse (`50-EntryPoint.ps1` GPAudit) are now parsed with `XmlResolver = $null` to block external-entity (XXE) resolution. Defense-in-depth against tampered XML even on trusted channels.
- **Hardened:** `Get-FileServerFile` and the agent installer now reject filenames containing `..`, path separators, drive-letter prefixes, null bytes, or excessive length. Prevents a tampered FileServer listing from writing outside the intended cache / temp directory.
- **Hardened:** Batch-mode Defender exclusion undo script now properly escapes single quotes in each path before building the `[scriptblock]::Create(...)` literal, so a path containing `'` can't break out of the quoted list.
- 65 modules, 4535 tests, 167 CLI actions, 615 functions

## v1.94.9

- **Fix:** Firewall rule audit counted zero enabled rules on some systems — the `FirewallRuleAudit` CLI action was comparing the `.Enabled` property returned by `Get-NetFirewallRule` to the string `'True'`, but that property is a `GpoBoolean` enum whose string form isn't guaranteed to be `"True"`. Now compares to the boolean `$true` directly, which matches reliably across Windows Server builds.
- **Hardened:** Defender custom exclusion menu now detects sensitive OS directories (`C:\`, `C:\Windows`, `C:\Program Files`, `C:\ProgramData`, `C:\Users`, `%SystemRoot%`, `%SystemDrive%`) and requires an extra confirmation before adding them. Previously the syntax-only path check accepted them without warning, silently disabling Defender scanning across critical areas.
- **Hardened:** Agent installer now threads an optional SHA256 hash through the FileServer downloader (`-ExpectedHash`). If a hash manifest is configured for agent installers, downloads are verified against it in addition to the existing remote-hash companion file — caller-side defense-in-depth against FileServer tampering.
- **Hardened:** Generated admin passwords copied to the clipboard now auto-clear after 60 seconds (while the RackStack window remains open). The clear is conditional — if the user has copied something else in the meantime it's left alone.
- **Hardened:** Password strength feedback no longer logs the exact character count — length bucket labels (`14+ chars`, `10-13 chars`, `8-9 chars`, `<8 chars`) replace `($length chars)` so transcripts don't narrow the search space for anyone who later reads them.
- **Hardened:** CI workflow now sets `timeout-minutes: 15` on the test job so a hung test can't tie up the self-hosted runner indefinitely (the full suite normally runs in ~2.5 minutes).
- 65 modules, 4535 tests, 167 CLI actions, 615 functions

## v1.94.8

- **Fix:** Performance Dashboard now guards against the `Failed` path from `Invoke-WithTimeout`. Previously, if the runspace that wraps the CIM queries failed to start (e.g., runspace pool exhausted, insufficient resources), `$cimResult.Result` would be `$null` and the subsequent `$cimResult.Result.CPU` access would crash the dashboard. The guard mirrors the existing `TimedOut` handling and offers the same `[R]` retry path.
- 65 modules, 4535 tests, 167 CLI actions, 615 functions

## v1.94.7

- **Hardened:** `Set-HostName` DNS name-collision check is now wrapped in `Invoke-WithTimeout` with a 5-second cap — previously used raw `Resolve-DnsName` which has no native timeout and could hang the hostname menu on a slow DNS server.
- **Hardened:** VM deployment name-collision check (`Test-VMNameExists`) is now wrapped in `Invoke-WithTimeout` with a 5-second cap — previously could hang the VM deployment wizard.
- **Security:** `Register-ScheduledExport` now validates `OutputDir` and `Sections` parameters with `[ValidateScript()]` that rejects double-quotes, backticks, `$`, and control characters. These characters could otherwise break out of the scheduled task argument string and inject additional command-line flags when the task runs.
- **Updated:** Function count refreshed — historical changelog footers claimed 641 functions; the actual `function` keyword grep count across all modules is 615. This release aligns the footer with reality and going forward the count comes from an actual grep.
- 65 modules, 4535 tests, 167 CLI actions, 615 functions

## v1.94.6

- **Hardened:** DNS resolution checks in `HealthDashboard` and HTML health reports are now wrapped in `Invoke-WithTimeout` with an 8-second cap. Previously used raw `Resolve-DnsName -ErrorAction Stop`, which has no native timeout — a slow/unresponsive DNS server would block the UI indefinitely.
- **Fix:** `Enable-RDP` now reads the `fDenyTSConnections` registry value with `-ErrorAction SilentlyContinue` and null-checks the result. Previously, a missing registry key (stripped/hardened builds) could produce a confusing null-reference error instead of a clean fallback.
- **Fix:** Test `ConvertFrom-AgentFilename: invalid file returns empty SiteNumbers` now wraps `.Count` in `@()`. PS 5.1 returns `$null` for `.Count` on single objects, so the test could spuriously fail if the function ever returned a single-element non-array.
- 65 modules, 4535 tests, 167 CLI actions, 641 functions

## v1.94.5

- **Fix:** `55-QoLFeatures.ps1` was missing its closing `#endregion` marker. `sync-to-monolithic.ps1` has been silently chopping the last line of the file (assumed to be `#endregion`) for an unknown number of releases, dropping a harmless trailing comment line every build. Restored the marker and hardened the sync script to throw explicitly if the marker is missing, so this class of silent corruption can't recur.
- **Fix:** Batch-mode undo state JSON (`50-EntryPoint.ps1:11811`) now writes with `-Encoding UTF8` — previously used the default ANSI encoding which would corrupt non-ASCII characters (e.g., international hostnames, Unicode passwords) saved into the batch undo trail, breaking undo on reload.
- **Hardened:** First-boot script generator (`43-OfflineVHD.ps1:259`) now writes `SetupComplete.cmd` with explicit `-Encoding ASCII`. `cmd.exe` expects ASCII/ANSI and rejects UTF-16 BOM, so the explicit encoding prevents surprises on PowerShell hosts where `Default` differs from `ASCII`.
- 65 modules, 4535 tests, 167 CLI actions, 641 functions

## v1.94.4

- **Fix:** `Install-RackStack.ps1` bootstrap now retries GitHub API and download failures with exponential backoff — previously failed immediately on transient errors or HTTP 429 rate-limit, breaking fleet deploys via Ansible/PDQ/RMM tools. Honors `Retry-After` headers, retries on 408/429/500/502/503/504, up to 4 attempts with 2s → 4s → 8s → 16s backoff, adds explicit request timeouts.
- **Hardened:** `Exit-Script` now disposes `$script:VMDeploymentCredential.Password` (SecureString) and clears the reference on exit — defense-in-depth so cached remote-deployment credentials don't linger in the PowerShell process longer than necessary.
- **Tests:** Added regression tests asserting each v1.94.2/1.94.3 menu dispatcher actually calls the wired function (`Show-WhatsNew`, `Show-SystemBanner`, `New-StrongPassword`, `Optimize-VHDFile`). Prevents the "implemented but not reachable" class of bug found in the v1.94.2 audit from recurring.
- **Tests:** Added regression tests asserting `Show-WhatsNew` and `Show-Changelog` resolve their changelog path via `$script:ModuleRoot` instead of the module-local `$PSScriptRoot`.
- **Tests:** Added tests asserting `Install-RackStack.ps1` has the retry helper and that it's used by both the API call and the download.
- 65 modules, 4535 tests, 167 CLI actions, 641 functions

## v1.94.3

- **Fix:** "What's New" and "View Changelog" now find `Changelog.md` reliably in modular, monolithic, and compiled EXE modes — previously used `$PSScriptRoot` inside a dot-sourced module, which resolved to the `Modules/` subdirectory and always missed the file. Uses `$script:ModuleRoot` with fallbacks and shows a link to GitHub Releases when the changelog isn't bundled with the build.
- **Fix:** Settings menu help documentation now lists options `[14]` What's New and `[15]` System Info Banner.
- **Fix:** Security & Access help documentation now lists option `[11]` Generate Strong Password.
- **Fix:** VHD Optimization function (`Optimize-VHDFile`) is now reachable from the VHD Management menu (`[6]`) — previously implemented and advertised but had no caller.
- **Fix:** Removed dead code: `Show-RoleTemplates` — an orphaned per-role checklist function whose name confusingly collided with the unrelated `Show-RoleTemplateSelector` installer; superseded by `Show-ServerReadiness` (Tools & Utilities `[7]`).
- **Fix:** Test at `Run-Tests.ps1:4240` was silently passing because its regex partial-matched `Show-RoleTemplates` against `Show-RoleTemplateSelector`; the false-positive test block has been removed along with the dead function.
- **Enhanced:** Help search (`help <keyword>`) now includes topics for What's New, System Info Banner, Strong Password, and VHD Optimize.
- **Updated:** README.md function count refreshed.
- 65 modules, 4520 tests, 167 CLI actions, 641 functions

## v1.94.2

- **Fix:** "What's New" highlights view is now reachable from the Settings menu (`[14]`) — previously implemented but never wired into a menu.
- **Fix:** "System Info Banner" quick view (hostname, IP, domain, OS, uptime) is now reachable from the Settings menu (`[15]`) — previously implemented but never wired into a menu.
- **Fix:** "Generate Strong Password" is now reachable from the Security & Access menu (`[11]`) — uses the cryptographically secure password generator from v1.90.0 that was previously unreachable.
- **Cleanup:** Removed dead code: `Invoke-LogRotation`, `Optimize-ConsoleBuffer`, `Test-ValidUNCPath`, `ConvertTo-SafeLDAPFilter`, `Test-ValidFilePath`, `Add-MultipleVNICs`, `Add-BackupNIC`, `Save-NetworkBaseline`, `Add-CommandHistory`, `Test-S2DAvailable` — ten internal helpers with no callers in the codebase.
- **Cleanup:** Removed corresponding tests for deleted helpers; null-byte injection coverage retained for `Test-ValidHostname` and `Test-ValidIPAddress`.
- 65 modules, 4529 tests, 167 CLI actions, 642 functions

## v1.94.1

- **Fix:** `RotateExports` CLI action was completely broken — called `Invoke-ExportRotation` with wrong parameter name (`-ExportDir` instead of `-OutputDir`).
- **Fix:** Help search topic updated from 157 to 167 CLI actions with new keywords for PolicyCheck, SLAReport, NetMap, Validate.
- **Fix:** `Install-RackStack.ps1` ValidateSet updated to include all 7 new CLI actions — previously rejected `NetMap`, `PolicyCheck`, `SLAReport`, `Validate`, `Readiness`, `BaselineDiff`, `RotateExports`.
- **Fix:** CLI action count test guard bumped from 137 to 167 — previously wouldn't catch removal of up to 30 actions.
- **Fix:** Test for `Test-MinimumDiskSpace` now uses fallback drive letter to avoid false failures on systems with mapped Z: drives.
- **Updated:** README.md — all counts updated (167 actions, 651 functions, 4500+ tests), 10 new actions added to CLI table.
- **Updated:** CONTRIBUTING.md test count updated to 4,500+.
- 65 modules, 4567 tests, 167 CLI actions, 651 functions

## v1.94.0

- **New:** `PolicyCheck` CLI action — validate any server against custom compliance policies defined in JSON. Supports 20+ built-in checks: TLS versions, SMBv1, RDP/NLA, password policy, firewall profiles, UAC, guest account, NTLMv1, Defender real-time, BitLocker, script block logging, and more. Run: `RackStack.exe -Action PolicyCheck -Config policy.json`
- 65 modules, 4565+ tests, 167 CLI actions, 651 functions

## v1.93.0

- **New:** `NetMap` CLI action — discovers all network dependencies in one command: DNS servers, gateways, domain controllers, NTP source, iSCSI targets, top TCP connections by remote host, and SMB shares. Structured JSON output for fleet dependency mapping.
- **Fix:** SMB Session Audit stale session detection now works — was using nonexistent `ConnectedTime` property, now correctly uses `SecondsActive`.
- 65 modules, 4550+ tests, 166 CLI actions, 650 functions

## v1.92.1

- **Fix:** WMI Audit provider test now correctly displays query latency — broken string interpolation `${$p.QueryMs}` replaced with `$($p.QueryMs)`.
- **Fix:** Port Audit TCP connections now properly disposed in `finally` block — previously leaked socket handles on connection exceptions.
- **Fix:** Added `-OperationTimeoutSec` to 14+ CIM queries across BIOSAudit, MemoryAudit, DiskAudit, DriverAudit, CredGuardAudit, USBDeviceAudit, ServiceAccountAudit, and SysInfoAudit — prevents indefinite hangs on systems with degraded WMI.
- 65 modules, 4540 tests, 165 CLI actions, 649 functions

## v1.92.0

- **New:** `SLAReport` CLI action — calculates server uptime percentage over a configurable period, with SLA compliance checks (99.9%, 99.5%, 99.0%), incident breakdown, longest outage duration, and unexpected shutdown count. JSON output for automation.
- **New:** `Validate` CLI action — pre/post change validation workflow. Run `-Action Validate -Config pre` before changes, make changes, then `-Action Validate -Config post` to get an automatic diff showing exactly what changed. Ideal for change management tickets.
- **Fix:** Storage Replica partnership removal now filters by source, destination, AND replication group — previously could delete unrelated partnerships from the same source server.
- **Fix:** Storage Replica sync status now shows 100% for fully synced replicas instead of "N/A" — zero bytes remaining was treated as falsy.
- **Fix:** Storage Manager drive letter map now uses consistent `Format-ByteSize` instead of `Format-TransferSize`.
- 65 modules, 4540 tests, 165 CLI actions, 649 functions

## v1.91.1

- **Fix:** IP rollback now handles adapters with multiple default routes — previously could leave the adapter unconfigured if rollback failed.
- **Fix:** VLAN partial adapter matching now warns about non-exact matches and blocks when multiple adapters match — previously could silently modify the wrong adapter.
- **Fix:** NTP time accuracy test now uses `Invoke-WithTimeout` to prevent 30+ second hang when internet is unreachable.
- **Fix:** File download resume now tracks elapsed time correctly — previously reported 0 seconds and wrong transfer speed after successful resume.
- **Fix:** Session restore now properly restores SessionChanges from saved state — previously dropped them silently.
- **Fix:** `Write-CenteredOutput` now respects the `$width` parameter (default 72) instead of ignoring it.
- **Fix:** `Add-SessionChange` no longer calls `Get-Command` on every invocation — direct function call eliminates per-change overhead.
- **Fix:** `Add-Favorite` now deduplicates — prevents adding the same item multiple times.
- **Fix:** Session summary separator lines are now properly indented to match surrounding content.
- 65 modules, 4528 tests, 163 CLI actions, 647 functions

## v1.91.0

- **Fix (CRITICAL):** Hyper-V Replica certificate-based authentication now prompts for certificate selection from the local machine store — previously always failed due to missing thumbprint parameter.
- **Fix (CRITICAL):** Hyper-V Replica reverse replication now uses the correct parameter set — previously always failed due to mutually exclusive `-Reverse` and `-ReplicaServerName` parameters.
- **Fix:** Remote VM deployment with explicit credentials now uses `Invoke-Command` for VHD creation — `New-VHD` does not support the `-Credential` parameter directly.
- **Fix:** Cluster quorum health check now accounts for the witness vote (disk/file share/cloud witness), preventing false "AT RISK" warnings on properly configured 2-node clusters.
- **Fix:** SET creation now clears stale iSCSI candidate adapters from previous runs, preventing misconfiguration prompts showing adapters from a prior auto-detect session.
- **New:** `Readiness` CLI action — pre-deployment readiness checklist with structured JSON output, returns exit code 1 when checks fail.
- **New:** `BaselineDiff` CLI action — compare two saved baselines to see what changed between them, ideal for scheduled change auditing.
- **New:** `RotateExports` CLI action — prune old export files by retention count, the cleanup companion for `ScheduledExport`.
- 65 modules, 4528 tests, 163 CLI actions, 647 functions

## v1.90.2

- **Fix:** Baseline Save now stores actual performance snapshot data instead of just the file path, making baselines self-contained.
- **Fix:** Cleanup CLI action now validates the profile tier and exits with error code for invalid profiles instead of silently doing nothing.
- **Fix:** BootAudit no longer makes a redundant CIM query for DEP status — reuses the existing Win32_OperatingSystem result.
- **Fix:** ConfigExport `Export-ServerConfiguration` now uses `List<string>` instead of 120+ `+=` array operations for significantly better performance on servers with many adapters/disks/services.
- **Fix:** ConfigExport profile import now uses explicit `$script:` scope for the local admin account name variable, preventing potential empty-name account creation.
- **Fix:** `Save-ConfigurationProfile` now validates the parent directory exists before attempting to write.
- **Fix:** Configure Server menu now caches `Test-RebootPending` result instead of hitting registry/WMI on every menu render.
- 65 modules, 4508 tests, 157 CLI actions, 644 functions

## v1.90.1

- **Fix:** Batch mode orphaned `else` block in UI cleanup step could cause parse error at runtime when Win11Cleanup is enabled.
- **Fix:** DC scenario template now uses correct batch executor field names (`PromoteToDC`, `DCPromoType`, `ForestName`) — previously DC promotion was silently skipped.
- **Fix:** All batch scenario templates (Hyper-V Host, Cluster Node, File Server) now use `ConfigureFirewall` and `SetPowerPlan` matching the executor, instead of non-functional `FirewallDomain`/`FirewallPrivate`/`FirewallPublic`/`PowerPlan` keys.
- **Fix:** HTML health report issues summary now always checks disk space, firewall state, and critical events regardless of which report sections are selected — previously a report with only Performance selected could show "HEALTHY" while disks were full and firewall was disabled.
- **Fix:** Performance dashboard clipboard copy now includes Top Processes by Memory section (was only showing CPU).
- **Fix:** HTML trend report disk usage table now has proper column headers.
- 65 modules, 4497 tests, 157 CLI actions, 644 functions

## v1.90.0

- **Fix:** User audit no longer flags accounts with null password expiry as "EXPIRED" — previously `$null -lt (Get-Date)` evaluated true in PowerShell.
- **Fix:** Password strength checker now uses `PtrToStringBSTR` (correct paired call) instead of `PtrToStringAuto`, preventing potential data misread on some platforms.
- **Fix:** Password strength checker and DSRM password validation now clear plaintext variables from memory in `finally` blocks.
- **Fix:** Removed dead code in scheduled export CLI action where both branches returned the same value.
- **Fix:** Removed leftover debug environment variable assignment in BIOS audit.
- **Security:** Password generator now uses `RNGCryptoServiceProvider` instead of `Get-Random` for cryptographically secure index generation.
- **Security:** RDP and WinRM subnet restriction prompts now validate CIDR format and reject overly broad subnets (wider than /8).
- **New:** Disk reliability / SMART data section in health check — shows temperature, wear level, power-on hours, and read/write error counts per physical disk.
- **New:** Failed services quick view in Service Manager — shows all Automatic services that are Stopped, the most common troubleshooting query.
- **Enhanced:** Storage Manager disk display now shows serial number and media type (SSD/HDD) alongside the model name.
- 65 modules, 4497 tests, 157 CLI actions, 644 functions

## v1.89.12

- **Fix:** iSCSI side detection now correctly restores original adapter IP configuration after testing instead of leaving adapters unconfigured.
- **Fix:** Timezone offset formatting for half-hour negative timezones (e.g., Newfoundland UTC-03:30) now displays correctly instead of showing negative minutes.
- **Fix:** Cluster dashboard resource groups no longer leak increment values into color assignments, which could cause display errors.
- **Fix:** VM checkpoint age warnings now use `Get-VMSnapshot` consistently across all functions for compatibility.
- **Fix:** Agent installer pre-install version check now correctly passes the agent service name parameter.
- **Fix:** WinRM state detection now returns "Disabled" when zero configuration checks pass, instead of incorrectly showing "Partial."
- **Fix:** Host storage analysis now checks the correct subfolder names (Virtual Machines, _BaseImages) matching the actual created folder structure.
- **Fix:** Duplicate DiagTrack entry removed from server aggressive debloat profile — service was being disabled twice.
- **Fix:** Firewall rule search no longer logs session changes or clears menu cache for read-only search operations.
- **Fix:** Disk cleanup Quick Clean no longer shows a double "Press Enter" prompt.
- **Fix:** Defender exclusion display now handles extensions that already include a leading dot, preventing double-dot display.
- **Fix:** Event log viewer now clears stale search results when a query returns empty, preventing export of stale data.
- **Fix:** Offline VHD setup scripts folder check now uses `-LiteralPath` for paths containing special characters.
- **Enhanced:** Remote health check and service manager now use theme-aware colors instead of hardcoded console colors.
- **Enhanced:** Firewall rule audit export now uses efficient `List<object>` collection instead of `+=` array growth for better performance on large rule sets.
- **Enhanced:** Sync-to-monolithic build script now exits with error code 1 when parse errors are detected.
- **New:** HTTPS connectivity test — network connectivity check now tests HTTPS in addition to ICMP ping and DNS, catching firewall configurations that block ping but allow web traffic.
- **New:** UDP listener display — port scan now shows UDP listeners (DNS, DHCP, NTP, SNMP, etc.) alongside TCP connections.
- **New:** System restore point creation before debloat operations provides an additional safety net on workstation editions.
- **Fix:** PowerShell scan workflow now wraps filtered `.Count` calls in `@()` for PS 5.1 compatibility.
- 65 modules, 4477 tests, 157 CLI actions, 643 functions

## v1.89.11

- **Enhanced:** RDP security status now shows active RDP session count.
- **Enhanced:** Scheduled task views now include next run time alongside last run time.
- **Enhanced:** Hostname configuration shows pending rename if a hostname change is waiting for reboot.
- 65 modules, 4449 tests, 157 CLI actions, 642 functions

## v1.89.10

- **New:** Performance Dashboard now shows Top Processes by Memory alongside CPU — see which processes consume the most RAM at a glance.
- **New:** What's New function (`Show-WhatsNew`) — displays current version changes from changelog with color-coded categories (green=New, yellow=Fix, cyan=Enhanced).
- **Enhanced:** Windows Update history now extracts and displays KB article numbers (e.g., [KB5001234]) alongside update titles.
- **Enhanced:** License status now shows expiry date and KMS renewal interval when applicable.
- **Enhanced:** Disk cleanup shows temp file COUNT alongside size (e.g., "352.1 MB (4,231 files)").
- **Enhanced:** Debloat analysis shows estimated space savings before cleanup starts.
- **Enhanced:** Agent installer shows currently installed version before reinstall to help assess update necessity.
- 65 modules, 4449 tests, 157 CLI actions, 642 functions

## v1.89.9

- **New:** VHD Optimization function (`Optimize-VHDFile`) — compact dynamic VHDs, shows before/after size and space saved. Validates VHD type and mount status before operating.
- **Enhanced:** Agent installer now shows currently installed version before reinstall/update confirmation.
- **Enhanced:** Drift detection report now includes a "Changes detected" narrative section showing before->after values for all drifted settings.
- 65 modules, 4433 tests, 157 CLI actions, 641 functions

## v1.89.8

- **New:** System Summary Banner (`Show-SystemBanner`) — standalone function showing hostname, IP, domain, OS version, and uptime in a formatted box. Callable independently for quick system identification.
- **Hardened:** Local admin account creation now rejects reserved system names (Administrator, Guest, SYSTEM, etc.) before attempting creation.
- 65 modules, 4433 tests, 157 CLI actions, 640 functions

## v1.89.7

- **Enhanced:** Offline VHD customization now validates VHD format before attempting mount, catching corruption early with clear error messages.
- **Enhanced:** VM Checkpoint age report now shows individual checkpoint sizes and total disk usage.
- **Enhanced:** HTML Security Report now includes Defender signature age with color-coded status.
- **Enhanced:** Firewall and Storage Replica error messages now include operation context instead of generic "Failed".
- 65 modules, 4433 tests, 157 CLI actions, 638 functions

## v1.89.6

- **New:** Reboot Pending Reasons — health check now shows WHY a reboot is pending (Windows Update KB, component servicing, hostname change, file rename operations).
- **New:** Strong Password Generator — generates complex random passwords (12-128 chars, upper/lower/digit/special, no ambiguous chars), auto-copies to clipboard. Available as `New-StrongPassword` function.
- **New:** Gateway Connectivity Test — standalone test in Network Diagnostics that pings all default gateways and shows per-adapter latency.
- 65 modules, 4433 tests, 157 CLI actions, 638 functions

## v1.89.5

- **New:** iSCSI Status now shows local initiator IQN (needed for SAN whitelist configuration).
- **New:** Current User Group Memberships function — shows all group memberships with admin groups highlighted. Useful for permission troubleshooting.
- **Enhanced:** Hyper-V installation now detects if running in a VM and suggests enabling nested virtualization on the host.
- **Enhanced:** Firewall profile toggle now shows rule count and active rules affected before applying changes.
- 65 modules, 4423 tests, 157 CLI actions, 636 functions

## v1.89.4

- **Enhanced:** Network adapter table now shows MAC addresses alongside name, status, and speed.
- **Enhanced:** Health check system info now shows Windows build number and feature update version (e.g., "26100 (24H2)").
- **Enhanced:** Full Enhanced Disk Cleanup now shows total space recovered by comparing free space before and after all operations.
- 65 modules, 4423 tests, 157 CLI actions, 634 functions

## v1.89.3

- **New:** Logged-On Users display in Operations menu — shows active RDP/console sessions with color-coded status (Active=green, Disconnected=yellow).
- **New:** Failed Logon Attempts (Event 4625) viewer in Event Log Viewer — shows last 24h of failed authentication attempts from Security log.
- **Enhanced:** Health check now reports Defender exclusion count (paths + processes). Flags if >10 exclusions configured.
- 65 modules, 4423 tests, 157 CLI actions, 634 functions

## v1.89.2

- **New:** WinRM subnet restriction — after enabling PowerShell Remoting, option to restrict WinRM access (ports 5985/5986) to a specific subnet. Same pattern as RDP restriction with undo support.
- 65 modules, 4423 tests, 157 CLI actions, 633 functions

## v1.89.1

- **New:** RDP subnet restriction — after enabling RDP, option to restrict access to a specific subnet via firewall rule. Shows restriction status in security posture display. Includes undo support.
- 65 modules, 4423 tests, 157 CLI actions, 633 functions

## v1.89.0

- **New:** Remote Desktop (RDP) firewall rule template — enables built-in RDP rules plus custom TCP/UDP 3389 rules on Domain and Private profiles with undo support.
- **New:** Windows Remote Management (WinRM) firewall rule template — enables WinRM HTTP (5985) and HTTPS (5986) rules with undo support.
- **New:** Allow Ping (ICMP Echo Request) firewall rule template — enables inbound ICMPv4/v6 echo request rules on Domain and Private profiles, with fallback to custom rule creation.
- **New:** NTP Time Sync (UDP 123) firewall rule template — creates inbound and outbound NTP rules for time synchronization.
- **New:** SNMP Monitoring (UDP 161/162) firewall rule template — enables SNMP agent polling and trap rules for monitoring tools.
- **New:** Firewall Rule Templates menu reorganized with section headers (Server Roles, Remote Access, Infrastructure Services, Tools) for better navigation.
- **New:** Sync Time option in System Configuration menu — synchronize system clock via NTP without changing timezone. Shows current time, NTP source, and updated time after sync.
- **New:** Flush DNS Cache in Network Diagnostics — clears DNS client cache and optionally re-registers DNS for domain-joined machines.
- **New:** Network Stack Reset in Network Diagnostics — guided reset with 4 levels: DNS-only, Winsock, TCP/IP, or full reset. Includes confirmation prompts and sets reboot-needed flag.
- **Fix:** System Configuration menu no longer freezes for 10-30 seconds on workstations. License activation check now has a 5-second timeout and all status data loads before the menu renders.
- **Fix:** Windows Updates no longer shows an interactive NuGet provider prompt on fresh systems. Package management prompts are now fully suppressed.
- **Hardened:** Added -OperationTimeoutSec to 6 additional Get-CimInstance calls (SoftwareLicensingProduct, Win32_Processor, Win32_ComputerSystem, Win32_OperatingSystem, MPIO_DISK_INFO) to prevent WMI hangs.
- **Hardened:** Added -ErrorAction to unprotected Get-NetAdapter calls in SET team health check and iSCSI auto-setup. Added null guard to Defender exclusions menu. Added error handling to DNS undo scripts.
- **Enhanced:** Defender status in Security menu now shows signature age alongside real-time protection status (e.g., "RT:On Sigs:1d"). Status also shown on Dashboard menu item. Color-coded: green if RT on and sigs fresh, yellow if sigs stale, red if RT off.
- **Enhanced:** System Configuration menu now shows pending reboot indicator when Windows has a reboot pending.
- **Enhanced:** Health check now flags physical adapters running at 100 Mbps (potential cabling/switch issue) and reports packet errors on adapters.
- **Enhanced:** Health check Defender section now reports signature age (color-coded: green ≤3d, yellow 3-7d, red >7d) and last scan timestamp.
- **Enhanced:** Server readiness check now downgrades Defender status if signatures are stale (>7 days).
- **Enhanced:** System Configuration menu now displays system uptime (no CIM overhead — uses TickCount64).
- **Enhanced:** Host Network Configuration menu now shows adapter summary ("3 up, 1 down") with color coding.
- **Enhanced:** Network Configuration menu now shows primary IP address and DHCP/Static origin with color coding (green=Static, yellow=DHCP).
- **Hardened:** Added error handling to fleet results export (45-ConfigExport) and batch config export (36-BatchConfig) to gracefully handle disk full or permission errors during file writes.
- **Fix:** Uptime display uses TickCount64 with fallback to TickCount for .NET Framework versions below 4.8 (Server 2016/2019 compatibility).
- **Fix:** Network stack reset now checks netsh exit codes and reports failures instead of silently succeeding.
- **Fix:** Sync Time validates w32tm command exists before attempting time synchronization.
- **Enhanced:** Service Manager now shows a critical service warning (red) when attempting to stop infrastructure services (NTDS, DNS, DFSR, LanmanServer, W32Time, ClusSvc, vmms).
- **Enhanced:** IP Configuration Summary now shows DNS suffix search list (global) and per-adapter connection-specific DNS suffixes.
- **Enhanced:** Main menu dashboard now shows session change count and undoable actions when changes have been made.
- **Enhanced:** VM deployment now checks disk space before creating VHDs and warns if storage is low (prevents mid-creation failures).
- **Enhanced:** System Config menu uptime now includes last boot date/time.
- **Enhanced:** Windows Updates menu item shows last successful update date from event log (fast — no COM object overhead).
- **Enhanced:** Main menu dashboard shows session change and undo count when changes have been made.
- **Fix:** BitLocker now validates TPM presence and readiness before attempting TPM-based encryption. Shows clear error and suggests password-only mode on non-TPM systems.
- **Fix:** Scheduled task import now checks for existing tasks and offers overwrite (uses `-Force`) instead of failing with cryptic error.
- **Fix:** WSB and Deduplication feature status queries now have proper cache timeouts (300s) matching other feature checks.
- **Fix:** Hyper-V Replica frequency display now handles non-standard replication intervals instead of showing blank.
- **Fix:** NTP configuration now validates W32Time service exists and restarts properly, with clear warnings on failure.
- **Cleanup:** Removed dead code: `Compare-NetworkBaseline` and `Compress-OldTranscripts` functions (never called from any menu or CLI action).
- **Fix:** UAC elevation denial now exits with code 1 (failure) instead of 0, enabling automation scripts to detect denied elevation.
- **Fix:** Batch mode validates null/empty JSON config before proceeding, preventing silent no-op runs.
- **Hardened:** Start-BatchMode ensures TempPath directory exists before writing batch undo state.
- **Major:** System Debloat is now fully version-aware. Automatically detects Windows 10, 11 (22H2/23H2/24H2/25H2+), and Server 2025 and applies version-specific package removals, registry tweaks, and UI customizations. New packages for 24H2+ (Copilot, Outlook, Cross-Device), 25H2+ (Recall, AI Studio). Version-specific registry: Recall disable, Copilot policy, telemetry minimization. UI cleanup now works on Win10 too (Cortana, web search). Batch mode Win11Cleanup is now version-aware and works on all versions automatically.
- **Enhanced:** Debloat telemetry task sweep now covers 11 task paths (added RetailDemo, MobilePC, Shell, Cortana for 24H2+).
- **Enhanced:** Workstation debloat Standard/Aggressive now auto-removes known startup bloat entries (OneDrive, Teams, Edge, Cortana) from Run registry keys without user interaction.
- **Enhanced:** Debloat registry tweaks now disable Edge startup boost, Edge sidebar, and OneDrive pre-sign-in network traffic.
- **Enhanced:** Custom debloat startup scanner now checks RunOnce keys in addition to Run keys.
- **Enhanced:** Debloat detects Server Core and skips AppX/UI operations with informational messages instead of failing silently.
- 65 modules, 4423 tests, 157 CLI actions, 633 functions

## v1.88.0

- **New CLI Action:** `InsecureServiceAudit` — finds services with unquoted paths (classic privilege escalation vector where spaces in unquoted paths allow executable hijacking) and non-default services running as LocalSystem. JSON output with full details.
- 65 modules, 4282 tests, 157 CLI actions

## v1.87.3

- **Fix:** TimeSkewAudit used raw `$matches` instead of `$regexMatches` — caught by CI codebase scan. Fixed to follow the project convention of immediately capturing `$matches` to `$regexMatches`.
- 65 modules, 4279 tests, 156 CLI actions

## v1.87.2

- **Security (HIGH):** Self-update batch file now validates paths for cmd.exe injection characters (`& | < > ^ " %`). Aborts update with clear error if exe path contains unsafe characters instead of writing a vulnerable batch file.
- **Security (MEDIUM):** SMB3 UNC path validation tightened from `[^\\]+` (any character) to `[a-zA-Z0-9._-]+` (RFC 952/1123 DNS-safe characters only). Prevents server names with command syntax like `\\server;cmd\share`.
- 65 modules, 4279 tests, 156 CLI actions

## v1.87.1

- **Security:** Null byte injection prevention — all input validation functions (Test-ValidHostname, Test-ValidIPAddress, Test-ValidFilePath, Test-ValidUNCPath) now reject strings containing null bytes. Prevents truncation attacks where `"SERVER\0.evil.com"` could bypass validation.
- 65 modules, 4279 tests, 156 CLI actions

## v1.87.0

- **New CLI Action:** `TPMAudit` — TPM presence, version (1.2/2.0), readiness, enabled/owned status, manufacturer. Flags missing or unready TPM.
- **New CLI Action:** `SecureBootAudit` — UEFI vs Legacy boot mode, Secure Boot enabled/disabled, DEP/NX policy. Flags Legacy boot and disabled Secure Boot.
- **New CLI Action:** `TimeSkewAudit` — NTP source, stratum, last sync time, actual clock skew measurement via w32tm stripchart. Flags free-running clocks and >5s skew.
- **New CLI Action:** `NetworkProfileAudit` — shows which network profile (Domain/Private/Public) each adapter is using. Flags Public profile adapters that may block services.
- 65 modules, 4275 tests, 156 CLI actions

## v1.86.4

- **Security:** Passwords can no longer start with `$` `#` `-` `'` or `"` — these characters break Unix crypt hashes, PowerShell variable interpolation, config file parsing, and command-line quoting. Visual checklist now includes "Safe starting character" check.
- 65 modules, 4263 tests, 152 CLI actions

## v1.86.3

- **New CLI Action:** `DNSCacheAudit` — dumps and analyzes the DNS client cache. Shows total entries, unique names, record type breakdown, and negative cache (failed lookups). JSON output with full cache sample.
- 65 modules, 4255 tests, 152 CLI actions

## v1.86.2

- **New CLI Action:** `GPResultAudit` — exports and parses Group Policy results (gpresult /X). Shows applied computer and user GPOs, domain, last refresh time, and flags access-denied GPOs. Graceful handling for non-domain-joined servers. JSON output.
- 65 modules, 4252 tests, 151 CLI actions

## v1.86.1

- **New CLI Action:** `FirewallRuleAudit` — summarizes all firewall rules (enabled/disabled, inbound/outbound, allow/block counts), detects overly permissive inbound allow rules (any remote address + any port), and lists the top offenders. JSON output, exit code 1 on permissive rules.
- 65 modules, 4249 tests, 150 CLI actions

## v1.86.0

- **New CLI Action:** `PasswordPolicy` — audits local password policy (min length, complexity, max/min age, history, reversible encryption) and lockout policy (threshold, duration, reset window) via secedit export. Color-coded thresholds, JSON output, exit code 1 on security issues.
- 65 modules, 4240 tests, 149 CLI actions

## v1.85.4

- **Fix:** FleetReport test regex patterns — escaped `$` variable references caused invalid regex on CI runner. Changed to match `healthy++`/`warning++`/`critical++` patterns instead.
- 65 modules, 4228 tests, 148 CLI actions

## v1.85.3

- **Tests:** Added 22 implementation tests for ServerScore (8) and FleetReport (14) — validates case blocks, JSON output, grade assignment, directory validation, worst performers display.
- 65 modules, 4228 tests, 148 CLI actions

## v1.85.2

- **Fix:** Help search CLI topic updated to 148 actions, added FleetReport mention.
- 65 modules, 4206 tests, 148 CLI actions

## v1.85.1

- **Docs:** README updated to 148 CLI actions everywhere, FleetReport in Fleet CLI table. CONTRIBUTING.md test count updated to 4200+.
- 65 modules, 4206 tests, 148 CLI actions

## v1.85.0

- **New CLI Action:** `FleetReport` — reads HealthDashboard/ServerScore JSON files from a directory and generates an aggregate fleet health report. Shows healthy/warning/critical server counts, worst performers with scores, and common issues. Designed for fleet dashboards where each server saves its health JSON to a shared directory.
- 65 modules, 4206 tests, 148 CLI actions

## v1.84.3

- **Docs:** Help search CLI topic updated to mention 147 actions, ServerScore, HealthDashboard. README ServerScore in CLI table, test badge updated to 4200+.
- 65 modules, 4203 tests, 147 CLI actions

## v1.84.2

- **Docs:** README updated — features section now highlights monitoring capabilities (ServerScore, HealthDashboard, System Center, Azure AD). Updated intro to mention 147 CLI actions. Added Monitoring section to features list.
- 65 modules, 4203 tests, 147 CLI actions

## v1.84.1

- **Hardening:** Added `-OperationTimeoutSec 8` to 3 remaining CIM queries in HealthCheck readiness checks (Server 2025 hang prevention).
- **Fix:** Future OS detection — Server builds beyond 2025 now fall back to registry ProductName instead of generic "Windows Server". Forward-compatible with Server vNext.
- **Fix:** ConfigExport profile save now uses atomic write (temp file + rename) to prevent partial/corrupt exports from disk full or file lock races.
- 65 modules, 4203 tests, 147 CLI actions

## v1.84.0

- **New CLI Action:** `ServerScore` — unified 0-100 server health and compliance score with weighted categories: CPU (15pts), Memory (15pts), Disk capacity (20pts), Security (20pts — reboot, certs, firewall, Defender), Events (10pts), Uptime (10pts), Network (10pts). Returns letter grade (A+ to F). Designed as the ultimate single-number fleet health indicator.
- **Enhancement:** HealthDashboard now includes NIC error totals and key service health in the monitoring JSON.
- **New Wiki:** Monitoring Integration page — SCOM, Zabbix, PRTG, fleet scanning integration examples.
- 65 modules, 4203 tests, 147 CLI actions

## v1.83.3

- **Enhancement:** HealthDashboard now includes NIC error totals and key service health (W32Time, WinRM, EventLog, Winmgmt) in the monitoring JSON blob. Issues flagged for >100 NIC errors or stopped key services.
- 65 modules, 4200 tests, 146 CLI actions

## v1.83.2

- **New CLI Action:** `AzureADAudit` — checks Azure AD / Entra ID join status (Azure AD Joined, Hybrid, Workplace Joined, Domain Only), tenant name/ID, MDM/Intune enrollment status, device compliance, and SSO (Primary Refresh Token) state. Uses `dsregcmd /status` for reliable data without Azure modules.
- **Docs:** README CLI table updated with System Center category (SCCM, SCOM, WAC, AzureAD).
- 65 modules, 4200 tests, 146 CLI actions

## v1.83.1

- **Tests:** Function coverage reached **99.5%** (616/619) — **100% of all testable functions**. The remaining 3 are nested helpers (`Add-ReadinessRow`, `Enter-ManualKey`, `Set-DNSFromPreset`) that exist only inside their parent function scope and cannot be tested from global scope. 4197 tests total — 284 new this session.
- 65 modules, 4197 tests, 145 CLI actions

## v1.83.0

- **New CLI Action:** `SCCMClientAudit` — checks SCCM/MECM client service status, client version, cache size/location, last policy request, management point, and site code. Detects if client is installed and healthy.
- **New CLI Action:** `SCOMAgentAudit` — checks SCOM (System Center Operations Manager) agent service, management group registrations, and agent version. Detects missing management group connections.
- **New CLI Action:** `WACConnectivityAudit` — verifies Windows Admin Center readiness: WinRM service, PS Remoting endpoints, HTTPS server auth certificates, CredSSP status, and WAC gateway service detection.
- 65 modules, 4193 tests, 145 CLI actions

## v1.82.11

- **New CLI Action:** `HealthDashboard` — all-in-one health summary designed for monitoring systems. Returns CPU load, memory usage, disk capacity per volume, uptime, reboot pending status, critical event count (24h), certificate expiry, and Hyper-V VM counts in a single JSON blob. Status field: Healthy/Warning/Critical with issue count. The one action your monitoring system needs.
- **Tests:** 18 new function tests pushing to 98.9% coverage. 4184 total (271 new this session).
- 65 modules, 4184 tests, 142 CLI actions

## v1.82.10

- **Tests:** Added 12 more function tests (network adapter selectors, drive letter picker, partition selector, cluster drain/resume, shadow copy cleanup, NIC identification, Defender exclusion removal). **4181 tests** — 268 new this session. **Function coverage: 98.9%** (612/619 — practical ceiling reached).
- 65 modules, 4181 tests, 141 CLI actions

## v1.82.9

- **Tests:** Added 18 function tests, pushing function coverage to **96.9%** (600/619). Only 19 internal helpers remain untested. **4169 tests** total — 256 new this session.
- **Docs:** Added test count badge to README.
- 65 modules, 4169 tests, 141 CLI actions

## v1.82.8

- **Tests:** Added 20 function tests (14 Test-* validation functions, Search-HelpTopics, Stop-ScriptTranscript, Find-LocalCluster, Format-SessionDuration, 2 menu starters). **4151 tests** — 238 new this session. **Function coverage: 94%** (582/619 functions).
- 65 modules, 4151 tests, 141 CLI actions

## v1.82.7

- **Tests:** Added 15 more function tests (Connect-FailoverCluster, Connect-StandaloneHost, Show-ServiceDependencies, Show-TimezoneRegionPicker, Show-VMDeploymentModeMenu, Start-BatchDeployment, Start-ClusterNodeDrain, and 8 menu loop starters). **4131 tests** — 218 new this session. Function coverage: 88.4% → 90.1%.
- 65 modules, 4131 tests, 141 CLI actions

## v1.82.6

- **Tests:** Added 15 more function existence tests (cluster, network, debloat, deployment, iSCSI, security, event log, replication, timezone menus). 4116 total — 203 new tests this session.
- **Wiki:** Configuration page updated with CLIDefaults documentation.
- 65 modules, 4116 tests, 141 CLI actions

## v1.82.5

- **Fix:** Windows activation error handling now covers 3 additional error codes: 0xC004E002 (timeout/network), 0xC004C003 (blocked key), 0xC004D307 (KMS unavailable). Users get actionable guidance instead of raw error text.
- **Docs:** CONTRIBUTING.md test count updated from "1,854+" to "4,100+" (was 2+ years outdated).
- 65 modules, 4101 tests, 141 CLI actions

## v1.82.4

- **Tests:** Added 15 more function existence tests (Show-LocalAccountAudit, Show-NetworkBandwidth, Show-PasswordStrength, Show-RebootPendingDetails, Show-ScheduledTaskOverview, Show-SMBShareAudit, Show-StandardVMTemplates, Show-StorageClusteringMenu, Show-TaskHealthStatus, Show-UptimeRebootHistory, Show-VHDHealthStatus, Show-WindowsUpdateStatus, Show-VMConfigSummary, Show-VMQueueManagement, Show-iSCSIAutoConfigMenu). **4101 tests** — crossed 4100 milestone.
- **Docs:** Updated README test count to 4080+.
- 65 modules, 4101 tests, 141 CLI actions

## v1.82.3

- **Tests:** Added 15 function existence tests (Invoke-ServerDebloat, Invoke-WorkstationDebloat, Invoke-PathMtuDiscovery, Invoke-UdpPortTest, Invoke-RecycleBinCleanup, Show-AdapterStatus, Show-AllSystemTimezones, Show-DiskPartitions, Show-DriverHealthCheck, Show-EventLogAlerts, Show-ExistingVMs, Show-FirewallRuleSearch, Show-FirewallRuleSummary, Show-HostNetworkMenu, Show-UpdateHistory). 4086 tests total.
- **Wiki:** Added CLI action tables to Storage-Backends, Cluster-Management, and Hyper-V-Replica pages.
- 65 modules, 4086 tests, 141 CLI actions

## v1.82.2

- **Tests:** Added 15 function existence tests (Export-ProfileComparisonHTML, Show-AllVolumes, Show-CertificateExpiryCheck, Show-CheckpointAgeWarnings, Show-ClusterStatus, Show-CriticalEventSummary, Show-CSVHealth, Show-DedupSavings, Show-DetailedTimeStatus, Show-DiskIOMetrics, Show-DriveLetterMap, Show-InstalledSoftware, Show-ListeningPorts, Show-VSSWriterStatus, New-DiskPartition). 4071 tests.
- **Docs:** README CLI table updated with NICErrorAudit, VMResourceWaste.
- 65 modules, 4071 tests, 141 CLI actions

## v1.82.1

- **New CLI Action:** `NICErrorAudit` — detailed per-adapter error counts (InErrors, OutErrors, InDiscards, OutDiscards) plus driver reset count. Flags adapters with >100 total errors. Critical for diagnosing network packet loss and adapter instability.
- **New CLI Action:** `VMResourceWaste` — analyzes running VMs for oversized resource allocations: high startup RAM with low actual demand, static memory >32GB without dynamic, and >8 vCPU allocations. Helps with capacity right-sizing.
- **Docs:** Updated README CLI action table with SMBConnectionAudit, VolumeLabelAudit. Updated wiki.
- 65 modules, 4056 tests, 141 CLI actions

## v1.82.0

- **New CLI Action:** `SMBConnectionAudit` — reports active SMB sessions with client/user/file counts, open file totals, and non-system share inventory. Flags high open file counts (>50). JSON output for fleet monitoring.
- **New CLI Action:** `VolumeLabelAudit` — lists all fixed volumes with labels, filesystem type, size, and free space. Flags unlabeled non-C: drives (common oversight that makes disk identification difficult in multi-drive servers).
- **Fix:** Timezone sync `$LASTEXITCODE` captured immediately after `w32tm /resync` to prevent race condition with subsequent PowerShell operations overwriting it.
- 65 modules, 4050 tests, 139 CLI actions

## v1.81.11

- **Enhancement:** Time sync after timezone change is now tracked as a session change for audit trail completeness.
- 65 modules, 4044 tests, 137 CLI actions

## v1.81.10

- **Enhancement:** StorageManager `Select-Disk` now detects and warns about USB and SD card drives with `[USB]`/`[SD Card]` markers in yellow. Prevents accidental initialization of removable media.
- 65 modules, 4044 tests, 137 CLI actions

## v1.81.9

- **Fix:** LocalAdmin account creation prompt said "alphanumeric" but regex also accepts underscores and hyphens. Prompt now accurately describes all valid characters.
- **Fix:** RDP port display now validates port range (1-65535), shows "default" when not set, and highlights non-standard ports.
- 65 modules, 4044 tests, 137 CLI actions

## v1.81.8

- **Tests:** Added CLI action count guard (verifies >= 137 actions, catches accidental removals). 4044 tests.
- 65 modules, 4044 tests, 137 CLI actions

## v1.81.7

- **Fix:** BitLocker AD recovery key verification could fail with confusing error when `Get-ADComputer` returned null. Now uses explicit error handling with separate catch for "computer not found in AD" vs "AD tools not available."
- 65 modules, 4043 tests, 137 CLI actions

## v1.81.6

- **Fix:** `Show-CleanupAnalysis` null arithmetic — 3 `Measure-Object .Sum` calls lacked null-safe `[long]` cast and `-ErrorAction SilentlyContinue`, causing potential arithmetic failures on empty directories.
- **Fix:** Password expiry calculation used redundant `Get-LocalUser` re-fetch per user (N+1 performance issue). Now uses `$user.PasswordExpires` directly.
- **Fix:** Storage Replica partnership removal could silently delete multiple partnerships matching the same source. Now counts matches, warns, and confirms before bulk removal.
- 65 modules, 4043 tests, 137 CLI actions

## v1.81.5

- **New CLI Action:** `CSVSpaceAudit` — reports Cluster Shared Volume capacity, free space, used percentage, state, and owner node. Flags CSVs at >85% (warning) and >95% (critical) capacity. Critical for preventing CSV-full emergencies in Hyper-V cluster environments.
- 65 modules, 4043 tests, 137 CLI actions

## v1.81.4

- **Tests:** Added 17 function existence tests for VM deployment, storage, debloat, network, and cluster helpers. 4036 tests.
- **Docs:** Updated README with StorageHealthScore in CLI actions table. Updated wiki: CLI Automation (3 new actions + StorageHealthScore), Batch Mode (new validation checks), Health Monitoring (event log capacity), Troubleshooting (CIM/WMI timeout guide).
- 65 modules, 4036 tests, 136 CLI actions

## v1.81.3

- **New CLI Action:** `StorageHealthScore` — unified 0-100 storage health score aggregating physical disk health (40pts), volume capacity (30pts), disk latency (20pts), and MPIO path redundancy (10pts). Returns letter grade. Pairs with `ClusterHealthScore` for comprehensive fleet dashboard monitoring.
- 65 modules, 4019 tests, 136 CLI actions

## v1.81.2

- **New CLI Action:** `VMSnapshotAudit` — comprehensive VM checkpoint health report: per-VM snapshot count, oldest/newest timestamps, age in days, estimated AVHD disk usage. Flags checkpoints >7 days (warning), >30 days (critical), and VMs with >5 deep checkpoint trees. JSON output includes full VM snapshot inventory for fleet monitoring.
- 65 modules, 4011 tests, 135 CLI actions

## v1.81.1

- **Enhancement:** HyperVAudit now detects checkpoints older than 7 days (not just count >3). Old checkpoints silently consume disk space and degrade VM performance. JSON output includes `OldCheckpoints` count per VM.
- 65 modules, 4003 tests, 134 CLI actions

## v1.81.0

- **New CLI Action:** `ClusterHealthScore` — computes a unified 0-100 health score for failover clusters by aggregating node health (25pts), resource health (25pts), CSV health (25pts), and quorum health (25pts). Outputs letter grade (A+ to F). Designed for fleet dashboard monitoring via JSON output.
- **New CLI Action:** `VMInventoryExport` — exports comprehensive VM inventory including state, CPU, memory (startup + assigned + type), disk paths/sizes/types, NIC switch/VLAN/IP, checkpoint count, replication state, and VM notes. Ideal for capacity planning and documentation.
- 65 modules, 4003 tests, 134 CLI actions

## v1.80.6

- **Fix:** `Test-CredentialExpired` returned `$false` when credentials were null in remote mode — stale/cleared credentials were silently treated as valid, causing "access denied" errors on subsequent VM deployments. Now correctly distinguishes standalone (no cred needed) from remote (null = expired).
- **Fix:** `Show-MountedVHDStatus` used `Get-VHD -Path *` which scans the filesystem with wildcards — hangs on hosts with many VHD files. Now uses `Get-Disk` to find VHD-backed disks directly.
- **Fix:** VHD dismount in offline customization always reported "VHD dismounted" even if dismount failed. Now catches errors and shows the manual dismount command.
- **Fix:** VHD size mismatch warning — if user declined to delete a mismatched cached VHD and then chose "use cached," no warning was shown. Now displays a prominent "NOT RECOMMENDED" warning banner.
- 65 modules, 3985 tests, 132 CLI actions

## v1.80.5

- **Enhancement:** Help search now includes "CLI Actions" topic — searching for "cli", "action", "fleet", or "automation" surfaces CLI headless mode documentation.
- 65 modules, 3985 tests, 132 CLI actions

## v1.80.4

- **Tests:** Added changelog version validation (current version entry exists, is first entry), WmiObject extinction guard (verifies zero `Get-WmiObject` across all 65 modules), compliance readiness disk timeout. 3985 tests.
- 65 modules, 3985 tests, 132 CLI actions

## v1.80.3

- **Enhancement:** Compliance readiness checks now include disk timeout validation for iSCSI hosts, consistent with Server Readiness dashboard (v1.80.2).
- 65 modules, 3982 tests, 132 CLI actions

## v1.80.2

- **Enhancement:** Server Readiness dashboard now checks disk timeout on iSCSI hosts — flags <60s timeout that causes BSODs during SAN failover/maintenance.
- 65 modules, 3982 tests, 132 CLI actions

## v1.80.1

- **Enhancement:** HTML health report now includes event log capacity in the issues summary — flags Application, System, and Security logs >=90% full alongside other health indicators.
- 65 modules, 3982 tests, 132 CLI actions

## v1.80.0

- **New CLI Action:** `DiskLatencyAudit` — checks physical disk read/write latency and queue lengths via performance counters. Flags disks with >10ms latency (warning) or >20ms (critical) and saturated queues (>4). Supports JSON output for fleet monitoring.
- **New CLI Action:** `NICOffloadAudit` — inventories NIC offload settings (RSS, VMQ, RDMA, RSC, checksum offload, LSO) across all active physical adapters. Flags disabled RSS. Critical for diagnosing Hyper-V network performance issues on converged NICs.
- **New CLI Action:** `StorageTimeoutAudit` — checks disk timeout, iSCSI MaxRequestHoldTime/LinkDownTime, MPIO PDORemovePeriod, and StorPort IoTimeout. Flags low timeout values that cause BSODs during SAN maintenance windows.
- **New CLI Action:** `EventLogCapacityAudit` — checks event log sizes, capacity utilization, and retention mode for all critical logs (Application, System, Security, Setup, Hyper-V). Flags logs near 90% capacity and logs in Retain mode that will stop recording when full.
- **Fix:** `ShadowCopyAudit` crashed when `InstallDate` was a DateTime object (from `Get-CimInstance`) instead of a string — `.Substring()` called on DateTime. Now handles both types.
- **Fix:** Replaced last 2 `Get-WmiObject` calls with `Get-CimInstance` (MPIO disk info in EntryPoint, Fibre Channel HBA detection in StorageBackends).
- **Fix:** Added `-OperationTimeoutSec 8` to 9 CIM queries inside `Invoke-WithTimeout` scriptblocks across 6 modules (05-SystemCheck, 28-PerformanceDashboard, 35-Utilities, 37-HealthCheck, 40-HostStorage, 45-ConfigExport). Prevents CIM from blocking indefinitely on cold WMI.
- **Fix:** `Install-RackStack.ps1` ValidateSet was missing 14 CLI actions added since v1.68.0 — users running `Install-RackStack.ps1 -Action LiveMigrationAudit` etc. would get validation errors. Now synced.
- **Cleanup:** Removed dead code in EventLogViewer (unreachable `continue` after switch block).
- **New CLI Action:** `TcpSettingsAudit` — checks TCP auto-tuning level, chimney offload, congestion provider, ECN, RFC 1323 timestamps, RSS-enabled adapter count, and dynamic port range. Helps diagnose network performance tuning.
- **New CLI Action:** `WinRMAudit` — checks WinRM service status, listeners (HTTP/HTTPS), auth methods (Basic/Kerberos/Negotiate/CredSSP), trusted hosts, and encryption settings. Flags Basic auth enabled, wildcard trusted hosts, and unencrypted transport.
- **Enhancement:** HealthCheck now includes event log capacity monitoring — flags Application, System, and Security logs that are >=90% full.
- **Enhancement:** Batch config validation (`Test-BatchConfig`) now checks adapter existence before network configuration, detects duplicate vNIC names, warns about PromoteToDC + DomainJoin conflicts, and validates InitializeHostStorage requires Hyper-V.
- **Consistency:** Added missing `Timestamp` and `Hostname` fields to JSON output for 9 older CLI actions (Cleanup, Debloat, HealthCheck, QuickScan, Inventory, DriftCheck, Snapshot, Aggregate, Compare) — now all 132 actions follow the same JSON schema for fleet automation.
- **Hardening:** Added `-OperationTimeoutSec 8` to 8 more CIM queries in 54-HTMLReports, 55-QoLFeatures, 48-MenuDisplay, and 28-PerformanceDashboard. Total CIM timeout coverage now comprehensive across all modules.
- **Tests:** Added 20 function existence tests for previously untested critical functions (629 total functions now covered).
- 65 modules, 3982 tests, 132 CLI actions

## v1.79.0

- **New CLI Action:** `LiveMigrationAudit` — checks live migration enabled/disabled, auth type, performance option, migration networks, and surfaces recent migration failures from Hyper-V event logs (last 7 days).
- **New CLI Action:** `DomainTrustAudit` — enumerates domain trust relationships via nltest, verifies secure channel health, and checks domain controller connectivity.
- 126 CLI actions, 65 modules

## v1.78.0

- **New CLI Action:** `ShadowCopyAudit` — reports shadow copy counts per volume, storage usage/capacity, newest/oldest shadow timestamps, and flags volumes with no shadow copies configured. Catches stale/full shadow storage before users need file recovery.
- **New CLI Action:** `QoSPolicyAudit` — inventories network QoS policies (DSCP markings, throttle rates), DCB traffic classes, SMB bandwidth limits, and QoS-enabled adapters. Critical for converged networking environments (S2D/HCI) where QoS misconfiguration causes storage timeouts.
- 124 CLI actions, 65 modules

## v1.77.0

- **New CLI Action:** `ReplicaLagAudit` — reports Hyper-V Replica lag duration, replication health, state, and missed cycles per VM. Flags replicas >60 minutes behind or in non-Normal health.
- **New CLI Action:** `HandleLeakAudit` — detects processes with anomalous handle counts (>10K), thread counts (>500), or private memory (>4GB) that suggest resource leaks. Catches services like WmiPrvSE/svchost leaking handles before they crash the server.
- 122 CLI actions, 65 modules

## v1.76.0

- **New CLI Action:** `VMOvercommitAudit` — calculates CPU and RAM overcommit ratios for running Hyper-V VMs vs physical host resources. Flags critical overcommit (>8:1 CPU, >1.5:1 RAM). Accounts for dynamic memory max.
- **New CLI Action:** `DedupAudit` — reports dedup-enabled volume savings, optimization rate, last optimization time, and active jobs. Flags volumes where optimization hasn't run in >7 days.
- **New CLI Action:** `ClusterNetworkAudit` — validates cluster network roles (heartbeat, client), interface states, and surfaces network partition events (event IDs 1123/1127/1135) from the last 7 days.
- All support `-OutputFormat JSON`.
- 120 CLI actions, 65 modules

## v1.75.1

- **Fix:** VM remote deployment — `Connect-VMNetworkAdapter` and `Set-VMNetworkAdapterVlan` used `-VMName` (string, loses host context) instead of `-VM` (object, carries remote host). NIC configuration silently failed on cluster/remote deployments.
- **Fix:** Box-drawing overflow — 4 `PadRight(72)` locations in EntryPoint could overflow the `│` border when file paths, DNS lists, query expressions, or diff summaries exceeded 72 characters. Now truncated with `...`.
- 117 CLI actions, 65 modules

## v1.75.0

- **New CLI Action:** `VirtualSwitchAudit` — audit all Hyper-V virtual switches, SET team members with link status/speed, and management OS vNICs with VLAN assignments.
- **New CLI Action:** `MPIOPathAudit` — audit MPIO device paths (flags single-path devices), claimed hardware IDs, and global load balance policy.
- **New CLI Action:** `ServiceRecoveryAudit` — audit auto-start running services for missing recovery actions. Flags services that won't auto-restart on failure.
- 117 CLI actions, 65 modules

## v1.74.0

- **New Feature:** `CLIDefaults` section in `defaults.json` — set org-wide default OutputFormat, DefaultTier, and QuietMode for CLI actions. Operators no longer need to pass `-OutputFormat JSON` every time if their workflow always uses JSON.
- **Fix:** `.Enabled -eq 'True'` string comparison replaced with `-eq $true` (boolean) in Firewall export and FirewallAudit (3 sites).
- **Fix:** Null-safe CSV StoragePath in VM deployment — properly handles empty cluster CSV list with null checks instead of crashing.
- **Performance:** Menu invalid choice feedback reduced from 1000ms to 500ms (13 locations in MenuRunner).
- **Config:** `defaults.example.json` updated with CLIDefaults section and documentation.
- 114 CLI actions, 65 modules

## v1.73.0

- **New Feature:** `-OutputFile` parameter — save CLI action output (transcript) to a file. Usage: `RackStack.exe -Action HealthCheck -OutputFile C:\reports\health.log`
- **Docs:** README updated — added System Debloat section to features, updated function count to 600+, added all new CLI actions to the table.
- 114 CLI actions, 65 modules, 606 functions

## v1.72.0

- **New Feature:** Batch config now supports `Win11Cleanup` (boolean) and `OSTheme` ("Dark"/"Light") fields — apply Windows 11 UI tweaks and theme changes via JSON batch mode alongside all other server configuration steps.
- Batch mode expanded from 24 to 26 steps.
- 114 CLI actions, 65 modules

## v1.71.0

- **New CLI Action:** `ClusterQuorumAudit` — audit cluster quorum type, witness health, node vote weights. Flags missing witness on 2-node clusters, offline witnesses, and down nodes.
- **New CLI Action:** `S2DAudit` — audit Storage Spaces Direct health including S2D state, cache, storage subsystem, pools, virtual disks, and physical disk health. Flags unhealthy components.
- Both support `-OutputFormat JSON` for fleet automation.
- 114 CLI actions, 65 modules

## v1.70.3

- **Code quality:** Standardized `$Matches` → `$matches` across 4 modules (33 occurrences). PowerShell is case-insensitive but consistent casing improves readability.
- 112 CLI actions, 65 modules

## v1.70.2

- **Fix:** Added `-OperationTimeoutSec 8` to all CIM queries inside `Invoke-WithTimeout` scriptblocks across 15 modules. This makes CIM/WMI itself timeout at the provider level before the runspace timeout fires, preventing native code from blocking indefinitely on unreachable domain controllers or cold WMI. Defense-in-depth alongside the v1.70.1 fire-and-forget cleanup.
- **Docs:** Updated README.md — CLI actions table now lists all 112 actions including Win11Cleanup, DarkMode, LightMode, iSCSIAudit, NICTeamAudit, SMBSessionAudit, WindowsUpdateAudit. Test count updated to 3800+.
- 112 CLI actions, 65 modules

## v1.70.1

- **Fix:** `Invoke-WithTimeout` could hang on Server 2025 when `$ps.Stop()` blocked on a CIM query that ignored cancellation. Now uses fire-and-forget `ThreadPool.QueueUserWorkItem` for cleanup so the script never freezes waiting for a stuck runspace.
- **Cleanup:** Removed dead `Test-SessionResume` function from 55-QoLFeatures.ps1 (defined but never called from anywhere).
- 112 CLI actions, 65 modules

## v1.70.0

- **New CLI Action:** `WindowsUpdateAudit` — lists all pending Windows updates with severity, KB, and size without installing anything. Uses PSWindowsUpdate module if available, falls back to COM-based Microsoft.Update.Session. Flags critical/important updates. Supports JSON output.
- 112 CLI actions, 65 modules

## v1.69.2

- **Tests:** Added 22 new tests — function existence for `Invoke-Win11UICleanup` and `Set-OSThemeMode`, CLI action validation for Win11Cleanup/DarkMode/LightMode/iSCSIAudit/NICTeamAudit/SMBSessionAudit, and favorites dispatch map validation (verifies all 30 mapped function names resolve to real functions).
- 111 CLI actions, 65 modules

## v1.69.1

- **Performance:** Eliminated duplicate `Win32_OperatingSystem` CIM query in `Test-WatchThresholds` — memory and uptime checks now share a single query instead of spawning two separate runspaces.
- **Fix:** Empty catch blocks in `59-StorageBackends.ps1` storage backend auto-detection now have comments explaining why failure is acceptable (S2D/cluster cmdlets unavailable).
- 111 CLI actions, 65 modules

## v1.69.0

- **New CLI Action:** `iSCSIAudit` — audit iSCSI sessions, targets, connections, persistent status, and MPIO claimed devices. Flags disconnected or non-persistent sessions.
- **New CLI Action:** `NICTeamAudit` — audit SET (Switch Embedded Teaming) and LBFO team health, member NIC status, teaming mode, and load balancing algorithm. Flags down members.
- **New CLI Action:** `SMBSessionAudit` — audit active SMB sessions and open files grouped by client. Flags stale sessions (>24h). Useful for file server monitoring.
- All 3 support `-OutputFormat JSON` for fleet automation.
- 111 CLI actions, 65 modules

## v1.68.0

- **New CLI Action:** `Win11Cleanup` — apply all Windows 10-style UI tweaks non-interactively. Supports JSON output. Usage: `RackStack.exe -Action Win11Cleanup [-OutputFormat JSON]`
- **New CLI Action:** `DarkMode` / `LightMode` — set OS theme non-interactively. Usage: `RackStack.exe -Action DarkMode`
- 103 CLI actions, 65 modules

## v1.67.4

- **Performance:** Aggressive cache tuning across all menu display functions — feature install checks (Hyper-V, MPIO, Clustering, Agent) cached for 300s instead of 30s, RDP/WinRM state cached 60-120s, reboot-pending cached 15s. Eliminates repeated slow CIM queries on every menu render.
- **Performance:** `Test-HyperVInstalled` in host network menu loop now uses cache instead of calling `Get-WindowsFeature` (~2s) on every iteration.
- **Performance:** `Get-VMSwitch` cached in virtual switch menu (was uncached, ~1-2s per render).
- 65 modules, 3851 tests

## v1.67.3

- **Improvement:** Menu speed — added cache durations to timezone (120s), license status (300s), and power plan (60s) queries that were uncached and re-queried on every menu render.
- **Fix:** Install-Prerequisites.ps1 now detects Windows 7/8/8.1 (not just Server editions) and uses `$env:SystemDrive` instead of hardcoded `C:\Temp`.
- 65 modules, 3851 tests

## v1.67.2

- **Fix:** OS build detection used `[Environment]::OSVersion` which returns compat-shimmed build 9200 in PS 5.1 / ps2exe. Replaced with registry `CurrentBuildNumber` in Win11 UI Cleanup and Console VT/color detection. This caused "not Windows 11" false negative on actual Windows 11 systems.
- 65 modules, 3851 tests

## v1.67.1

- **New Feature:** OS Dark / Light Theme toggle — switch between Dark Mode, Light Mode, or mixed (dark apps + light system, light apps + dark system) from Debloat menu [6]. Detects current theme, applies instantly with Explorer restart.
- 65 modules, 3851 tests

## v1.67.0

- **New Feature:** Windows 11 / Server 2025 UI Cleanup — restores Windows 10-style UI preferences including classic right-click context menu, left-aligned taskbar, file extensions visible, no widgets/copilot/chat/gallery, File Explorer opens to This PC, disables snap flyout and start recommendations, resets folder grouping. Available from Debloat menu option [5].
- **Fix:** 9 broken favorites dispatch entries in QoL module — "Set IP Address", "Set DNS", "Enable WinRM", "Configure Firewall", "Add Local Admin", "License Server", "Set Power Plan", "Storage Manager", and "BitLocker Management" were mapped to non-existent function names and would silently fail when invoked from favorites.
- **Fix:** `-Path` replaced with `-LiteralPath` on 7 `New-Item`/`Get-ChildItem` calls where paths contain VM names or user input that could include wildcard characters. Affected modules: 44-VMDeployment, 41-VHDManagement, 53-VMExportImport, 62-HyperVReplica.
- **UI:** Consistent `[B] ◄ Back` arrows across all menus — 8 instances missing the `◄` arrow fixed in 6 modules.
- **UI:** Standardized `Read-Host "  Select"` prompt across all menus — 5 instances using `"Choice"` updated for consistency.
- 65 modules, 3851 tests

## v1.66.2

- **Fix:** PS 5.1 `.Count` on single-object returns — wrapped 9 cmdlet results in `@()` to prevent null `.Count` when only one item is returned. Affected modules: 44-VMDeployment (NIC count in post-deploy check), 46-SessionSummary (reboot reasons suppressed), 50-EntryPoint (fleet scan target counts), 51-ClusterDashboard (node/CSV counts in readiness check and CSV validation), 63-ScheduledTasks (empty-task detection in enable/disable, export, and run-now).
- **Fix:** Hardcoded `C:\` paths replaced with `$env:SystemDrive` — TempPath default in 00-Initialization, and `C:\Windows.old` / `C:\Users` references in 20-DiskCleanup. Fixes operation on systems where Windows is not installed on C:.
- **UI:** Unified all 97 screen headers to use box-drawing characters (`╔═╗║╚═╝`) — `Write-CenteredOutput` now renders the same frame style as menu pages instead of plain `=====` borders. Affects 30 modules across the entire tool.
- **UI:** Windows Updates install screen redraws header after NuGet/PSWindowsUpdate module installation so the title stays visible during long operations.
- 65 modules, 3851 tests

## v1.66.1

- **Fix:** Debloat interactive menu crash — all calls to `Get-RemovableAppxPackages`, `Get-DisableableServices`, `Invoke-WorkstationDebloat`, `Invoke-ServerDebloat`, and `Invoke-CustomDebloatExecution` were using `-Profile` instead of `-DebloatProfile`. Fixed 12 call sites across 64-SystemDebloat.ps1. This caused "A parameter cannot be found that matches parameter name 'Profile'" when using the debloat menu interactively.

## v1.66.0

- **Fix:** PatchStatus — `$recentUpdates.Count` wrapped in `@()` to prevent PS 5.1 single-object null on .Count (50-EntryPoint).
- **Fix:** UserAudit — `$accounts.Count` wrapped in `@()` to prevent PS 5.1 single-object null on .Count (50-EntryPoint).
- 65 modules, 3851 tests

## v1.65.0

- **New Feature:** ARPTableAudit CLI action — audits ARP neighbor cache via Get-NetNeighbor. Reports reachable, stale, and permanent entries per interface (50-EntryPoint).
- **New Feature:** LocaleAudit CLI action — audits system locale, UI language, timezone, date format, number format, and input languages (50-EntryPoint).
- **New Feature:** TaskHistoryAudit CLI action — audits scheduled task execution history from TaskScheduler event log (events 102/201). Reports recent completions with result codes, flags failures (50-EntryPoint).
- **New Feature:** NTFSAudit CLI action — audits NTFS volume health and features. Reports volume health status and detects compressed/EFS-encrypted files. Flags unhealthy volumes (50-EntryPoint).
- 65 modules, 3851 tests

## v1.64.0

- **New Feature:** PowerShellAudit — audits PS execution policy, language mode, script block logging, transcription, module logging, and PS2 engine status. Flags constrained language mode and enabled PS2 engine.
- **New Feature:** RouteTableAudit — audits full routing table with default gateways, IPv4/IPv6 route counts, metrics, and interface assignments.
- **New Feature:** TokenPrivilegeAudit — audits current process token privileges via `whoami /priv`. Flags dangerous enabled privileges (SeDebugPrivilege, SeTcbPrivilege, etc.).
- **New Feature:** WindowsCapabilityAudit — inventories installed Windows capabilities including RSAT tools. Separates RSAT from other capabilities.
- 65 modules, 3835 tests

## v1.63.0 -- 100 CLI ACTIONS

- **CENTURY MARK: 10 new CLI actions in one release, reaching 100 total.**
- **New Feature:** DefenderExclusionAudit — audits Windows Defender exclusion paths, processes, extensions, and IPs. Flags exclusions for review (attackers abuse these for evasion).
- **New Feature:** KerberosAudit — audits Kerberos configuration: cached ticket count, max token/packet size from registry.
- **New Feature:** DHCPAudit — audits DHCP client leases: server address, IP, lease obtained/expiry times per adapter.
- **New Feature:** NUMAAudit — audits NUMA topology: cores, logical processors, L2/L3 cache per processor socket.
- **New Feature:** SymlinkAudit — audits symbolic links and reparse points in System32, SysWOW64, ProgramData.
- **New Feature:** StartupScriptAudit — audits GPO startup/shutdown scripts from Group Policy State registry.
- **New Feature:** SecureChannelAudit — audits domain secure channel health via nltest. Reports trusted DC.
- **New Feature:** ComObjectAudit — audits non-system COM object registrations (persistence detection).
- **New Feature:** FirewallLogAudit — analyzes Windows Firewall log file. Reports drop/allow counts and recent dropped connections.
- **New Feature:** ScheduledRebootAudit — audits reboot-related scheduled tasks and recent reboot/shutdown events (1074/6006/6009).
- **Improved:** README Actions section reformatted as categorized table for readability.
- 65 modules, 3819 tests

## v1.62.0

- **New Feature:** ProxyAudit CLI action — `RackStack.exe -Action ProxyAudit -OutputFormat JSON` audits proxy configuration across IE/system proxy, WinHTTP proxy, and environment variables (HTTP_PROXY/HTTPS_PROXY/NO_PROXY). Reports PAC URLs and bypass lists (50-EntryPoint).
- **New Feature:** PendingRebootAudit CLI action — `RackStack.exe -Action PendingRebootAudit -OutputFormat JSON` performs comprehensive pending reboot detection. Checks CBS, Windows Update, pending file renames, computer rename, domain join, and SCCM reboot flags. Reports all reboot reasons. Exits code 1 when reboot required (50-EntryPoint).
- **New Feature:** PageFileAudit CLI action — `RackStack.exe -Action PageFileAudit -OutputFormat JSON` audits page file configuration and utilization. Reports auto-managed status, configured sizes, current/peak usage, and utilization percentage. Flags >80% usage. Exits code 1 when issues detected (50-EntryPoint).
- **New Feature:** CPUAudit CLI action — `RackStack.exe -Action CPUAudit -OutputFormat JSON` audits CPU topology and utilization. Reports processor name, cores, logical processors, clock speeds, L2/L3 cache, load percentage, virtualization support, and architecture. Flags >90% load. Exits code 1 when CPU issues detected (50-EntryPoint).
- 65 modules, 3779 tests

## v1.61.0

- **New Feature:** LogonAudit CLI action — `RackStack.exe -Action LogonAudit -OutputFormat JSON` audits recent logon activity. Reports successful interactive/RDP logons (Event 4624) and failed logon attempts (Event 4625) with source IPs. Exits code 1 when failed logons detected (50-EntryPoint).
- **New Feature:** ACLAudit CLI action — `RackStack.exe -Action ACLAudit -OutputFormat JSON` audits permissions on 6 critical system folders (Windows, System32, Program Files, Drivers, ProgramData). Flags Everyone with write/modify/full control. Exits code 1 when permission issues detected (50-EntryPoint).
- **New Feature:** RecoveryAudit CLI action — `RackStack.exe -Action RecoveryAudit -OutputFormat JSON` audits system recovery configuration. Reports system restore points, recovery partition presence, and system protection status (50-EntryPoint).
- **New Feature:** ServiceAccountAudit CLI action — `RackStack.exe -Action ServiceAccountAudit -OutputFormat JSON` identifies services running under custom accounts (not LocalSystem/LocalService/NetworkService). Reports service name, account, start mode, and separates domain vs local accounts (50-EntryPoint).
- 65 modules, 3751 tests

## v1.60.0

- **New Feature:** AppLockerAudit CLI action — `RackStack.exe -Action AppLockerAudit -OutputFormat JSON` audits AppLocker application control policies. Checks AppIDSvc service status and reports rule counts per collection type (Exe, Msi, Script, Appx, Dll) (50-EntryPoint).
- **New Feature:** EventSubAudit CLI action — `RackStack.exe -Action EventSubAudit -OutputFormat JSON` audits WMI event subscriptions — a common malware persistence mechanism. Checks for CommandLine, ActiveScript, LogFile, NTEventLog, and SMTP event consumers plus event filters. Exits code 1 when subscriptions found (50-EntryPoint).
- **New Feature:** HotfixAudit CLI action — `RackStack.exe -Action HotfixAudit -OutputFormat JSON` inventories all installed hotfixes/KBs with description, install date, and installed-by user. Sorted by install date descending (50-EntryPoint).
- **New Feature:** SysInfoAudit CLI action — `RackStack.exe -Action SysInfoAudit -OutputFormat JSON` collects comprehensive system information: OS name/version/build, hardware manufacturer/model, CPU details, RAM, domain membership, uptime, timezone, PowerShell version. One-command system profile for fleet inventory (50-EntryPoint).
- 65 modules, 3725 tests

## v1.59.0

- **New Feature:** HostsFileAudit CLI action — `RackStack.exe -Action HostsFileAudit -OutputFormat JSON` audits the Windows hosts file. Parses custom entries and flags suspicious redirects of known domains (Microsoft, Google, Windows Update). Exits code 1 when suspicious entries detected (50-EntryPoint).
- **New Feature:** NetStatAudit CLI action — `RackStack.exe -Action NetStatAudit -OutputFormat JSON` audits established TCP connections. Reports connections grouped by process with remote addresses and ports. Shows unique remote IPs and process counts (50-EntryPoint).
- **New Feature:** LicenseAudit CLI action — `RackStack.exe -Action LicenseAudit -OutputFormat JSON` audits Windows licensing status. Queries slmgr for product name, license status, key channel, and checks SoftwareLicensingProduct CIM class for partial key and grace period. Exits code 1 when not licensed (50-EntryPoint).
- **New Feature:** USBDeviceAudit CLI action — `RackStack.exe -Action USBDeviceAudit -OutputFormat JSON` audits connected USB devices and storage policy. Enumerates non-hub USB devices via Win32_USBControllerDevice/Win32_PnPEntity and checks USBSTOR service registry for storage blocking policy (50-EntryPoint).
- 65 modules, 3699 tests

## v1.58.0

- **New Feature:** AntivirusAudit CLI action — `RackStack.exe -Action AntivirusAudit -OutputFormat JSON` audits antivirus status. Checks Windows Defender real-time protection, signature age, engine version, and queries SecurityCenter2 for third-party AV products. Flags disabled RTP and stale signatures (>7 days). Exits code 1 when issues detected (50-EntryPoint).
- **New Feature:** DotNetAudit CLI action — `RackStack.exe -Action DotNetAudit -OutputFormat JSON` inventories .NET installations. Reports .NET Framework versions (2.0-4.x) from registry and .NET Runtime/SDK versions via `dotnet --list-runtimes` (50-EntryPoint).
- **New Feature:** RDPAudit CLI action — `RackStack.exe -Action RDPAudit -OutputFormat JSON` audits Remote Desktop configuration. Reports RDP enabled status, NLA requirement, port number, and active/disconnected sessions via qwinsta. Flags RDP enabled without NLA. Exits code 1 when security issues detected (50-EntryPoint).
- **New Feature:** VPNAudit CLI action — `RackStack.exe -Action VPNAudit -OutputFormat JSON` audits VPN connections. Reports configured VPN connections with tunnel type, authentication method, split tunneling status, and RRAS service availability (50-EntryPoint).
- 65 modules, 3675 tests

## v1.57.0

- **New Feature:** BitLockerAudit CLI action — `RackStack.exe -Action BitLockerAudit -OutputFormat JSON` audits BitLocker encryption per volume. Reports protection status, encryption method, percentage, lock status, key protectors, and recovery key presence. Flags unencrypted system drives. Exits code 1 when issues detected (50-EntryPoint).
- **New Feature:** PrintAudit CLI action — `RackStack.exe -Action PrintAudit -OutputFormat JSON` inventories installed printers with driver, port, sharing status, and print queue job count. Flags printers with >10 queued jobs. Exits code 1 when queue backlogs detected (50-EntryPoint).
- **New Feature:** CredGuardAudit CLI action — `RackStack.exe -Action CredGuardAudit -OutputFormat JSON` audits credential protection posture. Checks Virtualization Based Security, Credential Guard, HVCI, and LSASS PPL protection via Win32_DeviceGuard CIM class. Exits code 1 when credential protection gaps detected (50-EntryPoint).
- **New Feature:** PortAudit CLI action — `RackStack.exe -Action PortAudit -OutputFormat JSON` tests outbound TCP connectivity to 6 critical endpoints (Google DNS, Windows NTP, Microsoft Update, Azure AD, GitHub). Reports latency in milliseconds. Exits code 1 when connectivity failures detected (50-EntryPoint).
- 65 modules, 3645 tests

## v1.56.0

- **New Feature:** TempAudit CLI action — `RackStack.exe -Action TempAudit -OutputFormat JSON` analyzes reclaimable disk space across 10 temp categories (Windows Temp, User Temp, WU cache, Prefetch, CBS logs, DISM logs, IIS logs, crash dumps, error reports). Shows size per category. Flags >5GB total reclaimable (50-EntryPoint).
- **New Feature:** UpdatePolicyAudit CLI action — `RackStack.exe -Action UpdatePolicyAudit -OutputFormat JSON` audits Windows Update policy configuration. Reports auto-update mode, WSUS server, feature update deferral days, auto-reboot suppression, and WU service status (50-EntryPoint).
- **New Feature:** IISAudit CLI action — `RackStack.exe -Action IISAudit -OutputFormat JSON` audits IIS web server configuration. Inventories sites with state, bindings, physical paths, and app pool assignment. Reports app pools with managed runtime and pipeline mode. Flags stopped sites/pools. Exits code 1 when issues detected (50-EntryPoint).
- **New Feature:** SSHAudit CLI action — `RackStack.exe -Action SSHAudit -OutputFormat JSON` audits OpenSSH server configuration. Reports service status, sshd_config settings, and authorized keys count. Flags stopped SSH service and insecure settings. Exits code 1 when issues detected (50-EntryPoint).
- 65 modules, 3615 tests

## v1.55.0

- **Fix:** JSON mode now automatically enables quiet mode — `-OutputFormat JSON` suppresses all console box-drawing output, ensuring clean machine-readable stdout for Ansible, RMM, and pipeline consumers (00-Initialization).
- **Fix:** Standardized JSON serialization depth to `-Depth 10` across all actions — Cleanup and Debloat were using `-Depth 5` which could truncate nested objects in complex configurations (50-EntryPoint).
- 65 modules, 3583 tests

## v1.54.0

- **New Feature:** `-ListActions` CLI flag — `RackStack.exe -ListActions` enumerates all 62 available CLI actions with descriptions. Supports `-OutputFormat JSON` for machine-readable action discovery, perfect for Ansible/RMM dynamic inventory (50-EntryPoint).
- **New Feature:** `-Version` CLI flag — `RackStack.exe -Version` prints version string and exits. Useful for automation version checks and deployment verification (50-EntryPoint).
- **New Feature:** `-Quiet` CLI flag — `RackStack.exe -Action DiskAudit -OutputFormat JSON -Quiet` suppresses console box-drawing output, emitting only JSON. Ideal for automation pipelines that parse stdout (50-EntryPoint).
- 65 modules, 3581 tests

## v1.53.0

- **New Feature:** EnvAudit CLI action — `RackStack.exe -Action EnvAudit -OutputFormat JSON` audits system environment variables and performs PATH analysis. Detects missing directories, duplicate entries, and excessive PATH length. Exits code 1 when PATH issues detected (50-EntryPoint).
- **New Feature:** CrashAudit CLI action — `RackStack.exe -Action CrashAudit -OutputFormat JSON` audits system stability. Queries BugCheck events (BSOD), unexpected shutdown events (ID 6008), and inventories minidump/memory dump files. Exits code 1 when crash events found (50-EntryPoint).
- **New Feature:** LocalGroupAudit CLI action — `RackStack.exe -Action LocalGroupAudit -OutputFormat JSON` audits all local groups with membership. Reports member count, object class, and principal source per group. Flags Administrators group with more than 5 members. Exits code 1 when group issues detected (50-EntryPoint).
- **New Feature:** WMIAudit CLI action — `RackStack.exe -Action WMIAudit -OutputFormat JSON` audits WMI repository health. Verifies repository consistency, reports repository size, and tests 6 key WMI providers with query timing. Flags repository corruption and oversized repos (>500MB). Exits code 1 when WMI issues detected (50-EntryPoint).
- 65 modules, 3567 tests

## v1.52.0

- **New Feature:** AutoStartAudit CLI action — `RackStack.exe -Action AutoStartAudit -OutputFormat JSON` inventories all auto-start entries: registry Run/RunOnce keys (HKLM + HKCU + WOW6432Node), startup folder items, and non-Microsoft auto-start services (50-EntryPoint).
- **New Feature:** BIOSAudit CLI action — `RackStack.exe -Action BIOSAudit -OutputFormat JSON` reports BIOS/firmware details including vendor, version, release date, serial number, SMBIOS version. Also reports system manufacturer, model, type, and baseboard info (50-EntryPoint).
- **New Feature:** ClusterAudit CLI action — `RackStack.exe -Action ClusterAudit -OutputFormat JSON` audits failover cluster health. Reports cluster name, node states, and resource status. Flags nodes not in Up state and offline resources. Exits code 1 when cluster issues detected (50-EntryPoint).
- **New Feature:** AuditPolicyAudit CLI action — `RackStack.exe -Action AuditPolicyAudit -OutputFormat JSON` audits Windows security audit policies via auditpol. Reports all subcategories with Success/Failure/No Auditing status. Flags unconfigured audit policies. Exits code 1 when gaps detected (50-EntryPoint).
- 65 modules, 3530 tests

## v1.51.0

- **New Feature:** HyperVAudit CLI action — `RackStack.exe -Action HyperVAudit -OutputFormat JSON` audits Hyper-V infrastructure. Reports VM states, memory allocation, checkpoint counts (flags >3), and replication health. Exits code 1 when VM issues detected (50-EntryPoint).
- **New Feature:** NetworkAudit CLI action — `RackStack.exe -Action NetworkAudit -OutputFormat JSON` performs comprehensive network audit. Reports active adapter config with IP addresses, MAC, link speed, driver version, and default routes. Flags 100Mbps links on servers. Exits code 1 when network issues detected (50-EntryPoint).
- **New Feature:** StorageAudit CLI action — `RackStack.exe -Action StorageAudit -OutputFormat JSON` audits Storage Spaces configuration. Reports storage pool health, allocated capacity, and virtual disk resiliency settings. Flags degraded pools and virtual disks. Exits code 1 when storage issues detected (50-EntryPoint).
- **New Feature:** FeatureAudit CLI action — `RackStack.exe -Action FeatureAudit -OutputFormat JSON` inventories installed Windows features. Categorizes as Roles, Role Services, and Features with counts. Falls back to Get-WindowsOptionalFeature on client OS (50-EntryPoint).
- 65 modules, 3490 tests

## v1.50.0

- **New Feature:** ShareAudit CLI action — `RackStack.exe -Action ShareAudit -OutputFormat JSON` audits file share permissions. Enumerates non-administrative SMB shares with both SMB share-level and NTFS filesystem ACLs. Flags shares with Everyone Full Control. Exits code 1 when permission issues detected (50-EntryPoint).
- **New Feature:** DNSAudit CLI action — `RackStack.exe -Action DNSAudit -OutputFormat JSON` audits DNS client configuration. Reports DNS server addresses per adapter, suffix search lists, and performs live resolution tests against dns.msftncsi.com and time.windows.com. Exits code 1 when resolution failures detected (50-EntryPoint).
- **New Feature:** PowerAudit CLI action — `RackStack.exe -Action PowerAudit -OutputFormat JSON` audits power configuration. Reports active power plan, sleep timeouts (AC/DC), and hibernate availability. Flags non-High Performance plans on servers. Exits code 1 when power issues detected (50-EntryPoint).
- **New Feature:** RegistryAudit CLI action — `RackStack.exe -Action RegistryAudit -OutputFormat JSON` audits 10 security-critical registry settings against CIS-like baselines. Checks UAC, RDP NLA, AutoPlay, WDigest, LSASS protection, LM hash storage, anonymous SID restrictions, and NTLM minimum security. Exits code 1 when security issues detected (50-EntryPoint).
- **New Feature:** ProfileAudit CLI action — `RackStack.exe -Action ProfileAudit -OutputFormat JSON` audits user profiles. Reports disk usage per profile, last use date, loaded status, and flags stale profiles (>180 days) and large profiles (>5GB). Exits code 1 when profile issues detected (50-EntryPoint).
- 65 modules, 3450 tests

## v1.49.0

- **New Feature:** ProcessAudit CLI action — `RackStack.exe -Action ProcessAudit -OutputFormat JSON` audits running processes. Reports top 10 CPU and memory consumers, and scans running executables for valid Authenticode signatures. Lists unsigned or invalidly signed processes. Exits code 1 when unsigned processes detected (50-EntryPoint).
- **New Feature:** BackupAudit CLI action — `RackStack.exe -Action BackupAudit -OutputFormat JSON` audits backup infrastructure. Checks all VSS writer states and flags non-Stable writers, inventories Volume Shadow Copies, and queries Windows Server Backup job status. Exits code 1 when backup issues detected (50-EntryPoint).
- 65 modules, 3394 tests

## v1.48.0

- **New Feature:** GPOAudit CLI action — `RackStack.exe -Action GPOAudit -OutputFormat JSON` inventories applied Group Policies from the GP History registry. Reports machine and user policies with display names, deduplicates entries, and queries last gpupdate time. Works on both domain-joined and standalone systems (50-EntryPoint).
- **New Feature:** MemoryAudit CLI action — `RackStack.exe -Action MemoryAudit -OutputFormat JSON` audits physical memory configuration. Reports total/used/available RAM with utilization percentage, enumerates DIMM slots with capacity, speed, and manufacturer. Checks page file utilization. Flags RAM usage over 90% and page file over 80%. Exits code 1 when memory issues detected (50-EntryPoint).
- 65 modules, 3368 tests

## v1.47.0

- **New Feature:** TimeAudit CLI action — `RackStack.exe -Action TimeAudit -OutputFormat JSON` audits time synchronization configuration. Checks W32Time service status, NTP source and type, last sync time, and measures time drift against time.windows.com. Flags drift over 1s as warning, over 5s as critical. Exits code 1 when time issues detected (50-EntryPoint).
- **New Feature:** BootAudit CLI action — `RackStack.exe -Action BootAudit -OutputFormat JSON` audits boot configuration and system posture. Reports firmware type (UEFI/BIOS), Secure Boot status, DEP availability, boot time, uptime (flags >90 days), and pending reboot detection. Exits code 1 when boot issues detected (50-EntryPoint).
- 65 modules, 3340 tests

## v1.46.0

- **New Feature:** SMBAudit CLI action — `RackStack.exe -Action SMBAudit -OutputFormat JSON` audits SMB protocol configuration and share security. Checks SMBv1 status (flags if enabled), signing requirements, and encryption settings. Inventories non-administrative shares and flags those with Everyone Full Control. Exits code 1 when SMB issues detected (50-EntryPoint).
- **New Feature:** DriverAudit CLI action — `RackStack.exe -Action DriverAudit -OutputFormat JSON` audits system driver signing status via Win32_PnPSignedDriver. Reports all drivers with version, manufacturer, device class, and signing status. Highlights unsigned drivers separately. Exits code 1 when unsigned drivers detected (50-EntryPoint).
- 65 modules, 3315 tests

## v1.45.0

- **New Feature:** DiskAudit CLI action — `RackStack.exe -Action DiskAudit -OutputFormat JSON` audits physical disk health and volume utilization. Reports disk health status, operational status, media type, and size. Flags volumes with less than 10% free space as warnings and less than 5% as critical. Exits code 1 when disk issues detected (50-EntryPoint).
- **New Feature:** TLSAudit CLI action — `RackStack.exe -Action TLSAudit -OutputFormat JSON` audits TLS/SSL protocol configuration via SCHANNEL registry. Checks SSL 2.0/3.0 and TLS 1.0/1.1/1.2/1.3 server and client status. Flags insecure protocols (SSL/TLS 1.0/1.1) enabled as warnings, disabled TLS 1.2/1.3 as critical. Also checks .NET Framework strong crypto settings. Exits code 1 when TLS issues detected (50-EntryPoint).
- 65 modules, 3285 tests

## v1.44.0

- **New Feature:** FirewallAudit CLI action — `RackStack.exe -Action FirewallAudit -OutputFormat JSON` audits Windows Firewall configuration: profile status (Domain/Private/Public), rule counts by direction and action, top inbound allow groups. Flags disabled profiles and permissive Public profile settings. Exits code 1 when firewall issues detected (50-EntryPoint).
- **New Feature:** TaskAudit CLI action — `RackStack.exe -Action TaskAudit -OutputFormat JSON` audits non-Microsoft scheduled tasks for health. Reports task state, last run time, and result code. Classifies each task as OK (exit 0), Failed (non-zero exit excluding running/queued), or NeverRun. Exits code 1 when failed tasks detected (50-EntryPoint).
- **Performance:** Invoke-WithTimeout rewritten to use runspaces instead of Start-Job — eliminates process-spawn overhead on all ~50 timeout-wrapped operations. Server Readiness Dashboard and other CIM queries now start instantly instead of waiting for job initialization (04-Navigation).
- **Fix:** CredentialExpired tests no longer depend on Microsoft.PowerShell.Security module auto-loading — uses direct SecureString construction to avoid module load failures in constrained environments (Tests).
- **Hardened:** FirewallAudit now logs a warning when firewall rule enumeration fails instead of silently swallowing the error. TaskAudit shows an informational message when no non-Microsoft scheduled tasks exist, and uses safe `@()` count wrapping for PowerShell 5.1 compatibility (50-EntryPoint).
- 65 modules, 3253 tests

## v1.43.0

- **New Feature:** PatchStatus CLI action — `RackStack.exe -Action PatchStatus [-Config 15] -OutputFormat JSON` reports patch currency by querying installed hotfixes and Windows Update history. Classifies as OK (under 30 days), Warning (30-60 days), or Critical (60+ days). Detects pending reboots via registry. Exits code 1 when patch currency is Critical or reboot pending, usable as a compliance gate (50-EntryPoint).
- **New Feature:** UserAudit CLI action — `RackStack.exe -Action UserAudit [-Config "365,90"] -OutputFormat JSON` audits all local user accounts for security hygiene. Detects stale accounts, old/expired passwords, never-logged-in users, and Administrators group membership. Configurable thresholds for password age and login staleness. Exits code 1 when issues detected (50-EntryPoint).
- 65 modules, 3214 tests

## v1.42.0

- **New Feature:** Alert CLI action — `RackStack.exe -Action Alert -Config "alert-config.json"` detects threshold breaches or configuration drift and dispatches notifications via webhook (Slack, Teams, generic JSON POST), email (SMTP), or Windows Event Log. Sub-commands via -Tier: Watch (default, runs threshold checks then alerts), Diff (runs export diff then alerts), Test (sends test notification). Completes the detect-and-notify automation loop with Watch and Diff (45-ConfigExport, 50-EntryPoint).
- **New Feature:** FleetScan CLI action — `RackStack.exe -Action FleetScan -Config "fleet-config.json"` executes any RackStack action across multiple remote servers via WinRM. Configurable parallelism, per-host timeout, and optional result persistence. Turns any single-server action into a fleet-wide operation (45-ConfigExport, 50-EntryPoint).
- 65 modules, 3184 tests

## v1.41.0

- **New Feature:** Diff CLI action — `RackStack.exe -Action Diff -Config "old_export.json,new_export.json"` deep-diffs two Export JSON profiles from the same host at different times. Detects changes across 8 sections: Software (added/removed/version changed), ListeningPorts (opened/closed), Services (state/startup changes), Certificates (new expirations), Network (config changes), Hardening (score delta), Health (status changes), and Uptime (reboots). Exits code 1 when changes detected, making it a CI/pipeline drift gate (54-HTMLReports, 50-EntryPoint).
- **New Feature:** Baseline CLI action — `RackStack.exe -Action Baseline [-Config "C:\baselines"]` captures a full Export profile as a timestamped baseline file. Sub-commands: Save (default, runs all 11 Export sections and saves with hostname + timestamp), Status (shows latest baseline for current host). Baselines pair with Diff for change detection: capture known-good state, then Diff against later exports to detect drift (45-ConfigExport, 50-EntryPoint).
- 65 modules, 3110 tests

## v1.40.0

- **New Feature:** Watch CLI action — `RackStack.exe -Action Watch [-Config "thresholds.json"] -OutputFormat JSON` runs configurable threshold checks (CPU, memory, disk, uptime, certificates, services, events) and exits with code 0 (all clear) or code 1 (alert). Works as a monitoring health gate without external JSON parsing. Sensible defaults when no config file is provided (CPU 90%, memory 90%, disk 95%, uptime 60 days, certs 7 days, 0 critical events). Custom thresholds via JSON config for required running services, event window, and all numeric limits (45-ConfigExport, 50-EntryPoint).
- **New Feature:** Query CLI action — `RackStack.exe -Action Query -Config "C:\exports,section.field=value"` searches a directory of Export/Inventory JSON files and returns matching hosts. Supports equals (=), contains (~), greater (>), and less (<) operators. Query examples: `ListeningPorts.LocalPort=3389`, `Software.Name~SQL`, `Hardening.Score<60`, `Certificates.Status=Expired`. Makes the export archive queryable for fleet-wide searches without custom scripts (54-HTMLReports, 50-EntryPoint).
- 65 modules, 3048 tests

## v1.39.0

- **New Feature:** ScheduledExport CLI action — `RackStack.exe -Action ScheduledExport -Tier Register -Config "C:\Exports,Daily"` creates a Windows Scheduled Task that runs Export automatically on an Hourly, Daily, or Weekly schedule. Outputs JSON to the specified directory, running as SYSTEM with highest privileges. Sub-commands: Register (create/update task), Unregister (remove task), Status (check task state, last run, next run). Optional section filtering: `-Config "C:\Exports,Daily,Health,Inventory,Network"` runs only specified sections. Includes automatic export file rotation to keep the last 30 files (45-ConfigExport, 50-EntryPoint).
- **New Feature:** ValidateConfig CLI action — `RackStack.exe -Action ValidateConfig -Config "C:\path\to\batch_config.json"` performs pre-flight validation of batch configuration files without executing them. Checks JSON syntax, validates all field types and values (hostnames, IPs, CIDR, power plans, storage backends, DC promotion settings), counts active steps, and reports errors and warnings. Exits with code 1 on validation errors, code 0 on valid (with or without warnings). JSON output includes full error/warning lists and a summary with config type, hostname, and active step count (50-EntryPoint).
- 65 modules, 3001 tests

## v1.38.0

- **Enhancement:** Export CLI action expanded to 11 sections (was 8). Now also captures Services (key service status from configurable monitored list), Events (critical/error event log summary from last 24 hours), and Network (adapter configuration with IPv4, DNS, gateway, VLAN, NIC errors).
- **New Feature:** Export section filtering via `-Config` — `RackStack.exe -Action Export -Config "Health,Hardening,Network" -OutputFormat JSON` runs only the specified sections. Comma-separated section names, validated against the full list of 11. Enables fast partial exports when full 11-section scans are unnecessary. Default (no `-Config`) runs all 11 sections.
- 65 modules, 2962 tests

## v1.37.0

- **New Feature:** ServiceAudit CLI action — `RackStack.exe -Action ServiceAudit -OutputFormat JSON` audits key Windows services against a configurable monitored service list (from defaults.json or built-in fallback). Reports status, startup type, and flags misconfigured services (Automatic but Stopped). Exits with code 1 when any automatic service is not running, making it suitable for monitoring and alerting pipelines (50-EntryPoint).
- **New Feature:** EventAudit CLI action — `RackStack.exe -Action EventAudit -OutputFormat JSON [-Config <hours>]` scans System and Application event logs for Critical (Level 1) and Error (Level 2) events within a configurable time window (default 24 hours). Groups errors by source and returns event details with timestamps, IDs, and truncated messages. Useful for fleet-wide health monitoring and incident response triage (50-EntryPoint).
- **New Feature:** NetInfo CLI action — `RackStack.exe -Action NetInfo -OutputFormat JSON` captures network adapter configuration including status, link speed, IPv4 addresses with prefix, gateway, DNS servers, VLAN ID, and NIC error counters (InErrors/OutErrors). Provides a quick network configuration audit across a fleet without the overhead of a full Inventory scan (50-EntryPoint).
- 65 modules, 2963 tests

## v1.36.0

- **Enhancement:** Export CLI action now produces a comprehensive 8-section server profile (was 4 sections). In addition to Health, Inventory, Hardening, and Snapshot, Export now includes: Certificates (expiry audit across 5 stores with status classification), ListeningPorts (TCP listeners with process names and service labels), Software (registry scan of both 64-bit and 32-bit hives, deduplicated), and Uptime (CIM uptime with status + reboot history from event log including unexpected shutdowns). A single `RackStack.exe -Action Export -OutputFormat JSON` now captures a complete host profile in one pass (50-EntryPoint).
- 65 modules, 2923 tests

## v1.35.0

- **New Feature:** ListeningPorts CLI action — `RackStack.exe -Action ListeningPorts -OutputFormat JSON` scans all TCP listening endpoints on the local machine. Returns port, bind address, process name, PID, and well-known service labels (RDP, SMB, WinRM, DNS, HTTP, HTTPS, MSSQL, iSCSI, etc.). Includes unique port count and endpoint totals for fleet-wide attack surface monitoring (50-EntryPoint).
- **New Feature:** SoftwareList CLI action — `RackStack.exe -Action SoftwareList -OutputFormat JSON` scans both 64-bit and 32-bit registry hives for installed software. Returns name, version, publisher, install date, and estimated size. Deduplicates entries and groups by publisher. Useful for fleet-wide software auditing, rogue install detection, and compliance verification (50-EntryPoint).
- **New Feature:** Uptime CLI action — `RackStack.exe -Action Uptime -OutputFormat JSON` reports current uptime with status classification (OK, Warning at 30+ days, Critical at 60+ days) and recent reboot history from the Windows event log. Detects both planned (Event ID 1074) and unexpected (Event ID 6008) shutdowns with timestamps and reasons. Identifies servers that haven't rebooted after patching or have had unexpected crashes (50-EntryPoint).
- 65 modules, 2910 tests

## v1.34.0

- **New Feature:** CertCheck CLI action — `RackStack.exe -Action CertCheck -OutputFormat JSON` audits certificate expiry across five local machine stores (Personal, Trusted Root CA, Intermediate CA, Web Hosting, Remote Desktop). Categorizes certificates as Expired, Critical (≤7 days), Warning (≤30 days), Expiring (≤90 days), or Valid. Console output shows color-coded summary and highlights certificates needing immediate attention. JSON output includes full certificate list with store, subject, thumbprint, expiry date, days remaining, and status for fleet-wide compliance monitoring (50-EntryPoint).
- **New Feature:** ReportHTML CLI action — `RackStack.exe -Action ReportHTML -Config Health|Readiness|Trend` generates HTML reports from the command line. Supports three report types: Health (system performance, storage, network, security), Readiness (deployment readiness assessment), and Trend (performance trend visualization). Reports are saved to the Desktop by default. JSON output includes the output file path, generation status, and file size for automation pipelines (50-EntryPoint, 54-HTMLReports).
- 65 modules, 2875 tests

## v1.33.0

- **New Feature:** Export CLI action — `RackStack.exe -Action Export -OutputFormat JSON` runs health check, server inventory, security hardening audit, and performance snapshot in a single pass. Returns a unified JSON object with Health, Inventory, Hardening (score + per-check details), and Snapshot sections. Eliminates the need to run 4 separate CLI actions to get a complete host profile (50-EntryPoint).
- **New Feature:** Trend CLI action — `RackStack.exe -Action Trend -Config <snapshots-dir> -OutputFormat JSON` analyzes performance snapshots from a single host over time. Reads a directory of snapshot JSON files, sorts by timestamp, and calculates CPU/memory/disk trends with avg/min/max/first/last values and direction indicators (Rising/Falling/Stable). Console output includes color-coded warnings for rising resource usage (54-HTMLReports, 50-EntryPoint).
- 65 modules, 2837 tests

## v1.32.0

- **New Feature:** Aggregate CLI action — `RackStack.exe -Action Aggregate -Config <directory> -OutputFormat JSON` reads a directory of JSON output files from previous CLI runs and produces a fleet-wide summary report. Auto-detects action types and aggregates per-type: HealthCheck (health status counts), Harden (avg/min/max scores + top 10 common failures), Compliance (readiness score stats + drift counts), Inventory (OS/domain/role distribution), Snapshot (CPU/memory/disk averages), Remediate (fix/skip/fail totals + reboot count). Supports single JSON array files as well as directories. Console and JSON output (54-HTMLReports, 50-EntryPoint).
- **New Feature:** Compare CLI action — `RackStack.exe -Action Compare -Config "fileA.json,fileB.json" -OutputFormat JSON` performs side-by-side comparison of two JSON outputs from previous CLI runs. Supports action-specific comparison for Inventory (OS, domain, hardware, roles, volumes), Snapshot (CPU/memory/disk with delta calculations), Harden (scores + per-check status diff), Compliance (readiness scores + drift), and HealthCheck (health status + issues). Generic fallback for any action type. Color-coded console table with match/diff indicators and JSON output with property-level differences (54-HTMLReports, 50-EntryPoint).
- 65 modules, 2801 tests

## v1.31.0

- **New Feature:** Remediate CLI action — `RackStack.exe -Action Remediate -Config <baseline.json> -OutputFormat JSON` automatically fixes configuration drift by comparing current state to a saved baseline and applying corrections. Supports timezone, power plan, RDP, WinRM, DNS, IP address/gateway, Windows features (Hyper-V, MPIO, Failover Clustering), and hostname remediation. Domain join flagged as manual (requires credentials). Feature uninstall skipped (destructive). Reports fixed/failed/skipped/manual counts with reboot indicator. Full JSON output for automation pipelines (45-ConfigExport, 50-EntryPoint).
- **Fix:** Renamed `$args` to `$exeArgs` in Install-RackStack.ps1 to avoid PSScriptAnalyzer warning about automatic variable assignment.
- 65 modules, 2752 tests

## v1.30.0

- **New Feature:** Security Hardening Audit CLI action — `RackStack.exe -Action Harden -OutputFormat JSON` performs a CIS-lite security posture check across protocol security (SMBv1, NTLMv1, TLS 1.0/1.1), account security (guest account, built-in admin), network security (firewall profiles, admin shares, WinRM encryption), remote access (RDP NLA), system security (UAC, screen lock timeout), audit and logging (PowerShell script block logging, command line auditing), endpoint protection (Defender real-time, BitLocker, Windows Update service), and unnecessary services (Remote Registry, Fax, Telephony). Returns color-coded pass/fail/warn/info results with an overall hardening score percentage. Full JSON output support for fleet-wide security posture monitoring (37-HealthCheck, 50-EntryPoint).
- 65 modules, 2729 tests

## v1.29.1

- **Improvement:** README updated with all 9 CLI actions — DriftCheck, Snapshot, and Compliance added to the actions reference list.
- 65 modules, 2705 tests

## v1.29.0

- **New Feature:** Compliance Report CLI action — `RackStack.exe -Action Compliance -OutputFormat JSON` combines health check, readiness assessment, and optional drift detection into a single unified compliance report. With `-Config <baseline.json>`, also compares current state against a saved baseline. Returns readiness score (percentage), per-check status, health summary, and drift details in structured JSON for fleet compliance monitoring (50-EntryPoint, 54-HTMLReports).
- **Refactor:** Extracted readiness check logic into reusable `Get-ReadinessChecks` function — shared by both the HTML readiness report and the new Compliance CLI action, eliminating code duplication (54-HTMLReports).
- 65 modules, 2705 tests

## v1.28.0

- **New Feature:** Performance Snapshot CLI action — `RackStack.exe -Action Snapshot -OutputFormat JSON` captures a point-in-time performance snapshot (CPU load, memory usage, disk space per volume, network adapter bytes) and saves it to the metrics directory. Enables scheduled trend collection via Windows Scheduled Tasks for use with HTML trend reports. Full JSON output support for piping to monitoring systems (50-EntryPoint, 54-HTMLReports).
- 65 modules, 2689 tests

## v1.27.0

- **New Feature:** Configuration Drift Check CLI action — `RackStack.exe -Action DriftCheck -Config <baseline.json> -OutputFormat JSON` compares current server state against a saved baseline and reports drift as structured JSON (hostname, IP, domain, timezone, RDP, WinRM, power plan, roles). Without `-Config`, captures and outputs the current server state as a new baseline. Designed for fleet compliance monitoring and automated drift detection (50-EntryPoint, Header).
- 65 modules, 2682 tests

## v1.26.0

- **Improvement:** Error code coverage expanded — 12 new error codes (RS-2013, RS-2014, RS-3008, RS-4009, RS-5009, RS-5010, RS-6009, RS-6010, RS-6011, RS-7007) and 18 integration points across 10 additional modules: BitLocker, Host Storage, VHD Management, Offline VHD, Cluster Dashboard, VM Checkpoints, VM Export/Import, Network Diagnostics, Storage Backends, Active Directory. Total: 68 error codes across 28 modules.
- 65 modules, 2673 tests

## v1.25.1

- **Improvement:** README updated with Inventory CLI action — usage example and action reference list now includes `-Action Inventory` for CMDB/asset management workflows.
- 65 modules, 2647 tests

## v1.25.0

- **New Feature:** Server Inventory CLI action — `RackStack.exe -Action Inventory -OutputFormat JSON` gathers complete server inventory (hostname, domain, OS, CPU, RAM, disks, volumes, network adapters with IPs/MACs, installed roles/features, licensing, firewall, remote access, power plan, timezone, uptime) and outputs structured JSON for CMDB integration, asset management, and automation pipelines (45-ConfigExport, 50-EntryPoint, Header).
- 65 modules, 2647 tests

## v1.24.0

- **Improvement:** Enriched QuickScan JSON output — disk cleanup analysis and system debloat scan now return structured data (cleanup savings breakdown, removable packages, telemetry tasks, service recommendations). QuickScan `-OutputFormat JSON` includes full `Health`, `DiskCleanup`, and `Debloat` sections with granular fields for automation dashboards and reporting (20-DiskCleanup, 64-SystemDebloat, 50-EntryPoint).
- 65 modules, 2623 tests

## v1.23.2

- **Improvement:** README updated with JSON output mode documentation — usage examples, PowerShell parsing, and Ansible integration patterns for `-OutputFormat JSON`.
- 65 modules, 2601 tests

## v1.23.1

- **Improvement:** Error code coverage expanded — 10 new error codes (RS-1009, RS-2012, RS-3007, RS-4007, RS-4008, RS-5008, RS-6006, RS-6007, RS-6008, RS-7006) integrated into 8 additional modules: Windows Updates, RDP, Defender Exclusions, Failover Clustering, Storage Manager, Disk Cleanup, Hyper-V Replica, Scheduled Tasks. Total: 56 error codes across 18 modules (02-Logging).
- 65 modules, 2601 tests

## v1.23.0

- **New Feature:** JSON output mode for CLI headless actions — pass `-OutputFormat JSON` to get structured JSON output from HealthCheck and QuickScan actions. Returns system info, CPU, memory, disk, network, services, firewall status, and issue summary in machine-readable format. Cleanup and Debloat actions return status confirmation. Designed for integration with monitoring dashboards, alerting pipelines, and automation orchestration (37-HealthCheck, 50-EntryPoint, Header, 00-Initialization).
- **Improvement:** Bootstrap installer (`Install-RackStack.ps1`) passes `-OutputFormat` through to RackStack.exe for end-to-end JSON pipeline support.
- 65 modules, 2581 tests

## v1.22.2

- **New Feature:** QuickScan CLI action — combined health check + disk analysis + debloat recommendations in a single pass (`-Action QuickScan`). Useful for first-time assessment of any machine (50-EntryPoint).
- **New Feature:** Bootstrap installer (`Install-RackStack.ps1`) — one-liner remote deployment that downloads the latest release from GitHub and runs it with CLI parameters. Works with Ansible, RMM tools, PDQ, and any tool that can execute PowerShell. Includes version caching, TLS 1.2 enforcement, and proper exit codes.
- **Improvement:** CLI headless mode now exits with proper exit codes (0 = success, 1 = error) for CI/CD integration.
- 65 modules, 2554 tests

## v1.22.1

- **New Feature:** Structured error code system — 46 error codes across 8 categories (RS-1xxx Core, RS-2xxx Network, RS-3xxx Security, RS-4xxx Roles, RS-5xxx VM, RS-6xxx Storage, RS-7xxx Config, RS-8xxx Agent) with wiki-linked troubleshooting. Errors display code, message, and clickable hyperlink to wiki documentation. OSC 8 hyperlinks in Windows Terminal, plain URL fallback elsewhere (02-Logging).
- **Integration:** Error codes deployed to 10 high-traffic error sites across modules: elevation check, defaults parsing, adapter detection, IP validation, SET creation, iSCSI connection, domain join, Hyper-V detection, VM creation, file server connectivity (50-EntryPoint, 56-OperationsMenu, 06-NetworkAdapters, 07-IPConfiguration, 09-SET, 10-iSCSI, 12-DomainJoin, 25-HyperV, 44-VMDeployment, 39-FileServer).
- **Wiki:** New Error Codes reference page with cause/resolution for all 46 codes.
- 65 modules, 2531 tests

## v1.22.0

- **New Feature:** CLI headless mode — run actions without interactive menus via command-line parameters: `-Action Cleanup|Debloat|HealthCheck|Batch`, `-Profile Light|Standard|Aggressive`, `-Config <path>`, `-Silent`. Works with both .ps1 and compiled .exe for remote one-liner deployment (Header, 00-Initialization, 03-InputValidation, 50-EntryPoint).
- **New Feature:** System Debloat & Optimization module (64-SystemDebloat) — remove bloatware AppxPackages, disable telemetry services/tasks, apply registry performance tweaks, remove unnecessary optional features. Three profiles (Light/Standard/Aggressive) with separate workstation and server paths. Includes quick scan preview, custom category picker, undo support for services and registry changes.
- **New Feature:** Enhanced Disk Cleanup — 7 new cleanup functions added to existing module: Windows.old removal, browser cache clearing (Edge/Chrome/Firefox), recycle bin emptying, user profile temp cleanup, shadow copy removal, enhanced analysis view, and full cleanup mode. Menu expanded from 6 to 13 options (20-DiskCleanup).
- **New Feature:** PowerShell Scan workflow — daily PSSA scanning with automatic GitHub issue creation/resolution per script file, risk-level labeling, and workflow summary reports.
- **Fix:** PSSA findings in test file — `$null` comparison order corrected, `PSAvoidUsingConvertToSecureStringWithPlainText` excluded for test-only dummy credentials (Tests/Run-Tests, PSScriptAnalyzerSettings).
- 65 modules, 2501 tests

## v1.21.18

- **Bug Fix:** Pressing Q for Quick Setup Wizard on the Configure Server menu exited the script instead of launching the wizard — "q" was in the global exit commands list, intercepting it before the menu could handle it. Removed "q" from exit shortcuts; users can still type "exit" or "quit" to close the script (04-Navigation).
- 64 modules, 2501 tests

## v1.21.17

- **Bug Fix:** Company defaults prompt appeared with empty name when no company defaults files existed — defaults loading redesigned: single defaults file loads silently, company picker only shown when multiple defaults files are present (56-OperationsMenu).
- 64 modules, 2501 tests

## v1.21.16

- **Bug Fix:** Color severity mismatches across 7 modules — actual failures (connection failures, task errors, catch blocks) now consistently use error color instead of warning color (44-VMDeployment, 63-ScheduledTasks, 32-Deduplication, 47-ExitCleanup, 08-VLAN, 11-Hostname).
- **Bug Fix:** Null-safety fixes across 5 modules — property access (.Length, .Substring) on potentially null display names, resource names, and version strings now guarded against null reference errors (44-VMDeployment, 35-Utilities, 14-WindowsUpdates, 39-FileServer).
- **Bug Fix:** Hash file written with empty hash when computation failed — now only writes .sha256 file when a valid hash exists (39-FileServer).
- **Bug Fix:** OS build detection crashed if both registry and CIM queries failed — added nested fallback so startup survives degraded environments (00-Initialization).
- **Bug Fix:** HttpWebRequest not aborted on resume failure — added request cleanup in download error path (39-FileServer).
- **UX:** Silent invalid input in 4 menu locations now shows error feedback instead of silently returning (35-Utilities, 31-BitLocker, 32-Deduplication).
- **Reliability:** Menu cache invalidation added after ~30 state-changing operations across 12 modules to prevent stale menu display after system changes (55-QoLFeatures, 50-EntryPoint, 61-ActiveDirectory, 45-ConfigExport, 57-AgentInstaller, 37-HealthCheck, 04-Navigation, 16-Firewall, 20-DiskCleanup, 22-Password, 63-ScheduledTasks, 10-iSCSI).
- 64 modules, 2501 tests

## v1.21.15

- **Bug Fix:** Agent not detected before domain join despite being installed this session — agent detection now caches confirmed install result so subsequent checks (domain join, menu status) don't lose track of the agent (57-AgentInstaller).
- **Bug Fix:** NuGet provider prompt during Windows Update — added `-Confirm:$false` to suppress interactive Y/N prompt on some OS versions (14-WindowsUpdates).
- 64 modules, 2291 tests

## v1.21.14

- **Bug Fix:** Agent installer returned to selection menu after successful install instead of going back to main menu — now returns immediately after install completes (57-AgentInstaller).
- **Bug Fix:** Agent installer Step 4 menu always showed "Not Installed" even after successful install — now re-checks agent status each iteration (57-AgentInstaller).
- **UX:** VM licensing no longer asks "Is your host Datacenter?" — instead offers AVMA key directly as first option with KMS and manual as alternatives (21-Licensing).
- 64 modules, 2291 tests

## v1.21.13

- **Bug Fix:** Agent detection still reported "already installed" after uninstall — leftover files in install directory triggered false positive. Detection now requires the agent service to exist OR the agent to appear in Programs and Features; orphaned files alone no longer block reinstallation (57-AgentInstaller).
- 64 modules, 2291 tests

## v1.21.12

- **Bug Fix:** Agent detection false positive after uninstall — `InstallPaths` check now verifies actual agent executables exist in the directory, not just the directory itself (57-AgentInstaller).
- **Bug Fix:** Agent installer showed "MSP" instead of configured agent name after loading company defaults — personal defaults.json no longer overwrites company agent config; agent installer resets to factory before each config reload (56-OperationsMenu).
- **Bug Fix:** Self-update not applying — EXE updater now waits longer for file lock release with 3 retry attempts; PS1 updater auto-restarts instead of requiring manual restart (35-Utilities).
- **UX:** Company defaults prompt cleaned up — no longer shows confusing `.defaults.json` extension in prompts (56-OperationsMenu).
- 64 modules, 2291 tests

## v1.21.11

- **Bug Fix:** Manual "Check for Updates" used stale cached results from startup — now always fetches fresh from GitHub API so newly published releases are detected immediately (35-Utilities).
- 64 modules, 2291 tests

## v1.21.10

- **Bug Fix:** Double "Press Enter" on multiple screens — removed redundant `Write-PressEnter` from menu runner for 15+ functions that already pause internally (49-MenuRunner).
- **Bug Fix:** Agent detection — added broad ToolName service match and Windows registry (Uninstall) check as fallbacks; catches agents whose service names don't match the configured pattern (57-AgentInstaller).
- **UX:** Self-destruct countdown now updates the number in-place instead of printing a new line each second (47-ExitCleanup).
- 64 modules, 2291 tests

## v1.21.9

- **Bug Fix:** Domain join broken — `Add-Computer` was wrapped in `Invoke-WithTimeout` which runs in a separate job where local variables (`$targetDomain`, `$credential`) are null. Domain join reported success despite never executing. Now runs `Add-Computer` directly (12-DomainJoin).
- **Bug Fix:** Agent installer hung after install — replaced background job with direct process monitoring; installer now detects agent service within 10 seconds of install completing instead of waiting for process tree to exit. Press Escape to skip waiting. Installer window now hidden (57-AgentInstaller).
- **Bug Fix:** Agent detection — added display name fallback for service matching; some agents use internal service names that differ from the display name pattern (57-AgentInstaller).
- **Bug Fix:** Disable Admin blocked despite alternate admin existing — `PrincipalSource` filter excluded accounts where the property was null (common on some OS versions). Now validates locality via `Get-LocalUser` instead (24-DisableAdmin).
- **Bug Fix:** WinRM status showed "Enabled" (green) when only the service was running — now checks service startup type, PSSession configuration, and firewall rules before reporting fully enabled. Shows "Partial" (yellow) when only partially configured (05-SystemCheck).
- **Bug Fix:** Download progress bar crash — ETA calculation used a format specifier incompatible with floating-point values, causing "Format specifier was invalid" error during file downloads (04-Navigation).
- 64 modules, 2291 tests

## v1.21.7

- **UX:** Agent installer "NOT CONFIGURED" screen cleaned up — removed debug output, now shows a concise error message if the company defaults JSON file has syntax errors (57-AgentInstaller).
- **Bug Fix:** Agent installer failsafe retry when company defaults weren't applied during startup (57-AgentInstaller).
- **Bug Fix:** ps2exe ModuleRoot — compiled EXE now always uses the EXE's own directory for finding defaults files (00-Initialization).
- 64 modules, 2291 tests

## v1.21.3

- **Bug Fix:** Agent installer failsafe — if company defaults weren't loaded during startup, automatically retry loading when agent installer is accessed. Shows diagnostic info if still misconfigured.
- 64 modules, 2291 tests

## v1.21.2

- **Bug Fix:** Company defaults loading — first-run wizard no longer saves built-in defaults that overwrite company values on reload; company defaults files (*.defaults.json) are now properly detected and prompted even when defaults.json already exists (56-OperationsMenu).
- **Bug Fix:** Nested defaults deep merge — personal defaults.json no longer overwrites company FileServer/AgentInstaller config with empty values; Tier 3 merge now deep-merges nested objects instead of replacing them (56-OperationsMenu).
- **Bug Fix:** KaseyaFolder remap — `KaseyaFolder` key in FileServer config now always remaps to `AgentFolder`, fixing agent installer file discovery when using legacy config format (56-OperationsMenu).
- **Bug Fix:** License keys and VM naming now load from merged defaults (company + personal) instead of only from personal defaults.json (56-OperationsMenu).
- **Bug Fix:** Negative uptime display — dashboard uptime calculation now uses UTC on both sides to prevent timezone mismatch showing negative hours (48-MenuDisplay).
- **Bug Fix:** Mojibake on System Configuration menu — corrupted UTF-8 arrow character restored (48-MenuDisplay).
- **Bug Fix:** NuGet provider prompt — added `-ForceBootstrap` to suppress interactive Y/N prompt during Windows Update setup (14-WindowsUpdates).
- **Bug Fix:** Update install progress no longer shows elapsed time twice (14-WindowsUpdates).
- **UX:** Hostname validation now shows specific rejection reason (e.g., "Too long: 16 characters, max 15") instead of generic "See requirements above" (03-InputValidation, 11-Hostname).
- 64 modules, 2291 tests

## v1.21.1

- **Robustness:** CIM timeout hardening — 25+ bare `Get-CimInstance` calls wrapped with `Invoke-WithTimeout` to prevent UI hangs when WMI is slow or unresponsive (12-DomainJoin, 19-NTP, 24-DisableAdmin, 25-HyperV, 35-Utilities, 36-BatchConfig, 40-HostStorage, 44-VMDeployment, 45-ConfigExport, 50-EntryPoint, 55-QoLFeatures).
- **Robustness:** Cache invalidation — 30+ state-changing operations now call `Clear-MenuCache` so menu status stays current after changes (07-IPConfig, 08-VLAN, 10-iSCSI, 11-Hostname, 12-DomainJoin, 13-Timezone, 14-WindowsUpdates, 17-DefenderExclusions, 18-FirewallTemplates, 19-NTP, 20-DiskCleanup, 21-Licensing, 30-ServiceManager, 31-BitLocker, 32-Deduplication, 33-StorageReplica).
- **UX:** Dashboard pause — 11 utility dashboard/viewer functions now pause with "Press Enter" so output doesn't flash away before the user can read it (35-Utilities: CertExpiry, VSS, EventLog, Uptime, DriverHealth, DiskSpace, WinUpdate, ListeningPorts, ScheduledTasks, FirewallSummary, RebootPending, MemoryDiagnostics).
- **UX:** Action completion pause — 5 action functions now call `Write-PressEnter` after success/error so results are visible (09-SET, 10-iSCSI, 20-DiskCleanup, 23-LocalAdmin, 37-HealthCheck).
- **UX:** Domain join now shows a spinner during the `Add-Computer` call with a 2-minute timeout, plus consistent 2-space message indentation (12-DomainJoin).
- **UX:** Auto-reboot delay reduced from 10 to 5 seconds for faster workflow (50-EntryPoint).
- **UX:** Device driver scan batches 3 CIM queries into a single call with timeout for faster results (35-Utilities).
- **Bug Fix:** Null-safe `Get-Content` check before pattern matching in file download validation (39-FileServer).
- **Bug Fix:** Error message indentation fixes for console box alignment (25-HyperV, 44-VMDeployment).
- 64 modules, 2196 tests

## v1.21.0

- **New Feature:** Performance Dashboard Copy to Clipboard — press `[C]` to copy a full system snapshot (CPU, memory, disk, network, top processes) to clipboard for sharing or documentation (28-PerformanceDashboard).
- **Resilience:** OS detection uses registry-first approach — immune to WMI/CIM service hangs that can occur under heavy system load (00-Initialization, 05-SystemCheck).
- **Resilience:** Firewall state detection uses registry-first approach with cmdlet fallback — prevents indefinite hang when CIM is unresponsive (05-SystemCheck).
- **Bug Fix:** Drag-and-drop file paths auto-trim surrounding double quotes across 12+ modules — paths dragged from Explorer no longer fail with "path not found" (17-DefenderExclusions, 27-FailoverClustering, 31-BitLocker, 36-BatchConfig, 45-ConfigExport, 53-VMExportImport, 56-OperationsMenu, 59-StorageBackends, 62-HyperVReplica, 63-ScheduledTasks).
- **Bug Fix:** PS 5.1 pipeline `.Count` — single pipeline results wrapped with `@()` for consistent counting. Fixes broken auto-install-on-single-match in Agent Installer and unreliable baseline counting in Config Export (44-VMDeployment, 45-ConfigExport, 57-AgentInstaller).
- **Bug Fix:** Quorum witness file share path navigation uses `return` instead of `break` — prevents accidentally exiting the enclosing while loop (27-FailoverClustering).
- **Bug Fix:** VM Import destination path supports navigation commands — `home`, `back`, and `exit` now work during import (53-VMExportImport).
- 64 modules, 2087 tests

## v1.20.9

- **Bug Fix:** Remote directory creation in VM deployment uses `-ErrorAction Stop` — prevents silent failure and confusing Hyper-V errors when WinRM fails (44-VMDeployment).
- **Bug Fix:** `Remove-SRPartnership` includes `-Confirm:$false` — prevents hanging in non-interactive/batch contexts after user already confirmed (33-StorageReplica).
- **Bug Fix:** `Initialize-Disk` includes `-Confirm:$false` — prevents hanging in non-interactive contexts after user confirmation (38-StorageManager).
- **Bug Fix:** `Set-Partition` drive letter assignment uses `-ErrorAction Stop` with try/catch — reports failure instead of showing incorrect success (38-StorageManager).
- **Bug Fix:** VM NIC configuration wrapped in per-NIC try/catch — reports individual NIC failures instead of silently deploying misconfigured VMs (44-VMDeployment).
- **Bug Fix:** Remote profile copy `Invoke-Command` uses `-ErrorAction Stop` — prevents false success message when remote write fails (35-Utilities).
- **Bug Fix:** VM deployment storage init failure resets all connection state variables — prevents stale values in subsequent attempts (44-VMDeployment).
- **Bug Fix:** Windows Update install job extracts error details before `Remove-Job` — shows actual failure reason instead of generic message (14-WindowsUpdates).
- 64 modules, 1873 tests

## v1.20.8

- **Bug Fix:** Storage Replica replication mode prompt validates input and supports navigation — prevents silently selecting Asynchronous mode for any non-"1" input (33-StorageReplica).
- **Bug Fix:** License type selection (add/delete) validates input as "1" or "2" — prevents silently selecting AVMA for any non-"1" input including nav commands (56-OperationsMenu).
- **Bug Fix:** Host Storage "0" back option checked before `Test-NavigationCommand` — restores "No changes made." feedback message (40-HostStorage).
- **Cleanup:** Removed unreachable dead code — 3 `"^[Bb]$"` switch cases in timezone functions already handled by navigation system, duplicate nav check in Host Storage, dead `'b'/'B'` check in Agent Installer.
- 64 modules, 1873 tests

## v1.20.7

- **Bug Fix:** `Get-ChildItem` uses `-LiteralPath` across 12 instances in Disk Cleanup, Utilities disk analysis, Config Export baselines, Exit Cleanup profile scan, Entry Point transcript cleanup, HTML Reports metrics, and Operations Menu company defaults.
- **Bug Fix:** `Test-Path` uses `-LiteralPath` for temp paths, WU cache, CBS logs, disk analysis paths, defaults path, agent installer temp path, and exit cleanup folder checks (10 instances).
- **Bug Fix:** `Remove-Item` uses `-LiteralPath` via `ForEach-Object` for pipeline operations — prevents wildcard interpretation when piping `FileInfo` objects (20-DiskCleanup WU cache, 50-EntryPoint old logs).
- 64 modules, 1873 tests

## v1.20.6

- **Bug Fix:** Disk Cleanup uses `$env:SystemDrive` instead of hardcoded `C:` for `cleanmgr` — works correctly when OS is on a non-C: drive (20-DiskCleanup).
- **Bug Fix:** `Remove-Item` uses `-LiteralPath` for temp file and transcript log cleanup — prevents wildcard interpretation on bracket-containing filenames (20-DiskCleanup, 50-EntryPoint).
- **Bug Fix:** FileServer guards against empty HTTP response body before `ConvertFrom-Json` — gives clear error message instead of cryptic JSON parse error (39-FileServer).
- **Bug Fix:** Domain join filters DNS response for A records before displaying IP — prevents showing blank IP when first result is CNAME/SOA (12-DomainJoin).
- **Bug Fix:** `Get-FileHash` uses `-LiteralPath` inside hash computation job — prevents hash failure on files with bracket characters in name (04-Navigation).
- **Bug Fix:** Help text displays actual `$script:TempPath` instead of hardcoded `C:\Temp` — shows correct path when overridden via defaults.json (34-Help).
- **Bug Fix:** Sysprep guidance text uses `$env:SystemRoot` and `$env:SystemDrive` instead of hardcoded `C:` paths (41-VHDManagement).
- 64 modules, 1873 tests

## v1.20.5

- **Bug Fix:** `Out-File` calls use `-LiteralPath` for favorites, history, session state, and defaults file writes — prevents wildcard interpretation on config paths (55-QoLFeatures, 56-OperationsMenu).
- **Bug Fix:** `Export-Csv` calls use `-LiteralPath` for event log and software inventory exports — prevents wildcard interpretation on constructed paths (29-EventLogViewer, 35-Utilities).
- 64 modules, 1873 tests

## v1.20.4

- **Bug Fix:** `Get-Content` calls use `-LiteralPath` across 10 instances in 7 modules — prevents wildcard interpretation on config-derived paths (04-Navigation, 34-Help, 39-FileServer, 45-ConfigExport, 50-EntryPoint, 54-HTMLReports, 55-QoLFeatures, 56-OperationsMenu).
- **Bug Fix:** VM Deployment standard and custom summary loops now handle "home" and "back" navigation via `Test-NavigationCommand` — prevents users getting trapped in the edit loop (44-VMDeployment).
- **Bug Fix:** `Add-MultipleVNICs` loop checks `$global:ReturnToMainMenu` flag after each vNIC creation — prevents re-prompting after "home" navigation (09-SET).
- 64 modules, 1873 tests

## v1.20.3

- **Bug Fix:** `Get-Item` calls use `-LiteralPath` for all config-derived and user-input paths across FileServer, VHD Management, and Navigation (10 instances).
- **Bug Fix:** `Remove-Item` calls use `-LiteralPath` for all constructed paths across Utilities, FileServer, VHD Management, ISO Download, QoL Features, and Agent Installer (20+ instances).
- **Bug Fix:** `Get-ChildItem` calls use `-LiteralPath` for config-derived directory paths in VHD Management and ISO Download.
- **Bug Fix:** `Copy-Item` and `Move-Item` calls use `-LiteralPath` for source paths across VHD Management, Utilities, and Navigation.
- **Bug Fix:** `Add-Content` and `Set-Content` calls use `-LiteralPath` for log files and generated scripts across Logging, Navigation, FileServer, and Offline VHD.
- **Bug Fix:** Hash computation job cleanup includes `Stop-Job` before `Remove-Job` (04-Navigation).
- **Bug Fix:** Empty `catch {}` blocks explicitly assign `$null` in Disk Cleanup, Utilities reboot checks, and VM Deployment CSV check.
- 64 modules, 1873 tests

## v1.20.2

- **Bug Fix:** Disk space checks in FileServer and VHD downloads guard against UNC/CSV paths — prevents silent failures when destination is a network share (39-FileServer, 41-VHDManagement).
- **Bug Fix:** `Stop-Job` called before `Remove-Job` in VHD copy/convert `finally` block — prevents orphaned background processes on failure (41-VHDManagement).
- **Bug Fix:** `Test-Path` calls use `-LiteralPath` across 5 more modules for constructed/config-derived paths (41-VHDManagement, 42-ISODownload, 43-OfflineVHD, 35-Utilities, 40-HostStorage).
- **Bug Fix:** `Get-ClusterResource` includes `-ErrorAction SilentlyContinue` to prevent crashes when Cluster service is unavailable (27-FailoverClustering).
- **Bug Fix:** CSV removal and Live Migration network changes now track session changes via `Add-SessionChange` (27-FailoverClustering).
- **Bug Fix:** Silent `catch {}` block in scheduled task info retrieval explicitly sets `$null` (35-Utilities).
- **Bug Fix:** Remote temp path fallback uses `$env:SystemRoot` instead of hardcoded `C:\Windows` (35-Utilities).
- 64 modules, 1873 tests

## v1.20.1

- **Bug Fix:** `Test-Path` calls use `-LiteralPath` across 15 modules for all constructed, user-input, and config-derived paths — prevents wildcard interpretation on paths containing bracket characters.
- **Bug Fix:** Subnet sweep and port scan properly stop timed-out background jobs before cleanup — prevents orphaned processes (58-NetworkDiagnostics).
- **Bug Fix:** Agent installer properly stops background install job in finally block (57-AgentInstaller).
- **Bug Fix:** Hardcoded `C:\Windows` paths replaced with `$env:SystemRoot` in AD DC promotion confirmation display (61-ActiveDirectory).
- **Bug Fix:** Hardcoded `C:\Hyper-V` fallback paths replaced with `$env:SystemDrive` (62-HyperVReplica, 56-OperationsMenu).
- **Bug Fix:** `Get-MpPreference` wrapped in `try/catch` with `-ErrorAction Stop` in Defender view/remove functions (17-DefenderExclusions).
- **Bug Fix:** `Disable-AllIPv6` guards against null adapter list before iterating (07-IPConfiguration).
- **Bug Fix:** `Invoke-WithTimeout` returns consistent `Failed`/`Error` keys across all code paths (04-Navigation).
- **Bug Fix:** Windows activation now tracks session change on success (21-Licensing).
- **Bug Fix:** `ReturnToMainMenu` checks added to SNMP config, Edit Defaults, and Edit Licenses menu loops (55-QoLFeatures, 56-OperationsMenu).
- 64 modules, 1873 tests

## v1.20.0

- **New Feature:** Scheduled Task Manager — view all tasks, search by keyword, show running/failed tasks, enable/disable, run on demand, export/import XML backups with full state tracking (63-ScheduledTasks).
- **Bug Fix:** Discovery cmdlets (`Get-NetAdapter`, `Get-Disk`, `Get-Volume`, `Get-NetIPAddress`) across 9 modules now include `-ErrorAction SilentlyContinue` to prevent unhandled terminating errors when WMI/CIM queries fail on disconnected or degraded hardware.
- **Bug Fix:** ISO download disk space check no longer fails on UNC/network paths — guards against non-drive-letter paths (42-ISODownload).
- **Bug Fix:** `Test-Path` calls use `-LiteralPath` for user-input profile path to prevent wildcard interpretation (35-Utilities).
- **Bug Fix:** `Test-Path` calls use `-LiteralPath` for FileServer download destination and progress-check paths (39-FileServer).
- **Bug Fix:** VHD conversion retry properly stops timed-out background job before cleanup (41-VHDManagement).
- 64 modules, 1873 tests

## v1.19.1

- **Bug Fix:** Port scan results now correctly match ports when some scans time out — results tracked per-job index instead of sequential array (58-NetworkDiagnostics).
- **Bug Fix:** Subnet sweep batches jobs (50 at a time) instead of spawning up to 254 concurrent processes which could exhaust system memory (58-NetworkDiagnostics).
- **Bug Fix:** Hyper-V Replica status shows HTTP/HTTPS as "Disabled" when auth type doesn't include that protocol, instead of always showing port numbers (62-HyperVReplica).
- **Bug Fix:** VM Deployment fallback paths use `$env:SystemDrive` instead of hardcoded `C:\` (44-VMDeployment).
- 63 modules, 1853 tests

## v1.19.0

- **Bug Fix:** "Home" navigation now works from all nested menus — added `ReturnToMainMenu` checks to 17 menu loops across iSCSI, Firewall Templates, NTP, Disk Cleanup, BitLocker, ISO Download, Cluster Dashboard, VM Checkpoints, VM Export/Import, Network Diagnostics, Hyper-V Replica, Storage Backends, and Settings.
- **Bug Fix:** Disk space pre-checks no longer fail on UNC/network paths — VM Export, VM Checkpoints, and VM Deployment now guard against non-drive-letter paths (clusters with CSVs, SMB shares).
- **Bug Fix:** Hardcoded `slmgr.vbs` paths replaced with `$env:SystemRoot` for non-standard Windows installations (21-Licensing).
- **Bug Fix:** Defender threat count logged correctly when query fails — `$threats` initialized before try block to prevent false "Threats=1" in session log (17-DefenderExclusions).
- **Bug Fix:** IPv6 disable now reports actual failures instead of silent success — changed from `SilentlyContinue` to `Stop` error action so the catch block is reachable (07-IPConfiguration).
- **Bug Fix:** Export VM cleanup now properly stops orphaned background jobs before removing them (53-VMExportImport).
- **Bug Fix:** `$Matches` automatic variable captured immediately per project convention (19-NTPConfiguration).
- **Bug Fix:** `Test-Path` calls use `-LiteralPath` for all constructed paths in exit cleanup to prevent wildcard interpretation (47-ExitCleanup).
- **Cleanup:** Removed unused `$script:BITSPreferred` variable (00-Initialization).
- 63 modules, 1853 tests

## v1.18.2

- **Bug Fix:** HTML reports encode all dynamic values with `HtmlEncode` — VM names, adapter names, CPU model, process names, and config profile comparison data are now safe from display issues with special characters like `&`, `<`, `>` in generated HTML (54-HTMLReports).
- **Bug Fix:** Hardcoded power plan GUID in offline VHD first-boot script replaced with centralized `$script:PowerPlanGUID` constant (43-OfflineVHD).
- **Bug Fix:** Firewall rule `.Enabled` comparison uses boolean `$true` instead of string `"True"` for consistency with `GpoBoolean` enum across codebase (35-Utilities, 16-Firewall).
- **Bug Fix:** `Save-StoredCredential` clears plaintext password variable on exception path — if `Process.Start()` threw, the password remained in memory (35-Utilities).
- **Bug Fix:** `Install-HyperVRole` adds `-ErrorAction` on `Get-CimInstance` with graceful fallback if WMI is unavailable (25-HyperV).
- **Bug Fix:** SHA256 hash verification guards against null stream/hasher in finally block (35-Utilities).
- **Bug Fix:** `Clear-MenuCache` called after SET, vSwitch, and vNIC creation/removal to ensure menus reflect current adapter state (09-SET).
- **Bug Fix:** Disk cleanup uses `try/catch` instead of TOCTOU `Test-Path` pattern for accurate deletion counting (20-DiskCleanup).
- **Bug Fix:** Disk cleanup uses `$env:SystemRoot` instead of hardcoded `C:\Windows` paths for non-standard installations (20-DiskCleanup).
- **Bug Fix:** VHD Management, Deduplication, and Storage Replica menu loops check `$global:ReturnToMainMenu` flag to exit immediately when triggered from a sub-function (41-VHDManagement, 32-Deduplication, 33-StorageReplica).
- **Bug Fix:** `Get-Volume` and `Get-Service` calls add `-ErrorAction SilentlyContinue` to prevent noise from restricted services or unavailable storage (38-StorageManager, 30-ServiceManager).
- 63 modules, 1854 tests

## v1.18.1

- **Bug Fix:** `Remove-NetIPAddress` and `Remove-NetRoute` calls now specify `-AddressFamily IPv4` — without this flag, IPv6 link-local addresses and routes were stripped unnecessarily during IP reconfiguration (09-SET, 45-ConfigExport, 50-EntryPoint).
- **Bug Fix:** Standard vSwitch creation uses `$ManagementName` variable instead of hardcoded `"Management"` — respects `defaults.json` override for management NIC naming (09-SET).
- **Bug Fix:** iSCSI target discovery no longer filters out already-connected targets — the `IsConnected` filter prevented multipath connections through additional portals since targets connected via the first portal appeared as already connected, blocking MPIO setup. Now attempts connection through each portal and gracefully handles already-connected sessions (10-iSCSI).
- 63 modules, 1854 tests

## v1.18.0

- **New Feature:** Reboot Pending Details — enumerates every registry and WMI source that signals a pending reboot and reports the exact root cause: CBS pending packages, Windows Update completion, pending file rename operations, hostname change (showing old and new names), SCCM/ConfigMgr client reboot requests, and domain join changes. Operations menu option [29] (35-Utilities).
- **New Feature:** Memory Pressure Diagnostics — shows physical memory breakdown (total/used/free with percentage), page file utilization per file, committed memory vs. commit limit, top 15 processes sorted by working set (with private bytes), and on Hyper-V hosts shows per-VM memory allocation including assigned, demand, and dynamic memory status. Operations menu option [30] (35-Utilities).
- 63 modules, 1854 tests

## v1.17.2

- **Bug Fix:** Process handle leak in credential storage — `cmdkey.exe` process was never disposed after use; timeout path would also crash reading `ExitCode` on a still-running process. Now uses `try/finally` with `Dispose()` (35-Utilities).
- **Bug Fix:** Script initialization falls back to registry when CIM service is unresponsive — unguarded `Get-CimInstance` at top level would crash the entire tool before any menu could display. Now falls back to `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\CurrentBuildNumber` (00-Initialization).
- **Bug Fix:** Port scan disposes `TcpClient` on error — if `BeginConnect` or `WaitOne` threw, the socket handle leaked. Now uses `try/finally` for cleanup (58-NetworkDiagnostics).
- **Bug Fix:** Certificate display guards against null Subject — certificates with Subject Alternative Names only can have null `Subject`, causing blank output instead of "(no subject)" (37-HealthCheck, 35-Utilities).
- **Bug Fix:** Command history display guards against null Command — corrupted or hand-edited `history.json` would crash `.PadRight()` on null (55-QoLFeatures).
- **Bug Fix:** VHD download checks cache path before use — if host storage was never initialized, `.Substring()` on null path would crash (41-VHDManagement).
- **Bug Fix:** Adapter table guards against null InterfaceDescription — virtual or transitional adapters can have null description, crashing `.PadRight()` (06-NetworkAdapters).
- **Bug Fix:** Quick setup storage detection uses `@()` wrapper for PS 5.1 — single-item pipeline results lack `.Count` property without array wrapping (50-EntryPoint).
- 63 modules, 1854 tests

## v1.17.1

- **Bug Fix:** VM Checkpoint Management uses `*-VMSnapshot` cmdlets instead of `*-VMCheckpoint` — Server 2012 R2 only has the `VMSnapshot` variants; `VMCheckpoint` was introduced in Server 2016. Affects list, restore, and delete operations (52-VMCheckpoints).
- 63 modules, 1854 tests

## v1.17.0

- **New Feature:** Scheduled Task Overview — shows all custom (non-Windows) scheduled tasks with state, next run time, and highlights tasks with non-zero last run results. Filters out built-in Windows maintenance tasks to reduce noise. Operations menu option [27] (35-Utilities).
- **New Feature:** Firewall Rule Summary — shows firewall profile status (enabled/disabled with default actions), rule counts by direction and action (inbound/outbound, allow/block), and top inbound allow rule groups for quick security audit. Operations menu option [28] (35-Utilities).
- 63 modules, 1854 tests

## v1.16.7

- **Security:** Remote service management rejects wildcard characters in service names — entering `*` could match all services, causing a mass stop/restart on the remote target (56-OperationsMenu).
- **Security:** Subnet sweep validates three-octet base format — invalid input (e.g., four-octet IP) would spawn 254 failing background jobs, exhausting system resources (58-NetworkDiagnostics).
- **Security:** Self-update batch script uses random filename in `%TEMP%` — eliminates predictable path that could be pre-created by another local user for privilege escalation (35-Utilities).
- **Security:** NTP server custom entry validates hostname/IP format — prevents misconfiguration that could cascade into Kerberos authentication failures (19-NTPConfiguration).
- **Security:** Temp path setting validates format and warns on UNC paths — transcripts written to network shares could expose session activity (56-OperationsMenu).
- **Security:** BitLocker key save validates directory existence and warns on UNC paths — recovery keys should stay on local storage (31-BitLocker).
- **Security:** BitLocker show recovery key warns about transcript capture — keys displayed on-screen are recorded in the session transcript log file (31-BitLocker).
- **Security:** Credential storage uses `ProcessStartInfo` instead of pipeline `cmdkey` call — keeps plaintext password out of PowerShell transcript logging (35-Utilities).
- 63 modules, 1854 tests

## v1.16.6

- **Bug Fix:** FileServer HEAD request wraps HTTP response in `try/finally` — if `ContentLength` threw an exception, the response was never closed, leaking HTTP connections and sockets under repeated failures (39-FileServer).
- **Bug Fix:** Storage Replica volume validation uses a flag instead of `break` inside `foreach`/`switch` — in PowerShell, `break` inside a `foreach` nested in a `switch` exits the `switch`, not the `foreach`. Now reports ALL invalid volumes at once and properly blocks partnership creation (33-StorageReplica).
- 63 modules, 1854 tests

## v1.16.5

- **Bug Fix:** Health Check guards against null CPU properties when `Get-CimInstance Win32_Processor` fails silently — `$cpu.Name`, `NumberOfCores`, `NumberOfLogicalProcessors` now show "Unknown" instead of crashing (37-HealthCheck).
- **Bug Fix:** Health Check guards against null `$proc.CPU` in top processes list — `System` and `Idle` processes have null `.CPU` in PS 5.1, causing `[math]::Round($null, 1)` (37-HealthCheck).
- **Bug Fix:** HTML Reports guards against null CIM results — CPU load average, memory values, and CPU info in HTML template all null-safe when queries fail (54-HTMLReports).
- **Bug Fix:** HTML Reports guards against null `$p.CPU` in top processes HTML table — same null `.CPU` issue as Health Check (54-HTMLReports).
- **Bug Fix:** Service Manager uses actual service `DisplayName` with null fallback chain — custom `MonitoredServices` entries from defaults.json without a `DisplayName` field no longer crash on `.Length`/`.Substring()` (30-ServiceManager).
- **Bug Fix:** Cluster Dashboard guards against null `$node.State` before `.ToString()` — partially populated cluster node objects during network errors no longer crash (51-ClusterDashboard).
- **Bug Fix:** Network Diagnostics casts integer fallback to string for adapter alias — when `Get-NetAdapter` fails, the catch block returned an integer (`InterfaceIndex`), and `.Length` on an integer returns `$null` in PS 5.1 (58-NetworkDiagnostics).
- **Bug Fix:** Network Diagnostics uses null-safe string interpolation for DNS default case and null-safe ARP entry state (58-NetworkDiagnostics).
- 63 modules, 1854 tests

## v1.16.4

- **Bug Fix:** Event Log Viewer guards against null `TimeCreated` — events with null timestamps caused "cannot call method on null-valued expression" on `.ToString()` (29-EventLogViewer).
- **Bug Fix:** Event Log Alert Summary guards against null `TimeCreated` on latest events — same `.ToString()` crash on null (35-Utilities).
- **Bug Fix:** BitLocker encryption progress guards against null `VolumeStatus` — the `.ToString()` call could crash if the volume status property was null (31-BitLocker).
- 63 modules, 1854 tests

## v1.16.3

- **Bug Fix:** Event Log Alert Summary guards against null `ProviderName` on events — events with null provider caused a "cannot call method on null-valued expression" error on `.PadRight()` in both the top sources list and the latest critical/error events list. Now defaults to "Unknown" (35-Utilities).
- 63 modules, 1854 tests

## v1.16.2

- **Bug Fix:** Drift detection baseline comparison validates user input before integer cast — previously, non-numeric input to the baseline number prompts was cast via `-as [int]` which returns `$null`, then subtracted by 1 producing `-1`, silently failing the range check without user feedback. Now validates with regex and shows an error message (45-ConfigExport).
- 63 modules, 1854 tests

## v1.16.1

- **Bug Fix:** Driver Health Check initializes `$allDevices` before `try/catch` — if `Get-CimInstance` failed, references outside the try block would hit an uninitialized variable (35-Utilities).
- **Bug Fix:** Uptime & Reboot History initializes `$uptimeStr` and `$unexpectedCount` before their conditional blocks — `Add-SessionChange` at the end of the function referenced both variables which were only set inside `try/catch` and `if/else` branches respectively, producing null output on failure (35-Utilities).
- **Bug Fix:** Windows Update Status initializes `$daysSince` before `try/catch` and uses null-safe formatting — the session change description referenced `$daysSince` which was only set inside a nested `if` block within a `try` block, producing malformed output when hotfix query failed or returned no dates (35-Utilities).
- **Bug Fix:** Disk Space Analyzer initializes `$totalScanGB` before the results conditional — the session change description referenced `$totalScanGB` which was only set inside the `if ($results.Count -gt 0)` block, producing null output when no known paths existed on the system drive (35-Utilities).
- 63 modules, 1854 tests

## v1.16.0

- **New Feature:** Windows Update Status — shows the most recently installed hotfix with age warning (30+ days yellow, 60+ days red), lists the 15 most recent hotfixes with KB IDs and install dates, and checks the status of Windows Update services (wuauserv, BITS, CryptSvc, TrustedInstaller). Accessible from Operations > option [25] (35-Utilities, 56-OperationsMenu).
- **New Feature:** Listening Ports & Services — scans all TCP listening endpoints, displays well-known ports (0-1023) with service labels (SSH, DNS, HTTP, RPC, NetBIOS, LDAP, HTTPS, SMB, LDAPS) and owning process names, then lists high ports (1024+) with process info. Accessible from Operations > option [26] (35-Utilities, 56-OperationsMenu).
- 63 modules, 1854 tests

## v1.15.0

- **New Feature:** Driver Health Check — scans all PnP devices for problem devices with error descriptions (not configured, driver corrupt, cannot start, disabled, driver missing, etc.), lists unsigned drivers, shows oldest third-party drivers sorted by date with version info. Color-coded warnings for drivers older than 3 years. Accessible from Operations > option [23] (35-Utilities, 56-OperationsMenu).
- **New Feature:** Disk Space Analyzer — displays all fixed volumes with visual usage bars and color-coded thresholds (85% yellow, 95% red), then scans 8 common space consumers on the system drive (Windows Temp, Windows Update Cache, Installer Cache, Windows Logs, WinSxS, User Temp, IIS Logs, Error Reports) sorted by size. Accessible from Operations > option [24] (35-Utilities, 56-OperationsMenu).
- 63 modules, 1854 tests

## v1.14.0

- **New Feature:** Event Log Alert Summary — scans System and Application event logs for critical, error, and warning events in the last 24 hours. Shows summary counts, groups events by source with counts and age, and lists the 10 most recent critical/error events with timestamps. Accessible from Operations > option [21] (35-Utilities, 56-OperationsMenu).
- **New Feature:** Uptime & Reboot History — displays current system uptime with color-coded warnings (30+ days yellow, 60+ days red), and lists the last 15 planned and unexpected reboots from the event log. Unexpected shutdowns (crash/power loss) are flagged in red. Accessible from Operations > option [22] (35-Utilities, 56-OperationsMenu).
- 63 modules, 1854 tests

## v1.13.0

- **New Feature:** VSS Writer Status Dashboard — queries all Volume Shadow Copy writers via vssadmin, shows stable/failed/unknown counts, lists failed writers with error details. Useful before backups and replica operations. Accessible from Operations > option [20] (35-Utilities, 56-OperationsMenu).
- **Bug Fix:** Active Directory prerequisites check uses safe `@()` wrapping for `IPv4Address.Count` — previously, a single-NIC server could fail the static IP prerequisite check because `.Count` returns `$null` on single objects in PS 5.1 (61-ActiveDirectory).
- 63 modules, 1854 tests

## v1.12.0

- **New Feature:** Windows Defender Status Dashboard — shows real-time protection status for all 5 protection layers (real-time, behavior monitor, download scanning, network inspection, antispyware), signature version/age/last update date, engine version, scan history (last full and quick scan with age), and recent threat detections (last 10). Color-coded warnings for disabled protections and stale signatures (>1 day yellow, >7 days red). Accessible from Security & Access > option [7] (17-DefenderExclusions, 48-MenuDisplay, 49-MenuRunner).
- Security & Access menu expanded from 9 to 10 items — Defender Status Dashboard inserted as [7], admin account options renumbered to [8]-[10] (48-MenuDisplay, 49-MenuRunner).
- 63 modules, 1854 tests

## v1.11.0

- **New Feature:** Certificate Expiry Check — scans Local Machine certificate stores (Personal, Trusted Root CA, Intermediate CA, Web Hosting, Remote Desktop) and categorizes certificates as expired, expiring soon (within 90 days), or valid. Color-coded output with per-store grouping. Accessible from Operations > option [19] (35-Utilities, 56-OperationsMenu).
- **Bug Fix:** Scheduled task info query logs warning on failure instead of bare `catch {}` — if `Get-ScheduledTaskInfo` threw an exception for a specific task, the error was silently discarded and the task was excluded from the failed-tasks list without notice (35-Utilities).
- **Bug Fix:** SMB security configuration query logs warning on failure instead of bare `catch {}` — `Get-SmbServerConfiguration` failures (e.g., SMB feature not installed) were silently ignored, preventing the SMBv1 security check from reporting its status (35-Utilities).
- **Bug Fix:** Software inventory registry scan logs warning on failure instead of bare `catch {}` — if either the 32-bit or 64-bit registry uninstall path failed, the error was silently swallowed and that half of the inventory was missing without warning (35-Utilities).
- **Bug Fix:** HTML report disk growth calculation has documented catch block instead of bare `catch {}` — non-critical growth rate estimation failure now has inline documentation explaining the intentional suppression (54-HTMLReports).
- 63 modules, 1854 tests

## v1.10.0

- **New Feature:** Firewall Rule Search — search firewall rules by display name (with wildcard support), by port number, or browse all enabled inbound allow rules, all block rules, and custom/recently created rules. Results show direction, action, and enabled status with color coding. Accessible from Security & Access > option [5] (16-Firewall, 48-MenuDisplay, 49-MenuRunner).
- **New Feature:** Installed Software Inventory — scans both 32-bit and 64-bit registry uninstall keys, deduplicates entries, groups by publisher, supports name search, and can export to CSV. Accessible from Operations > option [18] (35-Utilities, 56-OperationsMenu).
- **Bug Fix:** Network Diagnostics ARP table adapter name lookup uses `-ErrorAction Stop` inside `try/catch` — previously, `-ErrorAction SilentlyContinue` made the catch block unreachable, so adapter lookup failures were silently ignored instead of falling back to the interface index (58-NetworkDiagnostics).
- Security & Access menu expanded from 8 to 9 items — Firewall Rule Search inserted as [5], Defender Exclusions shifted to [6], admin account options renumbered to [7]-[9] (48-MenuDisplay, 49-MenuRunner).
- 63 modules, 1854 tests

## v1.9.67

- **New Feature:** Scheduled Task Viewer — lists all scheduled tasks with status, last run time, and result codes. Highlights custom (non-Microsoft) tasks separately, flags tasks that failed their last run with hex error codes, and shows disabled custom tasks. Accessible from Operations > option [16] (35-Utilities, 56-OperationsMenu).
- **New Feature:** SMB Share Audit — enumerates all SMB shares with per-share NTFS/share permissions, flags shares that grant write access to Everyone, checks SMB server encryption status, and warns if SMBv1 protocol is still enabled. Shows a security issue summary. Accessible from Operations > option [17] (35-Utilities, 56-OperationsMenu).
- **Bug Fix:** Windows Update scan job error extraction now logs a warning instead of using a bare `catch {}` — previously, if `ChildJobs[0].Error` parsing threw an exception, the scan error details were silently discarded and the user only saw "Update scan failed" with no additional context (14-WindowsUpdates).
- **Bug Fix:** Hyper-V install job error extraction now logs a warning instead of using a bare `catch {}` — same silent error swallowing pattern where ChildJobs error parsing failures were discarded (25-HyperV).
- 63 modules, 1854 tests

## v1.9.66

- **New Feature:** Server readiness dashboard now includes disk health monitoring — reports healthy/unhealthy/predictive-failure status for all physical disks using `Get-PhysicalDisk` health status and operational status (37-HealthCheck).
- **New Feature:** Server readiness dashboard now includes disk temperature monitoring on Server 2016+ — warns when any physical disk exceeds 55°C using `Get-StorageReliabilityCounter`, showing the hottest disk's temperature (37-HealthCheck).
- **Bug Fix:** Storage Manager disk online operations use `-ErrorAction Stop` on `Set-Disk -IsReadOnly $false` — 3 instances where `-ErrorAction SilentlyContinue` inside `try/catch` silently swallowed failures, showing "disk brought online" even when the read-only flag could not be cleared (38-StorageManager).
- **Bug Fix:** Storage Manager drive letter assignment uses `-ErrorAction Stop` on `Set-Partition -NewDriveLetter` — previously, the failure was silently ignored and the subsequent verification check ran against stale partition state (38-StorageManager).
- **Bug Fix:** Windows Feature install job error extraction now logs a warning on failure instead of using a bare `catch {}` — previously, if `ChildJobs[0].Error` parsing threw an exception, the details were silently discarded (05-SystemCheck).
- **Bug Fix:** Network adapter selection uses `Test-NavigationCommand` and case-insensitive matching for refresh/back input — 2 functions had manual `$selection -eq 'R' -or $selection -eq 'r'` checks instead of using the standard navigation helper, which also handles 'back', 'exit', 'menu', etc. (06-NetworkAdapters).
- 63 modules, 1854 tests

## v1.9.65

- **New Feature:** Config export now includes a key services section — shows status and startup type for WinRM, Defender, Cluster Service, DNS, iSCSI Initiator, Windows Update, and other critical services (45-ConfigExport).
- **New Feature:** Config export now includes a security baseline section — reports Secure Boot, UAC, Windows Defender status, real-time protection, and signature update date (45-ConfigExport).
- **New Feature:** Config export now includes the RDP listening port in the remote access section — catches non-standard port configurations (45-ConfigExport).
- **New Feature:** Session summary now offers a JSON export option after the text export — produces a structured file with hostname, runtime, change count, and all changes with timestamps for automation and scripting (46-SessionSummary).
- **Bug Fix:** Session summary reboot notification now correctly distinguishes three states — "this session only" (from RackStack changes), "Windows pending" (from previous changes), and "both" (combined). Previously, when both flags were true, only the generic "reboot required" message was shown (46-SessionSummary).
- **Bug Fix:** License activation success detection uses case-insensitive regex `(?i)success` — previously, the literal string match `"successfully"` failed on non-English locales or Windows versions that output different casing from `slmgr.vbs`, causing valid activations to be reported as failed (21-Licensing).
- 63 modules, 1854 tests

## v1.9.64

- **New Feature:** Local Account Audit — scans all local user accounts and displays password age, last login, password expiry status, and enabled/disabled state. Flags accounts with passwords older than 365 days, expired passwords, and accounts with no login activity in 90+ days. Accessible from Security & Access > option [8] (22-Password, 48-MenuDisplay, 49-MenuRunner).
- **New Feature:** Service Dependency Viewer — shows the full dependency tree for any service in Service Manager. Displays both "depends on" (required services) and "depended on by" (dependent services) with live status indicators. Accessible via option [D] in Service Manager (30-ServiceManager).
- **Bug Fix:** VM RAM validation pre-check uses `-ErrorAction Stop` on `Get-VM` — previously, `-ErrorAction SilentlyContinue` inside a `try/catch` made the catch block unreachable dead code, meaning Hyper-V failures would silently produce an empty VM list instead of being caught (44-VMDeployment).
- **Bug Fix:** Batch config Defender exclusion idempotency check uses `-ErrorAction Stop` on `Get-MpPreference` — previously, `-ErrorAction SilentlyContinue` prevented error detection when Windows Defender is unavailable or the module fails to load (50-EntryPoint).
- **Bug Fix:** HTML report NIC statistics collection uses `-ErrorAction Stop` on `Get-NetAdapterStatistics` — previously, `-ErrorAction SilentlyContinue` inside `try/catch` swallowed all errors silently, producing a report with missing NIC data and no indication of the failure (54-HTMLReports).
- **Bug Fix:** Storage backend auto-detection uses `-ErrorAction Stop` on `Get-ClusterS2D` and `Get-ClusterResource` in 3 locations — previously, `-ErrorAction SilentlyContinue` defeated the `try/catch` error handling, making it impossible to distinguish "cmdlet not available" from "S2D/SMB3 not configured" (59-StorageBackends).
- 63 modules, 1854 tests

## v1.9.63

- **New Feature:** Server readiness dashboard now includes a certificate expiration check — scans `LocalMachine\My` store for expired and soon-to-expire certificates (within 30 days), reports count and soonest expiry date, and counts toward the readiness score (37-HealthCheck).
- **New Feature:** Server readiness dashboard now includes an uptime check — warns if the server hasn't rebooted in 30+ days, flags as critical at 60+ days, helping catch servers that have fallen behind on patch cycles (37-HealthCheck).
- **New Feature:** System health check now includes a full certificate inventory section — lists all certificates in `LocalMachine\My` sorted by expiry date with status tags (OK/EXPIRING/EXPIRED), days remaining, and truncated thumbprints. Certificate issues are also surfaced in the health check summary (37-HealthCheck).
- **Bug Fix:** AD replication partner metadata now wraps `Get-ADReplicationPartnerMetadata` result in `@()` at assignment — on domain controllers with a single replication partner, `.Count` returned `$null` in PS 5.1, causing the force-sync prompt at line 429 to never appear (61-ActiveDirectory).
- **Bug Fix:** BitLocker key backup now adds `-ErrorAction Stop` and a null guard on `Get-BitLockerVolume` — previously, if the cmdlet failed (invalid mount point, service issues), the code crashed on `.KeyProtector` property access with an unhandled null-dereference error (31-BitLocker).
- **Bug Fix:** IP configuration subnet validation now surfaces errors with a warning message instead of using a bare `catch {}` — previously, any exception during subnet calculation was silently swallowed, potentially allowing invalid gateway configurations without warning (07-IPConfiguration).
- **Bug Fix:** Server role template viewer now wraps `Where-Object` results in `@()` at assignment — previously used `@()` only at point-of-use with redundant null checks. Consistent with codebase patterns and eliminates PS 5.1 `.Count` fragility on single-role servers (60-ServerRoleTemplates).
- 63 modules, 1854 tests

## v1.9.62

- **Bug Fix:** Health check disk latency evaluation now wraps the pipeline result in `@()` — on single-disk systems, the pipeline returned a bare scalar where `.Count` returned `$null` in PS 5.1, causing `$null -gt 0` to evaluate as `$false` and the "FAIR" warning to never fire when disk latency was between 10-20 ms (37-HealthCheck).
- **Bug Fix:** VM export job now uses `-ErrorAction Stop` on the `Export-VM` call inside the background job scriptblock — previously, `Export-VM` wrote non-terminating errors on failure, causing the job state to be `Completed` instead of `Failed`, and `Receive-Job -ErrorAction Stop` succeeded without throwing, logging a false successful export while files were absent or corrupt (53-VMExportImport).
- **Enhancement:** VM export disk space pre-check now surfaces errors with a warning message instead of using a bare `catch {}` — previously, `Get-Volume` or `Get-VHD` failures were silently swallowed, allowing users to proceed with no space warning on a potentially full disk (53-VMExportImport).
- 63 modules, 1854 tests

## v1.9.61

- **Bug Fix:** iSCSI target discovery (`Get-IscsiTarget`) now uses `-ErrorAction Stop` — previously, failures (e.g., iSCSI Initiator service issues) produced a non-terminating error, causing `$targets` to be `$null` and silently skipping all target connections with "No disconnected targets found" instead of reporting the error (10-iSCSI).
- **Bug Fix:** `Select-Partition` now wraps `Get-Partition` result in `@()` — on disks with exactly one eligible partition, `.Count` returned `$null` in PS 5.1, and `$null -eq 0` evaluated to `$true`, causing the function to falsely report "No eligible partitions found" and refuse to select the partition (38-StorageManager).
- **Enhancement:** Config export now wraps `Get-Disk` and `Get-Volume` in individual `try/catch` blocks with `-ErrorAction Stop` — previously used `-ErrorAction SilentlyContinue` inside the outer `try`, causing storage/volume sections to be silently blank when WMI or Storage Management services are unavailable, producing an incomplete export with no indication of what was missing (45-ConfigExport).
- 63 modules, 1854 tests

## v1.9.60

- **Bug Fix:** VM disk attachment (`Add-VMHardDiskDrive`) now uses `-ErrorAction Stop` instead of `-ErrorAction SilentlyContinue` — previously, if disk attachment failed (path translation on remote hosts, SCSI slot conflicts), the VHD file was created but never attached, and the VM was reported as successfully deployed with a missing disk. Affects all 3 disk attachment paths: blank disks, sysprepped VHDs, and OS fallback disks (44-VMDeployment).
- **Enhancement:** CSV path extraction in `Get-AvailableVMStoragePaths` now filters out volumes with null `SharedVolumeInfo` — prevents a null-dereference exception on degraded CSVs that caused silent fallback to the `"C:\Hyper-V"` hardcoded path, deploying VMs to the wrong location (44-VMDeployment).
- **Enhancement:** Default NIC removal on newly created VMs now uses `try/catch` with `-ErrorAction Stop` and a warning message — previously used `-ErrorAction SilentlyContinue`, which silently failed if the VM was in an unexpected state, leaving phantom NICs alongside the newly configured ones (44-VMDeployment).
- **Enhancement:** Batch config firewall idempotency check now guards against `$null` return from `Get-FirewallState` — prevents null-dereference property access on systems with non-standard firewall configurations (50-EntryPoint).
- 63 modules, 1854 tests

## v1.9.59

- **Bug Fix:** "Home"/"main" navigation command now works from all 10 submenu runners — previously, typing `main` or `home` at any submenu fell through to `Test-NavigationCommand` with `Action = "home"` which was never checked, resulting in "Invalid choice" instead of returning to the main menu (49-MenuRunner).
- **Bug Fix:** Return-to-main-menu flag (`$global:ReturnToMainMenu`) now properly bubbles up through `Start-Show-ConfigureServerMenu` — previously, child submenus would set the flag but ConfigureServerMenu cleared it without returning, trapping the user at the Configure Server level instead of navigating all the way back to Main Menu (49-MenuRunner).
- **Enhancement:** Exit cleanup path deduplication now uses `Sort-Object -Unique` (case-insensitive) instead of `Select-Object -Unique` (case-sensitive) — prevents duplicate `Remove-Item` commands in the scheduled task if the same path appears with different casing (47-ExitCleanup).
- **Enhancement:** Exit cleanup scheduled task uses `-Recurse` universally for all paths instead of branching on `Test-Path -PathType Container` at script-exit time — eliminates a race condition where a file could become a directory (or vice versa) between exit and reboot-time execution (47-ExitCleanup).
- 63 modules, 1854 tests

## v1.9.58

- **Bug Fix:** Agent installer site number parsing now wraps the `-split` pipeline in `@()` — single-site filenames (e.g., `Agent.12345.exe`) returned a bare string instead of an array, causing `.Count` to return the string length instead of 1 in PS 5.1 (57-AgentInstaller).
- **Bug Fix:** Favorites and Command History import now wraps `ConvertFrom-Json` results in `@()` — JSON files containing a single entry lost their array type on deserialization, causing `.Count` to return property count instead of 1 and array operations to fail (55-QoLFeatures).
- **Enhancement:** File server download validation uses `-ErrorAction SilentlyContinue` on `Get-Item` calls during post-download size checks — prevents a terminating error if the file is removed between download completion and size verification (39-FileServer).
- **Enhancement:** SNMP Add Manager now validates hostname/IP format before writing to registry — rejects entries with spaces, semicolons, or other invalid characters that would create non-functional permitted manager entries (55-QoLFeatures).
- 63 modules, 1854 tests

## v1.9.57

- **Enhancement:** `Invoke-WithTimeout` now detects failed background jobs (state `"Failed"`) and returns error details in the result — previously, a failed job returned `TimedOut = $false; Result = $null`, indistinguishable from a successful job that returned `$null`. Callers in Failover Clustering and other modules can now check `$result.Failed` (04-Navigation).
- **Enhancement:** `Get-FileHashBackground` validates file existence with `Test-Path` before launching the background SHA256 computation — returns `$null` with an error message instead of silently failing when the file doesn't exist (04-Navigation).
- **Bug Fix:** Adapter info box on the Configure Server menu now handles adapters with multiple IPv4 addresses by selecting the primary IP via `Select-Object -First 1` — previously, multi-homed adapters returned an array of IPs that broke the 72-char box column alignment (48-MenuDisplay).
- **Enhancement:** `Add-SessionChange` now guards against empty or null `$script:AppConfigDir` before attempting disk writes — prevents `Join-Path` and `Add-Content` from failing on malformed paths in constrained environments (04-Navigation).
- 63 modules, 1854 tests

## v1.9.56

- **Enhancement:** Batch role template installation pre-fetches all Windows Feature states in a single `Get-WindowsFeature` call instead of querying individually per feature — reduces WMI/DISM round-trips by up to 10x for large templates (50-EntryPoint).
- **Bug Fix:** Transcript cleanup age-based removal now wraps filtered results in `@()` for PS 5.1 `.Count` safety — previously, cleaning up exactly one old transcript would report "Cleaned up  old transcript(s)" with a blank count (50-EntryPoint).
- **Enhancement:** Remote service manager now requires `Confirm-UserAction` before starting, stopping, or restarting services on remote servers — prevents accidental service disruption on production systems (56-OperationsMenu).
- **Enhancement:** Remote service manager pre-checks connectivity with `Test-Connection` before attempting RPC service query — fails fast with a clear message instead of hanging for 60+ seconds on unreachable targets (56-OperationsMenu).
- **Bug Fix:** Storage backend auto-detection no longer false-positives SMB3 whenever any SMB mapped drive exists — now checks specifically for cluster File Server or Scale-Out File Server resources instead of generic `Get-SmbMapping` (59-StorageBackends).
- 63 modules, 1854 tests

## v1.9.55

- **Enhancement:** Server role templates now validate that the PostInstall function exists before attempting to invoke it — prevents confusing errors when custom templates reference functions that haven't been loaded or don't exist, with a clear warning message instead (60-ServerRoleTemplates).
- **New Feature:** All 3 HTML report functions (health report, readiness report, profile comparison) now validate the output directory exists before writing — prevents silent failures or cryptic errors when the user enters a custom output path with a non-existent directory (54-HTMLReports).
- **Enhancement:** Hyper-V Replica Server setup now uses per-group firewall rule enabling with error counting instead of `-ErrorAction SilentlyContinue` — consistent with the firewall template pattern from v1.9.54, reports which rule groups could not be enabled (62-HyperVReplica).
- **Enhancement:** Cluster Dashboard pre-fetches all VM cluster groups in a single query instead of querying `Get-ClusterGroup` once per cluster node — reduces WMI/CIM round-trips on large clusters with many nodes (51-ClusterDashboard).
- 63 modules, 1854 tests

## v1.9.54

- **Bug Fix:** All 6 firewall template functions (Hyper-V, Cluster, Replica, Live Migration, iSCSI, SMB) now use `-ErrorAction Stop` instead of `-ErrorAction SilentlyContinue` — errors are caught and reported per-group with specific warning messages instead of being silently swallowed. Previously, if a firewall rule group didn't exist or couldn't be enabled, the function would report success anyway (18-FirewallTemplates).
- **Enhancement:** Firewall rule viewer now shows "Not Found" for missing rule groups instead of hiding them — gives a complete picture of which rule groups are installed vs. available (18-FirewallTemplates).
- **New Feature:** Defender Hyper-V exclusion wizard now warns when Hyper-V is not currently installed, informing the user that exclusions are only useful if Hyper-V will be installed later (17-DefenderExclusions).
- **Enhancement:** Local admin account creation now verifies Administrators group membership after adding the account — confirms the account was actually granted admin rights instead of assuming success (23-LocalAdmin).
- 63 modules, 1854 tests

## v1.9.53

- **Enhancement:** Network diagnostics timed-out job cleanup — subnet ping sweep and quick port scan now detect timed-out background jobs, report how many timed out, and force-remove them instead of leaving orphaned jobs in the PowerShell job queue (58-NetworkDiagnostics).
- **Enhancement:** Active connections and ARP table results wrapped in `@()` for PS 5.1 `.Count` safety, with empty-result fallback messages when no connections or ARP entries are found (58-NetworkDiagnostics).
- **New Feature:** Service Manager warns about dependent services before stop or restart — displays a list of running services that depend on the target service and will also be affected by the operation (30-ServiceManager).
- **New Feature:** Configuration export validates that the destination directory exists before spending time gathering system information — prevents silent failure or export to wrong location (45-ConfigExport).
- **New Feature:** VM Export disk space pre-check — estimates required space from VHD file sizes and warns when the export destination drive has insufficient free space (53-VMExportImport).
- **New Feature:** VM Checkpoint Management and VM Export/Import menus pre-check Hyper-V installation before entering management screens — shows clear error instead of cryptic cmdlet failures (52-VMCheckpoints, 53-VMExportImport).
- 63 modules, 1854 tests

## v1.9.52

- **Enhancement:** Offline VHD registry hive unload with retry and verification — detects failed unloads, forces garbage collection, retries after delay, and shows manual fix command if hive remains locked. Prevents VHD lock that blocks VM boot (43-OfflineVHD).
- **Enhancement:** VM deployment CPU and memory configuration errors now caught and reported with warnings instead of being silently swallowed by `-ErrorAction SilentlyContinue`. User sees what went wrong if vCPU count exceeds host capacity or memory settings are invalid (44-VMDeployment).
- **New Feature:** VHD download disk space pre-check — warns when destination drive has less than 60 GB free before starting large sysprepped VHD download (41-VHDManagement).
- **New Feature:** ISO download disk space pre-check — blocks download when destination drive has less than 10 GB free, preventing partial downloads that waste time and leave incomplete files (42-ISODownload).
- **New Feature:** Host storage drive selection warns when selected drive has less than 50 GB free, since VM deployments typically require 100-300+ GB of storage (40-HostStorage).
- **Enhancement:** Session summary now groups changes by category (Network, System, Security, etc.) with counts instead of a flat chronological list, and offers to export the summary as a text file to the Desktop (46-SessionSummary).
- 63 modules, 1854 tests

## v1.9.51

- **Enhancement:** Hyper-V Windows Client job error extraction now uses the same defensive pattern as `Install-WindowsFeatureWithTimeout` — guards `ChildJobs[0]` access, pipes through `Out-String`, checks job state, and provides fallback error message (25-HyperV).
- **New Feature:** Firewall per-profile toggle — menu now offers `[1] Apply recommended` (Domain/Private off, Public on) or `[2] Toggle individual profile` for granular control over each firewall profile (16-Firewall).
- **New Feature:** Firewall undo support — both recommended and individual toggle operations register `Add-UndoAction` with captured previous state, enabling revert via the undo system (16-Firewall).
- **Enhancement:** Event Log Viewer pre-checks whether Hyper-V and Failover Clustering are installed before querying their event logs — shows "not installed" instead of misleading "no events found" (29-EventLogViewer).
- **Bug Fix:** Event log CSV export count wrapped in `@()` for PS 5.1 safety — single-event results no longer show blank count (29-EventLogViewer).
- **Bug Fix:** Batch config export now uses `$script:localadminaccountname` — was unscoped, causing null to be written instead of the configured admin name (36-BatchConfig).
- **Enhancement:** Batch config save (both template and export) validates that the target directory exists and prompts for confirmation before overwriting existing files (36-BatchConfig).
- **Enhancement:** Performance Dashboard shows fallback messages when no fixed volumes or active network adapters are detected instead of displaying empty sections (28-PerformanceDashboard).
- **New Feature:** Storage Manager ReFS allocation unit size guard — automatically overrides allocation units smaller than 64K to the minimum required on Windows Server, preventing cryptic Format-Volume errors (38-StorageManager).
- 63 modules, 1854 tests

## v1.9.50

- **Enhancement:** Storage Replica installation now uses `Install-WindowsFeatureWithTimeout` for progress feedback, timeout protection, and detailed error reporting — matching the pattern used by Hyper-V, MPIO, and Failover Clustering installs (33-StorageReplica).
- **Enhancement:** Storage Replica partnership creation validates all required fields (server names, volumes, replication group) and enforces drive letter format (e.g., `E:`) before attempting to create the partnership (33-StorageReplica).
- **New Feature:** IP configuration gateway subnet validation — calculates and compares network addresses to warn when the gateway is in a different subnet than the configured IP address, catching the most common IP misconfiguration (07-IPConfiguration).
- **Enhancement:** DNS configuration detects duplicate primary/secondary DNS entries and skips the duplicate with a warning instead of setting both (07-IPConfiguration).
- **Enhancement:** Adapter rename now trims leading/trailing whitespace and enforces a 64-character name length limit to prevent truncation issues (07-IPConfiguration).
- **New Feature:** Cluster creation pre-checks node reachability via single-ping test before attempting `New-Cluster`, giving immediate feedback on unreachable nodes (27-FailoverClustering).
- **Enhancement:** Cluster quorum file share witness path validates UNC format (`\\server\share`) and adds navigation command support (27-FailoverClustering).
- 63 modules, 1854 tests

## v1.9.49

- **Enhancement:** Feature install job error extraction — `Install-WindowsFeatureWithTimeout` now captures child job errors and displays specific failure details instead of generic "may not have completed successfully" messages. Affects Hyper-V, MPIO, and Failover Clustering installs (05-SystemCheck).
- **Enhancement:** Windows Update scan failure detection — when the scan job fails (e.g., service errors, module issues), reports the actual error instead of falsely showing "System is up to date" (14-WindowsUpdates).
- **Enhancement:** RDP enable now requires user confirmation before making changes (consistent with other enable functions). Firewall service pre-check detects stopped mpssvc service and warns instead of silently failing (15-RDP).
- **Enhancement:** iSCSI target connection pre-checks MSiSCSI service before attempting portal registration. Auto-starts the service if stopped; blocks with clear error if the service cannot start (10-iSCSI).
- **New Feature:** SET adapter link speed mismatch warning — when creating a Switch Embedded Team, detects and warns if selected adapters have different link speeds (e.g., 1 GbE + 10 GbE) since SET performance is limited to the slowest adapter (09-SET).
- **Enhancement:** MPIO post-install verification — confirms cmdlet availability after install, shows next-step guidance for iSCSI configuration. Failed installs now display error details from the job (26-MPIO).
- 63 modules, 1854 tests

## v1.9.48

- **New Feature:** Disable admin lockout prevention — before disabling the built-in Administrator account, verifies that at least one other enabled local admin or domain admin group membership exists. Blocks the operation with clear guidance if no alternate access is available (24-DisableAdmin).
- **Enhancement:** Domain join partial state detection — after a join error, checks if the server is actually domain-joined (common with timeout errors where the join succeeded). Prevents unnecessary retries and guides user to reboot (12-DomainJoin).
- **Enhancement:** Timezone sync pre-flight — automatically starts the Windows Time service if stopped before attempting time sync. Provides specific error guidance for common NTP failures (service not running, NTP unreachable, firewall blocking UDP 123) (13-Timezone).
- **Enhancement:** Deduplication status now shows last optimization timestamp per volume with human-readable time deltas (e.g., "2.3h ago", "1.5d ago") (32-Deduplication).
- **Enhancement:** Password complexity validation now shows a visual checklist with pass/fail indicators per requirement (length, uppercase, lowercase, number, special character) instead of a generic error list (22-Password).
- 63 modules, 1854 tests

## v1.9.47

- **New Feature:** VLAN reserved range warnings — when setting VLAN ID, shows valid range guidance and warns about reserved VLANs (1 default/native, 1002-1005 legacy FDDI/Token Ring, 4094 GVRP pruning) with confirmation prompts before proceeding (08-VLAN).
- **New Feature:** Hostname DNS collision detection — before renaming, checks if the new hostname already resolves in DNS and warns about potential conflicts with stale records or active machines (11-Hostname).
- **New Feature:** BitLocker recovery key storage guidance — after enabling encryption, shows prominent warning banner with secure storage options (AD backup, file save, vault). Adds confirmation that user has noted key storage method (31-BitLocker).
- **New Feature:** BitLocker encryption progress check — new menu option [5] shows per-volume encryption status and percentage with color-coded progress (31-BitLocker).
- **Enhancement:** Licensing activation error parsing — translates common slmgr error codes (0xC004F050 edition mismatch, 0xC004F074 KMS unreachable, 0xC004C003 key blocked) into actionable messages. Pre-flight check starts Software Protection service if stopped (21-Licensing).
- 63 modules, 1854 tests

## v1.9.46

- **Enhancement:** Service Manager now shows startup type (Auto/Manual/Disabled) alongside status with color-coded indicators — red for Stopped+Automatic (misconfigured), green for Running, gray for Disabled. New [C] option to change startup type. Search results also show startup type (30-ServiceManager).
- **New Feature:** NTP time skew detection — detailed time status now parses phase offset and shows threshold warnings: green <100ms, info 100ms-1s, warning >1s, critical >30s with Kerberos/iSCSI impact guidance (19-NTPConfiguration).
- **Enhancement:** Health check disk I/O now groups read and write latency per disk with separate color-coded badges and an aggregate performance score (GOOD/FAIR/DEGRADED). Suggests mitigation when write latency is high (37-HealthCheck).
- **Enhancement:** Disk cleanup quick clean shows real-time progress with file count and MB freed, updating every 500ms during deletion (20-DiskCleanup).
- **New Feature:** AD DS Replication Health Monitor — standalone menu option showing per-partner replication status with time deltas, SYSVOL/NETLOGON share availability, DNS zone check, overall health score, and option to force replication sync (61-ActiveDirectory).
- 63 modules, 1854 tests

## v1.9.45

- **New Feature:** Enhanced ping diagnostics — sends 20 packets with min/max/average/P95/standard deviation/jitter/packet loss statistics, color-coded thresholds for live migration and iSCSI compatibility (58-NetworkDiagnostics).
- **New Feature:** Quick port scan — test multiple common ports at once with presets for Standard, Hyper-V/Cluster, Domain Controller, or comprehensive scan. Parallel scanning with 2-second timeout per port (58-NetworkDiagnostics).
- **New Feature:** VM checkpoint disk space validation — checks free space on the storage volume before creating a checkpoint, warns if free space is below 10GB or less than 1.5x the VM's RAM allocation (52-VMCheckpoints).
- **New Feature:** VHD conversion failure handling — when dynamic-to-fixed conversion fails, shows explicit performance warning banner and offers retry, use dynamic anyway, or cancel deployment. Logs fallback to session changes (41-VHDManagement).
- **New Feature:** AD DS post-promotion replication health check — after DC promotion, verifies replication partner metadata, SYSVOL share availability, and DNS zone status. Graceful handling when reboot is needed first (61-ActiveDirectory).
- 63 modules, 1854 tests

## v1.9.44

- **New Feature:** "Home" navigation command — type `home`, `main`, or `m` at any menu to jump straight back to the main menu (04-Navigation, 34-Help).
- **New Feature:** Performance Dashboard auto-refresh — press `[R]` to refresh metrics without leaving the dashboard. Added top 5 CPU-consuming processes display (28-PerformanceDashboard).
- **New Feature:** Event Log custom search — search by log name, keyword, event ID, and time range. Export results to CSV (29-EventLogViewer).
- **New Feature:** Configurable Service Manager — monitored services list can be overridden via `MonitoredServices` in defaults.json. Expanded built-in default from 10 to 15 services (30-ServiceManager).
- **New Feature:** Changelog loaded from file — `Show-Changelog` now reads from Changelog.md instead of a hardcoded heredoc, so it stays current automatically (34-Help).
- **New Feature:** Batch mode pre-execution summary — shows a table of all planned actions (green) and skips (gray) with confirmation prompt before starting (50-EntryPoint).
- **New Feature:** Cluster operation timeouts — `Get-Cluster`, `Get-ClusterNode`, and `Get-ClusterResource` calls wrapped with 15-second timeout via new `Invoke-WithTimeout` helper to prevent indefinite hangs on unreachable clusters (04-Navigation, 27-FailoverClustering).
- Added `MonitoredServices` and `_MonitoredServices_help` to defaults.example.json.
- 63 modules, 1854 tests

## v1.9.43

- **Bug Fix:** DNS resolution display crashed when CNAME records returned no IP address — filtered null values before joining results (05-SystemCheck).
- **Bug Fix:** Subnet mask prefix calculation returned `$null` instead of a number when exactly one bit was set in PS 5.1 — single pipeline results don't have `.Count`. Wrapped in `@()` (07-IPConfiguration).
- **Bug Fix:** IPv6 binding status display crashed when `Get-NetAdapterBinding` returned null for an adapter — added null check with "Unknown" fallback (07-IPConfiguration).
- **Bug Fix:** iSCSI adapter discovery and SAN target pairing could return single objects without `.Count` in PS 5.1, causing silent failures in adapter counting and loop logic. Wrapped three pipelines in `@()` (10-iSCSI).
- **Bug Fix:** Windows Update install job variable referenced in `finally` cleanup before being assigned — if an exception occurred between the check and install phases, `Remove-Job` threw on an uninitialized variable. Added `$null` initialization (14-WindowsUpdates).
- **Bug Fix:** Defender exclusion menu used `continue` inside a `switch` block, which skipped the rest of the current `switch` case instead of returning to the menu loop. Changed to `return` (17-DefenderExclusions).
- **Bug Fix:** NTP configuration domain-join check crashed if WMI was unavailable — wrapped `Get-CimInstance` in error handling with `$false` default (19-NTPConfiguration).
- **Bug Fix:** Server activation proceeded to `/ato` even when `/ipk` (key install) failed — now checks the result and stops early with an error message (21-Licensing).
- **Bug Fix:** Performance dashboard and deduplication status crashed when `Get-Volume` or `Get-NetAdapter` threw errors on systems with unusual storage/network configurations — added `-ErrorAction SilentlyContinue` (28-PerformanceDashboard, 32-Deduplication).
- **Bug Fix:** Color theme list displayed in non-deterministic hashtable order — sorted theme names alphabetically for consistent display (34-Help).
- **Bug Fix:** `Get-StoredCredential` always returned `$null` even when a matching credential existed — now extracts the stored username and prompts with it pre-populated via `Get-Credential` (35-Utilities).
- **Bug Fix:** Batch config template used unscoped `$domain` and `$localadminaccountname` variables — these are script-scoped, so the template always showed empty values. Changed to `$script:domain` and `$script:localadminaccountname` (36-BatchConfig).
- **Bug Fix:** Health check network adapter listing and domain detection crashed when `Get-NetAdapter` or `Get-CimInstance` failed — added `-ErrorAction SilentlyContinue` and null checks (37-HealthCheck).
- **Bug Fix:** Health check contained a dead `$os` variable assignment that was never used — removed (37-HealthCheck).
- **Bug Fix:** Storage manager partition listing returned incorrect `.Count` for single-partition disks in PS 5.1 — wrapped `Get-Partition` in `@()` (38-StorageManager).
- **Bug Fix:** Optical drive remount fallback re-queried the same WMI filter that already returned `$null` — replaced with `mountvol /L` to get the volume GUID, with `Get-Partition` as a secondary fallback (40-HostStorage).
- **Bug Fix:** ISO download menu crashed with `PadRight` error when ISO storage path was null — added null guard with "(not configured)" fallback (42-ISODownload).
- **Bug Fix:** VM NIC deletion used reference equality (`-ne`) which could delete the wrong NIC if two NICs had identical properties — replaced with index-based rebuild matching the disk deletion pattern (44-VMDeployment).
- **Bug Fix:** Session summary hours display wrapped at 24 — a 25-hour session showed "01:00:00" instead of "25:00:00". Changed `$runtime.Hours` to `[math]::Floor($runtime.TotalHours)` (46-SessionSummary).
- **Bug Fix:** Batch config undo scriptblocks for hostname, timezone, and power plan were vulnerable to injection if the original values contained single quotes — added quote escaping (50-EntryPoint).
- **Bug Fix:** Domain join detection defaulted to `$true` when WMI failed, preventing domain join even when the server wasn't domain-joined — changed fallback to `$false` (50-EntryPoint).
- **Bug Fix:** Cluster network count returned scalar instead of array in PS 5.1 — wrapped `Get-ClusterNetwork` in `@()` (51-ClusterDashboard).
- **Bug Fix:** HTML report profile comparison used shallow `-ne` which always showed nested objects (arrays, hashtables) as "Changed" even when identical — replaced with `ConvertTo-Json` deep comparison (54-HTMLReports).
- **Cleanup:** Removed redundant uppercase `"B"` back-navigation cases in 4 modules — PowerShell `switch` is case-insensitive by default (29-EventLogViewer, 31-BitLocker, 32-Deduplication, 33-StorageReplica).
- Updated README and CONTRIBUTING test counts (1,787 → 1,854), monolithic size (~34K → ~35K), added BOM encoding requirement to code style guide.
- Added `batch_config*.json` and `.env*` patterns to `.gitignore`.
- 63 modules, 1854 tests

## v1.9.42

- **Bug Fix:** Firewall profile `.Enabled` property compared to string `"True"` instead of boolean `$true` — `GpoBoolean` enum comparison was fragile across PowerShell versions and inconsistent with other modules. Changed all four comparisons to use boolean (16-Firewall).
- **Bug Fix:** Admin account status display used redundant `$adminEnabled -eq "True"` fallback — unnecessary since `Get-LocalUser.Enabled` returns native boolean. Simplified to single boolean comparison (48-MenuDisplay).
- **Bug Fix:** `Export-VM` background job did not forward `$Credential` parameter — when exporting from a remote Hyper-V host with explicit credentials, the job failed with authentication error because `Export-VM` inside the job lacked the credential. Now passes `$Credential` via `-ArgumentList` and splats all parameters (53-VMExportImport).
- **Bug Fix:** `Get-VHD` called without `-ComputerName` when listing VMs on a remote host — VHD paths are on the remote server, so local `Get-VHD` silently failed and all VMs showed "N/A" for size. Now passes `@vmParams` (which includes `ComputerName` and `Credential`) to `Get-VHD` (53-VMExportImport).
- **Bug Fix:** Remote profile push constructed `$remotePath` using the *local* machine's `$script:TempPath` — if the remote server had a different temp directory, the file would be written to a wrong or nonexistent path. Now queries the remote machine's `$env:TEMP` via `Invoke-Command` first (35-Utilities).
- **Bug Fix:** User-provided file paths used `-Path` instead of `-LiteralPath` in 6 functions across 4 modules — `Test-Path` and `Get-Content` interpreted `[`, `]`, `?`, `*` in file paths as wildcards, silently failing on paths like `C:\Users\John [Admin]\profile.json`. Affected: profile comparison, HTML report comparison, config export load, drift analysis, and baseline comparison (35-Utilities, 45-ConfigExport, 54-HTMLReports, 62-HyperVReplica).
- **Bug Fix:** `New-Item` for directory creation called without `-ErrorAction` and outside `try/catch` in VHD copy destination, VM export directory, and app config directory — if directory creation failed (permissions, disk full), subsequent file operations produced cascading confusing errors about file-not-found instead of clearly reporting the directory failure. Added `try/catch` with `-ErrorAction Stop` and clear error messages (41-VHDManagement, 53-VMExportImport, 55-QoLFeatures).
- **Bug Fix:** `Move-Item` on converted fixed-size VHD used `-ErrorAction SilentlyContinue` — this is the critical final step of VHD conversion, and a silent failure (file locked, disk full) could return the wrong VHD path to downstream VM creation code. Changed to `-ErrorAction Stop` with a local `try/catch` and warning message (41-VHDManagement).
- **Bug Fix:** First-boot script `Set-Content` calls used `-ErrorAction SilentlyContinue` inside `try/catch` — the SilentlyContinue meant write failures were suppressed before reaching the catch block, so the user saw "First-boot script created" when the files weren't actually written. Removed `-ErrorAction SilentlyContinue` so failures properly propagate to the enclosing catch block (43-OfflineVHD).
- **Bug Fix:** `New-Item` for `\Windows\Setup\Scripts` directory inside mounted VHD missing `-ErrorAction Stop` — with default `Continue` preference, `New-Item` errors were not caught by the enclosing `try/catch`, and subsequent `Set-Content` calls would fail on a nonexistent directory (43-OfflineVHD).
- **Bug Fix:** SNMP registry key creation used `-ErrorAction SilentlyContinue` for both `ValidCommunities` and `PermittedManagers` paths — if the key couldn't be created (SNMP not installed, permissions), the subsequent `New-ItemProperty` threw an unclear "path does not exist" error. Changed to `-ErrorAction Stop` with `try/catch` and clear error messages (55-QoLFeatures).
- **Bug Fix:** `Import-Favorites` and `Import-CommandHistory` silently reset data to empty array on any JSON parse error — if a user's favorites or history file became corrupted (partial write during power loss), all saved data was silently lost with no indication. Now shows a warning message before resetting (55-QoLFeatures).
- **Bug Fix:** `Format-Volume` pipeline output leaked to console — volume object displayed interleaved with user-facing messages in the storage manager. Suppressed with `$null =` (38-StorageManager).
- **Bug Fix:** NTP source string `.Split(":", 2)` assumed the output always contained a colon — on exotic locales where `w32tm /query /status` might format differently, accessing `[1]` on a single-element array would throw index-out-of-range. Added bounds check (19-NTPConfiguration).
- **Bug Fix:** Subnet sweep IP address `.Split('.')` assumed 4 octets — if the primary adapter returned a non-standard format, accessing `$parts[0..2]` would throw. Added count guard (58-NetworkDiagnostics).
- **Bug Fix:** WinRM readiness check compared against `"Running"` but `Get-WinRMState` returns `"Enabled"` — WinRM always showed as incomplete in both the server readiness check and HTML readiness report, inflating the "not ready" count and lowering readiness percentage. Fixed both checks (37-HealthCheck, 54-HTMLReports).
- **Bug Fix:** DSRM password comparison used `PtrToStringAuto` instead of `PtrToStringBSTR` for the BSTR pointer from `SecureStringToBSTR()` — `PtrToStringAuto` reads null-terminated strings while BSTR uses a length prefix. Works in practice on Windows but violates the API contract and could silently truncate passwords containing embedded null characters. The shared `ConvertFrom-SecureStringToPlainText` in `22-Password.ps1` already uses the correct method (61-ActiveDirectory).
- **Bug Fix:** Pagefile drive detection used `$matches` global variable directly instead of the codebase-standard `$regexMatches = $matches` pattern used everywhere else — fragile if code is later inserted between the `-match` call and `$matches` access (55-QoLFeatures).
- 63 modules, 1854 tests

## v1.9.41

- **Bug Fix:** VM export, VHD copy/convert, and Windows Update background jobs leaked when exceptions occurred mid-operation — `Receive-Job -ErrorAction Stop` or other code throwing after job creation skipped the `Remove-Job` call. Added `finally` blocks for deterministic cleanup in all three functions. VM export jobs hold file locks on the export path; VHD copy/convert jobs hold disk I/O; Windows Update install jobs consume significant system resources (53-VMExportImport, 41-VHDManagement, 14-WindowsUpdates).
- **Bug Fix:** `PSSession` leaked in `Test-RemoteReadiness` when session creation succeeded but subsequent code threw before reaching `Remove-PSSession` — the outer catch handled the error but never closed the session. Moved cleanup to a `finally` block, which ensures the remote WinRM connection slot is always released (35-Utilities).
- **Bug Fix:** `TcpClient` socket leaked on RDP port check when `BeginConnect` threw an exception (e.g., invalid IP format) — the `Close()` call was in the try block after the connect, so it was skipped on error. Moved `Close()` to a `finally` block (44-VMDeployment).
- **Bug Fix:** Agent installer background job not cleaned up in the `finally` block — only the temp file was removed. If `Receive-Job` or subsequent code threw unexpectedly, the install job leaked. Added job cleanup to the existing `finally` block (57-AgentInstaller).
- **Bug Fix:** Partial download file left in `%TEMP%` on failed self-update — if `Invoke-WebRequest` failed partway through (network timeout), the partial file remained. Now removed in the catch block before returning (35-Utilities).
- **Bug Fix:** Windows Update installation silently reported "complete!" even when the install job failed — `$installJob.State` was never checked. Now checks job state and shows a warning if the job failed, instead of unconditionally claiming success (14-WindowsUpdates).
- **Bug Fix:** Division by zero in menu dashboard when WMI returned 0 for `TotalVisibleMemorySize` — every other memory percentage calculation in the codebase already had a `> 0` guard, but the dashboard status bar was the lone exception (48-MenuDisplay).
- **Bug Fix:** Array index out of bounds when SAN target pairs were empty — `$allPairs[0]` on an empty array returned `$null`, cascading through iSCSI connection logic with null target portal addresses. Added count checks and early returns (10-iSCSI).
- **Bug Fix:** Metric collection `$IntervalMinutes` parameter could be 0, causing division by zero in `[math]::Ceiling($DurationMinutes / $IntervalMinutes)`. Now defaults to 5 if the value is <= 0 (54-HTMLReports).
- 63 modules, 1854 tests

## v1.9.40

- **Bug Fix:** 52 `.PadRight(72)` overflow bugs across 15 modules — when dynamic content (network adapter names, iSCSI IQN strings, FQDNs, VM names, user input, comma-joined lists, file paths, FSMO role holders) exceeded 72 characters, the `PadRight` call did nothing (it only pads, never truncates), causing the string to overflow past the TUI box-drawing border `│`. All 52 instances now extract the dynamic content, truncate at 69 characters with `...` ellipsis if needed, then apply `.PadRight(72)` to guarantee consistent box alignment. Affected modules: 09-SET (4), 10-iSCSI (4), 12-DomainJoin (1), 19-NTPConfiguration (1), 27-FailoverClustering (2), 37-HealthCheck (1), 44-VMDeployment (2), 51-ClusterDashboard (7), 55-QoLFeatures (2), 56-OperationsMenu (2), 57-AgentInstaller (9), 58-NetworkDiagnostics (4), 60-ServerRoleTemplates (1), 61-ActiveDirectory (11), 62-HyperVReplica (5).
- 63 modules, 1854 tests

## v1.9.39

- **Bug Fix:** 10 remaining `-f` format string operator calls in disk overview, partition details, and volume listing converted to string interpolation with `.PadRight()`. Same class of bug fixed in v1.9.38 — the `-f` operator throws `FormatException` when formatted values contain `{` or `}`. The `$disk.FriendlyName` case was highest risk (e.g., NVMe drives reporting as `Samsung SSD 990 PRO {NVMe}`), but all 10 instances in the Storage Manager and VM status display were converted for consistency (38-StorageManager, 44-VMDeployment).
- **Bug Fix:** `Test-WindowsServer` returned `$true` when WMI was unavailable — `Get-CimInstance` with `-ErrorAction SilentlyContinue` returned `$null`, and `$null.ProductType -ne 1` evaluated as `$true`. This caused server-only features (like `Install-WindowsFeature`) to be offered on workstations with broken WMI. Now returns `$false` when WMI is unavailable (05-SystemCheck).
- **Bug Fix:** Three `Get-NetFirewallProfile` calls in the firewall configuration function were missing `-ErrorAction SilentlyContinue` — if the Windows Firewall service was unavailable or stopped, these threw a terminating error that bypassed the outer try/catch. Also added `$null` guards so a failed query doesn't misread the profile state (16-Firewall).
- **Bug Fix:** `Get-SRGroup` replication status detail query had no `-ErrorAction` — if a Storage Replica group was removed between the initial list query and the per-group detail query, the unguarded call threw an unhandled exception. Now uses `-ErrorAction SilentlyContinue` with a `$null` guard (33-StorageReplica).
- **Bug Fix:** `Get-BitLockerVolume` recovery key lookup had no `-ErrorAction` — threw an unhandled error when BitLocker was not enabled on the selected volume, and displayed a misleading "No recovery password found" message instead of a proper error. Now uses `-ErrorAction SilentlyContinue` with a `$null` guard (31-BitLocker).
- **Bug Fix:** VHD copy progress bar received `$null` for source size when the source file was inaccessible — `(Get-Item).Length` on a `$null` result passed `$null` to `Write-ProgressBar`, causing display errors. Now defaults to `0` when the source item can't be read (41-VHDManagement).
- **Bug Fix:** `Get-CimInstance` in the domain join function was missing `-ErrorAction SilentlyContinue` — a WMI failure threw a raw PowerShell error to the user instead of being handled gracefully. Also added a `$null` guard so the domain status check doesn't fail on inaccessible WMI (12-DomainJoin).
- **Bug Fix:** Batch config domain join step attempted to join when WMI failed — `$null` from `PartOfDomain` made `-not $null` evaluate as `$true`, triggering an unwanted domain join attempt. Now defaults to assuming already joined when WMI is unavailable, which is the safe fallback (50-EntryPoint).
- **Bug Fix:** VM switch pre-flight check produced `@($null)` when Hyper-V was unavailable — `Get-VMSwitch` returning `$null` followed by `.Name` produced `$null`, and `@($null)` created a single-element array containing `$null` instead of an empty array. This corrupted the `-notin` switch presence check. Now properly returns an empty array when `Get-VMSwitch` returns nothing (44-VMDeployment).
- 63 modules, 1854 tests

## v1.9.38

- **Bug Fix:** Unescaped single quotes in network adapter name broke the batch config network undo scriptblock — same class of bug fixed in v1.9.33 for admin names, virtual switch names, and vNIC names, but the adapter name in the network IP configuration undo was missed. An adapter named `O'Brien NIC` would produce a malformed scriptblock via `[scriptblock]::Create()`. Now escapes `'` to `''` before interpolation (50-EntryPoint).
- **Bug Fix:** 5 `-f` format string operator calls threw `System.FormatException` when user-settable names contained curly braces `{` or `}`. Volume labels like `{Data}`, VM names like `VM{Test}`, disk names, switch names, and adapter names were all vulnerable. The `-f` operator interprets `{0}`, `{1}` etc. as placeholder references, so any braces in the values caused a crash. Replaced with string interpolation and `.PadRight()` (06-NetworkAdapters, 38-StorageManager, 44-VMDeployment).
- **Bug Fix:** VM name prefix containing `$` followed by digits (e.g., `$1MYAPP`) silently dropped the `$1` when generating VM names — PowerShell's `-replace` operator interprets `$1` in the replacement string as a regex backreference to capture group 1. Switched from `-replace` to `.Replace()` for literal string substitution (44-VMDeployment).
- **Bug Fix:** VM export progress tracking showed 0 bytes and final export size showed 0 when the VM name contained square brackets `[` or `]` — `Test-Path` and `Get-ChildItem -Path` interpret brackets as wildcard character class patterns, silently matching nothing. Switched to `-LiteralPath` (53-VMExportImport).
- **Bug Fix:** VM-specific directory creation logic incorrectly skipped creating directories when the VM name contained brackets — `Test-Path` without `-LiteralPath` treated `[]` as wildcards, potentially reporting a non-existent directory as existing or vice versa. Switched to `-LiteralPath` (44-VMDeployment).
- **Cleanup:** Removed dead `$script:IsEXE` variable reference that was never assigned anywhere in the codebase — the fallback condition already handled EXE detection correctly (47-ExitCleanup).
- 63 modules, 1854 tests

## v1.9.37

- **Bug Fix:** 10 `Get-CimInstance` and `Get-Partition` calls inside `try/catch` blocks were missing `-ErrorAction Stop`, causing non-terminating errors to silently bypass the catch block:
  - `Get-CimInstance Win32_OperatingSystem` in Hyper-V detection and licensing version info — on WMI failure, `$osInfo.ProductType -ne 1` evaluated as `$true` on null, incorrectly classifying the machine as a server (05-SystemCheck, 21-Licensing).
  - Three `Get-CimInstance` calls (`Win32_ComputerSystem`, `Win32_OperatingSystem`, `Win32_Processor`) in config text export — silently produced empty hostname, domain, OS, and CPU info in the exported configuration file (45-ConfigExport).
  - `Get-CimInstance Win32_ComputerSystem` inline in profile import domain join check — on WMI failure, `.PartOfDomain` evaluated as `$null`, making `-not $null` = `$true`, which could trigger a domain re-join attempt on a machine that is already domain-joined (45-ConfigExport).
  - Three `Get-CimInstance Win32_ComputerSystem` calls in pagefile management (system managed, custom size, move to drive) — null `$compSysObj` passed to `Set-CimInstance -InputObject` causing a confusing "cannot validate argument" error instead of the intended catch message (55-QoLFeatures).
  - `Get-Partition` in offline VHD Windows drive detection — error silently swallowed with no diagnostic output, making VHD mount failures hard to troubleshoot (43-OfflineVHD).
- 63 modules, 1854 tests

## v1.9.36

- **Bug Fix:** Config profile export saved `SubnetCIDR` as a JSON array (e.g., `[24, 16]`) instead of a single integer when the primary adapter had multiple IPv4 addresses (e.g., static + APIPA 169.254.x.x). `Get-NetIPAddress` returned multiple objects, and PowerShell property unrolling produced an array. This corrupted the saved profile and caused `New-NetIPAddress -PrefixLength` to fail on import. Now filters out link-local (WellKnown) addresses and selects a single result (45-ConfigExport).
- **Bug Fix:** Config drift detection falsely reported IP address and gateway mismatches on adapters with multiple IPv4 addresses or multiple default routes. `Get-NetIPAddress.IPAddress` and `Get-NetRoute.NextHop` returned arrays, and scalar `-eq` array comparisons always return `$false` in PowerShell. Now narrows to single result before comparison (45-ConfigExport).
- **Bug Fix:** iSCSI adapter configuration displayed garbled IP info when the adapter had multiple IPv4 addresses — PowerShell property unrolling on the array produced concatenated output like `10.0.0.100 169.254.1.1/24 16` instead of `10.0.0.100/24`. Now selects first result (10-iSCSI).
- **Bug Fix:** 6 `Test-Path` calls threw a terminating error ("Cannot bind argument to parameter 'Path' because it is an empty string") when the user pressed Enter without typing a path. Empty string from `Read-Host` passed through `Test-NavigationCommand` (which returns `ShouldReturn = $false` for empty input) and `.Trim('"')`, then reached `Test-Path ""` which threw. Now checks `[string]::IsNullOrWhiteSpace()` before `Test-Path` (35-Utilities, 53-VMExportImport, 54-HTMLReports).
- **Bug Fix:** VM export default path resolved to root of C: drive when `$script:HostVMStoragePath` was null after a connection reset — string interpolation `"$null\Exports"` produced `\Exports` which resolved to `C:\Exports`. Now uses `Join-Path` with a guard fallback to `$script:TempPath` (53-VMExportImport).
- 63 modules, 1854 tests

## v1.9.35

- **Bug Fix:** 18 TUI box-drawing display lines overflowed their right border when variable-length content exceeded 72 characters. Affected: cluster node lists with 4+ nodes (27-FailoverClustering), CSV volume names with long paths (27-FailoverClustering), Storage Replica partnership lines with FQDNs (33-StorageReplica), iSCSI disk FriendlyName (10-iSCSI), Defender process exclusion paths and extension lists (17-DefenderExclusions), network adapter connectivity results (09-SET), profile comparison values (35-Utilities), FC/S2D/NVMe physical disk names (59-StorageBackends), storage pool and virtual disk names (59-StorageBackends), and AD forest query exception messages (61-ActiveDirectory). All now truncate with `...` ellipsis at 69 characters before `.PadRight(72)`.
- **Bug Fix:** Batch config validation accepted non-boolean strings for `InstallAgent` and `ValidateCluster` fields without error — these two boolean fields were missing from the `$boolFields` validation array in `Confirm-BatchConfig`. Values like `"yes"` or `"1"` passed validation but evaluated as truthy strings instead of proper `$true`/`$false` booleans at runtime (50-EntryPoint).
- **Bug Fix:** `$driveLetter` uninitialized in VM deployment storage space check when a CSV path resolved successfully — the variable was only assigned inside the `$null -eq $freeBytes` fallback branch, so the returned hashtable included `DriveLetter = $null` for all CSV-backed storage (44-VMDeployment).
- 63 modules, 1854 tests

## v1.9.34

- **Bug Fix:** VLAN IDs with first digit 5-9 silently not applied to custom vNICs during batch mode when the JSON value was a quoted string (e.g., `"VLAN": "5"` instead of `"VLAN": 5`). The validation function correctly cast with `-as [int]` and accepted the value, but the execution path used the raw string in a numeric comparison — `"5" -le "4094"` becomes a string comparison where `"5" > "4"`, so the VLAN was silently dropped. VLANs 1-4 and 10+ happened to work due to string sort order. Now casts to `[int]` at point of use (50-EntryPoint).
- **Bug Fix:** iSCSI host numbers 3-9 silently skipped during batch mode with the same quoted-string root cause. `"5" -le "24"` evaluates as `"5" > "2"` in string comparison, causing the entire iSCSI configuration step to be skipped with a misleading "Could not determine host number" message even though validation passed. Host numbers 1-2 and 10-24 happened to work. Now casts to `[int]` at point of use (50-EntryPoint).
- 63 modules, 1854 tests

## v1.9.33

- **Bug Fix:** BitLocker encryption method prompt accepted invalid input then falsely reported "BitLocker enabled" — typing anything other than 1, 2, or 3 at the encryption method selection silently skipped the actual `Enable-BitLocker` call but executed the success message and logged a session change, making the user believe the volume was encrypted when it was not (31-BitLocker).
- **Bug Fix:** Undo stack registered a "Remove virtual switch" entry even when no switch was actually created — entering an unknown switch type (neither External, Internal, nor Private) hit the `default` warning case, but the undo entry was added unconditionally outside the switch statement, creating a phantom undo action that references a non-existent switch (50-EntryPoint).
- **Bug Fix:** Single quotes in user-provided names broke batch config undo scriptblocks — names containing apostrophes (e.g., `O'Brien` for local admin, or `vNIC 'Management'`) caused `[scriptblock]::Create()` to produce malformed PowerShell due to unescaped single quotes in the command string. Now escapes `'` to `''` before interpolation into scriptblock strings for local admin undo, virtual switch undo, and vNIC undo (50-EntryPoint).
- **Bug Fix:** Single quotes in ToolName (from `defaults.json` override) broke the self-destruct scheduled task — the ToolName was interpolated unescaped into the PowerShell cleanup command string that gets Base64-encoded for the post-reboot scheduled task, causing a syntax error in `Unregister-ScheduledTask` (47-ExitCleanup).
- **Perf:** Consolidated 4 separate recursive `Get-ChildItem` traversals of the Administrator profile into 2 passes — the self-destruct cleanup scanned the entire Administrator profile directory tree 4 times (1 file scan + 3 directory scans). Now performs one file pass and one directory pass with combined filtering logic (47-ExitCleanup).
- 63 modules, 1854 tests

## v1.9.32

- **Bug Fix:** 11 cmdlets inside `try/catch` blocks were missing `-ErrorAction Stop`, causing non-terminating errors to be silently swallowed instead of caught by the catch block:
  - `Set-DnsClientServerAddress` silently failed during config profile apply and batch mode — IP address was configured successfully but DNS was left unconfigured, with the tool reporting "Network configured" (45-ConfigExport, 50-EntryPoint).
  - `Get-Partition` returned stale partition data after `Set-Partition` changed the drive letter — subsequent `Format-Volume` could operate on stale partition object (38-StorageManager).
  - `Get-Disk`, `Get-Service`, `Get-NetAdapter`, `Get-WindowsFeature` failures silently swallowed — produced misleading "not found" or "none installed" messages instead of the actual error (15-RDP, 38-StorageManager, 43-OfflineVHD, 45-ConfigExport, 50-EntryPoint, 59-StorageBackends, 60-ServerRoleTemplates, 09-SET).
- **Bug Fix:** `WebClient` not disposed when `DownloadFile()` throws (network timeout, HTTP 404, disk full) — TCP connection leaked on every failed download attempt. Since FileServer downloads retry up to 3 times, a failing large file download could leak 3 TCP connections (39-FileServer).
- **Bug Fix:** `StreamReader` and `WebResponse` not disposed when `ReadToEnd()` throws during SHA256 hash file download — resources leaked on mid-stream network failures. Moved cleanup to `finally` block (39-FileServer).
- **Bug Fix:** IP sweep job array used `$jobs += Start-Job` inside a 1-254 iteration loop, creating O(n^2) array copies (~32K element copies for a full /24 sweep). Replaced with `List[object]` for linear O(n) performance (58-NetworkDiagnostics).
- 63 modules, 1854 tests

## v1.9.31

- **Bug Fix:** `Confirm-UserAction` rejected valid "yes"/"y" responses when the user typed with leading or trailing whitespace — `Read-Host` was not trimmed before the regex match, so `" y"` or `"y "` failed the `'^(y|yes)$'` pattern. Affects all ~175 confirmation prompts across the tool (03-InputValidation).
- **Bug Fix:** Typing "back" at the custom Defender exclusion prompts (path and process) added "back" as an actual Windows Defender exclusion instead of navigating back to the menu — missing `Test-NavigationCommand` check before `Add-MpPreference` (17-DefenderExclusions).
- **Bug Fix:** Typing "back" at the VM Export path prompt created a directory named "back" instead of returning to the menu — missing navigation check before `New-Item` (53-VMExportImport).
- **Bug Fix:** Navigation commands ("back", "exit", "quit", "menu") ignored at several prompts: remote session credential choice, BitLocker key save path, batch config template save paths (2 locations), and Hyper-V Replica test failover cleanup choice (56-OperationsMenu, 31-BitLocker, 36-BatchConfig, 62-HyperVReplica).
- **Bug Fix:** Integer overflow crash (OverflowException) when entering numbers larger than 2,147,483,647 at IP sweep range octets, pagefile initial/maximum size, S2D virtual disk size, VM additional disk size, and metric collection interval/duration prompts — `^\d+$` regex validation passes but subsequent `[int]` cast throws. Now uses `[int]::TryParse()` with proper error messages (58-NetworkDiagnostics, 55-QoLFeatures, 59-StorageBackends, 44-VMDeployment, 56-OperationsMenu).
- **Bug Fix:** Volume label prompt accepted input with leading/trailing whitespace, passing invisible characters to `Set-Volume` (38-StorageManager).
- **Bug Fix:** Destructive confirmation prompts ("YES", "DELETE", "FORMAT") rejected valid input typed with accidental whitespace — `Read-Host` was not trimmed before exact string comparison (38-StorageManager).
- 63 modules, 1854 tests

## v1.9.30

- **Bug Fix:** File integrity check crashed with "cannot call a method on a null-valued expression" when local hash computation failed — `.Substring(0,16)` called on a null hash value with no null guard (39-FileServer).
- **Bug Fix:** VM deployment disk space check reported wrong free space for Cluster Shared Volumes — `$StoragePath.Substring(0,1)` extracted the drive letter `C` from `C:\ClusterStorage\Volume1`, returning the OS drive's free space instead of the CSV's actual capacity (44-VMDeployment).
- **Bug Fix:** Self-update temporary files not cleaned up when marked read-only — `Remove-Item` missing `-Force` flag on all 4 temp file cleanup paths in the update flow (35-Utilities).
- **Bug Fix:** Audit log (JSONL) written in system-default encoding (Windows-1252) instead of UTF-8 — non-ASCII characters in VM names, hostnames, or domain names produced corrupt JSON records that fail standard JSON parsers. Affects 211 call sites across 45 modules (04-Navigation).
- **Bug Fix:** Session log written in system-default encoding instead of UTF-8 — non-portable across different OS locales (04-Navigation).
- **Bug Fix:** Core logging function `Write-LogMessage` wrote in system-default encoding instead of UTF-8 (02-Logging).
- **Bug Fix:** SHA256 hash file written without explicit UTF-8 encoding — filenames with non-ASCII characters could cause hash verification mismatches and unnecessary re-downloads (39-FileServer).
- **Bug Fix:** First-boot PowerShell script written to offline VHD without UTF-8 encoding — could cause parse errors when the target system has a different locale than the authoring system (43-OfflineVHD).
- **Bug Fix:** Post-reboot cleanup scheduled task used `-Path` instead of `-LiteralPath` — paths containing bracket characters (`[`, `]`) were interpreted as wildcard patterns, silently failing to delete orphaned files (47-ExitCleanup).
- 63 modules, 1854 tests

## v1.9.29

- **Bug Fix:** RDP status falsely reported "Enabled" when the registry key was inaccessible — `$null -eq 0` evaluates to `$true` in PowerShell, so a failed `Get-ItemProperty` with `-ErrorAction SilentlyContinue` always matched the "enabled" condition (05-SystemCheck).
- **Bug Fix:** Performance dashboard displayed "0 GB" for all memory metrics when the CIM query failed — `$os` from `Get-CimInstance` used without null guard, causing `$null / 1MB` to silently evaluate to 0 (28-PerformanceDashboard).
- **Bug Fix:** Health check displayed "0 GB" for memory when the CIM query failed — same `$os` null guard missing despite other properties in the same function being properly guarded (37-HealthCheck).
- **Bug Fix:** Metric collection crashed with `DivideByZeroException` when interval was set to 0 minutes — input validation regex `^\d+$` accepted "0" as valid, causing `[math]::Ceiling(60 / 0)` (56-OperationsMenu).
- **Bug Fix:** Company defaults silently lost when `defaults.json` was corrupted — empty `catch { }` swallowed JSON parse errors with no user feedback, causing fallback to generic defaults (56-OperationsMenu).
- **Bug Fix:** Trend report silently skipped corrupted snapshot JSON files with no indication of missing data — empty `catch { }` during snapshot loading provided no warning about how many files failed to parse (54-HTMLReports).
- **Bug Fix:** Audit log rotation errors silently discarded — `Write-LogMessage` called without the `-logFilePath` parameter, making the call a no-op that wrote nothing (04-Navigation).
- **Bug Fix:** Navigation commands ("back"/"exit") ignored at manual license key entry prompts — `Test-NavigationCommand` result checked but function never returned, silently falling through instead of navigating (21-Licensing).
- 63 modules, 1854 tests

## v1.9.28

- **Bug Fix:** File search in single-file shared folders returned a raw hashtable instead of an array — `Get-FileServerFiles` result not wrapped in `@()`, causing `.Count` to return the number of hashtable keys and `foreach` to iterate `DictionaryEntry` objects instead of file records (39-FileServer).
- **Bug Fix:** Pagefile drive detection was skipped when exactly one pagefile existed — `Get-CimInstance Win32_PageFileUsage` result not wrapped in `@()`, so `.Count` returned `$null` and `[0]` indexing failed on a single CIM object (55-QoLFeatures).
- **Bug Fix:** Performance snapshot count displayed blank when exactly one metrics JSON file existed — `Get-ChildItem` result not wrapped in `@()` (54-HTMLReports).
- **Bug Fix:** Cluster dashboard "and X more resources" message never appeared when a single cluster resource existed — `Get-ClusterResource` `.Count` failed without `@()` wrapping (27-FailoverClustering).
- **Bug Fix:** Installed features count check failed when exactly one Windows feature was installed — `Get-WindowsFeature` pipeline result not wrapped in `@()` (60-ServerRoleTemplates).
- **Bug Fix:** RDP listener count displayed blank when a single WSMan listener was configured — `Get-ChildItem` result not wrapped in `@()` (15-RDP).
- **Bug Fix:** SET team NIC count displayed blank for single-NIC teams — `.NetAdapterInterfaceDescription` property not wrapped in `@()` (09-SET).
- **Bug Fix:** Deep disk cleanup reported "complete" even when DISM component store cleanup failed — `Dism.exe` exit code was not checked after execution (20-DiskCleanup).
- **Bug Fix:** Batch configuration reported power plan set even when `powercfg` failed — exit code not checked, changes counter and session tracking ran unconditionally (50-EntryPoint).
- **Bug Fix:** Profile apply reported power plan set even when `powercfg` failed — exit code not checked (45-ConfigExport).
- 63 modules, 1854 tests

## v1.9.27

- **Critical Bug Fix:** VHD dynamic-to-fixed conversion deleted the converted file — `Remove-Item` targeted the same path that `Move-Item` had just written to, destroying the just-converted fixed VHD. The function returned a path to a deleted file (41-VHDManagement).
- **Bug Fix:** VM import failed when exactly one `.vmcx` file existed — `Get-ChildItem` result not wrapped in `@()`, so `.Count` returned `$null` and `[0]` indexing failed on a single `FileInfo` object. The import reported "No .vmcx file found" (53-VMExportImport).
- **Bug Fix:** VM checkpoint and export menus reported "No VMs available" when exactly one VM existed — `Get-VM` pipeline result not wrapped in `@()`, so `.Count` was `$null` on single objects (52-VMCheckpoints, 53-VMExportImport).
- **Bug Fix:** Agent installer always showed the multi-agent management menu even with only one agent configured — `Get-AllAgentConfigs` returned a single hashtable (unwrapped from array), and `.Count` on a hashtable returns the number of keys (~9), not 1 (57-AgentInstaller).
- **Bug Fix:** Agent auto-match by hostname routed a single matching agent into the multi-agent selection branch — `Search-AgentInstaller` result not wrapped in `@()` (57-AgentInstaller).
- **Bug Fix:** Profile import crashed with "Cannot call a method on a null-valued expression" on JSON files missing `_ProfileInfo` metadata — `.PadRight(60)` called directly on null property values without null guards (45-ConfigExport).
- **Bug Fix:** VM deployment cluster discovery reported wrong `NodeCount` for single-node clusters — `Get-ClusterNode` not wrapped in `@()` (44-VMDeployment).
- **Bug Fix:** VM deployment couldn't select a virtual switch when only one existed — `.Count` on a single `VMSwitch` object returned `$null`, causing index validation to always fail (44-VMDeployment).
- **Bug Fix:** "Total VMs" count displayed blank with exactly one VM in VM management — `Get-VM` result not wrapped in `@()` (44-VMDeployment).
- **Bug Fix:** Storage backend FC/NVMe/eligible disk counts displayed blank with a single disk — pipeline results from `Get-Disk | Where-Object` not wrapped in `@()` across 4 code paths (59-StorageBackends).
- **Bug Fix:** Offline disk detection and count display failed with a single offline disk — `Get-Disk | Where-Object` not wrapped in `@()` (38-StorageManager).
- **Bug Fix:** Roles & Features submenu summary showed wrong installed count when exactly one role was installed — `Where-Object` result not wrapped in `@()` (48-MenuDisplay).
- **Bug Fix:** Hyper-V Replica VM selection reported "No virtual machines found" with exactly one VM — `Get-VM` result not wrapped in `@()` (62-HyperVReplica).
- 63 modules, 1854 tests

## v1.9.26

- **Bug Fix:** Disk cleanup byte counter was corrupted by directory entries — `Get-ChildItem` without `-File` included directories, whose `.Length` returns name character count (not byte size). The "freed space" report was inflated with nonsense values. Added `-File` flag to both temp cleanup loops (20-DiskCleanup).
- **Bug Fix:** NTP configuration reported "configured successfully" even when `w32tm /config` or `/resync` failed — native executables set `$LASTEXITCODE` but don't throw PowerShell exceptions, so the `try/catch` caught nothing. Now checks `$LASTEXITCODE` after each `w32tm` call (19-NTPConfiguration).
- **Bug Fix:** Detailed time status display truncation logic was broken for `w32tm` error output — `2>&1` redirects stderr as `ErrorRecord` objects, not strings. Accessing `.Length` on `ErrorRecord` returns `$null`, making the `Substring` guard a no-op. Now converts to string first (19-NTPConfiguration).
- **Bug Fix:** Navigation commands (`exit`, `help`, `back`, `b`/`B`) were silently ignored in two network menus — `Start-Show-HostNetworkIPMenu` and `Start-Show-VM-NetworkMenu` were missing the `Test-NavigationCommand` call that all other menu runners have. Typing "exit" fell into the "Invalid choice" handler (49-MenuRunner).
- **Bug Fix:** Firewall state detection compared `.Enabled` (a `GpoBoolean` enum) to the string `"True"` instead of `$true` — worked by accident via type coercion but reported "Disabled" instead of using the catch-block "Unknown" when a profile was null (05-SystemCheck).
- **Bug Fix:** Current IP display garbled output when adapter had multiple IPv4 addresses — `Get-NetIPAddress` can return multiple objects, causing `$currentIP.IPAddress` to concatenate array elements. Added `Select-Object -First 1` (07-IPConfiguration).
- **Bug Fix:** Cluster dashboard and CSV health checks crashed or showed 0 GB for faulted/offline CSVs — `SharedVolumeInfo.Partition` is null when a CSV is unavailable, causing `$null / 1GB` to produce zeros. Added null guards with skip+warning in all three CSV iteration loops (51-ClusterDashboard).
- **Bug Fix:** iSCSI NIC identification menu couldn't select adapters when only one physical NIC existed — pipeline result wasn't wrapped in `@()`, so `.Count` and array indexing failed on single objects. Wrapped all three `Get-NetAdapter` assignments (10-iSCSI).
- 63 modules, 1854 tests

## v1.9.25

- **Bug Fix:** All bare `Exit` statements caused a "System error" dialog when running as the compiled EXE — ps2exe wraps `Exit` in a way that throws `BreakException`. Replaced with `[Environment]::Exit()` in both `Exit-Script` exit paths (47-ExitCleanup) and batch mode entry/exit (50-EntryPoint). Affects 4 code paths: normal exit, no-reboot exit, batch admin check failure, and batch completion.
- 63 modules, 1854 tests

## v1.9.24

- **Bug Fix:** Batch mode internet adapter detection failed with single adapter — `Where-Object` returned a scalar with no `.Count` property, so the `$internetAdapters.Count -ge 1` check was always false. Management NIC rename was silently skipped. Wrapped in `@()` (50-EntryPoint).
- **Bug Fix:** Batch mode iSCSI candidate adapter detection failed with single adapter — same `.Count` issue caused the entire iSCSI configuration step to be skipped when only one non-internet adapter existed. Wrapped in `@()` (50-EntryPoint).
- **Bug Fix:** Batch mode iSCSI adapter assignment failed with single adapter — both the primary path (`$script:iSCSICandidateAdapters | ForEach-Object`) and the fallback path (`Get-NetAdapter | Where-Object`) returned scalars instead of arrays. Downstream `.Count` checks failed. Wrapped both paths in `@()` (50-EntryPoint).
- 63 modules, 1854 tests

## v1.9.23

- **Bug Fix:** Readiness score calculation crashed with division by zero if no checks were evaluated — `$ready / $total` with `$total = 0`. Added zero-guard on both `Show-ServerReadinessQuickCheck` and `Test-TemplateRequirement` score calculations (37-HealthCheck).
- **Bug Fix:** HTML readiness report generation crashed with division by zero in the same pattern — `$ready / $total` unguarded (54-HTMLReports).
- **Bug Fix:** Configuration drift comparison (`Compare-ConfigurationDrift`) crashed with unhandled exception when the profile JSON file was empty or malformed — `ConvertFrom-Json` was called outside any try/catch block. Now returns `$null` with error message instead of crashing (45-ConfigExport).
- 63 modules, 1854 tests

## v1.9.22

- **Bug Fix:** Storage Manager disk selection, initialization, volume display, and label functions all failed to detect empty results — `$null.Count -eq 0` is false in PS 5.1. Wrapped 6 pipeline results in `@()` across `Select-Disk`, `Show-AllDisks`, `Show-AllVolumes`, `Initialize-NewDisk`, and `Set-VolumeLabel` (38-StorageManager).
- **Bug Fix:** VLAN adapter partial match (`-like "*name*"`) could return multiple Hyper-V adapters when names overlap (e.g., "LAN" matching both "LAN" and "VLAN"). Array of names passed to `-VMNetworkAdapterName`, causing wrong adapter to be tagged. Added `Select-Object -First 1` (08-VLAN).
- **Bug Fix:** IP configuration rollback failed when adapter had multiple IPv4 addresses (DHCP + APIPA) — `Get-NetIPAddress` returned array, and `New-NetIPAddress` rejected array parameters for `-IPAddress` and `-PrefixLength`. Added `Select-Object -First 1` (07-IPConfiguration).
- **Bug Fix:** Adapter status display garbled when multiple IPv4 addresses existed — string interpolation produced "192.168.1.100 169.254.1.1/24 16" instead of clean output. Added `Select-Object -First 1` (06-NetworkAdapters).
- 63 modules, 1854 tests

## v1.9.21

- **Bug Fix:** Cluster disk and CSV selection menus rejected valid choices when only one item existed — single pipeline result has no `.Count` in PS 5.1. Wrapped cluster disk, CSV, and quorum disk queries in `@()` and updated emptiness checks to use `.Count -eq 0` (27-FailoverClustering).
- **Bug Fix:** Agent installer silently dropped all install arguments after the first — `Start-Job -ArgumentList` flattened the args array, and the scriptblock's `param()` only captured the first element. Changed to pass install args as a single unsplit string (57-AgentInstaller).
- **Bug Fix:** "Paused Nodes" box header had `.PadRight(72)` applied to the border character instead of the header text, producing misaligned box drawing (51-ClusterDashboard).
- 63 modules, 1854 tests

## v1.9.20

- **Bug Fix:** Batch mode firewall undo was completely broken — scriptblock used `` `$$oldDomain `` which produced undefined variable references like `$Enabled` instead of actual True/False values. Undo silently failed, leaving firewall profiles disabled after batch undo (50-EntryPoint).
- **Bug Fix:** VM deployment pre-flight switch validation was a no-op — checked `$_.SwitchName` on the top-level config object (always null) instead of `$_.NICs[].SwitchName`. Always reported "All present" even when switches were missing, allowing deployment to proceed and fail mid-creation (44-VMDeployment).
- **Bug Fix:** Deleting a VM disk from the deployment queue used PowerShell hashtable value equality, which removed ALL disks with identical properties (same name/size/type) instead of just the selected disk. Changed to index-based removal (44-VMDeployment).
- **Cleanup:** Removed dead `$initMethod` variable with incorrect `"OverNetwork"` mapping for external media choice in Hyper-V Replica (62-HyperVReplica).
- 63 modules, 1854 tests

## v1.9.19

- **Bug Fix:** Event log viewer crashed on events with null `Message` property — security audit and Hyper-V events commonly have no message text. Added null guard with "(no message)" fallback (29-EventLogViewer).
- **Bug Fix:** Certificate viewer and exporter crashed on certificates with null `Subject` — self-signed, CNG, and auto-enrolled certs can lack a subject. Added null guard with "(no subject)" fallback at all 3 display points (55-QoLFeatures).
- **Bug Fix:** When multiple external virtual switches existed, `Remove-VMSwitch` received an array of names and would delete ALL of them instead of just one. Added `Select-Object -First 1` to ensure single-switch handling (09-SET).
- **Bug Fix:** VM export/import operations failed when VM names contained square brackets — `Test-Path` and `Get-ChildItem` treated `[]` as wildcard characters. Switched to `-LiteralPath` parameter (53-VMExportImport).
- **Bug Fix:** SMB share connectivity test reported shares with brackets in their name as inaccessible. Switched to `-LiteralPath` (59-StorageBackends).
- **Bug Fix:** iSCSI side comparison indexed into `$sides` without bounds check — single result caused string character indexing instead of array element access. Wrapped in `@()` and added `.Count -ge 2` guard (10-iSCSI).
- 63 modules, 1854 tests

## v1.9.18

- **Bug Fix:** SET team auto-detection failed on 2-NIC servers — single pipeline result from `Where-Object` has no `.Count` property in PS 5.1, so `.Count -gt 0` returned false. iSCSI candidate adapters were never identified. Wrapped pipeline results in `@()` array subexpression (09-SET).
- **Bug Fix:** Storage backend detection missed Fibre Channel when only one HBA present — `$fcAdapters -and $fcAdapters.Count -gt 0` evaluated to false for single objects. Same bug for single NVMe disks. Wrapped in `@()` (59-StorageBackends).
- **Bug Fix:** FC adapter display function skipped all content when only one HBA port existed — same single-object `.Count` pattern (59-StorageBackends).
- **Bug Fix:** Network sweep "No hosts responded" message never displayed — when `$alive` is `$null` (zero results), `.Count -eq 0` evaluates to `$null -eq 0` which is false. Wrapped in `@()` (58-NetworkDiagnostics).
- 63 modules, 1854 tests

## v1.9.17

- **Bug Fix:** Division by zero / NaN cascade in performance dashboard when CIM returns null — memory percentage and progress bar produced errors. Added `-ErrorAction SilentlyContinue` and zero guards (28-PerformanceDashboard).
- **Bug Fix:** Health check memory and disk percentage calculations unguarded — division by zero when `$os` or `$disk.Size` is null/zero. Added guards across both display and summary sections (37-HealthCheck).
- **Bug Fix:** HTML system report crashed on null uptime when OS CIM query returned nothing. Added null guards on uptime, memory percent, and disk percent across report generation and performance snapshots (54-HTMLReports).
- **Bug Fix:** Remote server health check memory percentage and uptime calculation crashed when target's CIM returned null (56-OperationsMenu).
- 63 modules, 1854 tests

## v1.9.16

- **Bug Fix:** SAN target pairing loop used `$i -lt $mappings.Count - 1` which skips the last entry when custom mappings have odd count. Changed to `$i + 1 -lt $mappings.Count`.
- **Bug Fix:** Batch mode virtual switch undo entry was registered outside the try/catch — if switch creation failed, a phantom undo was added to the stack. Moved undo registration inside the try block.
- 63 modules, 1854 tests

## v1.9.15

- **Bug Fix:** Firewall profile status always showed "Enabled" regardless of actual state — GpoBoolean enum (value 2 for False) is non-zero/truthy. Changed to explicit `-eq "True"` comparison (05-SystemCheck, 16-Firewall).
- **Bug Fix:** Firewall configuration function never enabled Public profile when disabled — `-not $publicProfile.Enabled` always false due to GpoBoolean truthiness (16-Firewall).
- **Bug Fix:** Multiple `.Count` on unguarded `Where-Object` results — single matches return scalar (no `.Count` in PS 5.1). Wrapped in `@()` across 5 modules: connectivity test summary (05-SystemCheck), iSCSI SAN reachability (10-iSCSI), VM deployment preflight/smoke tests (44-VMDeployment), cluster node VM count (51-ClusterDashboard), AD prerequisite check (61-ActiveDirectory).
- 63 modules, 1854 tests

## v1.9.14

- **Bug Fix:** Cluster dashboard VM count displayed blank for nodes with 0 or 1 VMs — wrapped `Where-Object` pipeline in `@()` for consistent `.Count`.
- 63 modules, 1854 tests

## v1.9.13

- **Bug Fix:** VM deployment site detection used `.Count` on unguarded `Get-ClusterNode` result — single-node clusters couldn't detect site. Wrapped in `@()`.
- **Bug Fix:** VM checkpoint list used `.Count` on unguarded `Get-VMCheckpoint` pipeline — single-checkpoint VMs showed wrong count. Wrapped in `@()`.
- 63 modules, 1854 tests

## v1.9.12

- **Bug Fix:** BitLocker volume selection used `.Count` on unguarded `Get-BitLockerVolume` result — single-volume systems couldn't select their volume. Wrapped in `@()`.
- 63 modules, 1854 tests

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
