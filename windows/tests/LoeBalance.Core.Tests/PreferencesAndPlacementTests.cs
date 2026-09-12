using System.Text.Json;
using LoeBalance.Core.Models;
using LoeBalance.Core.Persistence;

namespace LoeBalance.Core.Tests;

public sealed class PreferencesAndPlacementTests
{
    [Fact]
    public void RoundTripsPreferencesIncludingDesktopCardFrameAndShakeNames()
    {
        var preferences = new AppPreferences(45, ShakeStrength.Strong, false, true, new DesktopCardFrame(120, 240, 326, 218));

        var json = JsonSerializer.Serialize(preferences, PersistenceJson.Options);
        var restored = JsonSerializer.Deserialize<AppPreferences>(json, PersistenceJson.Options);

        Assert.Contains("\"shakeStrength\": \"strong\"", json, StringComparison.Ordinal);
        Assert.Equal(preferences, restored);
    }

    [Fact]
    public void TaskbarBalanceReadoutIsOnByDefaultAndRoundTrips()
    {
        Assert.True(AppPreferences.Empty.ShowsTaskbarBalance);
        Assert.True(new AppPreferences(30).ShowsTaskbarBalance);

        var preferences = AppPreferences.Empty with { ShowsTaskbarBalance = false };
        var restored = JsonSerializer.Deserialize<AppPreferences>(
            JsonSerializer.Serialize(preferences, PersistenceJson.Options),
            PersistenceJson.Options);

        Assert.False(restored!.ShowsTaskbarBalance);
    }

    [Fact]
    public void MissingFieldsFallBackToDefaults()
    {
        var restored = JsonSerializer.Deserialize<AppPreferences>("{}", PersistenceJson.Options);

        Assert.NotNull(restored);
        Assert.Equal(30, restored!.RefreshIntervalSeconds);
        Assert.Equal(ShakeStrength.Weak, restored.ShakeStrength);
        Assert.True(restored.ShowsDesktopCard);
        Assert.False(restored.LaunchAtLogin);
        Assert.Null(restored.DesktopCardFrame);
    }

    [Fact]
    public void RefreshIntervalIsClampedToOneThroughThreeThousandSixHundred()
    {
        Assert.Equal(1, new AppPreferences(0).ClampedRefreshIntervalSeconds);
        Assert.Equal(1, new AppPreferences(-40).ClampedRefreshIntervalSeconds);
        Assert.Equal(3600, new AppPreferences(999_999).ClampedRefreshIntervalSeconds);
        Assert.Equal(45, new AppPreferences(45).WithClampedRefreshInterval().RefreshIntervalSeconds);
    }

    [Fact]
    public void PlacementClampsIntoScreenAndKeepsTheCardVisible()
    {
        var workArea = new DesktopWorkArea(0, 0, 1000, 700);

        var clamped = DesktopCardPlacement.Clamp(new DesktopCardFrame(900, 650, 326, 218), workArea, 326, 218);

        Assert.Equal(new DesktopCardFrame(674, 482, 326, 218), clamped);
    }

    [Fact]
    public void PlacementPinsToTheTopLeftWhenTheScreenIsSmallerThanTheCard()
    {
        var workArea = new DesktopWorkArea(50, 60, 200, 100);

        var clamped = DesktopCardPlacement.Clamp(new DesktopCardFrame(900, 650, 326, 218), workArea, 326, 218);

        Assert.Equal(new DesktopCardFrame(50, 60, 326, 218), clamped);
    }

    [Fact]
    public void DefaultPlacementUsesTheBottomRightCornerWithInsets()
    {
        var defaultFrame = DesktopCardPlacement.Default(new DesktopWorkArea(0, 0, 1920, 1040), 326, 218);

        Assert.Equal(new DesktopCardFrame(1920 - 326 - 24, 1040 - 218 - 24, 326, 218), defaultFrame);
    }

    [Fact]
    public void OffscreenPlacementDetectionSupportsMonitorFallback()
    {
        var workArea = new DesktopWorkArea(0, 0, 1000, 700);

        Assert.True(DesktopCardPlacement.Intersects(new DesktopCardFrame(500, 300, 326, 218), workArea));
        Assert.False(DesktopCardPlacement.Intersects(new DesktopCardFrame(4000, 3000, 326, 218), workArea));
    }
}
