package io.github.qwertyuiop1995.dsmnativeclient.ui

import io.github.qwertyuiop1995.dsmnativeclient.DownloadEnqueueResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingDownloadRequestStateTest {
    @Test
    fun `保存状态重建后保留最小稳定字段`() {
        val original = PendingDownloadRequestState(
            FileItem(
                path = "/synthetic/photo.jpg",
                name = "photo.jpg",
                isDirectory = false,
                size = 42,
                canRead = true,
                canWrite = true,
                canDelete = true,
                mimeType = "image/jpeg",
            ).toPendingDownloadRequest(profileId = "profile-a"),
        )

        val restored = pendingDownloadRequestStateFrom(original.toSaveableValues())

        assertEquals(original, restored)
        assertEquals(
            FileItem(
                path = "/synthetic/photo.jpg",
                name = "photo.jpg",
                isDirectory = false,
                size = 42,
                canRead = true,
            ),
            restored.request?.toFileItem(),
        )
        assertFalse(restored.toSaveableValues().any { value ->
            value.toString().contains("token", ignoreCase = true) ||
                value.toString().contains("password", ignoreCase = true)
        })
    }

    @Test
    fun `无待处理请求的保存状态可重建`() {
        val restored = pendingDownloadRequestStateFrom(
            PendingDownloadRequestState().toSaveableValues(),
        )

        assertNull(restored.request)
    }

    @Test
    fun `用户取消时只消费待处理请求且不丢弃目标`() {
        val pending = requestState(profileId = "profile-a")

        val cancelled = resolveDownloadDestination(
            pending = pending,
            activeProfileId = "profile-a",
            destinationSelected = false,
        )

        assertEquals(DownloadDestinationDecision.CANCELLED, cancelled.decision)
        assertNull(cancelled.request)
        assertNull(cancelled.nextPending.request)

        val repeated = resolveDownloadDestination(
            pending = cancelled.nextPending,
            activeProfileId = "profile-a",
            destinationSelected = true,
        )
        assertEquals(DownloadDestinationDecision.DISCARD_ORPHAN, repeated.decision)
    }

    @Test
    fun `资料不匹配或请求丢失时丢弃新建目标`() {
        val mismatch = resolveDownloadDestination(
            pending = requestState(profileId = "profile-a"),
            activeProfileId = "profile-b",
            destinationSelected = true,
        )
        val orphan = resolveDownloadDestination(
            pending = PendingDownloadRequestState(),
            activeProfileId = "profile-a",
            destinationSelected = true,
        )

        assertEquals(DownloadDestinationDecision.DISCARD_ORPHAN, mismatch.decision)
        assertEquals(DownloadDestinationDecision.DISCARD_ORPHAN, orphan.decision)
        assertNull(mismatch.nextPending.request)
        assertNull(orphan.nextPending.request)
    }

    @Test
    fun `仅真实后台下载需要请求通知权限`() {
        assertTrue(
            shouldRequestDownloadNotificationPermission(
                DownloadEnqueueResult.BACKGROUND,
                sdkInt = 35,
                notificationPermissionGranted = false,
            ),
        )
        assertFalse(
            shouldRequestDownloadNotificationPermission(
                DownloadEnqueueResult.FOREGROUND,
                sdkInt = 35,
                notificationPermissionGranted = false,
            ),
        )
        assertFalse(
            shouldRequestDownloadNotificationPermission(
                DownloadEnqueueResult.REJECTED,
                sdkInt = 35,
                notificationPermissionGranted = false,
            ),
        )
        assertFalse(
            shouldRequestDownloadNotificationPermission(
                DownloadEnqueueResult.BACKGROUND,
                sdkInt = 32,
                notificationPermissionGranted = false,
            ),
        )
        assertFalse(
            shouldRequestDownloadNotificationPermission(
                DownloadEnqueueResult.BACKGROUND,
                sdkInt = 35,
                notificationPermissionGranted = true,
            ),
        )
    }

    private fun requestState(profileId: String) = PendingDownloadRequestState(
        PendingDownloadRequest(
            profileId = profileId,
            path = "/synthetic/file.bin",
            name = "file.bin",
            isDirectory = false,
            size = 7,
            canRead = true,
        ),
    )
}
