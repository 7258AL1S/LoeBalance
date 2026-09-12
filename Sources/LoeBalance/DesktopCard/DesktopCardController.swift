import AppKit
import QuartzCore

@MainActor
protocol DesktopCardPresenting: AnyObject {
    func present(snapshot: BalanceSnapshot, connection: ConnectionState)
    func play(events: [BalanceAnimationEvent], shake: ShakeStrength, reduceMotion: Bool)
    func setVisible(_ visible: Bool)
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
        if let preferredFrame {
            initialFrame = visibleFrame.map { Self.clampedFrame(preferredFrame, to: $0) } ?? preferredFrame
        } else if let visibleFrame {
            initialFrame = Self.defaultFrame(in: visibleFrame)
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

    func windowDidMove(_ notification: Notification) {
        guard let movedPanel = notification.object as? NSPanel, movedPanel === panel else { return }
        preferences.desktopFrame = panel.frame
        try? preferencesStore.save(preferences)
    }

    static func clampedFrame(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let width = Self.panelContentSize.width
        let height = Self.panelContentSize.height
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - height)
        let x = min(max(frame.minX, visibleFrame.minX), maxX)
        let y = min(max(frame.minY, visibleFrame.minY), maxY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.contentView = cardView
        panel.contentView?.frame = NSRect(origin: .zero, size: Self.panelContentSize)
        panel.contentView?.autoresizingMask = [.width, .height]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.level = Self.desktopCardLevel
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

    private static let desktopCardLevel: NSWindow.Level = {
        let desktopLevel = Int(CGWindowLevelForKey(.desktopWindow))
        let normalLevel = NSWindow.Level.normal.rawValue
        return NSWindow.Level(rawValue: min(normalLevel - 1, desktopLevel + 1))
    }()

    private static func defaultFrame(in visibleFrame: CGRect) -> NSRect {
        let size = Self.panelContentSize
        return NSRect(
            x: max(visibleFrame.minX, visibleFrame.maxX - size.width - 24),
            y: max(visibleFrame.minY, visibleFrame.maxY - size.height - 24),
            width: size.width,
            height: size.height
        )
    }

    private static func visibleFrame(for preferredFrame: CGRect) -> CGRect? {
        let screen = NSScreen.screens.first {
            $0.frame.intersects(preferredFrame) || $0.visibleFrame.intersects(preferredFrame)
        } ?? NSScreen.main
        return screen?.visibleFrame
    }
}
