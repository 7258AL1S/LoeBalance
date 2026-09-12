# Task 11 Report: Application Coordination and Lifecycle Integration

Date: 2026-09-12
Branch: `feature/loe-balance`
Base: `de15704`

## Implemented

- Added the `@MainActor` `AppCoordinator` composition root with injectable authentication, balance, scheduler, network, desktop-card, status-bar, settings-window, and login-opening dependencies.
- Added production wiring for `APIClient`, Keychain-backed `AuthManager`, `BalanceService`, preferences and snapshot stores, `RefreshScheduler`, `NetworkMonitor`, `DesktopCardController`, `StatusBarController`, `SettingsWindowController`, `LaunchAtLoginService`, and a native login window.
- Added lifecycle transitions for missing/restored sessions, ordered snapshot presentation before animations, failure preservation, settings propagation, logout cleanup, wake, and network recovery.
- Added `AppDelegate` wake notification handling, termination cleanup, and accessory activation in `main.swift`.
- Added OSLog categories for auth, API, refresh, desktop, and status logging. Logs contain error descriptions only; no credentials or response bodies are logged.

## Files

- `Sources/LoeBalance/App/main.swift`
- `Sources/LoeBalance/App/AppDelegate.swift`
- `Sources/LoeBalance/App/AppCoordinator.swift`
- `Sources/LoeBalance/Support/Logger.swift`
- `Sources/LoeBalance/Core/AppError.swift` (removed the placeholder `@main` bootstrap so the real application entry point can link)
- `Tests/LoeBalanceTests/AppCoordinatorTests.swift`
- `.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-11/`

## TDD Evidence

`AppCoordinatorTests.swift` was added before the production coordinator. The required single focused command was attempted:

```sh
swift test --filter AppCoordinatorTests
```

It stopped during SwiftPM manifest compilation with `sandbox-exec: sandbox_apply: Operation not permitted`, before XCTest compilation. The repository retains the coordinator tests for a full Xcode/XCTest toolchain.

## Verification

The first full-source harness attempt was stopped after the compiler reported actor-isolated property accesses inside `require` autoclosures. Per the follow-up constraint, that full-source command was not retried. The runner was changed to a single bounded static focused check.

```sh
swift build
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-11/run-harness.sh
git diff --check
```

Results:

- `swift build`: passed, `Build complete! (3.92s)`.
- Task 11 bounded static harness: passed, `task-11 static harness passed: composition root, lifecycle transitions, ordered presentation, logging categories, and coordinator tests`.
- `git diff --check`: passed.

The single focused XCTest attempt remains environment-blocked before test compilation with:

```text
sandbox-exec: sandbox_apply: Operation not permitted
```

No second XCTest attempt and no second full-source harness compile were run.

The static harness verifies the real source files for the coordinator API, injectable dependency surface, wake/termination hooks, accessory activation, logging categories, secret/body logging exclusions, presentation-before-animation ordering, and required coordinator tests.

## Remaining Runtime Boundaries

- The active Command Line Tools environment cannot execute XCTest or SwiftPM manifest compilation in this sandbox, so the full test target and package build need a normal Xcode/SwiftPM environment.
- Live AppKit visual checks, login-window interaction, `SMAppService.mainApp`, Keychain access, and network path changes were not exercised.
- The prior full-source harness compile diagnostics were isolated to harness actor-access assertions; the revised required verification intentionally avoids another full-source compile per the latest constraint.

## Commit

`feat: integrate LoeBalance application lifecycle`

## Fix Round 1

Base: `ae6a3e3`

### Findings Addressed

- Refresh failures now reach `AppCoordinator`, map to offline/rate-limited/login-required/invalid-data connection states, preserve the last snapshot, update both surfaces, and never play animations on failure.
- Network loss now presents the cached snapshot as offline and pauses `RefreshScheduler`; recovery resumes scheduling and requests an immediate refresh.
- Menu-bar desktop-card toggles now go through `SettingsViewModel` persistence before coordinator/card/menu state changes. Failed saves retain the previous state and surface the settings error.
- App termination now uses `applicationShouldTerminate`, `.terminateLater`, awaited scheduler shutdown, and `NSApp.reply(toApplicationShouldTerminate: true)`.
- Logout marks the coordinator unauthenticated and clears the visible baseline before the first await, so queued refresh results are ignored.
- Auth restore only invalidates credentials for authentication-invalid errors. Transport, server, and rate-limit failures preserve credentials; the coordinator keeps retry/recovery active and presents the initial cached snapshot with the mapped connection state.

Focused XCTest sources were extended for failure mapping, network loss, transactional menu toggles, and transient restore recovery. XCTest was intentionally not run in this fix round.

The Task 11 harness remains a bounded static/focused check and does not invoke full-source `swiftc`.

### Verification

Final verification commands:

```sh
swift build
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-11/run-harness.sh
git diff --check
```

Results:

- `swift build`: passed, `Build complete! (3.88s)`.
- Task 11 bounded static harness: passed: `task-11 static harness passed: composition root, lifecycle transitions, ordered presentation, logging categories, and coordinator tests`.
- `git diff --check`: passed.

### Remaining Concerns

- Full SwiftPM/XCTest execution remains blocked by the active Command Line Tools sandbox; the new focused tests remain for a normal Xcode toolchain.
- Live AppKit termination, network path callbacks, Keychain behavior, and settings-window visual synchronization were not exercised.

### Commit

Commit message: `fix: harden application lifecycle integration`.
