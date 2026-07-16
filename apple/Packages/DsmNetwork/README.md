# DsmNetwork

当前包含：

- 仅使用 HTTPS 的 URLSession 传输。
- 统一表单与 `requestFormat=JSON` 参数编码。
- DSM 通用响应信封和脱敏错误映射。
- `SYNO.API.Info` 能力发现与受控旧入口回退。
- `SYNO.API.Auth` 密码/OTP 登录。
- SID 和 SynoToken 的 Keychain 安全存储。

当前使用系统默认 TLS 信任链，不包含全局跳过证书验证的路径。自签名证书首次信任、证书变化检测、multipart 和流式传输将在后续实现。
