# Task 7 Report: Deterministic Damage Motion Planning and Stream View

Date: 2026-09-12
Branch: `feature/loe-balance`
Base: `10b21f6`

## Implemented

- Added Foundation-only `DamageAnimationPlanner` with injectable `MotionRandomizing`.
- Added exact 0.23-second launch spacing, 0.82-second normal duration, desktop ranges, and smaller menu bar ranges.
- Added debit/credit styles and red/green presentation metadata.
- Added one shake marker per contiguous desktop debit burst for Weak/Strong, no marker for Off, menu bar, credits, or Reduce Motion.
- Added shorter Reduce Motion duration/rise ranges.
- Added main-actor, layer-backed `DamageStreamView` with fixed intrinsic size, non-editable `CATextLayer` labels, position/opacity/scale/rotation keyframes, and post-animation layer removal.
- Added complete planner XCTest source and a warnings-as-errors executable harness using real source files only.

## Commands and outputs

### Red phase, before production implementation

Command:

```sh
swift test --filter DamageAnimationPlannerTests
```

Result: exit 1 before planner diagnostics because the current Command Line Tools environment has no XCTest module:

```text
error: no such module 'XCTest'
```

The test source was written before the production files, as required. No XCTest assertions executed.

### Focused XCTest after implementation

Command:

```sh
swift test --filter DamageAnimationPlannerTests
```

Result: exit 1. Same environment limitation:

```text
error: no such module 'XCTest'
```

### Full XCTest suite

Command:

```sh
swift test
```

Result: exit 1. Same environment limitation:

```text
error: no such module 'XCTest'
```

### Production build

Command:

```sh
swift build
```

Result: exit 0.

```text
Build complete! (0.36s)
```

### Real-source harness

Command:

```sh
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-7/run-harness.sh
```

Result: exit 0. The runner uses `swiftc -warnings-as-errors` and compiles the real Core, planner, and AppKit stream-view sources without network or Keychain access.

```text
task-7 harness passed: cadence, ranges, deterministic randomness, styles, burst shake, Reduce Motion, fixed stream size
```

### Diff validation

Command:

```sh
git diff --check
```

Result: exit 0; no output.

## Self-review

- Planner ownership is independent from AppKit and uses only existing `BalanceAnimationEvent`, `Money`, and `ShakeStrength` domain types.
- Random values are consumed through an injected protocol, allowing repeatable seeded/sequence verification.
- Launch delays are indexed from one origin at 0.00, 0.23, and 0.46 seconds for the sample burst; all durations remain concurrent at 0.82 seconds in normal mode.
- Menu bar plans never carry shake metadata, and the stream view does not change its owner frame or intrinsic size when layers are added.
- Credit/debit labels are formatted from `Money.currencyText`, colored green/red, and removed after their scheduled animation completes.
- The committed XCTest source remains complete even though this command-line toolchain cannot import XCTest.

## Concerns

- XCTest could not be compiled or executed on this machine because `/Library/Developer/CommandLineTools` does not provide the XCTest module. The executable harness covers the requested planner and stream invariants instead; XCTest should be run under an Xcode toolchain.
- The stream view receives `reduceMotion` and shake settings through its caller via planned values; system accessibility preference wiring belongs to the later UI/controller task.
- Runtime visual appearance and card-level shake execution require a running macOS app and were not physically observed in this headless harness.

## Fix Round 1: Review Findings

Date: 2026-09-12
Base: `68a0e2d`

### Changes

- `DamageStreamView.play` now captures one converted `CACurrentMediaTime()` value and reuses it for every bead, while retaining each plan's launch delay.
- Replaced wall-clock `DispatchQueue.main.asyncAfter` removal with a retained `CAAnimationDelegate` attached to the position animation. Completion returns to the main actor by layer identity and removes the completed text layer.
- Debit and credit visible text now formats `Money.magnitude`, preserving `-`/`+` event direction without rendering double signs for negative values.
- Added focused XCTest assertions and harness assertions for label normalization, one clock sample per burst, 230 ms delayed cadence, and completion-delegate cleanup installation.

### Commands and outputs

Test-first focused attempt after adding the regression assertions and before the production fix:

```sh
swift test --filter DamageAnimationPlannerTests
```

Result: exit 1 because this Command Line Tools environment has no XCTest module:

```text
error: no such module 'XCTest'
```

Focused XCTest attempt after the fix:

```sh
swift test --filter DamageAnimationPlannerTests
```

Result: exit 1 for the same environment limitation:

```text
error: no such module 'XCTest'
```

Build, warnings-as-errors harness, and diff validation:

```sh
swift build && ./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-7/run-harness.sh && git diff --check
```

Result: exit 0.

```text
Build complete! (0.35s)
task-7 harness passed: cadence, ranges, deterministic randomness, styles, burst shake, Reduce Motion, fixed stream size
```

`git diff --check` produced no output.

### Self-review

- One `play` call samples the clock exactly once; all animation begin times derive from that shared value plus the planner's 0.23-second launch delay.
- Cleanup is tied to Core Animation completion rather than an independently estimated wall-clock deadline, and the delegate is retained per text layer until completion.
- Completion cleanup handles both finished and interrupted animation callbacks and removes only the layer identified by that delegate.
- Negative amounts are normalized only for visible text; the underlying `BalanceAnimationEvent` and debit/credit style remain unchanged.
- The diff contains no Task 5 source or behavior changes.

### Concerns

- XCTest remains unexecutable with `/Library/Developer/CommandLineTools` because `XCTest` is unavailable; the complete test source is retained for an Xcode toolchain.
- The headless harness verifies delegate installation and shared timing, but does not visually observe animation completion in a running window.
