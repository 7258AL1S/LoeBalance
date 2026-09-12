using Microsoft.Win32;
using LoeBalance.Platform.Windows;

namespace LoeBalance.Platform.Windows.Tests;

public sealed class StartupRegistrationTests
{
    // A dedicated test subkey keeps the real Run key untouched.
    private const string TestSubKey = @"Software\LoeBalance\Tests\Run";

    [Fact]
    public void ReportsAndAppliesTheActualRegistryState()
    {
        var registration = new StartupRegistration(@"C:\Apps\LoeBalance\LoeBalance.Desktop.Wpf.exe", TestSubKey);
        try
        {
            registration.SetEnabled(false);
            Assert.False(registration.IsEnabled);

            registration.SetEnabled(true);

            Assert.True(registration.IsEnabled);
            using (var key = Registry.CurrentUser.OpenSubKey(TestSubKey, writable: false))
            {
                Assert.Equal(
                    "\"C:\\Apps\\LoeBalance\\LoeBalance.Desktop.Wpf.exe\"",
                    key?.GetValue(StartupRegistration.DefaultValueName));
            }

            registration.SetEnabled(false);
            Assert.False(registration.IsEnabled);
        }
        finally
        {
            Registry.CurrentUser.DeleteSubKeyTree(TestSubKey, throwOnMissingSubKey: false);
        }
    }

    [Fact]
    public void DefaultRegistrationTargetsThePerUserRunKey()
    {
        var registration = new StartupRegistration(@"C:\Apps\LoeBalance.exe");

        Assert.Equal("\"C:\\Apps\\LoeBalance.exe\"", registration.Command);
        Assert.Equal(@"Software\Microsoft\Windows\CurrentVersion\Run", WindowsPlatformNotes.StartupRegistrySubKey);
    }
}

public sealed class NetworkAvailabilityMonitorTests
{
    [Fact]
    public void StartStopAndDisposeAreIdempotent()
    {
        using var monitor = new NetworkAvailabilityMonitor();

        monitor.Start();
        monitor.Start();
        Assert.IsType<bool>(monitor.IsAvailable);

        monitor.Stop();
        monitor.Stop();
        monitor.Dispose();
        monitor.Dispose();
    }

    [Fact]
    public void StoppedMonitorDoesNotRaiseEvents()
    {
        using var monitor = new NetworkAvailabilityMonitor();
        var raised = 0;
        monitor.AvailabilityChanged += (_, _) => Interlocked.Increment(ref raised);

        monitor.Start();
        monitor.Stop();
        // Handlers are detached on Stop; nothing should be raised afterwards even if the
        // operating system keeps sending station-level notifications.
        Thread.Sleep(50);

        Assert.Equal(0, raised);
    }
}

public sealed class PowerResumeMonitorTests
{
    [Fact]
    public void StartStopAndDisposeAreIdempotent()
    {
        using var monitor = new PowerResumeMonitor();

        monitor.Start();
        monitor.Start();
        monitor.Stop();
        monitor.Stop();
        monitor.Dispose();
        monitor.Dispose();

        Assert.IsType<bool>(monitor.IsSupported);
    }
}
