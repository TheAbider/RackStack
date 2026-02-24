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
}
#endregion
