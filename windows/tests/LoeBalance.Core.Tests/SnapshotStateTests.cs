using LoeBalance.Core.Auth;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;
using LoeBalance.Core.Persistence;
using LoeBalance.Core.Refresh;

namespace LoeBalance.Core.Tests;

public sealed class SnapshotStateTests
{
    [Fact]
    public void RecordUsageIdsKeepsNewestIdentifiersAndDropsDuplicates()
    {
        var state = new PersistedSnapshotState(null, null, [1, 2, 3]);

        var updated = state.RecordUsageIds([3, 4]);

        Assert.Equal([1, 2, 3, 4], updated.RecentUsageIds);
    }

    [Fact]
    public void RecordUsageIdsKeepsAtMostFiveHundredIdentifiersWithTheNewestLast()
    {
        var state = PersistedSnapshotState.Empty.RecordUsageIds(Enumerable.Range(1, 520).Select(value => (long)value));
        var updated = state.RecordUsageIds([521, 522]);

        Assert.Equal(PersistedSnapshotState.MaximumRecentUsageIds, updated.RecentUsageIds.Count);
        Assert.Equal(522, updated.RecentUsageIds[^1]);
        Assert.Equal(23, updated.RecentUsageIds[0]);
        Assert.DoesNotContain(22L, updated.RecentUsageIds);
    }

    [Fact]
    public async Task RefreshingRepeatedlyWithAFullIdentifierCacheNeverReplaysDebitAnimations()
    {
        var currentIds = Enumerable.Range(1, 100).Select(value => (long)value).ToArray();
        var fillerIds = Enumerable.Range(1000, 500).Select(value => (long)value).ToArray();
        var usage = currentIds
            .Select(id => new UsageRecord(id, DateTimeOffset.Parse("2026-09-12T00:00:00Z").AddSeconds(id), new Money(0.01m)))
            .ToArray();
        var api = new FakeApiClient
        {
            Usage = usage
        };
        var auth = new AuthManager(api, new MemoryCredentialStore());
        await auth.LoginAsync("user@example.com", "password");
        var store = new MemorySnapshotStore();
        var service = new BalanceService(api, auth, store);

        // Seed a saturated (600 identifier) cache that already contains the usage page.
        await store.SaveAsync(new PersistedSnapshotState(
            new BalanceSnapshot(new Money(19.58m), null, null, DateTimeOffset.Parse("2026-09-12T00:00:00Z")),
            null,
            fillerIds.Concat(currentIds).ToList()));

        var first = await service.RefreshAsync();
        var second = await service.RefreshAsync();

        Assert.Empty(first.Events);
        Assert.Empty(second.Events);

        var persisted = store.State!;
        Assert.Equal(PersistedSnapshotState.MaximumRecentUsageIds, persisted.RecentUsageIds.Count);
        Assert.Equal(currentIds, persisted.RecentUsageIds.TakeLast(currentIds.Length));
        Assert.DoesNotContain(fillerIds[0], persisted.RecentUsageIds);
    }

    [Fact]
    public async Task NewUsageAfterASaturatedCacheStillProducesDebitsOnce()
    {
        var api = new FakeApiClient();
        var auth = new AuthManager(api, new MemoryCredentialStore());
        await auth.LoginAsync("user@example.com", "password");
        var store = new MemorySnapshotStore();
        var service = new BalanceService(api, auth, store);

        await store.SaveAsync(new PersistedSnapshotState(
            new BalanceSnapshot(new Money(19.58m), null, null, DateTimeOffset.Parse("2026-09-12T00:00:00Z")),
            null,
            Enumerable.Range(1000, 500).Select(value => (long)value).ToList()));

        api.Usage = [new UsageRecord(7, DateTimeOffset.Parse("2026-09-12T00:00:07Z"), new Money(0.30m))];
        api.User = api.User with { Balance = new Money(19.28m) };

        var first = await service.RefreshAsync();
        var second = await service.RefreshAsync();

        var debit = Assert.IsType<BalanceAnimationEvent.Debit>(Assert.Single(first.Events));
        Assert.Equal(0.30m, debit.Amount.Decimal);
        Assert.Empty(second.Events);
    }

    private sealed class MemorySnapshotStore : ISnapshotStore
    {
        public PersistedSnapshotState? State { get; private set; }

        public Task<PersistedSnapshotState?> LoadAsync(CancellationToken cancellationToken = default) => Task.FromResult(State);

        public Task SaveAsync(PersistedSnapshotState state, CancellationToken cancellationToken = default)
        {
            State = state;
            return Task.CompletedTask;
        }

        public Task ClearAsync(CancellationToken cancellationToken = default)
        {
            State = null;
            return Task.CompletedTask;
        }
    }

    private sealed class MemoryCredentialStore : ICredentialStore
    {
        private StoredCredential? _credential;
        public Task<StoredCredential?> LoadAsync(CancellationToken cancellationToken = default) => Task.FromResult(_credential);
        public Task SaveAsync(StoredCredential credential, CancellationToken cancellationToken = default)
        {
            _credential = credential;
            return Task.CompletedTask;
        }
        public Task DeleteAsync(CancellationToken cancellationToken = default)
        {
            _credential = null;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeApiClient : IApiClient
    {
        public CurrentUserDto User { get; set; } = new(42, "user@example.com", "Arisu", new Money(19.58m));
        public IReadOnlyList<UsageRecord> Usage { get; set; } = [];
        public AuthSession LoginSession { get; } = new("access", "refresh", DateTimeOffset.UtcNow.AddHours(1), 42);

        public Task<AuthSession> LoginAsync(string email, string password, CancellationToken cancellationToken = default)
            => Task.FromResult(LoginSession);

        public Task<AuthSession> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default)
            => Task.FromResult(LoginSession);

        public Task<CurrentUserDto> FetchCurrentUserAsync(string accessToken, CancellationToken cancellationToken = default)
            => Task.FromResult(User);

        public Task<DashboardStatsDto> FetchDashboardStatsAsync(string accessToken, CancellationToken cancellationToken = default)
            => Task.FromResult(new DashboardStatsDto(2, new Money(0.30m)));

        public Task<IReadOnlyList<UsageRecord>> FetchUsageAsync(string accessToken, int pageSize, CancellationToken cancellationToken = default)
            => Task.FromResult(Usage);
    }
}
