#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Pester 5.x tests for navigation + formatting pure functions in 04-Navigation.ps1.

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    # 00-Initialization.ps1 reads CLI param variables ($Action, $Tier, etc.) that are
    # defined by RackStack.ps1's param() block at runtime. Pester runs under
    # Set-StrictMode -Version Latest by default, which makes those bare reads throw on
    # uninitialized variables. Relax strict mode for the dot-source, then re-arm it
    # so the test BODIES still get strict-mode coverage.
    $script:ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $modulesPath '..')).Path
    Set-StrictMode -Off
    . (Join-Path $modulesPath '00-Initialization.ps1')
    . (Join-Path $modulesPath '01-Console.ps1')
    . (Join-Path $modulesPath '02-Logging.ps1')
    . (Join-Path $modulesPath '04-Navigation.ps1')
    Set-StrictMode -Version Latest
}

Describe 'Test-NavigationCommand' {
    Context 'Back commands' {
        It 'recognizes "back"' { (Test-NavigationCommand -UserInput 'back').Action | Should -Be 'back' }
        It 'recognizes "b"' { (Test-NavigationCommand -UserInput 'b').Action | Should -Be 'back' }
        It 'recognizes "B" (case-insensitive)' { (Test-NavigationCommand -UserInput 'B').Action | Should -Be 'back' }
        It 'recognizes "cancel"' { (Test-NavigationCommand -UserInput 'cancel').Action | Should -Be 'back' }
        It 'recognizes "0"' { (Test-NavigationCommand -UserInput '0').Action | Should -Be 'back' }
        It 'sets ShouldReturn = true on back' { (Test-NavigationCommand -UserInput 'back').ShouldReturn | Should -BeTrue }
    }

    Context 'Exit commands' {
        It 'recognizes "exit"' { (Test-NavigationCommand -UserInput 'exit').Action | Should -Be 'exit' }
        It 'recognizes "quit"' { (Test-NavigationCommand -UserInput 'quit').Action | Should -Be 'exit' }
        It 'recognizes "QUIT" (case-insensitive)' { (Test-NavigationCommand -UserInput 'QUIT').Action | Should -Be 'exit' }
    }

    Context 'Home commands' {
        It 'recognizes "home"' { (Test-NavigationCommand -UserInput 'home').Action | Should -Be 'home' }
        It 'recognizes "main"' { (Test-NavigationCommand -UserInput 'main').Action | Should -Be 'home' }
        It 'recognizes "m"' { (Test-NavigationCommand -UserInput 'm').Action | Should -Be 'home' }
    }

    Context 'Continue / empty' {
        It 'returns continue for normal input' { (Test-NavigationCommand -UserInput '5').Action | Should -Be 'continue' }
        It 'returns continue for letter input' { (Test-NavigationCommand -UserInput 'x').Action | Should -Be 'continue' }
        It 'returns empty for empty input' { (Test-NavigationCommand -UserInput '').Action | Should -Be 'empty' }
        It 'returns empty for whitespace-only' { (Test-NavigationCommand -UserInput '   ').Action | Should -Be 'empty' }
        It 'continue and empty do not set ShouldReturn' {
            (Test-NavigationCommand -UserInput '5').ShouldReturn | Should -BeFalse
            (Test-NavigationCommand -UserInput '').ShouldReturn | Should -BeFalse
        }
    }
}

Describe 'Format-TransferSize' {
    It 'formats 0 bytes' { Format-TransferSize -Bytes 0 | Should -Be '0 B' }
    It 'formats 512 bytes' { Format-TransferSize -Bytes 512 | Should -Be '512 B' }
    It 'formats 1024 bytes as 1 KB' { Format-TransferSize -Bytes 1024 | Should -Be '1 KB' }
    It 'formats 1 MB' { Format-TransferSize -Bytes 1048576 | Should -Be '1 MB' }
    It 'formats 1 GB with decimals' { Format-TransferSize -Bytes 1073741824 | Should -Match 'GB' }
    It 'formats 1 TB' { Format-TransferSize -Bytes 1099511627776 | Should -Match 'TB' }
    It 'handles fractional GB' {
        $result = Format-TransferSize -Bytes 1500000000  # ~1.4 GB
        $result | Should -Match 'GB'
    }
}
