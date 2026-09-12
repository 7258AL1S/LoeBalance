import Foundation

struct AppPreferences: Codable, Equatable, Sendable {
    private(set) var refreshInterval: TimeInterval
    var shakeStrength: ShakeStrength
    var showsDesktopCard: Bool
    var launchAtLogin: Bool
    var desktopFrame: CGRect?

    init(refreshInterval: TimeInterval = 30, shakeStrength: ShakeStrength = .weak,
         showsDesktopCard: Bool = true, launchAtLogin: Bool = false, desktopFrame: CGRect? = nil) {
        self.refreshInterval = min(3600, max(1, refreshInterval))
        self.shakeStrength = shakeStrength
        self.showsDesktopCard = showsDesktopCard
        self.launchAtLogin = launchAtLogin
        self.desktopFrame = desktopFrame
    }

    mutating func setRefreshInterval(_ value: TimeInterval) {
        refreshInterval = min(3600, max(1, value))
    }

    private enum CodingKeys: String, CodingKey {
        case refreshInterval, shakeStrength, showsDesktopCard, launchAtLogin, desktopFrame
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            refreshInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .refreshInterval) ?? 30,
            shakeStrength: try container.decodeIfPresent(ShakeStrength.self, forKey: .shakeStrength) ?? .weak,
            showsDesktopCard: try container.decodeIfPresent(Bool.self, forKey: .showsDesktopCard) ?? true,
            launchAtLogin: try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false,
            desktopFrame: try container.decodeIfPresent(PersistedRect.self, forKey: .desktopFrame)?.cgRect
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.refreshInterval == rhs.refreshInterval && lhs.shakeStrength == rhs.shakeStrength &&
        lhs.showsDesktopCard == rhs.showsDesktopCard && lhs.launchAtLogin == rhs.launchAtLogin &&
        lhs.desktopFrame.map(PersistedRect.init) == rhs.desktopFrame.map(PersistedRect.init)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(refreshInterval, forKey: .refreshInterval)
        try container.encode(shakeStrength, forKey: .shakeStrength)
        try container.encode(showsDesktopCard, forKey: .showsDesktopCard)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(desktopFrame.map(PersistedRect.init), forKey: .desktopFrame)
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
