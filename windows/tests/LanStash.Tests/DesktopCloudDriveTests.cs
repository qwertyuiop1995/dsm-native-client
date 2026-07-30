using LanStash.Domain;

namespace LanStash.Tests;

public sealed class DesktopCloudDriveTests
{
    private const long GiB = 1024L * 1024 * 1024;

    [Fact]
    public void ParentAndChildMappingsOnTheSameNasOverlap()
    {
        var profileId = Guid.NewGuid();
        var parent = Mapping(profileId, DesktopDriveScope.Folder("/share/projects"));
        var child = Mapping(profileId, DesktopDriveScope.Folder("//share/projects/design/"));

        Assert.True(parent.Overlaps(child));
    }

    [Fact]
    public void DifferentNasOrSiblingMappingsDoNotOverlap()
    {
        var profileId = Guid.NewGuid();
        var first = Mapping(profileId, DesktopDriveScope.Folder("/share/project"));
        var differentProfile = Mapping(
            Guid.NewGuid(),
            DesktopDriveScope.Folder("/share/project"));
        var sibling = Mapping(
            profileId,
            DesktopDriveScope.Folder("/share/project-archive"));

        Assert.False(first.Overlaps(differentProfile));
        Assert.False(first.Overlaps(sibling));
    }

    [Fact]
    public void AllSharesOverlapsAnyFolderOnTheSameNas()
    {
        var profileId = Guid.NewGuid();

        Assert.True(
            Mapping(profileId, DesktopDriveScope.AllShares)
                .Overlaps(Mapping(profileId, DesktopDriveScope.Folder("/share/folder"))));
    }

    [Fact]
    public void SpaceDecisionUsesMissingBytesPeakAndReserve()
    {
        var decision = DesktopDriveCacheSpaceCalculator.Evaluate(
            [
                new(8 * GiB, 3 * GiB),
                new(2 * GiB, 2 * GiB),
            ],
            100 * GiB,
            20 * GiB);

        Assert.Equal(
            new DesktopDriveCacheSpaceDecision(
                DesktopDriveCacheSpaceDecisionKind.Allowed,
                15 * GiB,
                20 * GiB),
            decision);
    }

    [Fact]
    public void InsufficientSpaceIncludesTheShortage()
    {
        var decision = DesktopDriveCacheSpaceCalculator.Evaluate(
            [new(8 * GiB)],
            100 * GiB,
            10 * GiB);

        Assert.Equal(
            new DesktopDriveCacheSpaceDecision(
                DesktopDriveCacheSpaceDecisionKind.Insufficient,
                21 * GiB,
                10 * GiB,
                11 * GiB),
            decision);
    }

    [Fact]
    public void UnknownSizeBlocksTheCacheDecision()
    {
        var decision = DesktopDriveCacheSpaceCalculator.Evaluate(
            [new(null)],
            100 * GiB,
            50 * GiB);

        Assert.Equal(DesktopDriveCacheSpaceDecisionKind.UnknownSize, decision.Kind);
    }

    [Fact]
    public void PausedStateOnlyAllowsCheckRemoveOrFailure()
    {
        Assert.True(DesktopDriveMappingState.Paused.CanTransitionTo(
            DesktopDriveMappingState.Checking));
        Assert.True(DesktopDriveMappingState.Paused.CanTransitionTo(
            DesktopDriveMappingState.Removing));
        Assert.False(DesktopDriveMappingState.Paused.CanTransitionTo(
            DesktopDriveMappingState.Available));
        Assert.False(DesktopDriveMappingState.Paused.CanTransitionTo(
            DesktopDriveMappingState.Offline));
    }

    [Fact]
    public void TemporaryCacheEvictionUsesLeastRecentlyAccessedFirst()
    {
        var now = DateTimeOffset.UtcNow;
        var entries = new[]
        {
            new DesktopDriveCacheEntry(
                "/old.bin",
                DesktopDriveCacheEntryKind.Temporary,
                4,
                4,
                now.AddMinutes(-2),
                now),
            new DesktopDriveCacheEntry(
                "/new.bin",
                DesktopDriveCacheEntryKind.Temporary,
                6,
                6,
                now,
                now),
            new DesktopDriveCacheEntry(
                "/offline.bin",
                DesktopDriveCacheEntryKind.KeptOffline,
                100,
                100,
                now.AddMinutes(-3),
                now),
        };

        Assert.Equal(
            ["/old.bin"],
            DesktopDriveCacheEvictionPlanner.TemporaryPathsToEvict(entries, 6));
    }

    [Theory]
    [InlineData("report?.txt", "report%3F.txt")]
    [InlineData("name. ", "name%2E%20")]
    [InlineData("CON.txt", "%00CON.txt")]
    [InlineData("LPT9", "%00LPT9")]
    [InlineData("100%.txt", "100%25.txt")]
    public void WindowsNamesAreEscapedWithoutChangingTheRemoteName(
        string remoteName,
        string localName)
    {
        Assert.Equal(
            localName,
            DesktopDriveWindowsNameCodec.EscapeSegment(remoteName));
    }

    [Fact]
    public void WindowsCaseCollisionsGetStableDistinctSuffixes()
    {
        var result = DesktopDriveWindowsNameCodec.BuildSafeSegments(
            ["/share/Readme.txt", "/share/README.TXT"]);

        Assert.NotEqual(
            result["/share/Readme.txt"],
            result["/share/README.TXT"],
            StringComparer.OrdinalIgnoreCase);
        Assert.StartsWith("Readme.txt~", result["/share/Readme.txt"]);
        Assert.StartsWith("README.TXT~", result["/share/README.TXT"]);
        var reversed = DesktopDriveWindowsNameCodec.BuildSafeSegments(
            ["/share/README.TXT", "/share/Readme.txt"]);
        Assert.Equal(result["/share/Readme.txt"], reversed["/share/Readme.txt"]);
        Assert.Equal(result["/share/README.TXT"], reversed["/share/README.TXT"]);
    }

    [Fact]
    public async Task RecursivePlanPagesFoldersAndTotalsTrustedSizes()
    {
        var root = new[]
        {
            File("/share/root.txt", 3),
            Folder("/share/sub"),
        };
        var sub = new[]
        {
            File("/share/sub/a.bin", 5),
            File("/share/sub/b.bin", 7),
        };

        var plan = await DesktopDriveTreePlanner.BuildAsync(
            ["/share"],
            (path, offset, limit, _) =>
            {
                var source = path == "/share" ? root : sub;
                var items = source.Skip(offset).Take(limit).ToArray();
                return Task.FromResult(new FilePage(items, source.Length, offset));
            },
            pageSize: 1);

        Assert.True(plan.IsComplete);
        Assert.Equal(
            ["/share/root.txt", "/share/sub/a.bin", "/share/sub/b.bin"],
            plan.Files.Select(item => item.RemotePath));
        Assert.Equal(15, plan.TotalBytes);
        Assert.Equal(7, plan.LargestFileBytes);
        Assert.Equal(2, plan.FolderCount);
    }

    [Fact]
    public async Task UnknownSizeAndInaccessibleFolderBlockConfirmation()
    {
        var plan = await DesktopDriveTreePlanner.BuildAsync(
            ["/share"],
            (path, _, _, _) =>
            {
                if (path == "/share/private")
                {
                    throw new UnauthorizedAccessException();
                }
                return Task.FromResult(new FilePage(
                    [
                        File("/share/unknown.bin", -1),
                        Folder("/share/private"),
                    ],
                    2,
                    0));
            });

        Assert.False(plan.IsComplete);
        Assert.Equal(
            [
                DesktopDrivePlanIssueKind.InaccessibleFolder,
                DesktopDrivePlanIssueKind.UnknownFileSize,
            ],
            plan.Issues.Select(issue => issue.Kind).Order());
    }

    private static DesktopDriveMapping Mapping(
        Guid profileId,
        DesktopDriveScope scope) =>
        new(
            Guid.NewGuid(),
            profileId,
            "Mapping",
            scope,
            DesktopDriveAccessMode.ReadOnly,
            DesktopDriveCachePolicy.Default,
            true,
            DateTimeOffset.UtcNow);

    private static FileItem File(string path, long size) =>
        new(
            path,
            Path.GetFileName(path),
            false,
            size,
            null,
            null,
            false,
            false);

    private static FileItem Folder(string path) =>
        new(
            path,
            Path.GetFileName(path),
            true,
            0,
            null,
            null,
            false,
            false);
}
