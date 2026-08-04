package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProxySettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class ProxySettingsFallbackTest {
    @Test
    fun `启用代理回退使用已提交并核对的完整字段`() {
        val expected = NasProxySettings(true, "proxy.example.invalid", 3_128)

        val fallback = confirmedProxySettingsFallback(snapshot(NasProxySettings(false, "old", 80)), expected)

        assertEquals(expected, fallback?.proxySettings)
    }

    @Test
    fun `停用代理回退只改变开关并保留未提交的缓存字段`() {
        val cached = NasProxySettings(true, "cached.example.invalid", 8_080)
        val unsubmittedDraft = NasProxySettings(false, "draft.example.invalid", 9_090)

        val fallback = confirmedProxySettingsFallback(snapshot(cached), unsubmittedDraft)

        assertFalse(fallback?.proxySettings?.isEnabled ?: true)
        assertEquals("cached.example.invalid", fallback?.proxySettings?.host)
        assertEquals(8_080, fallback?.proxySettings?.port)
    }

    @Test
    fun `停用时没有已知代理快照则不伪造回退值`() {
        val fallback = confirmedProxySettingsFallback(
            snapshot(null),
            NasProxySettings(false, "draft.example.invalid", 9_090),
        )

        assertNull(fallback)
    }

    private fun snapshot(proxy: NasProxySettings?) = NasSettingsSnapshot(
        system = null,
        volumes = emptyList(),
        pools = emptyList(),
        disks = emptyList(),
        storageDisks = emptyList(),
        packages = emptyList(),
        scheduledTasks = emptyList(),
        accounts = emptyList(),
        groups = emptyList(),
        logs = emptyList(),
        connections = emptyList(),
        connectionsAvailable = true,
        networkInterfaces = emptyList(),
        networkInterfacesAvailable = true,
        ddnsDirectory = null,
        ddnsDirectoryAvailable = true,
        fileServiceSettings = null,
        terminalSettings = null,
        proxySettings = proxy,
        regionSettings = null,
        securitySettings = null,
        hardwareSettings = null,
        security = emptyList(),
    )
}
