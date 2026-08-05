package io.github.qwertyuiop1995.dsmnativeclient

import android.net.Uri
import androidx.work.ListenableWorker
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedPhotoBackupSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhotoBackupScanPolicyTest {
    @Test
    fun `截断扫描不部分入队并暂停后续扫描`() {
        val document = BackupDocument(
            uri = Uri.parse("content://synthetic/tree/image.jpg"),
            name = "image.jpg",
            mimeType = "image/jpeg",
            size = 42,
            relativeFolder = "",
        )

        val boundaryPlan = photoBackupScanPlan(
            DocumentTreeScan(files = listOf(document), truncated = false),
        )
        val truncatedPlan = photoBackupScanPlan(
            DocumentTreeScan(files = listOf(document), truncated = true),
        )
        val source = PersistedPhotoBackupSource(
            profileId = "profile-a",
            treeUri = "content://synthetic/tree",
            destinationPath = "/photo/backup",
            enabled = false,
            needsAttention = true,
        )
        val result = photoBackupScanFailure(PhotoBackupScanWorker.SCAN_OUTCOME_TOO_MANY_DOCUMENTS)

        assertEquals(listOf(document), boundaryPlan.files)
        assertFalse(boundaryPlan.needsAttention)
        assertTrue(truncatedPlan.files.isEmpty())
        assertTrue(truncatedPlan.needsAttention)
        assertFalse(shouldScanPhotoBackupSource(source))
        assertTrue(result is ListenableWorker.Result.Failure)
        assertEquals(
            PhotoBackupScanWorker.SCAN_OUTCOME_TOO_MANY_DOCUMENTS,
            result.outputData.getString(PhotoBackupScanWorker.KEY_SCAN_OUTCOME),
        )
    }
}
