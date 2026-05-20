# Security Policy

## Reporting a Vulnerability

**Please do not open a public GitHub issue for security vulnerabilities.**

Report privately via one of these channels, in order of preference:

1. **GitHub Security Advisories** (preferred):
   https://github.com/TheAbider/RackStack/security/advisories/new
   This notifies the maintainer directly and keeps the discussion private
   until a fix ships.
2. **Email the maintainer** via the address listed on the GitHub profile at
   https://github.com/TheAbider.

Please include:
- Description of the vulnerability and its real-world impact (what an
  attacker can do with it)
- Affected version(s) — `Get-RackStackVersion` output is fine
- Steps to reproduce or a minimal proof-of-concept
- Your preferred credit name (or a request to remain anonymous)

### Response timeline

| Stage                         | Target              |
| ----------------------------- | ------------------- |
| Acknowledgement of report     | within 5 business days  |
| Triage + severity assessment  | within 10 business days |
| Fix + coordinated release (Tier 1) | within 14 days where feasible |
| Public advisory + credit      | after fix ships, in coordination with reporter |

Severity is classified Tier 1 / Tier 2 / Tier 3 by blast radius. Tier 1 =
silent privilege escalation, credential leak, or data-destruction without
operator consent — these are patched as quickly as feasible. Tier 2/3
follow the regular release cadence.

This is a personal open-source project. We can't offer a bug bounty;
credit in the GitHub Security Advisory and Changelog is the only
acknowledgement we can provide.

## Supported Versions

Only the latest released version receives security updates. RackStack
ships a single-track release model — fixes land on master and publish as
the next patch (`x.y.Z`) release.

| Version            | Supported           |
| ------------------ | ------------------- |
| Latest release     | :white_check_mark:  |
| Older releases     | :x: (please update) |

Check the latest at
https://github.com/TheAbider/RackStack/releases/latest or via
`Test-RackStackUpdate` from the PowerShell Gallery module.

## Scope

In scope:
- `RackStack.exe` binary distributed via GitHub Releases
- The PowerShell Gallery wrapper module (`RackStack.psd1` / `RackStack.psm1`)
- The monolithic `RackStack v{version}.ps1` and the modular loader + `Modules/`
- `Install-RackStack.ps1` bootstrap installer
- Any code path that runs with the Administrator privileges the tool requires

Issues of particular concern:
- Command / argument injection via operator input or `defaults.json` fields
- Credential exposure in transcripts, logs, exports, or error messages
- Privilege escalation beyond the intended Administrator scope (or across
  a remote-PowerShell trust boundary)
- Path traversal, symlink/junction attacks, TOCTOU races in destructive ops
- Secrets leaking into git history, configuration exports, or HTML reports

Out of scope:
- Vulnerabilities in Windows itself or third-party modules (`Pester`,
  `PSScriptAnalyzer`, `ps2exe`) — please report those upstream
- Operator misconfiguration where the documented default is safe
- Findings that require an attacker who is already Administrator on the
  same machine (RackStack runs as Administrator by design)

## Verifying releases

Every release publishes a `release-hashes.txt` containing SHA-256 hashes
for the EXE, the monolithic `.ps1`, and `defaults.example.json`. Verify
before running:

```powershell
(Get-FileHash RackStack.exe -Algorithm SHA256).Hash.ToLower()
```

Once SignPath Foundation signing is active (in progress), the EXE will
also be Authenticode-signed by SignPath Foundation. Verify with:

```powershell
Get-AuthenticodeSignature -FilePath RackStack.exe
```

Signature `Status` should be `Valid` and the signer subject should
contain `SignPath Foundation`.

## defaults.json

The `defaults.json` file may contain sensitive data (Cloudflare Access
client secrets, KMS host keys, AD service-account hints). It is gitignored
by default. `defaults.example.json` contains only placeholder values; that
is the file that ships in releases. Never commit a populated
`defaults.json` to a public repository.

## Acknowledgements

Reporters of accepted vulnerabilities will be credited here once
advisories are published, unless they request anonymity.
