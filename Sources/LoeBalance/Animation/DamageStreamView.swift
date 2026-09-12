import AppKit
import QuartzCore

@MainActor
final class DamageStreamView: NSView {
    static let fixedSize = NSSize(width: 92, height: 42)

    override var intrinsicContentSize: NSSize {
        Self.fixedSize
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    func play(plans: [DamageMotionPlan], anchor: CGPoint) {
        guard !plans.isEmpty else { return }
        guard let hostLayer = layer else { return }

        for plan in plans {
            let textLayer = makeTextLayer(for: plan, anchor: anchor)
            hostLayer.addSublayer(textLayer)
            addAnimations(for: plan, to: textLayer, anchor: anchor)
            removeAfterAnimation(textLayer, duration: plan.duration + plan.launchDelay)
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
        textLayer.string = label(for: plan.event)
        textLayer.opacity = 0
        textLayer.frame = CGRect(x: anchor.x - 46, y: anchor.y - 10, width: 92, height: 20)
        return textLayer
    }

    private func addAnimations(for plan: DamageMotionPlan, to textLayer: CATextLayer, anchor: CGPoint) {
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

        let beginTime = textLayer.convertTime(CACurrentMediaTime(), from: nil) + plan.launchDelay
        for animation in [position, opacity, scale, rotation] {
            animation.beginTime = beginTime
            animation.duration = plan.duration
            animation.fillMode = .backwards
            animation.isRemovedOnCompletion = true
        }

        textLayer.add(position, forKey: "damage.position")
        textLayer.add(opacity, forKey: "damage.opacity")
        textLayer.add(scale, forKey: "damage.scale")
        textLayer.add(rotation, forKey: "damage.rotation")
    }

    private func removeAfterAnimation(_ textLayer: CATextLayer, duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak textLayer] in
            guard let self, let textLayer, textLayer.superlayer === self.layer else { return }
            textLayer.removeFromSuperlayer()
        }
    }

    private func label(for event: BalanceAnimationEvent) -> String {
        switch event {
        case let .debit(amount):
            "-\(amount.currencyText)"
        case let .credit(amount):
            "+\(amount.currencyText)"
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
