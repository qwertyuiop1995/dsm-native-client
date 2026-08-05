package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import java.io.InputStream
import java.io.OutputStream
import java.io.PipedInputStream
import java.io.PipedOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.supervisorScope

/** 跨 NAS 文件复制使用固定容量内存管道，不生成完整文件临时副本。 */
internal class CrossNasTransferCoordinator(
    private val pipeCapacityBytes: Int = DEFAULT_PIPE_CAPACITY_BYTES,
) {
    init {
        require(pipeCapacityBytes > 0)
    }

    suspend fun transfer(
        source: CrossNasTransferEndpoint,
        target: CrossNasTransferEndpoint,
        items: List<FileItem>,
        destination: FileItem,
        moveSource: Boolean,
        overwrite: Boolean = false,
        onProgress: (Long, Long) -> Unit = { _, _ -> },
    ): MutationResult {
        val submissionStarted = AtomicBoolean(false)
        val completedItems = AtomicInteger(0)
        return try {
            transferInternal(
                source,
                target,
                items,
                destination,
                moveSource,
                overwrite,
                submissionStarted,
                completedItems,
                onProgress,
            )
        } catch (_: CancellationException) {
            if (submissionStarted.get()) {
                result(
                    status = MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                    submitted = true,
                    succeeded = completedItems.get(),
                    unknown = (items.size - completedItems.get()).coerceAtLeast(1),
                    requiresRefresh = true,
                    tag = "file-station.cross-nas.cancelled-after-submission",
                )
            } else {
                result(
                    status = MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
                    submitted = false,
                    tag = "file-station.cross-nas.cancelled-before-submission",
                )
            }
        }
    }

    private suspend fun transferInternal(
        source: CrossNasTransferEndpoint,
        target: CrossNasTransferEndpoint,
        items: List<FileItem>,
        destination: FileItem,
        moveSource: Boolean,
        overwrite: Boolean,
        submissionStarted: AtomicBoolean,
        completedItems: AtomicInteger,
        onProgress: (Long, Long) -> Unit,
    ): MutationResult {
        if (items.isEmpty() || !destination.isDirectory || !destination.canWrite) {
            return result(
                status = MutationResultStatus.CONFIRMED_FAILURE,
                submitted = false,
                failed = items.size.coerceAtLeast(1),
                errorCategory = MutationErrorCategory.VALIDATION,
                tag = "file-station.cross-nas.invalid-input",
            )
        }
        if (!source.supportsSource(moveSource) ||
            !target.supportsTarget(items.any(FileItem::isDirectory))
        ) {
            return result(
                status = MutationResultStatus.UNSUPPORTED,
                submitted = false,
                failed = items.size,
                errorCategory = MutationErrorCategory.UNSUPPORTED,
                tag = "file-station.cross-nas.unsupported",
            )
        }
        if (moveSource && items.any { !it.canDelete }) {
            return result(
                status = MutationResultStatus.PERMISSION_DENIED,
                submitted = false,
                failed = items.size,
                errorCategory = MutationErrorCategory.PERMISSION,
                tag = "file-station.cross-nas.source-delete-denied",
            )
        }
        if (moveSource && items.any(FileItem::isDirectory)) {
            return result(
                status = MutationResultStatus.UNSUPPORTED,
                submitted = false,
                failed = items.size,
                errorCategory = MutationErrorCategory.UNSUPPORTED,
                tag = "file-station.cross-nas.directory-move-unsupported",
            )
        }
        if (items.any { !it.canRead || !it.isDirectory && it.size < 0 }) {
            return result(
                status = MutationResultStatus.CONFIRMED_FAILURE,
                submitted = false,
                failed = items.size,
                errorCategory = MutationErrorCategory.PERMISSION,
                tag = "file-station.cross-nas.source-unreadable",
            )
        }
        if (overwrite && items.any(FileItem::isDirectory)) {
            return result(
                status = MutationResultStatus.UNSUPPORTED,
                submitted = false,
                failed = items.size,
                errorCategory = MutationErrorCategory.UNSUPPORTED,
                tag = "file-station.cross-nas.folder-overwrite-unsupported",
            )
        }

        val sourceSnapshot = snapshotSourceTree(source, items)
        if (!sourceTreeStableBeforeWrite(source, items, sourceSnapshot)) {
            return result(
                status = MutationResultStatus.CONFIRMED_FAILURE,
                submitted = false,
                failed = items.size,
                errorCategory = MutationErrorCategory.CONFLICT,
                tag = "file-station.cross-nas.source-tree-changed",
            )
        }

        val existing = target.existingChildNames(destination.path, items.map(FileItem::name))
        if (!overwrite && existing.isNotEmpty()) {
            return result(
                status = MutationResultStatus.CONFIRMED_FAILURE,
                submitted = false,
                failed = existing.size,
                errorCategory = MutationErrorCategory.CONFLICT,
                tag = "file-station.cross-nas.target-conflict",
            )
        }

        val knownBytes = items.sumOf { if (it.isDirectory) 0L else it.size }.coerceAtLeast(0)
        var completedBytes = 0L
        var succeeded = 0
        for (item in items) {
            val itemResult = transferItem(
                source = source,
                target = target,
                item = item,
                destination = destination,
                overwrite = overwrite,
                sourceSnapshot = sourceSnapshot,
                submissionStarted = submissionStarted,
            ) { completed ->
                onProgress(completedBytes + completed, knownBytes)
            }
            if (itemResult.status != MutationResultStatus.CONFIRMED_SUCCESS) {
                return if (succeeded == 0) itemResult else result(
                    status = MutationResultStatus.PARTIAL_SUCCESS,
                    submitted = true,
                    succeeded = succeeded,
                    failed = itemResult.counts.failed,
                    unknown = itemResult.counts.unknown.coerceAtLeast(
                        if (itemResult.counts.failed == 0) 1 else 0,
                    ),
                    requiresRefresh = itemResult.requiresRefresh,
                    errorCategory = itemResult.errorCategory,
                    tag = "file-station.cross-nas.partial",
                )
            }
            completedBytes += if (item.isDirectory) 0L else item.size
            succeeded += 1
            completedItems.incrementAndGet()
        }

        if (moveSource) {
            if (!sourceTreeMatches(source, items, sourceSnapshot)) {
                return result(
                    status = MutationResultStatus.PARTIAL_SUCCESS,
                    submitted = true,
                    succeeded = succeeded,
                    unknown = items.size,
                    requiresRefresh = true,
                    errorCategory = MutationErrorCategory.CONFLICT,
                    tag = "file-station.cross-nas.move-source-changed",
                )
            }
            val deletion = source.deleteResult(items)
            if (deletion.status != MutationResultStatus.CONFIRMED_SUCCESS) {
                return result(
                    status = MutationResultStatus.PARTIAL_SUCCESS,
                    submitted = true,
                    succeeded = succeeded,
                    failed = deletion.counts.failed,
                    unknown = deletion.counts.unknown.coerceAtLeast(
                        if (deletion.counts.failed == 0) items.size else 0,
                    ),
                    requiresRefresh = deletion.requiresRefresh,
                    errorCategory = deletion.errorCategory,
                    tag = "file-station.cross-nas.move-source-retained",
                )
            }
        }
        return result(
            status = MutationResultStatus.CONFIRMED_SUCCESS,
            submitted = true,
            succeeded = items.size,
            tag = if (moveSource) {
                "file-station.cross-nas.move-confirmed"
            } else {
                "file-station.cross-nas.copy-confirmed"
            },
        )
    }

    private suspend fun transferItem(
        source: CrossNasTransferEndpoint,
        target: CrossNasTransferEndpoint,
        item: FileItem,
        destination: FileItem,
        overwrite: Boolean,
        sourceSnapshot: Map<String, List<FileItem>>,
        submissionStarted: AtomicBoolean,
        onProgress: (Long) -> Unit,
    ): MutationResult {
        if (!item.isDirectory) {
            if (source.findItem(item.path) != item) {
                return result(
                    status = MutationResultStatus.CONFIRMED_FAILURE,
                    submitted = false,
                    failed = 1,
                    errorCategory = MutationErrorCategory.CONFLICT,
                    tag = "file-station.cross-nas.source-baseline-changed",
                )
            }
            return transferFile(
                source,
                target,
                item,
                destination.path,
                overwrite,
                submissionStarted,
                onProgress,
            )
        }
        submissionStarted.set(true)
        val create = target.createFolderResult(destination, item.name)
        if (create.status != MutationResultStatus.CONFIRMED_SUCCESS) return create
        val createdPath = join(destination.path, item.name)
        val created = target.findItem(createdPath) ?: return result(
            status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            submitted = true,
            unknown = 1,
            requiresRefresh = true,
            tag = "file-station.cross-nas.folder-unverified",
        )
        for (child in sourceSnapshot[item.path].orEmpty()) {
            val childResult = transferItem(
                source,
                target,
                child,
                created,
                overwrite,
                sourceSnapshot,
                submissionStarted,
                onProgress,
            )
            if (childResult.status != MutationResultStatus.CONFIRMED_SUCCESS) {
                return result(
                    status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                    submitted = true,
                    unknown = 1,
                    requiresRefresh = true,
                    errorCategory = childResult.errorCategory,
                    tag = "file-station.cross-nas.folder-partial",
                )
            }
        }
        return result(
            status = MutationResultStatus.CONFIRMED_SUCCESS,
            submitted = true,
            succeeded = 1,
            tag = "file-station.cross-nas.folder-confirmed",
        )
    }

    private suspend fun transferFile(
        source: CrossNasTransferEndpoint,
        target: CrossNasTransferEndpoint,
        item: FileItem,
        destinationPath: String,
        overwrite: Boolean,
        submissionStarted: AtomicBoolean,
        onProgress: (Long) -> Unit,
    ): MutationResult = supervisorScope {
        val input = PipedInputStream(pipeCapacityBytes)
        val output = PipedOutputStream(input)
        val opened = AtomicBoolean(false)
        val uploadSource = UploadSource(
            displayName = item.name,
            contentType = item.mimeType,
            contentLength = item.size,
            openInputStream = {
                check(opened.compareAndSet(false, true)) { "cross-nas stream already opened" }
                submissionStarted.set(true)
                input
            },
        )
        val upload = async(Dispatchers.IO) {
            target.uploadResult(uploadSource, destinationPath, overwrite) { completed, _ ->
                onProgress(completed)
            }
        }
        val download = async(Dispatchers.IO) {
            try {
                output.use { source.download(item, it) }
            } catch (failure: Throwable) {
                currentCoroutineContext().ensureActive()
                throw failure
            }
        }
        try {
            val uploadResult = upload.await()
            if (uploadResult.status != MutationResultStatus.CONFIRMED_SUCCESS) {
                download.cancel()
                input.close()
                output.close()
                return@supervisorScope uploadResult
            }
            download.await()
            uploadResult
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Throwable) {
            currentCoroutineContext().ensureActive()
            throw failure
        } finally {
            upload.cancel()
            download.cancel()
            input.close()
            output.close()
        }
    }

    private fun result(
        status: MutationResultStatus,
        submitted: Boolean,
        succeeded: Int = 0,
        failed: Int = 0,
        unknown: Int = 0,
        requiresRefresh: Boolean = false,
        errorCategory: MutationErrorCategory? = null,
        tag: String,
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "crossNasTransfer",
        submitted = submitted,
        requiresRefresh = requiresRefresh,
        counts = MutationResultCounts(succeeded, failed, unknown),
        errorCategory = errorCategory,
        localizationKey = "mutation.cross_nas.${status.name.lowercase()}",
        diagnosticTag = tag,
    )

    private suspend fun snapshotSourceTree(
        source: CrossNasTransferEndpoint,
        roots: List<FileItem>,
    ): Map<String, List<FileItem>> {
        val snapshot = linkedMapOf<String, List<FileItem>>()
        suspend fun visit(item: FileItem) {
            if (!item.isDirectory) return
            val children = mutableListOf<FileItem>()
            var offset = 0
            do {
                val page = source.listDirectory(item.path, offset, PAGE_SIZE)
                children += page.items
                if (page.items.isEmpty()) break
                offset += page.items.size
            } while (offset < page.total)
            snapshot[item.path] = children
            children.forEach { visit(it) }
        }
        roots.forEach { visit(it) }
        return snapshot
    }

    private suspend fun sourceTreeMatches(
        source: CrossNasTransferEndpoint,
        roots: List<FileItem>,
        baseline: Map<String, List<FileItem>>,
    ): Boolean {
        for (root in roots) {
            if (source.findItem(root.path) != root) return false
        }
        return snapshotSourceTree(source, roots) == baseline
    }

    private suspend fun sourceTreeStableBeforeWrite(
        source: CrossNasTransferEndpoint,
        roots: List<FileItem>,
        baseline: Map<String, List<FileItem>>,
    ): Boolean {
        for (item in roots) {
            if (source.findItem(item.path) != item) return false
        }
        return snapshotSourceTree(source, roots) == baseline
    }

    private fun join(parent: String, name: String) =
        if (parent == "/") "/$name" else "${parent.trimEnd('/')}/$name"

    private companion object {
        const val DEFAULT_PIPE_CAPACITY_BYTES = 12 * 1024 * 1024
        const val PAGE_SIZE = 500
    }
}

internal interface CrossNasTransferEndpoint {
    fun supportsSource(moveSource: Boolean): Boolean
    fun supportsTarget(includesDirectory: Boolean): Boolean
    suspend fun listDirectory(path: String, offset: Int, limit: Int): FilePage
    suspend fun findItem(path: String): FileItem?
    suspend fun existingChildNames(parent: String, names: Collection<String>): Set<String>
    suspend fun createFolderResult(parent: FileItem, name: String): MutationResult
    suspend fun uploadResult(
        source: UploadSource,
        destinationPath: String,
        overwrite: Boolean,
        onProgress: (Long, Long) -> Unit,
    ): MutationResult
    suspend fun download(item: FileItem, output: OutputStream): Long
    suspend fun deleteResult(items: List<FileItem>): MutationResult
}

internal class RepositoryCrossNasTransferEndpoint(
    private val repository: DsmRepository,
) : CrossNasTransferEndpoint {
    override fun supportsSource(moveSource: Boolean) = repository.supportsCrossNasSource(moveSource)

    override fun supportsTarget(includesDirectory: Boolean) =
        repository.supportsCrossNasTarget(includesDirectory)

    override suspend fun listDirectory(path: String, offset: Int, limit: Int) =
        repository.listDirectory(path, offset, limit)

    override suspend fun findItem(path: String): FileItem? = repository.fileInfo(path)

    override suspend fun existingChildNames(parent: String, names: Collection<String>) =
        repository.existingChildNames(parent, names)

    override suspend fun createFolderResult(parent: FileItem, name: String) =
        repository.createFolderResult(parent, name)

    override suspend fun uploadResult(
        source: UploadSource,
        destinationPath: String,
        overwrite: Boolean,
        onProgress: (Long, Long) -> Unit,
    ) = repository.uploadResult(source, destinationPath, overwrite, onProgress)

    override suspend fun download(item: FileItem, output: OutputStream) =
        repository.download(item, output)

    override suspend fun deleteResult(items: List<FileItem>) = repository.deleteResult(items)

}
