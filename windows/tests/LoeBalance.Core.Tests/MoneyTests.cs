using System.Text.Json;
using LoeBalance.Core.Models;

namespace LoeBalance.Core.Tests;

public sealed class MoneyTests
{
    [Theory]
    [InlineData("12.34", 12.34)]
    [InlineData("\"12.34\"", 12.34)]
    [InlineData("0", 0)]
    public void ReadsNumericJsonValues(string json, double expected)
    {
        var money = JsonSerializer.Deserialize<Money>(json);
        Assert.Equal((decimal)expected, money.Decimal);
    }

    [Fact]
    public void RejectsInvalidNumericStrings()
    {
        Assert.Throws<JsonException>(() => JsonSerializer.Deserialize<Money>("\"not-money\""));
    }

    [Fact]
    public void FormatsUsdAndSupportsArithmetic()
    {
        var left = new Money(12.30m);
        var right = new Money(0.45m);

        Assert.Equal("$12.30", left.CurrencyText);
        Assert.Equal(12.75m, (left + right).Decimal);
        Assert.Equal(11.85m, (left - right).Decimal);
        Assert.Equal(0.45m, new Money(-0.45m).Magnitude.Decimal);
    }
}
