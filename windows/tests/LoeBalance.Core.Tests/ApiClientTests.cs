using System.Net;
using System.Net.Http.Headers;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;

namespace LoeBalance.Core.Tests;

public sealed class ApiClientTests
{
    [Fact]
    public async Task SendsExpectedPathsHeadersAndParsesEnvelope()
    {
        var requests = new List<HttpRequestMessage>();
        using var httpClient = new HttpClient(new StubHandler(request =>
        {
            requests.Add(request);
            var json = request.RequestUri!.AbsolutePath.EndsWith("/auth/me", StringComparison.Ordinal)
                ? "{\"code\":0,\"data\":{\"id\":42,\"email\":\"user@example.com\",\"username\":\"Arisu\",\"balance\":\"19.58\"}}"
                : "{\"code\":0,\"data\":{\"today_requests\":11,\"today_actual_cost\":0.30}}";
            return JsonResponse(json);
        }));
        var client = new ApiClient(httpClient);

        var user = await client.FetchCurrentUserAsync("access-token");
        var stats = await client.FetchDashboardStatsAsync("access-token");

        Assert.Equal(42L, user.Id);
        Assert.Equal(19.58m, user.Balance.Decimal);
        Assert.Equal(11, stats.TodayRequests);
        Assert.Equal(2, requests.Count);
        Assert.All(requests, request =>
        {
            Assert.Equal(HttpMethod.Get, request.Method);
            Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
            Assert.Equal("access-token", request.Headers.Authorization?.Parameter);
            Assert.Equal("zh", request.Headers.GetValues("Accept-Language").Single());
            Assert.Equal("1", request.Headers.GetValues("X-User-UI-Request").Single());
        });
        Assert.EndsWith("/auth/me", requests[0].RequestUri!.AbsolutePath);
        Assert.EndsWith("/usage/dashboard/stats", requests[1].RequestUri!.AbsolutePath);
    }

    [Fact]
    public async Task ParsesLoginAndUsageQuery()
    {
        HttpRequestMessage? captured = null;
        using var httpClient = new HttpClient(new StubHandler(request =>
        {
            captured = request;
            var json = request.RequestUri!.AbsolutePath.EndsWith("/auth/login", StringComparison.Ordinal)
                ? "{\"code\":0,\"data\":{\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"user\":{\"id\":42}}}"
                : "{\"code\":0,\"data\":{\"items\":[{\"id\":7,\"created_at\":\"2026-09-12T00:00:00Z\",\"actual_cost\":0.30}]}}";
            return JsonResponse(json);
        }));
        var client = new ApiClient(httpClient);

        var session = await client.LoginAsync("user@example.com", "password");
        var usage = await client.FetchUsageAsync(session.AccessToken, 100);

        Assert.Equal("refresh", session.RefreshToken);
        Assert.Equal(42L, session.UserId);
        Assert.Single(usage);
        Assert.Contains("/usage?page=1&page_size=100", captured!.RequestUri!.PathAndQuery);
    }

    [Fact]
    public async Task MapsRateLimitAndMalformedJson()
    {
        var now = new DateTimeOffset(2026, 9, 12, 12, 0, 0, TimeSpan.Zero);
        using var rateLimitedClient = new HttpClient(new StubHandler(_ =>
        {
            var response = new HttpResponseMessage((HttpStatusCode)429)
            {
                Content = new StringContent("{\"code\":429}")
            };
            response.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(4));
            return response;
        }));
        var rateLimitedApi = new ApiClient(rateLimitedClient, () => now);
        var rateLimit = await Assert.ThrowsAsync<AppException>(() => rateLimitedApi.FetchCurrentUserAsync("access"));

        Assert.Equal(AppErrorKind.RateLimited, rateLimit.Kind);
        Assert.Equal(now.AddSeconds(4), rateLimit.RetryAfter);

        using var malformedClient = new HttpClient(new StubHandler(_ => JsonResponse("not-json")));
        var malformedApi = new ApiClient(malformedClient);
        var malformed = await Assert.ThrowsAsync<AppException>(() => malformedApi.FetchCurrentUserAsync("access"));
        Assert.Equal(AppErrorKind.InvalidResponse, malformed.Kind);
    }

    private static HttpResponseMessage JsonResponse(string json)
        => new(HttpStatusCode.OK) { Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json") };

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(responder(request));
    }
}
