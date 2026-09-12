using Microsoft.Win32;

namespace LoeBalance.Platform.Windows;

/// <summary>
/// Reports system resume events through <see cref="SystemEvents.PowerModeChanged"/>.
/// The handler is detached on <see cref="Stop"/> because <see cref="SystemEvents"/> keeps
/// static subscriptions that would otherwise keep the application alive.
/// </summary>
public sealed class PowerResumeMonitor : IPowerResumeMonitor
{
    private readonly object _stateLock = new();
    private bool _started;
    private bool _disposed;

    public event EventHandler? Resumed;

    /// <summary>True when the platform supports system power notifications.</summary>
    public bool IsSupported { get; private set; } = true;

    public void Start()
    {
        lock (_stateLock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_started) return;

            try
            {
                SystemEvents.PowerModeChanged += OnPowerModeChanged;
                _started = true;
                IsSupported = true;
            }
            catch (Exception)
            {
                // Power notifications are unavailable in some hosted sessions. The app keeps
                // working; wake refreshes then rely on the next scheduled refresh instead.
                IsSupported = false;
            }
        }
    }

    public void Stop()
    {
        lock (_stateLock)
        {
            if (!_started) return;
            try
            {
                SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            }
            catch (Exception)
            {
                IsSupported = false;
            }
            _started = false;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        Stop();
        _disposed = true;
        Resumed = null;
    }

    private void OnPowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode != PowerModes.Resume) return;
        Resumed?.Invoke(this, EventArgs.Empty);
    }
}
