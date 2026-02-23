$errors = 0
Get-ChildItem (Join-Path $PSScriptRoot '..\Modules\*.ps1') | ForEach-Object {
    $parseErrors = $null
    [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$parseErrors) | Out-Null
    if ($parseErrors.Count -gt 0) {
        Write-Host "PARSE ERROR: $($_.Name)"
        foreach ($pe in $parseErrors) {
            Write-Host "  Line $($pe.Token.StartLine): $($pe.Message)"
        }
        $errors++
    }
}
Write-Host "Parse errors: $errors"
exit $errors
