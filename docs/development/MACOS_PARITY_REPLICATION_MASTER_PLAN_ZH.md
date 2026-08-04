# macOS 功能对齐 Windows 与 Apple 移动端总控计划

- 状态：规划基线，尚未开始本计划实施
- 编制日期：2026-08-03
- 源码参照：`01cd28001c0fade20462a62b9c311e2f50ec5bf1`

## 1. 决策摘要

本次采用三份计划文档：

1. 本文负责范围、功能对齐账本、依赖顺序、跨端共同出口和 Codex 多代理编排。
2. [Windows 专项计划](WINDOWS_MACOS_PARITY_DEVELOPMENT_PLAN_ZH.md)负责 WinUI 3、Windows 系统集成和 x64/arm64 验收。
3. [iPhone/iPad 专项计划](APPLE_MOBILE_MACOS_PARITY_DEVELOPMENT_PLAN_ZH.md)负责 SwiftUI 通用 App，并在同一文档内分别设置 iPhone 与 iPad 验收轨。

iPhone 与 iPad 不拆成两份计划。当前仓库已经使用同一个 `DsmMobile` Target、Bundle ID、共享 Package、Keychain 和本地化资源；拆成两份会让业务语义、危险写保护和进度状态发生漂移。两种设备只在信息架构、窗口宽度、输入方式、并列详情和系统集成上分轨。

## 2. 目标与完成定义

目标不是复制 macOS 截图，而是让 Windows、iPhone 和 iPad 获得相同的用户结果、权限边界、失败语义和恢复路径，同时使用各平台原生交互。

一个功能只有同时满足以下六项才能标记为“平台对齐”：

1. **业务等价**：读写范围、排序分页、冲突处理、取消和最终状态与 macOS 基线一致。
2. **安全等价**：能力与权限检查、危险确认、父子目标防重复、提交后不自动重放及写后复查均未弱化。
3. **平台等价**：使用 WinUI/Fluent 或 SwiftUI/iOS/iPadOS 原生导航、选择器、分享、通知和辅助功能，而非移植桌面手势。
4. **状态完整**：加载、空内容、筛选后为空、错误、正常内容五态，以及离线、会话过期、功能不可用和部分成功状态都有恢复动作。
5. **质量完整**：英语与简体中文、浅色/深色、高对比度或系统对比度、键盘/触控、屏幕阅读器、动态文字或缩放、减少动态效果均有证据。
6. **验证完整**：至少达到 `IMPLEMENTED`、`UNIT_TESTED` 和目标工程的 `BUILD_VERIFIED`；依赖签名、真实设备或 DSM 的能力继续明确标记为 `SIGNING_REQUIRED` 或“未验证”，不得提前称为完成。

验证等级以[功能实现与验证等级](../quality/VERIFICATION_LEVELS_ZH.md)为准，实时测试数量只写入[当前开发进度](../progress/STATUS.md)，不在本计划复制容易失效的数字。

## 3. 范围边界

### 3.1 本计划包含

- 以 macOS 已有源码入口为基线的登录、多 NAS、File Station、照片、Chat、Download Station、Container Manager、Virtual Machine Manager、NAS 管理、传输、应用设置和系统集成。
- Windows 对应的资源管理器 Cloud Files、通知区域常驻、窗口与键鼠体验。
- iPhone/iPad 对应的 Files/Photos/分享入口、后台传输、状态恢复、触控与 iPad 生产力体验。
- 为复刻所必需的目标平台领域模型、Repository、UI、合成 fixture、自动化测试和文档更新。

### 3.2 本计划明确排除

- 修改 `apple/Apps/DsmMac/**`。发现 macOS 缺陷时只记录证据并请求新的范围授权。
- 修改 Android 源码、资源或测试。若公共契约变化，只记录 Android 影响并遵循五端评估规则。
- 把 macOS 尚未实现的候选能力顺带加入目标端，例如完整 RSS 编辑、Container Compose 编辑/终端/日志流、VMM 迁移/克隆/高级磁盘、Chat 加密和其他尚未进入 macOS 的套件。
- 为了“看起来一致”自行猜测内部 API、改变安全策略或绕过目标平台限制。
- 未经批准增加第三方依赖、提高最低系统版本、改变 Bundle ID/MSIX Identity、签名、entitlement、包格式、持久化结构或公开契约。
- 本计划本身不授权在真实 NAS 上执行创建、修改、删除、断网、重启、关机或权限变更。

### 3.3 macOS 只读与共享 Package 边界

`apple/Apps/DsmMac/**` 在实施期间保持只读。`apple/Packages/**` 可在以下条件全部满足时做向后兼容增量修改：

- 目标能力已有 macOS 行为和 Repository 契约证据；
- 不要求 macOS App 改用新的 UI 或状态模型；
- 新接口不会改变既有请求、持久化或错误语义；
- Apple 共享测试和 macOS 无签名构建继续通过；
- 若需要把现有目录正式加入 Swift Package target，先按工具链变更规则取得用户同意。

## 4. 事实来源与基线冻结

发生冲突时按以下优先级重新核查，不采信模型记忆或旧总结：

1. 根目录 `AGENTS.md`、适用的契约、ADR 和安全基线；
2. macOS 源码与同一版本测试；
3. `docs/api/discovery/` 中对应环境和证据等级；
4. [平台功能矩阵](../progress/PLATFORM_MATRIX.md)与专项计划；
5. [当前开发进度](../progress/STATUS.md)中的实时验证结论。

平台矩阵和 `STATUS.md` 只负责汇总进度，不能自行提升证据等级。没有可复现命令输出，或没有 `contracts/private-api/compatibility.json` 与对应发现记录支持时，任何切片都不得仅凭进度文档标成“已验证”。

本文编制时 Apple 与 Windows 源码没有未提交差异，但契约、专项计划和 Android 存在用户进行中的改动。正式实施每个波次前必须重新执行：

```bash
git status --short --branch
git diff -- apple windows contracts docs/development AGENTS.md
git log -1 --oneline -- apple/Apps/DsmMac apple/Packages
```

若 macOS 在计划编制后新增功能，主 agent 先把新增行为加入对齐账本，再决定插入当前波次还是后续增量波次；不得静默改变正在验收的范围。

## 5. 对齐状态与账本格式

每个平台、每个功能 ID 使用以下状态之一：

这些是执行流状态，不替代 `VERIFICATION_LEVELS_ZH.md` 的证据等级；账本必须同时记录两者。尤其 `AUTO_VERIFIED` 只是阶段出口，仍需分别留下 `UNIT_TESTED`、`BUILD_VERIFIED` 等可复现证据。

| 状态 | 含义 |
| --- | --- |
| `NOT_STARTED` | 已有基线和目标，但未开始实现 |
| `IN_PROGRESS` | 已分配明确 owner，仍有开发或测试工作 |
| `CODE_COMPLETE` | 源码路径完整，但自动化或目标构建尚未全部通过 |
| `AUTO_VERIFIED` | 单元/集成/UI 自动化及目标工程构建通过 |
| `DEVICE_VERIFIED` | 目标设备和脱敏真实环境已验证 |
| `BLOCKED` | 有具体外部条件、证据或用户决策阻塞 |
| `NOT_APPLICABLE` | 平台不存在同类用户目标，且主 agent 已记录理由与替代路径 |

每个切片必须记录：

```text
功能 ID：
macOS 证据路径与验证等级：
目标平台用户结果：
原生交互转换：
公开/内部 API 与能力开关：
危险等级与重复提交策略：
owner 与允许修改文件：
自动化命令和结果：
目标设备/签名/DSM 未验证项：
状态与下一出口：
```

## 6. macOS 功能基线与跨端目标账本

以下是实施入口，不把“源码存在”表述为真实 DSM 已验证。详细验证边界继续以 `STATUS.md` 和专项计划为准。ID 后的证据标签含义如下，本次规划没有重新执行其既有测试：

- `A`：仓库中存在源码和对应自动化证据，只证明实现与测试路径存在。
- `B`：存在源码，但系统集成、专门自动化或目标环境证据仍不足。
- `C`：依赖内部 API，当前兼容结论仍是 degraded 或写操作未行为验证；未知环境默认关闭。
- `D`：macOS 明确未实现或禁用，不得算入本轮对齐完成；表格只在说明边界时提及。

登录安全还必须满足同一条不可弱化的链路：先使用系统信任；只有结构与有效期检查合格的叶证书才允许用户固定；QuickConnect relay 必须通过系统信任；路由发现阶段不得发送登录凭据；证书变化时同时展示旧、新指纹并要求重新确认。证据位于 `apple/Packages/DsmNetwork/Sources/DsmCertificateTrust.swift`、`apple/Packages/DsmNetwork/Sources/DsmQuickConnectResolver.swift` 及对应测试。

以下内部能力的当前验证边界必须直接进入各平台账本，不能因为 macOS 已有界面而省略：

- `download-station2-fallback`：`observed:degraded`；任务文件上传与设置写尚无行为验证。
- `file-station-remote-mount`：`observed:candidate`；内部挂载创建/断开尚无专用目标写行为验收，未知环境关闭。
- `container-manager-internal`：全部为内部 API，`observed:degraded`；镜像拉取请求曾在发送前终止，其他写操作未验证。
- `vmm-internal`：`read-verified:degraded`；创建、修改、网络写和删除未形成行为验证结论。
- `chat-internal` 与 `chat-realtime`：`observed:degraded`；各项读写按端点分别 gate，完整跨版本、睡眠唤醒和中继矩阵未验证。
- NAS 管理相关内部端点总体仍为 `observed:degraded`；外接存储、ZRAM、电源计划、进程、当前账号共享访问保持只读，系统升级安装、套件安装/升级和管理员 ACL 矩阵保持关闭。SMART、账号、网络、DDNS、电源等危险写必须逐端点取得权限、重复提交与写后复查证据。
- `photos-internal-candidate`：`static:disabled`；人物、地点、标签和真正相册实体不在本轮范围。

上述端点 ID 与证据等级以 `contracts/private-api/compatibility.json`、`docs/api/discovery/endpoints/INDEX.md` 和稳定端点记录为准。表中只写文件名时，App 类型位于 `apple/Apps/DsmMac/Sources/`，共享类型位于 `apple/Packages/*/Sources/`；请求证据位于 `contracts/request-fixtures/` 及 `apple/Packages/DsmNetwork/Tests/RequestFixtureContractTests.swift`，不得把类型名或“有 fixture”本身当作环境验证。

| ID | macOS 用户能力基线 | Windows 等价目标 | iPhone/iPad 等价或转换 | 主要证据 |
| --- | --- | --- | --- | --- |
| FND-01 · A | 多 NAS 资料、新建/删除/重排、OTP、可选保存密码、自动登录、会话恢复与退出 | Credential Locker、资料选择与独立“切换 NAS/退出登录” | Keychain、资料选择器、独立切换与退出；切换时保留安全后台任务 | `LoginViewModel.swift`、`DsmAuthenticationService.swift` |
| FND-02 · A/B | HTTPS 地址、可选端口、QuickConnect 直连/中继、连接方式提示 | 保持身份核对、官方中继域限制和路由提示 | 同一共享网络契约；在蜂窝/Wi-Fi 切换后重新确认路由 | `DsmQuickConnectResolver.swift`、`DsmCertificateTrust.swift` |
| FND-03 · A | 自签名证书指纹复核、按 NAS 绑定、证书变化阻断 | Windows 原生证书对话与 Credential Locker 分离 | 触控友好的安全核对页；技术指纹置于次级详情 | `LoginView.swift`、安全基线 |
| FND-04 · A/C | 模块能力发现、不可用提示、内部 API 按环境关闭 | 页面说明原因和可恢复动作，不静默隐藏 | 顶层入口保持可发现；详情解释套件/权限/版本条件 | `ApiCapability.swift`、私有 API 兼容矩阵 |
| NAV-01 · A | 侧栏分组、详情区、模块返回后保持目录/筛选/历史 | `NavigationView` + 模块专用页 + BackStack；窗口缩放不丢状态 | iPhone 五入口 Tab/Stack；iPad SplitView；每个 NAS 与 Scene 隔离恢复 | `WorkspaceSection`、`WorkspaceNavigationTests.swift` |
| FILE-01 · A | 共享目录、文件夹分页、列表/图标、排序/分组、面包屑、搜索 | 列表/网格切换、BreadcrumbBar、键盘搜索、多选 | iPhone 层级 Stack 与搜索；iPad 列表-详情三栏；返回恢复滚动/筛选 | `WorkspaceView.swift`、`DsmFileRepository.swift` |
| FILE-02 · A/C | 收藏、最近位置、回收站、远程位置、分享链接入口；公开 VirtualFolder 只读浏览与内部挂载管理分开 | 左侧位置集合与上下文菜单；内部创建/修改/断开在未知环境关闭 | Files 首页分区；iPad 可拖入侧栏，iPhone 使用操作菜单；读取失败可降级 | `WorkspaceModel.swift`、`file-station-remote-mount` |
| FILE-03 · A | 新建文件夹/空文件、重命名、详情、文件夹统计和 MD5 | 命令栏、F2、属性面板、触控菜单 | 表单 Sheet、长按菜单；iPad Inspector；不依赖双击/右键 | `WorkspaceModel.swift`、`FilePropertiesView` |
| FILE-04 · A/B | 系统选择器上传、覆盖确认、文件/文件夹/批量下载、取消，以及有恢复元数据时的继续/重试；上传重启发送，已知大小普通下载才用严格 Range 分片继续 | FileOpenPicker/FileSavePicker、后台传输和系统通知 | Document/Photos Picker、分享导出、后台 URLSession；不支持安全后台时明确前台降级 | `WorkspaceModel.swift`、`DsmFileRepository.swift` |
| FILE-05 · A/B | 同 NAS 复制/移动、跨 NAS 有界流、粘贴冲突、拖拽移动和限时撤销 | 剪贴板、拖放、键盘快捷键、Undo InfoBar | Edit 多选 + 目标选择器；iPad 拖放为快捷方式，iPhone 始终有可见替代操作 | `AppModel`、`WorkspaceModel.swift` |
| FILE-06 · A | ZIP/7z 压缩、常见格式解压、密码、编码和覆盖确认 | 分步 ContentDialog/任务中心 | 分步 Sheet；长任务进入活动中心，可取消且提交后不重放 | `WorkspaceModel.swift`、请求 fixture |
| FILE-07 · A | 创建/复制/列出/删除（撤销）分享链接，支持密码和有效期 | 系统剪贴板/分享、管理表格 | 系统 ShareLink/分享 Sheet；敏感链接不进通知或日志 | `WorkspaceModel.swift` |
| FILE-08 · A/B | 缩略图、图片/PDF/文本/音频/视频预览、图片切换缩放、媒体 Range、文本编辑与格式整理 | 原生媒体/文档控件、可调整预览区或独立窗口 | 全屏查看器、捏合/分页/系统分享；iPad 并列预览；编辑离开前保护未保存内容 | `FilePreviewView.swift` |
| FILE-09 · A/C | 安全删除、回收站发现与受兼容开关保护的恢复 | 权限摘要、强化确认、结果分级与刷新 | 底部危险操作与系统确认；永久删除加强提示；取消后只复查 | `WorkspaceModel.swift`、`MutationResult.swift` |
| ACT-01 · B | App 传输与 NAS 后台任务分源、速度/剩余时间、筛选、分页、通知 | 活动中心、Toast/系统通知、托盘摘要 | Activity Tab、Live 状态与本地通知；后台受系统调度，不承诺常驻 | `ActivityTask.swift`、`WorkspaceView.swift` |
| PHOTO-01 · A/D | 基于公开 File Station 扫描 `/home/Photos` 与 `/photo` 的个人/共享空间、文件夹、时间线、文件夹式相册、分页、搜索筛选、年/月定位；人物/地点/标签/真正相册实体未实现 | 自适应照片网格和时间线 | 内容优先网格；iPhone 全屏时间线，iPad 网格-详情；滚动按可见窗口取图 | `PhotoLibraryModel.swift`、`PhotoLibraryView.swift`、`photos-internal-candidate` |
| PHOTO-02 · A/B | 缩略图缓存、完整查看、HEIC/MOV/Live Photo 兜底、EXIF 详情 | 查看器、键盘前后切换、元数据面板 | 手势查看、Live Photo、分享；iPad 元数据 Inspector；大图严格内存上限 | `PhotoLibraryModel.swift`、`FilePreviewView.swift` |
| PHOTO-03 · A/C | 上传、导出、删除、分享、移动和照片页回收站恢复 | 多选命令栏、拖放导入导出 | Photos Picker/分享 Sheet、Edit 多选、目标文件夹 Sheet；系统照片图库删除不属于 parity | `PhotoLibraryModel.swift` |
| CHAT-01 · C | 会话、用户、首次单聊、私人群聊、成员与未读/置顶/本地已读 | 会话-消息-详情布局、通知入口 | iPhone 会话到消息 Stack；iPad 双栏/三栏；徽标只表示可解释未读 | `ChatWorkspaceModel.swift`、`DsmChatRepository.swift` |
| CHAT-02 · C | 消息分页、草稿、发送/失败重试、实时 Socket.IO 与轮询降级 | 键盘发送、连接状态与可恢复错误 | 安全区 Composer、系统返回保留草稿；前后台切换重新同步 | `ChatWorkspaceModel.swift`、`DsmChatRealtimeClient.swift` |
| CHAT-03 · C | 单附件上传/保存、缩略图、图片预览；提醒、定时消息与投票第一阶段 | 文件选择器、详情窗格、任务反馈 | Photos/Files 选择器、分享保存、原生 Sheet；内部写能力继续按版本关闭 | `ChatWorkspaceView.swift`、Chat 请求 fixture |
| CHAT-04 · C | 删除本人消息、关闭会话、消息转发、服务端消息置顶/取消置顶；语音发送和完整加密实现不存在 | 可发现的消息/会话菜单与结果回读 | 长按菜单和确认 Sheet；加密群创建继续拒绝，语音入口不冒充可发送 | `ChatWorkspaceModel.swift`、`DsmChatRepository.swift` |
| DS-01 · A/C | 下载任务列表、详情、进度/速度、网址或任务文件创建、目标目录 | 专用任务页、筛选与多选命令 | Activity 内 Download Station 分区；文件导入和目标目录选择 | `ServiceManagementModel.swift`、`ServiceManagementView.swift` |
| DS-02 · A/C | 暂停/继续/开始/删除，删除数据分支；官方基础设置 | 批量命令、设置页、结果回读 | Swipe 只用于可撤销低风险动作；删除数据必须显式确认 | 同上 |
| CM-01 · C | 概览、容器、映像、网络、项目、事件 | 模块专用分页/详情、键盘与多选 | NAS 管理下分区；iPad 列表-详情，iPhone 分层导航 | `ContainerManagerPane`、服务管理 Repository |
| CM-02 · C | 容器生命周期/删除、映像删除、网络创建/删除、Registry 搜索/标签/拉取 | 分步对话、后台任务状态 | 分步 Sheet、活动中心；内部写入口继续按能力与版本保护 | `ServiceManagementModel.swift` |
| VM-01 · C | 虚拟机、主机、存储、网络、映像、保护与事件读取 | 数据视图、详情与多选操作 | NAS 管理分区；iPad 多栏，iPhone 摘要优先 | `VirtualMachineManagerPane` |
| VM-02 · C | 基础创建/修改、电源/删除、网络修改/删除、映像删除、独立远程控制台 | 分步向导和可调整控制台窗口 | 分步 Sheet；控制台全屏、外接键盘和安全退出；不把桌面精确鼠标交互硬套到触屏 | `ServiceManagementModel.swift`、`ServiceManagementView.swift` |
| NAS-01 · A/C | 系统概况、性能趋势、更新检查/发布说明、存储/硬盘/外接存储/ZRAM | Dashboard + 原生图表/数据表 | 摘要卡 + 下钻；图表提供精确值与屏幕阅读器摘要 | `NasAdministrationModel.swift` |
| NAS-02 · A/C | 文件服务、终端、代理、接口、DDNS、区域时间、QuickConnect | 分类设置页、表单验证与写后回读 | Form 分组、渐进披露；可能断网/改时操作预告影响并提供恢复路径 | `NasAdministrationView.swift`、NAS Repository |
| NAS-03 · A/C | 硬件/休眠、UPS、防火墙基础控制、电源操作 | 危险操作与普通设置空间分离 | 危险操作置于详情底部；权限、确认、防重复与最终状态全部保留 | 同上、私有 API 记录 |
| NAS-04 · A/C | 套件、任务与运行记录、账号/群组、当前账号共享访问、进程、日志和连接 | 模块化表格、分页、筛选和详情 | 列表-详情、搜索筛选；隐私字段白名单不因屏幕小而放宽 | `NasSettingsPage`、NAS Repository |
| NAS-05 · A/B | 容量健康与共享/类型/所有者/大文件/时间/重复内容的统一存储分析 | 可取消分析、表格/图表与导出 | 前台发起、可取消、后台只保留安全进度；手机摘要、iPad 分析工作台 | `StorageAnalysisEngine` |
| SET-01 · A/B | 模块开关、语言、传输分块、本地占用与可再生缓存清理、诊断边界 | 设置页、系统主题、高对比与缓存管理 | Settings/Profile 入口、Dynamic Type、缓存清理；受保护数据永不列入清理 | `SettingsView`、本地化契约 |
| SYS-01 · A/B | Finder 只读云盘、按需读取、离线保留、缓存与后台驻留；`createItem`、`modifyItem`、`deleteItem` 返回 `featureUnsupported`，`enumerateChanges` 不承诺远端增量 | Cloud Files/资源管理器等价，延续当前实现并完成实机出口 | Files App 中只读 File Provider 为等价目标；若可靠变更枚举或 entitlement 未通过则以 App 内离线区明确降级 | `apple/Apps/DsmMac/FileProviderExtension/` |

## 7. UI/UX 共同设计系统

`ui-ux-pro-max` 检索结果只作为开发期输入。其 Web 字体、Bento 营销布局、GSAP 和夸张标题建议与本项目原生技术栈冲突，明确不采用；保留以下适合工具型 NAS 客户端的原则：

- 系统字体、系统图标和语义颜色优先，不引入 Web 字体或运行时设计依赖。
- Windows 采用 Fluent/WinUI 主题资源；Apple 采用 SwiftUI 系统材质与 SF Symbols。品牌色只用于主操作、选择和状态强调。
- 页面信息层级清楚，桌面可高密度但不可拥挤；移动端内容优先，次级技术信息渐进披露。
- 普通文本对比度至少 4.5:1；颜色之外同时使用文字、图标或形状表达状态。
- Apple 触控目标至少 44×44pt；Windows 同一界面同时支持鼠标、键盘、触控与可见焦点。
- 微交互通常 150–300ms，复杂转场不超过 400ms；动画表达层级或因果关系、可中断、不阻断输入，并服从系统“减少动态效果/关闭动画”。
- 超过约 300ms 的操作提供即时反馈，超过约 1 秒的内容加载使用稳定占位或分区进度，避免界面跳动。
- 所有新页面逐一验收加载、空内容、筛选空、错误和正常内容五态；错误必须说明发生了什么和下一步怎么做。

## 8. 总体架构与依赖顺序

```text
P0 基线冻结与功能账本
  └─ P1 请求 fixture、结果模型、领域接口与安全门
       ├─ P2 Windows / Apple 平台壳层和状态恢复
       ├─ P3 Files + 预览 + 传输
       │    └─ P4 Photos 文件系统照片库
       ├─ P5 Chat
       ├─ P6 Download / Container / VMM
       └─ P7 NAS 设置与统一存储
              └─ P8 系统集成（Cloud Files / File Provider / 后台 / 通知）
                    └─ P9 无障碍、性能、安全、真实设备与发布验收
```

依赖规则：

- P1 未稳定前不得并行复制写操作；UI agent 只能使用已验收的 mock/接口。
- Files/传输先于 Photos、Chat 附件和 Download 任务文件，因为后三者复用二进制、选择器、缓存和任务语义。
- 系统集成单独收口，不能和普通 UI 切片一起改 entitlement、工程文件或安装生命周期。
- Windows 与 Apple 轨可以并行，但 `contracts/**`、公共文档和本地化完整性检查由单一集成 owner 处理。
- 自动照片备份不是 macOS parity 依赖。它只能作为用户另行批准的移动增量，在 PhotoKit、后台模式和持久化迁移决策通过后实施；无论是否完成都不影响 P4 parity 状态。

## 9. Codex 多代理执行协议

### 9.1 主 agent 职责

主 agent 负责：

- 阅读规则、确认基线和维护本账本；
- 把工作拆成互不重叠的文件所有权；
- 先验收共享接口，再放行上层实现；
- 自己检查 `git diff`、请求 fixture、安全结果模型和所有测试输出；
- 让未参与实现的 agent 复核高风险切片；
- 只在证据满足完成定义时更新平台矩阵和状态。

主 agent 可以直接修改组合根、路由、共享资源或处理集成冲突，但不应在可独立委派时同时承担大块功能实现。

### 9.2 推荐波次

在四个并发槽（主 agent + 最多三个子 agent）下，推荐：

1. **调查波次**：三个子 agent 分别核查 macOS 基线、目标平台现状、契约/测试，全部只读。
2. **实现波次**：两个或三个子 agent 各自拥有独立功能目录和测试文件；共享接口、Shell 和资源由主 agent 或单一集成 agent 持有。
3. **验证波次**：至少一个未参与实现的 agent 做只读差异审查，一个 agent 运行目标测试；主 agent 复核结果并决定返工或合并下一波次。

若本地化资源仍是单文件，先由资源 owner 分配并写入双方资源键，功能 agent 只引用已经存在的键。不得让多个 agent 同时编辑同一 `.strings` 或 `.resw`。

### 9.3 子 agent 任务模板

```text
目标：一个可独立验收的用户结果
基线：macOS 源码/测试/契约的精确路径
允许修改：逐个列出文件或独占目录
禁止修改：Mac、Android、共享热点及用户现有改动
前置接口：已冻结的协议、模型、fixture 和资源键
安全要求：确认/权限/防重复/回读/取消语义
完成条件：代码、五态、双语、无障碍、测试
必须运行：精确命令
交接：改动、决策、结果、失败、风险、下一步、git status
```

## 10. 跨端共同验收矩阵

| 维度 | Windows | iPhone | iPad |
| --- | --- | --- | --- |
| 构建 | Windows SDK 下 Debug/Release，x64/arm64 | 无签名模拟器 + 正式签名真机 | 同 iPhone，另含多窗口/分屏配置 |
| 输入 | 鼠标、键盘、触控、快捷键、拖放 | 触控、系统返回、分享、旋转 | 触控、键盘、指针、拖放、分屏/台前调度 |
| 可访问性 | Narrator、键盘焦点、高对比、100–200% 缩放、Accessibility Insights | VoiceOver、最大动态文字、按钮形状、减少动态效果 | 同 iPhone，另检查多栏焦点与硬件键盘 |
| 视觉 | 浅色/深色、高对比、窄/宽窗口 | 小/大屏、浅/深色、纵/横屏、安全区 | 纵/横屏、紧凑/常规宽度、并列 App |
| 生命周期 | 窗口隐藏/恢复、托盘、休眠、重启、安装/卸载 | 前后台、系统终止、低电量、网络切换 | 同 iPhone，另含多个 Scene 的隔离恢复 |
| 网络 | 局域网、公网直连、QuickConnect 中继、证书变化 | Wi-Fi/蜂窝切换和后台调度 | 同 iPhone |
| DSM | 普通/管理员、套件有/无、只读/可写、当前记录 build | 同 Windows | 同 Windows |
| 写操作 | 成功、部分成功、权限拒绝、提交未确认、取消后复查 | 同 Windows | 同 Windows |

任何平台通过都不能替代另一平台或另一 DSM build 的验证。实机记录只使用 `lab-a`、`lab-b` 等稳定别名并遵循最小披露。

## 11. 每阶段质量门

每个功能波次合入下一阶段前，主 agent 至少执行并记录：

```bash
git diff --check
python3 tools/localization/check_localization.py
swift test --package-path apple
xcodebuild -project apple/Apps/DsmMac/DsmMac.xcodeproj -scheme DsmMac -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

只改 Windows 时可以不执行 Apple 构建。仅改移动 App 且未触碰共享 Package 时，可不执行上面的 DsmMac 构建；公共契约或 `apple/Packages/**` 改动必须同时执行共享测试和 DsmMac App + File Provider Extension 的无签名构建。Windows 还必须在 Windows 环境执行专项计划中的 .NET/WinUI 命令；Apple 移动端必须分别使用 iPhone 与 iPad Simulator 执行构建/UI 状态检查。真实系统集成按专项签名出口执行。

质量门还包括：

- 没有硬编码用户文案、秘密、真实路径或未脱敏响应；
- 没有用 UI 字符串、翻译或图标判断业务状态；
- 没有新增无限列表、无界缓存或主线程大文件解码；
- 高风险操作没有自动重试，提交未确认时只刷新最终状态；
- 内部只读失败不阻断无关模块，内部写在未知环境默认关闭；
- 没有通过跳过测试、降低断言或删除回归来制造通过。

## 12. 文档同步与交付

每个达到新验证等级的切片按实际影响更新：

- 本文的功能账本状态；
- 对应 Windows 或 Apple 移动专项计划；
- [平台功能矩阵](../progress/PLATFORM_MATRIX.md)；
- [当前开发进度](../progress/STATUS.md)中的实时结果；
- 相关功能专项计划、请求 fixture、私有 API 兼容矩阵和 DSM 兼容矩阵。

如果任务未完成需要交接，除根 `AGENTS.md` 规定内容外，还必须指出当前功能 ID、账本状态、已冻结接口、下一 owner 的允许文件和不能触碰的用户改动。

## 13. 参考资料

- [总体架构](../architecture/ARCHITECTURE.md)
- [原生技术栈 ADR](../architecture/decisions/0002-native-stacks.md)
- [官方 API 优先 ADR](../architecture/decisions/0003-official-api-first.md)
- [安全与隐私基线](../security/SECURITY_BASELINE.md)
- [请求契约与写操作结果计划](REQUEST_CONTRACT_AND_MUTATION_RESULT_PLAN_ZH.md)
- [桌面云盘专项计划](NATIVE_DSM_DESKTOP_CLOUD_DRIVE_DEVELOPMENT_PLAN_ZH.md)
- [Apple Replicated File Provider](https://developer.apple.com/documentation/fileprovider/replicated-file-provider-extension)
- [Apple 后台下载](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- [Microsoft WinUI NavigationView](https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/navigationview)
- [Microsoft Cloud Files API](https://learn.microsoft.com/en-us/windows/win32/cfapi/cloud-files-functions)
