using Microsoft.Win32;

namespace LoeBalance.Platform.Windows;

/// <summary>
/// Registers the application under <c>HKCU\Software\Microsoft\Windows\CurrentVersion\Run</c>.
/// <see cref="IsEnabled"/> always reports the state actually stored in the registry so the
/// UI never shows an optimistic value.
/// </summary>
public sealed class StartupRegistration : IStartupRegistration
{
    public const string DefaultValueName = "LoeBalance";

    private readonly string _executablePath;
    private readonly string _subKey;
    private readonly string _valueName;

    public StartupRegistration(
        string? executablePath = null,
        string subKey = WindowsPlatformNotes.StartupRegistrySubKey,
        string valueName = DefaultValueName)
    {
        _executablePath = executablePath ?? DefaultExecutablePath;
        _subKey = subKey;
        _valueName = valueName;
    }

    public static string DefaultExecutablePath
        => Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "LoeBalance.Desktop.Wpf.exe");

    public string Command => Quote(_executablePath);

    public bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(_subKey, writable: false);
            return key?.GetValue(_valueName) is string value && value.Length > 0;
        }
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled)
        {
            using var key = Registry.CurrentUser.CreateSubKey(_subKey, writable: true);
            key.SetValue(_valueName, Command, RegistryValueKind.String);
            return;
        }

        using var existing = Registry.CurrentUser.OpenSubKey(_subKey, writable: true);
        existing?.DeleteValue(_valueName, throwOnMissingValue: false);
    }

    private static string Quote(string path) => $"\"{path.Trim('"')}\"";
}
