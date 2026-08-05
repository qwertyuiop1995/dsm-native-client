# DSM 套件管理三端实现计划

> 当前完成情况和验证结果以[当前开发进度](../progress/STATUS.md)为准。本文只维护范围、契约、安全门槛、未完成工作和验收条件。

## 1. 范围

本计划覆盖 Download Station、Virtual Machine Manager 和 Container Manager。目标是在 macOS、移动端与 Windows 上共享同一领域契约、安全门槛和兼容矩阵，同时保持各平台原生界面。

三个模块分别覆盖 Download Station 任务与设置、Container Manager 容器与资源，以及 Virtual Machine Manager 虚拟机生命周期与控制台。各平台具体已实现范围不在本文重复维护。

## 2. 契约与接口优先级

1. Download Station 优先使用公开 `SYNO.DownloadStation.*`。只有能力发现未返回公开接口时，才使用独立的 `SYNO.DownloadStation2.*` 适配分支。
2. VMM 优先使用公开 `SYNO.Virtualization.API.*`。内部 `SYNO.Virtualization.*` 不复用公开接口的参数或响应模型。
3. Container Manager 当前依赖 `SYNO.Docker.*` 内部接口。每个 API、版本和方法必须由运行时能力发现明确返回后才可调用。
4. 未知状态必须原样保留，界面不得将未知值误报为失败或成功。
5. SID、SynoToken、Cookie、DID、下载链接、Tracker、容器环境变量、挂载路径、Registry 凭据、虚拟机控制台凭据和日志正文不得进入分析日志。
6. 容器主列表固定按当前已验证契约提交 `offset=0`、`limit=-1`、`type=all`；映像、网络、项目和活动记录属于附属读取，单项不可用不得遮蔽已成功读取的容器。
7. VMM 主列表优先读取官方 `SYNO.Virtualization.API.Guest`；只有官方读取明确不兼容且内部 Guest 能力同时存在时，才允许只读降级。主列表成功后，主机、存储、网络、映像、保护和日志单项失败不阻断页面；日志 `list` 必须携带网页端要求的筛选、日期和排序参数。各端必须区分“确实为空”和“读取不可用”，登录失效、证书变化与取消仍必须立即上报。
8. 镜像仓库使用已验证的内部契约：`SYNO.Docker.Registry.search` 提交 `offset=0`、`limit=50`、`page_size=50` 和 `q`，`tags` 使用 `repo`；下载由 `SYNO.Docker.Image.pull_start` 提交 `repository` 与 `tag`。三端不得退回未验证的 `pull` 方法。
9. VMM 基础创建和常规修改优先使用 Synology 官方 VMM API Guide 公开的 `SYNO.Virtualization.API.Guest` v1，并配合公开 Task、Storage、Network 与 Guest Image v1；内部 `SYNO.Virtualization.Guest.create/set` 只能作为经版本化验收的降级。控制台使用套件 noVNC 页面与 `synovirtualization/ws/{guest_id}` 通道。会话 Cookie 只注入非持久 WebView，不写入 URL、日志或磁盘。
10. VMM 映像删除优先使用公开 `SYNO.Virtualization.API.Guest.Image.delete`；网络修改和删除没有公开写接口，只允许在内部 `SYNO.Virtualization.Network` 能力存在、当前 DSM/VMM 版本通过契约验收后开放，并保持确认、防重复提交和写后回读。
11. Apple、Android 与 Windows 共用 `VirtualMachineManagerSnapshot` 的保护计划、计划策略、保留策略、日志和分区可用性语义；Android/Windows 实现界面时不得把读取失败呈现为空数据。
10. 下载任务文件使用官方 `SYNO.DownloadStation.Task.create` multipart 契约，文件是正文的最后一个字段；基础设置使用官方 `Info.getconfig/setserverconfig`，计划使用 `Schedule.getconfig/setconfig`，保存后必须回读核验。

## 3. 写操作安全门槛

所有写操作必须同时满足：

- 能力发现与版本范围检查。
- 当前账号权限由 NAS 最终裁决，客户端只显示可恢复提示。
- 单次操作防重复提交，操作期间禁用相关按钮并显示进度。
- 删除、移除下载数据、强制断电等不可逆操作二次确认。
- 能回读的操作必须在完成后重新读取目标状态；回读不一致不得报告成功。
- VMM 异步任务在接入创建、迁移、导入导出前必须增加任务轮询、取消、超时与最终状态核对。

## 4. 平台计划

### Apple

- `DsmCore` 保持平台无关模型与 `ServiceManagementRepository` 契约。
- `DsmNetwork` 负责公开/内部适配隔离、版本能力发现、写后回读和安全错误映射。
- macOS 使用 SwiftUI 原生列表、工具栏、确认对话框和键盘操作。
- iPhone/iPad 复用共享包；采用导航栈、底部操作栏和分步表单，不压缩桌面表格。

### Android

- 使用 Kotlin/Jetpack Compose 复刻相同领域字段和动作枚举。
- 将公开与内部适配器拆成不同数据源，禁止用一个动态 Map 贯穿界面。
- 使用 Material 确认对话框、WorkManager 长任务和系统安全存储。

### Windows

- 使用 C#/WinUI 复刻相同领域字段和动作枚举。
- 使用 NavigationView、DataGrid、ContentDialog 和系统凭据存储。
- 长任务通过可取消后台任务呈现，窗口关闭前提示仍在执行的高影响操作。

## 5. 后续里程碑

### M2：Download Station 完整功能

- Tracker、Peer、BT 文件选择与优先级。
- BT 搜索模块、类别、搜索结果和直接下载。
- RSS 站点、条目、下载过滤器。
- 已完成官方基础设置：默认位置、eMule、自动解压、BT/HTTP/FTP/NZB/eMule 限速与计划；继续补齐套件内部的高级 BT、监听目录、NZB 服务器、RSS 与通知设置。
- Android 已完成官方任务文件、Tracker、Peer 详情、RSS 站点/条目浏览、RSS 单站点手动刷新和 BT 实际搜索；搜索仅使用已启用模块并清理临时服务端任务，RSS 条目和搜索结果可经可写目录选择后直接创建任务。RSS 刷新具备目标预检、同站点防重复、写后回读和未确认结果；官方指南未公开 RSS 完整编辑或文件优先级写参数，相关能力与高级设置保持关闭并等待版本化契约和真实 NAS 验收。
- Android 已按官方 `SYNO.DownloadStation.Task.edit` v1 接入单任务保存位置修改：选择可写目录、明确提示可能移动已有文件，写前复核任务与目录完整基线，提交后严格回读，断线和取消不自动重放；该能力不复用 `DownloadStation2`。

### M3：Container Manager 完整功能

- 容器创建/编辑向导：端口、卷、网络、资源限制、启动策略与能力。
- 容器详情、进程、实时资源、日志流、终端与导入导出。
- 私有 Registry 管理与凭据安全存储。
- 项目 Compose 校验、创建、更新、构建日志和删除。
- 映像导入、导出、更新与清理未使用资源。

### M4：VMM 完整功能

- Android 已使用官方公开 v1 契约完成分步创建与常规设置修改，并覆盖提交前检查、防重复、任务轮询/清理和最终回读；独立 noVNC 控制台仍因 Android 侧稳定契约未验证而关闭。
- 扩展编辑向导：虚拟盘扩容/增删和多网络接口管理。
- 克隆、迁移、导入导出。
- 映像创建、上传、编辑与删除。
- 快照、保护计划、恢复与保留策略。
- Android 已使用官方 Guest v1 `additional=true` 只读展示磁盘与网卡配置，并使用 Task.Info v1 提供最多 100 项、不含任务 ID/内部状态的只读任务中心；`clear` 保持关闭。
- 许可证与 High Availability 状态。

## 6. 验收

- 每个 DSM build、套件版本与权限组合都记录在兼容矩阵。
- 公开 API、内部降级和接口缺失至少各有一组自动化契约测试。
- 所有危险写操作在专用测试目标完成成功、权限不足、重复点击、超时、状态不一致和断线恢复测试。
- 浅色/深色、键盘、触控、VoiceOver/屏幕阅读器、动态文字与降低动态效果均通过平台验收。
