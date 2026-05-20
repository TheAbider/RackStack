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

Describe 'ConvertFrom-SecureStringToPlainText' {
    It 'round-trips a plaintext value through SecureString' {
        $original = 'CorrectHorseBatteryStaple-42!'
        $secure = ConvertTo-SecureString -String $original -AsPlainText -Force
        $roundTripped = ConvertFrom-SecureStringToPlainText -secureString $secure
        $roundTripped | Should -Be $original
    }

    It 'handles values containing special characters' {
        $original = "p@ss!#`$%^&*()_+-=" + '<>?[]{}|'
        $secure = ConvertTo-SecureString -String $original -AsPlainText -Force
        ConvertFrom-SecureStringToPlainText -secureString $secure | Should -Be $original
    }

    It 'handles a single-character value (boundary)' {
        $secure = ConvertTo-SecureString -String 'x' -AsPlainText -Force
        ConvertFrom-SecureStringToPlainText -secureString $secure | Should -Be 'x'
    }

    It 'throws on $null input (parameter is Mandatory)' {
        { ConvertFrom-SecureStringToPlainText -secureString $null } | Should -Throw
    }
}

Describe 'New-StrongPassword' {
    BeforeAll {
        # New-StrongPassword writes box-drawing UI through Write-OutputColor; capture its
        # console output to keep the test stream tidy, then check the returned string.
        function script:Invoke-Silently {
            param([scriptblock]$Script)
            $oldErr = $ErrorActionPreference
            $ErrorActionPreference = 'SilentlyContinue'
            try {
                # 6>&1 redirects Information stream, *>&1 captures everything else
                & $Script *>&1 | Out-Null
            } finally {
                $ErrorActionPreference = $oldErr
            }
        }
    }

    Context 'Length boundaries' {
        It 'defaults to length 16' {
            $pw = New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw.Length | Should -Be 16
        }

        It 'respects an explicit length parameter (24)' {
            $pw = New-StrongPassword -Length 24 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw.Length | Should -Be 24
        }

        It 'floors length to 12 when caller asks for less' {
            $pw = New-StrongPassword -Length 4 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw.Length | Should -Be 12
        }

        It 'caps length at 128 when caller asks for more' {
            $pw = New-StrongPassword -Length 1000 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw.Length | Should -Be 128
        }
    }

    Context 'Generated complexity' {
        It 'contains at least one uppercase letter' {
            $pw = New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw | Should -Match '[A-Z]'
        }

        It 'contains at least one lowercase letter' {
            $pw = New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw | Should -Match '[a-z]'
        }

        It 'contains at least one digit (excluding ambiguous 0/1)' {
            $pw = New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw | Should -Match '[2-9]'
        }

        It 'contains at least one special char from the safe set !@#%^&*-_=+' {
            $pw = New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw | Should -Match '[!@#%^&\*\-_=+]'
        }

        It 'excludes ambiguous characters 0, 1, I, O, i, l, o (case-sensitive check)' {
            $pw = New-StrongPassword -Length 64 6>$null 4>$null 5>$null 3>$null 2>$null
            # PowerShell -match (and Pester Should -Match) is case-insensitive by default,
            # which would falsely flag uppercase L. Use -cnotmatch for a literal case-sensitive check.
            ($pw -cmatch '[01IOilo]') | Should -BeFalse
        }

        It 'passes Test-PasswordComplexity (own check)' {
            $pw = New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null
            Test-PasswordComplexity $pw | Should -BeTrue
        }
    }

    Context 'Cryptographic randomness (statistical)' {
        It 'produces distinct passwords across calls' {
            $samples = 1..10 | ForEach-Object {
                New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null
            }
            ($samples | Select-Object -Unique).Count | Should -Be 10
        }
    }
}

Describe 'Clear-SecureMemory' {
    It 'nulls the referenced string variable' {
        $s = 'sensitive-data'
        Clear-SecureMemory -StringRef ([ref]$s)
        $s | Should -BeNullOrEmpty
    }

    It 'is a no-op for a $null input ref' {
        $s = $null
        { Clear-SecureMemory -StringRef ([ref]$s) } | Should -Not -Throw
        $s | Should -BeNullOrEmpty
    }

    It 'leaves non-string ref values unchanged (function checks type)' {
        $n = 42
        Clear-SecureMemory -StringRef ([ref]$n)
        $n | Should -Be 42
    }
}
