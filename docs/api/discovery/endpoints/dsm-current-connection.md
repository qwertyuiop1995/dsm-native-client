# DSM 当前连接内部 API

## 标识

| 字段 | 值 |
| --- | --- |
| 端点或端点组标识 | `dsm-system-observability` |
| 项目组件标识 | `dsm-core` |
| 所属范围 | DSM 资源监控与连接管理 |
| 能力名称 | 当前连接列表与受保护的连接断开 |
| 分类 | `internal` |
| 操作性质 | `read / write` |
| 风险等级 | `high` |

## 请求契约

| 字段 | 值 |
| --- | --- |
| API 名称 | `SYNO.Core.CurrentConnection` |
| 路径 | 运行时通过 `SYNO.API.Info` 发现 |
| HTTP 方法 | `POST` |
| API 版本 | v1 |
| 鉴权机制 | DSM 会话 Cookie/表单与令牌请求头/表单，不记录值 |
| 内容类型 | `application/x-www-form-urlencoded` |

| 方法 / 参数 | 类型 | 必需 | 含义 | 脱敏示例 |
| --- | --- | --- | --- | --- |
| `list.start` / `limit` | `integer` | 是 | 有界分页 | `0` / `500` |
| `list.sort_by` / `sort_direction` | `string` | 是 | 按连接时间倒序 | `time` / `DESC` |
| `kick_connection.service_conn` | `objectArray` | 是 | 非网页连接目标，包含 `pid`、`type`、`who`、`from` | `<synthetic-service-connection>` |
| `kick_connection.http_conn` | `objectArray` | 是 | 网页连接目标，包含 `did`、`descr`、`who`、`from` | `<synthetic-http-connection>` |

网页连接只允许使用列表返回的非空 `did`；其他服务连接只允许使用非空 `pid`。目标必须
来自刚刚重新读取的列表，且 `can_be_kicked=true`。不得由显示文本、列表行号、用户名或
来源地址单独拼接写请求。

## 响应与错误

列表只保留 `pid`、`did`、`who`、`from`、`location`、`protocol`、`type`、`time`、
`descr`、`is_current_connected` 和 `can_be_kicked` 白名单字段。写响应的 `success=true`
只表示请求被接受；必须重新读取列表并确认同一设备或进程标识已经消失。

| 场景 | 错误语义 | 是否自动重试 | 降级或恢复 |
| --- | --- | --- | --- |
| API 或标识缺失 | 不支持/目标不可确认 | 否 | 保留只读列表，关闭断开入口 |
| `can_be_kicked` 不为真 | 权限或受保护目标 | 否 | 不发送写请求 |
| 当前会话 | 可能使本应用掉线 | 否 | 使用更强确认，说明需重新登录 |
| 权限不足或会话失效 | 明确拒绝 | 否 | 提示使用具备权限的账号或重新登录 |
| 提交后目标消失 | 确认成功 | 不适用 | 更新连接列表 |
| 提交超时、断线或回读失败 | 结果未确认 | 否 | 重新连接并刷新列表后核对 |

## 版本验证

| 环境标识 | 证据等级 | 接口版本 | 结果 | 日期 | 证据路径 |
| --- | --- | --- | --- | --- | --- |
| `lab-a-dsm-7-2-1-69057-u12-20260729` | `read-verified`（仅列表） | v1 | `list` 字段已核对；`kick_connection` 仅有官方网页请求线索和源码/合成测试，本环境未执行写行为 | 2026-07-27 | `docs/api/DSM_WEB_API_REFERENCE_ZH.md` |

列表证据不得提升断开操作的证据等级；连接断开保持“已实现、未实机验证”。

## 能力探测与降级

- 必须发现 `SYNO.Core.CurrentConnection` v1。
- 新 DSM build 在完成版本化写行为验证前，只能依据能力、列表显式许可和用户确认谨慎开放；无法取得完整目标字段时关闭。
- 列表失败仅影响连接页，不阻断文件、照片或其他 NAS 设置。
- 当前没有覆盖 DSM 会话与服务连接统一断开的公开 API。

## 客户端与测试

- Apple Adapter：`DsmNasAdministrationRepository.loadConnections` / `disconnectConnection`。
- Android Adapter：`DsmRepository.disconnectConnectionResult` 已使用 `kick_connection`、完整目标元数据、同目标防重复和列表回读；旧 `disconnect(id)` 已删除。
- Windows Adapter：待迁移。
- 脱敏 Fixture：尚无独立请求 Fixture；`ConnectionDisconnectMutationTest` 使用语义合成目标覆盖网页/服务参数、保护拒绝、权限拒绝、模糊提交回读和同目标防重复。
- 产品兼容矩阵：`docs/progress/PLATFORM_MATRIX.md` 的 NAS 设置与套件/任务/日志/连接条目。

## 安全与副作用

- 连接数据可能包含账号、来源地址、位置、设备和进程标识，不持久化、不遥测、不写日志。
- 断开当前会话会让应用失去连接；其他服务连接可能中断文件传输或后台任务。
- 同一设备/进程目标必须防重复；提交异常只回读，不自动重放。
- 写后只比较内存中的原始目标标识；诊断标签不得包含账号、地址、`did` 或 `pid`。

## 未验证事项

- 管理员/普通账号、当前会话、HTTP/HTTPS 与其他服务连接的真实权限及错误码未验证。
- QuickConnect 中继、目标自然结束、列表延迟和写后断线行为未验证。
- 当前没有专用测试目标授权，因此未通过浏览器或客户端触发真实连接断开。
