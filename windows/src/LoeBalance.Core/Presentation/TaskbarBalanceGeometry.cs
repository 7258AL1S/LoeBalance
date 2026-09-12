namespace LoeBalance.Core.Presentation;

public enum TaskbarEdge
{
    Bottom,
    Top,
    Left,
    Right
}

/// <summary>Rect in screen pixels with the origin at the top-left of the virtual desktop.</summary>
public sealed record ScreenRect(double X, double Y, double Width, double Height)
{
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

/// <summary>
/// Places the taskbar balance readout next to the notification area. Windows has no supported
/// API for custom text inside the taskbar, so the readout is a small overlay window that is
/// docked against the tray edge; this type owns the arithmetic so it can be unit tested.
/// </summary>
public static class TaskbarBalanceGeometry
{
    public const double DefaultGap = 8;

    /// <summary>Height of the balance pill, matching the tray row height at 100% scaling.</summary>
    public const double PillHeight = 24;

    /// <summary>
    /// Width of the animation strip reserved to the right of the balance. The macOS status item
    /// reserves the same 54 points so debit/credit numbers have room to float without moving
    /// the balance text.
    /// </summary>
    public const double DamageAreaWidth = 54;

    /// <summary>
    /// Height of the readout window: the pill plus enough room above it for the highest
    /// planned rise (menu-bar surface, 55 points) and the text height.
    /// </summary>
    public const double ReadoutWindowHeadroom = 63;

    public static double ReadoutWindowHeight => ReadoutWindowHeadroom * 2;

    /// <summary>
    /// Wraps the pill in a window that is vertically centred on the pill, so the damage track
    /// shares the pill's centre line and the numbers rise into the space above the taskbar.
    /// </summary>
    public static ScreenRect ReadoutWindow(ScreenRect pill, double windowHeight, double damageAreaWidth = DamageAreaWidth)
        => new(
            pill.X,
            pill.Y + (pill.Height / 2) - (windowHeight / 2),
            pill.Width + damageAreaWidth,
            windowHeight);

    public static ScreenRect Place(
        ScreenRect taskbar,
        ScreenRect tray,
        double width,
        double height,
        TaskbarEdge edge,
        double gap = DefaultGap)
    {
        double x;
        double y;

        switch (edge)
        {
            case TaskbarEdge.Top:
            case TaskbarEdge.Bottom:
                // Just left of the tray/clock block, vertically centred in the taskbar.
                x = tray.X - width - gap;
                y = taskbar.Y + ((taskbar.Height - height) / 2);
                break;
            default:
                // Vertical taskbar (Windows 10): sit above the tray block.
                x = taskbar.X + ((taskbar.Width - width) / 2);
                y = tray.Y - height - gap;
                break;
        }

        return Clamp(new ScreenRect(x, y, width, height), taskbar);
    }

    /// <summary>Clamps the readout so it never leaves the taskbar strip.</summary>
    public static ScreenRect Clamp(ScreenRect rect, ScreenRect bounds)
    {
        var x = bounds.Width <= rect.Width
            ? bounds.X
            : Math.Clamp(rect.X, bounds.X, bounds.Right - rect.Width);
        var y = bounds.Height <= rect.Height
            ? bounds.Y
            : Math.Clamp(rect.Y, bounds.Y, bounds.Bottom - rect.Height);
        return new ScreenRect(x, y, rect.Width, rect.Height);
    }

    /// <summary>Derives which edge of the monitor the taskbar occupies.</summary>
    public static TaskbarEdge EdgeFor(ScreenRect monitor, ScreenRect taskbar)
    {
        // A horizontal taskbar spans the monitor width; a vertical one does not. Comparing the
        // span first avoids ambiguous ties (a full-height side taskbar also touches the bottom).
        var spansWidth = taskbar.Width >= monitor.Width - 1;
        if (spansWidth)
        {
            return Math.Abs(taskbar.Y - monitor.Y) <= Math.Abs(taskbar.Bottom - monitor.Bottom)
                ? TaskbarEdge.Top
                : TaskbarEdge.Bottom;
        }

        return Math.Abs(taskbar.X - monitor.X) <= Math.Abs(taskbar.Right - monitor.Right)
            ? TaskbarEdge.Left
            : TaskbarEdge.Right;
    }

    /// <summary>
    /// Fallback tray rect used when the notification area cannot be located: reserve the width
    /// of a typical clock/tray block at the right (or bottom) end of the taskbar.
    /// </summary>
    public static ScreenRect FallbackTrayRect(ScreenRect taskbar, TaskbarEdge edge)
    {
        const double horizontalReserve = 320;
        const double verticalReserve = 60;

        return edge switch
        {
            TaskbarEdge.Top or TaskbarEdge.Bottom
                => new ScreenRect(taskbar.Right - horizontalReserve, taskbar.Y, horizontalReserve, taskbar.Height),
            _ => new ScreenRect(taskbar.X, taskbar.Bottom - verticalReserve, taskbar.Width, verticalReserve)
        };
    }
}
