import AppKit

struct StatusBarCommands {
    let refreshNow: @MainActor () -> Void
    let toggleDesktopCard: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    let logout: @MainActor () -> Void
    let quit: @MainActor () -> Void
}

@MainActor
protocol StatusBarPresenting: AnyObject {
    func present(snapshot: BalanceSnapshot, connection: ConnectionState, showsDesktopCard: Bool)
    func play(events: [BalanceAnimationEvent], reduceMotion: Bool)
    func setDesktopCardVisible(_ visible: Bool)
}

@MainActor
final class StatusBarController: NSObject, StatusBarPresenting {
    static let statusItemLength = StatusBarContentView.fixedSize.width

    let statusItem: NSStatusItem
    let contentView: StatusBarContentView
    let menu: NSMenu

    private let commands: StatusBarCommands
    private let balanceSummaryItem: NSMenuItem
    private let connectionSummaryItem: NSMenuItem
    private let refreshItem: NSMenuItem
    private let desktopCardItem: NSMenuItem
    private let settingsItem: NSMenuItem
    private let logoutItem: NSMenuItem
    private let quitItem: NSMenuItem
    private let dateFormatter: DateFormatter

    init(statusItem: NSStatusItem, commands: StatusBarCommands) {
        self.statusItem = statusItem
        self.contentView = StatusBarContentView(frame: NSRect(origin: .zero, size: StatusBarContentView.fixedSize))
        self.menu = NSMenu()
        self.commands = commands
        self.balanceSummaryItem = NSMenuItem(title: "Balance: --", action: nil, keyEquivalent: "")
        self.connectionSummaryItem = NSMenuItem(title: "Online · Updated --", action: nil, keyEquivalent: "")
        self.refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow(_:)), keyEquivalent: "r")
        self.desktopCardItem = NSMenuItem(title: "Show Desktop Card", action: #selector(toggleDesktopCard(_:)), keyEquivalent: "d")
        self.settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings(_:)), keyEquivalent: ",")
        self.logoutItem = NSMenuItem(title: "Log Out", action: #selector(logout(_:)), keyEquivalent: "")
        self.quitItem = NSMenuItem(title: "Quit LoeBalance", action: #selector(quit(_:)), keyEquivalent: "q")
        self.dateFormatter = DateFormatter()
        super.init()
        configure()
    }

    convenience init(commands: StatusBarCommands) {
        self.init(
            statusItem: NSStatusBar.system.statusItem(withLength: StatusBarContentView.fixedSize.width),
            commands: commands
        )
    }

    func present(snapshot: BalanceSnapshot, connection: ConnectionState, showsDesktopCard: Bool) {
        contentView.present(balance: snapshot.balance, connection: connection)
        balanceSummaryItem.title = "Balance: \(snapshot.balance.currencyText)"
        connectionSummaryItem.title = "\(Self.connectionTitle(connection)) · \(dateFormatter.string(from: snapshot.updatedAt))"
        desktopCardItem.title = showsDesktopCard ? "Hide Desktop Card" : "Show Desktop Card"

        let authenticated = connection != .loginRequired
        refreshItem.isEnabled = authenticated
        desktopCardItem.isEnabled = authenticated
        logoutItem.isEnabled = authenticated
    }

    func play(events: [BalanceAnimationEvent], reduceMotion: Bool) {
        guard !events.isEmpty else { return }
        contentView.layoutSubtreeIfNeeded()
        let plans = DamageAnimationPlanner().plan(
            events: events,
            surface: .menuBar,
            shake: .off,
            reduceMotion: reduceMotion
        )
        contentView.damageStreamView.play(plans: plans, anchor: contentView.damageAnchor())
    }

    func setDesktopCardVisible(_ visible: Bool) {
        desktopCardItem.title = visible ? "Hide Desktop Card" : "Show Desktop Card"
    }

    @objc func refreshNow(_ sender: Any?) {
        commands.refreshNow()
    }

    @objc func toggleDesktopCard(_ sender: Any?) {
        commands.toggleDesktopCard()
    }

    @objc func openSettings(_ sender: Any?) {
        commands.openSettings()
    }

    @objc func logout(_ sender: Any?) {
        commands.logout()
    }

    @objc func quit(_ sender: Any?) {
        commands.quit()
    }

    private func configure() {
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "'Updated' HH:mm:ss"

        for item in [balanceSummaryItem, connectionSummaryItem] {
            item.isEnabled = false
        }
        balanceSummaryItem.identifier = NSUserInterfaceItemIdentifier("balance-summary")
        connectionSummaryItem.identifier = NSUserInterfaceItemIdentifier("connection-summary")
        refreshItem.identifier = NSUserInterfaceItemIdentifier("refresh-now")
        desktopCardItem.identifier = NSUserInterfaceItemIdentifier("toggle-desktop-card")
        settingsItem.identifier = NSUserInterfaceItemIdentifier("settings")
        logoutItem.identifier = NSUserInterfaceItemIdentifier("logout")
        quitItem.identifier = NSUserInterfaceItemIdentifier("quit")

        for item in [refreshItem, desktopCardItem, settingsItem, logoutItem, quitItem] {
            item.target = self
        }
        menu.autoenablesItems = false
        menu.addItem(balanceSummaryItem)
        menu.addItem(connectionSummaryItem)
        menu.addItem(.separator())
        menu.addItem(refreshItem)
        menu.addItem(desktopCardItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(logoutItem)
        menu.addItem(quitItem)

        statusItem.length = Self.statusItemLength
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = nil
        button.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: button.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        statusItem.menu = menu
        button.layoutSubtreeIfNeeded()
        contentView.layoutSubtreeIfNeeded()
    }

    private static func connectionTitle(_ connection: ConnectionState) -> String {
        switch connection {
        case .online:
            "Online"
        case .offline:
            "Offline"
        case .rateLimited:
            "Rate limited"
        case .loginRequired:
            "Sign in required"
        case .invalidData:
            "Invalid data"
        }
    }
}
