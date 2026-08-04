package io.github.qwertyuiop1995.dsmnativeclient

import android.content.Context
import android.net.Uri
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.WorkerParameters
import io.github.qwertyuiop1995.dsmnativeclient.data.DsmRepository
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedUpload
import io.github.qwertyuiop1995.dsmnativeclient.data.TransferStore
import io.github.qwertyuiop1995.dsmnativeclient.data.UploadSource
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmConnectionResolver
import io.github.qwertyuiop1995.dsmnativeclient.storage.SecureProfileStore
import java.io.IOException
import kotlinx.coroutines.CancellationException

/** 用户通过系统照片选择器授权后，由 WorkManager 执行的单项备份。 */
class PhotoBackupWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    private val transfers = TransferStore(appContext)

    override suspend fun doWork(): Result {
        val taskId = inputData.getString(KEY_TASK_ID) ?: return Result.failure()
        val initial = transfers.upload(taskId) ?: return Result.failure()
        val executionId = id.toString()
        if (!initial.ownsUploadExecution(executionId)) return Result.success()
        if (initial.state !in setOf(TransferState.WAITING, TransferState.RUNNING)) {
            return Result.success(progressData(initial.completedBytes, initial.expectedBytes))
        }
        setForeground(
            TransferNotifications.foreground(
                applicationContext,
                taskId,
                id,
                TransferState.WAITING,
                initial.completedBytes,
                initial.expectedBytes,
                TransferDirection.UPLOAD,
            ),
        )
        val running = transfers.updateUpload(taskId) { current ->
            if (!current.ownsUploadExecution(executionId) ||
                current.state !in setOf(TransferState.WAITING, TransferState.RUNNING)
            ) {
                current
            } else {
                current.copy(
                    state = TransferState.RUNNING,
                    completedBytes = 0,
                    errorKind = null,
                    startedAtEpochMillis = System.currentTimeMillis(),
                )
            }
        }
        if (running?.ownsUploadExecution(executionId) != true ||
            running.state != TransferState.RUNNING
        ) {
            return Result.success(progressData(running?.completedBytes ?: 0, initial.expectedBytes))
        }
        return try {
            val repo = repository(initial)
            if (initial.backupMode || initial.mirrorDirectories) {
                repo.ensureSubdirectory(initial.destinationRootPath, initial.destinationPath)
            }
            val targetPath = initial.destinationPath.trimEnd('/') + "/" + initial.title
            val existing = if (repo.itemExists(targetPath)) repo.fileInfo(targetPath) else null
            val decision = if (initial.backupMode) {
                backupTargetDecision(existing, initial.expectedBytes)
            } else {
                userUploadTargetDecision(existing, initial.overwrite)
            }
            when (decision) {
                BackupTargetDecision.SKIP_MATCHING -> {
                    transfers.updateUpload(taskId) { current ->
                        current.completeUploadExecution(executionId, skippedExisting = true)
                    }
                    return Result.success(progressData(initial.expectedBytes, initial.expectedBytes))
                }
                BackupTargetDecision.CONFLICT -> throw DsmFailure(
                    null,
                    "An item with the same name already exists",
                    "Rename the local item or choose another backup folder.",
                    kind = DsmErrorKind.CHANGE_NOT_CONFIRMED,
                )
                BackupTargetDecision.UPLOAD -> Unit
            }
            val uri = Uri.parse(initial.sourceUri)
            val source = UploadSource(
                displayName = initial.title,
                contentType = initial.contentType,
                contentLength = initial.expectedBytes,
                openInputStream = {
                    applicationContext.contentResolver.openInputStream(uri)
                        ?: throw IOException("The selected photo is no longer available")
                },
            )
            var lastPublishedAt = 0L
            repo.upload(source, initial.destinationPath, overwrite = initial.overwrite) { completed, total ->
                val now = android.os.SystemClock.elapsedRealtime()
                if (now - lastPublishedAt >= PROGRESS_INTERVAL_MILLIS || completed == total) {
                    lastPublishedAt = now
                    transfers.updateUpload(taskId) { current ->
                        if (current.ownsUploadExecution(executionId) &&
                            current.state == TransferState.RUNNING
                        ) {
                            current.copy(completedBytes = completed)
                        } else {
                            current
                        }
                    }
                    setProgressAsync(progressData(completed, total))
                    setForegroundAsync(
                        TransferNotifications.foreground(
                            applicationContext,
                            taskId,
                            id,
                            TransferState.RUNNING,
                            completed,
                            total,
                            TransferDirection.UPLOAD,
                        ),
                    )
                }
            }
            val completed = transfers.updateUpload(taskId) { current ->
                current.completeUploadExecution(executionId, skippedExisting = false)
            }
            if (completed?.ownsUploadExecution(executionId) == true &&
                completed.state == TransferState.SUCCEEDED
            ) {
                TransferNotifications.completion(
                    applicationContext,
                    taskId,
                    succeeded = true,
                    direction = TransferDirection.UPLOAD,
                )
            }
            Result.success(progressData(initial.expectedBytes, initial.expectedBytes))
        } catch (error: CancellationException) {
            transfers.updateUpload(taskId) { current ->
                current.cancelUploadExecution(executionId)
            }
            throw error
        } catch (error: Throwable) {
            val kind = (error as? DsmFailure)?.kind ?: DsmErrorKind.UPLOAD_FAILED
            val failed = transfers.updateUpload(taskId) { current ->
                if (!current.ownsUploadExecution(executionId) ||
                    current.state != TransferState.RUNNING
                ) {
                    current
                } else {
                    current.copy(
                        state = TransferState.FAILED,
                        errorKind = kind.name,
                        requiresRefresh = !current.backupMode && (
                            current.completedBytes > 0 || kind in setOf(
                                DsmErrorKind.CONNECTION_FAILED,
                                DsmErrorKind.INVALID_RESPONSE,
                                DsmErrorKind.CHANGE_NOT_CONFIRMED,
                                DsmErrorKind.UPLOAD_LENGTH_MISMATCH,
                            )
                        ),
                    )
                }
            }
            if (failed?.ownsUploadExecution(executionId) == true &&
                failed.state == TransferState.FAILED
            ) {
                TransferNotifications.completion(
                    applicationContext,
                    taskId,
                    succeeded = false,
                    direction = TransferDirection.UPLOAD,
                )
            }
            Result.failure(Data.Builder().putString(KEY_ERROR_KIND, kind.name).build())
        }
    }

    private suspend fun repository(upload: PersistedUpload): DsmRepository {
        val store = SecureProfileStore(applicationContext)
        val profile = store.profiles().firstOrNull { it.id == upload.profileId }
            ?: throw IllegalStateException("The saved NAS profile is unavailable")
        val session = store.session(upload.profileId)
            ?: throw IllegalStateException("The saved session is unavailable")
        val api = DsmApiClient()
        val discovered = DsmConnectionResolver(api).discover(profile)
        return DsmRepository(discovered.profile, session, api, discovered.capabilities)
    }

    companion object {
        const val KEY_TASK_ID = "task_id"
        const val KEY_COMPLETED_BYTES = "completed_bytes"
        const val KEY_TOTAL_BYTES = "total_bytes"
        const val KEY_ERROR_KIND = "error_kind"
        const val UNIQUE_WORK_PREFIX = "photo-backup-"
        const val FILE_UPLOAD_UNIQUE_WORK_PREFIX = "file-upload-"
        private const val PROGRESS_INTERVAL_MILLIS = 400L

        fun progressData(completed: Long, total: Long): Data = Data.Builder()
            .putLong(KEY_COMPLETED_BYTES, completed)
            .putLong(KEY_TOTAL_BYTES, total)
            .build()
    }
}

internal enum class BackupTargetDecision { UPLOAD, SKIP_MATCHING, CONFLICT }

internal fun backupTargetDecision(
    existing: io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem?,
    expectedBytes: Long,
): BackupTargetDecision = when {
    existing == null -> BackupTargetDecision.UPLOAD
    !existing.isDirectory && existing.size == expectedBytes -> BackupTargetDecision.SKIP_MATCHING
    else -> BackupTargetDecision.CONFLICT
}

internal fun userUploadTargetDecision(
    existing: io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem?,
    overwrite: Boolean,
): BackupTargetDecision = when {
    existing == null -> BackupTargetDecision.UPLOAD
    overwrite && !existing.isDirectory -> BackupTargetDecision.UPLOAD
    else -> BackupTargetDecision.CONFLICT
}

internal fun PersistedUpload.ownsUploadExecution(executionId: String): Boolean =
    workId.isCurrentDownloadExecution(executionId)

internal fun PersistedUpload.cancelUploadExecution(executionId: String): PersistedUpload =
    if (workerCancellationDecision(state, workId, executionId) ==
        WorkerCancellationDecision.USER_CANCELLATION
    ) {
        copy(
            state = TransferState.CANCELLED,
            errorKind = null,
            requiresRefresh = !backupMode && completedBytes > 0,
        )
    } else {
        this
    }

internal fun PersistedUpload.completeUploadExecution(
    executionId: String,
    skippedExisting: Boolean,
): PersistedUpload = if (ownsUploadExecution(executionId) && state == TransferState.RUNNING) {
    copy(
        state = TransferState.SUCCEEDED,
        completedBytes = expectedBytes,
        errorKind = null,
        skippedExisting = skippedExisting,
        requiresRefresh = false,
    )
} else {
    this
}
