import AppKit

@MainActor
final class StatusBarContentView: NSView {
    static let fixedDamageWidth: CGFloat = 54
    static let damageSpacing: CGFloat = 2
    static let fixedHeight: CGFloat = 22
    static let maximumBalanceText = "$1,000,000.00"
    static let balanceFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    static let balanceWidth = ceil(
        (maximumBalanceText as NSString).size(withAttributes: [.font: balanceFont]).width
    )
    static let fixedSize = NSSize(
        width: 7 + 4 + balanceWidth + damageSpacing + fixedDamageWidth + 4,
        height: fixedHeight
    )

    let statusDot = NSView()
    let balanceLabel = NSTextField(labelWithString: "--")
    let damageStreamView = DamageStreamView(frame: .zero)

    var damageAreaWidth: CGFloat { Self.fixedDamageWidth }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        updateDamageMask()
    }

    func present(balance: Money, connection: ConnectionState) {
        balanceLabel.stringValue = balance.currencyText
        applyConnection(connection)
    }

    func damageAnchor() -> CGPoint {
        CGPoint(x: damageStreamView.bounds.midX, y: damageStreamView.bounds.midY)
    }

    private func configure() {
        frame.size = Self.fixedSize
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusDot.setAccessibilityRole(.valueIndicator)
        statusDot.setAccessibilityLabel("Connection")

        balanceLabel.font = Self.balanceFont
        balanceLabel.textColor = .labelColor
        balanceLabel.alignment = .right
        balanceLabel.usesSingleLineMode = true
        balanceLabel.lineBreakMode = .byClipping
        balanceLabel.isBezeled = false
        balanceLabel.drawsBackground = false
        balanceLabel.isEditable = false
        balanceLabel.isSelectable = false
        balanceLabel.translatesAutoresizingMaskIntoConstraints = false

        damageStreamView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(statusDot)
        addSubview(balanceLabel)
        addSubview(damageStreamView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.fixedSize.width),
            heightAnchor.constraint(equalToConstant: Self.fixedSize.height),
            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),
            balanceLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 4),
            balanceLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            balanceLabel.widthAnchor.constraint(equalToConstant: Self.balanceWidth),
            balanceLabel.heightAnchor.constraint(equalToConstant: 20),
            damageStreamView.leadingAnchor.constraint(equalTo: balanceLabel.trailingAnchor, constant: Self.damageSpacing),
            damageStreamView.centerYAnchor.constraint(equalTo: centerYAnchor),
            damageStreamView.widthAnchor.constraint(equalToConstant: Self.fixedDamageWidth),
            damageStreamView.heightAnchor.constraint(equalToConstant: DamageStreamView.fixedSize.height)
        ])

        applyConnection(.online)
    }

    private func updateDamageMask() {
        guard let layer = damageStreamView.layer else { return }
        let mask = layer.mask ?? CALayer()
        mask.backgroundColor = NSColor.white.cgColor
        mask.frame = CGRect(
            x: 0,
            y: -100,
            width: damageStreamView.bounds.width,
            height: damageStreamView.bounds.height + 200
        )
        layer.mask = mask
    }

    private func applyConnection(_ connection: ConnectionState) {
        let color: NSColor
        let description: String
        switch connection {
        case .online:
            color = .systemGreen
            description = "Online"
        case .offline:
            color = .systemRed
            description = "Offline"
        case .rateLimited:
            color = .systemOrange
            description = "Rate limited"
        case .loginRequired:
            color = .systemYellow
            description = "Sign in required"
        case .invalidData:
            color = .systemRed
            description = "Invalid data"
        }

        statusDot.layer?.backgroundColor = color.cgColor
        statusDot.setAccessibilityValue(description)
    }
}
