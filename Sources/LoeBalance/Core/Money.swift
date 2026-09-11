import Foundation

struct Money: Codable, Equatable, Comparable, Sendable {
    let decimal: Decimal

    init(decimal: Decimal) {
        self.decimal = decimal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let decimal = try? container.decode(Decimal.self) {
            self.init(decimal: decimal)
        } else if let double = try? container.decode(Double.self) {
            self.init(decimal: Decimal(double))
        } else if let string = try? container.decode(String.self),
                  let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) {
            self.init(decimal: decimal)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a decimal number or numeric string."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(decimal)
    }

    static let zero = Money(decimal: 0)

    static func cents(_ value: Int) -> Self {
        Self(decimal: Decimal(value) / 100)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.decimal < rhs.decimal
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(decimal: lhs.decimal + rhs.decimal)
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(decimal: lhs.decimal - rhs.decimal)
    }

    var magnitude: Self {
        Self(decimal: decimal < 0 ? -decimal : decimal)
    }

    var currencyText: String {
        Self.currencyFormatter.string(from: decimal as NSDecimalNumber) ?? "$0.00"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positiveFormat = "¤#,##0.00"
        formatter.negativeFormat = "-¤#,##0.00"
        return formatter
    }()
}
