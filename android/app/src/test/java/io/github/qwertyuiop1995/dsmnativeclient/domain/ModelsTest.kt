package io.github.qwertyuiop1995.dsmnativeclient.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ModelsTest {
    @Test
    fun `传输进度限制在有效范围`() {
        val task = TransferTask(
            id = "1",
            title = "测试",
            detail = "",
            direction = TransferDirection.DOWNLOAD,
            state = TransferState.RUNNING,
            completedBytes = 150,
            totalBytes = 100,
        )
        assertEquals(1f, task.progress)
    }

    @Test
    fun `未知总大小不伪造进度`() {
        val task = TransferTask(
            id = "1",
            title = "测试",
            detail = "",
            direction = TransferDirection.DOWNLOAD,
            state = TransferState.RUNNING,
        )
        assertNull(task.progress)
    }

    @Test
    fun `文件扩展名按小写解析`() {
        val item = FileItem(
            path = "/photo/IMG_0001.HEIC",
            name = "IMG_0001.HEIC",
            isDirectory = false,
        )
        assertEquals("heic", item.extension)
    }

    @Test
    fun `能力版本不会超出服务端范围`() {
        val capability = ApiCapability("api", "entry.cgi", 2, 4)
        assertEquals(2, capability.version(1))
        assertEquals(4, capability.version(8))
        assertEquals(3, capability.version(3))
    }
}
