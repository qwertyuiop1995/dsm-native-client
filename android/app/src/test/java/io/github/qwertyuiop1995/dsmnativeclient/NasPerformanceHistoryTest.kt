package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.PerformanceSample
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class NasPerformanceHistoryTest {
    @Test
    fun `相同服务端时间不会重复加入趋势`() {
        val existing = listOf(sample(100))

        val result = appendPerformanceSample(existing, sample(100))

        assertSame(existing, result)
    }

    @Test
    fun `性能趋势只保留最近120个有序采样`() {
        val existing = (1L..120L).map(::sample)

        val result = appendPerformanceSample(existing, sample(121))

        assertEquals(MAX_NAS_PERFORMANCE_SAMPLES, result.size)
        assertEquals(2L, result.first().timeEpochSeconds)
        assertEquals(121L, result.last().timeEpochSeconds)
    }

    private fun sample(time: Long) = PerformanceSample(
        timeEpochSeconds = time,
        cpuPercent = 20.0,
        cpuUserPercent = 10.0,
        cpuSystemPercent = 5.0,
        memoryPercent = 40.0,
        swapPercent = 1.0,
        networkReceiveBytesPerSecond = 1_024,
        networkSendBytesPerSecond = 2_048,
        diskReadBytesPerSecond = 4_096,
        diskWriteBytesPerSecond = 8_192,
        volumeReadBytesPerSecond = 3_000,
        volumeWriteBytesPerSecond = 4_000,
        diskUtilizationPercent = 15.0,
    )
}
