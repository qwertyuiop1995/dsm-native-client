# Android 页面五态审计矩阵

## 审计口径

- 清单覆盖 `ui/**` 下全部以 `Screen.kt`、`Dialog.kt` 命名的生产页面/弹窗，并额外纳入同时承载 Container、Registry 与 VMM 页面的 `services/ServiceScreens.kt`。
- “覆盖”表示该文件承载的页面在此状态适用时已有生产分支；“不适用”必须有明确产品理由，不能用来掩盖缺实现；“缺口”表示源码仍把两种状态混用或没有恢复路径。
- “筛选空”只适用于用户在已取得的非空源集合上应用搜索或筛选后没有结果。静态表单、详情、首次查询结果和没有筛选器的列表标为“不适用”。
- 自动化“完整”要求每个适用状态都有页面级 Compose 证据；通用容器单测、源码阅读或另一个页面通过只能记为“局部”。
- `WorkspaceShell.kt`、`LanStashApp.kt` 是组合/导航外壳，不是独立数据页面；确认、写入进度和持久结果由各写操作矩阵审计，不用五态概念重复包装。
- 本矩阵不把 API 35 模拟器、静态门禁或语义树测试表述为实体机、TalkBack、OEM 字体/显示缩放和真实 NAS 验收。

## 生产页面与弹窗清单

| 文件 | 页面/弹窗 | 加载 | 空内容 | 筛选空 | 错误 | 正常 | 自动化 | 代码与测试依据 |
|---|---|---|---|---|---|---|---|---|
| `ChatScreen.kt` | 会话列表、消息详情及管理弹窗 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | `LoadableContent`；`ChatConversationDialogTest`、Chat 发送/管理测试，缺主会话四态直测 |
| `DownloadDestinationDialog.kt` | 下载目的地目录选择 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | 目录 `Loadable` 分支；下载创建测试，缺四态直测 |
| `DownloadSettingsDialog.kt` | 下载设置表单 | 不适用 | 不适用 | 不适用 | 不适用 | 覆盖 | 局部 | 数据由已加载 Workspace 草稿提供；`DownloadSettingsUiTest` 覆盖表单和写入反馈 |
| `FileBrowserScreen.kt` | 文件列表与收藏/回收站 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 局部 | `PageUiState`；`FileFilteredEmptyStateTest`、`FileBrowserAdaptiveScreenTest`，缺四态页面直测 |
| `FileCopyMoveDialog.kt` | 复制/移动目录选择 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | 目录 `Loadable` 分支；File Station 写入界面测试，缺四态直测 |
| `FilePreviewDialog.kt` | 文件预览与文本加载 | 覆盖 | 不适用 | 不适用 | 覆盖 | 覆盖 | 局部 | 预览加载/失败/内容分支；`FilePreviewAdaptiveTest`，缺加载与失败直测闭环 |
| `PhotoMoveDialog.kt` | 照片移动目录选择 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | 目录 `Loadable` 分支；照片写入测试，缺四态直测 |
| `PhotosScreen.kt` | 文件夹、时间线与相册 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 局部 | 相册加载分支与 `PhotoFilteredEmpty`；`PhotoBrowserAdaptiveScreenTest`，缺五态直测 |
| `downloads/DownloadDiscoveryDialog.kt` | RSS、BT 搜索与结果选择 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | 每次查询自身是源请求，不把无结果伪装成筛选空；`DownloadDiscoveryDialogTest` |
| `downloads/DownloadTaskDetailsDialog.kt` | 下载任务详情/文件列表 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | 详情与文件 `Loadable` 分支；`DownloadTaskDetailsDialogTest`，缺全部适用态直测 |
| `downloads/DownloadsScreen.kt` | 下载任务列表 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | 当前没有用户结果筛选器；`DownloadAdaptiveScreenTest` 与任务管理测试，缺列表四态直测 |
| `login/LoginScreen.kt` | 登录、连接与证书确认 | 覆盖 | 不适用 | 不适用 | 覆盖 | 覆盖 | 局部 | 连接中/连接失败/表单分支；`LoginScreenTest`、连接反馈测试 |
| `nas/DdnsSettingsDialog.kt` | DDNS 管理 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层加载/失败；`DdnsFeedbackCardTest` 覆盖写入反馈，缺空/内容直测 |
| `nas/EthernetSettingsDialog.kt` | 网口与代理服务器管理 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层；`EthernetFeedbackCardTest`、`ProxyFeedbackCardTest` |
| `nas/NasConnectionScreen.kt` | 活跃连接管理 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层；`ConnectionFeedbackCardTest`，缺空/内容直测 |
| `nas/NasDirectoryManagementScreen.kt` | 账号与群组 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层；`DirectoryManagementUiTest`，缺空/内容直测 |
| `nas/NasHardwareSettingsScreen.kt` | 硬件、电源与 UPS | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层并区分不可用；`SecurityHardwareSettingsUiTest` |
| `nas/NasPackageManagementScreen.kt` | 套件管理 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层；`PackageManagementUiTest` 覆盖空/不可用/内容，外层加载错误由通用容器测试 |
| `nas/NasPerformanceScreen.kt` | 性能采样 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `NasPerformanceScreenTest` 直接覆盖首次加载、无样本、失败、正常与重试 |
| `nas/NasRegionSettingsScreen.kt` | 区域与时间设置 | 不适用 | 不适用 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层；`RegionFeedbackCardTest` 覆盖写入反馈 |
| `nas/NasRemoteAccessSettingsScreen.kt` | 远程访问设置 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层并区分不可用；`RemoteAccessSettingsUiTest` |
| `nas/NasSecuritySettingsScreen.kt` | 安全设置 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层并区分不可用；安全设置界面测试 |
| `nas/NasServiceSettingsScreen.kt` | 文件服务、终端与代理设置 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 局部 | 数据继承 NAS 设置外层并区分不可用；File Service/Terminal/Proxy 反馈测试 |
| `nas/NasSettingsScreen.kt` | NAS 设置外层与总览/日志 | 覆盖 | 覆盖 | 缺口 | 覆盖 | 覆盖 | 局部 | 外层 `LoadableContent` 覆盖四态；`LogList` 把源日志为空和筛选后为空合并成 `no_records_for_filter`，且缺总览/日志五态直测 |
| `nas/NasStorageScreen.kt` | 存储、内容分析与 SMART | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | `NasStorageScreenTest` 覆盖分析失败和空闲/运行/结果，但未覆盖整页所有适用态 |
| `services/ServiceScreens.kt` | Container、Registry 与 VMM | 覆盖 | 覆盖 | 缺口 | 覆盖 | 覆盖 | 局部 | `LoadableContent` 覆盖主列表；Container/VMM/Registry 测试已有局部证据；事件和 VMM 日志的 `LogList` 同样混用源空与筛选空 |
| `services/VirtualMachineCreationDialog.kt` | 虚拟机创建向导 | 不适用 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 局部 | 存储不可用/校验错误/正常步骤；`VirtualMachineCreationDialogTest`，不把表单提交状态当页面加载 |
| `settings/SettingsScreen.kt` | 应用设置与语言 | 不适用 | 不适用 | 不适用 | 不适用 | 覆盖 | 局部 | 完全本地静态设置；设置与本地化测试，不适用远端数据五态 |
| `transfers/TransfersScreen.kt` | App 传输与 NAS 后台任务 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 完整 | `FileBackgroundTaskUiTest` 直接覆盖 NAS 五态，`TransferServerPresentationTest` 覆盖来源筛选空与正常任务 |

## 当前结论与后续闭环

- 生产清单共 29 个页面/弹窗文件；存在 2 个生产状态缺口，均来自共用 `LogList` 未区分“源日志为空”和“筛选后为空”。这不是接口或 ViewModel 缺口，可在 `ServiceScreens.kt` 的共用日志组件用 `logs.isEmpty()` 与 `filtered.isEmpty()` 分流解决。
- 27 个页面仍只有局部页面级自动化。通用 `PageUiStateTest`、`PageErrorAccessibilityTest` 能证明状态策略和错误语义，但不能替代把每个适用状态实际送入页面的 Compose 测试。
- 因此 A8“每页五态”叶子目标必须保持未勾选。先修复两个日志缺口，再按高频主页面、NAS 子页、异步弹窗三组补齐页面级测试；无需给不适用的静态表单制造虚假 loading/error 分支。
- `tools/codex/check_android_page_state_matrix.py` 会扫描新增/删除的生产页面文件、矩阵状态词和计划勾选状态。矩阵仍有生产缺口或自动化未闭环时，若有人提前勾选 A8 叶子，门禁会失败。
