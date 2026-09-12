import AppKit
import QuartzCore

private final class DamageAnimationCleanupDelegate: NSObject, CAAnimationDelegate {
    weak var owner: DamageStreamView?
    weak var textLayer: CATextLayer?

    init(owner: DamageStreamView, textLayer: CATextLayer) {
        self.owner = owner
        self.textLayer = textLayer
    }

    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        let owner = owner
        let textLayerID = textLayer.map(ObjectIdentifier.init)
        DispatchQueue.main.async {
            owner?.removeCompletedLayer(withID: textLayerID)
        }
    }
}

@MainActor
final class DamageStreamView: NSView {
    static let fixedSize = NSSize(width: 92, height: 42)

    private let presentationSize: NSSize
    private let currentTime: () -> CFTimeInterval
    private var cleanupDelegates: [ObjectIdentifier: DamageAnimationCleanupDelegate] = [:]

    override var intrinsicContentSize: NSSize {
        presentationSize
    }

    override init(frame frameRect: NSRect) {
        presentationSize = Self.fixedSize
        currentTime = { CACurrentMediaTime() }
        super.init(frame: frameRect)
        configure()
    }

    init(frame frameRect: NSRect, currentTime: @escaping () -> CFTimeInterval) {
        presentationSize = Self.fixedSize
        self.currentTime = currentTime
        super.init(frame: frameRect)
        configure()
    }

    init(frame frameRect: NSRect, presentationSize: NSSize) {
        self.presentationSize = presentationSize
        currentTime = { CACurrentMediaTime() }
        super.init(frame: frameRect)
        configure()
    }

    init(
        frame frameRect: NSRect,
        presentationSize: NSSize,
        currentTime: @escaping () -> CFTimeInterval
    ) {
        self.presentationSize = presentationSize
        self.currentTime = currentTime
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        presentationSize = Self.fixedSize
        currentTime = { CACurrentMediaTime() }
        super.init(coder: coder)
        configure()
    }

    func play(plans: [DamageMotionPlan], anchor: CGPoint) {
        guard !plans.isEmpty else { return }
        guard let hostLayer = layer else { return }
        let beginTime = hostLayer.convertTime(currentTime(), from: nil)

        for plan in plans {
            let textLayer = makeTextLayer(for: plan, anchor: anchor)
            hostLayer.addSublayer(textLayer)
            addAnimations(for: plan, to: textLayer, anchor: anchor, beginTime: beginTime)
        }
    }

    private func configure() {
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    private func makeTextLayer(for plan: DamageMotionPlan, anchor: CGPoint) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        textLayer.alignmentMode = .center
        textLayer.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        textLayer.fontSize = 13
        textLayer.foregroundColor = color(for: plan).cgColor
        textLayer.string = Self.label(for: plan.event)
        textLayer.opacity = 0
        let textWidth = bounds.width
        textLayer.frame = CGRect(
            x: bounds.midX - textWidth / 2,
            y: anchor.y - 10,
            width: textWidth,
            height: 20
        )
        return textLayer
    }

    private func addAnimations(
        for plan: DamageMotionPlan,
        to textLayer: CATextLayer,
        anchor: CGPoint,
        beginTime: CFTimeInterval
    ) {
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = [
            NSValue(point: anchor),
            NSValue(point: CGPoint(x: anchor.x + plan.startX, y: anchor.y + plan.rise * 0.08)),
            NSValue(point: CGPoint(x: anchor.x + plan.midX, y: anchor.y + plan.rise * 0.55)),
            NSValue(point: CGPoint(x: anchor.x + plan.endX, y: anchor.y + plan.rise))
        ]
        position.keyTimes = [0, 0.15, 0.55, 1]
        position.calculationMode = .cubic

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.12, 0.72, 1]

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.86, 1.0, 1.0, 0.96]
        scale.keyTimes = [0, 0.14, 0.72, 1]

        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = [
            0,
            radians(plan.startRotationDegrees),
            radians(plan.endRotationDegrees),
            radians(plan.endRotationDegrees)
        ]
        rotation.keyTimes = [0, 0.15, 0.72, 1]

        for animation in [position, opacity, scale, rotation] {
            animation.beginTime = beginTime + plan.launchDelay
            animation.duration = plan.duration
            animation.fillMode = .backwards
            animation.isRemovedOnCompletion = true
        }

        let cleanupDelegate = DamageAnimationCleanupDelegate(owner: self, textLayer: textLayer)
        cleanupDelegates[ObjectIdentifier(textLayer)] = cleanupDelegate
        position.delegate = cleanupDelegate

        textLayer.add(position, forKey: "damage.position")
        textLayer.add(opacity, forKey: "damage.opacity")
        textLayer.add(scale, forKey: "damage.scale")
        textLayer.add(rotation, forKey: "damage.rotation")
    }

    fileprivate func removeCompletedLayer(withID textLayerID: ObjectIdentifier?) {
        guard let textLayerID,
              let cleanupDelegate = cleanupDelegates.removeValue(forKey: textLayerID),
              let textLayer = cleanupDelegate.textLayer else {
            return
        }
        if textLayer.superlayer === layer {
            textLayer.removeFromSuperlayer()
        }
    }

    static func label(for event: BalanceAnimationEvent) -> String {
        switch event {
        case let .debit(amount):
            "-\(amount.magnitude.currencyText)"
        case let .credit(amount):
            "+\(amount.magnitude.currencyText)"
        }
    }

    private func color(for plan: DamageMotionPlan) -> NSColor {
        switch plan.color {
        case .red:
            .systemRed
        case .green:
            .systemGreen
        }
    }

    private func radians(_ degrees: CGFloat) -> CGFloat {
        degrees * .pi / 180
    }
}
