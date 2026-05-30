# Governance

This document describes how decisions get made in the RackStack project,
who holds which role, and how the project keeps moving if any one person
becomes unavailable.

It exists to satisfy the OpenSSF Best Practices Silver-tier criteria
[`governance`], [`roles_responsibilities`], and [`access_continuity`].

---

## Model

RackStack uses a **single-maintainer benevolent dictator** model.

The maintainer ([@TheAbider](https://github.com/TheAbider)) makes every
substantive decision about scope, priorities, release timing, and the
architectural direction of the codebase. There is no formal steering
committee, no rotation schedule, and no voting mechanism. The maintainer
also acts as release manager, security responder, infrastructure
operator, and primary code reviewer.

This model is appropriate for the project's current size (single
contributor, ~70K LOC, ~1 active user beyond the maintainer). If the
project grows past a few external contributors or beyond a single
operational user, the maintainer commits to revisiting this document
and transitioning to a multi-maintainer model with documented decision
rights.

## Decision process

| Decision class                          | Who decides    | How it's communicated                                       |
| --------------------------------------- | -------------- | ----------------------------------------------------------- |
| New feature scope                       | Maintainer     | Issue or PR discussion; merged commit                       |
| Breaking change to public CLI surface   | Maintainer     | Changelog "BREAKING" entry + major version bump (when applicable) |
| Release timing                          | Maintainer     | Version bump in `Header.ps1`; CI auto-releases              |
| Security fix prioritization             | Maintainer     | Per [SECURITY.md](SECURITY.md) Tier 1 / 2 / 3 classification |
| Dependency updates                      | Dependabot + maintainer | Auto-PR + maintainer merge                       |
| Code-quality rules (PSSA, formatting)   | Maintainer     | `PSScriptAnalyzerSettings.psd1` + `CONTRIBUTING.md`         |
| Project governance changes              | Maintainer     | This file; PR-tracked                                       |

Anyone is welcome to open an issue or PR. Discussions are public.
External contributions are accepted at the maintainer's discretion;
the maintainer aims to respond to issues within 5 business days and to
PRs within 10 business days.

## Roles and responsibilities

| Role               | Holder                                        | Responsibilities                                                                                          |
| ------------------ | --------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Maintainer         | [@TheAbider](https://github.com/TheAbider)    | All decision rights above; merges PRs; bumps versions; responds to issues and disclosures.                |
| Release manager    | [@TheAbider](https://github.com/TheAbider)    | Bumps `Header.ps1` `.VERSION`; CI auto-builds, signs, and publishes to GitHub Releases + PowerShell Gallery. |
| Security responder | [@TheAbider](https://github.com/TheAbider)    | Receives GHSA reports; triages per SECURITY.md timeline; coordinates fixes and public advisories.         |
| Infra operator     | [@TheAbider](https://github.com/TheAbider)    | Manages GitHub repository settings, secrets, and rulesets; rotates `PSGALLERY_API_KEY` and `CODECOV_TOKEN`. |
| Code reviewer      | [@TheAbider](https://github.com/TheAbider)    | Reviews all non-Dependabot PRs; verifies CI is green before merge.                                        |

When this model transitions to multi-maintainer, this table will gain
additional rows naming the second maintainer and their explicit role
overlap.

## Continuity (bus-factor mitigation)

The project's bus factor is currently **1**. The following mitigations
limit the impact if the maintainer becomes unavailable:

### Code and history
- **All source is public** at https://github.com/TheAbider/RackStack
  under the MIT License. Any forker can pick up development immediately.
- **Full release history is reproducible** from any tagged commit via
  `.\sync-to-monolithic.ps1` + `Invoke-PS2EXE`. The same source produces
  byte-identical output up to ps2exe's PE timestamp.
- **CI is fully automated and GitHub-hosted.** No self-hosted
  infrastructure is on the critical path; GitHub-hosted `windows-2025`
  runners are free for public repos.

### Signing-key continuity
- **Sigstore cosign keyless signing** uses GitHub Actions OIDC, not a
  long-lived signing key. A fork on a different account can produce
  signatures with the same cryptographic strength immediately, signed
  by that fork's OIDC identity. Verifiers update the
  `--certificate-identity-regexp` to match the new fork's workflow URL.
- **SLSA Level 3 provenance** is produced by GitHub's
  `actions/attest-build-provenance@v2` and recorded in the GitHub
  attestation API; verifiable per-commit by any consumer with
  `gh attestation verify`.

### Repository access
- `master` branch is protected by the `master-protection` ruleset.
  Maintainer holds admin bypass via `bypass_mode: pull_request`.
- The PSGallery upload token (`PSGALLERY_API_KEY`) and Codecov token
  (`CODECOV_TOKEN`) are GitHub Actions repository secrets. A fork
  operator generates their own tokens; no key handoff required.
- DNS for any custom domain (none currently) is not part of the
  critical path — releases are served from `github.com/TheAbider`
  directly.

### Practical resumption plan
If the maintainer is unavailable for >30 days and resumption is
required:

1. Fork the repository under a new maintainer's account.
2. Update the cosign verification command in release notes with the
   new workflow identity URL.
3. Republish to PowerShell Gallery under the new maintainer (or
   continue publishing the same `RackStack` package if PSGallery
   ownership has been transferred).
4. Update `https://github.com/TheAbider/RackStack` README with a
   pointer to the new canonical fork.

No private keys, passwords, or proprietary credentials are required
for the resumption plan; everything depends only on the public source
code and the new maintainer's own GitHub identity.

## Code of conduct

See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). The maintainer enforces
the code of conduct in issues, PRs, and any project communication
channels.

## Changes to this document

Updates to this governance model are tracked via PRs to this file. The
maintainer reviews and merges PRs to GOVERNANCE.md the same way as any
other PR. Substantial changes (e.g. adding a second maintainer) are
announced in the corresponding release's changelog entry.
