using System.Windows;
using System.Windows.Controls;
using LoeBalance.Core.Models;
using LoeBalance.Desktop.Wpf.ViewModels;

namespace LoeBalance.Desktop.Wpf.Views;

public partial class SettingsWindow : Window
{
    private readonly SettingsViewModel _viewModel;
    private bool _suppressEvents;

    internal SettingsWindow(SettingsViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _viewModel.StateChanged += OnStateChanged;
        Closed += (_, _) => _viewModel.StateChanged -= OnStateChanged;
        ApplyState();
    }

    internal async Task InitializeAsync() => await _viewModel.InitializeAsync();

    internal void Present()
    {
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    internal void SetShowsDesktopCard(bool value) => DesktopCardCheck.IsChecked = value;

    internal void SetShowsTaskbarBalance(bool value) => TaskbarBalanceCheck.IsChecked = value;

    private async void OnShakeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressEvents) return;
        await _viewModel.SetShakeStrengthAsync(ShakeFor(ShakeBox.SelectedIndex));
    }

    private async void OnRefreshPresetChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressEvents) return;
        await _viewModel.SelectPresetAsync(PresetFor(RefreshBox.SelectedIndex));
    }

    private async void OnApplyIntervalClick(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        _viewModel.CustomInterval = CustomIntervalBox.Text;
        await _viewModel.ApplyRefreshIntervalAsync();
    }

    private async void OnDesktopCardToggled(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        await _viewModel.SetShowsDesktopCardAsync(DesktopCardCheck.IsChecked == true);
    }

    private async void OnTaskbarBalanceToggled(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        await _viewModel.SetShowsTaskbarBalanceAsync(TaskbarBalanceCheck.IsChecked == true);
    }

    private async void OnLaunchAtLoginToggled(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        await _viewModel.SetLaunchAtLoginAsync(LaunchAtLoginCheck.IsChecked == true);
    }

    private async void OnLogOutClick(object sender, RoutedEventArgs e)
    {
        if (_suppressEvents) return;
        await _viewModel.LogoutAsync();
    }

    private void OnStateChanged(object? sender, EventArgs e) => Dispatcher.Invoke(ApplyState);

    private void ApplyState()
    {
        _suppressEvents = true;
        try
        {
            ShakeBox.SelectedIndex = IndexFor(_viewModel.Shake);
            RefreshBox.SelectedIndex = IndexFor(_viewModel.RefreshPreset);
            CustomIntervalBox.Text = _viewModel.CustomInterval;
            CustomPanel.Visibility = _viewModel.RefreshPreset == RefreshIntervalPreset.Custom
                ? Visibility.Visible
                : Visibility.Collapsed;
            DesktopCardCheck.IsChecked = _viewModel.ShowsDesktopCard;
            TaskbarBalanceCheck.IsChecked = _viewModel.ShowsTaskbarBalance;
            LaunchAtLoginCheck.IsChecked = _viewModel.LaunchAtLogin;
            ErrorText.Text = _viewModel.ErrorMessage;
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    private static ShakeStrength ShakeFor(int index) => index switch
    {
        0 => ShakeStrength.Off,
        2 => ShakeStrength.Strong,
        _ => ShakeStrength.Weak
    };

    private static int IndexFor(ShakeStrength strength) => strength switch
    {
        ShakeStrength.Off => 0,
        ShakeStrength.Strong => 2,
        _ => 1
    };

    private static RefreshIntervalPreset PresetFor(int index) => index switch
    {
        0 => RefreshIntervalPreset.ThirtySeconds,
        1 => RefreshIntervalPreset.OneMinute,
        2 => RefreshIntervalPreset.FiveMinutes,
        _ => RefreshIntervalPreset.Custom
    };

    private static int IndexFor(RefreshIntervalPreset preset) => preset switch
    {
        RefreshIntervalPreset.ThirtySeconds => 0,
        RefreshIntervalPreset.OneMinute => 1,
        RefreshIntervalPreset.FiveMinutes => 2,
        _ => 3
    };
}
