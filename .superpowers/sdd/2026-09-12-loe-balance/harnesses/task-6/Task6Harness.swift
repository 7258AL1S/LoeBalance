import Foundation

enum AppError: Error { case rateLimited(Date?), transport, serverStatus(Int) }
enum ConnectionState { case online, offline, rateLimited(Date?) }
struct RefreshResult { let connectionState: ConnectionState }

actor HarnessSleeper: AsyncSleeping {
    private(set) var requests: [TimeInterval] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(for seconds: TimeInterval) async throws {
        requests.append(seconds)
        try Task.checkCancellation()
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiters.append($0) }
        } onCancel: {
            Task { await self.releaseAll() }
        }
        try Task.checkCancellation()
    }

    func release() { guard !waiters.isEmpty else { return }; waiters.removeFirst().resume() }
    func releaseAll() { let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
}

actor HarnessRefresh {
    private var results: [Result<RefreshResult, Error>]
    private(set) var calls = 0
    private var started = false
    private var gate: CheckedContinuation<Void, Never>?

    init(_ results: [Result<RefreshResult, Error>]) { self.results = results }

    func run() async throws -> RefreshResult {
        calls += 1
        started = true
        if let gate { self.gate = nil; gate.resume() }
        if !results.isEmpty { return try results.removeFirst().get() }
        return RefreshResult(connectionState: .online)
    }

    func waitForStart() async { if !started { await withCheckedContinuation { gate = $0 } } }
}

@main
struct Task6Harness {
    static func main() async throws {
        let sleeper = HarnessSleeper()
        let retryAt = Date().addingTimeInterval(0.01)
        let refresh = HarnessRefresh([
            .success(RefreshResult(connectionState: .online)),
            .failure(AppError.rateLimited(nil)),
            .failure(AppError.rateLimited(retryAt)),
            .success(RefreshResult(connectionState: .offline)),
            .success(RefreshResult(connectionState: .online))
        ])
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: refresh.run)

        await scheduler.start()
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            await sleeper.releaseAll()
        }
        let callsAfterStart = await refresh.calls
        assert(callsAfterStart == 1, "immediate start")
        await sleeper.release()
        await Task.yield()
        await scheduler.refreshNow()
        let callsBeforeTimer = await refresh.calls
        assert(callsBeforeTimer >= 2, "timer and manual remain serialized")
        await sleeper.release()
        await Task.yield()
        let requestCount = await sleeper.requests.count
        assert(requestCount >= 1, "injected timer")
        await scheduler.stop()

        await scheduler.start()
        await scheduler.systemDidWake()
        await scheduler.stop()
        let callsAfterWake = await refresh.calls
        assert(callsAfterWake >= 2, "restart and wake")
        print("task-6 harness passed: immediate, timer/manual sharing, retry-after/fallback, offline/restart/wake, injected sleep")
    }
}

func assert(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAIL: \(message)") }
}
