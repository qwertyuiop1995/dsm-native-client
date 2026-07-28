package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import java.io.IOException
import java.security.MessageDigest
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okio.Buffer

internal enum class QuickConnectEndpointKind {
    LOCAL,
    EXTERNAL,
    RELAY,
}

internal data class QuickConnectEndpoint(
    val host: String,
    val port: Int,
    val kind: QuickConnectEndpointKind,
)

internal data class QuickConnectRelayDescriptor(
    val endpoint: QuickConnectEndpoint,
    val serverId: String,
    val pingPongPath: String,
)

/**
 * QuickConnect 的受限解析器。
 *
 * `get_server_info` 与 `request_tunnel` 来自 Synology QuickConnect 当前客户端契约，
 * 属于未公开的内部 API。发送登录信息前必须限制官方域名并校验中继 NAS 身份。
 */
internal class DsmQuickConnectResolver(
    private val http: OkHttpClient = OkHttpClient.Builder()
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(true)
        .build(),
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    private val controlUrls: List<String> = if (
        Locale.getDefault().country.equals("CN", ignoreCase = true)
    ) {
        listOf(CHINA_CONTROL_URL, GLOBAL_CONTROL_URL)
    } else {
        listOf(GLOBAL_CONTROL_URL, CHINA_CONTROL_URL)
    }

    suspend fun resolve(id: String): List<QuickConnectEndpoint> {
        validateId(id)
        var lastFailure = serviceUnavailable()
        for (controlUrl in controlUrls) {
            try {
                return decodeEndpoints(
                    send("get_server_info", stopWhenSuccess = false, id, controlUrl)
                )
            } catch (error: CancellationException) {
                throw error
            } catch (error: DsmFailure) {
                lastFailure = error
            }
        }
        throw lastFailure
    }

    suspend fun requestRelay(id: String): QuickConnectEndpoint {
        validateId(id)
        val controlUrl = resolveControlUrl(id)
        var lastFailure = relayUnavailable()
        repeat(3) { attempt ->
            try {
                val descriptor = decodeRelayDescriptor(
                    send("request_tunnel", stopWhenSuccess = true, id, controlUrl),
                    id,
                )
                verifyRelay(descriptor)
                return descriptor.endpoint
            } catch (error: CancellationException) {
                throw error
            } catch (error: DsmFailure) {
                if (error.message == RELAY_DISABLED_MESSAGE ||
                    error.message == RELAY_IDENTITY_MISMATCH_MESSAGE
                ) {
                    throw error
                }
                lastFailure = error
                if (attempt < 2) delay((attempt + 1) * 1_000L)
            }
        }
        throw lastFailure
    }

    private suspend fun resolveControlUrl(id: String): String {
        var lastFailure = serviceUnavailable()
        for (controlUrl in controlUrls) {
            try {
                val host = decodeControlHost(
                    send("get_server_info", stopWhenSuccess = false, id, controlUrl)
                )
                return "https://$host/Serv.php"
            } catch (error: CancellationException) {
                throw error
            } catch (error: DsmFailure) {
                lastFailure = error
            }
        }
        throw lastFailure
    }

    private suspend fun send(
        command: String,
        stopWhenSuccess: Boolean,
        serverId: String,
        controlUrl: String,
    ): JsonArray {
        val body = buildJsonArray {
            add(
                buildJsonObject {
                    put("version", 1)
                    put("command", command)
                    put("stop_when_error", false)
                    put("stop_when_success", stopWhenSuccess)
                    put("id", "mainapp_https")
                    put("serverID", serverId)
                    put("is_gofile", false)
                    put("path", "")
                }
            )
        }.toString().toRequestBody(JSON_MEDIA_TYPE)
        val request = Request.Builder()
            .url(controlUrl)
            .post(body)
            .header("Accept", "application/json")
            .header("User-Agent", "LanStash-Android/0.1")
            .build()
        val timeout = if (command == "request_tunnel") 30_000L else 15_000L
        return try {
            withTimeout(timeout) {
                http.newCall(request).await().use { response ->
                    if (!response.isSuccessful) throw serviceUnavailable()
                    val bytes = response.readBoundedBody(::invalidResponse)
                    runCatching { json.parseToJsonElement(bytes.decodeToString()) as JsonArray }
                        .getOrElse { throw invalidResponse() }
                }
            }
        } catch (_: TimeoutCancellationException) {
            throw serviceUnavailable()
        }
    }

    private suspend fun verifyRelay(descriptor: QuickConnectRelayDescriptor) {
        val path = descriptor.pingPongPath
        if (!path.startsWith('/') ||
            path.length > 2_048 ||
            "://" in path ||
            '#' in path
        ) {
            throw invalidResponse()
        }
        val expectedId = MessageDigest.getInstance("MD5")
            .digest(descriptor.serverId.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        val url = "https://${descriptor.endpoint.host}$path"

        repeat(6) { attempt ->
            try {
                val request = Request.Builder()
                    .url(url)
                    .get()
                    .header("Accept", "application/json")
                    .header("User-Agent", "LanStash-Android/0.1")
                    .build()
                val responseJson = try {
                    withTimeout(15_000L) {
                        http.newCall(request).await().use { response ->
                            if (!response.isSuccessful) throw relayUnavailable()
                            val bytes = response.readBoundedBody(::relayUnavailable)
                            runCatching {
                                json.parseToJsonElement(bytes.decodeToString()).jsonObject
                            }.getOrElse { throw relayUnavailable() }
                        }
                    }
                } catch (_: TimeoutCancellationException) {
                    throw relayUnavailable()
                }
                val actualId = responseJson.string("ezid")?.lowercase()
                if (actualId != expectedId) throw relayIdentityMismatch()
                return
            } catch (error: CancellationException) {
                throw error
            } catch (error: DsmFailure) {
                if (error.message == RELAY_IDENTITY_MISMATCH_MESSAGE) throw error
                if (attempt < 5) delay(1_000L)
            }
        }
        throw relayUnavailable()
    }

    internal fun decodeEndpoints(responses: JsonArray): List<QuickConnectEndpoint> {
        val response = successfulResponse(responses)
        if (response.objectValue("server")?.string("ds_state")?.uppercase() != "CONNECTED") {
            throw DsmFailure(
                null,
                "QuickConnect 找到了这台 NAS，但设备目前不在线",
                "确认 NAS 已开机并联网后重试。",
            )
        }
        val service = response.objectValue("service") ?: throw noDirectRoute()
        val port = service.int("port")?.takeIf { it in 1..65_535 } ?: throw noDirectRoute()
        val smartDns = response.objectValue("smartdns") ?: throw noDirectRoute()
        val seen = mutableSetOf<String>()
        val local = smartDns.arrayValue("lan").mapNotNull { element ->
            val host = runCatching { element.jsonObject }.getOrNull()?.string("host")
                ?: runCatching { element.toString().trim('"') }.getOrNull()
            trustedDirectEndpoint(host, port, QuickConnectEndpointKind.LOCAL, seen)
        }
        val external = listOfNotNull(smartDns.string("host")).mapNotNull { host ->
            trustedDirectEndpoint(host, port, QuickConnectEndpointKind.EXTERNAL, seen)
        }
        return (local + external).ifEmpty { throw noDirectRoute() }
    }

    internal fun decodeControlHost(responses: JsonArray): String {
        val response = successfulResponse(responses)
        if (response.objectValue("server")?.string("ds_state")?.uppercase() != "CONNECTED") {
            throw invalidResponse()
        }
        val host = response.objectValue("env")?.string("control_host")?.lowercase()
            ?: throw invalidResponse()
        if (!isTrustedControlHost(host)) throw invalidResponse()
        return host
    }

    internal fun decodeRelayDescriptor(
        responses: JsonArray,
        quickConnectId: String,
    ): QuickConnectRelayDescriptor {
        if (responses.any { element ->
                runCatching { element.jsonObject.int("errno") == 19 }.getOrDefault(false)
            }
        ) {
            throw DsmFailure(
                null,
                RELAY_DISABLED_MESSAGE,
                "请在 DSM 的 QuickConnect 高级设置中开启中继后重试。",
            )
        }
        val response = successfulResponse(responses)
        val service = response.objectValue("service") ?: throw relayUnavailable()
        if (service.string("relay_ip").isNullOrBlank()) throw relayUnavailable()
        service.int("relay_port")?.takeIf { it in 1..65_535 } ?: throw relayUnavailable()
        val server = response.objectValue("server") ?: throw relayUnavailable()
        val serverId = server.string("serverID")?.takeIf(String::isNotBlank)
            ?: throw relayUnavailable()
        val environment = response.objectValue("env") ?: throw relayUnavailable()
        val region = environment.string("relay_region")?.lowercase()
            ?.takeIf(::isValidHostLabel)
            ?: throw relayUnavailable()
        val controlHost = environment.string("control_host")?.lowercase()
            ?.takeIf(::isTrustedControlHost)
            ?: throw relayUnavailable()
        val topDomain = if (controlHost.endsWith(".quickconnect.cn")) "cn" else "to"
        val host = "${quickConnectId.lowercase()}.$region.quickconnect.$topDomain"
        if (!isTrustedRelayHost(host)) throw invalidResponse()
        return QuickConnectRelayDescriptor(
            endpoint = QuickConnectEndpoint(host, 443, QuickConnectEndpointKind.RELAY),
            serverId = serverId,
            pingPongPath = server.string("pingpong_path")
                ?: "/webman/pingpong.cgi?action=cors&quickconnect=true",
        )
    }

    private fun successfulResponse(responses: JsonArray): JsonObject =
        responses.mapNotNull { runCatching { it.jsonObject }.getOrNull() }
            .firstOrNull { it.int("errno") == 0 }
            ?: throw DsmFailure(
                null,
                "没有找到这个 QuickConnect ID",
                "请检查拼写和 NAS 中的 QuickConnect 设置。",
            )

    private fun trustedDirectEndpoint(
        rawHost: String?,
        port: Int,
        kind: QuickConnectEndpointKind,
        seen: MutableSet<String>,
    ): QuickConnectEndpoint? {
        val host = rawHost?.lowercase()?.takeIf(::isTrustedDirectHost) ?: return null
        if (!seen.add(host)) return null
        return QuickConnectEndpoint(host, port, kind)
    }

    private fun validateId(id: String) {
        if (!NasAddressParser.isPotentialQuickConnectId(id)) {
            throw DsmFailure(
                null,
                "无法识别这个 QuickConnect ID",
                "请检查拼写后重试。",
            )
        }
    }

    private fun isTrustedDirectHost(host: String): Boolean {
        val labels = host.split('.')
        return labels.size >= 4 &&
            labels[labels.lastIndex - 2] == "direct" &&
            labels[labels.lastIndex - 1] == "quickconnect" &&
            labels.last() in setOf("to", "cn") &&
            labels.all(::isValidHostLabel)
    }

    internal fun isTrustedRelayHost(host: String): Boolean {
        val labels = host.lowercase().split('.')
        return labels.size == 4 &&
            labels[2] == "quickconnect" &&
            labels[3] in setOf("to", "cn") &&
            isValidHostLabel(labels[0]) &&
            isValidHostLabel(labels[1])
    }

    private fun isTrustedControlHost(host: String): Boolean =
        (host.endsWith(".quickconnect.to") || host.endsWith(".quickconnect.cn")) &&
            host.split('.').all(::isValidHostLabel)

    private fun isValidHostLabel(value: String): Boolean =
        value.length in 1..63 &&
            !value.startsWith('-') &&
            !value.endsWith('-') &&
            value.all { character ->
                character in 'a'..'z' ||
                    character in 'A'..'Z' ||
                    character in '0'..'9' ||
                    character == '-'
            }

    private fun noDirectRoute() = DsmFailure(
        null,
        "QuickConnect 没有提供可用的直接连接",
        "岚仓将继续尝试安全中继。",
    )

    private fun serviceUnavailable() = DsmFailure(
        null,
        "QuickConnect 暂时没有响应",
        "请稍后重试。",
    )

    private fun invalidResponse() = DsmFailure(
        null,
        "QuickConnect 返回的信息无法读取",
        "请稍后重试。",
    )

    private fun relayUnavailable() = DsmFailure(
        null,
        "QuickConnect 暂时无法建立中继连接",
        "请稍后重试。",
    )

    private fun relayIdentityMismatch() = DsmFailure(
        null,
        RELAY_IDENTITY_MISMATCH_MESSAGE,
        "为保护登录信息，岚仓已停止连接。",
    )

    private fun Response.readBoundedBody(failure: () -> DsmFailure): ByteArray {
        val responseBody = body ?: return byteArrayOf()
        val contentLength = responseBody.contentLength()
        if (contentLength > MAXIMUM_RESPONSE_BYTES) throw failure()

        val source = responseBody.source()
        val buffer = Buffer()
        var totalBytes = 0L
        while (true) {
            val remaining = MAXIMUM_RESPONSE_BYTES + 1L - totalBytes
            if (remaining <= 0L) throw failure()
            val read = source.read(buffer, minOf(8_192L, remaining))
            if (read == -1L) break
            totalBytes += read
        }
        if (totalBytes > MAXIMUM_RESPONSE_BYTES) throw failure()
        return buffer.readByteArray()
    }

    private suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
        continuation.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                if (!continuation.isCancelled) {
                    continuation.resumeWithException(serviceUnavailable())
                }
            }

            override fun onResponse(call: Call, response: Response) {
                continuation.resume(response)
            }
        })
    }

    private companion object {
        const val MAXIMUM_RESPONSE_BYTES = 1_024 * 1_024L
        const val GLOBAL_CONTROL_URL = "https://global.quickconnect.to/Serv.php"
        const val CHINA_CONTROL_URL = "https://global.quickconnect.cn/Serv.php"
        const val RELAY_DISABLED_MESSAGE = "这台 NAS 没有开启 QuickConnect 中继"
        const val RELAY_IDENTITY_MISMATCH_MESSAGE = "QuickConnect 返回的连接无法确认属于这台 NAS"
        val JSON_MEDIA_TYPE = "application/json".toMediaType()
    }
}
