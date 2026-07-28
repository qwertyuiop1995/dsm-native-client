# Android 原生客户端

Android 客户端使用 Kotlin、Jetpack Compose、Coroutines、OkHttp 和 Android Keystore。

当前工程：

```text
app/src/main/.../domain/    领域模型与错误语义
app/src/main/.../network/   DSM WebAPI 传输层
app/src/main/.../storage/   Keystore 保护的会话与可选密码存储
app/src/main/.../data/      文件、套件和管理 Repository
app/src/main/.../ui/        Compose 自适应界面
```

中文应用名为“岚仓”、英文应用名为 `LanStash`，applicationId 为
`io.github.qwertyuiop1995.dsmnativeclient`，最低 Android 版本为 API 29。

已接入 HTTPS 与 QuickConnect 登录、加密会话、手机/平板自适应导航、文件管理、照片列表、会话列表、下载任务、
Container Manager、Virtual Machine Manager、NAS 设置、传输中心和应用设置。VMM 包含虚拟机、
主机、存储、网络、映像、保护和日志；映像可删除，网络可修改和删除，危险操作均要求确认。
登录成功后会保留名称、NAS 地址和账号；用户可选择由 Android Keystore 保护密码，并可进一步开启自动登录。
可选的自定义 HTTPS 端口默认收在“高级连接设置”中。

本地验证：

```bash
./gradlew :app:testDebugUnitTest :app:assembleDebug :app:assembleRelease :app:assembleDebugAndroidTest
```

当前结果：19 项单元测试通过，Debug/Release APK 和仪器测试 APK 编译通过；Release 已在
Android 14 真机完成冷启动，QuickConnect 已完成不含登录凭据的真实能力发现测试。

自动化测试不能替代真实 NAS 的版本、套件、权限和写操作验收。
