package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import org.junit.Assert.assertEquals
import org.junit.Test
import androidx.work.NetworkType
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse

class PhotoBackupDecisionTest {
    @Test
    fun `不存在目标时上传`() {
        assertEquals(BackupTargetDecision.UPLOAD, backupTargetDecision(null, 100))
    }

    @Test
    fun `同名同大小文件视为已备份`() {
        val existing = FileItem("/photos/a.jpg", "a.jpg", isDirectory = false, size = 100)
        assertEquals(BackupTargetDecision.SKIP_MATCHING, backupTargetDecision(existing, 100))
    }

    @Test
    fun `同名不同大小和目录均拒绝覆盖`() {
        val different = FileItem("/photos/a.jpg", "a.jpg", isDirectory = false, size = 99)
        val directory = FileItem("/photos/a.jpg", "a.jpg", isDirectory = true)
        assertEquals(BackupTargetDecision.CONFLICT, backupTargetDecision(different, 100))
        assertEquals(BackupTargetDecision.CONFLICT, backupTargetDecision(directory, 100))
    }

    @Test
    fun `后台备份只在安全资源条件下运行`() {
        val constraints = photoBackupConstraints()

        assertEquals(NetworkType.UNMETERED, constraints.requiredNetworkType)
        assertTrue(constraints.requiresCharging())
        assertTrue(constraints.requiresBatteryNotLow())
        assertTrue(constraints.requiresStorageNotLow())
    }

    @Test
    fun `自动来源只接受安全名称并保留相对目录`() {
        assertTrue(isSafeBackupName("旅行 2026"))
        assertFalse(isSafeBackupName("../照片"))
        assertFalse(isSafeBackupName("a/b"))
        assertEquals("/photo/移动备份/旅行/海边", backupDestination("/photo/移动备份", "旅行/海边"))
    }

    @Test
    fun `普通上传只有明确确认后才允许替换文件`() {
        val file = FileItem("/share/a.txt", "a.txt", isDirectory = false, size = 10)
        val directory = FileItem("/share/a.txt", "a.txt", isDirectory = true)

        assertEquals(BackupTargetDecision.UPLOAD, userUploadTargetDecision(null, overwrite = false))
        assertEquals(BackupTargetDecision.CONFLICT, userUploadTargetDecision(file, overwrite = false))
        assertEquals(BackupTargetDecision.UPLOAD, userUploadTargetDecision(file, overwrite = true))
        assertEquals(BackupTargetDecision.CONFLICT, userUploadTargetDecision(directory, overwrite = true))
    }

    @Test
    fun `上传重试先读取目标再决定完成冲突或从头开始`() {
        val complete = FileItem("/share/a.txt", "a.txt", isDirectory = false, size = 10)
        val conflict = FileItem("/share/a.txt", "a.txt", isDirectory = false, size = 9)

        assertEquals(RetryUploadDecision.ALREADY_COMPLETE, retryUploadDecision(complete, 10, false))
        assertEquals(RetryUploadDecision.CONFLICT, retryUploadDecision(conflict, 10, false))
        assertEquals(RetryUploadDecision.REQUEUE, retryUploadDecision(conflict, 10, true))
        assertEquals(RetryUploadDecision.REQUEUE, retryUploadDecision(null, 10, false))
    }
}
