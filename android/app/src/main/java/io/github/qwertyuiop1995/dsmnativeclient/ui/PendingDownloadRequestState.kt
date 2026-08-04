package io.github.qwertyuiop1995.dsmnativeclient.ui

import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.listSaver
import io.github.qwertyuiop1995.dsmnativeclient.DownloadEnqueueResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem

/**
 * 系统保存页面返回前所需的最小下载请求。
 *
 * 只保存可恢复的文件元数据，不保存会话、凭据或本地 URI。
 */
internal data class PendingDownloadRequest(
    val profileId: String,
    val path: String,
    val name: String,
    val isDirectory: Boolean,
    val size: Long,
    val canRead: Boolean,
) {
    fun toFileItem(): FileItem = FileItem(
        path = path,
        name = name,
        isDirectory = isDirectory,
        size = size,
        canRead = canRead,
    )
}

internal data class PendingDownloadRequestState(
    val request: PendingDownloadRequest? = null,
)

internal fun FileItem.toPendingDownloadRequest(profileId: String): PendingDownloadRequest =
    PendingDownloadRequest(
        profileId = profileId,
        path = path,
        name = name,
        isDirectory = isDirectory,
        size = size,
        canRead = canRead,
    )

internal fun PendingDownloadRequestState.toSaveableValues(): List<Any> {
    val pending = request ?: return listOf(false)
    return listOf(
        true,
        pending.profileId,
        pending.path,
        pending.name,
        pending.isDirectory,
        pending.size,
        pending.canRead,
    )
}

internal fun pendingDownloadRequestStateFrom(values: List<Any>): PendingDownloadRequestState {
    if (values.firstOrNull() != true || values.size != PENDING_REQUEST_VALUE_COUNT) {
        return PendingDownloadRequestState()
    }
    val profileId = values[1] as? String ?: return PendingDownloadRequestState()
    val path = values[2] as? String ?: return PendingDownloadRequestState()
    val name = values[3] as? String ?: return PendingDownloadRequestState()
    val isDirectory = values[4] as? Boolean ?: return PendingDownloadRequestState()
    val size = values[5] as? Long ?: return PendingDownloadRequestState()
    val canRead = values[6] as? Boolean ?: return PendingDownloadRequestState()
    return PendingDownloadRequestState(
        PendingDownloadRequest(
            profileId = profileId,
            path = path,
            name = name,
            isDirectory = isDirectory,
            size = size,
            canRead = canRead,
        ),
    )
}

internal val PendingDownloadRequestStateSaver: Saver<PendingDownloadRequestState, Any> = listSaver(
    save = { state -> state.toSaveableValues() },
    restore = ::pendingDownloadRequestStateFrom,
)

internal enum class DownloadDestinationDecision {
    CANCELLED,
    ENQUEUE,
    DISCARD_ORPHAN,
}

internal data class ResolvedDownloadDestination(
    val decision: DownloadDestinationDecision,
    val request: PendingDownloadRequest? = null,
    val nextPending: PendingDownloadRequestState = PendingDownloadRequestState(),
)

/** 每个选择器结果只消费一次；调用方在执行决策前清空已保存请求。 */
internal fun resolveDownloadDestination(
    pending: PendingDownloadRequestState,
    activeProfileId: String,
    destinationSelected: Boolean,
): ResolvedDownloadDestination {
    if (!destinationSelected) {
        return ResolvedDownloadDestination(DownloadDestinationDecision.CANCELLED)
    }
    val request = pending.request
    return if (request != null && request.profileId == activeProfileId) {
        ResolvedDownloadDestination(DownloadDestinationDecision.ENQUEUE, request)
    } else {
        ResolvedDownloadDestination(DownloadDestinationDecision.DISCARD_ORPHAN)
    }
}

internal fun shouldRequestDownloadNotificationPermission(
    enqueueResult: DownloadEnqueueResult,
    sdkInt: Int,
    notificationPermissionGranted: Boolean,
): Boolean = enqueueResult == DownloadEnqueueResult.BACKGROUND &&
    sdkInt >= 33 &&
    !notificationPermissionGranted

private const val PENDING_REQUEST_VALUE_COUNT = 7
