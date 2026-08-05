# Android 写操作测试审计矩阵

本文以生产 Kotlin 中实际调用的 `*Result` 方法为生产入口事实源，审计每项写操作
是否具备提交前失败、成功回读、提交断线、写后回读失败和取消测试。批量或多阶段写入
还必须覆盖部分成功；单目标原子写入不伪造部分成功语义。固定失败关闭的能力只要求
证明零写请求；`resumeArchiveMutationResult` 只读恢复已提交任务，不计为新的写请求。

## 结论

- 当前在 `AppViewModel`、跨 NAS 协调器、照片备份 Worker 和 `DsmRepository` 四个已审文件中识别 74 个
  `*Result` 调用点、63 个唯一方法，其中包含固定关闭与只读恢复调用；全部已进入下方
  机器可读清单。四个文件的内容指纹、调用数量或生产源码中的调用文件集合变化时，
  `check_android_write_test_matrix.py` 会要求重新人工复核，不用正则猜测结果数据流。
- 所有已开放写入口均已形成闭环，包括文件操作、Download Station、Chat、NAS 设置、
  账号与群组、套件及 VMM；单目标原子操作按不适用记录 `partial=na`，不伪造部分成功。
- 固定失败关闭并有零请求证据的入口是 5 项容器写入口和 2 项 VMM 内部网络写入口。
- 63 个生产 `*Result` 方法的适用场景均有现存测试方法证据，矩阵门禁当前无
  `pending` 或 `gap`；A1“每项写操作测试”叶子目标已闭环。真实 NAS 权限、断线、
  取消和副作用仍按用户安排留待统一打包验收，不以自动化结果替代。

## 场景定义

| 场景 | 测试方法要求 |
| --- | --- |
| 提交前失败 `pre` | 输入、能力、权限、用户所见基线或提交前取消失败时，断言写请求为零 |
| 成功回读 `success` | 写响应本身不作为成功依据；断言专项回读与稳定目标匹配后才确认成功 |
| 提交断线 `disconnect` | 模拟写请求已可能到达但响应丢失，只允许回读，不允许自动重放 |
| 回读失败 `readback` | 模拟写后读取失败或结构不可信，保持未知/失败并要求刷新，不冒充成功 |
| 取消 `cancel` | 分别证明提交前零写；提交后只核对或停止已知任务，不重放写请求 |
| 部分成功 `partial` | 只适用于批量或多阶段操作，逐项计数成功、失败与未知 |
| 固定关闭 `zero` | 契约未验证或能力不开放时，生产调用稳定返回且网络写请求为零 |

## 可审计清单

下列 HTML 注释是静态门禁的数据源。证据格式为“测试文件名::测试名称片段”；`gap`
表示必须补测，`na` 表示该场景不适用。`pending` 会让门禁明确失败，避免缺口被误报
为完成。

### 文件与传输

<!-- WRITE-MUTATION methods=addFavoriteResult;state=open;multi=no;pre=FavoriteMutationTest.kt::收藏提交前协程已取消时零请求返回;success=FavoriteMutationTest.kt::收藏写入和回读一致;disconnect=FavoriteMutationTest.kt::收藏提交网络中断;readback=FavoriteMutationTest.kt::收藏提交成功但回读中断;cancel=FavoriteMutationTest.kt::收藏写请求在途取消保持提交边界;partial=na -->
<!-- WRITE-MUTATION methods=removeFavoriteResult;state=open;multi=no;pre=FavoriteMutationTest.kt::移除收藏提交前协程已取消时零请求返回;success=FavoriteMutationTest.kt::移除收藏后回读不再包含目标;disconnect=FavoriteMutationTest.kt::移除收藏提交断线保持未确认;readback=FavoriteMutationTest.kt::移除收藏提交成功但回读失败;cancel=FavoriteMutationTest.kt::移除收藏写请求在途取消保持提交边界;partial=na -->
<!-- WRITE-MUTATION methods=createFolderResult;state=open;multi=no;pre=FileEntryMutationResultTest.kt::新建文件夹输入或能力无效;success=FileEntryMutationResultTest.kt::新建文件夹精确提交公开参数并回读确认;disconnect=FileEntryMutationResultTest.kt::新建文件夹提交断线;readback=FileEntryMutationResultTest.kt::新建文件夹写后回读失败;cancel=FileEntryMutationResultTest.kt::新建文件夹提交后的取消;partial=na -->
<!-- WRITE-MUTATION methods=renameResult;state=open;multi=no;pre=FileEntryMutationResultTest.kt::重命名输入或能力无效;success=FileEntryMutationResultTest.kt::重命名精确提交路径和名称并复查源目标;disconnect=FileEntryMutationResultTest.kt::重命名提交断线;readback=FileEntryMutationResultTest.kt::重命名写后回读失败;cancel=FileEntryMutationResultTest.kt::重命名提交后的取消;partial=na -->
<!-- WRITE-MUTATION methods=deleteResult;state=open;multi=yes;pre=FileDeleteResultTest.kt::非法目标在提交前失败;success=FileDeleteResultTest.kt::删除任务完成并逐项回读不存在;disconnect=FileDeleteResultTest.kt::提交时断线只报告未确认;readback=FileDeleteResultTest.kt::删除完成但回读失败;cancel=FileDeleteResultTest.kt::提交后的取消只报告需要核对;partial=FileDeleteResultTest.kt::部分目标删除后逐项回读 -->
<!-- WRITE-MUTATION methods=moveResult;state=open;multi=yes;pre=PhotoMoveRepositoryTest.kt::只读目标在提交前返回权限不足;success=PhotoMoveRepositoryTest.kt::移动使用公开任务接口且完成后复查源与目标;disconnect=PhotoMoveRepositoryTest.kt::移动提交时断线保持未确认;readback=PhotoMoveRepositoryTest.kt::移动任务完成但回读失败;cancel=PhotoMoveRepositoryTest.kt::移动提交后的取消;partial=PhotoMoveRepositoryTest.kt::批量移动逐项回读并报告部分成功 -->
<!-- WRITE-MUTATION methods=copyResult;state=open;multi=yes;pre=PhotoMoveRepositoryTest.kt::批量复制拒绝覆盖并复查每个目标;success=PhotoMoveRepositoryTest.kt::批量复制拒绝覆盖并复查每个目标;disconnect=PhotoMoveRepositoryTest.kt::批量复制提交断线保持未确认且不自动重放;readback=PhotoMoveRepositoryTest.kt::批量复制任务完成但回读失败时保持未确认;cancel=PhotoMoveRepositoryTest.kt::复制提交后的取消只停止任务且不重放;partial=PhotoMoveRepositoryTest.kt::批量复制逐项回读并报告部分成功 -->
<!-- WRITE-MUTATION methods=compressResult;state=open;multi=no;pre=ArchiveRepositoryTest.kt::压缩目标目录只读时提交前拒绝;success=ArchiveRepositoryTest.kt::压缩使用公开任务接口且完成后复查目标;disconnect=ArchiveRepositoryTest.kt::压缩启动断线但目标回读存在;readback=ArchiveRepositoryTest.kt::压缩完成后零字节目标不能确认成功;cancel=ArchiveRepositoryTest.kt::压缩提交后取消会停止任务;partial=na -->
<!-- WRITE-MUTATION methods=extractResult;state=open;multi=yes;pre=ArchiveRepositoryTest.kt::解压目标目录只读时提交前拒绝;success=ArchiveRepositoryTest.kt::解压先读取内容拒绝覆盖并按顶层类型复查;disconnect=ArchiveRepositoryTest.kt::解压启动断线但全部目标回读存在时确认成功且不重放;readback=ArchiveRepositoryTest.kt::解压完成后输出类型必须与归档目录项一致;cancel=ArchiveRepositoryTest.kt::解压提交后取消会停止任务且不会再次启动;partial=ArchiveRepositoryTest.kt::解压只确认部分目标时返回部分成功 -->
<!-- WRITE-MUTATION methods=resumeArchiveMutationResult;state=readonly;multi=no;pre=na;success=ArchiveRepositoryTest.kt::恢复已提交压缩任务只读轮询且输出回读后确认成功;disconnect=na;readback=ArchiveRepositoryTest.kt::恢复任务即使状态完成也必须输出回读成功;cancel=ArchiveRepositoryTest.kt::恢复已提交压缩任务取消时只停止本地观察且不发送写请求;partial=na -->
<!-- WRITE-MUTATION methods=restoreFromRecycleResult;state=open;multi=no;pre=PhotoRestoreRepositoryTest.kt::原目录只读时提交前返回权限不足;success=PhotoRestoreRepositoryTest.kt::恢复前检查原目录权限和冲突并在移动后复查;disconnect=PhotoRestoreRepositoryTest.kt::恢复提交断线保持未确认且不自动重放;readback=PhotoRestoreRepositoryTest.kt::恢复任务完成但回读失败时保持未确认且不重放;cancel=PhotoRestoreRepositoryTest.kt::恢复提交后的取消只停止任务且不重放;partial=na -->
<!-- WRITE-MUTATION methods=createShareLinkResult;state=open;multi=no;pre=PhotoShareRepositoryTest.kt::共享链接输入或能力无效时零请求拒绝;success=PhotoShareRepositoryTest.kt::创建公开共享链接后必须通过列表回读确认;disconnect=PhotoShareRepositoryTest.kt::共享链接提交断线保持未确认;readback=PhotoShareRepositoryTest.kt::共享链接回读断线保持未确认;cancel=PhotoShareRepositoryTest.kt::共享链接提交后的取消;partial=na -->
<!-- WRITE-MUTATION methods=deleteShareLinksResult;state=open;multi=yes;pre=ShareLinkDeletionTest.kt::非法目标不支持能力和已消失目标;success=ShareLinkDeletionTest.kt::删除共享链接只提交一次并在列表回读消失后确认;disconnect=ShareLinkDeletionTest.kt::提交断线但回读链接已消失;readback=ShareLinkDeletionTest.kt::提交成功但回读失败;cancel=ShareLinkDeletionTest.kt::删除提交后取消只回读;partial=ShareLinkDeletionTest.kt::批量删除只移除部分链接时返回部分成功 -->
<!-- WRITE-MUTATION methods=uploadResult;state=open;multi=no;pre=FileUploadTest.kt::上传非法输入和能力不足均不访问网络;success=FileUploadTest.kt::上传请求符合公共Fixture且写后大小回读一致;disconnect=FileUploadTest.kt::上传断线但大小回读一致;readback=FileUploadTest.kt::上传响应成功但回读大小不一致;cancel=FileUploadTest.kt::上传提交后取消只要求刷新;partial=na -->
<!-- WRITE-MUTATION methods=ensureSubdirectoryResult;state=open;multi=yes;pre=BackupFolderRepositoryTest.kt::拒绝在配置根目录之外创建备份目录;success=BackupFolderRepositoryTest.kt::自动备份只在配置根目录下逐层创建子目录;disconnect=BackupFolderRepositoryTest.kt::目录创建提交断线后只读回读且不重放;readback=BackupFolderRepositoryTest.kt::提交后无法读回时保留未知且不重放创建;cancel=BackupFolderRepositoryTest.kt::取消发生在提交前后时返回不同状态;partial=BackupFolderRepositoryTest.kt::后续层级失败时保留已创建层级和部分成功语义 -->
<!-- WRITE-MUTATION methods=saveTextResult;state=open;multi=no;pre=FileUploadTest.kt::文本基线漂移时不发送;success=FileUploadTest.kt::文本覆盖保存后重新读取并逐字核对;disconnect=FileUploadTest.kt::上传断线且目标未确认;readback=FileUploadTest.kt::文本上传后读取失败保持未确认;cancel=FileUploadTest.kt::上传提交后取消只要求刷新;partial=na -->

### Download Station

<!-- WRITE-MUTATION methods=createDownloadResult;state=open;multi=no;pre=DownloadCreationResultTest.kt::非法链接和不支持能力均在提交前失败;success=DownloadCreationResultTest.kt::链接任务只在新任务回读后确认;disconnect=DownloadCreationResultTest.kt::链接提交断线后不把其他新任务归属;readback=DownloadCreationResultTest.kt::链接创建响应成功但回读失败;cancel=DownloadCreationResultTest.kt::链接创建提交后的取消;partial=na -->
<!-- WRITE-MUTATION methods=createDownloadFromFileResult;state=open;multi=no;pre=DownloadCreationResultTest.kt::非法任务文件在上传前失败;success=DownloadCreationResultTest.kt::任务文件只在稳定任务回读后确认成功且只上传一次;disconnect=DownloadCreationResultTest.kt::任务文件提交断线只回读不猜测归属且不再次上传;readback=DownloadCreationResultTest.kt::任务文件上传成功但回读失败时保持未确认且不再次上传;cancel=DownloadCreationResultTest.kt::任务文件提交后的取消只要求核对且不再次上传;partial=na -->
<!-- WRITE-MUTATION methods=controlDownloadsResult;state=open;multi=yes;pre=DownloadMutationResultTest.kt::稳定基线或适用状态漂移时写请求为零;success=DownloadMutationResultTest.kt::暂停和继续按最终状态逐项确认;disconnect=DownloadMutationResultTest.kt::提交断线后在不可取消回读确认最终状态;readback=DownloadMutationResultTest.kt::提交断线且严格回读失败;cancel=DownloadMutationResultTest.kt::提交阶段取消仍执行不可取消严格回读;partial=DownloadMutationResultTest.kt::批量暂停只把已确认项计成功 -->
<!-- WRITE-MUTATION methods=editDownloadDestinationResult;state=open;multi=no;pre=DownloadMutationResultTest.kt::目标目录或任务基线漂移时保存位置写请求为零;success=DownloadMutationResultTest.kt::修改保存位置仅发送一次官方v1写请求并按回读确认;disconnect=DownloadMutationResultTest.kt::写请求连接失败但回读已生效时不重放并确认成功;readback=DownloadMutationResultTest.kt::修改保存位置写后回读失败保持未确认且不重放;cancel=DownloadMutationResultTest.kt::修改保存位置提交阶段取消只回读且不重放;partial=na -->
<!-- WRITE-MUTATION methods=saveDownloadSettingsResult;state=open;multi=yes;pre=DownloadSettingsRepositoryTest.kt::计划预读失败时保持未提交;success=DownloadSettingsRepositoryTest.kt::保存两组件后严格回读;disconnect=DownloadSettingsRepositoryTest.kt::计划提交失败但基础设置已确认;readback=DownloadSettingsRepositoryTest.kt::计划回读失败保留unknown;cancel=DownloadSettingsRepositoryTest.kt::第二阶段取消只回读;partial=DownloadSettingsRepositoryTest.kt::计划提交失败但基础设置已确认时返回部分成功 -->
<!-- WRITE-MUTATION methods=refreshDownloadRssSiteResult;state=open;multi=no;pre=DownloadDiscoveryRepositoryTest.kt::RSS 目标已变化时不提交刷新;success=DownloadDiscoveryRepositoryTest.kt::RSS 刷新固定使用公开 v1 且写前写后回读目标;disconnect=DownloadDiscoveryRepositoryTest.kt::RSS 刷新提交时断线标记未确认且不自动重放;readback=DownloadDiscoveryRepositoryTest.kt::RSS 刷新提交成功但回读失败时保持未确认且不重放;cancel=DownloadDiscoveryRepositoryTest.kt::RSS 刷新提交后的取消只要求刷新且不重放;partial=na -->

### Chat

<!-- WRITE-MUTATION methods=openDirectChatConversationResult,createPrivateChatGroupResult;state=open;multi=yes;pre=ChatConversationMutationResultTest.kt::单聊写前列表失败时不提交;success=ChatConversationMutationResultTest.kt::单聊成功响应仍须列表回读确认;disconnect=ChatConversationMutationResultTest.kt::单聊创建断线但列表回读匹配;readback=ChatConversationMutationResultTest.kt::单聊权限拒绝且回读不匹配;cancel=ChatConversationMutationResultTest.kt::群聊创建提交后取消;partial=ChatConversationMutationResultTest.kt::群聊邀请断线且成员不完整时报告部分成功 -->
<!-- WRITE-MUTATION methods=sendChatTextMessageResult;state=open;multi=no;pre=ChatTextMutationResultTest.kt::非法输入不支持能力和提交前取消;success=ChatTextMutationResultTest.kt::响应缺少消息ID但回读匹配;disconnect=ChatTextMutationResultTest.kt::提交断线但近期消息回读匹配;readback=ChatTextMutationResultTest.kt::断线后回读也失败;cancel=ChatTextMutationResultTest.kt::提交后取消只回读;partial=na -->
<!-- WRITE-MUTATION methods=sendChatAttachmentMessageResult;state=open;multi=no;pre=ChatAttachmentMutationResultTest.kt::附件流未上传完成时失败不回读;success=ChatAttachmentMutationResultTest.kt::响应缺少消息ID但回读附件匹配;disconnect=ChatAttachmentMutationResultTest.kt::完整上传后断线且近期附件匹配;readback=ChatAttachmentMutationResultTest.kt::完整上传后断线且回读无匹配;cancel=ChatAttachmentMutationResultTest.kt::完整上传后取消只回读;partial=na -->
<!-- WRITE-MUTATION methods=setChatReminderResult,deleteChatReminderResult;state=open;multi=no;pre=ChatReminderMutationResultTest.kt::写前回读失败时不提交提醒变更;success=ChatReminderMutationResultTest.kt::设置提交断线但回读匹配;disconnect=ChatReminderMutationResultTest.kt::删除提交断线但回读已不存在;readback=ChatReminderMutationResultTest.kt::成功响应但回读失败;cancel=ChatReminderMutationResultTest.kt::提交后取消只回读;partial=na -->
<!-- WRITE-MUTATION methods=createChatScheduledMessageResult,deleteChatScheduledMessageResult;state=open;multi=no;pre=ChatScheduleMutationResultTest.kt::写前回读失败时不提交定时消息;success=ChatScheduleMutationResultTest.kt::创建成功响应仍须列表回读确认;disconnect=ChatScheduleMutationResultTest.kt::取消定时消息断线但回读已不存在;readback=ChatScheduleMutationResultTest.kt::创建断线且回读不匹配;cancel=ChatScheduleMutationResultTest.kt::提交后取消只回读;partial=na -->
<!-- WRITE-MUTATION methods=createChatPollResult;state=open;multi=no;pre=ChatPollMutationResultTest.kt::写前回读失败时不提交投票;success=ChatPollMutationResultTest.kt::创建成功响应仍须近期消息回读确认;disconnect=ChatPollMutationResultTest.kt::创建断线但近期消息回读匹配;readback=ChatPollMutationResultTest.kt::提交后回读失败;cancel=ChatPollMutationResultTest.kt::提交后取消只回读;partial=na -->

### NAS 设置、套件与连接

<!-- WRITE-MUTATION methods=saveEthernetInterfaceResult;state=open;multi=no;pre=EthernetMutationResultTest.kt::非法标识地址 MTU 与 VLAN;success=EthernetMutationResultTest.kt::DHCP 设置与共享 Fixture 一致并使用固定版本回读;disconnect=EthernetMutationResultTest.kt::设置响应丢失后只回读;readback=EthernetMutationResultTest.kt::设置成功但回读断线;cancel=EthernetMutationResultTest.kt::预检取消零写且设置在途取消;partial=na -->
<!-- WRITE-MUTATION methods=testDdnsResult,saveDdnsResult,deleteDdnsResult,refreshDdnsResult;state=open;multi=no;pre=DdnsMutationResultTest.kt::Provider 或 Record 不含 v1 时四入口均零网络;success=DdnsMutationResultTest.kt::新建只提交一次并严格回读;disconnect=DdnsMutationResultTest.kt::新建响应丢失后只读取一次目录;readback=DdnsMutationResultTest.kt::模糊保存单次回读失败;cancel=DdnsMutationResultTest.kt::DDNS 四个写入口在途取消都不重放写请求;partial=na -->
<!-- WRITE-MUTATION methods=saveFileServiceSettingsResult;state=open;multi=yes;pre=NasServiceSettingsMutationTest.kt::文件服务后续能力缺失时一次性预检;success=NasServiceSettingsMutationTest.kt::文件服务只提交变化 API 组并整体回读;disconnect=NasServiceSettingsMutationTest.kt::文件服务提交与回读均断线;readback=NasServiceSettingsMutationTest.kt::文件服务写入响应成功但回读全不匹配;cancel=NasServiceSettingsMutationTest.kt::文件服务写请求在途取消;partial=NasServiceSettingsMutationTest.kt::文件服务前序生效后后续失败返回部分成功 -->
<!-- WRITE-MUTATION methods=saveTerminalSettingsResult;state=open;multi=yes;pre=NasServiceSettingsMutationTest.kt::终端预检在途取消不会进入写请求;success=NasServiceSettingsMutationTest.kt::终端设置提交完整字段并回读确认;disconnect=NasServiceSettingsMutationTest.kt::终端提交响应丢失后部分字段匹配;readback=NasServiceSettingsMutationTest.kt::终端提交成功但回读失败;cancel=NasServiceSettingsMutationTest.kt::终端写请求在途取消;partial=NasServiceSettingsMutationTest.kt::终端提交响应丢失后部分字段匹配返回部分成功 -->
<!-- WRITE-MUTATION methods=saveProxySettingsResult;state=open;multi=yes;pre=NasServiceSettingsMutationTest.kt::代理非法地址与端口零请求拒绝;success=NasServiceSettingsMutationTest.kt::代理启用请求与 Fixture 字段一致并回读确认;disconnect=NasServiceSettingsMutationTest.kt::代理提交响应丢失后部分生效;readback=NasServiceSettingsMutationTest.kt::代理提交断线且回读失败;cancel=NasServiceSettingsMutationTest.kt::代理写请求在途取消回读;partial=NasServiceSettingsMutationTest.kt::代理提交响应丢失后部分生效保留未知字段 -->
<!-- WRITE-MUTATION methods=saveRegionSettingsResult;state=open;multi=yes;pre=NasServiceSettingsMutationTest.kt::区域预检拒绝未知自动校时模式;success=NasServiceSettingsMutationTest.kt::区域设置按固定版本保存回读;disconnect=NasServiceSettingsMutationTest.kt::区域配置提交超时只回读;readback=NasServiceSettingsMutationTest.kt::区域配置权限失败与回读失败;cancel=NasServiceSettingsMutationTest.kt::区域配置写请求在途取消;partial=NasServiceSettingsMutationTest.kt::区域配置确认后校时超时返回部分成功 -->
<!-- WRITE-MUTATION methods=saveRemoteAccessSettingsResult;state=open;multi=yes;pre=RemoteAccessSettingsMutationTest.kt::无变化基线漂移和能力缺口均零写入;success=RemoteAccessSettingsMutationTest.kt::两项写入按固定顺序执行并完整回读确认;disconnect=RemoteAccessSettingsMutationTest.kt::提交断线后只回读确认;readback=RemoteAccessSettingsMutationTest.kt::回读单字段失败必须要求刷新;cancel=RemoteAccessSettingsMutationTest.kt::提交阶段取消后仍回读;partial=RemoteAccessSettingsMutationTest.kt::第二步权限失败报告部分成功 -->
<!-- WRITE-MUTATION methods=saveSecuritySettingsResult;state=open;multi=yes;pre=SecuritySettingsMutationResultTest.kt::完整基线漂移时零写入;success=NasServiceSettingsMutationTest.kt::安全设置四个子操作使用固定契约并整体回读;disconnect=NasServiceSettingsMutationTest.kt::安全设置中途断线后停止后续提交;readback=NasServiceSettingsMutationTest.kt::安全设置提交断网且回读失败;cancel=SecuritySettingsMutationResultTest.kt::正式入口提交后取消;partial=SecuritySettingsMutationResultTest.kt::正式入口提交后取消按整体回读返回部分成功 -->
<!-- WRITE-MUTATION methods=saveHardwareSettingsResult;state=open;multi=yes;pre=HardwareSettingsMutationResultTest.kt::完整硬件基线漂移时零写入;success=NasServiceSettingsMutationTest.kt::硬件六组设置按契约提交并整体回读;disconnect=NasServiceSettingsMutationTest.kt::硬件设置中途断线停止后续写入;readback=NasServiceSettingsMutationTest.kt::硬件设置写入成功但回读失败保持未确认且不重放;cancel=NasServiceSettingsMutationTest.kt::硬件设置写请求在途取消只回读且不重放;partial=NasServiceSettingsMutationTest.kt::硬件设置中途断线停止后续写入并回读部分成功 -->
<!-- WRITE-MUTATION methods=performPowerActionResult;state=open;multi=no;pre=NasServiceSettingsMutationTest.kt::电源动作能力缺失与预检拒绝均零写入;success=NasServiceSettingsMutationTest.kt::关机与重启均先预检且只提交一次无参数动作;disconnect=NasServiceSettingsMutationTest.kt::电源请求提交断线报告未确认;readback=NasServiceSettingsMutationTest.kt::电源动作无安全回读且成功仅表示请求已接受;cancel=NasServiceSettingsMutationTest.kt::电源请求在途取消保留已提交语义且不重放;partial=na -->
<!-- WRITE-MUTATION methods=changeDiskTestResult;state=open;multi=no;pre=SmartTestMutationTest.kt::其他检测占用时零写请求;success=SmartTestMutationTest.kt::快速检测使用预检返回的device且回读运行状态;disconnect=SmartTestMutationTest.kt::提交断线后仅回读确认;readback=SmartTestMutationTest.kt::写后检测能力漂移不得确认成功;cancel=SmartTestMutationTest.kt::写入阶段取消只专项回读一次;partial=na -->
<!-- WRITE-MUTATION methods=disconnectConnectionResult;state=open;multi=no;pre=ConnectionDisconnectMutationTest.kt::列表未明确允许断开时不发送写请求;success=ConnectionDisconnectMutationTest.kt::网页连接使用设备标识且回读消失后确认成功;disconnect=ConnectionDisconnectMutationTest.kt::断开请求响应丢失后只回读;readback=ConnectionDisconnectMutationTest.kt::写后回读缺少列表根;cancel=ConnectionDisconnectMutationTest.kt::断开请求在途取消只回读;partial=na -->
<!-- WRITE-MUTATION methods=deleteAccountResult;state=open;multi=no;pre=DirectoryDeletionMutationTest.kt::目录未明确允许删除时不发送写请求;success=DirectoryDeletionMutationTest.kt::账号删除使用名称数组并在目录消失后确认成功;disconnect=DirectoryDeletionMutationTest.kt::账号删除响应丢失后只回读;readback=DirectoryDeletionMutationTest.kt::账号删除后回读根缺失;cancel=DirectoryDeletionMutationTest.kt::账号与群组删除在途取消只回读且不重放;partial=na -->
<!-- WRITE-MUTATION methods=deleteGroupResult;state=open;multi=no;pre=DirectoryDeletionMutationTest.kt::目录未明确允许删除时不发送写请求;success=DirectoryDeletionMutationTest.kt::群组删除使用专用 API 与名称数组;disconnect=DirectoryDeletionMutationTest.kt::群组删除响应丢失后只回读且不重放;readback=DirectoryDeletionMutationTest.kt::群组删除写后畸形回读保持未确认;cancel=DirectoryDeletionMutationTest.kt::账号与群组删除在途取消只回读且不重放;partial=na -->
<!-- WRITE-MUTATION methods=controlPackageResult;state=open;multi=no;pre=PackageControlMutationTest.kt::可行性检查权限不足属于提交前权限拒绝;success=PackageControlMutationTest.kt::停止按 Fixture 只提交稳定 ID 并回读停止状态;disconnect=PackageControlMutationTest.kt::写请求断线后只回读且状态已变化;readback=PackageControlMutationTest.kt::控制写入后畸形回读不得确认成功;cancel=PackageControlMutationTest.kt::控制写请求在途取消只回读;partial=na -->
<!-- WRITE-MUTATION methods=uninstallPackageResult;state=open;multi=no;pre=PackageUninstallMutationTest.kt::系统或未明确允许卸载的套件;success=PackageUninstallMutationTest.kt::卸载按共享 Fixture 传递稳定 ID;disconnect=PackageUninstallMutationTest.kt::卸载写请求断线后只回读且目标消失时确认成功;readback=PackageUninstallMutationTest.kt::卸载后畸形回读;cancel=PackageUninstallMutationTest.kt::卸载写请求在途取消只严格回读一次且不重放;partial=na -->

### Virtual Machine Manager 与固定关闭能力

<!-- WRITE-MUTATION methods=createVirtualMachineResult;state=open;multi=yes;pre=VirtualMachineCreationRepositoryTest.kt::名称预检取消按提交前取消;success=VirtualMachineCreationRepositoryTest.kt::公开 VMM 创建轮询任务应用配置并完整回读;disconnect=VirtualMachineCreationRepositoryTest.kt::创建提交响应模糊时同名回读;readback=VirtualMachineCreationRepositoryTest.kt::创建配置回读缺字段时不确认;cancel=VirtualMachineCreationRepositoryTest.kt::任务轮询取消只回读;partial=VirtualMachineCreationRepositoryTest.kt::创建成功但常规配置未确认时报告部分成功 -->
<!-- WRITE-MUTATION methods=importVirtualMachineImageResult;state=open;multi=no;pre=VirtualMachineImageImportRepositoryTest.kt::源文件完整基线漂移时零创建;success=VirtualMachineImageImportRepositoryTest.kt::官方映像创建只提交一次并以任务映像标识严格回读;disconnect=VirtualMachineImageImportRepositoryTest.kt::创建请求断线后保持未确认且不重放;readback=VirtualMachineImageImportRepositoryTest.kt::任务终态缺少映像标识时保持未确认且不清理;cancel=VirtualMachineImageImportRepositoryTest.kt::创建请求在途取消后保持提交边界且不重放;partial=na -->
<!-- WRITE-MUTATION methods=updateVirtualMachineSettingsResult;state=open;multi=no;pre=VirtualMachineCreationRepositoryTest.kt::常规设置锁内发现用户所见基线漂移;success=VirtualMachineCreationRepositoryTest.kt::公开 VMM 常规设置提交后完整回读;disconnect=VirtualMachineCreationRepositoryTest.kt::常规设置提交断线后只回读且不重放;readback=VirtualMachineCreationRepositoryTest.kt::常规设置写后回读结构失败保持未确认;cancel=VirtualMachineCreationRepositoryTest.kt::常规设置写请求在途取消只回读且不重放;partial=na -->
<!-- WRITE-MUTATION methods=controlVirtualMachineResult;state=open;multi=no;pre=VirtualMachineMutationResultTest.kt::生命周期锁内状态偏离用户所见基线;success=VirtualMachineMutationResultTest.kt::正常关机必须在列表回读为停止后才确认成功;disconnect=VirtualMachineMutationResultTest.kt::生命周期提交断线后只回读确认最终状态;readback=VirtualMachineMutationResultTest.kt::生命周期写后回读失败保持未确认;cancel=VirtualMachineMutationResultTest.kt::生命周期与删除在途取消只回读且不重放;partial=na -->
<!-- WRITE-MUTATION methods=deleteVirtualMachineResult;state=open;multi=no;pre=VirtualMachineMutationResultTest.kt::VMM 删除预检遇到缺失标识时不发送写请求;success=VirtualMachineMutationResultTest.kt::删除虚拟机必须回读消失且发送稳定标识;disconnect=VirtualMachineMutationResultTest.kt::虚拟机删除提交断线后只回读确认目标消失;readback=VirtualMachineMutationResultTest.kt::虚拟机删除写后回读失败保持未确认;cancel=VirtualMachineMutationResultTest.kt::生命周期与删除在途取消只回读且不重放;partial=na -->
<!-- WRITE-MUTATION methods=deleteVirtualMachineImageResult;state=open;multi=no;pre=VirtualMachineMutationResultTest.kt::仅有内部映像 API 时删除零请求关闭;success=VirtualMachineMutationResultTest.kt::公开映像删除成功断线与取消均不重放;disconnect=VirtualMachineMutationResultTest.kt::公开映像删除成功断线与取消均不重放;readback=VirtualMachineMutationResultTest.kt::映像删除提交后回读断线;cancel=VirtualMachineMutationResultTest.kt::公开映像删除成功断线与取消均不重放;partial=na -->
<!-- WRITE-MUTATION methods=renameVirtualMachineNetworkResult,deleteVirtualMachineNetworkResult;state=closed;multi=no;zero=VirtualMachineMutationResultTest.kt::内部网络改名契约未行为验证时零请求关闭 -->
<!-- WRITE-MUTATION methods=controlContainerResult,deleteContainerResult,deleteContainerImageResult,createContainerNetworkResult,deleteContainerNetworkResult;state=closed;multi=no;zero=ContainerMutationResultTest.kt::行为未验证时所有容器写操作稳定拒绝且零请求 -->

## 运行门禁

```bash
python3 tools/codex/check_android_write_test_matrix.py
python3 -m unittest discover -s tools/codex/tests -p 'test_check_android_write_test_matrix.py'
```

第一条命令在当前缺口补齐前应失败并逐项打印 `待补测试`；这不是误报，而是防止 A1
在证据不足时被勾选。第二条命令验证入口提取、重复/缺失检测、批量部分成功规则、
`pending` 精确缺口以及测试证据链接检查本身。

## 实机边界

矩阵只证明 JVM 假 API 下的请求边界与结果语义，不代替实体机、真实 NAS、断电、
Doze、进程杀死或 OEM 网络栈验收。按当前约定，这些实体机验证留给用户后续打包执行，
不阻塞矩阵继续补齐，但必须继续标为“未验证”。
