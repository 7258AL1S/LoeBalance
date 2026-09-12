# LoeBalance Windows Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an isolated Windows port foundation on macOS while leaving the existing macOS application untouched.

**Architecture:** A .NET 8 solution under `windows/` separates platform-neutral LoeBalance behavior from Windows services and a future WPF shell. Core behavior mirrors the Swift implementation; Windows-only UI and OS integration remain explicit adapters for the Windows handoff.

**Tech Stack:** C# 12, .NET 8, xUnit, `HttpClient`, `System.Text.Json`, WPF, GitHub Actions Windows runners.

**Spec:** `docs/superpowers/specs/2026-09-12-windows-port-design.md`

## Global Constraints

- Do not modify any existing file under `Sources/`, `Tests/`, `script/`, `outputs/`, or the macOS release workflow.
- All Windows-port files live under `windows/`, except the specification, plan, handoff document, and GitHub workflow.
- Core projects must not reference WPF, Win32, Windows Forms, or Windows-only assemblies.
- Preserve the API URL, request headers, refresh semantics, reconciliation rules, and animation-planning contract from the Swift implementation.
- Windows runtime identifiers are `win-x64` and `win-x86`.

### Task 1: Create the isolated .NET solution

**Files:**
- Create: `windows/LoeBalance.Windows.sln`
- Create: `windows/src/LoeBalance.Core/LoeBalance.Core.csproj`
- Create: `windows/src/LoeBalance.Platform.Windows/LoeBalance.Platform.Windows.csproj`
- Create: `windows/src/LoeBalance.Desktop.Wpf/LoeBalance.Desktop.Wpf.csproj`
- Create: `windows/tests/LoeBalance.Core.Tests/LoeBalance.Core.Tests.csproj`
- Create: `windows/Directory.Build.props`
- Create: `windows/Directory.Build.targets`

- [x] **Step 1: Add project files and solution references.**

The core project targets `net8.0`; the WPF shell targets `net8.0-windows` with `UseWPF=true` and `EnableWindowsTargeting=true`; the platform project targets `net8.0`; the test project references the core project and xUnit packages.

- [x] **Step 2: Add a source layout manifest.**

Create `windows/README.md` with the project map, macOS isolation rule, and the exact commands used by the Windows handoff.

- [ ] **Step 3: Commit the solution skeleton.**

```bash
git add windows
git commit -m "port: scaffold Windows solution"
```

### Task 2: Port pure core models and money

**Files:**
- Create: `windows/src/LoeBalance.Core/Models/Money.cs`
- Create: `windows/src/LoeBalance.Core/Models/BalanceModels.cs`
- Create: `windows/src/LoeBalance.Core/Models/AppError.cs`
- Test: `windows/tests/LoeBalance.Core.Tests/MoneyTests.cs`
- Test: `windows/tests/LoeBalance.Core.Tests/ModelSerializationTests.cs`

- [x] **Step 1: Write tests for decimal parsing and formatting.**

Cover numeric JSON values, numeric strings, invalid strings, USD formatting with two decimal places, addition/subtraction, and magnitude.

- [x] **Step 2: Implement immutable records and enums.**

Use `decimal` for money. Define `BalanceSnapshot`, `UsageRecord`, `RefreshResult`, `ConnectionState`, `ShakeStrength`, and `BalanceAnimationEvent` with immutable properties.

- [ ] **Step 3: Run the core tests.**

```bash
dotnet test windows/tests/LoeBalance.Core.Tests/LoeBalance.Core.Tests.csproj
```

- [ ] **Step 4: Commit the core models.**

```bash
git add windows/src/LoeBalance.Core/Models windows/tests/LoeBalance.Core.Tests
git commit -m "port: add Windows core models"
```

### Task 3: Port API contracts and authentication

**Files:**
- Create: `windows/src/LoeBalance.Core/Networking/ApiContracts.cs`
- Create: `windows/src/LoeBalance.Core/Networking/ApiClient.cs`
- Create: `windows/src/LoeBalance.Core/Auth/AuthManager.cs`
- Create: `windows/src/LoeBalance.Core/Auth/CredentialContracts.cs`
- Test: `windows/tests/LoeBalance.Core.Tests/ApiClientTests.cs`
- Test: `windows/tests/LoeBalance.Core.Tests/AuthManagerTests.cs`

- [x] **Step 1: Write HTTP contract tests.**

Use a fake `HttpMessageHandler` to verify `POST /auth/login`, `POST /auth/refresh`, authenticated headers, `GET /auth/me`, `GET /usage/dashboard/stats`, `GET /usage?page=1&page_size=100`, API envelope errors, HTTP 401, HTTP 429, and malformed payloads.

- [x] **Step 2: Implement `ApiClient`.**

Use `HttpClient`, `System.Text.Json`, 30-second timeouts, snake-case JSON naming, flexible ISO-8601 date parsing, and typed `AppError` mapping.

- [x] **Step 3: Write and implement serialized token refresh.**

Expose `LoginAsync`, `RestoreSessionAsync`, `WithAccessTokenAsync`, and `LogoutAsync`. Store only a `StoredCredential` through `ICredentialStore`; keep access and refresh session values in memory.

- [ ] **Step 4: Run focused tests and commit.**

```bash
dotnet test windows/tests/LoeBalance.Core.Tests/LoeBalance.Core.Tests.csproj --filter "FullyQualifiedName~ApiClientTests|FullyQualifiedName~AuthManagerTests"
git add windows/src/LoeBalance.Core/Networking windows/src/LoeBalance.Core/Auth windows/tests/LoeBalance.Core.Tests
git commit -m "port: add Windows API and auth core"
```

### Task 4: Port balance service, persistence contracts, and reconciliation

**Files:**
- Create: `windows/src/LoeBalance.Core/Persistence/PersistenceContracts.cs`
- Create: `windows/src/LoeBalance.Core/Refresh/BalanceReconciler.cs`
- Create: `windows/src/LoeBalance.Core/Refresh/BalanceService.cs`
- Test: `windows/tests/LoeBalance.Core.Tests/BalanceReconcilerTests.cs`
- Test: `windows/tests/LoeBalance.Core.Tests/BalanceServiceTests.cs`

- [x] **Step 1: Write reconciliation tests.**

Cover chronological ordering, duplicate usage filtering, first-refresh baseline suppression, debit total reconciliation, residual credit, residual debit, 19 individual debit events, and aggregation beyond 20 records.

- [x] **Step 2: Implement storage contracts and balance refresh.**

Define `ISettingsStore`, `ISnapshotStore`, and `PersistedSnapshotState`. Keep the core independent from the Windows filesystem and Credential Manager.

- [x] **Step 3: Implement `BalanceService`.**

Fetch user, dashboard stats, and usage concurrently; preserve a usable user balance if stats or usage fail; save the next snapshot only after successful usage reconciliation.

- [ ] **Step 4: Run tests and commit.**

```bash
dotnet test windows/tests/LoeBalance.Core.Tests/LoeBalance.Core.Tests.csproj --filter "FullyQualifiedName~Balance"
git add windows/src/LoeBalance.Core/Persistence windows/src/LoeBalance.Core/Refresh windows/tests/LoeBalance.Core.Tests
git commit -m "port: add Windows balance reconciliation"
```

### Task 5: Port refresh scheduling and damage animation planning

**Files:**
- Create: `windows/src/LoeBalance.Core/Refresh/RefreshScheduler.cs`
- Create: `windows/src/LoeBalance.Core/Animation/DamageAnimationPlanner.cs`
- Test: `windows/tests/LoeBalance.Core.Tests/RefreshSchedulerTests.cs`
- Test: `windows/tests/LoeBalance.Core.Tests/DamageAnimationPlannerTests.cs`

- [x] **Step 1: Write scheduler tests.**

Cover one in-flight request, interval updates, manual refresh, offline pause, network recovery, system wake, retry-after deadlines, exponential backoff, cancellation, and 1/3600 second clamping.

- [x] **Step 2: Implement the scheduler.**

Use `CancellationToken`, a single loop task, a single in-flight refresh task, and an injected clock where deadline behavior needs deterministic tests.

- [x] **Step 3: Write animation planner tests.**

Cover desktop/menu ranges, debit/credit colors, launch delay `index * 0.23`, random movement bounds, reduce-motion ranges, and desktop-only shake.

- [x] **Step 4: Implement the planner.**

Keep the planner pure and deterministic when supplied with an injected random source. Leave actual WPF rendering outside the core.

- [ ] **Step 5: Run tests and commit.**

```bash
dotnet test windows/tests/LoeBalance.Core.Tests/LoeBalance.Core.Tests.csproj --filter "FullyQualifiedName~RefreshSchedulerTests|FullyQualifiedName~DamageAnimationPlannerTests"
git add windows/src/LoeBalance.Core/Refresh windows/src/LoeBalance.Core/Animation windows/tests/LoeBalance.Core.Tests
git commit -m "port: add Windows refresh and animation core"
```

### Task 6: Define Windows platform contracts and WPF shell boundaries

**Files:**
- Create: `windows/src/LoeBalance.Platform.Windows/PlatformContracts.cs`
- Create: `windows/src/LoeBalance.Platform.Windows/WindowsPlatformNotes.cs`
- Create: `windows/src/LoeBalance.Desktop.Wpf/App.xaml`
- Create: `windows/src/LoeBalance.Desktop.Wpf/App.xaml.cs`
- Create: `windows/src/LoeBalance.Desktop.Wpf/MainWindow.xaml`
- Create: `windows/src/LoeBalance.Desktop.Wpf/MainWindow.xaml.cs`
- Create: `windows/src/LoeBalance.Desktop.Wpf/Views/DesktopCardWindow.xaml`
- Create: `windows/src/LoeBalance.Desktop.Wpf/Views/TrayApplication.cs`

- [x] **Step 1: Define platform interfaces.**

Specify `ICredentialStore`, `ISettingsStore`, `INetworkAvailability`, `IPowerResumeMonitor`, `IStartupRegistration`, `ITrayPresenter`, and `IDesktopCardPresenter`. Document that Windows tray text is represented by tooltip/menu rather than a macOS-style text status item.

- [x] **Step 2: Add a minimal WPF shell.**

Create a non-functional but compilable shell with a desktop card placeholder, tray integration seam, and comments identifying the required Win32 styles: no taskbar button, non-activating behavior, non-topmost desktop placement, and DPI-aware positioning.

- [ ] **Step 3: Commit the platform boundary.**

```bash
git add windows/src/LoeBalance.Platform.Windows windows/src/LoeBalance.Desktop.Wpf
git commit -m "port: define Windows platform boundaries"
```

### Task 7: Add CI, packaging instructions, and handoff documentation

**Files:**
- Create: `.github/workflows/windows.yml`
- Create: `windows/README.md`
- Create: `docs/windows-port-handoff.md`
- Modify: `.gitignore` only for Windows build output patterns

- [x] **Step 1: Add Windows CI.**

Build and test the core on `windows-latest`, publish the WPF shell for `win-x64` and `win-x86`, and upload artifacts without requiring signing.

- [x] **Step 2: Add reproducible commands.**

Document `dotnet restore`, `dotnet build`, `dotnet test`, `dotnet publish -r win-x64`, and `dotnet publish -r win-x86`.

- [x] **Step 3: Write the handoff document.**

Include exact completed files, the Swift-to-C# mapping, Windows-only implementation tasks, known platform differences, environment assumptions, test evidence, and a step-by-step Windows acceptance checklist.

- [ ] **Step 4: Validate repository isolation and commit.**

```bash
git diff --name-only HEAD~1..HEAD
git status --short
git add .github/workflows/windows.yml windows/README.md docs/windows-port-handoff.md .gitignore
git commit -m "docs: hand off Windows port"
```

### Task 8: Final verification and handoff

- [x] **Step 1: Run Mac-side checks.**

Run source-level checks, YAML parsing if available, `git diff --check`, and confirm no file under the existing macOS implementation changed.

- [x] **Step 2: Record toolchain limitations.**

If `.NET` is not installed on macOS, explicitly record that the C# projects were not compiled locally and that GitHub Actions or Windows must provide the first real build.

- [x] **Step 3: Produce the final handoff summary.**

Report the exact handoff document path, current commit, files intentionally untouched, checks performed, and the first command to run on Windows.
