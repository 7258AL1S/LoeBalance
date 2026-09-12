using System.Text.Json;
using LoeBalance.Core.Models;
using LoeBalance.Core.Persistence;
using LoeBalance.Platform.Windows;

namespace LoeBalance.Platform.Windows.Tests;

public sealed class LocalAppDataStoreTests : IDisposable
{
    private readonly string _directory = Path.Combine(
        Path.GetTempPath(),
        "LoeBalance.Tests",
        Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_directory)) Directory.Delete(_directory, recursive: true);
    }

    [Fact]
    public async Task SettingsRoundTripAndClampTheRefreshInterval()
    {
        var store = new LocalAppDataSettingsStore(_directory);

        await store.SaveAsync(new AppPreferences(0.25, ShakeStrength.Strong, false, true, new DesktopCardFrame(120, 240, 326, 218)));
        var loaded = await store.LoadAsync();

        Assert.NotNull(loaded);
        Assert.Equal(1, loaded!.RefreshIntervalSeconds);
        Assert.Equal(ShakeStrength.Strong, loaded.ShakeStrength);
        Assert.False(loaded.ShowsDesktopCard);
        Assert.True(loaded.LaunchAtLogin);
        Assert.Equal(new DesktopCardFrame(120, 240, 326, 218), loaded.DesktopCardFrame);
    }

    [Fact]
    public async Task SettingsAreWrittenAtomicallyWithoutLeavingTemporaryFiles()
    {
        var store = new LocalAppDataSettingsStore(_directory);

        await store.SaveAsync(new AppPreferences(30));

        Assert.True(File.Exists(store.SettingsPath));
        Assert.Empty(Directory.GetFiles(_directory, "*.tmp"));
        Assert.Contains("\"refreshIntervalSeconds\"", await File.ReadAllTextAsync(store.SettingsPath), StringComparison.Ordinal);
    }

    [Fact]
    public async Task SettingsJsonContainsOnlyPersistedFields()
    {
        var store = new LocalAppDataSettingsStore(_directory);

        await store.SaveAsync(new AppPreferences(45, ShakeStrength.Strong, true, false, null));

        using var document = JsonDocument.Parse(await File.ReadAllTextAsync(store.SettingsPath));
        var names = document.RootElement.EnumerateObject().Select(property => property.Name).OrderBy(name => name).ToArray();
        Assert.Equal(
            [
                "desktopCardFrame", "launchAtLogin", "refreshIntervalSeconds", "shakeStrength",
                "showsDesktopCard", "showsTaskbarBalance"
            ],
            names);
    }

    [Fact]
    public async Task MissingAndCorruptSettingsFilesLoadAsNull()
    {
        var store = new LocalAppDataSettingsStore(_directory);
        Assert.Null(await store.LoadAsync());

        Directory.CreateDirectory(_directory);
        await File.WriteAllTextAsync(store.SettingsPath, "{ not json");

        Assert.Null(await store.LoadAsync());
    }

    [Fact]
    public async Task SnapshotRoundTripBoundsTheRecentUsageIdentifiers()
    {
        var store = new LocalAppDataSnapshotStore(_directory);
        var state = PersistedSnapshotState.Empty
            .RecordUsageIds(Enumerable.Range(0, 620).Select(value => (long)value))
            with
            {
                CachedSnapshot = new BalanceSnapshot(new Money(19.58m), new Money(0.30m), 11, DateTimeOffset.Parse("2026-09-12T00:00:00Z")),
                WatermarkTime = DateTimeOffset.Parse("2026-09-12T00:00:00Z")
            };

        await store.SaveAsync(state);
        var loaded = await store.LoadAsync();

        Assert.NotNull(loaded);
        Assert.Equal(PersistedSnapshotState.MaximumRecentUsageIds, loaded!.RecentUsageIds.Count);
        Assert.Equal(619, loaded.RecentUsageIds[^1]);
        Assert.Equal(new Money(19.58m), loaded.CachedSnapshot!.Balance);
        Assert.Equal(11, loaded.CachedSnapshot.TodayRequests);
    }

    [Fact]
    public async Task SnapshotRoundTripKeepsWatermarkAndClearRemovesTheFile()
    {
        var store = new LocalAppDataSnapshotStore(_directory);
        var watermark = DateTimeOffset.Parse("2026-09-12T08:30:00Z");

        await store.SaveAsync(new PersistedSnapshotState(null, watermark, []));
        var loaded = await store.LoadAsync();

        Assert.NotNull(loaded);
        Assert.Equal(watermark, loaded!.WatermarkTime);

        await store.ClearAsync();

        Assert.Null(await store.LoadAsync());
        Assert.False(File.Exists(store.SnapshotPath));
    }

    [Fact]
    public async Task UnknownPropertiesAndNumericEnumsStillLoad()
    {
        Directory.CreateDirectory(_directory);
        var path = Path.Combine(_directory, WindowsAppPaths.SettingsFileName);
        await File.WriteAllTextAsync(path, "{\"refreshIntervalSeconds\":60,\"shakeStrength\":2,\"futureField\":true}");

        var loaded = await new LocalAppDataSettingsStore(_directory).LoadAsync();

        Assert.NotNull(loaded);
        Assert.Equal(60, loaded!.RefreshIntervalSeconds);
        Assert.Equal(ShakeStrength.Strong, loaded.ShakeStrength);
    }

    [Fact]
    public void DefaultDirectoryTargetsLocalAppData()
    {
        var expected = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "LoeBalance");

        Assert.Equal(expected, LocalAppDataSettingsStore.DefaultDirectory);
        Assert.Equal(expected, WindowsAppPaths.DefaultDirectory);
    }
}
