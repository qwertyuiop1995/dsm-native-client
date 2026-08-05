package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationExpectedOutput
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationLifecycle
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationTarget
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationVerification
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferTask
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FileServerMutationStatePolicyTest {
    private val source = FileItem(
        path = "/volume1/shared/source.txt",
        name = "source.txt",
        isDirectory = false,
        size = 12,
        modifiedAtEpochSeconds = 100,
        canRead = true,
        canWrite = true,
        canDelete = true,
    )
    private val destination = FileItem(
        path = "/volume1/shared",
        name = "shared",
        isDirectory = true,
        modifiedAtEpochSeconds = 90,
        canRead = true,
        canWrite = true,
        canDelete = false,
    )
    private val target = FileServerMutationTarget(
        profileId = "profile-a",
        module = Module.FILES,
        operation = FileServerMutationOperation.COMPRESS,
        sourceBaselines = listOf(source),
        destinationFolderBaseline = destination,
        expectedOutputs = listOf(
            FileServerMutationExpectedOutput("${destination.path}/archive.zip", false),
        ),
    )

    @Test
    fun `运行中未知结果和刷新失败均阻止退出`() {
        assertTrue(hasBlockingFileServerTransfer(listOf(task(
            state = TransferState.RUNNING,
            lifecycle = FileServerMutationLifecycle(target, generation = 1),
        ))))
        assertTrue(hasBlockingFileServerTransfer(listOf(task(
            state = TransferState.FAILED,
            lifecycle = FileServerMutationLifecycle(
                target,
                result = unknownResult(),
                generation = 2,
            ),
        ))))
        assertTrue(hasBlockingFileServerTransfer(listOf(task(
            state = TransferState.FAILED,
            lifecycle = FileServerMutationLifecycle(
                target,
                result = unknownResult(),
                refreshFailure = failure(),
                generation = 3,
            ),
        ))))
        assertFalse(hasBlockingFileServerTransfer(listOf(task(
            state = TransferState.FAILED,
            lifecycle = FileServerMutationLifecycle(
                target,
                result = unknownResult(),
                refreshCompleted = true,
                verification = FileServerMutationVerification.DIFFERS,
                generation = 4,
            ),
        ))))
    }

    @Test
    fun `目标和代次共同构成归档回调身份`() {
        val lifecycle = FileServerMutationLifecycle(target, generation = 7)
        assertNotEquals(lifecycle, lifecycle.copy(generation = 8))
        assertNotEquals(
            lifecycle,
            lifecycle.copy(target = target.copy(profileId = "profile-b")),
        )
        assertNotEquals(
            lifecycle,
            lifecycle.copy(target = target.copy(expectedOutputs = listOf(
                FileServerMutationExpectedOutput("${destination.path}/other.zip", false),
            ))),
        )
        assertEquals(lifecycle, lifecycle.copy())
    }

    @Test
    fun `刷新核对四态均可原样记录且刷新中保持门禁`() {
        FileServerMutationVerification.entries.forEach { verification ->
            val lifecycle = FileServerMutationLifecycle(
                target = target,
                result = unknownResult(),
                refreshCompleted = true,
                verification = verification,
                generation = 9,
            )
            assertEquals(verification, lifecycle.copy().verification)
            assertEquals(
                verification == FileServerMutationVerification.UNAVAILABLE,
                fileServerMutationBlocksWorkspaceExit(lifecycle),
            )
            assertTrue(fileServerMutationCanBeExplicitlyCleared(lifecycle))
            assertTrue(fileServerMutationBlocksWorkspaceExit(
                lifecycle.copy(refreshInProgress = true, refreshCompleted = false),
            ))
        }
    }

    private fun task(
        state: TransferState,
        lifecycle: FileServerMutationLifecycle,
    ) = TransferTask(
        id = "task-${lifecycle.generation}",
        title = "archive.zip",
        detail = "synthetic",
        direction = TransferDirection.SERVER,
        state = state,
        requiresRefresh = lifecycle.result?.requiresRefresh == true,
        fileServerMutation = lifecycle,
    )

    private fun unknownResult() = MutationResult(
        schemaVersion = 1,
        status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
        operation = "archiveCompress",
        submitted = true,
        requiresRefresh = true,
        counts = MutationResultCounts(0, 0, 1),
    )

    private fun failure() = DsmFailure(
        code = null,
        message = "Synthetic failure",
        recovery = "Retry.",
        kind = DsmErrorKind.UNKNOWN,
    )
}
