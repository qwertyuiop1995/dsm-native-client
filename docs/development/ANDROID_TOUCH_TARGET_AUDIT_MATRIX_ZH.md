# Android 点击目标审计矩阵

## 目标与口径

- Android 触控点击区域至少为 `48dp × 48dp`。
- `Button`、`TextButton`、`IconButton`、`Switch`、`Checkbox`、`RadioButton`、`Tab`、`Chip`、`ListItem` 等 Material 组件沿用 Compose Material 的原生最小交互尺寸、语义和按压反馈。
- 直接在 `Row`、`Card` 或其他 `Modifier` 上使用 `clickable`、`combinedClickable`、`toggleable`、`selectable` 时，源码必须显式提供双向至少 48dp 的尺寸约束；横向占满或按权重分配视为宽度约束。
- 自定义点击不得关闭原生 `indication`。新增 `pointerInput` 或 `detectTapGestures` 点击手势必须先单独审计，静态门禁默认拒绝。
- 本矩阵只证明源码约束、自动化测试和 API 35 模拟器结果；不同 OEM 的字体缩放、显示缩放、触控精度与 TalkBack 实体机结论仍为“未验证”。

## 自定义交互盘点

| 模块 | 自定义目标 | 尺寸与交互依据 | 自动化证据 |
|---|---|---|---|
| 登录 | 记住密码、自动登录、已保存 NAS 卡片 | 整行占宽且高度至少 48dp；行统一处理开关动作，避免嵌套重复点击；保留 ripple 与 Switch 状态语义 | 静态门禁；`LoginScreenTest` 聚焦验证 |
| 文件 | 列表项、网格卡片的点击与长按 | 项目占满单元格宽度且高度至少 48dp；`combinedClickable` 保留点击、长按语义与原生反馈 | 静态门禁；`FileBrowserAdaptiveScreenTest` 聚焦验证 |
| 照片 | 照片/文件夹卡片 | 卡片占满网格单元格且高度至少 48dp；保留 Card 与 clickable 原生反馈 | 静态门禁；`PhotoBrowserAdaptiveScreenTest` 聚焦验证 |
| Chat | 新会话成员复选行 | 整行占宽且高度至少 48dp；使用 `toggleable(Role.Checkbox)`，由整行统一处理状态切换 | 静态门禁；`ChatConversationDialogTest` 聚焦验证 |
| 下载 | 任务管理动作行、活动重试与 BT 搜索选项 | 任务动作行占满宽度且高度至少 52dp；搜索、重试、展开按钮及提供方/类别/排序 FilterChip 至少 48dp，保留 Material 选中与禁用语义 | 静态门禁；既有下载管理测试及第 80 批 `DownloadDiscoveryDialogTest`、`DownloadActivityUiTest` |
| 虚拟机与容器 | 自动启动、放置选项、映像类型、存储空间、NAS 文件选择与任务清理 | 整行占宽且高度至少 48dp；映像类型使用原生 FilterChip，存储与文件使用单选组及 `Role.RadioButton`；已结束任务清理入口及确认两端按钮使用 Material 组件且至少 48dp | 静态门禁；既有虚拟机测试、`VirtualMachineImageImportDialogTest` 及第 80 批 `VirtualMachineTaskCleanupDialogTest` |
| NAS 管理 | DDNS、网口、区域、远程访问、硬件、安全与服务开关/选项 | 整行或等权选项至少 48dp 高，宽度由占满或权重保证；保留 Switch/RadioButton 角色 | 静态门禁；既有管理与危险确认 API 35 测试 |
| 公共动作行 | 通用操作入口 | 占满宽度且固定 52dp 高；保留 clickable ripple | 静态门禁；调用方既有聚焦测试 |

当前生产 UI 没有 `pointerInput`/`detectTapGestures` 点击目标。所有显式自定义点击链由 `tools/codex/check_android_touch_targets.py` 全量扫描；新增目标未声明 48dp 双向尺寸、禁用按压反馈或新增手势点击时门禁失败。

## 验证分层

1. 静态门禁：全量扫描生产 UI 的自定义点击修饰符，确保至少 48dp、宽度来源和按压反馈。
2. Python 单测：覆盖合规目标、47dp 反例、缺宽/缺高、禁用反馈与新增手势点击反例。
3. API 35 聚焦测试：复用登录、文件、照片、Chat、下载、NAS 管理和危险确认测试，并对高频节点执行 `assertHeightIsAtLeast(48.dp)`。
4. 用户后续打包验证：实体机显示缩放、最大字体、横竖屏、TalkBack 与 OEM 行为；这些条件未在本轮冒充已验证。
