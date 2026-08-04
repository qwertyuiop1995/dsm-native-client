package io.github.qwertyuiop1995.dsmnativeclient

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedUpload
import io.github.qwertyuiop1995.dsmnativeclient.data.TransferStore
import java.util.UUID

/** 扫描用户授权的目录；只登记媒体任务，不读取或记录媒体正文。 */
class PhotoBackupScanWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    private val transfers = TransferStore(appContext)

    override suspend fun doWork(): Result {
        val profileId = inputData.getString(KEY_PROFILE_ID) ?: return Result.failure()
        val source = transfers.photoBackupSource(profileId)?.takeIf { it.enabled }
            ?: return Result.success()
        val treeUri = Uri.parse(source.treeUri)
        val items = runCatching {
            scanDocumentTree(applicationContext, treeUri, MAX_DOCUMENTS_PER_SCAN) { mime ->
                mime.startsWith("image/") || mime.startsWith("video/")
            }.files
        }.getOrElse { return Result.failure() }
        val existing = transfers.uploads(profileId)
        val workManager = WorkManager.getInstance(applicationContext)
        items.forEach { item ->
            val destination = backupDestination(source.destinationPath, item.relativeFolder)
            val duplicate = existing.any {
                it.sourceUri == item.uri.toString() &&
                    it.destinationPath == destination &&
                    it.title == item.name &&
                    it.expectedBytes == item.size
            }
            if (duplicate) return@forEach
            val record = PersistedUpload(
                id = UUID.randomUUID().toString(),
                profileId = profileId,
                sourceUri = item.uri.toString(),
                title = item.name,
                contentType = item.mimeType,
                expectedBytes = item.size,
                destinationPath = destination,
                destinationRootPath = source.destinationPath,
                ownsPersistedReadGrant = false,
                sourceTreeUri = source.treeUri,
            )
            transfers.upsert(record)
            val request = OneTimeWorkRequestBuilder<PhotoBackupWorker>()
                .setInputData(workDataOf(PhotoBackupWorker.KEY_TASK_ID to record.id))
                .setConstraints(photoBackupConstraints())
                .addTag(PhotoBackupWorker.UNIQUE_WORK_PREFIX + record.id)
                .build()
            transfers.updateUpload(record.id) { it.copy(workId = request.id.toString()) }
            workManager.enqueueUniqueWork(
                PhotoBackupWorker.UNIQUE_WORK_PREFIX + record.id,
                ExistingWorkPolicy.KEEP,
                request,
            )
        }
        return Result.success()
    }

    companion object {
        const val KEY_PROFILE_ID = "profile_id"
        const val UNIQUE_WORK_PREFIX = "photo-backup-scan-"
        const val MAX_DOCUMENTS_PER_SCAN = 10_000
    }
}

internal fun isSafeBackupName(value: String): Boolean =
    value.isNotBlank() && '/' !in value && '\\' !in value && value !in setOf(".", "..")

internal fun backupDestination(root: String, relativeFolder: String): String =
    if (relativeFolder.isBlank()) root else root.trimEnd('/') + "/" + relativeFolder

internal data class BackupDocument(
    val uri: Uri,
    val name: String,
    val mimeType: String,
    val size: Long,
    val relativeFolder: String,
)

internal data class DocumentTreeScan(
    val files: List<BackupDocument>,
    val truncated: Boolean,
)

internal fun scanDocumentTree(
    context: Context,
    treeUri: Uri,
    maximumDocuments: Int,
    includeMimeType: (String) -> Boolean,
): DocumentTreeScan {
    require(maximumDocuments > 0)
    val rootId = DocumentsContract.getTreeDocumentId(treeUri)
    val pending = ArrayDeque<Pair<String, List<String>>>().apply { add(rootId to emptyList()) }
    val result = mutableListOf<BackupDocument>()
    var visited = 0
    while (pending.isNotEmpty() && visited < maximumDocuments) {
        val (parentId, relativeParts) = pending.removeFirst()
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        context.contentResolver.query(childrenUri, TREE_PROJECTION, null, null, null)?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            while (visited < maximumDocuments && cursor.moveToNext()) {
                visited++
                val id = cursor.getString(idIndex)
                val name = cursor.getString(nameIndex)?.trim().orEmpty()
                val mime = cursor.getString(mimeIndex).orEmpty()
                if (!isSafeBackupName(name)) continue
                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    pending.add(id to (relativeParts + name))
                } else if (includeMimeType(mime) && !cursor.isNull(sizeIndex) && cursor.getLong(sizeIndex) >= 0) {
                    result += BackupDocument(
                        uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
                        name = name,
                        mimeType = mime,
                        size = cursor.getLong(sizeIndex),
                        relativeFolder = relativeParts.joinToString("/"),
                    )
                }
            }
            if (cursor.moveToNext()) return DocumentTreeScan(result, truncated = true)
        }
    }
    return DocumentTreeScan(result, truncated = pending.isNotEmpty())
}

private val TREE_PROJECTION = arrayOf(
    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
    DocumentsContract.Document.COLUMN_MIME_TYPE,
    DocumentsContract.Document.COLUMN_SIZE,
)
