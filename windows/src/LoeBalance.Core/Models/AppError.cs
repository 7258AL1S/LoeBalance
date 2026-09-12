namespace LoeBalance.Core.Models;

public enum AppErrorKind
{
    Transport,
    Unauthorized,
    RateLimited,
    ServerStatus,
    ApiEnvelope,
    InvalidResponse,
    InvalidUrl,
    CredentialStore
}

public sealed class AppException : Exception
{
    public AppErrorKind Kind { get; }
    public int? StatusCode { get; }
    public DateTimeOffset? RetryAfter { get; }

    public AppException(
        AppErrorKind kind,
        string message,
        Exception? innerException = null,
        int? statusCode = null,
        DateTimeOffset? retryAfter = null)
        : base(message, innerException)
    {
        Kind = kind;
        StatusCode = statusCode;
        RetryAfter = retryAfter;
    }
}
