import Foundation

enum DamageSurface: Sendable {
    case desktop
    case menuBar
}

protocol MotionRandomizing: Sendable {
    func value(in range: ClosedRange<CGFloat>) -> CGFloat
}

struct SystemMotionRandom: MotionRandomizing {
    func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        .random(in: range)
    }
}

enum DamageMotionStyle: Sendable, Equatable {
    case debit
    case credit
}

enum DamageMotionColor: Sendable, Equatable {
    case red
    case green
}

struct DamageMotionPlan: Equatable, Sendable {
    let event: BalanceAnimationEvent
    let launchDelay: TimeInterval
    let duration: TimeInterval
    let startX: CGFloat
    let midX: CGFloat
    let endX: CGFloat
    let rise: CGFloat
    let startRotationDegrees: CGFloat
    let endRotationDegrees: CGFloat
    let shakeStrength: ShakeStrength?

    var style: DamageMotionStyle {
        switch event {
        case .debit:
            .debit
        case .credit:
            .credit
        }
    }

    var color: DamageMotionColor {
        switch style {
        case .debit:
            .red
        case .credit:
            .green
        }
    }
}

struct DamageAnimationPlanner: Sendable {
    private let random: any MotionRandomizing

    init(random: any MotionRandomizing = SystemMotionRandom()) {
        self.random = random
    }

    func plan(
        events: [BalanceAnimationEvent],
        surface: DamageSurface,
        shake: ShakeStrength = .off,
        reduceMotion: Bool
    ) -> [DamageMotionPlan] {
        var plans: [DamageMotionPlan] = []
        plans.reserveCapacity(events.count)

        var inDebitBurst = false
        for (index, event) in events.enumerated() {
            let isDebit: Bool
            switch event {
            case .debit:
                isDebit = true
            case .credit:
                isDebit = false
            }

            let startsDebitBurst = isDebit && !inDebitBurst
            inDebitBurst = isDebit

            let ranges = MotionRanges(surface: surface, reduceMotion: reduceMotion)
            let shakeStrength: ShakeStrength? = {
                guard surface == .desktop, !reduceMotion, startsDebitBurst, shake != .off else {
                    return nil
                }
                return shake
            }()

            plans.append(
                DamageMotionPlan(
                    event: event,
                    launchDelay: TimeInterval(index) * 0.23,
                    duration: ranges.duration,
                    startX: random.value(in: ranges.startX),
                    midX: random.value(in: ranges.midX),
                    endX: random.value(in: ranges.endX),
                    rise: random.value(in: ranges.rise),
                    startRotationDegrees: random.value(in: ranges.rotation),
                    endRotationDegrees: random.value(in: ranges.rotation),
                    shakeStrength: shakeStrength
                )
            )
        }

        return plans
    }
}

private struct MotionRanges {
    let startX: ClosedRange<CGFloat>
    let midX: ClosedRange<CGFloat>
    let endX: ClosedRange<CGFloat>
    let rise: ClosedRange<CGFloat>
    let rotation: ClosedRange<CGFloat>
    let duration: TimeInterval

    init(surface: DamageSurface, reduceMotion: Bool) {
        switch surface {
        case .desktop:
            startX = -5...5
            midX = -9...9
            endX = -13...13
            rise = reduceMotion ? 43...50 : 86...100
            rotation = -8...8
        case .menuBar:
            startX = -3...3
            midX = -5...5
            endX = -7...7
            rise = reduceMotion ? 24...28 : 47...55
            rotation = -4...4
        }

        duration = reduceMotion ? 0.48 : 0.82
    }
}
