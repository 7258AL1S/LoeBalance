using LoeBalance.Core.Models;
using LoeBalance.Core.Persistence;

namespace LoeBalance.Platform.Windows;

public interface IWindowsCredentialStore : LoeBalance.Core.Auth.ICredentialStore { }

public interface IWindowsSettingsStore : ISettingsStore, ISnapshotStore { }

public interface INetworkAvailabilityMonitor : IDisposable
{
    event EventHandler<bool>? AvailabilityChanged;
    void Start();
    void Stop();
}

public interface IPowerResumeMonitor : IDisposable
{
    event EventHandler? Resumed;
    void Start();
    void Stop();
}

public interface IStartupRegistration
{
    bool IsEnabled { get; }
    void SetEnabled(bool enabled);
}

public interface ITrayPresenter : IDisposable
{
    void Present(BalanceSnapshot snapshot, ConnectionState connection, bool showsDesktopCard);
    void ShowError(string message);
}

public interface IDesktopCardPresenter : IDisposable
{
    void Present(BalanceSnapshot snapshot, ConnectionState connection);
    void Play(IReadOnlyList<LoeBalance.Core.Animation.DamageMotionPlan> plans);
    void SetVisible(bool visible);
}
