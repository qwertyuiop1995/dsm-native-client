# 请求契约校验工具

运行：

```bash
python3 tools/request-contract/validate_contracts.py
python3 -m unittest discover -s tools/request-contract/tests -p 'test_*.py'
```

工具严格校验请求 Fixture 的字段、隐私边界和写操作重试策略，并校验统一写操作结果
示例的状态与数量不变量。它不验证真实 DSM 兼容性。
