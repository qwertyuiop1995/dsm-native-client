package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class NasAddressParserTest {
    @Test
    fun `单段地址识别为 QuickConnect ID`() {
        val parsed = NasAddressParser.parse("family-nas")

        assertEquals("family-nas", parsed.host)
        assertEquals(5_001, parsed.port)
        assertEquals(NasAddressKind.QUICK_CONNECT, parsed.kind)
        assertFalse(parsed.hasExplicitPort)
    }

    @Test
    fun `QuickConnect 门户链接提取 ID`() {
        val parsed = NasAddressParser.parse("https://quickconnect.to/family-nas")

        assertEquals("family-nas", parsed.host)
        assertEquals(NasAddressKind.QUICK_CONNECT, parsed.kind)
    }

    @Test
    fun `裸 IP 默认使用 DSM HTTPS 端口`() {
        val parsed = NasAddressParser.parse("192.168.1.20")

        assertEquals(5_001, parsed.port)
        assertEquals(NasAddressKind.DIRECT, parsed.kind)
    }

    @Test
    fun `完整 HTTPS 地址默认使用标准 HTTPS 端口`() {
        val parsed = NasAddressParser.parse("https://nas.example.com")

        assertEquals(443, parsed.port)
        assertEquals(NasAddressKind.DIRECT, parsed.kind)
    }

    @Test
    fun `端口覆盖应用于 QuickConnect 候选`() {
        val parsed = NasAddressParser.parse("family-nas", portOverride = 6_001)

        assertEquals(6_001, parsed.port)
        assertTrue(parsed.hasExplicitPort)
    }

    @Test
    fun `拒绝明文地址和嵌入式凭据`() {
        assertThrows(DsmFailure::class.java) {
            NasAddressParser.parse("http://nas.example.com")
        }
        assertThrows(DsmFailure::class.java) {
            NasAddressParser.parse("https://user:password@nas.example.com")
        }
    }
}
