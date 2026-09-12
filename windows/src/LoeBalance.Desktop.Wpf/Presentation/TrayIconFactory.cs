using System.Drawing;
using System.Drawing.Drawing2D;
using LoeBalance.Core.Models;
using LoeBalance.Desktop.Wpf.Interop;

namespace LoeBalance.Desktop.Wpf.Presentation;

/// <summary>
/// Draws the tray icon for each connection state. The icon is a colored dot with a ring so
/// the state stays readable at 16x16 while the balance itself lives in the tooltip and menu.
/// </summary>
internal sealed class TrayIconFactory : IDisposable
{
    private readonly Dictionary<ConnectionState, Icon> _icons = [];
    private bool _disposed;

    internal Icon For(ConnectionState connection)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_icons.TryGetValue(connection, out var icon)) return icon;

        icon = Create(ConnectionPresentation.Color(connection));
        _icons[connection] = icon;
        return icon;
    }

    internal static Icon Create(Color color)
    {
        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.Clear(Color.Transparent);

            using var ring = new SolidBrush(Color.FromArgb(230, 255, 255, 255));
            graphics.FillEllipse(ring, 1, 1, 30, 30);

            using var fill = new SolidBrush(color);
            graphics.FillEllipse(fill, 4, 4, 24, 24);
        }

        var handle = bitmap.GetHicon();
        try
        {
            using var temporary = Icon.FromHandle(handle);
            return (Icon)temporary.Clone();
        }
        finally
        {
            NativeMethods.DestroyIcon(handle);
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        foreach (var icon in _icons.Values) icon.Dispose();
        _icons.Clear();
    }
}
