# Android 第 83 批功能对齐账本

## 目标与证据

| 能力 | macOS / 契约证据 | Android 等价语义 | 安全与降级 | 验证等级 |
| --- | --- | --- | --- | --- |
| 套件可用更新提示 | `Package.list` v2 的 `additional.available_operation`；macOS `NasPackage.isUpgradeAvailable` | 仅当服务端明确返回 `upgrade` 时显示“DSM 中有可用更新”，不提供安装或升级按钮 | 缺字段或没有 `upgrade` 时不显示；安装/升级继续关闭 | 源码与合成自动化 |
| 已安装套件图标 | 已登记内部只读 `SYNO.Core.Package.Thumb.get` v1，参数 `name`、`ver`、`size`；macOS 同契约 | 套件行优先显示真实位图，读取或解码失败时使用现有本地图标 | 运行时 v1 能力门禁；认证仅在 Cookie/请求头；2 MiB 流式上限；只接受 PNG/JPEG/GIF/WebP 签名并要求 Bitmap 解码成功；4 MiB 内存 LRU，不写磁盘 | 源码与合成自动化；真实响应未验证 |
| Registry 官方来源标识 | `ContainerRegistryImage.isOfficial` 已由既有 Registry 搜索响应的 `is_official` 解析 | 搜索结果和当前所选镜像详情仅在 `isOfficial=true` 时显示“官方镜像” | 不从 `trusted`、`automated`、Registry 名称或文案推断，不新增请求和写入口 | 源码与 AndroidTest 编译 |

## 交互转换

- 套件更新是非交互辅助信息，不把“存在更新”转化为危险写入口。
- 套件图标是装饰性图片，屏幕阅读器继续读取套件名称、版本、状态和可用操作；加载失败不增加错误噪声，也不遮蔽列表。
- Registry 官方标识使用双语可见文案和屏幕阅读器语义，位于可换行、可滚动内容中，兼容 2× 字体。

## 边界与非目标

- 不实现套件安装、升级、队列、取消或最终版本回读。
- 不持久保存套件图标、响应、认证信息或 NAS 地址；缓存键只按当前 profile、套件 ID、版本和请求尺寸隔离。
- 不把官方来源解释为镜像安全审计、签名验证或可信保证。
- 不改变 A0–A8 原目标或计分口径；三项均完善既有组合能力，当前仍为 183/202（90.6%），剩余 19 项。

## 本地验证

- `:app:compileDebugKotlin` 通过。
- 套件与 Registry 相关 JVM 51/51，通过且无跳过。
- `:app:compileDebugAndroidTestKotlin` 通过；当前没有连接设备或模拟器，设备测试留给用户统一验证。
- 1976 项 Android 双语资源、82 份请求 Fixture、页面五态、触控、动效、写矩阵、49 项工具测试及契约/Fixture 工具全部通过。
- 独立只读对抗复核发现的文档漂移和失败图标重组重复请求两项 P2 已修复，最终无未解决 P0/P1/P2。
- GitHub [Android Build 31022870159](https://github.com/yuangy1995/dsm-native-client/actions/runs/31022870159) 完成 1245/1245 JVM、Debug/Release/R8、仪器测试 APK、Debug lint 与报告/安装包上传；[Repository Check 31022869808](https://github.com/yuangy1995/dsm-native-client/actions/runs/31022869808) 同步通过。
