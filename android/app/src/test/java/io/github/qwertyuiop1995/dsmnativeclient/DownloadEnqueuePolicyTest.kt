package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedDownload
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadEnqueuePolicyTest {
    @Test
    fun `后台下载同时要求保存会话和持久目标授权`() {
        assertTrue(
            canRunDownloadInBackground(
                savedSessionAvailable = true,
                persistableDestinationGrant = true,
            ),
        )
        assertFalse(
            canRunDownloadInBackground(
                savedSessionAvailable = true,
                persistableDestinationGrant = false,
            ),
        )
        assertFalse(
            canRunDownloadInBackground(
                savedSessionAvailable = false,
                persistableDestinationGrant = true,
            ),
        )
        assertFalse(
            canRunDownloadInBackground(
                savedSessionAvailable = false,
                persistableDestinationGrant = false,
            ),
        )
    }

    @Test
    fun `上传授权降级仍使用选择文件时的目标快照`() {
        assertEquals(
            "/share/original",
            resolveUploadDestination(
                destinationSnapshot = "/share/original",
                currentBrowserPath = "/share/later",
            ),
        )
        assertEquals(
            "/share/current",
            resolveUploadDestination(
                destinationSnapshot = null,
                currentBrowserPath = "/share/current",
            ),
        )
    }

    @Test
    fun `前台目录失败按独立执行所有权清理目标`() {
        val directory = PersistedDownload(
            id = "task",
            profileId = "profile",
            sourcePath = "/synthetic/folder",
            title = "folder.zip",
            destinationUri = "content://synthetic/folder.zip",
            isDirectory = true,
            state = TransferState.FAILED,
            workId = null,
        )

        assertTrue(shouldDeleteFailedForegroundDownload(directory, ownsExecution = true))
        assertFalse(shouldDeleteFailedForegroundDownload(directory, ownsExecution = false))
        assertFalse(
            shouldDeleteFailedForegroundDownload(
                directory.copy(isDirectory = false),
                ownsExecution = true,
            ),
        )
    }

    @Test
    fun `恢复后台下载只对明确缺失的当前任务重新入队`() {
        val record = PersistedDownload(
            id = "task",
            profileId = "profile",
            sourcePath = "/synthetic/file.bin",
            title = "file.bin",
            destinationUri = "content://synthetic/file.bin",
            isDirectory = false,
            workId = "work-a",
            backgroundCapable = true,
        )

        assertEquals(
            RestoredBackgroundDownloadDecision.MONITOR,
            restoredBackgroundDownloadDecision(
                lookup = RestoredBackgroundWorkLookup.PRESENT,
                current = record,
                expectedRecordId = record.id,
                expectedProfileId = record.profileId,
                expectedWorkId = "work-a",
            ),
        )
        assertEquals(
            RestoredBackgroundDownloadDecision.REENQUEUE,
            restoredBackgroundDownloadDecision(
                lookup = RestoredBackgroundWorkLookup.MISSING,
                current = record,
                expectedRecordId = record.id,
                expectedProfileId = record.profileId,
                expectedWorkId = "work-a",
            ),
        )
        assertEquals(
            RestoredBackgroundDownloadDecision.MONITOR,
            restoredBackgroundDownloadDecision(
                lookup = RestoredBackgroundWorkLookup.QUERY_FAILED,
                current = record,
                expectedRecordId = record.id,
                expectedProfileId = record.profileId,
                expectedWorkId = "work-a",
            ),
        )
        assertEquals(
            RestoredBackgroundDownloadDecision.IGNORE,
            restoredBackgroundDownloadDecision(
                lookup = RestoredBackgroundWorkLookup.MISSING,
                current = record.copy(workId = "work-b"),
                expectedRecordId = record.id,
                expectedProfileId = record.profileId,
                expectedWorkId = "work-a",
            ),
        )
        assertEquals(
            RestoredBackgroundDownloadDecision.FINALIZE_CANCELLATION,
            restoredBackgroundDownloadDecision(
                lookup = RestoredBackgroundWorkLookup.MISSING,
                current = record.copy(state = TransferState.CANCELLING),
                expectedRecordId = record.id,
                expectedProfileId = record.profileId,
                expectedWorkId = "work-a",
            ),
        )
        assertEquals(
            RestoredBackgroundDownloadDecision.IGNORE,
            restoredBackgroundDownloadDecision(
                lookup = RestoredBackgroundWorkLookup.MISSING,
                current = record.copy(state = TransferState.PAUSED),
                expectedRecordId = record.id,
                expectedProfileId = record.profileId,
                expectedWorkId = "work-a",
            ),
        )
    }

    @Test
    fun `后台入队边界拒绝迟到的所有权或状态`() {
        val waiting = PersistedDownload(
            id = "task",
            profileId = "profile",
            sourcePath = "/synthetic/file.bin",
            title = "file.bin",
            destinationUri = "content://synthetic/file.bin",
            isDirectory = false,
            workId = null,
            backgroundCapable = true,
        )

        assertTrue(waiting.canReplaceBackgroundDownloadWorkId(waiting))
        assertFalse(waiting.copy(workId = "new-work").canReplaceBackgroundDownloadWorkId(waiting))
        assertFalse(
            waiting.copy(state = TransferState.CANCELLING).canReplaceBackgroundDownloadWorkId(waiting),
        )
    }
}
