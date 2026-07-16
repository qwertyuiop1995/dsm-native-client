# DsmNetwork

当前包含：

- 仅使用 HTTPS 的 URLSession 传输。
- 统一表单与 `requestFormat=JSON` 参数编码。
- DSM 通用响应信封和脱敏错误映射。
- `SYNO.API.Info` 能力发现与受控旧入口回退。
- QuickConnect ID 的受限直连地址解析；不实现中继隧道。
- `SYNO.API.Auth` 密码/OTP 登录。
- SID 和 SynoToken 的 Keychain 安全存储。
- 使用内存 Cookie 请求头和 POST `_sid` 双路径传递同一会话，兼容不同 DSM 登录行为。
- 系统证书验证，以及用户核对指纹后仅绑定到指定 NAS 的自签名证书信任。
- 证书变化阻断和过期证书拒绝。

当前不包含全局跳过证书验证的路径。本地 IP、短主机名或 `.local` 地址与证书名称不一致时，可在用户明确核对指纹后继续；信任只绑定到该 NAS 配置和该证书。multipart 和流式传输已由文件仓库的受控实现覆盖，仍需继续完成 DSM 实机兼容验证。
