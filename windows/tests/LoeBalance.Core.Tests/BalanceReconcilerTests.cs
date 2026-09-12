using LoeBalance.Core.Models;
using LoeBalance.Core.Refresh;

namespace LoeBalance.Core.Tests;

public sealed class BalanceReconcilerTests
{
    [Fact]
    public void OrdersUsageAndCreatesResidualCredit()
    {
        var reconciler = new BalanceReconciler();
        var usage = new[]
        {
            new UsageRecord(2, DateTimeOffset.Parse("2026-09-12T00:00:02Z"), new Money(0.20m)),
            new UsageRecord(1, DateTimeOffset.Parse("2026-09-12T00:00:01Z"), new Money(0.10m))
        };

        var events = reconciler.Reconcile(new Money(20m), new Money(19.90m), usage);

        Assert.Collection(events,
            first => Assert.Equal(0.10m, Assert.IsType<BalanceAnimationEvent.Debit>(first).Amount.Decimal),
            second => Assert.Equal(0.20m, Assert.IsType<BalanceAnimationEvent.Debit>(second).Amount.Decimal),
            third => Assert.Equal(0.20m, Assert.IsType<BalanceAnimationEvent.Credit>(third).Amount.Decimal));
    }

    [Fact]
    public void AggregatesUsageAfterNineteenRecords()
    {
        var usage = Enumerable.Range(1, 21)
            .Select(id => new UsageRecord(id, DateTimeOffset.UtcNow.AddSeconds(id), new Money(0.01m)))
            .ToArray();

        var events = new BalanceReconciler().DebitEvents(usage);

        Assert.Equal(20, events.Count);
        Assert.Equal(0.02m, Assert.IsType<BalanceAnimationEvent.Debit>(events[^1]).Amount.Decimal);
    }
}
