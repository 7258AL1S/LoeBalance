# LoeBalance Windows Port

This directory is an isolated Windows implementation path. The existing macOS app under `Sources/LoeBalance/` is intentionally untouched.

## Current state

Implemented and compiled on Windows (.NET 8):

- .NET 8 solution and project boundaries.
- Platform-neutral money, models, API contracts, authentication, balance service, reconciliation, scheduler, and animation planner.
- Windows Credential Manager store that persists only the refresh token and user id.
- `%LOCALAPPDATA%\LoeBalance` settings and snapshot stores with atomic writes.
- Network availability monitor, power-resume monitor, and per-user startup registration.
- NotifyIcon tray presenter: connection icon, balance tooltip, right-click menu.
- Taskbar balance readout docked against the notification area (topmost overlay window,
  because Windows 11 has no deskband/taskbar-text API). Static balance only, toggled from the
  tray menu or settings.
- Desktop card window: borderless, non-activating, no taskbar button, never topmost,
  desktop-layer placement, work-area clamping, and saved position memory.
- Damage stream canvas with single-track launches, red debits, green credits, card-only shake.
- WPF login and settings windows, composition root, single-instance guard.
- xUnit tests for core behavior plus Windows-only adapter tests.

Still requires manual verification on Windows hardware:

- Real account login and live balance refresh against `https://api.loe.cx/api/v1`.
- 125% and 150% DPI plus mixed-DPI multi-monitor placement.
- Sleep/wake refresh, network disconnect/reconnect refresh, and `Retry-After` behavior.
- Installer, Authenticode signing, and SmartScreen validation.

## Commands on Windows

```powershell
dotnet restore windows\LoeBalance.Windows.sln
dotnet build windows\LoeBalance.Windows.sln -c Release
dotnet test windows\tests\LoeBalance.Core.Tests\LoeBalance.Core.Tests.csproj
dotnet test windows\tests\LoeBalance.Platform.Windows.Tests\LoeBalance.Platform.Windows.Tests.csproj
dotnet publish windows\src\LoeBalance.Desktop.Wpf\LoeBalance.Desktop.Wpf.csproj -c Release -r win-x64 --self-contained true
dotnet publish windows\src\LoeBalance.Desktop.Wpf\LoeBalance.Desktop.Wpf.csproj -c Release -r win-x86 --self-contained true
```

## Diagnostic entry points

```powershell
# Shows the desktop card with a synthetic snapshot and a repeating debit/credit burst.
# Use it to check z-order, DPI scaling, multi-monitor clamping and the animations without
# a live account.
LoeBalance.Desktop.Wpf.exe --preview-card

# Prints the card window styles (tool window, no app window, no activate, not topmost),
# its rect, the monitor work area, and can move the card to test position memory.
powershell -File windows\tools\verify-desktop-card.ps1 -ProcessId <pid> -MoveToX 300 -MoveToY 200
```

The Windows-specific acceptance list is in `docs/windows-port-handoff.md`.
