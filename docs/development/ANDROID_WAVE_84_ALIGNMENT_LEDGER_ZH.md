# Android 第 84 批功能对齐账本

## 目标与证据

| 能力 | macOS / 契约证据 | Android 等价语义 | 安全与降级 | 验证等级 |
| --- | --- | --- | --- | --- |
| VMM 任务页可见期轮询 | 公开 `SYNO.Virtualization.API.Task.Info` v1；既有任务中心与 2 秒增量刷新 | 只有任务页真实可见且存在未结束任务时轮询；切换到其他 VMM 分区或返回根页立即停止 | 不新增请求类型，不持久化任务 token，不把模块可见冒充任务页可见 | 源码与自动化通过；设备未验证 |
| VMM 任务固定深页 | 既有 VMM 任务中心；第 82 批固定无载荷深页规则 | `lanstash://open/virtual-machines/tasks` 只打开任务分区，系统返回回到 VMM 根页 | 只保存目标枚举；严格区分协议与主机大小写，并拒绝查询、片段、用户信息、端口、编码路径、额外层级和业务对象；Task.Info v1 缺失时拒绝 | 源码与自动化通过；设备未验证 |
| NAS 性能固定深页 | 已登记只读 `SYNO.Core.System.Utilization.get` v1；既有性能趋势页 | `lanstash://open/nas-settings/performance` 只打开性能分区，进入后启动既有可见期采样，返回根页后停止 | 只保存目标枚举；迟到回调按代次、NAS、Repository、页签和可见性隔离；不持久化原始响应；能力缺失时拒绝，不新增写入口 | 源码与自动化通过；设备未验证 |

## 交互转换

- 固定深页使用现有 Compose 页面和系统返回，不新增平行页面、弹窗或业务载荷路由。
- VMM 任务轮询归属任务分区可见性，避免用户查看虚拟机、映像、网络或日志时继续产生无关请求。
- 性能采样继续遵守既有暂停、离页停止和错误重试行为；固定入口只决定初始分区，不改变采样契约。

## 边界与非目标

- 不实现任务对象深链、任务 token 持久化、任意 NAS 设置深链或携带 NAS 身份的外部 URI。
- 不实现 VMM 高级硬件编辑、迁移、克隆、导出、noVNC、Container 写操作或新的私有 API。
- 不把固定深页冒充任意业务对象深链、全部深层页、真实进程死亡或真机预测返回验收。
- 三项均完善既有组合目标，不拆分、删除或重复计分；A0–A8 保持 183/202（90.6%），剩余 19 项。

## 验证计划

- 外部 URI 严格解析、Workspace 未就绪、Activity 重建、最新请求覆盖、能力门禁、同模块根页收口和系统返回。
- VMM 任务页进入、切出、未结束任务完成及 Repository/NAS 切换时的轮询启停。
- NAS 性能深页进入、返回和模块切换时的采样启停。
- 聚焦 JVM、Debug 与 AndroidTest Kotlin 编译、双语资源、页面/触控/动效/写矩阵、契约与 GitHub 完整门禁。
- 当前实体机与真实 NAS 行为按用户安排留待统一打包验证。

## 当前验证结果

- 聚焦 JVM 19/19 通过，Debug 与 AndroidTest Kotlin 编译通过。
- 49/49 工具测试、1976 项 Android 双语资源、82 份请求 Fixture，以及页面五态、触控、动效、写操作矩阵和契约检查通过。
- 独立对抗复核发现的同模块根路由未关闭深页、性能迟到回调污染两项 P1，以及 URI 大小写宽松解析一项 P2 均已修复；第二轮复核无未解决 P0/P1/P2。
- GitHub [Android Build 31028760878](https://github.com/yuangy1995/dsm-native-client/actions/runs/31028760878) 完成完整 JVM 1248/1248（0 失败、0 跳过）、Debug/Release/R8、仪器测试 APK、Debug lint 和四组产物上传；[Repository Check 31028761405](https://github.com/yuangy1995/dsm-native-client/actions/runs/31028761405) 同步通过。
