# 样本脱敏工具

`sanitize.py` 用于把只保存在本机的 DSM JSON 响应转换为待人工复核的脱敏候选文件。

```bash
python3 tools/fixture-sanitization/sanitize.py \
  /absolute/private/raw-response.json \
  /tmp/response.json \
  --redactions /tmp/redactions.json
```

工具会替换凭据、会话、主机、账号、路径、名称和常见网络标识，并在同一响应内保持占位符稳定。它不能判断聊天正文、日志、照片元数据或业务字段中的所有用户内容，因此输出不能直接提交。

提交前必须：

1. 人工检查候选响应，只保留复现契约差异所需字段。
2. 按 `fixture-metadata.schema.json` 创建 `metadata.json`。
3. 将候选样本放入 `contracts/fixtures-redacted/<模块>/<端点>/<fixtureId>/`。
4. 运行 `python3 tools/contract-validation/validate_fixtures.py`。
5. 删除原始响应、临时候选文件和脱敏字段清单。

原始响应、HAR、Cookie、SID、SynoToken、DID、真实路径和用户数据不得进入仓库。
