using System.Text.Json;
using LoeBalance.Core.Persistence;

namespace LoeBalance.Platform.Windows;

/// <summary>
/// Persists preferences as JSON under <c>%LOCALAPPDATA%\LoeBalance</c>. Writes go to a
/// temporary file that is flushed to disk before replacing the target so a crash cannot
/// leave a half-written file behind.
/// </summary>
public sealed class LocalAppDataSettingsStore : IWindowsSettingsStore
{
    private readonly string _directory;

    public LocalAppDataSettingsStore(string? directory = null)
        => _directory = string.IsNullOrWhiteSpace(directory) ? DefaultDirectory : directory;

    public string Directory => _directory;
    public string SettingsPath => Path.Combine(_directory, WindowsAppPaths.SettingsFileName);

    public static string DefaultDirectory => WindowsAppPaths.DefaultDirectory;

    public async Task<AppPreferences?> LoadAsync(CancellationToken cancellationToken = default)
    {
        var preferences = await AtomicJsonFile.ReadAsync<AppPreferences>(SettingsPath, cancellationToken).ConfigureAwait(false);
        return preferences?.WithClampedRefreshInterval();
    }

    public Task SaveAsync(AppPreferences preferences, CancellationToken cancellationToken = default)
        => AtomicJsonFile.WriteAsync(SettingsPath, preferences.WithClampedRefreshInterval(), cancellationToken);
}

/// <summary>
/// Persists the cached balance snapshot and the recent usage identifiers as JSON under
/// <c>%LOCALAPPDATA%\LoeBalance</c>.
/// </summary>
public sealed class LocalAppDataSnapshotStore : IWindowsSnapshotStore
{
    private readonly string _directory;

    public LocalAppDataSnapshotStore(string? directory = null)
        => _directory = string.IsNullOrWhiteSpace(directory) ? LocalAppDataSettingsStore.DefaultDirectory : directory;

    public string SnapshotPath => Path.Combine(_directory, WindowsAppPaths.SnapshotFileName);

    public async Task<PersistedSnapshotState?> LoadAsync(CancellationToken cancellationToken = default)
    {
        var state = await AtomicJsonFile.ReadAsync<PersistedSnapshotState>(SnapshotPath, cancellationToken).ConfigureAwait(false);
        return state is null
            ? null
            : state with { RecentUsageIds = PersistedSnapshotState.BoundedUnique(state.RecentUsageIds ?? []) };
    }

    public Task SaveAsync(PersistedSnapshotState state, CancellationToken cancellationToken = default)
        => AtomicJsonFile.WriteAsync(SnapshotPath, state, cancellationToken);

    public Task ClearAsync(CancellationToken cancellationToken = default)
    {
        if (File.Exists(SnapshotPath)) File.Delete(SnapshotPath);
        return Task.CompletedTask;
    }
}

public static class WindowsAppPaths
{
    public const string SettingsFileName = "settings.json";
    public const string SnapshotFileName = "snapshot.json";

    public static string DefaultDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "LoeBalance");
}

internal static class AtomicJsonFile
{
    public static async Task<T?> ReadAsync<T>(string path, CancellationToken cancellationToken)
        where T : class
    {
        if (!File.Exists(path)) return null;

        try
        {
            await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
            return await JsonSerializer.DeserializeAsync<T>(stream, PersistenceJson.Options, cancellationToken)
                .ConfigureAwait(false);
        }
        catch (JsonException)
        {
            // A corrupt file behaves like a missing file: the app falls back to defaults and
            // the next successful save rewrites it.
            return null;
        }
        catch (IOException)
        {
            return null;
        }
    }

    public static async Task WriteAsync<T>(string path, T value, CancellationToken cancellationToken)
    {
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) System.IO.Directory.CreateDirectory(directory);

        var temporaryPath = path + ".tmp";
        await using (var stream = new FileStream(temporaryPath, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            await JsonSerializer.SerializeAsync(stream, value, PersistenceJson.Options, cancellationToken).ConfigureAwait(false);
            await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
            stream.Flush(flushToDisk: true);
        }

        File.Move(temporaryPath, path, overwrite: true);
    }
}
