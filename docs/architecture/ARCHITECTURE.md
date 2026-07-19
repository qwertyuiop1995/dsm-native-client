# 总体架构

## 架构目标

- 五个平台保持相同业务语义和安全规则。
- 各平台使用原生 UI、网络、存储和后台任务能力。
- Apple 三端共享 Swift 协议层与业务层。
- Android 和 Windows 独立实现，但共同遵循 `contracts`。
- 官方 API 与内部 API 使用不同 Adapter。

## 分层

```text
原生 UI
  -> ViewModel / Presentation
    -> Repository
      -> Official API Adapter / Internal API Adapter
        -> Capability Discovery
          -> HTTP / TLS / Session / Encoding
            -> Synology DSM
```

## 模块

| 模块 | 职责 |
| --- | --- |
| Core Domain | NAS、会话、文件、任务和错误领域模型 |
| Network | HTTPS、证书、表单、multipart、流式传输 |
| Auth | 能力发现、登录、OTP、退出和会话恢复 |
| Files | 共享目录、分页、详情、缩略图和预览 |
| Transfer | 下载、上传、进度、取消和后台状态 |
| Recycle | 回收站发现、恢复计划、冲突和校验 |
| Local Storage | 非秘密配置、能力缓存和任务元数据 |
| Secure Storage | SID、SynoToken、DID 和证书绑定 |

## 依赖方向

领域层不依赖平台 HTTP 或 UI。平台基础设施实现领域层定义的接口，UI 只依赖业务 Repository。

## API 边界

- 官方：`SYNO.API.*`、公开 File Station API。
- 内部：`SYNO.Core.*` 等未公开接口。
- 内部能力默认关闭，必须按 DSM build 和套件版本验证。

当前工作范围和验收顺序参见[当前开发与验收计划](../development/NATIVE_DSM_FILE_APP_DEVELOPMENT_PLAN_ZH.md)；早期完整规格保存在[第一阶段开发文档归档](../archive/NATIVE_DSM_FILE_APP_DEVELOPMENT_PLAN_V1_ARCHIVE_ZH.md)。
