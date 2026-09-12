using LoeBalance.Core.Models;
using LoeBalance.Core.Refresh;

namespace LoeBalance.Core.Tests;

public sealed class RefreshSchedulerTests
{
    [Fact]
    public async Task ManualRefreshIsSerialized()
    {
        var calls = 0;
        var scheduler = new RefreshScheduler(0, _ =>
        {
            Interlocked.Increment(ref calls);
            return Task.FromResult(new RefreshResult(
                new BalanceSnapshot(new Money(1m), null, null, DateTimeOffset.UtcNow),
                [], new ConnectionState.Online()));
        });

        await Task.WhenAll(scheduler.RefreshNowAsync(), scheduler.RefreshNowAsync());

        Assert.Equal(2, calls);
    }
}
