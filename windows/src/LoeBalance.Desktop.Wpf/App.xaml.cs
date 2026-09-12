using System.Windows;

namespace LoeBalance.Desktop.Wpf;

public partial class App : System.Windows.Application
{
    private TrayApplication? _tray;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _tray = new TrayApplication();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        base.OnExit(e);
    }
}
