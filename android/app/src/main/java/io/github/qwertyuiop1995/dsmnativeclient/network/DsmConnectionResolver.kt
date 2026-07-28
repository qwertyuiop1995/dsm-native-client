package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import kotlinx.coroutines.CancellationException

internal data class DiscoveredConnection(
    val profile: NasProfile,
    val capabilities: Map<String, ApiCapability>,
)

/**
 * 登录前只使用不含凭据的能力发现探测连接候选。
 * 找到可信连接后，调用方才可以提交账号、密码和验证码。
 */
internal class DsmConnectionResolver(
    private val api: DsmApiClient,
    private val quickConnect: DsmQuickConnectResolver = DsmQuickConnectResolver(),
) {
    suspend fun discover(
        profile: NasProfile,
        onStatus: (String) -> Unit = {},
    ): DiscoveredConnection {
        val parsed = NasAddressParser.parse(profile.address, profile.port)
        if (parsed.kind == NasAddressKind.DIRECT) {
            onStatus("正在连接 NAS…")
            val connectionProfile = profile.copy(
                address = "https://${parsed.host}",
                port = parsed.port,
            )
            return DiscoveredConnection(connectionProfile, api.discover(connectionProfile))
        }

        onStatus("正在通过 QuickConnect 查找 NAS…")
        val endpoints = try {
            quickConnect.resolve(parsed.host)
        } catch (error: DsmFailure) {
            if (error.message == "QuickConnect 没有提供可用的直接连接") {
                emptyList()
            } else {
                throw error
            }
        }
        var lastDirectFailure: DsmFailure? = null
        for (endpoint in endpoints) {
            onStatus(
                if (endpoint.kind == QuickConnectEndpointKind.LOCAL) {
                    "正在尝试局域网连接…"
                } else {
                    "正在尝试外网直接连接…"
                }
            )
            val connectionProfile = profile.copy(
                address = "https://${endpoint.host}",
                port = profile.port ?: endpoint.port,
            )
            try {
                return DiscoveredConnection(connectionProfile, api.discover(connectionProfile))
            } catch (error: CancellationException) {
                throw error
            } catch (error: DsmFailure) {
                lastDirectFailure = error
            }
        }

        onStatus("正在建立 QuickConnect 安全中继…")
        return try {
            val relay = quickConnect.requestRelay(parsed.host)
            val connectionProfile = profile.copy(
                address = "https://${relay.host}",
                port = relay.port,
            )
            DiscoveredConnection(connectionProfile, api.discover(connectionProfile))
        } catch (error: CancellationException) {
            throw error
        } catch (error: DsmFailure) {
            throw if (error.message == "QuickConnect 暂时无法建立中继连接") {
                lastDirectFailure ?: error
            } else {
                error
            }
        }
    }
}
