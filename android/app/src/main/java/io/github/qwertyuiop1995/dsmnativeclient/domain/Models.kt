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

data class DsmFailure(
    val code: Int?,
    override val message: String,
    val recovery: String,
    val isAuthenticationFailure: Boolean = false,
) : RuntimeException(message)

enum class Module(
    val title: String,
    val subtitle: String,
) {
    FILES("文件浏览器", "浏览、搜索和管理 NAS 文件"),
    PHOTOS("照片", "按时间线浏览和管理照片"),
    CHAT("消息", "使用 Synology Chat 收发消息"),
    DOWNLOADS("下载管理", "管理 Download Station 任务"),
    CONTAINERS("容器管理", "查看和控制容器、映像与项目"),
    VIRTUAL_MACHINES("虚拟机管理", "管理虚拟机、网络、映像和保护"),
    NAS_SETTINGS("NAS 设置", "系统、存储、账号、网络和安全"),
    TRANSFERS("传输中心", "查看上传、下载与 NAS 后台任务"),
    SETTINGS("设置", "管理模块、缓存和本机数据"),
}

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
    val owner: String? = null,
    val mimeType: String? = null,
    val canRead: Boolean = true,
    val canWrite: Boolean = false,
    val canDelete: Boolean = false,
    val isFavorite: Boolean = false,
) {
    val extension: String get() = name.substringAfterLast('.', "").lowercase()
}

data class FilePage(
    val items: List<FileItem>,
    val total: Int,
    val offset: Int,
)

enum class TransferDirection { DOWNLOAD, UPLOAD, SERVER }
enum class TransferState { WAITING, RUNNING, PAUSED, SUCCEEDED, FAILED, CANCELLED }

data class TransferTask(
    val id: String,
    val title: String,
    val detail: String,
    val direction: TransferDirection,
    val state: TransferState,
    val completedBytes: Long = 0,
    val totalBytes: Long? = null,
    val errorMessage: String? = null,
) {
    val progress: Float?
        get() = totalBytes?.takeIf { it > 0 }?.let {
            (completedBytes.toDouble() / it.toDouble()).coerceIn(0.0, 1.0).toFloat()
        }
}

enum class PhotoSpaceKind { PERSONAL, SHARED }

data class PhotoSpace(
    val id: String,
    val title: String,
    val rootPath: String,
    val kind: PhotoSpaceKind,
)

data class PhotoItem(
    val id: String,
    val file: FileItem,
    val takenAtEpochSeconds: Long?,
    val width: Int? = null,
    val height: Int? = null,
    val isVideo: Boolean = false,
    val isLivePhoto: Boolean = false,
)

data class ChatUser(
    val id: Long,
    val displayName: String,
    val username: String,
    val isDisabled: Boolean = false,
)

enum class ConversationKind { DIRECT, GROUP }

data class ChatConversation(
    val id: Long,
    val title: String,
    val kind: ConversationKind,
    val unreadCount: Int = 0,
    val isPinnedLocally: Boolean = false,
    val memberCount: Int = 0,
    val latestPreview: String? = null,
    val latestAtEpochSeconds: Long? = null,
)

data class ChatAttachment(
    val id: Long,
    val name: String,
    val mimeType: String?,
    val size: Long?,
)

data class ChatMessage(
    val id: Long,
    val conversationId: Long,
    val sender: ChatUser?,
    val body: String,
    val createdAtEpochSeconds: Long,
    val isMine: Boolean,
    val attachments: List<ChatAttachment> = emptyList(),
    val isPinned: Boolean = false,
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
)

data class DownloadTask(
    val id: String,
    val title: String,
    val status: ResourceState,
    val size: Long?,
    val transferred: Long?,
    val downloadSpeed: Long?,
    val uploadSpeed: Long?,
    val destination: String?,
    val error: String?,
)

data class DownloadSettings(
    val destination: String,
    val downloadLimitKb: Int,
    val uploadLimitKb: Int,
    val autoExtract: Boolean,
    val emuleEnabled: Boolean,
)

data class ContainerOverview(
    val containers: List<ManagedResource>,
    val images: List<ManagedResource>,
    val networks: List<ManagedResource>,
    val projects: List<ManagedResource>,
)

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

data class CapacitySummary(
    val id: String,
    val name: String,
    val totalBytes: Long,
    val usedBytes: Long,
    val status: ResourceState,
)

data class PerformanceSample(
    val timeEpochSeconds: Long,
    val cpuPercent: Double?,
    val memoryPercent: Double?,
    val networkReceiveBytesPerSecond: Long?,
    val networkSendBytesPerSecond: Long?,
)

data class NasAccount(
    val id: Long?,
    val name: String,
    val description: String?,
    val email: String?,
    val disabled: Boolean,
)

data class NasGroup(
    val id: Long?,
    val name: String,
    val description: String?,
)

data class PackageInfo(
    val id: String,
    val name: String,
    val version: String,
    val status: ResourceState,
    val description: String?,
    val canStart: Boolean,
    val canStop: Boolean,
)

data class ActiveConnection(
    val id: String,
    val user: String,
    val service: String,
    val client: String,
    val connectedAtEpochSeconds: Long?,
    val isCurrent: Boolean,
)

data class NasSettingsSnapshot(
    val system: SystemSummary?,
    val volumes: List<CapacitySummary>,
    val pools: List<ManagedResource>,
    val disks: List<ManagedResource>,
    val packages: List<PackageInfo>,
    val scheduledTasks: List<ManagedResource>,
    val accounts: List<NasAccount>,
    val groups: List<NasGroup>,
    val logs: List<LogEntry>,
    val connections: List<ActiveConnection>,
    val networkInterfaces: List<ManagedResource>,
    val ddnsRecords: List<ManagedResource>,
    val security: List<ManagedResource>,
)

data class ModuleAvailability(
    val module: Module,
    val isAvailable: Boolean,
    val reason: String? = null,
)

