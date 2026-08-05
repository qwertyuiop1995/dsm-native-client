package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CrossNasTransferCoordinatorTest {
    @Test
    fun `large file crosses a small bounded pipe without a disk copy`() = runBlocking {
        val bytes = ByteArray(512 * 1024) { (it % 251).toByte() }
        val source = FakeEndpoint(downloadBytes = bytes)
        val target = FakeEndpoint(uploadReadDelayMillis = 1)

        val result = withTimeout(10_000) {
            CrossNasTransferCoordinator(pipeCapacityBytes = 1024).transfer(
                source = source,
                target = target,
                items = listOf(file("/source/large.bin", bytes.size.toLong())),
                destination = folder("/target"),
                moveSource = false,
            )
        }

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertArrayEquals(bytes, target.uploadedBytes)
        assertFalse(source.deleteCalled)
        assertEquals(1, target.openCount.get())
    }

    @Test
    fun `move deletes the source only after every target upload is confirmed`() = runBlocking {
        val source = FakeEndpoint(downloadBytes = byteArrayOf(1, 2, 3))
        val target = FakeEndpoint()
        source.targetToObserve = target

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(file("/source/a.bin", 3)),
            destination = folder("/target"),
            moveSource = true,
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertTrue(source.deleteCalled)
        assertTrue(source.deleteObservedTargetUpload)
    }

    @Test
    fun `unverified target upload retains every source item`() = runBlocking {
        val source = FakeEndpoint(downloadBytes = byteArrayOf(1, 2, 3))
        val target = FakeEndpoint(uploadResult = mutation(
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            submitted = true,
            unknown = 1,
            requiresRefresh = true,
        ))
        source.targetToObserve = target

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(file("/source/a.bin", 3)),
            destination = folder("/target"),
            moveSource = true,
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertFalse(source.deleteCalled)
    }

    @Test
    fun `name conflict is rejected before source download starts`() = runBlocking {
        val source = FakeEndpoint(downloadBytes = byteArrayOf(1))
        val target = FakeEndpoint(existingNames = setOf("a.bin"))

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(file("/source/a.bin", 1)),
            destination = folder("/target"),
            moveSource = false,
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertEquals(0, source.downloadCount)
    }

    @Test
    fun `move without source delete permission performs no upload or delete`() = runBlocking {
        val source = FakeEndpoint(downloadBytes = byteArrayOf(1))
        val target = FakeEndpoint()

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(file("/source/a.bin", 1).copy(canDelete = false)),
            destination = folder("/target"),
            moveSource = true,
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertEquals(0, source.downloadCount)
        assertEquals(0, target.openCount.get())
        assertFalse(source.deleteCalled)
    }

    @Test
    fun `directory move is rejected before creating a target directory`() = runBlocking {
        val source = FakeEndpoint()
        val target = FakeEndpoint()

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(folder("/source/folder")),
            destination = folder("/target"),
            moveSource = true,
        )

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertEquals(0, target.createFolderCount)
        assertFalse(source.deleteCalled)
    }

    @Test
    fun `target preflight rejection wakes a blocked source writer`() = runBlocking {
        val source = FakeEndpoint(downloadBytes = ByteArray(1024 * 1024))
        val target = FakeEndpoint(
            uploadResult = mutation(
                MutationResultStatus.CONFIRMED_FAILURE,
                submitted = false,
                failed = 1,
            ),
            readUploadBody = false,
        )

        val result = withTimeout(2_000) {
            CrossNasTransferCoordinator(pipeCapacityBytes = 64).transfer(
                source = source,
                target = target,
                items = listOf(file("/source/a.bin", 1024L * 1024L)),
                destination = folder("/target"),
                moveSource = false,
            )
        }

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
    }

    @Test
    fun `directory copy uses the frozen recursive snapshot`() = runBlocking {
        val root = folder("/source/folder")
        val source = FakeEndpoint(
            downloadBytes = byteArrayOf(1, 2, 3),
            directoryItems = mapOf(root.path to listOf(file("${root.path}/a.bin", 3))),
        )
        val target = FakeEndpoint()

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(root),
            destination = folder("/target"),
            moveSource = false,
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertFalse(source.deleteCalled)
        assertArrayEquals(byteArrayOf(1, 2, 3), target.uploadedBytes)
    }

    @Test
    fun `cancellation closes both sides of the pipe`() {
        runBlocking {
            val source = FakeEndpoint(downloadBytes = ByteArray(1024 * 1024))
            val target = FakeEndpoint(cancelAfterOpen = true)
            val result = CrossNasTransferCoordinator(pipeCapacityBytes = 64).transfer(
                source = source,
                target = target,
                items = listOf(file("/source/a.bin", 1024L * 1024L)),
                destination = folder("/target"),
                moveSource = false,
            )
            assertEquals(
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                result.status,
            )
            assertTrue(result.requiresRefresh)
        }
    }

    @Test
    fun `directory child changed after snapshot is not downloaded or reported successful`() = runBlocking {
        val root = folder("/source/folder")
        val child = file("${root.path}/a.bin", 3)
        val source = FakeEndpoint(
            downloadBytes = byteArrayOf(1, 2, 3),
            directoryItems = mapOf(root.path to listOf(child)),
            findItems = mapOf(
                child.path to child.copy(modifiedAtEpochSeconds = 99),
            ),
        )
        val target = FakeEndpoint()

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(root),
            destination = folder("/target"),
            moveSource = false,
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(0, source.downloadCount)
        assertEquals(1, target.createFolderCount)
    }

    @Test
    fun `replaced root directory is rejected before a target folder is created`() = runBlocking {
        val root = folder("/source/folder")
        val source = FakeEndpoint(
            findItems = mapOf(root.path to root.copy(owner = "changed-owner")),
        )
        val target = FakeEndpoint()

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(root),
            destination = folder("/target"),
            moveSource = false,
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(0, target.createFolderCount)
    }

    @Test
    fun `directory listing drift between two snapshots is rejected before writing`() = runBlocking {
        val root = folder("/source/folder")
        val first = file("${root.path}/a.bin", 3)
        val changed = file("${root.path}/b.bin", 3)
        val source = FakeEndpoint(
            downloadBytes = byteArrayOf(1, 2, 3),
            directoryItems = mapOf(root.path to listOf(first)),
            changedDirectoryItems = mapOf(root.path to listOf(changed)),
        )
        val target = FakeEndpoint()

        val result = CrossNasTransferCoordinator(pipeCapacityBytes = 2).transfer(
            source = source,
            target = target,
            items = listOf(root),
            destination = folder("/target"),
            moveSource = false,
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(0, target.createFolderCount)
        assertEquals(0, source.downloadCount)
    }

    @Test
    fun `real job cancellation after upload opens remains observable as submitted`() = runBlocking {
        val opened = CompletableDeferred<Unit>()
        val observed = CompletableDeferred<MutationResult>()
        val source = FakeEndpoint(downloadBytes = ByteArray(1024 * 1024))
        val target = FakeEndpoint(uploadReadDelayMillis = 20, onStreamOpened = { opened.complete(Unit) })
        val coordinator = CrossNasTransferCoordinator(pipeCapacityBytes = 64)
        val job = launch {
            observed.complete(
                coordinator.transfer(
                    source = source,
                    target = target,
                    items = listOf(file("/source/a.bin", 1024L * 1024L)),
                    destination = folder("/target"),
                    moveSource = true,
                ),
            )
        }
        opened.await()
        job.cancel()
        withTimeout(2_000) { job.join() }

        val result = withTimeout(2_000) { observed.await() }
        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result.status)
        assertTrue(result.requiresRefresh)
        assertFalse(source.deleteCalled)
    }

    private class FakeEndpoint(
        private val downloadBytes: ByteArray = byteArrayOf(),
        private val existingNames: Set<String> = emptySet(),
        private val uploadResult: MutationResult = mutation(
            MutationResultStatus.CONFIRMED_SUCCESS,
            submitted = true,
            succeeded = 1,
        ),
        private val uploadReadDelayMillis: Long = 0,
        private val readUploadBody: Boolean = true,
        private val directoryItems: Map<String, List<FileItem>> = emptyMap(),
        private val changedDirectoryItems: Map<String, List<FileItem>> = emptyMap(),
        private val findItems: Map<String, FileItem> = emptyMap(),
        private val cancelAfterOpen: Boolean = false,
        private val onStreamOpened: (() -> Unit)? = null,
    ) : CrossNasTransferEndpoint {
        var uploadedBytes = byteArrayOf()
        var deleteCalled = false
        var deleteObservedTargetUpload = false
        var downloadCount = 0
        var targetToObserve: FakeEndpoint? = null
        val openCount = AtomicInteger()
        var createFolderCount = 0
        private val directoryListCounts = mutableMapOf<String, Int>()

        override fun supportsSource(moveSource: Boolean) = true

        override fun supportsTarget(includesDirectory: Boolean) = true

        override suspend fun listDirectory(path: String, offset: Int, limit: Int): FilePage {
            val requestCount = directoryListCounts.getOrDefault(path, 0)
            directoryListCounts[path] = requestCount + 1
            val all = if (requestCount > 0 && path in changedDirectoryItems) {
                changedDirectoryItems.getValue(path)
            } else {
                directoryItems[path].orEmpty()
            }
            val page = all.drop(offset).take(limit)
            return FilePage(page, all.size, offset)
        }

        override suspend fun findItem(path: String) = findItems[path] ?: if (path.endsWith(".bin")) {
            file(path, downloadBytes.size.toLong())
        } else {
            folder(path)
        }

        override suspend fun existingChildNames(parent: String, names: Collection<String>) =
            existingNames.intersect(names.toSet())

        override suspend fun createFolderResult(parent: FileItem, name: String): MutationResult {
            createFolderCount += 1
            return mutation(
                MutationResultStatus.CONFIRMED_SUCCESS,
                submitted = true,
                succeeded = 1,
            )
        }

        override suspend fun uploadResult(
            source: UploadSource,
            destinationPath: String,
            overwrite: Boolean,
            onProgress: (Long, Long) -> Unit,
        ): MutationResult {
            if (!readUploadBody) return uploadResult
            openCount.incrementAndGet()
            val input = source.openInputStream()
            onStreamOpened?.invoke()
            if (cancelAfterOpen) {
                input.close()
                throw CancellationException("synthetic upload cancellation")
            }
            val output = ArrayList<Byte>()
            input.use {
                val buffer = ByteArray(257)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    repeat(count) { output += buffer[it] }
                    onProgress(output.size.toLong(), source.contentLength)
                    if (uploadReadDelayMillis > 0) delay(uploadReadDelayMillis)
                }
            }
            uploadedBytes = output.toByteArray()
            return uploadResult
        }

        override suspend fun download(item: FileItem, output: OutputStream): Long {
            downloadCount += 1
            output.write(downloadBytes)
            return downloadBytes.size.toLong()
        }

        override suspend fun deleteResult(items: List<FileItem>): MutationResult {
            deleteCalled = true
            deleteObservedTargetUpload = targetToObserve?.uploadedBytes?.isNotEmpty()
                ?: uploadedBytes.isNotEmpty()
            return mutation(
                MutationResultStatus.CONFIRMED_SUCCESS,
                submitted = true,
                succeeded = items.size,
            )
        }
    }

    private companion object {
        fun file(path: String, size: Long) = FileItem(
            path = path,
            name = path.substringAfterLast('/'),
            isDirectory = false,
            size = size,
            canRead = true,
            canDelete = true,
        )

        fun folder(path: String) = FileItem(
            path = path,
            name = path.substringAfterLast('/'),
            isDirectory = true,
            canRead = true,
            canWrite = true,
            canDelete = true,
        )

        fun mutation(
            status: MutationResultStatus,
            submitted: Boolean,
            succeeded: Int = 0,
            failed: Int = 0,
            unknown: Int = 0,
            requiresRefresh: Boolean = false,
        ) = MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "testMutation",
            submitted = submitted,
            requiresRefresh = requiresRefresh,
            counts = MutationResultCounts(succeeded, failed, unknown),
        )
    }
}
