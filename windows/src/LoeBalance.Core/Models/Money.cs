using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace LoeBalance.Core.Models;

[JsonConverter(typeof(MoneyJsonConverter))]
public readonly record struct Money(decimal Decimal) : IComparable<Money>
{
    public static Money Zero => new(0m);

    public Money(int cents) : this(cents / 100m) { }

    public int CompareTo(Money other) => Decimal.CompareTo(other.Decimal);

    public Money Magnitude => new(Math.Abs(Decimal));

    public string CurrencyText => Decimal.ToString("C2", CultureInfo.GetCultureInfo("en-US"));

    public static Money operator +(Money left, Money right) => new(left.Decimal + right.Decimal);
    public static Money operator -(Money left, Money right) => new(left.Decimal - right.Decimal);
    public static bool operator >(Money left, Money right) => left.Decimal > right.Decimal;
    public static bool operator <(Money left, Money right) => left.Decimal < right.Decimal;
}

public sealed class MoneyJsonConverter : JsonConverter<Money>
{
    // Mirrors the Swift `Money.parseDecimalString` grammar: an optional sign followed by
    // digits with an optional fraction, or a bare fraction. Thousands separators,
    // exponents, hex, NaN, and Infinity are rejected.
    private static readonly Regex DecimalStringPattern =
        new(@"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$", RegexOptions.Compiled | RegexOptions.CultureInvariant);

    public override Money Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Number && reader.TryGetDecimal(out var number))
        {
            return new Money(number);
        }

        if (reader.TokenType == JsonTokenType.String && TryParseDecimalString(reader.GetString(), out var textNumber))
        {
            return new Money(textNumber);
        }

        throw new JsonException("Expected a decimal number or numeric string.");
    }

    public override void Write(Utf8JsonWriter writer, Money value, JsonSerializerOptions options)
        => writer.WriteNumberValue(value.Decimal);

    private static bool TryParseDecimalString(string? value, out decimal parsed)
    {
        parsed = 0m;
        if (value is null) return false;
        var trimmed = value.Trim();
        if (trimmed.Length == 0 || !DecimalStringPattern.IsMatch(trimmed)) return false;
        return decimal.TryParse(trimmed, NumberStyles.AllowLeadingSign | NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out parsed);
    }
}
