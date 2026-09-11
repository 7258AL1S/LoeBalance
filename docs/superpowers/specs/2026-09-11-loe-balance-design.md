# LoeBalance macOS Desktop Balance Monitor Design

**Date:** 2026-09-11  
**Status:** Approved in conversation; pending written-spec review  
**Target:** macOS 15.7.9 on Intel (`x86_64`)  
**Toolchain:** Swift 6.1.2 command-line tools, without a full Xcode installation

## 1. Summary

LoeBalance is a lightweight native macOS application that monitors the balance
of the authenticated account at `https://api.loe.cx`. It presents the current
balance in two places:

- a draggable, widget-like card that sits on the desktop layer and is covered
  by ordinary application windows;
- a menu bar item that continuously shows the current balance and exposes the
  app's commands.

The application polls the service at a configurable interval, updates the true
balance immediately, and then presents debit or credit changes as short visual
feedback. Debit feedback resembles game damage numbers beside a health bar.

## 2. Goals

- Display the current balance on the macOS desktop and in the menu bar.
- Keep the desktop card below normal application windows.
- Support a configurable refresh interval from 10 to 3,600 seconds.
- Authenticate through the site's existing account login flow.
- Store no password and keep the refresh token in macOS Keychain.
- Show today's spend and request count on the desktop card.
- Detect newly returned usage records and animate individual debit amounts.
- Detect balance increases and animate a credit amount.
- Preserve the approved high-frequency, single-origin, bead-like debit effect.
- Build and run using the currently installed Swift command-line toolchain.

## 3. Non-Goals

- A WidgetKit extension or an entry in the macOS widget gallery.
- App Store distribution, Developer ID notarization, or automatic updates.
- API key creation, subscription management, payment, or redemption workflows.
- Reproducing the full Sub2API dashboard.
- Persisting a complete usage-history database.

## 4. Constraints and Assumptions

- The API used by the website is not documented as a public integration API.
  The contract is derived from the site's current frontend and may change.
- The current public configuration has CAPTCHA and TOTP login disabled.
- The initial build is for this Intel Mac and uses local ad-hoc signing.
- Polling, not server push, is the source of balance and usage updates.
- The server's balance is authoritative. Animation never calculates or delays
  the displayed balance.

## 5. User Experience

### 5.1 Desktop Card

The approved card uses the balanced layout:

- title: `Sub2API 余额`;
- prominent current balance;
- today's spend;
- today's request count;
- connection indicator and last-update time.

The card has a dark translucent material, restrained border and shadow, rounded
corners, and automatic light/dark appearance adaptation. It can be dragged on
the desktop, and its position is restored on launch. It joins all Spaces and is
not included in the normal window cycle.

The panel is placed above the desktop background and Finder desktop icons as
needed for visibility, but below normal application windows. It does not steal
keyboard focus during ordinary use.

### 5.2 Menu Bar

The status item shows an availability dot and the current balance, for example
`● $19.38`. Clicking it opens a compact menu containing:

- current balance and connection state;
- last successful update time;
- Refresh Now;
- Show or Hide Desktop Card;
- Settings;
- Log Out;
- Quit LoeBalance.

The menu bar balance never shakes, scales, or moves during debit or credit
feedback.

### 5.3 Settings

Settings contain:

- refresh interval presets: 10 seconds, 30 seconds, 1 minute, and 5 minutes;
- a custom interval from 10 to 3,600 seconds;
- desktop card shake: Off, Weak, or Strong;
- launch at login, default Off;
- show or hide the desktop card;
- sign out.

Non-sensitive settings use `UserDefaults`.

## 6. Visual Feedback

### 6.1 Debit Feedback

Debit amounts appear in red beside the balance, not in a separate visible
track. The desktop and menu bar play the same detected debit sequence.

- Amount format: `-$0.30`.
- New amounts begin about every 230 milliseconds during a burst.
- Multiple amounts may be visible at once.
- All amounts originate beside the balance and rise along the same conceptual
  path, producing the approved bead-like stream.
- Constant duration and minimum launch spacing prevent vertical overlap.
- Desktop random motion reaches approximately 13 pixels horizontally and 8
  degrees of rotation.
- Menu bar randomness is restrained to approximately 7 pixels and 4 degrees.
- The menu bar debit origin is visually close to the balance while retaining a
  small collision-safe gap.

Card shake is independent of the damage-number animation. The setting has Off,
Weak, and Strong levels. For a high-frequency burst, the card shakes once at
the beginning rather than once per usage record.

When Reduce Motion is enabled in macOS accessibility settings, shake is
disabled and debit feedback becomes a shorter fade-and-rise transition.

### 6.2 Credit Feedback

A balance increase produces one green amount such as `+$5.00` beside the
balance. The desktop card performs a short, subtle green pulse and rebound. The
menu bar balance stays fixed while the green amount rises and fades.

### 6.3 Burst Limits

- Up to 20 new usage records are animated individually in chronological order.
- If a refresh returns more than 20 new records, the first 19 are animated and
  the remainder are combined into a final debit amount.
- The displayed server balance changes immediately, before the animation burst
  completes.
- Starting a second manual refresh never creates duplicate requests or replayed
  usage records.

## 7. Architecture

### 7.1 Process Model

LoeBalance is one native menu bar application with an accessory activation
policy. It owns both the status item and a non-activating desktop `NSPanel`.
There is no helper process in the first version.

### 7.2 Components

`AppCoordinator`
: Starts the app, constructs services and controllers, restores state, and
  coordinates login, logout, sleep, wake, and termination.

`APIClient`
: Sends typed HTTPS requests, applies common headers, decodes the response
  envelope, enforces the timeout, and maps server failures to app errors.

`AuthManager`
: Logs in, owns the in-memory access token, refreshes it once after an
  authentication failure, and clears credentials during logout.

`KeychainStore`
: Stores only the refresh token and associated account identifier.

`BalanceService`
: Fetches account and usage data, deduplicates refreshes, produces a new
  `BalanceSnapshot`, and detects debit and credit events.

`RefreshScheduler`
: Runs the cancellable polling loop, responds to interval changes, and performs
  an immediate refresh after system wake or network recovery.

`SnapshotStore`
: Persists the last valid snapshot, the usage watermark, and a bounded set of
  recently observed usage IDs.

`AnimationCoordinator`
: Converts detected events into synchronized desktop and menu bar feedback,
  applies the burst limit, and respects Reduce Motion.

`DesktopCardController`
: Owns the desktop panel, drag behavior, window level, appearance, position
  persistence, and card rendering.

`StatusBarController`
: Owns the status item, menu commands, status presentation, and menu bar
  feedback layer.

`SettingsController`
: Owns the login and settings windows and validates user-editable preferences.

## 8. API Contract

The base URL is `https://api.loe.cx/api/v1`.

Common request behavior:

- 30-second request timeout;
- `Content-Type: application/json`;
- `Accept-Language: zh`;
- `X-User-UI-Request: 1` for authenticated user endpoints;
- `Authorization: Bearer <access token>` when authenticated;
- local time zone supplied for GET requests where supported.

The client accepts the site's envelope shape and treats `code == 0` as
success. Only required fields are decoded, so unrelated added fields do not
break the app.

### 8.1 Login

`POST /auth/login`

Request fields:

- `email`;
- `password`.

Successful response fields used by the app:

- `access_token`;
- `refresh_token`;
- `expires_in`;
- `user.id` and display identity fields when available.

The app clears its owned password field and request buffer immediately after
the request completes and never persists the password. If the server later
enables CAPTCHA or returns a two-factor challenge, version one stops the native
login flow and directs the user to the web dashboard instead of attempting to
bypass the challenge.

### 8.2 Refresh Token

`POST /auth/refresh`

Request field: `refresh_token`.

New access and refresh tokens replace the previous credentials atomically.

### 8.3 Account Balance

`GET /auth/me`

Required field: `balance`.

### 8.4 Dashboard Summary

`GET /usage/dashboard/stats`

Required fields include today's actual spend and today's request count. Missing
optional statistics render as unavailable without invalidating the balance.

### 8.5 Usage Records

`GET /usage?page=1&page_size=100`

Required fields per record:

- stable record ID;
- creation time;
- actual debit cost.

The decoder also accepts model and token fields for future diagnostics, but the
first version does not display them.

## 9. Authentication and Security

1. The user enters email and password in the native login window.
2. The password is submitted over HTTPS only to `api.loe.cx`.
3. The password is not stored in defaults, Keychain, logs, or crash metadata.
4. The access token remains in process memory.
5. The refresh token is stored as a generic password in macOS Keychain.
6. A `401` triggers one refresh-token exchange and one replay of the failed
   request.
7. A failed refresh clears the access token and returns the app to Login
   Required state.
8. Log Out deletes the Keychain item, snapshot, watermark, and deduplication
   state.

Logs exclude credentials, authorization headers, passwords, and complete
response bodies.

## 10. Refresh and Reconciliation

The default refresh interval is 30 seconds. The scheduler clamps all stored or
entered values to the 10-to-3,600-second range.

Each refresh performs the balance, dashboard-statistics, and latest-usage
requests concurrently. A single-flight guard makes concurrent timer and manual
refresh requests share the same in-progress operation.

On the first successful refresh after login, the app establishes the current
balance and usage watermark without replaying historical debits.

For subsequent refreshes:

1. Decode and publish the latest server balance immediately.
2. Sort unseen usage records from oldest to newest.
3. Sum all unseen usage costs, including records later combined by the burst
   limit, and animate those debits using the burst rules.
4. Calculate the net balance change and subtract the animated debit total from
   the reconciliation equation.
5. If the remaining reconciliation value is positive, emit one credit event.
   This correctly detects a recharge that occurred in the same interval as new
   usage.
6. If the remaining reconciliation value is negative, emit one unattributed
   aggregate debit event. This covers delayed usage records, manual balance
   adjustments, and small API timing differences.
7. Ignore reconciliation residuals below a small currency tolerance to avoid
   floating-point noise.
8. Persist the new snapshot and watermark only after successful decoding.

Usage records drive animation details, while `/auth/me` remains the source of
truth for the displayed balance. Small timing or rounding mismatches never
modify the authoritative value.

## 11. Error Handling

`Offline`
: Keep the last successful values, turn the status indicator gray, and show the
  last update time. Retry when the network returns.

`Unauthorized`
: Refresh once. If refresh fails, show Login Required and stop scheduled API
  traffic until the user signs in again.

`Rate Limited`
: Honor `Retry-After` when present. Otherwise use bounded exponential backoff.
  Show a yellow status indicator without discarding cached data.

`Server Failure`
: Retain cached data and retry at the next eligible interval.

`Invalid Response`
: Reject the new snapshot, retain the previous balance, and show Data Format
  Error. Never replace a known balance with zero because decoding failed.

`Partial Summary Failure`
: If balance succeeds but usage statistics fail, update the balance and mark
  only the failed secondary fields unavailable.

## 12. Persistence

Keychain stores:

- refresh token;
- account identifier needed to scope the credential.

`UserDefaults` stores:

- refresh interval;
- shake level;
- desktop-card visibility;
- desktop-card position;
- launch-at-login preference;
- last successful non-sensitive snapshot;
- usage watermark and bounded recent-ID set.

The app keeps at most 500 recent usage IDs for deduplication.

## 13. Launch at Login

Launch at login is Off by default. When enabled, the app registers its main app
through the supported macOS service-management API. Failure leaves the setting
Off and presents a concrete error; the app does not silently install an
untracked background script.

## 14. Build and Packaging

The repository is a Swift Package that produces a macOS executable. A project
script at `script/build_and_run.sh` will:

1. stop an existing LoeBalance process;
2. run `swift build`;
3. stage `dist/LoeBalance.app` with a stable bundle identifier and Info.plist;
4. apply local ad-hoc signing;
5. launch the fresh bundle;
6. optionally verify that the process is running.

`.codex/environments/environment.toml` will expose the same script as the Codex
Run action. The user-facing deliverable will be an app archive under `outputs/`.

## 15. Testing Strategy

### 15.1 Unit Tests

- response-envelope and model decoding;
- refresh-token replacement and one-retry behavior;
- refresh-interval validation and clamping;
- usage-record sorting and deduplication;
- first-login baseline behavior;
- debit, credit, and aggregate reconciliation;
- 20-item burst limit and remainder aggregation;
- settings persistence;
- animation event timing and shake rate limiting.

### 15.2 Service Tests

Use an injected URL-loading layer with deterministic mock responses for:

- successful login and refresh;
- expired access token followed by successful refresh;
- failed refresh;
- offline errors;
- `429` backoff;
- malformed envelopes;
- partial dashboard-statistics failure.

### 15.3 Manual Validation

- login without persisting the password;
- relaunch using the Keychain refresh token;
- desktop card below normal app windows;
- card drag and position restoration;
- behavior across Spaces and Finder restart;
- menu bar commands and stable balance text;
- Off, Weak, and Strong shake settings;
- high-frequency single-origin debit stream without overlap;
- increased random motion within the approved range;
- green credit feedback;
- Reduce Motion behavior;
- light and dark appearance;
- sleep, wake, offline, recovery, and logout;
- build, bundle launch, and running-process verification.

## 16. Acceptance Criteria

- The user can sign in and see the server balance on both surfaces.
- No password is stored after login.
- The refresh token survives relaunch only in Keychain.
- The desktop card remains on the desktop layer and ordinary windows cover it.
- The menu bar balance remains stable during all animations.
- Refresh frequency is user-configurable within the agreed bounds.
- New debit records animate beside the balance at high frequency without text
  overlap.
- Debit randomness is visibly varied but remains within collision-safe limits.
- Credit changes use green feedback and do not trigger damage shake.
- Failed or malformed requests never replace a valid balance with an invented
  value.
- The app builds and launches through the project build script on this Mac.

## 17. Primary Risks

- The frontend-derived API contract may change without notice.
- Finder and macOS window-level behavior can differ across Spaces or OS updates
  and requires runtime validation.
- Very short refresh intervals increase service traffic and may trigger rate
  limiting.
- Local ad-hoc signing is appropriate for this machine but is not a substitute
  for notarized distribution.

These risks are handled through isolated API decoding, cached-state protection,
bounded backoff, focused window-level testing, and explicit packaging limits.
