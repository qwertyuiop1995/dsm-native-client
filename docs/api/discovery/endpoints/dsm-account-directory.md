# DSM 账号与群组目录内部 API

## 标识

| 字段 | 值 |
| --- | --- |
| 端点或端点组标识 | `dsm-account-directory` |
| 项目组件标识 | `dsm-core` |
| 所属范围 | DSM |
| 能力名称 | 账号与群组目录读取和管理 |
| 分类 | `internal` |
| 操作性质 | `mixed` |
| 风险等级 | `critical` |

## 请求契约

| 字段 | 值 |
| --- | --- |
| API 名称 | `SYNO.Core.User`、`SYNO.Core.Group` |
| 路径 | 运行时通过 `SYNO.API.Info` 发现；客户端当前测试路径为 `entry.cgi` |
| HTTP 方法 | `POST` |
| API 版本 | v1 |
| 鉴权机制 | DSM 会话 Cookie 与请求字段；可用时同时携带 SynoToken 请求头与字段，不记录值 |
| 内容类型 | `application/x-www-form-urlencoded` |

账号方法：`list`、`get`、`create`、`set`、`delete`。群组方法使用相同方法名和独立的
`SYNO.Core.Group` API。

关键参数：

| 参数 | 类型 | 必需 | 含义 | 脱敏示例 |
| --- | --- | --- | --- | --- |
| `offset`、`limit` | `integer` | 列表需要 | 分页范围 | `0`、`1000` |
| `additional` | `string[]` | 列表需要 | 请求数字标识、说明、状态和可操作性字段 | `["uid","can_delete"]` |
| `name` | `string` 或 `string[]` | 写入需要 | 合成账号或群组标识；删除使用数组 | `<synthetic-account>` |
| `description`、`email`、`expired` | 多类型 | 账号保存需要 | 只发送编辑器当前值 | 完全合成值 |
| `groups` | `string[]` | 可选 | 账号所属群组 | `["<synthetic-group>"]` |
| `password`、`password_confirm` | `string` | 新建账号需要 | 只用于当次请求 | 仅记录存在和已脱敏，不保存值 |

## 响应与错误

只读成功响应使用 DSM 通用信封，`User.list` 的 `data.users` 与 `Group.list` 的
`data.groups` 为数组。客户端只解析名称、数字标识、说明、邮件地址、停用状态、群组
以及 `can_edit`、`can_delete`；字段缺失时不推断额外权限。

| 场景 | 错误语义 | 是否可重试 | 降级或恢复 |
| --- | --- | --- | --- |
| API 或版本未发现 | 当前环境不支持 | 否 | 关闭账号管理入口 |
| 会话失效 | 需要重新登录 | 否 | 停止写入并重新认证 |
| 权限不足 | 当前账号不能执行操作 | 否 | 不尝试管理员权限 |
| 写请求连接中断 | 最终结果未确认 | 否 | 先重新读取目录，不自动重放 |
| 写后目录不符合预期 | 结果不一致 | 否 | 保留当前列表并提示人工核对 |

## 版本验证

| 环境标识 | 证据等级 | 接口版本 | 结果 | 日期 | 证据路径 |
| --- | --- | --- | --- | --- | --- |
| `lab-a-dsm-7-2-1-69057-u12-20260729` | `observed` | User / Group v1 | 只读结构和网页请求已记录；未执行账号写行为验收 | 2026-07-27 | `docs/api/DSM_WEB_API_REFERENCE_ZH.md` |

共享请求 Fixture 和本地源码测试只证明客户端请求没有漂移，不把本环境提升为
`behavior-verified`。

## 能力探测与降级

- 启用条件：`SYNO.API.Info` 返回对应 API、v1 和可用路径，当前会话具备页面权限。
- 新版本默认行为：未记录的新 DSM build 上内部写入口保持关闭，完成重新观察和专用
  环境行为验收后再形成兼容结论。
- 接口缺失：账号管理页面独立降级，不阻断文件浏览等公开 API 主流程。
- 字段缺失或类型变化：忽略无法安全解析的条目，不假定其可编辑或可删除。
- 权限不足：显示可恢复说明，不自动切换或尝试更高权限账号。
- 网络失败：写后先重新读取账号与群组目录，不自动重新提交。
- 替代的官方 API：当前项目未找到满足 DSM 本地账号管理需求的公开 API。
- 功能开关：运行时能力发现与平台账号管理入口共同控制。

## 客户端与测试

- Apple Adapter：`apple/Packages/DsmNetwork/Sources/DsmNasAdministrationRepository.swift`
- Android Adapter：尚未迁移。
- Windows Adapter：尚未迁移。
- Schema：`contracts/schemas/request-fixture.schema.json`
- 合成 Fixture：
  - `contracts/request-fixtures/users/create/synthetic-account/request.json`
  - `contracts/request-fixtures/users/delete/synthetic-account/request.json`
- 自动化测试：
  - `apple/Packages/DsmNetwork/Tests/RequestFixtureContractTests.swift`
  - `apple/Packages/DsmNetwork/Tests/DsmNasAdministrationRepositoryTests.swift`
- 产品兼容矩阵条目：`contracts/private-api/compatibility.json` 的
  `dsm-account-directory`

## 安全与副作用

- 会读取的数据类别：账号与群组名称、说明、邮件地址、状态、成员关系和可操作性。
- 可能产生的副作用：创建、修改或删除 DSM 本地账号与群组，可能影响访问权限。
- 所需权限：由 DSM 返回的能力和当前会话权限决定；客户端不得提升权限。
- 重复提交保护：Repository 与 macOS 模型均按稳定账号或群组标识隔离正在执行的删除。
- 写后结果校验：保存或删除后重新读取账号与群组目录并核对目标状态；提交后断网、取消
  或回读失败均返回未确认结果，不自动再次删除。
- 临时数据清理：密码只存在于编辑草稿和当次请求，不写入 Fixture、日志或持久化。

## 未验证事项

- 当前环境未在专用测试账号上完成创建、修改、删除、权限不足、网络中断和重复提交的
  行为验收。
- Android、Windows 以及 iPhone、iPad 的账号管理调用链尚未迁移。
- DSM 升级后的方法参数、权限和错误码变化尚未验证。
