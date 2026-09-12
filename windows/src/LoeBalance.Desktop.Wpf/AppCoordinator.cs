using System.Net.Http;
using System.Windows;
using LoeBalance.Core.Animation;
using LoeBalance.Core.Auth;
using LoeBalance.Core.Models;
using LoeBalance.Core.Networking;
using LoeBalance.Core.Persistence;
using LoeBalance.Core.Refresh;
using LoeBalance.Desktop.Wpf.Presentation;
using LoeBalance.Desktop.Wpf.ViewModels;
using LoeBalance.Desktop.Wpf.Views;
using LoeBalance.Platform.Windows;

namespace LoeBalance.Desktop.Wpf;

/// <summary>
/// Windows composition root and lifecycle owner. It mirrors the macOS AppCoordinator:
/// restore the session, start the monitors and scheduler, mirror refresh results into the
/// tray and desktop card, and tear everything down on logout or quit.
/// </summary>
internal sealed class AppCoordinator : IDisposable
{
    private readonly WindowsCredentialStore _credentials = new();
    private readonly LocalAppDataSettingsStore _settingsStore = new();
    private readonly LocalAppDataSnapshotStore _snapshotStore = new();
    private readonly StartupRegistration _startup = new();
    private readonly NetworkAvailabilityMonitor _network = new();
    private readonly PowerResumeMonitor _power = new();
    private readonly AuthManager _auth;
    private readonly BalanceService _balanceService;
    private readonly RefreshScheduler _scheduler;
    private readonly TrayPresenter _tray;
    private readonly DesktopCardWindow _card;
    private readonly DamageAnimationPlanner _planner = new();

    private AppPreferences _preferences = AppPreferences.Empty;
    private BalanceSnapshot? _currentSnapshot;
    private BalanceSnapshot? _initialSnapshot;
    private LoginWindow? _loginWindow;
    private SettingsWindow? _settingsWindow;
    private bool _authenticated;
    private bool _started;
    private bool _disposed;

    internal AppCoordinator()
    {
        var api = new ApiClient(new HttpClient());
        _auth = new AuthManager(api, _credentials);
        _balanceService = new BalanceService(api, _auth, _snapshotStore);
        _scheduler = new RefreshScheduler(30, RefreshAsync);
        _tray = new TrayPresenter(new TrayCommands(
            RefreshNow: () => _ = _scheduler.RefreshNowAsync(),
            ToggleDesktopCard: ToggleDesktopCard,
            OpenSettings: OpenSettings,
            Logout: () => _ = LogoutAsync(),
            Quit: Quit));
        _card = new DesktopCardWindow(null, SaveDesktopCardFrame);
    }

    private Func<bool> ReduceMotion => static () => !SystemParameters.ClientAreaAnimation;

    internal async Task StartAsync()
    {
        if (_started) return;
        _started = true;

        await LoadStateAsync();

        try
        {
            _authenticated = await _auth.RestoreSessionAsync();
        }
        catch (AppException exception)
        {
            if (IsAuthenticationFailure(exception))
            {
                _authenticated = false;
            }
            else
            {
                // The stored session is still valid but the network failed; keep the app
                // authenticated and show the cached snapshot with the matching state.
                _authenticated = true;
                PresentCachedSnapshot(ConnectionStateFor(exception));
            }
        }
        catch (Exception)
        {
            _authenticated = false;
        }

        if (!_authenticated)
        {
            _card.SetVisible(false);
            _network.Start();
            ShowLogin();
            return;
        }

        _network.Start();
        _power.Start();
        _card.SetVisible(_preferences.ShowsDesktopCard);
        await _scheduler.StartAsync();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        _network.Dispose();
        _power.Dispose();
        _settingsWindow?.Close();
        _loginWindow?.Close();
        _card.Close();
        _tray.Dispose();

        try
        {
            _scheduler.StopAsync().GetAwaiter().GetResult();
        }
        catch (Exception)
        {
            // Shutdown must not throw.
        }
    }

    private async Task<RefreshResult> RefreshAsync(CancellationToken cancellationToken)
    {
        try
        {
            var result = await _balanceService.RefreshAsync(cancellationToken);
            await DispatchAsync(() => HandleRefreshResult(result));
            return result;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            await DispatchAsync(() => HandleRefreshFailure(exception));
            throw;
        }
    }

    private void HandleRefreshResult(RefreshResult result)
    {
        if (!_authenticated) return;
        _currentSnapshot = result.Snapshot;

        _card.Present(result.Snapshot, result.ConnectionState);
        _tray.Present(result.Snapshot, result.ConnectionState, _preferences.ShowsDesktopCard);

        // Only the desktop card animates. The tray reports state through icon and tooltip;
        // it never carries floating debit numbers.
        var plans = _planner.Plan(result.Events, DamageSurface.Desktop, _preferences.ShakeStrength, ReduceMotion());
        _card.Play(plans);
    }

    private void HandleRefreshFailure(Exception exception)
    {
        PresentCachedSnapshot(ConnectionStateFor(exception));
    }

    private void PresentCachedSnapshot(ConnectionState connection)
    {
        var snapshot = _currentSnapshot ?? _initialSnapshot;
        if (snapshot is null) return;

        _card.Present(snapshot, connection);
        _tray.Present(snapshot, connection, _preferences.ShowsDesktopCard);
    }

    private void ToggleDesktopCard()
    {
        var next = !_preferences.ShowsDesktopCard;
        _preferences = _preferences with { ShowsDesktopCard = next };
        _ = PersistPreferencesAsync(_preferences);

        _card.SetVisible(next && _authenticated);
        _tray.SetDesktopCardVisible(next);
        _settingsWindow?.SetShowsDesktopCard(next);
    }

    private void OpenSettings() => _ = OpenSettingsAsync();

    private async Task OpenSettingsAsync()
    {
        _settingsWindow ??= CreateSettingsWindow();
        await _settingsWindow.InitializeAsync();
        _settingsWindow.Present();
    }

    private SettingsWindow CreateSettingsWindow()
    {
        var viewModel = new SettingsViewModel(
            _settingsStore,
            _scheduler,
            _startup,
            onShakeStrengthChanged: value => _preferences = _preferences with { ShakeStrength = value },
            onShowsDesktopCardChanged: value =>
            {
                _preferences = _preferences with { ShowsDesktopCard = value };
                _card.SetVisible(value && _authenticated);
                _tray.SetDesktopCardVisible(value);
            },
            logout: LogoutAsync);
        return new SettingsWindow(viewModel);
    }

    private void ShowLogin()
    {
        _loginWindow ??= new LoginWindow(new LoginViewModel(_auth, OnLoginSucceeded));
        _loginWindow.Present();
    }

    private void OnLoginSucceeded()
    {
        _authenticated = true;
        _loginWindow?.Hide();
        _network.Start();
        _power.Start();
        _card.SetVisible(_preferences.ShowsDesktopCard);
        _ = _scheduler.StartAsync();
    }

    private async Task LogoutAsync()
    {
        _authenticated = false;
        _currentSnapshot = null;
        _card.SetVisible(false);
        await _scheduler.StopAsync();
        _network.Stop();
        _power.Stop();

        try
        {
            await _auth.LogoutAsync();
        }
        catch (Exception exception)
        {
            // Logout must still complete locally even when the credential store fails.
            _tray.ShowError($"Logout reported: {exception.Message}");
        }

        try
        {
            await _balanceService.ClearBaselineAsync();
        }
        catch (Exception exception)
        {
            _tray.ShowError($"Snapshot reset reported: {exception.Message}");
        }

        _tray.Present(new BalanceSnapshot(Money.Zero, null, null, DateTimeOffset.Now), new ConnectionState.LoginRequired(), _preferences.ShowsDesktopCard);
        ShowLogin();
    }

    private void Quit()
    {
        Dispose();
        System.Windows.Application.Current.Shutdown();
    }

    private async Task LoadStateAsync()
    {
        _preferences = await _settingsStore.LoadAsync() ?? AppPreferences.Empty;
        _initialSnapshot = (await _snapshotStore.LoadAsync())?.CachedSnapshot;
        _card.SetSavedFrame(_preferences.DesktopCardFrame);
        _scheduler.UpdateInterval(_preferences.ClampedRefreshIntervalSeconds);
    }

    private void SaveDesktopCardFrame(DesktopCardFrame frame)
    {
        _preferences = _preferences with { DesktopCardFrame = frame };
        _ = PersistPreferencesAsync(_preferences);
    }

    private async Task PersistPreferencesAsync(AppPreferences preferences)
    {
        try
        {
            await _settingsStore.SaveAsync(preferences);
        }
        catch (Exception exception)
        {
            _tray.ShowError($"Settings could not be saved: {exception.Message}");
        }
    }

    private static Task DispatchAsync(Action action)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            action();
            return Task.CompletedTask;
        }
        return dispatcher.InvokeAsync(action).Task;
    }

    private static bool IsAuthenticationFailure(Exception exception)
        => exception is AppException { Kind: AppErrorKind.Unauthorized };

    private static ConnectionState ConnectionStateFor(Exception exception) => exception switch
    {
        AppException { Kind: AppErrorKind.Transport } => new ConnectionState.Offline(),
        AppException { Kind: AppErrorKind.RateLimited, RetryAfter: { } until } => new ConnectionState.RateLimited(until),
        AppException { Kind: AppErrorKind.RateLimited } => new ConnectionState.RateLimited(null),
        AppException { Kind: AppErrorKind.Unauthorized } => new ConnectionState.LoginRequired(),
        AppException => new ConnectionState.InvalidData(),
        _ => new ConnectionState.InvalidData()
    };
}
