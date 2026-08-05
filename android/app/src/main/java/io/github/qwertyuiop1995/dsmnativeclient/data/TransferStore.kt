package io.github.qwertyuiop1995.dsmnativeclient.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskPage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskSummary
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationExpectedOutput
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationTarget
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationVerification
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * 只保存恢复传输所需的非凭据状态；SID、令牌、账号和 NAS 地址不进入此存储。
 */
class TransferStore(
    context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()
    private val preferences = EncryptedSharedPreferences.create(
        context,
        PREFERENCES_NAME,
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    @Synchronized
    fun downloads(profileId: String): List<PersistedDownload> = all().filter { it.profileId == profileId }

    @Synchronized
    fun download(id: String): PersistedDownload? = all().firstOrNull { it.id == id }

    @Synchronized
    fun uploads(profileId: String): List<PersistedUpload> = allUploads().filter { it.profileId == profileId }

    @Synchronized
    fun upload(id: String): PersistedUpload? = allUploads().firstOrNull { it.id == id }

    @Synchronized
    fun servers(profileId: String): List<PersistedServerTransfer> =
        allServers().filter { it.profileId == profileId }

    @Synchronized
    fun server(id: String): PersistedServerTransfer? = allServers().firstOrNull { it.id == id }

    @Synchronized
    fun fileBackgroundTaskSnapshot(profileId: String): PersistedFileBackgroundTaskSnapshot? =
        allFileBackgroundTaskSnapshots().firstOrNull { it.profileId == profileId }

    @Synchronized
    fun photoBackupSource(profileId: String): PersistedPhotoBackupSource? =
        allBackupSources().firstOrNull { it.profileId == profileId }

    @Synchronized
    fun upsert(download: PersistedDownload) {
        val next = all().filterNot { it.id == download.id } + download
        save(next)
    }

    @Synchronized
    fun update(id: String, transform: (PersistedDownload) -> PersistedDownload): PersistedDownload? {
        var updated: PersistedDownload? = null
        val next = all().map { current ->
            if (current.id == id) transform(current).also { updated = it } else current
        }
        if (updated != null) save(next)
        return updated
    }

    @Synchronized
    fun upsert(upload: PersistedUpload) {
        saveUploads(allUploads().filterNot { it.id == upload.id } + upload)
    }

    @Synchronized
    fun updateUpload(id: String, transform: (PersistedUpload) -> PersistedUpload): PersistedUpload? {
        var updated: PersistedUpload? = null
        val next = allUploads().map { current ->
            if (current.id == id) transform(current).also { updated = it } else current
        }
        if (updated != null) saveUploads(next)
        return updated
    }

    @Synchronized
    fun upsert(server: PersistedServerTransfer) {
        saveServers(allServers().filterNot { it.id == server.id } + server)
    }

    @Synchronized
    fun updateServer(
        id: String,
        transform: (PersistedServerTransfer) -> PersistedServerTransfer,
    ): PersistedServerTransfer? {
        var updated: PersistedServerTransfer? = null
        val next = allServers().map { current ->
            if (current.id == id) transform(current).also { updated = it } else current
        }
        if (updated != null) saveServers(next)
        return updated
    }

    /** 只有已经安全收敛的终态任务可以从普通清理入口移除。 */
    @Synchronized
    fun removeServer(id: String): Boolean {
        val current = allServers()
        val target = current.firstOrNull { it.id == id } ?: return false
        if (!target.canRemoveFinishedServer()) return false
        saveServers(current.filterNot { it.id == id })
        return true
    }

    /** 丢弃无法还原目标的损坏记录；正常任务始终带有完整目标基线。 */
    @Synchronized
    fun removeInvalidServer(id: String): Boolean {
        val current = allServers()
        val target = current.firstOrNull { it.id == id } ?: return false
        if (target.toFileServerMutationTarget() != null) return false
        saveServers(current.filterNot { it.id == id })
        return true
    }

    @Synchronized
    fun replaceFileBackgroundTaskSnapshot(snapshot: PersistedFileBackgroundTaskSnapshot) {
        saveFileBackgroundTaskSnapshots(
            allFileBackgroundTaskSnapshots().filterNot { it.profileId == snapshot.profileId } + snapshot,
        )
    }

    @Synchronized
    fun upsertPhotoBackupSource(source: PersistedPhotoBackupSource) {
        saveBackupSources(allBackupSources().filterNot { it.profileId == source.profileId } + source)
    }

    @Synchronized
    fun removePhotoBackupSource(profileId: String) {
        saveBackupSources(allBackupSources().filterNot { it.profileId == profileId })
    }

    @Synchronized
    fun removeTerminal(profileId: String) {
        save(
            all().filterNot {
                it.profileId == profileId && it.state in TERMINAL_STATES
            },
        )
        saveUploads(
            allUploads().filterNot {
                it.profileId == profileId && it.canRemoveFinishedUpload()
            },
        )
        saveServers(
            allServers().filterNot {
                it.profileId == profileId && it.canRemoveFinishedServer()
            },
        )
    }

    @Synchronized
    fun remove(id: String) {
        save(all().filterNot { it.id == id })
    }

    @Synchronized
    fun removeProfile(profileId: String) {
        save(all().filterNot { it.profileId == profileId })
        saveUploads(allUploads().filterNot { it.profileId == profileId })
        saveServers(allServers().filterNot { it.profileId == profileId })
        saveBackupSources(allBackupSources().filterNot { it.profileId == profileId })
        saveFileBackgroundTaskSnapshots(
            allFileBackgroundTaskSnapshots().filterNot { it.profileId == profileId },
        )
    }

    private fun all(): List<PersistedDownload> {
        val value = preferences.getString(KEY_DOWNLOADS, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(PersistedDownload.serializer()), value)
        }.getOrDefault(emptyList())
    }

    private fun save(downloads: List<PersistedDownload>) {
        preferences.edit()
            .putString(KEY_DOWNLOADS, json.encodeToString(ListSerializer(PersistedDownload.serializer()), downloads))
            .apply()
    }

    private fun allUploads(): List<PersistedUpload> {
        val value = preferences.getString(KEY_UPLOADS, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(PersistedUpload.serializer()), value)
        }.getOrDefault(emptyList())
    }

    private fun saveUploads(uploads: List<PersistedUpload>) {
        check(
            preferences.edit()
            .putString(KEY_UPLOADS, json.encodeToString(ListSerializer(PersistedUpload.serializer()), uploads))
            .commit(),
        ) { "transfer.upload_state_not_persisted" }
    }

    private fun allBackupSources(): List<PersistedPhotoBackupSource> {
        val value = preferences.getString(KEY_BACKUP_SOURCES, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(PersistedPhotoBackupSource.serializer()), value)
        }.getOrDefault(emptyList())
    }

    private fun allServers(): List<PersistedServerTransfer> {
        val value = preferences.getString(KEY_SERVERS, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(ListSerializer(PersistedServerTransfer.serializer()), value)
        }.getOrDefault(emptyList())
    }

    private fun saveServers(servers: List<PersistedServerTransfer>) {
        check(
            preferences.edit()
                .putString(
                    KEY_SERVERS,
                    json.encodeToString(ListSerializer(PersistedServerTransfer.serializer()), servers),
                )
                .commit(),
        ) { "transfer.server_state_not_persisted" }
    }

    private fun allFileBackgroundTaskSnapshots(): List<PersistedFileBackgroundTaskSnapshot> {
        val value = preferences.getString(KEY_FILE_BACKGROUND_TASKS, null) ?: return emptyList()
        return runCatching {
            json.decodeFromString(
                ListSerializer(PersistedFileBackgroundTaskSnapshot.serializer()),
                value,
            )
        }.getOrDefault(emptyList())
    }

    private fun saveFileBackgroundTaskSnapshots(snapshots: List<PersistedFileBackgroundTaskSnapshot>) {
        check(
            preferences.edit()
                .putString(
                    KEY_FILE_BACKGROUND_TASKS,
                    json.encodeToString(
                        ListSerializer(PersistedFileBackgroundTaskSnapshot.serializer()),
                        snapshots,
                    ),
                )
                .commit(),
        ) { "transfer.file_background_tasks_not_persisted" }
    }

    private fun saveBackupSources(sources: List<PersistedPhotoBackupSource>) {
        preferences.edit()
            .putString(
                KEY_BACKUP_SOURCES,
                json.encodeToString(ListSerializer(PersistedPhotoBackupSource.serializer()), sources),
            )
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "lanstash_transfer_tasks"
        const val KEY_DOWNLOADS = "downloads"
        const val KEY_UPLOADS = "uploads"
        const val KEY_SERVERS = "servers"
        const val KEY_BACKUP_SOURCES = "photo_backup_sources"
        const val KEY_FILE_BACKGROUND_TASKS = "file_background_tasks"
        val TERMINAL_STATES = setOf(
            TransferState.SUCCEEDED,
            TransferState.FAILED,
            TransferState.CANCELLED,
        )
    }
}

@Serializable
data class PersistedDownload(
    val id: String,
    val profileId: String,
    val sourcePath: String,
    val title: String,
    val destinationUri: String,
    val isDirectory: Boolean,
    val expectedBytes: Long? = null,
    val state: TransferState = TransferState.WAITING,
    val completedBytes: Long = 0,
    val totalBytes: Long? = expectedBytes,
    val errorKind: String? = null,
    val workId: String? = null,
    val backgroundCapable: Boolean = false,
    val startedAtEpochMillis: Long? = null,
)

@Serializable
data class PersistedUpload(
    val id: String,
    val profileId: String,
    val sourceUri: String,
    val title: String,
    val contentType: String? = null,
    val expectedBytes: Long,
    val destinationPath: String,
    val destinationRootPath: String = destinationPath,
    val state: TransferState = TransferState.WAITING,
    val completedBytes: Long = 0,
    val errorKind: String? = null,
    val workId: String? = null,
    val skippedExisting: Boolean = false,
    val ownsPersistedReadGrant: Boolean = true,
    val sourceTreeUri: String? = null,
    val backupMode: Boolean = true,
    val overwrite: Boolean = false,
    val requiresRefresh: Boolean = false,
    val mirrorDirectories: Boolean = false,
    val startedAtEpochMillis: Long? = null,
    val directoryMutationResult: PersistedMutationResult? = null,
    val uploadMutationResult: PersistedMutationResult? = null,
)

/** NAS 写任务的请求边界；恢复后只有 `PREPARING` 能确认尚未提交。 */
@Serializable
enum class PersistedServerSubmissionPhase {
    PREPARING,
    SUBMITTING,
    SUBMITTED,
    TERMINAL,
}

@Serializable
enum class PersistedServerOperation {
    COMPRESS,
    EXTRACT,
}

/** 恢复目标核对所需的文件基线；内容只保存在现有加密传输存储中。 */
@Serializable
data class PersistedServerFileBaseline(
    val path: String,
    val name: String,
    val isDirectory: Boolean,
    val size: Long = 0,
    val modifiedAtEpochSeconds: Long? = null,
    val owner: String? = null,
    val canRead: Boolean = true,
    val canWrite: Boolean = false,
    val canDelete: Boolean = false,
    val mountPointType: String? = null,
)

@Serializable
data class PersistedServerExpectedOutput(
    val path: String,
    val isDirectory: Boolean,
    val requiresNonEmptyFile: Boolean = false,
)

/**
 * App 发起、由 NAS 执行的任务状态。opaque task ID 只用于恢复只读轮询，不包含会话或地址。
 */
@Serializable
data class PersistedServerTransfer(
    val id: String,
    val profileId: String,
    val title: String,
    val operation: PersistedServerOperation,
    val state: TransferState = TransferState.WAITING,
    val submissionPhase: PersistedServerSubmissionPhase = PersistedServerSubmissionPhase.PREPARING,
    val executionGeneration: Long = 0,
    val readOnlyObservation: Boolean = false,
    val nasTaskId: String? = null,
    val completedUnits: Long = 0,
    val totalUnits: Long? = null,
    val startedAtEpochMillis: Long? = null,
    val requiresRefresh: Boolean = false,
    val errorKind: String? = null,
    val sourceModule: String = Module.FILES.name,
    val sourceBaselines: List<PersistedServerFileBaseline> = emptyList(),
    val destinationFolderBaseline: PersistedServerFileBaseline? = null,
    val expectedOutputs: List<PersistedServerExpectedOutput> = emptyList(),
    val mutationResult: PersistedMutationResult? = null,
    val refreshCompleted: Boolean = false,
    val verification: String? = null,
    val refreshFailureKind: String? = null,
)

/** 官方 BackgroundTask 的脱敏快照；不保存路径、参数、消息或响应正文。 */
@Serializable
data class PersistedFileBackgroundTaskSnapshot(
    val profileId: String,
    val observedAtEpochSeconds: Long,
    val tasks: List<PersistedFileBackgroundTaskSummary> = emptyList(),
)

@Serializable
data class PersistedFileBackgroundTaskSummary(
    val id: String,
    val kind: PersistedFileBackgroundTaskKind,
    val state: PersistedFileBackgroundTaskState,
    val progress: Double? = null,
    val createdAtEpochSeconds: Long? = null,
    val processedItemCount: Int? = null,
    val totalItemCount: Int? = null,
    val processedBytes: Long? = null,
    val totalBytes: Long? = null,
)

@Serializable
enum class PersistedFileBackgroundTaskKind {
    COPY_OR_MOVE,
    DELETE,
    COMPRESS,
    EXTRACT,
}

@Serializable
enum class PersistedFileBackgroundTaskState {
    ACTIVE,
    FINISHED,
}

/** 仅保留恢复与结果展示所需的稳定语义，不保存响应、路径、凭据或用户数据。 */
@Serializable
data class PersistedMutationResult(
    val status: MutationResultStatus = MutationResultStatus.CONFIRMED_FAILURE,
    val submitted: Boolean = false,
    val requiresRefresh: Boolean = false,
    val counts: MutationResultCounts = MutationResultCounts(0, 0, 0),
    val errorCategory: MutationErrorCategory? = null,
    val diagnosticTag: String? = null,
    val writeSubmitted: Boolean = false,
)

internal fun MutationResult.toPersistedMutationResult(
    writeSubmitted: Boolean = submitted,
) = PersistedMutationResult(
    status = status,
    submitted = submitted,
    requiresRefresh = requiresRefresh,
    counts = counts,
    errorCategory = errorCategory,
    diagnosticTag = diagnosticTag,
    writeSubmitted = writeSubmitted,
)

internal fun PersistedMutationResult.toMutationResult(operation: String) = MutationResult(
    schemaVersion = 1,
    status = status,
    operation = operation,
    submitted = submitted,
    requiresRefresh = requiresRefresh,
    counts = counts,
    errorCategory = errorCategory,
    diagnosticTag = diagnosticTag,
)

internal fun FileItem.toPersistedServerFileBaseline() = PersistedServerFileBaseline(
    path = path,
    name = name,
    isDirectory = isDirectory,
    size = size,
    modifiedAtEpochSeconds = modifiedAtEpochSeconds,
    owner = owner,
    canRead = canRead,
    canWrite = canWrite,
    canDelete = canDelete,
    mountPointType = mountPointType,
)

internal fun PersistedServerFileBaseline.toFileItem() = FileItem(
    path = path,
    name = name,
    isDirectory = isDirectory,
    size = size,
    modifiedAtEpochSeconds = modifiedAtEpochSeconds,
    owner = owner,
    canRead = canRead,
    canWrite = canWrite,
    canDelete = canDelete,
    mountPointType = mountPointType,
)

internal fun FileServerMutationExpectedOutput.toPersistedServerExpectedOutput() =
    PersistedServerExpectedOutput(path, isDirectory, requiresNonEmptyFile)

internal fun PersistedServerExpectedOutput.toFileServerMutationExpectedOutput() =
    FileServerMutationExpectedOutput(path, isDirectory, requiresNonEmptyFile)

internal fun FileServerMutationOperation.toPersistedServerOperation() = when (this) {
    FileServerMutationOperation.COMPRESS -> PersistedServerOperation.COMPRESS
    FileServerMutationOperation.EXTRACT -> PersistedServerOperation.EXTRACT
}

internal fun PersistedServerOperation.toFileServerMutationOperation() = when (this) {
    PersistedServerOperation.COMPRESS -> FileServerMutationOperation.COMPRESS
    PersistedServerOperation.EXTRACT -> FileServerMutationOperation.EXTRACT
}

internal fun FileServerMutationTarget.toPersistedServerTransfer(
    id: String,
    title: String,
    state: TransferState = TransferState.WAITING,
    submissionPhase: PersistedServerSubmissionPhase = PersistedServerSubmissionPhase.PREPARING,
    startedAtEpochMillis: Long? = null,
) = PersistedServerTransfer(
    id = id,
    profileId = profileId,
    title = title,
    operation = operation.toPersistedServerOperation(),
    state = state,
    submissionPhase = submissionPhase,
    startedAtEpochMillis = startedAtEpochMillis,
    sourceModule = module.name,
    sourceBaselines = sourceBaselines.map(FileItem::toPersistedServerFileBaseline),
    destinationFolderBaseline = destinationFolderBaseline.toPersistedServerFileBaseline(),
    expectedOutputs = expectedOutputs.map(
        FileServerMutationExpectedOutput::toPersistedServerExpectedOutput,
    ),
)

internal fun PersistedServerTransfer.toFileServerMutationTarget(): FileServerMutationTarget? {
    val destination = destinationFolderBaseline ?: return null
    val module = runCatching { Module.valueOf(sourceModule) }.getOrNull() ?: return null
    return FileServerMutationTarget(
        profileId = profileId,
        module = module,
        operation = operation.toFileServerMutationOperation(),
        sourceBaselines = sourceBaselines.map(PersistedServerFileBaseline::toFileItem),
        destinationFolderBaseline = destination.toFileItem(),
        expectedOutputs = expectedOutputs.map(
            PersistedServerExpectedOutput::toFileServerMutationExpectedOutput,
        ),
    )
}

internal fun PersistedServerTransfer.toFileServerMutationVerification(): FileServerMutationVerification? =
    verification?.let { value ->
        runCatching { FileServerMutationVerification.valueOf(value) }.getOrNull()
    }

internal fun FileBackgroundTaskPage.toPersistedFileBackgroundTaskSnapshot(
    profileId: String,
    observedAtEpochSeconds: Long,
) = PersistedFileBackgroundTaskSnapshot(
    profileId = profileId,
    observedAtEpochSeconds = observedAtEpochSeconds,
    tasks = tasks.map(FileBackgroundTaskSummary::toPersistedFileBackgroundTaskSummary),
)

internal fun FileBackgroundTaskSummary.toPersistedFileBackgroundTaskSummary() =
    PersistedFileBackgroundTaskSummary(
        id = id,
        kind = kind.toPersistedFileBackgroundTaskKind(),
        state = state.toPersistedFileBackgroundTaskState(),
        progress = progress,
        createdAtEpochSeconds = createdAtEpochSeconds,
        processedItemCount = processedItemCount,
        totalItemCount = totalItemCount,
        processedBytes = processedBytes,
        totalBytes = totalBytes,
    )

internal fun PersistedFileBackgroundTaskSnapshot.toFileBackgroundTaskPage() = FileBackgroundTaskPage(
    tasks = tasks.map { task ->
        FileBackgroundTaskSummary(
            id = task.id,
            kind = task.kind.toFileBackgroundTaskKind(),
            state = task.state.toFileBackgroundTaskState(),
            progress = task.progress,
            createdAtEpochSeconds = task.createdAtEpochSeconds,
            processedItemCount = task.processedItemCount,
            totalItemCount = task.totalItemCount,
            processedBytes = task.processedBytes,
            totalBytes = task.totalBytes,
        )
    },
    offset = 0,
    nextOffset = tasks.size,
    total = tasks.size,
    hasMore = false,
)

internal fun FileBackgroundTaskKind.toPersistedFileBackgroundTaskKind() = when (this) {
    FileBackgroundTaskKind.COPY_OR_MOVE -> PersistedFileBackgroundTaskKind.COPY_OR_MOVE
    FileBackgroundTaskKind.DELETE -> PersistedFileBackgroundTaskKind.DELETE
    FileBackgroundTaskKind.COMPRESS -> PersistedFileBackgroundTaskKind.COMPRESS
    FileBackgroundTaskKind.EXTRACT -> PersistedFileBackgroundTaskKind.EXTRACT
}

internal fun PersistedFileBackgroundTaskKind.toFileBackgroundTaskKind() = when (this) {
    PersistedFileBackgroundTaskKind.COPY_OR_MOVE -> FileBackgroundTaskKind.COPY_OR_MOVE
    PersistedFileBackgroundTaskKind.DELETE -> FileBackgroundTaskKind.DELETE
    PersistedFileBackgroundTaskKind.COMPRESS -> FileBackgroundTaskKind.COMPRESS
    PersistedFileBackgroundTaskKind.EXTRACT -> FileBackgroundTaskKind.EXTRACT
}

internal fun FileBackgroundTaskState.toPersistedFileBackgroundTaskState() = when (this) {
    FileBackgroundTaskState.ACTIVE -> PersistedFileBackgroundTaskState.ACTIVE
    FileBackgroundTaskState.FINISHED -> PersistedFileBackgroundTaskState.FINISHED
}

internal fun PersistedFileBackgroundTaskState.toFileBackgroundTaskState() = when (this) {
    PersistedFileBackgroundTaskState.ACTIVE -> FileBackgroundTaskState.ACTIVE
    PersistedFileBackgroundTaskState.FINISHED -> FileBackgroundTaskState.FINISHED
}

@Serializable
data class PersistedPhotoBackupSource(
    val profileId: String,
    val treeUri: String,
    val destinationPath: String,
    val workId: String? = null,
    val enabled: Boolean = true,
)

internal fun TransferState.hasIncompleteDownloadDestination(): Boolean = this !in setOf(
    TransferState.SUCCEEDED,
    TransferState.FAILED,
    TransferState.CANCELLED,
)

internal fun PersistedUpload.canRemoveFinishedUpload(): Boolean =
    state in setOf(TransferState.SUCCEEDED, TransferState.FAILED, TransferState.CANCELLED) &&
        !requiresRefresh

internal fun PersistedServerTransfer.canRemoveFinishedServer(): Boolean =
    state in setOf(TransferState.SUCCEEDED, TransferState.FAILED, TransferState.CANCELLED) &&
        submissionPhase == PersistedServerSubmissionPhase.TERMINAL &&
        !requiresRefresh && (mutationResult?.requiresRefresh != true || refreshCompleted)
