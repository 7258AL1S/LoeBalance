import Foundation
import XCTest
@testable import LoeBalance

final class PersistenceTests: XCTestCase {
    func testRefreshIntervalIsClampedToSupportedRange() {
        XCTAssertEqual(AppPreferences(refreshInterval: 0).refreshInterval, 1)
        XCTAssertEqual(AppPreferences(refreshInterval: 1).refreshInterval, 1)
        XCTAssertEqual(AppPreferences(refreshInterval: 30).refreshInterval, 30)
        XCTAssertEqual(AppPreferences(refreshInterval: 9999).refreshInterval, 3600)
    }

    func testRefreshIntervalSetterAndLegacyDecodeAreClamped() throws {
        var preferences = AppPreferences()
        preferences.setRefreshInterval(0)
        XCTAssertEqual(preferences.refreshInterval, 1)
        preferences.setRefreshInterval(9999)
        XCTAssertEqual(preferences.refreshInterval, 3600)

        let low = Data(#"{"refreshInterval":0,"shakeStrength":"weak","showsDesktopCard":true,"launchAtLogin":false,"desktopFrame":null}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: low).refreshInterval, 1)
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

    func testCardPositionAndLayerRoundTrip() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LoeBalance.PersistenceTests.cardOptions"))
        defaults.removePersistentDomain(forName: "LoeBalance.PersistenceTests.cardOptions")
        let store = UserDefaultsPreferencesStore(userDefaults: defaults)
        let expected = AppPreferences(
            shakeStrength: .strong,
            cardPosition: .custom,
            cardLayer: .aboveApplications
        )

        try store.save(expected)

        XCTAssertEqual(try store.load(), expected)
    }

    func testLegacyPreferencesWithFrameMigrateToCustomPosition() throws {
        let data = Data(#"{"refreshInterval":30,"shakeStrength":"weak","showsDesktopCard":true,"launchAtLogin":false,"desktopFrame":{"x":10,"y":20,"width":326,"height":218}}"#.utf8)

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(preferences.cardPosition, .custom)
        XCTAssertEqual(preferences.cardLayer, .betweenDesktopIconsAndApplications)
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

    func testSnapshotDecodeNormalizesDuplicateAndOversizedUsageIDs() throws {
        let ids = ([1, 2, 1] + Array(3...501)).map(String.init).joined(separator: ",")
        let json = Data("{\"cachedSnapshot\":null,\"watermarkTime\":null,\"recentUsageIDs\":[\(ids)]}".utf8)

        let state = try JSONDecoder().decode(PersistedSnapshotState.self, from: json)

        XCTAssertEqual(state.recentUsageIDs.count, 500)
        XCTAssertEqual(state.recentUsageIDs.first, 2)
        XCTAssertEqual(state.recentUsageIDs.last, 501)
        XCTAssertEqual(state.recentUsageIDs, Array(2...501).map(Int64.init))
    }
}
