using LoeBalance.Core.Models;

namespace LoeBalance.Core.Refresh;

public sealed class BalanceReconciler
{
    private static readonly Money Tolerance = new(0.0001m);

    public IReadOnlyList<BalanceAnimationEvent> Reconcile(
        Money previousBalance,
        Money currentBalance,
        IEnumerable<UsageRecord> unseenUsage)
    {
        var sorted = unseenUsage.OrderBy(record => record.CreatedAt).ThenBy(record => record.Id).ToArray();
        var debitTotal = sorted.Aggregate(Money.Zero, (total, record) => total + record.ActualCost);
        var events = DebitEvents(sorted).ToList();
        var residual = currentBalance - previousBalance + debitTotal;
        if (residual > Tolerance) events.Add(new BalanceAnimationEvent.Credit(residual));
        else if (residual < new Money(-Tolerance.Decimal)) events.Add(new BalanceAnimationEvent.Debit(residual.Magnitude));
        return events;
    }

    public IReadOnlyList<BalanceAnimationEvent> DebitEvents(IReadOnlyList<UsageRecord> usage)
    {
        if (usage.Count <= 20) return usage.Select(record => new BalanceAnimationEvent.Debit(record.ActualCost)).ToArray();
        var individual = usage.Take(19).Select(record => new BalanceAnimationEvent.Debit(record.ActualCost)).ToList();
        var remainder = usage.Skip(19).Aggregate(Money.Zero, (total, record) => total + record.ActualCost);
        individual.Add(new BalanceAnimationEvent.Debit(remainder));
        return individual;
    }
}
