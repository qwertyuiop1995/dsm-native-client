# Synology DSM Web API 原生应用开发参考

> 文档版本：1.0.0
> 整理日期：2026-07-16
> 项目源码基线：`apaipai/dsm_helper` 的 `dev` 分支提交 `8c104e9a783a1acaf366a250e5fcd1d623f14eb2`
> 该提交日期：2024-06-25；本文不会把更晚的 DSM/套件行为推断为已经验证
> 适用范围：面向 Android、iOS、macOS 等原生客户端的 HTTP API 调用层设计

## 1. 文档目的与边界

本文将群晖 DSM Web API 分为三类：

| 标记 | 含义 | 维护策略 |
| --- | --- | --- |
| `官方` | 群晖提供正式开发文档，接口名称、方法和参数有公开说明 | 可作为核心功能依赖，但仍需运行时查询版本 |
| `混合` | 同一产品存在官方 API，但项目使用了不同名称、更新版本或额外方法 | 优先调用官方版本，内部变体单独适配 |
| `内部` | DSM 网页或套件自身使用，但没有找到对应的正式 API 规范 | 视为易变实现细节，必须做能力探测和降级 |

本文不是群晖官方文档的替代品。官方接口的完整字段、限制与错误码应以群晖原文为准；内部接口仅记录项目源码中观察到的调用方式，不代表群晖承诺兼容。

### 1.1 资料来源

- [DSM Login Web API Guide](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Os/DSM/All/enu/DSM_Login_Web_API_Guide_enu.pdf)
- [File Station Official API Guide](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/FileStation/All/enu/Synology_File_Station_API_Guide.pdf)
- [Download Station Web API Guide](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/DownloadStation/All/enu/Synology_Download_Station_Web_API.pdf)
- [Virtual Machine Manager API Guide](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Package/Virtualization/All/enu/Synology_Virtual_Machine_Manager_API_Guide.pdf)
- [DSM Developer Guide 7](https://global.download.synology.com/download/Document/Software/DeveloperGuide/Os/DSM/All/enu/DSM_Developer_Guide_7_enu.pdf)
- [`dsm_helper` 项目源码](https://gitee.com/apaipai/dsm_helper/tree/dev/)
- 项目集中式接口实现：[`lib/utils/api.dart`](https://gitee.com/apaipai/dsm_helper/blob/dev/lib/utils/api.dart)
- 项目模型与分模块接口：[`lib/models/Syno`](https://gitee.com/apaipai/dsm_helper/tree/dev/lib/models/Syno)

### 1.2 尚未完成的动态验证

本文完成了官方资料与静态源码对照，但没有连接具体 NAS 对所有内部接口逐项执行。正式开发时应补充以下验证矩阵：

- DSM 6 与 DSM 7 的具体版本及 build number。
- 安装的 File Station、Download Station、Container Manager、Synology Photos、VMM 版本。
- 管理员与普通用户的权限差异。
- 请求格式、返回字段和错误码的实际差异。

## 2. DSM Web API 通用协议

### 2.1 基础地址

推荐只使用 HTTPS：

```text
https://<NAS_HOST>:5001/webapi/<API_PATH>
```

常见路径：

| 路径 | 用途 |
| --- | --- |
| `/webapi/entry.cgi` | 当前登录指南中的 API 查询固定入口，也是 DSM 6/7 大量 API 的统一入口 |
| `/webapi/query.cgi` | 旧版 File Station/Download Station 指南中的 API 查询入口 |
| `/webapi/auth.cgi` | 旧文档中的认证入口；新登录文档通常返回 `entry.cgi` |
| `/webapi/FileStation/...` | 部分旧版 File Station 专用 CGI |
| `/webapi/DownloadStation/...` | 旧版 Download Station 专用 CGI |

不要硬编码业务 API 路径。启动时先在 `/webapi/entry.cgi` 调用 `SYNO.API.Info`；兼容较旧 DSM 时，如该入口明确不存在，再回退 `/webapi/query.cgi`。之后始终使用 NAS 返回的 `path`。

### 2.2 通用请求字段

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `api` | String | API 名称，例如 `SYNO.FileStation.List` |
| `version` | Int | API 版本，必须处于 `minVersion...maxVersion` 范围内 |
| `method` | String | API 方法，例如 `list`、`get`、`start` |
| `_sid` | String | 使用 SID 模式登录时的会话 ID |
| `SynoToken` | String | 开启 SynoToken 后的 CSRF 令牌，部分管理接口需要 |

建议默认采用 `POST` 和 `application/x-www-form-urlencoded`。虽然官方示例经常使用 GET，但 GET 会把密码、SID、文件路径等写入 URL、代理日志和浏览器历史。

### 2.3 `requestFormat=JSON`

`SYNO.API.Info` 的响应可能包含：

```json
{
  "path": "entry.cgi",
  "minVersion": 1,
  "maxVersion": 2,
  "requestFormat": "JSON"
}
```

当 `requestFormat` 为 `JSON` 时，除 `api`、`version`、`method` 等控制字段外，数组、布尔值、对象和字符串参数应按 JSON 值编码后再作为表单字段发送。例如：

```text
path=["/video/a.mp4","/video/b.mp4"]
additional=["size","time","perm"]
overwrite=true
```

不要沿用旧项目中随处手工拼接双引号的方式，应由统一编码器根据 `requestFormat` 编码。

### 2.4 通用响应信封

成功响应：

```json
{
  "success": true,
  "data": {}
}
```

失败响应：

```json
{
  "success": false,
  "error": {
    "code": 105
  }
}
```

部分批处理、文件操作和内部接口会在 `error.errors` 或 `data.result` 中返回嵌套错误，客户端不能只检查 HTTP 状态码。

### 2.5 通用错误码

| 错误码 | 含义 | 建议处理 |
| --- | --- | --- |
| `100` | 未知错误 | 记录已脱敏上下文并提示重试 |
| `101` | 缺少 API、method 或 version | 客户端参数错误 |
| `102` | API 不存在 | 标记功能不支持，不要循环重试 |
| `103` | method 不存在 | 切换适配器或禁用功能 |
| `104` | 版本不支持 | 重新查询 `SYNO.API.Info` |
| `105` | 当前会话权限不足 | 提示权限，不要要求用户直接改用管理员 |
| `106` | 会话超时 | 清理 SID 并重新认证 |
| `107` | 重复登录导致会话中断 | 清理旧会话后重试一次 |
| `108` | 文件上传失败 | 检查大小、空间和传输状态 |
| `109`-`111` | 网络不稳定或系统繁忙 | 有上限地退避重试 |
| `114` | 缺少该 API 所需参数 | 客户端参数错误 |
| `115` | 不允许上传文件 | 提示权限或服务器策略 |
| `116` | 演示站点不允许执行 | 禁用对应操作 |
| `117`-`118` | 网络不稳定或系统繁忙 | 有上限地退避重试 |
| `119` | 会话无效 | 清理 SID 并重新认证 |
| `150` | 请求来源 IP 与登录 IP 不一致 | 不自动重试，检查网络切换或代理 |

## 3. API 能力发现

### 3.1 `SYNO.API.Info` - 官方

| 项目 | 值 |
| --- | --- |
| 当前固定路径 | `/webapi/entry.cgi`；旧 DSM 可回退 `/webapi/query.cgi` |
| version | `1` |
| method | `query` |
| 是否需要登录 | 否 |

请求参数：

| 参数 | 必需 | 说明 |
| --- | --- | --- |
| `query` | 是 | 逗号分隔的 API 名称，或 `all` |

安全的命令行示例：

```bash
curl --fail --silent --show-error \
  --request POST \
  --data-urlencode 'api=SYNO.API.Info' \
  --data-urlencode 'version=1' \
  --data-urlencode 'method=query' \
  --data-urlencode 'query=SYNO.API.Auth,SYNO.FileStation.List' \
  'https://nas.example.com:5001/webapi/entry.cgi'
```

典型响应字段：

| 字段 | 说明 |
| --- | --- |
| `path` | 实际 CGI 路径 |
| `minVersion` | 最低支持版本 |
| `maxVersion` | 最高支持版本 |
| `requestFormat` | 参数编码方式；可能为 `JSON` |

注意：`query=all` 能发现许多内部接口，但“能够发现”不等于“官方公开支持”。

### 3.2 推荐的客户端缓存结构

```json
{
  "nasId": "本地生成的设备标识",
  "dsmBuild": "72806",
  "packages": {
    "FileStation": "3.x",
    "ContainerManager": "24.x"
  },
  "apis": {
    "SYNO.FileStation.List": {
      "path": "entry.cgi",
      "minVersion": 1,
      "maxVersion": 2,
      "requestFormat": "JSON"
    }
  }
}
```

当 DSM build、套件版本或服务器地址变化时，应使能力缓存失效并重新查询。

## 4. 登录、令牌与会话

### 4.1 `SYNO.API.Auth` - 官方

当前登录指南给出的范围为 version 3-7，并推荐 version 6。实际使用前仍应通过 `SYNO.API.Info` 查询。

#### login

| 参数 | 必需 | 版本 | 说明 |
| --- | --- | --- | --- |
| `account` | 是 | 3+ | DSM 用户名 |
| `passwd` | 是 | 3+ | DSM 密码；只在内存中短暂存在 |
| `session` | 否 | 3+ | 会话名，例如 `FileStation`、`DownloadStation` |
| `format` | 否 | 3+ | `cookie` 或 `sid`；原生客户端推荐 `sid` |
| `otp_code` | 否 | 3+ | 双重验证 OTP |
| `enable_syno_token` | 否 | 6+ | 请求返回 SynoToken |
| `enable_device_token` | 否 | 6+ | 请求可信设备 ID |
| `device_name` | 否 | 6+ | 可信设备名称 |
| `device_id` | 否 | 6+ | 已获取的设备 ID |

推荐请求：

```bash
curl --fail --silent --show-error \
  --request POST \
  --data-urlencode 'api=SYNO.API.Auth' \
  --data-urlencode 'version=6' \
  --data-urlencode 'method=login' \
  --data-urlencode 'account=<USERNAME>' \
  --data-urlencode 'passwd=<PASSWORD>' \
  --data-urlencode 'session=NativeClient' \
  --data-urlencode 'format=sid' \
  --data-urlencode 'enable_syno_token=yes' \
  'https://nas.example.com:5001/webapi/entry.cgi'
```

成功响应的关键字段：

| 字段 | 说明 | 存储建议 |
| --- | --- | --- |
| `sid` | 授权会话 ID | Keychain/Android Keystore，退出后删除 |
| `did` | 可信设备 ID | 仅用户明确选择“信任设备”时安全存储 |
| `synotoken` | CSRF 令牌 | 与 SID 同生命周期安全存储 |
| `is_portal_port` | 门户端口标志 | 普通状态字段 |

#### token

version 6 的 `method=token` 可重新查询 SynoToken。若页面或会话重载导致令牌变化，应更新内存中的值。

#### logout

```text
api=SYNO.API.Auth
version=<已探测版本>
method=logout
_sid=<SID>
```

退出成功后，无论服务端响应如何，客户端都应清理本地 SID、SynoToken 和临时 Cookie。

#### 认证错误码

| 错误码 | 含义 |
| --- | --- |
| `400` | 账号不存在或密码错误 |
| `401` | 账号已禁用 |
| `402` | 权限被拒绝 |
| `403` | 需要双重验证 |
| `404` | OTP 验证失败 |
| `406` | 强制执行双重验证 |
| `407` | 来源 IP 被阻止 |
| `408` | 密码已过期且不能更改 |
| `409` | 密码已过期 |
| `410` | 必须修改密码 |

### 4.2 原生应用凭据规则

- 不持久化 DSM 明文密码。
- 不把 `passwd`、`otp_code`、`_sid`、Cookie、SynoToken、DID 写入日志、崩溃报告或分析平台。
- 不把 SID 放入图片 URL、通知文本或剪贴板。
- iOS 使用 Keychain；Android 使用 Keystore 加密后的存储。
- 生物识别只用于解锁本地令牌，不能代替 DSM 的服务端认证。
- 以普通用户完成日常文件操作，高权限操作按需提示并二次确认。

## 5. File Station 官方 API

官方要求使用 `SYNO.API.Auth` 登录；传统会话名为 `FileStation`。下表是适合客户端实现的索引，完整字段以官方 PDF 为准。

### 5.1 接口总览

| API | version | methods | 关键参数/用途 |
| --- | ---: | --- | --- |
| `SYNO.FileStation.Info` | 2 | `get` | File Station 能力、主机名、是否管理员 |
| `SYNO.FileStation.List` | 2 | `list_share`, `list`, `getinfo` | 共享文件夹、目录列表、文件详情 |
| `SYNO.FileStation.Search` | 2 | `start`, `list`, `stop`, `clean` | 异步搜索 |
| `SYNO.FileStation.VirtualFolder` | 2 | `list` | CIFS/NFS/ISO 等虚拟挂载点 |
| `SYNO.FileStation.Favorite` | 2 | `list`, `add`, `delete`, `clear_broken`, `edit`, `replace_all` | 收藏目录 |
| `SYNO.FileStation.Thumb` | 2 | `get` | 获取缩略图二进制 |
| `SYNO.FileStation.DirSize` | 2 | `start`, `status`, `stop` | 异步计算目录大小 |
| `SYNO.FileStation.MD5` | 2 | `start`, `status`, `stop` | 异步计算文件 MD5 |
| `SYNO.FileStation.CheckPermission` | 3 | `write` | 上传或创建前检查写权限 |
| `SYNO.FileStation.Upload` | 2 | `upload` | multipart 文件上传 |
| `SYNO.FileStation.Download` | 2 | `download` | 文件原始流或多文件 ZIP 流 |
| `SYNO.FileStation.Sharing` | 3 | `getinfo`, `list`, `create`, `delete`, `clear_invalid`, `edit` | 共享链接 |
| `SYNO.FileStation.CreateFolder` | 2 | `create` | 创建目录 |
| `SYNO.FileStation.Rename` | 2 | `rename` | 重命名 |
| `SYNO.FileStation.CopyMove` | 3 | `start`, `status`, `stop` | 异步复制和移动 |
| `SYNO.FileStation.Delete` | 2 | `start`, `status`, `stop`, `delete` | 异步或同步删除 |
| `SYNO.FileStation.Extract` | 2 | `start`, `status`, `stop`, `list` | 解压和查看压缩包 |
| `SYNO.FileStation.Compress` | 3 | `start`, `status`, `stop` | 异步压缩 |
| `SYNO.FileStation.BackgroundTask` | 3 | `list` | 汇总后台文件任务 |

### 5.2 列出共享文件夹

```text
api=SYNO.FileStation.List
version=2
method=list_share
offset=0
limit=100
sort_by=name
sort_direction=asc
additional=["real_path","size","owner","time","perm","mount_point_type","volume_status"]
```

关键响应字段：`shares[]`、`offset`、`total`。每个共享对象至少关注 `name`、`path`、`isdir`、`additional`。

### 5.3 列出目录与文件详情

`method=list` 常用参数：

| 参数 | 说明 |
| --- | --- |
| `folder_path` | 目录路径，例如 `/video` |
| `offset` / `limit` | 分页；不要假定目录最多 1000 项 |
| `sort_by` | `name`、`size`、`user`、`group`、`mtime`、`atime`、`ctime`、`crtime`、`posix` |
| `sort_direction` | `asc` 或 `desc` |
| `pattern` | 可选名称过滤 |
| `filetype` | `file`、`dir` 或全部 |
| `additional` | `real_path`、`size`、`owner`、`time`、`perm`、`mount_point_type`、`type` 等 |

`method=getinfo` 使用 `path=[...]` 批量读取详情，返回 `files[]`。

### 5.4 搜索

1. `start`：传入 `folder_path`、`pattern`、`recursive`、`search_content`、`search_type`，返回 `taskid`。
2. `list`：使用 `taskid`、`offset`、`limit`、`additional` 轮询结果。
3. `stop`：停止搜索。
4. `clean`：释放搜索任务。

客户端离开搜索页面时应调用 `stop` 或 `clean`，避免服务器残留任务。

### 5.5 收藏、缩略图和校验

| API | 调用要点 |
| --- | --- |
| `Favorite.list` | 支持分页和 `additional` |
| `Favorite.add` | `path`、`name` |
| `Favorite.edit` | `path`、新 `name` |
| `Favorite.delete` | `path` |
| `Thumb.get` | `path` 和缩略图尺寸，响应是二进制而非 JSON |
| `DirSize.start` | `path=[...]`，返回 `taskid` |
| `DirSize.status` | `taskid`，直到 `finished=true` |
| `MD5.start` | `file_path`，返回 `taskid` |
| `MD5.status` | 返回 `finished` 和 `md5` |
| `CheckPermission.write` | `path`、`filename`，可带 `create_only` 或覆盖策略 |

### 5.6 上传

`SYNO.FileStation.Upload.upload` 必须使用 `multipart/form-data`，文件二进制部分必须位于最后。

| part | 必需 | 说明 |
| --- | --- | --- |
| `api` | 是 | `SYNO.FileStation.Upload` |
| `version` | 是 | 运行时探测，官方文档主版本为 2 |
| `method` | 是 | `upload` |
| `_sid` | 是 | SID 模式下 |
| `path` | 是 | 目标目录 |
| `create_parents` | 是 | 是否创建父目录 |
| `overwrite` | 否 | `true/false`，较新版本也可能接受 `overwrite/skip` |
| `mtime`、`crtime`、`atime` | 否 | 毫秒 Unix 时间戳 |
| `file` | 是 | 最后一个 multipart part |

不要在上传失败日志中打印完整本地路径、远程路径、文件内容或 SID。

### 5.7 下载

```text
api=SYNO.FileStation.Download
version=2
method=download
path=["/video/movie.mp4"]
mode=download
_sid=<SID>
```

- 单文件返回文件内容。
- 多文件或目录返回动态生成的 ZIP 流。
- `mode=open` 尝试返回真实 MIME；`mode=download` 返回附件。
- 原生客户端应以流式方式写入临时文件，不能一次性读入内存。
- 如果只能通过 URL 交给系统播放器，避免在 URL 中放 SID；优先使用应用内代理或带认证 Header 的播放器数据源。

### 5.8 共享链接

| method | 关键参数 | 结果 |
| --- | --- | --- |
| `getinfo` | `id` | 单个共享链接详情 |
| `list` | `offset`、`limit`、排序 | `links[]`、`total` |
| `create` | `path=[...]`、可选 `password`、`date_expired`、`date_available` | URL、ID、二维码 |
| `edit` | `id=[...]`、密码、日期 | 空成功响应 |
| `delete` | `id=[...]` | 删除指定链接 |
| `clear_invalid` | 无 | 删除失效和损坏链接 |

共享链接属于敏感数据，不应发送到分析、日志或第三方二维码服务。

### 5.9 文件变更与后台任务

| 操作 | start 关键参数 | 轮询 |
| --- | --- | --- |
| 创建目录 | `folder_path=[...]`、`name=[...]`、`force_parent` | 同步返回 |
| 重命名 | `path=[...]`、`name=[...]` | 同步返回 |
| 复制/移动 | `path=[...]`、`dest_folder_path`、`remove_src`、`overwrite`、`accurate_progress` | `CopyMove.status(taskid)` |
| 删除 | `path=[...]`、`recursive`、`accurate_progress` | `Delete.status(taskid)` |
| 解压 | `file_path`、`dest_folder_path`、`overwrite`、`keep_dir`、`create_subfolder`、`password` | `Extract.status(taskid)` |
| 压缩 | `path=[...]`、`dest_file_path`、`level`、`mode`、`format`、`password` | `Compress.status(taskid)` |

异步任务通用原则：

- `start` 成功后保存 `taskid`。
- 采用退避轮询，前台建议 500 ms、1 s、2 s，后台进一步降低频率。
- 页面销毁不等于取消服务端任务；用户明确取消时调用 `stop`。
- `finished=true` 后再刷新目录列表。

## 6. Download Station API

### 6.1 官方公开接口

群晖公开的 Download Station 文档使用 `SYNO.DownloadStation.*` 命名空间。它与项目源码中的 `SYNO.DownloadStation2.*` 不是同一套接口，不应混用参数或响应模型。

| API | version | methods | 用途 |
| --- | ---: | --- | --- |
| `SYNO.DownloadStation.Info` | 1 | `getinfo`, `getconfig`, `setserverconfig` | 套件信息与基础设置 |
| `SYNO.DownloadStation.Schedule` | 1 | `getconfig`, `setconfig` | 下载计划 |
| `SYNO.DownloadStation.Task` | 1 | `list`, `getinfo`, `create`, `delete`, `pause`, `resume`, `edit` | 下载任务生命周期 |
| `SYNO.DownloadStation.Statistic` | 1 | `getinfo` | 当前下载/上传速度 |
| `SYNO.DownloadStation.RSS.Site` | 1 | `list`, `refresh` | RSS 站点 |
| `SYNO.DownloadStation.RSS.Feed` | 1 | `list` | RSS 条目 |
| `SYNO.DownloadStation.BTSearch` | 1 | `start`, `list`, `getCategory`, `clean`, `getModule` | BT 搜索 |

调用前先通过 `SYNO.API.Info` 查询路径。旧版文档中的路径可能是 `DownloadStation/*.cgi`，不能假定新套件仍保持相同位置。

#### 任务列表

```text
api=SYNO.DownloadStation.Task
version=1
method=list
offset=0
limit=100
additional=["detail","transfer","file","tracker","peer"]
```

典型响应为 `tasks[]`、`offset`、`total`。任务状态可能包括等待、下载、暂停、完成、校验、做种和错误；UI 应保留未知状态，不要把未知值直接映射为“失败”。

#### 创建任务

```text
api=SYNO.DownloadStation.Task
version=1
method=create
uri=<HTTP_URL_OR_MAGNET>
destination=<OPTIONAL_SHARED_FOLDER>
```

上传 `.torrent` 或 `.nzb` 时应按官方文档使用 multipart 请求。磁力链接、下载 URL、文件名和 tracker 地址都可能包含隐私，不得写入分析日志。

#### 控制任务

```text
api=SYNO.DownloadStation.Task
version=1
method=pause|resume|delete
id=<逗号分隔或按服务器要求编码的任务 ID>
force_complete=false
```

`force_complete` 只适用于删除场景且会改变任务结果，必须由用户明确触发。

### 6.2 项目使用的 `DownloadStation2` - 内部接口

项目 `dev` 分支主要调用以下内部接口：

| API | 源码中观察到的方法 | 用途 | 风险 |
| --- | --- | --- | --- |
| `SYNO.DownloadStation2.Task` | `list`, `get`, `create` 以及动态动作方法 | 任务列表、详情、创建和控制 | 高 |
| `SYNO.DownloadStation2.Task.Statistic` | `get` | 速率统计 | 高 |
| `SYNO.DownloadStation2.Settings.Location` | `get` | 下载位置 | 高 |
| `SYNO.DownloadStation2.Task.List` | `get` | 列表初始化 | 高 |
| `SYNO.DownloadStation2.Task.List.Polling` | `download` | 增量轮询 | 高 |
| `SYNO.DownloadStation2.Task.BT.Tracker` | `list`, `add` | Tracker | 高 |
| `SYNO.DownloadStation2.Task.BT.Peer` | `list` | Peer | 高 |
| `SYNO.DownloadStation2.Task.BT.File` | `list` | BT 文件列表 | 高 |

建议原生应用优先实现官方 `SYNO.DownloadStation.*` 适配器。只有当目标套件实际查询到 `DownloadStation2` 且官方接口缺少必要能力时，才启用内部适配器，并将其与官方响应模型隔离。

## 7. Virtual Machine Manager API

### 7.1 官方公开接口

官方 VMM 指南使用 `SYNO.Virtualization.API.*` 命名空间，文档主版本为 1：

| API | methods | 用途 |
| --- | --- | --- |
| `SYNO.Virtualization.API.Task.Info` | `list`, `get`, `clear` | 异步任务 |
| `SYNO.Virtualization.API.Network` | `list` | 网络列表 |
| `SYNO.Virtualization.API.Storage` | `list` | 存储列表 |
| `SYNO.Virtualization.API.Host` | `list` | 主机列表 |
| `SYNO.Virtualization.API.Guest` | `list`, `get`, `create`, `delete` | 虚拟机生命周期 |
| `SYNO.Virtualization.API.Guest.Action` | `poweron`, `poweroff`, `shutdown` | 电源控制 |
| `SYNO.Virtualization.API.Guest.Image` | `list`, `create`, `delete` | 镜像管理 |

创建、删除、镜像导入等操作通常返回任务 ID，应通过 `Task.Info.get` 轮询。`poweroff` 相当于强制断电，必须与正常 `shutdown` 在 UI 中清楚区分。

### 7.2 项目使用的 VMM 内部接口

项目调用的是另一套不带 `.API` 的命名空间：

| API | 方法 | 观察用途 |
| --- | --- | --- |
| `SYNO.Virtualization.Cluster` | `get` | 集群摘要 |
| `SYNO.Virtualization.Host` | `list` | 主机列表 |
| `SYNO.Virtualization.Guest` | `list` | 虚拟机列表 |
| `SYNO.Virtualization.Guest.Action` | `pwr_ctl`, `can_save`, `save`, `restore` | 电源、保存和恢复状态 |

这组调用应标记为内部接口，不能用官方 `SYNO.Virtualization.API.*` 文档来推断其参数。

## 8. 项目源码中的内部与混合接口目录

### 8.1 判定方法

本节的“内部”表示：在本文审阅的群晖公开 PDF 中没有找到相同 API 名称和方法，但在 `dsm_helper` 源码、DSM Web UI 或套件前端中可观察到。它不等于恶意接口，也不等于作者凭空创建；多数是作者观察 DSM 自身请求后进行的客户端复现。

风险等级：

| 等级 | 含义 |
| --- | --- |
| 低 | 只读、容易降级，字段变化影响有限 |
| 中 | 会改配置或依赖套件版本，需要强能力探测 |
| 高 | 管理、删除、关机、安装、远程连接等高影响操作 |

### 8.2 File Station 扩展 - 混合

| API | 方法 | 用途 | 风险 |
| --- | --- | --- | --- |
| `SYNO.FileStation.VFS.Connection` | `delete` | 删除 VFS 连接 | 中 |
| `SYNO.FileStation.Mount` | `mount_remote`, `unmount` | 远程挂载 | 高 |
| `SYNO.FileStation.Property.CompressSize` | `get` | 压缩大小属性 | 低 |
| `SYNO.Entry.Request` | `request` | 将多个子请求合并为批处理 | 中 |

`SYNO.Entry.Request` 的子请求可能分别成功或失败，必须逐项检查结果。不要因为外层 `success=true` 就假定所有修改都完成。

### 8.3 系统状态、连接与日志 - 内部

| API | 方法 | 主要参数/用途 | 风险 |
| --- | --- | --- | --- |
| `SYNO.Core.System` | `info` | 系统与网络信息；源码出现 v1/v3 | 低 |
| `SYNO.Core.System.Utilization` | `get` | `resource`, `type`；CPU、内存、网络等 | 低 |
| `SYNO.Core.System.Process` | `list` | 进程列表 | 中 |
| `SYNO.Core.System.ProcessGroup` | `list`, `service_info` | 服务进程组 | 中 |
| `SYNO.Core.CurrentConnection` | `get`, `kick_connection` | 当前连接与踢出连接 | 高 |
| `SYNO.Core.FileHandle` | `get`, `kick` | 打开的文件与强制断开 | 高 |
| `SYNO.Core.Service` | `get` | 服务状态 | 低 |
| `SYNO.Core.Service.PortInfo` | `load` | 服务端口 | 低 |
| `SYNO.Core.Desktop.Initdata` | `get` | DSM 桌面初始化数据 | 中 |
| `SYNO.Core.Desktop.SessionData` | `getjs` | 登录阶段的桌面会话数据 | 高 |
| `SYNO.Core.UserSettings` | `apply` | DSM 用户设置 | 中 |
| `SYNO.Core.DSMNotify` | `notify` | DSM 通知 | 中 |
| `SYNO.Core.DSMNotify.Strings` | `get` | 通知文本资源 | 低 |
| `SYNO.Core.SyslogClient.Status` | `latestlog_get` | 最新日志 | 中 |
| `SYNO.Core.SyslogClient.Log` | `list` | 系统日志 | 中 |
| `SYNO.Core.SyslogClient.FileTransfer` | `get`, `get_level`, `set_level` | 文件传输日志开关与级别 | 中 |
| `SYNO.LogCenter.History` | `list` | Log Center 历史 | 中 |
| `SYNO.Core.SecurityScan.Status` | `rule_get`, `system_get` | 安全扫描状态 | 低 |

连接、进程、文件句柄和日志可能泄漏用户名、IP、共享路径、文件名与服务信息。客户端只应按需展示，默认禁止遥测上报。

### 8.4 存储、硬盘与硬件控制 - 内部

| API | 方法 | 用途 | 风险 |
| --- | --- | --- | --- |
| `SYNO.Storage.CGI.Storage` | `load_info` | 存储总览 | 低 |
| `SYNO.Storage.CGI.Smart` | `get_health_info` | SMART 健康摘要 | 低 |
| `SYNO.Core.Storage.Volume` | `list` | 存储空间列表 | 低 |
| `SYNO.Core.Storage.Disk` | `disk_test_log_get`, `get_smart_test_log`, `do_smart_test` | SMART 测试与日志 | 中 |
| `SYNO.Core.Hardware.ZRAM` | `get`, `set` | ZRAM 配置 | 高 |
| `SYNO.Core.Hardware.PowerRecovery` | `get`, `set` | 来电自启 | 高 |
| `SYNO.Core.Hardware.BeepControl` | `get`, `set` | 蜂鸣器 | 中 |
| `SYNO.Core.Hardware.FanSpeed` | `get`, `set` | 风扇模式 | 高 |
| `SYNO.Core.Hardware.Led.Brightness` | `get`, `set` | LED 亮度 | 中 |
| `SYNO.Core.Hardware.Hibernation` | `get`, `set` | 休眠设置 | 中 |
| `SYNO.Core.Hardware.PowerSchedule` | `load`, `save` | 电源计划 | 高 |
| `SYNO.Core.ExternalDevice.UPS` | `get`, `set` | UPS 设置 | 高 |
| `SYNO.Core.ExternalDevice.Storage.USB` | `list`, `eject` | USB 设备与安全弹出 | 高 |
| `SYNO.Core.ExternalDevice.Storage.eSATA` | `list` | eSATA 设备 | 低 |
| `SYNO.Core.ExternalDevice.Printer.BonjourSharing` | `get` | 打印机 Bonjour 共享 | 低 |

硬件操作必须使用精确的设备标识并在提交前显示摘要。不要根据数组索引选择硬盘或外接设备。

### 8.5 终端、套件与计划任务 - 内部

| API | 方法 | 主要参数/用途 | 风险 |
| --- | --- | --- | --- |
| `SYNO.Core.Terminal` | `get`, `set` | `enable_ssh`, `enable_telnet`, `ssh_port` | 高 |
| `SYNO.Core.TrustDevice` | `delete`, `logout` | 删除可信设备或退出会话 | 高 |
| `SYNO.Core.Package` | `list`, `get`, `feasibility_check` | 套件与可行性检查 | 中 |
| `SYNO.Core.Package.Info` | `get` | 套件详情 | 低 |
| `SYNO.Core.Package.Server` | `list` | 套件源 | 中 |
| `SYNO.Core.Package.Control` | `start`, `stop` | 启停套件 | 高 |
| `SYNO.Core.Package.Installation` | `install`, `status`, `get_queue`, `cancel` | 安装队列 | 高 |
| `SYNO.Core.Package.Uninstallation` | `uninstall` | 卸载套件 | 高 |
| `SYNO.Core.TaskScheduler` | `list`, `run`, `delete`, `set_enable`, `view`, `result_list`, `result_get_file` | 计划任务及结果 | 高 |
| `SYNO.Core.EventScheduler` | `run`, `delete`, `set_enable`, `result_list`, `result_get_file` | 事件计划任务 | 高 |
| `SYNO.Core.Upgrade.Server` | `check` | DSM 更新检查 | 中 |

套件安装 URL、计划任务脚本和任务结果都可能包含秘密。源码中存在直接安装/执行能力，不应在普通功能页静默触发。

### 8.6 用户、群组、共享与配额 - 内部

| API | 观察到的方法/用途 | 风险 |
| --- | --- | --- |
| `SYNO.Core.User` | `list`, `get`, `set` | 高 |
| `SYNO.Core.Group` | `list` | 中 |
| `SYNO.Core.Group.Member` | `add`, `remove` | 高 |
| `SYNO.Core.NormalUser` | `get`, `set` | 高 |
| `SYNO.Core.User.PasswordExpiry` | `get` | 中 |
| `SYNO.Core.Share.Permission` | `list_by_user` | 中 |
| `SYNO.Core.Quota` | `get` | 中 |
| `SYNO.Core.PersonalSettings` | 配额相关调用 | 中 |
| `SYNO.Core.OTP`, `SYNO.Core.OTP.Admin` | OTP 与管理员设置 | 高 |
| `SYNO.Core.Share` | `list`, `get`, `add`, `set`, `delete`, `get_all_move_task`, `move_status` | 高 |
| `SYNO.Core.RecycleBin` | `start` | 清理回收站 | 高 |

这些接口涉及账号、权限与数据删除。原生客户端应要求重新确认，并只发送用户改变的字段，避免把完整对象回写导致覆盖新设置。

### 8.7 网络、文件服务与 DDNS - 内部

| API 组 | 观察到的方法/用途 | 风险 |
| --- | --- | --- |
| `SYNO.Core.Network` | `get`；网络总览 | 中 |
| `SYNO.Core.Network.Ethernet` | `list`；网卡 | 中 |
| `SYNO.Core.Network.PPPoE` | `list`；PPPoE | 高 |
| `SYNO.Core.Network.Proxy` | `get`；代理 | 中 |
| `SYNO.Core.BandwidthControl` | `get`；账号带宽规则 | 中 |
| `SYNO.Core.Web.DSM` | `get`；DSM HTTP/HTTPS 与门户设置 | 中 |
| `SYNO.Core.FileServ.SMB` | `get`；SMB 设置 | 中 |
| `SYNO.Core.FileServ.FTP` | `get`；FTP 设置 | 中 |
| `SYNO.Core.FileServ.FTP.SFTP` | `get`；SFTP 设置 | 中 |
| `SYNO.Core.FileServ.NFS` | `get`；NFS 设置 | 中 |
| `SYNO.Core.FileServ.AFP` | `get`；AFP 设置 | 中 |
| `SYNO.Core.FileServ.ReflinkCopy` | `get`；写时复制能力 | 低 |
| `SYNO.Core.FileServ.ServiceDiscovery` | `get`；服务发现 | 低 |
| `SYNO.Core.ACL` | `get_bypass_traverse` | 中 |
| `SYNO.Core.Security.Firewall.Rules.Serv` | `policy_check` | 中 |
| `SYNO.Backup.Service.NetworkBackup` | `get` | 中 |
| `SYNO.Core.DDNS.Provider` | `list` | 低 |
| `SYNO.Core.DDNS.Record` | `list`, `set`, `update_ip_address`, `delete`, `test` | 高 |
| `SYNO.Core.DDNS.ExtIP` | `list` | 中 |
| `SYNO.Core.DDNS.Synology` | `get_myds_account` | 高 |

网络与 DDNS 响应可能包含公网 IP、域名、账号和代理配置。抓包样本必须删除这些字段后才能共享。

### 8.8 Container Manager/Docker - 内部

| API | 观察到的方法 | 风险 |
| --- | --- | --- |
| `SYNO.Docker.Container` | `list`, `get`, `start`, `restart`, `stop`, `signal`, `delete`, `get_process` | 高 |
| `SYNO.Docker.Container.Resource` | `get` | 低 |
| `SYNO.Docker.Container.Log` | `get`, `get_date_list` | 高 |
| `SYNO.Docker.Image` | `list`, `delete`, `upgrade_start`, `upgrade_status`, `pull_start`, `pull_status` | 高 |
| `SYNO.Docker.Registry` | `search`, `tags` | 中 |
| `SYNO.Docker.Network` | `list` | 中 |
| `SYNO.Docker.Project` | `list`, `get`, `create`, `delete` | 高 |
| `SYNO.Docker.Log` | `list` | 高 |

这些名称对应旧 Docker/Container Manager Web UI 内部接口。套件升级时名称、字段和流式日志方式很容易改变。容器环境变量、挂载路径、Registry 凭据和日志应视为秘密。

### 8.9 Synology Photos - 内部

| API 组 | 观察到的方法/用途 | 风险 |
| --- | --- | --- |
| `SYNO.Foto.Browse.Album` / `SYNO.FotoTeam.Browse.Album` | 相册列表与详情 | 中 |
| `SYNO.Foto.Browse.Folder` / Team 变体 | 文件夹浏览 | 中 |
| `SYNO.Foto.Browse.Item` / Team 变体 | 照片项目列表 | 中 |
| `SYNO.Foto.Browse.Timeline` / Team 变体 | 时间线 | 中 |
| `SYNO.Foto.Browse.RecentlyAdded` / Team 变体 | 最近添加 | 中 |
| `SYNO.Foto.Browse.GeneralTag` / Team 变体 | 标签 | 高 |
| `SYNO.Foto.Browse.Geocoding` / Team 变体 | 地理位置聚合 | 高 |
| `SYNO.Foto.Thumbnail` / Team 变体 | 缩略图二进制 | 中 |
| `SYNO.Foto.Download` / Team 变体 | 原图下载 | 高 |

源码还包含 DSM 6 时代 Moments/Photo 相关变体，应按产品版本拆分适配。特别注意：项目中部分缩略图和下载 URL 把 `_sid` 拼在查询串中；新应用不要照搬，应使用带认证的请求数据源，避免 SID 出现在日志、历史或第三方播放器中。

### 8.10 其他内部接口

| API | 方法/用途 | 风险 |
| --- | --- | --- |
| `SYNO.SynologyDrive.Index` | `get_native_client_status` | 低 |
| `SYNO.Core.MediaIndexing` | `reindex`, `status` | 中 |
| `SYNO.Core.MediaIndexing.ThumbnailQuality` | `get`, `set` | 中 |
| `SYNO.Core.MediaIndexing.MobileEnabled` | `get`, `set` | 中 |
| `SYNO.Core.MediaIndexing.MediaConverter` | `status` 及动态转换动作 | 中 |

### 8.11 内部接口的调用规则

每个内部 API 必须满足以下条件才能启用：

1. `SYNO.API.Info` 能查询到该 API。
2. 客户端选择 `maxVersion` 与已验证上限的较小值，不能盲目固定源码中的版本。
3. 套件已安装且运行，当前账号权限足够。
4. 对当前 DSM build/套件版本存在已通过的契约测试样本。
5. 接口失败时有明确降级，不自动切换成管理员账号。
6. 写操作有用户确认、幂等保护和审计摘要。

建议为内部适配器使用 feature flag，例如：

```json
{
  "feature": "container.list",
  "api": "SYNO.Docker.Container",
  "verifiedBuilds": ["DSM-7.2.2-72806"],
  "packageRange": "ContainerManager 24.x",
  "enabled": false
}
```

默认值应为关闭，动态探测和本地验证成功后才开启。

## 9. 合法合规的抓包与接口复现流程

只抓取自己拥有或已获得明确授权的 NAS、账号和测试设备。不要抓取他人的会话，不要尝试绕过访问控制，也不要把含秘密的 HAR/PCAP 上传到公共 Issue。

### 9.1 优先方案：浏览器开发者工具

用于观察 DSM Web UI 自己发出的请求，通常不需要中间人证书：

1. 新建专用普通测试账号，给最小权限，并准备无敏感内容的测试共享文件夹。
2. 在独立浏览器配置文件中登录 DSM。
3. 打开开发者工具的 Network，开启 Preserve log，筛选 `webapi`、`entry.cgi`、`query.cgi`。
4. 清空现有记录，只执行一个动作，例如“列出目录”或“暂停测试下载任务”。
5. 记录请求路径、HTTP 方法、Content-Type、`api`、`version`、`method`、业务参数和响应结构。
6. 比较操作前后两次请求，区分初始化请求、轮询请求和真正的写操作。
7. 导出 HAR 前先离线脱敏；更安全的做法是只人工复制所需字段。
8. 完成后退出 DSM、清除浏览器站点数据并删除测试账号或撤销权限。

### 9.2 原生客户端抓包

可使用 Charles、Proxyman 或 mitmproxy，流程相同：

1. 只在隔离测试网络和测试设备上配置 HTTP(S) 代理。
2. 只在测试设备中安装代理 CA；不要安装到生产设备或组织根证书库。
3. 将测试 NAS 主机加入抓取范围，排除其他域名以减少无关隐私。
4. 启动记录后只执行单一动作，立即停止记录。
5. 对照客户端日志中的本地请求 ID，但日志中不得含 SID、密码或响应正文。
6. 导出前按 9.4 的规则脱敏，验证文件中搜索不到秘密。
7. 删除代理 CA、关闭代理、退出会话并删除原始捕获文件。

如果系统或应用启用了证书固定，不要为了抓包在生产构建中关闭 TLS 校验。应使用专门的 Debug 构建，通过受控的调试网络安全配置允许测试 CA，Release 构建保持严格验证。

### 9.3 从单次动作还原 API 契约

对每个功能保留一份脱敏记录：

```yaml
feature: file.list
source: dsm-web-ui
dsm_build: 7.2.2-72806
package: FileStation
package_version: <已脱敏或实际版本>
request:
  path: entry.cgi
  content_type: application/x-www-form-urlencoded
  api: SYNO.FileStation.List
  version: 2
  method: list
  parameters:
    folder_path: /test-share
    offset: 0
    limit: 100
response:
  success: true
  required_fields:
    - data.files
    - data.offset
    - data.total
notes:
  - folder_path 需 URL 编码
```

复现顺序：

1. 先用 `SYNO.API.Info` 验证名称、路径和版本。
2. 用普通测试账号登录并获取独立 SID。
3. 用命令行或最小测试客户端重放一次只读请求。
4. 刻意测试无权限、会话过期、空结果、分页和未知字段。
5. 写操作只作用于可丢弃的测试对象，并先验证读取接口。
6. 将稳定字段设为必需，将版本相关字段设为可选。
7. 在两种 DSM/套件版本上复测后，才能标记为“已验证”。

### 9.4 必须脱敏的字段

| 类型 | 典型字段/内容 | 替换值 |
| --- | --- | --- |
| 凭据 | `account`, `passwd`, `otp_code` | `<REDACTED_CREDENTIAL>` |
| 会话 | `_sid`, `sid`, `SynoToken`, `did`, Cookie | `<REDACTED_SESSION>` |
| 网络身份 | NAS 域名、公网/内网 IP、QuickConnect ID、MAC | `<REDACTED_HOST>` |
| 用户隐私 | 用户名、邮箱、头像、相册、人脸、标签、地理位置 | `<REDACTED_PERSONAL>` |
| 文件数据 | 路径、文件名、共享链接、下载 URL、磁力链接 | `<REDACTED_PATH>` |
| 容器/系统 | 环境变量、Registry 凭据、日志、任务脚本 | `<REDACTED_SECRET>` |
| 设备信息 | 序列号、硬盘序列号、设备 ID | `<REDACTED_DEVICE>` |

脱敏完成后，应再次全文搜索：`sid`、`token`、`cookie`、`passwd`、`Authorization`、NAS 域名、用户名和常见共享目录名。仅把脱敏后的最小样本提交版本库。

## 10. 原生客户端实现建议

### 10.1 分层结构

```text
UI / ViewModel
    -> 业务 Repository
        -> 官方 API Adapter / 内部 API Adapter
            -> 能力发现与版本选择
                -> HTTP、TLS、会话与统一编码层
```

- 官方和内部接口使用不同 Adapter，不共享具体响应 DTO。
- HTTP 层统一负责表单/JSON 参数编码、SID 注入、SynoToken、超时和错误信封。
- Repository 只暴露业务语义，例如 `listFiles()`，不让 UI 接触 API 名称。
- 未知 JSON 字段应忽略；关键字段缺失要产生可诊断但不含隐私的错误。
- 二进制下载/缩略图不经过 JSON 解码器。

### 10.2 版本选择算法

```text
server = SYNO.API.Info 返回的能力
client = 客户端已实现并测试的版本范围
selected = min(server.maxVersion, client.maxVersion)

只有 selected >= max(server.minVersion, client.minVersion) 时才可调用
```

不要总是选择服务器最高版本。如果客户端只实现了 v2，而服务器最高为 v3，应使用 v2。

### 10.3 Swift `URLSession` 最小调用器

```swift
import Foundation

struct DsmEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: DsmError?
}

struct DsmError: Decodable, Error {
    let code: Int
}

final class DsmClient {
    private let baseURL: URL
    private let session: URLSession
    private var sid: String?

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func setSessionId(_ sid: String?) {
        self.sid = sid
    }

    func call<T: Decodable>(
        path: String,
        api: String,
        version: Int,
        method: String,
        parameters: [String: String] = [:],
        responseType: T.Type
    ) async throws -> T {
        let url = baseURL.appending(path: "webapi/\(path)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )

        var fields = parameters
        fields["api"] = api
        fields["version"] = String(version)
        fields["method"] = method
        if let sid { fields["_sid"] = sid }
        request.httpBody = Self.formEncode(fields).data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let envelope = try JSONDecoder().decode(DsmEnvelope<T>.self, from: data)
        if let error = envelope.error { throw error }
        guard envelope.success, let value = envelope.data else {
            throw URLError(.cannotParseResponse)
        }
        return value
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        fields.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(escape(key))=\(escape(value))"
        }.joined(separator: "&")
    }

    private static func escape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
```

生产实现还需补充：Keychain、信任策略、证书变化提示、超时、取消、上传/下载流、重认证互斥锁和错误码映射。不要在自定义 `URLProtocol` 或日志拦截器中输出请求体。

### 10.4 Android Kotlin/OkHttp 最小调用器

```kotlin
import kotlinx.serialization.json.Json
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request

class DsmClient(
    private val baseUrl: String,
    private val http: OkHttpClient,
    private val json: Json,
) {
    @Volatile
    private var sid: String? = null

    fun setSessionId(value: String?) {
        sid = value
    }

    fun call(
        path: String,
        api: String,
        version: Int,
        method: String,
        parameters: Map<String, String> = emptyMap(),
    ): String {
        val form = FormBody.Builder().apply {
            add("api", api)
            add("version", version.toString())
            add("method", method)
            sid?.let { add("_sid", it) }
            parameters.forEach { (key, value) -> add(key, value) }
        }.build()

        val request = Request.Builder()
            .url("${baseUrl.trimEnd('/')}/webapi/$path")
            .post(form)
            .build()

        http.newCall(request).execute().use { response ->
            check(response.isSuccessful) { "DSM HTTP 错误：${response.code}" }
            return requireNotNull(response.body).string()
        }
    }
}
```

Android 生产实现应使用协程/异步封装，SID 存在 Keystore 保护的存储中，Release 构建禁用明文流量和会泄密的网络日志拦截器。示例中的 `json` 用于实际项目解码统一响应，最小片段未展开 DTO。

### 10.5 登录状态机

```text
未认证
  -> 查询 Auth 能力
  -> 提交账号和密码
  -> 若 403/406：请求 OTP
  -> 若 409/410：引导用户在 DSM 官方界面修改密码
  -> 保存 SID/SynoToken
  -> 已认证
  -> 106/107/119：只允许一次受控重登录
  -> 退出：服务端 logout + 无条件清理本地秘密
```

不要在收到任意业务错误时自动重登，否则可能造成密码重试、账号锁定或重复写操作。

## 11. 安全与隐私基线

### 11.1 传输安全

- 默认仅允许 HTTPS；不要给用户一个长期有效的“忽略所有证书错误”开关。
- 自签名证书首次信任应显示主机名、SHA-256 指纹并要求明确确认；证书变化再次告警。
- 不在公网直接暴露 DSM 管理端口；优先使用受信任 VPN 或用户已配置的安全访问方式。
- 正确设置连接、读取和总体超时；写操作超时后先查询状态，不盲目重复提交。

### 11.2 最小权限

- 日常文件浏览使用独立普通账号，只授予需要的共享目录权限。
- 管理、套件、用户、终端和硬件控制功能与文件功能分离。
- UI 中显示当前账号及目标 NAS，危险操作要求再次确认目标。
- 不在应用内自动关闭 DSM 安全选项或降低防火墙策略。

### 11.3 日志与崩溃报告

允许记录：本地 request ID、API 分类、耗时、HTTP 状态、DSM 错误码、重试次数。

禁止记录：URL 查询串、完整请求体、完整响应体、Header、账号、SID、令牌、路径、文件名、相册、容器日志及系统日志。

建议日志样式：

```text
requestId=6F1C apiClass=FileList durationMs=184 http=200 dsmCode=0
```

### 11.4 项目源码中应避免照搬的做法

静态审阅发现项目若干调用会把 `_sid` 拼接到下载或缩略图 URL。URL 容易进入访问日志、播放器日志、崩溃报告和缓存键，因此新应用应改为认证请求数据源。

此外，项目大量硬编码 API 版本或手工为 JSON 参数加引号。新实现应以能力发现结果为准，并用统一编码器处理参数，避免版本或转义差异造成错误。

## 12. 开发优先级与兼容策略

推荐分三期实现：

| 阶段 | 范围 | 发布条件 |
| --- | --- | --- |
| 第一阶段 | 登录、能力发现、File Station 官方 API | DSM 6/7 各至少一个版本通过测试 |
| 第二阶段 | 官方 Download Station、官方 VMM | 对应套件存在时按能力开启 |
| 第三阶段 | Photos、Container、系统管理等内部 API | 每个 DSM build/套件版本有契约测试和降级 |

对于“基于 dsm_helper 继续开发还是独立开发”的决定：可以把该项目用作接口行为和 UI 功能参考，但原生客户端的网络层、数据模型、安全存储和平台 UI 应独立实现。不要逐行移植 Flutter/Dart 网络代码，也不要默认继承项目中对内部接口稳定性的假设。

## 13. 验证清单

### 13.1 每台 NAS 首次连接

- [ ] 验证 HTTPS 证书或完成可审计的首次信任。
- [ ] 查询 `SYNO.API.Auth` 与所需业务 API。
- [ ] 记录 DSM build 和套件版本，但不记录设备序列号。
- [ ] 使用普通账号验证最小权限。
- [ ] 缓存 `path`、版本范围和 `requestFormat`。

### 13.2 每个 API 适配器

- [ ] 成功、无权限、API 不存在、版本不支持和会话超时测试。
- [ ] 空列表、分页、非 ASCII 名称、特殊字符路径测试。
- [ ] 未知字段、字段缺失和数字范围测试。
- [ ] 取消、超时和重复提交测试。
- [ ] 日志与崩溃样本全文检索确认无秘密。
- [ ] 内部接口验证 DSM build 与套件版本，不匹配时自动关闭。

### 13.3 发布前

- [ ] Release 构建不信任调试代理 CA，不允许明文 HTTP。
- [ ] 密码只在认证请求期间存在于内存，不落盘。
- [ ] SID、DID、SynoToken 使用系统安全存储。
- [ ] 登出和删除 NAS 配置会清理所有秘密与缓存。
- [ ] 危险写操作都有确认和明确的目标摘要。
- [ ] 没有把 HAR、PCAP、真实响应或测试账号提交到仓库。

## 14. 源码证据索引

本节便于后续追踪项目实现；行号可能随分支变化，链接固定到 `dev` 分支目录：

| 功能 | 项目位置 |
| --- | --- |
| 集中式 API 与旧实现 | [`lib/utils/api.dart`](https://gitee.com/apaipai/dsm_helper/blob/dev/lib/utils/api.dart) |
| DSM 模型化接口 | [`lib/models/Syno`](https://gitee.com/apaipai/dsm_helper/tree/dev/lib/models/Syno) |
| Docker/Container | [`lib/models/Syno/Docker`](https://gitee.com/apaipai/dsm_helper/tree/dev/lib/models/Syno/Docker) |
| 系统控制 | [`lib/models/Syno/Core`](https://gitee.com/apaipai/dsm_helper/tree/dev/lib/models/Syno/Core) |
| VMM | [`lib/models/Syno/Virtualization`](https://gitee.com/apaipai/dsm_helper/tree/dev/lib/models/Syno/Virtualization) |
| Photos | [`lib/models/photos`](https://gitee.com/apaipai/dsm_helper/tree/dev/lib/models/photos) |

## 15. 结论

- “官方公开 API”主要包括认证与能力查询、File Station、旧 `SYNO.DownloadStation.*` 以及 `SYNO.Virtualization.API.*`。
- 项目大量功能依赖 DSM Web UI/套件内部接口；这些接口大多是通过观察请求、源码样本和实际响应摸索出来的，不受公开文档兼容承诺保护。
- 原生应用可以使用内部接口，但应把它们视为可选插件能力：运行时探测、按版本验证、默认关闭、失败可降级。
- 最稳妥的开发起点是独立实现安全的原生网络层，先覆盖官方 API，再按实际需求逐个加入经过抓包与契约测试的内部适配器。
