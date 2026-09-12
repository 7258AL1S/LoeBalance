import Foundation
import XCTest
@testable import LoeBalance

final class RefreshSchedulerTests: XCTestCase {
    func testStartRefreshesImmediatelyThenUsesConfiguredInterval() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder()
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()

        XCTAssertEqual(await recorder.callCount, 1)
        XCTAssertEqual(await sleeper.requestedDurations.first, 30)
        await scheduler.stop()
    }

    func testIntervalUpdatesAreClampedAndUsedForTheNextCycle() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder()
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await scheduler.updateInterval(1)
        await sleeper.releaseNextSleep()
        await Task.yield()

        XCTAssertEqual(await sleeper.requestedDurations, [30, 10])
        await scheduler.stop()
    }

    func testManualRefreshSharesAnInFlightRefresh() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder(blocked: true)
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        async let first = scheduler.refreshNow()
        await recorder.waitUntilStarted()
        async let second = scheduler.refreshNow()
        await recorder.release()
        await first
        await second

        XCTAssertEqual(await recorder.callCount, 1)
    }

    func testOfflineResultPausesUntilNetworkRecovery() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder(results: [RefreshResult.fixture(state: .offline), .fixture()])
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await sleeper.releaseNextSleep()
        await scheduler.networkBecameAvailable()

        XCTAssertEqual(await recorder.callCount, 2)
        await scheduler.stop()
    }

    func testRateLimitUsesRetryAfterThenResetsBackoffAfterSuccess() async {
        let sleeper = RecordingSleeper()
        let until = Date().addingTimeInterval(75)
        let recorder = RefreshRecorder(results: [RefreshResult.fixture(state: .rateLimited(until: until)), .fixture()])
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        XCTAssertEqual(await sleeper.requestedDurations.first!, until.timeIntervalSinceNow, accuracy: 2)
        await sleeper.releaseNextSleep()
        XCTAssertEqual(await recorder.callCount, 2)
        await scheduler.stop()
    }

    func testFailuresUseBoundedExponentialBackoff() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder(errors: [AppError.transport(URLError(.timedOut)), AppError.transport(URLError(.timedOut))])
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await sleeper.releaseNextSleep()
        await sleeper.releaseNextSleep()

        XCTAssertEqual(Array((await sleeper.requestedDurations).prefix(3)), [30, 10, 20])
        await scheduler.stop()
    }

    func testStopCancelsLoopAndPendingSleep() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder()
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await scheduler.stop()
        await sleeper.releaseAll()
        await Task.yield()

        XCTAssertEqual(await recorder.callCount, 1)
    }

    func testSystemWakeRefreshesImmediately() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder()
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await scheduler.systemDidWake()

        XCTAssertEqual(await recorder.callCount, 2)
        await scheduler.stop()
    }
}

actor RecordingSleeper: AsyncSleeping {
    private(set) var requestedDurations: [TimeInterval] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for seconds: TimeInterval) async throws {
        requestedDurations.append(seconds)
        try Task.checkCancellation()
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiters.append($0) }
        } onCancel: {
            Task { await self.releaseAll() }
        }
        try Task.checkCancellation()
    }

    func releaseNextSleep() {
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }

    func releaseAll() {
        let current = waiters
        waiters.removeAll()
        current.forEach { $0.resume() }
    }
}

actor RefreshRecorder {
    private(set) var callCount = 0
    private var results: [Result<RefreshResult, Error>]
    private let blocked: Bool
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(results: [RefreshResult] = [.fixture()], errors: [Error] = [], blocked: Bool = false) {
        self.results = results.map(Result.success) + errors.map(Result.failure)
        self.blocked = blocked
    }

    func run() async throws -> RefreshResult {
        callCount += 1
        started = true
        continuation?.resume()
        continuation = nil
        if blocked { await withCheckedContinuation { continuation = $0 } }
        guard !results.isEmpty else { return .fixture() }
        return try results.removeFirst().get()
    }

    func waitUntilStarted() async {
        if !started { await withCheckedContinuation { continuation = $0 } }
    }

    func release() { continuation?.resume(); continuation = nil }
}

private extension RefreshResult {
    static func fixture(state: ConnectionState = .online) -> Self {
        Self(snapshot: BalanceSnapshot(balance: Money(decimal: 1), todaySpend: nil, todayRequests: nil, updatedAt: Date()), events: [], connectionState: state)
    }
}
