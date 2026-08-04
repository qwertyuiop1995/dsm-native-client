package io.github.qwertyuiop1995.dsmnativeclient.domain

/**
 * 照片“释放设备空间”的纯领域门禁条件。
 *
 * 所有条件都必须由上层显式提供且同时成立；任何未知、未完成或未开放状态都按拒绝处理。
 * 此模型只表达是否允许继续，不申请权限，也不执行设备文件删除。
 */
internal data class PhotoDeviceSpaceReleaseConditions(
    val isEveryNasItemReadBackConfirmed: Boolean,
    val isBackupStateStable: Boolean,
    val hasUserSecondConfirmation: Boolean,
    val isBehaviorEnabled: Boolean,
    val canDeleteDeviceMedia: Boolean,
)

/** 仅当 NAS 逐项确认、备份稳定、用户二次确认且删除能力已明确开放时才允许继续。 */
internal fun PhotoDeviceSpaceReleaseConditions.allowsDeviceSpaceRelease(): Boolean =
    isEveryNasItemReadBackConfirmed &&
        isBackupStateStable &&
        hasUserSecondConfirmation &&
        isBehaviorEnabled &&
        canDeleteDeviceMedia
