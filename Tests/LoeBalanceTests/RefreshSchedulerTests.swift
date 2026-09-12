import Foundation
import XCTest
@testable import LoeBalance

final class RefreshSchedulerTests: XCTestCase {
    func testStartRefreshesImmediatelyThenUsesConfiguredInterval() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder()
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()

        let calls = await recorder.callCount
        let durations = await sleeper.requestedDurations
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(durations.first, 30)
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

        let durations = await sleeper.requestedDurations
        XCTAssertEqual(durations, [30, 10])
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

        let calls = await recorder.callCount
        XCTAssertEqual(calls, 1)
    }

    func testOfflineResultPausesUntilNetworkRecovery() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder(results: [RefreshResult.fixture(state: .offline), .fixture()])
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await sleeper.releaseNextSleep()
        await scheduler.networkBecameAvailable()

        let calls = await recorder.callCount
        XCTAssertEqual(calls, 2)
        await scheduler.stop()
    }

    func testRateLimitUsesRetryAfterThenResetsBackoffAfterSuccess() async {
        let sleeper = RecordingSleeper()
        let until = Date().addingTimeInterval(75)
        let recorder = RefreshRecorder(results: [RefreshResult.fixture(state: .rateLimited(until: until)), .fixture()])
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        let durations = await sleeper.requestedDurations
        XCTAssertEqual(durations.first!, until.timeIntervalSinceNow, accuracy: 2)
        await sleeper.releaseNextSleep()
        let calls = await recorder.callCount
        XCTAssertEqual(calls, 2)
        await scheduler.stop()
    }

    func testFailuresUseBoundedExponentialBackoff() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder(errors: [AppError.transport(URLError(.timedOut)), AppError.transport(URLError(.timedOut))])
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await sleeper.releaseNextSleep()
        await sleeper.releaseNextSleep()

        let durations = await sleeper.requestedDurations
        XCTAssertEqual(Array(durations.prefix(3)), [30, 10, 20])
        await scheduler.stop()
    }

    func testNoHeaderRateLimitUsesFullFallbackSequence() async {
        let sleeper = RecordingSleeper()
        let errors: [Error] = Array(repeating: AppError.rateLimited(retryAfter: nil), count: 6)
        let recorder = RefreshRecorder(errors: errors)
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        for _ in 0..<6 {
            await sleeper.releaseNextSleep()
            await Task.yield()
        }

        let durations = await sleeper.requestedDurations
        XCTAssertEqual(Array(durations.dropFirst().prefix(6)), [10, 20, 40, 80, 160, 300])
        await scheduler.stop()
    }

    func testStopInFlightThenRestartIgnoresStaleCompletion() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder(blocked: true)
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        async let firstStart = scheduler.start()
        await recorder.waitUntilStarted()
        await scheduler.stop()
        await recorder.release()
        await firstStart

        let restarted = RefreshRecorder()
        let replacement = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: restarted.run)
        await replacement.start()
        let calls = await restarted.callCount
        XCTAssertEqual(calls, 1)
        await replacement.stop()
    }

    func testStopCancelsLoopAndPendingSleep() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder()
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await scheduler.stop()
        await sleeper.releaseAll()
        await Task.yield()

        let calls = await recorder.callCount
        XCTAssertEqual(calls, 1)
    }

    func testSystemWakeRefreshesImmediately() async {
        let sleeper = RecordingSleeper()
        let recorder = RefreshRecorder()
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: recorder.run)

        await scheduler.start()
        await scheduler.systemDidWake()

        let calls = await recorder.callCount
        XCTAssertEqual(calls, 2)
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
