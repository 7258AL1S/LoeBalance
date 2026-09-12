using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using LoeBalance.Core.Animation;
using LoeBalance.Core.Models;
using LoeBalance.Core.Persistence;
using LoeBalance.Desktop.Wpf.Interop;
using LoeBalance.Desktop.Wpf.Presentation;
using LoeBalance.Platform.Windows;
// WinForms is referenced for the tray icon, so System.Drawing and System.Windows.Media
// both define these types.
using Color = System.Windows.Media.Color;
using FontFamily = System.Windows.Media.FontFamily;

namespace LoeBalance.Desktop.Wpf.Views;

/// <summary>
/// The desktop card: a borderless, non-activating, never-topmost window that sits on the
/// desktop layer. It shows the detailed balance and plays the debit/credit stream. macOS
/// menu-bar shaking does not exist here — only the card itself shakes, and only when the
/// planner allows it.
/// </summary>
public partial class DesktopCardWindow : Window, IDesktopCardPresenter
{
    internal const double CardWidth = 326;
    internal const double CardHeight = 218;
    private const double MinimumBalanceFontSize = 14;
    private const double MinimumStatusFontSize = 9;

    private readonly DesktopCardPlacement _placement = new(CardWidth, CardHeight);
    private readonly Action<DesktopCardFrame>? _frameChanged;
    private readonly DispatcherTimer _frameSaveTimer;
    private IntPtr _handle;
    private bool _visible;
    private bool _disposed;

    internal DesktopCardWindow(DesktopCardFrame? savedFrame, Action<DesktopCardFrame>? frameChanged = null)
    {
        InitializeComponent();
        _frameChanged = frameChanged;
        _frameSaveTimer = new DispatcherTimer(DispatcherPriority.Background, Dispatcher)
        {
            Interval = TimeSpan.FromMilliseconds(400)
        };
        _frameSaveTimer.Tick += (_, _) =>
        {
            _frameSaveTimer.Stop();
            PersistFrame();
        };

        SourceInitialized += OnSourceInitialized;
        LocationChanged += (_, _) => ScheduleFrameSave();
        MouseLeftButtonDown += (_, _) =>
        {
            try
            {
                DragMove();
            }
            catch (InvalidOperationException)
            {
                // DragMove can fail if the button was already released; nothing to do.
            }
        };

        Present(new BalanceSnapshot(Money.Zero, null, null, DateTimeOffset.Now), new ConnectionState.Online());
        _savedFrame = savedFrame;
    }

    public void Present(BalanceSnapshot snapshot, ConnectionState connection)
    {
        BalanceText.Text = snapshot.Balance.CurrencyText;
        TodaySpendText.Text = snapshot.TodaySpend?.CurrencyText ?? "--";
        TodayRequestsText.Text = snapshot.TodayRequests?.ToString(CultureInfo.InvariantCulture) ?? "--";
        UpdatedText.Text = $"Updated {snapshot.UpdatedAt.ToLocalTime():HH:mm:ss}";
        ConnectionText.Text = ConnectionPresentation.Text(connection);
        ConnectionDot.Fill = new SolidColorBrush(ToMediaColor(ConnectionPresentation.Color(connection)));
        FitToWidth(BalanceText, 30, MinimumBalanceFontSize);
        FitToWidth(ConnectionText, 12, MinimumStatusFontSize);
    }

    public void Play(IReadOnlyList<DamageMotionPlan> plans)
    {
        if (plans.Count == 0) return;
        DamageStream.Play(plans);

        var shake = plans.Select(plan => plan.ShakeStrength).FirstOrDefault(static strength => strength is not null);
        if (shake is ShakeStrength strength && strength != ShakeStrength.Off)
        {
            PlayShake(strength);
        }
    }

    public void SetVisible(bool visible)
    {
        if (_disposed || visible == _visible) return;
        _visible = visible;

        if (visible)
        {
            // Create the window handle (and its per-monitor DPI) before solving the position
            // so the placement math uses the real scale factor instead of assuming 100%.
            EnsureHandle();
            var (frame, _) = _placement.Resolve(this, _savedFrame);
            DesktopCardPlacement.Apply(this, frame, sendToBottom: false);
            Show();
            DesktopCardPlacement.SendToBottom(this);
        }
        else
        {
            Hide();
            PersistFrame();
        }
    }

    /// <summary>Applies the persisted frame; called after the window handle exists.</summary>
    internal void ApplySavedPlacement(DesktopCardFrame? savedFrame)
    {
        EnsureHandle();
        var (frame, _) = _placement.Resolve(this, savedFrame);
        DesktopCardPlacement.Apply(this, frame, sendToBottom: false);
    }

    private void EnsureHandle()
    {
        if (_handle != IntPtr.Zero) return;
        _handle = new WindowInteropHelper(this).EnsureHandle();
    }

    internal void ReassertDesktopLayer()
    {
        if (_visible) DesktopCardPlacement.SendToBottom(this);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _frameSaveTimer.Stop();
        try
        {
            PersistFrame();
            Close();
        }
        catch (InvalidOperationException)
        {
            // The window was already closed during shutdown.
        }
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _handle = new WindowInteropHelper(this).Handle;

        // No taskbar button, never activates, stays out of Alt+Tab.
        var style = NativeMethods.GetWindowLongPtr(_handle, NativeMethods.GwlExStyle).ToInt64();
        style = (style | NativeMethods.WsExNoActivate | NativeMethods.WsExToolWindow) & ~NativeMethods.WsExAppWindow;
        NativeMethods.SetWindowLongPtr(_handle, NativeMethods.GwlExStyle, new IntPtr(style));

        var source = HwndSource.FromHwnd(_handle);
        source?.AddHook(WindowHook);
    }

    private IntPtr WindowHook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == NativeMethods.WmMouseActivate)
        {
            // Clicking the card must never pull focus away from the foreground window.
            handled = true;
            return new IntPtr(NativeMethods.MaNoActivate);
        }
        return IntPtr.Zero;
    }

    private void PlayShake(ShakeStrength strength)
    {
        var amplitude = strength == ShakeStrength.Strong ? 6d : 3d;
        var duration = TimeSpan.FromSeconds(strength == ShakeStrength.Strong ? 0.34 : 0.24);

        var animation = new DoubleAnimationUsingKeyFrames { Duration = duration, FillBehavior = FillBehavior.Stop };
        animation.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromPercent(0)));
        animation.KeyFrames.Add(new LinearDoubleKeyFrame(-amplitude, KeyTime.FromPercent(0.2)));
        animation.KeyFrames.Add(new LinearDoubleKeyFrame(amplitude, KeyTime.FromPercent(0.45)));
        animation.KeyFrames.Add(new LinearDoubleKeyFrame(-amplitude * 0.5, KeyTime.FromPercent(0.65)));
        animation.KeyFrames.Add(new LinearDoubleKeyFrame(amplitude * 0.35, KeyTime.FromPercent(0.85)));
        animation.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromPercent(1)));
        ShakeTransform.BeginAnimation(TranslateTransform.XProperty, animation);
    }

    private void ScheduleFrameSave()
    {
        if (_handle == IntPtr.Zero || !IsVisible) return;
        _frameSaveTimer.Stop();
        _frameSaveTimer.Start();
    }

    private void PersistFrame()
    {
        if (_frameChanged is null) return;
        var frame = DesktopCardPlacement.Capture(this);
        if (frame.Width > 0 && frame.Height > 0) _frameChanged(frame);
    }

    private static void FitToWidth(System.Windows.Controls.TextBlock text, double preferredSize, double minimumSize)
    {
        var available = text.ActualWidth > 0 ? text.ActualWidth : text.Width;
        if (available <= 0) return;

        var size = preferredSize;
        text.FontSize = size;
        while (Measure(text.Text, text.FontFamily, size, text.FontWeight) > available && size > minimumSize)
        {
            size = Math.Max(minimumSize, size - 0.5);
            text.FontSize = size;
        }
    }

    private static double Measure(string value, FontFamily family, double size, FontWeight weight)
    {
        if (string.IsNullOrEmpty(value)) return 0;
        var formatted = new FormattedText(
            value,
            CultureInfo.CurrentCulture,
            System.Windows.FlowDirection.LeftToRight,
            new Typeface(family, FontStyles.Normal, weight, FontStretches.Normal),
            size,
            System.Windows.Media.Brushes.White,
            1.0);
        return formatted.Width;
    }

    private static Color ToMediaColor(System.Drawing.Color color)
        => Color.FromRgb(color.R, color.G, color.B);

    private DesktopCardFrame? _savedFrame;

    internal void SetSavedFrame(DesktopCardFrame? frame) => _savedFrame = frame;
}
