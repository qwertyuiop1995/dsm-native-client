using System.Collections.ObjectModel;
using LanStash.Domain;

namespace LanStash.App.ViewModels;

public sealed class WorkspaceViewModel(AppViewModel app) : ObservableObject
{
    private readonly SemaphoreSlim _mutationGate = new(1, 1);
    private AppModule _module = AppModule.Files;
    private string _selectedCategory = string.Empty;
    private string _currentPath = string.Empty;
    private bool _isLoading;
    private string? _message;
    private WorkspaceRow? _selectedItem;

    public ObservableCollection<string> Categories { get; } = [];
    public ObservableCollection<WorkspaceRow> Items { get; } = [];

    public AppModule Module
    {
        get => _module;
        private set
        {
            if (SetProperty(ref _module, value))
            {
                RaisePropertyChanged(nameof(Title));
                RaisePropertyChanged(nameof(CanCreate));
                RaisePropertyChanged(nameof(CanRename));
                RaisePropertyChanged(nameof(CanControl));
                RaisePropertyChanged(nameof(CanDelete));
            }
        }
    }

    public string Title => Module.Title();

    public string SelectedCategory
    {
        get => _selectedCategory;
        set
        {
            if (SetProperty(ref _selectedCategory, value) && !string.IsNullOrWhiteSpace(value))
            {
                _ = ReloadAsync();
                RaiseCommandState();
            }
        }
    }

    public string CurrentPath
    {
        get => _currentPath;
        private set => SetProperty(ref _currentPath, value);
    }

    public bool IsLoading
    {
        get => _isLoading;
        private set => SetProperty(ref _isLoading, value);
    }

    public string? Message
    {
        get => _message;
        private set
        {
            SetProperty(ref _message, value);
            RaisePropertyChanged(nameof(HasMessage));
        }
    }

    public bool HasMessage => !string.IsNullOrWhiteSpace(Message);

    public WorkspaceRow? SelectedItem
    {
        get => _selectedItem;
        set
        {
            if (SetProperty(ref _selectedItem, value))
            {
                RaiseCommandState();
            }
        }
    }

    public bool CanCreate =>
        Module is AppModule.Files or AppModule.Downloads ||
        Module == AppModule.Containers && SelectedCategory == "网络";

    public bool CanRename =>
        SelectedItem is not null &&
        (Module == AppModule.Files ||
         Module == AppModule.VirtualMachines && SelectedCategory == "网络");

    public bool CanControl =>
        SelectedItem is not null &&
        (Module is AppModule.Downloads or AppModule.Containers or AppModule.VirtualMachines) &&
        SelectedCategory is not ("映像" or "网络" or "保护" or "日志");

    public bool CanDelete =>
        SelectedItem is not null &&
        (Module == AppModule.Files ||
         Module == AppModule.Downloads ||
         Module == AppModule.Containers && (SelectedCategory is "容器" or "映像" or "网络") ||
         Module == AppModule.VirtualMachines && (SelectedCategory is "虚拟机" or "网络" or "映像"));

    public async Task ShowModuleAsync(AppModule module)
    {
        Module = module;
        CurrentPath = string.Empty;
        SelectedItem = null;
        Categories.Clear();
        foreach (var category in CategoriesFor(module))
        {
            Categories.Add(category);
        }
        _selectedCategory = Categories.FirstOrDefault() ?? string.Empty;
        RaisePropertyChanged(nameof(SelectedCategory));
        RaiseCommandState();
        await ReloadAsync();
    }

    public async Task ReloadAsync(string? search = null)
    {
        var repository = app.Repository;
        if (repository is null || IsLoading)
        {
            return;
        }
        IsLoading = true;
        Message = null;
        SelectedItem = null;
        try
        {
            var rows = await LoadRowsAsync(repository, search);
            Items.Clear();
            foreach (var row in rows)
            {
                Items.Add(row);
            }
            if (Items.Count == 0)
            {
                Message = "没有可显示的项目。";
            }
        }
        catch (DsmException error)
        {
            Message = $"{error.Message} {error.Recovery}";
        }
        catch
        {
            Message = "暂时无法读取，请检查连接后重试。";
        }
        finally
        {
            IsLoading = false;
        }
    }

    public async Task OpenSelectedAsync()
    {
        if (Module != AppModule.Files || SelectedItem?.Payload is not FileItem file || !file.IsDirectory)
        {
            return;
        }
        CurrentPath = file.Path;
        await ReloadAsync();
    }

    public async Task GoUpAsync()
    {
        if (Module != AppModule.Files || string.IsNullOrWhiteSpace(CurrentPath))
        {
            return;
        }
        var index = CurrentPath.LastIndexOf('/');
        CurrentPath = index > 0 ? CurrentPath[..index] : string.Empty;
        await ReloadAsync();
    }

    public async Task CreateAsync(string value, string? secondary = null)
    {
        await MutateAsync(async repository =>
        {
            switch (Module)
            {
                case AppModule.Files:
                    await repository.CreateFolderAsync(CurrentPath, value);
                    break;
                case AppModule.Downloads:
                    await repository.CreateDownloadAsync(
                        value,
                        string.IsNullOrWhiteSpace(secondary) ? null : secondary);
                    break;
                case AppModule.Containers when SelectedCategory == "网络":
                    await repository.CreateContainerNetworkAsync(value, secondary ?? "bridge");
                    break;
            }
        });
    }

    public async Task RenameSelectedAsync(string name)
    {
        await MutateAsync(async repository =>
        {
            if (SelectedItem?.Payload is FileItem file)
            {
                await repository.RenameAsync(file.Path, name);
            }
            else if (Module == AppModule.VirtualMachines &&
                     SelectedCategory == "网络" &&
                     SelectedItem is not null)
            {
                await repository.RenameVirtualMachineNetworkAsync(SelectedItem.Id, name);
            }
        });
    }

    public async Task ControlSelectedAsync(string action)
    {
        if (SelectedItem is null)
        {
            return;
        }
        await MutateAsync(async repository =>
        {
            if (Module == AppModule.Downloads)
            {
                await repository.ControlDownloadsAsync([SelectedItem.Id], action);
            }
            else if (Module == AppModule.Containers)
            {
                await repository.ControlContainerAsync(SelectedItem.Id, action);
            }
            else if (Module == AppModule.VirtualMachines)
            {
                await repository.ControlVirtualMachineAsync(SelectedItem.Id, action);
            }
        });
    }

    public async Task DeleteSelectedAsync(bool removeData = false)
    {
        if (SelectedItem is null)
        {
            return;
        }
        await MutateAsync(async repository =>
        {
            switch (Module)
            {
                case AppModule.Files when SelectedItem.Payload is FileItem file:
                    await repository.DeleteFilesAsync([file.Path]);
                    break;
                case AppModule.Downloads:
                    await repository.ControlDownloadsAsync([SelectedItem.Id], "delete", removeData);
                    break;
                case AppModule.Containers when SelectedCategory == "容器":
                    await repository.DeleteContainerAsync(SelectedItem.Id);
                    break;
                case AppModule.Containers when SelectedCategory == "映像":
                    await repository.DeleteContainerImageAsync(SelectedItem.Id);
                    break;
                case AppModule.Containers when SelectedCategory == "网络":
                    await repository.DeleteContainerNetworkAsync(SelectedItem.Id);
                    break;
                case AppModule.VirtualMachines when SelectedCategory == "虚拟机":
                    await repository.DeleteVirtualMachineAsync(SelectedItem.Id);
                    break;
                case AppModule.VirtualMachines when SelectedCategory == "网络":
                    await repository.DeleteVirtualMachineNetworkAsync(SelectedItem.Id);
                    break;
                case AppModule.VirtualMachines when SelectedCategory == "映像":
                    await repository.DeleteVirtualMachineImageAsync(SelectedItem.Id);
                    break;
            }
        });
    }

    private async Task<IReadOnlyList<WorkspaceRow>> LoadRowsAsync(
        IDsmRepository repository,
        string? search)
    {
        IEnumerable<WorkspaceRow> rows = Module switch
        {
            AppModule.Files => await LoadFilesAsync(repository, search),
            AppModule.Photos => (await repository.ListFilesAsync("/photo")).Items
                .Where(item => !item.IsDirectory)
                .Select(FileRow),
            AppModule.Chat => (await repository.LoadConversationsAsync()).Select(item =>
                new WorkspaceRow(
                    item.Id,
                    item.Title,
                    item.LatestMessage ?? "暂无新消息",
                    item.UnreadCount > 0 ? $"{item.UnreadCount} 条未读" : string.Empty,
                    "\uE8BD",
                    item)),
            AppModule.Downloads => (await repository.LoadDownloadsAsync()).Select(item =>
                new WorkspaceRow(
                    item.Id,
                    item.Title,
                    item.Destination ?? "下载任务",
                    item.Progress is null ? StatusText(item.Status) : $"{item.Progress:P0}",
                    "\uE896",
                    item)),
            AppModule.Containers => RowsForContainer(await repository.LoadContainersAsync()),
            AppModule.VirtualMachines => RowsForVirtualMachines(await repository.LoadVirtualMachinesAsync()),
            AppModule.NasSettings => RowsForNasSettings(await repository.LoadNasSettingsAsync()),
            AppModule.Transfers => [],
            AppModule.Settings => app.ActiveProfile is null
                ? []
                : [new WorkspaceRow(
                    app.ActiveProfile.Id.ToString(),
                    app.ActiveProfile.DisplayName,
                    app.ActiveProfile.Host,
                    "已连接",
                    "\uEDA2",
                    app.ActiveProfile)],
            _ => [],
        };
        if (!string.IsNullOrWhiteSpace(search) && Module != AppModule.Files)
        {
            rows = rows.Where(item =>
                item.Title.Contains(search, StringComparison.CurrentCultureIgnoreCase) ||
                item.Detail.Contains(search, StringComparison.CurrentCultureIgnoreCase));
        }
        return rows.ToArray();
    }

    private async Task<IReadOnlyList<WorkspaceRow>> LoadFilesAsync(
        IDsmRepository repository,
        string? search)
    {
        var items = string.IsNullOrWhiteSpace(search)
            ? (await repository.ListFilesAsync(CurrentPath)).Items
            : await repository.SearchFilesAsync(CurrentPath, search);
        return items.Select(FileRow).ToArray();
    }

    private IEnumerable<WorkspaceRow> RowsForContainer(ContainerSnapshot snapshot) =>
        SelectedCategory switch
        {
            "映像" => snapshot.Images.Select(ResourceRow),
            "网络" => snapshot.Networks.Select(ResourceRow),
            "项目" => snapshot.Projects.Select(ResourceRow),
            _ => snapshot.Containers.Select(ResourceRow),
        };

    private IEnumerable<WorkspaceRow> RowsForVirtualMachines(VirtualMachineSnapshot snapshot) =>
        SelectedCategory switch
        {
            "主机" => snapshot.Hosts.Select(ResourceRow),
            "存储" => snapshot.Storages.Select(ResourceRow),
            "网络" => snapshot.Networks.Select(ResourceRow),
            "映像" => snapshot.Images.Select(ResourceRow),
            "保护" => snapshot.ProtectionPlans
                .Concat(snapshot.ProtectionSchedules)
                .Concat(snapshot.RetentionPolicies)
                .DistinctBy(item => item.Id)
                .Select(ResourceRow),
            "日志" => snapshot.Logs.Select(LogRow),
            _ => snapshot.Machines.Select(ResourceRow),
        };

    private IEnumerable<WorkspaceRow> RowsForNasSettings(NasSettingsSnapshot snapshot) =>
        SelectedCategory switch
        {
            "存储" => snapshot.Volumes.Concat(snapshot.Pools).Concat(snapshot.Disks).Select(ResourceRow),
            "套件" => snapshot.Packages.Select(ResourceRow),
            "账号" => snapshot.Accounts.Concat(snapshot.Groups).Select(ResourceRow),
            "日志" => snapshot.Logs.Select(LogRow),
            "连接" => snapshot.Connections.Select(ResourceRow),
            "网络" => snapshot.Networks.Select(ResourceRow),
            "安全" => snapshot.Security.Select(ResourceRow),
            _ => snapshot.System is null
                ? []
                : [new WorkspaceRow(
                    "system",
                    snapshot.System.ServerName,
                    $"{snapshot.System.Model ?? "NAS"} · DSM {snapshot.System.Version ?? "未知"}",
                    "运行中",
                    "\uEDA2",
                    snapshot.System)],
        };

    private static WorkspaceRow FileRow(FileItem item) =>
        new(
            item.Path,
            item.Name,
            item.IsDirectory ? "文件夹" : FormatBytes(item.Size),
            item.ModifiedAt?.ToLocalTime().ToString("g") ?? string.Empty,
            item.IsDirectory ? "\uE8B7" : "\uE8A5",
            item);

    private static WorkspaceRow ResourceRow(ResourceItem item) =>
        new(
            item.Id,
            item.Name,
            item.Detail,
            StatusText(item.State.ToString()),
            "\uE7F4",
            item);

    private static WorkspaceRow LogRow(LogEntry item) =>
        new(
            item.Id,
            item.Event,
            string.IsNullOrWhiteSpace(item.User) ? "系统" : item.User,
            item.Time?.ToLocalTime().ToString("g") ?? item.Level,
            "\uE9D9",
            item);

    private static string[] CategoriesFor(AppModule module) => module switch
    {
        AppModule.Containers => ["容器", "映像", "网络", "项目"],
        AppModule.VirtualMachines => ["虚拟机", "主机", "存储", "网络", "映像", "保护", "日志"],
        AppModule.NasSettings => ["概览", "存储", "套件", "账号", "日志", "连接", "网络", "安全"],
        _ => [],
    };

    private static string StatusText(string value) => value.ToLowerInvariant() switch
    {
        "running" or "healthy" or "seeding" or "finished" => "正常",
        "stopped" => "已停止",
        "paused" => "已暂停",
        "waiting" => "等待中",
        "warning" => "需要注意",
        "error" => "异常",
        _ => value,
    };

    private static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        var value = (double)Math.Max(bytes, 0);
        var index = 0;
        while (value >= 1024 && index < units.Length - 1)
        {
            value /= 1024;
            index++;
        }
        return $"{value:0.#} {units[index]}";
    }

    private async Task MutateAsync(Func<IDsmRepository, Task> operation)
    {
        if (!await _mutationGate.WaitAsync(0))
        {
            return;
        }
        try
        {
            var repository = app.Repository ?? throw new InvalidOperationException();
            await operation(repository);
            await ReloadAsync();
        }
        finally
        {
            _mutationGate.Release();
        }
    }

    private void RaiseCommandState()
    {
        RaisePropertyChanged(nameof(CanCreate));
        RaisePropertyChanged(nameof(CanRename));
        RaisePropertyChanged(nameof(CanControl));
        RaisePropertyChanged(nameof(CanDelete));
    }
}

public sealed record WorkspaceRow(
    string Id,
    string Title,
    string Detail,
    string Status,
    string Glyph,
    object Payload);
