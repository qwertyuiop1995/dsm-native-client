package io.github.qwertyuiop1995.dsmnativeclient.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * 仅用于本机加密外链映射的最小业务定位符。
 *
 * 这个模型不能进入 URI、Intent、SavedState 或日志。打开链接时仍须从当前 NAS 重新读取目标，
 * 因此这里刻意不保存完整领域对象、显示名、NAS 地址、会话或服务端响应。
 */
@Serializable
sealed interface OpaqueWorkspaceTarget {
    @Serializable
    @SerialName("file_directory")
    data class FileDirectory(
        val canonicalPath: String,
    ) : OpaqueWorkspaceTarget

    @Serializable
    @SerialName("file_preview")
    data class FilePreview(
        val canonicalPath: String,
    ) : OpaqueWorkspaceTarget

    @Serializable
    @SerialName("photo_folder")
    data class PhotoFolder(
        val spaceId: String,
        val canonicalPath: String,
    ) : OpaqueWorkspaceTarget

    @Serializable
    @SerialName("photo_viewer")
    data class PhotoViewer(
        val spaceId: String,
        val canonicalPath: String,
    ) : OpaqueWorkspaceTarget

    @Serializable
    @SerialName("chat_conversation")
    data class ChatConversation(
        val conversationId: String,
    ) : OpaqueWorkspaceTarget

    @Serializable
    @SerialName("download_task")
    data class DownloadTask(
        val taskId: String,
    ) : OpaqueWorkspaceTarget

    @Serializable
    @SerialName("virtual_machine_guest")
    data class VirtualMachineGuest(
        val guestId: String,
    ) : OpaqueWorkspaceTarget
}

/**
 * 已加密保存的本机外链记录。
 *
 * [token] 是 URI 中唯一允许出现的值；其余字段只保存在现有的加密资料存储内。
 */
@Serializable
data class OpaqueWorkspaceRouteRecord(
    val token: String,
    val profileId: String,
    val target: OpaqueWorkspaceTarget,
    val createdAtEpochMillis: Long,
    val schemaVersion: Int = OPAQUE_WORKSPACE_ROUTE_SCHEMA_VERSION,
)

const val OPAQUE_WORKSPACE_ROUTE_SCHEMA_VERSION = 1
