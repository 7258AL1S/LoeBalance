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

## 12. Windows Implementation Update (2026-09-12, Windows workstation)

This section records what the Windows session completed on top of the handoff above.
Nothing under `Sources/`, `Tests/`, `script/`, or `outputs/` was modified, and every
Windows change lives under `windows/`.

### 12.1 Build fixes required before the port could compile

| File | Problem | Fix |
|---|---|---|
| `windows/src/LoeBalance.Core/Animation/DamageAnimationPlanner.cs` | `CS0173`: conditional expression between `ShakeStrength` and `null` | Declared the local as `ShakeStrength?`, matching the Swift optional `shakeStrength` |
| `windows/src/LoeBalance.Desktop.Wpf/App.xaml.cs` | `CS0104`: `Application` ambiguous between WPF and WinForms | Qualify as `System.Windows.Application` |
| `windows/src/LoeBalance.Desktop.Wpf/LoeBalance.Desktop.Wpf.csproj` | `NETSDK1137` deprecated `Microsoft.NET.Sdk.WindowsDesktop` | Use `Microsoft.NET.Sdk` and keep `UseWPF`/`UseWindowsForms` |

The failing GitHub Actions run `34701033140` stopped on exactly the `DamageAnimationPlanner`
error, so the first Windows build reproduced the same failure before the fix.

### 12.2 Behaviour gaps found while reviewing the ported core

1. `PersistedSnapshotState` did not bound or reorder recent usage ids. With a saturated
   cache the newest ids were dropped and the next refresh replayed debit animations.
   Fixed with macOS `recordUsageIDs` semantics (move to the end, dedupe, keep newest 500).
2. `Money` accepted `1,234.56` and other non-strict numeric strings that the macOS grammar
   rejects. Now validated against the same strict decimal pattern.
3. `AuthManager` used a two-minute proactive refresh window, did not verify the refreshed
   user id, and could reuse a session without a user id. Now 60 seconds, user id verified,
   and a user mismatch invalidates the stored credential.
4. `RefreshScheduler` treated a past or missing `Retry-After` as an immediate retry, which
   could busy-loop, and an unexpected exception stopped the loop. Now mirrors the macOS
   `applyRateLimit` rules (future deadline wins, otherwise bounded backoff) and the loop
   survives unexpected failures.
5. `IWindowsSettingsStore` inherited both `ISettingsStore` and `ISnapshotStore`, which
   declare `LoadAsync` with different return types and cannot be implemented by one class.
   Split into `IWindowsSettingsStore` and `IWindowsSnapshotStore`.

### 12.3 Implemented on Windows

- `WindowsCredentialStore`: `CredRead`/`CredWrite`/`CredDelete` against the generic
  credential target `LoeBalance:sub2api-refresh-token`. The stored blob is JSON with
  exactly two fields, `refreshToken` and `userId`. Passwords and access tokens are never
  written to disk; the access token stays in memory.
- `LocalAppDataSettingsStore` / `LocalAppDataSnapshotStore`: separate JSON files under
  `%LOCALAPPDATA%\LoeBalance`, written to a temporary file, flushed to disk, then moved
  over the target.
- `NetworkAvailabilityMonitor`: `NetworkAvailabilityChanged` plus `NetworkAddressChanged`,
  deduplicated, handlers detached on `Stop`/`Dispose`.
- `PowerResumeMonitor`: `SystemEvents.PowerModeChanged` resume notifications, detached on
  `Stop`/`Dispose`, degrades gracefully when power notifications are unavailable.
- `StartupRegistration`: per-user `Run` key registration that reports the actual registry
  state after every change.
- `TrayPresenter`: connection-state icon, balance/status tooltip, and the context menu
  (balance, status, Refresh Now, Show/Hide Desktop Card, Settings, Log Out, Quit) with the
  macOS enablement rules. No floating debit numbers are drawn next to the tray icon.
- `DesktopCardWindow`: borderless, `ShowInTaskbar=false`, `WS_EX_NOACTIVATE` +
  `WS_EX_TOOLWINDOW`, never topmost, pushed to the desktop layer, drag to move, position
  memory, and work-area clamping on the owning monitor.
- `DamageStreamCanvas`: one visual track, `index * 0.23s` launch delays, bounded random
  horizontal offsets, red debit and green credit text, plus card-only shake for the first
  debit of a burst and reduced travel under Reduce Motion.
- WPF login and settings windows, `AppCoordinator` composition root, single-instance guard,
  and `ShutdownMode.OnExplicitShutdown` so the tray keeps the process alive.
- `--preview-card` diagnostic mode and `windows/tools/verify-desktop-card.ps1` for
  real-machine checks of z-order, DPI, clamping and the animation stream.

### 12.4 Verification performed on Windows

Executed on this workstation (Windows, .NET SDK 8.0.425 installed into the session's work
directory because the machine had runtimes only):

| Command | Result |
|---|---|
| `dotnet restore windows\LoeBalance.Windows.sln` | success |
| `dotnet build windows\LoeBalance.Windows.sln -c Release` | success, 0 warnings, 0 errors |
| `dotnet test windows\tests\LoeBalance.Core.Tests\...` | 67 passed, 0 failed |
| `dotnet test windows\tests\LoeBalance.Platform.Windows.Tests\...` | 17 passed, 0 failed (real Credential Manager, registry and file-store usage) |
| `dotnet publish ... -r win-x64 --self-contained true` | success |
| `dotnet publish ... -r win-x86 --self-contained true` | success |

Real-machine observations from launching the published `win-x64` build:

- Normal start with no stored credential: process stays alive and shows the Sign In window.
- Second instance exits immediately (single-instance guard).
- `--preview-card`: the card window reports `WS_EX_TOOLWINDOW` and `WS_EX_NOACTIVATE`, has
  no `WS_EX_APPWINDOW` (no taskbar button), is not topmost, and stays visible.
- Moving the card to `300,200` writes `desktopCardFrame` `{x:300, y:200, 326x218}` to
  `%LOCALAPPDATA%\LoeBalance\settings.json`; the next start restores it exactly.
- A saved off-screen frame of `5000,5000` is clamped back inside the monitor work area.
- A mixed DPI defect (native `SetWindowPos` pixels fighting WPF's DIP model at 150%) was
  found during this testing and fixed by letting WPF own `Left`/`Top` in DIPs.

### 12.5 Still requires manual verification

- Live login and balance refresh against the real API with a real account.
- 125% / 150% DPI and mixed-DPI multi-monitor placement (only 100% DPI was exercised here).
- Sleep/wake refresh, network disconnect/reconnect refresh, and live `Retry-After` behavior.
- Tray tooltip truncation and context-menu behavior at high DPI.
- Installer, Authenticode signing, and SmartScreen validation.

## 13. Taskbar Balance Readout (2026-09-13)

The Windows taskbar has no supported API for custom text: deskbands are gone and Windows 11
removed the toolbars that older shell extensions used. The readout is therefore implemented
as a small topmost, non-activating overlay window docked against the notification area, which
is the same technique desktop taskbar widgets use.

### 13.1 Behaviour

- Docked just left of `TrayNotifyWnd` (tray + clock) on horizontal taskbars, and above the
  tray block on vertical Windows 10 taskbars. The arithmetic lives in
  `LoeBalance.Core.Presentation.TaskbarBalanceGeometry` and is unit tested.
- Follows the taskbar every second, so resolution changes, taskbar docking changes, taskbar
  auto-hide and Explorer restarts are picked up. When the shell reports a full-screen app,
  presentation mode, the lock screen or an absent session, the readout hides itself.
- Topmost, `WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`, no taskbar button, never activates on click.
- Left-clicking the readout opens the same context menu as the tray icon.
- Shows a static balance plus the connection dot. It never shakes and never carries the
  floating debit/credit numbers; those stay on the desktop card.
- Toggleable from the tray menu ("Show/Hide Taskbar Balance") and from
  Settings → "Show balance on the taskbar". Persisted as `showsTaskbarBalance` (default on).

### 13.2 Verification performed

| Item | Evidence |
|---|---|
| Core geometry | 6 new unit tests (bottom/top/vertical taskbars, clamping, edge detection, fallback tray rect) |
| Build and suites | Release build 0 warnings/0 errors; 74 core tests and 18 platform tests pass |
| Real machine (Windows 11 26200, 2560x1600 @125%) | Readout window created at 66x24 DIP just left of the tray (8 DIP gap), ex-style `0x08080088` = TOPMOST + TOOLWINDOW + NOACTIVATE + LAYERED, no app window |
| Rendering | Screen capture of the taskbar strip shows the readout drawn above the taskbar with the live balance |

A defect found during this work: the readout window never appeared because the placement ran
before the HWND existed and returned early. Fixed by creating the handle up front
(`EnsureHandle`) before solving the position, the same fix applied earlier to the desktop card.

### 13.3 Still requires manual verification

- Clicking the readout to open the context menu.
- Toggling the readout from both the tray menu and the settings window.
- Behaviour with a full-screen game/video and with taskbar auto-hide enabled.
