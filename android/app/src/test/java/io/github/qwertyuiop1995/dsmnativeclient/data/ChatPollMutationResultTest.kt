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
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import okhttp3.FormBody
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatPollMutationResultTest {
    @Test
    fun `创建断线但近期消息回读匹配时确认成功且不重放`() = runBlocking {
        val transport = ScriptedPollResultInterceptor(
            emptyPollMessages(), IOException("synthetic disconnect"), pollMessages(),
        )

        val outcome = repository(transport).createChatPollResult(
            "channel-1", "Question?", listOf("First", "Second"), true, false, "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertNotNull(outcome.message?.poll)
        assertEquals(listOf("list", "create", "list"), transport.methods())
        assertEquals(1, transport.methods().count { it == "create" })
    }

    @Test
    fun `创建成功响应仍须近期消息回读确认`() = runBlocking {
        val transport = ScriptedPollResultInterceptor(
            emptyPollMessages(), successResponse(), pollMessages(),
        )

        val outcome = repository(transport).createChatPollResult(
            "channel-1", "Question?", listOf("First", "Second"), true, false, "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals(listOf("list", "create", "list"), transport.methods())
    }

    @Test
    fun `创建断线且回读不匹配时保持未确认`() = runBlocking {
        val transport = ScriptedPollResultInterceptor(
            emptyPollMessages(), IOException("synthetic disconnect"), emptyPollMessages(),
        )

        val outcome = repository(transport).createChatPollResult(
            "channel-1", "Question?", listOf("First", "Second"), true, false, "request-1",
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "create" })
    }

    @Test
    fun `创建权限拒绝且回读不匹配时报告权限不足`() = runBlocking {
        val transport = ScriptedPollResultInterceptor(
            emptyPollMessages(), """{"success":false,"error":{"code":105}}""", emptyPollMessages(),
        )

        val outcome = repository(transport).createChatPollResult(
            "channel-1", "Question?", listOf("First", "Second"), false, false, "request-1",
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, outcome.result.status)
        assertEquals(MutationErrorCategory.PERMISSION, outcome.result.errorCategory)
    }

    @Test
    fun `写前回读失败时不提交投票`() = runBlocking {
        val transport = ScriptedPollResultInterceptor(IOException("synthetic preflight failure"))

        val outcome = repository(transport).createChatPollResult(
            "channel-1", "Question?", listOf("First", "Second"), false, false, "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, outcome.result.status)
        assertFalse(outcome.result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `提交后回读失败时保持未确认`() = runBlocking {
        val transport = ScriptedPollResultInterceptor(
            emptyPollMessages(), successResponse(), IOException("synthetic readback failure"),
        )

        val outcome = repository(transport).createChatPollResult(
            "channel-1", "Question?", listOf("First", "Second"), false, false, "request-1",
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "create" })
    }

    @Test
    fun `非法输入不支持能力和提交前取消均零请求关闭`() {
        val invalidTransport = ScriptedPollResultInterceptor()
        runBlocking {
            val invalid = repository(invalidTransport).createChatPollResult(
                "channel-1", "Question?", listOf("Same", "same"), false, false, "request-1",
            )
            assertEquals(MutationErrorCategory.VALIDATION, invalid.result.errorCategory)
        }
        assertTrue(invalidTransport.requests.isEmpty())

        val unsupportedTransport = ScriptedPollResultInterceptor()
        runBlocking {
            val unsupported = repository(unsupportedTransport, voteVersion = 0).createChatPollResult(
                "channel-1", "Question?", listOf("First", "Second"), false, false, "request-1",
            )
            assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.result.status)
        }
        assertTrue(unsupportedTransport.requests.isEmpty())

        val cancelledTransport = ScriptedPollResultInterceptor()
        val job = Job()
        var status: MutationResultStatus? = null
        runCatching {
            runBlocking(job) {
                job.cancel()
                status = repository(cancelledTransport).createChatPollResult(
                    "channel-1", "Question?", listOf("First", "Second"), false, false, "request-1",
                ).result.status
            }
        }
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, status)
        assertTrue(cancelledTransport.requests.isEmpty())
    }

    @Test
    fun `同一投票使用不同请求ID并发时仍拒绝重复创建`() = runBlocking {
        val transport = BlockingPollResultInterceptor(pollAppears = true)
        val repo = repository(transport)
        val first = async(Dispatchers.IO) {
            repo.createChatPollResult(
                "channel-1", "Question?", listOf("First", "Second"), true, false, "request-1",
            )
        }
        assertTrue(transport.writeStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.createChatPollResult(
            "channel-1", "Question?", listOf("First", "Second"), true, false, "request-2",
        )
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.result.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.result.errorCategory)

        transport.allowWrite.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().result.status)
        assertEquals(1, transport.writeRequests.get())
    }

    @Test
    fun `提交后取消只回读并要求刷新且不重放`() = runBlocking {
        val transport = BlockingPollResultInterceptor(pollAppears = false)
        val repo = repository(transport)
        var status: MutationResultStatus? = null
        val worker = launch(Dispatchers.IO) {
            status = repo.createChatPollResult(
                "channel-1", "Question?", listOf("First", "Second"), true, false, "request-1",
            ).result.status
        }
        assertTrue(transport.writeStarted.await(2, TimeUnit.SECONDS))

        worker.cancel()
        transport.allowWrite.countDown()
        worker.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, status)
        assertEquals(1, transport.writeRequests.get())
        assertEquals(2, transport.listRequests.get())
    }

    private fun repository(interceptor: Interceptor, voteVersion: Int = 1) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "synthetic-session", "synthetic-token"),
        DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build(),
        ),
        buildMap {
            put("SYNO.Chat.Post", ApiCapability("SYNO.Chat.Post", "entry.cgi", 1, 8))
            if (voteVersion > 0) {
                put(
                    "SYNO.Chat.Post.Vote",
                    ApiCapability("SYNO.Chat.Post.Vote", "entry.cgi", 1, voteVersion),
                )
            }
        },
    )
}

private class ScriptedPollResultInterceptor(vararg steps: Any) : Interceptor {
    private val pending = ArrayDeque(steps.toList())
    val requests: MutableList<Request> = Collections.synchronizedList(mutableListOf())

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val step = pending.removeFirstOrNull() ?: error("缺少合成 Chat 投票响应")
        if (step is IOException) throw step
        return pollResultResponse(request, step as String)
    }

    fun methods(): List<String?> = requests.map { it.pollResultFields()["method"] }
}

private class BlockingPollResultInterceptor(
    private val pollAppears: Boolean,
) : Interceptor {
    val writeStarted = CountDownLatch(1)
    val allowWrite = CountDownLatch(1)
    val writeRequests = AtomicInteger()
    val listRequests = AtomicInteger()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val body = when (request.pollResultFields()["method"]) {
            "create" -> {
                writeRequests.incrementAndGet()
                writeStarted.countDown()
                check(allowWrite.await(2, TimeUnit.SECONDS)) { "等待 Chat 投票请求超时" }
                successResponse()
            }
            else -> {
                val count = listRequests.incrementAndGet()
                if (count > 1 && pollAppears) pollMessages() else emptyPollMessages()
            }
        }
        return pollResultResponse(request, body)
    }
}

private fun Request.pollResultFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}

private fun pollResultResponse(request: Request, body: String) = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody())
    .build()

private fun successResponse() = """{"success":true,"data":{}}"""

private fun emptyPollMessages() = """{"success":true,"data":{"posts":[],"total":0}}"""

private fun pollMessages(): String {
    val now = System.currentTimeMillis() / 1_000
    return """{"success":true,"data":{"posts":[{"post_id":"post-1","channel_id":"channel-1","creator_id":"current","is_my_post":true,"create_at":$now,"message":"Question?","vote":{"vote_id":"vote-1","choices":[{"choice_id":"c1","text":"First"},{"choice_id":"c2","text":"Second"}],"options":"{\"multiple\":true,\"anonymous\":false}"}}],"total":1}}"""
}
