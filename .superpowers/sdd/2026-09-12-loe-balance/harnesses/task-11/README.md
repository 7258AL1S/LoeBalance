# Task 11 Harness

Run from the worktree root:

```sh
./.superpowers/sdd/2026-09-12-loe-balance/harnesses/task-11/run-harness.sh
```

The runner performs a bounded focused static check over the real Task 11 production sources and tests. It validates the composition-root APIs, lifecycle hooks, presentation-before-animation ordering, logging categories, and required coordinator test names without triggering the full AppKit/Network source compilation that is blocked by the current Command Line Tools sandbox.

Coverage includes missing/restored authentication, success presentation ordering, failed refresh snapshot preservation, preference propagation, logout cleanup, wake, and network recovery.
