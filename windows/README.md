# LoeBalance Windows Port

This directory is an isolated Windows implementation path. The existing macOS app under `Sources/LoeBalance/` is intentionally untouched.

## Current phase

Implemented on macOS:

- .NET 8 solution and project boundaries.
- Platform-neutral money, models, API contracts, authentication, balance service, reconciliation, scheduler, and animation planner.
- xUnit tests for the pure core behavior.
- Windows platform interfaces and a future WPF shell boundary.

Still requires Windows:

- Credential Manager implementation.
- WPF tray icon and context menu.
- Desktop card window layering and non-activating behavior.
- DPI and multi-monitor testing.
- Startup registration, network/power event adapters, installer, signing, and runtime tests.

## Commands on Windows

```powershell
dotnet restore windows\LoeBalance.Windows.sln
dotnet build windows\LoeBalance.Windows.sln -c Release
dotnet test windows\tests\LoeBalance.Core.Tests\LoeBalance.Core.Tests.csproj
dotnet publish windows\src\LoeBalance.Desktop.Wpf\LoeBalance.Desktop.Wpf.csproj -c Release -r win-x64 --self-contained true
dotnet publish windows\src\LoeBalance.Desktop.Wpf\LoeBalance.Desktop.Wpf.csproj -c Release -r win-x86 --self-contained true
```

The Windows-specific acceptance list is in `docs/windows-port-handoff.md`.
