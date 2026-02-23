$modulesPath = Join-Path $PSScriptRoot "..\Modules"

$results = Invoke-ScriptAnalyzer -Path $modulesPath -Recurse

# Show per-rule breakdown with example locations
$grouped = $results | Group-Object RuleName | Sort-Object Count -Descending
foreach ($group in $grouped) {
    Write-Host ""
    Write-Host ("=== {0} ({1} warnings) ===" -f $group.Name, $group.Count) -ForegroundColor Cyan
    # Show first 5 examples
    $examples = $group.Group | Select-Object -First 5
    foreach ($ex in $examples) {
        $file = Split-Path $ex.ScriptName -Leaf
        Write-Host ("  {0}:{1}  {2}" -f $file, $ex.Line, $ex.Message.Substring(0, [Math]::Min(90, $ex.Message.Length))) -ForegroundColor DarkGray
    }
    if ($group.Count -gt 5) {
        Write-Host "  ... and $($group.Count - 5) more" -ForegroundColor DarkGray
    }
}

# Show which files have PSUseDeclaredVarsMoreThanAssignments (the least obvious one)
Write-Host ""
Write-Host "=== PSUseDeclaredVarsMoreThanAssignments details ===" -ForegroundColor Yellow
$varResults = $results | Where-Object RuleName -eq 'PSUseDeclaredVarsMoreThanAssignments'
foreach ($v in $varResults) {
    $file = Split-Path $v.ScriptName -Leaf
    Write-Host ("  {0}:{1}  {2}" -f $file, $v.Line, $v.Message) -ForegroundColor DarkGray
}

# Show which files have PSAvoidGlobalVars (need to verify they're by-design)
Write-Host ""
Write-Host "=== PSAvoidGlobalVars unique variables ===" -ForegroundColor Yellow
$globalResults = $results | Where-Object RuleName -eq 'PSAvoidGlobalVars'
$uniqueVars = $globalResults | ForEach-Object {
    if ($_.Message -match "'([^']+)'") { $matches[1] }
} | Sort-Object -Unique
foreach ($v in $uniqueVars) {
    Write-Host "  $v" -ForegroundColor DarkGray
}
