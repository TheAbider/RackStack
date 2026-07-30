# winget manifests

The very first submission of `TheAbider.RackStack` to winget had to be
done by hand -- `wingetcreate update` (the CI automation in `ci.yml`) only
works once the package already exists in `microsoft/winget-pkgs`.

A first submission was made with version 1.122.0
(https://github.com/microsoft/winget-pkgs/pull/403660) and then
voluntarily withdrawn before review; it will be resubmitted later.
The manifests in `1.122.0/` validated cleanly with `winget validate`
and the CLA is already signed for this account, so resubmitting is
just: re-author the folder for the current version (version, URL,
SHA-256, ReleaseDate), fork/branch, open the PR.

Once a first PR merges, every future release auto-submits via the
ci.yml step -- do not hand-maintain these files after that.

## Notes on the manifest choices

- **`InstallerType: portable`** -- `RackStack.exe` is a standalone
  ps2exe-compiled executable, not an installer. winget installs it as a
  portable package: it places the EXE and registers a PATH alias.
- **`Commands: [rackstack]`** -- so `rackstack` works from any shell
  after install. The EXE auto-elevates itself when run.
- **`Platform: [Windows.Desktop]`** -- the winget 1.6 schema's Platform
  enum only allows `Windows.Desktop` and `Windows.Universal`; there is
  no `Windows.Server` value (an earlier draft of these manifests had one
  and failed `winget validate`). winget itself runs fine on Windows
  Server; the enum simply does not model it.
- **`InstallerSha256`** -- must match the released `RackStack.exe` for
  the manifest's version. If a manifest is ever re-authored by hand,
  update the version, URL, SHA-256, and `ReleaseDate` in all three
  files, then run `winget validate --manifest <folder>`.

## Release retention: releases are never deleted

Earlier versions of `ci.yml` deleted the previous patch release within a
minor when a new one published, which meant a published winget manifest's
`InstallerUrl` went dead as soon as the next patch shipped.

That retention step has been removed. Release assets are permanent, because
every package registry pins the asset URL for its own version and keeps
approved versions indefinitely. The same defect silently broke the approved
Chocolatey package (`choco install rackstack` returned 404 for about two
months) before it was found on 2026-07-29.

Do not reintroduce release deletion. `Run-Tests` section 206 fails the suite
if any workflow calls `gh release delete` or `--cleanup-tag`.
