import Foundation
import XCTest
@testable import LoeBalance

final class PersistenceTests: XCTestCase {
    func testRefreshIntervalIsClampedToSupportedRange() {
        XCTAssertEqual(AppPreferences(refreshInterval: 1).refreshInterval, 10)
        XCTAssertEqual(AppPreferences(refreshInterval: 30).refreshInterval, 30)
        XCTAssertEqual(AppPreferences(refreshInterval: 9999).refreshInterval, 3600)
    }

    func testRefreshIntervalSetterAndLegacyDecodeAreClamped() throws {
        var preferences = AppPreferences()
        preferences.setRefreshInterval(1)
        XCTAssertEqual(preferences.refreshInterval, 10)
        preferences.setRefreshInterval(9999)
        XCTAssertEqual(preferences.refreshInterval, 3600)

        let low = Data(#"{"refreshInterval":1,"shakeStrength":"weak","showsDesktopCard":true,"launchAtLogin":false,"desktopFrame":null}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: low).refreshInterval, 10)
        let high = Data(#"{"refreshInterval":9999,"shakeStrength":"weak","showsDesktopCard":true,"launchAtLogin":false,"desktopFrame":null}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: high).refreshInterval, 3600)
    }

    func testPreferencesRoundTripUsesInjectedSuite() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LoeBalance.PersistenceTests.preferences"))
        defaults.removePersistentDomain(forName: "LoeBalance.PersistenceTests.preferences")
        let store = UserDefaultsPreferencesStore(userDefaults: defaults)
        let frame = CGRect(x: 1, y: 2, width: 300, height: 400)
        let expected = AppPreferences(refreshInterval: 42, shakeStrength: .strong, showsDesktopCard: false, launchAtLogin: true, desktopFrame: frame)
        try store.save(expected)
        XCTAssertEqual(try store.load(), expected)
    }

    func testSnapshotRoundTripAndUsageOrdering() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LoeBalance.PersistenceTests.snapshot"))
        defaults.removePersistentDomain(forName: "LoeBalance.PersistenceTests.snapshot")
        let store = UserDefaultsSnapshotStore(userDefaults: defaults)
        let snapshot = BalanceSnapshot(balance: Money(decimal: 12.34), todaySpend: Money(decimal: 1.23), todayRequests: 7, updatedAt: .fixtureNow)
        var expected = PersistedSnapshotState(cachedSnapshot: snapshot, watermarkTime: .fixtureNow.addingTimeInterval(10), recentUsageIDs: [1, 2])
        expected.recordUsageIDs([2, 3, 1])
        try store.save(expected)
        XCTAssertEqual(try store.load(), expected)
        XCTAssertEqual(expected.recentUsageIDs, [2, 3, 1])
    }

    func testRecentUsageIDsRemainBounded() {
        var state = PersistedSnapshotState.empty
        state.recordUsageIDs((1...700).map(Int64.init))
        XCTAssertEqual(state.recentUsageIDs.count, 500)
        XCTAssertEqual(state.recentUsageIDs.first, 201)
        XCTAssertTrue(state.recentUsageIDs.contains(700))
    }
}
