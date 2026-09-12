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
    func networkBecameUnavailable()
    func networkBecameAvailable() async
    func systemDidWake() async
}

actor RefreshScheduler: RefreshScheduling {
    private let sleeper: any AsyncSleeping
    private let refresh: @Sendable () async throws -> RefreshResult
    private let now: @Sendable () -> Date
    private var interval: TimeInterval
    private var loopTask: Task<Void, Never>?
    private var inFlightRefresh: (epoch: Int, task: Task<RefreshResult, Error>)?
    private var isOnline = true
    private var backoffStep = 0
    private var retryAfter: Date?
    private var started = false
    private var epoch = 0

    init(
        interval: TimeInterval,
        sleeper: any AsyncSleeping = TaskSleeper(),
        now: @escaping @Sendable () -> Date = { Date() },
        refresh: @escaping @Sendable () async throws -> RefreshResult
    ) {
        self.interval = Self.clamp(interval)
        self.sleeper = sleeper
        self.now = now
        self.refresh = refresh
    }

    func start() async {
        guard !started else { return }
        epoch += 1
        let currentEpoch = epoch
        started = true
        isOnline = true
        await refreshNow(epoch: currentEpoch)
        guard started, epoch == currentEpoch else { return }
        loopTask = Task { [weak self] in
            await self?.runLoop(epoch: currentEpoch)
        }
    }

    func stop() {
        epoch += 1
        started = false
        retryAfter = nil
        backoffStep = 0
        isOnline = true
        loopTask?.cancel()
        loopTask = nil
        inFlightRefresh?.task.cancel()
        inFlightRefresh = nil
    }

    func updateInterval(_ seconds: TimeInterval) {
        interval = Self.clamp(seconds)
    }

    func networkBecameUnavailable() {
        isOnline = false
        retryAfter = nil
    }

    func refreshNow() async {
        guard started || loopTask == nil else { return }
        await refreshNow(epoch: epoch)
    }

    func networkBecameAvailable() async {
        guard !isOnline else { return }
        isOnline = true
        guard started else { return }
        await refreshNow(epoch: epoch)
    }

    func systemDidWake() async {
        guard started else { return }
        await refreshNow(epoch: epoch)
    }

    private func refreshNow(epoch requestedEpoch: Int) async {
        guard started, requestedEpoch == epoch, isOnline else { return }
        await performRefresh(epoch: requestedEpoch, delay: retryDelay())
    }

    private func runLoop(epoch loopEpoch: Int) async {
        while !Task.isCancelled && started && epoch == loopEpoch {
            guard isOnline else {
                do { try await sleeper.sleep(for: interval) } catch { return }
                continue
            }
            await performRefresh(epoch: loopEpoch, delay: nextDelay())
        }
    }

    private func nextDelay() -> TimeInterval {
        guard isOnline else { return interval }
        if let retryAfter {
            return max(0, retryAfter.timeIntervalSince(now()))
        }
        return backoffStep == 0 ? interval : [10, 20, 40, 80, 160, 300][min(backoffStep - 1, 5)]
    }

    private func performRefresh(epoch requestedEpoch: Int, delay: TimeInterval) async {
        guard started, requestedEpoch == epoch, isOnline else { return }
        if let inFlightRefresh, inFlightRefresh.epoch == requestedEpoch {
            _ = try? await inFlightRefresh.task.value
            return
        }

        let task = Task { [sleeper, refresh] in
            if delay > 0 { try await sleeper.sleep(for: delay) }
            return try await refresh()
        }
        inFlightRefresh = (requestedEpoch, task)

        do {
            let result = try await task.value
            guard started, epoch == requestedEpoch else { return }
            retryAfter = nil
            switch result.connectionState {
            case .offline:
                isOnline = false
            case .rateLimited(let deadline):
                applyRateLimit(deadline)
            default:
                isOnline = true
                backoffStep = 0
            }
        } catch is CancellationError {
            return
        } catch let error as AppError {
            guard started, epoch == requestedEpoch else { return }
            switch error {
            case .rateLimited(let deadline):
                applyRateLimit(deadline)
            case .transport, .serverStatus:
                isOnline = true
                retryAfter = nil
                backoffStep = min(backoffStep + 1, 6)
            default:
                retryAfter = nil
                backoffStep = min(backoffStep + 1, 6)
            }
        } catch {
            guard started, epoch == requestedEpoch else { return }
            retryAfter = nil
            backoffStep = min(backoffStep + 1, 6)
        }

        guard inFlightRefresh?.epoch == requestedEpoch else { return }
        inFlightRefresh = nil
    }

    private func applyRateLimit(_ deadline: Date?) {
        if let deadline, deadline > now() {
            retryAfter = deadline
            backoffStep = 0
        } else {
            retryAfter = nil
            backoffStep = min(backoffStep + 1, 6)
        }
    }

    private func retryDelay() -> TimeInterval {
        guard let retryAfter else { return 0 }
        return max(0, retryAfter.timeIntervalSince(now()))
    }

    private static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        min(3600, max(10, seconds))
    }
}
