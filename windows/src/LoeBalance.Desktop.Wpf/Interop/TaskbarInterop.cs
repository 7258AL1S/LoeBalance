using System.Runtime.InteropServices;

namespace LoeBalance.Desktop.Wpf.Interop;

/// <summary>
/// Locates the Windows taskbar and its notification area so the balance readout can be docked
/// against the tray. Windows has no supported API for custom text inside the taskbar
/// (deskbands were removed in Windows 11), so the readout is a small topmost overlay window
/// positioned over the taskbar strip, which is the approach desktop widgets use.
/// </summary>
internal static class TaskbarInterop
{
    private const int AbmGetTaskbarPos = 5;
    private const int AbmGetState = 4;

    internal const int AbsAutoHide = 0x0000001;

    internal static IntPtr PrimaryTaskbar => NativeMethods.FindWindow("Shell_TrayWnd", null);

    internal static IntPtr NotificationArea(IntPtr taskbar)
        => taskbar == IntPtr.Zero
            ? IntPtr.Zero
            : NativeMethods.FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);

    internal static bool TryGetTaskbarRect(IntPtr taskbar, out NativeMethods.Rect rect)
    {
        rect = default;
        if (taskbar == IntPtr.Zero || !NativeMethods.IsWindowVisible(taskbar)) return false;

        var data = new NativeMethods.AppBarData
        {
            Size = Marshal.SizeOf<NativeMethods.AppBarData>(),
            Window = taskbar
        };
        if (NativeMethods.SHAppBarMessage(AbmGetTaskbarPos, ref data) != 0)
        {
            rect = data.Rect;
            return true;
        }

        return NativeMethods.GetWindowRect(taskbar, out rect);
    }

    internal static bool IsAutoHideEnabled(IntPtr taskbar)
    {
        var data = new NativeMethods.AppBarData
        {
            Size = Marshal.SizeOf<NativeMethods.AppBarData>(),
            Window = taskbar
        };
        var state = NativeMethods.SHAppBarMessage(AbmGetState, ref data);
        return (state & AbsAutoHide) != 0;
    }

    internal static bool TryGetWindowRect(IntPtr window, out NativeMethods.Rect rect)
        => NativeMethods.GetWindowRect(window, out rect);

    /// <summary>
    /// True when the shell reports a state where a taskbar overlay would be intrusive:
    /// a full-screen app, presentation mode, the lock screen or a session that is not present.
    /// </summary>
    internal static bool ShouldHideForFullScreen()
    {
        try
        {
            if (NativeMethods.SHQueryUserNotificationState(out var state) != 0) return false;
            return state switch
            {
                1 => true, // QUNS_NOT_PRESENT (locked, screensaver, no interactive session)
                2 => true, // QUNS_BUSY (full-screen app such as F11 or a game)
                3 => true, // QUNS_RUNNING_D3D_FULL_SCREEN
                4 => true, // QUNS_PRESENTATION_MODE
                _ => false
            };
        }
        catch (DllNotFoundException)
        {
            return false;
        }
        catch (EntryPointNotFoundException)
        {
            return false;
        }
    }

}
