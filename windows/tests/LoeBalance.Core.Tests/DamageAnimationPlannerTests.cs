using LoeBalance.Core.Animation;
using LoeBalance.Core.Models;

namespace LoeBalance.Core.Tests;

public sealed class DamageAnimationPlannerTests
{
    [Fact]
    public void UsesSingleTrackDelaysAndDesktopShakeOnlyAtBurstStart()
    {
        var events = new BalanceAnimationEvent[]
        {
            new BalanceAnimationEvent.Debit(new Money(0.10m)),
            new BalanceAnimationEvent.Debit(new Money(0.20m)),
            new BalanceAnimationEvent.Credit(new Money(1m))
        };
        var plans = new DamageAnimationPlanner(new FixedRandom(0.5)).Plan(events, DamageSurface.Desktop, ShakeStrength.Strong, false);

        Assert.Equal(TimeSpan.Zero, plans[0].LaunchDelay);
        Assert.Equal(TimeSpan.FromSeconds(0.23), plans[1].LaunchDelay);
        Assert.Equal(ShakeStrength.Strong, plans[0].ShakeStrength);
        Assert.Null(plans[1].ShakeStrength);
        Assert.Equal(DamageMotionColor.Green, plans[2].Color);
    }

    [Fact]
    public void MenuBarNeverShakesAndReduceMotionShortensTravel()
    {
        var eventItem = new[] { new BalanceAnimationEvent.Debit(new Money(0.10m)) };
        var plan = new DamageAnimationPlanner(new FixedRandom(0.5)).Plan(eventItem, DamageSurface.MenuBar, ShakeStrength.Strong, true)[0];

        Assert.Null(plan.ShakeStrength);
        Assert.InRange(plan.Rise, 24, 28);
        Assert.Equal(TimeSpan.FromSeconds(0.48), plan.Duration);
    }

    private sealed class FixedRandom(double value) : IMotionRandom
    {
        public double Value(double minimum, double maximum) => minimum + ((maximum - minimum) * value);
    }
}
