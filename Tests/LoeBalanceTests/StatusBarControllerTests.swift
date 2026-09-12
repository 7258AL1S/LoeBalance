import AppKit
import Foundation
import XCTest
@testable import LoeBalance

@MainActor
final class StatusBarControllerTests: XCTestCase {
    private var statusItems: [NSStatusItem] = []

    override func tearDown() {
        for item in statusItems {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItems.removeAll()
        super.tearDown()
    }

    func testContentReservesFixedDamageAreaAndDoesNotCaptureStatusItemClicks() {
        let view = StatusBarContentView(frame: .zero)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.bounds.size, StatusBarContentView.fixedSize)
        XCTAssertEqual(view.damageAreaWidth, 54)
        XCTAssertEqual(view.damageStreamView.frame.width, 54)
        XCTAssertEqual(view.damageStreamView.frame.minX, view.balanceLabel.frame.maxX + 2, accuracy: 0.01)
        XCTAssertNil(view.hitTest(CGPoint(x: 1, y: 1)))
    }

    func testPlayingDamageLeavesBalanceTextAndContentWidthStable() {
        let controller = makeController()
        let snapshot = BalanceSnapshot(
            balance: Money(decimal: 19.58),
            todaySpend: Money(decimal: 0.30),
            todayRequests: 11,
            updatedAt: .fixtureNow
        )

        controller.present(snapshot: snapshot, connection: .online, showsDesktopCard: true)
        let balanceBefore = controller.contentView.balanceLabel.stringValue
        let widthBefore = controller.contentView.bounds.width

        controller.play(events: [.debit(.cents(30)), .credit(.cents(5))], reduceMotion: false)

        XCTAssertEqual(controller.contentView.balanceLabel.stringValue, balanceBefore)
        XCTAssertEqual(controller.contentView.bounds.width, widthBefore)
        XCTAssertEqual(controller.statusItem.length, StatusBarContentView.fixedSize.width)
    }

    func testCommandsInvokeTheirClosures() {
        let recorder = CommandRecorder()
        let controller = makeController(commands: recorder.commands)

        controller.refreshNow(nil)
        controller.toggleDesktopCard(nil)
        controller.openSettings(nil)
        controller.logout(nil)
        controller.quit(nil)

        XCTAssertEqual(recorder.refreshCount, 1)
        XCTAssertEqual(recorder.toggleCount, 1)
        XCTAssertEqual(recorder.settingsCount, 1)
        XCTAssertEqual(recorder.logoutCount, 1)
        XCTAssertEqual(recorder.quitCount, 1)
    }

    func testConnectionStateUpdatesDotAndMenuStatusInPlace() {
        let controller = makeController()
        let snapshot = BalanceSnapshot(
            balance: Money(decimal: 19.58),
            todaySpend: nil,
            todayRequests: nil,
            updatedAt: .fixtureNow
        )
        let summaryItem = controller.menu.items[0]
        let statusItem = controller.menu.items[1]

        let cases: [(ConnectionState, String, NSColor, Bool)] = [
            (.online, "Online", .systemGreen, true),
            (.offline, "Offline", .systemRed, true),
            (.rateLimited(until: nil), "Rate limited", .systemOrange, true),
            (.loginRequired, "Sign in required", .systemYellow, false)
        ]

        for (state, title, color, enabled) in cases {
            controller.present(snapshot: snapshot, connection: state, showsDesktopCard: true)
            XCTAssertTrue(statusItem.title.contains(title))
            XCTAssertEqual(controller.contentView.statusDot.layer?.backgroundColor, color.cgColor)
            XCTAssertEqual(controller.menu.item(withTitle: "Refresh Now")?.isEnabled, enabled)
            XCTAssertFalse(summaryItem !== controller.menu.items[0])
            XCTAssertFalse(statusItem !== controller.menu.items[1])
        }
    }

    func testMenuOrderAndItemsRemainStableWhenSnapshotsRepeat() {
        let controller = makeController()
        let initialItems = controller.menu.items
        let snapshot = BalanceSnapshot(
            balance: Money(decimal: 1.25),
            todaySpend: Money(decimal: 0.30),
            todayRequests: 2,
            updatedAt: .fixtureNow
        )

        controller.present(snapshot: snapshot, connection: .online, showsDesktopCard: true)
        controller.present(snapshot: snapshot, connection: .online, showsDesktopCard: false)

        let titles = controller.menu.items.map { $0.isSeparatorItem ? "|" : $0.title }
        XCTAssertEqual(titles[0], "Balance: $1.25")
        XCTAssertTrue(titles[1].hasPrefix("Online · Updated "))
        XCTAssertEqual(
            Array(titles.dropFirst(2)),
            ["|", "Refresh Now", "Show Desktop Card", "Settings", "|", "Log Out", "Quit LoeBalance"]
        )
        XCTAssertEqual(controller.menu.items.count, initialItems.count)
        XCTAssertTrue(zip(initialItems, controller.menu.items).allSatisfy { $0 === $1 })
    }

    private func makeController(commands: StatusBarCommands? = nil) -> StatusBarController {
        let item = NSStatusBar.system.statusItem(withLength: StatusBarContentView.fixedSize.width)
        statusItems.append(item)
        return StatusBarController(
            statusItem: item,
            commands: commands ?? CommandRecorder().commands
        )
    }
}

@MainActor
private final class CommandRecorder {
    var refreshCount = 0
    var toggleCount = 0
    var settingsCount = 0
    var logoutCount = 0
    var quitCount = 0

    lazy var commands = StatusBarCommands(
        refreshNow: { self.refreshCount += 1 },
        toggleDesktopCard: { self.toggleCount += 1 },
        openSettings: { self.settingsCount += 1 },
        logout: { self.logoutCount += 1 },
        quit: { self.quitCount += 1 }
    )
}
