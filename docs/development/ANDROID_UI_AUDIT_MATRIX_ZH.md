# Android 界面体验审计矩阵

本文记录不依赖真实设备即可复验的 Android 界面体验证据，并明确自动化证据与
真实辅助服务、真实触控和设备行为之间的边界。矩阵不会把 API 35 模拟器、Compose
语义树或源码检查表述为 TalkBack 或实体机验收。

## 全局动效审计

审计范围为 `android/app/src/main/java/io/github/qwertyuiop1995/dsmnativeclient/ui/**`
中的生产 Compose 界面。显式时间动效必须有明确的状态变化目的、可中断，并遵守
Android 系统动画开关。

| 界面/能力 | 动效目的 | 实现 | 可中断 | 系统关闭动画 | 自动化证据 | 真实设备状态 |
| --- | --- | --- | --- | --- | --- | --- |
| Workspace 预测返回 | 跟随系统手势表达当前页面退出或返回上一级 | `WorkspaceShell.kt` 使用手势进度即时投影位移与轻微透明度；手势取消时仅用 150ms 回弹 | 手势流可取消；取消分支在 `NonCancellable` 中只负责恢复到静止状态，不触发导航或业务写入 | 手势进度和取消回弹均检查 `ValueAnimator.areAnimatorsEnabled()`；关闭时直接 `snapTo(0f)` | `WorkspaceShellTest` 覆盖关闭动画时视觉进度为零；`check_android_motion_audit.py` 限定唯一允许的显式时间动效及双重系统开关门禁 | API 34+ 真机手势取消/完成仍未验证 |
| 文件/照片预览缩放与平移 | 直接跟随双指或拖动手势查看内容 | `graphicsLayer` 使用当前手势比例与偏移即时投影，不使用 `tween`、`spring` 或其他时间插值 | 松手即停止，状态可立即复位 | 不属于时间动效；系统关闭动画时不会产生额外时间插值 | 静态门禁明确不把 `graphicsLayer` 即时手势投影误判为时间动效 | 真实触控、厂商手势冲突仍未验证 |
| Material 3 标准组件反馈 | 按压、抽屉、弹窗等平台标准状态反馈 | 使用 Material 3 组件默认实现，项目未自建时间参数或无限循环动效 | 由平台组件管理 | 由 Android/Compose 平台组件响应系统动画设置 | 静态门禁阻止生产 UI 新增未经记录的显式时间动效 API | 不以源码审计代替真实设备观感 |

### 静态门禁

在仓库根目录运行：

```bash
python3 tools/codex/check_android_motion_audit.py
python3 -m unittest discover -s tools/codex/tests -p 'test_check_android_motion_audit.py'
```

门禁扫描生产 UI 的 Android/Compose 显式时间动效导入和调用。当前只允许
`WorkspaceShell.kt` 中预测返回所需的 `Animatable`、`animateTo`、`tween` 和
`ValueAnimator` 精确源码行，并要求手势进度与取消回弹都存在系统动画开关。
新增动效不能通过扩大通配白名单绕过审计；应先说明用户可见目的、中断语义和系统
关闭动画行为，再精确更新矩阵、门禁与测试。

### 审计结论与边界

- 当前生产 UI 没有自定义无限循环动效、装饰性时间动效或不受系统设置控制的显式
  时间动效。
- 当前唯一显式时间动效只用于预测返回取消后的视觉复位，不改变导航、网络请求、
  持久状态或业务结果。
- 此结论可由源码和轻量自动化复验；真实预测返回手势、触控采样、OEM 动画实现及
  感知体验继续保留为未验证，不得据此宣称实体机验收完成。

## 页面状态与 2× 字体矩阵

- 页面五态已经按 29 个生产页面/弹窗文件闭环；三个页面矩阵测试在 API 35
  `Medium_Phone_API_35` 共 56/56 通过。静态表单、已加载实体详情和没有筛选器的列表
  只覆盖真实适用态，不制造虚假 loading/error/筛选空。
- 严格按 `fontScale = 2f` 复核，不把 `Density(2f, 1f)` 的显示密度测试冒充大字体。
  当前 21 个主页面/页根中 18 个已有生产 Composable 证据；缺口为
  `TransfersScreen`、`NasPerformanceScreen` 和 NAS 日志页根。
- 确认框按通用 `ConfirmDialog`、13 个专用确认组件以及文件上传覆盖确认、文本修改
  丢弃确认统计；当前只有 `RemoteAccessConfirmationDialog` 有明确 2× 证据，其余保持
  未完成。宿主 `Box` 的宽高不会约束独立 `Dialog` 窗口，因此只继承 `fontScale=2f`
  的测试不得表述为已完成小屏对话框验收。
- 持久反馈卡仍缺 `DownloadSettingsMutationFeedbackCard`、DDNS 反馈/失败卡、共享
  `ManagementMutationFeedbackCard`、共享 `SettingsMutationFeedbackCard` 和
  `PowerActionFeedbackCard` 的 2× 证据；既有 Chat、File Station、Download 创建/控制/RSS、
  VMM、连接、区域、文件服务、终端、代理和 Ethernet 反馈卡已有局部证据。

因此“全部主页面、确认框和持久反馈卡完成 2× 字体矩阵”继续保持未勾选；真实 TalkBack、
平板/折叠屏、键盘鼠标、OEM 字体/显示缩放和实体机设备矩阵也继续保持未验证。
