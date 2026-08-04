package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatRealtimeClientTest {
    @Test
    fun `解析EngineIO与SocketIO控制帧`() {
        assertEquals(
            listOf(ChatSocketAction.ENGINE_OPENED),
            chatSocketActions("""0{"sid":"synthetic","pingInterval":25000,"pingTimeout":20000}"""),
        )
        assertEquals(listOf(ChatSocketAction.NAMESPACE_CONNECTED), chatSocketActions("40"))
        assertEquals(listOf(ChatSocketAction.REPLY_PONG), chatSocketActions("2"))
        assertEquals(listOf(ChatSocketAction.DISCONNECTED), chatSocketActions("41"))
    }

    @Test
    fun `消息事件只上报内容变化且支持复合帧`() {
        val frame = """42["post_create",{"message":"not exposed"}]""" + '\u001E' +
            """42["channel_update",{"id":"synthetic"}]"""

        assertEquals(
            listOf(ChatSocketAction.CONTENT_CHANGED, ChatSocketAction.CONTENT_CHANGED),
            chatSocketActions(frame),
        )
        assertEquals(listOf(ChatSocketAction.IGNORED), chatSocketActions("""43["ack"]"""))
    }

    @Test
    fun `握手请求只在请求头携带会话材料`() {
        val request = chatSocketRequest(
            "https://nas.example.invalid:5001/base",
            DsmSession("profile", "synthetic-session", "synthetic-token"),
            4,
        )

        assertEquals("/base/sc/socket.io/", request.url.encodedPath)
        assertEquals("4", request.url.queryParameter("EIO"))
        assertEquals("websocket", request.url.queryParameter("transport"))
        assertFalse(request.url.queryParameterNames.any {
            it.equals("_sid", true) || it.contains("token", true)
        })
        assertEquals("id=synthetic-session", request.header("Cookie"))
        assertEquals("synthetic-token", request.header("X-SYNO-TOKEN"))
        assertEquals("https://nas.example.invalid:5001", request.header("Origin"))
    }

    @Test
    fun `握手只接受已支持Engine版本与HTTPS端点`() {
        assertThrows { chatSocketRequest("http://nas.example.invalid", DsmSession("p", "s"), 4) }
        assertThrows { chatSocketRequest("https://nas.example.invalid", DsmSession("p", "s"), 2) }
    }

    private fun assertThrows(block: () -> Unit) {
        var thrown = false
        try {
            block()
        } catch (_: Throwable) {
            thrown = true
        }
        assertTrue(thrown)
    }
}
