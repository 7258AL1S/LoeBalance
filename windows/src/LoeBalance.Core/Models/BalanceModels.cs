namespace LoeBalance.Core.Models;

public abstract record BalanceAnimationEvent
{
    public sealed record Debit(Money Amount) : BalanceAnimationEvent;
    public sealed record Credit(Money Amount) : BalanceAnimationEvent;
}

public sealed record BalanceSnapshot(
    Money Balance,
    Money? TodaySpend,
    int? TodayRequests,
    DateTimeOffset UpdatedAt);

public sealed record UsageRecord(
    long Id,
    DateTimeOffset CreatedAt,
    Money ActualCost);

public sealed record RefreshResult(
    BalanceSnapshot Snapshot,
    IReadOnlyList<BalanceAnimationEvent> Events,
    ConnectionState ConnectionState);

public abstract record ConnectionState
{
    public sealed record Online : ConnectionState;
    public sealed record Offline : ConnectionState;
    public sealed record RateLimited(DateTimeOffset? Until) : ConnectionState;
    public sealed record LoginRequired : ConnectionState;
    public sealed record InvalidData : ConnectionState;
}

public enum ShakeStrength
{
    Off,
    Weak,
    Strong
}
