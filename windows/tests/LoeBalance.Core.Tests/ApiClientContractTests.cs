using System.Net;
using System.Net.Http.Headers;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;

namespace LoeBalance.Core.Tests;

public sealed class ApiClientContractTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-12T12:00:00Z");

    [Fact]
    public async Task MapsUnauthorizedAndServerStatusErrors()
    {
        var unauthorized = CreateClient(new HttpResponseMessage(HttpStatusCode.Unauthorized));
        var unauthorizedError = await Assert.ThrowsAsync<AppException>(() => unauthorized.FetchCurrentUserAsync("access"));
        Assert.Equal(AppErrorKind.Unauthorized, unauthorizedError.Kind);
        Assert.Equal(401, unauthorizedError.StatusCode);

        var serverError = CreateClient(new HttpResponseMessage(HttpStatusCode.InternalServerError));
        var serverErrorResult = await Assert.ThrowsAsync<AppException>(() => serverError.FetchCurrentUserAsync("access"));
        Assert.Equal(AppErrorKind.ServerStatus, serverErrorResult.Kind);
        Assert.Equal(500, serverErrorResult.StatusCode);
    }

    [Fact]
    public async Task MapsApiEnvelopeFailures()
    {
        var client = CreateClient(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent("{\"code\":1001,\"message\":\"no balance\"}")
        });

        var error = await Assert.ThrowsAsync<AppException>(() => client.FetchCurrentUserAsync("access"));

        Assert.Equal(AppErrorKind.ApiEnvelope, error.Kind);
        Assert.Equal("no balance", error.Message);
    }

    [Fact]
    public async Task MapsTransportFailures()
    {
        using var httpClient = new HttpClient(new ThrowingHandler());
        var client = new ApiClient(httpClient);

        var error = await Assert.ThrowsAsync<AppException>(() => client.FetchCurrentUserAsync("access"));

        Assert.Equal(AppErrorKind.Transport, error.Kind);
    }

    [Fact]
    public async Task RateLimitHonorsBothDeltaAndHttpDateRetryAfterAndClampsNegatives()
    {
        var delta = CreateClient(RateLimited(TimeSpan.FromSeconds(4)));
        var deltaError = await Assert.ThrowsAsync<AppException>(() => delta.FetchCurrentUserAsync("access"));
        Assert.Equal(Now.AddSeconds(4), deltaError.RetryAfter);

        var httpDate = new DateTimeOffset(2026, 9, 12, 12, 30, 0, TimeSpan.Zero);
        var response = new HttpResponseMessage((HttpStatusCode)429) { Content = new StringContent("{}") };
        response.Headers.TryAddWithoutValidation("Retry-After", httpDate.ToString("R"));
        var dateClient = CreateClient(response);
        var dateError = await Assert.ThrowsAsync<AppException>(() => dateClient.FetchCurrentUserAsync("access"));
        Assert.Equal(httpDate, dateError.RetryAfter);

        var negative = CreateClient(RateLimited(TimeSpan.FromSeconds(-30)));
        var negativeError = await Assert.ThrowsAsync<AppException>(() => negative.FetchCurrentUserAsync("access"));
        Assert.Equal(Now, negativeError.RetryAfter);
    }

    [Fact]
    public async Task RefreshPostsSnakeCaseBodyWithJsonContentType()
    {
        HttpRequestMessage? captured = null;
        string? body = null;
        using var httpClient = new HttpClient(new CapturingHandler(async request =>
        {
            captured = request;
            body = request.Content is null ? null : await request.Content.ReadAsStringAsync();
            return Json("{\"code\":0,\"data\":{\"access_token\":\"a-2\",\"refresh_token\":\"r-2\",\"expires_in\":3600,\"user\":{\"id\":42}}}");
        }));
        var client = new ApiClient(httpClient, () => Now);

        var session = await client.RefreshAsync("refresh-1");

        Assert.Equal("/api/v1/auth/refresh", captured!.RequestUri!.AbsolutePath);
        Assert.Equal(HttpMethod.Post, captured.Method);
        Assert.Equal("application/json", captured.Content!.Headers.ContentType!.MediaType);
        Assert.Contains("\"refresh_token\":\"refresh-1\"", body, StringComparison.Ordinal);
        Assert.DoesNotContain("Bearer", body, StringComparison.Ordinal);
        Assert.Equal("r-2", session.RefreshToken);
        Assert.Equal(42, session.UserId);
        Assert.Equal(Now.AddSeconds(3600), session.ExpiresAt);
        Assert.Null(captured.Headers.Authorization);
    }

    [Fact]
    public async Task UsageRequestUsesPageOneAndRequestedPageSize()
    {
        HttpRequestMessage? captured = null;
        using var httpClient = new HttpClient(new CapturingHandler(request =>
        {
            captured = request;
            return Task.FromResult(Json("{\"code\":0,\"data\":{\"items\":[]}}"));
        }));
        var client = new ApiClient(httpClient);

        await client.FetchUsageAsync("access", 100);

        Assert.Contains("/api/v1/usage?page=1&page_size=100", captured!.RequestUri!.PathAndQuery, StringComparison.Ordinal);
    }

    private static ApiClient CreateClient(HttpResponseMessage response)
    {
        var httpClient = new HttpClient(new StubHandler(_ => response));
        return new ApiClient(httpClient, () => Now);
    }

    private static HttpResponseMessage RateLimited(TimeSpan retryAfter)
    {
        var response = new HttpResponseMessage((HttpStatusCode)429) { Content = new StringContent("{}") };
        response.Headers.RetryAfter = new RetryConditionHeaderValue(retryAfter);
        return response;
    }

    private static HttpResponseMessage Json(string json)
        => new(HttpStatusCode.OK) { Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json") };

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(responder(request));
    }

    private sealed class CapturingHandler(Func<HttpRequestMessage, Task<HttpResponseMessage>> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => responder(request);
    }

    private sealed class ThrowingHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromException<HttpResponseMessage>(new HttpRequestException("no network"));
    }
}
