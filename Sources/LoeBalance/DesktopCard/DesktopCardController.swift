import AppKit
import QuartzCore

@MainActor
protocol DesktopCardPresenting: AnyObject {
    func present(snapshot: BalanceSnapshot, connection: ConnectionState)
    func play(events: [BalanceAnimationEvent], shake: ShakeStrength, reduceMotion: Bool)
    func setVisible(_ visible: Bool)
    func setCardPosition(_ position: CardPositionPreset)
    func setCardLayer(_ layer: CardLayer)
}

@MainActor
final class DesktopCardController: NSObject, DesktopCardPresenting, NSWindowDelegate {
    static let panelContentSize = DesktopCardView.fixedSize

    let panel: NSPanel
    let cardView: DesktopCardView

    private let preferencesStore: any PreferencesStoreProtocol
    private var preferences: AppPreferences
    private let visibleFrameProvider: @MainActor (CGRect) -> CGRect?

    init(
        preferencesStore: any PreferencesStoreProtocol = UserDefaultsPreferencesStore(userDefaults: .standard),
        visibleFrameProvider: @escaping @MainActor (CGRect) -> CGRect? = DesktopCardController.visibleFrame(for:)
    ) {
        self.preferencesStore = preferencesStore
        self.visibleFrameProvider = visibleFrameProvider
        self.preferences = (try? preferencesStore.load()) ?? AppPreferences()

        let preferredFrame = self.preferences.desktopFrame
        let visibleFrame = visibleFrameProvider(preferredFrame ?? .zero)
        let initialFrame: NSRect
        if self.preferences.cardPosition == .custom, let preferredFrame {
            initialFrame = visibleFrame.map { Self.clampedFrame(preferredFrame, to: $0) }
                ?? NSRect(origin: preferredFrame.origin, size: Self.panelContentSize)
        } else if let visibleFrame {
            initialFrame = Self.frame(for: self.preferences.cardPosition, in: visibleFrame)
        } else if let preferredFrame {
            initialFrame = NSRect(origin: preferredFrame.origin, size: Self.panelContentSize)
        } else {
            initialFrame = NSRect(origin: .zero, size: Self.panelContentSize)
        }

        self.panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.cardView = DesktopCardView(frame: NSRect(origin: .zero, size: Self.panelContentSize))
        super.init()
        configurePanel()
    }

    func present(snapshot: BalanceSnapshot, connection: ConnectionState) {
        cardView.present(snapshot: snapshot, connection: connection)
    }

    func play(events: [BalanceAnimationEvent], shake: ShakeStrength, reduceMotion: Bool) {
        cardView.layer?.removeAnimation(forKey: "desktop-card.shake")
        cardView.layoutSubtreeIfNeeded()
        let plans = DamageAnimationPlanner().plan(
            events: events,
            surface: .desktop,
            shake: shake,
            reduceMotion: reduceMotion
        )
        cardView.damageStreamView.play(plans: plans, anchor: cardView.damageAnchor())

        guard let strength = plans.compactMap(\.shakeStrength).first else { return }
        playShake(strength)
    }

    func setVisible(_ visible: Bool) {
        if visible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    func setCardPosition(_ position: CardPositionPreset) {
        preferences.cardPosition = position
        if position == .custom {
            preferences.desktopFrame = panel.frame
        } else if let visibleFrame = visibleFrameProvider(panel.frame) {
            let frame = Self.frame(for: position, in: visibleFrame)
            panel.setFrame(frame, display: true, animate: true)
            preferences.desktopFrame = frame
        }
        panel.isMovableByWindowBackground = position == .custom
        try? preferencesStore.save(preferences)
    }

    func setCardLayer(_ layer: CardLayer) {
        preferences.cardLayer = layer
        panel.level = Self.windowLevel(for: layer)
        try? preferencesStore.save(preferences)
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedPanel = notification.object as? NSPanel, movedPanel === panel else { return }
        guard preferences.cardPosition == .custom else { return }
        preferences.desktopFrame = panel.frame
        try? preferencesStore.save(preferences)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard preferences.cardPosition != .custom,
              let visibleFrame = visibleFrameProvider(panel.frame) else { return }
        panel.setFrame(Self.frame(for: preferences.cardPosition, in: visibleFrame), display: true, animate: false)
    }

    static func frame(for position: CardPositionPreset, in visibleFrame: CGRect) -> NSRect {
        let size = Self.panelContentSize
        let margin: CGFloat = 24
        let rawFrame: CGRect
        switch position {
        case .topLeft:
            rawFrame = CGRect(
                x: visibleFrame.minX + margin,
                y: visibleFrame.maxY - size.height - margin,
                width: size.width,
                height: size.height
            )
        case .bottomLeft:
            rawFrame = CGRect(
                x: visibleFrame.minX + margin,
                y: visibleFrame.minY + margin,
                width: size.width,
                height: size.height
            )
        case .topRight:
            rawFrame = CGRect(
                x: visibleFrame.maxX - size.width - margin,
                y: visibleFrame.maxY - size.height - margin,
                width: size.width,
                height: size.height
            )
        case .bottomRight, .custom:
            rawFrame = CGRect(
                x: visibleFrame.maxX - size.width - margin,
                y: visibleFrame.minY + margin,
                width: size.width,
                height: size.height
            )
        }
        return Self.clampedFrame(rawFrame, to: visibleFrame)
    }

    static func clampedFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = Self.panelContentSize.width
        let height = Self.panelContentSize.height
        let x: CGFloat
        if visibleFrame.width < width {
            x = visibleFrame.minX
        } else {
            x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        }

        let y: CGFloat
        if visibleFrame.height < height {
            y = visibleFrame.maxY - height
        } else {
            y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "Sub2API 余额"
        panel.setAccessibilityTitle("Sub2API 余额")
        panel.contentView = cardView
        panel.contentView?.frame = NSRect(origin: .zero, size: Self.panelContentSize)
        panel.contentView?.autoresizingMask = [.width, .height]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = preferences.cardPosition == .custom
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.level = Self.windowLevel(for: preferences.cardLayer)
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
    }

    private func playShake(_ strength: ShakeStrength) {
        guard let layer = cardView.layer else { return }
        let amplitude: CGFloat
        let duration: TimeInterval
        switch strength {
        case .weak:
            amplitude = 3
            duration = 0.24
        case .strong:
            amplitude = 6
            duration = 0.34
        case .off:
            return
        }

        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -amplitude, amplitude, -amplitude * 0.5, amplitude * 0.35, 0]
        animation.duration = duration
        animation.calculationMode = .cubic
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "desktop-card.shake")
    }

    static func windowLevel(for layer: CardLayer) -> NSWindow.Level {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        let normalLevel = NSWindow.Level.normal.rawValue
        let belowDesktopIcons = min(max(desktopLevel, desktopIconLevel - 1), normalLevel - 2)
        let betweenDesktopIconsAndApplications = min(
            max(belowDesktopIcons + 1, desktopIconLevel + 1),
            normalLevel - 1
        )

        switch layer {
        case .belowDesktopIcons:
            return NSWindow.Level(rawValue: belowDesktopIcons)
        case .betweenDesktopIconsAndApplications:
            return NSWindow.Level(rawValue: betweenDesktopIconsAndApplications)
        case .aboveApplications:
            return .floating
        }
    }

    private static func visibleFrame(for preferredFrame: CGRect) -> CGRect? {
        let screen = NSScreen.screens.first {
            $0.frame.intersects(preferredFrame) || $0.visibleFrame.intersects(preferredFrame)
        } ?? NSScreen.main
        return screen?.visibleFrame
    }
}
