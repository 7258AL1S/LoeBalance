namespace LoeBalance.Desktop.Wpf;

/// <summary>
/// Keeps a single LoeBalance instance per user session. The tray icon and desktop card are
/// session-scoped resources, so a second process exits immediately instead of duplicating
/// them.
/// </summary>
internal sealed class SingleInstanceGuard : IDisposable
{
    private const string MutexName = @"Local\LoeBalance.Desktop.Wpf.SingleInstance";

    private readonly Mutex _mutex;
    private bool _disposed;

    private SingleInstanceGuard(Mutex mutex) => _mutex = mutex;

    internal static SingleInstanceGuard? TryAcquire()
    {
        var mutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        if (createdNew) return new SingleInstanceGuard(mutex);

        mutex.Dispose();
        return null;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        try
        {
            _mutex.ReleaseMutex();
        }
        catch (ApplicationException)
        {
            // The mutex was already released; nothing to do.
        }
        _mutex.Dispose();
    }
}
