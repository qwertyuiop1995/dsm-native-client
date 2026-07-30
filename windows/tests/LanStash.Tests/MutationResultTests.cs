using System.Text.Json;
using LanStash.Domain;

namespace LanStash.Tests;

public sealed class MutationResultTests
{
    [Theory]
    [InlineData(MutationResultStatus.ConfirmedSuccess, "confirmedSuccess")]
    [InlineData(MutationResultStatus.ConfirmedFailure, "confirmedFailure")]
    [InlineData(MutationResultStatus.SubmittedButUnverified, "submittedButUnverified")]
    [InlineData(MutationResultStatus.PartialSuccess, "partialSuccess")]
    [InlineData(MutationResultStatus.CancelledBeforeSubmission, "cancelledBeforeSubmission")]
    [InlineData(
        MutationResultStatus.CancellationRequestedAfterSubmission,
        "cancellationRequestedAfterSubmission")]
    [InlineData(MutationResultStatus.PermissionDenied, "permissionDenied")]
    [InlineData(MutationResultStatus.Unsupported, "unsupported")]
    public void 所有稳定状态序列化后保持线值(
        MutationResultStatus status,
        string wireValue)
    {
        var result = CreateValidResult(status);

        var json = JsonSerializer.Serialize(result);
        var decoded = JsonSerializer.Deserialize<MutationResult>(json);

        Assert.Equal(result, decoded);
        Assert.Contains($"\"status\":\"{wireValue}\"", json);
        Assert.Contains("\"schemaVersion\":1", json);
    }

    [Fact]
    public void 提交未确认必须要求刷新()
    {
        Assert.Throws<ArgumentException>(() => new MutationResult(
            1,
            MutationResultStatus.SubmittedButUnverified,
            "delete",
            submitted: true,
            requiresRefresh: false,
            new MutationResultCounts(0, 0, 1)));
    }

    [Fact]
    public void 诊断标签拒绝路径和自由文本()
    {
        Assert.Throws<ArgumentException>(() => new MutationResult(
            1,
            MutationResultStatus.ConfirmedFailure,
            "delete",
            submitted: true,
            requiresRefresh: false,
            new MutationResultCounts(0, 1, 0),
            diagnosticTag: "/volume1/private/file"));
    }

    private static MutationResult CreateValidResult(MutationResultStatus status)
    {
        return status switch
        {
            MutationResultStatus.ConfirmedSuccess =>
                Create(status, submitted: true, succeeded: 1),
            MutationResultStatus.ConfirmedFailure =>
                Create(status, submitted: true, failed: 1),
            MutationResultStatus.SubmittedButUnverified or
                MutationResultStatus.CancellationRequestedAfterSubmission =>
                Create(status, submitted: true, requiresRefresh: true, unknown: 1),
            MutationResultStatus.PartialSuccess =>
                Create(
                    status,
                    submitted: true,
                    requiresRefresh: true,
                    succeeded: 1,
                    failed: 1),
            MutationResultStatus.CancelledBeforeSubmission =>
                Create(status),
            MutationResultStatus.PermissionDenied or MutationResultStatus.Unsupported =>
                Create(status, failed: 1),
            _ => throw new ArgumentOutOfRangeException(nameof(status)),
        };
    }

    private static MutationResult Create(
        MutationResultStatus status,
        bool submitted = false,
        bool requiresRefresh = false,
        int succeeded = 0,
        int failed = 0,
        int unknown = 0)
    {
        return new MutationResult(
            1,
            status,
            "delete",
            submitted,
            requiresRefresh,
            new MutationResultCounts(succeeded, failed, unknown));
    }
}
