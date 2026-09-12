using System.Drawing;
using System.Windows.Forms;

namespace LoeBalance.Desktop.Wpf;

public sealed class TrayApplication : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu;
    private bool _disposed;

    public TrayApplication()
    {
        _menu = new ContextMenuStrip();
        _menu.Items.Add("Balance: --").Enabled = false;
        _menu.Items.Add(new ToolStripSeparator());
        _menu.Items.Add("Refresh Now");
        _menu.Items.Add("Settings");
        _menu.Items.Add("Quit", null, (_, _) => System.Windows.Application.Current.Shutdown());
        _notifyIcon = new NotifyIcon
        {
            Icon = SystemIcons.Application,
            Visible = true,
            Text = "LoeBalance: --",
            ContextMenuStrip = _menu
        };
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _menu.Dispose();
    }
}
