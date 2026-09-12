import Foundation
import XCTest
@testable import LoeBalance

final class BalanceServiceTests: XCTestCase {
    func testFirstRefreshEstablishesBaselineWithoutEvents() async throws {
        let store = TestSnapshotStore()
        let api = ServiceTestAPI(user: CurrentUserDTO(id: 42, email: nil, username: nil, balance: Money(decimal: 12)), usage: [.fixture(id: 1, cost: 0.50)])
        let service = try await makeService(api: api, store: store)

        let result = try await service.refresh()

        XCTAssertEqual(result.events, [])
        XCTAssertEqual(store.value?.cachedSnapshot?.balance, Money(decimal: 12))
        XCTAssertEqual(store.value?.cachedSnapshot?.todaySpend, Money(decimal: 1))
        XCTAssertEqual(store.value?.cachedSnapshot?.todayRequests, 3)
        XCTAssertEqual(store.value?.recentUsageIDs, [1])
    }

    func testLaterRefreshFiltersKnownUsageIDsAndProducesOnlyNewEvents() async throws {
        let initial = BalanceSnapshot(balance: Money(decimal: 10), todaySpend: nil, todayRequests: nil, updatedAt: .fixtureNow)
        let store = TestSnapshotStore(PersistedSnapshotState(cachedSnapshot: initial, recentUsageIDs: [1]))
        let api = ServiceTestAPI(user: CurrentUserDTO(id: 42, email: nil, username: nil, balance: Money(decimal: 9.50)), usage: [.fixture(id: 1, cost: 0.50), .fixture(id: 2, cost: 0.50, secondsAfterBaseline: 1)])
        let service = try await makeService(api: api, store: store)

        let result = try await service.refresh()

        XCTAssertEqual(result.events, [.debit(Money(decimal: 0.50))])
    }

    func testUsageFailureDoesNotAdvanceStateThenNextSuccessReconcilesOnce() async throws {
        let initial = BalanceSnapshot(balance: Money(decimal: 10), todaySpend: nil, todayRequests: nil, updatedAt: .fixtureNow)
        let initialState = PersistedSnapshotState(
            cachedSnapshot: initial,
            watermarkTime: .fixtureNow,
            recentUsageIDs: [7]
        )
        let store = TestSnapshotStore(initialState)
        let api = ServiceTestAPI(
            user: CurrentUserDTO(id: 42, email: nil, username: nil, balance: Money(decimal: 9)),
            usageResults: [
                .failure(.invalidResponse),
                .success([.fixture(id: 8, cost: 1, secondsAfterBaseline: 1)])
            ]
        )
        let service = try await makeService(api: api, store: store)

        let failed = try await service.refresh()

        XCTAssertEqual(failed.snapshot.balance, Money(decimal: 9))
        XCTAssertEqual(failed.events, [])
        XCTAssertEqual(store.value, initialState)

        let recovered = try await service.refresh()

        XCTAssertEqual(recovered.events, [.debit(Money(decimal: 1))])
        XCTAssertEqual(store.value?.cachedSnapshot?.balance, Money(decimal: 9))
        XCTAssertEqual(store.value?.watermarkTime, Date.fixtureNow.addingTimeInterval(1))
        XCTAssertEqual(store.value?.recentUsageIDs, [7, 8])
    }

    func testSecondaryFailuresKeepAuthoritativeBalanceAndNilSecondaryValues() async throws {
        let store = TestSnapshotStore()
        let api = ServiceTestAPI(
            user: CurrentUserDTO(id: 42, email: nil, username: nil, balance: Money(decimal: 12)),
            dashboardError: .invalidResponse,
            usageError: .invalidResponse
        )
        let service = try await makeService(api: api, store: store)

        let result = try await service.refresh()

        XCTAssertEqual(result.snapshot.balance, Money(decimal: 12))
        XCTAssertNil(result.snapshot.todaySpend)
        XCTAssertNil(result.snapshot.todayRequests)
    }

    func testBalanceDashboardAndUsageRequestsStartConcurrently() async throws {
        let arrivals = AsyncArrivalCounter()
        let gate = AsyncGate()
        let api = ServiceTestAPI(arrivals: arrivals, gate: gate)
        let service = try await makeService(api: api, store: TestSnapshotStore())

        async let refresh = service.refresh()
        await arrivals.wait(until: 3)
        await gate.open()
        _ = try await refresh

        let arrivalCount = await arrivals.arrivalCount
        XCTAssertEqual(arrivalCount, 3)
    }

    func testConcurrentRefreshesShareOneFetch() async throws {
        let gate = AsyncGate()
        let api = ServiceTestAPI(gate: gate)
        let service = try await makeService(api: api, store: TestSnapshotStore())

        async let first = service.refresh()
        while await api.totalFetchCount < 3 { await Task.yield() }
        async let second = service.refresh()
        await gate.open()
        _ = try await (first, second)

        let fetchCount = await api.totalFetchCount
        XCTAssertEqual(fetchCount, 3)
    }

    func testCurrentUserDecodeFailureDoesNotPersistState() async throws {
        let store = TestSnapshotStore()
        let api = ServiceTestAPI(userError: .invalidResponse)
        let service = try await makeService(api: api, store: store)

        XCTAssertThrowsError(try await service.refresh())
        XCTAssertEqual(store.saveCount, 0)
    }

    private func makeService(api: ServiceTestAPI, store: TestSnapshotStore) async throws -> BalanceService {
        let credentials = InMemoryCredentialStore(StoredCredential(refreshToken: "refresh-token", userID: 42))
        let auth = AuthManager(api: api, credentials: credentials)
        try await auth.restoreSession()
        return BalanceService(api: api, auth: auth, snapshotStore: store, now: { .fixtureNow })
    }
}

private actor ServiceTestAPI: APIClientProtocol {
    let user: CurrentUserDTO
    let userError: AppError?
    let dashboard: DashboardStatsDTO
    let usage: [UsageRecord]
    private var usageResults: [Result<[UsageRecord], AppError>]
    let dashboardError: AppError?
    let usageError: AppError?
    let arrivals: AsyncArrivalCounter?
    let gate: AsyncGate?
    private(set) var totalFetchCount = 0

    init(
        user: CurrentUserDTO = CurrentUserDTO(id: 42, email: nil, username: nil, balance: Money(decimal: 10)),
        userError: AppError? = nil,
        dashboard: DashboardStatsDTO = DashboardStatsDTO(todayRequests: 3, todayActualCost: Money(decimal: 1)),
        usage: [UsageRecord] = [],
        usageResults: [Result<[UsageRecord], AppError>]? = nil,
        dashboardError: AppError? = nil,
        usageError: AppError? = nil,
        arrivals: AsyncArrivalCounter? = nil,
        gate: AsyncGate? = nil
    ) {
        self.user = user
        self.userError = userError
        self.dashboard = dashboard
        self.usage = usage
        self.usageResults = usageResults ?? []
        if self.usageResults.isEmpty, let usageError {
            self.usageResults = [.failure(usageError)]
        }
        self.dashboardError = dashboardError
        self.usageError = usageError
        self.arrivals = arrivals
        self.gate = gate
    }

    func login(email: String, password: String) async throws -> AuthSession { .fixture }
    func refresh(refreshToken: String) async throws -> AuthSession { .fixture }

    func fetchCurrentUser(accessToken: String) async throws -> CurrentUserDTO {
        await recordFetch()
        if let userError { throw userError }
        return user
    }

    func fetchDashboardStats(accessToken: String) async throws -> DashboardStatsDTO {
        await recordFetch()
        if let dashboardError { throw dashboardError }
        return dashboard
    }

    func fetchUsage(accessToken: String, pageSize: Int) async throws -> [UsageRecord] {
        await recordFetch()
        if !usageResults.isEmpty {
            return try usageResults.removeFirst().get()
        }
        return usage
    }

    private func recordFetch() async {
        totalFetchCount += 1
        await arrivals?.arrive()
        await gate?.wait()
    }
}

private final class TestSnapshotStore: SnapshotStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var state: PersistedSnapshotState?
    private var saves = 0

    init(_ state: PersistedSnapshotState? = nil) { self.state = state }

    var value: PersistedSnapshotState? {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return saves
    }

    func load() throws -> PersistedSnapshotState? { value }

    func save(_ state: PersistedSnapshotState) throws {
        lock.lock()
        self.state = state
        saves += 1
        lock.unlock()
    }
}

private extension UsageRecord {
    static func fixture(id: Int64, cost: Decimal, secondsAfterBaseline: TimeInterval = 0) -> Self {
        Self(id: id, createdAt: Date.fixtureNow.addingTimeInterval(secondsAfterBaseline), actualCost: Money(decimal: cost))
    }
}
