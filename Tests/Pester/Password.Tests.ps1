#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Pester 5.x tests for password complexity validation (pure function, no I/O).

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    # Strict-mode relaxation around dot-source — see Navigation.Tests.ps1 for the explanation.
    $script:ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $modulesPath '..')).Path
    Set-StrictMode -Off
    . (Join-Path $modulesPath '00-Initialization.ps1')
    . (Join-Path $modulesPath '02-Logging.ps1')
    . (Join-Path $modulesPath '22-Password.ps1')
    Set-StrictMode -Version Latest
}

Describe 'Test-PasswordComplexity' {
    Context 'Length' {
        It 'rejects (throws on) empty password — refuse-to-evaluate is correct security behavior' {
            # Function has [ValidateNotNullOrEmpty()] so empty input throws at parameter binding.
            { Test-PasswordComplexity '' } | Should -Throw
        }
        It 'rejects short password (under MinPasswordLength)' { Test-PasswordComplexity 'Aa1!' | Should -BeFalse }
        It 'accepts 14-character strong password (default min)' { Test-PasswordComplexity 'MyStr0ngP@ss12' | Should -BeTrue }
    }

    Context 'Character classes' {
        It 'rejects no uppercase' { Test-PasswordComplexity 'alllowercase1!@' | Should -BeFalse }
        It 'rejects no lowercase' { Test-PasswordComplexity 'ALLUPPERCASE1!@' | Should -BeFalse }
        It 'rejects no digit' { Test-PasswordComplexity 'NoDigitsHere!@#' | Should -BeFalse }
        It 'rejects no special char' { Test-PasswordComplexity 'NoSpecial12345A' | Should -BeFalse }
        It 'accepts all four classes' { Test-PasswordComplexity 'MyStr0ngP@ssw0rd!' | Should -BeTrue }
    }

    Context 'Edge cases' {
        It 'rejects unicode-only special chars (PowerShell -cmatch may not classify)' {
            # Cyrillic chars in place of special — should fail complexity
            $cyrillicNotSpecial = 'MyStr0ngPaasss12'
            Test-PasswordComplexity $cyrillicNotSpecial | Should -BeFalse
        }
        It 'accepts dollar-sign as special' { Test-PasswordComplexity 'MyStr0ngPass$$$' | Should -BeTrue }
        It 'accepts hash-sign as special' { Test-PasswordComplexity 'MyStr0ngPass###' | Should -BeTrue }
    }
}
