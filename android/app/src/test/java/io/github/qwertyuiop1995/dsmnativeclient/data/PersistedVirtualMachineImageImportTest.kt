package io.github.qwertyuiop1995.dsmnativeclient.data

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PersistedVirtualMachineImageImportTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `旧记录缺少后续字段时使用安全默认值`() {
        val legacy = json.decodeFromString<PersistedVirtualMachineImageImport>(
            """{
                "id":"import-1",
                "profileId":"profile-1",
                "sourceUri":"content://synthetic/image",
                "sourceDisplayName":"disk.img",
                "expectedBytes":4096,
                "stagingDirectoryPath":"/share/staging",
                "temporaryFileName":"lanstash-vmm-import-1.img",
                "imageName":"Synthetic disk",
                "imageType":"DISK",
                "storageId":"storage-1"
            }""".trimIndent(),
        )

        assertEquals(PersistedVirtualMachineImageImportStage.PREPARING, legacy.stage)
        assertTrue(legacy.ownsPersistedReadGrant)
        assertFalse(legacy.requiresRefresh)
        assertNull(legacy.taskId)
        assertNull(legacy.temporaryFileBaseline)
    }

    @Test
    fun `序列化只包含恢复字段且默认输出不泄露敏感载荷`() {
        val record = record().copy(
            taskId = "private-task-token",
            imageId = "private-image-id",
        )

        val encoded = json.encodeToString(record)
        val restored = json.decodeFromString<PersistedVirtualMachineImageImport>(encoded)
        val rendered = record.toString()

        assertEquals(record, restored)
        listOf("sid", "synotoken", "cookie", "password", "nasaddress", "hostname").forEach {
            assertFalse(it, encoded.lowercase().contains("\"$it\""))
        }
        assertFalse(rendered.contains(record.sourceUri))
        assertFalse(rendered.contains(record.stagingDirectoryPath))
        assertFalse(rendered.contains("private-task-token"))
        assertFalse(rendered.contains("private-image-id"))
    }

    @Test
    fun `列表CRUD按标识替换且不存在更新不制造记录`() {
        val first = record()
        val second = first.copy(id = "import-2", imageName = "Second")
        val inserted = emptyList<PersistedVirtualMachineImageImport>()
            .upsert(first)
            .upsert(second)
        val replaced = inserted.upsert(first.copy(imageName = "Updated"))
        val (updated, value) = replaced.updateById("import-2") {
            it.copy(stage = PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING)
        }
        val (unchanged, missing) = updated.updateById("missing") { it }

        assertEquals(2, replaced.size)
        assertEquals("Updated", replaced.single { it.id == first.id }.imageName)
        assertEquals(PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING, value?.stage)
        assertEquals(updated, unchanged)
        assertNull(missing)
        val (retained, activeRemoved) = updated.removeFinishedById("import-2")
        assertFalse(activeRemoved)
        assertEquals(updated, retained)
        val terminal = updated.map {
            if (it.id == "import-2") it.copy(
                stage = PersistedVirtualMachineImageImportStage.SUCCEEDED,
                temporaryFileBaseline = null,
            ) else it
        }
        val (removed, terminalRemoved) = terminal.removeFinishedById("import-2")
        assertTrue(terminalRemoved)
        assertEquals(listOf("import-1"), removed.map { it.id })
    }

    @Test
    fun `上传提交中必须精确回读后才继续或无覆盖重传`() {
        val submitting = checkNotNull(record().markUploadSubmitting())

        assertEquals(
            PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW,
            submitting.recoveryAction(),
        )
        assertEquals(
            PersistedVmmImportRecoveryAction.CONFIRM_UPLOAD_READBACK,
            submitting.recoveryAction(PersistedVmmUploadReadback.MATCHES),
        )
        assertEquals(
            PersistedVmmImportRecoveryAction.RETRY_UPLOAD_WITHOUT_OVERWRITE,
            submitting.recoveryAction(PersistedVmmUploadReadback.MISSING),
        )
        assertEquals(
            PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW,
            submitting.recoveryAction(PersistedVmmUploadReadback.DIFFERS),
        )
        assertNull(submitting.confirmUploaded(baseline(size = 4095)))
        assertNull(submitting.confirmUploaded(baseline(path = "/share/staging/other.img")))

        val uploaded = checkNotNull(submitting.confirmUploaded(baseline()))
        assertEquals(PersistedVirtualMachineImageImportStage.UPLOADED, uploaded.stage)
        assertTrue(uploaded.ownsPersistedReadGrant)
        assertFalse(uploaded.markReadGrantReleased().ownsPersistedReadGrant)
        assertEquals(PersistedVmmImportRecoveryAction.START_CREATE, uploaded.recoveryAction())
    }

    @Test
    fun `创建提交边界无任务标识时零重放而有标识只恢复只读任务`() {
        val uploaded = checkNotNull(
            checkNotNull(record().markUploadSubmitting()).confirmUploaded(baseline()),
        )
        val submitting = checkNotNull(uploaded.markCreateSubmitting())

        assertEquals(
            PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW,
            submitting.recoveryAction(),
        )
        assertFalse(submitting.recoveryAction() == PersistedVmmImportRecoveryAction.START_CREATE)
        val tracking = checkNotNull(submitting.captureTaskId("task-1"))
        assertEquals(PersistedVmmImportRecoveryAction.READ_TASK, tracking.recoveryAction())
        assertNull(uploaded.captureTaskId("task-1"))
        assertNull(submitting.captureTaskId(" "))
        assertEquals(
            PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW,
            uploaded.copy(temporaryFileBaseline = null).recoveryAction(),
        )
    }

    @Test
    fun `映像回读任务清理和临时文件清理不能跳序`() {
        val tracking = trackingRecord()

        assertNull(tracking.markTaskClearing())
        assertNull(tracking.markTemporaryCleanup())
        val imageReadback = checkNotNull(tracking.markImageReadback("image-1"))
        assertEquals(PersistedVmmImportRecoveryAction.READ_IMAGE, imageReadback.recoveryAction())
        val clearing = checkNotNull(imageReadback.markTaskClearing())
        assertEquals(PersistedVmmImportRecoveryAction.CLEAR_TASK, clearing.recoveryAction())
        assertNull(clearing.markTemporaryCleanup())
        val submittedClearing = checkNotNull(clearing.markTaskClearSubmitted())
        assertEquals(
            PersistedVmmImportRecoveryAction.CHECK_TASK_CLEARED,
            submittedClearing.recoveryAction(),
        )
        val cleanup = checkNotNull(submittedClearing.markTemporaryCleanup())
        assertNull(cleanup.taskId)
        assertEquals(
            PersistedVmmImportRecoveryAction.DELETE_TEMP_FILE_WITH_BASELINE,
            cleanup.recoveryAction(),
        )
        val pending = checkNotNull(cleanup.markCleanupPending("cleanup-failed"))
        assertTrue(pending.requiresRefresh)
        assertEquals(PersistedVirtualMachineImageImportStage.CLEANUP_PENDING, pending.stage)
        assertFalse(pending.canRemoveFromHistory())
        val succeeded = checkNotNull(pending.markSucceeded())
        assertTrue(succeeded.canRemoveFromHistory())
        assertNull(succeeded.temporaryFileBaseline)
        assertEquals(
            PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW,
            imageReadback.copy(taskId = null).recoveryAction(),
        )
        assertEquals(
            PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW,
            clearing.copy(taskId = null).recoveryAction(),
        )
    }

    @Test
    fun `缺少临时文件基线时清理只能转人工核对`() {
        val cleanup = record().copy(
            stage = PersistedVirtualMachineImageImportStage.TEMP_CLEANUP,
            taskId = null,
            temporaryFileBaseline = null,
        )

        assertEquals(PersistedVmmImportRecoveryAction.WAIT_FOR_REVIEW, cleanup.recoveryAction())
        assertFalse(cleanup.canRemoveFromHistory())
    }

    @Test
    fun `同资料同映像名称的非终态记录由稳定标识较小者领取work`() {
        val first = record()
        val duplicate = record().copy(id = "import-2", imageName = " synthetic disk ")
        val otherProfile = record().copy(id = "import-3", profileId = "profile-2")

        assertTrue(listOf(first, duplicate).canClaimWork(first.id))
        assertFalse(listOf(first, duplicate).canClaimWork(duplicate.id))
        assertTrue(listOf(duplicate, first).canClaimWork(first.id))
        assertTrue(listOf(first, otherProfile).canClaimWork(first.id))
        assertFalse(listOf(first.copy(workId = "work")).canClaimWork(first.id))
        assertTrue(
            listOf(
                first,
                duplicate.copy(stage = PersistedVirtualMachineImageImportStage.SUCCEEDED),
            ).canClaimWork(first.id),
        )
        assertFalse(
            listOf(first, duplicate.copy(workId = "work")).canClaimWork(first.id),
        )
    }

    @Test
    fun `入队异常只撤销仍匹配的work领取`() {
        val claimed = listOf(record().copy(workId = "work-1"))

        val (unchanged, rejected) = claimed.releaseWorkClaim("import-1", "work-2")
        val (released, accepted) = claimed.releaseWorkClaim("import-1", "work-1")

        assertFalse(rejected)
        assertEquals(claimed, unchanged)
        assertTrue(accepted)
        assertNull(released.single().workId)
    }

    @Test
    fun `首次记录原子插入领取且同名败者不落盘`() {
        val first = record()
        val duplicate = record().copy(id = "import-2", imageName = " synthetic disk ")

        val (inserted, accepted) = emptyList<PersistedVirtualMachineImageImport>()
            .insertAndClaimWork(first, "work-1")
        val (unchanged, rejected) = inserted.insertAndClaimWork(duplicate, "work-2")

        assertTrue(accepted)
        assertEquals("work-1", inserted.single().workId)
        assertFalse(rejected)
        assertEquals(inserted, unchanged)
        assertFalse(unchanged.any { it.id == duplicate.id })
    }

    @Test
    fun `首次入队异常只删除匹配且仍处于准备阶段的新记录`() {
        val claimed = listOf(record().copy(workId = "work-1"))

        val (wrongOwner, ownerRejected) = claimed.removeOwnedPreparingImport("import-1", "work-2")
        val advanced = claimed.single().copy(
            stage = PersistedVirtualMachineImageImportStage.UPLOAD_SUBMITTING,
        )
        val (wrongStage, stageRejected) = listOf(advanced)
            .removeOwnedPreparingImport("import-1", "work-1")
        val (removed, accepted) = claimed.removeOwnedPreparingImport("import-1", "work-1")

        assertFalse(ownerRejected)
        assertEquals(claimed, wrongOwner)
        assertFalse(stageRejected)
        assertEquals(listOf(advanced), wrongStage)
        assertTrue(accepted)
        assertTrue(removed.isEmpty())
    }

    private fun trackingRecord(): PersistedVirtualMachineImageImport {
        val submitting = checkNotNull(
            checkNotNull(
                checkNotNull(record().markUploadSubmitting()).confirmUploaded(baseline()),
            ).markCreateSubmitting(),
        )
        return checkNotNull(submitting.captureTaskId("task-1"))
    }

    private fun record() = PersistedVirtualMachineImageImport(
        id = "import-1",
        profileId = "profile-1",
        sourceUri = "content://synthetic/image",
        sourceDisplayName = "disk.img",
        sourceContentType = "application/octet-stream",
        expectedBytes = 4096,
        stagingDirectoryPath = "/share/staging",
        temporaryFileName = "lanstash-vmm-import-1.img",
        imageName = "Synthetic disk",
        imageType = PersistedVirtualMachineImageType.DISK,
        storageId = "storage-1",
        storageName = "Synthetic storage",
        storageStatus = "online",
    )

    private fun baseline(
        path: String = "/share/staging/lanstash-vmm-import-1.img",
        size: Long = 4096,
    ) = PersistedServerFileBaseline(
        path = path,
        name = path.substringAfterLast('/'),
        isDirectory = false,
        size = size,
        modifiedAtEpochSeconds = 100,
        canRead = true,
        canDelete = true,
    )
}
