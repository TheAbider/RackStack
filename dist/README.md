# Distribution channels

RackStack ships through multiple Windows package managers in addition to
the GitHub Releases page. This directory holds the per-channel manifests
and submission scaffolding.

| Channel | Status | One-liner install |
|---|---|---|
| [GitHub Releases](https://github.com/TheAbider/RackStack/releases/latest) | ✅ Live (every release) | Download `RackStack.exe`, run as Administrator |
| [PowerShell Gallery](https://www.powershellgallery.com/packages/RackStack) | ✅ Live (every release) | `Install-Module RackStack` |
| [Scoop](https://scoop.sh/) | ✅ Live — bucket published | `scoop bucket add rackstack https://github.com/TheAbider/scoop-bucket; scoop install rackstack` |
| [Chocolatey](https://community.chocolatey.org/packages/rackstack) | ⏳ Submitted — in community moderation review | `choco install rackstack` |
| [winget](https://github.com/microsoft/winget-pkgs) | ⏳ First-submission manifests ready (`dist/winget/1.99.1/`); awaiting the one-time PR to winget-pkgs | `winget install TheAbider.RackStack` |

## winget

Automated as a step in `.github/workflows/ci.yml` — it runs inside the
release job right after the GitHub Release is created. (It is inlined
rather than a separate `release:`-triggered workflow because a release
created with `GITHUB_TOKEN` does not trigger `release` event workflows.)
The step uses Microsoft's `wingetcreate` CLI directly — not a winget
submission Action, because the popular one pulls in an unpinned
transitive action that the repo's SHA-pinning policy rejects.

`wingetcreate update` requires the package to already exist in
`microsoft/winget-pkgs`. So the **first** submission of
`TheAbider.RackStack` is a one-time manual step; every release after
that is automated.

**Setup:**
1. `WINGET_TOKEN` (a Personal Access Token, classic, `public_repo` scope)
   is already set as a repo secret — the ci.yml step uses it for the
   automated update PRs.
2. **First submission (one-time, manual):** the three ready-to-submit
   manifest files are pre-authored in `dist/winget/1.99.1/`. Fork
   `microsoft/winget-pkgs`, drop those three files into
   `manifests/t/TheAbider/RackStack/1.99.1/`, and open a PR. Full steps
   in `dist/winget/README.md`.
3. After that first PR merges, every release auto-submits via the ci.yml
   `wingetcreate update` step — no further action needed.

## Scoop

See `scoop/README.md`. Two paths:
- **Option A (recommended):** create `https://github.com/TheAbider/scoop-bucket`
  and drop `scoop/rackstack.json` in it.
- **Option B:** submit to the official `ScoopInstaller/Extras` bucket.

## Chocolatey

See `chocolatey/README.md`. First submission requires manual community
moderation review — slower than winget/scoop. Once approved, subsequent
releases can be automated via the `CHOCO_API_KEY` secret.

## Verification (every channel)

After install, the binary should be Sigstore-cosign-signed and
SLSA Level 3 provenance-attested. Verify with:

```powershell
# Cosign keyless signature
$exe = (Get-Command RackStack.exe).Source
cosign verify-blob `
  --certificate "$exe.pem" `
  --signature "$exe.sig" `
  --certificate-identity-regexp "^https://github.com/TheAbider/RackStack/.github/workflows/ci.yml@refs/heads/master$" `
  --certificate-oidc-issuer https://token.actions.githubusercontent.com `
  $exe

# GitHub-native attestation
gh attestation verify RackStack.exe --owner TheAbider
```

The `.sig` and `.pem` files are always attached to the matching GitHub
Release. Some package managers (scoop, chocolatey) don't download these
alongside the binary; download them manually from the release page if
you want to verify post-install.
