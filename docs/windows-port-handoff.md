# LoeBalance Windows Port Handoff

**Handoff date:** 2026-09-12
**Source repository:** `https://github.com/7258AL1S/LoeBalance`
**Current branch:** `main`
**Purpose:** Continue the Windows port on a Windows computer without changing the existing macOS app.

This phase leaves the working tree uncommitted so the next Windows session can review the complete port foundation before creating a release commit.

## 1. Current Status

The Windows port is isolated under `windows/`. No existing macOS implementation file under `Sources/LoeBalance/` was modified for this work. The macOS build scripts and macOS release artifacts remain separate.

Completed on the Mac:

- Created a .NET 8 solution with core, Windows platform, WPF shell, and test projects.
- Ported the platform-neutral money model and balance models.
- Ported typed API contracts and the Sub2API HTTP client.
- Ported serialized authentication and refresh-token lifecycle boundaries.
- Ported balance refresh, snapshot persistence contracts, reconciliation, and burst aggregation.
- Ported refresh scheduling behavior and damage animation planning behavior.
- Defined Windows service interfaces for credentials, settings, network, power resume, startup, tray, and desktop card presentation.
- Added a minimal WPF shell and tray integration seam.
- Added xUnit tests for core behavior.
- Added GitHub Actions workflow for Windows build/test and `win-x64`/`win-x86` publish artifacts.

Not completed and must be done on Windows:

- Real Windows Credential Manager adapter.
- Persistent settings/snapshot adapter using `%LOCALAPPDATA%` with atomic writes.
- Production tray menu and tooltip updates.
- Production desktop card rendering and damage animations.
- Desktop-only Z-order and non-activating behavior.
- Network availability and power-resume adapters.
- Startup registration.
- Single-instance behavior.
- Windows 10/11, DPI, multi-monitor, sleep/wake, and real-account testing.
- Installer, Authenticode signing, SmartScreen validation, and final release publication.

## 2. Important Isolation Rule

Do not edit these existing macOS paths while completing the Windows port:

```text
Sources/LoeBalance/
Tests/LoeBalanceTests/
script/build_and_run.sh
script/package_release.sh
outputs/
```

Windows work belongs in:

```text
windows/
```

The only intended shared documentation changes are under `docs/` and the root `.gitignore`.

## 3. Solution Layout

```text
windows/
  LoeBalance.Windows.sln
  Directory.Build.props
  Directory.Build.targets
  README.md
  src/
    LoeBalance.Core/
      Models/
      Networking/
      Auth/
      Persistence/
      Refresh/
      Animation/
    LoeBalance.Platform.Windows/
    LoeBalance.Desktop.Wpf/
  tests/
    LoeBalance.Core.Tests/
```

`LoeBalance.Core` must remain free of WPF, Win32, Windows Forms, and Windows-only references. It is the only project that should contain behavior-level parity with the Swift implementation.

## 4. Swift-to-C# Mapping

| macOS source | Windows destination | Status |
|---|---|---|
| `Core/Money.swift` | `Core/Models/Money.cs` | Ported |
| `Core/Models.swift` | `Core/Models/BalanceModels.cs` | Ported |
| `Core/AppError.swift` | `Core/Models/AppError.cs` | Ported |
| `Networking/APIModels.swift` | `Core/Networking/ApiContracts.cs` | Ported |
| `Networking/APIClient.swift` | `Core/Networking/ApiClient.cs` | Ported |
| `Auth/AuthManager.swift` | `Core/Auth/AuthManager.cs` | Ported behavior boundary |
| `Auth/CredentialStore.swift` | `Platform.Windows` Credential Manager adapter | Pending Windows implementation |
| `Refresh/BalanceService.swift` | `Core/Refresh/BalanceService.cs` | Ported |
| `Refresh/BalanceReconciler.swift` | `Core/Refresh/BalanceReconciler.cs` | Ported |
| `Refresh/RefreshScheduler.swift` | `Core/Refresh/RefreshScheduler.cs` | Ported behavior boundary |
| `Animation/DamageAnimationPlanner.swift` | `Core/Animation/DamageAnimationPlanner.cs` | Ported |
| `Animation/DamageStreamView.swift` | WPF `Canvas`/Storyboard control | Pending |
| `DesktopCard/*` | WPF desktop card window | Shell placeholder only |
| `StatusBar/*` | WinForms `NotifyIcon` + context menu | Shell placeholder only |
| `Settings/*` | WPF settings/login windows | Pending |
| `Persistence/*` | Windows JSON stores | Contract only |
| `Support/NetworkMonitor.swift` | Windows network adapter | Contract only |
| `Support/LaunchAtLoginService.swift` | Windows startup adapter | Contract only |
| `App/AppCoordinator.swift` | WPF composition root | Pending |

## 5. Behavioral Contract

The Windows implementation must preserve these values and rules:

- Base URL: `https://api.loe.cx/api/v1`.
- Authenticated headers: `Authorization: Bearer <access token>`, `Accept-Language: zh`, and `X-User-UI-Request: 1`.
- Request timeout: 30 seconds.
- Usage request: `page=1&page_size=100`.
- Refresh interval clamp: 1 through 3600 seconds.
- One in-flight refresh request at a time.
- 401: refresh once and replay the failed operation once.
- 429: honor `Retry-After` when present.
- Offline: pause scheduled refreshes; network recovery triggers an immediate refresh.
- Power resume: trigger an immediate refresh.
- First successful refresh after no cached snapshot: show no debit/credit animation.
- Usage ordering: `(createdAt, id)` ascending.
- Up to 20 usage records: individual debit events.
- More than 20 records: first 19 individual events plus one aggregate event.
- Debit animation color: red.
- Credit animation color: green.
- Launch delay: `index * 0.23` seconds.
- Menu/tray surface never shakes.
- Desktop surface supports shake `Off`, `Weak`, and `Strong` unless Reduce Motion is enabled.

## 6. First Windows Session

Run these commands from the repository root in PowerShell:

```powershell
dotnet --info
dotnet restore windows\LoeBalance.Windows.sln
dotnet build windows\LoeBalance.Windows.sln -c Release
dotnet test windows\tests\LoeBalance.Core.Tests\LoeBalance.Core.Tests.csproj
```

If the solution does not compile, fix project/SDK issues before implementing platform services. Do not work around failures by adding macOS source references.

## 7. Windows Implementation Order

1. Implement `IWindowsCredentialStore` with Windows Credential Manager. Store only refresh token and user id. Never store password or access token.
2. Implement `IWindowsSettingsStore` using `%LOCALAPPDATA%\LoeBalance`. Use separate settings and snapshot JSON files, write to a temporary file, flush, then replace the target.
3. Implement `INetworkAvailabilityMonitor` and `IPowerResumeMonitor`. Ensure event handlers can be detached and do not keep the app alive after shutdown.
4. Implement `IStartupRegistration`. Report the actual enabled state after changes.
5. Replace `TrayApplication` with a real `ITrayPresenter`. Use icon state plus tooltip/context menu. Do not attempt to keep a floating red number attached to the tray icon.
6. Implement `IDesktopCardPresenter` with a non-resizable, borderless WPF window. Validate non-activation, non-topmost desktop placement, taskbar exclusion, DPI scaling, and position clamping.
7. Implement WPF login/settings views and connect them to `AuthManager`, `ISettingsStore`, and `IRefreshScheduler`.
8. Add the composition root and lifecycle transitions equivalent to `AppCoordinator`.
9. Add single-instance locking and clean shutdown.
10. Add installer/signing and publish both runtime identifiers.

## 8. UI Decisions

The Windows notification area is not a direct equivalent of macOS `NSStatusItem`. The accepted Windows design is:

- Tray icon: connection state icon.
- Tooltip: current balance and last update time.
- Context menu: balance summary, connection state, refresh, desktop card toggle, settings, logout, quit.
- Desktop card: detailed balance, today spend, today requests, connection state, red debit stream, green credit stream, and desktop shake.

The red debit numbers must not overlap. Keep one visual track, launch at short fixed intervals, and randomize horizontal offsets within a bounded area.

## 9. Testing Requirements

Core tests should run on every commit and must cover:

- decimal money parsing and formatting;
- API headers, URLs, envelope errors, 401, 429, and malformed JSON;
- serialized token refresh and one retry;
- snapshot persistence and duplicate usage filtering;
- residual credit/debit reconciliation;
- 19-plus-one usage aggregation;
- scheduler clamping and cancellation;
- network recovery, wake, retry-after, and backoff;
- animation ranges, delays, colors, Reduce Motion, and desktop-only shake.

Windows manual test matrix:

| Area | Cases |
|---|---|
| OS | Windows 10 and Windows 11 |
| Runtime | `win-x64` and `win-x86` |
| Display | 100%, 125%, 150%, mixed DPI |
| Displays | one monitor, two monitors, monitor disconnect |
| Window | show desktop, open/close apps, move card, relaunch |
| Lifecycle | startup, logout, quit, sleep/wake, network disconnect/reconnect |
| Security | Credential Manager persistence, no password on disk/logs |
| API | normal response, 401 refresh, 429 retry-after, offline timeout |
| Animation | debit burst, credit, high-frequency debit, Reduce Motion |

## 10. Current Evidence and Limitations

The macOS host used for this phase is Intel macOS 15.7.9 with Swift 6.1.2 and Command Line Tools. `swift build` passed for the existing macOS application. `swift test` reached the test target but could not import `XCTest` because the host has Command Line Tools only; this is an environment limitation.

The host does not have the .NET SDK installed, so the new C# projects were not compiled locally. The first authoritative C# build must be performed by GitHub Actions or on the Windows computer. This Windows-port work did not alter the existing macOS source or scripts.

The workflow `.github/workflows/windows.yml` is configured for `windows-latest`, .NET 8, `win-x64`, and `win-x86`.

## 11. Completion Criteria

The Windows port is ready for release only when all of the following are true:

- `dotnet build windows\LoeBalance.Windows.sln -c Release` passes on Windows.
- Core xUnit tests pass.
- Both `win-x64` and `win-x86` publish commands pass.
- Credential Manager and password non-persistence are manually verified.
- Tray tooltip/menu and desktop card work on Windows 10 and 11.
- Desktop-only placement is verified at 100%, 125%, and 150% DPI.
- Sleep/wake and network recovery are verified.
- Installer is signed and tested on a clean Windows user account.
- GitHub Release notes clearly identify `win-x64` and `win-x86` packages.
