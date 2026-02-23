$settingsPath = Join-Path $PSScriptRoot '..\PSScriptAnalyzerSettings.psd1'
$errors = 0
Get-ChildItem (Join-Path $PSScriptRoot '..\Modules\*.ps1') | ForEach-Object {
    $results = Invoke-ScriptAnalyzer -Path $_.FullName -Settings $settingsPath -Severity Error
    if ($results) {
        foreach ($r in $results) {
            Write-Host "ERROR: $($_.Name):$($r.Line) - $($r.RuleName): $($r.Message)"
            $errors++
        }
    }
}
Write-Host "PSSA errors: $errors"
exit $errors
