import Foundation

protocol AsyncSleeping: Sendable {
    func sleep(for seconds: TimeInterval) async throws
}

struct TaskSleeper: AsyncSleeping {
    func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

protocol RefreshScheduling: Actor {
    func start() async
    func stop()
    func updateInterval(_ seconds: TimeInterval)
    func refreshNow() async
    func networkBecameAvailable() async
    func systemDidWake() async
}

actor RefreshScheduler: RefreshScheduling {
    private let sleeper: any AsyncSleeping
    private let refresh: @Sendable () async throws -> RefreshResult
    private var interval: TimeInterval
    private var loopTask: Task<Void, Never>?
    private var inFlightRefresh: Task<RefreshResult, Error>?
    private var isOnline = true
    private var backoffStep = 0
    private var retryAfter: Date?
    private var started = false

    init(
        interval: TimeInterval,
        sleeper: any AsyncSleeping = TaskSleeper(),
        refresh: @escaping @Sendable () async throws -> RefreshResult
    ) {
        self.interval = Self.clamp(interval)
        self.sleeper = sleeper
        self.refresh = refresh
    }

    func start() async {
        guard !started else { return }
        started = true
        await refreshNow()
        guard started else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func stop() {
        started = false
        loopTask?.cancel()
        loopTask = nil
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
    }

    func updateInterval(_ seconds: TimeInterval) {
        interval = Self.clamp(seconds)
    }

    func refreshNow() async {
        guard started || loopTask == nil else { return }
        await performRefresh()
    }

    func networkBecameAvailable() async {
        isOnline = true
        guard started else { return }
        await refreshNow()
    }

    func systemDidWake() async {
        guard started else { return }
        await refreshNow()
    }

    private func runLoop() async {
        while !Task.isCancelled && started {
            do {
                try await sleeper.sleep(for: nextDelay())
            } catch {
                return
            }
            guard !Task.isCancelled, started else { return }
            if isOnline { await performRefresh() }
        }
    }

    private func nextDelay() -> TimeInterval {
        guard isOnline else { return interval }
        if let retryAfter {
            self.retryAfter = nil
            return max(0, retryAfter.timeIntervalSinceNow)
        }
        return backoffStep == 0 ? interval : [10, 20, 40, 80, 160, 300][min(backoffStep - 1, 5)]
    }

    private func performRefresh() async {
        if let inFlightRefresh {
            _ = try? await inFlightRefresh.value
            return
        }

        let task = Task { [refresh] in try await refresh() }
        inFlightRefresh = task
        do {
            let result = try await task.value
            switch result.connectionState {
            case .offline:
                isOnline = false
            case .rateLimited(let until):
                isOnline = true
                backoffStep = 0
                if let until, until > Date() {
                    retryAfter = until
                }
            default:
                isOnline = true
                backoffStep = 0
            }
        } catch AppError.rateLimited(let retryAfter) {
            isOnline = true
            if let retryAfter, retryAfter > Date() {
                self.retryAfter = retryAfter
                backoffStep = 0
            } else {
                backoffStep = min(backoffStep + 1, 6)
            }
        } catch AppError.transport, AppError.serverStatus {
            backoffStep = min(backoffStep + 1, 6)
        } catch {
            backoffStep = min(backoffStep + 1, 6)
        }
        inFlightRefresh = nil
    }

    private static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        min(3600, max(10, seconds))
    }
}
