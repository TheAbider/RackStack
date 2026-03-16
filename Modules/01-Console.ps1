#region ===== CONSOLE INITIALIZATION =====
# Function to initialize console window size and title
function Initialize-ConsoleWindow {
    # Set window title
    try { [Console]::Title = "$($script:ToolFullName) v$($script:ScriptVersion)" } catch { }

    # Maximize the console window using Win32 API
    try {
        if (-not ([System.Management.Automation.PSTypeName]'Win32.ConsoleMax').Type) {
            Add-Type -Name ConsoleMax -Namespace Win32 -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -ErrorAction Stop
        }

        $hwnd = [Win32.ConsoleMax]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [void][Win32.ConsoleMax]::ShowWindow($hwnd, 3)  # SW_MAXIMIZE = 3
        }
    }
    catch { }

    # Resize console buffer and window to fill available space
    try {
        $rawUI = (Get-Host).UI.RawUI
        $maxWin = $rawUI.MaxWindowSize

        if ($maxWin.Width -gt 0 -and $maxWin.Height -gt 0) {
            # Buffer width must be >= window width, so expand buffer first
            $buf = $rawUI.BufferSize
            if ($buf.Width -lt $maxWin.Width) { $buf.Width = $maxWin.Width }
            if ($buf.Height -lt 3000) { $buf.Height = 3000 }
            $rawUI.BufferSize = $buf

            # Set window to fill the maximized console area
            $rawUI.WindowSize = New-Object System.Management.Automation.Host.Size($maxWin.Width, $maxWin.Height)
        }
    }
    catch { }

    # Detect and store terminal capabilities
    $script:ConsoleCapabilities = Get-ConsoleCapabilities
}

# Detect terminal capabilities (Unicode support, buffer dimensions, color depth)
function Get-ConsoleCapabilities {
    $capabilities = @{
        SupportsUnicode   = $false
        SupportsVT        = $false
        BufferWidth       = 80
        BufferHeight      = 300
        WindowWidth       = 80
        WindowHeight      = 25
        ColorDepth        = 16
        IsRedirected      = $false
        HostName          = "Unknown"
    }

    # Detect host name and redirected output
    try {
        $hostInfo = Get-Host
        $capabilities.HostName = $hostInfo.Name
        # ConsoleHost supports full features; ISE and others may not
        $capabilities.IsRedirected = [Console]::IsOutputRedirected
    }
    catch {
        # IsOutputRedirected may throw in non-console hosts
    }

    # Detect Unicode support via output encoding and code page
    try {
        $outputEncoding = [Console]::OutputEncoding
        $codePage = [Console]::OutputEncoding.CodePage
        # UTF-8 (65001) or Unicode code pages indicate Unicode support
        if ($codePage -eq 65001 -or $codePage -eq 1200 -or $codePage -eq 1201) {
            $capabilities.SupportsUnicode = $true
        }
        else {
            # Also check if the font can render box-drawing characters
            # TrueType console fonts generally support Unicode
            $capabilities.SupportsUnicode = ($null -ne $outputEncoding -and $outputEncoding.EncodingName -match 'Unicode|UTF')
        }
    }
    catch {
        # Assume basic support if detection fails
    }

    # Detect VT/ANSI escape sequence support (Windows 10 1607+ / Server 2016+)
    try {
        $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction SilentlyContinue).CurrentBuildNumber
        # VT support was added in Windows 10 build 14393 (Anniversary Update)
        if ($build -ge 14393) {
            $capabilities.SupportsVT = $true
        }
    }
    catch { }

    # Read current buffer and window dimensions
    try {
        $rawUI = (Get-Host).UI.RawUI
        if ($null -ne $rawUI.BufferSize) {
            $capabilities.BufferWidth = $rawUI.BufferSize.Width
            $capabilities.BufferHeight = $rawUI.BufferSize.Height
        }
        if ($null -ne $rawUI.WindowSize) {
            $capabilities.WindowWidth = $rawUI.WindowSize.Width
            $capabilities.WindowHeight = $rawUI.WindowSize.Height
        }
    }
    catch { }

    # Detect color depth based on host capabilities
    try {
        $hostName = (Get-Host).Name
        if ($hostName -eq 'ConsoleHost') {
            $build = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction SilentlyContinue).CurrentBuildNumber
            # Windows 10 1703+ supports 24-bit color in ConHost
            if ($build -ge 15063 -and $capabilities.SupportsVT) {
                $capabilities.ColorDepth = 256
            }
            else {
                $capabilities.ColorDepth = 16
            }
        }
        else {
            # ISE and other hosts typically support 16 colors
            $capabilities.ColorDepth = 16
        }
    }
    catch { }

    return $capabilities
}

# Optimize console buffer size based on detected capabilities
# Call after Initialize-ConsoleWindow if buffer needs adjustment
function Optimize-ConsoleBuffer {
    param(
        [int]$MinWidth = 120,
        [int]$MinBufferHeight = 3000,
        [int]$MaxBufferHeight = 9999
    )

    try {
        $rawUI = (Get-Host).UI.RawUI
        $buf = $rawUI.BufferSize
        $changed = $false

        # Ensure buffer width is at least MinWidth (for wide table output)
        if ($buf.Width -lt $MinWidth) {
            $maxAllowed = $rawUI.MaxPhysicalWindowSize.Width
            if ($maxAllowed -gt 0) {
                $buf.Width = [math]::Min($MinWidth, $maxAllowed)
            }
            else {
                $buf.Width = $MinWidth
            }
            $changed = $true
        }

        # Ensure buffer height is in acceptable range for scrollback
        if ($buf.Height -lt $MinBufferHeight) {
            $buf.Height = $MinBufferHeight
            $changed = $true
        }
        elseif ($buf.Height -gt $MaxBufferHeight) {
            $buf.Height = $MaxBufferHeight
            $changed = $true
        }

        if ($changed) {
            $rawUI.BufferSize = $buf
        }

        return $changed
    }
    catch {
        return $false
    }
}
#endregion
