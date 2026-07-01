@{
    RootModule           = 'RackStack.psm1'
    ModuleVersion        = '1.121.10'
    GUID                 = 'c19b8e71-4a35-4f2b-9d06-8a24f7bc0e91'
    Author               = 'TheAbider'
    CompanyName          = 'TheAbider'
    Copyright            = '(c) TheAbider. All rights reserved.'
    Description          = 'PowerShell cmdlet wrappers around the RackStack.exe CLI. Invoke any of the 176 CLI actions (SelfTest, UpdateSelf, ExportLogs, Batch, every audit action, etc.) as structured cmdlets from scripts and pipelines. Auto-locates the installed EXE via the Programs-and-Features registry key, PATH, or the RACKSTACK_EXE environment variable. RackStack.exe is downloaded separately from https://github.com/TheAbider/RackStack/releases — the module itself is a thin wrapper, not the tool.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
        'Get-RackStackExePath'
        'Test-RackStackInstalled'
        'Get-RackStackVersion'
        'Test-RackStackUpdate'
        'Invoke-RackStackAction'
        'Update-RackStack'
        'Invoke-RackStackSelfTest'
        'Export-RackStackLogs'
        'Get-RackStackActionList'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('RackStack', 'Windows', 'WindowsServer', 'HyperV', 'Sysadmin', 'CLI', 'Automation', 'ServerConfig')
            LicenseUri   = 'https://github.com/TheAbider/RackStack/blob/master/LICENSE'
            ProjectUri   = 'https://github.com/TheAbider/RackStack'
            IconUri      = 'https://raw.githubusercontent.com/TheAbider/RackStack/master/.github/assets/icon.png'
            ReleaseNotes = 'See https://github.com/TheAbider/RackStack/releases for per-version changelog.'
        }
    }
}
