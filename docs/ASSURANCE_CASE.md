# Security Assurance Case

This document satisfies the OpenSSF Best Practices Silver-tier
`[assurance_case]` criterion. It is the security claim the project
asserts about itself, together with the evidence that backs the claim.

The structure follows the standard "assurance case" pattern: claim →
sub-claims → evidence + counter-arguments.

Last updated: **2026-05-20** (commit at `master` head).

---

## Top-level claim

**RackStack's security requirements are met to the extent reasonable
for a single-maintainer open-source Windows Server administration
toolkit, given the documented threat model and trust boundaries.**

The qualifying clauses are deliberate. RackStack is not — and does
not claim to be — a hardened kernel, a sandboxed runtime, or a
zero-trust agent. It is a privileged operator tool that helps an
already-trusted administrator configure Windows servers efficiently.
What it does claim is that an attacker who is *not* already an
administrator on the same machine, or who has compromised a single
component such as a config file or a registry key but not the
operator identity, cannot escalate to arbitrary code execution as
the operator.

The rest of this document unpacks what that means concretely.

---

## Threat model

### Assets to protect

| Asset | Sensitivity | Why |
|---|---|---|
| Administrator/SYSTEM access on the host running RackStack | High | The operator's identity is the bedrock of every other trust assumption. |
| Operator-provided credentials (local admin password, AD service-account creds, BitLocker recovery keys) | High | Disclosure breaks domain trust, leaks BitLocker volumes, or enables lateral movement. |
| Released artifacts (`RackStack.exe`, monolithic `.ps1`) | Medium | Compromise allows supply-chain attack on every downstream operator. |
| `defaults.json` operator config | Medium | Contains Cloudflare Access secrets, KMS host keys, AD service-account hints. |
| Audit log file (`<Tool>Config_<host>_<ts>.log`) | Medium | Contains operational history; should not contain plaintext secrets. |
| Session transcript | Medium | Same as above; PowerShell `Start-Transcript` records every line. |

### Adversaries

| Adversary | Capability assumption | Goal |
|---|---|---|
| **Non-admin local user** | Can read files the OS allows, can run unprivileged processes, may have write access to world-writable paths like `C:\Temp`. Cannot read protected registry hives or admin-only file paths. | Escalate to Administrator/SYSTEM via a flaw in RackStack. |
| **Remote attacker on the same network** | Can reach the iSCSI/SAN/management subnets, can spoof DNS, can intercept unencrypted traffic. | Read operator secrets in flight, inject configuration into running RackStack actions. |
| **Compromised dependency** | Controls the content of an action / module / PowerShell module that RackStack pulls in. | Execute arbitrary code in the RackStack process. |
| **Supply-chain attacker against the maintainer** | Compromises the maintainer's GitHub token or workstation. | Inject malicious code into a tagged release. |
| **Targeted reconnaissance** | Reads release artifacts, source, audit logs to find weaknesses. | Find a zero-day to weaponize against operators. |

### Out of scope (explicit non-claims)

- An attacker who already has Administrator on the target host. RackStack runs *as* that identity; further hardening against it would defeat the tool's purpose.
- An attacker who has compromised the operator's interactive PowerShell session. RackStack offers no defense against arbitrary code injected into its own runtime.
- An attacker who has physical-access keylogger on the operator's keyboard. RackStack does not implement secure input.
- Kernel-level rootkits on the target host.
- Vulnerabilities in Windows, .NET, PowerShell, Hyper-V, or other OS components.
- Operator misconfiguration where the documented default would be safe (e.g. an operator who manually edits a generated XML scheduled-task file to add a malicious command).

---

## Trust boundaries

RackStack's runtime crosses several trust boundaries. Each one is a
place where untrusted input flows into a more-privileged context, and
each one is where defensive code must be applied.

```
+--------------------------------------------------------------+
|                    Administrator session                      |
|  (operator identity, full host privileges, trusted runtime)   |
|                                                                |
|  +----------------------------------------------------------+ |
|  |                   RackStack.exe process                   | |
|  |              (also runs as Administrator)                 | |
|  |                                                             | |
|  |   reads ----> defaults.json   <----- Trust boundary 1     | |
|  |               (operator-trusted; admin-only DACL by default) |
|  |                                                             | |
|  |   reads ----> registry HKLM\...\Uninstall\RackStack       | |
|  |               <----- Trust boundary 2                     | |
|  |               (admin-only write; admin-trusted)            | |
|  |                                                             | |
|  |   reads ----> %ProgramData%\<Tool>\state\*                | |
|  |               <----- Trust boundary 3                     | |
|  |               (Admins+SYSTEM-only DACL; ACL-verified on read) |
|  |                                                             | |
|  |   reads ----> %TEMP%\RackStack-*.tmp transient files      | |
|  |               <----- Trust boundary 4                     | |
|  |               (per-process; cleanup on exit)               | |
|  |                                                             | |
|  |   spawns ---> Restart-Computer, slmgr.vbs, schtasks.exe, etc. |
|  |               <----- Trust boundary 5                     | |
|  |               (passes validated inputs as array args)      | |
|  +----------------------------------------------------------+ |
|                                                                |
|       network <----> HTTPS file-server (Cloudflare Access)     |
|                      <----- Trust boundary 6                  |
|                      (TLS 1.2+; certificate verification on)  |
|                                                                |
|       network <----> iSCSI/SAN management plane                |
|                      <----- Trust boundary 7                  |
|                      (cleartext on isolated VLAN by deployment) |
+--------------------------------------------------------------+
```

The boundaries that need active defensive code, with the defense
applied at each:

| # | Boundary | Defense |
|---|---|---|
| 1 | `defaults.json` → process | Schema validation via `Test-BatchConfig`; type checking via `ValidateSet`; rejection of unsafe values (`Test-ValidHostname`, `Test-ValidIPAddress`). |
| 2 | Registry → process | Allowlist regex on `InstallLocation` and `OutputPath` (`["`&|<>^%()]`, `..`, `[\x00-\x1F]` all rejected). |
| 3 | State file → process | DACL-verified directory creation under `%ProgramData%`; `Test-RackStackStateFileAcl` refuses to load if a non-admin SID has write access. |
| 4 | Temp file → process | Cryptographically random per-process names (`[guid]::NewGuid()`); atomic write-then-rename; cleanup on `Exit-Script`. |
| 5 | Process → child process | Always-array `Start-Process -ArgumentList`; never string concatenation of untrusted values into a single arg string; single-quote escaping of every operator-derived value passed to `[scriptblock]::Create`. |
| 6 | Process → file server | `Tls12 -bor Tls13` set explicitly before any HTTPS call; certificate verification on (no `-SkipCertificateCheck` anywhere). |
| 7 | iSCSI/SAN | Deployment-time responsibility; documentation requires isolated VLAN. RackStack does not transmit secrets over this plane. |

---

## Sub-claims (with evidence)

### SC-1: Operator-trusted inputs are validated before use

| Evidence | Where |
|---|---|
| Allowlist regex for every operator-typed field | `Modules/03-InputValidation.ps1` — `Test-ValidHostname`, `Test-ValidIPAddress`, `Test-ValidVLANId`; `Modules/21-Licensing.ps1` `Test-ValidLicenseKey`; `Modules/22-Password.ps1` `Test-PasswordComplexity`. |
| Null-byte injection rejected | Both `Test-ValidHostname` and `Test-ValidIPAddress` test `$Input.Contains([char]0)` before regex; covered by Pester tests in `Tests/Pester/InputValidation.Tests.ps1`. |
| Unicode lookalikes rejected | ASCII-only regex naturally rejects Cyrillic-`а`-instead-of-Latin-`a`; covered by Pester. |
| `ValidateSet` enforcement on CLI parameters | `Modules/50-EntryPoint.ps1` `Invoke-CLIAction` param block — `[ValidateSet('Light','Standard','Aggressive')]` etc. |
| `ValidatePattern` for structured codes | Error codes (`^RS-\d{4}$` in `Write-RackStackError`), license keys, MAC addresses. |
| Property-based fuzz on validators | `Tests/Pester/Fuzz.Tests.ps1` — runs 500+ random inputs through each validator on every CI run; asserts no crashes and consistent typed output. |

**Counter-argument considered.** Operator MIGHT bypass validation by
hand-editing `batch_config.json`. **Response:** validation is applied
at `Test-BatchConfig` time as well, not just at the interactive
prompt. Bypass requires the operator to bypass their own protection,
which is consistent with the "compromised administrator" out-of-scope
threat.

### SC-2: Untrusted secondary inputs do not enable privilege escalation

| Evidence | Where |
|---|---|
| Registry `InstallLocation` is sanitized before embedding in cmd.exe | `Modules/50-EntryPoint.ps1` `ScheduleUpdateCheck` — rejects `["`&|<>^%()]`, `..`, `[\x00-\x1F]`. |
| Scheduled-task XML is built with `[scriptblock]::Create` only over admin-controlled, single-quote-escaped values | Same module; pattern is `"... '$($val -replace ''',''''')' ..."` everywhere. |
| Action-history file moved out of `C:\Temp` to ACL-locked `%ProgramData%\<Tool>\state\` | v1.98.55 fix; see `Get-RackStackSecureStateDir` helper. |
| Batch-undo state file ACL-verified on load | `Modules/50-EntryPoint.ps1` `Invoke-BatchMode` — `Test-RackStackStateFileAcl` refuses to deserialize if any non-admin SID has write access. |
| File-server downloads use HTTPS only; no http:// scheme allowed | `Modules/39-FileServer.ps1` — `BaseURL` is operator-set and documented as HTTPS-only. |
| All `Start-Process -ArgumentList` use array form when arguments could come from any input that's not maintainer-controlled | Audited across all 65 modules in round 33. |

**Counter-argument considered.** An attacker who's already an admin
could write to HKLM. **Response:** correct — but they already won.
The defense in `ScheduleUpdateCheck` is not against them; it's
against a future non-admin path that might write to a less-privileged
key but flow into the same code.

### SC-3: Credentials don't leak to disk

| Evidence | Where |
|---|---|
| SecureString → plaintext conversion always paired with `ZeroFreeBSTR` | `Modules/22-Password.ps1` `ConvertFrom-SecureStringToPlainText`; audited across all callers (`27-FailoverClustering.ps1`, `61-ActiveDirectory.ps1`). |
| `Set-Transcript` paused around password display so the plaintext does not enter the session log | `Modules/22-Password.ps1` `New-StrongPassword` lines 393–410; `Modules/31-BitLocker.ps1` BitLocker key display block. |
| Structured-log secret-key redaction | `Modules/02-Logging.ps1` `Write-StructuredLog` `$secretKeyPattern` — covers `password`, `token`, `secret`, `cookie`, `session`, `sid`, `signature`, `sig`, `private_key`, `pem`, `dsrm`, `recovery`, `webhook_url`, plus their snake_case and CamelCase variants. |
| gitleaks scans every push for accidentally-committed secrets | `.github/workflows/gitleaks.yml` — weekly full-history sweep too. |
| `defaults.json` is gitignored; only `defaults.example.json` ships with placeholder values | `.gitignore`. |

**Counter-argument considered.** A future caller could route a credential
through `Write-StructuredLog -Data` under a key not in the redact
pattern (e.g. `OAuth2RefreshToken`). **Response:** the pattern catches
`token` substring, so this specific example is caught. The Pester
test suite covers the documented key vocabulary; new key shapes are
added as part of the patch that introduces them, by policy.

### SC-4: Release artifacts are verifiable

| Evidence | Where |
|---|---|
| SHA-256 hash of every artifact published in `release-hashes.txt` | Every release. |
| Sigstore cosign keyless signature on every artifact (`.sig` + `.pem`) | Every release since v1.98.54; verification command in release notes. |
| SLSA Level 3 build provenance attestation | `actions/attest-build-provenance@v2` on every release; verifiable via `gh attestation verify`. |
| Reproducible build from source | `.\sync-to-monolithic.ps1` produces deterministic monolithic; `Invoke-PS2EXE` output is byte-identical given the same source + version arguments. |
| SHA-pinned GitHub Actions enforced at the repo policy level | `gh api repos/TheAbider/RackStack/actions/permissions` shows `"sha_pinning_required": true`. |

**Counter-argument considered.** The maintainer's GitHub account could
be compromised, then signatures over malicious artifacts would still
verify. **Response:** correct — that's the unsolvable supply-chain
problem. Mitigations: branch protection blocks direct admin push
without PR; Sigstore Rekor records every signature publicly so a
divergence between published release and what consumers downloaded
is detectable; the maintainer's GitHub account requires MFA.

### SC-5: Operator transcripts contain operational truth, not surprises

| Evidence | Where |
|---|---|
| All meaningful operator actions logged via `Add-SessionChange` | Audited per module; each `Show-*` function with a state mutation calls `Add-SessionChange`. |
| Audit log path under operator-writable `$script:TempPath` (operator-trusted) | `Modules/02-Logging.ps1` `Write-LogMessage`. |
| Transcript stops if the operator opts to display a password — no plaintext gets recorded | See SC-3. |
| Session-summary is shown on exit, including any rebooted services, edited registry keys, started services, and persisted changes | `Modules/46-SessionSummary.ps1`. |
| Atomic write-then-rename for every operator-visible export file | `Modules/45-ConfigExport.ps1`, `Modules/54-HTMLReports.ps1`. |

**Counter-argument considered.** A bug in `Add-SessionChange` could
miss a side effect. **Response:** the regex-pattern harness in
`Tests/Run-Tests.ps1` specifically asserts that every documented
side-effect function calls `Add-SessionChange`; new functions failing
this rule are caught by CI at PR time.

---

## Counterclaims and unresolved risks

This document would be dishonest if it claimed no remaining risk. The
following are acknowledged and tracked:

### CR-1: Single-maintainer bus factor
- The maintainer is the only person who can ship a fix. If they
  become unavailable for an extended period, no fix ships until
  somebody forks per `GOVERNANCE.md`'s resumption plan.
- Mitigation: full source on GitHub, MIT license, automated CI, no
  proprietary signing keys. A fork can resume releases in hours.
- Not currently planned: onboarding a second maintainer.

### CR-2: No CodeQL coverage for PowerShell
- CodeQL doesn't have a PowerShell language analyzer. We scan
  JavaScript (in github-script blocks) and GitHub Actions workflow YAML
  only.
- Mitigation: PSScriptAnalyzer + the 32-round internal audit campaign
  + property-based fuzz tests on validators + cross-cutting structural
  tests in `Run-Tests.ps1`.
- Tracking: if Microsoft releases a CodeQL PowerShell pack, integrate
  on next release after publication.

### CR-3: Pester coverage is measured on a subset of modules
- 96.18% coverage applies to 3 modules (03-InputValidation,
  22-Password, 02-Logging). The other 62 modules are covered by the
  regex-pattern harness, which is structural rather than line-based.
- Mitigation: expanding measured coverage is a tracked roadmap item
  (`ROADMAP.md` Next quarter).
- Honest scope statement: a Pester-measured 96% is not the same as a
  whole-codebase 96%; readers should weight the regex harness's
  4598-pattern coverage alongside.

### CR-4: ps2exe PE timestamp non-determinism
- The compiled EXE has a PE COFF timestamp field that's set by ps2exe
  to "now" at build time. Two builds from the same source produce
  different SHA-256 hashes for that reason alone.
- Mitigation: `release-hashes.txt` is signed per-build; downstream
  verifiers check the cosign signature, not bit-for-bit reproducibility
  with their own rebuild.
- Tracking: a ps2exe patch upstream could fix this; not currently
  planned to fork.

### CR-5: Operator can disable defenses
- An operator with admin rights can edit `defaults.json` to skip
  BitLocker recovery checks, disable Defender exclusions, or run
  destructive operations without confirmation prompts via `-Silent`.
- Mitigation: documented defaults are safe; out-of-scope per the
  threat model.

---

## How this document is maintained

- **Audit rounds** (33 done; ongoing) are the primary source of
  evidence. When a round finds a new finding, the matching SC- or CR-
  section is updated in the same commit that ships the fix.
- **Significant architectural changes** (e.g. moving state under
  `%ProgramData%` in v1.98.55) update the trust-boundary diagram
  *before* the change is merged.
- **Reader feedback** is welcome via issue. The assurance case is the
  project's public claim about itself; if a reader can show a sub-claim
  is unjustified, that's a high-value report.

---

## References

- [SECURITY.md](../SECURITY.md) — vulnerability disclosure process and supported versions
- [GOVERNANCE.md](../GOVERNANCE.md) — decision rights and bus-factor mitigation
- [ROADMAP.md](../ROADMAP.md) — what's planned for the next 12 months
- [Changelog.md](../Changelog.md) — full per-release history including all audit-driven fixes
- [PSScriptAnalyzerSettings.psd1](../PSScriptAnalyzerSettings.psd1) — static-analysis ruleset + per-rule justification for suppressions
