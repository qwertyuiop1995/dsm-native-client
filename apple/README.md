# Apple 原生客户端

本目录包含 macOS App、通用 iPhone/iPad App 和共享 Swift Package。

```text
Package.swift                  Apple 共享 Swift Package
DsmNativeClient.xcworkspace/  Apple 工作区
Apps/DsmMac/                   macOS 原生应用
Apps/DsmMobile/                iPhone/iPad 通用原生应用占位目录
Packages/DsmCore/              领域模型、错误和 Repository 协议
Packages/DsmNetwork/           DSM HTTP、会话和参数编码
Packages/DsmFileFeature/       浏览、详情和预览
Packages/DsmTransferFeature/   下载、上传、删除和恢复任务
```

## 当前实现

- 中文应用名：“岚仓”；英文应用名：`LanStash`。
- macOS Bundle ID：`io.github.qwertyuiop1995.dsmnativeclient.macos`。
- macOS 安装产物：`LanStash.app`；中文系统显示为“岚仓”。
- 最低系统：macOS 14；共享包同时声明 iOS 17。
- macOS App 使用 SwiftUI 和 App Sandbox。
- 当前网络层仅接受系统信任的 HTTPS 证书；自签名证书首次信任尚未实现。

## 构建

```bash
swift test --package-path apple
xcodebuild \
  -workspace apple/DsmNativeClient.xcworkspace \
  -scheme DsmMac \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

`Apps/DsmMac/project.yml` 是 XcodeGen 工程定义。修改工程结构后运行：

```bash
cd apple/Apps/DsmMac
xcodegen generate --spec project.yml
```
