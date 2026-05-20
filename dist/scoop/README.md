# Scoop manifest

`rackstack.json` is the Scoop package manifest. It can be served two ways:

## Option A: Custom bucket (recommended, single-maintainer-friendly)

1. Create a new public repo at `https://github.com/TheAbider/scoop-bucket`.
2. Copy `rackstack.json` from this directory into the new repo's root or `bucket/` directory.
3. Update the `version`, `url`, and `hash` fields to match the current release (or rely on the embedded `checkver` / `autoupdate` blocks to do that automatically via scoop maintainer tools).
4. Users install via:
   ```powershell
   scoop bucket add rackstack https://github.com/TheAbider/scoop-bucket
   scoop install rackstack
   scoop update rackstack    # picks up new releases via autoupdate
   ```

## Option B: Submit to ScoopInstaller/Extras

The official `extras` bucket maintained by the Scoop community. Submission via PR to https://github.com/ScoopInstaller/Extras. Pros: discovered by default `scoop search`. Cons: subject to community review and the bucket maintainers' ongoing approval. The `checkver` block in this manifest is already in the format that the Extras bucket's auto-update bot understands.

## Automation

Once the bucket repo exists, a workflow can keep the manifest version + hash in sync with new GitHub releases. The simplest path is the official `MCOfficer/scoop-updater` action which runs `scoop checkver` on a schedule and opens PRs against the bucket. Manual maintenance also works for low-frequency releases.

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
