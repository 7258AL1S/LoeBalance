using System.Text.Json;
using LoeBalance.Core.Models;

namespace LoeBalance.Core.Persistence;

public sealed record AppPreferences(
    double RefreshIntervalSeconds = 30,
    ShakeStrength ShakeStrength = ShakeStrength.Weak,
    bool ShowsDesktopCard = true,
    bool LaunchAtLogin = false)
{
    public double ClampedRefreshIntervalSeconds => Math.Clamp(RefreshIntervalSeconds, 1, 3600);
}

public sealed record PersistedSnapshotState(
    BalanceSnapshot? CachedSnapshot,
    DateTimeOffset? WatermarkTime,
    List<long> RecentUsageIds)
{
    public static PersistedSnapshotState Empty => new(null, null, []);
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
    private readonly JsonSerializerOptions _options = new(JsonSerializerDefaults.Web);

    public JsonFileSnapshotStore(string path) => _path = path;

    public async Task<PersistedSnapshotState?> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(_path)) return null;
        await using var stream = File.OpenRead(_path);
        return await JsonSerializer.DeserializeAsync<PersistedSnapshotState>(stream, _options, cancellationToken);
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
