using LoeBalance.Core.Models;

namespace LoeBalance.Core.Networking;

public sealed record AuthSession(
    string AccessToken,
    string RefreshToken,
    DateTimeOffset ExpiresAt,
    long? UserId);

public sealed record CurrentUserDto(long? Id, string? Email, string? Username, Money Balance);

public sealed record DashboardStatsDto(int TodayRequests, Money TodayActualCost);

public sealed record UsagePageDto(IReadOnlyList<UsageRecord> Items);

public sealed record StoredCredential(string RefreshToken, long UserId);

public interface IApiClient
{
    Task<AuthSession> LoginAsync(string email, string password, CancellationToken cancellationToken = default);
    Task<AuthSession> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default);
    Task<CurrentUserDto> FetchCurrentUserAsync(string accessToken, CancellationToken cancellationToken = default);
    Task<DashboardStatsDto> FetchDashboardStatsAsync(string accessToken, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<UsageRecord>> FetchUsageAsync(string accessToken, int pageSize, CancellationToken cancellationToken = default);
}
