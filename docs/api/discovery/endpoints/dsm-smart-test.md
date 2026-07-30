# DSM S.M.A.R.T. 检测内部 API

## 标识

| 字段 | 值 |
| --- | --- |
| 端点或端点组标识 | `dsm-smart-test` |
| 项目组件标识 | `storage-manager` |
| 所属范围 | DSM 存储管理器 |
| 能力名称 | 硬盘 S.M.A.R.T. 检测状态、历史、启动与停止 |
| 分类 | `internal` |
| 操作性质 | `read / write` |
| 风险等级 | `high` |

## 请求契约

| 字段 | 值 |
| --- | --- |
| API 名称 | `SYNO.Core.Storage.Disk` |
| 路径 | 运行时通过 `SYNO.API.Info` 发现 |
| HTTP 方法 | `POST` |
| API 版本 | v1 |
| 鉴权机制 | DSM 会话 Cookie/表单与令牌请求头/表单，不记录值 |
| 内容类型 | `application/x-www-form-urlencoded` |

参数：

| 方法 | 参数 | 类型 | 必需 | 含义 | 脱敏示例 |
| --- | --- | --- | --- | --- | --- |
| `get_smart_test_log` | `device` | `string` | 是 | 从存储列表取得的硬盘设备标识 | `<synthetic-device>` |
| `disk_test_log_get` | `device`、`offset`、`limit`、`sort_by`、`sort_direction`、`type` | 多类型 | 是 | 读取检测历史 | 合成设备标识，`type=smart` |
| `do_smart_test` | `device`、`type` | `string` | 是 | 启动快速/完整检测或停止当前检测 | `quick`、`extend`、`stop` |

界面使用的稳定硬盘 `id` 只用于定位存储列表项；所有检测请求必须使用同一项返回的
`device`，两者不得混用或接受用户输入。

## 响应与错误

`get_smart_test_log` 从 `testInfo` 读取 `testing`、`test_type`、`remain`、
`ihm_testing`、`perf_testing` 和最近结果。`disk_test_log_get` 从 `testLog` 分别
选择最近的快速和完整检测记录。

| 场景 | 错误语义 | 是否可重试 | 降级或恢复 |
| --- | --- | --- | --- |
| 硬盘不存在或不支持检测 | 目标不可用 | 否 | 关闭检测按钮并刷新存储列表 |
| 已有 S.M.A.R.T. 检测运行 | 状态冲突 | 否 | 保留当前运行状态 |
| IHM 或性能检测占用 | 其他检测正在使用硬盘 | 否 | 等待完成后重新读取 |
| 权限不足 | 当前账号不能启停检测 | 否 | 提示使用具备存储管理权限的账号 |
| 提交断网、超时或响应无效 | 启停结果未知 | 否 | 立即回读检测状态，不自动重放 |
| 提交成功但轮询超时 | 最终状态尚未确认 | 否 | 保持未知提示并继续允许手动刷新 |
| 提交后取消 | 请求可能已生效 | 否 | 停止等待，刷新后再决定下一步 |

## 版本验证

| 环境标识 | 证据等级 | 接口版本 | 结果 | 日期 | 证据路径 |
| --- | --- | --- | --- | --- | --- |
| `lab-a-dsm-7-2-1-69057-u12-20260729` | `read-verified` | v1 | 状态与历史读取结构已核对；启停只完成合成请求和故障注入测试，未执行写行为验收 | 2026-07-27 | `docs/api/DSM_WEB_API_REFERENCE_ZH.md` |

## 能力探测与降级

- 启用条件：同时发现存储列表和 `SYNO.Core.Storage.Disk` v1，且目标硬盘明确支持检测。
- 新版本默认行为：未记录的新 DSM build 默认关闭内部写入口。
- 接口缺失：只关闭硬盘检测，不阻断容量与健康摘要读取。
- 字段缺失或类型变化：不能确定当前检测状态时禁止写入。
- 权限不足：不提升权限、不切换账号。
- 网络失败：提交前失败可恢复后重试；提交开始后必须先回读，不自动再次启停。
- 替代的官方 API：当前项目未找到覆盖 DSM 原生硬盘检测的公开 API。
- 功能开关：NAS 设置模块、运行时能力发现和环境兼容记录共同控制。

## 客户端与测试

- Apple Adapter：`DsmNasAdministrationRepository`。
- Android Adapter：复用领域结果类型，调用链尚未迁移。
- Windows Adapter：复用领域结果类型，调用链尚未迁移。
- Schema：复用 `MutationResult` 与请求 Fixture Schema。
- 脱敏 Fixture：
  - `contracts/request-fixtures/storage/start-smart-test/synthetic-disk/request.json`
  - `contracts/request-fixtures/storage/stop-smart-test/synthetic-disk/request.json`
- 自动化测试：覆盖启停确认成功、提交断网、超时后回读成功、同硬盘重复提交与提交后取消。
- 产品兼容矩阵条目：`NAS 设置`、`统一写操作结果 MR0/MR1/MR2`。

## 安全与副作用

- 会读取的数据类别：硬盘设备标识、检测运行状态、进度与历史结果。
- 可能产生的副作用：增加硬盘负载，完整检测可能持续较长时间，停止会中断当前检测。
- 所需权限：由 DSM 返回的能力和当前会话权限决定。
- 重复提交保护：Repository 与 macOS 模型均按稳定硬盘标识阻止并发启停。
- 写后结果校验：轮询同一硬盘状态并确认 `testing` 达到目标值；未知结果不得重放。
- 临时数据清理：不保存真实设备标识、序列号、响应正文、任务日志或主机信息。

## 未验证事项

- 当前环境未在专用测试硬盘完成快速/完整检测启动、停止、权限不足、提交断网和长期
  轮询行为验收。
- 不同 DSM build、HDD/SSD 类型和 USB/eSATA 扩展设备的字段与错误码差异尚未验证。
- Android、Windows 以及 iPhone、iPad 调用链尚未迁移。
