namespace LanStash.Domain;

public sealed record DesktopDrivePlannedFile(
    string RemotePath,
    long SizeBytes,
    DateTimeOffset? ModifiedAt);

public enum DesktopDrivePlanIssueKind
{
    InaccessibleFolder,
    UnknownFileSize,
    InvalidPath,
    ItemLimitReached,
    SizeOverflow,
    Cancelled,
}

public sealed record DesktopDrivePlanIssue(
    DesktopDrivePlanIssueKind Kind,
    string? RemotePath = null);

public sealed record DesktopDriveCachePlan(
    IReadOnlyList<DesktopDrivePlannedFile> Files,
    IReadOnlyList<string> Folders,
    IReadOnlyList<DesktopDrivePlanIssue> Issues,
    long TotalBytes,
    long LargestFileBytes,
    int FolderCount)
{
    public bool IsComplete => Issues.Count == 0;
}

public sealed record DesktopDrivePlanningProgress(
    int FolderCount,
    int FileCount,
    long DiscoveredBytes);

public enum DesktopDriveOfflinePhase
{
    Planning,
    CheckingSpace,
    Preparing,
    Downloading,
    Completed,
    Cancelled,
    Failed,
}

public sealed record DesktopDriveOfflineProgress(
    DesktopDriveOfflinePhase Phase,
    int CompletedFiles = 0,
    int TotalFiles = 0,
    long CompletedBytes = 0,
    long TotalBytes = 0,
    long? RequiredBytes = null,
    long? AvailableBytes = null,
    long? ShortageBytes = null,
    string? VolumeName = null);

public static class DesktopDriveTreePlanner
{
    public static async Task<DesktopDriveCachePlan> BuildAsync(
        IReadOnlyList<string> rootFolders,
        Func<string, int, int, CancellationToken, Task<FilePage>> loadPage,
        IReadOnlyList<DesktopDrivePlannedFile>? rootFiles = null,
        int itemLimit = 1_000_000,
        int pageSize = 500,
        IProgress<DesktopDrivePlanningProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        if (itemLimit <= 0 || pageSize <= 0)
        {
            return Result(
                [],
                [],
                [new(DesktopDrivePlanIssueKind.ItemLimitReached)],
                0,
                0,
                0);
        }

        var queue = new List<string>(rootFolders);
        var nextFolderIndex = 0;
        var visitedFolders = new HashSet<string>(StringComparer.Ordinal);
        var folders = new List<string>();
        var visitedFiles = new HashSet<string>(StringComparer.Ordinal);
        var files = new List<DesktopDrivePlannedFile>();
        var issues = new List<DesktopDrivePlanIssue>();
        long totalBytes = 0;
        long largestFileBytes = 0;

        foreach (var file in rootFiles ?? [])
        {
            if (files.Count >= itemLimit)
            {
                issues.Add(new(DesktopDrivePlanIssueKind.ItemLimitReached));
                break;
            }
            var path = DesktopDrivePath.Normalize(file.RemotePath);
            if (path is null)
            {
                issues.Add(new(
                    DesktopDrivePlanIssueKind.InvalidPath,
                    file.RemotePath));
                continue;
            }
            if (file.SizeBytes < 0)
            {
                issues.Add(new(
                    DesktopDrivePlanIssueKind.UnknownFileSize,
                    path));
                continue;
            }
            if (!visitedFiles.Add(path))
            {
                continue;
            }
            try
            {
                totalBytes = checked(totalBytes + file.SizeBytes);
            }
            catch (OverflowException)
            {
                issues.Add(new(DesktopDrivePlanIssueKind.SizeOverflow));
                totalBytes = long.MaxValue;
                largestFileBytes = Math.Max(
                    largestFileBytes,
                    file.SizeBytes);
                break;
            }
            largestFileBytes = Math.Max(largestFileBytes, file.SizeBytes);
            files.Add(file with { RemotePath = path });
        }
        progress?.Report(new(0, files.Count, totalBytes));

        while (nextFolderIndex < queue.Count)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                issues.Add(new(DesktopDrivePlanIssueKind.Cancelled));
                break;
            }
            var rawFolder = queue[nextFolderIndex++];
            var folder = DesktopDrivePath.Normalize(rawFolder);
            if (folder is null)
            {
                issues.Add(new(DesktopDrivePlanIssueKind.InvalidPath, rawFolder));
                continue;
            }
            if (!visitedFolders.Add(folder))
            {
                continue;
            }
            folders.Add(folder);

            var offset = 0;
            var folderFailed = false;
            do
            {
                try
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var page = await loadPage(
                        folder,
                        offset,
                        pageSize,
                        cancellationToken).ConfigureAwait(false);
                    foreach (var item in page.Items)
                    {
                        if (visitedFolders.Count + visitedFiles.Count >= itemLimit)
                        {
                            issues.Add(new(DesktopDrivePlanIssueKind.ItemLimitReached));
                            return Result(
                                files,
                                folders,
                                issues,
                                totalBytes,
                                largestFileBytes,
                                visitedFolders.Count);
                        }
                        if (item.IsDirectory)
                        {
                            queue.Add(item.Path);
                            continue;
                        }
                        var normalizedPath = DesktopDrivePath.Normalize(item.Path);
                        if (normalizedPath is null)
                        {
                            issues.Add(new(
                                DesktopDrivePlanIssueKind.InvalidPath,
                                item.Path));
                            continue;
                        }
                        if (!visitedFiles.Add(normalizedPath))
                        {
                            continue;
                        }
                        if (item.Size < 0)
                        {
                            issues.Add(new(
                                DesktopDrivePlanIssueKind.UnknownFileSize,
                                normalizedPath));
                            continue;
                        }
                        try
                        {
                            totalBytes = checked(totalBytes + item.Size);
                        }
                        catch (OverflowException)
                        {
                            issues.Add(new(DesktopDrivePlanIssueKind.SizeOverflow));
                            return Result(
                                files,
                                folders,
                                issues,
                                long.MaxValue,
                                Math.Max(largestFileBytes, item.Size),
                                visitedFolders.Count);
                        }
                        largestFileBytes = Math.Max(largestFileBytes, item.Size);
                        files.Add(new(
                            normalizedPath,
                            item.Size,
                            item.ModifiedAt));
                    }
                    progress?.Report(new(
                        visitedFolders.Count,
                        files.Count,
                        totalBytes));
                    var nextOffset = page.Offset + page.Items.Count;
                    if (nextOffset <= offset ||
                        page.Items.Count == 0 ||
                        nextOffset >= page.Total)
                    {
                        break;
                    }
                    offset = nextOffset;
                }
                catch (OperationCanceledException)
                {
                    issues.Add(new(DesktopDrivePlanIssueKind.Cancelled));
                    return Result(
                        files,
                        folders,
                        issues,
                        totalBytes,
                        largestFileBytes,
                        visitedFolders.Count);
                }
                catch
                {
                    issues.Add(new(
                        DesktopDrivePlanIssueKind.InaccessibleFolder,
                        folder));
                    folderFailed = true;
                }
            }
            while (!folderFailed);
        }

        return Result(
            files,
            folders,
            issues,
            totalBytes,
            largestFileBytes,
            visitedFolders.Count);
    }

    private static DesktopDriveCachePlan Result(
        IReadOnlyList<DesktopDrivePlannedFile> files,
        IReadOnlyList<string> folders,
        IReadOnlyList<DesktopDrivePlanIssue> issues,
        long totalBytes,
        long largestFileBytes,
        int folderCount) =>
        new(files, folders, issues, totalBytes, largestFileBytes, folderCount);
}
