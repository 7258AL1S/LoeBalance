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

enum CardPositionPreset: String, Codable, CaseIterable, Sendable {
    case topLeft
    case bottomLeft
    case topRight
    case bottomRight
    case custom

    var title: String {
        switch self {
        case .topLeft: "左上"
        case .bottomLeft: "左下"
        case .topRight: "右上"
        case .bottomRight: "右下"
        case .custom: "自定义"
        }
    }
}

enum CardLayer: String, Codable, CaseIterable, Sendable {
    case belowDesktopIcons
    case betweenDesktopIconsAndApplications
    case aboveApplications

    var title: String {
        switch self {
        case .belowDesktopIcons: "桌面图标下方"
        case .betweenDesktopIconsAndApplications: "图标与应用之间"
        case .aboveApplications: "所有应用上方"
        }
    }

    var sliderIndex: Double {
        Double(Self.allCases.firstIndex(of: self) ?? 0)
    }

    init(sliderIndex: Double) {
        let index = min(max(Int(sliderIndex.rounded()), 0), Self.allCases.count - 1)
        self = Self.allCases[index]
    }
}
