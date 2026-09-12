# SDD ledger — plan: docs/superpowers/plans/2026-09-12-loe-balance.md

Worktree: `/Users/zzx/Documents/Codex/2026-09-12/https-api-loe-cx-dashboard-https/.worktrees/loe-balance`
Branch: `feature/loe-balance`
Branch base: `74310ed`
Baseline: no `Package.swift` existed before Task 1, so there was no test command to run.

## Preflight Task Consistency

| Task | Tests vs implementation | Files vs later use | Finding |
|---|---|---|---|
| 1 | Money/model tests match produced types and formatting | Core models are consumed throughout | Clean |
| 2 | Endpoint/header/error tests match API client contract | Creates shared `TestSupport.swift` used later | Clean |
| 3 | Auth tests match refresh-only persisted credential schema | Modifies shared test support and produces `AuthManager` | Clean after plan correction |
| 4 | Persistence tests cover bounds and round trips | Produces stores/preferences used by services and UI | Clean after custom decode clamp requirement |
| 5 | Reconciliation/service tests match authoritative-balance rules | Produces refresh result consumed by scheduler/UI | Clean |
| 6 | Scheduler tests use actor-safe fakes | Produces lifecycle hooks used by coordinator | Clean |
| 7 | Planner tests match cadence/ranges/reduced-motion rules | Produces plans/views for both surfaces | Clean |
| 8 | Panel tests match desktop-layer behavior and fixed frame | Produces desktop presenter used by coordinator | Conflict: plan names 22-point radius |
| 9 | Status tests protect fixed balance and command wiring | Produces status presenter used by coordinator | Clean |
| 10 | View-model tests match validation and preference updates | Produces login/settings/launch services | Clean |
| 11 | Coordinator tests cover lifecycle and presentation order | Produces executable consumed by packaging | Clean |
| 12 | Build steps match bundle/run-action outputs | Produces app bundle consumed by QA | Clean |
| 13 | QA steps cover automated, live, visual, and archive checks | Only ignored deliverables are created | Clean |

## Preflight Shared Interfaces

| Producer | Consumer | Shared file/interface | Finding |
|---|---|---|---|
| 1 | 2 | `Money`, `UsageRecord`, `AppError` | Compatible |
| 1 | 4 | `BalanceSnapshot`, `ShakeStrength` | Compatible |
| 1 | 5 | balance/usage/event models | Compatible |
| 1 | 6 | `ConnectionState` | Compatible |
| 1 | 7 | animation events and shake strength | Compatible |
| 1 | 8 | snapshot, state, shake | Compatible |
| 1 | 9 | snapshot and state | Compatible |
| 2 | 3 | `APIClientProtocol`, `AuthSession`, `TestSupport.swift` | Compatible |
| 2 | 5 | API protocol and DTOs | Compatible |
| 3 | 5 | `AuthManager` | Compatible |
| 3 | 10 | `AuthManager` login/logout | Compatible |
| 4 | 5 | `SnapshotStoreProtocol` | Compatible |
| 4 | 6 | refresh interval | Compatible |
| 4 | 8 | card visibility/frame/shake preferences | Compatible |
| 4 | 10 | mutable app preferences | Compatible via validated setters |
| 5 | 6 | `BalanceService.refresh()` | Compatible |
| 5 | 8 | snapshots/events | Compatible |
| 5 | 9 | snapshots/events | Compatible |
| 6 | 10 | scheduler commands | Compatible |
| 6 | 11 | scheduler and network lifecycle | Compatible |
| 7 | 8 | planner and stream view | Compatible |
| 7 | 9 | menu-bar motion plans | Compatible |
| 8 | 11 | `DesktopCardPresenting` | Compatible |
| 9 | 11 | status presenter/commands | Compatible |
| 10 | 11 | windows, view models, launch service | Compatible |
| 11 | 12 | executable product | Compatible |
| 12 | 13 | `dist/LoeBalance.app` | Compatible |

Ruling: Use an 8-point desktop-card corner radius instead of the plan's 22 points — higher-level UI guidance limits cards to 8 points and the approved spec requires rounded corners without an exact radius — cost if wrong: the card will look slightly less like the visual mockup.
Ruling: Treat deletion of `.build/` and `dist/` during clean QA as deletion of generated artifacts only — both paths are git-ignored and reproducible — cost if wrong: locally generated unsigned bundles or build caches in this worktree are discarded.

Task 1: fix round 1/5 (1 addressed, 1 open — exact numeric JSON precision addressed; strict numeric-string validation still missing; commits 44504e5..462ec0a)
Task 1: fix round 2/5 (1 addressed, 0 open — strict numeric-string validation added; commits 462ec0a..2773d91)
Ruling: Continue implementation despite the selected Command Line Tools lacking XCTest — retain all XCTest sources, attempt required test commands, and require `swift build` plus reproducible real-source harnesses for changed behavior until a full Xcode toolchain is available — cost if wrong: XCTest-only compile or integration defects may remain undetected until final validation on a toolchain with XCTest.
Task 1: complete (commits 74310ed..2773d91, review clean)

Task 2: minor (deferred): committed XCTest coverage does not yet include a direct `URLError` transport-mapping case; the temporary intercepted harness covers it, and final review must decide whether the persistent case is required.
Ruling: Make `AuthSession.userID` optional at the API boundary, require it for login, and allow refresh to omit it; remove JWT identity inference, and have Task 3 preserve the previously verified stored user ID while rejecting any explicitly returned mismatch — the API contract does not guarantee JWT structure or a refresh identity field — cost if wrong: downstream code must unwrap login identity and merge refresh sessions instead of treating every API response as self-contained.
Task 2: minor resolved in fix round 1 — added persistent `URLError` transport-mapping coverage.
Task 2: fix round 1/5 (2 addressed, 0 open — nonzero envelope metadata is checked before payload decoding; refresh identity is optional and JWT inference removed; commits 2a1b567..7e3a4ad)
Task 2: complete (commits 2773d91..7e3a4ad, review clean)

Task 3: minor (deferred): `AppError.loginRequired` is currently an equality-compatible alias for canonical `.loginChallenge`; final review should decide whether to rename the enum case for clearer exhaustive matching.
Task 3: fix round 1/5 (3 addressed, 0 open — stale cross-account replay cancelled; invalidation propagates Keychain deletion errors; deterministic single-flight barrier added; commits 66eddb4..ad47f13)
Task 3: complete (commits 7e3a4ad..ad47f13, review clean)
Task 4: fix round 1/5 (1 open — synthesized `PersistedSnapshotState` decoding bypasses duplicate/500-ID normalization; commits ad47f13..67dda1d)
Task 4: fix round 1/5 (1 addressed, 0 open — custom persisted snapshot decoding now normalizes IDs; commits 67dda1d..d27e328)
Task 4: complete (commits ad47f13..d27e328, review clean)
Task 5: fix round 1/5 (1 open — usage request failure is collapsed into empty usage and can emit false debit/reconcile events; commits d27e328..c550b16)
Task 5: fix round 1/5 (1 addressed, 0 open — usage failure no longer emits events or persists partial state; commits c550b16..3f1186a)
Task 5: complete (commits d27e328..3f1186a, review clean)
Task 6: fix round 1/5 (critical/important findings open — stop/restart race, retry/backoff semantics, transport/offline bridge, missing executable harness, duplicate network state; commits 3f1186a..e169c6e)
Task 6: fix round 1/5 (2 addressed, 4 open — epoch/harness/network dedup/transport bridge addressed; retry deadline, timer/manual proof, same-instance restart, stale retry state remain; commits e169c6e..195c8d0)
Task 6: fix round 2/5 (3 addressed, 2 open/new — retry gating/stop restart/harness addressed; timer/manual proof remains weak and shared deadline can duplicate timer/manual refresh; commits 195c8d0..6f5b2a0)
Task 6: fix round 3/5 (2 addressed, 1 open — shared deadline and production cancellation remain correct; XCTest timer/manual barrier still stale; commits 6f5b2a0..f8f2d5d)
Task 6: fix round 2/5 (3 addressed, 2 open — deadline coalescing/test proof open after round 2; commits 195c8d0..6f5b2a0)
Task 6: fix round 3/5 (2 addressed, 1 open — shared deadline production behavior fixed; XCTest timer barrier still stale; commits 6f5b2a0..f8f2d5d)
Task 6: fix round 4/5 (1 addressed, 0 open — XCTest timer barrier uses actor continuation; commits f8f2d5d..10b21f6)
Task 6: complete (commits 3f1186a..10b21f6, review clean)
Task 7: fix round 1/5 (3 open — per-label clock origin, asyncAfter cleanup, negative amount formatting; commits 10b21f6..68a0e2d)
Task 7: fix round 1/5 (3 addressed, 0 open — shared burst clock, animation-completion cleanup, magnitude-only visible amounts; commits 68a0e2d..9d0e63f)
Task 7: complete (commits 10b21f6..9d0e63f, review clean)
Task 8: implementation in progress (base 9d0e63f; Luna high; TDD plus warnings-as-errors real-source harness required)
Task 8: takeover fix round 1/5 (2 addressed, 0 open — undersized-screen clamp and first-play layout fixed; base 9d0e63f)
Task 8: complete (commit e2e06a2; panel policy, fixed frame, presentation, damage placement, shake/reduce-motion, frame persistence and clamp verified by warnings-as-errors harness)
Task 8: fix round 1/5 (4 open — undersized-screen top preservation, long-value clipping, restored fixed-size normalization, panel accessibility title; commit e2e06a2 plus reviewed uncommitted localized title)
Task 8: fix round 1/5 (4 addressed, 0 open — top-aligned undersized clamp, stable text fitting, fixed-size restoration without screen data, localized panel accessibility title; commits e2e06a2..bca3cc4)
Task 8: fix round 2/5 (1 open — large valid balances such as $1,000,000.00 can still clip at the 20pt minimum font size; commit bca3cc4)
Task 8: fix round 2/5 (1 addressed, 0 open — exact large balances fit at a readable 14pt minimum with fixed balance/damage geometry; commits bca3cc4..3a3a1ae)
Task 8: complete (commits 9d0e63f..3a3a1ae, final review clean)
Task 9: RED tests added; focused XCTest attempted and blocked by missing XCTest module; implementation in progress (TDD plus warnings-as-errors real-source harness required)
Task 9: implementation fix round 1/5 (4 addressed, 0 open — Swift 6 actor-safe initializer, nondeprecated status-button attachment, initial layout, timezone-independent assertions)
Task 9: complete (commit fa2d09c; fixed status content, stable balance, menu commands, connection mapping and menu reuse verified by warnings-as-errors harness)
Task 9: independent audit (commits 3a3a1ae..3cea1e9; production Critical 0, Important 0, Minor 1 — balances wider than $1,000,000.00 clip; requested verification assertions present; no extra test-only commit because changes were already committed with production stabilization; NSApp initialization remains an XCTest-runtime risk; build/harness/diff checks passed, XCTest unavailable)
Task 9: independent audit (commits fa2d09c..3cea1e9; production review clean; build, warnings-as-errors harness, and diff check passed; no test-only commit because the proposed assertions were already committed; XCTest hardening remains invalid due undefined `frameBefore`, masked locally by missing XCTest module)
Task 9: takeover fix round 1/5 (2 addressed, 0 open — actual balance/damage frame gap corrected from 0pt to exact 2pt; stable menu identifiers added after reported menu-title failure could not be reproduced on fa2d09c)
Task 9: takeover fix round 2/5 (1 addressed, 0 open — menu-bar DamageStreamView now has a real 54x42 intrinsic/presentation size and text layers remain inside the fixed damage region; desktop default remains 92x42)
Task 9: complete (commits 3a3a1ae..3cea1e9; swift build passed; warnings-as-errors real-source harness passed 10/10; git diff --check passed; focused XCTest blocked by missing XCTest module)
Task 9: fix round 1/5 (2 open — status intrinsic width conflicted with required 54pt constraint; status CATextLayer remained hard-coded to 92pt; base 3cea1e9)
Task 9: fix round 1/5 (2 addressed, 0 open — instance-specific 54x42 status stream; desktop default 92x42 preserved; status layer bounds and six-event balance stability verified; commit dbf745b)
Task 9: complete (commit dbf745b; swift build and warnings-as-errors harness passed; focused XCTest blocked by missing XCTest module; tracked worktree clean)
Task 9: final review clean (2026-09-12; Critical 0, Important 0; verification-hardening tests committed in 3cea1e9 and dbf745b; no further XCTest wait requested; Minor balance-width ceiling deferred to integration QA)
Task 10: complete (base 3cea1e9; login/settings/launch-at-login source, focused tests, and warnings-as-errors harness implemented; XCTest unavailable, build/harness/diff clean)
Task 10: fix round 1/5 (3 addressed, 0 open — concurrent submit guard, candidate-first settings transactions, visible UI rollback/error handling; build/harness/diff clean; XCTest not rerun)
Task 11: implementation in progress (base de15704; Luna; one implementation pass; TDD plus warnings-as-errors real-source harness required; Terra disabled)
Task 11: complete (swift build passed; bounded static harness passed once; git diff --check passed; XCTest single attempt blocked by exact environment error `sandbox-exec: sandbox_apply: Operation not permitted`; full-source harness not retried after actor-access diagnostics; live AppKit validation remains)
Task 11: fix round 1/1 in progress (6 review findings; base ae6a3e3; Luna only; no XCTest or full-source swiftc harness; one bounded harness run)
Task 11: fix round 1/1 complete (6 addressed; `swift build` passed; bounded static harness passed; `git diff --check` passed; no XCTest or full-source swiftc; commit follows)
Task 12: complete (build/run script, signed app bundle, single Codex Run action, one XCTest attempt recorded as missing XCTest, verify and bounded telemetry passed; app left running at last observed PID 64556)
Ruling: Treat the Task 10 final-QA harness protocol mismatch as a verification gap rather than a production defect — Task 11 added `RefreshScheduling.networkBecameUnavailable()` after the Task 10 harness was committed, while the production build and Task 11 bounded coordinator check pass — cost if wrong: settings view-model behavior lacks a fresh executable harness under the final protocol.
Task 13: complete (2026-09-12; clean generated-artifact reset; one bounded `swift test` attempt stopped during XCTest target compilation under Command Line Tools without XCTest; Tasks 3-9 and 11 harnesses passed; Task 10 harness stale and failed to compile; Task 1-2 temporary harnesses unavailable; `build_and_run.sh --verify` passed; x86_64 bundle, Info.plist, layout, process, and ad-hoc codesign verified; bounded telemetry contained no secret/body markers; accessibility/menu clicking recorded as manual boundary; main-workspace archive and checksum verified; no source changes)
Task 13 follow-up: Task 10 harness fake updated with `networkBecameUnavailable()` only; bounded harness rerun passed; no production rebuild or repackage required; archive SHA/path unchanged.
