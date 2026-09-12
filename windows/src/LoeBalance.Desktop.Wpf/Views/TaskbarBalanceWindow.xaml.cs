using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using LoeBalance.Core.Models;
using LoeBalance.Core.Presentation;
using LoeBalance.Desktop.Wpf.Interop;
using LoeBalance.Desktop.Wpf.Presentation;
// WinForms is referenced for the tray icon, so System.Drawing and System.Windows.Media both
// define these types.
using Color = System.Windows.Media.Color;

namespace LoeBalance.Desktop.Wpf.Views;

/// <summary>
/// Small balance readout docked against the notification area of the Windows taskbar.
///
/// Windows has no supported way to add text to the taskbar (deskbands were removed in
/// Windows 11), so this is a topmost, non-activating overlay window positioned on the taskbar
/// strip: left of the tray/clock on horizontal taskbars and above it on vertical ones.
///
/// The readout shows a static balance only. It never shakes and never carries the floating
/// debit/credit numbers, which stay on the desktop card.
/// </summary>
public partial class TaskbarBalanceWindow : Window, IDisposable
{
    private const double DotWidth = 7;
    private const double DotMargin = 5;
    private const double HorizontalPadding = 14;
    private const double MinimumWidth = 54;

    private readonly DispatcherTimer _layoutTimer;
    private readonly Action _openMenu;
    private BalanceSnapshot? _snapshot;
    private ConnectionState _connection = new ConnectionState.Online();
    private IntPtr _handle;
    private bool _visible;
    private bool _disposed;
    private bool _hiddenForFullScreen;

    internal TaskbarBalanceWindow(Action openMenu)
    {
        InitializeComponent();
        _openMenu = openMenu;
        _layoutTimer = new DispatcherTimer(DispatcherPriority.Background, Dispatcher)
        {
            Interval = TimeSpan.FromSeconds(1)
        };
        _layoutTimer.Tick += (_, _) => RefreshPlacement();

        SourceInitialized += OnSourceInitialized;
        MouseLeftButtonUp += OnMouseLeftButtonUp;
        Present(new BalanceSnapshot(Money.Zero, null, null, DateTimeOffset.Now), new ConnectionState.Online());
    }

    public void Present(BalanceSnapshot snapshot, ConnectionState connection)
    {
        _snapshot = snapshot;
        _connection = connection;
        BalanceText.Text = snapshot.Balance.CurrencyText;
        ConnectionDot.Fill = new SolidColorBrush(ToMediaColor(ConnectionPresentation.Color(connection)));
        ReadoutSurface.ToolTip =
            $"{snapshot.Balance.CurrencyText} · {ConnectionPresentation.Text(connection)} · Updated {snapshot.UpdatedAt.ToLocalTime():HH:mm:ss}";
        ResizeToContent();
        RefreshPlacement();
    }

    public void SetVisible(bool visible)
    {
        if (_disposed || visible == _visible) return;
        _visible = visible;

        // The placement math and the extended styles need a real HWND, and a WPF window only
        // gets one when it is shown. Create it up front, otherwise Show() would happen after
        // the position was already discarded.
        EnsureHandle();
        ApplyVisibility();
        if (visible) _layoutTimer.Start();
        else _layoutTimer.Stop();
    }

    private void EnsureHandle()
    {
        if (_handle != IntPtr.Zero) return;
        _handle = new WindowInteropHelper(this).EnsureHandle();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _layoutTimer.Stop();
        try
        {
            Close();
        }
        catch (InvalidOperationException)
        {
            // Already closed during shutdown.
        }
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        _handle = new WindowInteropHelper(this).Handle;

        var style = NativeMethods.GetWindowLongPtr(_handle, NativeMethods.GwlExStyle).ToInt64();
        style = (style | NativeMethods.WsExNoActivate | NativeMethods.WsExToolWindow) & ~NativeMethods.WsExAppWindow;
        NativeMethods.SetWindowLongPtr(_handle, NativeMethods.GwlExStyle, new IntPtr(style));

        HwndSource.FromHwnd(_handle)?.AddHook(WindowHook);
    }

    private IntPtr WindowHook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == NativeMethods.WmMouseActivate)
        {
            // Clicking the readout must not take focus from the foreground window.
            handled = true;
            return new IntPtr(NativeMethods.MaNoActivate);
        }
        return IntPtr.Zero;
    }

    private void OnMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        e.Handled = true;
        _openMenu();
    }

    private void ResizeToContent()
    {
        var textWidth = Measure(BalanceText.Text);
        Width = Math.Max(MinimumWidth, HorizontalPadding + DotWidth + DotMargin + textWidth);
        Height = 24;
    }

    private static double Measure(string value)
    {
        if (string.IsNullOrEmpty(value)) return 0;
        var formatted = new FormattedText(
            value,
            System.Globalization.CultureInfo.CurrentCulture,
            System.Windows.FlowDirection.LeftToRight,
            new Typeface(new System.Windows.Media.FontFamily("Consolas, Segoe UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal),
            12,
            System.Windows.Media.Brushes.White,
            1.0);
        return formatted.Width;
    }

    /// <summary>Recomputes the dock position; also re-asserts topmost so the taskbar stays below.</summary>
    private void RefreshPlacement()
    {
        if (_disposed) return;
        EnsureHandle();
        if (_handle == IntPtr.Zero) return;

        var shouldHide = TaskbarInterop.ShouldHideForFullScreen();
        if (shouldHide != _hiddenForFullScreen)
        {
            _hiddenForFullScreen = shouldHide;
            ApplyVisibility();
        }
        if (shouldHide) return;

        var taskbar = TaskbarInterop.PrimaryTaskbar;
        if (!TaskbarInterop.TryGetTaskbarRect(taskbar, out var taskbarRect) || taskbarRect.Right - taskbarRect.Left <= 0)
        {
            // Explorer is restarting: stay hidden until the taskbar comes back.
            Hide();
            return;
        }

        var scale = ScaleFactor();
        var taskbarDip = ToDip(taskbarRect, scale);
        var monitorRect = MonitorRect(taskbar);
        var edge = TaskbarBalanceGeometry.EdgeFor(ToDip(monitorRect, scale), taskbarDip);

        var trayDip = TaskbarInterop.TryGetWindowRect(TaskbarInterop.NotificationArea(taskbar), out var trayRect) && trayRect.Right > trayRect.Left
            ? ToDip(trayRect, scale)
            : TaskbarBalanceGeometry.FallbackTrayRect(taskbarDip, edge);

        var frame = TaskbarBalanceGeometry.Place(taskbarDip, trayDip, Width, Height, edge);

        Left = frame.X;
        Top = frame.Y;

        if (!IsVisible) Show();
        NativeMethods.SetWindowPos(
            _handle,
            NativeMethods.HwndTopMost,
            0,
            0,
            0,
            0,
            NativeMethods.SwpNoMove | NativeMethods.SwpNoSize | NativeMethods.SwpNoActivate);
    }

    private void ApplyVisibility()
    {
        if (!_visible || _hiddenForFullScreen)
        {
            if (IsVisible) Hide();
            return;
        }
        RefreshPlacement();
    }

    private NativeMethods.Rect MonitorRect(IntPtr taskbar)
    {
        var monitor = NativeMethods.MonitorFromWindow(taskbar, NativeMethods.MonitorDefaultToNearest);
        var info = new NativeMethods.MonitorInfo { Size = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.MonitorInfo>() };
        if (monitor != IntPtr.Zero && NativeMethods.GetMonitorInfo(monitor, ref info)) return info.Monitor;

        var screen = System.Windows.Forms.Screen.FromHandle(taskbar).Bounds;
        return new NativeMethods.Rect { Left = screen.Left, Top = screen.Top, Right = screen.Right, Bottom = screen.Bottom };
    }

    private double ScaleFactor()
    {
        try
        {
            var dpi = VisualTreeHelper.GetDpi(this);
            return dpi.DpiScaleX > 0 ? dpi.DpiScaleX : 1d;
        }
        catch (InvalidOperationException)
        {
            return 1d;
        }
    }

    private static ScreenRect ToDip(NativeMethods.Rect rect, double scale)
        => new(rect.Left / scale, rect.Top / scale, (rect.Right - rect.Left) / scale, (rect.Bottom - rect.Top) / scale);

    private static Color ToMediaColor(System.Drawing.Color color)
        => Color.FromRgb(color.R, color.G, color.B);
}
