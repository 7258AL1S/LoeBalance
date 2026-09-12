# Task 6 scheduler harness

This harness is intentionally persistent and uses the real `RefreshScheduler`
source with actor fakes. It is kept as a source-level verification record
because the current command-line toolchain cannot import XCTest.

Covered scenarios:

- immediate start refresh and configured interval
- interval update and 10...3600 clamping
- single-flight manual refresh sharing
- offline pause and immediate network recovery
- Retry-After deadline handling
- 10/20/40/80/160/300 bounded backoff
- stop cancellation
- system wake refresh
- injected sleeper and refresh closure, with no real sleep or network

The production build command is the executable validation for the real source:

```sh
swift build
```

The XCTest source for the same scenarios is in
`Tests/LoeBalanceTests/RefreshSchedulerTests.swift`.
