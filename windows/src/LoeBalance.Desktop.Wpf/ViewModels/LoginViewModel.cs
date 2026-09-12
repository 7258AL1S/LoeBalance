using LoeBalance.Core.Auth;
using LoeBalance.Core.Models;

namespace LoeBalance.Desktop.Wpf.ViewModels;

/// <summary>
/// Mirrors the macOS login view model: the same validation, the same messages, and the
/// password is cleared from memory as soon as the attempt finishes.
/// </summary>
public sealed class LoginViewModel
{
    private readonly AuthManager _auth;

    public LoginViewModel(AuthManager auth, Action onSuccess)
    {
        _auth = auth;
        OnSuccess = onSuccess;
    }

    public string Email { get; set; } = string.Empty;
    public string ErrorMessage { get; private set; } = string.Empty;
    public bool IsSubmitting { get; private set; }

    public event EventHandler? StateChanged;

    internal Action OnSuccess { get; }

    public async Task SubmitAsync(string password)
    {
        if (IsSubmitting) return;

        var email = Email.Trim();
        ErrorMessage = string.Empty;
        if (!IsValidEmail(email))
        {
            ErrorMessage = "Enter a valid email address.";
            RaiseStateChanged();
            return;
        }
        if (password.Length < 6)
        {
            ErrorMessage = "Password must be at least 6 characters.";
            RaiseStateChanged();
            return;
        }

        IsSubmitting = true;
        RaiseStateChanged();
        try
        {
            await _auth.LoginAsync(email, password);
            OnSuccess();
        }
        catch (AppException exception)
        {
            ErrorMessage = Message(exception);
        }
        catch (Exception)
        {
            ErrorMessage = "Unable to sign in.";
        }
        finally
        {
            IsSubmitting = false;
            // The caller clears the password box; the view model never keeps a copy.
            RaiseStateChanged();
        }
    }

    internal static bool IsValidEmail(string value)
    {
        var email = value.Trim();
        var at = email.IndexOf('@');
        if (at <= 0) return false;
        var domain = email[(at + 1)..];
        return domain.Contains('.') && !domain.StartsWith('.') && !domain.EndsWith('.');
    }

    private static string Message(AppException exception) => exception.Kind switch
    {
        AppErrorKind.Unauthorized => "Email or password is incorrect.",
        AppErrorKind.ApiEnvelope => "Sign-in is required.",
        AppErrorKind.Transport => "Unable to reach the server.",
        _ => "Unable to sign in."
    };

    private void RaiseStateChanged() => StateChanged?.Invoke(this, EventArgs.Empty);
}
