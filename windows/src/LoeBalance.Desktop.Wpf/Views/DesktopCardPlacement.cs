using System.Runtime.InteropServices;
using LoeBalance.Core.Persistence;
using LoeBalance.Desktop.Wpf.Interop;

namespace LoeBalance.Desktop.Wpf.Views;

/// <summary>
/// Places the desktop card on the monitor that owns the saved position, clamps the position
/// inside that monitor's work area so the card never leaves the screen after a display
/// change, and keeps everything in device pixels to stay stable across mixed-DPI setups.
/// </summary>
internal sealed class DesktopCardPlacement
{
    private readonly double _cardWidthDip;
    private readonly double _cardHeightDip;

    internal DesktopCardPlacement(double cardWidthDip, double cardHeightDip)
    {
        _cardWidthDip = cardWidthDip;
        _cardHeightDip = cardHeightDip;
    }

    /// <summary>Resolves the device-pixel frame to apply, using the saved frame when usable.</summary>
    internal (DesktopCardFrame Frame, bool HasSavedPosition) Resolve(IntPtr windowHandle, DesktopCardFrame? saved)
    {
        var monitor = saved is null ? MonitorForWindow(windowHandle) : MonitorForFrame(saved);
        var scale = DpiScale(monitor, windowHandle);
        var cardWidth = _cardWidthDip * scale;
        var cardHeight = _cardHeightDip * scale;
        var workArea = WorkArea(monitor, windowHandle);

        return saved is null
            ? (DesktopCardPlacementCore.Default(workArea, cardWidth, cardHeight), false)
            : (DesktopCardPlacementCore.Clamp(saved, workArea, cardWidth, cardHeight), true);
    }

    /// <summary>Applies a device-pixel frame; <paramref name="sendToBottom"/> keeps the desktop layer.</summary>
    internal static void Apply(IntPtr windowHandle, DesktopCardFrame frame, bool sendToBottom)
    {
        if (windowHandle == IntPtr.Zero) return;

        var insertAfter = sendToBottom ? NativeMethods.HwndBottom : IntPtr.Zero;
        var flags = NativeMethods.SwpNoActivate | NativeMethods.SwpNoOwnerZOrder;
        if (!sendToBottom) flags |= NativeMethods.SwpNoZOrder;

        NativeMethods.SetWindowPos(
            windowHandle,
            insertAfter,
            (int)Math.Round(frame.X),
            (int)Math.Round(frame.Y),
            (int)Math.Round(frame.Width),
            (int)Math.Round(frame.Height),
            flags);
    }

    internal static void SendToBottom(IntPtr windowHandle)
    {
        if (windowHandle == IntPtr.Zero) return;
        NativeMethods.SetWindowPos(
            windowHandle,
            NativeMethods.HwndBottom,
            0,
            0,
            0,
            0,
            NativeMethods.SwpNoMove | NativeMethods.SwpNoSize | NativeMethods.SwpNoActivate);
    }

    /// <summary>Reads the current window frame back as a device-pixel rect for persistence.</summary>
    internal static DesktopCardFrame Capture(IntPtr windowHandle)
        => !NativeMethods.GetWindowRect(windowHandle, out var rect)
            ? new DesktopCardFrame(0, 0, 0, 0)
            : new DesktopCardFrame(
                rect.Left,
                rect.Top,
                rect.Right - rect.Left,
                rect.Bottom - rect.Top);

    private static IntPtr MonitorForFrame(DesktopCardFrame frame)
    {
        var rect = ToRect(frame);
        return NativeMethods.MonitorFromRect(ref rect, NativeMethods.MonitorDefaultToNearest);
    }

    private static IntPtr MonitorForWindow(IntPtr windowHandle)
    {
        if (windowHandle != IntPtr.Zero && NativeMethods.GetWindowRect(windowHandle, out var rect))
        {
            return NativeMethods.MonitorFromRect(ref rect, NativeMethods.MonitorDefaultToNearest);
        }

        var primary = System.Windows.Forms.Screen.PrimaryScreen!;
        return NativeMethods.MonitorFromPoint(
            new NativeMethods.Point(primary.WorkingArea.Left + 1, primary.WorkingArea.Top + 1),
            NativeMethods.MonitorDefaultToNearest);
    }

    private static DesktopWorkArea WorkArea(IntPtr monitor, IntPtr windowHandle)
    {
        var info = new NativeMethods.MonitorInfo { Size = Marshal.SizeOf<NativeMethods.MonitorInfo>() };
        if (monitor != IntPtr.Zero && NativeMethods.GetMonitorInfo(monitor, ref info))
        {
            return new DesktopWorkArea(
                info.Work.Left,
                info.Work.Top,
                info.Work.Right - info.Work.Left,
                info.Work.Bottom - info.Work.Top);
        }

        var fallback = System.Windows.Forms.Screen.FromHandle(windowHandle);
        var area = windowHandle == IntPtr.Zero
            ? System.Windows.Forms.Screen.PrimaryScreen!.WorkingArea
            : fallback.WorkingArea;
        return new DesktopWorkArea(area.Left, area.Top, area.Width, area.Height);
    }

    private static double DpiScale(IntPtr monitor, IntPtr windowHandle)
    {
        if (monitor != IntPtr.Zero)
        {
            try
            {
                if (GetDpiForMonitor(monitor, 0, out var dpiX, out _) == 0 && dpiX > 0)
                {
                    return dpiX / 96d;
                }
            }
            catch (DllNotFoundException)
            {
            }
            catch (EntryPointNotFoundException)
            {
            }
        }

        var dpi = windowHandle == IntPtr.Zero ? 0 : NativeMethods.GetDpiForWindow(windowHandle);
        return dpi == 0 ? 1d : dpi / 96d;
    }

    private static NativeMethods.Rect ToRect(DesktopCardFrame frame)
        => new()
        {
            Left = (int)Math.Round(frame.X),
            Top = (int)Math.Round(frame.Y),
            Right = (int)Math.Round(frame.X + frame.Width),
            Bottom = (int)Math.Round(frame.Y + frame.Height)
        };

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);
}

/// <summary>
/// Pure placement math shared with the core tests. Coordinates are device pixels with the
/// origin at the top-left corner of the virtual desktop.
/// </summary>
internal static class DesktopCardPlacementCore
{
    internal static DesktopCardFrame Clamp(DesktopCardFrame requested, DesktopWorkArea workArea, double cardWidth, double cardHeight)
        => Core.Persistence.DesktopCardPlacement.Clamp(requested, workArea, cardWidth, cardHeight);

    internal static DesktopCardFrame Default(DesktopWorkArea workArea, double cardWidth, double cardHeight)
        => Core.Persistence.DesktopCardPlacement.Default(workArea, cardWidth, cardHeight);
}
