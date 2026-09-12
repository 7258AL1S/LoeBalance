using System.Globalization;
using System.Text.Json;
using LoeBalance.Core.Models;

namespace LoeBalance.Core.Tests;

/// <summary>
/// Mirrors the macOS `testMoneyAcceptsOnlyStrictDecimalStringGrammar` and
/// `testMoneyRejectsMalformedNumericStrings` cases.
/// </summary>
public sealed class MoneyGrammarTests
{
    [Theory]
    [InlineData("\"+12\"", "12")]
    [InlineData("\"-0.50\"", "-0.50")]
    [InlineData("\"19.\"", "19")]
    [InlineData("\".5\"", "0.5")]
    [InlineData("\"  +12  \"", "12")]
    [InlineData("\"1234567890.123456789\"", "1234567890.123456789")]
    public void AcceptsStrictDecimalStrings(string json, string expected)
    {
        var money = JsonSerializer.Deserialize<Money>(json);
        Assert.Equal(decimal.Parse(expected, CultureInfo.InvariantCulture), money.Decimal);
    }

    [Theory]
    [InlineData("\"19.38oops\"")]
    [InlineData("\"1,234.56\"")]
    [InlineData("\"--1\"")]
    [InlineData("\"+-1\"")]
    [InlineData("\"\"")]
    [InlineData("\"   \"")]
    [InlineData("\"1e3\"")]
    [InlineData("\"1 2\"")]
    [InlineData("\"NaN\"")]
    [InlineData("\"Infinity\"")]
    public void RejectsMalformedNumericStrings(string json)
        => Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<Money>(json));

    [Fact]
    public void FormatsCurrencyTheSameWayAsTheMacApp()
    {
        Assert.Equal("$19.08", new Money(19.08m).CurrencyText);
        Assert.Equal("$1,000,000.00", new Money(1_000_000m).CurrencyText);
    }
}
