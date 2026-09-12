using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;
using LoeBalance.Core.Auth;

namespace LoeBalance.Core.Tests;

public sealed class AuthManagerTests
{
    [Fact]
    public async Task RefreshesOnceAndReplaysUnauthorizedOperation()
    {
        var api = new FakeApiClient
        {
            LoginResult = new AuthSession("access-1", "refresh-1", DateTimeOffset.UtcNow.AddHours(1), 42),
            RefreshResult = new AuthSession("access-2", "refresh-2", DateTimeOffset.UtcNow.AddHours(1), 42)
        };
        var credentials = new MemoryCredentialStore();
        var manager = new AuthManager(api, credentials);
        await manager.LoginAsync("user@example.com", "password");

        var attempts = 0;
        var result = await manager.WithAccessTokenAsync(token =>
        {
            attempts++;
            if (attempts == 1) throw new AppException(AppErrorKind.Unauthorized, "expired");
            return Task.FromResult(token);
        });

        Assert.Equal("access-2", result);
        Assert.Equal(2, attempts);
        Assert.Equal(1, api.RefreshCalls);
        Assert.Equal("refresh-2", credentials.Value!.RefreshToken);
    }

    private sealed class MemoryCredentialStore : ICredentialStore
    {
        public StoredCredential? Value { get; private set; }
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
        public AuthSession LoginResult { get; init; } = new("", "", DateTimeOffset.UtcNow, null);
        public AuthSession RefreshResult { get; init; } = new("", "", DateTimeOffset.UtcNow, null);
        public int RefreshCalls { get; private set; }

        public Task<AuthSession> LoginAsync(string email, string password, CancellationToken cancellationToken = default)
            => Task.FromResult(LoginResult);

        public Task<AuthSession> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default)
        {
            RefreshCalls++;
            return Task.FromResult(RefreshResult);
        }

        public Task<CurrentUserDto> FetchCurrentUserAsync(string accessToken, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<DashboardStatsDto> FetchDashboardStatsAsync(string accessToken, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();

        public Task<IReadOnlyList<UsageRecord>> FetchUsageAsync(string accessToken, int pageSize, CancellationToken cancellationToken = default)
            => throw new NotSupportedException();
    }
}
