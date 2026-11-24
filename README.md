# Tile Windows on Monitor

A Windows 11 PowerShell utility that restores and extends the classic **Show windows side by side** and **Cascade windows** workflows, with per-monitor control.

Move the mouse pointer to the monitor you want to arrange, then use a global hotkey.

## Hotkeys

- `Ctrl+Alt+T` — Tile eligible windows on the monitor under the mouse pointer
- `Ctrl+Alt+C` — Cascade eligible windows on the monitor under the mouse pointer
- `Ctrl+Alt+Q` — Quit cleanly

## Why this exists

Windows 11 no longer exposes the old taskbar commands for arranging all windows side by side or cascading them. Snap Layouts are useful for a few windows, but become cumbersome when many windows are open.

This script recreates that workflow while adding multi-monitor targeting, grouped cascading, diagnostics, and configuration options.

## Features

- Per-monitor Tile and Cascade modes
- Monitor selected by current mouse-pointer position
- Configurable tile gap
- Grouped Cascade with configurable group size, offsets, window dimensions, and spacing
- Optional alphabetical Cascade ordering by window title
- Explicit back-to-front Cascade ordering
- Excludes minimized, cloaked, helper, script-console, and known non-normal windows
- Per-run diagnostic list of every processed window
- Global hotkeys
- Single-instance protection
- Hotkey-conflict warning
- QuickEdit/Select-mode watchdog
- Red SELECT MODE warning with automatic-release countdown
- PowerShell comment-based help via `Get-Help`
- Windows PowerShell 5.1 compatible

## Requirements

- Windows 11
- Windows PowerShell 5.1

Run as Administrator if you also need the utility to arrange elevated windows.

## Installation

1. Download `Tile-WindowsOnMonitor.ps1`.
2. Save it somewhere permanent, for example:
   `C:\Users\<you>\Scripts\Tile-WindowsOnMonitor.ps1`
3. Create a Windows shortcut with a target similar to:
   `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\<you>\Scripts\Tile-WindowsOnMonitor.ps1"`
4. Optionally configure the shortcut to **Run as administrator** if elevated windows must also be managed.
5. Start the shortcut and leave the utility running.

## Configuration

The main user-adjustable variables are grouped near the beginning of the script:

```powershell
$Version = 3.5

# Watchdog
$AutoExitSelectMode = $true
$ShowSelectModeWarning = $true
$SelectModeTimeoutSeconds = 10

# Tile
$gap = 3

# Cascade
$cascadeSortByTitle = $true
$cascadeWindowWidth = 700
$cascadeWindowHeight = 500
$cascadeOffsetX = 30
$cascadeOffsetY = 32
$cascadePerGroup = 4
$cascadeGroupGapX = 10
$cascadeGroupGapY = 2
```

## Help

PowerShell comment-based help is built in:

```powershell
Get-Help .\Tile-WindowsOnMonitor.ps1 -Full
```

## Version 3.5

- Added per-monitor Tile and grouped Cascade modes
- Added alphabetical Cascade sorting and configurable grouping
- Added single-instance and hotkey-conflict protection
- Added per-run window diagnostics
- Added filtering of non-normal windows such as `Program Manager`
- Added Select-mode watchdog and automatic recovery
- Added red SELECT MODE warning with live auto-release countdown
- Added PowerShell `Get-Help` documentation and authorship
- Tested with Windows PowerShell 5.1 on Windows 11

## Authors

**Idea, concept, requirements and relentless testing:**  
Mikael Nilsson

**PowerShell implementation:**  
Microsoft Copilot, with contributions by Mikael Nilsson

## License

MIT License. See `LICENSE`.
