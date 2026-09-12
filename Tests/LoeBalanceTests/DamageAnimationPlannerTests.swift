import Foundation
import XCTest
@testable import LoeBalance

final class DamageAnimationPlannerTests: XCTestCase {
    func testDesktopDebitPlansFormConcurrentSingleOriginStream() {
        let planner = DamageAnimationPlanner(random: SequenceRandom(values: [0.0, 1.0, 0.5]))
        let plans = planner.plan(
            events: [.debit(.cents(3)), .debit(.cents(6)), .debit(.cents(12))],
            surface: .desktop,
            reduceMotion: false
        )

        XCTAssertEqual(plans.map(\.launchDelay), [0.00, 0.23, 0.46])
        XCTAssertEqual(plans.map(\.duration), [0.82, 0.82, 0.82])
        XCTAssertTrue(plans.allSatisfy { (-13...13).contains(Int($0.endX.rounded())) })
        XCTAssertTrue(plans.allSatisfy { (-8...8).contains(Int($0.endRotationDegrees.rounded())) })
    }

    func testDesktopRangesAndRandomSourceAreDeterministic() {
        let values = [0.0, 1.0, 0.5, 1.0, 0.0, 1.0]
        let first = DamageAnimationPlanner(random: SequenceRandom(values: values)).plan(
            events: [.debit(.cents(3))],
            surface: .desktop,
            reduceMotion: false
        )
        let second = DamageAnimationPlanner(random: SequenceRandom(values: values)).plan(
            events: [.debit(.cents(3))],
            surface: .desktop,
            reduceMotion: false
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first[0].startX, -5)
        XCTAssertEqual(first[0].midX, 9)
        XCTAssertEqual(first[0].endX, 0)
        XCTAssertEqual(first[0].rise, 100)
        XCTAssertEqual(first[0].startRotationDegrees, -8)
        XCTAssertEqual(first[0].endRotationDegrees, 8)
    }

    func testMenuPlansUseSmallerMotionRanges() {
        let plans = DamageAnimationPlanner(random: SequenceRandom(values: [0.0, 1.0, 0.0, 1.0, 0.0, 1.0])).plan(
            events: [.debit(.cents(3))],
            surface: .menuBar,
            reduceMotion: false
        )

        XCTAssertEqual(plans[0].startX, -3)
        XCTAssertEqual(plans[0].midX, 5)
        XCTAssertEqual(plans[0].endX, -7)
        XCTAssertEqual(plans[0].rise, 55)
        XCTAssertEqual(plans[0].startRotationDegrees, -4)
        XCTAssertEqual(plans[0].endRotationDegrees, 4)
        XCTAssertNil(plans[0].shakeStrength)
    }

    func testCreditPlansUseGreenStyleAndNeverShake() {
        let plans = DamageAnimationPlanner(random: SequenceRandom(values: [0.5])).plan(
            events: [.credit(.cents(500))],
            surface: .desktop,
            shake: .strong,
            reduceMotion: false
        )

        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].style, .credit)
        XCTAssertEqual(plans[0].color, .green)
        XCTAssertNil(plans[0].shakeStrength)
    }

    func testDebitBurstHasOneShakePlanForWeakAndStrong() {
        for strength in [ShakeStrength.weak, .strong] {
            let plans = DamageAnimationPlanner(random: SequenceRandom(values: [0.5])).plan(
                events: [.debit(.cents(3)), .debit(.cents(6)), .debit(.cents(12))],
                surface: .desktop,
                shake: strength,
                reduceMotion: false
            )

            XCTAssertEqual(plans.filter { $0.shakeStrength != nil }.count, 1)
            XCTAssertEqual(plans.first?.shakeStrength, strength)
            XCTAssertTrue(plans.dropFirst().allSatisfy { $0.shakeStrength == nil })
        }
    }

    func testOffDisablesShake() {
        let plans = DamageAnimationPlanner(random: SequenceRandom(values: [0.5])).plan(
            events: [.debit(.cents(3)), .debit(.cents(6))],
            surface: .desktop,
            shake: .off,
            reduceMotion: false
        )

        XCTAssertTrue(plans.allSatisfy { $0.shakeStrength == nil })
    }

    func testReduceMotionDisablesShakeAndShortensRise() {
        let normal = DamageAnimationPlanner(random: SequenceRandom(values: [0.5])).plan(
            events: [.debit(.cents(3))],
            surface: .desktop,
            shake: .strong,
            reduceMotion: false
        )[0]
        let reduced = DamageAnimationPlanner(random: SequenceRandom(values: [0.5])).plan(
            events: [.debit(.cents(3))],
            surface: .desktop,
            shake: .strong,
            reduceMotion: true
        )[0]

        XCTAssertNil(reduced.shakeStrength)
        XCTAssertLessThan(reduced.duration, normal.duration)
        XCTAssertLessThan(reduced.rise, normal.rise)
    }

    func testEmptyEventsProduceNoPlans() {
        let plans = DamageAnimationPlanner().plan(events: [], surface: .desktop, reduceMotion: false)

        XCTAssertTrue(plans.isEmpty)
    }
}

final class SequenceRandom: MotionRandomizing, @unchecked Sendable {
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
