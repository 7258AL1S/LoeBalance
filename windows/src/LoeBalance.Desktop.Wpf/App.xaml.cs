using System.Windows;
using System.Windows.Threading;

namespace LoeBalance.Desktop.Wpf;

public partial class App : System.Windows.Application
{
    private SingleInstanceGuard? _guard;
    private AppCoordinator? _coordinator;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Tray application: only the explicit Quit command ends the process.
        ShutdownMode = ShutdownMode.OnExplicitShutdown;

        _guard = SingleInstanceGuard.TryAcquire();
        if (_guard is null)
        {
            Shutdown();
            return;
        }

        DispatcherUnhandledException += OnDispatcherUnhandledException;
        _coordinator = new AppCoordinator();
        _ = e.Args.Contains("--preview-card", StringComparer.OrdinalIgnoreCase)
            ? _coordinator.StartPreviewAsync()
            : _coordinator.StartAsync();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        DispatcherUnhandledException -= OnDispatcherUnhandledException;
        _coordinator?.Dispose();
        _coordinator = null;
        _guard?.Dispose();
        _guard = null;
        base.OnExit(e);
    }

    private static void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        // Keep the tray app alive; the failure is surfaced in the tray tooltip on the next
        // refresh, and the message never contains credentials.
        System.Diagnostics.Debug.WriteLine($"LoeBalance unhandled error: {e.Exception.GetType().Name}");
        e.Handled = true;
    }
}
