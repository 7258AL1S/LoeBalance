using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using LoeBalance.Core.Models;

namespace LoeBalance.Core.Networking;

public sealed class ApiClient : IApiClient
{
    public const string BaseUrl = "https://api.loe.cx/api/v1";

    private readonly HttpClient _httpClient;
    private readonly Func<DateTimeOffset> _now;
    private readonly JsonSerializerOptions _jsonOptions;

    public ApiClient(HttpClient httpClient, Func<DateTimeOffset>? now = null)
    {
        _httpClient = httpClient;
        _httpClient.BaseAddress ??= new Uri(BaseUrl + "/");
        _httpClient.Timeout = TimeSpan.FromSeconds(30);
        _now = now ?? (() => DateTimeOffset.UtcNow);
        _jsonOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
            PropertyNameCaseInsensitive = true
        };
    }

    public async Task<AuthSession> LoginAsync(string email, string password, CancellationToken cancellationToken = default)
    {
        var response = await SendAsync<AuthSessionResponse>(HttpMethod.Post, "auth/login", new { email, password }, null, cancellationToken);
        return ToSession(response);
    }

    public async Task<AuthSession> RefreshAsync(string refreshToken, CancellationToken cancellationToken = default)
    {
        var response = await SendAsync<AuthSessionResponse>(HttpMethod.Post, "auth/refresh", new { refresh_token = refreshToken }, null, cancellationToken);
        return ToSession(response);
    }

    public Task<CurrentUserDto> FetchCurrentUserAsync(string accessToken, CancellationToken cancellationToken = default)
        => SendAsync<CurrentUserDto>(HttpMethod.Get, "auth/me", null, accessToken, cancellationToken);

    public Task<DashboardStatsDto> FetchDashboardStatsAsync(string accessToken, CancellationToken cancellationToken = default)
        => SendAsync<DashboardStatsDto>(HttpMethod.Get, "usage/dashboard/stats", null, accessToken, cancellationToken);

    public async Task<IReadOnlyList<UsageRecord>> FetchUsageAsync(string accessToken, int pageSize, CancellationToken cancellationToken = default)
    {
        var payload = await SendAsync<UsagePageDto>(
            HttpMethod.Get,
            $"usage?page=1&page_size={pageSize}",
            null,
            accessToken,
            cancellationToken);
        return payload.Items;
    }

    private async Task<T> SendAsync<T>(
        HttpMethod method,
        string path,
        object? body,
        string? accessToken,
        CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(method, path);
        if (body is not null)
        {
            request.Content = JsonContent.Create(body, options: _jsonOptions);
        }
        if (accessToken is not null)
        {
            request.Headers.Authorization = new("Bearer", accessToken);
            request.Headers.TryAddWithoutValidation("Accept-Language", "zh");
            request.Headers.TryAddWithoutValidation("X-User-UI-Request", "1");
        }

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, cancellationToken);
        }
        catch (HttpRequestException exception)
        {
            throw new AppException(AppErrorKind.Transport, "The network request failed.", exception);
        }

        try
        {
            await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            var retryAfter = ParseRetryAfter(response);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
            {
                throw new AppException(AppErrorKind.Unauthorized, "Authentication is required.", statusCode: 401);
            }
            if (response.StatusCode == (HttpStatusCode)429)
            {
                throw new AppException(AppErrorKind.RateLimited, "The server rate-limited the request.", statusCode: 429, retryAfter: retryAfter);
            }
            if (!response.IsSuccessStatusCode)
            {
                throw new AppException(AppErrorKind.ServerStatus, $"The server returned {(int)response.StatusCode}.", statusCode: (int)response.StatusCode);
            }

            var envelope = await JsonSerializer.DeserializeAsync<ApiEnvelope<T>>(stream, _jsonOptions, cancellationToken);
            if (envelope is null || envelope.Code != 0)
            {
                throw new AppException(AppErrorKind.ApiEnvelope, envelope?.Message ?? "The API returned an error.");
            }
            return envelope.Data ?? throw new AppException(AppErrorKind.InvalidResponse, "The API response contained no data.");
        }
        catch (JsonException exception)
        {
            throw new AppException(AppErrorKind.InvalidResponse, "The server response was invalid.", exception);
        }
        finally
        {
            response.Dispose();
        }
    }

    private AuthSession ToSession(AuthSessionResponse response)
    {
        if (string.IsNullOrWhiteSpace(response.AccessToken) || string.IsNullOrWhiteSpace(response.RefreshToken))
        {
            throw new AppException(AppErrorKind.InvalidResponse, "The authentication response contained no tokens.");
        }
        return new AuthSession(
            response.AccessToken,
            response.RefreshToken,
            _now().AddSeconds(response.ExpiresIn),
            response.User?.Id);
    }

    private DateTimeOffset? ParseRetryAfter(HttpResponseMessage response)
    {
        var retryAfter = response.Headers.RetryAfter;
        if (retryAfter is null) return null;
        // The macOS client clamps negative deltas to "now" so a past deadline is treated
        // as an exhausted rate limit instead of a deadline in the past.
        if (retryAfter.Delta is TimeSpan delta) return _now().Add(delta < TimeSpan.Zero ? TimeSpan.Zero : delta);
        return retryAfter.Date;
    }

    private sealed record ApiEnvelope<T>(int Code, T? Data, string? Message);

    private sealed record AuthSessionResponse(
        string AccessToken,
        string RefreshToken,
        double ExpiresIn,
        AuthUser? User);

    private sealed record AuthUser(long Id);
}
