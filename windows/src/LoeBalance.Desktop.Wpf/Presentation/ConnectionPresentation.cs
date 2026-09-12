using System.Drawing;
using LoeBalance.Core.Models;

namespace LoeBalance.Desktop.Wpf.Presentation;

/// <summary>
/// Single source of truth for how a connection state is described on Windows. The macOS
/// menu-bar dot colors map onto tray icon colors and the matching English status text.
/// </summary>
internal static class ConnectionPresentation
{
    internal static string Text(ConnectionState connection) => connection switch
    {
        ConnectionState.Online => "Online",
        ConnectionState.Offline => "Offline",
        ConnectionState.RateLimited => "Rate limited",
        ConnectionState.LoginRequired => "Sign in required",
        ConnectionState.InvalidData => "Invalid data",
        _ => "Unknown"
    };

    internal static Color Color(ConnectionState connection) => connection switch
    {
        ConnectionState.Online => System.Drawing.Color.FromArgb(0x30, 0xD1, 0x58),
        ConnectionState.Offline => System.Drawing.Color.FromArgb(0xFF, 0x45, 0x3A),
        ConnectionState.RateLimited => System.Drawing.Color.FromArgb(0xFF, 0x9F, 0x0A),
        ConnectionState.LoginRequired => System.Drawing.Color.FromArgb(0xFF, 0xD6, 0x0A),
        ConnectionState.InvalidData => System.Drawing.Color.FromArgb(0xFF, 0x45, 0x3A),
        _ => System.Drawing.Color.Gray
    };

    /// <summary>Commands that require an authenticated session are disabled otherwise.</summary>
    internal static bool IsAuthenticated(ConnectionState connection)
        => connection is not ConnectionState.LoginRequired;
}
