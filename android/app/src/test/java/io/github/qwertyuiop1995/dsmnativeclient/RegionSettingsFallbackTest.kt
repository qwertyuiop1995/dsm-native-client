package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.NasManualDateTime
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasRegionSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasTimeZoneOption
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RegionSettingsFallbackTest {
    private val zones = listOf(NasTimeZoneOption("Asia/Shanghai", "Beijing"))
    private val cachedTime = NasManualDateTime(2026, 8, 4, 12, 34, 56)

    @Test
    fun `区域成功回退规范化提交字段并保留未编辑时间与时区目录`() {
        val cached = region(manual = cachedTime, zones = zones)
        val draft = region(manual = null, zones = listOf(NasTimeZoneOption("fake", "fake"))).copy(
            dateFormat = " Y/m/d ",
            timeFormat = " H:i:s ",
            timeZone = "UTC",
            isNetworkTimeEnabled = true,
            timeServers = listOf(" time.example.invalid ", ""),
        )

        val value = confirmedRegionSettingsFallback(snapshot(cached), draft)?.regionSettings

        assertEquals("Y/m/d", value?.dateFormat)
        assertEquals("H:i:s", value?.timeFormat)
        assertEquals("UTC", value?.timeZone)
        assertEquals(listOf("time.example.invalid"), value?.timeServers)
        assertEquals(cachedTime, value?.manualDateTime)
        assertEquals(zones, value?.timeZones)
    }

    @Test
    fun `用户明确编辑手动时间时成功回退只替换该时间`() {
        val edited = NasManualDateTime(2026, 8, 5, 1, 2, 3)

        val value = confirmedRegionSettingsFallback(
            snapshot(region(manual = cachedTime, zones = zones)),
            region(manual = edited, zones = emptyList()),
        )?.regionSettings

        assertEquals(edited, value?.manualDateTime)
        assertEquals(zones, value?.timeZones)
    }

    @Test
    fun `没有已知区域快照时不伪造成功回退`() {
        assertNull(confirmedRegionSettingsFallback(snapshot(null), region(null, zones)))
    }

    private fun region(
        manual: NasManualDateTime?,
        zones: List<NasTimeZoneOption>,
    ) = NasRegionSettings(
        "Y-m-d", "H:i", "Asia/Shanghai", false, emptyList(), manual, zones,
    )

    private fun snapshot(region: NasRegionSettings?) = NasSettingsSnapshot(
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
        proxySettings = null,
        regionSettings = region,
        securitySettings = null,
        hardwareSettings = null,
        security = emptyList(),
    )
}
