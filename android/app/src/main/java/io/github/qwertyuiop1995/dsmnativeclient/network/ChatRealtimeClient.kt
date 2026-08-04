package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString

internal enum class ChatSocketAction { ENGINE_OPENED, NAMESPACE_CONNECTED, CONTENT_CHANGED, REPLY_PONG, DISCONNECTED, IGNORED }

internal fun chatSocketActions(frame: String): List<ChatSocketAction> =
    frame.split('\u001E').filter(String::isNotEmpty).map { packet ->
        when {
            packet.startsWith("0") -> ChatSocketAction.ENGINE_OPENED
            packet == "2" -> ChatSocketAction.REPLY_PONG
            packet == "1" || packet.startsWith("41") || packet.startsWith("44") -> ChatSocketAction.DISCONNECTED
            packet.startsWith("40") -> ChatSocketAction.NAMESPACE_CONNECTED
            packet.startsWith("42") -> ChatSocketAction.CONTENT_CHANGED
            else -> ChatSocketAction.IGNORED
        }
    }

internal fun chatSocketRequest(
    endpoint: String,
    session: DsmSession,
    engineVersion: Int,
): Request {
    require(engineVersion in setOf(3, 4))
    val base = endpoint.toHttpUrl()
    require(base.isHttps)
    val path = base.encodedPath.trimEnd('/') + "/sc/socket.io/"
    val url = base.newBuilder()
        .encodedPath(path)
        .query(null)
        .addQueryParameter("EIO", engineVersion.toString())
        .addQueryParameter("transport", "websocket")
        .build()
    val origin = base.newBuilder().encodedPath("/").query(null).fragment(null).build().toString().trimEnd('/')
    return Request.Builder()
        .url(url)
        .header("Cookie", "id=${session.sid}")
        .header("Origin", origin)
        .apply {
            session.synoToken?.takeIf(String::isNotBlank)?.let { header("X-SYNO-TOKEN", it) }
        }
        .build()
}

/** Socket.IO 事件只触发 API 回读，不解析或记录内部事件载荷。 */
class ChatRealtimeClient internal constructor(
    private val api: DsmApiClient,
    private val profile: NasProfile,
    private val session: DsmSession,
    private val onConnectionChanged: (Boolean) -> Unit,
    private val onContentChanged: () -> Unit,
) {
    private var job: Job? = null
    @Volatile private var socket: WebSocket? = null
    private var preferredEngineVersion = 4

    fun start(scope: CoroutineScope) {
        if (job != null) return
        job = scope.launch {
            var retryMillis = 1_000L
            while (isActive) {
                var connectedInRound = false
                for (version in listOf(preferredEngineVersion, if (preferredEngineVersion == 4) 3 else 4)) {
                    if (!isActive) return@launch
                    val connected = runCatching { connect(version) }.getOrElse {
                        if (it is CancellationException) throw it
                        false
                    }
                    if (connected) {
                        connectedInRound = true
                        preferredEngineVersion = version
                        retryMillis = 1_000L
                        break
                    }
                }
                onConnectionChanged(false)
                if (connectedInRound) retryMillis = 1_000L
                delay(retryMillis)
                retryMillis = (retryMillis * 2).coerceAtMost(30_000L)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        socket?.close(1001, null)
        socket = null
        onConnectionChanged(false)
    }

    private suspend fun connect(engineVersion: Int): Boolean {
        val finished = CompletableDeferred<Boolean>()
        val connected = AtomicBoolean(false)
        var engineOpened = false
        var namespaceConnected = false
        val request = chatSocketRequest(api.endpoint(profile), session, engineVersion)
        val webSocket = api.openWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                if (text.toByteArray().size > MAX_FRAME_BYTES) {
                    webSocket.close(1009, null)
                    finished.complete(connected.get())
                    return
                }
                val packets = text.split('\u001E').filter(String::isNotEmpty)
                packets.zip(chatSocketActions(text)).forEach { (packet, action) ->
                    when (action) {
                        ChatSocketAction.ENGINE_OPENED -> {
                            if (!validHandshake(packet)) {
                                webSocket.close(1002, null)
                                finished.complete(false)
                            } else {
                                engineOpened = true
                                webSocket.send("40")
                            }
                        }
                        ChatSocketAction.NAMESPACE_CONNECTED -> if (engineOpened) {
                            namespaceConnected = true
                            connected.set(true)
                            onConnectionChanged(true)
                        }
                        ChatSocketAction.CONTENT_CHANGED -> if (namespaceConnected) onContentChanged()
                        ChatSocketAction.REPLY_PONG -> webSocket.send("3")
                        ChatSocketAction.DISCONNECTED -> finished.complete(connected.get())
                        ChatSocketAction.IGNORED -> Unit
                    }
                }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                if (bytes.size > MAX_FRAME_BYTES) {
                    webSocket.close(1009, null)
                    finished.complete(connected.get())
                } else {
                    onMessage(webSocket, bytes.utf8())
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                finished.complete(connected.get())
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                finished.complete(connected.get())
            }
        })
        socket = webSocket
        return try {
            withTimeout(20_000L) { finished.await() }
        } finally {
            if (socket === webSocket) socket = null
            webSocket.close(1001, null)
        }
    }

    private fun validHandshake(packet: String): Boolean = runCatching {
        if (!packet.startsWith('0')) return false
        val objectValue = Json.parseToJsonElement(packet.drop(1)).jsonObject
        val sid = objectValue["sid"]?.jsonPrimitive?.content.orEmpty()
        sid.isNotEmpty() && sid.length <= 512
    }.getOrDefault(false)

    private companion object {
        const val MAX_FRAME_BYTES = 1024 * 1024
    }
}
