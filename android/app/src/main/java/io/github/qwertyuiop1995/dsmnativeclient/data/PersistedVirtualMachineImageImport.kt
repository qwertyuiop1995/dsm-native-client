package io.github.qwertyuiop1995.dsmnativeclient.data

import kotlinx.serialization.Serializable

/**
 * 本地映像经 File Station 暂存后导入 VMM 的加密恢复记录。
 *
 * 仅保存恢复所需的稳定标识、用户授权 URI 和 NAS 文件基线；不得加入会话、令牌、账号、
 * NAS 地址或响应正文。服务端 task/image 标识也不得进入日志或默认 `toString()`。
 */
@Serializable
data class PersistedVirtualMachineImageImport(
    val id: String,
    val profileId: String,
    val sourceUri: String,
    val sourceDisplayName: String,
    val expectedBytes: Long,
    val stagingDirectoryPath: String,
    val temporaryFileName: String,
    val imageName: String,
    val imageType: PersistedVirtualMachineImageType,
    val storageId: String,
    val sourceContentType: String? = null,
    val storageName: String = "",
    val storageStatus: String = "",
    val stage: PersistedVirtualMachineImageImportStage =
        PersistedVirtualMachineImageImportStage.PREPARING,
    val workId: String? = null,
    val taskId: String? = null,
    val taskClearSubmitted: Boolean = false,
    val imageId: String? = null,
    val temporaryFileBaseline: PersistedServerFileBaseline? = null,
    val ownsPersistedReadGrant: Boolean = true,
    val requiresRefresh: Boolean = false,
    val errorKind: String? = null,
) {
    val temporaryFilePath: String
        get() = stagingDirectoryPath.trimEnd('/') + "/" + temporaryFileName

    override fun toString(): String =
        "PersistedVirtualMachineImageImport(id=$id, profileId=$profileId, stage=$stage, " +
            "hasTaskId=${taskId != null}, hasImageId=${imageId != null})"
}

@Serializable
enum class PersistedVirtualMachineImageType {
    DISK,
    VDSM,
    ISO,
}

@Serializable
enum class PersistedVirtualMachineImageImportStage {
    PREPARING,
    UPLOAD_SUBMITTING,
    UPLOADED,
    CREATE_SUBMITTING,
    TASK_TRACKING,
    IMAGE_READBACK,
    TASK_CLEARING,
    TEMP_CLEANUP,
    CLEANUP_PENDING,
    NEEDS_REVIEW,
    SUCCEEDED,
    FAILED,
    CANCELLED,
}

/** UPLOAD_SUBMITTING 恢复时，必须先对唯一 NAS 临时路径做严格回读。 */
enum class PersistedVmmUploadReadback {
    MATCHES,
    MISSING,
    DIFFERS,
}

/** 纯恢复决策不执行网络写操作，调用方必须先持久化下一阶段再执行对应动作。 */
enum class PersistedVmmImportRecoveryAction {
    START_UPLOAD,
    CONFIRM_UPLOAD_READBACK,
    RETRY_UPLOAD_WITHOUT_OVERWRITE,
    START_CREATE,
    READ_TASK,
    READ_IMAGE,
    CLEAR_TASK,
    CHECK_TASK_CLEARED,
    DELETE_TEMP_FILE_WITH_BASELINE,
    WAIT_FOR_REVIEW,
    NONE,
}

internal fun PersistedVirtualMachineImageImport.recoveryAction(
    uploadReadback: PersistedVmmUploadReadback? = null,
): PersistedVmmImportRecoveryAction = when (stage) {
    PersistedVirtualMachineImageImportStage.PREPARING ->
        PersistedVmmImportRecoveryAction.START_UPLOAD
    PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING -> when (uploadReadback) {
        PersistedVmmUploadReadback.MATCHES ->
            PersistedVmmImportRecoveryAction.CONFIRM_UPLOAD_READBACK
        PersistedVmmUploadReadback.MISSING ->
            PersistedVmmImportRecoveryAction.RETRY_UPLOAD_WITHOUT_OVERWRITE
        PersistedVmmUploadReadback.DIFFERS, null ->
            PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW
    }
    PersistedVirtualMachineImageImportStage.UPLOADED -> if (temporaryFileBaseline == null) {
        PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW
    } else {
        PersistedVmmImportRecoveryAction.START_CREATE
    }
    PersistedVirtualMachineImageImportStage.CREATE_SUBMITTING -> if (taskId == null) {
        PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW
    } else {
        PersistedVmmImportRecoveryAction.READ_TASK
    }
    PersistedVirtualMachineImageImportStage.TASK_TRACKING -> if (taskId == null) {
        PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW
    } else {
        PersistedVmmImportRecoveryAction.READ_TASK
    }
    PersistedVirtualMachineImageImportStage.IMAGE_READBACK -> if (taskId == null || imageId == null) {
        PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW
    } else {
        PersistedVmmImportRecoveryAction.READ_IMAGE
    }
    PersistedVirtualMachineImageImportStage.TASK_CLEARING -> when {
        taskId == null -> PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW
        taskClearSubmitted -> PersistedVmmImportRecoveryAction.CHECK_TASK_CLEARED
        else -> PersistedVmmImportRecoveryAction.CLEAR_TASK
    }
    PersistedVirtualMachineImageImportStage.TEMP_CLEANUP,
    PersistedVirtualMachineImageImportStage.CLEANUP_PENDING,
    -> if (temporaryFileBaseline == null) {
        PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW
    } else {
        PersistedVmmImportRecoveryAction.DELETE_TEMP_FILE_WITH_BASELINE
    }
    PersistedVirtualMachineImageImportStage.NEEDS_REVIEW ->
        PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW
    PersistedVirtualMachineImageImportStage.SUCCEEDED,
    PersistedVirtualMachineImageImportStage.FAILED,
    PersistedVirtualMachineImageImportStage.CANCELLED,
    -> PersistedVmmImportRecoveryAction.NONE
}

internal fun PersistedVirtualMachineImageImport.markUploadSubmitting():
    PersistedVirtualMachineImageImport? = takeIf {
    stage == PersistedVirtualMachineImageImportStage.PREPARING
}?.copy(stage = PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING)

internal fun PersistedVirtualMachineImageImport.confirmUploaded(
    baseline: PersistedServerFileBaseline,
): PersistedVirtualMachineImageImport? = takeIf {
    stage == PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING &&
        baseline.path == temporaryFilePath && baseline.name == temporaryFileName &&
        !baseline.isDirectory && baseline.size == expectedBytes
}?.copy(
    stage = PersistedVirtualMachineImageImportStage.UPLOADED,
    temporaryFileBaseline = baseline,
    errorKind = null,
)

internal fun PersistedVirtualMachineImageImport.markReadGrantReleased() =
    copy(ownsPersistedReadGrant = false)

/** 必须先持久化此边界，再调用 Guest.Image.create。 */
internal fun PersistedVirtualMachineImageImport.markCreateSubmitting():
    PersistedVirtualMachineImageImport? = takeIf {
    stage == PersistedVirtualMachineImageImportStage.UPLOADED && temporaryFileBaseline != null
}?.copy(
    stage = PersistedVirtualMachineImageImportStage.CREATE_SUBMITTING,
    taskId = null,
)

internal fun PersistedVirtualMachineImageImport.captureTaskId(value: String):
    PersistedVirtualMachineImageImport? = takeIf {
    stage == PersistedVirtualMachineImageImportStage.CREATE_SUBMITTING
}?.let { current -> value.takeIf(String::isNotBlank)?.let {
    current.copy(stage = PersistedVirtualMachineImageImportStage.TASK_TRACKING, taskId = it)
} }

internal fun PersistedVirtualMachineImageImport.markImageReadback(value: String):
    PersistedVirtualMachineImageImport? = takeIf {
    stage == PersistedVirtualMachineImageImportStage.TASK_TRACKING && taskId != null
}?.let { current -> value.takeIf(String::isNotBlank)?.let {
    current.copy(stage = PersistedVirtualMachineImageImportStage.IMAGE_READBACK, imageId = it)
} }

internal fun PersistedVirtualMachineImageImport.markTaskClearing():
    PersistedVirtualMachineImageImport? = takeIf {
    stage == PersistedVirtualMachineImageImportStage.IMAGE_READBACK &&
        taskId != null && imageId != null
}?.copy(
    stage = PersistedVirtualMachineImageImportStage.TASK_CLEARING,
    taskClearSubmitted = false,
)

internal fun PersistedVirtualMachineImageImport.markTaskClearSubmitted():
    PersistedVirtualMachineImageImport? = takeIf {
    stage == PersistedVirtualMachineImageImportStage.TASK_CLEARING &&
        taskId != null && !taskClearSubmitted
}?.copy(taskClearSubmitted = true)

internal fun PersistedVirtualMachineImageImport.markTemporaryCleanup():
    PersistedVirtualMachineImageImport? = takeIf {
    stage == PersistedVirtualMachineImageImportStage.TASK_CLEARING &&
        taskId != null && taskClearSubmitted
}?.copy(
    stage = PersistedVirtualMachineImageImportStage.TEMP_CLEANUP,
    taskId = null,
    taskClearSubmitted = false,
)

internal fun PersistedVirtualMachineImageImport.markCleanupPending(errorKind: String?):
    PersistedVirtualMachineImageImport? = takeIf {
    stage in setOf(
        PersistedVirtualMachineImageImportStage.TEMP_CLEANUP,
        PersistedVirtualMachineImageImportStage.CLEANUP_PENDING,
    )
}?.copy(
    stage = PersistedVirtualMachineImageImportStage.CLEANUP_PENDING,
    requiresRefresh = true,
    errorKind = errorKind,
)

internal fun PersistedVirtualMachineImageImport.markSucceeded():
    PersistedVirtualMachineImageImport? = takeIf {
    stage in setOf(
        PersistedVirtualMachineImageImportStage.TEMP_CLEANUP,
        PersistedVirtualMachineImageImportStage.CLEANUP_PENDING,
    )
}?.copy(
    stage = PersistedVirtualMachineImageImportStage.SUCCEEDED,
    requiresRefresh = false,
    errorKind = null,
    temporaryFileBaseline = null,
)

internal fun PersistedVirtualMachineImageImport.markNeedsReview(errorKind: String?) = copy(
    stage = PersistedVirtualMachineImageImportStage.NEEDS_REVIEW,
    requiresRefresh = true,
    errorKind = errorKind,
)

internal fun PersistedVirtualMachineImageImport.canRemoveFromHistory(): Boolean =
    stage in setOf(
        PersistedVirtualMachineImageImportStage.SUCCEEDED,
        PersistedVirtualMachineImageImportStage.FAILED,
        PersistedVirtualMachineImageImportStage.CANCELLED,
    ) && !requiresRefresh && temporaryFileBaseline == null

internal fun List<PersistedVirtualMachineImageImport>.upsert(
    value: PersistedVirtualMachineImageImport,
): List<PersistedVirtualMachineImageImport> = filterNot { it.id == value.id } + value

internal fun List<PersistedVirtualMachineImageImport>.canClaimWork(id: String): Boolean {
    val target = firstOrNull { it.id == id } ?: return false
    if (target.workId != null) return false
    val contenders = filter {
        it.profileId == target.profileId &&
            it.imageName.trim().equals(target.imageName.trim(), ignoreCase = true) &&
            it.workId == null &&
            it.stage !in setOf(
                PersistedVirtualMachineImageImportStage.SUCCEEDED,
                PersistedVirtualMachineImageImportStage.FAILED,
                PersistedVirtualMachineImageImportStage.CANCELLED,
            )
    }
    val activeOwner = any {
        it.id != id && it.profileId == target.profileId &&
            it.imageName.trim().equals(target.imageName.trim(), ignoreCase = true) &&
            it.workId != null &&
            it.stage !in setOf(
                PersistedVirtualMachineImageImportStage.SUCCEEDED,
                PersistedVirtualMachineImageImportStage.FAILED,
                PersistedVirtualMachineImageImportStage.CANCELLED,
            )
    }
    return !activeOwner && contenders.minByOrNull { it.id }?.id == id
}

internal fun List<PersistedVirtualMachineImageImport>.insertAndClaimWork(
    value: PersistedVirtualMachineImageImport,
    workId: String,
): Pair<List<PersistedVirtualMachineImageImport>, Boolean> {
    if (value.workId != null || any { it.id == value.id }) return this to false
    val hasActiveName = any {
        it.profileId == value.profileId &&
            it.imageName.trim().equals(value.imageName.trim(), ignoreCase = true) &&
            it.stage !in setOf(
                PersistedVirtualMachineImageImportStage.SUCCEEDED,
                PersistedVirtualMachineImageImportStage.FAILED,
                PersistedVirtualMachineImageImportStage.CANCELLED,
            )
    }
    if (hasActiveName) return this to false
    return this + value.copy(workId = workId) to true
}

internal fun List<PersistedVirtualMachineImageImport>.updateById(
    id: String,
    transform: (PersistedVirtualMachineImageImport) -> PersistedVirtualMachineImageImport,
): Pair<List<PersistedVirtualMachineImageImport>, PersistedVirtualMachineImageImport?> {
    var updated: PersistedVirtualMachineImageImport? = null
    val values = map { current ->
        if (current.id == id) transform(current).also { updated = it } else current
    }
    return values to updated
}

internal fun List<PersistedVirtualMachineImageImport>.releaseWorkClaim(
    id: String,
    workId: String,
): Pair<List<PersistedVirtualMachineImageImport>, Boolean> {
    val target = firstOrNull { it.id == id } ?: return this to false
    if (target.workId != workId) return this to false
    return map { if (it.id == id) it.copy(workId = null) else it } to true
}

internal fun List<PersistedVirtualMachineImageImport>.removeOwnedPreparingImport(
    id: String,
    workId: String,
): Pair<List<PersistedVirtualMachineImageImport>, Boolean> {
    val target = firstOrNull { it.id == id } ?: return this to false
    if (target.workId != workId || target.stage != PersistedVirtualMachineImageImportStage.PREPARING) {
        return this to false
    }
    return filterNot { it.id == id } to true
}

internal fun List<PersistedVirtualMachineImageImport>.removeFinishedById(
    id: String,
): Pair<List<PersistedVirtualMachineImageImport>, Boolean> {
    val target = firstOrNull { it.id == id } ?: return this to false
    if (!target.canRemoveFromHistory()) return this to false
    return filterNot { it.id == id } to true
}
