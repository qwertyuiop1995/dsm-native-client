# Windows 原生客户端

Windows 客户端使用 C#、WinUI 3、HttpClient、System.Text.Json 和 Windows
Credential Locker。

当前 solution：

```text
LanStash.Domain          领域模型与跨模块契约
LanStash.Infrastructure  DSM WebAPI、会话和 Repository
LanStash.App             WinUI 3 原生界面
LanStash.Tests           不依赖真实 NAS 的自动化测试
```

中文应用名为“岚仓”、英文应用名为 `LanStash`。正式 MSIX Identity Name 保持为
`qwertyuiop1995.DsmNativeClient`；Publisher 由签名证书或商店身份决定，源码不预填虚假值。

已接入 HTTPS 与 QuickConnect 登录、Credential Locker 会话、NavigationView 导航、文件管理、照片、消息、下载任务、
Container Manager、Virtual Machine Manager、NAS 设置、传输中心和应用设置。VMM 包含保护与日志；
映像支持删除，网络支持重命名和删除。删除和退出登录均需要确认，写操作完成后由 Repository 回读检查。
登录成功后会保留名称、NAS 地址和账号；用户可选择由 Windows 凭据管理器保护密码，并可进一步开启自动登录。
可选的自定义 HTTPS 端口默认收在“高级连接设置”中。

Windows 验证：

```powershell
dotnet restore LanStash.slnx
dotnet test tests\LanStash.Tests\LanStash.Tests.csproj -c Release
dotnet build src\LanStash.App\LanStash.App.csproj -c Release -r win-x64
```

WinUI 只能在 Windows SDK 环境构建，本仓库同时提供 `windows-build.yml` 进行 Windows CI 验证。
当前已在 macOS 使用 .NET 10 Release 完成 Domain、Infrastructure 编译并通过 13 项单元测试；
QuickConnect 已完成不含登录凭据的真实能力发现。完整 WinUI XAML 编译与安装包启动检查仍由
Windows CI/设备完成。
