using System.Security.Cryptography;
using System.Text;

namespace LanStash.Domain;

public enum DesktopDriveScopeKind
{
    AllShares,
    Folder,
}

public sealed record DesktopDriveScope(
    DesktopDriveScopeKind Kind,
    string? FolderPath = null)
{
    public static DesktopDriveScope AllShares { get; } =
        new(DesktopDriveScopeKind.AllShares);

    public static DesktopDriveScope Folder(string path) =>
        new(DesktopDriveScopeKind.Folder, path);
}

public enum DesktopDriveAccessMode
{
    ReadOnly,
}

public enum DesktopDriveCacheLocationKind
{
    SystemDefault,
    EligibleVolume,
}

public sealed record DesktopDriveCacheLocation(
    DesktopDriveCacheLocationKind Kind,
    string? VolumeId = null)
{
    public static DesktopDriveCacheLocation SystemDefault { get; } =
        new(DesktopDriveCacheLocationKind.SystemDefault);

    public static DesktopDriveCacheLocation EligibleVolume(string volumeId) =>
        new(DesktopDriveCacheLocationKind.EligibleVolume, volumeId);
}

public sealed record DesktopDriveCachePolicy(
    DesktopDriveCacheLocation Location,
    long TemporaryLimitBytes)
{
    public const long DefaultTemporaryLimitBytes = 10L * 1024 * 1024 * 1024;
    public const long MinimumFreeReserveBytes = 2L * 1024 * 1024 * 1024;
    public const long MaximumFreeReserveBytes = 20L * 1024 * 1024 * 1024;

    public static DesktopDriveCachePolicy Default { get; } =
        new(DesktopDriveCacheLocation.SystemDefault, DefaultTemporaryLimitBytes);
}

public enum DesktopDriveMappingState
{
    Preparing,
    Available,
    Checking,
    Paused,
    Offline,
    AuthenticationRequired,
    CacheVolumeUnavailable,
    InsufficientLocalSpace,
    Degraded,
    Removing,
    Failed,
}

public static class DesktopDriveMappingStateExtensions
{
    public static bool CanTransitionTo(
        this DesktopDriveMappingState source,
        DesktopDriveMappingState target)
    {
        if (source == target)
        {
            return true;
        }
        return source switch
        {
            DesktopDriveMappingState.Preparing =>
                target is DesktopDriveMappingState.Available
                    or DesktopDriveMappingState.Paused
                    or DesktopDriveMappingState.Offline
                    or DesktopDriveMappingState.AuthenticationRequired
                    or DesktopDriveMappingState.CacheVolumeUnavailable
                    or DesktopDriveMappingState.InsufficientLocalSpace
                    or DesktopDriveMappingState.Failed,
            DesktopDriveMappingState.Available =>
                target is DesktopDriveMappingState.Checking
                    or DesktopDriveMappingState.Paused
                    or DesktopDriveMappingState.Offline
                    or DesktopDriveMappingState.AuthenticationRequired
                    or DesktopDriveMappingState.CacheVolumeUnavailable
                    or DesktopDriveMappingState.InsufficientLocalSpace
                    or DesktopDriveMappingState.Degraded
                    or DesktopDriveMappingState.Removing
                    or DesktopDriveMappingState.Failed,
            DesktopDriveMappingState.Checking =>
                target is DesktopDriveMappingState.Available
                    or DesktopDriveMappingState.Paused
                    or DesktopDriveMappingState.Offline
                    or DesktopDriveMappingState.AuthenticationRequired
                    or DesktopDriveMappingState.CacheVolumeUnavailable
                    or DesktopDriveMappingState.InsufficientLocalSpace
                    or DesktopDriveMappingState.Degraded
                    or DesktopDriveMappingState.Removing
                    or DesktopDriveMappingState.Failed,
            DesktopDriveMappingState.Paused =>
                target is DesktopDriveMappingState.Checking
                    or DesktopDriveMappingState.Removing
                    or DesktopDriveMappingState.Failed,
            DesktopDriveMappingState.Offline =>
                target is DesktopDriveMappingState.Checking
                    or DesktopDriveMappingState.Paused
                    or DesktopDriveMappingState.AuthenticationRequired
                    or DesktopDriveMappingState.Removing
                    or DesktopDriveMappingState.Failed,
            DesktopDriveMappingState.AuthenticationRequired
                or DesktopDriveMappingState.CacheVolumeUnavailable
                or DesktopDriveMappingState.InsufficientLocalSpace =>
                target is DesktopDriveMappingState.Checking
                    or DesktopDriveMappingState.Paused
                    or DesktopDriveMappingState.Removing
                    or DesktopDriveMappingState.Failed,
            DesktopDriveMappingState.Degraded =>
                target is DesktopDriveMappingState.Checking
                    or DesktopDriveMappingState.Available
                    or DesktopDriveMappingState.Paused
                    or DesktopDriveMappingState.Offline
                    or DesktopDriveMappingState.AuthenticationRequired
                    or DesktopDriveMappingState.CacheVolumeUnavailable
                    or DesktopDriveMappingState.InsufficientLocalSpace
                    or DesktopDriveMappingState.Removing
                    or DesktopDriveMappingState.Failed,
            DesktopDriveMappingState.Removing =>
                target is DesktopDriveMappingState.Failed,
            DesktopDriveMappingState.Failed =>
                target is DesktopDriveMappingState.Preparing
                    or DesktopDriveMappingState.Checking
                    or DesktopDriveMappingState.Removing,
            _ => false,
        };
    }
}

public enum DesktopDriveItemAvailabilityState
{
    OnlineOnly,
    Downloading,
    TemporarilyAvailable,
    PinnedPending,
    AvailableOffline,
    Releasing,
    Unavailable,
    Failed,
}

public enum DesktopDriveCacheEntryKind
{
    Temporary,
    KeptOffline,
}

public sealed record DesktopDriveCacheEntry(
    string RemotePath,
    DesktopDriveCacheEntryKind Kind,
    long LogicalSizeBytes,
    long AllocatedSizeBytes,
    DateTimeOffset LastAccessedAt,
    DateTimeOffset UpdatedAt);

public sealed record DesktopDriveMappingRuntime(
    DesktopDriveMappingState State,
    bool IsManuallyPaused,
    DateTimeOffset? LastSuccessfulCheckAt,
    IReadOnlyList<string> PinnedPaths,
    IReadOnlyDictionary<string, DesktopDriveCacheEntry> CacheEntries)
{
    public static DesktopDriveMappingRuntime Default { get; } =
        new(
            DesktopDriveMappingState.Preparing,
            false,
            null,
            [],
            new Dictionary<string, DesktopDriveCacheEntry>(
                StringComparer.Ordinal));

    public bool KeepsOffline(string remotePath)
    {
        var normalized = DesktopDrivePath.Normalize(remotePath);
        return normalized is not null &&
            PinnedPaths.Any(candidate =>
                DesktopDrivePath.Normalize(candidate) is { } root &&
                DesktopDrivePath.IsAncestorOrSame(root, normalized));
    }
}

public sealed record DesktopDriveCacheSummary(
    long TemporaryBytes,
    long KeptOfflineBytes,
    int TemporaryItemCount,
    int KeptOfflineItemCount)
{
    public long TotalBytes => checked(TemporaryBytes + KeptOfflineBytes);
}

public sealed record DesktopDriveMapping(
    Guid Id,
    Guid ProfileId,
    string DisplayName,
    DesktopDriveScope Scope,
    DesktopDriveAccessMode AccessMode,
    DesktopDriveCachePolicy CachePolicy,
    bool LaunchAtLogin,
    DateTimeOffset CreatedAt)
{
    public bool Overlaps(DesktopDriveMapping other)
    {
        if (ProfileId != other.ProfileId)
        {
            return false;
        }
        if (Scope.Kind == DesktopDriveScopeKind.AllShares ||
            other.Scope.Kind == DesktopDriveScopeKind.AllShares)
        {
            return true;
        }
        var left = DesktopDrivePath.Normalize(Scope.FolderPath);
        var right = DesktopDrivePath.Normalize(other.Scope.FolderPath);
        return left is not null &&
            right is not null &&
            (DesktopDrivePath.IsAncestorOrSame(left, right) ||
             DesktopDrivePath.IsAncestorOrSame(right, left));
    }
}

public static class DesktopDrivePath
{
    public static string? Normalize(string? path)
    {
        if (path is null)
        {
            return null;
        }
        var components = path.Split(
            '/',
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (components.Any(component => component is "." or ".."))
        {
            return null;
        }
        return components.Length == 0 ? "/" : $"/{string.Join('/', components)}";
    }

    public static bool IsAncestorOrSame(string candidate, string path) =>
        candidate == "/" ||
        string.Equals(candidate, path, StringComparison.Ordinal) ||
        path.StartsWith($"{candidate}/", StringComparison.Ordinal);
}

public static class DesktopDriveWindowsNameCodec
{
    private static readonly HashSet<char> InvalidCharacters =
        ['<', '>', ':', '"', '/', '\\', '|', '?', '*'];

    public static string EscapeSegment(string value)
    {
        var builder = new StringBuilder();
        for (var index = 0; index < value.Length; index++)
        {
            var character = value[index];
            var isTrailingSpaceOrDot =
                character is ' ' or '.' &&
                value[(index + 1)..].All(item => item is ' ' or '.');
            if (character == '%' ||
                character < 32 ||
                InvalidCharacters.Contains(character) ||
                isTrailingSpaceOrDot)
            {
                foreach (var item in Encoding.UTF8.GetBytes([character]))
                {
                    builder.Append('%').Append(item.ToString("X2"));
                }
            }
            else
            {
                builder.Append(character);
            }
        }
        var escaped = builder.ToString();
        var stem = escaped.Split('.')[0];
        if (IsReservedDeviceName(stem))
        {
            escaped = $"%00{escaped}";
        }
        return escaped.Length == 0 ? "%00" : escaped;
    }

    public static IReadOnlyDictionary<string, string> BuildSafeSegments(
        IEnumerable<string> remotePaths)
    {
        var normalized = remotePaths
            .Select(DesktopDrivePath.Normalize)
            .OfType<string>()
            .Distinct(StringComparer.Ordinal)
            .Select(path => new
            {
                Path = path,
                Parent = path[..Math.Max(path.LastIndexOf('/'), 0)],
                BaseName = EscapeSegment(
                    path[(path.LastIndexOf('/') + 1)..]),
            })
            .ToArray();
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var group in normalized.GroupBy(
                     item => $"{item.Parent}\0{item.BaseName}",
                     StringComparer.OrdinalIgnoreCase))
        {
            if (group.Count() == 1)
            {
                var item = group.Single();
                result[item.Path] = item.BaseName;
                continue;
            }
            foreach (var item in group)
            {
                var digest = Convert.ToHexString(
                    SHA256.HashData(Encoding.UTF8.GetBytes(item.Path)))
                    .ToLowerInvariant()[..8];
                result[item.Path] = $"{item.BaseName}~{digest}";
            }
        }
        return result;
    }

    private static bool IsReservedDeviceName(string value) =>
        value.Equals("CON", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("PRN", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("AUX", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("NUL", StringComparison.OrdinalIgnoreCase) ||
        value.Length == 4 &&
        (value.StartsWith("COM", StringComparison.OrdinalIgnoreCase) ||
         value.StartsWith("LPT", StringComparison.OrdinalIgnoreCase)) &&
        value[3] is >= '1' and <= '9';
}

public static class DesktopDriveItemIdentity
{
    public static string? Identifier(Guid mappingId, string? remotePath)
    {
        var path = DesktopDrivePath.Normalize(remotePath);
        if (path is null)
        {
            return null;
        }
        var input = Encoding.UTF8.GetBytes(
            $"{mappingId:D}".ToLowerInvariant() + "\0" + path);
        return $"item:{Convert.ToHexString(SHA256.HashData(input)).ToLowerInvariant()}";
    }
}

public sealed record DesktopDriveCacheCandidate(
    long? SizeBytes,
    long LocallyAvailableBytes = 0);

public enum DesktopDriveCacheSpaceDecisionKind
{
    Allowed,
    Insufficient,
    UnknownSize,
    InvalidCapacity,
}

public sealed record DesktopDriveCacheSpaceDecision(
    DesktopDriveCacheSpaceDecisionKind Kind,
    long RequiredBytes = 0,
    long AvailableBytes = 0,
    long ShortageBytes = 0);

public static class DesktopDriveCacheSpaceCalculator
{
    public static DesktopDriveCacheSpaceDecision Evaluate(
        IReadOnlyList<DesktopDriveCacheCandidate> candidates,
        long volumeCapacityBytes,
        long availableCapacityBytes,
        long? transientPeakBytes = null)
    {
        if (volumeCapacityBytes < 0 || availableCapacityBytes < 0)
        {
            return new(DesktopDriveCacheSpaceDecisionKind.InvalidCapacity);
        }

        long missingBytes = 0;
        long largestMissingItem = 0;
        try
        {
            foreach (var candidate in candidates)
            {
                if (candidate.SizeBytes is null or < 0)
                {
                    return new(DesktopDriveCacheSpaceDecisionKind.UnknownSize);
                }
                var localBytes = Math.Max(candidate.LocallyAvailableBytes, 0);
                var missing = Math.Max(candidate.SizeBytes.Value -
                    Math.Min(localBytes, candidate.SizeBytes.Value), 0);
                missingBytes = checked(missingBytes + missing);
                largestMissingItem = Math.Max(largestMissingItem, missing);
            }

            var transientPeak = Math.Max(transientPeakBytes ?? largestMissingItem, 0);
            var required = checked(
                missingBytes +
                transientPeak +
                SafetyReserve(volumeCapacityBytes));
            if (required <= availableCapacityBytes)
            {
                return new(
                    DesktopDriveCacheSpaceDecisionKind.Allowed,
                    required,
                    availableCapacityBytes);
            }
            return new(
                DesktopDriveCacheSpaceDecisionKind.Insufficient,
                required,
                availableCapacityBytes,
                required - availableCapacityBytes);
        }
        catch (OverflowException)
        {
            return new(
                DesktopDriveCacheSpaceDecisionKind.Insufficient,
                long.MaxValue,
                availableCapacityBytes,
                long.MaxValue);
        }
    }

    public static long SafetyReserve(long volumeCapacityBytes)
    {
        if (volumeCapacityBytes <= 0)
        {
            return DesktopDriveCachePolicy.MinimumFreeReserveBytes;
        }
        var fivePercent = volumeCapacityBytes / 20;
        return Math.Min(
            Math.Max(fivePercent, DesktopDriveCachePolicy.MinimumFreeReserveBytes),
            DesktopDriveCachePolicy.MaximumFreeReserveBytes);
    }
}

public static class DesktopDriveCacheEvictionPlanner
{
    public static IReadOnlyList<string> TemporaryPathsToEvict(
        IEnumerable<DesktopDriveCacheEntry> entries,
        long limitBytes)
    {
        var limit = Math.Max(limitBytes, 0);
        var temporary = entries
            .Where(entry => entry.Kind == DesktopDriveCacheEntryKind.Temporary)
            .OrderBy(entry => entry.LastAccessedAt)
            .ThenBy(entry => entry.RemotePath, StringComparer.Ordinal)
            .ToArray();
        long total = 0;
        foreach (var entry in temporary)
        {
            try
            {
                total = checked(total + Math.Max(entry.AllocatedSizeBytes, 0));
            }
            catch (OverflowException)
            {
                total = long.MaxValue;
                break;
            }
        }
        if (total <= limit)
        {
            return [];
        }
        var paths = new List<string>();
        foreach (var entry in temporary)
        {
            paths.Add(entry.RemotePath);
            total = Math.Max(total - Math.Max(entry.AllocatedSizeBytes, 0), 0);
            if (total <= limit)
            {
                break;
            }
        }
        return paths;
    }
}
