import AppKit

@MainActor
final class DesktopCardView: NSView {
    static let fixedSize = NSSize(width: 326, height: 218)

    let titleLabel = NSTextField(labelWithString: "LoeBalance")
    let balanceLabel = NSTextField(labelWithString: "--")
    let todaySpendLabel = NSTextField(labelWithString: "--")
    let todayRequestsLabel = NSTextField(labelWithString: "--")
    let connectionIndicator = NSView()
    let lastUpdateLabel = NSTextField(labelWithString: "Updated --")
    let damageStreamView = DamageStreamView(frame: .zero)

    private let visualEffectView = NSVisualEffectView()
    private let todaySpendTitleLabel = NSTextField(labelWithString: "Today's spend")
    private let todayRequestsTitleLabel = NSTextField(labelWithString: "Today's requests")
    private let connectionStatusLabel = NSTextField(labelWithString: "Online")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func present(snapshot: BalanceSnapshot, connection: ConnectionState) {
        balanceLabel.stringValue = snapshot.balance.currencyText
        todaySpendLabel.stringValue = snapshot.todaySpend?.currencyText ?? "--"
        todayRequestsLabel.stringValue = snapshot.todayRequests.map(String.init) ?? "--"
        lastUpdateLabel.stringValue = Self.updateFormatter.string(from: snapshot.updatedAt)
        applyConnection(connection)
    }

    func damageAnchor() -> CGPoint {
        CGPoint(x: damageStreamView.bounds.midX, y: damageStreamView.bounds.midY)
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        configureTitleLabel()
        configureNumericLabel(balanceLabel, fontSize: 30, weight: .semibold)
        configureNumericLabel(todaySpendLabel)
        configureNumericLabel(todayRequestsLabel)
        configureSecondaryLabel(todaySpendTitleLabel)
        configureSecondaryLabel(todayRequestsTitleLabel)
        configureSecondaryLabel(lastUpdateLabel)
        configureSecondaryLabel(connectionStatusLabel)

        connectionIndicator.wantsLayer = true
        connectionIndicator.layer?.cornerRadius = 5
        connectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        connectionIndicator.setAccessibilityRole(.valueIndicator)
        connectionIndicator.setAccessibilityLabel("Connection")

        addSubview(visualEffectView)
        visualEffectView.addSubview(titleLabel)
        visualEffectView.addSubview(balanceLabel)
        visualEffectView.addSubview(damageStreamView)
        visualEffectView.addSubview(todaySpendTitleLabel)
        visualEffectView.addSubview(todaySpendLabel)
        visualEffectView.addSubview(todayRequestsTitleLabel)
        visualEffectView.addSubview(todayRequestsLabel)
        visualEffectView.addSubview(connectionIndicator)
        visualEffectView.addSubview(connectionStatusLabel)
        visualEffectView.addSubview(lastUpdateLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.fixedSize.width),
            heightAnchor.constraint(equalToConstant: Self.fixedSize.height),
            visualEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            visualEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            visualEffectView.topAnchor.constraint(equalTo: topAnchor),
            visualEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 18),
            titleLabel.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 17),
            titleLabel.widthAnchor.constraint(equalToConstant: 150),
            titleLabel.heightAnchor.constraint(equalToConstant: 22),

            balanceLabel.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 18),
            balanceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 9),
            balanceLabel.widthAnchor.constraint(equalToConstant: 132),
            balanceLabel.heightAnchor.constraint(equalToConstant: 40),

            damageStreamView.leadingAnchor.constraint(equalTo: balanceLabel.trailingAnchor, constant: 4),
            damageStreamView.centerYAnchor.constraint(equalTo: balanceLabel.centerYAnchor),
            damageStreamView.widthAnchor.constraint(equalToConstant: DamageStreamView.fixedSize.width),
            damageStreamView.heightAnchor.constraint(equalToConstant: DamageStreamView.fixedSize.height),

            todaySpendTitleLabel.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 18),
            todaySpendTitleLabel.topAnchor.constraint(equalTo: balanceLabel.bottomAnchor, constant: 13),
            todaySpendTitleLabel.widthAnchor.constraint(equalToConstant: 130),
            todaySpendTitleLabel.heightAnchor.constraint(equalToConstant: 18),
            todaySpendLabel.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -18),
            todaySpendLabel.centerYAnchor.constraint(equalTo: todaySpendTitleLabel.centerYAnchor),
            todaySpendLabel.widthAnchor.constraint(equalToConstant: 100),
            todaySpendLabel.heightAnchor.constraint(equalToConstant: 18),

            todayRequestsTitleLabel.leadingAnchor.constraint(equalTo: todaySpendTitleLabel.leadingAnchor),
            todayRequestsTitleLabel.topAnchor.constraint(equalTo: todaySpendTitleLabel.bottomAnchor, constant: 5),
            todayRequestsTitleLabel.widthAnchor.constraint(equalTo: todaySpendTitleLabel.widthAnchor),
            todayRequestsTitleLabel.heightAnchor.constraint(equalTo: todaySpendTitleLabel.heightAnchor),
            todayRequestsLabel.trailingAnchor.constraint(equalTo: todaySpendLabel.trailingAnchor),
            todayRequestsLabel.centerYAnchor.constraint(equalTo: todayRequestsTitleLabel.centerYAnchor),
            todayRequestsLabel.widthAnchor.constraint(equalTo: todaySpendLabel.widthAnchor),
            todayRequestsLabel.heightAnchor.constraint(equalTo: todaySpendLabel.heightAnchor),

            connectionIndicator.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 18),
            connectionIndicator.topAnchor.constraint(equalTo: todayRequestsTitleLabel.bottomAnchor, constant: 16),
            connectionIndicator.widthAnchor.constraint(equalToConstant: 10),
            connectionIndicator.heightAnchor.constraint(equalToConstant: 10),
            connectionStatusLabel.leadingAnchor.constraint(equalTo: connectionIndicator.trailingAnchor, constant: 6),
            connectionStatusLabel.centerYAnchor.constraint(equalTo: connectionIndicator.centerYAnchor),
            connectionStatusLabel.widthAnchor.constraint(equalToConstant: 78),
            connectionStatusLabel.heightAnchor.constraint(equalToConstant: 18),
            lastUpdateLabel.leadingAnchor.constraint(equalTo: connectionStatusLabel.trailingAnchor, constant: 6),
            lastUpdateLabel.centerYAnchor.constraint(equalTo: connectionStatusLabel.centerYAnchor),
            lastUpdateLabel.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -18),
            lastUpdateLabel.heightAnchor.constraint(equalToConstant: 18)
        ])

        applyConnection(.online)
    }

    private func configureTitleLabel() {
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left
        titleLabel.usesSingleLineMode = true
        titleLabel.lineBreakMode = .byClipping
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureNumericLabel(_ label: NSTextField, fontSize: CGFloat = 15, weight: NSFont.Weight = .medium) {
        label.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: weight)
        label.textColor = .labelColor
        label.alignment = .right
        label.usesSingleLineMode = true
        label.lineBreakMode = .byClipping
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureSecondaryLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        label.usesSingleLineMode = true
        label.lineBreakMode = .byClipping
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.translatesAutoresizingMaskIntoConstraints = false
    }

    private func applyConnection(_ connection: ConnectionState) {
        let description: String
        let color: NSColor
        switch connection {
        case .online:
            description = "Online"
            color = .systemGreen
        case .offline:
            description = "Offline"
            color = .systemRed
        case .rateLimited:
            description = "Rate limited"
            color = .systemOrange
        case .loginRequired:
            description = "Sign in required"
            color = .systemOrange
        case .invalidData:
            description = "Invalid data"
            color = .systemRed
        }

        connectionStatusLabel.stringValue = description
        connectionIndicator.layer?.backgroundColor = color.cgColor
        connectionIndicator.setAccessibilityValue(description)
    }

    private static let updateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "'Updated' HH:mm:ss"
        return formatter
    }()
}
