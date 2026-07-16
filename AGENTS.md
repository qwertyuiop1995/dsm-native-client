# 项目协作规则

- 使用中文编写项目文档和代码注释。
- 优先使用 Synology 官方公开 API，内部 API 必须明确标注。
- 不提交密码、OTP、SID、SynoToken、Cookie、DID、证书私钥或真实用户数据。
- 不提交未脱敏的 HAR、PCAP、DSM 响应、文件路径和主机地址。
- 临时调试代码、临时抓包、临时测试账号资料和生成物在任务结束前删除。
- 正式自动化测试属于项目源码，可以保留；一次性调试文件不得提交。
- 修改 API 契约时同步更新三端实现计划和兼容矩阵。
- 危险写操作必须具备确认、权限检查、重复提交保护和结果校验。

## UI/UX Pro Max 自动使用

- 任何会改变界面外观、布局、组件、导航、交互、动效、可访问性或用户体验的任务，都必须自动使用 `ui-ux-pro-max` Skill，不需要用户重复点名。
- 开始 UI/UX 任务前，先运行 `python3 tools/codex/ensure_ui_ux_pro_max.py`；Windows 使用 `python tools\codex\ensure_ui_ux_pro_max.py`。
- 引导脚本仅在全局 Skill 缺失时安装固定版本。安装后必须完整读取 `$CODEX_HOME/skills/ui-ux-pro-max/SKILL.md`；未设置 `CODEX_HOME` 时使用 `~/.codex/skills/ui-ux-pro-max/SKILL.md`。
- 新页面或整体重设计先生成 design system；局部组件、体验审查和 UI 缺陷按 Skill 路由使用对应领域检索。
- Apple、Android、Windows 分别使用 `swiftui`、`jetpack-compose`、`winui` 技术栈指南，不接受 Skill 中与本项目实际技术栈冲突的默认值。
- UI 建议必须保持平台原生体验，并满足浅色/深色模式、键盘、触控、VoiceOver/屏幕阅读器、动态文字和降低动态效果要求。
- Skill 只用于开发期设计支持，不得加入 App 运行时依赖，不得借 UI 修改改变 API、安全策略、Bundle ID、包名、会话存储或业务语义。
- 纯网络、协议、存储、构建、CI 或其他不影响界面的任务不运行该引导脚本。
