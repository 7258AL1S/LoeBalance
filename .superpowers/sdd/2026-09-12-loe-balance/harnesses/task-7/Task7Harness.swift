import AppKit
import Foundation

final class HarnessRandom: MotionRandomizing, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CGFloat]

    init(values: [CGFloat]) {
        self.values = values
    }

    func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        let normalized = values.isEmpty ? 0.5 : values.removeFirst()
        return range.lowerBound + (range.upperBound - range.lowerBound) * normalized
    }
}

@main
@MainActor
struct Task7Harness {
    static func main() {
        let deterministicValues = Array(repeating: CGFloat(0.5), count: 64)
        let planner = DamageAnimationPlanner(random: HarnessRandom(values: deterministicValues))
        let desktopPlans = planner.plan(
            events: [.debit(.cents(3)), .debit(.cents(6)), .debit(.cents(12))],
            surface: .desktop,
            shake: .strong,
            reduceMotion: false
        )

        assert(desktopPlans.map(\.launchDelay) == [0.00, 0.23, 0.46], "desktop cadence is 230 ms")
        assert(desktopPlans.allSatisfy { $0.duration == 0.82 }, "normal duration is 820 ms")
        assert(desktopPlans.allSatisfy { (-13...13).contains(Int($0.endX.rounded())) }, "desktop X range")
        assert(desktopPlans.allSatisfy { (-8...8).contains(Int($0.endRotationDegrees.rounded())) }, "desktop rotation range")

        let seededFirst = DamageAnimationPlanner(random: HarnessRandom(values: [0, 1, 0.5, 1, 0, 1])).plan(
            events: [.debit(.cents(3))],
            surface: .desktop,
            reduceMotion: false
        )[0]
        let seededSecond = DamageAnimationPlanner(random: HarnessRandom(values: [0, 1, 0.5, 1, 0, 1])).plan(
            events: [.debit(.cents(3))],
            surface: .desktop,
            reduceMotion: false
        )[0]
        assert(seededFirst == seededSecond, "seeded random source is deterministic")
        assert(seededFirst.startX == -5 && seededFirst.midX == 9 && seededFirst.endX == 0, "seeded desktop offsets")

        let menuPlan = DamageAnimationPlanner(random: HarnessRandom(values: [0, 1, 0, 1, 0, 1])).plan(
            events: [.debit(.cents(3))],
            surface: .menuBar,
            shake: .strong,
            reduceMotion: false
        )[0]
        assert(menuPlan.startX == -3 && menuPlan.midX == 5 && menuPlan.endX == -7, "menu X range")
        assert(menuPlan.startRotationDegrees == -4 && menuPlan.endRotationDegrees == 4, "menu rotation range")
        assert(menuPlan.shakeStrength == nil, "menu bar never shakes")

        let creditPlan = planner.plan(
            events: [.credit(.cents(500))],
            surface: .desktop,
            shake: .strong,
            reduceMotion: false
        )[0]
        assert(creditPlan.style == .credit && creditPlan.color == .green, "credit uses green style")
        assert(creditPlan.shakeStrength == nil, "credit does not shake")
        assert(desktopPlans.allSatisfy { $0.style == .debit && $0.color == .red }, "debit uses red style")

        let burstPlans = planner.plan(
            events: [.debit(.cents(3)), .debit(.cents(6)), .credit(.cents(1)), .debit(.cents(12))],
            surface: .desktop,
            shake: .weak,
            reduceMotion: false
        )
        assert(burstPlans.filter { $0.shakeStrength != nil }.count == 2, "one shake per debit burst")
        assert(burstPlans[0].shakeStrength == .weak && burstPlans[3].shakeStrength == .weak, "shake strength is preserved")

        let reducedPlan = planner.plan(
            events: [.debit(.cents(3))],
            surface: .desktop,
            shake: .strong,
            reduceMotion: true
        )[0]
        assert(reducedPlan.shakeStrength == nil, "Reduce Motion disables shake")
        assert(reducedPlan.duration < desktopPlans[0].duration && reducedPlan.rise < desktopPlans[0].rise, "Reduce Motion shortens movement")

        let view = DamageStreamView(frame: .zero)
        let fixedFrame = view.frame
        let fixedIntrinsicSize = view.intrinsicContentSize
        view.play(plans: desktopPlans, anchor: CGPoint(x: 40, y: 20))
        assert(view.frame == fixedFrame, "playing does not resize the owner view")
        assert(view.intrinsicContentSize == fixedIntrinsicSize && fixedIntrinsicSize == DamageStreamView.fixedSize, "stream has fixed owner size")
        assert(view.layer?.sublayers?.count == desktopPlans.count, "one layer per plan")

        print("task-7 harness passed: cadence, ranges, deterministic randomness, styles, burst shake, Reduce Motion, fixed stream size")
    }
}

func assert(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("FAIL: \(message)") }
}
