# 私有 API 机器可读契约

本目录保存 DSM 与套件私有 API 的机器可读版本索引。详细发现过程和人工审查记录位于 [`docs/api/discovery`](../../docs/api/discovery/README.md)。

## 文件

- `compatibility.json`：环境、端点及其版本验证结论。
- `../schemas/private-api-compatibility.schema.json`：索引结构约束。
- `../fixtures-redacted`：经过彻底脱敏的请求或响应样本。

## 更新规则

- 每个环境和端点使用稳定且不含设备信息的标识。
- 不同 NAS 使用 `lab-a`、`lab-b` 等匿名稳定别名；同一 NAS 升级后沿用别名并新建环境基线。
- 每个设备别名最多有一个 `current` 基线；升级后的旧基线保留为 `historical`，新基线通过 `supersedes` 指向旧基线。
- 紧密关联的 API 可以组成端点组，但 `apiNames` 和 `versionMatrix` 必须逐项列出，不能只写模糊的通配名称。
- `environmentId` 必须引用 `environments` 中已存在的环境。
- `evidenceRefs` 只能引用仓库内的脱敏文档、Schema、fixture 或测试。
- 观察到的新版本必须新增 verification，不覆盖旧版本结论。
- `static` 和 `observed` 不能作为写能力兼容依据。
- 内部写能力只有在对应环境达到 `behavior-verified` 后才可标为 `enabled`。
- 真实地址、账号、路径、文件名、消息、日志、凭据和响应正文不得进入本目录。
