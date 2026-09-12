using LoeBalance.Core.Models;

namespace LoeBalance.Core.Refresh;

public interface IRefreshScheduler
{
    Task StartAsync(CancellationToken cancellationToken = default);
    Task StopAsync();
    void UpdateInterval(double seconds);
    Task RefreshNowAsync(CancellationToken cancellationToken = default);
    void NetworkBecameUnavailable();
    Task NetworkBecameAvailableAsync(CancellationToken cancellationToken = default);
    Task SystemDidWakeAsync(CancellationToken cancellationToken = default);
}

public sealed class RefreshScheduler : IRefreshScheduler
{
    private readonly Func<CancellationToken, Task<RefreshResult>> _refresh;
    private readonly Func<DateTimeOffset> _now;
    private readonly SemaphoreSlim _refreshLock = new(1, 1);
    private readonly object _stateLock = new();
    private CancellationTokenSource? _loopCancellation;
    private Task? _loopTask;
    private TimeSpan _interval;
    private bool _online = true;
    private DateTimeOffset? _retryAfter;
    private int _backoffStep;

    public RefreshScheduler(double intervalSeconds, Func<CancellationToken, Task<RefreshResult>> refresh, Func<DateTimeOffset>? now = null)
    {
        _interval = TimeSpan.FromSeconds(Clamp(intervalSeconds));
        _refresh = refresh;
        _now = now ?? (() => DateTimeOffset.UtcNow);
    }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        lock (_stateLock)
        {
            if (_loopTask is not null) return;
            _loopCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            _loopTask = RunAsync(_loopCancellation.Token);
        }
        await RefreshNowAsync(cancellationToken);
    }

    public async Task StopAsync()
    {
        Task? loop;
        lock (_stateLock)
        {
            _loopCancellation?.Cancel();
            loop = _loopTask;
            _loopTask = null;
            _loopCancellation = null;
        }
        if (loop is not null) await loop;
    }

    public void UpdateInterval(double seconds) => _interval = TimeSpan.FromSeconds(Clamp(seconds));

    public Task RefreshNowAsync(CancellationToken cancellationToken = default)
        => PerformRefreshAsync(cancellationToken);

    public void NetworkBecameUnavailable()
    {
        lock (_stateLock) { _online = false; _retryAfter = null; }
    }

    public Task NetworkBecameAvailableAsync(CancellationToken cancellationToken = default)
    {
        lock (_stateLock) _online = true;
        return RefreshNowAsync(cancellationToken);
    }

    public Task SystemDidWakeAsync(CancellationToken cancellationToken = default) => RefreshNowAsync(cancellationToken);

    private async Task RunAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                var delay = NextDelay();
                await Task.Delay(delay, cancellationToken);
                await PerformRefreshAsync(cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { return; }
        }
    }

    private async Task PerformRefreshAsync(CancellationToken cancellationToken)
    {
        lock (_stateLock) { if (!_online) return; }
        await _refreshLock.WaitAsync(cancellationToken);
        try
        {
            try
            {
                var result = await _refresh(cancellationToken);
                lock (_stateLock)
                {
                    _retryAfter = result.ConnectionState is ConnectionState.RateLimited rate ? rate.Until : null;
                    _backoffStep = 0;
                    _online = result.ConnectionState is not ConnectionState.Offline;
                }
            }
            catch (AppException exception)
            {
                lock (_stateLock)
                {
                    if (exception.Kind == AppErrorKind.RateLimited) _retryAfter = exception.RetryAfter;
                    else _backoffStep = Math.Min(_backoffStep + 1, 6);
                }
            }
        }
        finally { _refreshLock.Release(); }
    }

    private TimeSpan NextDelay()
    {
        lock (_stateLock)
        {
            if (_retryAfter is DateTimeOffset retryAfter) return TimeSpan.FromSeconds(Math.Max(0, (retryAfter - _now()).TotalSeconds));
            if (_backoffStep == 0) return _interval;
            return TimeSpan.FromSeconds(new[] { 10, 20, 40, 80, 160, 300 }[Math.Min(_backoffStep - 1, 5)]);
        }
    }

    private static double Clamp(double seconds) => Math.Clamp(seconds, 1, 3600);
}
