using System.Drawing;
using System.Globalization;
using System.Windows.Forms;
using LoeBalance.Core.Models;
using LoeBalance.Platform.Windows;

namespace LoeBalance.Desktop.Wpf.Presentation;

internal sealed record TrayCommands(
    Action RefreshNow,
    Action ToggleDesktopCard,
    Action OpenSettings,
    Action Logout,
    Action Quit);

/// <summary>
/// Windows notification-area presenter.
///
/// The Windows tray is not a macOS status item: the balance is reported through the tooltip
/// and the context menu, and the floating debit/credit numbers stay in the desktop card.
/// Nothing is drawn next to the tray icon.
/// </summary>
internal sealed class TrayPresenter : ITrayPresenter
{
    private const int MaximumTooltipLength = 63;

    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu;
    private readonly TrayIconFactory _iconFactory;
    private readonly ToolStripMenuItem _balanceItem;
    private readonly ToolStripMenuItem _connectionItem;
    private readonly ToolStripMenuItem _refreshItem;
    private readonly ToolStripMenuItem _desktopCardItem;
    private readonly ToolStripMenuItem _settingsItem;
    private readonly ToolStripMenuItem _logoutItem;
    private readonly ToolStripMenuItem _quitItem;
    private bool _disposed;

    internal TrayPresenter(TrayCommands commands)
    {
        _iconFactory = new TrayIconFactory();

        _balanceItem = new ToolStripMenuItem("Balance: --") { Enabled = false };
        _connectionItem = new ToolStripMenuItem("Online · Updated --") { Enabled = false };
        _refreshItem = new ToolStripMenuItem("Refresh Now", null, (_, _) => commands.RefreshNow());
        _desktopCardItem = new ToolStripMenuItem("Show Desktop Card", null, (_, _) => commands.ToggleDesktopCard());
        _settingsItem = new ToolStripMenuItem("Settings…", null, (_, _) => commands.OpenSettings());
        _logoutItem = new ToolStripMenuItem("Log Out", null, (_, _) => commands.Logout());
        _quitItem = new ToolStripMenuItem("Quit LoeBalance", null, (_, _) => commands.Quit());

        _menu = new ContextMenuStrip();
        _menu.Items.AddRange(
        [
            _balanceItem,
            _connectionItem,
            new ToolStripSeparator(),
            _refreshItem,
            _desktopCardItem,
            _settingsItem,
            new ToolStripSeparator(),
            _logoutItem,
            _quitItem
        ]);

        _notifyIcon = new NotifyIcon
        {
            Icon = _iconFactory.For(new ConnectionState.Online()),
            Text = "LoeBalance: --",
            Visible = true,
            ContextMenuStrip = _menu
        };
    }

    public void Present(BalanceSnapshot snapshot, ConnectionState connection, bool showsDesktopCard)
    {
        var status = ConnectionPresentation.Text(connection);
        var updated = snapshot.UpdatedAt.ToLocalTime().ToString("HH:mm:ss", CultureInfo.InvariantCulture);

        _notifyIcon.Icon = _iconFactory.For(connection);
        _notifyIcon.Text = Truncate($"LoeBalance {snapshot.Balance.CurrencyText} · {status} · Updated {updated}");

        _balanceItem.Text = $"Balance: {snapshot.Balance.CurrencyText}";
        _connectionItem.Text = $"{status} · Updated {updated}";
        _desktopCardItem.Text = showsDesktopCard ? "Hide Desktop Card" : "Show Desktop Card";

        var authenticated = ConnectionPresentation.IsAuthenticated(connection);
        _refreshItem.Enabled = authenticated;
        _desktopCardItem.Enabled = authenticated;
        _logoutItem.Enabled = authenticated;
    }

    /// <summary>Sets the desktop-card toggle text without waiting for the next refresh.</summary>
    internal void SetDesktopCardVisible(bool visible)
        => _desktopCardItem.Text = visible ? "Hide Desktop Card" : "Show Desktop Card";

    public void ShowError(string message)
    {
        if (string.IsNullOrWhiteSpace(message)) return;
        _notifyIcon.BalloonTipTitle = "LoeBalance";
        _notifyIcon.BalloonTipText = Truncate(message);
        _notifyIcon.BalloonTipIcon = ToolTipIcon.Warning;
        _notifyIcon.ShowBalloonTip(5000);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
        _iconFactory.Dispose();
    }

    private static string Truncate(string value)
        => value.Length <= MaximumTooltipLength ? value : value[..(MaximumTooltipLength - 1)] + "…";
}
