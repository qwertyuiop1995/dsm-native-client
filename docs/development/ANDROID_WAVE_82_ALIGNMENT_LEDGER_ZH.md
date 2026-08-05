# Android 第 82 批功能对齐账本

更新时间：2026-08-05

本账本只记录第 82 批的实施边界，不替代或拆分
`ANDROID_CLIENT_COMPLETION_PLAN_ZH.md` 中的 A0–A8 原目标。完成一个子能力不等于完成父目标，
实体机验收按用户安排保留为未验证。

| 切片 | macOS / 契约证据 | Android 等价语义与移动交互 | 契约依赖 | 安全级别 | 批前验证等级 | 本批决定 | 明确非目标 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A0 深层导航与返回栈 | `apple/Apps/DsmMac/Sources/WorkspaceModel.swift`、`WorkspaceView.swift`、`Tests/WorkspaceNavigationTests.swift`；Android 事实来源为 `WorkspaceRoute.kt`、`WorkspaceShell.kt` 与现有路由测试 | 继续使用 Material 3 顶部返回、系统返回和预测返回；路由只保存模块与无载荷页面层级，不复制路径、会话、任务、查询、镜像或 NAS 标识。配置重建后恢复安全层级，业务对象仍由当前内存领域状态解析 | 不新增 DSM 请求；外部入口仅在当前已认证 Workspace 内执行，并先经过能力门禁 | 中；外部入口按高风险输入处理 | 模块根外部入口与 5 类内部末级路由已有 JVM / Compose 证据，真实进程死亡和真机预测返回未验证 | 审计确认现成且安全的最大固定深页只有 `lanstash://open/containers/registry`。已按“固定枚举 → Containers 根 → Registry 能力门禁 → 无载荷末级页”实现；成功或拒绝后清除 URI，Workspace 未就绪和 Activity 重建保持最新枚举请求 | 不在 URI、SavedState、日志或磁盘保存业务标识；不为“任意业务对象”猜测身份映射；不宣称实机通过 |
| A6 Container 创建/编辑与 Compose | `apple/Apps/DsmMac/Sources/ServiceManagementModel.swift`、`ServiceManagementView.swift`；`docs/api/discovery/endpoints/container-manager-internal.md`、`contracts/private-api/compatibility.json` | 手机端若未来开放，应使用分步表单、可返回草稿、明确确认、部署进度与可恢复结果；当前不得把纯本地文本检查冒充 NAS 校验或部署 | 当前稳定范围只有只读列表与 Registry 搜索/标签；`pull_start`、创建/编辑、Compose 校验/部署和异步任务 Schema 尚未行为验证 | 高；会创建或改写容器工作负载 | observed / degraded，只读自动化；写操作三层零请求关闭 | 本批不新增无真实出口的草稿或假部署入口；保留关闭并记录所需证据 | 不解析静态脚本猜字段，不操作真实 NAS 写接口，不改变兼容结论 |
| A6 VMM 高级管理 | `apple/Packages/DsmCore/Sources/ServiceManagement.swift`、`apple/Packages/DsmNetwork/Sources/DsmServiceManagementRepository.swift`；公开 VMM v1 指南登记于 `DSM_WEB_API_REFERENCE_ZH.md`，内部候选见 `vmm-internal.md` | 高级硬件编辑、迁移、克隆、导出应采用独立确认、单次提交、Task.Info 只读跟踪和最终资源回读；手机端使用分步表单而非桌面表格 | 公开 `Guest.set` 当前只覆盖名称、描述、vCPU、内存和自动启动；内部 clone/move/export/image edit 未行为验证 | 高；可能中断虚拟机或产生大文件 | 公开基础创建/设置/映像导入与任务中心已有自动化；高级写候选仅 static / observed | 审计确认没有可安全新增的公开高级写闭环，相关入口继续关闭；同时修正 `Guest.Image.delete` Fixture：公开删除返回空成功，必须由 Image.list 回读，不能误标为 Task.Info 轮询 | 不用公开 v1 参数推断内部 v2，不执行真实生命周期或迁移写操作，不把任务列表等同于高级管理完成 |

## 实施结果

- 修改范围：Android 固定外部路由解析、Activity 待处理枚举、Registry 能力导航及专项测试；VMM 删除映像 Fixture 和精确策略守护测试。
- 未新增可见文案、第三方依赖、权限、Manifest 契约、DSM 请求、持久业务载荷或私有写能力。
- 本地已通过 60 项外部/Workspace/VMM 聚焦 JVM、Debug 与 AndroidTest Kotlin 编译、49 项工具测试、82 份请求 Fixture、13 项请求契约工具测试和 VMM 策略守护。独立复核发现的 VIEW/内部 extra 优先级 P1，以及旧 Bundle、能力后置和同模块根页 3 项 P2 已修复。GitHub [Android Build 31018613142](https://github.com/yuangy1995/dsm-native-client/actions/runs/31018613142) 完成 1238/1238 JVM、Debug/Release/R8、仪器测试 APK、Debug lint 与产物上传；[Repository Check 31018611379](https://github.com/yuangy1995/dsm-native-client/actions/runs/31018611379) 完成仓库门禁。
- A0/A6 父组合目标均未完成，A0–A8 仍为 183/202（90.6%），剩余 19 项。

## 本批共同出口

- 所有新增可见文案同时提供英语和简体中文资源，不在 Compose 中硬编码。
- 返回优先级、能力不可用、加载、空、错误、正常和提交中状态必须可测试。
- 自定义触控目标保持至少 48dp，并使用原生按压、键盘和屏幕阅读器语义。
- 本机只运行聚焦 JVM、Kotlin 编译及轻量静态门禁；完整 Debug/Release/R8、仪器测试 APK 与 lint 交给 GitHub Runner。
- 本批不会因为契约或设备条件不足而删除、拆分或重写 A0/A6 原目标。
