# 产品路线图

> 最后更新：2026-07-22
> “已实现”表示源码和自动化测试路径已经建立；“已验收”必须有真实 NAS 和版本记录。

## M0：工程基础与安全登录

状态：macOS 已实现，正在完成真实环境验收。

- 单仓库、文档、协议契约和脱敏规则。
- 多 NAS 配置、HTTPS、证书核对和能力发现。
- 密码、OTP、SID、SynoToken、QuickConnect 直连与中继。
- 可选记住密码、每台 NAS 自动登录和显式退出。

## M1：文件浏览与预览

状态：macOS 已实现，媒体兼容性和大目录场景待继续验收。

- 共享目录、分页浏览、排序、图标/列表视图和分组。
- 文件详情、文件夹大小、账号可见空间、缩略图、收藏和最近访问。
- 远程位置浏览，以及能力发现保护下的 SMB/NFS 创建、修改和删除；内部接口必须按 DSM build 验收。
- 当前目录/子目录搜索和正则筛选。
- 图片、文本、PDF、音频和视频预览。
- 图片切换、旋转、缩放和全屏；常见文本编辑、保存与格式整理。

## M2：传输与文件管理

状态：macOS 已实现，复杂冲突、网络切换和大文件场景待继续验收。

- 文件及文件夹上传、下载、文件夹 ZIP 下载和保留目录结构下载。
- HTTP Range 断点续传、暂停、取消、继续、重试和传输中心。
- 创建目录、重命名、复制、移动、拖拽、框选和限时撤销。
- 仅在实际发生同名冲突时提示跳过或替换。
- NAS 端 ZIP/7z 压缩、常见压缩包解压、密码和编码处理。
- 分享链接创建、密码、有效期、复制、列表和取消分享。
- 系统通知、连接方式提示和应用存储管理。

## M3：危险操作与恢复

状态：macOS 已实现受保护路径，必须按 DSM build 验收后开放。

- 删除前确认、任务轮询、重复提交保护和结果校验。
- 浏览 `#recycle`、原始路径候选计算和冲突保护。
- 使用 `SYNO.FileStation.CopyMove` 恢复并校验结果。
- 专用内部恢复接口只保留研究记录，不作为默认依赖。

## M4：macOS 发布准备

状态：下一阶段。

- 完成兼容矩阵规定的真实 NAS 场景。
- 完成浅色/深色模式、键盘、VoiceOver、动态文字和降低动态效果检查。
- 完成性能、缓存、通知、应用退出、签名和公证验证。
- 清除一次性调试资料并选择许可证和分发方式。

## M5：照片基础能力与 macOS 首版

状态：进行中；PH1 文件夹扫描已获实机确认，PH2/PH3 的时间线、查看和基础管理主流程已实现，等待完整验收。

- 完成照片领域契约、基础照片库和能力降级模型。
- 已实现个人空间、共享空间、文件夹浏览和按天分组的基础时间线；**年/月快速定位、年视图与月视图入口待补齐**。
- 已实现惰性照片墙、搜索筛选，并复用全屏图片/视频查看和基础详情；**EXIF 详情（分辨率、相机、镜头、位置、拍摄参数）待补齐**。
- 已实现上传、批量导出、删除确认和分享；**移动、收藏、基础相册、照片页回收站恢复入口待补齐**。
- 完成 1 千、1 万和 10 万项目性能验证，以及 macOS 键盘、VoiceOver、深色模式和降低动态效果验收。

详细批次和完成门槛参见[照片管理开发计划](../development/NATIVE_DSM_PHOTOS_DEVELOPMENT_PLAN_ZH.md)。

## M6：智能照片库

状态：计划。

- 在能力发现、真实版本契约测试和功能开关保护下接入 Synology Photos 内部 Adapter（`SYNO.Foto*` / `SYNO.FotoTeam*`）。
- 复用 NAS 时间轴、相册、最近添加、标签、人物、主题、地点、缩略图和可用转码结果；逐一记录 DSM build 与 Synology Photos 套件版本。
- 每项增强能力可独立失败和降级，不阻止基础照片浏览。
- 能力范围：相册创建/编辑/删除、向相册添加/移除项目、人物/主题/地点/标签浏览与命名、最近添加、视频转码结果复用。

## M7：Apple 移动端与照片备份

状态：计划。

- iPhone 和 iPad 复用 Apple 共享业务层，实现触控原生照片界面。
- 接入系统照片库、增量扫描、后台上传、任务恢复和备份状态。
- “释放设备空间”必须在 NAS 原件核对和用户确认后执行。
- 完成前后台切换、网络切换、权限变化、重复项和大量首次备份验证。

## M8：Android 与 Windows 原生对齐

状态：计划。

- Android 初始化 Kotlin/Jetpack Compose 多模块工程并实现照片浏览和移动备份。
- Windows 初始化 C#/WinUI 3 solution，并实现桌面照片浏览、导入和导出。
- 三套原生实现共同遵循照片契约、安全语义和兼容矩阵，不引入跨平台 UI 运行时。

## M9：Synology Chat 协议与 macOS 聊天模块

状态：已立项，尚未开始实现。

- 在专用测试 NAS 上验证 Chat Server 套件、用户会话、完整客户端接口和实时同步方式。
- 明确公开 `SYNO.Chat.External` 不用于普通用户聊天，建立独立用户聊天内部 Adapter。
- 建立用户、会话、私人群聊、消息、附件和同步游标的共同契约。
- 完成 macOS 一对一聊天、创建私人群聊、文字与 Unicode Emoji 收发。
- 完成图片、视频、普通文件和语音消息的录制或选择、发送、预览、播放、下载和打开。
- 完成消息提醒、单选/多选投票及结果同步。
- 在密钥协议、安全存储、恢复、轮换和跨设备验证通过后支持加密一对一与私人群聊。
- 所有内部能力按 DSM build 与 Chat Server 版本执行能力发现、契约测试、功能开关和失败降级。

## M10：Apple 移动端 Chat

状态：计划。

- iPhone 和 iPad 复用 Apple Chat 领域层、Repository、同步和安全实现。
- 实现一对一聊天、私人群聊、文字、Emoji、图片、视频、文件、语音消息、提醒、投票和加密会话的原生移动体验。
- 完成触控、横竖屏、文件选择、媒体播放、VoiceOver、动态文字和弱网恢复验收。

## M11：Android 与 Windows Chat 对齐

状态：计划。

- Android 使用 Kotlin、Jetpack Compose、OkHttp 和 Android Keystore 实现相同聊天与加密范围。
- Windows 使用 C#、WinUI 3、HttpClient 和 Credential Locker/DPAPI 实现相同聊天与加密范围。
- 三端分别遵循平台原生导航、通知、键盘、触控、屏幕阅读器和窗口行为。

Chat 的阶段、接口边界、安全规则和发布门槛参见[Synology Chat 原生聊天功能开发计划](../development/NATIVE_DSM_CHAT_DEVELOPMENT_PLAN_ZH.md)。

## 已识别但未排期的能力

按 DSM 套件与风险等级整理，后续逐个按能力发现 + 版本契约测试 + 功能开关方式接入：

### File Station 扩展
- `SYNO.FileStation.BackgroundTask` 后台任务汇总
- `SYNO.FileStation.DirSize` 异步目录大小计算
- `SYNO.FileStation.MD5` 异步文件 MD5 计算
- `SYNO.FileStation.VFS.Connection` / `SYNO.Entry.Request` 批量与 VFS 扩展
- 回收站恢复在照片页的直接入口

### 下载与传输套件
- Download Station：`SYNO.DownloadStation.*` 官方接口与 `SYNO.DownloadStation2.*` 内部适配
- 后台下载/上传、离线任务恢复、多端同步、版本历史与冲突合并

### 虚拟化与容器
- Virtual Machine Manager：`SYNO.Virtualization.API.*` / `SYNO.Virtualization.*` 虚拟机生命周期、电源控制、镜像管理
- Container Manager / Docker：`SYNO.Docker.*` 容器、镜像、网络、项目管理

### 系统与硬件控制
- 系统信息/利用率/进程/连接/日志：`SYNO.Core.System*`、`SYNO.Core.SyslogClient*`、`SYNO.LogCenter.History`
- 存储/硬盘/SMART：`SYNO.Storage.*`、`SYNO.Core.Storage.*`
- 硬件控制：风扇、LED、蜂鸣器、电源计划、UPS、ZRAM
- 网络/DDNS/代理/防火墙：`SYNO.Core.Network*`、`SYNO.Core.DDNS.*`、`SYNO.Core.Security.*`
- 用户/群组/共享/配额：`SYNO.Core.User*`、`SYNO.Core.Group*`、`SYNO.Core.Share*`、`SYNO.Core.Quota*`
- 套件管理：`SYNO.Core.Package.*` 安装、启停、卸载
- 计划任务：`SYNO.Core.TaskScheduler`、`SYNO.Core.EventScheduler`
- 终端 SSH/Telnet：`SYNO.Core.Terminal`

### 其他套件
- Audio Station、Video Station、Note Station
- Synology Drive（`SYNO.SynologyDrive.*`）
- Calendar、Contacts
- Synology Chat 已移入 M9-M11，不再作为未排期候选
- Surveillance Station
- Hyper Backup / Active Backup
- Synology Office

## 后续候选

- 按用户优先级和 DSM 版本验证情况，从“已识别但未排期的能力”中挑选进入里程碑。
- 每项内部接口默认关闭，通过 `SYNO.API.Info` 能力发现、版本契约测试和实机验证后才启用。
