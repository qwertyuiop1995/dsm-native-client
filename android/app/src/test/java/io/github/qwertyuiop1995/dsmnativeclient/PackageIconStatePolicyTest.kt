package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.PackageInfo
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PackageIconStatePolicyTest {
    @Test
    fun `缓存键隔离 NAS 套件版本和尺寸`() {
        val original = packageInfo()
        val key = packageIconCacheKey("nas-a", original, 128)

        assertEquals(key, packageIconCacheKey("nas-a", original, 128))
        assertFalse(key == packageIconCacheKey("nas-b", original, 128))
        assertFalse(key == packageIconCacheKey("nas-a", original.copy(id = "other"), 128))
        assertFalse(key == packageIconCacheKey("nas-a", original.copy(version = "2.0"), 128))
        assertFalse(key == packageIconCacheKey("nas-a", original, 64))
    }

    @Test
    fun `迟到图标仅可写回原 Repository NAS 和设置模块`() {
        assertTrue(packageIconRequestMatches(true, "nas-a", Module.NAS_SETTINGS, "nas-a"))
        assertFalse(packageIconRequestMatches(false, "nas-a", Module.NAS_SETTINGS, "nas-a"))
        assertFalse(packageIconRequestMatches(true, "nas-b", Module.NAS_SETTINGS, "nas-a"))
        assertFalse(packageIconRequestMatches(true, "nas-a", Module.FILES, "nas-a"))
    }

    @Test
    fun `位图采样保持二次幂并限制解码尺寸`() {
        assertEquals(1, packageIconSampleSize(256, 128, 256))
        assertEquals(4, packageIconSampleSize(1024, 512, 256))
        assertEquals(8, packageIconSampleSize(2000, 400, 256))
    }

    private fun packageInfo() = PackageInfo(
        id = "synthetic-package",
        name = "Synthetic Package",
        version = "1.0",
        status = ResourceState.RUNNING,
        description = null,
        canStart = false,
        canStop = true,
    )
}
