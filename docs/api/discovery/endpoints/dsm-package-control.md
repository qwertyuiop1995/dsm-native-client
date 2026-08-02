# DSM 套件启动与停止内部 API

## 标识

| 字段 | 值 |
| --- | --- |
| 端点或端点组标识 | `dsm-package-control` |
| 项目组件标识 | `dsm-core` |
| 所属范围 | DSM 套件中心 |
| 能力名称 | 已安装套件列表、启动可行性检查、启动与停止 |
| 分类 | `internal` |
| 操作性质 | `read / write` |
| 风险等级 | `high` |

## 请求契约

| 字段 | 值 |
| --- | --- |
| API 名称 | `SYNO.Core.Package`、`SYNO.Core.Package.Control` |
| 路径 | 运行时通过 `SYNO.API.Info` 发现 |
| HTTP 方法 | `POST` |
| API 版本 | 套件列表与可行性检查 v2；启动与停止 v1 |
| 鉴权机制 | DSM 会话 Cookie/表单与令牌请求头/表单，不记录值 |
| 内容类型 | `application/x-www-form-urlencoded` |

| API / 方法 | 参数 | 类型 | 必需 | 含义 |
| --- | --- | --- | --- | --- |
| `Package.list` | `offset`、`limit`、`additional` | 多类型 | 是 | 读取稳定套件 ID、状态、可用操作和桌面应用标识 |
| `Package.feasibility_check` | `type` | `string` | 是 | 启动使用 `start_check`，停止使用 `stop_check` |
| `Package.feasibility_check` | `packages` | `stringArray` | 是 | 只包含当前目标的稳定套件 ID |
| `Package.Control.start` | `id` | `string` | 是 | 启动目标套件 |
| `Package.Control.start` | `dsm_apps` | `stringArray` | 是 | 使用列表返回的桌面应用标识，不接受用户输入 |
| `Package.Control.stop` | `id` | `string` | 是 | 停止目标套件 |

客户端不得根据界面行号、显示名称或翻译后的状态选择目标。每次启动或停止都先重新读取
列表，确认稳定套件 ID 仍存在且 `canStart` / `canStop` 与当前动作一致，再执行
`feasibility_check`。任何预检失败都不得发送 `start` 或 `stop`。

## 结果语义与写后回读

1. 同一稳定套件 ID 的启动、停止和卸载共享 Repository 互斥，不能并行提交。
2. 写请求明确成功后最多读取套件列表十次，每次间隔一秒，确认目标达到运行或停止状态。
3. 写请求超时、断线、响应无效或服务繁忙时，不重放原写请求，只读取列表核对；普通
   模糊失败最多核对三次。
4. 提交阶段取消后使用独立的只读任务尝试一次状态核对；无法确认时保留“提交后取消”
   语义。
5. 只有列表确认目标状态后才返回 `confirmedSuccess`。列表仍是旧状态、目标意外消失或
   回读失败时返回 `submittedButUnverified`，要求用户刷新后再决定下一步。

| 场景 | 结果语义 | 恢复方式 |
| --- | --- | --- |
| API 未发现或版本不可用 | 不支持、未提交 | 关闭启动和停止入口 |
| 套件不存在或当前状态不允许动作 | 预检失败、未提交 | 刷新列表并核对套件状态 |
| 可行性检查权限不足 | 权限拒绝、未提交 | 使用具备套件管理权限的账号 |
| 写请求明确权限不足或会话失效 | 明确失败 | 重新登录或更换有权限的账号 |
| 写请求后列表确认目标状态 | 确认成功 | 更新界面状态 |
| 写请求超时后列表确认目标状态 | 确认成功 | 不重放写请求 |
| 写请求后无法确认目标状态 | 已提交结果未确认 | 刷新列表，确认前不得再次执行同一动作 |
| 提交前取消 | 未提交取消 | 不需要状态恢复 |
| 提交阶段取消 | 已提交结果未确认 | 先刷新套件列表 |
| 同一套件已有操作 | 重复提交冲突 | 等待当前操作完成 |

## 版本验证

| 环境标识 | 证据等级 | 结果 | 日期 | 证据路径 |
| --- | --- | --- | --- | --- |
| `lab-a-dsm-7-2-1-69057-u12-20260729` | `static` | 已核对能力范围、官方网页前端请求线索、合成请求和故障注入测试；本批未在真实 NAS 启动或停止套件 | 2026-07-31 | `docs/api/DSM_WEB_API_REFERENCE_ZH.md` |

合成 Fixture 与源码测试只能证明客户端请求形态、预检顺序、互斥、回读和禁止重放策略，
不能把当前环境提升为 `behavior-verified`。

## 能力探测与降级

- 必须同时发现 `SYNO.Core.Package` 和 `SYNO.Core.Package.Control`；缺少任一能力时
  启动与停止均保持关闭。
- 列表字段缺失、目标不存在或无法判断 `canStart` / `canStop` 时禁止写入，不猜测
  套件状态。
- `feasibility_check` 是提交前的必要条件，但不替代目标写方法自身的权限判断。
- 新 DSM build 或未记录版本上的内部写入口默认保持关闭，直至完成版本化验证。
- 套件控制失败只降级套件管理，不阻断文件、照片、消息或其他 NAS 设置读取。
- 当前项目未找到覆盖 DSM 套件启动与停止的统一公开 API。

## 客户端与测试

- Apple Adapter：`DsmNasAdministrationRepository`。
- macOS：启动和停止均使用原生确认框；操作期间显示进度、禁用同一套件操作并提供
  VoiceOver 标签。
- Android、Windows、iPhone 与 iPad：复用领域结果类型，套件控制调用链尚未迁移。
- 合成 Fixture（`retryPolicy=queryStateBeforeDecision`、`readbackPolicy=required`）：
  - `contracts/request-fixtures/packages/start/synthetic-package/request.json`
  - `contracts/request-fixtures/packages/stop/synthetic-package/request.json`
- 自动化测试覆盖请求参数、预检顺序、状态拒绝、能力缺失、提交前取消、写后确认、提交
  超时后回读、明确权限拒绝、同 ID 重复提交、提交后取消和 Model 层反馈。

## 安全与副作用

- 停止套件会中断该套件提供的功能和连接；启动也可能触发后台任务和资源占用，界面必须
  在提交前说明影响并要求确认。
- 请求只使用列表返回的稳定 ID 和 `dsm_apps`，不接受任意用户输入的 API 参数。
- 请求 Fixture 不记录真实套件、NAS 地址、账号、Cookie、SID、SynoToken 或响应。
- 未确认结果不得自动重试，也不得建议用户立即再次启动或停止。
- 套件卸载继续使用独立的破坏性结果链路；安装和升级仍保持关闭。

## 未验证事项

- 不同 DSM build、管理员/普通账号、依赖套件、套件忙碌、启动失败、停止超时和
  QuickConnect 中继下的真实行为尚未验收。
- 部分套件可能返回过渡状态或需要超过十秒才能稳定，当前没有权威的统一任务 ID。
- 系统套件、依赖链和正在处理存储或备份任务的套件可能有额外拒绝语义。
- Android、Windows、iPhone 与 iPad 调用链尚未迁移。
