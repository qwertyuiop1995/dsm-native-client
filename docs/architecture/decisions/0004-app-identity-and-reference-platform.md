# ADR-0004：应用身份与首个参考平台

状态：已接受
日期：2026-07-16

## 决策

项目中文应用名确定为“岚仓”，英文应用名确定为 `LanStash`，首个参考实现平台确定为 macOS。

平台标识如下：

| 平台 | 标识 |
| --- | --- |
| 中文显示名称 | `岚仓` |
| 英文显示名称 | `LanStash` |
| Apple 基础命名空间 | `io.github.qwertyuiop1995.dsmnativeclient` |
| macOS Bundle ID | `io.github.qwertyuiop1995.dsmnativeclient.macos` |
| iPhone/iPad 通用 App Bundle ID | `io.github.qwertyuiop1995.dsmnativeclient.mobile` |
| Android applicationId | `io.github.qwertyuiop1995.dsmnativeclient` |
| Windows MSIX Identity Name | `qwertyuiop1995.DsmNativeClient` |

Windows 的 Publisher 和各平台签名身份由证书或商店账号决定，不在源码中预填虚假值。平台商店若分配不同包身份，必须通过新的 ADR 记录迁移方案。

## 原因

- 中英文名称形成独立、统一的用户品牌，不把 DSM 产品名作为客户端品牌。
- 反向域名使用公开 GitHub 所有者命名空间，避免依赖尚未拥有的域名。
- macOS 便于验证 URLSession、Keychain、文件系统和 DSM API，完成的 Swift Package 可继续服务 iPhone/iPad。

## 结果

- 先初始化独立 macOS SwiftUI App 和 Apple 共享 Swift Package。
- 品牌更名只影响显示名称和安装产物名；既有 Bundle ID、包名、Keychain service、会话名和工程命名保持不变。
- Android 与 Windows 后续按本 ADR 使用已确定的包标识初始化工程。
- 发布前仍需检查应用名称、商标、签名和商店保留状态。
