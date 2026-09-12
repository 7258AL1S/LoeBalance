import Foundation

enum AppError: Error { case rateLimited(Date?), transport, serverStatus(Int), other }
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
    func waitUntilRequested(_ count: Int) async {
        while requests.count < count { await Task.yield() }
    }
}

actor HarnessRefresh {
    private var results: [Result<RefreshResult, Error>]
    private(set) var calls = 0
    private var started = false
    private var gate: CheckedContinuation<Void, Never>?
    private var blockNext = false

    init(_ results: [Result<RefreshResult, Error>]) { self.results = results }

    func run() async throws -> RefreshResult {
        calls += 1
        started = true
        if let gate { self.gate = nil; gate.resume() }
        if blockNext {
            blockNext = false
            await withCheckedContinuation { gate = $0 }
        }
        if !results.isEmpty { return try results.removeFirst().get() }
        return RefreshResult(connectionState: .online)
    }

    func waitForStart() async { if !started { await withCheckedContinuation { gate = $0 } } }
    func waitUntilCalls(_ target: Int) async {
        while calls < target { await Task.yield() }
    }
    func blockNextRefresh() { blockNext = true }
    func release() { gate?.resume(); gate = nil }
}

@main
struct Task6Harness {
    static func main() async throws {
        let sleeper = HarnessSleeper()
        let refresh = HarnessRefresh([.success(RefreshResult(connectionState: .online))])
        let scheduler = RefreshScheduler(interval: 30, sleeper: sleeper, refresh: { try await refresh.run() })
        await scheduler.start()
        await refresh.blockNextRefresh()
        await sleeper.waitUntilRequested(1)
        await sleeper.release()
        await refresh.waitUntilCalls(2)
        let timerManual = Task { await scheduler.refreshNow() }
        await Task.yield()
        let blockedCalls = await refresh.calls
        assert(blockedCalls == 2, "timer/manual share blocked refresh")
        await refresh.release()
        await timerManual.value
        await scheduler.stop()

        let deadlineSleeper = HarnessSleeper()
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        let retryAt = fixedNow.addingTimeInterval(120)
        let deadlineRefresh = HarnessRefresh([
            .success(RefreshResult(connectionState: .online)),
            .success(RefreshResult(connectionState: .rateLimited(retryAt))),
            .success(RefreshResult(connectionState: .online))
        ])
        let deadlineScheduler = RefreshScheduler(interval: 30, sleeper: deadlineSleeper, now: { fixedNow }, refresh: { try await deadlineRefresh.run() })
        await deadlineScheduler.start()
        await deadlineSleeper.waitUntilRequested(1)
        let retrySleep = await deadlineSleeper.requests.first
        assert(retrySleep == 30, "normal interval before rate limit")
        await deadlineSleeper.release()
        await deadlineSleeper.waitUntilRequested(2)
        let retryDeadlineSleep = await deadlineSleeper.requests.last
        assert(retryDeadlineSleep == 120, "automatic polling honors Retry-After")
        let deadlineManual = Task { await deadlineScheduler.refreshNow() }
        await Task.yield()
        let deadlineCalls = await deadlineRefresh.calls
        assert(deadlineCalls == 2, "deadline manual joins scheduled refresh")
        await deadlineSleeper.release()
        await deadlineManual.value
        let finalCalls = await deadlineRefresh.calls
        assert(finalCalls == 3, "one refresh after shared deadline")
        await deadlineScheduler.stop()
        print("task-6 harness passed: timer/manual barrier, shared Retry-After deadline, single request")
    }
}

func assert(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAIL: \(message)") }
}
