# 岚仓社区兼容性计划

[English](COMMUNITY_COMPATIBILITY_PROGRAM_EN.md)

社区兼容性计划用于收集不同 NAS 型号、DSM Build、套件版本和客户端平台上的结构化测试结果，帮助用户判断自己的环境是否已有实际使用记录，也帮助维护者决定优先复验的组合。

社区报告是用户自愿提交的观察结果，不等同于项目维护者的实机验收，也不能替代私有 API 发现证据。维护者验证记录仍以 [`DSM_COMPATIBILITY_MATRIX.md`](DSM_COMPATIBILITY_MATRIX.md) 和 [`contracts/private-api/compatibility.json`](../../contracts/private-api/compatibility.json) 为准。

## 参与方式

普通用户可以使用 GitHub 的“社区兼容性报告 / Community compatibility report”表单。熟悉 GitHub 的贡献者也可以参照 [`example-report.json`](../../contracts/community-compatibility/examples/example-report.json) 提交结构化报告 Pull Request。

提交前：

1. 使用正式发布的岚仓版本，不使用带临时调试代码的构建。
2. 阅读并执行 [`社区兼容性测试指南`](COMMUNITY_TEST_GUIDE_ZH.md)。
3. 只测试自己有权使用的 NAS、账号和数据。
4. 写操作只对专门创建、可以丢弃的测试项目执行。
5. 删除所有真实文件名、路径、账号、主机和错误响应。

## 收集范围

首版收集：

- 岚仓版本、客户端平台和平台版本。
- NAS 产品型号与 CPU 架构。
- DSM 版本、Build 和 Update 编号。
- 与测试有关的套件版本。
- 连接方式类别、账号权限类别和证书类别。
- 固定能力 ID 对应的通过、失败、部分通过、跳过或不支持结果。
- 失败类别，不收集原始错误正文。
- 公开来源 Issue 或 Pull Request 编号，用于审核和去重；结构化数据不保存贡献者用户名。

NAS 产品型号是公开产品标识，可以提交。以下内容禁止提交：

- 序列号、设备名称、MAC 地址、IP、域名、端口和 QuickConnect ID。
- 用户名、密码、OTP、SID、SynoToken、Cookie、DID 或证书内容。
- 共享名、卷名、文件名、文件路径、聊天内容和容器环境变量。
- 日志、截图、HAR、PCAP、DSM 原始响应、崩溃转储或用户文件。

第一阶段不接受任何日志附件。遇到失败时，只选择固定的失败类别；如果需要进一步排查，请按 [`SECURITY.md`](../../SECURITY.md) 判断应使用公开缺陷报告还是私密安全渠道。

## 审核与证据状态

| 状态 | 含义 |
| --- | --- |
| `submitted` | 结构化报告已提交，尚未完成审核 |
| `reviewed` | 格式、版本信息和隐私检查已通过 |
| `corroborated` | 至少两个不同贡献者在相同版本组合上提交了相符结果 |
| `maintainer-verified` | 维护者在已记录环境中完成了复验 |
| `disputed` | 同一版本组合存在互相冲突的报告 |
| `superseded` | 报告已被同一环境的新版本测试取代 |

审核只确认报告结构合理且没有明显隐私数据，不保证结论真实或完整。社区矩阵显示报告数量和冲突，不用多数结果覆盖失败记录。

## 数据来源与生成流程

机器可读数据位于：

```text
contracts/community-compatibility/
├── capabilities.json
└── reports/*.json
```

运行：

```bash
python3 tools/community-compatibility/validate.py
python3 tools/community-compatibility/generate.py
```

生成：

- [`COMMUNITY_COMPATIBILITY_MATRIX_ZH.md`](COMMUNITY_COMPATIBILITY_MATRIX_ZH.md)
- [`COMMUNITY_COMPATIBILITY_MATRIX_EN.md`](COMMUNITY_COMPATIBILITY_MATRIX_EN.md)

生成文件不得直接手改。CI 会验证报告、隐私规则、能力 ID 和生成结果是否同步。

## 版本与兼容结论

兼容性组合至少由以下维度决定：

```text
NAS 型号 + CPU 架构 + DSM Build/Update + 客户端平台 + 岚仓版本
```

套件相关能力还必须记录对应套件版本。一个组合通过不能推导其他型号、DSM Build、平台或套件版本也兼容。升级 DSM、套件或岚仓后，应提交新报告而不是覆盖历史记录。

## 维护者处理流程

首次启用时，仓库管理员应在 GitHub 创建 `compatibility-report` 和 `needs-review` 标签。标签不存在不会阻止表单显示，但 GitHub 不会自动为新报告添加标签。

1. 检查 Issue 或 Pull Request 是否包含禁止信息。
2. 无法安全编辑时关闭报告，并请贡献者重新提交；不要在评论中重复敏感内容。
3. 分配下一个 `cc-NNNNNN` 报告 ID。
4. 将公开来源记录为 `issue-N` 或 `pull-N`，再把固定字段写入 `contracts/community-compatibility/reports/`。
5. 根据核验程度设置证据状态。
6. 运行校验和矩阵生成命令。
7. 只提交结构化报告、生成矩阵和必要文档，不保存原始附件。

发现疑似凭据或真实用户数据时，不得合并，也不得复制到外部系统。

## 第二阶段路线

第二阶段保持使用第一阶段的结构化数据契约，只有在实际报告数量、维护成本或用户需求证明有必要时才扩展。计划范围：

1. 提供维护者辅助命令，将已审核 Issue 内容转换为候选 JSON，自动分配报告 ID、校验能力 ID，并生成待复核差异；工具不得直接写入主分支。
2. 检测重复来源、重复环境、同一环境的冲突结果和被新版本取代的报告，辅助维护者设置 `corroborated`、`disputed` 和 `superseded`。
3. 按版本化测试套件增加 Photos、Chat、Download Station、Container Manager、Virtual Machine Manager 和 Storage Manager 能力；新增能力必须保持旧报告可读取。
4. 当 Markdown 矩阵确实难以浏览时，从同一份已审核 JSON 生成静态筛选页，支持按 NAS 型号、DSM Build、平台、岚仓版本、套件和结果筛选，不建立独立用户数据库。
5. 设计五端本地“兼容性诊断摘要”导出能力：仅通过字段白名单生成、导出前本地预览、用户主动确认、默认不含日志正文，并同步完成中英文资源和无障碍审查。
6. 建立匿名统计口径、报告过期策略、测试套件升级说明和定期复核流程，但不把报告数量直接解释为设备市场占有率或总体成功率。

第二阶段明确不包含：

- 自动遥测、后台上传或未征得用户同意的数据收集。
- 接受任意日志、HAR、PCAP、截图、崩溃转储或 DSM 原始响应。
- 机器人绕过人工隐私审核直接合并报告或写入主分支。
- 因社区报告通过而自动启用内部写接口。

进入第二阶段前至少应满足：第一阶段真实报告流程已运行稳定、Schema 变更策略已验证、隐私事件处理责任明确，并有足够报告证明自动化可以降低实际维护成本。
