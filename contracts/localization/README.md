# 客户端语言契约

`supported-locales.json` 是 macOS、iPhone、iPad、Android 和 Windows 的统一语言注册表。

## 当前支持

- `system`：跟随系统首选语言。
- `en`：英语。
- `zh-Hans`：简体中文。

首次启动没有用户偏好时使用 `system`。跟随系统时只判断系统首选语言：

- `en` 及其地区变体解析为英语。
- `zh-Hans`、`zh-CN`、`zh-SG` 解析为简体中文。
- 繁体中文和其他未支持语言统一回退英语。

用户明确选择英语或简体中文后，该选择优先于系统语言并在本机持久保存。语言偏好属于整个 App，不与 NAS 配置、账号、密码或会话绑定。

## 扩展新语言

增加语言时必须在同一次变更中：

1. 更新 `supported-locales.json`。
2. 增加 Apple String Catalog、Android `values-*` 和 Windows `.resw` 资源。
3. 更新各平台语言选择器、语言解析测试和资源完整性校验。
4. 更新中英文 README 与平台进度矩阵。

资源键必须稳定且表达语义。翻译后的文案不得作为导航、筛选、持久化、API 参数或业务分支依据。

提交前运行：

```bash
python3 tools/localization/check_localization.py
```

该检查会验证三套资源的双语键、格式参数和源码引用，并扫描 Apple、Android、Windows 生产源码中的可见文案硬编码。
