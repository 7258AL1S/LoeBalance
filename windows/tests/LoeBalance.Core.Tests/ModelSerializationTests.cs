using System.Text.Json;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;

namespace LoeBalance.Core.Tests;

public sealed class ModelSerializationTests
{
    [Fact]
    public void ApiPayloadUsesSnakeCaseAndFlexibleMoney()
    {
        const string json = "{\"id\":42,\"email\":\"user@example.com\",\"username\":\"Arisu\",\"balance\":\"19.58\"}";
        var user = JsonSerializer.Deserialize<CurrentUserDto>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));

        Assert.NotNull(user);
        Assert.Equal(42L, user!.Id);
        Assert.Equal(19.58m, user.Balance.Decimal);
    }

    [Fact]
    public void RefreshResultKeepsConnectionAndEvents()
    {
        var snapshot = new BalanceSnapshot(new Money(19.58m), new Money(0.30m), 4, DateTimeOffset.UtcNow);
        var result = new RefreshResult(snapshot, [new BalanceAnimationEvent.Debit(new Money(0.30m))], new ConnectionState.Online());

        Assert.Single(result.Events);
        Assert.IsType<ConnectionState.Online>(result.ConnectionState);
    }
}
