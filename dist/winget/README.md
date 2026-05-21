# winget manifests

The very first submission of `TheAbider.RackStack` to winget has to be
done by hand — `wingetcreate update` (the CI automation in `ci.yml`) only
works once the package already exists in `microsoft/winget-pkgs`.

`1.99.1/` contains the three ready-to-submit manifest files. After this
first PR merges, every future release auto-submits via the ci.yml step.

## First submission — copy-paste PR

1. Fork **https://github.com/microsoft/winget-pkgs**.
2. In your fork, create the path:
   `manifests/t/TheAbider/RackStack/1.99.1/`
3. Copy the three files from `1.99.1/` here into that folder:
   - `TheAbider.RackStack.yaml` (version)
   - `TheAbider.RackStack.installer.yaml` (installer)
   - `TheAbider.RackStack.locale.en-US.yaml` (default locale)
4. (Optional, on a Windows box) validate before submitting:
   ```powershell
   winget validate --manifest manifests\t\TheAbider\RackStack\1.99.1
   ```
5. Commit and open a PR against `microsoft/winget-pkgs`. Title it
   `New package: TheAbider.RackStack version 1.99.1`.
6. The winget-pkgs validation pipeline runs automatically (it installs
   the package in a sandbox and checks the manifests). Once it's green
   and a moderator approves, `winget install TheAbider.RackStack` goes
   live.

## After the first submission

Don't hand-maintain these files going forward. The `ci.yml` release job
runs `wingetcreate update TheAbider.RackStack ...` on every release,
which regenerates the manifests from the winget-pkgs entry and opens the
update PR automatically. This `1.99.1/` folder is kept only as a record
of the initial submission.

## Notes on the manifest choices

- **`InstallerType: portable`** — `RackStack.exe` is a standalone
  ps2exe-compiled executable, not an installer. winget installs it as a
  portable package: it places the EXE and registers a PATH alias.
- **`Commands: [rackstack]`** — so `rackstack` works from any shell
  after install. The EXE auto-elevates itself when run.
- **`InstallerSha256`** — must match the v1.99.1 `RackStack.exe`. If you
  re-author for a later version, update the version, URL, SHA-256, and
  `ReleaseDate` in all three files.
