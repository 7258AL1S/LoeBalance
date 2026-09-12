using System.Globalization;
using LoeBalance.Core.Models;
using LoeBalance.Core.Persistence;
using LoeBalance.Core.Refresh;
using LoeBalance.Platform.Windows;

namespace LoeBalance.Desktop.Wpf.ViewModels;

public enum RefreshIntervalPreset
{
    ThirtySeconds,
    OneMinute,
    FiveMinutes,
    Custom
}

/// <summary>
/// Mirrors the macOS settings view model: preset selection, clamped custom intervals,
/// persistence with error rollback, and launch-at-login that always reflects the real
/// service state.
/// </summary>
public sealed class SettingsViewModel
{
    private readonly IWindowsSettingsStore _preferencesStore;
    private readonly IRefreshScheduler _scheduler;
    private readonly IStartupRegistration _launchAtLogin;
    private AppPreferences _preferences;

    public SettingsViewModel(
        IWindowsSettingsStore preferencesStore,
        IRefreshScheduler scheduler,
        IStartupRegistration launchAtLogin,
        Action<ShakeStrength> onShakeStrengthChanged,
        Action<bool> onShowsDesktopCardChanged,
        Action<bool> onShowsTaskbarBalanceChanged,
        Func<Task> logout)
    {
        _preferencesStore = preferencesStore;
        _scheduler = scheduler;
        _launchAtLogin = launchAtLogin;
        _preferences = AppPreferences.Empty;
        OnShakeStrengthChanged = onShakeStrengthChanged;
        OnShowsDesktopCardChanged = onShowsDesktopCardChanged;
        OnShowsTaskbarBalanceChanged = onShowsTaskbarBalanceChanged;
        Logout = logout;
    }

    // Named `Shake` so the property does not shadow the ShakeStrength type inside this class.
    public ShakeStrength Shake { get; private set; } = ShakeStrength.Weak;
    public bool ShowsDesktopCard { get; private set; } = true;
    public bool ShowsTaskbarBalance { get; private set; } = true;
    public bool LaunchAtLogin { get; private set; }
    public RefreshIntervalPreset RefreshPreset { get; private set; } = RefreshIntervalPreset.ThirtySeconds;
    public string CustomInterval { get; set; } = "30";
    public string ErrorMessage { get; private set; } = string.Empty;

    internal Action<ShakeStrength> OnShakeStrengthChanged { get; }
    internal Action<bool> OnShowsDesktopCardChanged { get; }
    internal Action<bool> OnShowsTaskbarBalanceChanged { get; }
    internal Func<Task> Logout { get; }

    public event EventHandler? StateChanged;

    public async Task InitializeAsync()
    {
        _preferences = await _preferencesStore.LoadAsync() ?? AppPreferences.Empty;
        Shake = _preferences.ShakeStrength;
        ShowsDesktopCard = _preferences.ShowsDesktopCard;
        ShowsTaskbarBalance = _preferences.ShowsTaskbarBalance;
        LaunchAtLogin = _launchAtLogin.IsEnabled;
        RefreshPreset = PresetFor(_preferences.ClampedRefreshIntervalSeconds);
        CustomInterval = _preferences.ClampedRefreshIntervalSeconds.ToString("0", CultureInfo.InvariantCulture);
        RaiseStateChanged();
    }

    public async Task SelectPresetAsync(RefreshIntervalPreset preset)
    {
        RefreshPreset = preset;
        if (preset is not RefreshIntervalPreset.Custom)
        {
            CustomInterval = SecondsFor(preset).ToString("0", CultureInfo.InvariantCulture);
            RaiseStateChanged();
            await ApplyRefreshIntervalAsync();
            return;
        }

        RaiseStateChanged();
    }

    public async Task ApplyRefreshIntervalAsync()
    {
        if (!double.TryParse(CustomInterval, NumberStyles.Float, CultureInfo.InvariantCulture, out var value) ||
            !double.IsFinite(value))
        {
            RefreshPreset = RefreshIntervalPreset.Custom;
            ErrorMessage = "Enter a valid refresh interval.";
            RaiseStateChanged();
            return;
        }

        if (value < 1)
        {
            RefreshPreset = RefreshIntervalPreset.Custom;
            ErrorMessage = "Enter a refresh interval of at least 1 second.";
            RaiseStateChanged();
            return;
        }

        var candidate = _preferences.WithRefreshInterval(value);
        try
        {
            await _preferencesStore.SaveAsync(candidate);
        }
        catch (Exception)
        {
            ErrorMessage = "Unable to save settings.";
            RaiseStateChanged();
            return;
        }

        _preferences = candidate;
        RefreshPreset = PresetFor(candidate.ClampedRefreshIntervalSeconds);
        CustomInterval = candidate.ClampedRefreshIntervalSeconds.ToString("0", CultureInfo.InvariantCulture);
        ErrorMessage = string.Empty;
        _scheduler.UpdateInterval(candidate.ClampedRefreshIntervalSeconds);
        RaiseStateChanged();
    }

    public async Task SetShakeStrengthAsync(ShakeStrength value)
    {
        var candidate = _preferences with { ShakeStrength = value };
        if (!await TrySaveAsync(candidate)) return;

        Shake = value;
        OnShakeStrengthChanged(value);
        RaiseStateChanged();
    }

    public async Task SetShowsDesktopCardAsync(bool value)
    {
        var candidate = _preferences with { ShowsDesktopCard = value };
        if (!await TrySaveAsync(candidate)) return;

        ShowsDesktopCard = value;
        OnShowsDesktopCardChanged(value);
        RaiseStateChanged();
    }

    public async Task SetShowsTaskbarBalanceAsync(bool value)
    {
        var candidate = _preferences with { ShowsTaskbarBalance = value };
        if (!await TrySaveAsync(candidate)) return;

        ShowsTaskbarBalance = value;
        OnShowsTaskbarBalanceChanged(value);
        RaiseStateChanged();
    }

    public async Task SetLaunchAtLoginAsync(bool value)
    {
        var previous = _launchAtLogin.IsEnabled;
        try
        {
            _launchAtLogin.SetEnabled(value);
        }
        catch (Exception)
        {
            LaunchAtLogin = _launchAtLogin.IsEnabled;
            ErrorMessage = "Unable to update Launch at Login.";
            RaiseStateChanged();
            return;
        }

        var actual = _launchAtLogin.IsEnabled;
        var candidate = _preferences with { LaunchAtLogin = actual };
        if (!await TrySaveAsync(candidate))
        {
            try
            {
                _launchAtLogin.SetEnabled(previous);
            }
            catch (Exception)
            {
                // Keep the framework-reported state when the rollback itself fails.
            }
            LaunchAtLogin = _launchAtLogin.IsEnabled;
            RaiseStateChanged();
            return;
        }

        LaunchAtLogin = actual;
        RaiseStateChanged();
    }

    public async Task LogoutAsync()
    {
        await Logout();
        await InitializeAsync();
    }

    private async Task<bool> TrySaveAsync(AppPreferences candidate)
    {
        try
        {
            await _preferencesStore.SaveAsync(candidate);
        }
        catch (Exception)
        {
            ErrorMessage = "Unable to save settings.";
            RaiseStateChanged();
            return false;
        }

        _preferences = candidate;
        ErrorMessage = string.Empty;
        return true;
    }

    private static RefreshIntervalPreset PresetFor(double seconds) => seconds switch
    {
        30 => RefreshIntervalPreset.ThirtySeconds,
        60 => RefreshIntervalPreset.OneMinute,
        300 => RefreshIntervalPreset.FiveMinutes,
        _ => RefreshIntervalPreset.Custom
    };

    private static double SecondsFor(RefreshIntervalPreset preset) => preset switch
    {
        RefreshIntervalPreset.ThirtySeconds => 30,
        RefreshIntervalPreset.OneMinute => 60,
        RefreshIntervalPreset.FiveMinutes => 300,
        _ => 30
    };

    private void RaiseStateChanged() => StateChanged?.Invoke(this, EventArgs.Empty);
}
