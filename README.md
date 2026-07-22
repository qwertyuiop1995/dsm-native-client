# 岚仓（LanStash）

岚仓（LanStash）是面向 Windows、macOS、Android、iPhone 和 iPad 的 Synology DSM 原生客户端项目。

项目坚持平台原生实现：

- macOS、iPhone、iPad：Swift、SwiftUI；共享 Apple 原生 Swift Package。
- Android：Kotlin、Jetpack Compose。
- Windows：C#、WinUI 3。
- 三套技术栈共享 API 契约、脱敏样本、错误语义和验收标准，不共享跨平台 UI 运行时。

## 当前阶段

当前里程碑：`macOS 文件客户端实机验收与稳定性收敛`。

macOS 当前重点：

1. 在局域网、公网直连和 QuickConnect 环境完成真实 NAS 验收。
2. 验证文件浏览、预览、编辑、传输、压缩、分享和危险写操作的完整闭环。
3. 收敛会话、缓存、通知、网络切换和应用退出等稳定性问题。
4. 将验证结果同步到兼容矩阵，再开始其他平台的界面实现。

## 文档

- [DSM Web API 参考](docs/api/DSM_WEB_API_REFERENCE_ZH.md)
- [当前开发与验收计划](docs/development/NATIVE_DSM_FILE_APP_DEVELOPMENT_PLAN_ZH.md)
- [Synology Chat 原生聊天功能开发计划](docs/development/NATIVE_DSM_CHAT_DEVELOPMENT_PLAN_ZH.md)
- [第一阶段开发文档归档](docs/archive/NATIVE_DSM_FILE_APP_DEVELOPMENT_PLAN_V1_ARCHIVE_ZH.md)
- [当前进度](docs/progress/STATUS.md)
- [产品路线图](docs/progress/ROADMAP.md)
- [平台功能矩阵](docs/progress/PLATFORM_MATRIX.md)
- [总体架构](docs/architecture/ARCHITECTURE.md)
- [DSM 兼容矩阵](docs/compatibility/DSM_COMPATIBILITY_MATRIX.md)
- [安全基线](docs/security/SECURITY_BASELINE.md)

## 目录

```text
apple/       macOS 与通用 iPhone/iPad 原生工程
android/     Android 原生工程
windows/     Windows 原生工程
contracts/   三端共同遵循的协议契约与脱敏样本
docs/        API、开发、架构、进度、安全和兼容文档
tools/       契约校验和样本脱敏工具
```

## 开发原则

- 官方 API 优先，内部 API 必须经过能力探测、抓包验证和版本隔离。
- 密码默认不保存；macOS 仅在用户明确选择后使用应用沙盒内的 AES-GCM 加密文件保存密码和会话，其他平台使用各自的系统安全存储。
- Release 构建只允许 HTTPS，不提供全局忽略证书错误的选项。
- 删除和恢复必须有确认、冲突保护和结果校验。
- 仓库禁止提交真实 NAS 地址、账号、文件路径、SID、抓包和用户文件。

## 构建状态

macOS 参考工程已形成完整的文件客户端源码闭环，包含多 NAS 与 QuickConnect、安全登录、目录浏览与搜索、账号可见空间、收藏和最近访问、SMB/NFS 远程位置管理、缩略图和多格式预览、文本编辑、上传下载、文件夹 ZIP 下载、复制移动、拖拽、压缩解压、分享链接、传输中心、系统通知以及应用存储管理。远程位置、删除和回收站恢复等高影响能力仍受能力发现、确认、结果校验和兼容开关保护。

上述状态表示代码路径和自动化测试已经建立；尚未完成兼容矩阵记录的能力仍需在真实 NAS 上验收。iPhone、iPad、Android 与 Windows 的原生客户端目录继续保留，后续按平台路线图实现。

Apple 本地验证：

```bash
swift test --package-path apple
xcodebuild \
  -workspace apple/DsmNativeClient.xcworkspace \
  -scheme DsmMac \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

所有 DSM 行为仍需在记录了 DSM build、File Station 版本和证书类型的专用测试 NAS 上完成实机验证。未通过兼容验证时，正式连接不会开放“恢复到原位置”。

## 许可证

当前尚未选择开源许可证。公开访问不代表自动授予复制、修改或分发权限；确定对外授权方式后再添加正式许可证。
