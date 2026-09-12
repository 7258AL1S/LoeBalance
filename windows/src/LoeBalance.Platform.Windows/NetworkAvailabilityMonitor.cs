using System.Net.NetworkInformation;

namespace LoeBalance.Platform.Windows;

/// <summary>
/// Raises availability changes from <see cref="NetworkChange.NetworkAvailabilityChanged"/>
/// and <see cref="NetworkChange.NetworkAddressChanged"/>. Handlers are detached on
/// <see cref="Stop"/> so a stopped monitor never keeps the application alive.
/// </summary>
public sealed class NetworkAvailabilityMonitor : INetworkAvailabilityMonitor
{
    private readonly object _stateLock = new();
    private bool? _lastReported;
    private bool _started;
    private bool _disposed;

    public event EventHandler<bool>? AvailabilityChanged;

    public bool IsAvailable => NetworkInterface.GetIsNetworkAvailable();

    public void Start()
    {
        lock (_stateLock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_started) return;

            _lastReported = IsAvailable;
            NetworkChange.NetworkAvailabilityChanged += OnNetworkAvailabilityChanged;
            NetworkChange.NetworkAddressChanged += OnNetworkAddressChanged;
            _started = true;
        }
    }

    public void Stop()
    {
        lock (_stateLock)
        {
            if (!_started) return;
            NetworkChange.NetworkAvailabilityChanged -= OnNetworkAvailabilityChanged;
            NetworkChange.NetworkAddressChanged -= OnNetworkAddressChanged;
            _started = false;
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        Stop();
        _disposed = true;
        AvailabilityChanged = null;
    }

    private void OnNetworkAvailabilityChanged(object? sender, NetworkAvailabilityEventArgs e)
        => Report(e.IsAvailable);

    private void OnNetworkAddressChanged(object? sender, EventArgs e)
        => Report(IsAvailable);

    private void Report(bool available)
    {
        EventHandler<bool>? handler;
        lock (_stateLock)
        {
            if (!_started || _lastReported == available) return;
            _lastReported = available;
            handler = AvailabilityChanged;
        }
        handler?.Invoke(this, available);
    }
}
