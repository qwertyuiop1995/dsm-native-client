# 岚仓（LanStash）当前开发与验收入口

> 最后更新：2026-07-30
> 当前状态：[当前开发进度](../progress/STATUS.md)
> 后续优先级：[产品路线图](../progress/ROADMAP.md)
> 历史规格：[第一阶段开发文档归档](../archive/NATIVE_DSM_FILE_APP_DEVELOPMENT_PLAN_V1_ARCHIVE_ZH.md)

## 文档用途

本文只定义跨模块共同适用的验收顺序和发布出口，不重复记录功能完成情况、API 参数、平台差异或专项设计。相关事实分别由当前进度、API 参考、平台矩阵、安全基线、兼容矩阵和专项开发计划维护。

## 当前验收顺序

| 优先级 | 工作 | 验收出口 |
| --- | --- | --- |
| P0 | macOS 文件客户端与真实 NAS 回归 | 登录、浏览、预览、传输和危险写操作形成带版本信息的脱敏记录 |
| P0 | macOS Finder 云盘位置 | 正式签名后完成 File Provider、按需读取、离线保留、清理、重启和退出行为验收 |
| P0 | Windows 客户端与云盘位置 | 在 Windows x64/arm64 完成 WinUI 构建、Cloud Files、资源管理器、重启和安装/卸载验收 |
| P0 | 移动端登录恢复 | iPhone、iPad 和 Android 分别完成真实设备完整登录、恢复与显式退出验证 |
| P1 | 照片、Chat 与 NAS 设置 | 按各专项计划完成真实套件、权限、性能和写操作验收 |

功能是否已经实现、测试数量和当前阻塞项只在[当前开发进度](../progress/STATUS.md)更新。

## 真实 NAS 验收要求

1. 记录 DSM build、相关套件完整版本、日期、连接方式类别、证书类型和权限类别，不记录真实地址、账号或路径。
2. 覆盖局域网、公网直连和 QuickConnect 可用场景；验证会话过期、网络切换和证书变化。
3. 覆盖中文、特殊字符、深层目录、大目录分页、大文件、空间不足和权限不足。
4. 写操作必须验证确认、权限检查、防重复提交、取消或超时处理以及最终状态复查。
5. 内部 API 按发现规范记录证据等级；未验证的新 build 默认关闭内部写能力。
6. 结果写入[DSM 兼容矩阵](../compatibility/DSM_COMPATIBILITY_MATRIX.md)，自动化测试不能替代实机证据。

## 发布共同出口

- 目标平台的正式测试、Release 构建和安装启动通过。
- 用户凭据、会话、证书、日志、缓存和诊断信息符合[安全与隐私基线](../security/SECURITY_BASELINE.md)。
- 新增用户文案具备英语和简体中文资源，本地化完整性与硬编码扫描通过。
- 浅色/深色模式、键盘或触控、VoiceOver/屏幕阅读器、动态文字和降低动态效果完成检查。
- 危险写操作具备确认、权限检查、防重复提交和结果校验。
- 当前进度、平台矩阵、兼容矩阵和变更记录与同一源码版本同步。
- 一次性调试文件、日志、构建产物和测试账号资料已经清理。

## 专项计划

- [桌面端 NAS 云盘映射与按需缓存](NATIVE_DSM_DESKTOP_CLOUD_DRIVE_DEVELOPMENT_PLAN_ZH.md)
- [照片管理](NATIVE_DSM_PHOTOS_DEVELOPMENT_PLAN_ZH.md)
- [Synology Chat](NATIVE_DSM_CHAT_DEVELOPMENT_PLAN_ZH.md)
- [DSM 套件管理](NATIVE_DSM_SERVICE_MANAGEMENT_PLAN_ZH.md)
- [统一存储管理](NATIVE_DSM_STORAGE_MANAGEMENT_PLAN_ZH.md)

专项计划只维护范围、长期约束、未完成工作和验收条件；实时状态统一回到当前进度文档。

## 工程事实来源

- [DSM Web API 参考](../api/DSM_WEB_API_REFERENCE_ZH.md)
- [私有 API 发现规范](../api/discovery/README.md)
- [平台功能矩阵](../progress/PLATFORM_MATRIX.md)
- [总体架构](../architecture/ARCHITECTURE.md)
- [安全与隐私基线](../security/SECURITY_BASELINE.md)
