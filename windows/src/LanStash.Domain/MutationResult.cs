using System.Text.Json;
using System.Text.Json.Serialization;

namespace LanStash.Domain;

[JsonConverter(typeof(MutationResultStatusJsonConverter))]
public enum MutationResultStatus
{
    ConfirmedSuccess,
    ConfirmedFailure,
    SubmittedButUnverified,
    PartialSuccess,
    CancelledBeforeSubmission,
    CancellationRequestedAfterSubmission,
    PermissionDenied,
    Unsupported,
}

[JsonConverter(typeof(MutationErrorCategoryJsonConverter))]
public enum MutationErrorCategory
{
    Validation,
    Authentication,
    Permission,
    Conflict,
    Network,
    Server,
    Unsupported,
    Unknown,
}

public sealed class MutationResultStatusJsonConverter()
    : JsonStringEnumConverter<MutationResultStatus>(
        JsonNamingPolicy.CamelCase,
        allowIntegerValues: false);

public sealed class MutationErrorCategoryJsonConverter()
    : JsonStringEnumConverter<MutationErrorCategory>(
        JsonNamingPolicy.CamelCase,
        allowIntegerValues: false);

public sealed record MutationResultCounts
{
    [JsonPropertyName("succeeded")]
    public int Succeeded { get; }

    [JsonPropertyName("failed")]
    public int Failed { get; }

    [JsonPropertyName("unknown")]
    public int Unknown { get; }

    [JsonConstructor]
    public MutationResultCounts(int succeeded, int failed, int unknown)
    {
        if (succeeded < 0 || failed < 0 || unknown < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(succeeded), "mutation.invalid_count");
        }
        Succeeded = succeeded;
        Failed = failed;
        Unknown = unknown;
    }
}

public sealed record MutationResult
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; }

    [JsonPropertyName("status")]
    public MutationResultStatus Status { get; }

    [JsonPropertyName("operation")]
    public string Operation { get; }

    [JsonPropertyName("submitted")]
    public bool Submitted { get; }

    [JsonPropertyName("requiresRefresh")]
    public bool RequiresRefresh { get; }

    [JsonPropertyName("counts")]
    public MutationResultCounts Counts { get; }

    [JsonPropertyName("errorCategory")]
    public MutationErrorCategory? ErrorCategory { get; }

    [JsonPropertyName("localizationKey")]
    public string? LocalizationKey { get; }

    [JsonPropertyName("diagnosticTag")]
    public string? DiagnosticTag { get; }

    [JsonConstructor]
    public MutationResult(
        int schemaVersion,
        MutationResultStatus status,
        string operation,
        bool submitted,
        bool requiresRefresh,
        MutationResultCounts counts,
        MutationErrorCategory? errorCategory = null,
        string? localizationKey = null,
        string? diagnosticTag = null)
    {
        if (schemaVersion != 1)
        {
            throw new ArgumentOutOfRangeException(
                nameof(schemaVersion),
                "mutation.unsupported_schema");
        }
        if (!IsValidOperation(operation))
        {
            throw new ArgumentException("mutation.invalid_operation", nameof(operation));
        }
        if (!IsValidSafeTag(localizationKey) || !IsValidSafeTag(diagnosticTag))
        {
            throw new ArgumentException("mutation.invalid_safe_tag");
        }
        ValidateState(status, submitted, requiresRefresh, counts);

        SchemaVersion = schemaVersion;
        Status = status;
        Operation = operation;
        Submitted = submitted;
        RequiresRefresh = requiresRefresh;
        Counts = counts;
        ErrorCategory = errorCategory;
        LocalizationKey = localizationKey;
        DiagnosticTag = diagnosticTag;
    }

    private static void ValidateState(
        MutationResultStatus status,
        bool submitted,
        bool requiresRefresh,
        MutationResultCounts counts)
    {
        var valid = status switch
        {
            MutationResultStatus.ConfirmedSuccess =>
                submitted && counts.Failed == 0 && counts.Unknown == 0,
            MutationResultStatus.CancelledBeforeSubmission =>
                !submitted &&
                !requiresRefresh &&
                counts.Succeeded == 0 &&
                counts.Failed == 0 &&
                counts.Unknown == 0,
            MutationResultStatus.SubmittedButUnverified or
                MutationResultStatus.CancellationRequestedAfterSubmission =>
                submitted && requiresRefresh,
            MutationResultStatus.PartialSuccess =>
                submitted &&
                counts.Succeeded > 0 &&
                counts.Failed + counts.Unknown > 0,
            _ => true,
        };
        if (!valid)
        {
            throw new ArgumentException("mutation.inconsistent_state");
        }
    }

    private static bool IsValidOperation(string? value)
    {
        return !string.IsNullOrEmpty(value) &&
            value[0] is >= 'a' and <= 'z' &&
            value.All(character =>
                character is >= 'a' and <= 'z' or
                    >= 'A' and <= 'Z' or
                    >= '0' and <= '9');
    }

    private static bool IsValidSafeTag(string? value)
    {
        return value is null ||
            (
                value.Length > 0 &&
                value.All(character =>
                    character is >= 'a' and <= 'z' or
                        >= '0' and <= '9' or
                        '.' or
                        '_' or
                        '-')
            );
    }
}
