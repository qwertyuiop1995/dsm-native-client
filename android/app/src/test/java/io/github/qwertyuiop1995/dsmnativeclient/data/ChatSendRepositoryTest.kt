package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatDeliveryState
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.runBlocking
import okhttp3.FormBody
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatSendRepositoryTest {
    @Test
    fun `文字发送只提交会话和正文且不发送客户端请求ID`() = runBlocking {
        val transport = ChatSendInterceptor(body(successPost()))

        val message = repository(transport).sendChatTextMessage(
            "synthetic-channel", " Synthetic message ", "request-1",
        )

        assertEquals("post-1", message.id)
        assertEquals("你好 👋", message.body)
        assertEquals(ChatDeliveryState.SENT, message.deliveryState)
        RequestFixtureAssertions.assertRequest(
            transport.requests.single(),
            "chat/send-text/synthetic-message/request.json",
        )
        val fields = transport.fields().single()
        assertEquals("SYNO.Chat.Post", fields["api"])
        assertEquals("create", fields["method"])
        assertEquals("5", fields["version"])
        assertEquals("synthetic-channel", fields["channel_id"])
        assertEquals("Synthetic message", fields["message"])
        assertTrue(fields.keys.none { it.contains("request", ignoreCase = true) })
    }

    @Test
    fun `同一客户端请求成功后复用内存结果而不重复发送`() = runBlocking {
        val transport = ChatSendInterceptor(body(successPost()))
        val repo = repository(transport)

        val first = repo.sendChatTextMessage("channel-1", "hello", "request-1")
        val second = repo.sendChatTextMessage("channel-1", "hello", "request-1")

        assertEquals(first, second)
        assertEquals(1, transport.requests.size)
    }

    @Test
    fun `提交断线不会在Repository内自动重放`() = runBlocking {
        val transport = ChatSendInterceptor(
            failure(IOException("synthetic disconnect")),
            body("""{"success":true,"data":{"total":0,"posts":[]}}"""),
        )

        assertThrows {
            repository(transport).sendChatTextMessage("channel-1", "hello", "request-1")
        }

        assertEquals(2, transport.requests.size)
        assertEquals(1, transport.fields().count { it["method"] == "create" })
    }

    @Test
    fun `空正文和超长正文均零请求拒绝`() = runBlocking {
        val transport = ChatSendInterceptor()
        val repo = repository(transport)

        assertThrows { repo.sendChatTextMessage("channel-1", "  ", "request-1") }
        assertThrows {
            repo.sendChatTextMessage("channel-1", "x".repeat(10_001), "request-2")
        }
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `运行时能力不覆盖已确认的v5时零请求拒绝`() = runBlocking {
        val transport = ChatSendInterceptor()

        assertThrows {
            repository(transport, maximumVersion = 4)
                .sendChatTextMessage("channel-1", "hello", "request-1")
        }

        assertTrue(transport.requests.isEmpty())
    }

    private fun repository(
        interceptor: ChatSendInterceptor,
        maximumVersion: Int = 5,
    ) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build()),
        mapOf(
            "SYNO.Chat.Post" to ApiCapability(
                "SYNO.Chat.Post",
                "entry.cgi",
                1,
                maximumVersion,
            ),
        ),
    )

    private fun successPost() = """{"success":true,"data":{
        "post_id":"post-1","channel_id":"channel-1","message":"你好 👋",
        "create_at":1700000000000
    }}"""
    private fun body(value: String) = ChatSendStep.Body(value)
    private fun failure(error: IOException) = ChatSendStep.Failure(error)

    private suspend fun assertThrows(block: suspend () -> Unit) {
        var thrown = false
        try {
            block()
        } catch (_: Throwable) {
            thrown = true
        }
        assertTrue(thrown)
    }
}

private sealed interface ChatSendStep {
    data class Body(val value: String) : ChatSendStep
    data class Failure(val error: IOException) : ChatSendStep
}

private class ChatSendInterceptor(vararg steps: ChatSendStep) : Interceptor {
    private val queue = ArrayDeque(steps.toList())
    val requests = CopyOnWriteArrayList<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return when (val step = queue.removeFirstOrNull() ?: error("Unexpected request")) {
            is ChatSendStep.Failure -> throw step.error
            is ChatSendStep.Body -> Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(step.value.toResponseBody("application/json".toMediaType()))
                .build()
        }
    }

    fun fields(): List<Map<String, String>> = requests.map { request ->
        val form = request.body as? FormBody
        buildMap { if (form != null) repeat(form.size) { put(form.name(it), form.value(it)) } }
    }
}
