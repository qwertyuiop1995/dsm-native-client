# 协议契约

本目录定义 Apple、Android 和 Windows 三套原生实现共同遵循的 DSM 领域语义。

## 内容

```text
schemas/             JSON Schema
error-codes/         DSM 通用错误映射
fixtures-redacted/   彻底脱敏的响应样本
```

## 修改规则

- Schema 变更必须同步评估三端实现。
- 新增字段默认可选，除非所有已验证 DSM 版本都会返回。
- 未知 JSON 字段必须能够忽略。
- fixture 只能来自专用测试数据，并在提交前脱敏。
- 不允许保存真实 SID、主机、账号、共享名、路径或文件内容。
