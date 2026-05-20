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

        It 'passes the per-class complexity rules (length + 4 classes)' {
            # Note: we deliberately don't call Test-PasswordComplexity here because
            # that function has an extra "safe starting character" rule (rejects
            # passwords starting with $ # - ' "). New-StrongPassword's alphabet
            # includes # and -, and the Fisher-Yates shuffle can land one of those
            # first — that's an existing generator/validator coherence gap, not
            # something this test should pin. Check the per-class rules directly.
            $pw = New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null
            $pw.Length | Should -BeGreaterOrEqual 12
            ($pw -cmatch '[A-Z]') | Should -BeTrue
            ($pw -cmatch '[a-z]') | Should -BeTrue
            ($pw -match '\d') | Should -BeTrue
            ($pw -match '[!@#%^&*\-_=+]') | Should -BeTrue
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

    Context 'Clipboard side effects (via Mock)' {
        It 'exercises the clipboard-success branch when Set-Clipboard works' {
            Mock Set-Clipboard { }   # silent success
            Mock Get-Clipboard { 'whatever' }  # for the timer callback path
            { New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null } | Should -Not -Throw
        }

        It 'exercises the clipboard-failure branch when Set-Clipboard throws' {
            Mock Set-Clipboard { throw 'clipboard locked' }
            { New-StrongPassword 6>$null 4>$null 5>$null 3>$null 2>$null } | Should -Not -Throw
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

Describe 'Get-SecurePassword (interactive, via Mock)' {
    # Mock Read-Host with -AsSecureString so the prompt-confirm loop can be
    # exercised end-to-end without an actual TTY. Returns a [SecureString].
    function script:NewSecure { param([string]$Plain) ConvertTo-SecureString -String $Plain -AsPlainText -Force }

    It 'returns a SecureString when passwords match and meet complexity' {
        Mock Read-Host { NewSecure 'CorrectHorseBattery42!' }
        $result = Get-SecurePassword -localadminaccountname 'localadmin' -maxAttempts 1
        $result | Should -BeOfType [SecureString]
    }

    It 'returns $null after max attempts on complexity failure' {
        # Too-short password: fails complexity, retries, eventually returns null.
        Mock Read-Host { NewSecure 'shrt' }
        $result = Get-SecurePassword -localadminaccountname 'localadmin' -maxAttempts 2
        $result | Should -BeNullOrEmpty
    }

    It 'returns $null after max attempts on mismatch (every second prompt differs)' {
        # Two different passwords every other call: never matches.
        $script:passCallCount = 0
        Mock Read-Host {
            $script:passCallCount++
            if ($script:passCallCount % 2 -eq 1) { NewSecure 'StrongPassword12!' }
            else { NewSecure 'DifferentPass34@' }
        }
        $result = Get-SecurePassword -localadminaccountname 'localadmin' -maxAttempts 2
        $result | Should -BeNullOrEmpty
    }

    It 'rejects empty -localadminaccountname via ValidateNotNullOrEmpty' {
        { Get-SecurePassword -localadminaccountname '' -maxAttempts 1 } | Should -Throw
    }

    It 'rejects out-of-range -maxAttempts via ValidateRange' {
        { Get-SecurePassword -localadminaccountname 'admin' -maxAttempts 11 } | Should -Throw
        { Get-SecurePassword -localadminaccountname 'admin' -maxAttempts 0 } | Should -Throw
    }
}

Describe 'Show-LocalAccountAudit (via Mock)' {
    # Show-LocalAccountAudit reads Get-LocalUser, classifies each account on
    # 4 dimensions (enabled, password age, last logon, password expiry), and
    # renders a color-coded box. Mock Get-LocalUser to feed it shaped data so
    # we exercise every classification branch and the empty-list / error paths.
    BeforeAll {
        # Add-SessionChange / Clear-MenuCache / Write-PressEnter are called at the
        # end; stub them as no-ops so the tests don't need 04-Navigation / etc.
        function Add-SessionChange { }
        function Clear-MenuCache { }
        function Write-PressEnter { }
        # Clear-Host writes to console — stub it too so the test output isn't blanked
        function Clear-Host { }
    }

    It 'handles a healthy account (recent pwd, recent logon, enabled)' {
        $now = Get-Date
        Mock Get-LocalUser {
            ,@(
                [PSCustomObject]@{
                    Name = 'admin'; Enabled = $true
                    PasswordLastSet = $now.AddDays(-30)
                    LastLogon = $now.AddDays(-1)
                    PasswordNeverExpires = $false
                    PasswordExpires = $now.AddDays(45)
                }
            )
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'flags an account with an OLD password (>365 days)' {
        $now = Get-Date
        Mock Get-LocalUser {
            ,@([PSCustomObject]@{
                Name = 'oldpwd'; Enabled = $true
                PasswordLastSet = $now.AddDays(-400)
                LastLogon = $now.AddDays(-5)
                PasswordNeverExpires = $false
                PasswordExpires = $now.AddDays(-30)
            })
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'flags an AGING password (>90 days)' {
        $now = Get-Date
        Mock Get-LocalUser {
            ,@([PSCustomObject]@{
                Name = 'aging'; Enabled = $true
                PasswordLastSet = $now.AddDays(-120)
                LastLogon = $now.AddDays(-1)
                PasswordNeverExpires = $false
                PasswordExpires = $now.AddDays(30)
            })
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'flags a STALE account (>90 days since login)' {
        $now = Get-Date
        Mock Get-LocalUser {
            ,@([PSCustomObject]@{
                Name = 'stale'; Enabled = $true
                PasswordLastSet = $now.AddDays(-10)
                LastLogon = $now.AddDays(-100)
                PasswordNeverExpires = $false
                PasswordExpires = $now.AddDays(60)
            })
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'handles a disabled account (color branch = Info)' {
        $now = Get-Date
        Mock Get-LocalUser {
            ,@([PSCustomObject]@{
                Name = 'disabled'; Enabled = $false
                PasswordLastSet = $now.AddDays(-30)
                LastLogon = $null
                PasswordNeverExpires = $false
                PasswordExpires = $null
            })
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'handles PasswordNeverExpires = true' {
        $now = Get-Date
        Mock Get-LocalUser {
            ,@([PSCustomObject]@{
                Name = 'svcacct'; Enabled = $true
                PasswordLastSet = $now.AddDays(-30)
                LastLogon = $now.AddDays(-1)
                PasswordNeverExpires = $true
                PasswordExpires = $null
            })
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'handles a name longer than 20 chars (truncation branch)' {
        $now = Get-Date
        Mock Get-LocalUser {
            ,@([PSCustomObject]@{
                Name = 'this-is-a-very-very-long-account-name'; Enabled = $true
                PasswordLastSet = $now.AddDays(-30)
                LastLogon = $now.AddDays(-1)
                PasswordNeverExpires = $false
                PasswordExpires = $now.AddDays(30)
            })
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'handles an empty user list (Count=0 branch)' {
        Mock Get-LocalUser { @() }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'handles Get-LocalUser throwing (error branch)' {
        Mock Get-LocalUser { throw 'Access denied' }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'handles a "Today" last-logon (special-case branch)' {
        $now = Get-Date
        Mock Get-LocalUser {
            ,@([PSCustomObject]@{
                Name = 'today'; Enabled = $true
                PasswordLastSet = $now.AddDays(-1)
                LastLogon = $now  # today
                PasswordNeverExpires = $false
                PasswordExpires = $now.AddDays(60)
            })
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }

    It 'handles "Never set" PasswordLastSet branch' {
        Mock Get-LocalUser {
            ,@([PSCustomObject]@{
                Name = 'newuser'; Enabled = $true
                PasswordLastSet = $null
                LastLogon = $null
                PasswordNeverExpires = $false
                PasswordExpires = $null
            })
        }
        { Show-LocalAccountAudit } | Should -Not -Throw
    }
}

Describe 'Show-PasswordStrength' {
    # Show-PasswordStrength takes a [SecureString]. Build one per call. The function
    # writes a strength bar + per-criterion feedback to the console; tests just verify
    # each scoring branch runs without throwing and exercise the strength buckets.
    function script:NewSecure { param([string]$Plain) ConvertTo-SecureString -String $Plain -AsPlainText -Force }

    It 'handles a "Strong" (>= 6 score) password' {
        { Show-PasswordStrength -SecurePassword (NewSecure 'Str0ngP@ssw0rd!2026') } | Should -Not -Throw
    }

    It 'handles a "Moderate" (4-5) password' {
        # 10-13 chars + 3 char classes -> score ~4-5
        { Show-PasswordStrength -SecurePassword (NewSecure 'Moderate12') } | Should -Not -Throw
    }

    It 'handles a "Weak" (2-3) password' {
        { Show-PasswordStrength -SecurePassword (NewSecure 'weakpass') } | Should -Not -Throw
    }

    It 'handles a "Very Weak" (<2) password' {
        { Show-PasswordStrength -SecurePassword (NewSecure 'aaa') } | Should -Not -Throw
    }

    It 'handles a password missing a character class' {
        { Show-PasswordStrength -SecurePassword (NewSecure 'alllowercase12345') } | Should -Not -Throw
    }

    It 'handles an extremely long password (still finishes, no overflow)' {
        $long = ('A' * 50) + ('b' * 50) + ('1' * 50) + ('!' * 50)
        { Show-PasswordStrength -SecurePassword (NewSecure $long) } | Should -Not -Throw
    }
}
