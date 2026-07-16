# ADR-0003：官方 API 优先

状态：已接受
日期：2026-07-16

## 决策

核心文件功能优先使用官方 DSM Login 与 File Station API。内部 API 只在官方 API 无法实现必要功能时使用。

## 内部接口准入

1. `SYNO.API.Info` 能发现。
2. 已记录 DSM build 和套件版本。
3. 有脱敏契约样本。
4. 有失败降级和功能开关。
5. 写操作有确认和结果校验。

## 回收站

公开 File Station API 没有专用 Restore API。第一阶段通过 `#recycle` 和官方 `CopyMove` 做验证，不猜测接口名称。
