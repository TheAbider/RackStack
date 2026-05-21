# Chocolatey package

`rackstack.nuspec` + `tools/` is the Chocolatey package scaffold. Publishing
to the public Chocolatey Community Repository is a one-time setup with
ongoing review for each new version. Slower than winget or scoop, but
worth doing because a meaningful fraction of Windows admins still rely on
`choco install` as their primary package manager.

## Build the .nupkg locally

```powershell
# Install Chocolatey CLI if not already present
Set-ExecutionPolicy Bypass -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Replace version + checksum placeholders with the real values for the
# release you're packaging
$ver = '1.98.57'
$exeHash = (Get-FileHash "..\..\builds\RackStack.exe" -Algorithm SHA256).Hash.ToLower()
(Get-Content tools\chocolateyinstall.ps1) `
    -replace '__VERSION__', $ver `
    -replace '__CHECKSUM_SHA256__', $exeHash `
    | Set-Content tools\chocolateyinstall.ps1
(Get-Content rackstack.nuspec) -replace '<version>0\.0\.0</version>', "<version>$ver</version>" | Set-Content rackstack.nuspec

# Pack
choco pack rackstack.nuspec
```

The result is `rackstack.$ver.nupkg`.

## Submit to community.chocolatey.org

1. Sign up at https://community.chocolatey.org/account/Register (free).
2. Generate an API key at https://community.chocolatey.org/account.
3. Push the package:
   ```powershell
   choco apikey --key <YOUR_KEY> --source https://push.chocolatey.org/
   choco push rackstack.$ver.nupkg --source https://push.chocolatey.org/
   ```
4. **Wait for community moderation review.** First-time submissions get
   stricter review; subsequent updates from the same publisher are usually
   approved within a few business days. Reviewers check the install script,
   verify URL + checksum, and ensure the package follows Chocolatey
   guidelines. Be ready to respond to comments on the package page.

## Automation (already wired)

Per-release Chocolatey publishing is automated as a step in
`.github/workflows/ci.yml` — it runs inside the release job, right after
the GitHub Release is created, gated on the `CHOCO_API_KEY` repo secret.
It stamps this directory's templated `rackstack.nuspec` +
`tools/chocolateyinstall.ps1` with the release version and the EXE's
SHA-256, runs `choco pack`, and `choco push`es to
`https://push.chocolatey.org/`.

It is inlined into ci.yml rather than a separate `release:`-triggered
workflow because a release created with `GITHUB_TOKEN` does not trigger
`release` event workflows (GitHub's recursion-prevention).

The first submission of the `rackstack` package ID still goes through
Chocolatey community moderation review regardless — the workflow pushes
it, then the maintainer watches the package page and responds to any
moderator comments. Subsequent versions from an established publisher
are usually auto-approved.

## Verification

After install, verify the binary's Sigstore signature:

```powershell
$exe = (Get-Command RackStack.exe).Source
cosign verify-blob `
  --certificate "$exe.pem" `
  --signature "$exe.sig" `
  --certificate-identity-regexp "^https://github.com/TheAbider/RackStack/.github/workflows/ci.yml@refs/heads/master$" `
  --certificate-oidc-issuer https://token.actions.githubusercontent.com `
  $exe
```

Note: Chocolatey downloads the EXE separately at install time, so the
`.sig` and `.pem` files aren't automatically alongside the install. To
verify, download them from the matching GitHub Release.
