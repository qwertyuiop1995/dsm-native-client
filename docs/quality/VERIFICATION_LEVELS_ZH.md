# 功能实现与验证等级

本文统一描述“代码存在”“自动化通过”和“真实环境已验证”的区别。状态必须基于同一
源码版本的可复现证据记录；低等级证据不能替代高等级证据，也不能从其他平台、DSM
build、套件版本或签名方式推断通过。

## 等级定义

| 标识 | 含义 | 最低证据 |
| --- | --- | --- |
| `IMPLEMENTED` | 目标路径已有源码实现 | 代码审查确认入口、错误处理和安全边界存在 |
| `UNIT_TESTED` | 不依赖目标系统的纯逻辑已通过自动化测试 | 测试命令、通过数量和源码提交 |
| `BUILD_VERIFIED` | 目标工程在声明的平台工具链中成功构建 | 构建命令、工具链、架构和签名类型 |
| `SIGNING_REQUIRED` | 下一项验证依赖正式签名、entitlement 或系统注册 | 明确列出所需证书、权限和目标系统 |
| `DEVICE_VERIFIED` | 在真实目标设备和受控测试数据上通过 | 脱敏环境类别、步骤、结果和日期 |
| `COMMUNITY_VERIFIED` | 至少两个相互独立的外部环境给出一致结果 | 已审核的结构化社区报告，不含敏感信息 |
| `STABLE` | 已达到项目定义的稳定支持门槛 | 发布周期、回归覆盖、已知限制和回滚验证 |

这些标识是证据集合，不是自动晋级的单一进度条。例如某功能可以同时标记
`IMPLEMENTED`、`UNIT_TESTED`、`BUILD_VERIFIED` 和 `SIGNING_REQUIRED`；只有完成真实
设备验证后才能增加 `DEVICE_VERIFIED`。社区报告不会提升私有 API 的证据等级，也不
会自动解除内部写接口的兼容保护。

## 记录规则

每个需要发布判断的功能至少记录：

- 功能和平台；
- 源码提交；
- 已获得的等级；
- 测试命令或脱敏证据路径；
- 尚缺的目标平台、签名、设备、DSM build、套件版本或账号权限；
- 已知限制和失败后的恢复方式。

自动化数量变化时只在[当前开发进度](../progress/STATUS.md)维护实时数字。专项计划和
平台矩阵可以引用等级，但不得复制容易失效的测试数量。

## macOS 桌面云盘当前基线

| 范围 | 当前证据 | 尚缺证据 |
| --- | --- | --- |
| 映射、枚举、按需读取、进度、取消、续传和缓存领域逻辑 | `IMPLEMENTED`、`UNIT_TESTED` | 正式签名 Finder 长时间运行 |
| macOS App 与 File Provider Extension 无签名构建 | `BUILD_VERIFIED` | Developer ID 分发构建、entitlement 和扩展注册 |
| App Group 与共享 Keychain | `IMPLEMENTED`、`SIGNING_REQUIRED` | 主 App/Extension 共享容器与访问组实测 |
| Finder domain 生命周期、升级和恢复 | `IMPLEMENTED`、`SIGNING_REQUIRED` | 安装、覆盖升级、重启、睡眠、卸载和孤立 domain 实测 |
| 公证、staple 与 Gatekeeper | `SIGNING_REQUIRED` | 正式发布候选 DMG |

在上述缺口关闭前，桌面云盘不得表述为 `DEVICE_VERIFIED` 或 `STABLE`。完整步骤见
[macOS 桌面云盘发布与升级验收](../compatibility/DESKTOP_CLOUD_DRIVE_RELEASE_ACCEPTANCE_ZH.md)。
