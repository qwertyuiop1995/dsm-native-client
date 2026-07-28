using System.Text.Json;
using System.Text.Json.Nodes;
using LanStash.Domain;

namespace LanStash.Infrastructure;

public sealed class DsmRepository(
    NasProfile profile,
    DsmSession session,
    IDsmApiClient api,
    IReadOnlyDictionary<string, ApiCapability> capabilities) : IDsmRepository
{
    private readonly NasProfile _profile = profile;
    private readonly DsmSession _session = session;
    private readonly IDsmApiClient _api = api;
    private readonly IReadOnlyDictionary<string, ApiCapability> _capabilities = capabilities;

    public IReadOnlyList<AppModule> AvailableModules =>
    [
        AppModule.Files,
        AppModule.Photos,
        .. (Supports("SYNO.Chat.Channel")
            ? new[] { AppModule.Chat }
            : Array.Empty<AppModule>()),
        .. (Supports("SYNO.DownloadStation.Task") || Supports("SYNO.DownloadStation2.Task")
            ? new[] { AppModule.Downloads }
            : Array.Empty<AppModule>()),
        .. (Supports("SYNO.Docker.Container")
            ? new[] { AppModule.Containers }
            : Array.Empty<AppModule>()),
        .. (Supports("SYNO.Virtualization.Guest") || Supports("SYNO.Virtualization.API.Guest")
            ? new[] { AppModule.VirtualMachines }
            : Array.Empty<AppModule>()),
        .. (Supports("SYNO.Core.System")
            ? new[] { AppModule.NasSettings }
            : Array.Empty<AppModule>()),
        AppModule.Transfers,
        AppModule.Settings,
    ];

    public async Task<FilePage> ListFilesAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        var method = string.IsNullOrWhiteSpace(path) ? "list_share" : "list";
        var parameters = new Dictionary<string, string>
        {
            ["offset"] = "0",
            ["limit"] = "500",
            ["sort_by"] = "name",
            ["sort_direction"] = "asc",
            ["additional"] = "[\"real_path\",\"size\",\"owner\",\"time\",\"perm\",\"volume_status\"]",
        };
        if (method == "list")
        {
            parameters["folder_path"] = path;
            parameters["filetype"] = "all";
        }
        var data = await CallAsync(
            "SYNO.FileStation.List",
            method,
            parameters,
            cancellationToken).ConfigureAwait(false);
        return ParseFilePage(data, method == "list" ? "files" : "shares");
    }

    public async Task<IReadOnlyList<FileItem>> SearchFilesAsync(
        string path,
        string query,
        CancellationToken cancellationToken = default)
    {
        var start = await CallAsync(
            "SYNO.FileStation.Search",
            "start",
            new Dictionary<string, string>
            {
                ["folder_path"] = string.IsNullOrWhiteSpace(path) ? "/" : path,
                ["pattern"] = query,
                ["recursive"] = "true",
            },
            cancellationToken).ConfigureAwait(false);
        var taskId = start.String("taskid")
            ?? throw new DsmException("NAS 没有开始搜索", "请稍后重试。");
        try
        {
            var result = await CallAsync(
                "SYNO.FileStation.Search",
                "list",
                new Dictionary<string, string>
                {
                    ["taskid"] = taskId,
                    ["offset"] = "0",
                    ["limit"] = "1000",
                    ["additional"] = "[\"size\",\"owner\",\"time\",\"perm\"]",
                },
                cancellationToken).ConfigureAwait(false);
            return ParseFilePage(result, "files").Items;
        }
        finally
        {
            try
            {
                await CallAsync(
                    "SYNO.FileStation.Search",
                    "stop",
                    new Dictionary<string, string> { ["taskid"] = taskId },
                    cancellationToken).ConfigureAwait(false);
            }
            catch (DsmException)
            {
                // 停止失败不覆盖已取得的搜索结果。
            }
        }
    }

    public async Task CreateFolderAsync(
        string parentPath,
        string name,
        CancellationToken cancellationToken = default)
    {
        ValidateName(name);
        await CallAsync(
            "SYNO.FileStation.CreateFolder",
            "create",
            new Dictionary<string, string>
            {
                ["folder_path"] = string.IsNullOrWhiteSpace(parentPath) ? "/" : parentPath,
                ["name"] = name.Trim(),
                ["force_parent"] = "false",
            },
            cancellationToken).ConfigureAwait(false);
        await VerifyFileExistsAsync(parentPath, name.Trim(), cancellationToken).ConfigureAwait(false);
    }

    public async Task RenameAsync(
        string path,
        string newName,
        CancellationToken cancellationToken = default)
    {
        ValidateName(newName);
        await CallAsync(
            "SYNO.FileStation.Rename",
            "rename",
            new Dictionary<string, string>
            {
                ["path"] = path,
                ["name"] = newName.Trim(),
            },
            cancellationToken).ConfigureAwait(false);
        var parent = path.Contains('/') ? path[..path.LastIndexOf('/')] : string.Empty;
        await VerifyFileExistsAsync(parent, newName.Trim(), cancellationToken).ConfigureAwait(false);
    }

    public async Task DeleteFilesAsync(
        IReadOnlyList<string> paths,
        CancellationToken cancellationToken = default)
    {
        if (paths.Count == 0)
        {
            throw new ArgumentException("请先选择要删除的项目。", nameof(paths));
        }
        await CallVoidAsync(
            "SYNO.FileStation.Delete",
            "start",
            new Dictionary<string, string>
            {
                ["path"] = JsonSerializer.Serialize(paths),
                ["recursive"] = "true",
                ["accurate_progress"] = "true",
            },
            cancellationToken).ConfigureAwait(false);
        await WaitUntilAsync(
            async () =>
            {
                foreach (var group in paths.GroupBy(ParentPath))
                {
                    var page = await ListFilesAsync(group.Key, cancellationToken).ConfigureAwait(false);
                    var remaining = page.Items.Select(item => item.Path).ToHashSet(StringComparer.Ordinal);
                    if (group.Any(remaining.Contains))
                    {
                        return false;
                    }
                }
                return true;
            },
            "NAS 尚未确认项目已删除，请刷新后重试。",
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<DownloadTask>> LoadDownloadsAsync(
        CancellationToken cancellationToken = default)
    {
        var apiName = Preferred("SYNO.DownloadStation2.Task", "SYNO.DownloadStation.Task");
        var data = await CallAsync(
            apiName,
            "list",
            new Dictionary<string, string>
            {
                ["offset"] = "0",
                ["limit"] = "1000",
                ["additional"] = "detail,transfer",
            },
            cancellationToken).ConfigureAwait(false);
        return data.Array("tasks").OfType<JsonObject>().Select(item =>
        {
            var transfer = item.Object("additional")?.Object("transfer");
            var detail = item.Object("additional")?.Object("detail");
            return new DownloadTask(
                item.String("id") ?? string.Empty,
                item.String("title") ?? "未命名任务",
                item.String("status") ?? "unknown",
                item.Long("size"),
                item.Long("size_downloaded") ?? transfer?.Long("size_downloaded"),
                transfer?.Long("speed_download"),
                transfer?.Long("speed_upload"),
                detail?.String("destination"),
                detail?.String("error_detail"));
        }).Where(item => !string.IsNullOrWhiteSpace(item.Id)).ToArray();
    }

    public Task CreateDownloadAsync(
        string uri,
        string? destination,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(uri);
        var values = new Dictionary<string, string> { ["uri"] = uri.Trim() };
        if (!string.IsNullOrWhiteSpace(destination))
        {
            values["destination"] = destination;
        }
        return CallVoidAsync(
            Preferred("SYNO.DownloadStation2.Task", "SYNO.DownloadStation.Task"),
            "create",
            values,
            cancellationToken);
    }

    public async Task ControlDownloadsAsync(
        IReadOnlyList<string> ids,
        string action,
        bool removeData = false,
        CancellationToken cancellationToken = default)
    {
        if (action is not ("pause" or "resume" or "delete"))
        {
            throw new ArgumentOutOfRangeException(nameof(action));
        }
        var values = new Dictionary<string, string> { ["id"] = string.Join(',', ids) };
        if (action == "delete")
        {
            values["force_complete"] = removeData.ToString().ToLowerInvariant();
        }
        await CallVoidAsync(
            Preferred("SYNO.DownloadStation2.Task", "SYNO.DownloadStation.Task"),
            action,
            values,
            cancellationToken).ConfigureAwait(false);
        if (action == "delete")
        {
            await WaitUntilAsync(
                async () =>
                {
                    var remaining = await LoadDownloadsAsync(cancellationToken).ConfigureAwait(false);
                    return ids.All(id => remaining.All(item => item.Id != id));
                },
                "NAS 尚未确认下载任务已删除，请刷新后重试。",
                cancellationToken).ConfigureAwait(false);
        }
    }

    public async Task<ContainerSnapshot> LoadContainersAsync(
        CancellationToken cancellationToken = default) =>
        new(
            await LoadResourcesAsync("SYNO.Docker.Container", "containers", cancellationToken)
                .ConfigureAwait(false),
            await LoadResourcesAsync("SYNO.Docker.Image", "images", cancellationToken)
                .ConfigureAwait(false),
            await LoadResourcesAsync("SYNO.Docker.Network", "networks", cancellationToken)
                .ConfigureAwait(false),
            await LoadResourcesAsync("SYNO.Docker.Project", "projects", cancellationToken)
                .ConfigureAwait(false));

    public Task ControlContainerAsync(
        string id,
        string action,
        CancellationToken cancellationToken = default)
    {
        if (action is not ("start" or "stop" or "restart"))
        {
            throw new ArgumentOutOfRangeException(nameof(action));
        }
        return CallVoidAsync(
            "SYNO.Docker.Container",
            action,
            new Dictionary<string, string> { ["id"] = id },
            cancellationToken);
    }

    public Task DeleteContainerAsync(
        string id,
        CancellationToken cancellationToken = default) =>
        DeleteResourceAsync("SYNO.Docker.Container", "containers", id, cancellationToken);

    public Task DeleteContainerImageAsync(
        string id,
        CancellationToken cancellationToken = default) =>
        DeleteResourceAsync("SYNO.Docker.Image", "images", id, cancellationToken);

    public async Task CreateContainerNetworkAsync(
        string name,
        string driver,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        await CallVoidAsync(
            "SYNO.Docker.Network",
            "create",
            new Dictionary<string, string>
            {
                ["name"] = name.Trim(),
                ["driver"] = driver,
            },
            cancellationToken).ConfigureAwait(false);
        await WaitUntilAsync(
            async () =>
            {
                var snapshot = await LoadContainersAsync(cancellationToken).ConfigureAwait(false);
                return snapshot.Networks.Any(item =>
                    string.Equals(item.Name, name.Trim(), StringComparison.OrdinalIgnoreCase));
            },
            "NAS 尚未确认网络已创建，请刷新后重试。",
            cancellationToken).ConfigureAwait(false);
    }

    public async Task DeleteContainerNetworkAsync(
        string id,
        CancellationToken cancellationToken = default)
    {
        await CallVoidAsync(
            "SYNO.Docker.Network",
            "remove",
            new Dictionary<string, string> { ["id"] = id },
            cancellationToken).ConfigureAwait(false);
        await WaitUntilAsync(
            async () =>
            {
                var remaining = await LoadResourcesAsync(
                    "SYNO.Docker.Network",
                    "networks",
                    cancellationToken).ConfigureAwait(false);
                return remaining.All(item => item.Id != id);
            },
            "NAS 尚未确认网络已删除，请刷新后重试。",
            cancellationToken).ConfigureAwait(false);
    }

    public async Task<VirtualMachineSnapshot> LoadVirtualMachinesAsync(
        CancellationToken cancellationToken = default)
    {
        var guestApi = Preferred("SYNO.Virtualization.Guest", "SYNO.Virtualization.API.Guest");
        var hostApi = PreferredOptional("SYNO.Virtualization.Host", "SYNO.Virtualization.API.Host");
        var storageApi = PreferredOptional("SYNO.Virtualization.Repo", "SYNO.Virtualization.API.Storage");
        var networkApi = PreferredOptional("SYNO.Virtualization.Network", "SYNO.Virtualization.API.Network");
        var imageApi = PreferredOptional(
            "SYNO.Virtualization.Guest.Image",
            "SYNO.Virtualization.API.Guest.Image");
        var machines = await LoadResourcesAsync(guestApi, "guests", cancellationToken)
            .ConfigureAwait(false);
        IReadOnlyList<ResourceItem> hosts = hostApi is null
            ? []
            : await TryLoadResourcesAsync(hostApi, "hosts", cancellationToken).ConfigureAwait(false);
        IReadOnlyList<ResourceItem> storages = storageApi is null
            ? []
            : await TryLoadResourcesAsync(storageApi, "repos", cancellationToken).ConfigureAwait(false);
        IReadOnlyList<ResourceItem> networks = networkApi is null
            ? []
            : await TryLoadResourcesAsync(networkApi, "networks", cancellationToken).ConfigureAwait(false);
        IReadOnlyList<ResourceItem> images = imageApi is null
            ? []
            : await TryLoadResourcesAsync(imageApi, "images", cancellationToken).ConfigureAwait(false);
        var protectionData = await TryCallFirstAsync(
            "SYNO.Virtualization.GuestProtect.Plan",
            ["list", "get"],
            cancellationToken).ConfigureAwait(false);
        IReadOnlyList<ResourceItem> protection = protectionData is null
            ? []
            : ParseResources(
                protectionData,
                "plans",
                "plan",
                "protection_plans",
                "guest_protects",
                "data",
                "list");
        IReadOnlyList<ResourceItem> schedules = protectionData is null
            ? []
            : ParseResources(
                protectionData,
                "schedule_policies",
                "schedules",
                "schedule_policy");
        IReadOnlyList<ResourceItem> retentions = protectionData is null
            ? []
            : ParseResources(
                protectionData,
                "retention_policies",
                "retentions",
                "retention_policy");
        var logs = await LoadVirtualizationLogsAsync(cancellationToken).ConfigureAwait(false);
        return new(
            machines,
            hosts,
            storages,
            networks,
            images,
            protection,
            schedules,
            retentions,
            logs);
    }

    public Task ControlVirtualMachineAsync(
        string id,
        string action,
        CancellationToken cancellationToken = default) =>
        CallVoidAsync(
            Preferred(
                "SYNO.Virtualization.Guest.Action",
                "SYNO.Virtualization.API.Guest.Action"),
            action,
            new Dictionary<string, string> { ["guest_id"] = id, ["id"] = id },
            cancellationToken);

    public Task DeleteVirtualMachineAsync(
        string id,
        CancellationToken cancellationToken = default) =>
        DeleteResourceAsync(
            Preferred("SYNO.Virtualization.Guest", "SYNO.Virtualization.API.Guest"),
            "guests",
            id,
            cancellationToken);

    public async Task RenameVirtualMachineNetworkAsync(
        string id,
        string name,
        CancellationToken cancellationToken = default)
    {
        // 内部、实验性契约：已核对的 VMM 网页端使用 set。
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        await CallVoidAsync(
            Preferred("SYNO.Virtualization.Network", "SYNO.Virtualization.API.Network"),
            "set",
            new Dictionary<string, string>
            {
                ["network_id"] = id,
                ["id"] = id,
                ["name"] = name.Trim(),
            },
            cancellationToken).ConfigureAwait(false);
        await WaitUntilAsync(
            async () =>
            {
                var snapshot = await LoadVirtualMachinesAsync(cancellationToken).ConfigureAwait(false);
                return snapshot.Networks.Any(item =>
                    item.Id == id &&
                    string.Equals(item.Name, name.Trim(), StringComparison.Ordinal));
            },
            "NAS 尚未确认网络设置已保存，请刷新后重试。",
            cancellationToken).ConfigureAwait(false);
    }

    public Task DeleteVirtualMachineNetworkAsync(
        string id,
        CancellationToken cancellationToken = default) =>
        DeleteResourceAsync(
            Preferred("SYNO.Virtualization.Network", "SYNO.Virtualization.API.Network"),
            "networks",
            id,
            cancellationToken);

    public Task DeleteVirtualMachineImageAsync(
        string id,
        CancellationToken cancellationToken = default) =>
        DeleteResourceAsync(
            Preferred(
                "SYNO.Virtualization.Guest.Image",
                "SYNO.Virtualization.API.Guest.Image"),
            "images",
            id,
            cancellationToken);

    public async Task<IReadOnlyList<ChatConversation>> LoadConversationsAsync(
        CancellationToken cancellationToken = default)
    {
        var data = await CallFirstAsync(
            "SYNO.Chat.Channel",
            ["list", "get"],
            new Dictionary<string, string> { ["offset"] = "0", ["limit"] = "500" },
            cancellationToken).ConfigureAwait(false);
        return new[] { "channels", "channel_list", "items" }
            .SelectMany(data.Array)
            .OfType<JsonObject>()
            .Select(item => new ChatConversation(
                item.String("channel_id") ?? item.String("id") ?? string.Empty,
                item.String("name") ?? item.String("channel_name") ?? "会话",
                item.Int("unread") ?? item.Int("unread_count") ?? 0,
                item.String("last_post") ?? item.String("last_message"),
                item.Date("last_update_at") ?? item.Date("time")))
            .Where(item => !string.IsNullOrWhiteSpace(item.Id))
            .DistinctBy(item => item.Id)
            .ToArray();
    }

    public async Task<NasSettingsSnapshot> LoadNasSettingsAsync(
        CancellationToken cancellationToken = default)
    {
        var system = await TryCallFirstAsync("SYNO.Core.System", ["info", "get"], cancellationToken)
            .ConfigureAwait(false);
        var storage = await TryCallFirstAsync(
            "SYNO.Storage.CGI.Storage",
            ["load_info", "get"],
            cancellationToken).ConfigureAwait(false);
        var packages = await TryLoadResourcesAsync("SYNO.Core.Package", "packages", cancellationToken)
            .ConfigureAwait(false);
        var users = await TryLoadResourcesAsync("SYNO.Core.User", "users", cancellationToken)
            .ConfigureAwait(false);
        var groups = await TryLoadResourcesAsync("SYNO.Core.Group", "groups", cancellationToken)
            .ConfigureAwait(false);
        var logData = await TryCallFirstAsync(
            PreferredOptional("SYNO.LogCenter.History", "SYNO.Core.SyslogClient.Log"),
            ["list", "get"],
            cancellationToken).ConfigureAwait(false);
        var connections = await TryLoadResourcesAsync(
            "SYNO.Core.CurrentConnection",
            "connections",
            cancellationToken).ConfigureAwait(false);
        var networks = await TryLoadResourcesAsync(
            "SYNO.Core.Network.Ethernet",
            "interfaces",
            cancellationToken).ConfigureAwait(false);
        return new NasSettingsSnapshot(
            system is null ? null : new SystemOverview(
                system.String("server_name") ?? system.String("hostname") ?? "NAS",
                system.String("model"),
                system.String("firmware_ver") ?? system.String("version"),
                system.Long("up_time") ?? system.Long("uptime"),
                system.String("cpu_model"),
                system.Long("ram_size") ?? system.Long("memory_size")),
            storage is null ? [] : ParseResources(storage, "volumes"),
            storage is null ? [] : ParseResources(storage, "storagePools", "pools"),
            storage is null ? [] : ParseResources(storage, "disks"),
            packages,
            users,
            groups,
            logData is null ? [] : ParseLogs(logData),
            connections,
            networks,
            await LoadSecurityAsync(cancellationToken).ConfigureAwait(false));
    }

    private async Task<IReadOnlyList<LogEntry>> LoadVirtualizationLogsAsync(
        CancellationToken cancellationToken)
    {
        if (!Supports("SYNO.Virtualization.Log"))
        {
            return [];
        }
        var data = await CallAsync(
            "SYNO.Virtualization.Log",
            "list",
            new Dictionary<string, string>
            {
                ["offset"] = "0",
                ["limit"] = "1000",
                ["loglevel"] = "",
                ["filter_content"] = "",
                ["datefrom"] = "0",
                ["dateto"] = "0",
                ["sort_by"] = "time",
                ["sort_dir"] = "DESC",
            },
            cancellationToken).ConfigureAwait(false);
        return ParseLogs(data);
    }

    private async Task<IReadOnlyList<ResourceItem>> LoadSecurityAsync(
        CancellationToken cancellationToken)
    {
        var result = new List<ResourceItem>();
        foreach (var (apiName, title) in new[]
        {
            ("SYNO.Core.Security.AutoBlock", "自动封锁"),
            ("SYNO.Core.Security.DoS", "DoS 防护"),
            ("SYNO.Core.Security.Firewall", "防火墙"),
        })
        {
            var data = await TryCallFirstAsync(apiName, ["get", "list"], cancellationToken)
                .ConfigureAwait(false);
            if (data is null)
            {
                continue;
            }
            var enabled = data.Bool("enable") ?? data.Bool("enabled");
            result.Add(new ResourceItem(
                apiName,
                title,
                enabled is false ? "已关闭" : "已开启",
                enabled is false ? ResourceState.Warning : ResourceState.Healthy));
        }
        return result;
    }

    private async Task DeleteResourceAsync(
        string apiName,
        string root,
        string id,
        CancellationToken cancellationToken)
    {
        await CallAsync(
            apiName,
            "delete",
            new Dictionary<string, string>
            {
                ["id"] = id,
                ["guest_id"] = id,
                ["network_id"] = id,
                ["image_id"] = id,
            },
            cancellationToken).ConfigureAwait(false);
        await WaitUntilAsync(
            async () =>
            {
                var remaining = await LoadResourcesAsync(apiName, root, cancellationToken)
                    .ConfigureAwait(false);
                return remaining.All(item => item.Id != id);
            },
            "NAS 尚未确认删除结果，请刷新后检查项目状态。",
            cancellationToken).ConfigureAwait(false);
    }

    private async Task<IReadOnlyList<ResourceItem>> LoadResourcesAsync(
        string apiName,
        string root,
        CancellationToken cancellationToken)
    {
        if (!Supports(apiName))
        {
            return [];
        }
        var data = await CallFirstAsync(
            apiName,
            ["list", "get"],
            parameters: null,
            cancellationToken: cancellationToken).ConfigureAwait(false);
        return ParseResources(data, root, "items");
    }

    private async Task<IReadOnlyList<ResourceItem>> TryLoadResourcesAsync(
        string apiName,
        string root,
        CancellationToken cancellationToken)
    {
        try
        {
            return await LoadResourcesAsync(apiName, root, cancellationToken).ConfigureAwait(false);
        }
        catch (DsmException)
        {
            return [];
        }
    }

    private async Task<JsonObject> CallFirstAsync(
        string apiName,
        IReadOnlyList<string> methods,
        IReadOnlyDictionary<string, string>? parameters,
        CancellationToken cancellationToken)
    {
        DsmException? lastError = null;
        foreach (var method in methods)
        {
            try
            {
                return await CallAsync(apiName, method, parameters, cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (DsmException error) when (error.Code is 102 or 103)
            {
                lastError = error;
            }
        }
        throw lastError ?? new DsmException(
            "当前 NAS 不支持这项功能",
            "请更新相关套件。");
    }

    private async Task<JsonObject?> TryCallFirstAsync(
        string? apiName,
        IReadOnlyList<string> methods,
        CancellationToken cancellationToken)
    {
        if (apiName is null || !Supports(apiName))
        {
            return null;
        }
        try
        {
            return await CallFirstAsync(
                apiName,
                methods,
                parameters: null,
                cancellationToken: cancellationToken).ConfigureAwait(false);
        }
        catch (DsmException)
        {
            return null;
        }
    }

    private Task<JsonObject> CallAsync(
        string apiName,
        string method,
        IReadOnlyDictionary<string, string>? parameters,
        CancellationToken cancellationToken)
    {
        if (!_capabilities.TryGetValue(apiName, out var capability))
        {
            throw new DsmException(
                "当前 NAS 不支持这项功能",
                "请更新 DSM 或相关套件。",
                102);
        }
        return _api.CallAsync(
            _profile,
            _session,
            capability,
            method,
            parameters,
            cancellationToken);
    }

    private async Task CallVoidAsync(
        string apiName,
        string method,
        IReadOnlyDictionary<string, string>? parameters,
        CancellationToken cancellationToken) =>
        _ = await CallAsync(apiName, method, parameters, cancellationToken).ConfigureAwait(false);

    private static async Task WaitUntilAsync(
        Func<Task<bool>> predicate,
        string failureMessage,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 8; attempt++)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (await predicate().ConfigureAwait(false))
            {
                return;
            }
            await Task.Delay(TimeSpan.FromMilliseconds(500), cancellationToken).ConfigureAwait(false);
        }
        throw new DsmException(
            failureMessage,
            "请刷新列表；如果项目仍存在，请确认没有其他任务正在使用它。");
    }

    private static string ParentPath(string path)
    {
        var index = path.LastIndexOf('/');
        return index > 0 ? path[..index] : string.Empty;
    }

    private async Task VerifyFileExistsAsync(
        string parent,
        string name,
        CancellationToken cancellationToken)
    {
        var page = await ListFilesAsync(
            string.IsNullOrWhiteSpace(parent) ? "/" : parent,
            cancellationToken).ConfigureAwait(false);
        if (!page.Items.Any(item => string.Equals(item.Name, name, StringComparison.Ordinal)))
        {
            throw new DsmException(
                "NAS 没有确认这次更改",
                "请刷新列表并检查结果。");
        }
    }

    private FilePage ParseFilePage(JsonObject data, string root)
    {
        var items = data.Array(root).OfType<JsonObject>().Select(item =>
        {
            var additional = item.Object("additional");
            var time = additional?.Object("time");
            var permission = additional?.Object("perm");
            return new FileItem(
                item.String("path") ?? string.Empty,
                item.String("name") ?? item.String("path")?.Split('/').Last() ?? "项目",
                item.Bool("isdir") ?? false,
                item.Long("size") ?? additional?.Long("size") ?? 0,
                time?.Date("mtime") ?? item.Date("mtime"),
                additional?.Object("owner")?.String("user") ?? additional?.String("owner"),
                permission?.Bool("write") ?? false,
                permission?.Bool("delete") ?? false);
        }).Where(item => !string.IsNullOrWhiteSpace(item.Path)).ToArray();
        return new FilePage(
            items,
            data.Int("total") ?? items.Length,
            data.Int("offset") ?? 0);
    }

    private static IReadOnlyList<ResourceItem> ParseResources(
        JsonObject data,
        params string[] roots)
    {
        var nodes = roots.SelectMany(data.Array).OfType<JsonObject>();
        return nodes.Select((item, index) =>
        {
            var id = item.String("id")
                ?? item.String("uuid")
                ?? item.String("name")
                ?? $"item-{index}";
            var name = item.String("name")
                ?? item.String("title")
                ?? item.String("guest_name")
                ?? item.String("repo")
                ?? id;
            var status = item.String("status") ?? item.String("state") ?? item.String("health");
            var metadata = item
                .Where(pair => pair.Value is JsonValue)
                .ToDictionary(
                    pair => pair.Key,
                    pair => pair.Value?.ToJsonString().Trim('"') ?? string.Empty,
                    StringComparer.Ordinal);
            return new ResourceItem(
                id,
                name,
                status ?? item.String("description") ?? string.Empty,
                ParseState(status),
                metadata);
        }).DistinctBy(item => item.Id).ToArray();
    }

    private static IReadOnlyList<LogEntry> ParseLogs(JsonObject data) =>
        new[] { "logs", "log", "events", "records", "entries", "items", "data", "list" }
            .SelectMany(data.Array)
            .OfType<JsonObject>()
            .Select((item, index) => new LogEntry(
                item.String("id") ?? item.String("log_id") ?? $"log-{index}",
                item.String("level")
                    ?? item.String("severity")
                    ?? item.String("type")
                    ?? item.String("priority")
                    ?? "unknown",
                item.Date("time")
                    ?? item.Date("timestamp")
                    ?? item.Date("date")
                    ?? item.Date("event_time")
                    ?? item.Date("create_time")
                    ?? item.Date("created_at"),
                item.String("user")
                    ?? item.String("username")
                    ?? item.String("owner")
                    ?? item.String("account")
                    ?? item.String("user_name")
                    ?? "SYSTEM",
                item.String("event")
                    ?? item.String("message")
                    ?? item.String("description")
                    ?? item.String("msg")
                    ?? item.String("content")
                    ?? item.String("detail")
                    ?? string.Empty))
            .Where(item => !string.IsNullOrWhiteSpace(item.Event))
            .DistinctBy(item => item.Id)
            .ToArray();

    private static ResourceState ParseState(string? value)
    {
        var state = value?.ToLowerInvariant() ?? string.Empty;
        if (state is "running" or "started" or "online" or "active" or "downloading" or "seeding")
        {
            return ResourceState.Running;
        }
        if (state is "stopped" or "shutdown" or "offline" or "inactive" or "finished")
        {
            return ResourceState.Stopped;
        }
        if (state is "paused" or "suspended")
        {
            return ResourceState.Paused;
        }
        if (state is "waiting" or "pending" or "creating" or "starting" or "stopping")
        {
            return ResourceState.Waiting;
        }
        if (state is "healthy" or "normal" or "good")
        {
            return ResourceState.Healthy;
        }
        if (state.Contains("warn", StringComparison.Ordinal) ||
            state.Contains("degrad", StringComparison.Ordinal))
        {
            return ResourceState.Warning;
        }
        if (state.Contains("error", StringComparison.Ordinal) ||
            state.Contains("fail", StringComparison.Ordinal) ||
            state.Contains("critical", StringComparison.Ordinal))
        {
            return ResourceState.Error;
        }
        return ResourceState.Unknown;
    }

    private static void ValidateName(string name)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        if (name.Contains('/'))
        {
            throw new ArgumentException("名称不能包含路径分隔符。", nameof(name));
        }
    }

    private bool Supports(string apiName) => _capabilities.ContainsKey(apiName);

    private string Preferred(params string[] names) =>
        names.FirstOrDefault(Supports)
        ?? throw new DsmException(
            "当前 NAS 不支持这项功能",
            "请更新 DSM 或相关套件。",
            102);

    private string? PreferredOptional(params string[] names) => names.FirstOrDefault(Supports);
}

internal static class JsonExtensions
{
    public static string? String(this JsonObject value, string key) =>
        value[key] is JsonValue node && node.TryGetValue<string>(out var result) ? result : null;

    public static int? Int(this JsonObject value, string key) =>
        value[key] is JsonValue node && node.TryGetValue<int>(out var result) ? result : null;

    public static long? Long(this JsonObject value, string key) =>
        value[key] is JsonValue node && node.TryGetValue<long>(out var result) ? result : null;

    public static bool? Bool(this JsonObject value, string key) =>
        value[key] is JsonValue node && node.TryGetValue<bool>(out var result) ? result : null;

    public static DateTimeOffset? Date(this JsonObject value, string key)
    {
        var epoch = value.Long(key);
        if (epoch is not null)
        {
            return epoch > 10_000_000_000
                ? DateTimeOffset.FromUnixTimeMilliseconds(epoch.Value)
                : DateTimeOffset.FromUnixTimeSeconds(epoch.Value);
        }
        var text = value.String(key);
        return DateTimeOffset.TryParse(text, out var result) ? result : null;
    }

    public static JsonObject? Object(this JsonObject value, string key) =>
        value[key] as JsonObject;

    public static IEnumerable<JsonNode?> Array(this JsonObject value, string key) =>
        value[key] as JsonArray ?? [];
}
