import AppKit
import Foundation
import XCTest
@testable import LoeBalance

@MainActor
final class DesktopCardControllerTests: XCTestCase {
    func testPanelUsesDesktopLayerPolicyAndFixedContentSize() {
        let store = DesktopCardPreferencesStore()
        let controller = DesktopCardController(preferencesStore: store)
        let panel = controller.panel

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.isMovableByWindowBackground)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertGreaterThan(panel.level.rawValue, Int(CGWindowLevelForKey(.desktopWindow)))
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.normal.rawValue)
        XCTAssertEqual(panel.contentView?.bounds.size, DesktopCardView.fixedSize)
        XCTAssertEqual(controller.cardView.layer?.cornerRadius, 8)
        XCTAssertEqual(panel.title, "Sub2API 余额")
        XCTAssertEqual(panel.accessibilityTitle(), "Sub2API 余额")
    }

    func testPresentUpdatesAllFieldsWithoutChangingPanelFrame() {
        let store = DesktopCardPreferencesStore()
        let controller = DesktopCardController(preferencesStore: store)
        controller.panel.setFrame(NSRect(x: 120, y: 240, width: 326, height: 218), display: false)
        let frameBeforePresentation = controller.panel.frame
        let snapshot = BalanceSnapshot(
            balance: Money(decimal: 19.08),
            todaySpend: Money(decimal: 2.34),
            todayRequests: 17,
            updatedAt: .fixtureNow
        )

        controller.present(snapshot: snapshot, connection: .offline)

        let title = controller.cardView.titleLabel.stringValue
        let balance = controller.cardView.balanceLabel.stringValue
        let spend = controller.cardView.todaySpendLabel.stringValue
        let requests = controller.cardView.todayRequestsLabel.stringValue
        let update = controller.cardView.lastUpdateLabel.stringValue
        let connection = controller.cardView.connectionIndicator.accessibilityValue() as? String
        XCTAssertEqual(title, "Sub2API 余额")
        XCTAssertEqual(balance, "$19.08")
        XCTAssertEqual(spend, "$2.34")
        XCTAssertEqual(requests, "17")
        XCTAssertTrue(update.contains("Updated"))
        XCTAssertEqual(connection, "Offline")
        XCTAssertEqual(controller.panel.frame, frameBeforePresentation)
    }

    func testRestoredFrameIsClampedAndWindowMovePersistsFrame() throws {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1_000, height: 700)
        let store = DesktopCardPreferencesStore(
            preferences: AppPreferences(desktopFrame: CGRect(x: 900, y: 650, width: 326, height: 218))
        )
        let controller = DesktopCardController(
            preferencesStore: store,
            visibleFrameProvider: { _ in visibleFrame }
        )

        XCTAssertEqual(controller.panel.frame, CGRect(x: 674, y: 482, width: 326, height: 218))

        let movedFrame = CGRect(x: 200, y: 300, width: 326, height: 218)
        controller.panel.setFrame(movedFrame, display: false)
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: controller.panel))

        let saved = try XCTUnwrap(store.savedPreferences?.desktopFrame)
        XCTAssertEqual(saved, movedFrame)
    }

    func testPresetFramesUseVisibleWorkAreaCorners() {
        let visibleFrame = CGRect(x: 100, y: 80, width: 1_000, height: 700)

        XCTAssertEqual(
            DesktopCardController.frame(for: .topLeft, in: visibleFrame),
            CGRect(x: 124, y: 538, width: 326, height: 218)
        )
        XCTAssertEqual(
            DesktopCardController.frame(for: .bottomLeft, in: visibleFrame),
            CGRect(x: 124, y: 104, width: 326, height: 218)
        )
        XCTAssertEqual(
            DesktopCardController.frame(for: .topRight, in: visibleFrame),
            CGRect(x: 750, y: 538, width: 326, height: 218)
        )
        XCTAssertEqual(
            DesktopCardController.frame(for: .bottomRight, in: visibleFrame),
            CGRect(x: 750, y: 104, width: 326, height: 218)
        )
    }

    func testPresetPositionDisablesDraggingAndCustomPositionEnablesIt() {
        let store = DesktopCardPreferencesStore(preferences: AppPreferences(cardPosition: .topLeft))
        let controller = DesktopCardController(
            preferencesStore: store,
            visibleFrameProvider: { _ in CGRect(x: 0, y: 0, width: 1_000, height: 700) }
        )

        XCTAssertFalse(controller.panel.isMovableByWindowBackground)

        controller.setCardPosition(.custom)

        XCTAssertTrue(controller.panel.isMovableByWindowBackground)
        XCTAssertEqual(store.savedPreferences?.cardPosition, .custom)
    }

    func testLayerMappingProvidesThreeDistinctLevels() {
        let levels = CardLayer.allCases.map(DesktopCardController.windowLevel(for:))

        XCTAssertEqual(levels.count, 3)
        XCTAssertEqual(Set(levels.map(\.rawValue)).count, 3)
        XCTAssertLessThan(levels[0].rawValue, levels[1].rawValue)
        XCTAssertLessThan(levels[1].rawValue, levels[2].rawValue)
    }

    func testClampingPreservesTopEdgeInsideUndersizedVisibleFrame() {
        let visibleFrame = CGRect(x: 50, y: 60, width: 200, height: 100)

        let clamped = DesktopCardController.clampedFrame(
            CGRect(x: 900, y: 650, width: 640, height: 480),
            to: visibleFrame
        )

        XCTAssertEqual(clamped, CGRect(x: 50, y: -58, width: 326, height: 218))
        XCTAssertEqual(clamped.maxY, visibleFrame.maxY)
    }

    func testRestoredFrameWithoutVisibleScreenStillUsesFixedCardSize() {
        let store = DesktopCardPreferencesStore(
            preferences: AppPreferences(desktopFrame: CGRect(x: 120, y: 240, width: 640, height: 480))
        )

        let controller = DesktopCardController(
            preferencesStore: store,
            visibleFrameProvider: { _ in nil }
        )

        XCTAssertEqual(controller.panel.frame, CGRect(x: 120, y: 240, width: 326, height: 218))
    }

    func testLongBalanceAndLoginStatusFitWithoutMovingDamageStream() throws {
        let controller = DesktopCardController(preferencesStore: DesktopCardPreferencesStore())
        controller.cardView.layoutSubtreeIfNeeded()
        let balanceFrame = controller.cardView.balanceLabel.frame
        let damageFrame = controller.cardView.damageStreamView.frame
        let snapshot = BalanceSnapshot(
            balance: Money(decimal: 1_000),
            todaySpend: nil,
            todayRequests: nil,
            updatedAt: .fixtureNow
        )

        controller.present(snapshot: snapshot, connection: .loginRequired)
        controller.cardView.layoutSubtreeIfNeeded()

        let balanceLabel = controller.cardView.balanceLabel
        let statusLabel = try XCTUnwrap(textField(in: controller.cardView, matching: "Sign in required"))
        XCTAssertLessThanOrEqual(renderedTextWidth(of: balanceLabel), balanceLabel.bounds.width)
        XCTAssertLessThanOrEqual(renderedTextWidth(of: statusLabel), statusLabel.bounds.width)
        XCTAssertEqual(balanceLabel.frame, balanceFrame)
        XCTAssertEqual(controller.cardView.damageStreamView.frame, damageFrame)
        XCTAssertGreaterThanOrEqual(
            controller.cardView.damageStreamView.frame.minX,
            balanceLabel.frame.maxX
        )
    }

    func testLargeBalancesFitAtReadableMonospacedSizeWithoutMovingDamageStream() throws {
        let controller = DesktopCardController(preferencesStore: DesktopCardPreferencesStore())
        controller.cardView.layoutSubtreeIfNeeded()
        let balanceFrame = controller.cardView.balanceLabel.frame
        let damageFrame = controller.cardView.damageStreamView.frame
        let cases = [
            ("1000000", "$1,000,000.00"),
            ("987654321.09", "$987,654,321.09")
        ]

        for (decimalText, expectedCurrencyText) in cases {
            let decimal = try XCTUnwrap(Decimal(string: decimalText, locale: Locale(identifier: "en_US_POSIX")))
            controller.present(
                snapshot: BalanceSnapshot(
                    balance: Money(decimal: decimal),
                    todaySpend: nil,
                    todayRequests: nil,
                    updatedAt: .fixtureNow
                ),
                connection: .online
            )
            controller.cardView.layoutSubtreeIfNeeded()

            let label = controller.cardView.balanceLabel
            let font = try XCTUnwrap(label.font)
            XCTAssertEqual(label.stringValue, expectedCurrencyText)
            XCTAssertLessThanOrEqual(renderedTextWidth(of: label), label.bounds.width)
            XCTAssertGreaterThanOrEqual(font.pointSize, 14)
            XCTAssertEqual(renderedWidth(of: "1111", font: font), renderedWidth(of: "8888", font: font), accuracy: 0.01)
            XCTAssertEqual(label.frame, balanceFrame)
            XCTAssertEqual(controller.cardView.damageStreamView.frame, damageFrame)
        }
    }

    func testPlayPlacesDamageBesideBalanceAndHonorsShakeStrengthAndReduceMotion() {
        let store = DesktopCardPreferencesStore()
        let controller = DesktopCardController(preferencesStore: store)
        let event = BalanceAnimationEvent.debit(.cents(25))

        controller.play(events: [event], shake: .strong, reduceMotion: false)

        let streamFrame = controller.cardView.damageStreamView.frame
        let balanceFrame = controller.cardView.balanceLabel.frame
        let streamPositionAnimation = controller.cardView.damageStreamView.layer?.sublayers?.first?.animation(forKey: "damage.position")
        let shakeAnimation = controller.cardView.layer?.animation(forKey: "desktop-card.shake")
        XCTAssertGreaterThan(balanceFrame.width, 0)
        XCTAssertGreaterThan(streamFrame.width, 0)
        XCTAssertGreaterThanOrEqual(streamFrame.minX, balanceFrame.maxX)
        XCTAssertNotNil(streamPositionAnimation)
        XCTAssertNotNil(shakeAnimation)

        controller.play(events: [event], shake: .off, reduceMotion: false)
        let offShakeAnimation = controller.cardView.layer?.animation(forKey: "desktop-card.shake")
        XCTAssertNil(offShakeAnimation)

        controller.play(events: [event], shake: .strong, reduceMotion: true)
        let reducedShakeAnimation = controller.cardView.layer?.animation(forKey: "desktop-card.shake")
        XCTAssertNil(reducedShakeAnimation)
    }

    private func textField(in view: NSView, matching text: String) -> NSTextField? {
        if let field = view as? NSTextField, field.stringValue == text { return field }
        return view.subviews.lazy.compactMap { textField(in: $0, matching: text) }.first
    }

    private func renderedTextWidth(of label: NSTextField) -> CGFloat {
        label.attributedStringValue.size().width
    }

    private func renderedWidth(of text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

private final class DesktopCardPreferencesStore: PreferencesStoreProtocol {
    private var preferences: AppPreferences?

    init(preferences: AppPreferences? = nil) {
        self.preferences = preferences
    }

    var savedPreferences: AppPreferences? { preferences }

    func load() throws -> AppPreferences? { preferences }

    func save(_ preferences: AppPreferences) throws {
        self.preferences = preferences
    }
}
