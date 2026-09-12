import AppKit
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
}

private final class HarnessBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) { storage = value }

    var value: Value {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func update(_ body: (inout Value) -> Void) {
        lock.lock(); body(&storage); lock.unlock()
    }
}

private actor HarnessAuth: CoordinatorAuthenticating {
    let restored: Bool
    private(set) var restoreCount = 0
    private(set) var logoutCount = 0

    init(restored: Bool) { self.restored = restored }

    func restoreSession() async throws -> Bool {
        restoreCount += 1
        return restored
    }

    func logout() async throws { logoutCount += 1 }

    func counts() -> (restore: Int, logout: Int) { (restoreCount, logoutCount) }
}

private actor HarnessBalance: BalanceServicing {
    private(set) var clearCount = 0

    func refresh() async throws -> RefreshResult {
        RefreshResult(snapshot: .fixture, events: [], connectionState: .online)
    }

    func clearBaseline() async throws { clearCount += 1 }

    func clearBaselineCalls() -> Int { clearCount }
}

private actor HarnessScheduler: RefreshScheduling {
    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var intervals: [TimeInterval] = []
    private(set) var wakes = 0
    private(set) var recoveries = 0

    func start() async { starts += 1 }
    func stop() { stops += 1 }
    func updateInterval(_ seconds: TimeInterval) { intervals.append(seconds) }
    func refreshNow() async {}
    func networkBecameAvailable() async { recoveries += 1 }
    func systemDidWake() async { wakes += 1 }

    func state() -> (starts: Int, stops: Int, intervals: [TimeInterval], wakes: Int, recoveries: Int) {
        (starts, stops, intervals, wakes, recoveries)
    }
}

private final class HarnessNetwork: NetworkMonitoring {
    private(set) var starts = 0
    private(set) var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor
private final class HarnessCard: DesktopCardPresenting {
    let order: HarnessBox<[String]>
    private(set) var snapshots: [BalanceSnapshot] = []
    private(set) var visibility: [Bool] = []

    init(order: HarnessBox<[String]>) { self.order = order }

    func present(snapshot: BalanceSnapshot, connection: ConnectionState) {
        snapshots.append(snapshot)
        order.update { $0.append("card.present") }
    }

    func play(events: [BalanceAnimationEvent], shake: ShakeStrength, reduceMotion: Bool) {
        order.update { $0.append("card.play") }
    }

    func setVisible(_ visible: Bool) { visibility.append(visible) }
}

@MainActor
private final class HarnessStatus: StatusBarPresenting {
    let order: HarnessBox<[String]>
    private(set) var snapshots: [BalanceSnapshot] = []

    init(order: HarnessBox<[String]>) { self.order = order }

    func present(snapshot: BalanceSnapshot, connection: ConnectionState, showsDesktopCard: Bool) {
        snapshots.append(snapshot)
        order.update { $0.append("status.present") }
    }

    func play(events: [BalanceAnimationEvent], reduceMotion: Bool) {
        order.update { $0.append("status.play") }
    }
}

@MainActor
private final class HarnessSettings: SettingsWindowPresenting {
    private(set) var presents = 0
    func present() { presents += 1 }
}

@MainActor
private final class HarnessLogin {
    private(set) var opens = 0
    func open() { opens += 1 }
}

private extension BalanceSnapshot {
    static let fixture = Self(
        balance: Money(decimal: 19.58),
        todaySpend: Money(decimal: 0.30),
        todayRequests: 11,
        updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}

@main
@MainActor
struct Task11Harness {
    static func main() async {
        let missingAuth = HarnessAuth(restored: false)
        let missingScheduler = HarnessScheduler()
        let missingLogin = HarnessLogin()
        let missingCoordinator = makeCoordinator(
            auth: missingAuth,
            scheduler: missingScheduler,
            login: missingLogin
        )
        await missingCoordinator.start()
        require(missingLogin.opens == 1, "missing session opens login")
        let missingSchedulerState = await missingScheduler.state()
        require(missingSchedulerState.starts == 0, "missing session does not start scheduler")

        let auth = HarnessAuth(restored: true)
        let scheduler = HarnessScheduler()
        let balance = HarnessBalance()
        let order = HarnessBox<[String]>([])
        let card = HarnessCard(order: order)
        let status = HarnessStatus(order: order)
        let login = HarnessLogin()
        let coordinator = makeCoordinator(
            auth: auth,
            balance: balance,
            scheduler: scheduler,
            card: card,
            status: status,
            login: login
        )
        await coordinator.start()
        let restoredAuthState = await auth.counts()
        let startedSchedulerState = await scheduler.state()
        require(restoredAuthState.restore == 1, "restored session checked")
        require(startedSchedulerState.starts == 1, "restored session starts scheduler")

        coordinator.handleRefreshResult(RefreshResult(
            snapshot: .fixture,
            events: [.debit(Money(decimal: 0.30))],
            connectionState: .online
        ))
        require(order.value == ["card.present", "status.present", "card.play", "status.play"], "snapshot precedes animations")
        coordinator.handleRefreshFailure(AppError.transport(URLError(.notConnectedToInternet)))
        require(card.snapshots.count == 1 && status.snapshots.count == 1, "failed refresh preserves snapshot")

        coordinator.preferenceRefreshIntervalChanged(90)
        coordinator.preferenceShakeStrengthChanged(.strong)
        coordinator.preferenceDesktopCardChanged(false)
        await Task.yield()
        let preferenceSchedulerState = await scheduler.state()
        require(preferenceSchedulerState.intervals == [90], "interval propagates")
        require(coordinator.shakeStrength == .strong, "shake propagates")
        require(!coordinator.showsDesktopCard, "desktop-card preference propagates")

        coordinator.applicationDidWake()
        coordinator.networkBecameAvailable()
        await Task.yield()
        let recoverySchedulerState = await scheduler.state()
        require(recoverySchedulerState.wakes == 1, "wake requests immediate refresh")
        require(recoverySchedulerState.recoveries == 1, "network recovery requests immediate refresh")

        await coordinator.logout()
        let loggedOutSchedulerState = await scheduler.state()
        let loggedOutAuthState = await auth.counts()
        let clearCount = await balance.clearBaselineCalls()
        require(loggedOutSchedulerState.stops == 1, "logout stops scheduler")
        require(loggedOutAuthState.logout == 1, "logout clears auth")
        require(clearCount == 1, "logout clears snapshot baseline")
        require(card.visibility.last == false, "logout hides desktop card")
        require(login.opens == 1, "logout opens login")

        print("task-11 harness passed: auth transitions, ordered presentation, failure preservation, preferences, wake/recovery, logout")
    }

    private static func makeCoordinator(
        auth: HarnessAuth,
        balance: HarnessBalance = HarnessBalance(),
        scheduler: HarnessScheduler,
        card: HarnessCard? = nil,
        status: HarnessStatus? = nil,
        login: HarnessLogin
    ) -> AppCoordinator {
        let order = HarnessBox<[String]>([])
        let card = card ?? HarnessCard(order: order)
        let status = status ?? HarnessStatus(order: order)
        return AppCoordinator(dependencies: .init(
            authentication: auth,
            balanceService: balance,
            scheduler: scheduler,
            networkMonitor: HarnessNetwork(),
            desktopCard: card,
            statusBar: status,
            settingsWindow: HarnessSettings(),
            openLogin: { login.open() },
            initialPreferences: AppPreferences(),
            reduceMotion: true
        ))
    }
}
