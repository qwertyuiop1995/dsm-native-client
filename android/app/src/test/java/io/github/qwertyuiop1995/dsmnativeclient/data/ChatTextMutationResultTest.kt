package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
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
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatTextMutationResultTest {
    @Test
    fun `提交断线但近期消息回读匹配时确认成功且不重放`() = runBlocking {
        val transport = ScriptedChatTextInterceptor(
            IOException("synthetic disconnect"),
            recentPosts("hello"),
        )

        val outcome = repository(transport).sendChatTextMessageResult("channel-1", "hello", "request-1")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals("post-readback", outcome.message?.id)
        assertEquals(1, transport.methods().count { it == "create" })
        assertEquals(1, transport.methods().count { it == "list" })
    }

    @Test
    fun `提交断线且回读无匹配消息时保持未确认`() = runBlocking {
        val transport = ScriptedChatTextInterceptor(
            IOException("synthetic disconnect"),
            emptyPosts(),
        )

        val outcome = repository(transport).sendChatTextMessageResult("channel-1", "hello", "request-1")

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertEquals(1, outcome.result.counts.unknown)
        assertTrue(outcome.result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "create" })
    }

    @Test
    fun `响应缺少消息ID但回读匹配时确认成功`() = runBlocking {
        val transport = ScriptedChatTextInterceptor(
            """{"success":true,"data":{}}""",
            recentPosts("hello"),
        )

        val outcome = repository(transport).sendChatTextMessageResult("channel-1", "hello", "request-1")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals("post-readback", outcome.message?.id)
    }

    @Test
    fun `权限拒绝后回读无消息时明确报告权限不足`() = runBlocking {
        val transport = ScriptedChatTextInterceptor(
            """{"success":false,"error":{"code":105}}""",
            emptyPosts(),
        )

        val outcome = repository(transport).sendChatTextMessageResult("channel-1", "hello", "request-1")

        assertEquals(MutationResultStatus.PERMISSION_DENIED, outcome.result.status)
        assertEquals(MutationErrorCategory.PERMISSION, outcome.result.errorCategory)
        assertEquals(1, transport.methods().count { it == "create" })
    }

    @Test
    fun `断线后回读也失败时保持未确认`() = runBlocking {
        val transport = ScriptedChatTextInterceptor(
            IOException("synthetic disconnect"),
            IOException("synthetic readback failure"),
        )

        val outcome = repository(transport).sendChatTextMessageResult("channel-1", "hello", "request-1")

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "create" })
    }

    @Test
    fun `非法输入不支持能力和提交前取消均零请求关闭`() {
        val invalidTransport = ScriptedChatTextInterceptor()
        runBlocking {
            val invalid = repository(invalidTransport)
                .sendChatTextMessageResult("channel-1", " ", "request-1")
            assertEquals(MutationErrorCategory.VALIDATION, invalid.result.errorCategory)
        }
        assertTrue(invalidTransport.requests.isEmpty())

        val unsupportedTransport = ScriptedChatTextInterceptor()
        runBlocking {
            val unsupported = repository(unsupportedTransport, maximumVersion = 4)
                .sendChatTextMessageResult("channel-1", "hello", "request-1")
            assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.result.status)
        }
        assertTrue(unsupportedTransport.requests.isEmpty())

        val cancelledTransport = ScriptedChatTextInterceptor()
        val job = Job()
        var cancelledStatus: MutationResultStatus? = null
        runCatching {
            runBlocking(job) {
                job.cancel()
                cancelledStatus = repository(cancelledTransport)
                    .sendChatTextMessageResult("channel-1", "hello", "request-1").result.status
            }
        }
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, cancelledStatus)
        assertTrue(cancelledTransport.requests.isEmpty())
    }

    @Test
    fun `同一客户端请求发送中拒绝重复提交`() = runBlocking {
        val transport = BlockingChatTextInterceptor(messageAppears = true)
        val repo = repository(transport)
        val first = async(Dispatchers.IO) {
            repo.sendChatTextMessageResult("channel-1", "hello", "request-1")
        }
        assertTrue(transport.createStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.sendChatTextMessageResult("channel-1", "hello", "request-1")
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.result.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.result.errorCategory)
        assertFalse(duplicate.result.submitted)

        transport.allowCreate.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().result.status)
        assertEquals(1, transport.createRequests.get())
    }

    @Test
    fun `提交后取消只回读并要求核对且不重放`() = runBlocking {
        val transport = BlockingChatTextInterceptor(messageAppears = false)
        val repo = repository(transport)
        var status: MutationResultStatus? = null
        val worker = launch(Dispatchers.IO) {
            status = repo.sendChatTextMessageResult("channel-1", "hello", "request-1").result.status
        }
        assertTrue(transport.createStarted.await(2, TimeUnit.SECONDS))

        worker.cancel()
        transport.allowCreate.countDown()
        worker.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, status)
        assertEquals(1, transport.createRequests.get())
    }

    private fun repository(
        interceptor: Interceptor,
        maximumVersion: Int = 5,
    ) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build(),
        ),
        mapOf(
            "SYNO.Chat.Post" to ApiCapability("SYNO.Chat.Post", "entry.cgi", 1, maximumVersion),
        ),
    )
}

private class ScriptedChatTextInterceptor(vararg steps: Any) : Interceptor {
    private val pending = ArrayDeque(steps.toList())
    val requests: MutableList<Request> = Collections.synchronizedList(mutableListOf())

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val step = pending.removeFirstOrNull() ?: error("缺少合成 Chat 文字发送响应")
        if (step is IOException) throw step
        return chatTextResponse(request, step as String)
    }

    fun methods(): List<String?> = requests.map { it.chatTextFields()["method"] }
}

private class BlockingChatTextInterceptor(
    private val messageAppears: Boolean,
) : Interceptor {
    val createStarted = CountDownLatch(1)
    val allowCreate = CountDownLatch(1)
    val createRequests = AtomicInteger()
    private val created = AtomicBoolean(false)

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val method = request.chatTextFields()["method"]
        val body = if (method == "create") {
            createRequests.incrementAndGet()
            createStarted.countDown()
            check(allowCreate.await(2, TimeUnit.SECONDS)) { "等待 Chat 发送请求超时" }
            if (messageAppears) created.set(true)
            """{"success":true,"data":{"post_id":"post-1","channel_id":"channel-1","message":"hello","create_at":${System.currentTimeMillis()}}}"""
        } else {
            if (created.get()) recentPosts("hello") else emptyPosts()
        }
        return chatTextResponse(request, body)
    }
}

private fun Request.chatTextFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}

private fun chatTextResponse(request: Request, body: String) = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody("application/json".toMediaType()))
    .build()

private fun recentPosts(text: String): String =
    """{"success":true,"data":{"total":1,"posts":[{"post_id":"post-readback","channel_id":"channel-1","message":"$text","create_at":${System.currentTimeMillis()},"is_my_post":true}]}}"""

private fun emptyPosts() = """{"success":true,"data":{"total":0,"posts":[]}}"""
