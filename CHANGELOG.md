# 变更记录

本项目使用语义化版本，并在里程碑版本后附加阶段标识。

## Unreleased

### 新增

- 初始化单仓库目录结构。
- 添加 DSM API 参考和第一阶段开发文档。
- 添加进度、架构、安全和兼容性文档体系。
- 添加协议契约目录和初始 JSON Schema。
- 添加 GitHub 仓库结构检查工作流。
- 确定应用名称、跨平台包标识和 macOS 参考平台。
- 初始化 macOS SwiftUI App、Xcode workspace 与 Apple 共享 Swift Package。
- 实现 `DsmCore`、`DsmNetwork`、API 能力发现、密码/OTP 登录和 Keychain 会话存储。
- 添加 Apple 单元测试与构建工作流。
- 添加 UI UX Pro Max 自动路由、新设备引导安装脚本和离线测试。

### 变更

- 客户端中文品牌名称统一为“岚仓”，英文品牌名称统一为 `LanStash`。
- macOS 显示名称、窗口标题和安装产物名称改用新品牌，兼容性技术标识保持不变。
