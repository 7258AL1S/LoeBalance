import XCTest
@testable import LoeBalance

final class MoneyAndModelsTests: XCTestCase {
    func testMoneyDecodesNumberAndString() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(Money.self, from: Data("19.38".utf8)),
            Money(decimal: try XCTUnwrap(Decimal(string: "19.38", locale: Locale(identifier: "en_US_POSIX"))))
        )
        XCTAssertEqual(try JSONDecoder().decode(Money.self, from: Data("\"0.30\"".utf8)), Money(decimal: 0.30))
    }

    func testMoneyPreservesHighPrecisionNumericJSON() throws {
        let expected = try XCTUnwrap(
            Decimal(string: "1234567890.123456789", locale: Locale(identifier: "en_US_POSIX"))
        )

        XCTAssertEqual(
            try JSONDecoder().decode(Money.self, from: Data("1234567890.123456789".utf8)),
            Money(decimal: expected)
        )
    }

    func testMoneyArithmeticUsesDecimalValues() {
        XCTAssertEqual(Money(decimal: 19.38) - Money(decimal: 0.30), Money(decimal: 19.08))
        XCTAssertEqual(Money(decimal: 19.08).currencyText, "$19.08")
    }

    func testShakeStrengthHasThreeStableCases() {
        XCTAssertEqual(ShakeStrength.allCases, [.off, .weak, .strong])
    }
}
