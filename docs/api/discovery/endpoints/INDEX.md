# 当前私有 API 端点组索引

本页按稳定业务边界汇总源码已经接入或明确保持关闭的内部 API。端点组用于减少重复，但每个 API 名称仍逐项列出。版本含义必须结合环境 verification 阅读：

- “客户端范围”来自 `DsmCapabilityDiscovery.supportedRanges`，不是某台 NAS 的实机承诺。
- “当前确认”来自 [`lab-a` 当前基线](../environments/2026-07-29-lab-a-dsm-69057-u12.md) 所引用的既有脱敏发现证据。
- 同一端点组可以在不同 NAS 或版本下拥有不同 verification，不复制端点定义。

## 端点组

### `quickconnect-relay-control`

- 组件：`dsm-core`
- 内部协议：QuickConnect `Serv.php`
- 命令：`get_server_info`、`request_tunnel`
- 数字 API 版本：不适用
- 当前证据：中继建立、目标身份核对及随后 `SYNO.API.Info` 探测已有行为记录。
- 降级：直连候选全部失败时才尝试；中继异常时停止，不绕过证书或身份核对。

### `file-station-remote-mount`

- 组件：`file-station`
- API：`SYNO.FileStation.Mount`
- 客户端范围：v1
- 当前确认：v1 `mount_remote`、`unmount` 为内部实验性契约。
- 状态：候选写能力；需要专用环境完成权限、错误凭据、重连、重复提交和公开 `getinfo` 回读验证。

### `dsm-system-observability`

- 组件：`dsm-core`
- API 与当前确认：
  - `SYNO.Core.System`：`info` v3。
  - `SYNO.Core.System.Utilization`：`get` v1。
  - `SYNO.Core.CurrentConnection`：`list` / `kick_connection` v1；只读列表已核对，断开未执行。
  - `SYNO.Core.SyslogClient.Log`：`list` v1。
  - `SYNO.Core.Upgrade.Server`：`check` v3。
  - `SYNO.LogCenter.History`：客户端范围 v1；无记录时允许空结果。
- 降级：性能、连接、日志或更新检查失败时各自显示不可用，不阻断其他 NAS 管理能力。

### `dsm-storage-hardware`

- 组件：`dsm-core`、`storage-manager`
- API 与客户端范围：
  - `SYNO.Storage.CGI.Storage` v1。
  - `SYNO.Storage.CGI.Smart` v1。
  - `SYNO.Core.Storage.Volume` v1。
  - `SYNO.Core.Storage.Disk` v1。
  - `SYNO.Core.Hardware.PowerRecovery`、`Led.Brightness`、`FanSpeed`、`BeepControl`、`Hibernation` v1。
  - `SYNO.Core.ExternalDevice.UPS` v1。
- 当前确认：`Storage.load_info` v1 与硬盘检测读取结构已核对；`Storage.Volume.list` 在当前环境返回错误 `101`；S.M.A.R.T. 启停和硬件设置没有为发现而执行。
- 降级：以 `load_info` 为主，不使用失败的 `Volume.list` 覆盖有效结果；写入口按能力与权限逐项关闭。

### `dsm-administration`

- 组件：`dsm-core`
- 套件与任务：
  - `SYNO.Core.Package` v1-v2，当前列表使用 v2。
  - `SYNO.Core.Package.Control`、`SYNO.Core.Package.Uninstallation`、`SYNO.Core.Package.Thumb` v1。
  - `SYNO.Core.TaskScheduler` v1-v4；列表/运行使用 v3，详情/创建/修改使用 v4。
  - `SYNO.Core.EventScheduler` v1。
- 账号：`SYNO.Core.User`、`SYNO.Core.Group` v1。
- 控制面板：
  - `SYNO.Core.Terminal`、`SYNO.Core.FileServ.SMB`、`SYNO.Core.FileServ.NFS` v1-v3。
  - `SYNO.Core.FileServ.FTP`、`SYNO.Core.FileServ.FTP.SFTP`、`SYNO.Core.Network.Proxy` v1。
  - `SYNO.Core.QuickConnect` v1-v3、`SYNO.Core.QuickConnect.Upnp` v1。
  - `SYNO.Core.Security.AutoBlock`、`SYNO.Core.FileServ.ServiceDiscovery` v1。
  - `SYNO.Core.Web.DSM`、`SYNO.Core.Network.Ethernet`、`SYNO.Core.Security.DoS` v1-v2。
  - `SYNO.Core.Region.NTP` v1-v3。
  - `SYNO.Core.DDNS.Provider`、`SYNO.Core.DDNS.Record` v1。
  - `SYNO.Core.Security.Firewall`、`Firewall.Conf`、`Firewall.Profile.Apply` v1。
- 当前证据：只读结构、网页请求和能力发现已分项记录；套件启停/卸载、任务写入、账号、网络、防火墙等不得仅凭同一端点组标记为行为验证。

### `download-station2-fallback`

- 组件：`download-station`
- API 与客户端范围：
  - `SYNO.DownloadStation2.Task` v1-v2。
  - `SYNO.DownloadStation2.Task.Statistic` v1。
  - `SYNO.DownloadStation2.Settings.Location` v1。
  - `SYNO.DownloadStation2.RSS.Feed` v1。
- 既有静态目录还包含 `Task.List`、`Task.List.Polling`、BT Tracker/Peer/File，但未进入当前稳定能力表。
- 状态：仅在官方 `SYNO.DownloadStation.*` 缺少必要能力且运行时明确发现时使用。

### `vmm-internal`

- 组件：`virtual-machine-manager`
- API 与客户端范围：
  - `SYNO.Virtualization.Guest`、`Guest.Image`、`Host`、`Repo`、`Network`、`GuestProtect.Plan` v1-v2。
  - `SYNO.Virtualization.Guest.Action` v1。
  - `SYNO.Virtualization.Log` v1。
- 当前确认：VMM `2.6.5-12202` 的读取方法、日志 v1 参数和 noVNC 地址生成逻辑已有记录；网络 `set/delete`、创建和修改未形成写行为验证结论。
- 降级：优先公开 `SYNO.Virtualization.API.*` v1；内部读取不可用时保留明确的不可用状态。

### `container-manager-internal`

- 组件：`container-manager`
- API：`SYNO.Docker.Container`、`Image`、`Registry`、`Network`、`Project`、`Log`
- 客户端范围：全部 v1
- 当前确认：Container Manager `24.0.2-1535` 下，容器列表、仓库搜索和标签参数已经核对；镜像拉取请求在发送前终止。
- 状态：读取按能力降级；所有写行为仍需专用目标验证。

### `chat-internal`

- 组件：`synology-chat-server`
- API 与客户端范围：
  - `SYNO.Chat.Channel` v1-v5。
  - `SYNO.Chat.Channel.Named` v1。
  - `SYNO.Chat.Channel.Anonymous` v1-v2，当前确认 `initiate` v2。
  - `SYNO.Chat.Channel.Member` v1。
  - `SYNO.Chat.User` v1-v3、`SYNO.Chat.User.Avatar` v1。
  - `SYNO.Chat.Post` v1-v8；当前确认的创建、转发与公告方法使用 v5。
  - `SYNO.Chat.Post.File` v1-v2，当前确认 v2。
  - `SYNO.Chat.Post.Reminder`、`Post.Vote`、`Post.Schedule` v1。
- 当前证据：Chat Server `2.4.1-22111` 官方网页客户端与能力发现契约；读取、创建、删除、提醒、投票等仍按原兼容矩阵的单项证据等级处理。
- 降级：内部接口不可用时隐藏聊天能力，不用公开 Bot/Webhook API 冒充用户会话。

### `chat-realtime`

- 组件：`synology-chat-server`
- 协议：同源 `sc/socket.io`
- Engine.IO 客户端兼容：4 / 3
- 状态：实时事件只触发 API 回读；连接失败时回退 5 秒轮询，连接稳定时每 30 秒校准。
- 未验证：不同 Chat Server 版本、QuickConnect 中继、睡眠唤醒和登录续期的完整矩阵。

### `photos-internal-candidate`

- 组件：`synology-photos`
- 候选命名空间：`SYNO.Foto.*`、`SYNO.FotoTeam.*`
- 候选能力：Album、Folder、Item、Timeline、RecentlyAdded、GeneralTag、Geocoding、Thumbnail、Download。
- 当前证据：仅为静态候选目录；在 Synology Photos `1.8.2-10090` 上没有完成内部 Adapter 契约测试。
- 状态：增强能力保持关闭；基础照片库继续使用官方 File Station 能力。

## 未形成稳定端点的组件

- `storage-analyzer`：当前安装版本 `2.1.0-0620`，但历史报告内部 API 尚未固化，不登记猜测的 API 名称。
- 只有源码候选名称、没有当前环境证据的接口，不得自动提升到本索引的“当前确认”。

