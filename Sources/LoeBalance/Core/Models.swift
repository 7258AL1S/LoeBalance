import Foundation

enum BalanceAnimationEvent: Equatable, Sendable {
    case debit(Money)
    case credit(Money)
}

struct BalanceSnapshot: Codable, Equatable, Sendable {
    let balance: Money
    let todaySpend: Money?
    let todayRequests: Int?
    let updatedAt: Date
}

struct UsageRecord: Codable, Equatable, Identifiable, Sendable {
    let id: Int64
    let createdAt: Date
    let actualCost: Money
}

struct RefreshResult: Equatable, Sendable {
    let snapshot: BalanceSnapshot
    let events: [BalanceAnimationEvent]
    let connectionState: ConnectionState
}

enum ConnectionState: Equatable, Sendable {
    case online
    case offline
    case rateLimited(until: Date?)
    case loginRequired
    case invalidData
}

enum ShakeStrength: String, Codable, CaseIterable, Sendable {
    case off
    case weak
    case strong
}
