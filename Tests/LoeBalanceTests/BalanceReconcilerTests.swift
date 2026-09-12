import Foundation
import XCTest
@testable import LoeBalance

final class BalanceReconcilerTests: XCTestCase {
    func testBaselineProducesNoEvents() {
        let result = BalanceReconciler().reconcile(
            previousBalance: Money(decimal: 10),
            currentBalance: Money(decimal: 10),
            unseenUsage: []
        )

        XCTAssertEqual(result, [])
    }

    func testConcurrentDebitAndRechargeReconcileToNetBalanceChange() {
        let result = BalanceReconciler().reconcile(
            previousBalance: Money(decimal: 10),
            currentBalance: Money(decimal: 14.50),
            unseenUsage: [.fixture(id: 1, cost: 0.50)]
        )

        XCTAssertEqual(result, [.debit(Money(decimal: 0.50)), .credit(Money(decimal: 5.00))])
    }

    func testMoreThanTwentyDebitsAggregateTheRemainder() {
        let usage = (1...25).map { UsageRecord.fixture(id: Int64($0), cost: 0.10) }

        let result = BalanceReconciler().debitEvents(from: usage)

        XCTAssertEqual(result.count, 20)
        XCTAssertEqual(result.last, .debit(Money(decimal: 0.60)))
    }

    func testUnseenUsageSortsOldestFirstAndBreaksTiesByID() {
        let usage = [
            .fixture(id: 2, cost: 0.20, secondsAfterBaseline: 10),
            .fixture(id: 3, cost: 0.30),
            .fixture(id: 1, cost: 0.10, secondsAfterBaseline: 10)
        ]

        let result = BalanceReconciler().reconcile(
            previousBalance: Money(decimal: 10),
            currentBalance: Money(decimal: 9),
            unseenUsage: usage
        )

        XCTAssertEqual(result, [
            .debit(Money(decimal: 0.30)),
            .debit(Money(decimal: 0.10)),
            .debit(Money(decimal: 0.20))
        ])
    }

    func testPositiveResidualCreatesCredit() {
        let result = BalanceReconciler().reconcile(
            previousBalance: Money(decimal: 10),
            currentBalance: Money(decimal: 12),
            unseenUsage: [.fixture(id: 1, cost: 0.50)]
        )

        XCTAssertEqual(result, [.debit(Money(decimal: 0.50)), .credit(Money(decimal: 2.50))])
    }

    func testNegativeResidualCreatesAggregateDebit() {
        let result = BalanceReconciler().reconcile(
            previousBalance: Money(decimal: 10),
            currentBalance: Money(decimal: 8),
            unseenUsage: [.fixture(id: 1, cost: 0.50)]
        )

        XCTAssertEqual(result, [.debit(Money(decimal: 0.50)), .debit(Money(decimal: 2.50))])
    }

    func testResidualBelowToleranceIsIgnored() {
        let result = BalanceReconciler().reconcile(
            previousBalance: Money(decimal: 10),
            currentBalance: Money(decimal: 10.00005),
            unseenUsage: []
        )

        XCTAssertEqual(result, [])
    }
}

private extension UsageRecord {
    static func fixture(id: Int64, cost: Decimal, secondsAfterBaseline: TimeInterval = 0) -> Self {
        Self(
            id: id,
            createdAt: Date.fixtureNow.addingTimeInterval(secondsAfterBaseline),
            actualCost: Money(decimal: cost)
        )
    }
}
