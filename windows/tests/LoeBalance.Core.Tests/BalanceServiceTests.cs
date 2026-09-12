using LoeBalance.Core.Auth;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;
using LoeBalance.Core.Persistence;
using LoeBalance.Core.Refresh;

namespace LoeBalance.Core.Tests;

public sealed class BalanceServiceTests
{
    [Fact]
    public async Task SuppressesInitialAnimationAndFiltersPreviouslySeenUsage()
    {
        var api = new FakeApiClient
        {
            User = new CurrentUserDto(42, "user@example.com", "Arisu", new Money(19.50m)),
            Usage =
            [
                new UsageRecord(1, DateTimeOffset.Parse("2026-09-12T00:00:01Z"), new Money(0.20m)),
                new UsageRecord(2, DateTimeOffset.Parse("2026-09-12T00:00:02Z"), new Money(0.30m))
            ]
        };
        var auth = new AuthManager(api, new MemoryCredentialStore());
        await auth.LoginAsync("user@example.com", "password");
        var store = new MemorySnapshotStore();
        var service = new BalanceService(api, auth, store);

        var first = await service.RefreshAsync();
        Assert.Empty(first.Events);

        api.User = api.User with { Balance = new Money(19.20m) };
        var second = await service.RefreshAsync();

        Assert.Single(second.Events);
        Assert.Equal(0.30m, Assert.IsType<BalanceAnimationEvent.Debit>(second.Events[0]).Amount.Decimal);
    }

    private sealed class MemorySnapshotStore : ISnapshotStore
    {
        private PersistedSnapshotState? _state;
        public Task<PersistedSnapshotState?> LoadAsync(CancellationToken cancellationToken = default) => Task.FromResult(_state);
        public Task SaveAsync(PersistedSnapshotState state, CancellationToken cancellationToken = default)
        {
            _state = state;
            return Task.CompletedTask;
        }
        public Task ClearAsync(CancellationToken cancellationToken = default)
        {
            _state = null;
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
        public CurrentUserDto User { get; set; } = new(null, null, null, Money.Zero);
        public IReadOnlyList<UsageRecord> Usage { get; init; } = [];
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
