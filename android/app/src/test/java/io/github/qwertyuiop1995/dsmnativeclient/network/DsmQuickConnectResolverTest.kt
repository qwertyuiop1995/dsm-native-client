package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DsmQuickConnectResolverTest {
    private val json = Json { ignoreUnknownKeys = true }
    private val resolver = DsmQuickConnectResolver()

    @Test
    fun `只接受官方直连域名并保持局域网优先`() {
        val endpoints = resolver.decodeEndpoints(
            responses(
                """
                [{
                  "errno": 0,
                  "server": {"ds_state": "CONNECTED"},
                  "service": {"port": 5001},
                  "smartdns": {
                    "lan": [
                      "192-168-1-20.family-nas.direct.quickconnect.to",
                      "malicious.example.com"
                    ],
                    "host": "family-nas.direct.quickconnect.to"
                  }
                }]
                """
            )
        )

        assertEquals(2, endpoints.size)
        assertEquals(QuickConnectEndpointKind.LOCAL, endpoints[0].kind)
        assertEquals(QuickConnectEndpointKind.EXTERNAL, endpoints[1].kind)
        assertTrue(endpoints.all { it.host.endsWith(".direct.quickconnect.to") })
    }

    @Test
    fun `没有可信直连地址时拒绝候选`() {
        assertThrows(DsmFailure::class.java) {
            resolver.decodeEndpoints(
                responses(
                    """
                    [{
                      "errno": 0,
                      "server": {"ds_state": "CONNECTED"},
                      "service": {"port": 5001},
                      "smartdns": {"lan": [], "host": "malicious.example.com"}
                    }]
                    """
                )
            )
        }
    }

    @Test
    fun `中继地址只能来自官方域名且外部端口固定为 443`() {
        val descriptor = resolver.decodeRelayDescriptor(
            responses(
                """
                [{
                  "errno": 0,
                  "server": {
                    "serverID": "server-identity",
                    "pingpong_path": "/webman/pingpong.cgi?action=cors"
                  },
                  "service": {"relay_ip": "203.0.113.10", "relay_port": 12345},
                  "env": {
                    "relay_region": "r1",
                    "control_host": "global.quickconnect.to"
                  }
                }]
                """
            ),
            "family-nas",
        )

        assertEquals("family-nas.r1.quickconnect.to", descriptor.endpoint.host)
        assertEquals(443, descriptor.endpoint.port)
        assertEquals(QuickConnectEndpointKind.RELAY, descriptor.endpoint.kind)
        assertTrue(resolver.isTrustedRelayHost(descriptor.endpoint.host))
        assertFalse(resolver.isTrustedRelayHost("family-nas.r1.quickconnect.to.evil.example"))
        assertFalse(resolver.isTrustedRelayHost("family-nas.direct.quickconnect.to"))
        assertTrue(isTrustedQuickConnectRelayHost("family-nas.r1.quickconnect.cn"))
    }

    @Test
    fun `拒绝非官方控制主机`() {
        assertThrows(DsmFailure::class.java) {
            resolver.decodeControlHost(
                responses(
                    """
                    [{
                      "errno": 0,
                      "server": {"ds_state": "CONNECTED"},
                      "env": {"control_host": "quickconnect.to.evil.example"}
                    }]
                    """
                )
            )
        }
    }

    private fun responses(value: String): JsonArray =
        json.parseToJsonElement(value.trimIndent()) as JsonArray
}
