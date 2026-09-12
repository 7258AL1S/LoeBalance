using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using LoeBalance.Core.Animation;
using LoeBalance.Core.Models;
// The WPF shell also references WinForms (tray icon), which brings System.Drawing into
// scope. These aliases keep the animation code unambiguous.
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace LoeBalance.Desktop.Wpf.Views;

/// <summary>
/// Renders the debit/credit stream: one visual track, short fixed launch delays, random
/// horizontal offsets inside the planner's bounded range, and no waiting for the previous
/// number to finish. The card surface alone is allowed to shake.
/// </summary>
public sealed class DamageStreamCanvas : Canvas
{
    internal const double StreamWidth = 92;
    internal const double StreamHeight = 42;

    private static readonly Brush DebitBrush = new SolidColorBrush(Color.FromRgb(0xFF, 0x45, 0x3A));
    private static readonly Brush CreditBrush = new SolidColorBrush(Color.FromRgb(0x30, 0xD1, 0x58));

    static DamageStreamCanvas()
    {
        DebitBrush.Freeze();
        CreditBrush.Freeze();
    }

    /// <summary>Plays one animation per plan; existing numbers keep running.</summary>
    public void Play(IReadOnlyList<DamageMotionPlan> plans)
    {
        if (plans.Count == 0) return;
        var anchor = new Point(ActualWidth > 0 ? ActualWidth / 2 : StreamWidth / 2, ActualHeight > 0 ? ActualHeight / 2 : StreamHeight / 2);

        foreach (var plan in plans)
        {
            Play(plan, anchor);
        }
    }

    public static string Label(BalanceAnimationEvent animationEvent) => animationEvent switch
    {
        BalanceAnimationEvent.Debit debit => $"-{debit.Amount.Magnitude.CurrencyText}",
        BalanceAnimationEvent.Credit credit => $"+{credit.Amount.Magnitude.CurrencyText}",
        _ => string.Empty
    };

    private void Play(DamageMotionPlan plan, Point anchor)
    {
        var text = new TextBlock
        {
            Width = StreamWidth,
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            Foreground = plan.Color == DamageMotionColor.Red ? DebitBrush : CreditBrush,
            Text = Label(plan.Event),
            TextAlignment = TextAlignment.Center,
            IsHitTestVisible = false,
            Opacity = 0
        };

        var translate = new TranslateTransform();
        var scale = new ScaleTransform(0.86, 0.86);
        var rotate = new RotateTransform(0);
        var group = new TransformGroup();
        group.Children.Add(scale);
        group.Children.Add(rotate);
        group.Children.Add(translate);
        text.RenderTransform = group;
        text.RenderTransformOrigin = new Point(0.5, 0.5);

        SetLeft(text, anchor.X - StreamWidth / 2);
        SetTop(text, anchor.Y - 10);
        Children.Add(text);

        // WPF grows downward, so a positive planner "rise" becomes a negative Y offset.
        var duration = plan.Duration;
        var position = new DoubleAnimationUsingKeyFrames { Duration = duration, BeginTime = plan.LaunchDelay, FillBehavior = FillBehavior.Stop };
        position.KeyFrames.Add(KeyFrame(0, 0));
        position.KeyFrames.Add(KeyFrame(plan.StartX, 0.15));
        position.KeyFrames.Add(KeyFrame(plan.MidX, 0.55));
        position.KeyFrames.Add(KeyFrame(plan.EndX, 1));

        var rise = new DoubleAnimationUsingKeyFrames { Duration = duration, BeginTime = plan.LaunchDelay, FillBehavior = FillBehavior.Stop };
        rise.KeyFrames.Add(KeyFrame(0, 0));
        rise.KeyFrames.Add(KeyFrame(-plan.Rise * 0.08, 0.15));
        rise.KeyFrames.Add(KeyFrame(-plan.Rise * 0.55, 0.55));
        rise.KeyFrames.Add(KeyFrame(-plan.Rise, 1));

        var opacity = new DoubleAnimationUsingKeyFrames { Duration = duration, BeginTime = plan.LaunchDelay, FillBehavior = FillBehavior.Stop };
        opacity.KeyFrames.Add(KeyFrame(0, 0));
        opacity.KeyFrames.Add(KeyFrame(1, 0.12));
        opacity.KeyFrames.Add(KeyFrame(1, 0.72));
        opacity.KeyFrames.Add(KeyFrame(0, 1));

        var scaleX = new DoubleAnimationUsingKeyFrames { Duration = duration, BeginTime = plan.LaunchDelay, FillBehavior = FillBehavior.Stop };
        var scaleY = new DoubleAnimationUsingKeyFrames { Duration = duration, BeginTime = plan.LaunchDelay, FillBehavior = FillBehavior.Stop };
        foreach (var frames in new[] { scaleX, scaleY })
        {
            frames.KeyFrames.Add(KeyFrame(0.86, 0));
            frames.KeyFrames.Add(KeyFrame(1.0, 0.14));
            frames.KeyFrames.Add(KeyFrame(1.0, 0.72));
            frames.KeyFrames.Add(KeyFrame(0.96, 1));
        }

        var rotation = new DoubleAnimationUsingKeyFrames { Duration = duration, BeginTime = plan.LaunchDelay, FillBehavior = FillBehavior.Stop };
        rotation.KeyFrames.Add(KeyFrame(0, 0));
        rotation.KeyFrames.Add(KeyFrame(plan.StartRotationDegrees, 0.15));
        rotation.KeyFrames.Add(KeyFrame(plan.EndRotationDegrees, 0.72));
        rotation.KeyFrames.Add(KeyFrame(plan.EndRotationDegrees, 1));

        opacity.Completed += (_, _) => Children.Remove(text);

        text.BeginAnimation(OpacityProperty, opacity);
        translate.BeginAnimation(TranslateTransform.XProperty, position);
        translate.BeginAnimation(TranslateTransform.YProperty, rise);
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, scaleX);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, scaleY);
        rotate.BeginAnimation(RotateTransform.AngleProperty, rotation);
    }

    private static SplineDoubleKeyFrame KeyFrame(double value, double keyTime)
        => new(value, KeyTime.FromPercent(keyTime), new KeySpline(0.42, 0, 0.58, 1));
}
