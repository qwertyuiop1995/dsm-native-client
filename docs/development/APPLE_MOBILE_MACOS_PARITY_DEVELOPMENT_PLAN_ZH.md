# iPhone 与 iPad 对齐 macOS 功能开发计划

- 状态：规划基线，尚未开始实施
- 上位计划：[macOS 功能对齐总控计划](MACOS_PARITY_REPLICATION_MASTER_PLAN_ZH.md)
- 目标技术栈：Swift 6、SwiftUI、URLSession、Apple 系统框架
- 最低系统基线：保持当前 iOS/iPadOS 17，不在本计划中提高

## 1. 为什么共用一份计划

当前 `DsmMobile` 是一个 Universal Target：

- `TARGETED_DEVICE_FAMILY` 同时包含 iPhone 与 iPad；
- 使用同一个 Bundle ID、源码目录、Keychain、安全会话和本地化资源；
- 共同依赖 `DsmCore`、`DsmNetwork`、`DsmLocalization`；
- 业务契约、权限、安全写操作和网络行为不应按设备复制两套。

因此本文使用三条泳道：

1. **共享业务与平台能力**：领域、Repository、任务、权限、安全和状态恢复。
2. **iPhone 紧凑体验**：五个顶层入口、单列导航、触控与全屏内容。
3. **iPad 宽屏生产力体验**：多栏、键盘、指针、拖放、多窗口与动态宽度。

任何功能必须同时通过共享业务出口和对应设备形态出口，不能用 iPhone 通过代替 iPad，也不能用横屏 iPad 截图代替 Split View/Stage Manager 验证。

## 2. 当前 DsmMobile 基线

### 2.1 已有能力

- HTTPS/QuickConnect 登录、OTP 字段、资料保存、Keychain 可选密码、会话恢复和自动登录基础链路。
- 九个模块入口：文件、照片、Chat、Download Station、Container、VMM、NAS、传输、设置。
- iPhone 使用 `NavigationStack`，常规宽度使用基础 `NavigationSplitView`。
- 文件基础列表/搜索/新建文件夹/重命名/单项删除。
- Download Station 基础列表、URL 创建、暂停/继续/删除。
- Container/VMM 基础资源列表和少量操作。
- NAS 概况、存储、套件、账号、日志、连接的浅层只读摘要。
- 英语/简中共享资源和基础可访问性标签。

### 2.2 不能视为已对齐的部分

当前主要源码集中在 `MobileRootView.swift`、`MobileAppModel.swift`、Keychain 和 App 入口，测试主要覆盖入口与登录恢复。以下仍是占位或浅层切片：

| 模块 | 真实差距 |
| --- | --- |
| 登录/安全 | 缺 macOS 等价的自签证书核对、按 NAS pin、证书变化阻断、可取消连接和能力不可用原因 |
| Files | 缺分页、视图/排序/筛选、多选、预览、上传下载、复制移动、压缩解压、收藏/最近、远程位置、分享链接、回收站和传输 |
| Photos | 当前只是按扩展名筛选 `FileItem` 并显示占位图，尚未使用共享 `PhotoLibraryRepository` |
| Chat | 只有会话列表，没有消息、发送、实时、附件、群组或提醒等工作流 |
| Download | 缺目标目录、任务文件、设置、详情和完整结果语义 |
| Container/VMM | 缺 Registry 拉取、typed 详情、VMM 创建/编辑和控制台 |
| NAS | 只有少量只读摘要，远少于 macOS `NasSettingsPage` 范围 |
| Transfers | 明确为空状态占位，没有客户端任务引擎、后台恢复或通知 |
| iPad | 仅以 horizontal size class 分支，没有按实际窗口宽度、Scene、多窗口、键盘、指针和拖放设计 |

静态源码中尚未形成完整的 PhotoKit/PhotosPicker、系统文件导入导出、后台 URLSession/BGTask、本地通知、QuickLook/AVKit/PDFKit 移动查看器、WKWebView 控制台和多窗口实现。现有入口不能用来推断这些能力已存在。

## 3. 复刻口径与能力边界

### 3.1 macOS 是行为基线，不是移动页面模板

移动端需要保留：

- 用户可以完成的目标；
- API 能力和版本门控；
- 权限、确认、防重复、取消和回读；
- 部分成功、未知结果、网络中断和会话过期的语义；
- 按 NAS 隔离的资料、状态、草稿、缓存和任务。

移动端需要替换：

- 侧栏/菜单栏 → Tab、Stack、SplitView 和 Profile 菜单；
- 右键/悬停/双击 → 可见按钮、上下文菜单、长按与标准点按；
- 框选/Ctrl 多选 → Edit 模式与底部动作栏；
- 可调整预览窗口 → iPhone 全屏查看器、iPad 详情/独立 Scene；
- Finder/常驻进程 → Files App Provider、系统后台传输和可恢复状态；
- 桌面大表格/横向标签 → 分组钻取列表、摘要卡、筛选和详情 Inspector。

### 3.2 必须如实保留的 macOS 边界

- **照片**：macOS 当前通过公开 File Station 扫描个人/共享照片目录，提供时间线和文件夹式相册；不等同完整 Synology Photos。人物、地点、标签和真正相册实体等内部候选继续关闭。
- **Chat**：内部能力当前仍是 degraded；加密会话拒绝明文降级，语音未进入完整发送流程。移动端不能扩张为已支持。
- **Container**：全部属于内部 API，当前证据 degraded；未知环境写入口关闭。
- **VMM**：读取和少量写有内部契约边界；创建、编辑、网络写和删除不能因 macOS 有 UI 就宣称已实机可用。
- **NAS 管理**：多项危险写缺行为验证；外接存储、ZRAM、进程、电源计划摘要等保持只读，系统升级安装、套件安装/升级和管理员 ACL 矩阵保持关闭。
- **File Provider**：macOS 是只读枚举、按需读取和离线缓存，创建/修改/删除不支持，也没有远端增量同步承诺；移动端等价目标同样只读。

## 4. 审批门与平台权限

以下能力会修改权限、entitlement、Target、Info.plist、签名边界、数据格式或持久化结构，实施前必须单独说明必要性、影响、迁移和回滚，并取得用户明确同意：

| 决策门 | 可能变更 | 未批准时的安全降级 |
| --- | --- | --- |
| 自动照片备份 | PhotoKit 使用说明、照片权限、后台处理标识/模式 | 只提供 `PhotosPicker` 的用户主动选择导入 |
| 后台文件传输 | 后台 `URLSession` 的稳定 identifier、任务映射与恢复状态 | 保持前台文件传输；离开前明确提示，不伪装后台运行 |
| 照片发现/准备 | `BGTaskSchedulerPermittedIdentifiers`、Background Processing mode | 不影响已文件化的后台 URLSession；仅把照片发现/准备降为前台 |
| Files App 集成 | 新 File Provider Extension Target、App Group、共享 Keychain access group、entitlement、签名 | App 内文件浏览/离线区 + 系统导入导出；`SYS-01` 保持部分对齐，不能标记完成 |
| 本地通知 | 运行时通知授权与隐私文案 | App 内活动中心和状态反馈正常工作 |
| 移动端持久化 schema | SceneState、任务库、照片游标、Provider domain 等数据格式 | 只允许内存原型，不把不可迁移状态写入设备 |
| 多窗口 | `WindowGroup`/`openWindow`、Scene manifest、`UIApplicationSupportsMultipleScenes`、restoration activity | iPad 保留单窗口 SplitView，不影响核心业务 |

不新增第三方依赖。上述审批只允许实现计划中明确的能力，不授权真实 NAS 危险写或改变 Bundle ID/最低系统版本。

持久化 schema 决策必须先记录版本、迁移、回滚、旧版本兼容、损坏恢复，以及卸载、删除 profile、退出登录时分别清理什么。File Provider 的 App Group 只保存 opaque domain/profile 元数据；SID、Token、Cookie、证书 pin 和密码只能进入共享 Keychain access group，不能进入 App Group、URL 或日志。

## 5. 目标信息架构

### 5.1 iPhone：五个顶层入口

使用最多五个带图标与文字的顶层 Tab，每个 Tab 有独立 `NavigationStack`、路径、筛选、滚动和草稿状态：

1. **文件**：共享目录、收藏/最近、远程位置、分享链接、回收站。
2. **照片**：个人/共享空间、时间线、文件夹式相册。
3. **Chat**：会话、消息和成员/会话详情。
4. **活动**：App 传输、NAS 文件任务、Download Station，以来源分段而非混成同一种任务。
5. **更多**：NAS 管理、Container、VMM 和应用设置。

全局搜索不能在各模块之间偷换语义；每个 Tab 自己管理搜索和筛选。Profile 菜单是 NAS/profile 切换、连接状态和退出登录的唯一入口；“更多”负责应用设置和管理模块。危险操作不放在主导航旁边。

### 5.2 iPad：按实际可用宽度自适应

- 常规宽度使用 `NavigationSplitView`：模块/位置侧栏 → 列表或内容 → 详情/Inspector。
- 紧凑宽度（Split View、Slide Over 或较窄 Stage Manager 窗口）自动折叠成 Stack；不能用 `UIDevice.userInterfaceIdiom == .pad` 决定多栏。
- 同一层级不同时堆叠 Tab Bar 与 Sidebar；共享 RouteModel 将同一目的地映射到紧凑或常规容器。
- 多窗口后段支持文件查看、Chat 会话或 VMM 控制台等明确场景，每个 Scene 单独保存当前 NAS、导航和草稿；凭据与后台任务仍由进程级安全协调器统一管理。

### 5.3 交互映射

| 用户目标 | iPhone | iPad |
| --- | --- | --- |
| 浏览深层目录 | 单列 Stack、系统返回、可点路径菜单 | Sidebar + 列表 + 详情，紧凑时自动折叠 |
| 多选文件/照片 | Edit + 底部动作栏，选择计数可读 | 同左，另支持键盘 Shift/Command 与指针 |
| 复制/移动 | 目标目录选择 Sheet | 目标选择器 + 可选拖放；拖放始终有可见替代 |
| 项目菜单 | 44pt 更多按钮/长按菜单 | 上下文菜单、键盘命令和 Toolbar |
| 图片/媒体预览 | 全屏、捏合、左右切换、底部工具栏 | 详情区或独立窗口，支持键盘前后与 Inspector |
| 属性/元数据 | 分组 Sheet | 右侧 Inspector，可收起 |
| 长表单/向导 | 全屏或大 Sheet，分步显示 | 定宽 Form Sheet 或详情列，保留步骤状态 |
| NAS 危险操作 | 详情底部、影响摘要、确认 Sheet | 同左，不因宽屏减少确认 |
| VMM 控制台 | 横屏友好的全屏 WKWebView、可见退出 | 详情/独立 Scene、外接键盘和指针 |
| 系统分享 | ShareLink/Activity Sheet | 同左，可使用拖放到其他 App |

### 5.4 全局交互与动效合同

- 所有触控目标至少 44×44pt，相邻目标保留足够间距；主操作不被 Safe Area、键盘或底部 Sheet 遮挡。
- 只使用系统字体、SF Symbols、语义颜色和系统材质；普通文字对比度至少 4.5:1，状态不能只靠颜色表达。
- 动效优先 SwiftUI 原生转场，通常 150–300ms、可中断且只表达层级或操作因果；优先动画 `opacity`/`transform`，避免大范围布局抖动。
- 开启 Reduce Motion 时取消视差、弹跳和空间位移，以短淡入淡出或无动画替代；动画不能阻断输入。
- 长按、Swipe、拖放和捏合都必须有可见按钮、菜单或键盘命令作为等价路径；不能把隐藏手势作为唯一入口。
- 每个子 agent 的完成出口都必须覆盖浅色/深色、Dynamic Type、VoiceOver、旋转和紧凑/常规宽度，不能留到 M9 才第一次检查。

## 6. 目标代码结构与状态边界

先在 DsmMobile App 内建立功能目录，不立即改变 Swift Package target：

```text
apple/Apps/DsmMobile/Sources/
  AppShell/
    AdaptiveShell.swift
    AppDestination.swift
    SceneState.swift
  Session/
    MobileSessionCoordinator.swift
    CertificateReviewState.swift
    ProfileWorkspaceStore.swift
  CommonUI/
    PageStateView.swift
    MutationFeedbackView.swift
    AdaptiveInspector.swift
  Features/
    Files/
    Photos/
    Chat/
    Activity/
    Services/Downloads/
    Services/Containers/
    Services/VirtualMachines/
    Administration/
    Settings/
  Platform/
    Documents/
    Photos/
    Background/
    Notifications/
    FileProvider/
    Windowing/
```

规则：

- `MobileAppModel` 在 M0 先由单一 agent 机械拆分；迁移期间可保留兼容 facade，但新功能不得继续塞入全局模型。
- 每个 Feature 有自己的 `@MainActor` ViewModel、Route、PageState 和测试，不直接持有其他 Feature 的 UI 状态。
- 进程级 actor 负责安全会话、稳定目标写操作锁和任务注册；Scene 只保存当前 NAS、导航、选择、筛选与草稿引用。
- Profile 切换前由任务协调器判断哪些任务可安全转后台、暂停或必须阻止切换；退出登录与切换 NAS 保持不同语义。
- `DsmCore`/`DsmNetwork` 只做向后兼容扩展。若至少两个 Apple 客户端确需共享纯业务编排，再评估启用现有 `DsmFileFeature`/`DsmTransferFeature` 目录；修改 `Package.swift` 前先取得工具链变更批准。
- App UI 不解析原始 JSON，不读取翻译来判断状态，不直接拼接 API 参数。

## 7. 共享安全协调器

当前全局 `actionInProgress` 只能阻止一个页面同时操作，不能作为危险写保护。目标流程统一为：

```text
能力/版本检查
  → 权限、目标存在和当前状态预检
  → profile + operation + stableTarget 锁
  → 展示目标与影响并确认
  → 只提交一次
  → 处理提交前/提交后取消
  → 最终状态或语义回读
  → MutationResult + 通俗反馈
```

要求：

- 提交未确认、网络超时或取消发生在提交后时，只刷新最终状态，绝不自动重放。
- 批量操作保留失败或未知目标，只有确认成功项从选择中移除。
- 跨 NAS 移动只有目标端全部确认后才删除源；部分复制成功时不扩大源删除范围。
- 重启/关机等无法常规回读的操作使用“请求已确认 + 预期离线状态”模型，不能把连接中断等同成功。
- 内部只读失败只影响当前分区；内部写在未知环境默认关闭。

## 8. 后台、通知与隐私边界

### 8.1 客户端字节传输

- 后台上传和下载使用独立、稳定标识的后台 `URLSession`；上传必须先形成受保护的本地文件，不能依赖内存 `Data` 或流在进程退出后继续。
- 系统决定实际调度时机并可暂停或中断；用户从多任务界面强制结束 App 会取消后台 session 任务，权限撤销、低电量、低数据或存储不足也都是正常状态分支。
- App 重启后用同一 session identifier 重新关联系统任务，并以 `profileId + taskId` 恢复展示。
- 认证、证书 pin、QuickConnect 重定向和后台 session 的兼容性先做合成服务/专用 NAS 原型；验证前不能承诺后台稳定传输。
- File Station 上传如果没有官方 offset 契约，只能提供“从头重试”；下载仅在严格验证 Range 和片段后提供继续。

### 8.2 NAS 服务器任务

Download Station 和 File Station BackgroundTask 在 NAS 上运行，App 只轮询状态。它们与本地字节传输分源持久化；不能把“NAS 仍在处理”显示成本机后台上传。

### 8.3 通知

- 成功/失败通知默认不显示 NAS 名称、账号、文件名、路径、Chat 正文或附件。
- 用户拒绝通知时，活动中心仍完整工作。
- 无 APNs 服务端或 NAS 推送整合时，Chat 只保证前台 Socket.IO 和轮询降级；BGRefresh 是尽力而为，不能承诺后台即时消息。
- 提醒可以使用本地通知，但到期内容默认隐私化，点击只携带不含秘密的 opaque route ID。

## 9. 分阶段实施 DAG

```text
M0 基线、黄金测试、机械拆分
  └─ M1 Session + Adaptive Shell + Scene State
       └─ M2-A Mutation / Transfer 接口、状态机、fixture 与测试冻结
            ├─ M2-B Transfer / Background Prototype
            ├─ M3 Files + Preview（最终出口依赖 M2-B 集成证据）
            │    └─ M4 Photos（NAS 库 → 主动导入；自动备份另行审批）
            ├─ M5-A Chat 核心
            ├─ M6 Downloads / Containers / VMM
            └─ M7 NAS Administration / Storage Analysis
  M3 + M4-B + M5-A 出口通过 ─ M5-B Chat 附件
  M2-B 与 M3–M7 核心完成 ─ M8 iPad 生产力 / 多窗口 / File Provider 决策门
                         └─ M9 真机、真实 NAS、安全、性能和发布验收
```

### M0：基线、测试护栏与机械拆分

- 固定 macOS 参考提交和移动端能力账本；标注同等实现、移动等价、外部阻塞、未验证和不适用。
- 为现有登录、模块选择和基础写操作补行为测试，防止拆分时回退。
- 单一 owner 拆分 `MobileRootView.swift` 与 `MobileAppModel.swift`，只移动代码和建立注入点，不同时新增功能。
- 在 `project.yml` 中由唯一工程 owner 增加必要的单元/UI 测试 Target；不手改生成工程。
- 建立 CommonUI 五态容器、语义颜色/间距/动效 token 和双语资源键流程。
- 把 5.4 的触控、Safe Area、对比度、动效、Reduce Motion 与可见替代动作固化为组件测试清单，后续 feature 不得自建冲突规则。

出口：现有行为测试不退步，生产源码按功能目录分离，Shell/资源/工程文件都有唯一 owner。

### M1：会话、安全与自适应 Shell

- 多 NAS 新建/删除/选择/重命名/排序，切换 NAS 与退出登录分离。
- QuickConnect 路由提示、可取消连接、会话恢复和能力不可用原因。
- 自签名证书首次核对、按 profile pin、证书变化阻断；只有结构/有效期合格的叶证书可固定，变化时展示旧/新指纹，relay 只接受系统信任，路由发现阶段不发送登录凭据。
- iPhone 五 Tab，每个独立 Stack；iPad SplitView 按实际宽度折叠。
- SceneState 按 profile 和 Scene 隔离导航、筛选、选择与草稿。
- 外部通知/深链只解析 opaque route，不接受主机、路径、会话或任意 URL 参数。

出口：紧凑/常规宽度、系统返回、会话过期、证书变化和切换 NAS 均有测试；最大动态文字不丢主操作。

### M2：写操作、传输和后台原型

#### M2-A：先冻结契约

- 实现稳定目标级 `MutationCoordinator` 和 `MutationResult` UI。
- 冻结 App 字节任务与 NAS 服务任务的分源模型、暂停/取消/重试/恢复状态机、合成 fixture 和错误映射测试。
- 主 agent 独立复核目标锁、防重复、提交未确认与写后复查语义；出口通过前，M2-B、M3、M5-A、M6、M7 不得开始写实现。
- M2-A 出口通过后，后续分支可针对冻结接口与 fake 并行；M3/M6 的最终出口仍必须取得 M2-B 的真实集成证据，不能以 mock 通过宣布完成。

#### M2-B：实现传输与平台原型

- 在持久化 schema 获批后按 NAS 保存任务；未获批时只做内存原型。
- 系统 Document Picker/Exporter、分享 Sheet 与临时文件生命周期。
- 在不新增权限时完成前台传输；后台 URLSession、BGProcessing 和通知分别按各自决策门原型，拒绝 BGProcessing 不得把已经验证的文件型后台传输一并降级。
- 清理只删除可再生缓存，任务元数据、登录资料、用户导出和离线保留内容不参与。

出口：系统终止、用户取消、提交未确认、网络切换、空间不足和会话失效都有确定状态；没有假断点或自动重放。

### M3：File Station 与预览

- 共享/目录分页、目录历史、列表/网格、排序/分组/筛选、递归搜索和状态恢复。
- 收藏、最近、远程位置、分享链接、回收站和当前账号可见空间。公开 VirtualFolder 只读浏览与内部 `SYNO.FileStation.Mount` 管理分开；创建、修改、断开在未知版本关闭，密码不进入 URL/日志，并保留确认、防重复和最终回读。
- Edit 多选、新建/空文件、重命名、详情、目录统计。
- 上传、文件/文件夹/批量下载、复制/移动/跨 NAS、同名处理、压缩解压和撤销。
- 图片/PDF/文本/音视频原生查看器；图片切换/缩放，Range 媒体，文本编辑/格式整理和未保存保护。
- iPad 键盘、指针、Inspector 和拖放；iPhone 始终有非手势替代。

出口：五态、分页、大文件、弱网、前后台、缓存上限、格式不支持和危险写结果均有自动化/设备计划证据。

### M4：文件系统照片库与移动增强

#### M4-A：复刻 macOS NAS 照片体验

- 使用共享 `PhotoLibraryRepository`，实现个人/共享空间、文件夹、时间线、文件夹式相册、分页、搜索和年/月定位。
- 真实缩略图、可见窗口优先和有限预取；滚动/离页/切换 NAS 释放旧任务。
- 图片/视频/Live Photo 配对、EXIF 白名单、沉浸查看器。
- 上传、导出、分享、移动、删除和回收站恢复复用 M2/M3。

#### M4-B：用户主动导入

- 优先使用 `PhotosPicker` 选择明确项目，不为了单次导入索取整库权限。
- 保留拍摄日期/方向等安全元数据，无法保留的字段在确认前说明。
- 原图导出到受控临时文件，再进入统一传输任务；完成/取消/失败后清理临时副本。

#### M4-C：可选自动备份（审批后）

- 支持完整、有限、拒绝和授权撤销；使用稳定本地 asset ID 与增量游标，不记录照片正文到日志。
- 用户选择 NAS 目标、网络/电量/充电策略和是否包含视频；没有安全会话时不在后台排队。
- 先把资源文件化，再交给后台 URLSession；BGProcessing 仅用于发现/准备，不能承诺准时。
- 去重必须有可解释策略；不能只凭文件名认定已备份。

M4-C 是移动增量，不属于 macOS parity 完成条件。该 App 不提供“只删除本机副本、保留 iCloud 原件”的释放空间入口；iCloud Photos 的设备占用交给系统“优化储存空间”。也不在后台自动删除系统照片图库项目。

语义出口：整个模块仍称文件系统照片库，不宣传人物/地点/真正 Synology Photos 相册能力。

### M5-A：Chat 核心

- 会话/用户/消息/成员 typed 状态；首次单聊与非加密私人群聊。
- 消息分页、草稿、文字/Emoji、失败重试、本地置顶/已读、删除本人消息和关闭会话。
- 消息转发、服务端消息置顶/取消置顶按独立能力 gate；语音发送和完整加密实现不在当前 parity 范围。
- 前台 Socket.IO + 轮询降级，重连去重，进入后台后释放不必要连接。
- 提醒、纯文字定时消息和投票当前 macOS 范围；每个内部写能力独立 gate。
- iPhone 会话 → 消息 Stack；iPad 会话列表 + 消息 + 可选详情，返回保持草稿和滚动锚点。

出口：未记录 DSM build + Chat Server 完整版本时写入口关闭；加密会话明确拒绝，无 APNs 时不承诺后台即时消息。核心出口不依赖附件。

### M5-B：Chat 附件

- 等 M3 预览/传输与 M4-B PhotosPicker adapter 接口冻结后，再接入 Photos/Files 单附件选择、上传进度/取消/重试、保存和图片预览。
- 临时文件、通知和诊断不包含消息、真实路径或附件正文；弱网/重试/切换会话不重复发送。

出口：iPhone/iPad 的选择器、后台切换、取消和失败恢复有独立测试；附件能力不能反向阻塞纯文字 Chat。

### M6：Download Station、Container Manager 与 VMM

Download Station：任务列表/筛选/详情、目标目录、URL/magnet/任务文件、暂停/继续/删除数据分支和官方基础设置。

Container Manager：概览、容器、映像、网络、项目、事件；生命周期/删除、Registry 搜索/标签/拉取、网络创建/删除，分区独立降级。

VMM：机器、主机、存储、网络、映像、保护、事件；三步基础创建、停止态编辑、电源/删除、网络编辑/删除、映像删除和短生命周期控制台。控制台先过独立安全原型门：精确 origin allowlist，直连按 profile pin、中继按系统信任，SID/会话材料只以内存 Cookie 注入且不进入 URL/日志，使用 `WKWebsiteDataStore.nonPersistent()`，阻止任意跳转、弹窗和下载，并在关闭或进入后台时清理会话；验证前入口保持关闭。

移动转换：iPhone 使用分层列表与分步 Sheet；iPad 使用列表-详情。VMM 控制台 iPhone 全屏、iPad 可独立 Scene，均提供外接键盘、安全退出和可解释触控映射。

出口：内部能力按操作和版本 gate；Compose/终端/高级迁移等 macOS 未实现能力继续排除。

### M7：NAS 管理与统一存储

按用户目标分组，不复制 21 个横向标签：

- **概况与健康**：系统、性能趋势、更新检查/说明、连接方式。
- **存储**：池/卷/硬盘/SMART、外接存储、ZRAM、统一存储分析。
- **网络与访问**：文件服务、终端、代理、接口、QuickConnect、DDNS、区域时间。
- **设备与保护**：硬件/休眠、UPS、防火墙、电源。
- **用户与服务**：套件、任务、账号/群组、当前账号共享访问。
- **活动与诊断**：进程、日志分页、当前连接。

iPhone 使用摘要 → 分类 → 详情；iPad 使用 Sidebar + 列表 + 详情。图表必须提供精确值、单位、图例和屏幕阅读器摘要，不能只靠颜色。

出口：只读边界和 disabled 能力与 macOS 一致；可能断网、改时、重启或关机的操作有额外影响提示和专用测试环境证据。

### M8：iPad 生产力、多窗口与 Files App

- 所有核心模块完成紧凑/常规宽度切换，Split View/Stage Manager 缩放不丢状态。
- 统一键盘命令、指针状态、上下文菜单、拖放和可见替代动作。
- 经批准后增加多窗口：文件/照片查看、Chat 会话、VMM 控制台等明确 Scene。
- 经批准后增加只读 Replicated File Provider：浏览、按需下载、系统离线保留、释放本地空间、认证恢复和域清理。
- File Provider 创建/修改/删除全部拒绝；实现 working set、持久化同步锚点、`enumerateChanges` 和 `signalEnumerator`。没有 DSM 增量接口时，必须以分页快照差异形成可复验锚点，不能仅靠访问/手动刷新掩盖过期内容。
- 远端变更枚举原型、域删除/重建、认证恢复、签名和长时间刷新全部通过后才能启用 Provider；否则继续使用 Document Picker/App 内离线区。共享会话遵守第 4 节的 App Group/Keychain 边界。

出口：没有 entitlement/签名实机证据时标记 `SIGNING_REQUIRED`；App 内离线区不能冒充 Files App 已对齐。

### M9：稳定化与发布验收

- iPhone/iPad Debug、Release、Archive、签名、安装、启动和升级。
- 全量双语、本地化格式、五态、VoiceOver、Dynamic Type、减少动态效果、浅/深色。
- 大目录、大图库、长会话、长时间媒体、后台任务和存储压力。
- 真实 NAS 的连接方式、权限、套件版本、危险写和未知结果。
- 隐私说明、权限撤销、缓存/临时文件清理和诊断最小披露。

## 10. Codex 子 agent 文件边界

### 10.1 主 agent 监管、唯一集成 owner 写入

主 agent 不与实现 agent 同时写这些热点；每一波只可明确委派一个集成 owner，主 agent 负责独立复核和最终验收：

- 能力账本、阶段 DAG 与验收结论；
- `project.yml`、Info.plist、entitlements、Target、Package.swift 和生成工程；
- AppShell 路由与组合根；
- 共享领域/Repository 协议、请求契约和持久化 schema；
- 两份 Apple 本地化资源及跨端进度/平台矩阵；
- 全量构建、Mac 回归和最终差异审查。

### 10.2 推荐并行目录

| 波次 | Agent A | Agent B | Agent C |
| --- | --- | --- | --- |
| 1 | `Session/**` | 被委派的唯一集成 owner：`AppShell/**` + Scene state | `CommonUI/**` + 只读测试审查 |
| 2-A | 本波唯一集成 owner：Mutation/Transfer 接口与 fixture | 状态机和结果语义 Tests | 独立安全审查；通过出口后才开 2-B |
| 2-B | M2-B：Activity/Transfer/Platform Documents | M3：Files/Preview | M5-A：Chat 核心 |
| 3-A | M4：Photos + Photo adapter | M6：Downloads/Containers/VMM | M7：Administration/Storage |
| 3-B | M5-B：Chat 附件 | 对应 Photos/Chat/Transfer 回归测试 | 独立 QA；不得抢改生产文件 |
| 4 | iPad commands/drag/drop/window | Background/notifications | 可访问性/本地化/性能只读复核 |

在 M0 拆分前，不得让多个 agent 同时修改 `MobileRootView.swift` 或 `MobileAppModel.swift`。本地化 agent 是资源文件唯一 owner；功能 agent 先获得资源键或提交键值清单。工程 owner 只通过 `project.yml` 更新生成配置。

高风险切片（证书、后台、跨 NAS、NAS 照片删除、File Provider、Chat/Container/VMM/NAS 内部写）必须由未参与实现的 agent 做只读对抗复核，主 agent 再决定是否进入真机/真实 NAS 验收。

## 11. 自动化与构建门禁

从仓库根目录执行共享门禁：

```bash
git diff --check
python3 tools/localization/check_localization.py
python3 tools/contract-validation/validate_fixtures.py
python3 tools/request-contract/validate_contracts.py
swift test --package-path apple
```

由唯一工程 owner 生成并构建移动工程：

```bash
(
  cd apple/Apps/DsmMobile
  xcodegen generate

  xcodebuild \
    -project DsmMobile.xcodeproj \
    -scheme DsmMobile \
    -sdk iphonesimulator \
    -configuration Debug \
    CODE_SIGNING_ALLOWED=NO \
    build
)
```

单元/UI 测试分别选择当前 Xcode 实际安装的 iPhone 与 iPad Simulator，不在文档锁死可能过期的设备名：

```bash
xcodebuild -project apple/Apps/DsmMobile/DsmMobile.xcodeproj -scheme DsmMobile \
  -destination 'platform=iOS Simulator,name=<available iPhone>' test

xcodebuild -project apple/Apps/DsmMobile/DsmMobile.xcodeproj -scheme DsmMobile \
  -destination 'platform=iOS Simulator,name=<available iPad>' test
```

若修改 `apple/Packages/**`，还必须执行以下无签名 DsmMac App + File Provider Extension 构建，证明只读基线没有被共享代码破坏：

```bash
xcodebuild -project apple/Apps/DsmMac/DsmMac.xcodeproj \
  -scheme DsmMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

模拟器通过不能替代真机、签名、后台和 File Provider 验收。

## 12. 自动化覆盖要求

- 每个 Feature 的状态机、分页、筛选、取消、恢复和错误映射单元测试。
- 每个写操作的成功、部分、拒绝、提交未确认、提交后取消和回读不一致。
- 合成请求 fixture 验证 API 名、版本、方法、路径、参数、认证材料位置和 no-retry 策略。
- iPhone/iPad UI 测试覆盖五态、导航返回、Tab/Sidebar 状态、确认框和动态文字主流程。
- 后台 URLSession 用受控服务验证重建、文件型上传、系统取消原因和结果关联。
- PhotoKit adapter 覆盖完整/有限/拒绝/撤销、iCloud-only/优化储存资源、共享图库归属、增量游标和重复候选；有限权限只处理已授权项目。
- File Provider 测试覆盖 working set、锚点持久化、分页快照差异、`enumerateChanges`、`signalEnumerator`、域重建和过期内容收敛。
- Scene 测试证明不同窗口的 NAS、Route 和草稿不串用。
- 性能测试覆盖大目录、约十万项照片索引场景、长聊天、缓存上限和快速滚动取消。

## 13. 真机与真实环境矩阵

### 13.1 设备与界面

- 小屏与大屏 iPhone，纵屏和横屏。
- iPad mini 级、常规 11 英寸级和大屏级；纵/横屏。
- Split View 各比例、Slide Over、Stage Manager 窄/宽窗口和外接显示器（若项目支持）。
- 浅/深色、英语/简中、最大动态文字、粗体文字、按钮形状、减少动态效果和 VoiceOver。
- iPad 外接键盘、指针、拖放、Command 菜单和焦点顺序。

### 13.2 生命周期与权限

- 前台/后台、系统挂起、系统终止、用户强制结束、设备重启和 App 升级；设备重启后首次解锁前、锁屏时受保护数据不可用，任务进入等待解锁而非重新登录或盲目重试。
- Wi-Fi/蜂窝切换、低数据、低电量、无网、慢网和存储不足。
- 照片完整/有限/拒绝/撤销、iCloud-only/优化储存资源及共享图库；有限权限只备份已授权项目。另覆盖通知允许/拒绝、Files Provider 认证失效。
- 多 Scene 同 NAS/不同 NAS，确保任务、选择、草稿和控制台不串用。

### 13.3 DSM

- 局域网、公网直连、QuickConnect 中继和证书变化。
- 普通账号、受限管理员、功能无权限、套件未安装和 capability 缺失。
- 当前记录的 DSM build + 套件完整版本；未记录环境的内部写必须关闭。
- 成功、部分成功、权限拒绝、超时、提交未知、取消后复查和回读不一致。

## 14. 关键风险

| 风险 | 处理 |
| --- | --- |
| 单体模型无法支持多模块/多 Scene | M0 先机械拆分，之后才允许功能并行 |
| 后台执行被误认为常驻 | UI 明示系统调度；任务状态可恢复，不能承诺准时或无限运行 |
| Photos 权限过度 | 单次导入优先 PhotosPicker；自动备份另行审批，完整/有限都可用 |
| 把 iCloud 照片删除误作“释放本机空间” | 不实现该入口；交由系统“优化储存空间”，后台永不自动删除系统照片图库项目 |
| iPad 只按机型适配 | 依据实际宽度/size class，强制测试 Split View/Stage Manager |
| File Provider 被误作双向盘 | 只读能力，所有本地写返回不支持，签名实机前保持 `SIGNING_REQUIRED` |
| Chat 后台即时承诺 | 无 APNs/NAS 推送时只保证前台实时和轮询降级 |
| 内部 API UI 先行导致误开放 | capability + compatibility + 版本 gate 在 ViewModel 之前完成 |
| 共享 Package 影响 macOS | 只做兼容增量并运行 Mac 回归；需要改 Mac App 时停止请求授权 |

## 15. Apple 官方平台依据

- [NavigationSplitView 在紧凑宽度自动折叠](https://developer.apple.com/documentation/swiftui/navigationsplitview)
- [SwiftUI WindowGroup 与多窗口](https://developer.apple.com/documentation/swiftui/windowgroup)
- [Replicated File Provider 可用于 iOS/macOS](https://developer.apple.com/documentation/fileprovider/replicated-file-provider-extension)
- [File Provider 变更跟踪](https://developer.apple.com/documentation/fileprovider/tracking-your-file-provider-s-changes)
- [后台 URLSession 下载与重建限制](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)
- [后台 URLSession 任务取消原因](https://developer.apple.com/documentation/foundation/url-session-background-task-cancellation-reasons)
- [BGProcessingTask 由系统调度且可中断](https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask)
- [选择后台策略](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
- [PhotosPicker 选择照片与视频](https://developer.apple.com/documentation/photokit/selecting-photos-and-videos-in-ios)
- [PhotoKit 有限照片库隐私模型](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app)
- [iCloud Photos 删除与“优化储存空间”的系统语义](https://support.apple.com/en-us/104967)
- [iPad 多窗口支持](https://developer.apple.com/documentation/uikit/supporting-multiple-windows-on-ipad)
- [系统文档选择器访问沙盒外文件](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)
- [本地通知调度](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
