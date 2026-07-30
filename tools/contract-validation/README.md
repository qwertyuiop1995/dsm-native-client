# 契约校验工具

`validate_fixtures.py` 严格校验仓库内脱敏 Fixture 的目录结构、元数据、DSM 响应信封和常见隐私模式：

```bash
python3 tools/contract-validation/validate_fixtures.py
```

校验器会拒绝：

- 缺少 `metadata.json` 或 `response.json` 的样本；
- 不符合稳定环境别名、DSM build、API 或证据等级规则的元数据；
- 未替换的会话、账号、主机和设备字段；
- URL、IPv4、MAC、电子邮箱及常见真实 NAS 路径；
- 样本目录中的额外文件。

校验通过不替代人工隐私复核，也不证明真实 DSM 兼容性。三端解析测试负责验证同一 Fixture 的领域语义。
