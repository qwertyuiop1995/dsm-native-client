# Virtual Machine Manager 内部接口

## 标识

| 字段 | 值 |
| --- | --- |
| 端点或端点组标识 | `vmm-internal` |
| 项目组件标识 | `virtual-machine-manager` |
| 所属范围 | Virtual Machine Manager |
| 能力名称 | VMM 网页端读取、日志与隔离写能力 |
| 分类 | `internal` |
| 操作性质 | `mixed` |
| 风险等级 | `critical` |

## 请求契约

| 字段 | 值 |
| --- | --- |
| API 名称 | `SYNO.Virtualization.Guest`、`SYNO.Virtualization.Guest.Action`、`SYNO.Virtualization.Guest.Image`、`SYNO.Virtualization.Host`、`SYNO.Virtualization.Repo`、`SYNO.Virtualization.Network`、`SYNO.Virtualization.GuestProtect.Plan`、`SYNO.Virtualization.Log` |
| 路径 | 由 `SYNO.API.Info` 在运行时返回，不固定拼接 |
| HTTP 方法 | `POST` |
| API 版本 | 读取组客户端范围 v1-v2；`Guest.Action` 为 v1；`Log.list` 为 v1 |
| 鉴权机制 | DSM 会话 Cookie 与可选安全请求头；值不得进入 URL、日志或诊断导出 |
| 内容类型 | 由能力发现与当前 DSM 客户端适配器决定 |

当前已有资料记录的方法如下；公开 `SYNO.Virtualization.API.*` 的参数不能用于推断这些内部接口：

| API | 已记录方法与版本 | 当前边界 |
| --- | --- | --- |
| `SYNO.Virtualization.Host` | `list`、`get` v2 | 只读 |
| `SYNO.Virtualization.Guest` | `list`、`get`、`get_basic`、`set`、`delete` v2 | 读取已记录；修改和删除没有行为验证 |
| `SYNO.Virtualization.Guest.Action` | `pwr_ctl`、`reset`、`clone`、`move`、`export`、`check_poweron` v1 | 写操作没有行为验证 |
| `SYNO.Virtualization.Guest.Image` | `list`、`create`、`delete`、`edit` v2 | 读取已记录；写操作没有行为验证 |
| `SYNO.Virtualization.Network` | `list`、`get` v2；`set`、`delete` 待验收 | 写方法与参数必须在专用目标重新拦截核对 |
| `SYNO.Virtualization.Repo` | `list`、`get` v2 | 只读 |
| `SYNO.Virtualization.GuestProtect.Plan` | `list`、`get` 兼容读取 | 只读，具体版本按运行时能力范围 |
| `SYNO.Virtualization.Log` | `list` v1 | 分页参数之外必须提交 `loglevel`、`filter_content`、`datefrom`、`dateto`、`sort_by=time`、`sort_dir=DESC` |

除日志已记录的必需参数外，本记录不补写其他方法参数或响应字段。

## 响应与错误

当前只依赖 DSM 响应的稳定外层：

```json
{
  "success": true,
  "data": {}
}
```

- 各读取分区按能力独立解析；失败必须显示不可用状态，不把错误伪装成空列表。
- 能力缺失、版本不覆盖或字段变化时关闭相应内部读取或写入，不猜测参数。
- 登录失效、证书变化和权限错误应保留其原始语义。
- 写请求若在提交后断线、超时或取消，结果未知，不得自动重放或仅凭外层成功报告完成。

## 版本验证

| 环境标识 | 证据等级 | 接口版本 | 结果 | 日期 | 证据路径 |
| --- | --- | --- | --- | --- | --- |
| `lab-a-dsm-7-2-1-69057-u12-20260729` | `read-verified` | `Guest`、`Guest.Image`、`Host`、`Repo`、`Network`、`GuestProtect.Plan` 客户端范围 v1-v2；`Guest.Action` v1；`Log.list` v1 | `degraded`；VMM `2.6.5-12202`，创建、修改、网络写和删除未形成行为验证结论 | 2026-07-27 | `docs/api/DSM_WEB_API_REFERENCE_ZH.md`、`docs/compatibility/DSM_COMPATIBILITY_MATRIX.md` |

读取方法由当前官方 VMM 网页前端静态代码与 `SYNO.API.Info` 交叉确认；`read-verified` 不提升任何写方法的证据等级。

## 能力探测与降级

- 默认优先使用公开 `SYNO.Virtualization.API.*` v1。
- 内部调用前必须由 `SYNO.API.Info` 确认 API、路径和版本范围。
- 内部读取失败时显示明确不可用状态；不以公开 API 参数拼装内部请求。
- 未记录的新 DSM build 或 VMM 版本默认关闭全部内部写能力。
- 网络 `set/delete`、虚拟机和镜像的创建、修改、删除及动作只有在专用目标完成行为验证后才能进入发布兼容范围。

## 客户端与测试

- 本记录不新增或变更客户端实现路径，仅把现有兼容条目从汇总索引迁移为独立稳定记录。
- 兼容索引：`contracts/private-api/compatibility.json`。
- 事实来源：`docs/api/DSM_WEB_API_REFERENCE_ZH.md` 与 `docs/compatibility/DSM_COMPATIBILITY_MATRIX.md`。
- 后续 fixture 必须彻底脱敏虚拟机、主机、网络、存储、镜像、日志、地址和路径信息。

## 安全与副作用

- VMM 数据可能包含虚拟机名称、网络地址、存储位置、镜像名称、日志正文和远程控制信息，不得写入普通日志或提交原始响应。
- 电源、重置、创建、修改、删除、克隆、迁移、导出和网络变更均为高风险写操作；当前没有行为验证，不得开放。
- 后续开放写能力时必须具备明确确认、权限检查、稳定目标识别、防重复提交和写后最终状态复查。
- 远程控制地址生成逻辑已有记录，但本端点记录不保存真实地址、会话值或连接令牌。

## 未验证事项

- 除日志外各内部 API 的完整参数、响应 Schema、权限与错误码。
- 网络 `set/delete` 的实际方法、参数和写后状态。
- 虚拟机与镜像的创建、修改、删除及生命周期动作。
- 不同 DSM build、VMM 版本、账号权限与连接方式下的兼容性。
