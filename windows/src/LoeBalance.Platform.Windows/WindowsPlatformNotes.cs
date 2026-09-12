namespace LoeBalance.Platform.Windows;

public static class WindowsPlatformNotes
{
    public const string CredentialManagerTarget = "LoeBalance:sub2api-refresh-token";
    public const string SettingsDirectory = "%LOCALAPPDATA%\\LoeBalance";
    public const string StartupRegistryKey = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run";

    public const string DesktopWindowRequirements =
        "Use a borderless WPF window with ShowInTaskbar=false, no activation on show, Topmost=false, " +
        "DPI-aware positioning, and explicit SetWindowPos validation for desktop-only placement.";

    public const string TrayBehavior =
        "Use NotifyIcon for the notification area. Show the balance in tooltip/context menu; keep floating debit text in the desktop card.";
}
