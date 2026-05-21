# Roadmap

This document describes what RackStack plans to do — and explicitly not
do — over the next twelve months. It exists to satisfy the OpenSSF Best
Practices Silver-tier `documentation_roadmap` criterion and to set
expectations for any external contributors evaluating where to invest
time.

The roadmap is intentionally narrow. RackStack is a single-maintainer
project; commitments here are realistic, not aspirational.

Last updated: **2026-05-20** (v1.98.55).

---

## Now (next 30 days)

| Item | Status | Why |
|---|---|---|
| OpenSSF Best Practices **Silver** badge | In progress (Passing earned; this roadmap + GOVERNANCE.md + ASSURANCE_CASE.md unblock Silver) | Silver tier is achievable; Gold is structurally blocked by single-maintainer bus factor. |
| GPG-signed git tags | Planned | Closes the OpenSSF `version_tags_signed` criterion. One-time `git config commit.gpgsign true` + `tag.gpgsign true` + key registration at https://github.com/TheAbider.gpg. |
| Codecov coverage badge | In progress (token added; waiting for next CI upload to populate) | Public coverage % surface. |

## Next quarter (June–August 2026)

| Item | Why |
|---|---|
| Expand Pester coverage to 4 more modules (`07-IPConfiguration`, `13-Timezone`, `21-Licensing`, `06-NetworkAdapters`) | Currently coverage is measured against 3 modules; broadening the denominator while keeping coverage above 90% improves Codecov / Scorecard signal. |
| `SBOM` for the PSGallery module specifically (separate from the EXE SBOM) | Currently SBOM scans the whole repo as a directory; an explicit module-only SBOM would let consumers verify the `RackStack.psd1` + `RackStack.psm1` dependency surface independently. |
| Documentation generator polish | The PlatyPS-generated cmdlet docs at `theabider.github.io/RackStack/cmdlets/` need a theme + nav. Currently they render as flat markdown. |
| Anchor 1.98 release line; cut a `1.99-rc1` if a breaking change becomes necessary | If a defaults.json schema change is needed for new features, that's a 2.0 candidate. No such change is currently planned. |

## Later (September 2026 – April 2027)

| Item | Why |
|---|---|
| Optional: ARM64 EXE | If demand emerges. ps2exe + .NET on ARM64 is straightforward; CI matrix expansion only. |
| Optional: PowerShell 7 module path | The thin-wrapper module already supports both editions via the `.psd1` `CompatiblePSEditions = @('Desktop', 'Core')`. A PS7-only feature track is not currently planned. |
| `RackStack.exe -Action FleetScan` improvements (PSRemoting over WinRM HTTPS, parallel host limits) | Adoption-driven — only if a real multi-host operator surfaces concrete asks. |

## Explicitly not on the roadmap

| Item | Why not |
|---|---|
| Cross-platform port (Linux, macOS) | RackStack's entire purpose is Windows Server configuration. Hyper-V, BitLocker, Failover Clustering, MPIO, AD DS, iSCSI initiator — none of these have a meaningful Linux/macOS equivalent in the same workflow. A port would be a different project. |
| Switch from PowerShell to C# / Go / Rust | The existing 70K LOC + 65 modules + 4598 regression tests would be lost. Rewrite cost-benefit is not justifiable. |
| GUI front-end | The 72-char box-drawing console UI is intentional; it works over RDP, SSH-tunneled PowerShell, and emergency console-only scenarios where a GUI cannot. |
| Web dashboard | Out of scope. Operators integrate via the `-OutputFormat JSON` CLI surface and route into their own dashboards. |
| External REST API | Same as above — `-OutputFormat JSON` is the integration surface. |
| Major version bumps without operator pain | The 1.98.x line will continue with backwards-compatible additions. A 2.0 release would only happen for a `defaults.json` schema break, and would include a documented one-shot migration tool. |
| OSS-Fuzz integration | OSS-Fuzz primarily supports C/C++/Go/Python/JVM. PowerShell is not supported. The existing Pester property-based fuzz harness covers the validator surface; expanding it to more functions is a maintenance task, not a roadmap item. |
| Multi-maintainer transition | Not currently planned. If the project grows beyond solo development, `GOVERNANCE.md` documents the transition path. |

## Release cadence

- **Patch releases** (`x.y.Z`) ship as needed for security fixes (Tier 1: within 14 days of confirmed disclosure, per `SECURITY.md`).
- **Minor releases** (`x.Y.0`) — feature batches, typically every few weeks during active development.
- **Major releases** (`X.0.0`) — only when a backwards-incompatible `defaults.json` schema or CLI surface change is unavoidable. None currently planned.
- The current line is **1.98.x**. CI auto-bumps and auto-releases on every commit to `master` that bumps `Header.ps1` `.VERSION`.

## How this roadmap is maintained

This file is updated:
- On every patch release that completes a "Now" item (item moves to a "Completed" section in the next revision and the changelog records it).
- Quarterly, to refresh the "Next quarter" and "Later" sections.
- Whenever the maintainer decides to add or remove a "Not on the roadmap" item.

Updates are tracked via PR like any other source file. Issues that
request roadmap additions are welcome and read; the maintainer prefers
issues over private mail for roadmap discussions so the rationale is
preserved publicly.
