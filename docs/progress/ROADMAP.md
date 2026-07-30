# 产品路线图

> 最后更新：2026-07-30
> 当前实现、测试和阻塞情况以[当前开发进度](STATUS.md)为准。

本文只记录未来优先级和里程碑出口，不重复维护已经实现的功能清单。

## P0：发布与实机验收

### macOS 文件客户端

- 完成目标 DSM build 下的登录、浏览、预览、传输、远程位置和危险写操作回归。
- 完成签名、公证、缓存、通知、关闭窗口后台运行、性能和无障碍验收。
- 将真实环境结论写入兼容矩阵。

### 桌面端只读云盘位置

- 补齐 runtime schema 无法解码和共享会话缺失的恢复路径；创建/移除、启动续清理、
  系统盘补注册、外接卷保护和孤立 domain 清理已有代码级故障注入测试。
- 使用正式签名验证 macOS Finder/File Provider 端到端行为。
- 在 Windows x64/arm64 完成 WinUI 构建、Cloud Files 回调、资源管理器状态、固定与释放、只读保护、重启、外部磁盘和安装/卸载验收。
- 通过真实 NAS 验证整个 NAS/指定目录映射、按需读取、离线保留、空间预检、缓存清理和后台恢复。

详细设计和验收条件见[桌面端云盘开发计划](../development/NATIVE_DSM_DESKTOP_CLOUD_DRIVE_DEVELOPMENT_PLAN_ZH.md)。

### 契约与危险写操作

- 在现有脱敏响应 Fixture 之外建立请求契约测试，优先覆盖删除、覆盖上传、权限、
  套件、容器、虚拟机、网络、防火墙和系统更新；记录 API、方法、版本、路径、参数
  编码、认证要求、重试策略和危险等级。
- 评估五端统一的写操作结果语义，至少区分已回读确认、明确失败、已提交但无法确认、
  部分成功、提交前取消和提交后请求取消；超时或结果未知时禁止界面引导用户立即
  重复提交。
- 请求契约或结果模型进入公共契约前，必须同步评估五端实现计划、兼容矩阵、迁移和
  回滚，不在单个平台先行固化未经验证的 DSM 行为。
- 扩充诊断“禁止出现”测试，覆盖 URL、主机、路径、显示名称、查询参数、会话材料和
  原始底层错误；继续使用白名单结构化摘要，不导出原始日志。

实施顺序、五端影响、迁移和回滚见
[请求契约与写操作结果模型实施计划](../development/REQUEST_CONTRACT_AND_MUTATION_RESULT_PLAN_ZH.md)。

### 移动端与 Windows 基础客户端

- iPhone、iPad 和 Android 分别完成真实设备完整登录、自动恢复、网络切换和显式退出验收。
- Windows 完成完整 WinUI 构建、安装启动、登录恢复和平台安全存储验收。

## P1：现有模块收敛

### 照片管理

- 完成大图库、元数据、权限、弱网、缓存和危险写操作验收。
- 补齐基础相册入口，再按版本化契约评估人物、主题、地点、标签等增强能力。
- 达到 macOS 发布出口后，再推进 iPhone、iPad、Android 和 Windows 原生界面及移动照片备份。

详细范围见[照片管理开发计划](../development/NATIVE_DSM_PHOTOS_DEVELOPMENT_PLAN_ZH.md)。

### Synology Chat

- 完成首次单聊、私人群聊、附件、提醒、定时消息、投票创建和实时刷新的真实套件验收。
- 补齐语音、投票参与及其他未完成消息能力。
- 加密会话必须先完成密钥生命周期、安全评审和跨设备验证，不允许明文降级。
- macOS 范围稳定后，再推进其他平台原生实现。

详细范围见[Synology Chat 开发计划](../development/NATIVE_DSM_CHAT_DEVELOPMENT_PLAN_ZH.md)。

### NAS 设置、套件与统一存储

- 使用专用测试目标验证可能断网、改时、停服或影响存储状态的写操作。
- 补齐 Download Station、Container Manager、Virtual Machine Manager 的高级功能和异步任务闭环。
- 验证统一存储管理的大目录、取消、权限、QuickConnect 和 MD5 任务；取得版本化契约后再评估套件历史报告与计划任务。

详细范围见[套件管理计划](../development/NATIVE_DSM_SERVICE_MANAGEMENT_PLAN_ZH.md)和[统一存储管理计划](../development/NATIVE_DSM_STORAGE_MANAGEMENT_PLAN_ZH.md)。

## P2：五端能力对齐

- Apple 移动端复用共享领域层，按触控、小屏、后台任务和系统权限设计原生体验。
- Android 使用 Kotlin 与 Jetpack Compose，Windows 使用 C# 与 WinUI 3。
- 各端遵循共同契约、安全语义和兼容矩阵，不共享跨平台 UI 运行时。
- 平台对齐范围根据[平台功能矩阵](PLATFORM_MATRIX.md)逐项确定，不以单个平台实现代替其他平台验收。

## P3：候选能力

- File Station 后台任务、异步目录大小、MD5、VFS 扩展和更完整的恢复入口。
- Download Station、Container Manager 和 Virtual Machine Manager 的剩余高级能力。
- Audio Station、Video Station、Note Station、Synology Drive、Calendar、Contacts、Surveillance Station、Hyper Backup、Active Backup 和 Synology Office。
- 社区兼容性计划第二阶段，包括维护者辅助工具、冲突检测和本地诊断摘要。

候选能力只有在用户优先级明确、API 来源清楚、安全边界成立且具备目标环境验证条件后，才进入活动里程碑。

## 里程碑完成规则

- “已实现”只表示源码和自动化测试路径已经建立。
- “已完成”必须满足专项验收条件并形成目标平台或真实 NAS 证据。
- 每次状态变化只更新[当前开发进度](STATUS.md)；本路线图仅在优先级、范围或里程碑出口发生变化时更新。
