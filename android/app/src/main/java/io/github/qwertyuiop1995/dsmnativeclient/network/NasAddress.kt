package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import java.net.URI

internal enum class NasAddressKind {
    DIRECT,
    QUICK_CONNECT,
}

internal data class ParsedNasAddress(
    val host: String,
    val port: Int,
    val kind: NasAddressKind,
    val hasExplicitPort: Boolean,
)

/**
 * 解析用户保存的 NAS 地址。
 *
 * QuickConnect ID 只在连接期间解析为临时候选地址，不能覆盖用户保存的原始 ID。
 */
internal object NasAddressParser {
    fun parse(input: String, portOverride: Int? = null): ParsedNasAddress {
        if (portOverride != null && portOverride !in 1..65_535) {
            throw invalidAddress()
        }
        val trimmed = input.trim()
        if (trimmed.isEmpty()) {
            throw DsmFailure(
                null,
                "NAS address or QuickConnect ID is required",
                "Enter the address and connect again.",
                kind = DsmErrorKind.INVALID_ADDRESS,
            )
        }

        val hasExplicitScheme = "://" in trimmed
        val uri = runCatching {
            URI(if (hasExplicitScheme) trimmed else "https://$trimmed")
        }.getOrElse {
            throw invalidAddress()
        }
        if (uri.userInfo != null || uri.fragment != null || uri.query != null) {
            throw invalidAddress()
        }

        val host = uri.host?.lowercase()?.takeIf(String::isNotBlank)
            ?: throw invalidAddress()
        quickConnectId(host, uri.path.orEmpty())?.let { id ->
            if (!isPotentialQuickConnectId(id)) throw invalidAddress()
            return ParsedNasAddress(
                host = id,
                port = portOverride ?: DEFAULT_DSM_HTTPS_PORT,
                kind = NasAddressKind.QUICK_CONNECT,
                hasExplicitPort = portOverride != null,
            )
        }

        if (uri.scheme?.lowercase() != "https") {
            throw DsmFailure(
                null,
                "The address is not secure",
                "Use an HTTPS address to protect sign-in information.",
                kind = DsmErrorKind.INSECURE_ADDRESS,
            )
        }
        if (isPotentialQuickConnectId(host)) {
            return ParsedNasAddress(
                host = host,
                port = portOverride ?: DEFAULT_DSM_HTTPS_PORT,
                kind = NasAddressKind.QUICK_CONNECT,
                hasExplicitPort = portOverride != null,
            )
        }

        val explicitUriPort = uri.port.takeIf { it > 0 }
        val port = portOverride
            ?: explicitUriPort
            ?: if (hasExplicitScheme) DEFAULT_HTTPS_PORT else DEFAULT_DSM_HTTPS_PORT
        if (port !in 1..65_535) throw invalidAddress()
        return ParsedNasAddress(
            host = host,
            port = port,
            kind = NasAddressKind.DIRECT,
            hasExplicitPort = portOverride != null || explicitUriPort != null,
        )
    }

    fun isPotentialQuickConnectId(value: String): Boolean {
        if (value.length !in 1..64 ||
            '.' in value ||
            ':' in value ||
            value.startsWith('-') ||
            value.endsWith('-')
        ) {
            return false
        }
        return value.all(::isAsciiHostCharacter)
    }

    private fun quickConnectId(host: String, path: String): String? {
        if (host in QUICK_CONNECT_PORTALS) {
            return path.split('/').firstOrNull(String::isNotBlank)?.lowercase()
        }
        return QUICK_CONNECT_PORTALS.firstNotNullOfOrNull { portal ->
            val suffix = ".$portal"
            host.takeIf { it.endsWith(suffix) && it.count { character -> character == '.' } == 2 }
                ?.removeSuffix(suffix)
                ?.lowercase()
        }
    }

    private fun invalidAddress() = DsmFailure(
        null,
        "The address is invalid",
        "Enter a QuickConnect ID, NAS IP address, domain, or full HTTPS address.",
        kind = DsmErrorKind.INVALID_ADDRESS,
    )

    private const val DEFAULT_HTTPS_PORT = 443
    private const val DEFAULT_DSM_HTTPS_PORT = 5_001
    private val QUICK_CONNECT_PORTALS = setOf("quickconnect.to", "quickconnect.cn")

    private fun isAsciiHostCharacter(value: Char): Boolean =
        value in 'a'..'z' || value in 'A'..'Z' || value in '0'..'9' || value == '-'
}
