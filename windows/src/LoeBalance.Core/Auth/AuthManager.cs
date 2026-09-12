using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;

namespace LoeBalance.Core.Auth;

public sealed class AuthManager
{
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
        if (stored is null) return false;

        try
        {
            await RefreshSessionAsync(stored.RefreshToken, cancellationToken);
            return true;
        }
        catch (AppException exception) when (exception.Kind == AppErrorKind.Unauthorized)
        {
            await _credentials.DeleteAsync(cancellationToken);
            _session = null;
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
            var refreshed = await RefreshSessionAsync(session.RefreshToken, cancellationToken, force: true);
            return await operation(refreshed.AccessToken);
        }
    }

    public async Task LogoutAsync(CancellationToken cancellationToken = default)
    {
        _session = null;
        await _credentials.DeleteAsync(cancellationToken);
    }

    private async Task<AuthSession> UsableSessionAsync(CancellationToken cancellationToken)
    {
        if (_session is null)
        {
            throw new AppException(AppErrorKind.Unauthorized, "No active session.");
        }
        if (_session.ExpiresAt - _now() > TimeSpan.FromMinutes(2)) return _session;
        return await RefreshSessionAsync(_session.RefreshToken, cancellationToken);
    }

    private async Task<AuthSession> RefreshSessionAsync(
        string refreshToken,
        CancellationToken cancellationToken,
        bool force = false)
    {
        await _refreshLock.WaitAsync(cancellationToken);
        try
        {
            if (_session is not null && _session.RefreshToken != refreshToken) return _session;
            if (!force && _session is not null && _session.ExpiresAt - _now() > TimeSpan.FromMinutes(2)) return _session;
            var refreshed = await _api.RefreshAsync(refreshToken, cancellationToken);
            _session = refreshed;
            if (refreshed.UserId is long userId)
            {
                await _credentials.SaveAsync(new StoredCredential(refreshed.RefreshToken, userId), cancellationToken);
            }
            return refreshed;
        }
        finally
        {
            _refreshLock.Release();
        }
    }
}
