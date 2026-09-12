# Task 10 Report: Login, Settings, and Launch at Login

Date: 2026-09-12
Branch: `feature/loe-balance`
Base: `3cea1e9`

## Implemented

- Added `LoginViewModel` with email validation, six-character minimum password validation, async `AuthManager` login, error mapping, and password clearing for both success and failure. The awaited login receives a local password copy that is cleared in `defer`.
- Added compact native SwiftUI `LoginView` with email, secure password, progress state, error state, and Sign In.
- Added `SettingsViewModel` with refresh presets, custom seconds/minutes conversion, `AppPreferences` 10...3600 clamping, preference persistence, scheduler interval updates, shake/card callbacks, launch-at-login state rollback, and logout dispatch.
- Added compact native SwiftUI `SettingsView` with segmented shake control, refresh menu/picker, custom interval controls, card/login toggles, and Log Out.
- Added `SettingsWindowController` using `NSHostingController` and explicit AppKit ownership.
- Added `LaunchAtLoginService` wrapping `SMAppService.mainApp` registration/unregistration and reading actual service status.
- Added focused `SettingsViewModelTests.swift` and a deterministic real-source harness under `harnesses/task-10`.

## Files Changed

- `Sources/LoeBalance/Settings/LoginView.swift`
- `Sources/LoeBalance/Settings/LoginViewModel.swift`
- `Sources/LoeBalance/Settings/SettingsView.swift`
- `Sources/LoeBalance/Settings/SettingsViewModel.swift`
- `Sources/LoeBalance/Settings/SettingsWindowController.swift`
- `Sources/LoeBalance/Support/LaunchAtLoginService.swift`
- `Tests/LoeBalanceTests/SettingsViewModelTests.swift`
- `.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-10/README.md`
- `.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-10/run-harness.sh`
- `.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-10/Task10Harness.swift`
- `.superpowers/sdd/2026-09-12-loe-balance/task-10-report.md`
- `.superpowers/sdd/2026-09-12-loe-balance/progress.md`

## TDD Evidence

The focused XCTest source was added before Task 10 production files. The required focused attempt was run once:

```sh
swift test --filter SettingsViewModelTests
```

Result: exit 1 at the known environment boundary because the active Command Line Tools toolchain has no XCTest module:

```text
error: no such module 'XCTest'
```

The new test source was included in the attempted test-target compilation; no XCTest assertions executed. No second focused XCTest attempt was run.

## Harness Coverage

The runner compiles the real Task 10 source and required dependencies with:

```sh
swiftc -warnings-as-errors -parse-as-library ...
```

It avoids live network access, Keychain access, and live `SMAppService.mainApp` state by using actor API/scheduler fakes plus in-memory credentials, preferences, and launch services.

Command:

```sh
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-10/run-harness.sh
```

Result:

```text
task-10 harness passed: login validation/cleanup, interval settings, callbacks, launch rollback, logout
```

Coverage includes:

- invalid email and five-character password rejection without API calls;
- successful and failed login password delivery and published password clearing;
- 30-second/one-minute/five-minute presets;
- custom minutes-to-seconds conversion;
- lower and upper interval clamping to 10 and 3,600 seconds;
- shake strength and desktop-card visibility persistence and callbacks;
- launch-at-login registration, actual state reading, and failure rollback;
- logout command dispatch.

## Verification

Commands:

```sh
swift build
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-10/run-harness.sh
git diff --check
```

Results:

```text
Build complete! (3.22s)
task-10 harness passed: login validation/cleanup, interval settings, callbacks, launch rollback, logout
```

`git diff --check` produced no output.

## Self-Review

- Swift 6 isolation is explicit: view models and SwiftUI/AppKit controllers are `@MainActor`; scheduler/API fakes in the harness are actors; actor values are read into locals before assertions.
- Existing `AuthManager`, `AppPreferences`, `PreferencesStoreProtocol`, and `RefreshScheduling` APIs are consumed without changing unrelated modules.
- Launch-at-login is isolated behind `LaunchAtLoginServicing`, allowing deterministic failure rollback while production uses `SMAppService.mainApp`.
- The settings UI is compact and native: segmented shake control, picker/menu refresh control, numeric interval plus unit picker, toggles, and a logout button. No explanatory feature text was added.
- The committed XCTest source covers the requested behavior even though XCTest cannot run in this environment.

## Remaining Risks and Runtime Boundaries

- XCTest remains unavailable under the active Command Line Tools installation, so the focused test assertions were not executed here.
- SwiftUI layout, keyboard focus, accessibility presentation, and the live settings window appearance were not visually observed in a running app.
- Actual `SMAppService.mainApp` registration/unregistration was not exercised; the production adapter is a thin framework wrapper and the harness validates its protocol contract with a fake.
- The Task 11 coordinator must wire the view models' callbacks, scheduler, and logout action into the application lifecycle.
