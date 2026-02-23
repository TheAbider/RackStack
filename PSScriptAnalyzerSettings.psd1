@{
    # PSScriptAnalyzer settings for RackStack
    # This is an interactive console UI tool - rules designed for reusable
    # PowerShell modules/cmdlets do not apply.

    ExcludeRules = @(
        # Console UI tool - Write-Host is required for colored output,
        # progress spinners, and box-drawing menus
        'PSAvoidUsingWriteHost',

        # Cross-scope flags (RebootNeeded, DisabledAdminReboot, ReturnToMainMenu)
        # must be global so they persist across dot-sourced module boundaries
        'PSAvoidGlobalVars',

        # Interactive menu functions (Set-HostName, Start-ISODownload, etc.)
        # use Confirm-UserAction for confirmation, not ShouldProcess
        'PSUseShouldProcessForStateChangingFunctions',

        # Functions returning collections are correctly named plural
        # (Get-FileServerFiles, Connect-iSCSITargets, etc.)
        'PSUseSingularNouns',

        # Intentional silent catches on optional/fallback operations
        # (e.g., Get-Item on files that may not exist, service queries)
        'PSAvoidUsingEmptyCatchBlock',

        # False positive: Start-Job with -ArgumentList + param() block
        # Variables ARE passed via ArgumentList, not captured from outer scope
        'PSUseUsingScopeModifierInNewRunspaces',

        # Module-scoped initialization variables ($domain, $localadminaccountname, etc.)
        # defined in 00-Initialization.ps1, used across dot-sourced modules at runtime
        'PSUseDeclaredVarsMoreThanAssignments',

        # Test helper functions (Write-TestResult, Write-Check) are called hundreds of
        # times with clear, obvious parameter ordering -- named params would add noise
        'PSAvoidUsingPositionalParameters',

        # Script-level params (e.g. $Verbose) used inside nested functions within the
        # same script -- PSSA cannot trace usage across scope boundaries
        'PSReviewUnusedParameter',

        # Install-Prerequisites.ps1 uses Get-WmiObject for PS 2.0 compatibility
        # (Get-CimInstance not available until PS 3.0/WMF 3.0)
        'PSAvoidUsingWMICmdlet'
    )
}
