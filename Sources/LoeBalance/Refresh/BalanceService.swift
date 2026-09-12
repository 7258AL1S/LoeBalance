import Foundation

actor BalanceService {
    private let api: any APIClientProtocol
    private let auth: AuthManager
    private let snapshotStore: any SnapshotStoreProtocol
    private let reconciler: BalanceReconciler
    private let now: @Sendable () -> Date
    private let usagePageSize: Int

    private var refreshTask: Task<RefreshResult, Error>?

    init(
        api: any APIClientProtocol,
        auth: AuthManager,
        snapshotStore: any SnapshotStoreProtocol,
        reconciler: BalanceReconciler = BalanceReconciler(),
        now: @escaping @Sendable () -> Date = { Date() },
        usagePageSize: Int = 100
    ) {
        self.api = api
        self.auth = auth
        self.snapshotStore = snapshotStore
        self.reconciler = reconciler
        self.now = now
        self.usagePageSize = usagePageSize
    }

    func refresh() async throws -> RefreshResult {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { [self] in
            try await performRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    func clearBaseline() async throws {
        try snapshotStore.save(.empty)
    }

    private func performRefresh() async throws -> RefreshResult {
        let persisted = try snapshotStore.load() ?? .empty

        return try await auth.withAccessToken { [api, usagePageSize] token in
            async let currentUser = api.fetchCurrentUser(accessToken: token)
            async let dashboard = api.fetchDashboardStats(accessToken: token)
            async let usage = api.fetchUsage(accessToken: token, pageSize: usagePageSize)

            let user = try await currentUser
            let stats = try? await dashboard
            guard let records = try? await usage else {
                let snapshot = BalanceSnapshot(
                    balance: user.balance,
                    todaySpend: stats?.todayActualCost,
                    todayRequests: stats?.todayRequests,
                    updatedAt: now()
                )
                return RefreshResult(snapshot: snapshot, events: [], connectionState: .online)
            }
            let unseen = records
                .filter { !persisted.recentUsageIDs.contains($0.id) }
                .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }

            let snapshot = BalanceSnapshot(
                balance: user.balance,
                todaySpend: stats?.todayActualCost,
                todayRequests: stats?.todayRequests,
                updatedAt: now()
            )
            let events: [BalanceAnimationEvent]
            if let previous = persisted.cachedSnapshot {
                events = reconciler.reconcile(
                    previousBalance: previous.balance,
                    currentBalance: snapshot.balance,
                    unseenUsage: unseen
                )
            } else {
                events = []
            }

            var nextState = PersistedSnapshotState(
                cachedSnapshot: snapshot,
                watermarkTime: records.map(\.createdAt).max() ?? persisted.watermarkTime,
                recentUsageIDs: persisted.recentUsageIDs
            )
            nextState.recordUsageIDs(records.map(\.id))
            try snapshotStore.save(nextState)

            return RefreshResult(snapshot: snapshot, events: events, connectionState: .online)
        }
    }
}
