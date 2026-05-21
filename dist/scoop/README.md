# Scoop manifest

`rackstack.json` here is a reference **template** (version `0.0.0`,
zeroed hash). The **live** manifest users actually install from lives in
the dedicated bucket repo with real version + hash values — see below.

## Live: custom bucket — ✅ published

The bucket is live at **https://github.com/TheAbider/scoop-bucket**.
Users install with:

```powershell
scoop bucket add rackstack https://github.com/TheAbider/scoop-bucket
scoop install rackstack
scoop update rackstack    # picks up new releases
```

When a new RackStack version ships, update the bucket repo's
`rackstack.json` — bump the `version`, `url`, and `hash` to the new
release (the EXE SHA-256 is in that release's `release-hashes.txt`).
The manifest's embedded `checkver` / `autoupdate` blocks let Scoop's
maintainer tooling do this automatically if a `scoop-updater` workflow
is added to the bucket repo later.

## Optional: submit to ScoopInstaller/Extras

The official `extras` bucket maintained by the Scoop community.
Submission via PR to https://github.com/ScoopInstaller/Extras. Pro:
discoverable by default `scoop search` without adding the custom
bucket. Con: subject to community review. The `checkver` block in this
manifest is already in the format the Extras auto-update bot understands.
Not required — the custom bucket above already works.

## Verification

After install, verify the EXE Sigstore signature:

```powershell
$exe = (scoop which rackstack.exe)
cosign verify-blob `
  --certificate "$exe.pem" `
  --signature "$exe.sig" `
  --certificate-identity-regexp "^https://github.com/TheAbider/RackStack/.github/workflows/ci.yml@refs/heads/master$" `
  --certificate-oidc-issuer https://token.actions.githubusercontent.com `
  $exe
```
