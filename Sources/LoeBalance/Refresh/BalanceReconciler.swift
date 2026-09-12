import Foundation

struct BalanceReconciler: Sendable {
    let tolerance = Money(decimal: 0.0001)

    func reconcile(
        previousBalance: Money,
        currentBalance: Money,
        unseenUsage: [UsageRecord]
    ) -> [BalanceAnimationEvent] {
        let sorted = unseenUsage.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let debitTotal = sorted.reduce(.zero) { $0 + $1.actualCost }
        var events = debitEvents(from: sorted)
        let residual = (currentBalance - previousBalance) + debitTotal
        if residual > tolerance {
            events.append(.credit(residual))
        } else if residual < Money(decimal: -tolerance.decimal) {
            events.append(.debit(residual.magnitude))
        }
        return events
    }

    func debitEvents(from usage: [UsageRecord]) -> [BalanceAnimationEvent] {
        guard usage.count > 20 else {
            return usage.map { .debit($0.actualCost) }
        }

        let individual = usage.prefix(19).map { BalanceAnimationEvent.debit($0.actualCost) }
        let remainder = usage.dropFirst(19).reduce(.zero) { $0 + $1.actualCost }
        return individual + [.debit(remainder)]
    }
}
