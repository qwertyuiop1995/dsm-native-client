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
- 支持系统信任的 HTTPS 证书，以及核对 SHA-256 指纹后的自签名证书首次信任。
- 支持使用 IP、域名、QuickConnect ID 连接，也可以粘贴浏览器最终地址；QuickConnect 会优先探测直连候选，失败后建立并校验中继隧道。
- 已实现共享与目录浏览、图片/文本/PDF 预览、上传、下载、安全删除和传输中心。
- 回收站可浏览和下载；恢复引擎只有在当前 DSM build 通过兼容验证后才开放正式入口。

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

直接生成 macOS App 和 DMG，并在完成后运行：

```bash
cd apple/Apps/DsmMac
./package.sh
```

脚本无需参数，启动后可从菜单选择构建类型、目标架构、签名方式和打包后是否运行。产物位于 `apple/Apps/DsmMac/dist/`。
新安装包验证成功后，脚本会自动清理该目录中更早版本的 DMG，并保留当前版本的不同架构。

`Apps/DsmMac/project.yml` 是 XcodeGen 工程定义。修改工程结构后运行：

```bash
cd apple/Apps/DsmMac
xcodegen generate --spec project.yml
```
