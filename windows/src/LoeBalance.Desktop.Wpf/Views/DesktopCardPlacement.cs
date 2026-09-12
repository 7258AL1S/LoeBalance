using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using LoeBalance.Core.Persistence;
using LoeBalance.Desktop.Wpf.Interop;

namespace LoeBalance.Desktop.Wpf.Views;

/// <summary>
/// Places the desktop card on the monitor that owns the saved position and clamps that
/// position inside the monitor's work area, so the card never leaves the screen after a
/// resolution or monitor change.
///
/// Everything is expressed in WPF device-independent units and assigned through
/// <see cref="Window.Left"/>/<see cref="Window.Top"/> so WPF owns the per-monitor DPI
/// conversion. Mixing raw SetWindowPos pixel placement with WPF's DIP model produced
/// inconsistent positions at 150% scaling during real-machine testing, so the only native
/// call left here is the z-order change that keeps the card on the desktop layer.
/// </summary>
internal sealed class DesktopCardPlacement
{
    private readonly double _cardWidth;
    private readonly double _cardHeight;

    internal DesktopCardPlacement(double cardWidth, double cardHeight)
    {
        _cardWidth = cardWidth;
        _cardHeight = cardHeight;
    }

    /// <summary>Resolves the frame (in DIPs) to apply, using the saved frame when usable.</summary>
    internal (DesktopCardFrame Frame, bool HasSavedPosition) Resolve(Window window, DesktopCardFrame? saved)
    {
        var scale = ScaleFor(window);
        var monitor = saved is null ? MonitorForWindow(window) : MonitorForFrame(saved, scale);
        var workArea = WorkArea(monitor, scale, window);

        return saved is null
            ? (DesktopCardPlacementCore.Default(workArea, _cardWidth, _cardHeight), false)
            : (DesktopCardPlacementCore.Clamp(saved, workArea, _cardWidth, _cardHeight), true);
    }

    /// <summary>Applies a DIP frame through WPF, then optionally pushes the card to the desktop layer.</summary>
    internal static void Apply(Window window, DesktopCardFrame frame, bool sendToBottom)
    {
        window.Width = frame.Width > 0 ? frame.Width : window.Width;
        window.Height = frame.Height > 0 ? frame.Height : window.Height;
        window.Left = frame.X;
        window.Top = frame.Y;

        if (sendToBottom) SendToBottom(window);
    }

    /// <summary>Keeps the card below every normal window without activating it.</summary>
    internal static void SendToBottom(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        NativeMethods.SetWindowPos(
            handle,
            NativeMethods.HwndBottom,
            0,
            0,
            0,
            0,
            NativeMethods.SwpNoMove | NativeMethods.SwpNoSize | NativeMethods.SwpNoActivate);
    }

    /// <summary>Reads the current WPF frame for persistence.</summary>
    internal static DesktopCardFrame Capture(Window window)
        => new(window.Left, window.Top, window.Width, window.Height);

    private static double ScaleFor(Window window)
    {
        try
        {
            var dpi = VisualTreeHelper.GetDpi(window);
            return dpi.DpiScaleX > 0 ? dpi.DpiScaleX : 1d;
        }
        catch (InvalidOperationException)
        {
            return 1d;
        }
    }

    private static IntPtr MonitorForFrame(DesktopCardFrame frame, double scale)
    {
        var rect = new NativeMethods.Rect
        {
            Left = (int)Math.Round(frame.X * scale),
            Top = (int)Math.Round(frame.Y * scale),
            Right = (int)Math.Round((frame.X + frame.Width) * scale),
            Bottom = (int)Math.Round((frame.Y + frame.Height) * scale)
        };
        return NativeMethods.MonitorFromRect(ref rect, NativeMethods.MonitorDefaultToNearest);
    }

    private static IntPtr MonitorForWindow(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle != IntPtr.Zero)
        {
            return NativeMethods.MonitorFromWindow(handle, NativeMethods.MonitorDefaultToNearest);
        }

        var primary = System.Windows.Forms.Screen.PrimaryScreen!;
        return NativeMethods.MonitorFromPoint(
            new NativeMethods.Point(primary.WorkingArea.Left + 1, primary.WorkingArea.Top + 1),
            NativeMethods.MonitorDefaultToNearest);
    }

    private static DesktopWorkArea WorkArea(IntPtr monitor, double scale, Window window)
    {
        var info = new NativeMethods.MonitorInfo { Size = Marshal.SizeOf<NativeMethods.MonitorInfo>() };
        if (monitor != IntPtr.Zero && NativeMethods.GetMonitorInfo(monitor, ref info))
        {
            return ToWorkArea(info.Work, scale);
        }

        var handle = new WindowInteropHelper(window).Handle;
        var area = handle == IntPtr.Zero
            ? System.Windows.Forms.Screen.PrimaryScreen!.WorkingArea
            : System.Windows.Forms.Screen.FromHandle(handle).WorkingArea;
        return new DesktopWorkArea(area.Left / scale, area.Top / scale, area.Width / scale, area.Height / scale);
    }

    private static DesktopWorkArea ToWorkArea(NativeMethods.Rect work, double scale)
        => new(
            work.Left / scale,
            work.Top / scale,
            (work.Right - work.Left) / scale,
            (work.Bottom - work.Top) / scale);
}

/// <summary>
/// Thin facade over the pure placement math in <see cref="Core.Persistence.DesktopCardPlacement"/>
/// so the WPF window and the core tests share one implementation.
/// </summary>
internal static class DesktopCardPlacementCore
{
    internal static DesktopCardFrame Clamp(DesktopCardFrame requested, DesktopWorkArea workArea, double cardWidth, double cardHeight)
        => Core.Persistence.DesktopCardPlacement.Clamp(requested, workArea, cardWidth, cardHeight);

    internal static DesktopCardFrame Default(DesktopWorkArea workArea, double cardWidth, double cardHeight)
        => Core.Persistence.DesktopCardPlacement.Default(workArea, cardWidth, cardHeight);
}
