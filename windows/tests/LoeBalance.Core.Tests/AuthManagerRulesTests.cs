using LoeBalance.Core.Auth;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;

namespace LoeBalance.Core.Tests;

/// <summary>
/// Coverage for the handoff rules: a 401 always forces a refresh-token exchange and a
/// single replay, only the refresh token plus user id are persisted, and a refreshed
/// session belonging to another user invalidates the session.
/// </summary>
public sealed class AuthManagerRulesTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-12T12:00:00Z");

    [Fact]
    public async Task UnauthorizedAlwaysRefreshesEvenWhenTheAccessTokenIsStillFresh()
    {
        var api = new FakeApiClient
        {
            LoginResult = new AuthSession("access-1", "refresh-1", Now.AddHours(4), 42),
            RefreshResult = new AuthSession("access-2", "refresh-2", Now.AddHours(4), 42)
        };
        var credentials = new MemoryCredentialStore();
        var manager = new AuthManager(api, credentials, () => Now);
        await manager.LoginAsync("user@example.com", "password");

        var attempts = new List<string>();
        var result = await manager.WithAccessTokenAsync(token =>
        {
            attempts.Add(token);
            return attempts.Count == 1
                ? Task.FromException<string>(new AppException(AppErrorKind.Unauthorized, "expired", statusCode: 401))
                : Task.FromResult(token);
        });

        Assert.Equal(["access-1", "access-2"], attempts);
        Assert.Equal("access-2", result);
        Assert.Equal(1, api.RefreshCalls);
        Assert.Equal(new StoredCredential("refresh-2", 42), credentials.Value);
    }

    [Fact]
    public async Task OnlyTheRefreshTokenAndUserIdArePersisted()
    {
        var api = new FakeApiClient
        {
            LoginResult = new AuthSession("access-1", "refresh-1", Now.AddHours(4), 42)
        };
        var credentials = new MemoryCredentialStore();
        var manager = new AuthManager(api, credentials, () => Now);

        await manager.LoginAsync("user@example.com", "hunter2-password");

        var stored = Assert.IsType<StoredCredential>(credentials.Value);
        Assert.Equal("refresh-1", stored.RefreshToken);
        Assert.Equal(42, stored.UserId);
        Assert.DoesNotContain("hunter2-password", stored.ToString(), StringComparison.Ordinal);
        Assert.DoesNotContain("access-1", stored.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task MissingUserIdOnLoginIsRejectedAndNothingIsStored()
    {
        var api = new FakeApiClient
        {
            LoginResult = new AuthSession("access-1", "refresh-1", Now.AddHours(4), null)
        };
        var credentials = new MemoryCredentialStore();
        var manager = new AuthManager(api, credentials, () => Now);

        var exception = await Assert.ThrowsAsync<AppException>(() => manager.LoginAsync("user@example.com", "password"));

        Assert.Equal(AppErrorKind.InvalidResponse, exception.Kind);
        Assert.Null(credentials.Value);
    }

    [Fact]
    public async Task RestoreSessionRefreshesAndPersistsTheRotatedRefreshToken()
    {
        var api = new FakeApiClient
        {
            RefreshResult = new AuthSession("access-2", "refresh-2", Now.AddHours(1), 42)
        };
        var credentials = new MemoryCredentialStore { Value = new StoredCredential("refresh-1", 42) };
        var manager = new AuthManager(api, credentials, () => Now);

        var restored = await manager.RestoreSessionAsync();

        Assert.True(restored);
        Assert.Equal(1, api.RefreshCalls);
        Assert.Equal(new StoredCredential("refresh-2", 42), credentials.Value);
    }

    [Fact]
    public async Task RestoreSessionDeletesCredentialsWhenTheRefreshTokenIsRejected()
    {
        var api = new FakeApiClient
        {
            RefreshFailure = new AppException(AppErrorKind.Unauthorized, "rejected", statusCode: 401)
        };
        var credentials = new MemoryCredentialStore { Value = new StoredCredential("refresh-1", 42) };
        var manager = new AuthManager(api, credentials, () => Now);

        var restored = await manager.RestoreSessionAsync();

        Assert.False(restored);
        Assert.Null(credentials.Value);
    }

    [Fact]
    public async Task RefreshedSessionForAnotherUserInvalidatesTheStoredCredential()
    {
        var api = new FakeApiClient
        {
            LoginResult = new AuthSession("access-1", "refresh-1", Now.AddHours(4), 42),
            RefreshResult = new AuthSession("access-2", "refresh-2", Now.AddHours(4), 99)
        };
        var credentials = new MemoryCredentialStore();
        var manager = new AuthManager(api, credentials, () => Now);
        await manager.LoginAsync("user@example.com", "password");

        var exception = await Assert.ThrowsAsync<AppException>(() =>
            manager.WithAccessTokenAsync<string>(_ => Task.FromException<string>(new AppException(AppErrorKind.Unauthorized, "expired"))));

        Assert.Equal(AppErrorKind.Unauthorized, exception.Kind);
        Assert.Null(credentials.Value);
    }

    [Fact]
    public async Task LogoutClearsTheStoredCredentialAndTheInMemorySession()
    {
        var api = new FakeApiClient
        {
            LoginResult = new AuthSession("access-1", "refresh-1", Now.AddHours(4), 42)
        };
        var credentials = new MemoryCredentialStore();
        var manager = new AuthManager(api, credentials, () => Now);
        await manager.LoginAsync("user@example.com", "password");

        await manager.LogoutAsync();

        Assert.Null(credentials.Value);
        await Assert.ThrowsAsync<AppException>(() => manager.WithAccessTokenAsync(_ => Task.FromResult("token")));
    }

    [Fact]
    public async Task ExpiringAccessTokenIsRefreshedProactively()
    {
        var api = new FakeApiClient
        {
            LoginResult = new AuthSession("access-1", "refresh-1", Now.AddSeconds(30), 42),
            RefreshResult = new AuthSession("access-2", "refresh-2", Now.AddHours(1), 42)
        };
        var manager = new AuthManager(api, new MemoryCredentialStore(), () => Now);
        await manager.LoginAsync("user@example.com", "password");

        var token = await manager.WithAccessTokenAsync(value => Task.FromResult(value));

        Assert.Equal("access-2", token);
        Assert.Equal(1, api.RefreshCalls);
    }

    private sealed class MemoryCredentialStore : ICredentialStore
    {
        public StoredCredential? Value { get; set; }
        public Task<StoredCredential?> LoadAsync(CancellationToken cancellationToken = default) => Task.FromResult(Value);
        public Task SaveAsync(StoredCredential credential, CancellationToken cancellationToken = default)
        {
            Value = credential;
            return Task.CompletedTask;
        }
        public Task DeleteAsync(CancellationToken cancellationToken = default)
        {
            Value = null;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeApiClient : IApiClient
    {
        public AuthSession LoginResult { get; init; } = new("access", "refresh", Now.AddHours(1), 42);
        public AuthSession RefreshResult { get; init; } = new("access", "refresh", Now.AddHours(1), 42);
        public AppException? RefreshFailure { get; init; }
        public int RefreshCalls { get; private set; }

        public Task<AuthSession> LoginAsync(string email, string password, CancellationToken cancellationToken = default)
            => Task.FromResult(LoginResult);

        public Task<AuthSession> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default)
        {
            RefreshCalls++;
            return RefreshFailure is null
                ? Task.FromResult(RefreshResult)
                : Task.FromException<AuthSession>(RefreshFailure);
        }

        public Task<CurrentUserDto> FetchCurrentUserAsync(string accessToken, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<DashboardStatsDto> FetchDashboardStatsAsync(string accessToken, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<UsageRecord>> FetchUsageAsync(string accessToken, int pageSize, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();
    }
}
