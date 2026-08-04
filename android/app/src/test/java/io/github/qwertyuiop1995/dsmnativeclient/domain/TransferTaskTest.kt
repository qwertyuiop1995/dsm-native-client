package io.github.qwertyuiop1995.dsmnativeclient.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TransferTaskTest {
    @Test
    fun `传输速度和剩余时间使用已完成字节与运行时间估算`() {
        val task = TransferTask(
            id = "task",
            title = "file",
            detail = "running",
            direction = TransferDirection.DOWNLOAD,
            state = TransferState.RUNNING,
            completedBytes = 2_000,
            totalBytes = 5_000,
            startedAtEpochMillis = 1_000,
        )

        assertEquals(1_000L, task.speedBytesPerSecond(nowEpochMillis = 3_000))
        assertEquals(3L, task.estimatedRemainingSeconds(nowEpochMillis = 3_000))
    }

    @Test
    fun `未满一秒或没有开始时间时不显示不稳定速度`() {
        assertNull(transferSpeedBytesPerSecond(1_000, null, 3_000))
        assertNull(transferSpeedBytesPerSecond(1_000, 2_500, 3_000))
    }
}
