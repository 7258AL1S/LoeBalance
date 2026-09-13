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

    func testFailurePresentsCachedSnapshotWithMappedConnectionAndDoesNotAnimate() {
        let card = CoordinatorCardSpy()
        let status = CoordinatorStatusSpy()
        let coordinator = makeCoordinator(card: card, status: status)
        coordinator.handleRefreshResult(RefreshResult(snapshot: .fixture, events: [], connectionState: .online))

        coordinator.handleRefreshFailure(AppError.rateLimited(retryAfter: .fixtureNow))

        XCTAssertEqual(card.presentedConnections, [.online, .rateLimited(until: .fixtureNow)])
        XCTAssertEqual(status.presentedConnections, [.online, .rateLimited(until: .fixtureNow)])
        XCTAssertEqual(card.calls, [.present, .present])
        XCTAssertEqual(status.calls, [.present, .present])
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

    func testCardPositionAndLayerPreferencesPropagateToDesktopCard() {
        let card = CoordinatorCardSpy()
        let coordinator = makeCoordinator(card: card)

        coordinator.preferenceCardPositionChanged(.topLeft)
        coordinator.preferenceCardLayerChanged(.aboveApplications)

        XCTAssertEqual(card.positions, [.topLeft])
        XCTAssertEqual(card.layers, [.aboveApplications])
    }

    func testNetworkUnavailablePausesSchedulerAndPresentsOfflineSnapshot() async {
        let scheduler = CoordinatorTestScheduler()
        let card = CoordinatorCardSpy()
        let status = CoordinatorStatusSpy()
        let coordinator = makeCoordinator(scheduler: scheduler, card: card, status: status)
        coordinator.handleRefreshResult(RefreshResult(snapshot: .fixture, events: [], connectionState: .online))

        coordinator.networkBecameUnavailable()
        await Task.yield()

        let state = await scheduler.state()
        XCTAssertEqual(state.unavailable, 1)
        XCTAssertEqual(card.presentedConnections.last, .offline)
        XCTAssertEqual(status.presentedConnections.last, .offline)
    }

    func testMenuToggleUsesSettingsTransactionBeforeUpdatingCoordinatorState() {
        let settings = CoordinatorSettingsSpy(result: true)
        let card = CoordinatorCardSpy()
        let status = CoordinatorStatusSpy()
        let coordinator = makeCoordinator(card: card, status: status, settings: settings)

        coordinator.toggleDesktopCard()

        XCTAssertEqual(settings.values, [false])
        XCTAssertFalse(coordinator.showsDesktopCard)
        XCTAssertEqual(status.visibility, [false])
    }

    func testTransientRestoreFailureKeepsCachedSnapshotAndStartsRetryingSession() async {
        let auth = CoordinatorTestAuth(error: .transport(URLError(.notConnectedToInternet)))
        let scheduler = CoordinatorTestScheduler()
        let card = CoordinatorCardSpy()
        let status = CoordinatorStatusSpy()
        let login = CoordinatorLoginSpy()
        let coordinator = makeCoordinator(
            auth: auth,
            scheduler: scheduler,
            card: card,
            status: status,
            login: login,
            initialSnapshot: .fixture
        )

        await coordinator.start()

        let state = await scheduler.state()
        XCTAssertEqual(state.start, 1)
        XCTAssertEqual(login.openCount, 0)
        XCTAssertEqual(card.presentedConnections, [.offline])
        XCTAssertEqual(status.presentedConnections, [.offline])
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
        login: CoordinatorLoginSpy = CoordinatorLoginSpy(),
        settings: CoordinatorSettingsSpy = CoordinatorSettingsSpy(),
        initialSnapshot: BalanceSnapshot? = nil
    ) -> AppCoordinator {
        AppCoordinator(dependencies: .init(
            authentication: auth,
            balanceService: balance,
            scheduler: scheduler,
            networkMonitor: CoordinatorNetworkSpy(),
            desktopCard: card,
            statusBar: status,
            settingsWindow: settings,
            openLogin: { login.open() },
            initialPreferences: AppPreferences(),
            initialSnapshot: initialSnapshot,
            reduceMotion: true
        ))
    }
}

private extension BalanceSnapshot {
    static let fixture = Self(balance: Money(decimal: 19.58), todaySpend: Money(decimal: 0.3), todayRequests: 2, updatedAt: .fixtureNow)
}

private actor CoordinatorTestAuth: CoordinatorAuthenticating {
    let restored: Bool
    let error: AppError?
    private(set) var restoreCount = 0
    private(set) var logoutCount = 0

    init(restored: Bool = true, error: AppError? = nil) {
        self.restored = restored
        self.error = error
    }

    func restoreSession() async throws -> Bool {
        restoreCount += 1
        if let error { throw error }
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
    private(set) var networkUnavailableCount = 0

    func start() async { startCount += 1 }
    func stop() { stopCount += 1 }
    func updateInterval(_ seconds: TimeInterval) { updatedIntervals.append(seconds) }
    func refreshNow() async {}
    func networkBecameUnavailable() { networkUnavailableCount += 1 }
    func networkBecameAvailable() async { networkRecoveryCount += 1 }
    func systemDidWake() async { wakeCount += 1 }

    func state() -> (start: Int, stop: Int, intervals: [TimeInterval], wake: Int, recovery: Int, unavailable: Int) {
        (startCount, stopCount, updatedIntervals, wakeCount, networkRecoveryCount, networkUnavailableCount)
    }
}

@MainActor
private final class CoordinatorCardSpy: DesktopCardPresenting {
    enum Call: Equatable { case present, play }
    enum Order: Equatable { case cardPresent, statusPresent, cardPlay, statusPlay }
    var calls: [Call] = []
    var order: [Order] = []
    var presentedSnapshots: [BalanceSnapshot] = []
    var presentedConnections: [ConnectionState] = []
    var visibility: [Bool] = []
    var positions: [CardPositionPreset] = []
    var layers: [CardLayer] = []

    func present(snapshot: BalanceSnapshot, connection: ConnectionState) { calls.append(.present); presentedSnapshots.append(snapshot); presentedConnections.append(connection); order.append(.cardPresent) }
    func play(events: [BalanceAnimationEvent], shake: ShakeStrength, reduceMotion: Bool) { calls.append(.play); order.append(.cardPlay) }
    func setVisible(_ visible: Bool) { visibility.append(visible) }
    func setCardPosition(_ position: CardPositionPreset) { positions.append(position) }
    func setCardLayer(_ layer: CardLayer) { layers.append(layer) }
}

@MainActor
private final class CoordinatorStatusSpy: StatusBarPresenting {
    enum Call: Equatable { case present, play }
    var calls: [Call] = []
    var presentedSnapshots: [BalanceSnapshot] = []
    var presentedConnections: [ConnectionState] = []
    var visibility: [Bool] = []
    var onPresent: (() -> Void)?

    func present(snapshot: BalanceSnapshot, connection: ConnectionState, showsDesktopCard: Bool) { calls.append(.present); presentedSnapshots.append(snapshot); presentedConnections.append(connection); onPresent?() }
    func play(events: [BalanceAnimationEvent], reduceMotion: Bool) { calls.append(.play) }
    func setDesktopCardVisible(_ visible: Bool) { visibility.append(visible) }
}

@MainActor
private final class CoordinatorLoginSpy {
    private(set) var openCount = 0
    func open() { openCount += 1 }
}

@MainActor
private final class CoordinatorSettingsSpy: SettingsWindowPresenting {
    var result: Bool
    var values: [Bool] = []

    init(result: Bool = true) { self.result = result }
    func present() {}
    func setShowsDesktopCard(_ value: Bool) -> Bool {
        values.append(value)
        return result
    }
}

private final class CoordinatorNetworkSpy: NetworkMonitoring {
    func start() {}
    func stop() {}
}
