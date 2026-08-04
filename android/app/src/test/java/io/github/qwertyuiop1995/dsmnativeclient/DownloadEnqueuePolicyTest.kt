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
}
