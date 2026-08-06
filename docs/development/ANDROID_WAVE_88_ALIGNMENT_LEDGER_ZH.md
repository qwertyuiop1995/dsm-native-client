# Android 第 88 批功能对齐账本

- 目标：为已有公开 `SYNO.Virtualization.API.Guest.get` v1 的 VMM Guest 增加独立只读详情页、`ModuleRoot(VIRTUAL_MACHINES) → GuestDetails` 返回层级与不透明对象深链。
- 稳定目标：加密映射仅保存当前资料 ID 与 `guest_id`；URI、Intent、Bundle 和日志仍只允许 32 字节不透明令牌。
- 重读门禁：必须发现官方 `SYNO.Virtualization.API.Guest` v1，按 `guest_id` 单项读取并核对响应 ID；资料、Repository、代次或能力变化时拒绝陈旧结果。
- 交互转换：外链只打开独立只读页；不打开现有含启动、编辑、关机和删除动作的弹窗。系统返回先关闭详情，再回 VMM Machines 根页。
- 可见内容：复用现有 Guest 基础信息与只读硬件投影；加载、错误和正常状态提供重试，不展示内部 ID、API、任务令牌或凭据。
- 安全级别：只读。外链不恢复编辑器、确认框、选中 tab 或任何危险操作；能力缺失、对象消失或 ID 不一致时终态拒绝，暂态网络失败保留重试。
- 非目标：VMM 写操作、noVNC、映像/存储/网络/任务对象深链、Container/套件私有对象、macOS 源码与 DSM 契约变更。
- 验收：Repository 单项重读、路由/返回、opaque 签发恢复、五态/2× 字体与双语资源自动化；真实 NAS 与实体机仍由用户统一验收。

## 完成记录

- 已完成：本地入口、独立只读页、官方 Guest v1 单项重读、加载/失败重试、强类型返回、opaque 签发与恢复、双语和无障碍测试均已接通；原 VMM 写动作入口保持可达，外链永不打开动作弹窗。
- 复核修正：请求前与返回后双重拒绝活跃编辑、确认、mutation target 和在途写状态；严格要求非空 `guest_name`，避免通用资源投影以内部 ID 代替标题；能力缺失时不显示本地详情入口。
- 本地验证：VMM Repository/状态/路由/opaque 聚焦 JVM 通过，`compileDebugKotlin` 与 `compileDebugAndroidTestKotlin` 通过；31 页五态矩阵、49 项工具测试、1985 项 Android 双语资源、触控、动效、写操作矩阵与差异检查通过。
- 云端验证：GitHub Android Build `31064773022` 与 Repository Check `31064773033` 通过；完整 JVM、Debug/Release/R8、仪器测试 APK、Debug lint、报告和安装包上传均由托管 Runner 完成。
- 进度：本批完善 A0/A6/A8 既有组合目标，不拆分、删除或重复计分；A0–A8 仍为 183/202（90.6%），剩余 19 项。真实 NAS 与实体机结论保持“未验证”。
