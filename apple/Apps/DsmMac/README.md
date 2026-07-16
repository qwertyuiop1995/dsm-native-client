# DsmMac

岚仓（LanStash）的 macOS 参考 App，使用 SwiftUI 并通过 Apple 共享 Swift Package 引用 `DsmCore` 与 `DsmNetwork`。`DsmMac` 作为内部 target 和 scheme 名保留，安装产物为 `LanStash.app`。

当前登录页支持：

- HTTPS NAS 主机和端口输入。
- `SYNO.API.Info` 能力发现。
- 账号密码登录与 OTP 状态切换。
- SID 和 SynoToken 写入 Keychain。

密码和 OTP 只保留在登录界面的内存状态中；成功或非 OTP 错误后立即清空。自签名证书首次信任尚未开放。
