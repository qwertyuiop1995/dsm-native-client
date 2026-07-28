package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class DsmApiClientTest {
    private val client = DsmApiClient()

    @Test
    fun `地址缺少协议时默认使用 HTTPS`() {
        val endpoint = client.endpoint(profile(address = "nas.example.com"))
        assertEquals("https://nas.example.com", endpoint)
    }

    @Test
    fun `用户指定端口优先于地址中的端口`() {
        val endpoint = client.endpoint(
            profile(address = "https://nas.example.com:5001/dsm", port = 8443)
        )
        assertEquals("https://nas.example.com:8443/dsm", endpoint)
    }

    @Test
    fun `正式连接拒绝明文 HTTP`() {
        assertThrows(DsmFailure::class.java) {
            client.endpoint(profile(address = "http://nas.example.com"))
        }
    }

    @Test
    fun `非法地址给出可恢复错误`() {
        val failure = assertThrows(DsmFailure::class.java) {
            client.endpoint(profile(address = "https://"))
        }
        assertEquals(DsmErrorKind.INVALID_ADDRESS, failure.kind)
    }

    private fun profile(address: String, port: Int? = null) = NasProfile(
        id = "test-profile",
        name = "测试 NAS",
        address = address,
        username = "tester",
        port = port,
    )
}
