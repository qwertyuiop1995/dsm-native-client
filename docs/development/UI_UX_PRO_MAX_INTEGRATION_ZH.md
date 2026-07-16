# UI UX Pro Max 项目接入说明

## 目标

岚仓在后续 UI 实现、交互优化和体验审查中自动使用 UI UX Pro Max，不要求用户在每次任务中手动点名。

UI UX Pro Max 是开发期设计 Skill，不是 Apple、Android 或 Windows App 的运行时依赖。

## 自动触发

项目根目录的 `AGENTS.md` 规定，任何涉及以下内容的任务都必须自动使用该 Skill：

- 页面、布局、组件和视觉层级。
- 导航、表单、反馈、动效和交互。
- 配色、字体、间距、图标和设计系统。
- 深色模式、键盘、触控和无障碍体验。

纯 API、网络、存储、构建和 CI 任务不会触发安装或设计检索。

## 新设备自动安装

UI/UX 任务开始前，Codex 必须运行：

```bash
python3 tools/codex/ensure_ui_ux_pro_max.py
```

Windows 使用：

```powershell
python tools\codex\ensure_ui_ux_pro_max.py
```

脚本行为：

1. 从 `CODEX_HOME` 或默认 `~/.codex` 定位全局 Skill。
2. 同时验证 `SKILL.md` 和 `scripts/search.py`。
3. 完整安装存在时不执行网络请求。
4. Skill 缺失时通过官方 npm CLI 安装固定版本 `2.11.0`。
5. 发现残缺目录时拒绝覆盖并要求人工检查。
6. 缺少 Python 或 Node.js 时不自行安装系统软件，而是停止并提示用户。

## 技术栈路由

| 平台 | UI UX Pro Max stack |
| --- | --- |
| macOS、iPhone、iPad | `swiftui` |
| Android | `jetpack-compose` |
| Windows | `winui` |

新页面或整体重设计必须先生成 design system。局部组件和体验问题可按 `style`、`ux`、`color`、`typography`、`icons` 等领域补充检索。

## 用户文案

- 界面默认面向普通用户，不假设用户了解 API、协议、证书链、会话存储或内部兼容机制。
- 主流程使用用户熟悉的对象和动作，例如“NAS 地址”“用户名”“连接”“重新登录”。
- 安全指纹等必须展示的技术信息先用通俗语言解释，再作为可核对的次级详情呈现。
- 错误提示同时给出原因和恢复建议；内部错误码、请求标识和调试信息不出现在默认界面。
- 每次 UI 修改都要审查新增和受影响区域的全部可见文案，避免同一页面混用用户语言与开发术语。

## 验证

引导脚本的自动化测试不访问网络，也不会修改真实的 Codex 目录：

```bash
python3 -m unittest discover -s tools/codex/tests -p 'test_*.py'
```

## 安全边界

- 安装只发生在开发用户的 Codex Skill 目录，不写入 App 沙箱或发布产物。
- 不在构建脚本、App 启动、CI 或测试中自动执行安装。
- 不把第三方 Skill 整包提交仓库，避免来源混淆和无控制更新。
- 版本升级必须修改引导脚本中的固定版本，并重新验证三端指南与安装流程。
- UI 工作不得改变 API、安全策略、Bundle ID、包名、Keychain、会话或用户数据兼容性。
