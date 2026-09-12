using LoeBalance.Core.Models;

namespace LoeBalance.Core.Animation;

public enum DamageSurface { Desktop, MenuBar }
public enum DamageMotionStyle { Debit, Credit }
public enum DamageMotionColor { Red, Green }

public sealed record DamageMotionPlan(
    BalanceAnimationEvent Event,
    TimeSpan LaunchDelay,
    TimeSpan Duration,
    double StartX,
    double MidX,
    double EndX,
    double Rise,
    double StartRotationDegrees,
    double EndRotationDegrees,
    ShakeStrength? ShakeStrength)
{
    public DamageMotionStyle Style => Event is BalanceAnimationEvent.Debit ? DamageMotionStyle.Debit : DamageMotionStyle.Credit;
    public DamageMotionColor Color => Style == DamageMotionStyle.Debit ? DamageMotionColor.Red : DamageMotionColor.Green;
}

public interface IMotionRandom
{
    double Value(double minimum, double maximum);
}

public sealed class SystemMotionRandom : IMotionRandom
{
    public double Value(double minimum, double maximum) => Random.Shared.NextDouble() * (maximum - minimum) + minimum;
}

public sealed class DamageAnimationPlanner
{
    private readonly IMotionRandom _random;

    public DamageAnimationPlanner(IMotionRandom? random = null) => _random = random ?? new SystemMotionRandom();

    public IReadOnlyList<DamageMotionPlan> Plan(
        IReadOnlyList<BalanceAnimationEvent> events,
        DamageSurface surface,
        ShakeStrength shake,
        bool reduceMotion)
    {
        var result = new List<DamageMotionPlan>(events.Count);
        var inDebitBurst = false;
        for (var index = 0; index < events.Count; index++)
        {
            var debit = events[index] is BalanceAnimationEvent.Debit;
            var startsBurst = debit && !inDebitBurst;
            inDebitBurst = debit;
            var ranges = surface == DamageSurface.Desktop
                ? new Ranges(-5, 5, -9, 9, -13, 13, reduceMotion ? 43 : 86, reduceMotion ? 50 : 100, -8, 8, reduceMotion ? 0.48 : 0.82)
                : new Ranges(-3, 3, -5, 5, -7, 7, reduceMotion ? 24 : 47, reduceMotion ? 28 : 55, -4, 4, reduceMotion ? 0.48 : 0.82);
            var planShake = surface == DamageSurface.Desktop && !reduceMotion && startsBurst && shake != ShakeStrength.Off ? shake : null;
            result.Add(new DamageMotionPlan(
                events[index], TimeSpan.FromSeconds(index * 0.23), TimeSpan.FromSeconds(ranges.Duration),
                _random.Value(ranges.StartMin, ranges.StartMax), _random.Value(ranges.MidMin, ranges.MidMax),
                _random.Value(ranges.EndMin, ranges.EndMax), _random.Value(ranges.RiseMin, ranges.RiseMax),
                _random.Value(ranges.RotationMin, ranges.RotationMax), _random.Value(ranges.RotationMin, ranges.RotationMax), planShake));
        }
        return result;
    }

    private sealed record Ranges(
        double StartMin, double StartMax, double MidMin, double MidMax, double EndMin, double EndMax,
        double RiseMin, double RiseMax, double RotationMin, double RotationMax, double Duration);
}
