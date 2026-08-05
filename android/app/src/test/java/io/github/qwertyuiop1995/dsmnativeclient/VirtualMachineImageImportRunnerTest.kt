package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.data.DsmRepository
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedServerFileBaseline
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageImport
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageImportStage
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageType
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import java.io.IOException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlinx.coroutines.test.runTest

class VirtualMachineImageImportRunnerTest {
    @Test
    fun `完整阶段按序持久化并在任务清理后删除临时文件`() = runTest {
        val store = MemoryImportStore(record())
        val operations = FakeImportOperations().apply {
            files.add(null)
            files.add(file())
            files.add(file())
            files.add(null)
        }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.SUCCEEDED, result)
        assertEquals(PersistedVirtualMachineImageImportStage.SUCCEEDED, store.value.stage)
        assertFalse(store.value.ownsPersistedReadGrant)
        assertEquals(
            listOf("file", "upload", "file", "release", "create", "task", "image", "clear", "file", "delete", "file"),
            operations.calls,
        )
        assertEquals(
            listOf(
                PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING,
                PersistedVirtualMachineImageImportStage.UPLOADED,
                PersistedVirtualMachineImageImportStage.UPLOADED,
                PersistedVirtualMachineImageImportStage.CREATE_SUBMITTING,
                PersistedVirtualMachineImageImportStage.TASK_TRACKING,
                PersistedVirtualMachineImageImportStage.IMAGE_READBACK,
                PersistedVirtualMachineImageImportStage.TASK_CLEARING,
                PersistedVirtualMachineImageImportStage.TASK_CLEARING,
                PersistedVirtualMachineImageImportStage.TEMP_CLEANUP,
                PersistedVirtualMachineImageImportStage.SUCCEEDED,
            ),
            store.stages,
        )
    }

    @Test
    fun `创建提交中无任务标识绝不重放create`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.CREATE_SUBMITTING,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
            ),
        )
        val operations = FakeImportOperations()

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.NEEDS_REVIEW, result)
        assertEquals(PersistedVirtualMachineImageImportStage.NEEDS_REVIEW, store.value.stage)
        assertFalse("create" in operations.calls)
    }

    @Test
    fun `创建提交中已有任务标识只恢复任务读取`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.TASK_TRACKING,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
            ),
        )
        val operations = FakeImportOperations().apply { taskFinished = false }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals("${store.value} ${operations.calls}", VirtualMachineImageImportRunResult.RETRY, result)
        assertEquals(listOf("task"), operations.calls)
    }

    @Test
    fun `上传提交恢复先回读匹配文件且不重传`() = runTest {
        val store = MemoryImportStore(
            record().copy(stage = PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING),
        )
        val operations = FakeImportOperations().apply {
            files.add(file())
            taskFinished = false
        }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals("${store.value} ${operations.calls}", VirtualMachineImageImportRunResult.RETRY, result)
        assertFalse("upload" in operations.calls)
        assertEquals(1, operations.calls.count { it == "create" })
    }

    @Test
    fun `本地授权未释放时保留证据且不开始create`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.UPLOADED,
                temporaryFileBaseline = baseline(),
            ),
        )
        val operations = FakeImportOperations().apply { grantReleased = false }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.NEEDS_REVIEW, result)
        assertTrue(store.value.ownsPersistedReadGrant)
        assertFalse("create" in operations.calls)
    }

    @Test
    fun `清理失败保留完整基线和cleanup pending`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.TEMP_CLEANUP,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
            ),
        )
        val operations = FakeImportOperations().apply {
            files.add(file())
            deleteSucceeded = false
        }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.NEEDS_REVIEW, result)
        assertEquals(PersistedVirtualMachineImageImportStage.CLEANUP_PENDING, store.value.stage)
        assertEquals(baseline(), store.value.temporaryFileBaseline)
        assertTrue(store.value.requiresRefresh)
    }

    @Test
    fun `clear提交未知恢复时任务仍存在则继续只读重试`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.TASK_CLEARING,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
                taskClearSubmitted = true,
            ),
        )
        val operations = FakeImportOperations().apply { taskExists = true }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.RETRY, result)
        assertEquals(PersistedVirtualMachineImageImportStage.TASK_CLEARING, store.value.stage)
        assertEquals(listOf("task-exists"), operations.calls)
        assertFalse("clear" in operations.calls)
    }

    @Test
    fun `上传前路径瞬时读取失败保留阶段且后续不重传已有文件`() = runTest {
        val store = MemoryImportStore(
            record().copy(stage = PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING),
        )
        val operations = FakeImportOperations().apply {
            fileFailures = 1
            files.add(file())
            taskFinished = false
        }

        val first = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")
        val second = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.RETRY, first)
        assertEquals(VirtualMachineImageImportRunResult.RETRY, second)
        assertFalse(store.value.stage == PersistedVirtualMachineImageImportStage.NEEDS_REVIEW)
        assertFalse("upload" in operations.calls)
        assertEquals(1, operations.calls.count { it == "create" })
    }

    @Test
    fun `上传调用异常进入人工核对且不会由同次执行重放`() = runTest {
        val store = MemoryImportStore(
            record().copy(stage = PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING),
        )
        val operations = FakeImportOperations().apply {
            files.add(null)
            uploadFailures = 1
        }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.NEEDS_REVIEW, result)
        assertEquals(PersistedVirtualMachineImageImportStage.NEEDS_REVIEW, store.value.stage)
        assertEquals(1, operations.calls.count { it == "upload" })
        assertFalse("create" in operations.calls)
    }

    @Test
    fun `任务读取瞬时失败保留追踪阶段且后续可完成`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.TASK_TRACKING,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
            ),
        )
        val operations = FakeImportOperations().apply {
            taskFailures = 1
            files.add(null)
        }

        val first = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")
        assertEquals(VirtualMachineImageImportRunResult.RETRY, first)
        assertEquals(PersistedVirtualMachineImageImportStage.TASK_TRACKING, store.value.stage)

        val second = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")
        assertEquals(VirtualMachineImageImportRunResult.SUCCEEDED, second)
        assertEquals(1, operations.calls.count { it == "clear" })
    }

    @Test
    fun `映像回读瞬时失败保留阶段且后续只提交一次clear`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.IMAGE_READBACK,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
                imageId = "image",
            ),
        )
        val operations = FakeImportOperations().apply {
            imageFailures = 1
            files.add(null)
        }

        val first = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")
        assertEquals(VirtualMachineImageImportRunResult.RETRY, first)
        assertEquals(PersistedVirtualMachineImageImportStage.IMAGE_READBACK, store.value.stage)

        val second = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")
        assertEquals(VirtualMachineImageImportRunResult.SUCCEEDED, second)
        assertEquals(1, operations.calls.count { it == "clear" })
    }

    @Test
    fun `映像尚未出现在列表时保留回读阶段继续等待`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.IMAGE_READBACK,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
                imageId = "image",
            ),
        )
        val operations = FakeImportOperations().apply {
            imageMatch = DsmRepository.VirtualMachineImageMatch.MISSING
        }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.RETRY, result)
        assertEquals(PersistedVirtualMachineImageImportStage.IMAGE_READBACK, store.value.stage)
        assertFalse("clear" in operations.calls)
    }

    @Test
    fun `同一映像标识的名称或类型冲突进入人工核对`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.IMAGE_READBACK,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
                imageId = "image",
            ),
        )
        val operations = FakeImportOperations().apply {
            imageMatch = DsmRepository.VirtualMachineImageMatch.DIFFERS
        }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.NEEDS_REVIEW, result)
        assertEquals(PersistedVirtualMachineImageImportStage.NEEDS_REVIEW, store.value.stage)
        assertFalse("clear" in operations.calls)
    }

    @Test
    fun `已提交clear的存在性读取瞬时失败后继续只读恢复`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.TASK_CLEARING,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
                taskClearSubmitted = true,
            ),
        )
        val operations = FakeImportOperations().apply {
            taskExistsFailures = 1
            taskExists = false
            files.add(null)
        }

        val first = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")
        assertEquals(VirtualMachineImageImportRunResult.RETRY, first)
        assertEquals(PersistedVirtualMachineImageImportStage.TASK_CLEARING, store.value.stage)

        val second = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")
        assertEquals(VirtualMachineImageImportRunResult.SUCCEEDED, second)
        assertFalse("clear" in operations.calls)
    }

    @Test
    fun `clear提交未知恢复时任务已不存在才继续清理`() = runTest {
        val store = MemoryImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.TASK_CLEARING,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
                taskClearSubmitted = true,
            ),
        )
        val operations = FakeImportOperations().apply {
            taskExists = false
            files.add(null)
        }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.SUCCEEDED, result)
        assertFalse("clear" in operations.calls)
        assertEquals(listOf("task-exists", "file"), operations.calls)
    }

    @Test
    fun `唯一工作名使用稳定摘要且不泄漏资料或映像名称`() {
        val first = stableVirtualMachineImageImportWorkName("private-record-id")
        val same = stableVirtualMachineImageImportWorkName("private-record-id")
        val other = stableVirtualMachineImageImportWorkName("other-record-id")

        assertEquals(first, same)
        assertFalse(first == other)
        assertTrue(first.startsWith(VirtualMachineImageImportWorker.UNIQUE_WORK_PREFIX))
        assertFalse(first.contains("private", ignoreCase = true))
    }

    @Test
    fun `profile或workId变化时旧Worker零副作用退出`() = runTest {
        val store = MemoryImportStore(record())
        val operations = FakeImportOperations()

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "old-work")

        assertEquals(VirtualMachineImageImportRunResult.STALE, result)
        assertTrue(operations.calls.isEmpty())
        assertTrue(store.stages.isEmpty())
    }

    private fun record() = PersistedVirtualMachineImageImport(
        id = "record",
        profileId = "profile",
        sourceUri = "content://synthetic/image",
        sourceDisplayName = "image.img",
        expectedBytes = 4096,
        stagingDirectoryPath = "/staging",
        temporaryFileName = "temporary.img",
        imageName = "Imported image",
        imageType = PersistedVirtualMachineImageType.DISK,
        storageId = "storage",
        storageName = "Storage",
        storageStatus = "online",
        workId = "work",
    )

    private fun baseline() = PersistedServerFileBaseline(
        path = "/staging/temporary.img",
        name = "temporary.img",
        isDirectory = false,
        size = 4096,
        modifiedAtEpochSeconds = 10,
        canRead = true,
        canDelete = true,
    )

    private fun file() = FileItem(
        path = "/staging/temporary.img",
        name = "temporary.img",
        isDirectory = false,
        size = 4096,
        modifiedAtEpochSeconds = 10,
        canRead = true,
        canDelete = true,
    )
}

private class MemoryImportStore(
    var value: PersistedVirtualMachineImageImport,
) : VirtualMachineImageImportRecordStore {
    val stages = mutableListOf<PersistedVirtualMachineImageImportStage>()

    override fun get(id: String) = value.takeIf { it.id == id }

    override fun updateOwned(
        id: String,
        profileId: String,
        workId: String,
        transform: (PersistedVirtualMachineImageImport) -> PersistedVirtualMachineImageImport,
    ): PersistedVirtualMachineImageImport? {
        if (value.id != id || value.profileId != profileId || value.workId != workId) return null
        value = transform(value)
        stages += value.stage
        return value
    }
}

private class FakeImportOperations : VirtualMachineImageImportOperations {
    val calls = mutableListOf<String>()
    val files = ArrayDeque<FileItem?>()
    var grantReleased = true
    var taskFinished = true
    var taskImageId: String? = "image"
    var imageMatch = DsmRepository.VirtualMachineImageMatch.MATCH
    var deleteSucceeded = true
    var taskExists = true
    var fileFailures = 0
    var uploadFailures = 0
    var taskFailures = 0
    var imageFailures = 0
    var taskExistsFailures = 0

    override suspend fun file(path: String): FileItem? {
        calls += "file"
        if (fileFailures-- > 0) throw IOException("synthetic-file-read")
        return files.removeFirstOrNull()
    }

    override suspend fun upload(record: PersistedVirtualMachineImageImport): Boolean {
        calls += "upload"
        if (uploadFailures-- > 0) throw IOException("synthetic-upload")
        return true
    }

    override suspend fun startCreate(record: PersistedVirtualMachineImageImport): String {
        calls += "create"
        return "task"
    }

    override suspend fun task(taskId: String): DsmRepository.VirtualMachineImageTaskReadback {
        calls += "task"
        if (taskFailures-- > 0) throw IOException("synthetic-task-read")
        return DsmRepository.VirtualMachineImageTaskReadback(taskFinished, taskImageId)
    }

    override suspend fun imageMatches(
        record: PersistedVirtualMachineImageImport,
    ): DsmRepository.VirtualMachineImageMatch {
        calls += "image"
        if (imageFailures-- > 0) throw IOException("synthetic-image-read")
        return imageMatch
    }

    override suspend fun clearTask(taskId: String) {
        calls += "clear"
    }

    override suspend fun taskExists(taskId: String): Boolean {
        calls += "task-exists"
        if (taskExistsFailures-- > 0) throw IOException("synthetic-task-exists-read")
        return taskExists
    }

    override suspend fun deleteTemporary(baseline: FileItem): Boolean {
        calls += "delete"
        return deleteSucceeded
    }

    override fun releaseReadGrant(sourceUri: String): Boolean {
        calls += "release"
        return grantReleased
    }
}
