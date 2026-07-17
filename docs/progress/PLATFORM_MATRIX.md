# 平台功能矩阵

## 技术栈

| 平台 | 语言 | UI | 网络 | 安全存储 |
| --- | --- | --- | --- | --- |
| macOS | Swift | SwiftUI + AppKit | URLSession | Keychain |
| iPhone | Swift | SwiftUI + UIKit | URLSession | Keychain |
| iPad | Swift | SwiftUI + UIKit | URLSession | Keychain |
| Android | Kotlin | Jetpack Compose | OkHttp | Android Keystore |
| Windows | C# | WinUI 3 | HttpClient | Credential Locker/DPAPI |

## 发布支持

| 能力 | macOS | iPhone | iPad | Android | Windows |
| --- | --- | --- | --- | --- | --- |
| 原生 UI | 已实现，待实机验收 | 计划 | 计划 | 计划 | 计划 |
| 后台下载 | 前台任务已实现 | 计划 | 计划 | 计划 | 计划 |
| 后台上传 | 前台任务已实现 | 计划 | 计划 | 计划 | 计划 |
| 多 NAS 切换时保持传输 | 已实现，待实机验收 | 复用 Apple 共享实现 | 复用 Apple 共享实现 | 计划 | 计划 |
| 下载断点续传 | 已实现 HTTP Range 分片，待实机验收 | 复用 Apple 共享实现 | 复用 Apple 共享实现 | 计划 | 计划 |
| 上传断点续传 | 公开 API 不支持，暂停后从头重传 | 同左 | 同左 | 计划 | 计划 |
| 跨 NAS 复制/移动 | 已实现 12 MiB 有界内存中转，不生成整文件磁盘暂存，待实机验收 | 计划 | 计划 | 计划 | 计划 |
| 系统文件选择器 | 已实现 | 计划 | 计划 | 计划 | 计划 |
| 图片预览 | 已实现，待实机验收 | 计划 | 计划 | 计划 | 计划 |
| PDF 预览 | 已实现，待实机验收 | 计划 | 计划 | 计划 | 计划 |
| 文本预览 | 已实现，待实机验收 | 计划 | 计划 | 计划 | 计划 |
| 音乐流式预览 | 已实现 Range 分段读取，待实机验收 | 计划 | 计划 | 计划 | 计划 |
| 视频流式预览 | 已实现 Range 分段读取，待实机验收 | 计划 | 计划 | 计划 | 计划 |
| QuickConnect ID 直连解析 | 已实现并完成公开入口实机探测 | 复用 Apple 共享实现 | 复用 Apple 共享实现 | 计划 | 计划 |
| Cookie + `_sid` 会话兼容 | 已实现，待完整登录复测 | 复用 Apple 共享实现 | 复用 Apple 共享实现 | 计划 | 计划 |
| QuickConnect 中继隧道 | 已实现并完成能力发现实机验证 | 复用 Apple 共享实现 | 复用 Apple 共享实现 | 计划 | 计划 |

功能状态以 [STATUS.md](STATUS.md) 为准，本文件记录平台能力差异和技术选择。
