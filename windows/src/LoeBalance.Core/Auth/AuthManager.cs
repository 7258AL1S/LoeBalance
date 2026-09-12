using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;

namespace LoeBalance.Core.Auth;

public sealed class AuthManager
{
    // Matches the macOS `AuthManager.proactiveRefreshInterval`: refresh before the access
    // token actually expires so scheduled requests do not race the expiry deadline.
    private static readonly TimeSpan ProactiveRefreshInterval = TimeSpan.FromSeconds(60);

    private readonly IApiClient _api;
    private readonly ICredentialStore _credentials;
    private readonly Func<DateTimeOffset> _now;
    private readonly SemaphoreSlim _refreshLock = new(1, 1);
    private AuthSession? _session;

    public AuthManager(IApiClient api, ICredentialStore credentials, Func<DateTimeOffset>? now = null)
    {
        _api = api;
        _credentials = credentials;
        _now = now ?? (() => DateTimeOffset.UtcNow);
    }

    public async Task LoginAsync(string email, string password, CancellationToken cancellationToken = default)
    {
        var session = await _api.LoginAsync(email, password, cancellationToken);
        if (session.UserId is not long userId)
        {
            throw new AppException(AppErrorKind.InvalidResponse, "The login response contained no user id.");
        }
        await _credentials.SaveAsync(new StoredCredential(session.RefreshToken, userId), cancellationToken);
        _session = session;
    }

    public async Task<bool> RestoreSessionAsync(CancellationToken cancellationToken = default)
    {
        var stored = await _credentials.LoadAsync(cancellationToken);
        if (stored is null)
        {
            _session = null;
            return false;
        }

        _session = new AuthSession(string.Empty, stored.RefreshToken, DateTimeOffset.MinValue, stored.UserId);
        try
        {
            await RefreshSessionAsync(stored.RefreshToken, cancellationToken);
            return true;
        }
        catch (AppException exception) when (exception.Kind == AppErrorKind.Unauthorized)
        {
            await InvalidateSessionAsync(cancellationToken);
            return false;
        }
    }

    public async Task<T> WithAccessTokenAsync<T>(Func<string, Task<T>> operation, CancellationToken cancellationToken = default)
    {
        var session = await UsableSessionAsync(cancellationToken);
        try
        {
            return await operation(session.AccessToken);
        }
        catch (AppException exception) when (exception.Kind == AppErrorKind.Unauthorized)
        {
            // A 401 always forces a refresh-token exchange, even when the cached access
            // token still looks valid, and the original operation is replayed exactly once.
            var refreshed = await RefreshSessionAsync(session.RefreshToken, cancellationToken, force: true);
            return await operation(refreshed.AccessToken);
        }
    }

    public async Task LogoutAsync(CancellationToken cancellationToken = default)
    {
        await InvalidateSessionAsync(cancellationToken);
    }

    private async Task<AuthSession> UsableSessionAsync(CancellationToken cancellationToken)
    {
        if (_session is not { UserId: not null } session)
        {
            throw new AppException(AppErrorKind.Unauthorized, "No active session.");
        }
        if (session.ExpiresAt - _now() > ProactiveRefreshInterval) return session;
        return await RefreshSessionAsync(session.RefreshToken, cancellationToken);
    }

    private async Task<AuthSession> RefreshSessionAsync(
        string refreshToken,
        CancellationToken cancellationToken,
        bool force = false)
    {
        await _refreshLock.WaitAsync(cancellationToken);
        try
        {
            var expectedUserId = _session?.UserId;

            // Another caller already completed a refresh for a newer token.
            if (_session is { } current && current.RefreshToken != refreshToken) return current;
            if (!force && _session is { } fresh && fresh.ExpiresAt - _now() > ProactiveRefreshInterval) return fresh;

            var refreshed = await _api.RefreshAsync(refreshToken, cancellationToken);
            if (refreshed.UserId is long refreshedUserId && expectedUserId is long expected && refreshedUserId != expected)
            {
                await InvalidateSessionAsync(cancellationToken);
                throw new AppException(AppErrorKind.Unauthorized, "The refreshed session belongs to a different user.");
            }

            var userId = refreshed.UserId ?? expectedUserId
                ?? throw new AppException(AppErrorKind.InvalidResponse, "The refresh response contained no user id.");
            var verified = refreshed with { UserId = userId };
            await _credentials.SaveAsync(new StoredCredential(verified.RefreshToken, userId), cancellationToken);
            _session = verified;
            return verified;
        }
        finally
        {
            _refreshLock.Release();
        }
    }

    private async Task InvalidateSessionAsync(CancellationToken cancellationToken)
    {
        _session = null;
        await _credentials.DeleteAsync(cancellationToken);
    }
}
