import Foundation

struct PersistedSnapshotState: Codable, Equatable, Sendable {
    static let maximumRecentUsageIDs = 500

    var cachedSnapshot: BalanceSnapshot?
    var watermarkTime: Date?
    private(set) var recentUsageIDs: [Int64]

    static var empty: Self { Self(cachedSnapshot: nil, watermarkTime: nil, recentUsageIDs: []) }

    init(cachedSnapshot: BalanceSnapshot? = nil, watermarkTime: Date? = nil, recentUsageIDs: [Int64] = []) {
        self.cachedSnapshot = cachedSnapshot
        self.watermarkTime = watermarkTime
        self.recentUsageIDs = Self.boundedUniqueIDs(recentUsageIDs)
    }

    mutating func recordUsageIDs(_ ids: [Int64]) {
        var ordered = recentUsageIDs
        for id in ids {
            ordered.removeAll { $0 == id }
            ordered.append(id)
        }
        recentUsageIDs = Self.boundedUniqueIDs(ordered)
    }

    private static func boundedUniqueIDs(_ ids: [Int64]) -> [Int64] {
        var seen = Set<Int64>()
        let unique = ids.filter { seen.insert($0).inserted }
        return Array(unique.suffix(maximumRecentUsageIDs))
    }
}

protocol SnapshotStoreProtocol {
    func load() throws -> PersistedSnapshotState?
    func save(_ state: PersistedSnapshotState) throws
}

struct UserDefaultsSnapshotStore: SnapshotStoreProtocol {
    private let userDefaults: UserDefaults
    private let key = "LoeBalance.snapshotState"

    init(userDefaults: UserDefaults) { self.userDefaults = userDefaults }

    func load() throws -> PersistedSnapshotState? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(PersistedSnapshotState.self, from: data)
    }

    func save(_ state: PersistedSnapshotState) throws {
        userDefaults.set(try JSONEncoder().encode(state), forKey: key)
    }
}
