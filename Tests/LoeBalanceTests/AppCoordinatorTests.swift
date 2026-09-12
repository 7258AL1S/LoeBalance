import Foundation
import XCTest
@testable import LoeBalance

@MainActor
final class AppCoordinatorTests: XCTestCase {
    func testMissingSessionOpensLoginAndDoesNotStartScheduler() async {
        let auth = CoordinatorTestAuth(restored: false)
        let scheduler = CoordinatorTestScheduler()
        let login = CoordinatorLoginSpy()
        let coordinator = makeCoordinator(auth: auth, scheduler: scheduler, login: login)

        await coordinator.start()

        XCTAssertEqual(login.openCount, 1)
        let state = await scheduler.state()
        XCTAssertEqual(state.start, 0)
    }

    func testRestoredSessionStartsSchedulerForBaselineRefresh() async {
        let auth = CoordinatorTestAuth(restored: true)
        let scheduler = CoordinatorTestScheduler()
        let coordinator = makeCoordinator(auth: auth, scheduler: scheduler)

        await coordinator.start()

        let authState = await auth.state()
        let schedulerState = await scheduler.state()
        XCTAssertEqual(authState.restore, 1)
        XCTAssertEqual(schedulerState.start, 1)
    }

    func testSuccessfulRefreshPresentsBothSurfacesBeforeAnimations() {
        let events: [BalanceAnimationEvent] = [.debit(Money(decimal: 0.3))]
        let result = RefreshResult(snapshot: .fixture, events: events, connectionState: .online)
        let card = CoordinatorCardSpy()
        let status = CoordinatorStatusSpy()
        let coordinator = makeCoordinator(card: card, status: status)

        coordinator.handleRefreshResult(result)

        XCTAssertEqual(card.calls, [.present, .play])
        XCTAssertEqual(status.calls, [.present, .play])
        XCTAssertEqual(card.order, [.cardPresent, .statusPresent, .cardPlay, .statusPlay])
    }

    func testFailureDoesNotReplaceExistingSnapshot() {
        let card = CoordinatorCardSpy()
        let status = CoordinatorStatusSpy()
        let coordinator = makeCoordinator(card: card, status: status)
        coordinator.handleRefreshResult(RefreshResult(snapshot: .fixture, events: [], connectionState: .online))

        coordinator.handleRefreshFailure(AppError.transport(URLError(.notConnectedToInternet)))

        XCTAssertEqual(card.presentedSnapshots.count, 1)
        XCTAssertEqual(status.presentedSnapshots.count, 1)
    }

    func testPreferencesPropagateToSchedulerShakeAndCard() async {
        let scheduler = CoordinatorTestScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)

        coordinator.preferenceRefreshIntervalChanged(90)
        coordinator.preferenceShakeStrengthChanged(.strong)
        coordinator.preferenceDesktopCardChanged(false)

        let schedulerState = await scheduler.state()
        XCTAssertEqual(schedulerState.intervals, [90])
        XCTAssertEqual(coordinator.shakeStrength, .strong)
        XCTAssertEqual(coordinator.showsDesktopCard, false)
    }

    func testLogoutStopsClearsHidesAndOpensLogin() async {
        let auth = CoordinatorTestAuth(restored: true)
        let scheduler = CoordinatorTestScheduler()
        let balance = CoordinatorTestBalance()
        let card = CoordinatorCardSpy()
        let login = CoordinatorLoginSpy()
        let coordinator = makeCoordinator(auth: auth, balance: balance, scheduler: scheduler, card: card, login: login)

        await coordinator.logout()

        let schedulerState = await scheduler.state()
        let authState = await auth.state()
        let balanceState = await balance.state()
        XCTAssertEqual(schedulerState.stop, 1)
        XCTAssertEqual(authState.logout, 1)
        XCTAssertEqual(balanceState.clear, 1)
        XCTAssertEqual(card.visibility, [false])
        XCTAssertEqual(login.openCount, 1)
    }

    func testWakeAndNetworkRecoveryRequestImmediateRefresh() async {
        let scheduler = CoordinatorTestScheduler()
        let coordinator = makeCoordinator(scheduler: scheduler)

        coordinator.applicationDidWake()
        coordinator.networkBecameAvailable()
        await Task.yield()

        let schedulerState = await scheduler.state()
        XCTAssertEqual(schedulerState.wake, 1)
        XCTAssertEqual(schedulerState.recovery, 1)
    }

    private func makeCoordinator(
        auth: CoordinatorTestAuth = CoordinatorTestAuth(restored: true),
        balance: CoordinatorTestBalance = CoordinatorTestBalance(),
        scheduler: CoordinatorTestScheduler = CoordinatorTestScheduler(),
        card: CoordinatorCardSpy = CoordinatorCardSpy(),
        status: CoordinatorStatusSpy = CoordinatorStatusSpy(),
        login: CoordinatorLoginSpy = CoordinatorLoginSpy()
    ) -> AppCoordinator {
        AppCoordinator(dependencies: .init(
            authentication: auth,
            balanceService: balance,
            scheduler: scheduler,
            networkMonitor: CoordinatorNetworkSpy(),
            desktopCard: card,
            statusBar: status,
            settingsWindow: CoordinatorSettingsSpy(),
            openLogin: { login.open() },
            initialPreferences: AppPreferences(),
            reduceMotion: true
        ))
    }
}

private extension BalanceSnapshot {
    static let fixture = Self(balance: Money(decimal: 19.58), todaySpend: Money(decimal: 0.3), todayRequests: 2, updatedAt: .fixtureNow)
}

private actor CoordinatorTestAuth: CoordinatorAuthenticating {
    let restored: Bool
    private(set) var restoreCount = 0
    private(set) var logoutCount = 0

    init(restored: Bool) { self.restored = restored }

    func restoreSession() async throws -> Bool {
        restoreCount += 1
        return restored
    }

    func logout() async throws { logoutCount += 1 }

    func state() -> (restore: Int, logout: Int) { (restoreCount, logoutCount) }
}

private actor CoordinatorTestBalance: BalanceServicing {
    private(set) var clearBaselineCount = 0

    func refresh() async throws -> RefreshResult { .init(snapshot: .fixture, events: [], connectionState: .online) }
    func clearBaseline() async throws { clearBaselineCount += 1 }

    func state() -> (clear: Int) { (clearBaselineCount) }
}

private actor CoordinatorTestScheduler: RefreshScheduling {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var updatedIntervals: [TimeInterval] = []
    private(set) var wakeCount = 0
    private(set) var networkRecoveryCount = 0

    func start() async { startCount += 1 }
    func stop() { stopCount += 1 }
    func updateInterval(_ seconds: TimeInterval) { updatedIntervals.append(seconds) }
    func refreshNow() async {}
    func networkBecameAvailable() async { networkRecoveryCount += 1 }
    func systemDidWake() async { wakeCount += 1 }

    func state() -> (start: Int, stop: Int, intervals: [TimeInterval], wake: Int, recovery: Int) {
        (startCount, stopCount, updatedIntervals, wakeCount, networkRecoveryCount)
    }
}

@MainActor
private final class CoordinatorCardSpy: DesktopCardPresenting {
    enum Call: Equatable { case present, play }
    enum Order: Equatable { case cardPresent, statusPresent, cardPlay, statusPlay }
    var calls: [Call] = []
    var order: [Order] = []
    var presentedSnapshots: [BalanceSnapshot] = []
    var visibility: [Bool] = []

    func present(snapshot: BalanceSnapshot, connection: ConnectionState) { calls.append(.present); presentedSnapshots.append(snapshot); order.append(.cardPresent) }
    func play(events: [BalanceAnimationEvent], shake: ShakeStrength, reduceMotion: Bool) { calls.append(.play); order.append(.cardPlay) }
    func setVisible(_ visible: Bool) { visibility.append(visible) }
}

@MainActor
private final class CoordinatorStatusSpy: StatusBarPresenting {
    enum Call: Equatable { case present, play }
    var calls: [Call] = []
    var presentedSnapshots: [BalanceSnapshot] = []
    var onPresent: (() -> Void)?

    func present(snapshot: BalanceSnapshot, connection: ConnectionState, showsDesktopCard: Bool) { calls.append(.present); presentedSnapshots.append(snapshot); onPresent?() }
    func play(events: [BalanceAnimationEvent], reduceMotion: Bool) { calls.append(.play) }
}

@MainActor
private final class CoordinatorLoginSpy {
    private(set) var openCount = 0
    func open() { openCount += 1 }
}

@MainActor
private final class CoordinatorSettingsSpy: SettingsWindowPresenting {
    func present() {}
}

private final class CoordinatorNetworkSpy: NetworkMonitoring {
    func start() {}
    func stop() {}
}
