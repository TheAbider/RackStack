# Distribution channels

RackStack ships through multiple Windows package managers in addition to
the GitHub Releases page. This directory holds the per-channel manifests
and submission scaffolding.

| Channel | Status | One-liner install |
|---|---|---|
| [GitHub Releases](https://github.com/TheAbider/RackStack/releases/latest) | ✅ Live (every release) | Download `RackStack.exe`, run as Administrator |
| [PowerShell Gallery](https://www.powershellgallery.com/packages/RackStack) | ✅ Live (every release) | `Install-Module RackStack` |
| [winget](https://github.com/microsoft/winget-pkgs) | ⏳ Pending first submission | `winget install TheAbider.RackStack` |
| [Scoop](https://scoop.sh/) | ⏳ Pending bucket creation | `scoop bucket add rackstack https://github.com/TheAbider/scoop-bucket; scoop install rackstack` |
| [Chocolatey](https://community.chocolatey.org/packages) | ⏳ Pending first submission | `choco install rackstack` |

## winget

Automated as a step in `.github/workflows/ci.yml` — it runs inside the
release job right after the GitHub Release is created. (It is inlined
rather than a separate `release:`-triggered workflow because a release
created with `GITHUB_TOKEN` does not trigger `release` event workflows.)
Activates on every release once the `WINGET_TOKEN` repo secret is set
(Personal Access Token classic with `public_repo` scope). The first
submission opens a PR against `microsoft/winget-pkgs` for human review;
subsequent releases auto-submit identical-shape manifests.

**Setup:**
1. Create a Personal Access Token (classic) with `public_repo` scope at
   https://github.com/settings/tokens/new?scopes=public_repo
2. Save it as `WINGET_TOKEN` at
   https://github.com/TheAbider/RackStack/settings/secrets/actions/new
3. The next release will auto-submit a PR to winget-pkgs. Review and merge
   it (your name appears as author).

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
