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
| `ChatScreen.kt` | 会话列表、消息详情及管理弹窗 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测加载、源空、失败和会话内容 |
| `DownloadDestinationDialog.kt` | 下载目的地目录选择 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `DownloadLoginPageStateMatrixTest` 直测四个适用态 |
| `DownloadSettingsDialog.kt` | 下载设置表单 | 不适用 | 不适用 | 不适用 | 不适用 | 覆盖 | 完整 | 已加载 Workspace 草稿是唯一适用态；`DownloadLoginPageStateMatrixTest` 直测生产表单 |
| `FileBrowserScreen.kt` | 文件列表与收藏/回收站 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测五态 |
| `FileCopyMoveDialog.kt` | 复制/移动目录选择 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测四个适用态 |
| `FilePreviewDialog.kt` | 文件预览与文本加载 | 覆盖 | 不适用 | 不适用 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测加载、失败和文本内容 |
| `PhotoMoveDialog.kt` | 照片移动目录选择 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测四个适用态 |
| `PhotosScreen.kt` | 文件夹、时间线与相册 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测五态 |
| `downloads/DownloadDiscoveryDialog.kt` | RSS、BT 搜索与结果选择 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `DownloadLoginPageStateMatrixTest` 直测既有四态；`DownloadDiscoveryDialogTest` 补模块/类别目录加载、空、错误重试、正常选项与 2× 字体 |
| `downloads/DownloadTaskDetailsDialog.kt` | 下载任务详情/文件列表 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | 详情只在已有任务实体后打开；`DownloadLoginPageStateMatrixTest` 直测空文件与正常详情 |
| `downloads/DownloadsScreen.kt` | 下载任务列表与当前活动摘要 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `DownloadLoginPageStateMatrixTest` 直测任务列表四态；`DownloadActivityUiTest` 直测活动加载、零活动、局部错误/独立重试与正常速率，统计失败不遮蔽任务列表 |
| `login/LoginScreen.kt` | 登录、连接与证书确认 | 覆盖 | 不适用 | 不适用 | 覆盖 | 覆盖 | 完整 | `DownloadLoginPageStateMatrixTest` 直测连接中、错误与正常表单 |
| `nas/DdnsSettingsDialog.kt` | DDNS 管理 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 通过生产复用的 `DdnsManagementContent` 直测不可用、空和内容 |
| `nas/EthernetSettingsDialog.kt` | 网口与代理服务器管理 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 直测不可用、空、内容和保存中 |
| `nas/NasConnectionScreen.kt` | 活跃连接管理 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 直测不可用、空、内容和进行中 |
| `nas/NasDirectoryManagementScreen.kt` | 账号与群组 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 直测不可用、空、内容和进行中 |
| `nas/NasHardwareSettingsScreen.kt` | 硬件、电源与 UPS | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 直测不可用、内容和保存中 |
| `nas/NasPackageManagementScreen.kt` | 套件管理 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 直测不可用、空、内容和进行中 |
| `nas/NasPerformanceScreen.kt` | 性能采样 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `NasPerformanceScreenTest` 直接覆盖首次加载、无样本、失败、正常与重试 |
| `nas/NasRegionSettingsScreen.kt` | 区域与时间设置 | 不适用 | 不适用 | 不适用 | 不适用 | 覆盖 | 完整 | 数据继承 NAS 设置外层；`NasServicePageStateMatrixTest` 直测不可用、内容和保存中 |
| `nas/NasRemoteAccessSettingsScreen.kt` | 远程访问设置 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 直测不可用、内容和保存中 |
| `nas/NasSecuritySettingsScreen.kt` | 安全设置 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 直测不可用、空、内容和保存中 |
| `nas/NasServiceSettingsScreen.kt` | 文件服务、终端与代理设置 | 不适用 | 覆盖 | 不适用 | 不适用 | 覆盖 | 完整 | `NasServicePageStateMatrixTest` 直测无设置、内容和保存中 |
| `nas/NasSettingsScreen.kt` | NAS 设置外层与总览/日志 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测外层加载/错误/内容及真实日志页签的源空、内容、筛选空 |
| `nas/NasStorageScreen.kt` | 存储、内容分析与 SMART | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 与 `NasStorageScreenTest` 覆盖 SMART 空、分析加载/错误/结果及存储内容 |
| `services/ServiceScreens.kt` | Container、Registry 与 VMM | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测三页主状态，并通过 Container Events/VMM Logs 真实页签覆盖筛选空 |
| `services/VirtualMachineCreationDialog.kt` | 虚拟机创建向导 | 不适用 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `PrimaryPageStateMatrixTest` 直测校验错误、无存储与正常复核步骤 |
| `services/VirtualMachineImageImportDialog.kt` | 从 NAS 文件创建 VMM 映像 | 覆盖 | 覆盖 | 不适用 | 覆盖 | 覆盖 | 完整 | `VirtualMachineImageImportDialogTest` 直测加载、失败与重试、源空、目录及文件正常内容，并覆盖系统返回和提交门禁 |
| `services/VirtualMachineGuestDetailsScreen.kt` | VMM Guest 独立只读详情 | 覆盖 | 不适用 | 不适用 | 覆盖 | 覆盖 | 完整 | `VirtualMachineGuestDetailsUiTest` 直测加载、失败重试、正常只读内容、无写动作和 2× 字体空硬件配置 |
| `settings/SettingsScreen.kt` | 应用设置与语言 | 不适用 | 不适用 | 不适用 | 不适用 | 覆盖 | 完整 | 完全本地静态设置；`DownloadLoginPageStateMatrixTest` 直测生产设置页 |
| `transfers/TransfersScreen.kt` | App 传输与 NAS 后台任务 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 覆盖 | 完整 | `FileBackgroundTaskUiTest` 直接覆盖 NAS 五态，`TransferServerPresentationTest` 覆盖来源筛选空与正常任务 |

## 当前结论与后续闭环

- 生产清单共 31 个页面/弹窗文件；共用 `LogList` 已区分“源日志为空”和“筛选后为空”，当前生产状态缺口为 0。
- 31 个页面/弹窗文件的全部适用状态均已有生产 Composable 页面级证据；静态表单和已加载实体详情没有被人为制造空内容或筛选空。
- API 35 `Medium_Phone_API_35` 既有页面矩阵运行 `PrimaryPageStateMatrixTest`、`DownloadLoginPageStateMatrixTest`、`NasServicePageStateMatrixTest` 及 `VirtualMachineImageImportDialogTest` 共 61/61 通过；第 80 批另以 `DownloadDiscoveryDialogTest` 与 `DownloadActivityUiTest` 7/7 补齐搜索目录及活动摘要状态。测试同时发现并修复 NAS、Container 与 VMM 日志内容区未占用剩余高度的裁切问题。
- `tools/codex/check_android_page_state_matrix.py` 会扫描新增/删除的生产页面文件、矩阵状态词和计划勾选状态。矩阵仍有生产缺口或自动化未闭环时，若有人提前勾选 A8 叶子，门禁会失败。
