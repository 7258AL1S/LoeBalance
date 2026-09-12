# Task 10 settings and login harness

This harness compiles the real Task 10 view-model, SwiftUI, AppKit window, and
launch-service sources with `swiftc -warnings-as-errors`. It uses actor fakes
for the API and scheduler plus in-memory preferences and launch-at-login
services; it does not access the network, Keychain, or live
`SMAppService.mainApp` state.

Coverage:

- email and six-character password validation
- password delivery to `AuthManager` and clearing after success/failure
- refresh presets, seconds/minutes custom conversion, and 10...3600 clamping
- shake/card preference persistence and callbacks
- launch-at-login actual-state success and failure rollback
- logout command dispatch

Run with:

```sh
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-10/run-harness.sh
```
