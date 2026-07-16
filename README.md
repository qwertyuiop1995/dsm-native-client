# 岚仓（LanStash）

岚仓（LanStash）是面向 Windows、macOS、Android、iPhone 和 iPad 的 Synology DSM 原生客户端项目。

项目坚持平台原生实现：

- macOS、iPhone、iPad：Swift、SwiftUI；共享 Apple 原生 Swift Package。
- Android：Kotlin、Jetpack Compose。
- Windows：C#、WinUI 3。
- 三套技术栈共享 API 契约、脱敏样本、错误语义和验收标准，不共享跨平台 UI 运行时。

## 当前阶段

当前里程碑：`macOS 第一阶段实现与 DSM 实机验证`。

第一阶段目标：

1. DSM 登录与安全会话。
2. 文件和共享目录浏览。
3. 图片、文本和 PDF 预览。
4. 文件下载和上传。
5. 安全删除。
6. 经过实机验证的回收站恢复。

## 文档

- [DSM Web API 参考](docs/api/DSM_WEB_API_REFERENCE_ZH.md)
- [第一阶段开发文档](docs/development/NATIVE_DSM_FILE_APP_DEVELOPMENT_PLAN_ZH.md)
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
- 密码不持久化；SID、SynoToken 和 DID 使用系统安全存储。
- Release 构建只允许 HTTPS，不提供全局忽略证书错误的选项。
- 删除和恢复必须有确认、冲突保护和结果校验。
- 仓库禁止提交真实 NAS 地址、账号、文件路径、SID、抓包和用户文件。

## 构建状态

macOS 参考工程已完成第一阶段源码闭环，包含多 NAS 配置、证书指纹信任、能力发现、密码/OTP 登录、共享与目录浏览、图片/文本/PDF 预览、上传、下载、安全删除、传输中心和受兼容开关保护的回收站恢复。应用提供不访问网络的演示模式，方便直接检查完整界面。Android 与 Windows 工程将在后续批次初始化。

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
