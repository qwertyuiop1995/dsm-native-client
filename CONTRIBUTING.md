# 参与开发

## 分支命名

```text
feature/auth-apple
feature/file-browser-android
feature/download-windows
fix/session-expired-apple
docs/recycle-contract
```

## 提交要求

- 一个提交只处理一个明确目标。
- 修改行为时同步更新对应文档、契约和进度状态。
- 提交前确认没有秘密、真实响应、抓包或用户文件。
- 代码注释使用中文，公共类型和方法命名遵循平台语言习惯。

## API 变更

API 相关修改必须说明：

- 接口属于官方、混合还是内部。
- 已验证的 DSM build 和套件版本。
- 请求版本、路径、参数编码和错误处理。
- 功能不可用时的降级行为。

## Pull Request

Pull Request 应包含变更内容、影响平台、验证方法、安全影响和文档更新情况。
