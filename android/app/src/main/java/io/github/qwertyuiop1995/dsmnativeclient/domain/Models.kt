package io.github.qwertyuiop1995.dsmnativeclient.domain

import kotlinx.serialization.Serializable

@Serializable
data class NasProfile(
    val id: String,
    val name: String,
    val address: String,
    val username: String,
    val port: Int? = null,
    val rememberSession: Boolean = true,
)

@Serializable
data class DsmSession(
    val profileId: String,
    val sid: String,
    val synoToken: String? = null,
    val deviceId: String? = null,
)

@Serializable
data class ApiCapability(
    val name: String,
    val path: String,
    val minVersion: Int,
    val maxVersion: Int,
) {
    fun version(preferred: Int = maxVersion): Int = preferred.coerceIn(minVersion, maxVersion)
}

enum class DsmErrorKind {
    UNKNOWN,
    INVALID_ADDRESS,
    INSECURE_ADDRESS,
    INVALID_QUICK_CONNECT_ID,
    QUICK_CONNECT_NOT_FOUND,
    QUICK_CONNECT_OFFLINE,
    QUICK_CONNECT_DIRECT_UNAVAILABLE,
    QUICK_CONNECT_SERVICE_UNAVAILABLE,
    QUICK_CONNECT_INVALID_RESPONSE,
    QUICK_CONNECT_RELAY_DISABLED,
    QUICK_CONNECT_RELAY_UNAVAILABLE,
    QUICK_CONNECT_IDENTITY_MISMATCH,
    MISSING_LOGIN_FIELDS,
    NO_SAVED_SESSION,
    SAVED_SESSION_EXPIRED,
    REQUEST_FAILED,
    FEATURE_UNSUPPORTED,
    PACKAGE_VERSION_UNSUPPORTED,
    SESSION_EXPIRED,
    PERMISSION_DENIED,
    RATE_LIMITED,
    AUTHENTICATION_FAILED,
    OTP_REQUIRED,
    OTP_INVALID,
    DEVICE_CONFIRMATION_REQUIRED,
    CONNECTION_FAILED,
    INVALID_RESPONSE,
    SEARCH_NOT_STARTED,
    EMPTY_FILE_UNSUPPORTED,
    CHANGE_NOT_CONFIRMED,
    UPLOAD_FAILED,
    UPLOAD_NOT_ALLOWED,
    UPLOAD_LENGTH_MISMATCH,
    DOWNLOAD_FAILED,
    DOWNLOAD_LENGTH_MISMATCH,
    PREVIEW_TOO_LARGE,
}

data class DsmFailure(
    val code: Int?,
    override val message: String,
    val recovery: String,
    val isAuthenticationFailure: Boolean = false,
    val kind: DsmErrorKind = DsmErrorKind.UNKNOWN,
) : RuntimeException(message)

enum class Module {
    FILES,
    PHOTOS,
    CHAT,
    DOWNLOADS,
    CONTAINERS,
    VIRTUAL_MACHINES,
    NAS_SETTINGS,
    TRANSFERS,
    SETTINGS,
}

enum class ModuleUnavailableReason {
    CHAT_SERVICE,
    DOWNLOAD_STATION,
    CONTAINER_MANAGER,
    VIRTUAL_MACHINE_MANAGER,
}

enum class NasPowerAction { SHUTDOWN, REBOOT }

enum class FileLocationKind {
    SHARE,
    DIRECTORY,
    RECYCLE_BIN,
    FAVORITE,
    RECENT,
    REMOTE,
}

data class FileItem(
    val path: String,
    val name: String,
    val isDirectory: Boolean,
    val size: Long = 0,
    val modifiedAtEpochSeconds: Long? = null,
    val accessedAtEpochSeconds: Long? = null,
    val owner: String? = null,
    val mimeType: String? = null,
    val canRead: Boolean = true,
    val canWrite: Boolean = false,
    val canDelete: Boolean = false,
    val isFavorite: Boolean = false,
    val mountPointType: String? = null,
) {
    val extension: String get() = name.substringAfterLast('.', "").lowercase()
}

enum class StorageFileCategory { IMAGE, VIDEO, AUDIO, DOCUMENT, ARCHIVE, OTHER, NO_EXTENSION }

data class StorageAnalysisShare(
    val name: String,
    val path: String,
    val usedBytes: Long,
    val fileCount: Int,
)

data class StorageAnalysisCategory(
    val category: StorageFileCategory,
    val usedBytes: Long,
    val fileCount: Int,
)

data class StorageAnalysisOwner(
    val name: String?,
    val usedBytes: Long,
    val fileCount: Int,
)

data class StorageDuplicateGroup(
    val checksum: String,
    val sizeBytes: Long,
    val files: List<FileItem>,
) {
    val reclaimableBytes: Long get() = (files.size - 1).coerceAtLeast(0) * sizeBytes
}

data class StorageAnalysisSnapshot(
    val generatedAtEpochSeconds: Long,
    val shares: List<StorageAnalysisShare>,
    val categories: List<StorageAnalysisCategory>,
    val owners: List<StorageAnalysisOwner>,
    val largeFiles: List<FileItem>,
    val recentlyModifiedFiles: List<FileItem>,
    val leastRecentlyAccessedFiles: List<FileItem>,
    val duplicateGroups: List<StorageDuplicateGroup>,
    val scannedFileCount: Int,
    val scannedBytes: Long,
    val duplicateCheckWasLimited: Boolean,
    val duplicateCheckUnavailable: Boolean,
)

data class StorageAnalysisProgress(
    val phase: String,
    val completed: Int,
    val total: Int,
) {
    val fraction: Float? get() = total.takeIf { it > 0 }?.let { completed.toFloat() / it }
}

data class FilePage(
    val items: List<FileItem>,
    val total: Int,
    val offset: Int,
)

/** File Station 在 NAS 上执行的只读后台任务类别。 */
enum class FileBackgroundTaskKind { COPY_OR_MOVE, DELETE, COMPRESS, EXTRACT }

/** `FINISHED` 只表示任务已经结束，不代表任务成功。 */
enum class FileBackgroundTaskState { ACTIVE, FINISHED }

/**
 * NAS 后台文件任务的脱敏摘要。
 *
 * 此模型刻意不包含任务参数、源/目标路径、当前处理路径或服务端消息，避免敏感内容进入
 * 界面、日志或持久化数据。
 */
data class FileBackgroundTaskSummary(
    val id: String,
    val kind: FileBackgroundTaskKind,
    val state: FileBackgroundTaskState,
    val progress: Double?,
    val createdAtEpochSeconds: Long?,
    val processedItemCount: Int?,
    val totalItemCount: Int?,
    val processedBytes: Long?,
    val totalBytes: Long?,
)

data class FileBackgroundTaskPage(
    val tasks: List<FileBackgroundTaskSummary>,
    val offset: Int,
    val nextOffset: Int,
    val total: Int,
    val hasMore: Boolean,
)

data class FavoriteLocation(
    val path: String,
    val name: String,
)

data class FileShareLink(
    val id: String,
    val name: String,
    val path: String,
    val url: String,
    val hasPassword: Boolean = false,
    val expiresAt: String? = null,
)

data class RecycleLocation(
    val recycleRoot: String,
    val relativePath: String,
    val originalPath: String,
    val originalParentPath: String,
) {
    companion object {
        fun from(recyclePath: String): RecycleLocation? {
            val normalized = if (recyclePath.startsWith('/')) recyclePath else "/$recyclePath"
            val components = normalized.split('/').filter(String::isNotBlank)
            val recycleIndex = components.indexOf("#recycle")
            if (recycleIndex != 1 || components.size <= recycleIndex + 1) return null
            val share = components.first()
            val tail = components.drop(recycleIndex + 1)
            val relative = "/${tail.joinToString("/")}"
            val original = "/$share$relative"
            return RecycleLocation(
                recycleRoot = "/$share/#recycle",
                relativePath = relative,
                originalPath = original,
                originalParentPath = original.substringBeforeLast('/', "/$share"),
            )
        }
    }
}

@Serializable
enum class TransferDirection { DOWNLOAD, UPLOAD, SERVER }

@Serializable
enum class TransferState { WAITING, RUNNING, PAUSED, CANCELLING, SUCCEEDED, FAILED, CANCELLED }

enum class FileServerMutationOperation { COMPRESS, EXTRACT }

enum class FileServerMutationVerification { MATCHES, DIFFERS, DISAPPEARED, UNAVAILABLE }

data class FileServerMutationExpectedOutput(
    val path: String,
    val isDirectory: Boolean,
    val requiresNonEmptyFile: Boolean = false,
)

data class FileServerMutationTarget(
    val profileId: String,
    val module: Module,
    val operation: FileServerMutationOperation,
    val sourceBaselines: List<FileItem>,
    val destinationFolderBaseline: FileItem,
    val expectedOutputs: List<FileServerMutationExpectedOutput> = emptyList(),
)

data class FileServerMutationLifecycle(
    val target: FileServerMutationTarget,
    val result: MutationResult? = null,
    val failure: DsmFailure? = null,
    val refreshInProgress: Boolean = false,
    val refreshCompleted: Boolean = false,
    val refreshFailure: DsmFailure? = null,
    val verification: FileServerMutationVerification? = null,
    val generation: Long = 0L,
)

data class UploadMutationLifecycle(
    val directoryResult: MutationResult? = null,
    val uploadResult: MutationResult? = null,
)

data class TransferTask(
    val id: String,
    val title: String,
    val detail: String,
    val direction: TransferDirection,
    val state: TransferState,
    val completedBytes: Long = 0,
    val totalBytes: Long? = null,
    val errorMessage: String? = null,
    val requiresRefresh: Boolean = false,
    val startedAtEpochMillis: Long? = null,
    val fileServerMutation: FileServerMutationLifecycle? = null,
    val uploadMutation: UploadMutationLifecycle? = null,
    val canCancel: Boolean = true,
) {
    val progress: Float?
        get() = totalBytes?.takeIf { it > 0 }?.let {
            (completedBytes.toDouble() / it.toDouble()).coerceIn(0.0, 1.0).toFloat()
        }

    fun speedBytesPerSecond(nowEpochMillis: Long = System.currentTimeMillis()): Long? =
        transferSpeedBytesPerSecond(completedBytes, startedAtEpochMillis, nowEpochMillis)

    fun estimatedRemainingSeconds(nowEpochMillis: Long = System.currentTimeMillis()): Long? {
        val total = totalBytes ?: return null
        val speed = speedBytesPerSecond(nowEpochMillis)?.takeIf { it > 0 } ?: return null
        return ((total - completedBytes).coerceAtLeast(0) + speed - 1) / speed
    }
}

internal fun transferSpeedBytesPerSecond(
    completedBytes: Long,
    startedAtEpochMillis: Long?,
    nowEpochMillis: Long,
): Long? {
    val started = startedAtEpochMillis ?: return null
    val elapsedMillis = nowEpochMillis - started
    if (completedBytes <= 0 || elapsedMillis < 1_000) return null
    return (completedBytes * 1_000L / elapsedMillis).takeIf { it > 0 }
}

data class ChatUser(
    val id: String,
    val displayName: String,
    val username: String,
    val isDisabled: Boolean = false,
    val isCurrent: Boolean = false,
)

enum class ConversationKind { DIRECT, GROUP }

data class ChatConversation(
    val id: String,
    val title: String,
    val kind: ConversationKind,
    val memberIds: List<String> = emptyList(),
    val unreadCount: Int = 0,
    val isPinnedLocally: Boolean = false,
    val memberCount: Int = 0,
    val latestPreview: String? = null,
    val latestAtEpochSeconds: Long? = null,
)

data class ChatAttachment(
    val id: String,
    val name: String,
    val mimeType: String?,
    val size: Long?,
)

data class ChatReminder(
    val id: String,
    val messageId: String,
    val remindAtEpochMillis: Long,
)

data class ChatScheduledMessage(
    val id: String,
    val conversationId: String,
    val text: String,
    val sendAtEpochMillis: Long,
)

data class ChatPollOption(
    val id: String,
    val text: String,
    val voteCount: Int = 0,
    val isSelectedByCurrentUser: Boolean = false,
)

data class ChatPoll(
    val id: String,
    val question: String,
    val allowsMultipleSelection: Boolean,
    val isAnonymous: Boolean,
    val isClosed: Boolean = false,
    val options: List<ChatPollOption>,
)

data class ChatMessage(
    val id: String,
    val conversationId: String,
    val sender: ChatUser?,
    val body: String,
    val createdAtEpochSeconds: Long,
    val isMine: Boolean,
    val attachments: List<ChatAttachment> = emptyList(),
    val isPinned: Boolean = false,
    val clientRequestId: String? = null,
    val deliveryState: ChatDeliveryState = ChatDeliveryState.SENT,
    val attachmentProgress: Float? = null,
    val poll: ChatPoll? = null,
)

enum class ChatDeliveryState { SENDING, SENT, FAILED }

data class ChatMessagePage(
    val messages: List<ChatMessage>,
    val nextOffset: Int?,
    val hasMore: Boolean,
)

enum class ResourceState {
    RUNNING,
    STOPPED,
    PAUSED,
    WAITING,
    HEALTHY,
    WARNING,
    ERROR,
    UNKNOWN,
}

data class ManagedResource(
    val id: String,
    val name: String,
    val detail: String,
    val state: ResourceState,
    val metadata: Map<String, String> = emptyMap(),
    val localizedLabel: ManagedResourceLabel? = null,
)

enum class ManagedResourceLabel {
    SECURITY_AUTO_BLOCK,
    SECURITY_DOS_PROTECTION,
    SECURITY_FIREWALL,
}

data class DownloadTask(
    val id: String,
    val type: String?,
    val title: String,
    val status: ResourceState,
    val size: Long?,
    val transferred: Long?,
    val downloadSpeed: Long?,
    val uploadSpeed: Long?,
    val destination: String?,
    val error: String?,
    val createdAtEpochSeconds: Long? = null,
    val priority: String? = null,
    val totalPeers: Int? = null,
    val connectedSeeders: Int? = null,
    val connectedLeechers: Int? = null,
    val files: List<DownloadTaskFile> = emptyList(),
    val trackers: List<DownloadTaskTracker> = emptyList(),
    val peers: List<DownloadTaskPeer> = emptyList(),
)

/** Download Station 任务控制使用的稳定操作类型，避免以自由字符串区分危险删除语义。 */
enum class DownloadTaskMutationAction {
    PAUSE,
    RESUME,
    REMOVE_TASK,
    REMOVE_TASK_AND_FILES,
}

/**
 * 写入确认前保存的稳定任务基线。速率、已传输字节和 Peer 等易变字段不得参与写前冲突判断。
 */
data class DownloadTaskMutationBaseline(
    val id: String,
    val type: String?,
    val title: String,
    val status: ResourceState,
    val size: Long?,
    val destination: String?,
    val createdAtEpochSeconds: Long?,
) {
    companion object {
        fun from(task: DownloadTask) = DownloadTaskMutationBaseline(
            id = task.id,
            type = task.type,
            title = task.title,
            status = task.status,
            size = task.size,
            destination = task.destination,
            createdAtEpochSeconds = task.createdAtEpochSeconds,
        )
    }
}

data class DownloadTaskFile(
    val name: String,
    val size: Long?,
    val downloaded: Long?,
    val priority: String?,
)

data class DownloadTaskTracker(
    val url: String,
    val status: String?,
    val updateTimerSeconds: Int?,
    val seeds: Int?,
    val peers: Int?,
)

data class DownloadTaskPeer(
    val address: String,
    val agent: String?,
    val progress: Double?,
    val downloadSpeed: Long?,
    val uploadSpeed: Long?,
)

data class DownloadRssSite(
    val id: String,
    val title: String,
    val isUpdating: Boolean,
    val lastUpdatedAtEpochSeconds: Long?,
)

data class DownloadRssFeed(
    val title: String,
    val size: Long?,
    val publishedAtEpochSeconds: Long?,
    val downloadUri: String,
    val externalLink: String?,
)

data class DownloadBtSearchResult(
    val title: String,
    val size: Long?,
    val listedAt: String?,
    val downloadUri: String,
    val externalLink: String?,
    val peers: Int?,
    val seeds: Int?,
    val leeches: Int?,
    val provider: String?,
)

data class DownloadSettings(
    val defaultDestination: String = "",
    val emuleEnabled: Boolean = false,
    val autoExtractEnabled: Boolean = false,
    val btDownloadLimitKb: Int = 0,
    val btUploadLimitKb: Int = 0,
    val httpDownloadLimitKb: Int = 0,
    val ftpDownloadLimitKb: Int = 0,
    val nzbDownloadLimitKb: Int = 0,
    val emuleDownloadLimitKb: Int = 0,
    val emuleUploadLimitKb: Int = 0,
    val scheduleEnabled: Boolean = false,
    val emuleScheduleEnabled: Boolean = false,
)

data class ContainerOverview(
    val containers: List<ManagedResource>,
    val images: List<ManagedResource>,
    val networks: List<ManagedResource>,
    val projects: List<ManagedResource>,
    val events: List<LogEntry> = emptyList(),
    val unavailableSections: Set<ContainerSection> = emptySet(),
)

enum class ContainerSection { IMAGES, NETWORKS, PROJECTS, EVENTS }

data class ContainerRegistryImage(
    val name: String,
    val registry: String,
    val description: String?,
    val starCount: Int,
    val isOfficial: Boolean,
    val isAutomated: Boolean,
    val isTrusted: Boolean,
) {
    val id: String get() = "$registry/$name"
}

enum class VirtualMachineSection { HOSTS, STORAGES, NETWORKS, IMAGES, PROTECTION, LOGS }

data class VirtualMachineOverview(
    val machines: List<ManagedResource>,
    val hosts: List<ManagedResource>,
    val storages: List<ManagedResource>,
    val networks: List<ManagedResource>,
    val images: List<ManagedResource>,
    val protectionPlans: List<ManagedResource>,
    val protectionSchedules: List<ManagedResource>,
    val retentionPolicies: List<ManagedResource>,
    val logs: List<LogEntry>,
    val unavailableSections: Set<VirtualMachineSection> = emptySet(),
)

data class VirtualMachineCreation(
    val name: String,
    val description: String,
    val cpuCount: Int,
    val memoryMiB: Int,
    val diskGiB: Int,
    val storageId: String,
    val networkId: String?,
    val diskImageId: String?,
    val autoStart: Boolean,
)

data class VirtualMachineSettings(
    val name: String,
    val description: String,
    val cpuCount: Int,
    val memoryMiB: Int,
    val autoStart: Boolean,
)

enum class LogLevel { INFO, WARNING, ERROR, UNKNOWN }

data class LogEntry(
    val id: String,
    val level: LogLevel,
    val timeEpochSeconds: Long?,
    val user: String,
    val event: String,
)

data class SystemSummary(
    val serverName: String,
    val model: String,
    val serial: String?,
    val dsmVersion: String,
    val uptimeSeconds: Long?,
    val temperatureCelsius: Double?,
)

/** DSM 更新服务返回的只读检查结果；不代表已下载或安装更新。 */
data class NasSystemUpdateInfo(
    val isUpdateAvailable: Boolean,
    val currentVersion: String?,
    val latestVersion: String?,
    val releaseNotes: String?,
)

data class CapacitySummary(
    val id: String,
    val name: String,
    val totalBytes: Long,
    val usedBytes: Long,
    val status: ResourceState,
)

enum class NasDiskTestType { QUICK, EXTENDED }

data class NasStorageDisk(
    val id: String,
    /** 必须来自存储列表，只用于硬盘检测请求，不能接受用户输入。 */
    val deviceId: String,
    val name: String,
    val model: String?,
    val status: String?,
    val smartStatus: String?,
    val temperatureCelsius: Double?,
    val supportsSmartTest: Boolean,
)

data class NasDiskTestStatus(
    val diskId: String,
    val isRunning: Boolean,
    val isBusyWithOtherTest: Boolean,
    val runningType: NasDiskTestType?,
    val progressDescription: String?,
    val lastQuickTest: String?,
    val lastExtendedTest: String?,
    val lastResult: String?,
    val isHistoryAvailable: Boolean,
)

data class PerformanceSample(
    val timeEpochSeconds: Long,
    val cpuPercent: Double?,
    val cpuUserPercent: Double?,
    val cpuSystemPercent: Double?,
    val memoryPercent: Double?,
    val swapPercent: Double?,
    val networkReceiveBytesPerSecond: Long?,
    val networkSendBytesPerSecond: Long?,
    val diskReadBytesPerSecond: Long?,
    val diskWriteBytesPerSecond: Long?,
    val volumeReadBytesPerSecond: Long?,
    val volumeWriteBytesPerSecond: Long?,
    val diskUtilizationPercent: Double?,
)

data class NasAccount(
    val id: Long?,
    val name: String,
    val description: String?,
    val email: String?,
    val disabled: Boolean,
    val canDelete: Boolean = false,
)

data class NasGroup(
    val id: Long?,
    val name: String,
    val description: String?,
    val canDelete: Boolean = false,
)

data class PackageInfo(
    val id: String,
    val name: String,
    val version: String,
    val status: ResourceState,
    val description: String?,
    val canStart: Boolean,
    val canStop: Boolean,
    val canUninstall: Boolean = false,
    val dsmApps: List<String> = emptyList(),
)

data class ActiveConnection(
    val id: String,
    val user: String,
    val service: String,
    val client: String,
    val connectedAtEpochSeconds: Long?,
    val isCurrent: Boolean,
    val processId: String? = null,
    val deviceId: String? = null,
    val type: String? = null,
    val description: String? = null,
    val canDisconnect: Boolean = false,
)

data class NasEthernetInterface(
    val id: String,
    val displayName: String,
    val status: String?,
    val usesDhcp: Boolean,
    val address: String,
    val subnetMask: String,
    val gateway: String,
    val dnsServers: String,
    val isDefaultGateway: Boolean,
    val mtu: Int,
    val isVlanEnabled: Boolean,
    val vlanId: Int?,
)

data class NasDdnsProvider(
    val id: String,
    val displayName: String,
)

data class NasDdnsRecord(
    val providerId: String,
    val providerName: String,
    val hostname: String,
    val address: String?,
    val status: String?,
    val lastUpdated: String?,
    val isEnabled: Boolean,
    val username: String,
    val networkType: String,
    val ipv4: String,
    val ipv6: String,
    val interfaceV4: String,
    val interfaceV6: String,
    val heartbeat: Boolean,
)

data class NasDdnsDirectory(
    val providers: List<NasDdnsProvider>,
    val records: List<NasDdnsRecord>,
)

/** null 字段表示当前 NAS 未提供对应文件服务能力。 */
data class NasFileServiceSettings(
    val isSmbEnabled: Boolean?,
    val isNfsEnabled: Boolean?,
    val isFtpEnabled: Boolean?,
    val isFtpsEnabled: Boolean?,
    val ftpPort: Int?,
    val isSftpEnabled: Boolean?,
    val sftpPort: Int?,
    val isSsdpEnabled: Boolean?,
    val isBonjourEnabled: Boolean?,
    val isSmbTimeMachineEnabled: Boolean?,
)

data class NasTerminalSettings(
    val isSshEnabled: Boolean,
    val isTelnetEnabled: Boolean,
    val sshPort: Int?,
)

/** 互联网代理凭据不在此模型中读取、保存或提交。 */
data class NasProxySettings(
    val isEnabled: Boolean,
    val host: String,
    val port: Int?,
)

/**
 * DSM 远程访问设置。null 表示对应内部接口不可用或响应不可信，不得折叠为关闭。
 * 连接类别与环境写门禁均由客户端可信上下文派生，不接受界面输入。
 */
data class NasRemoteAccessSettings(
    val isRelayEnabled: Boolean?,
    val isRouterConfigurationEnabled: Boolean?,
    val isConnectedThroughTrustedRelay: Boolean,
    val canManage: Boolean,
)

data class NasTimeZoneOption(
    val id: String,
    val displayName: String,
)

/** NAS 返回的墙上时间；仅用于区域设置预检与用户明确编辑后的提交。 */
data class NasManualDateTime(
    val year: Int,
    val month: Int,
    val day: Int,
    val hour: Int,
    val minute: Int,
    val second: Int,
)

data class NasRegionSettings(
    val dateFormat: String,
    val timeFormat: String,
    val timeZone: String,
    val isNetworkTimeEnabled: Boolean,
    val timeServers: List<String>,
    /** null 表示用户没有编辑手动时间，保存时必须使用刚从 NAS 读取的值。 */
    val manualDateTime: NasManualDateTime?,
    val timeZones: List<NasTimeZoneOption>,
)

data class NasDoSProtectionSetting(
    val id: String,
    val displayName: String,
    val isEnabled: Boolean,
)

data class NasSecuritySettings(
    val isAutoBlockEnabled: Boolean,
    val failedAttempts: Int,
    val withinMinutes: Int,
    /** null 表示封锁不会自动过期。 */
    val expirationDays: Int?,
    val dosProtection: List<NasDoSProtectionSetting>,
    val isFirewallEnabled: Boolean?,
    /** 只接受 NAS 预检返回的配置档名称，界面不得允许用户输入。 */
    val firewallProfileName: String?,
    val isPortScanProtectionEnabled: Boolean?,
)

data class NasUpsSettings(
    val isEnabled: Boolean,
    val mode: String,
    val safeModeDelaySeconds: Int?,
    val waitsUntilLowBattery: Boolean?,
    val shutsDownUpsAfterSafeMode: Boolean?,
    val networkServerAddress: String?,
    val snmpServerAddress: String?,
)

/** null 字段表示当前设备未提供对应硬件能力。 */
data class NasHardwareSettings(
    val restartsAfterPowerFailure: Boolean?,
    val ledBrightness: Int?,
    val ledBrightnessMinimum: Int?,
    val ledBrightnessMaximum: Int?,
    val fanMode: String?,
    val isFanFailureAlertEnabled: Boolean?,
    val isVolumeFailureAlertEnabled: Boolean?,
    val isPowerOnSoundEnabled: Boolean?,
    val isPowerOffSoundEnabled: Boolean?,
    val isResetSoundEnabled: Boolean?,
    val isExternalDriveDeepSleepEnabled: Boolean?,
    val isWakeUpLogEnabled: Boolean?,
    val isSataSleepEnabled: Boolean?,
    val ignoresNetworkDiscoveryDuringSleep: Boolean?,
    val isAutomaticPowerOffEnabled: Boolean?,
    val ups: NasUpsSettings?,
)

/** DDNS 密码或密钥只用于当前测试或保存请求，不得持久化。 */
data class NasDdnsDraft(
    val originalProviderId: String? = null,
    val providerId: String,
    val hostname: String,
    val username: String,
    val password: String = "",
    val isEnabled: Boolean = true,
    val networkType: String = "auto",
    val ipv4: String = "0.0.0.0",
    val ipv6: String = "0:0:0:0:0:0:0:0",
    val interfaceV4: String = "",
    val interfaceV6: String = "",
    val heartbeat: Boolean = false,
)

data class NasSettingsSnapshot(
    val system: SystemSummary?,
    val volumes: List<CapacitySummary>,
    val pools: List<ManagedResource>,
    val disks: List<ManagedResource>,
    val storageDisks: List<NasStorageDisk>,
    val packages: List<PackageInfo>,
    val scheduledTasks: List<ManagedResource>,
    val accounts: List<NasAccount>,
    val groups: List<NasGroup>,
    val logs: List<LogEntry>,
    val connections: List<ActiveConnection>,
    val connectionsAvailable: Boolean,
    val networkInterfaces: List<NasEthernetInterface>,
    val networkInterfacesAvailable: Boolean,
    val ddnsDirectory: NasDdnsDirectory?,
    val ddnsDirectoryAvailable: Boolean,
    val fileServiceSettings: NasFileServiceSettings?,
    val terminalSettings: NasTerminalSettings?,
    val proxySettings: NasProxySettings?,
    val regionSettings: NasRegionSettings?,
    val securitySettings: NasSecuritySettings?,
    val hardwareSettings: NasHardwareSettings?,
    val security: List<ManagedResource>,
    /** false 表示安全设置读取失败，不得把 null 当成可信空配置。 */
    val securitySettingsAvailable: Boolean = securitySettings != null,
    /** false 表示硬件设置读取失败，不得把 null 当成设备没有对应能力。 */
    val hardwareSettingsAvailable: Boolean = hardwareSettings != null,
    /** false 表示套件列表读取失败，空列表不得用于确认卸载成功。 */
    val packagesAvailable: Boolean = true,
    /** false 表示账号列表读取失败，空列表不得用于确认删除成功。 */
    val accountsAvailable: Boolean = true,
    /** false 表示群组列表读取失败，空列表不得用于确认删除成功。 */
    val groupsAvailable: Boolean = true,
    val remoteAccessSettings: NasRemoteAccessSettings? = null,
    /** false 表示两项远程访问读取均失败，不得把 null 当成可信关闭。 */
    val remoteAccessSettingsAvailable: Boolean = remoteAccessSettings != null,
)

data class ModuleAvailability(
    val module: Module,
    val isAvailable: Boolean,
    val reason: ModuleUnavailableReason? = null,
)

enum class ArchiveFormat(val apiValue: String, val fileExtension: String) {
    ZIP("zip", "zip"),
    SEVEN_ZIP("7z", "7z"),
}

enum class ArchiveCompressionLevel(val apiValue: String) {
    STORE("store"),
    FASTEST("fastest"),
    MODERATE("moderate"),
    BEST("best"),
}

data class ArchiveItem(
    val id: Int,
    val name: String,
    val path: String,
    val isDirectory: Boolean,
)
