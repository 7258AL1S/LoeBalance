import Foundation

struct AppPreferences: Codable, Equatable, Sendable {
    private(set) var refreshInterval: TimeInterval
    var shakeStrength: ShakeStrength
    var showsDesktopCard: Bool
    var launchAtLogin: Bool
    var desktopFrame: CGRect?
    var cardPosition: CardPositionPreset
    var cardLayer: CardLayer

    init(refreshInterval: TimeInterval = 30, shakeStrength: ShakeStrength = .weak,
         showsDesktopCard: Bool = true, launchAtLogin: Bool = false, desktopFrame: CGRect? = nil,
         cardPosition: CardPositionPreset? = nil,
         cardLayer: CardLayer = .betweenDesktopIconsAndApplications) {
        self.refreshInterval = min(3600, max(1, refreshInterval))
        self.shakeStrength = shakeStrength
        self.showsDesktopCard = showsDesktopCard
        self.launchAtLogin = launchAtLogin
        self.desktopFrame = desktopFrame
        self.cardPosition = cardPosition ?? (desktopFrame == nil ? .bottomRight : .custom)
        self.cardLayer = cardLayer
    }

    mutating func setRefreshInterval(_ value: TimeInterval) {
        refreshInterval = min(3600, max(1, value))
    }

    private enum CodingKeys: String, CodingKey {
        case refreshInterval, shakeStrength, showsDesktopCard, launchAtLogin, desktopFrame, cardPosition, cardLayer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let desktopFrame = try container.decodeIfPresent(PersistedRect.self, forKey: .desktopFrame)?.cgRect
        self.init(
            refreshInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 30,
            shakeStrength: try container.decodeIfPresent(ShakeStrength.self, forKey: .shakeStrength) ?? .weak,
            showsDesktopCard: try container.decodeIfPresent(Bool.self, forKey: .showsDesktopCard) ?? true,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            desktopFrame: desktopFrame,
            cardPosition: try container.decodeIfPresent(CardPositionPreset.self, forKey: .cardPosition)
                ?? (desktopFrame == nil ? .bottomRight : .custom),
            cardLayer: try container.decodeIfPresent(CardLayer.self, forKey: .cardLayer)
                ?? .betweenDesktopIconsAndApplications
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.refreshInterval == rhs.refreshInterval && lhs.shakeStrength == rhs.shakeStrength &&
        lhs.showsDesktopCard == rhs.showsDesktopCard && lhs.launchAtLogin == rhs.launchAtLogin &&
        lhs.desktopFrame.map(PersistedRect.init) == rhs.desktopFrame.map(PersistedRect.init) &&
        lhs.cardPosition == rhs.cardPosition && lhs.cardLayer == rhs.cardLayer
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(shakeStrength, forKey: .shakeStrength)
        try container.encode(showsDesktopCard, forKey: .showsDesktopCard)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(desktopFrame.map(PersistedRect.init), forKey: .desktopFrame)
        try container.encode(cardPosition, forKey: .cardPosition)
        try container.encode(cardLayer, forKey: .cardLayer)
    }
}

private struct PersistedRect: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x; y = rect.origin.y; width = rect.size.width; height = rect.size.height
    }

    var cgRect: CGRect { CGRect(origin: CGPoint(x: x, y: y), size: CGSize(width: width, height: height)) }
}

protocol PreferencesStoreProtocol {
    func load() throws -> AppPreferences?
    func save(_ preferences: AppPreferences) throws
}

struct UserDefaultsPreferencesStore: PreferencesStoreProtocol {
    private let userDefaults: UserDefaults
    private let key = "LoeBalance.preferences"

    init(userDefaults: UserDefaults) { self.userDefaults = userDefaults }

    func load() throws -> AppPreferences? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(AppPreferences.self, from: data)
    }

    func save(_ preferences: AppPreferences) throws {
        userDefaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}
