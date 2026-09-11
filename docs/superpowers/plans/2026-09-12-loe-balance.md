# LoeBalance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu bar application with a desktop-layer balance card, secure Sub2API login, configurable polling, and synchronized debit/credit feedback.

**Architecture:** A single SwiftPM AppKit executable owns an accessory-mode app process, an `NSStatusItem`, and a non-activating desktop `NSPanel`. Actor-isolated networking, authentication, refresh scheduling, and reconciliation publish immutable snapshots to main-actor UI controllers; Keychain stores the refresh token and `UserDefaults` stores non-sensitive preferences and cached state.

**Tech Stack:** Swift 6.1.2, Swift Package Manager, AppKit, SwiftUI for settings/login forms, Foundation `URLSession`, Security Keychain APIs, Network framework, ServiceManagement, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-11-loe-balance-design.md`

## Global Constraints

- Target the current Intel Mac (`x86_64`) running macOS 15.7.9; set the package platform floor to macOS 13.
- Use only Apple frameworks; add no third-party package dependencies.
- Base API URL: `https://api.loe.cx/api/v1`.
- Default refresh interval: 30 seconds; accepted range: 10 through 3,600 seconds.
- Store the refresh token only in macOS Keychain; never persist the password or access token.
- Treat `/auth/me` as authoritative for displayed balance.
- Update displayed balance immediately; animation never delays or calculates the authoritative value.
- Desktop debit animation uses one origin beside the balance, 230 ms launch cadence, 820 ms duration, concurrent bead-like upward motion, desktop randomness up to about 13 px and 8 degrees, and smaller menu bar randomness.
- Menu bar balance text never shakes, scales, or moves.
- Card shake has Off, Weak, and Strong levels and runs once per debit burst.
- Animate at most 20 debit entries per refresh: first 19 individually and one aggregate remainder.
- Respect macOS Reduce Motion by disabling shake and reducing movement.
- Keep the desktop panel below normal application windows and restore its saved position.
- Build and launch through `script/build_and_run.sh`; expose the same command as the Codex Run action.

---

## File Structure

```text
Package.swift
Sources/LoeBalance/
  App/
    main.swift
    AppCoordinator.swift
    AppDelegate.swift
  Core/
    AppError.swift
    Money.swift
    Models.swift
  Networking/
    APIClient.swift
    APIModels.swift
  Auth/
    AuthManager.swift
    CredentialStore.swift
  Persistence/
    PreferencesStore.swift
    SnapshotStore.swift
  Refresh/
    BalanceReconciler.swift
    BalanceService.swift
    RefreshScheduler.swift
  Animation/
    DamageAnimationPlanner.swift
    DamageStreamView.swift
  DesktopCard/
    DesktopCardView.swift
    DesktopCardController.swift
  StatusBar/
    StatusBarContentView.swift
    StatusBarController.swift
  Settings/
    LoginView.swift
    LoginViewModel.swift
    SettingsView.swift
    SettingsViewModel.swift
    SettingsWindowController.swift
  Support/
    LaunchAtLoginService.swift
    NetworkMonitor.swift
    Logger.swift
Tests/LoeBalanceTests/
  TestSupport.swift
  MoneyAndModelsTests.swift
  APIClientTests.swift
  AuthManagerTests.swift
  PersistenceTests.swift
  BalanceReconcilerTests.swift
  BalanceServiceTests.swift
  RefreshSchedulerTests.swift
  DamageAnimationPlannerTests.swift
  DesktopCardControllerTests.swift
  StatusBarControllerTests.swift
  SettingsViewModelTests.swift
  AppCoordinatorTests.swift
script/build_and_run.sh
.codex/environments/environment.toml
```

Each source file has one responsibility. Pure money, reconciliation, scheduling, and animation-planning logic remain independent of AppKit so they can be tested deterministically.

---

### Task 1: SwiftPM Foundation, Money, and Domain Models

**Files:**
- Create: `Package.swift`
- Create: `Sources/LoeBalance/Core/AppError.swift`
- Create: `Sources/LoeBalance/Core/Money.swift`
- Create: `Sources/LoeBalance/Core/Models.swift`
- Create: `Tests/LoeBalanceTests/MoneyAndModelsTests.swift`

**Interfaces:**
- Consumes: None.
- Produces: `Money`, `BalanceSnapshot`, `UsageRecord`, `BalanceAnimationEvent`, `RefreshResult`, `ConnectionState`, `ShakeStrength`, and `AppError`.

- [ ] **Step 1: Create the package manifest and failing money/model tests**

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoeBalance",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LoeBalance", targets: ["LoeBalance"])],
    targets: [
        .executableTarget(name: "LoeBalance"),
        .testTarget(name: "LoeBalanceTests", dependencies: ["LoeBalance"])
    ]
)
```

```swift
import XCTest
@testable import LoeBalance

final class MoneyAndModelsTests: XCTestCase {
    func testMoneyDecodesNumberAndString() throws {
        XCTAssertEqual(try JSONDecoder().decode(Money.self, from: Data("19.38".utf8)), Money(decimal: 19.38))
        XCTAssertEqual(try JSONDecoder().decode(Money.self, from: Data("\"0.30\"".utf8)), Money(decimal: 0.30))
    }

    func testMoneyArithmeticUsesDecimalValues() {
        XCTAssertEqual(Money(decimal: 19.38) - Money(decimal: 0.30), Money(decimal: 19.08))
        XCTAssertEqual(Money(decimal: 19.08).currencyText, "$19.08")
    }

    func testShakeStrengthHasThreeStableCases() {
        XCTAssertEqual(ShakeStrength.allCases, [.off, .weak, .strong])
    }
}
```

- [ ] **Step 2: Run the tests and verify the missing-type failure**

Run: `swift test --filter MoneyAndModelsTests`

Expected: compilation fails because `Money` and `ShakeStrength` do not exist.

- [ ] **Step 3: Implement money arithmetic, formatting, app errors, and immutable models**

```swift
struct Money: Codable, Equatable, Comparable, Sendable {
    let decimal: Decimal

    init(decimal: Decimal) { self.decimal = decimal }
    static let zero = Money(decimal: 0)
    static func cents(_ value: Int) -> Self { Self(decimal: Decimal(value) / 100) }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.decimal < rhs.decimal }
    static func + (lhs: Self, rhs: Self) -> Self { Self(decimal: lhs.decimal + rhs.decimal) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(decimal: lhs.decimal - rhs.decimal) }
    var magnitude: Self { Self(decimal: decimal < 0 ? -decimal : decimal) }
    var currencyText: String { Self.currencyFormatter.string(from: decimal as NSDecimalNumber) ?? "$0.00" }
}
```

Implement custom single-value decoding that accepts `Decimal`, `Double`, or numeric `String`. Configure the formatter with `en_US_POSIX`, currency code `USD`, and two fraction digits.

```swift
enum BalanceAnimationEvent: Equatable, Sendable {
    case debit(Money)
    case credit(Money)
}

struct BalanceSnapshot: Codable, Equatable, Sendable {
    let balance: Money
    let todaySpend: Money?
    let todayRequests: Int?
    let updatedAt: Date
}

struct UsageRecord: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let createdAt: Date
    let actualCost: Money
}

struct RefreshResult: Equatable, Sendable {
    let snapshot: BalanceSnapshot
    let events: [BalanceAnimationEvent]
    let connectionState: ConnectionState
}

enum ConnectionState: Equatable, Sendable { case online, offline, rateLimited(until: Date?), loginRequired, invalidData }
enum ShakeStrength: String, Codable, CaseIterable, Sendable { case off, weak, strong }
```

Define `AppError` cases for invalid URL, transport, server status, API envelope, unauthorized, rate limited, invalid response, Keychain status, and login challenge.

- [ ] **Step 4: Run the focused and full test suites**

Run: `swift test --filter MoneyAndModelsTests && swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit the foundation**

```bash
git add Package.swift Sources/LoeBalance/Core Tests/LoeBalanceTests/MoneyAndModelsTests.swift
git commit -m "feat: add LoeBalance core models"
```

---

### Task 2: Typed Sub2API Client

**Files:**
- Create: `Sources/LoeBalance/Networking/APIModels.swift`
- Create: `Sources/LoeBalance/Networking/APIClient.swift`
- Create: `Tests/LoeBalanceTests/TestSupport.swift`
- Create: `Tests/LoeBalanceTests/APIClientTests.swift`

**Interfaces:**
- Consumes: `Money`, `UsageRecord`, and `AppError` from Task 1.
- Produces: `APIClientProtocol`, `APIClient`, `AuthSession`, `CurrentUserDTO`, `DashboardStatsDTO`, and `UsagePageDTO`.

- [ ] **Step 1: Add a deterministic URL protocol stub and failing endpoint tests**

```swift
final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler = { _ in
        throw URLError(.badServerResponse)
    }

    static func install(_ newHandler: @escaping Handler) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    private static func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        let currentHandler = handler
        lock.unlock()
        return try currentHandler(request)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
```

Use `URLProtocolStub.install` in each test and reset it in `tearDown`. Test that login sends `POST /api/v1/auth/login` with only `email` and `password`; authenticated GET requests include `Authorization`, `Accept-Language: zh`, and `X-User-UI-Request: 1`; `fetchUsage` sends `page=1&page_size=100`; envelope `code != 0`, HTTP `401`, HTTP `429`, and malformed JSON map to the expected `AppError`.

- [ ] **Step 2: Run API tests and verify they fail because the client is absent**

Run: `swift test --filter APIClientTests`

Expected: compilation fails for missing `APIClient` and DTO types.

- [ ] **Step 3: Implement DTOs, envelope decoding, and endpoint methods**

```swift
struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: Int64
}

protocol APIClientProtocol: Sendable {
    func login(email: String, password: String) async throws -> AuthSession
    func refresh(refreshToken: String) async throws -> AuthSession
    func fetchCurrentUser(accessToken: String) async throws -> CurrentUserDTO
    func fetchDashboardStats(accessToken: String) async throws -> DashboardStatsDTO
    func fetchUsage(accessToken: String, pageSize: Int) async throws -> [UsageRecord]
}
```

`APIClient` must use `https://api.loe.cx/api/v1`, a 30-second timeout, ephemeral URL session configuration, snake-case decoding, and a flexible date decoder that accepts ISO-8601 timestamps with or without fractional seconds.

Implement these exact paths:

```text
POST /auth/login
POST /auth/refresh
GET  /auth/me
GET  /usage/dashboard/stats
GET  /usage?page=1&page_size=<pageSize>
```

Decode the site's `{ "code": 0, "data": ..., "message": ... }` envelope. Accept usage pages whose items live under `data.items`; ignore unrelated fields.

Add stable shared fixtures in `TestSupport.swift` after the DTOs exist:

```swift
extension Date {
    static let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000)
}

extension AuthSession {
    static let fixture = Self(
        accessToken: "access-token",
        refreshToken: "refresh-token",
        expiresAt: .fixtureNow.addingTimeInterval(3_600),
        userID: 42
    )
}
```

- [ ] **Step 4: Run API tests and the complete suite**

Run: `swift test --filter APIClientTests && swift test`

Expected: all endpoint, header, envelope, date, and error-mapping tests pass.

- [ ] **Step 5: Commit the API layer**

```bash
git add Sources/LoeBalance/Networking Tests/LoeBalanceTests/TestSupport.swift Tests/LoeBalanceTests/APIClientTests.swift
git commit -m "feat: add typed Sub2API client"
```

---

### Task 3: Keychain Credentials and Authentication Actor

**Files:**
- Create: `Sources/LoeBalance/Auth/CredentialStore.swift`
- Create: `Sources/LoeBalance/Auth/AuthManager.swift`
- Modify: `Tests/LoeBalanceTests/TestSupport.swift`
- Create: `Tests/LoeBalanceTests/AuthManagerTests.swift`

**Interfaces:**
- Consumes: `APIClientProtocol`, `AuthSession`, and `AppError`.
- Produces: `CredentialStoreProtocol`, `KeychainCredentialStore`, and actor `AuthManager` with `login`, `restoreSession`, `withAccessToken`, and `logout`.

- [ ] **Step 1: Write failing authentication tests using fake API and credential stores**

```swift
func testLoginStoresRefreshTokenButNotPasswordOrAccessToken() async throws {
    let credentials = InMemoryCredentialStore()
    let api = FakeAPIClient(session: .fixture)
    let manager = AuthManager(api: api, credentials: credentials, now: { .fixtureNow })

    try await manager.login(email: "user@example.com", password: "secret123")

    XCTAssertEqual(credentials.saved, StoredCredential(refreshToken: "refresh-token", userID: 42))
    let receivedLogin = await api.receivedLogin
    XCTAssertEqual(receivedLogin?.email, "user@example.com")
    XCTAssertEqual(receivedLogin?.password, "secret123")
}
```

Add `Date.fixtureNow`, `AuthSession.fixture`, actor `FakeAPIClient`, and locked `InMemoryCredentialStore` helpers to `TestSupport.swift`; the stored fake exposes only `StoredCredential`, making password/access-token persistence impossible by construction. Add tests for restored refresh token, proactive refresh near expiry, one refresh after `AppError.unauthorized`, failed refresh producing `loginRequired`, and logout deleting credentials.

- [ ] **Step 2: Run authentication tests and verify the missing-type failure**

Run: `swift test --filter AuthManagerTests`

Expected: compilation fails because the stores and actor do not exist.

- [ ] **Step 3: Implement Keychain storage and actor-isolated token lifecycle**

```swift
struct StoredCredential: Codable, Equatable, Sendable {
    let refreshToken: String
    let userID: Int64
}

protocol CredentialStoreProtocol: Sendable {
    func load() throws -> StoredCredential?
    func save(_ credential: StoredCredential) throws
    func delete() throws
}

actor AuthManager {
    func login(email: String, password: String) async throws
    func restoreSession() async throws -> Bool
    func withAccessToken<T: Sendable>(
        _ operation: @Sendable (String) async throws -> T
    ) async throws -> T
    func logout() throws
}
```

Use Keychain service `cx.loe.LoeBalance` and account `sub2api-refresh-token`. Keep the active `AuthSession` only inside the actor. Serialize refresh operations by reusing one in-flight refresh `Task<AuthSession, Error>`. Replay an unauthorized operation exactly once.

- [ ] **Step 4: Run focused and complete tests**

Run: `swift test --filter AuthManagerTests && swift test`

Expected: all tests pass and no test fixture writes to the real Keychain.

- [ ] **Step 5: Commit authentication**

```bash
git add Sources/LoeBalance/Auth Tests/LoeBalanceTests/AuthManagerTests.swift
git commit -m "feat: secure Sub2API authentication"
```

---

### Task 4: Preferences and Snapshot Persistence

**Files:**
- Create: `Sources/LoeBalance/Persistence/PreferencesStore.swift`
- Create: `Sources/LoeBalance/Persistence/SnapshotStore.swift`
- Create: `Tests/LoeBalanceTests/PersistenceTests.swift`

**Interfaces:**
- Consumes: `BalanceSnapshot` and `ShakeStrength`.
- Produces: `AppPreferences`, `PreferencesStoreProtocol`, `UserDefaultsPreferencesStore`, `PersistedSnapshotState`, and `SnapshotStoreProtocol`.

- [ ] **Step 1: Write failing persistence and interval-clamping tests**

```swift
func testRefreshIntervalIsClampedToSupportedRange() {
    XCTAssertEqual(AppPreferences(refreshInterval: 1).refreshInterval, 10)
    XCTAssertEqual(AppPreferences(refreshInterval: 30).refreshInterval, 30)
    XCTAssertEqual(AppPreferences(refreshInterval: 9999).refreshInterval, 3600)
}

func testRecentUsageIDsRemainBounded() throws {
    var state = PersistedSnapshotState.empty
    state.recordUsageIDs((1...700).map(Int64.init))
    XCTAssertEqual(state.recentUsageIDs.count, 500)
    XCTAssertTrue(state.recentUsageIDs.contains(700))
}
```

Add round-trip tests for card visibility, shake strength, launch at login, saved panel frame, cached snapshot, watermark time, and recent usage IDs.

- [ ] **Step 2: Run persistence tests and verify they fail**

Run: `swift test --filter PersistenceTests`

Expected: compilation fails because persistence types are missing.

- [ ] **Step 3: Implement validated preferences and Codable snapshot state**

```swift
struct AppPreferences: Codable, Equatable, Sendable {
    private(set) var refreshInterval: TimeInterval
    var shakeStrength: ShakeStrength
    var showsDesktopCard: Bool
    var launchAtLogin: Bool
    var desktopFrame: CGRect?

    init(refreshInterval: TimeInterval = 30, shakeStrength: ShakeStrength = .weak,
         showsDesktopCard: Bool = true, launchAtLogin: Bool = false, desktopFrame: CGRect? = nil) {
        self.refreshInterval = min(3600, max(10, refreshInterval))
        self.shakeStrength = shakeStrength
        self.showsDesktopCard = showsDesktopCard
        self.launchAtLogin = launchAtLogin
        self.desktopFrame = desktopFrame
    }

    mutating func setRefreshInterval(_ value: TimeInterval) {
        refreshInterval = min(3600, max(10, value))
    }
}
```

Implement a custom `init(from:)` that decodes fields and delegates to the validated initializer, so invalid legacy values are clamped too. Add a decoding test with stored values `1` and `9999`. Use injected `UserDefaults` suites in tests. Save preferences and snapshot state as separate JSON blobs. `recordUsageIDs` must preserve insertion order, deduplicate IDs, and retain the newest 500.

- [ ] **Step 4: Run focused and complete tests**

Run: `swift test --filter PersistenceTests && swift test`

Expected: all persistence and clamping tests pass.

- [ ] **Step 5: Commit persistence**

```bash
git add Sources/LoeBalance/Persistence Tests/LoeBalanceTests/PersistenceTests.swift
git commit -m "feat: persist LoeBalance preferences and snapshots"
```

---

### Task 5: Balance Reconciliation and Refresh Service

**Files:**
- Create: `Sources/LoeBalance/Refresh/BalanceReconciler.swift`
- Create: `Sources/LoeBalance/Refresh/BalanceService.swift`
- Create: `Tests/LoeBalanceTests/BalanceReconcilerTests.swift`
- Create: `Tests/LoeBalanceTests/BalanceServiceTests.swift`

**Interfaces:**
- Consumes: `APIClientProtocol`, `AuthManager`, `SnapshotStoreProtocol`, domain models.
- Produces: `BalanceReconciler.reconcile(previous:current:unseenUsage:)` and actor `BalanceService.refresh()`.

- [ ] **Step 1: Write failing pure reconciliation tests**

Cover these exact cases:

```swift
func testConcurrentDebitAndRechargeReconcileToNetBalanceChange() {
    let result = BalanceReconciler().reconcile(
        previousBalance: Money(decimal: 10),
        currentBalance: Money(decimal: 14.50),
        unseenUsage: [.fixture(id: 1, cost: 0.50)]
    )
    XCTAssertEqual(result, [.debit(Money(decimal: 0.50)), .credit(Money(decimal: 5.00))])
}

func testMoreThanTwentyDebitsAggregateTheRemainder() {
    let usage = (1...25).map { UsageRecord.fixture(id: Int64($0), cost: 0.10) }
    let result = BalanceReconciler().debitEvents(from: usage)
    XCTAssertEqual(result.count, 20)
    XCTAssertEqual(result.last, .debit(Money(decimal: 0.60)))
}
```

Add this local fixture to `BalanceReconcilerTests.swift` so record ordering is explicit:

```swift
private extension UsageRecord {
    static func fixture(id: Int64, cost: Decimal, secondsAfterBaseline: TimeInterval = 0) -> Self {
        Self(
            id: id,
            createdAt: Date.fixtureNow.addingTimeInterval(secondsAfterBaseline),
            actualCost: Money(decimal: cost)
        )
    }
}
```

Also test baseline produces no events, unseen usage sorts oldest first, positive residual creates credit, negative residual creates aggregate debit, and residuals below `$0.0001` are ignored.

- [ ] **Step 2: Run reconciliation tests and verify they fail**

Run: `swift test --filter BalanceReconcilerTests`

Expected: compilation fails because `BalanceReconciler` is missing.

- [ ] **Step 3: Implement the reconciliation algorithm**

```swift
struct BalanceReconciler: Sendable {
    let tolerance = Money(decimal: 0.0001)

    func reconcile(
        previousBalance: Money,
        currentBalance: Money,
        unseenUsage: [UsageRecord]
    ) -> [BalanceAnimationEvent] {
        let sorted = unseenUsage.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let debitTotal = sorted.reduce(.zero) { $0 + $1.actualCost }
        var events = debitEvents(from: sorted)
        let residual = (currentBalance - previousBalance) + debitTotal
        if residual > tolerance { events.append(.credit(residual)) }
        if residual < Money(decimal: -tolerance.decimal) { events.append(.debit(residual.magnitude)) }
        return events
    }
}
```

`debitEvents` returns all entries when count is at most 20. For larger arrays it returns the first 19 amounts and one debit containing the sum of every remaining amount.

- [ ] **Step 4: Write failing service tests and implement `BalanceService`**

Tests must prove that the first refresh establishes a baseline, later refreshes ignore known IDs, current user and dashboard stats are requested concurrently, a dashboard-stats failure still publishes balance with nil secondary values, and successful state is persisted after decoding.

```swift
actor BalanceService {
    func refresh() async throws -> RefreshResult
    func clearBaseline() async throws
}
```

Inside `refresh`, call `AuthManager.withAccessToken`, use `async let` for current user, dashboard stats, and usage, preserve balance when secondary data fails, filter records against the persisted ID set, reconcile events, then save the new snapshot and IDs.

- [ ] **Step 5: Run service tests and commit**

Run: `swift test --filter BalanceReconcilerTests && swift test --filter BalanceServiceTests && swift test`

Expected: all reconciliation and service tests pass.

```bash
git add Sources/LoeBalance/Refresh/BalanceReconciler.swift Sources/LoeBalance/Refresh/BalanceService.swift Tests/LoeBalanceTests/BalanceReconcilerTests.swift Tests/LoeBalanceTests/BalanceServiceTests.swift
git commit -m "feat: reconcile balance and usage updates"
```

---

### Task 6: Refresh Scheduler, Backoff, and Network Recovery

**Files:**
- Create: `Sources/LoeBalance/Refresh/RefreshScheduler.swift`
- Create: `Sources/LoeBalance/Support/NetworkMonitor.swift`
- Create: `Tests/LoeBalanceTests/RefreshSchedulerTests.swift`

**Interfaces:**
- Consumes: `BalanceService.refresh`, `AppPreferences.refreshInterval`, and `ConnectionState`.
- Produces: `RefreshScheduling`, actor `RefreshScheduler`, and `NetworkMonitoring`.

- [ ] **Step 1: Write failing scheduler tests with an injected sleeper**

```swift
protocol AsyncSleeping: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

func testStartRefreshesImmediatelyThenUsesConfiguredInterval() async {
    let sleeper = RecordingSleeper()
    let recorder = RefreshRecorder()
    let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)
    await scheduler.start()
    let callCount = await recorder.callCount
    let durations = await sleeper.requestedDurations
    XCTAssertEqual(callCount, 1)
    XCTAssertEqual(durations.first, 30)
}
```

Implement `RecordingSleeper` and `RefreshRecorder` as actors in the test file so their state can be read safely under Swift 6 concurrency checks. Add tests for interval changes, manual refresh sharing the in-flight task, offline pause, immediate network-recovery refresh, `Retry-After`, bounded exponential backoff, stop cancellation, and system-wake refresh.

- [ ] **Step 2: Run scheduler tests and verify they fail**

Run: `swift test --filter RefreshSchedulerTests`

Expected: compilation fails because scheduler interfaces are missing.

- [ ] **Step 3: Implement the scheduler actor and path monitor adapter**

```swift
actor RefreshScheduler {
    func start() async
    func stop()
    func updateInterval(_ seconds: TimeInterval)
    func refreshNow() async
    func networkBecameAvailable() async
    func systemDidWake() async
}
```

Clamp intervals to 10 through 3,600 seconds. Keep one `loopTask` and one `inFlightRefresh`. For `429`, use `Retry-After` when present; otherwise use delays of 10, 20, 40, 80, 160, then 300 seconds. Reset backoff after success. `NWPathMonitor` publishes only status changes and never owns refresh logic.

- [ ] **Step 4: Run focused and complete tests**

Run: `swift test --filter RefreshSchedulerTests && swift test`

Expected: scheduler tests pass without real sleeping or network access.

- [ ] **Step 5: Commit scheduling**

```bash
git add Sources/LoeBalance/Refresh/RefreshScheduler.swift Sources/LoeBalance/Support/NetworkMonitor.swift Tests/LoeBalanceTests/RefreshSchedulerTests.swift
git commit -m "feat: schedule resilient balance refreshes"
```

---

### Task 7: Deterministic Damage Motion Planning and Stream View

**Files:**
- Create: `Sources/LoeBalance/Animation/DamageAnimationPlanner.swift`
- Create: `Sources/LoeBalance/Animation/DamageStreamView.swift`
- Create: `Tests/LoeBalanceTests/DamageAnimationPlannerTests.swift`

**Interfaces:**
- Consumes: `BalanceAnimationEvent` and `ShakeStrength`.
- Produces: `DamageSurface`, `DamageMotionPlan`, `DamageAnimationPlanner.plan`, and main-actor `DamageStreamView.play`.

- [ ] **Step 1: Write failing planner tests for cadence, ranges, and Reduce Motion**

```swift
func testDesktopDebitPlansFormConcurrentSingleOriginStream() {
    let planner = DamageAnimationPlanner(random: SequenceRandom(values: [0.0, 1.0, 0.5]))
    let plans = planner.plan(events: [.debit(.cents(3)), .debit(.cents(6)), .debit(.cents(12))], surface: .desktop, reduceMotion: false)
    XCTAssertEqual(plans.map(\.launchDelay), [0.00, 0.23, 0.46])
    XCTAssertEqual(plans.map(\.duration), [0.82, 0.82, 0.82])
    XCTAssertTrue(plans.allSatisfy { (-13...13).contains($0.endX) })
    XCTAssertTrue(plans.allSatisfy { (-8...8).contains($0.endRotationDegrees) })
}
```

Add tests that menu offsets stay within 7 px and 4 degrees, credits use green style, only one shake plan exists per debit burst, Off disables shake, and Reduce Motion disables shake and shortens rise.

- [ ] **Step 2: Run planner tests and verify they fail**

Run: `swift test --filter DamageAnimationPlannerTests`

Expected: compilation fails because planner types are missing.

- [ ] **Step 3: Implement exact motion plans and random-source injection**

```swift
enum DamageSurface: Sendable { case desktop, menuBar }

protocol MotionRandomizing: Sendable {
    func value(in range: ClosedRange<CGFloat>) -> CGFloat
}

struct SystemMotionRandom: MotionRandomizing {
    func value(in range: ClosedRange<CGFloat>) -> CGFloat { .random(in: range) }
}

struct DamageMotionPlan: Equatable, Sendable {
    let event: BalanceAnimationEvent
    let launchDelay: TimeInterval
    let duration: TimeInterval
    let startX: CGFloat
    let midX: CGFloat
    let endX: CGFloat
    let rise: CGFloat
    let startRotationDegrees: CGFloat
    let endRotationDegrees: CGFloat
}
```

Add a locked `SequenceRandom: MotionRandomizing, @unchecked Sendable` in the test file; it consumes normalized values in order and maps each value into the requested closed range. `DamageAnimationPlanner` accepts `any MotionRandomizing`, defaulting to `SystemMotionRandom`. Use 0.23-second launch spacing and 0.82-second normal duration. Desktop ranges: start X ±5, mid X ±9, end X ±13, rotations ±8, rise 86 through 100. Menu ranges: start X ±3, mid X ±5, end X ±7, rotations ±4, rise 47 through 55.

- [ ] **Step 4: Implement the layer-backed stream view**

`DamageStreamView.play(plans:anchor:)` creates one non-editable label per plan, positions every label at the same anchor beside the balance, and schedules `CAKeyframeAnimation` for position, opacity, transform scale, and rotation. Red labels represent debit; green labels represent credit. Remove each label after completion. The view must not resize its owning card or status item.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter DamageAnimationPlannerTests && swift test`

Expected: all planner tests pass and the AppKit animation view compiles.

```bash
git add Sources/LoeBalance/Animation Tests/LoeBalanceTests/DamageAnimationPlannerTests.swift
git commit -m "feat: add bead-style balance animations"
```

---

### Task 8: Desktop Card and Desktop-Layer Panel

**Files:**
- Create: `Sources/LoeBalance/DesktopCard/DesktopCardView.swift`
- Create: `Sources/LoeBalance/DesktopCard/DesktopCardController.swift`
- Create: `Tests/LoeBalanceTests/DesktopCardControllerTests.swift`

**Interfaces:**
- Consumes: `BalanceSnapshot`, `ConnectionState`, `DamageStreamView`, `DamageAnimationPlanner`, `AppPreferences`.
- Produces: main-actor `DesktopCardPresenting` and `DesktopCardController`.

- [ ] **Step 1: Write failing window-policy and presentation tests**

Test that the panel is non-activating, transparent, excluded from the window cycle, visible on all Spaces, stationary in Mission Control, below normal windows, movable by its background, and initialized to the approved 326-by-218-point content size. Test that presenting a snapshot updates all labels without modifying the panel frame.

- [ ] **Step 2: Run desktop-card tests and verify they fail**

Run: `swift test --filter DesktopCardControllerTests`

Expected: compilation fails because card types are missing.

- [ ] **Step 3: Build the approved card view**

Create a layer-backed `NSView` containing an `NSVisualEffectView`, title, balance, today's spend, today's requests, connection dot, last-update label, and `DamageStreamView`. Use Auto Layout with fixed outer size, stable label widths, monospaced digits, 22-point corner radius, and no visible animation track. Anchor damage labels directly beside the balance.

- [ ] **Step 4: Implement panel configuration, dragging, Spaces behavior, and frame persistence**

```swift
@MainActor
protocol DesktopCardPresenting: AnyObject {
    func present(snapshot: BalanceSnapshot, connection: ConnectionState)
    func play(events: [BalanceAnimationEvent], shake: ShakeStrength, reduceMotion: Bool)
    func setVisible(_ visible: Bool)
}
```

Use a borderless `.nonactivatingPanel` `NSPanel`, `isOpaque = false`, `backgroundColor = .clear`, `hidesOnDeactivate = false`, `.canJoinAllSpaces`, `.stationary`, and `.ignoresCycle`. Resolve a Core Graphics window level above the desktop surface but below `.normal`. Save `panel.frame` after drag completion and clamp a restored frame to an attached screen's visible frame.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter DesktopCardControllerTests && swift test`

Expected: all card tests pass.

```bash
git add Sources/LoeBalance/DesktopCard Tests/LoeBalanceTests/DesktopCardControllerTests.swift
git commit -m "feat: add desktop balance card"
```

---

### Task 9: Menu Bar Balance, Feedback, and Commands

**Files:**
- Create: `Sources/LoeBalance/StatusBar/StatusBarContentView.swift`
- Create: `Sources/LoeBalance/StatusBar/StatusBarController.swift`
- Create: `Tests/LoeBalanceTests/StatusBarControllerTests.swift`

**Interfaces:**
- Consumes: snapshots, connection state, damage plans, and command closures.
- Produces: `StatusBarPresenting`, `StatusBarCommands`, and `StatusBarController`.

- [ ] **Step 1: Write failing status-bar tests**

Test that the balance string remains unchanged while events play, the content view reserves a fixed damage area close to the balance, menu commands call the correct closures, connection colors map to online/offline/rate-limited/login-required states, and repeated snapshot presentation does not create duplicate menu items.

- [ ] **Step 2: Run status-bar tests and verify they fail**

Run: `swift test --filter StatusBarControllerTests`

Expected: compilation fails because status-bar types are missing.

- [ ] **Step 3: Implement fixed-width status content without balance movement**

Create `StatusBarContentView` with a dot, monospaced balance label, and a 54-point `DamageStreamView` placed 2 points after the balance. Set `NSStatusItem.length` to a stable width derived from the balance label's maximum supported text plus the damage area. The custom view must return `nil` from `hitTest` so the status button continues to receive clicks.

- [ ] **Step 4: Implement the status menu and command protocol**

```swift
struct StatusBarCommands {
    let refreshNow: @MainActor () -> Void
    let toggleDesktopCard: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    let logout: @MainActor () -> Void
    let quit: @MainActor () -> Void
}
```

Build the menu in this order: balance summary, connection/last update, separator, Refresh Now, Show or Hide Desktop Card, Settings, separator, Log Out, Quit LoeBalance. Update existing item titles and enabled states in place.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter StatusBarControllerTests && swift test`

Expected: all status-bar tests pass.

```bash
git add Sources/LoeBalance/StatusBar Tests/LoeBalanceTests/StatusBarControllerTests.swift
git commit -m "feat: show balance in the menu bar"
```

---

### Task 10: Login, Settings, and Launch at Login

**Files:**
- Create: `Sources/LoeBalance/Settings/LoginView.swift`
- Create: `Sources/LoeBalance/Settings/LoginViewModel.swift`
- Create: `Sources/LoeBalance/Settings/SettingsView.swift`
- Create: `Sources/LoeBalance/Settings/SettingsViewModel.swift`
- Create: `Sources/LoeBalance/Settings/SettingsWindowController.swift`
- Create: `Sources/LoeBalance/Support/LaunchAtLoginService.swift`
- Create: `Tests/LoeBalanceTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `AuthManager`, preferences, scheduler commands, and `SMAppService.mainApp`.
- Produces: `LoginViewModel`, `SettingsViewModel`, `SettingsWindowController`, and `LaunchAtLoginServicing`.

- [ ] **Step 1: Write failing view-model tests**

Test email validation, six-character password minimum, password clearing after both successful and failed login, interval preset/custom conversion, interval clamping, shake updates, card visibility updates, launch-at-login success, and launch-at-login failure reverting the toggle.

- [ ] **Step 2: Run settings tests and verify they fail**

Run: `swift test --filter SettingsViewModelTests`

Expected: compilation fails because settings types are missing.

- [ ] **Step 3: Implement testable view models and launch service**

```swift
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    func submit() async
}

protocol LaunchAtLoginServicing {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}
```

`submit` validates locally, copies the password only for the awaited login call, and clears both the local copy and published password with `defer`. Wrap `SMAppService.mainApp.register()` and `.unregister()`; report the actual service state after each operation.

- [ ] **Step 4: Implement compact SwiftUI login and settings windows**

Login contains email, secure password, progress/error state, and Sign In. Settings uses a segmented control for shake, menu/picker for refresh presets, numeric custom interval with seconds/minutes unit, toggles for card visibility and launch at login, and a Log Out command. Do not add explanatory feature text to the app UI.

- [ ] **Step 5: Run tests and commit**

Run: `swift test --filter SettingsViewModelTests && swift test`

Expected: all settings and login tests pass.

```bash
git add Sources/LoeBalance/Settings Sources/LoeBalance/Support/LaunchAtLoginService.swift Tests/LoeBalanceTests/SettingsViewModelTests.swift
git commit -m "feat: add login and settings windows"
```

---

### Task 11: Application Coordination and Lifecycle Integration

**Files:**
- Create: `Sources/LoeBalance/App/main.swift`
- Create: `Sources/LoeBalance/App/AppDelegate.swift`
- Create: `Sources/LoeBalance/App/AppCoordinator.swift`
- Create: `Sources/LoeBalance/Support/Logger.swift`
- Create: `Tests/LoeBalanceTests/AppCoordinatorTests.swift`

**Interfaces:**
- Consumes: every service and UI controller from Tasks 2 through 10.
- Produces: runnable `LoeBalance` executable and one composition root.

- [ ] **Step 1: Write failing coordinator tests with UI spies**

Test these transitions: no Keychain token opens login; restored session performs baseline refresh; successful refresh presents the snapshot before starting animations; offline failure preserves the old snapshot; preference changes reschedule polling and update shake; logout stops scheduling, clears persisted state, hides the card, and opens login; wake and network recovery request immediate refresh.

- [ ] **Step 2: Run coordinator tests and verify they fail**

Run: `swift test --filter AppCoordinatorTests`

Expected: compilation fails because the coordinator is missing.

- [ ] **Step 3: Implement the composition root and lifecycle state machine**

```swift
@MainActor
final class AppCoordinator {
    func start() async
    func handleRefreshResult(_ result: RefreshResult)
    func refreshNow()
    func openSettings()
    func toggleDesktopCard()
    func logout() async
    func applicationDidWake()
}
```

Construct concrete stores, API client, auth manager, balance service, scheduler, animation planner, card controller, status controller, settings controller, network monitor, and launch service in one initializer. Publish snapshot text to both surfaces first, then ask the planner/controllers to play events.

- [ ] **Step 4: Implement AppKit startup and lifecycle notifications**

`main.swift` creates `NSApplication.shared`, sets activation policy `.accessory`, installs `AppDelegate`, and runs the application. `AppDelegate` starts the coordinator, subscribes to `NSWorkspace.didWakeNotification`, and stops scheduler/network monitor during termination. Use `Logger` categories `auth`, `api`, `refresh`, `desktop`, and `status`; never log secrets or full response bodies.

- [ ] **Step 5: Run all tests and commit**

Run: `swift test`

Expected: every test passes and the executable target links.

```bash
git add Sources/LoeBalance/App Sources/LoeBalance/Support/Logger.swift Tests/LoeBalanceTests/AppCoordinatorTests.swift
git commit -m "feat: integrate LoeBalance application lifecycle"
```

---

### Task 12: Project Build, App Bundle, Run Action, and Smoke Launch

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

**Interfaces:**
- Consumes: executable product `LoeBalance`.
- Produces: `dist/LoeBalance.app`, stable build/run command, and Codex Run action.

- [ ] **Step 1: Write the build/run script with strict failure handling**

The script must support default, `--verify`, `--logs`, and `--telemetry` modes. It must stop an existing process, run `swift build`, stage this bundle structure, generate Info.plist, ad-hoc sign, launch with `/usr/bin/open -n`, and verify with `pgrep -x LoeBalance`:

```text
dist/LoeBalance.app/
  Contents/
    Info.plist
    MacOS/LoeBalance
    Resources/
```

Use bundle identifier `cx.loe.LoeBalance`, display name `LoeBalance`, minimum system version `13.0`, `LSUIElement=true`, and `NSPrincipalClass=NSApplication`. Sign with `codesign --force --deep --sign - dist/LoeBalance.app`.

- [ ] **Step 2: Add the Codex Run action**

```toml
[[actions]]
name = "Run"
icon = "run"
command = "./script/build_and_run.sh"
```

- [ ] **Step 3: Run the complete test suite before launching**

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 4: Build and verify the GUI process**

Run: `chmod +x script/build_and_run.sh && ./script/build_and_run.sh --verify`

Expected: Swift build succeeds, bundle signing succeeds, and `pgrep -x LoeBalance` finds the running process.

- [ ] **Step 5: Inspect launch logs and commit build tooling**

Run: `./script/build_and_run.sh --telemetry`

Expected: app startup, status-item creation, and login-required state appear without credential values or crashes. Stop log streaming after confirming those events.

```bash
git add script/build_and_run.sh .codex/environments/environment.toml
git commit -m "build: package and launch LoeBalance"
```

---

### Task 13: End-to-End QA and User-Facing App Archive

**Files:**
- Create: `outputs/LoeBalance-macOS-x86_64.zip`
- Create: `outputs/LoeBalance-macOS-x86_64.sha256`
- Modify only if QA exposes a defect: the smallest owning source/test file.

**Interfaces:**
- Consumes: the complete app and build script.
- Produces: verified local app archive and checksum.

- [ ] **Step 1: Run automated verification from a clean build directory**

Run: `rm -rf .build dist && swift test && ./script/build_and_run.sh --verify`

Expected: clean compilation, all tests pass, bundle launches, and the process is present.

- [ ] **Step 2: Perform desktop and menu bar validation**

Verify on the current Mac that the desktop card is visible above the desktop surface, covered by normal windows, movable, restored after relaunch, visible across Spaces, absent from the normal window cycle, and correctly adapted to light/dark appearance. Verify menu balance stability, menu commands, and Show/Hide Desktop Card.

- [ ] **Step 3: Perform authentication and live-data validation**

Have the user enter credentials in the app. Verify successful balance and statistics retrieval, first-login baseline without historical animations, relaunch through Keychain refresh, manual refresh, configurable interval, token-expiry refresh, logout cleanup, and no secrets in telemetry output.

- [ ] **Step 4: Validate debit, credit, and accessibility behavior**

Using deterministic debug fixtures or newly observed live records, verify Off/Weak/Strong shake, one shake per burst, 230 ms concurrent single-origin debit stream, no text overlap, approved random motion, fixed menu balance, 20-item aggregation, green credit pulse, and Reduce Motion behavior.

- [ ] **Step 5: Package the verified bundle and checksum**

```bash
mkdir -p outputs
ditto -c -k --sequesterRsrc --keepParent dist/LoeBalance.app outputs/LoeBalance-macOS-x86_64.zip
shasum -a 256 outputs/LoeBalance-macOS-x86_64.zip > outputs/LoeBalance-macOS-x86_64.sha256
```

Expected: both output files exist, the archive expands to `LoeBalance.app`, and the checksum validates with `shasum -a 256 -c outputs/LoeBalance-macOS-x86_64.sha256`.

- [ ] **Step 6: Record final repository state**

Run: `git status --short && git log --oneline --decorate -15`

Expected: source and test changes are committed; only ignored build/output artifacts remain outside Git tracking.
