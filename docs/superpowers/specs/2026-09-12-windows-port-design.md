# LoeBalance Windows Port Design

## Goal

Create a Windows implementation path for LoeBalance without changing the existing macOS application. The first phase runs on macOS and delivers reusable .NET core logic, Windows platform contracts, automated Windows CI, and a handoff document for completion on a Windows machine.

## Scope

In scope:

- C#/.NET 8 core library for models, money, API contracts, authentication state, balance reconciliation, refresh scheduling, and damage animation planning.
- Platform interfaces for secure credentials, local settings, network availability, power resume, startup registration, and tray/desktop presentation.
- xUnit tests for pure core behavior.
- A Windows-targeted WPF shell skeleton that documents the integration boundaries without being required to run on macOS.
- GitHub Actions workflow that builds and tests the core library on Windows for `win-x64` and `win-x86`.
- A complete handoff document describing completed work, Windows-only work, known risks, commands, and acceptance checks.

Out of scope for this phase:

- Any modification to the macOS source or macOS release scripts.
- Runtime validation of WPF, Windows Credential Manager, Windows tray behavior, desktop window layering, DPI, startup, or power events.
- A Windows installer or code signing certificate.

## Architecture

The Windows port uses C#/.NET 8. `LoeBalance.Core` contains no Windows-only APIs and owns the behavior that must match the Swift implementation. `LoeBalance.Platform.Windows` defines platform service contracts and later hosts Windows implementations. `LoeBalance.Desktop.Wpf` is the future presentation shell for the tray icon, login/settings windows, and desktop card.

The Windows shell intentionally differs from macOS in one place: the Windows notification area is represented by a tray icon with tooltip and context menu, while the detailed balance and animations are displayed in the desktop card.

## Behavioral Contract

- API base URL: `https://api.loe.cx/api/v1`.
- Authenticated requests use Bearer access tokens, `Accept-Language: zh`, and `X-User-UI-Request: 1`.
- Login and refresh token exchange are serialized; one in-flight refresh is shared by concurrent callers.
- Refresh interval is clamped to 1 through 3600 seconds.
- Manual refresh, network recovery, power resume, retry-after, offline pause, exponential backoff, and in-flight request coalescing remain supported.
- Balance reconciliation orders usage by `(createdAt, id)`, shows individual debit events up to 19 records, and aggregates larger bursts into a final debit event.
- First baseline refresh produces no animation events.
- Debit events are red and credit events are green. Animation planning preserves a single track, high-frequency bead-like launch delays, random horizontal offsets, and desktop-only shake strength.

## Validation Boundary

Mac validation covers compilation of platform-neutral projects, unit tests where the local .NET SDK is available, source-level checks, and GitHub Actions configuration. Windows validation must additionally cover WPF compilation, tray behavior, secure storage, desktop layering, multi-monitor DPI, startup, power resume, network changes, and both runtime identifiers.
