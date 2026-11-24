# Tile Windows on Monitor v3.5

First stable public release.

## Highlights

- Tile all eligible windows on the monitor under the mouse pointer with `Ctrl+Alt+T`
- Grouped, configurable Cascade with `Ctrl+Alt+C`
- Clean shutdown with `Ctrl+Alt+Q`
- Alphabetical Cascade sorting
- Multi-monitor support
- Single-instance and hotkey-conflict protection
- Per-run processed-window diagnostics
- QuickEdit/Select-mode watchdog with red countdown warning
- Built-in `Get-Help` documentation
- Windows PowerShell 5.1 / Windows 11 support

## Known behavior

- Minimized windows are intentionally ignored.
- Run the utility elevated if it must reposition elevated application windows.
- A known non-normal top-level window titled `Program Manager` is excluded.
