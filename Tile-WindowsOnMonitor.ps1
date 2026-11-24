#requires -Version 5.1

<#
.SYNOPSIS
    Tiles and cascades visible windows on the monitor under the mouse pointer.

.DESCRIPTION
    Developed collaboratively from Mikael Nilsson's idea to recreate and
    extend the classic Windows "Show windows side by side" and "Cascade
    windows" functionality for Windows 11, with per-monitor control.

    Supports tiling, grouped cascading, alphabetical window sorting,
    global keyboard shortcuts, single-instance protection, and automatic
    recovery from console Select mode.

.NOTES
    Version:
        3.5

    Idea, concept, requirements and relentless testing:
        Mikael Nilsson

    PowerShell implementation:
        Microsoft Copilot, with contributions by Mikael Nilsson

    Requirements:
        Windows PowerShell 5.1
        Windows 11

    Hotkeys:
        Ctrl+Alt+T = Tile windows on the monitor under the pointer
        Ctrl+Alt+C = Cascade windows on the monitor under the pointer
        Ctrl+Alt+Q = Quit the script

    Changelog - Version 3.5:
        - Added per-monitor Tile and grouped Cascade modes.
        - Added alphabetical Cascade sorting and configurable grouping.
        - Added single-instance and hotkey-conflict protection.
        - Added per-run window diagnostics.
        - Added filtering of non-normal windows such as Program Manager.
        - Added Select-mode watchdog and automatic recovery.
        - Added red SELECT MODE warning with live auto-release countdown.
        - Added PowerShell Get-Help documentation and authorship.
        - Tested with Windows PowerShell 5.1 on Windows 11.
#>

# ============================================================
# User settings
# ============================================================

$Version = 3.5

# Watchdog settings
$AutoExitSelectMode = $true
$ShowSelectModeWarning = $true
$SelectModeTimeoutSeconds = 10

# Tile settings
$gap = 3

# Cascade settings
$cascadeSortByTitle  = $true

# Preferred window size.
# Height may be reduced automatically if multiple group rows
# are needed to fit above the taskbar.
$cascadeWindowWidth  = 700
$cascadeWindowHeight = 500

# Offset between windows inside each group.
$cascadeOffsetX = 30
$cascadeOffsetY = 32

# Number of windows in each cascade group.
$cascadePerGroup = 4

# Gap between complete cascade groups.
$cascadeGroupGapX = 10
$cascadeGroupGapY = 2

# ============================================================
# Single-instance protection
# ============================================================

Add-Type -AssemblyName System.Windows.Forms

$mutexName = 'Global\TileWindowsMonitorTiler'
$createdNew = $false

$scriptMutex = New-Object System.Threading.Mutex(
    $true,
    $mutexName,
    [ref]$createdNew
)

if (-not $createdNew) {

    [System.Windows.Forms.MessageBox]::Show(
        "Tile Windows is already running.",
        "Tile Windows",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    $scriptMutex.Dispose()
    exit
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class MonitorWindowTiler
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(
        EnumWindowsProc lpEnumFunc,
        IntPtr lParam
    );

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetWindow(
        IntPtr hWnd,
        uint uCmd
    );

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(
        IntPtr hWnd,
        StringBuilder lpString,
        int nMaxCount
    );

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(
        IntPtr hWnd,
        out uint processId
    );

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromPoint(
        POINT pt,
        uint dwFlags
    );

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(
        IntPtr hWnd,
        uint dwFlags
    );

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool GetMonitorInfo(
        IntPtr hMonitor,
        ref MONITORINFO lpmi
    );

    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(
        IntPtr hWnd,
        IntPtr hWndInsertAfter,
        int X,
        int Y,
        int cx,
        int cy,
        uint uFlags
    );

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(
        IntPtr hWnd,
        int nCmdShow
    );

    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(
        IntPtr hWnd,
        int dwAttribute,
        out int pvAttribute,
        int cbAttribute
    );

    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(
        IntPtr hWnd,
        int id,
        uint fsModifiers,
        uint vk
    );

    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(
        IntPtr hWnd,
        int id
    );

    [DllImport("user32.dll")]
    public static extern int GetMessage(
        out MSG lpMsg,
        IntPtr hWnd,
        uint wMsgFilterMin,
        uint wMsgFilterMax
    );

    [DllImport("user32.dll")]
    public static extern bool SetProcessDpiAwarenessContext(
        IntPtr dpiContext
    );
}
'@

function Get-TargetMonitor {
    $point = New-Object MonitorWindowTiler+POINT

    if (-not [MonitorWindowTiler]::GetCursorPos([ref]$point)) {
        throw 'Unable to determine the mouse pointer position.'
    }

    # MONITOR_DEFAULTTONEAREST
    $monitor = [MonitorWindowTiler]::MonitorFromPoint($point, 2)

    if ($monitor -eq [IntPtr]::Zero) {
        throw 'Unable to determine the monitor under the mouse pointer.'
    }

    $monitor
}

function Get-MonitorWorkArea {
    param(
        [Parameter(Mandatory)]
        [IntPtr]$Monitor
    )

    $monitorInfo = New-Object MonitorWindowTiler+MONITORINFO
    $monitorInfo.cbSize = [Runtime.InteropServices.Marshal]::SizeOf(
        [type][MonitorWindowTiler+MONITORINFO]
    )

    if (-not [MonitorWindowTiler]::GetMonitorInfo(
        $Monitor,
        [ref]$monitorInfo
    )) {
        throw 'Unable to read the monitor work area.'
    }

    $monitorInfo.rcWork
}

function Get-TileableWindows {
    param(
        [Parameter(Mandatory)]
        [IntPtr]$Monitor
    )

    $windows = New-Object 'System.Collections.Generic.List[System.IntPtr]'
    $currentProcessId = [uint32]$PID

    $callback = [MonitorWindowTiler+EnumWindowsProc]{
        param(
            [IntPtr]$windowHandle,
            [IntPtr]$parameter
        )

        # Ignore hidden and minimized windows.
        if (-not [MonitorWindowTiler]::IsWindowVisible($windowHandle)) {
            return $true
        }

        if ([MonitorWindowTiler]::IsIconic($windowHandle)) {
            return $true
        }

        # Ignore owned/helper windows.
        # GW_OWNER = 4
        if ([MonitorWindowTiler]::GetWindow($windowHandle, 4) -ne
            [IntPtr]::Zero) {
            return $true
        }

        # Ignore windows without a normal title.
        if ([MonitorWindowTiler]::GetWindowTextLength($windowHandle) -le 0) {
            return $true
        }

        # Ignore this script's Windows Terminal window.
        $titleLength = [MonitorWindowTiler]::GetWindowTextLength($windowHandle)
        $titleBuilder = New-Object System.Text.StringBuilder ($titleLength + 1)

        $null = [MonitorWindowTiler]::GetWindowText(
            $windowHandle,
            $titleBuilder,
            $titleBuilder.Capacity
        )

        $windowTitle = $titleBuilder.ToString()

        if ($windowTitle -like '*Tile windows') {
            return $true
        }

        # Ignore the hidden/non-normal Program Manager top-level window.
        if ($windowTitle -eq 'Program Manager') {
            return $true
        }

        # Ignore invisible UWP/DWM placeholder windows.
        # DWMWA_CLOAKED = 14
        $cloaked = 0

        $null = [MonitorWindowTiler]::DwmGetWindowAttribute(
            $windowHandle,
            14,
            [ref]$cloaked,
            4
        )

        if ($cloaked -ne 0) {
            return $true
        }

        # Ignore the PowerShell process running this script.
        $windowProcessId = [uint32]0

        $null = [MonitorWindowTiler]::GetWindowThreadProcessId(
            $windowHandle,
            [ref]$windowProcessId
        )

        if ($windowProcessId -eq $currentProcessId) {
            return $true
        }

        # Only include windows assigned to the target monitor.
        # MONITOR_DEFAULTTONEAREST = 2
        $windowMonitor = [MonitorWindowTiler]::MonitorFromWindow(
            $windowHandle,
            2
        )

        if ($windowMonitor -eq $Monitor) {
            $windows.Add($windowHandle)
        }

return $true
    }

    [MonitorWindowTiler]::EnumWindows($callback, [IntPtr]::Zero) |
        Out-Null

    $windows
}

function Invoke-TileMonitor {

    # Compensate for invisible Windows 11 window borders.
    $gapX = $gap - 16
    $gapY = $gap - 10

    $monitor = Get-TargetMonitor
    $workArea = Get-MonitorWorkArea -Monitor $monitor
    $windows = @(Get-TileableWindows -Monitor $monitor)
    $windowCount = $windows.Count

    if ($windowCount -eq 0) {
        Show-TilerHeader
        Write-Host 'No tileable windows found on the selected screen.' -ForegroundColor Yellow
        return
    }

    Show-TilerHeader
    Write-Host 'TILE' -ForegroundColor Green
    Write-Host ''

    for ($listIndex = 0; $listIndex -lt $windowCount; $listIndex++) {
        $listTitle = Get-WindowDisplayTitle -WindowHandle $windows[$listIndex]
        Write-Host ('{0,2}. {1}' -f ($listIndex + 1), $listTitle)
    }

    Write-Host ''

    $columns = [int][Math]::Ceiling([Math]::Sqrt($windowCount))
    $rows = [int][Math]::Ceiling($windowCount / [double]$columns)

    $availableWidth = $workArea.Right - $workArea.Left
    $availableHeight = $workArea.Bottom - $workArea.Top

    $baseCellWidth = [int][Math]::Floor(
        ($availableWidth - (($columns - 1) * $gapX)) / [double]$columns
    )

    $baseCellHeight = [int][Math]::Floor(
        ($availableHeight - (($rows - 1) * $gapY)) / [double]$rows
    )

    for ($index = 0; $index -lt $windowCount; $index++) {
        $row = [int][Math]::Floor($index / [double]$columns)
        $column = $index % $columns

        $x = $workArea.Left + ($column * ($baseCellWidth + $gapX))
        $y = $workArea.Top + ($row * ($baseCellHeight + $gapY))

        if ($column -eq ($columns - 1)) {
            $width = $workArea.Right - $x
        }
        else {
            $width = $baseCellWidth
        }

        if ($row -eq ($rows - 1)) {
            $height = $workArea.Bottom - $y
        }
        else {
            $height = $baseCellHeight
        }

        $windowHandle = $windows[$index]

        [MonitorWindowTiler]::ShowWindowAsync($windowHandle, 9) | Out-Null

        # SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW
        $flags = 0x0004 -bor 0x0010 -bor 0x0040

        [MonitorWindowTiler]::SetWindowPos(
            $windowHandle,
            [IntPtr]::Zero,
            $x,
            $y,
            $width,
            $height,
            $flags
        ) | Out-Null
    }

    Write-Host (
        'Tiled {0} windows into a {1} x {2} grid.' -f
        $windowCount,
        $columns,
        $rows
    ) -ForegroundColor Green
}

function Invoke-CascadeMonitor {

    $monitor = Get-TargetMonitor
    $workArea = Get-MonitorWorkArea -Monitor $monitor
    $windows = @(Get-TileableWindows -Monitor $monitor)

    if ($cascadeSortByTitle) {
        $windowsWithTitles = @(
            foreach ($windowHandle in $windows) {
                $titleLength = [MonitorWindowTiler]::GetWindowTextLength($windowHandle)
                $titleBuilder = New-Object System.Text.StringBuilder ($titleLength + 1)

                $null = [MonitorWindowTiler]::GetWindowText(
                    $windowHandle,
                    $titleBuilder,
                    $titleBuilder.Capacity
                )

                [PSCustomObject]@{
                    Handle = $windowHandle
                    Title  = $titleBuilder.ToString()
                }
            }
        )

        $windows = @(
            $windowsWithTitles |
                Sort-Object -Property Title |
                Select-Object -ExpandProperty Handle
        )
    }

    $windowCount = $windows.Count

    if ($windowCount -eq 0) {
        Show-TilerHeader
        Write-Host 'No cascadeable windows found on the selected screen.' -ForegroundColor Yellow
        return
    }

    $availableWidth = $workArea.Right - $workArea.Left
    $availableHeight = $workArea.Bottom - $workArea.Top

    $groupCount = [int][Math]::Ceiling(
        $windowCount / [double]$cascadePerGroup
    )

    # Choose a balanced group grid from the monitor aspect ratio.
    # Portrait monitors therefore use more than one group column instead of
    # creating one very tall vertical chain of groups.
    $idealColumns = [int][Math]::Ceiling(
        [Math]::Sqrt(
            $groupCount * ($availableWidth / [double]$availableHeight)
        )
    )

    $groupsPerRow = [int][Math]::Max(1, $idealColumns)
    $groupsPerRow = [int][Math]::Min($groupsPerRow, $groupCount)

    $groupRows = [int][Math]::Ceiling(
        $groupCount / [double]$groupsPerRow
    )

    # Calculate the maximum bounding box available to each cascade group.
    $widthForGroups = $availableWidth -
        (($groupsPerRow - 1) * $cascadeGroupGapX)

    $heightForGroups = $availableHeight -
        (($groupRows - 1) * $cascadeGroupGapY)

    $groupCellWidth = [int][Math]::Floor(
        $widthForGroups / [double]$groupsPerRow
    )

    $groupCellHeight = [int][Math]::Floor(
        $heightForGroups / [double]$groupRows
    )

    # The requested window size is a maximum. Reduce it only as much as
    # needed to fit the stepped windows inside each group cell.
    $maximumWindowWidth = $groupCellWidth -
        (($cascadePerGroup - 1) * $cascadeOffsetX)

    $maximumWindowHeight = $groupCellHeight -
        (($cascadePerGroup - 1) * $cascadeOffsetY)

    $maximumWindowWidth = [int][Math]::Max(1, $maximumWindowWidth)
    $maximumWindowHeight = [int][Math]::Max(1, $maximumWindowHeight)

    $windowWidth = [int][Math]::Min(
        $cascadeWindowWidth,
        $maximumWindowWidth
    )

    $windowHeight = [int][Math]::Min(
        $cascadeWindowHeight,
        $maximumWindowHeight
    )

    $groupWidth = $windowWidth +
        (($cascadePerGroup - 1) * $cascadeOffsetX)

    $groupHeight = $windowHeight +
        (($cascadePerGroup - 1) * $cascadeOffsetY)

    Show-TilerHeader
    Write-Host 'CASCADE' -ForegroundColor Green
    Write-Host ''

    for ($listIndex = 0; $listIndex -lt $windowCount; $listIndex++) {
        $listGroup = [int][Math]::Floor(
            $listIndex / [double]$cascadePerGroup
        )
        $listStep = $listIndex % $cascadePerGroup
        $listTitle = Get-WindowDisplayTitle -WindowHandle $windows[$listIndex]

        Write-Host (
            '{0,2}. Group {1} / {2} : {3}' -f
            ($listIndex + 1),
            ($listGroup + 1),
            ($listStep + 1),
            $listTitle
        )
    }

    Write-Host ''

    for ($index = 0; $index -lt $windowCount; $index++) {
        $group = [int][Math]::Floor(
            $index / [double]$cascadePerGroup
        )

        $step = $index % $cascadePerGroup
        $groupColumn = $group % $groupsPerRow

        $groupRow = [int][Math]::Floor(
            $group / [double]$groupsPerRow
        )

        # Place each group at the beginning of its grid cell.
        $groupX = $workArea.Left +
            ($groupColumn * ($groupCellWidth + $cascadeGroupGapX))

        $groupY = $workArea.Top +
            ($groupRow * ($groupCellHeight + $cascadeGroupGapY))

        $x = $groupX + ($step * $cascadeOffsetX)
        $y = $groupY + ($step * $cascadeOffsetY)

        $windowHandle = $windows[$index]

        [MonitorWindowTiler]::ShowWindowAsync(
            $windowHandle,
            9
        ) | Out-Null

        # SWP_NOACTIVATE | SWP_SHOWWINDOW. SWP_NOZORDER is intentionally
        # omitted, so each successive window is placed at HWND_TOP.
        $flags = 0x0010 -bor 0x0040

        [MonitorWindowTiler]::SetWindowPos(
            $windowHandle,
            [IntPtr]::Zero,
            $x,
            $y,
            $windowWidth,
            $windowHeight,
            $flags
        ) | Out-Null
    }

    Write-Host (
        'Cascaded {0} windows in {1} groups using a {2} x {3} group grid.' -f
        $windowCount,
        $groupCount,
        $groupsPerRow,
        $groupRows
    ) -ForegroundColor Green
}

# Improve coordinate handling when monitors use different scaling levels.
try {
    # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
    [MonitorWindowTiler]::SetProcessDpiAwarenessContext(
        -4
    ) | Out-Null
}
catch {
    # The PowerShell host may already have selected its DPI mode.
}

# Hotkey modifiers
$MOD_ALT = 0x0001
$MOD_CONTROL = 0x0002
$modifiers = $MOD_ALT -bor $MOD_CONTROL

# Virtual-key codes
$VK_T = 0x54
$VK_C = 0x43
$VK_Q = 0x51


$tileHotkeyId = 1
$cascadeHotkeyId = 2
$quitHotkeyId = 3
$WM_HOTKEY = 0x0312

$tileRegistered = [MonitorWindowTiler]::RegisterHotKey(
    [IntPtr]::Zero,
    $tileHotkeyId,
    $modifiers,
    $VK_T
)

$cascadeRegistered = [MonitorWindowTiler]::RegisterHotKey(
    [IntPtr]::Zero,
    $cascadeHotkeyId,
    $modifiers,
    $VK_C
)

$quitRegistered = [MonitorWindowTiler]::RegisterHotKey(
    [IntPtr]::Zero,
    $quitHotkeyId,
    $modifiers,
    $VK_Q
)


if (
    -not $tileRegistered -or
    -not $cascadeRegistered -or
    -not $quitRegistered
) {

    # Clean up any hotkey that WAS successfully registered by this instance.
    if ($tileRegistered) {
        [MonitorWindowTiler]::UnregisterHotKey(
            [IntPtr]::Zero,
            $tileHotkeyId
        ) | Out-Null
    }

    if ($cascadeRegistered) {
        [MonitorWindowTiler]::UnregisterHotKey(
            [IntPtr]::Zero,
            $cascadeHotkeyId
        ) | Out-Null
    }

    if ($quitRegistered) {
        [MonitorWindowTiler]::UnregisterHotKey(
            [IntPtr]::Zero,
            $quitHotkeyId
        ) | Out-Null
    }

    Add-Type -AssemblyName System.Windows.Forms

    [System.Windows.Forms.MessageBox]::Show(
        "Unable to register Ctrl+Alt+T, Ctrl+Alt+C or Ctrl+Alt+Q.`r`n`r`nAnother application is probably using one of these hotkeys.",
        "Tile Windows - Hotkey conflict",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    exit
}

function Show-TilerHeader {
    Clear-Host
    Write-Host ("Monitor window tiler {0} is running." -f $Version) -ForegroundColor Cyan
    Write-Host '  Ctrl+Alt+T : Tile windows on screen under mouse pointer'
    Write-Host '  Ctrl+Alt+C : Cascade windows on screen under mouse pointer'
    Write-Host '  Ctrl+Alt+Q : Quit'
    Write-Host ''
}

function Get-WindowDisplayTitle {
    param(
        [Parameter(Mandatory)]
        [IntPtr]$WindowHandle
    )

    $titleLength = [MonitorWindowTiler]::GetWindowTextLength($WindowHandle)

    if ($titleLength -le 0) {
        return '<no title>'
    }

    $titleBuilder = New-Object System.Text.StringBuilder ($titleLength + 1)
    $null = [MonitorWindowTiler]::GetWindowText(
        $WindowHandle,
        $titleBuilder,
        $titleBuilder.Capacity
    )

    $titleBuilder.ToString()
}


function Start-SelectModeWatchdog {
    if (-not $AutoExitSelectMode) {
        return $null
    }

    $watchdogScript = @'
$parentProcessId = __PARENT_PROCESS_ID__
$timeoutSeconds = __TIMEOUT_SECONDS__
$showWarning = __SHOW_WARNING__

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class SelectModeWatchdogNative
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(
        IntPtr hWnd,
        uint Msg,
        IntPtr wParam,
        IntPtr lParam
    );
}
"@

$WM_KEYDOWN = 0x0100
$WM_KEYUP = 0x0101
$VK_ESCAPE = 0x1B
$selectStarted = $null
$warningForm = $null
$lastCountdownValue = -1

function Show-SelectWarning {
    param(
        [IntPtr]$TargetHandle
    )

    if (-not $showWarning -or $null -ne $warningForm) {
        return
    }

    $rect = New-Object System.Drawing.Rectangle
    $screen = [System.Windows.Forms.Screen]::FromHandle($TargetHandle)

    $script:warningForm = New-Object System.Windows.Forms.Form
    $warningForm = $script:warningForm
    $warningForm.Text = 'SELECT MODE'
    $warningForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedToolWindow
    $warningForm.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $warningForm.ShowInTaskbar = $false
    $warningForm.TopMost = $true
    $warningForm.BackColor = [System.Drawing.Color]::DarkRed
    $warningForm.ForeColor = [System.Drawing.Color]::White
    $warningForm.Width = 400
    $warningForm.Height = 70

    $x = $screen.WorkingArea.Right - $warningForm.Width - 20
    $y = $screen.WorkingArea.Top + 20
    $warningForm.Location = New-Object System.Drawing.Point($x, $y)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "SELECT MODE - Auto release in $timeoutSeconds s"
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $label.ForeColor = [System.Drawing.Color]::White
    $label.BackColor = [System.Drawing.Color]::DarkRed
    $label.Font = New-Object System.Drawing.Font(
        'Segoe UI',
        16,
        [System.Drawing.FontStyle]::Bold
    )

    $warningForm.Controls.Add($label)
    $warningForm.Show()
    $warningForm.Refresh()
}

function Update-SelectWarning {
    param(
        [int]$SecondsRemaining
    )

    if ($null -ne $warningForm) {
        $label = $warningForm.Controls[0]
        if ($null -ne $label) {
            $label.Text = "SELECT MODE - Auto release in $SecondsRemaining s"
        }
        $warningForm.Refresh()
    }
}

function Hide-SelectWarning {
    if ($null -ne $warningForm) {
        try {
            $warningForm.Close()
            $warningForm.Dispose()
        }
        catch {
        }
        $script:warningForm = $null
    }
}

while ($true) {
    try {
        $parentProcess = Get-Process -Id $parentProcessId -ErrorAction Stop
        $parentProcess.Refresh()
        $windowHandle = $parentProcess.MainWindowHandle
        $windowTitle = $parentProcess.MainWindowTitle
    }
    catch {
        break
    }

    if (
        $windowHandle -ne [IntPtr]::Zero -and
        $windowTitle -like 'Select *Tile windows*'
    ) {
        Show-SelectWarning -TargetHandle $windowHandle

        if ($null -eq $selectStarted) {
            $selectStarted = [DateTime]::UtcNow
            $lastCountdownValue = -1
        }

        $elapsedSeconds = (
            [DateTime]::UtcNow - $selectStarted
        ).TotalSeconds

        $secondsRemaining = [int][Math]::Ceiling(
            $timeoutSeconds - $elapsedSeconds
        )

        if ($secondsRemaining -lt 0) {
            $secondsRemaining = 0
        }

        if ($secondsRemaining -ne $lastCountdownValue) {
            Update-SelectWarning -SecondsRemaining $secondsRemaining
            $lastCountdownValue = $secondsRemaining
        }

        if ($elapsedSeconds -ge $timeoutSeconds) {
            [SelectModeWatchdogNative]::PostMessage(
                $windowHandle,
                $WM_KEYDOWN,
                [IntPtr]$VK_ESCAPE,
                [IntPtr]::Zero
            ) | Out-Null

            [SelectModeWatchdogNative]::PostMessage(
                $windowHandle,
                $WM_KEYUP,
                [IntPtr]$VK_ESCAPE,
                [IntPtr]::Zero
            ) | Out-Null

            $selectStarted = $null
            Hide-SelectWarning
        }
    }
    else {
        $selectStarted = $null
        $lastCountdownValue = -1
        Hide-SelectWarning
    }

    if ($null -ne $warningForm) {
        [System.Windows.Forms.Application]::DoEvents()
    }

    Start-Sleep -Milliseconds 250
}

Hide-SelectWarning
'@

    $watchdogScript = $watchdogScript.Replace(
        '__PARENT_PROCESS_ID__',
        $PID.ToString()
    )

    $watchdogScript = $watchdogScript.Replace(
        '__TIMEOUT_SECONDS__',
        ([int]$SelectModeTimeoutSeconds).ToString()
    )

    $watchdogScript = $watchdogScript.Replace(
        '__SHOW_WARNING__',
        ('$' + ([bool]$ShowSelectModeWarning).ToString().ToLower())
    )

    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($watchdogScript)
    )

    Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList @(
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-EncodedCommand',
            $encodedCommand
        ) `
        -WindowStyle Hidden `
        -PassThru
}

$watchdogProcess = Start-SelectModeWatchdog

Show-TilerHeader
if ($AutoExitSelectMode) {
    Write-Host (
        '  Select-mode watchdog: enabled ({0} seconds)' -f
        $SelectModeTimeoutSeconds
    ) -ForegroundColor DarkGray

    if ($ShowSelectModeWarning) {
        Write-Host '  Select-mode warning: enabled' -ForegroundColor DarkGray
    }
    else {
        Write-Host '  Select-mode warning: disabled' -ForegroundColor DarkGray
    }
}
else {
    Write-Host '  Select-mode watchdog: disabled' -ForegroundColor DarkGray
}
Write-Host ''
Write-Host 'Move the pointer onto the target screen and press Ctrl+Alt+T or Ctrl+Alt+C.' 
Write-Host ''

try {
    $message = New-Object MonitorWindowTiler+MSG

    while (
        [MonitorWindowTiler]::GetMessage(
            [ref]$message,
            [IntPtr]::Zero,
            0,
            0
        ) -gt 0
    ) {
        if ($message.message -ne $WM_HOTKEY) {
            continue
        }

        $hotkeyId = $message.wParam.ToUInt32()

        switch ($hotkeyId) {

            $tileHotkeyId {
                try {
                    Invoke-TileMonitor
                }
                catch {
                    Write-Warning $_.Exception.Message
                }
            }

            $cascadeHotkeyId {
                try {
                    Invoke-CascadeMonitor
                }
                catch {
                    Write-Warning $_.Exception.Message
                }
            }

            $quitHotkeyId {
                Write-Host 'Window tiler stopped.' -ForegroundColor Cyan
                return
            }
        }
    }
}
finally {
    if ($watchdogProcess) {
        try {
            if (-not $watchdogProcess.HasExited) {
                Stop-Process -Id $watchdogProcess.Id -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            # The watchdog may already have exited with the parent process.
        }
    }

    [MonitorWindowTiler]::UnregisterHotKey(
        [IntPtr]::Zero,
        $tileHotkeyId
    ) | Out-Null

    [MonitorWindowTiler]::UnregisterHotKey(
        [IntPtr]::Zero,
        $cascadeHotkeyId
    ) | Out-Null

    [MonitorWindowTiler]::UnregisterHotKey(
        [IntPtr]::Zero,
        $quitHotkeyId
    ) | Out-Null

    if ($scriptMutex) {
        try {
            $scriptMutex.ReleaseMutex()
        }
        catch {
            # Mutex may already have been released.
        }

        $scriptMutex.Dispose()
    }
}