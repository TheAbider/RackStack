# Contributing to RackStack

Thanks for your interest in contributing! Here's how to get started.

## Getting Started

1. Fork the repo and clone it locally
2. Copy `defaults.example.json` to `defaults.json` and fill in your environment details
3. Make your changes in the `Modules/` directory
4. Run the test suite before submitting

## Development Workflow

```powershell
# 1. Edit modules in Modules/
notepad Modules\07-IPConfiguration.ps1

# 2. Quick test with the modular loader (RackStack.ps1 -- dot-sources modules)
.\RackStack.ps1

# 3. Build the monolithic (RackStack v{version}.ps1 -- single file, used for .exe)
.\sync-to-monolithic.ps1

# 4. Run tests
powershell -ExecutionPolicy Bypass -File Tests\Run-Tests.ps1

# 5. Run PSScriptAnalyzer
powershell -ExecutionPolicy Bypass -File Tests\pssa-check.ps1
```

## Pull Request Checklist

- [ ] All 4,759 tests pass (`Run-Tests.ps1` exits with code 0)
- [ ] PSScriptAnalyzer reports 0 errors (`pssa-check.ps1`)
- [ ] Monolithic synced (`sync-to-monolithic.ps1` shows 0 parse errors)
- [ ] New functions follow PowerShell verb-noun naming (`Get-`, `Set-`, `Test-`, `Show-`)
- [ ] Menu items use `Write-MenuItem` (not raw `Write-Host`)
- [ ] Menu boxes use 72-char inner width
- [ ] No hardcoded organization names, paths, or credentials in code
- [ ] New test(s) added for new functionality

## Code Style

- **Colors:** Use semantic names (`Success`, `Warning`, `Error`, `Info`) not raw color names
- **Null checks:** `$null -eq $var` (not `$var -eq $null` -- PSSA requirement)
- **Regex captures:** Use `$regexMatches` instead of `$matches` (reserved automatic variable)
- **Variables:** Avoid `$input`, `$profile`, `$matches` (all reserved by PowerShell)
- **Menu width:** All menu boxes use 72-char inner width with `PadRight(72)`
- **Strings:** Use `${var}:` not `$var:` when variable name is followed by colon (parse error)
- **Encoding:** All `.ps1` files MUST be saved with UTF-8 BOM encoding (required for Unicode box-drawing characters)

## Adding a New Module

1. Create `Modules/XX-YourModule.ps1` with a `#region` header matching the region name
2. Add the filename to `RackStack.ps1` (modular loader) in the correct load order position
3. Add corresponding tests to `Tests/Run-Tests.ps1`
4. Update the expected module count in `Tests/Validate-Release.ps1` and `Tests/Run-Tests.ps1`

## Adding a New Menu Item

1. Add the menu item display in the appropriate menu function using `Write-MenuItem`
2. Add the handler in the corresponding `switch` block in `49-MenuRunner.ps1`
3. Wire it up with the correct key binding

## Configuration Safety

Never hardcode organization names, domains, contact info, or credentials in module code. Use the `$script:` variables that are loaded from `defaults.json`:

- `$script:Domain` for domain operations
- `$script:SupportContact` for error messages
- DNS, KMS keys, cloud config all come from defaults

## Reporting Issues

- Use the GitHub issue templates (bug report or feature request)
- Include your PowerShell version (`$PSVersionTable.PSVersion`)
- Include your Windows version (`(Get-CimInstance Win32_OperatingSystem).Caption`)
- Paste the full error output if applicable

## License and Developer Certificate of Origin

By submitting a pull request you assert that:

1. The contribution is your own original work, OR you have the right to submit it under the project's MIT License.
2. Your contribution may be redistributed under the MIT License (see [LICENSE](LICENSE)).
3. You agree to the [Developer Certificate of Origin v1.1](https://developercertificate.org/), which is reproduced below:

```
By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

We do not currently require `Signed-off-by:` in commit messages — by opening a PR you are implicitly making the above certification. If the project grows to multiple external contributors this requirement may tighten; the change will be announced in a release note.

## Project governance

See [GOVERNANCE.md](GOVERNANCE.md) for the project's decision-making model, role assignments, and continuity plan.
