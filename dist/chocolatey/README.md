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

## Automation (optional, after first publish)

Once your API key is set as the `CHOCO_API_KEY` GitHub secret, a CI step
could automate per-release builds and pushes. The Chocolatey CLI is
installable on `windows-latest` GitHub runners. A skeleton workflow:

```yaml
- name: Build and push Chocolatey package
  if: github.event.release.tag_name
  env:
    CHOCO_API_KEY: ${{ secrets.CHOCO_API_KEY }}
  shell: pwsh
  run: |
    $ver = '${{ github.event.release.tag_name }}' -replace '^v',''
    $hash = (Get-FileHash 'builds/RackStack.exe' -Algorithm SHA256).Hash.ToLower()
    cd dist/chocolatey
    (Get-Content tools/chocolateyinstall.ps1) `
      -replace '__VERSION__',$ver `
      -replace '__CHECKSUM_SHA256__',$hash `
      | Set-Content tools/chocolateyinstall.ps1
    (Get-Content rackstack.nuspec) -replace '<version>0\.0\.0</version>', "<version>$ver</version>" | Set-Content rackstack.nuspec
    choco pack rackstack.nuspec
    choco apikey --key $env:CHOCO_API_KEY --source https://push.chocolatey.org/
    choco push "rackstack.$ver.nupkg" --source https://push.chocolatey.org/
```

Skipping the automation initially is fine — the first submission needs
manual review anyway, so do it by hand the first time, then automate after
the publisher reputation is established.

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
