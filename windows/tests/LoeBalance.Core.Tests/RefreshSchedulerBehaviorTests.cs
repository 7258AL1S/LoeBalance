using LoeBalance.Core.Models;
using LoeBalance.Core.Refresh;

namespace LoeBalance.Core.Tests;

/// <summary>
/// Behaviour checks that mirror the macOS scheduler test suite: retry-after deadlines,
/// the fallback backoff sequence, offline pausing, network recovery and wake refreshes.
/// </summary>
public sealed class RefreshSchedulerBehaviorTests
{
    [Fact]
    public async Task StartRefreshesImmediatelyAndThenUsesTheConfiguredInterval()
    {
        var delayer = new RecordingDelayer();
        var calls = 0;
        var scheduler = CreateScheduler(delayer, () => { calls++; return new ConnectionState.Online(); });

        await scheduler.StartAsync();

        Assert.Equal(1, calls);
        await delayer.WaitForRecordedDelaysAsync(1);
        Assert.Equal(TimeSpan.FromSeconds(30), delayer.Delays[0]);
        await scheduler.StopAsync();
    }

    [Fact]
    public async Task IntervalUpdatesAreClampedToOneAndThreeThousandSixHundredSeconds()
    {
        var delayer = new RecordingDelayer();
        var scheduler = CreateScheduler(delayer, () => new ConnectionState.Online());

        await scheduler.StartAsync();
        scheduler.UpdateInterval(0.25);
        await delayer.ReleaseNextAsync();
        await delayer.WaitForRecordedDelaysAsync(2);
        Assert.Equal(TimeSpan.FromSeconds(1), delayer.Delays[1]);

        scheduler.UpdateInterval(99_999);
        await delayer.ReleaseNextAsync();
        await delayer.WaitForRecordedDelaysAsync(3);
        Assert.Equal(TimeSpan.FromSeconds(3600), delayer.Delays[2]);
        await scheduler.StopAsync();
    }

    [Fact]
    public async Task RateLimitWithARetryAfterDeadlineWaitsUntilTheDeadline()
    {
        var delayer = new RecordingDelayer();
        var now = DateTimeOffset.Parse("2026-09-12T12:00:00Z");
        var calls = 0;
        var scheduler = CreateScheduler(
            delayer,
            () => Interlocked.Increment(ref calls) == 1
                ? new ConnectionState.RateLimited(now.AddSeconds(75))
                : new ConnectionState.Online(),
            () => now);

        await scheduler.StartAsync();
        await delayer.WaitForRecordedDelaysAsync(1);

        Assert.Equal(TimeSpan.FromSeconds(75), delayer.Delays[0]);
        await scheduler.StopAsync();
    }

    [Fact]
    public async Task RateLimitWithoutARetryAfterDeadlineUsesTheBoundedBackoffSequence()
    {
        var delayer = new RecordingDelayer();
        var scheduler = CreateScheduler(
            delayer,
            () => throw new AppException(AppErrorKind.RateLimited, "limited", statusCode: 429));

        await scheduler.StartAsync();
        for (var index = 0; index < 6; index++)
        {
            await delayer.WaitForRecordedDelaysAsync(index + 1);
            await delayer.ReleaseNextAsync();
        }

        Assert.Equal(
            new[]
            {
                TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(20), TimeSpan.FromSeconds(40),
                TimeSpan.FromSeconds(80), TimeSpan.FromSeconds(160), TimeSpan.FromSeconds(300)
            },
            delayer.Delays);
        await scheduler.StopAsync();
    }

    [Fact]
    public async Task TransportFailuresKeepRefreshingWithBackoff()
    {
        var delayer = new RecordingDelayer();
        var calls = 0;
        var scheduler = CreateScheduler(
            delayer,
            () =>
            {
                if (Interlocked.Increment(ref calls) > 1)
                {
                    throw new AppException(AppErrorKind.Transport, "offline");
                }
                return new ConnectionState.Online();
            });

        await scheduler.StartAsync();
        await delayer.WaitForRecordedDelaysAsync(1);
        await delayer.ReleaseNextAsync();
        await delayer.WaitForRecordedDelaysAsync(2);
        await delayer.ReleaseNextAsync();
        await delayer.WaitForRecordedDelaysAsync(3);

        Assert.Equal(
            new[]
            {
                TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(20)
            },
            delayer.Delays);
        await scheduler.StopAsync();
    }

    [Fact]
    public async Task OfflineResultsPauseScheduledRefreshesUntilTheNetworkReturns()
    {
        var delayer = new RecordingDelayer();
        var calls = 0;
        var scheduler = CreateScheduler(delayer, () =>
        {
            Interlocked.Increment(ref calls);
            return calls == 1 ? new ConnectionState.Offline() : new ConnectionState.Online();
        });

        await scheduler.StartAsync();
        Assert.Equal(1, calls);

        // Release several loop cycles; while offline the scheduler must not call refresh.
        for (var index = 0; index < 3; index++)
        {
            await delayer.WaitForRecordedDelaysAsync(index + 1);
            await delayer.ReleaseNextAsync();
            await Task.Delay(30);
        }
        Assert.Equal(1, calls);

        await scheduler.NetworkBecameAvailableAsync();
        Assert.Equal(2, calls);
        await scheduler.StopAsync();
    }

    [Fact]
    public async Task SystemWakeAndManualRefreshBothRefreshImmediately()
    {
        var delayer = new RecordingDelayer();
        var calls = 0;
        var scheduler = CreateScheduler(delayer, () => { Interlocked.Increment(ref calls); return new ConnectionState.Online(); });

        await scheduler.StartAsync();
        await scheduler.SystemDidWakeAsync();
        await scheduler.RefreshNowAsync();

        Assert.Equal(3, calls);
        await scheduler.StopAsync();
    }

    [Fact]
    public async Task StopCancelsTheLoopAndFurtherRefreshes()
    {
        var delayer = new RecordingDelayer();
        var calls = 0;
        var scheduler = CreateScheduler(delayer, () => { Interlocked.Increment(ref calls); return new ConnectionState.Online(); });

        await scheduler.StartAsync();
        await scheduler.StopAsync();
        await delayer.ReleaseNextAsync();
        await Task.Delay(30);

        Assert.Equal(1, calls);
    }

    private static RefreshScheduler CreateScheduler(
        RecordingDelayer delayer,
        Func<ConnectionState> stateFactory,
        Func<DateTimeOffset>? now = null)
        => new(
            30,
            _ => Task.FromResult(new RefreshResult(
                new BalanceSnapshot(new Money(1m), null, null, DateTimeOffset.UtcNow),
                [],
                stateFactory())),
            now,
            delayer.DelayAsync);

    private sealed class RecordingDelayer
    {
        private readonly SemaphoreSlim _release = new(0);
        private readonly object _lock = new();
        private readonly List<TimeSpan> _delays = [];

        public IReadOnlyList<TimeSpan> Delays
        {
            get { lock (_lock) return _delays.ToArray(); }
        }

        public async Task DelayAsync(TimeSpan duration, CancellationToken cancellationToken)
        {
            lock (_lock) _delays.Add(duration);
            await _release.WaitAsync(cancellationToken);
        }

        public Task ReleaseNextAsync()
        {
            _release.Release();
            return Task.CompletedTask;
        }

        public async Task WaitForRecordedDelaysAsync(int count)
        {
            var deadline = DateTimeOffset.UtcNow.AddSeconds(5);
            while (Delays.Count < count)
            {
                if (DateTimeOffset.UtcNow > deadline)
                {
                    throw new TimeoutException($"Only {Delays.Count} delays were recorded, expected {count}.");
                }
                await Task.Delay(10);
            }
        }
    }
}
