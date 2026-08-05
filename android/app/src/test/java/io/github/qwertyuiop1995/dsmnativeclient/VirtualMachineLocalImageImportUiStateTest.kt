package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageImport
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageImportStage
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedVirtualMachineImageType
import java.lang.reflect.Modifier
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VirtualMachineLocalImageImportUiStateTest {
    @Test
    fun `只有尚未领取的准备阶段显示安全重试`() {
        assertTrue(record().toVirtualMachineLocalImageImportUiState().canRetry)
        assertFalse(
            record(workId = "claimed").toVirtualMachineLocalImageImportUiState().canRetry,
        )
        assertFalse(
            record(stage = PersistedVirtualMachineImageImportStage.CREATE_SUBMITTING)
                .toVirtualMachineLocalImageImportUiState().canRetry,
        )
        assertFalse(
            record(stage = PersistedVirtualMachineImageImportStage.TASK_CLEARING)
                .toVirtualMachineLocalImageImportUiState().canRetry,
        )
    }

    @Test
    fun `未知写与清理未确认只提示核对且不允许移除`() {
        listOf(
            PersistedVirtualMachineImageImportStage.NEEDS_REVIEW,
            PersistedVirtualMachineImageImportStage.CLEANUP_PENDING,
        ).forEach { stage ->
            val state = record(stage = stage).toVirtualMachineLocalImageImportUiState()
            assertTrue(state.needsReview)
            assertFalse(state.canRetry)
            assertFalse(state.canRemove)
        }
    }

    @Test
    fun `只有完整成功且无待清理证据时允许移除且UI状态不暴露URI路径`() {
        val state = record(stage = PersistedVirtualMachineImageImportStage.SUCCEEDED)
            .toVirtualMachineLocalImageImportUiState()

        assertTrue(state.canRemove)
        assertFalse(state.toString().contains("content://private"))
        assertFalse(state.toString().contains("/share/private"))
        assertTrue(
            VirtualMachineLocalImageImportUiState::class.java.declaredFields
                .filterNot { it.isSynthetic || Modifier.isStatic(it.modifiers) }
                .map { it.name }
                .none { it.contains("uri", ignoreCase = true) || it.contains("path", ignoreCase = true) },
        )
    }

    private fun record(
        stage: PersistedVirtualMachineImageImportStage =
            PersistedVirtualMachineImageImportStage.PREPARING,
        workId: String? = null,
    ) = PersistedVirtualMachineImageImport(
        id = "record-1",
        profileId = "profile-1",
        sourceUri = "content://private/source",
        sourceDisplayName = "private.vmdk",
        expectedBytes = 1L,
        stagingDirectoryPath = "/share/private",
        temporaryFileName = ".temporary.vmdk",
        imageName = "Local image",
        imageType = PersistedVirtualMachineImageType.DISK,
        storageId = "storage-1",
        stage = stage,
        workId = workId,
    )
}
