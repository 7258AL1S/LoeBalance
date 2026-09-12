using LoeBalance.Core.Auth;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;
using LoeBalance.Core.Persistence;

namespace LoeBalance.Core.Refresh;

public sealed class BalanceService
{
    private readonly IApiClient _api;
    private readonly AuthManager _auth;
    private readonly ISnapshotStore _snapshotStore;
    private readonly BalanceReconciler _reconciler;
    private readonly Func<DateTimeOffset> _now;
    private readonly int _usagePageSize;
    private readonly SemaphoreSlim _refreshLock = new(1, 1);

    public BalanceService(
        IApiClient api,
        AuthManager auth,
        ISnapshotStore snapshotStore,
        BalanceReconciler? reconciler = null,
        Func<DateTimeOffset>? now = null,
        int usagePageSize = 100)
    {
        _api = api;
        _auth = auth;
        _snapshotStore = snapshotStore;
        _reconciler = reconciler ?? new BalanceReconciler();
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _usagePageSize = usagePageSize;
    }

    public async Task<RefreshResult> RefreshAsync(CancellationToken cancellationToken = default)
    {
        await _refreshLock.WaitAsync(cancellationToken);
        try
        {
            var persisted = await _snapshotStore.LoadAsync(cancellationToken) ?? PersistedSnapshotState.Empty;
            return await _auth.WithAccessTokenAsync(async token =>
            {
                var userTask = _api.FetchCurrentUserAsync(token, cancellationToken);
                var statsTask = _api.FetchDashboardStatsAsync(token, cancellationToken);
                var usageTask = _api.FetchUsageAsync(token, _usagePageSize, cancellationToken);
                var user = await userTask;
                var stats = await TryGetAsync(statsTask);
                var usage = await TryGetAsync(usageTask);
                var snapshot = new BalanceSnapshot(user.Balance, stats?.TodayActualCost, stats?.TodayRequests, _now());
                if (usage is null)
                {
                    return new RefreshResult(snapshot, Array.Empty<BalanceAnimationEvent>(), new ConnectionState.Online());
                }

                var unseen = usage
                    .Where(record => !persisted.RecentUsageIds.Contains(record.Id))
                    .OrderBy(record => record.CreatedAt)
                    .ThenBy(record => record.Id)
                    .ToArray();
                var events = persisted.CachedSnapshot is null
                    ? Array.Empty<BalanceAnimationEvent>()
                    : _reconciler.Reconcile(persisted.CachedSnapshot.Balance, snapshot.Balance, unseen);
                var recentIds = usage.Select(record => record.Id).Concat(persisted.RecentUsageIds).Distinct().TakeLast(500).ToList();
                var watermark = usage.Count == 0 ? persisted.WatermarkTime : usage.Max(record => record.CreatedAt);
                await _snapshotStore.SaveAsync(new PersistedSnapshotState(snapshot, watermark, recentIds), cancellationToken);
                return new RefreshResult(snapshot, events, new ConnectionState.Online());
            }, cancellationToken);
        }
        finally
        {
            _refreshLock.Release();
        }
    }

    public Task ClearBaselineAsync(CancellationToken cancellationToken = default)
        => _snapshotStore.ClearAsync(cancellationToken);

    private static async Task<T?> TryGetAsync<T>(Task<T> task)
    {
        try { return await task; }
        catch { return default; }
    }
}
