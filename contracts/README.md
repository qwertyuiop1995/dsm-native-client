# 协议契约

本目录定义 Apple、Android 和 Windows 三套原生实现共同遵循的 DSM 领域语义。

## 内容

```text
schemas/             JSON Schema
error-codes/         DSM 通用错误映射
fixtures-redacted/   彻底脱敏的响应样本
```

照片基础契约包括 `photo-space.schema.json`、`photo-item.schema.json` 和 `photo-page.schema.json`。其中照片页面的分页位置基于 NAS 原始目录项目计算，即使客户端过滤了非媒体文件，也必须使用 `nextOffset` 继续读取，避免重复或遗漏。

Chat 基础契约包括能力、用户、会话、消息、附件、投票、提醒和消息分页 Schema。它们定义岚仓三端共同使用的领域语义，不代表群晖内部 API 的原始字段；实际 Adapter 必须先经过脱敏实机契约验证，再映射到这些模型。

## 修改规则

- Schema 变更必须同步评估三端实现。
- 新增字段默认可选，除非所有已验证 DSM 版本都会返回。
- 未知 JSON 字段必须能够忽略。
- fixture 只能来自专用测试数据，并在提交前脱敏。
- 不允许保存真实 SID、主机、账号、共享名、路径或文件内容。
