# Roadmap

This document describes what RackStack plans to do — and explicitly not
do — over the next twelve months. It exists to satisfy the OpenSSF Best
Practices Silver-tier `documentation_roadmap` criterion and to set
expectations for any external contributors evaluating where to invest
time.

The roadmap is intentionally narrow. RackStack is a single-maintainer
project; commitments here are realistic, not aspirational.

Last updated: **2026-05-30** (v1.119.1).

Recently shipped: the **v1.109.0 → v1.119.0 feature arc** — eleven
serial minor releases covering VHDX encryption-at-rest verification
(31), AD DS Recycle Bin enablement (61), Failover Cluster Validation
Report (27), richer VM inventory export (50), SMB signing/encryption
enforcement (56), print-server cleanup (35), in-box network throughput
benchmarking (58), NTP clock-tamper protection (19), and three new
modules: **78-CertificateAudit** (service-certificate binding audit),
**79-DFS** (DFS Namespaces & Replication), and
**80-RemoteDesktopServices** (RDS role lifecycle + licensing-mode
configuration). v1.119.1 then cleared two CI deprecation notices
(`actions/attest-sbom` → `actions/attest`; `windows-latest` →
`windows-2025`). RackStack is now **81 modules, 201 CLI actions, and
5,167 structural regression tests** (plus the Pester suite).

A recurring theme of that arc: where a planned mutation could not be
implemented safely or verified honestly, it was **deferred with a written
rationale rather than shipped untested** — see "Deferred" below.

---

## Now (next 30 days)

| Item | Status | Why |
|---|---|---|
| OpenSSF Best Practices **Silver** badge | **Earned** (Passing + Silver both achieved) | Gold is structurally blocked by the single-maintainer bus factor. |
| In-program defaults editor + Extended Undo | Planned | Edit `rackstack.config.json` / `<company>.rackstack.config.json` from inside the tool with hot-reload, and extend the single-level undo to multi-step. Both compose with the Dry-Run queue and need no schema break. Still unbuilt as of v1.119.x. |
| GPG-signed git tags | Planned | Closes the OpenSSF `version_tags_signed` criterion. One-time `git config commit.gpgsign true` + `tag.gpgsign true` + key registration at https://github.com/TheAbider.gpg. CI currently auto-tags releases without a maintainer GPG signature. |

## Next quarter (June–August 2026)

| Item | Why |
|---|---|
| Expand Pester coverage to 4 more modules (`07-IPConfiguration`, `13-Timezone`, `21-Licensing`, `06-NetworkAdapters`) | Coverage is measured against a small module set; broadening the denominator while keeping coverage above 90% improves Codecov / Scorecard signal. |
| `SBOM` for the PSGallery module specifically (separate from the EXE SBOM) | The SBOM currently scans the whole repo as a directory; an explicit module-only SBOM would let consumers verify the `RackStack.psd1` + `RackStack.psm1` dependency surface independently. |
| Documentation generator polish | The PlatyPS-generated cmdlet docs at `theabider.github.io/RackStack/cmdlets/` need a theme + nav. Currently they render as flat markdown. |
| Revisit the windows-2025 → VS2026 image migration (2026-06-15) | The runners are pinned to `windows-2025`; GitHub moves that image's Visual Studio sub-image to VS2026 on 2026-06-15. RackStack's pipeline never invokes the VS toolchain, so this is expected to be a no-op — confirm green after the migration and update this line. |

## Deferred (built or scoped, then intentionally held back)

These were prototyped or designed during the v1.109–v1.119 arc and
deferred for correctness/safety reasons. They are the most likely source
of the next feature releases once they can be validated safely.

| Item | Why deferred | What unblocks it |
|---|---|---|
| RDP listener certificate **rotation** (extends `78-CertificateAudit`, which today only audits) | An adversarial review surfaced a real RDP lock-out risk — a freshly self-signed cert's private key is not readable by `NETWORK SERVICE` by default, and CIM writability of `SSLCertificateSHA1Hash` varies by Windows build. | A correct private-key ACL grant, validated on a live, elevated, RDP-enabled server (not testable on the dev workstation). |
| RDS **session-collection quick-deploy** + CAL activation (extends `80-RemoteDesktopServices`, which today does role install + licensing mode) | `New-RDSessionDeployment` reconfigures the server and needs a reboot; CAL activation is done against a license agreement in RD Licensing Manager, where that key material belongs. | A real RDS-capable server to validate the deployment flow; CAL/key handling stays in the GUI by design. |
| `diskspd` storage benchmarking | `diskspd.exe` is a separate Microsoft download, not in-box, and RackStack does not auto-download unverified binaries. | A detect-and-orchestrate model: run only when the operator has placed `diskspd.exe` on the host (same pattern as any operator-provided tool). |
| WinRM HTTPS listener certificate rotation (read-only in `78` today) | Rebuilding the HTTPS listener can disrupt an active remoting session. | Same RDP-rotation groundwork above, plus a safe listener-swap path. |

## Later (September 2026 – April 2027)

| Item | Why |
|---|---|
| Optional: ARM64 EXE | If demand emerges. ps2exe + .NET on ARM64 is straightforward; CI matrix expansion only. |
| Optional: PowerShell 7 module path | The thin-wrapper module already supports both editions via the `.psd1` `CompatiblePSEditions = @('Desktop', 'Core')`. A PS7-only feature track is not currently planned. |
| `RackStack.exe -Action FleetScan` improvements (PSRemoting over WinRM HTTPS, parallel host limits) | Adoption-driven — only if a real multi-host operator surfaces concrete asks. |

## Explicitly not on the roadmap

| Item | Why not |
|---|---|
| Server Core ↔ Server-with-Desktop conversion | Dropped during roadmap design. Windows Server 2019 and later removed in-place conversion between the Server Core and Desktop Experience installation options, so there is no supported, reversible operation for the tool to wrap. |
| Cross-platform port (Linux, macOS) | RackStack's entire purpose is Windows Server configuration. Hyper-V, BitLocker, Failover Clustering, MPIO, AD DS, iSCSI initiator — none of these have a meaningful Linux/macOS equivalent in the same workflow. A port would be a different project. |
| Switch from PowerShell to C# / Go / Rust | The existing 81 modules + 5,167 regression tests would be lost. Rewrite cost-benefit is not justifiable. |
| GUI front-end | The 72-char box-drawing console UI is intentional; it works over RDP, SSH-tunneled PowerShell, and emergency console-only scenarios where a GUI cannot. |
| Web dashboard | Out of scope. Operators integrate via the `-OutputFormat JSON` CLI surface and route into their own dashboards. |
| External REST API | Same as above — `-OutputFormat JSON` is the integration surface. |
| Major version bumps without operator pain | The 1.x line will continue with backwards-compatible additions. A 2.0 release would only happen for a `rackstack.config.json` schema break, and would include a documented one-shot migration tool. |
| OSS-Fuzz integration | OSS-Fuzz primarily supports C/C++/Go/Python/JVM. PowerShell is not supported. The existing Pester property-based fuzz harness covers the validator surface; expanding it to more functions is a maintenance task, not a roadmap item. |
| Multi-maintainer transition | Not currently planned. If the project grows beyond solo development, `GOVERNANCE.md` documents the transition path. |

## Release cadence

- **Patch releases** (`x.y.Z`) ship as needed for security fixes (Tier 1: within 14 days of confirmed disclosure, per `SECURITY.md`) and for CI/maintenance fixes (e.g. v1.119.1).
- **Minor releases** (`x.Y.0`) — feature batches; the v1.109–v1.119 arc shipped them one feature at a time.
- **Major releases** (`X.0.0`) - only when a backwards-incompatible `rackstack.config.json` schema or CLI surface change is unavoidable. None currently planned.
- The current line is **1.119.x**. CI auto-bumps and auto-releases on every commit to `master` that bumps `Header.ps1` `.VERSION`.

## How this roadmap is maintained

This file is updated:
- On every release that completes or defers a roadmap item (the item moves to the appropriate section and the changelog records it).
- Quarterly, to refresh the "Next quarter" and "Later" sections.
- Whenever the maintainer decides to add or remove a "Not on the roadmap" item.

Updates are tracked via PR like any other source file. Issues that
request roadmap additions are welcome and read; the maintainer prefers
issues over private mail for roadmap discussions so the rationale is
preserved publicly.
