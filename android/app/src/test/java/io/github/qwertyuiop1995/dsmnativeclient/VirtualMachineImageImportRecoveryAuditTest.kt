package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.data.DsmRepository
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedServerFileBaseline
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageImport
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageImportStage
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageType
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** 对后台恢复边界的补充审计测试；不依赖真实 NAS 或实体机。 */
class VirtualMachineImageImportRecoveryAuditTest {
    @Test
    fun `上传提交读回必须同时匹配路径名称类型和长度`() = runTest {
        val mismatches = listOf(
            serverFile(path = "/other/temporary.img"),
            serverFile(name = "other.img"),
            serverFile(isDirectory = true),
            serverFile(size = 4095),
        )

        mismatches.forEach { observed ->
            val store = AuditImportStore(
                record().copy(stage = PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING),
            )
            val operations = AuditImportOperations().apply { files.add(observed) }

            val result = VirtualMachineImageImportRunner(store, operations)
                .run("record", "profile", "work")

            assertEquals(VirtualMachineImageImportRunResult.NEEDS_REVIEW, result)
            assertEquals(PersistedVirtualMachineImageImportStage.NEEDS_REVIEW, store.value.stage)
            assertEquals("upload-conflict", store.value.errorKind)
            assertEquals(listOf("file"), operations.calls)
            assertTrue(store.value.ownsPersistedReadGrant)
        }
    }

    @Test
    fun `映像读回瞬时异常保留原阶段与全部恢复证据`() = runTest {
        val original = record().copy(
            stage = PersistedVirtualMachineImageImportStage.IMAGE_READBACK,
            temporaryFileBaseline = baseline(),
            ownsPersistedReadGrant = false,
            taskId = "task",
            imageId = "image",
        )
        val store = AuditImportStore(original)
        val operations = AuditImportOperations().apply { imageFailure = true }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.RETRY, result)
        assertEquals(PersistedVirtualMachineImageImportStage.IMAGE_READBACK, store.value.stage)
        assertEquals("task", store.value.taskId)
        assertEquals("image", store.value.imageId)
        assertEquals(original.temporaryFileBaseline, store.value.temporaryFileBaseline)
        assertFalse(store.value.requiresRefresh)
        assertEquals(listOf("image"), operations.calls)
    }

    @Test
    fun `只有授权实际释放后才持久化已释放标记`() = runTest {
        lateinit var store: AuditImportStore
        val operations = AuditImportOperations().apply {
            releaseResult = true
            onRelease = {
                assertTrue(store.value.ownsPersistedReadGrant)
                assertEquals(PersistedVirtualMachineImageImportStage.UPLOADED, store.value.stage)
            }
            taskFinished = false
        }
        store = AuditImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.UPLOADED,
                temporaryFileBaseline = baseline(),
            ),
        )

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.RETRY, result)
        assertFalse(store.value.ownsPersistedReadGrant)
        assertTrue(operations.calls.indexOf("release") < operations.calls.indexOf("create"))
        assertFalse(store.snapshots.first().ownsPersistedReadGrant)
    }

    @Test
    fun `任务清理未知且任务仍存在时不删除临时文件`() = runTest {
        val store = AuditImportStore(
            record().copy(
                stage = PersistedVirtualMachineImageImportStage.TASK_CLEARING,
                temporaryFileBaseline = baseline(),
                ownsPersistedReadGrant = false,
                taskId = "task",
                imageId = "image",
                taskClearSubmitted = true,
            ),
        )
        val operations = AuditImportOperations().apply { taskStillExists = true }

        val result = VirtualMachineImageImportRunner(store, operations)
            .run("record", "profile", "work")

        assertEquals(VirtualMachineImageImportRunResult.RETRY, result)
        assertEquals(PersistedVirtualMachineImageImportStage.TASK_CLEARING, store.value.stage)
        assertEquals(listOf("task-exists"), operations.calls)
        assertFalse("clear" in operations.calls)
        assertFalse("delete" in operations.calls)
        assertNotNull(store.value.temporaryFileBaseline)
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

    private fun serverFile(
        path: String = "/staging/temporary.img",
        name: String = "temporary.img",
        isDirectory: Boolean = false,
        size: Long = 4096,
    ) = FileItem(
        path = path,
        name = name,
        isDirectory = isDirectory,
        size = size,
        modifiedAtEpochSeconds = 10,
        canRead = true,
        canDelete = true,
    )
}

private class AuditImportStore(
    var value: PersistedVirtualMachineImageImport,
) : VirtualMachineImageImportRecordStore {
    val snapshots = mutableListOf<PersistedVirtualMachineImageImport>()

    override fun get(id: String) = value.takeIf { it.id == id }

    override fun updateOwned(
        id: String,
        profileId: String,
        workId: String,
        transform: (PersistedVirtualMachineImageImport) -> PersistedVirtualMachineImageImport,
    ): PersistedVirtualMachineImageImport? {
        if (value.id != id || value.profileId != profileId || value.workId != workId) return null
        value = transform(value)
        snapshots += value
        return value
    }
}

private class AuditImportOperations : VirtualMachineImageImportOperations {
    val calls = mutableListOf<String>()
    val files = ArrayDeque<FileItem?>()
    var releaseResult = true
    var onRelease: () -> Unit = {}
    var taskFinished = true
    var taskStillExists = true
    var imageFailure = false

    override suspend fun file(path: String): FileItem? {
        calls += "file"
        return files.removeFirstOrNull()
    }

    override suspend fun upload(record: PersistedVirtualMachineImageImport): Boolean {
        calls += "upload"
        return true
    }

    override suspend fun startCreate(record: PersistedVirtualMachineImageImport): String {
        calls += "create"
        return "task"
    }

    override suspend fun task(taskId: String): DsmRepository.VirtualMachineImageTaskReadback {
        calls += "task"
        return DsmRepository.VirtualMachineImageTaskReadback(taskFinished, "image")
    }

    override suspend fun imageMatches(
        record: PersistedVirtualMachineImageImport,
    ): DsmRepository.VirtualMachineImageMatch {
        calls += "image"
        if (imageFailure) error("synthetic readback failure")
        return DsmRepository.VirtualMachineImageMatch.MATCH
    }

    override suspend fun clearTask(taskId: String) {
        calls += "clear"
    }

    override suspend fun taskExists(taskId: String): Boolean {
        calls += "task-exists"
        return taskStillExists
    }

    override suspend fun deleteTemporary(baseline: FileItem): Boolean {
        calls += "delete"
        return true
    }

    override fun releaseReadGrant(sourceUri: String): Boolean {
        calls += "release"
        onRelease()
        return releaseResult
    }
}
