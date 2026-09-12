# Task 6 Report: Refresh Scheduler, Backoff, and Network Recovery

Date: 2026-09-12
Branch: `feature/loe-balance`
Base: `3f1186a`

## Implemented

- Added actor-isolated `RefreshScheduler` with immediate start refresh, configured and clamped intervals, interval updates, shared in-flight refreshes, offline pause, network recovery, system wake refresh, Retry-After deadlines, bounded backoff of 10/20/40/80/160/300 seconds, and stop cancellation.
- Added `NetworkMonitor` as a status-only `NWPathMonitor` adapter. It emits availability changes and does not own refresh behavior.
- Added actor-safe scheduler tests with injected sleepers and refresh fakes.
- Added persistent harness notes at `harnesses/task-6/README.md` covering all required scenarios and explicitly avoiding real sleep/network.

## Commands and outputs

### Red phase, before implementation

Command:

```sh
swift test --filter RefreshSchedulerTests
```

Result: exit 1. Compilation stopped with:

```text
error: no such module 'XCTest'
```

### Red phase, after test source was added

Command:

```sh
swift test --filter RefreshSchedulerTests
```

Result: exit 1. Same environment failure: `error: no such module 'XCTest'` while compiling the existing test target and the new scheduler test source.

### Focused verification

Command:

```sh
swift test --filter RefreshSchedulerTests
```

Result: exit 1. Same `XCTest` module failure. No scheduler assertions executed.

### Full test suite

Command:

```sh
swift test
```

Result: exit 1. Same `XCTest` module failure. No tests executed.

### Production build and whitespace validation

Command:

```sh
swift build && git diff --check
```

Result: exit 0.

```text
Build complete!
```

`git diff --check` produced no output.

## Concerns

- XCTest is unavailable in the current command-line toolchain, so the new test suite could not be compiled or run here. The test source remains in the requested target and should be run on the macOS/Xcode environment that provides XCTest.
- Physical network path transitions were not exercised. The monitor adapter is platform-conditional and only publishes status; scheduler behavior is covered by injected calls in the test source.

## Fix Round 1

### Focused XCTest attempt

Command:

```sh
swift test --filter RefreshSchedulerTests
```

Result: exit 1. The current command-line toolchain still cannot import XCTest:

```text
error: no such module 'XCTest'
```

The new tests now read actor values into locals before XCTest assertions and include timer/manual sharing, no-header 429 fallback, the complete fallback sequence, and stop/in-flight/restart coverage.

### Build and executable harness

Commands:

```sh
swift build
git diff --check
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-6/run-harness.sh
```

Results:

```text
Build complete!
task-6 harness passed: immediate, timer/manual sharing, retry-after/fallback, offline/restart/wake, injected sleep
```

`git diff --check` produced no output. The harness compiles and runs the real `Sources/LoeBalance/Refresh/RefreshScheduler.swift` with actor fakes and injected sleeping; it does not use XCTest, real network, or real polling sleeps.

### Fix scope

- Added epoch guards to loop and refresh task completion paths, including cleanup.
- Made Retry-After an active shared deadline; success clears it and resets fallback retry state.
- Added fallback handling for `rateLimited(nil)` and transport/server failures without normal-interval polling spin.
- Suppressed duplicate network availability callbacks.
- Added executable harness sources and runner.

## Fix Round 2

### Focused XCTest

Command:

```sh
swift test --filter RefreshSchedulerTests
```

Result: exit 1 because this environment has no XCTest module:

```text
error: no such module 'XCTest'
```

### Build, diff, and executable harness

Commands:

```sh
swift build
git diff --check
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-6/run-harness.sh
```

Results:

```text
Build complete! (0.33s)
task-6 harness passed: immediate, timer/manual sharing, retry-after/fallback, offline/restart/wake, injected sleep
```

`git diff --check` produced no output.

### Fixes

- Automatic polling now requests the active Retry-After remaining duration before normal interval/backoff; manual, wake, and recovery paths share the same deadline task.
- Added timer/manual single-flight coverage with a gated timer refresh.
- Stop clears retry deadline and backoff state; restart coverage uses the same scheduler instance.
- Added fixed-clock executable assertion for a 120-second Retry-After sleep request.
- Injected refresh closures remain explicitly `@Sendable`; harness output is warning-free.
