using System.Text.Json;
using System.Text.Json.Serialization;
using LoeBalance.Core.Models;

namespace LoeBalance.Core.Persistence;

/// <summary>
/// Shared JSON settings for every persisted file so the Windows stores stay compatible
/// with each other and with the macOS camelCase payloads.
/// </summary>
public static class PersistenceJson
{
    public static JsonSerializerOptions Options { get; } = CreateOptions();

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web)
        {
            WriteIndented = true
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: true));
        return options;
    }
}

/// <summary>
/// Device-independent screen bounds for the desktop card. Coordinates use the Windows
/// convention: the origin is the top-left corner of the virtual desktop.
/// </summary>
public sealed record DesktopCardFrame(double X, double Y, double Width, double Height);

/// <summary>
/// Screen rectangle in the same coordinate space as <see cref="DesktopCardFrame"/>.
/// </summary>
public sealed record DesktopWorkArea(double X, double Y, double Width, double Height);

public sealed record AppPreferences(
    double RefreshIntervalSeconds = 30,
    ShakeStrength ShakeStrength = ShakeStrength.Weak,
    bool ShowsDesktopCard = true,
    bool LaunchAtLogin = false,
    DesktopCardFrame? DesktopCardFrame = null)
{
    public double ClampedRefreshIntervalSeconds => Math.Clamp(RefreshIntervalSeconds, 1, 3600);

    public static AppPreferences Empty => new();

    public AppPreferences WithClampedRefreshInterval()
        => this with { RefreshIntervalSeconds = ClampedRefreshIntervalSeconds };

    public AppPreferences WithRefreshInterval(double seconds)
        => this with { RefreshIntervalSeconds = Math.Clamp(seconds, 1, 3600) };
}

public sealed record PersistedSnapshotState(
    BalanceSnapshot? CachedSnapshot,
    DateTimeOffset? WatermarkTime,
    List<long> RecentUsageIds)
{
    public const int MaximumRecentUsageIds = 500;

    public static PersistedSnapshotState Empty => new(null, null, []);

    /// <summary>
    /// Records freshly observed usage identifiers the same way the macOS implementation does:
    /// existing entries move to the end, duplicates collapse, and the newest
    /// <see cref="MaximumRecentUsageIds"/> identifiers are kept.
    /// </summary>
    public PersistedSnapshotState RecordUsageIds(IEnumerable<long> ids)
    {
        var ordered = new List<long>(RecentUsageIds ?? []);
        foreach (var id in ids)
        {
            ordered.RemoveAll(existing => existing == id);
            ordered.Add(id);
        }
        return this with { RecentUsageIds = BoundedUnique(ordered) };
    }

    public static List<long> BoundedUnique(IEnumerable<long> ids)
    {
        var seen = new HashSet<long>();
        var unique = new List<long>();
        foreach (var id in ids)
        {
            if (seen.Add(id)) unique.Add(id);
        }
        if (unique.Count <= MaximumRecentUsageIds) return unique;
        return unique.Skip(unique.Count - MaximumRecentUsageIds).ToList();
    }
}

/// <summary>
/// Clamps a saved card position into a monitor work area, keeping the card fully visible
/// when the work area is large enough and pinning it to the top-left edge otherwise.
/// </summary>
public static class DesktopCardPlacement
{
    public static DesktopCardFrame Clamp(DesktopCardFrame requested, DesktopWorkArea workArea, double cardWidth, double cardHeight)
    {
        var x = workArea.Width < cardWidth
            ? workArea.X
            : Math.Clamp(requested.X, workArea.X, workArea.X + workArea.Width - cardWidth);
        var y = workArea.Height < cardHeight
            ? workArea.Y
            : Math.Clamp(requested.Y, workArea.Y, workArea.Y + workArea.Height - cardHeight);
        return new DesktopCardFrame(x, y, cardWidth, cardHeight);
    }

    public static DesktopCardFrame Default(DesktopWorkArea workArea, double cardWidth, double cardHeight)
    {
        var x = Math.Max(workArea.X, workArea.X + workArea.Width - cardWidth - 24);
        var y = Math.Max(workArea.Y, workArea.Y + workArea.Height - cardHeight - 24);
        return Clamp(new DesktopCardFrame(x, y, cardWidth, cardHeight), workArea, cardWidth, cardHeight);
    }

    public static bool Intersects(DesktopCardFrame frame, DesktopWorkArea workArea)
        => frame.X < workArea.X + workArea.Width
           && frame.X + frame.Width > workArea.X
           && frame.Y < workArea.Y + workArea.Height
           && frame.Y + frame.Height > workArea.Y;
}

public interface ISettingsStore
{
    Task<AppPreferences?> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default);
}

public interface ISnapshotStore
{
    Task<PersistedSnapshotState?> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(PersistedSnapshotState state, CancellationToken cancellationToken = default);
    Task ClearAsync(CancellationToken cancellationToken = default);
}

public sealed class JsonFileSnapshotStore : ISnapshotStore
{
    private readonly string _path;
    private readonly JsonSerializerOptions _options = PersistenceJson.Options;

    public JsonFileSnapshotStore(string path) => _path = path;

    public async Task<PersistedSnapshotState?> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_path)) return null;
        await using var stream = File.OpenRead(_path);
        var state = await JsonSerializer.DeserializeAsync<PersistedSnapshotState>(stream, _options, cancellationToken);
        return state is null
            ? null
            : state with { RecentUsageIds = PersistedSnapshotState.BoundedUnique(state.RecentUsageIds ?? []) };
    }

    public async Task SaveAsync(PersistedSnapshotState state, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        await using var stream = File.Create(_path);
        await JsonSerializer.SerializeAsync(stream, state, _options, cancellationToken);
    }

    public Task ClearAsync(CancellationToken cancellationToken = default)
    {
        if (File.Exists(_path)) File.Delete(_path);
        return Task.CompletedTask;
    }
}
