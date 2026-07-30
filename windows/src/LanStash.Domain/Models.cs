namespace LanStash.Domain;

public sealed record NasProfile(
    Guid Id,
    string DisplayName,
    string Host,
    int? Port,
    string Username,
    bool RememberSession = true,
    bool AutoLogin = false);

public sealed record DsmSession(
    Guid ProfileId,
    string Sid,
    string? SynoToken,
    string? DeviceId);

public sealed record ApiCapability(
    string Name,
    string Path,
    int MinVersion,
    int MaxVersion,
    string RequestFormat)
{
    public int SelectVersion(int preferred) => Math.Clamp(preferred, MinVersion, MaxVersion);
}

public enum DsmErrorKind
{
    Unknown,
    InvalidAddress,
    InsecureAddress,
    InvalidQuickConnectId,
    QuickConnectNotFound,
    QuickConnectOffline,
    QuickConnectDirectUnavailable,
    QuickConnectServiceUnavailable,
    QuickConnectInvalidResponse,
    QuickConnectRelayDisabled,
    QuickConnectRelayUnavailable,
    QuickConnectIdentityMismatch,
}

public static class UserText
{
    public const string ResourcePrefix = "loc:";

    public static string Key(string resourceKey) => $"{ResourcePrefix}{resourceKey}";
}

public sealed class DsmException(
    string message,
    string recovery,
    int? code = null,
    bool authenticationFailure = false,
    DsmErrorKind kind = DsmErrorKind.Unknown) : Exception(message)
{
    public string Recovery { get; } = recovery;
    public int? Code { get; } = code;
    public bool AuthenticationFailure { get; } = authenticationFailure;
    public DsmErrorKind Kind { get; } = kind;
}

public enum AppModule
{
    Files,
    Photos,
    Chat,
    Downloads,
    Containers,
    VirtualMachines,
    NasSettings,
    Transfers,
    Settings,
}

public enum AppLanguageSelection
{
    System,
    English,
    SimplifiedChinese,
}

public static class AppLanguageResolver
{
    public static string Resolve(
        AppLanguageSelection selection,
        string? primaryPreferredLanguage)
    {
        return selection switch
        {
            AppLanguageSelection.English => "en-US",
            AppLanguageSelection.SimplifiedChinese => "zh-CN",
            _ => ResolveSystemLanguage(primaryPreferredLanguage),
        };
    }

    public static string ResolveSystemLanguage(string? identifier)
    {
        if (string.IsNullOrWhiteSpace(identifier))
        {
            return "en-US";
        }
        var parts = identifier.Replace('_', '-')
            .Split('-', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (parts.Length == 0)
        {
            return "en-US";
        }
        if (string.Equals(parts[0], "en", StringComparison.OrdinalIgnoreCase))
        {
            return "en-US";
        }
        if (!string.Equals(parts[0], "zh", StringComparison.OrdinalIgnoreCase))
        {
            return "en-US";
        }
        if (parts.Any(part =>
                part.Equals("Hant", StringComparison.OrdinalIgnoreCase) ||
                part.Equals("TW", StringComparison.OrdinalIgnoreCase) ||
                part.Equals("HK", StringComparison.OrdinalIgnoreCase) ||
                part.Equals("MO", StringComparison.OrdinalIgnoreCase)))
        {
            return "en-US";
        }
        return parts.Any(part =>
                part.Equals("Hans", StringComparison.OrdinalIgnoreCase) ||
                part.Equals("CN", StringComparison.OrdinalIgnoreCase) ||
                part.Equals("SG", StringComparison.OrdinalIgnoreCase))
            ? "zh-CN"
            : "en-US";
    }
}

public static class AppModuleExtensions
{
    public static string Glyph(this AppModule module) => module switch
    {
        AppModule.Files => "\uE8B7",
        AppModule.Photos => "\uEB9F",
        AppModule.Chat => "\uE8BD",
        AppModule.Downloads => "\uE896",
        AppModule.Containers => "\uE7B8",
        AppModule.VirtualMachines => "\uE7F4",
        AppModule.NasSettings => "\uEDA2",
        AppModule.Transfers => "\uE898",
        AppModule.Settings => "\uE713",
        _ => "\uE946",
    };
}

public enum ResourceState
{
    Running,
    Stopped,
    Paused,
    Waiting,
    Healthy,
    Warning,
    Error,
    Unknown,
}

public sealed record FileItem(
    string Path,
    string Name,
    bool IsDirectory,
    long Size,
    DateTimeOffset? ModifiedAt,
    string? Owner,
    bool CanWrite,
    bool CanDelete);

public sealed record FilePage(
    IReadOnlyList<FileItem> Items,
    int Total,
    int Offset);

public sealed record ResourceItem(
    string Id,
    string Name,
    string Detail,
    ResourceState State,
    IReadOnlyDictionary<string, string>? Metadata = null);

public sealed record DownloadTask(
    string Id,
    string Title,
    string Status,
    long? Size,
    long? Downloaded,
    long? DownloadSpeed,
    long? UploadSpeed,
    string? Destination,
    string? Error)
{
    public double? Progress =>
        Size is > 0 && Downloaded is not null
            ? Math.Clamp((double)Downloaded.Value / Size.Value, 0, 1)
            : null;
}

public sealed record LogEntry(
    string Id,
    string Level,
    DateTimeOffset? Time,
    string User,
    string Event);

public sealed record ContainerSnapshot(
    IReadOnlyList<ResourceItem> Containers,
    IReadOnlyList<ResourceItem> Images,
    IReadOnlyList<ResourceItem> Networks,
    IReadOnlyList<ResourceItem> Projects);

public sealed record VirtualMachineSnapshot(
    IReadOnlyList<ResourceItem> Machines,
    IReadOnlyList<ResourceItem> Hosts,
    IReadOnlyList<ResourceItem> Storages,
    IReadOnlyList<ResourceItem> Networks,
    IReadOnlyList<ResourceItem> Images,
    IReadOnlyList<ResourceItem> ProtectionPlans,
    IReadOnlyList<ResourceItem> ProtectionSchedules,
    IReadOnlyList<ResourceItem> RetentionPolicies,
    IReadOnlyList<LogEntry> Logs);

public sealed record ChatConversation(
    string Id,
    string Title,
    int UnreadCount,
    string? LatestMessage,
    DateTimeOffset? LatestAt);

public sealed record SystemOverview(
    string ServerName,
    string? Model,
    string? Version,
    long? UptimeSeconds,
    string? CpuModel,
    long? MemoryBytes);

public sealed record NasSettingsSnapshot(
    SystemOverview? System,
    IReadOnlyList<ResourceItem> Volumes,
    IReadOnlyList<ResourceItem> Pools,
    IReadOnlyList<ResourceItem> Disks,
    IReadOnlyList<ResourceItem> Packages,
    IReadOnlyList<ResourceItem> Accounts,
    IReadOnlyList<ResourceItem> Groups,
    IReadOnlyList<LogEntry> Logs,
    IReadOnlyList<ResourceItem> Connections,
    IReadOnlyList<ResourceItem> Networks,
    IReadOnlyList<ResourceItem> Security);

public interface ISecureSessionStore
{
    Task SaveAsync(DsmSession session, CancellationToken cancellationToken = default);
    Task<DsmSession?> LoadAsync(Guid profileId, CancellationToken cancellationToken = default);
    Task RemoveAsync(Guid profileId, CancellationToken cancellationToken = default);
}

public interface ISecurePasswordStore
{
    Task SaveAsync(Guid profileId, string password, CancellationToken cancellationToken = default);
    Task<string?> LoadAsync(Guid profileId, CancellationToken cancellationToken = default);
    Task RemoveAsync(Guid profileId, CancellationToken cancellationToken = default);
}

public interface IDsmApiClient
{
    Uri GetBaseUri(NasProfile profile);
    Task<IReadOnlyDictionary<string, ApiCapability>> DiscoverAsync(
        NasProfile profile,
        CancellationToken cancellationToken = default);
    Task<DsmSession> LoginAsync(
        NasProfile profile,
        string password,
        string? otp,
        CancellationToken cancellationToken = default);
    Task LogoutAsync(
        NasProfile profile,
        DsmSession session,
        CancellationToken cancellationToken = default);
    Task<System.Text.Json.Nodes.JsonObject> CallAsync(
        NasProfile profile,
        DsmSession session,
        ApiCapability capability,
        string method,
        IReadOnlyDictionary<string, string>? parameters = null,
        CancellationToken cancellationToken = default);
    Task<byte[]> ReadFileRangeAsync(
        NasProfile profile,
        DsmSession session,
        ApiCapability capability,
        string remotePath,
        long offset,
        long length,
        CancellationToken cancellationToken = default);
}

public interface IDsmRepository
{
    IReadOnlyList<AppModule> AvailableModules { get; }
    Task<FilePage> ListFilesAsync(
        string path,
        CancellationToken cancellationToken = default);
    Task<FilePage> ListFilesAsync(
        string path,
        int offset,
        int limit,
        CancellationToken cancellationToken = default);
    Task<byte[]> ReadFileRangeAsync(
        string remotePath,
        long offset,
        long length,
        CancellationToken cancellationToken = default);
    Task<IReadOnlyList<FileItem>> SearchFilesAsync(
        string path,
        string query,
        CancellationToken cancellationToken = default);
    Task CreateFolderAsync(
        string parentPath,
        string name,
        CancellationToken cancellationToken = default);
    Task RenameAsync(
        string path,
        string newName,
        CancellationToken cancellationToken = default);
    Task DeleteFilesAsync(
        IReadOnlyList<string> paths,
        CancellationToken cancellationToken = default);
    Task<IReadOnlyList<DownloadTask>> LoadDownloadsAsync(
        CancellationToken cancellationToken = default);
    Task CreateDownloadAsync(
        string uri,
        string? destination,
        CancellationToken cancellationToken = default);
    Task ControlDownloadsAsync(
        IReadOnlyList<string> ids,
        string action,
        bool removeData = false,
        CancellationToken cancellationToken = default);
    Task<ContainerSnapshot> LoadContainersAsync(
        CancellationToken cancellationToken = default);
    Task ControlContainerAsync(
        string id,
        string action,
        CancellationToken cancellationToken = default);
    Task DeleteContainerAsync(
        string id,
        CancellationToken cancellationToken = default);
    Task DeleteContainerImageAsync(
        string id,
        CancellationToken cancellationToken = default);
    Task CreateContainerNetworkAsync(
        string name,
        string driver,
        CancellationToken cancellationToken = default);
    Task DeleteContainerNetworkAsync(
        string id,
        CancellationToken cancellationToken = default);
    Task<VirtualMachineSnapshot> LoadVirtualMachinesAsync(
        CancellationToken cancellationToken = default);
    Task ControlVirtualMachineAsync(
        string id,
        string action,
        CancellationToken cancellationToken = default);
    Task DeleteVirtualMachineAsync(
        string id,
        CancellationToken cancellationToken = default);
    Task RenameVirtualMachineNetworkAsync(
        string id,
        string name,
        CancellationToken cancellationToken = default);
    Task DeleteVirtualMachineNetworkAsync(
        string id,
        CancellationToken cancellationToken = default);
    Task DeleteVirtualMachineImageAsync(
        string id,
        CancellationToken cancellationToken = default);
    Task<IReadOnlyList<ChatConversation>> LoadConversationsAsync(
        CancellationToken cancellationToken = default);
    Task<NasSettingsSnapshot> LoadNasSettingsAsync(
        CancellationToken cancellationToken = default);
}
