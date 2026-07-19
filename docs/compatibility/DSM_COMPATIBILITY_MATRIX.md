# DSM 兼容矩阵

> 只记录版本和验证结论，不记录 NAS 地址、序列号、账号或真实共享名。

| DSM build | File Station | 证书类型 | 平台 | 登录 | 浏览 | 下载 | 上传 | 删除 | 恢复 | 日期 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 待填写 | 待填写 | 待填写 | macOS | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | - |

## 连接方式验证

| 连接方式 | 平台 | 地址发现 | 公开登录入口 | 完整登录 | 备注 |
| --- | --- | --- | --- | --- | --- |
| QuickConnect ID 直连 | macOS | 已通过 | 已通过 | 待用户复测 | 局域网与公网候选会在提交凭据前逐一探测；不记录 ID、解析地址和证书指纹 |
| QuickConnect 中继 | macOS | 已通过 | 已通过 | 待用户使用新密码复测 | 已完成真实环境的隧道建立、NAS 身份核对和 `SYNO.API.Info` 探测；`request_tunnel` 属于内部、可降级契约 |

## 文件操作验证

| 能力 | 使用契约 | macOS 状态 | 实机要求 |
| --- | --- | --- | --- |
| 同 NAS 复制/移动 | `SYNO.FileStation.CopyMove` 官方 API | 已实现 | 验证文件夹、冲突、取消和权限不足 |
| 文件与文件夹重命名 | `SYNO.FileStation.Rename` 官方 API | macOS 已实现；iOS/Android 待接入同一契约 | 验证同名冲突、无写入权限和特殊字符 |
| NAS 端压缩与解压缩 | `SYNO.FileStation.Compress` v3、`SYNO.FileStation.Extract` v2 官方 API | macOS 已实现；共享契约包含压缩包预读、密码检测和文件名编码，iOS/Android UI 待接入 | 验证 ZIP/7z 创建、简体中文旧版 ZIP、加密包密码循环、常见压缩格式、空间不足、同名覆盖和取消任务 |
| 跨 NAS 复制/移动 | Download + CreateFolder + Upload + 可选 Delete 官方 API | 已实现 12 MiB 有界内存中转 | 验证递归文件夹与背压；移动必须确认目标完成后源才删除 |
| 下载断点续传 | Download 响应的 HTTP Range | 已实现、待验证 | 确认目标 DSM 返回 `206`，以及中断后字节一致 |
| 含糊扩展名识别 | Download 的 4 KiB Range 文件头 + 文件签名 | macOS 已实现；三端共享识别契约 | 验证 `.ts` 的 MPEG 传输流与 TypeScript；禁止按文件大小猜测 |
| 上传断点续传 | Upload multipart | 不支持字节续传 | 公开 API 未提供 offset/token；暂停后从头重新上传 |
| 子目录搜索 | `SYNO.FileStation.Search` 官方 API | 已实现 | 验证任务清理、中文、正则结果上限和无权限目录 |
| 收藏夹 | `SYNO.FileStation.Favorite` 官方 API | 已实现 | 验证新增、移除和失效路径 |
| 分享链接管理 | `SYNO.FileStation.Sharing` 官方 API | 已实现 | 验证密码、有效期、批量路径、复制和取消分享 |
| 当前账号可见空间 | `SYNO.FileStation.List.list_share` 官方 API 的 `real_path` 与 `volume_status` | 已实现并按卷去重 | 验证多共享同卷、多卷、配额账号和字段缺失；结果不代表物理硬盘容量 |
| 远程位置浏览 | `SYNO.FileStation.VirtualFolder` 官方 API；旧版回退共享列表挂载类型 | 已实现 | 验证 CIFS/SMB、NFS、失效位置和普通共享的区分 |
| 远程位置创建、修改、删除 | `SYNO.FileStation.Mount` v1 内部实验性 API；`getinfo` 复查 | macOS 已实现、默认由能力发现控制，尚未实机验收 | 必须记录 DSM build；验证管理员/普通账号权限、只读、错误密码、重复提交、修改回滚和断开后远端文件不受影响 |
| 基础照片空间与时间线 | `SYNO.FileStation.List`、`Thumb` 官方 API | macOS 文件夹扫描已获实机确认；时间线改为目录分页渐进扫描，待完整验收 | 分别验证 `/home/Photos`、`/photo` 权限，1 千/1 万/10 万项目、取消、弱网和深层目录 |

## 记录要求

- 每次 DSM 或 File Station 升级后重新执行关键契约测试。
- 证书类型只记录“公共 CA”“自签名”或“私有 CA”，不记录证书正文、主机名或指纹。
- 内部 API 必须精确记录验证版本。
- “API 可发现”不能替代行为验证。
- 恢复必须完成删除、进入 `#recycle`、恢复和冲突测试。

## Synology Photos 兼容记录

> 照片内部接口未完成真实版本契约测试前保持关闭；基础照片库只使用官方登录和 File Station 能力。

| DSM build | Synology Photos 版本 | 平台 | 个人空间 | 共享空间 | 基础照片库 | 时间轴 | 相册 | 人物/主题 | 地点/标签 | 日期 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 待填写 | 待填写 | macOS | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | 未验证 | - |

照片兼容记录必须满足：

- 只记录 DSM build、套件版本、平台和结论，不记录 NAS 地址、账号、真实路径、相册名、人物或地点。
- 个人空间与共享空间分别验证不存在、无权限、只读和完整访问场景。
- 基础照片库验证套件未安装、停用和内部接口不可用时的文件夹浏览与管理。
- 时间轴、相册、人物、主题、地点和标签分别记录，不能用一个总开关代替逐项能力判断。
- 每次 DSM 或 Synology Photos 套件升级后重新运行内部 Adapter 契约测试。
- 内部写操作只有在对应版本、权限、确认、幂等和结果校验全部通过后才能启用。
