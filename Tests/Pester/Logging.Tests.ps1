#Requires -Modules @{ ModuleName='Pester'; ModuleVersion='5.0.0' }
#
# Pester 5.x tests for the structured-logging path in 02-Logging.ps1.
# Focus: Write-StructuredLog's format guarantees and its secret-key redaction
# (defense-in-depth — accidentally routing a credential through structured logging
# must not write the plaintext to disk).

BeforeAll {
    $modulesPath = Join-Path $PSScriptRoot '..\..\Modules'
    $script:ModuleRoot = (Resolve-Path -LiteralPath (Join-Path $modulesPath '..')).Path
    Set-StrictMode -Off
    . (Join-Path $modulesPath '00-Initialization.ps1')
    . (Join-Path $modulesPath '01-Console.ps1')
    . (Join-Path $modulesPath '02-Logging.ps1')
    # Write-RackStackError reads $script:ConsoleCapabilities for VT-escape
    # decoration and Write-StructuredLog reads $script:TranscriptPath for the
    # fall-through log path. Under strict mode, uninitialized reads throw —
    # initialize both now so the tests exercise the documented branches.
    $script:ConsoleCapabilities = Get-ConsoleCapabilities
    $script:TranscriptPath = $null
    Set-StrictMode -Version Latest

    function script:Read-LogContent {
        param([string]$Path)
        Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    }
}

Describe 'Write-StructuredLog' {
    BeforeEach {
        $script:logPath = Join-Path ([System.IO.Path]::GetTempPath()) "rackstack-pester-$([guid]::NewGuid()).log"
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:logPath) {
            Remove-Item -LiteralPath $script:logPath -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Basic emission' {
        It 'writes a single line for one call' {
            Write-StructuredLog -Message 'hello' -LogFilePath $script:logPath
            $lines = Get-Content -LiteralPath $script:logPath
            @($lines).Count | Should -Be 1
        }

        It 'includes the message verbatim' {
            Write-StructuredLog -Message 'unique-payload-12345' -LogFilePath $script:logPath
            (Read-LogContent $script:logPath) | Should -Match 'unique-payload-12345'
        }

        It 'defaults Level to INFO when omitted' {
            Write-StructuredLog -Message 'plain' -LogFilePath $script:logPath
            (Read-LogContent $script:logPath) | Should -Match '\| INFO \|'
        }

        It 'defaults Category to General when omitted' {
            Write-StructuredLog -Message 'plain' -LogFilePath $script:logPath
            (Read-LogContent $script:logPath) | Should -Match '\| General \|'
        }

        It 'honors a custom Level' {
            Write-StructuredLog -Message 'oops' -Level 'ERROR' -LogFilePath $script:logPath
            (Read-LogContent $script:logPath) | Should -Match '\| ERROR \|'
        }

        It 'honors a custom Category' {
            Write-StructuredLog -Message 'event' -Category 'Networking' -LogFilePath $script:logPath
            (Read-LogContent $script:logPath) | Should -Match '\| Networking \|'
        }

        It 'embeds the hostname' {
            Write-StructuredLog -Message 'host-test' -LogFilePath $script:logPath
            (Read-LogContent $script:logPath) | Should -Match ([regex]::Escape($env:COMPUTERNAME))
        }

        It 'emits a millisecond-precision timestamp prefix' {
            Write-StructuredLog -Message 'ts-test' -LogFilePath $script:logPath
            (Read-LogContent $script:logPath) | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \|'
        }
    }

    Context 'Parameter validation' {
        It 'rejects empty Message via ValidateNotNullOrEmpty' {
            { Write-StructuredLog -Message '' -LogFilePath $script:logPath } | Should -Throw
        }

        It 'rejects an unknown Level' {
            { Write-StructuredLog -Message 'm' -Level 'TRACE' -LogFilePath $script:logPath } | Should -Throw
        }

        It 'accepts all documented Level values' {
            foreach ($lvl in 'INFO','WARN','ERROR','SUCCESS','DEBUG') {
                { Write-StructuredLog -Message "m-$lvl" -Level $lvl -LogFilePath $script:logPath } | Should -Not -Throw
            }
        }
    }

    Context 'Key-value data block' {
        It 'appends Data hashtable as KEY=VALUE pairs' {
            Write-StructuredLog -Message 'kv' -LogFilePath $script:logPath -Data @{ Action = 'install'; Result = 'ok' }
            $content = Read-LogContent $script:logPath
            $content | Should -Match 'Action=install'
            $content | Should -Match 'Result=ok'
        }

        It 'separates multiple KV pairs with semicolons' {
            Write-StructuredLog -Message 'kv' -LogFilePath $script:logPath -Data @{ A = '1'; B = '2' }
            (Read-LogContent $script:logPath) | Should -Match ';'
        }

        It 'represents $null values as the literal "(null)"' {
            Write-StructuredLog -Message 'kv' -LogFilePath $script:logPath -Data @{ Missing = $null }
            (Read-LogContent $script:logPath) | Should -Match 'Missing=\(null\)'
        }

        It 'omits the KV section entirely when Data is empty' {
            Write-StructuredLog -Message 'no-kv' -LogFilePath $script:logPath -Data @{}
            $content = Read-LogContent $script:logPath
            # Trailing semicolons or "key=" patterns shouldn't appear in the line
            $content | Should -Not -Match '\| no-kv \| '
        }
    }

    Context 'Secret redaction (defense-in-depth)' {
        # The redaction matches on the KEY name, not the value. This is intentional —
        # value-pattern matching would have too many false positives. These tests pin
        # the documented key patterns so a future refactor that breaks redaction is
        # caught immediately.

        It 'redacts a key named "Password"' {
            Write-StructuredLog -Message 'auth' -LogFilePath $script:logPath -Data @{ Password = 'hunter2-plaintext' }
            $content = Read-LogContent $script:logPath
            $content | Should -Not -Match 'hunter2-plaintext'
            $content | Should -Match 'Password=\[REDACTED\]'
        }

        It 'redacts a key named "Token"' {
            Write-StructuredLog -Message 'auth' -LogFilePath $script:logPath -Data @{ Token = 'sk_live_abcd1234' }
            (Read-LogContent $script:logPath) | Should -Not -Match 'sk_live_abcd1234'
        }

        It 'redacts a key named "Secret"' {
            Write-StructuredLog -Message 'auth' -LogFilePath $script:logPath -Data @{ Secret = 'topsecret-xyz' }
            (Read-LogContent $script:logPath) | Should -Not -Match 'topsecret-xyz'
        }

        It 'redacts a key named "ApiKey"' {
            Write-StructuredLog -Message 'auth' -LogFilePath $script:logPath -Data @{ ApiKey = 'should-not-appear' }
            (Read-LogContent $script:logPath) | Should -Not -Match 'should-not-appear'
        }

        It 'redacts a key named "ClientSecret"' {
            Write-StructuredLog -Message 'auth' -LogFilePath $script:logPath -Data @{ ClientSecret = 'oauth-leak' }
            (Read-LogContent $script:logPath) | Should -Not -Match 'oauth-leak'
        }

        It 'redacts a key named "Authorization"' {
            Write-StructuredLog -Message 'auth' -LogFilePath $script:logPath -Data @{ Authorization = 'Bearer xyz' }
            (Read-LogContent $script:logPath) | Should -Not -Match 'Bearer xyz'
        }

        It 'is case-insensitive in key matching' {
            Write-StructuredLog -Message 'auth' -LogFilePath $script:logPath -Data @{ PASSWORD = 'caps-pwd' }
            (Read-LogContent $script:logPath) | Should -Not -Match 'caps-pwd'
        }

        It 'does NOT redact unrelated keys' {
            Write-StructuredLog -Message 'normal' -LogFilePath $script:logPath -Data @{ Username = 'maxz'; Hostname = 'web-01' }
            $content = Read-LogContent $script:logPath
            $content | Should -Match 'Username=maxz'
            $content | Should -Match 'Hostname=web-01'
        }
    }
}

Describe 'Write-LogMessage' {
    BeforeEach {
        $script:logPath = Join-Path ([System.IO.Path]::GetTempPath()) "rackstack-pester-wlm-$([guid]::NewGuid()).log"
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:logPath) {
            Remove-Item -LiteralPath $script:logPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes message with timestamp prefix' {
        Write-LogMessage -message 'simple log' -logFilePath $script:logPath
        $content = Get-Content -LiteralPath $script:logPath -Raw
        $content | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} - simple log'
    }

    It 'is a no-op when logFilePath is empty' {
        # Should not throw, should not create any file
        { Write-LogMessage -message 'orphan' -logFilePath '' } | Should -Not -Throw
    }
}

Describe 'Write-OutputColor — exercise every theme + color branch' {
    # These tests exist primarily for code coverage. Write-OutputColor's return value
    # is $null (it writes to the host), so we can't assert on output directly without
    # capturing the console stream. The goal is to exercise every documented color name
    # and every branch (with/without -NoNewline, with/without box-drawing chars) so
    # uncovered lines don't accumulate.

    It 'handles every documented color name without throwing' {
        foreach ($color in 'Success','Warning','Error','Info','Debug','Critical','Verbose') {
            { Write-OutputColor "msg-$color" -color $color } | Should -Not -Throw
        }
    }

    It 'handles -NoNewline switch' {
        { Write-OutputColor 'no-newline-test' -color 'Info' -NoNewline } | Should -Not -Throw
        # Emit one final newline so subsequent test output isn't on the same line
        Write-Host ''
    }

    It 'handles an empty message (special-case branch)' {
        { Write-OutputColor '' -color 'Info' } | Should -Not -Throw
    }

    It 'handles an empty message with -NoNewline (returns early)' {
        { Write-OutputColor '' -color 'Info' -NoNewline } | Should -Not -Throw
    }

    It 'handles box-drawing content (triggers the multi-color split branch)' {
        # A line containing the U+2502 box-drawing vertical bar at start AND end
        # triggers Write-OutputColor's auto-split rendering.
        $pipe = [char]0x2502
        $boxed = "$pipe  some content      $pipe"
        { Write-OutputColor $boxed -color 'Success' } | Should -Not -Throw
    }

    It 'handles box-drawing content with -NoNewline' {
        $pipe = [char]0x2502
        $boxed = "$pipe  content  $pipe"
        { Write-OutputColor $boxed -color 'Error' -NoNewline } | Should -Not -Throw
        Write-Host ''
    }

    It 'falls back gracefully on unknown theme (uses Default map)' {
        $oldTheme = $script:ColorTheme
        try {
            $script:ColorTheme = 'NonexistentThemeName'
            { Write-OutputColor 'fallback-test' -color 'Info' } | Should -Not -Throw
        } finally {
            $script:ColorTheme = $oldTheme
        }
    }
}

Describe 'Write-CenteredOutput' {
    It 'renders a centered banner without throwing' {
        { Write-CenteredOutput -text 'CENTERED' -color 'Info' -width 50 } | Should -Not -Throw
    }

    It 'handles short text (padding stays valid)' {
        { Write-CenteredOutput -text 'X' -color 'Info' -width 40 } | Should -Not -Throw
    }

    It 'handles text longer than width (does not throw on negative padding)' {
        $long = 'X' * 100
        { Write-CenteredOutput -text $long -color 'Info' -width 20 } | Should -Not -Throw
    }

    It 'defaults width to 72 when omitted' {
        { Write-CenteredOutput -text 'default' -color 'Info' } | Should -Not -Throw
    }
}

Describe 'Write-RackStackError' {
    # Documented error-code dispatcher: takes RS-NNNN, looks up message in
    # $script:ErrorCodes, displays formatted error. Tests exercise the format
    # contract + the unknown-code fallback path.
    It 'rejects invalid code format via ValidatePattern' {
        { Write-RackStackError -Code 'BAD-CODE' } | Should -Throw
    }

    It 'accepts a valid RS-NNNN code' {
        { Write-RackStackError -Code 'RS-9999' } | Should -Not -Throw
    }

    It 'accepts a code with detail' {
        { Write-RackStackError -Code 'RS-0001' -Detail 'Something went wrong.' } | Should -Not -Throw
    }

    It 'falls back gracefully when code is not in $script:ErrorCodes' {
        # RS-9999 isn't a real code; exercise the "Unknown error" fallback branch.
        { Write-RackStackError -Code 'RS-9999' -Detail 'unknown-fallback' } | Should -Not -Throw
    }
}

Describe 'Write-MenuItem' {
    # 2-column menu line renderer. Used throughout the menu UI to render
    # rows with a status badge on the right.
    It 'renders a basic menu item without throwing' {
        { Write-MenuItem -Text 'Configure IP' } | Should -Not -Throw
    }

    It 'renders a menu item with a status badge' {
        { Write-MenuItem -Text 'Configure IP' -Status 'OK' -StatusColor 'Success' } | Should -Not -Throw
    }

    It 'accepts each documented StatusColor value (ValidateSet)' {
        foreach ($c in 'Success','Warning','Error','Info','Debug','Critical','Verbose','') {
            { Write-MenuItem -Text 'item' -Status 'X' -StatusColor $c } | Should -Not -Throw
        }
    }

    It 'rejects unknown StatusColor (ValidateSet enforcement)' {
        { Write-MenuItem -Text 'item' -Status 'X' -StatusColor 'Fuchsia' } | Should -Throw
    }

    It 'tolerates an unknown -Color value (falls back to theme default)' {
        { Write-MenuItem -Text 'item' -Color 'NoSuchColor' } | Should -Not -Throw
    }

    It 'rejects empty Text via ValidateNotNullOrEmpty' {
        { Write-MenuItem -Text '' } | Should -Throw
    }
}

Describe 'Write-LogMessage (additional coverage)' {
    BeforeEach {
        $script:logPath = Join-Path ([System.IO.Path]::GetTempPath()) "rackstack-pester-wlm2-$([guid]::NewGuid()).log"
    }
    AfterEach {
        if (Test-Path -LiteralPath $script:logPath) {
            Remove-Item -LiteralPath $script:logPath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'appends to an existing log file (not overwrite)' {
        Write-LogMessage -message 'first' -logFilePath $script:logPath
        Write-LogMessage -message 'second' -logFilePath $script:logPath
        $lines = Get-Content -LiteralPath $script:logPath
        @($lines).Count | Should -Be 2
        $lines[0] | Should -Match 'first'
        $lines[1] | Should -Match 'second'
    }
}
