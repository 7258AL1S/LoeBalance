import Foundation
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

    func testMoneyAcceptsOnlyStrictDecimalStringGrammar() throws {
        let examples = [
            (input: "+12", expected: "12"),
            (input: "-0.50", expected: "-0.50"),
            (input: "19.", expected: "19"),
            (input: ".5", expected: "0.5"),
            (input: "  +12  ", expected: "12")
        ]

        for example in examples {
            let expected = try XCTUnwrap(
                Decimal(string: example.expected, locale: Locale(identifier: "en_US_POSIX"))
            )
            XCTAssertEqual(
                try JSONDecoder().decode(Money.self, from: JSONEncoder().encode(example.input)),
                Money(decimal: expected),
                "Expected to accept \(example.input.debugDescription)"
            )
        }
    }

    func testMoneyRejectsMalformedNumericStrings() throws {
        let examples = [
            "19.38oops",
            "1,234.56",
            "--1",
            "+-1",
            "",
            "   ",
            "1e3",
            "1 2",
            "NaN",
            "Infinity"
        ]

        for example in examples {
            XCTAssertThrowsError(
                try JSONDecoder().decode(Money.self, from: JSONEncoder().encode(example)),
                "Expected to reject \(example.debugDescription)"
            )
        }
    }

    func testMoneyArithmeticUsesDecimalValues() {
        XCTAssertEqual(Money(decimal: 19.38) - Money(decimal: 0.30), Money(decimal: 19.08))
        XCTAssertEqual(Money(decimal: 19.08).currencyText, "$19.08")
    }

    func testShakeStrengthHasThreeStableCases() {
        XCTAssertEqual(ShakeStrength.allCases, [.off, .weak, .strong])
    }
}
