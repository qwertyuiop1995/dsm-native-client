package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import org.junit.Assert.assertEquals
import org.junit.Test

class TransferNotificationContentTest {
    @Test
    fun `普通上传使用上传标题和状态`() {
        val waiting = foregroundNotificationContent(
            TransferDirection.UPLOAD,
            TransferState.WAITING,
            isPhotoBackup = false,
        )
        val running = foregroundNotificationContent(
            TransferDirection.UPLOAD,
            TransferState.RUNNING,
            isPhotoBackup = false,
        )

        assertEquals(R.string.notification_upload_title, waiting.title)
        assertEquals(R.string.transfer_waiting, waiting.status)
        assertEquals(R.string.notification_upload_title, running.title)
        assertEquals(R.string.transfer_uploading, running.status)
        assertEquals(
            R.string.notification_upload_completed,
            completionNotificationTitle(TransferDirection.UPLOAD, true, isPhotoBackup = false),
        )
        assertEquals(
            R.string.notification_upload_failed,
            completionNotificationTitle(TransferDirection.UPLOAD, false, isPhotoBackup = false),
        )
    }

    @Test
    fun `照片备份继续使用备份标题和状态`() {
        val waiting = foregroundNotificationContent(
            TransferDirection.UPLOAD,
            TransferState.WAITING,
            isPhotoBackup = true,
        )
        val running = foregroundNotificationContent(
            TransferDirection.UPLOAD,
            TransferState.RUNNING,
            isPhotoBackup = true,
        )

        assertEquals(R.string.notification_backup_title, waiting.title)
        assertEquals(R.string.transfer_waiting_to_backup, waiting.status)
        assertEquals(R.string.notification_backup_title, running.title)
        assertEquals(R.string.transfer_backing_up, running.status)
        assertEquals(
            R.string.notification_backup_completed,
            completionNotificationTitle(TransferDirection.UPLOAD, true, isPhotoBackup = true),
        )
        assertEquals(
            R.string.notification_backup_failed,
            completionNotificationTitle(TransferDirection.UPLOAD, false, isPhotoBackup = true),
        )
    }

    @Test
    fun `下载通知不受备份标记影响`() {
        val content = foregroundNotificationContent(
            TransferDirection.DOWNLOAD,
            TransferState.RUNNING,
            isPhotoBackup = true,
        )

        assertEquals(R.string.notification_download_title, content.title)
        assertEquals(R.string.transfer_downloading, content.status)
        assertEquals(
            R.string.notification_download_completed,
            completionNotificationTitle(TransferDirection.DOWNLOAD, true, isPhotoBackup = true),
        )
        assertEquals(
            R.string.notification_download_failed,
            completionNotificationTitle(TransferDirection.DOWNLOAD, false, isPhotoBackup = true),
        )
    }

    @Test
    fun `取消与待核验通知不误报失败`() {
        assertEquals(
            R.string.notification_upload_cancelled,
            completionNotificationTitle(
                TransferDirection.UPLOAD,
                TransferCompletionOutcome.CANCELLED,
                isPhotoBackup = false,
            ),
        )
        assertEquals(
            R.string.notification_backup_cancelled,
            completionNotificationTitle(
                TransferDirection.UPLOAD,
                TransferCompletionOutcome.CANCELLED,
                isPhotoBackup = true,
            ),
        )
        assertEquals(
            R.string.notification_upload_needs_review,
            completionNotificationTitle(
                TransferDirection.UPLOAD,
                TransferCompletionOutcome.NEEDS_REVIEW,
                isPhotoBackup = false,
            ),
        )
        assertEquals(
            R.string.notification_backup_needs_review,
            completionNotificationTitle(
                TransferDirection.UPLOAD,
                TransferCompletionOutcome.NEEDS_REVIEW,
                isPhotoBackup = true,
            ),
        )
    }
}
