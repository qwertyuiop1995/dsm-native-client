using System.Text.Json;
using LanStash.Domain;

namespace LanStash.App.CloudDrive;

internal sealed class DesktopCloudDriveStore
{
    private sealed record Snapshot(
        int Version,
        IReadOnlyList<DesktopDriveMapping> Mappings,
        IReadOnlyDictionary<Guid, IReadOnlyDictionary<string, string>> ItemPaths,
        IReadOnlyDictionary<Guid, DesktopDriveMappingRuntime>? Runtimes);

    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly string _path = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "LanStash",
        "desktop-drives-v1.json");

    internal async Task<IReadOnlyList<DesktopDriveMapping>> LoadAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            return (await LoadSnapshotUnlockedAsync().ConfigureAwait(false)).Mappings;
        }
        finally
        {
            _gate.Release();
        }
    }

    internal async Task SaveAsync(IReadOnlyList<DesktopDriveMapping> mappings)
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var snapshot = await LoadSnapshotUnlockedAsync().ConfigureAwait(false);
            var mappingIds = mappings.Select(item => item.Id).ToHashSet();
            var itemPaths = snapshot.ItemPaths
                .Where(item => mappingIds.Contains(item.Key))
                .ToDictionary(item => item.Key, item => item.Value);
            var runtimes = (snapshot.Runtimes
                    ?? new Dictionary<Guid, DesktopDriveMappingRuntime>())
                .Where(item => mappingIds.Contains(item.Key))
                .ToDictionary(item => item.Key, item => item.Value);
            await SaveSnapshotUnlockedAsync(
                new Snapshot(3, mappings, itemPaths, runtimes)).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    internal async Task<DesktopDriveMappingRuntime> LoadRuntimeAsync(
        Guid mappingId)
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var snapshot = await LoadSnapshotUnlockedAsync().ConfigureAwait(false);
            return snapshot.Runtimes?.GetValueOrDefault(mappingId)
                ?? DesktopDriveMappingRuntime.Default;
        }
        finally
        {
            _gate.Release();
        }
    }

    internal async Task SaveRuntimeAsync(
        Guid mappingId,
        DesktopDriveMappingRuntime runtime)
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var snapshot = await LoadSnapshotUnlockedAsync().ConfigureAwait(false);
            if (!snapshot.Mappings.Any(item => item.Id == mappingId))
            {
                return;
            }
            var runtimes = (snapshot.Runtimes
                    ?? new Dictionary<Guid, DesktopDriveMappingRuntime>())
                .ToDictionary(item => item.Key, item => item.Value);
            runtimes[mappingId] = runtime;
            await SaveSnapshotUnlockedAsync(
                snapshot with { Version = 3, Runtimes = runtimes })
                .ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    internal async Task UpdateRuntimeAsync(
        Guid mappingId,
        Func<DesktopDriveMappingRuntime, DesktopDriveMappingRuntime> update)
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var snapshot = await LoadSnapshotUnlockedAsync().ConfigureAwait(false);
            if (!snapshot.Mappings.Any(item => item.Id == mappingId))
            {
                return;
            }
            var runtimes = (snapshot.Runtimes
                    ?? new Dictionary<Guid, DesktopDriveMappingRuntime>())
                .ToDictionary(item => item.Key, item => item.Value);
            var current = runtimes.GetValueOrDefault(mappingId)
                ?? DesktopDriveMappingRuntime.Default;
            runtimes[mappingId] = update(current);
            await SaveSnapshotUnlockedAsync(
                snapshot with { Version = 3, Runtimes = runtimes })
                .ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    internal async Task<IReadOnlyDictionary<string, string>> LoadItemPathsAsync(
        Guid mappingId)
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var snapshot = await LoadSnapshotUnlockedAsync().ConfigureAwait(false);
            return snapshot.ItemPaths.TryGetValue(mappingId, out var values)
                ? values
                : new Dictionary<string, string>();
        }
        finally
        {
            _gate.Release();
        }
    }

    internal async Task RegisterItemPathsAsync(
        Guid mappingId,
        IEnumerable<string> remotePaths)
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            var snapshot = await LoadSnapshotUnlockedAsync().ConfigureAwait(false);
            if (!snapshot.Mappings.Any(item => item.Id == mappingId))
            {
                return;
            }
            var allPaths = snapshot.ItemPaths.ToDictionary(
                item => item.Key,
                item => item.Value);
            var mappingPaths = allPaths.TryGetValue(mappingId, out var existing)
                ? existing.ToDictionary(item => item.Key, item => item.Value)
                : new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var rawPath in remotePaths)
            {
                var path = DesktopDrivePath.Normalize(rawPath);
                var identity = DesktopDriveItemIdentity.Identifier(mappingId, path);
                if (path is not null && identity is not null)
                {
                    mappingPaths[identity] = path;
                }
            }
            allPaths[mappingId] = mappingPaths;
            await SaveSnapshotUnlockedAsync(
                snapshot with
                {
                    Version = 3,
                    ItemPaths = allPaths,
                }).ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<Snapshot> LoadSnapshotUnlockedAsync()
    {
        if (!File.Exists(_path))
        {
            return new(
                3,
                [],
                new Dictionary<Guid, IReadOnlyDictionary<string, string>>(),
                new Dictionary<Guid, DesktopDriveMappingRuntime>());
        }
        var content = await File.ReadAllTextAsync(_path).ConfigureAwait(false);
        using var document = JsonDocument.Parse(content);
        if (document.RootElement.ValueKind == JsonValueKind.Array)
        {
            var mappings = JsonSerializer.Deserialize<List<DesktopDriveMapping>>(content)
                ?? [];
            return new(
                3,
                mappings,
                new Dictionary<Guid, IReadOnlyDictionary<string, string>>(),
                new Dictionary<Guid, DesktopDriveMappingRuntime>());
        }
        return JsonSerializer.Deserialize<Snapshot>(content)
            ?? new(
                3,
                [],
                new Dictionary<Guid, IReadOnlyDictionary<string, string>>(),
                new Dictionary<Guid, DesktopDriveMappingRuntime>());
    }

    private async Task SaveSnapshotUnlockedAsync(Snapshot snapshot)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
        var temporaryPath = $"{_path}.{Guid.NewGuid():N}.tmp";
        try
        {
            await File.WriteAllTextAsync(
                temporaryPath,
                JsonSerializer.Serialize(snapshot)).ConfigureAwait(false);
            File.Move(temporaryPath, _path, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporaryPath))
            {
                File.Delete(temporaryPath);
            }
        }
    }
}
