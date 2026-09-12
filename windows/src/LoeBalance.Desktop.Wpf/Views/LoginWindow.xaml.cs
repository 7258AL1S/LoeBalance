using System.Windows;
using LoeBalance.Desktop.Wpf.ViewModels;

namespace LoeBalance.Desktop.Wpf.Views;

public partial class LoginWindow : Window
{
    private readonly LoginViewModel _viewModel;

    internal LoginWindow(LoginViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _viewModel.StateChanged += OnStateChanged;
        Closed += (_, _) => _viewModel.StateChanged -= OnStateChanged;
        Loaded += (_, _) => EmailBox.Focus();
        ApplyState();
    }

    /// <summary>Shows the window and brings it to the foreground for sign-in.</summary>
    internal void Present()
    {
        Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
        EmailBox.Focus();
    }

    private async void OnSignInClick(object sender, RoutedEventArgs e) => await SubmitAsync();

    private async Task SubmitAsync()
    {
        _viewModel.Email = EmailBox.Text;
        var password = PasswordBox.Password;
        try
        {
            await _viewModel.SubmitAsync(password);
        }
        finally
        {
            // The password never leaves this scope and is cleared from the control.
            password = string.Empty;
            PasswordBox.Clear();
        }
    }

    private void OnStateChanged(object? sender, EventArgs e) => Dispatcher.Invoke(ApplyState);

    private void ApplyState()
    {
        ErrorText.Text = _viewModel.ErrorMessage;
        SignInButton.IsEnabled = !_viewModel.IsSubmitting;
        EmailBox.IsEnabled = !_viewModel.IsSubmitting;
        PasswordBox.IsEnabled = !_viewModel.IsSubmitting;
        ProgressText.Text = _viewModel.IsSubmitting ? "Signing in…" : string.Empty;
    }
}
