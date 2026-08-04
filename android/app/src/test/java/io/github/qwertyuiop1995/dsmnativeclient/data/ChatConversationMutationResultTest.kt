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

class ChatConversationMutationResultTest {
    @Test
    fun `单聊创建断线但列表回读匹配时确认成功且不重放`() = runBlocking {
        val transport = ScriptedConversationResultInterceptor(
            users(), emptyChannels(), IOException("synthetic disconnect"), users(), directChannels(),
        )

        val outcome = repository(transport).openDirectChatConversationResult("2", "request-1")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals("27", outcome.conversation?.id)
        assertEquals(1, transport.methods().count { it == "initiate" })
    }

    @Test
    fun `单聊成功响应仍须列表回读确认`() = runBlocking {
        val transport = ScriptedConversationResultInterceptor(
            users(), emptyChannels(), success("""{"channel_id":"27"}"""), users(), emptyChannels(),
        )

        val outcome = repository(transport).openDirectChatConversationResult("2", "request-1")

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
    }

    @Test
    fun `单聊权限拒绝且回读不匹配时报告权限不足`() = runBlocking {
        val transport = ScriptedConversationResultInterceptor(
            users(), emptyChannels(), """{"success":false,"error":{"code":105}}""",
            users(), emptyChannels(),
        )

        val outcome = repository(transport).openDirectChatConversationResult("2", "request-1")

        assertEquals(MutationResultStatus.PERMISSION_DENIED, outcome.result.status)
        assertEquals(MutationErrorCategory.PERMISSION, outcome.result.errorCategory)
    }

    @Test
    fun `单聊写前列表失败时不提交`() = runBlocking {
        val transport = ScriptedConversationResultInterceptor(
            users(), IOException("synthetic preflight failure"),
        )

        val outcome = repository(transport).openDirectChatConversationResult("2", "request-1")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, outcome.result.status)
        assertFalse(outcome.result.submitted)
        assertTrue(transport.methods().none { it == "initiate" })
    }

    @Test
    fun `非法输入不支持能力和提交前取消均零请求关闭`() {
        val invalidTransport = ScriptedConversationResultInterceptor()
        runBlocking {
            val invalid = repository(invalidTransport).createPrivateChatGroupResult(
                "", listOf("2"), "request-1",
            )
            assertEquals(MutationErrorCategory.VALIDATION, invalid.result.errorCategory)
        }
        assertTrue(invalidTransport.requests.isEmpty())

        val unsupportedTransport = ScriptedConversationResultInterceptor()
        runBlocking {
            val unsupported = repository(unsupportedTransport, anonymousVersion = 1)
                .openDirectChatConversationResult("2", "request-1")
            assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.result.status)
        }
        assertTrue(unsupportedTransport.requests.isEmpty())

        val cancelledTransport = ScriptedConversationResultInterceptor()
        val job = Job()
        var status: MutationResultStatus? = null
        runCatching {
            runBlocking(job) {
                job.cancel()
                status = repository(cancelledTransport)
                    .openDirectChatConversationResult("2", "request-1").result.status
            }
        }
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, status)
        assertTrue(cancelledTransport.requests.isEmpty())
    }

    @Test
    fun `同一单聊使用不同请求ID并发时仍拒绝重复创建`() = runBlocking {
        val transport = BlockingDirectConversationInterceptor(conversationAppears = true)
        val repo = repository(transport)
        val first = async(Dispatchers.IO) {
            repo.openDirectChatConversationResult("2", "request-1")
        }
        assertTrue(transport.writeStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.openDirectChatConversationResult("2", "request-2")
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.result.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.result.errorCategory)

        transport.allowWrite.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().result.status)
        assertEquals(1, transport.writeRequests.get())
    }

    @Test
    fun `单聊提交后取消只回读并要求刷新且不重放`() = runBlocking {
        val transport = BlockingDirectConversationInterceptor(conversationAppears = false)
        val repo = repository(transport)
        var status: MutationResultStatus? = null
        val worker = launch(Dispatchers.IO) {
            status = repo.openDirectChatConversationResult("2", "request-1").result.status
        }
        assertTrue(transport.writeStarted.await(2, TimeUnit.SECONDS))

        worker.cancel()
        transport.allowWrite.countDown()
        worker.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, status)
        assertEquals(1, transport.writeRequests.get())
        assertEquals(2, transport.channelListRequests.get())
    }

    @Test
    fun `群聊邀请断线且成员不完整时报告部分成功`() = runBlocking {
        val transport = ScriptedConversationResultInterceptor(
            users(), emptyChannels(),
            success("""{"channel_id":"42"}"""), success("{}"),
            IOException("synthetic invite disconnect"),
            users(), partialGroupChannels(), memberIds("1", "2"), users(),
        )

        val outcome = repository(transport).createPrivateChatGroupResult(
            "Group", listOf("2", "3"), "request-1",
        )

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
        assertNotNull(outcome.conversation)
        assertEquals(1, transport.methods().count { it == "invite" })
    }

    @Test
    fun `群聊邀请断线但成员回读完整时确认成功`() = runBlocking {
        val transport = ScriptedConversationResultInterceptor(
            users(), emptyChannels(),
            success("""{"channel_id":"42"}"""), success("{}"),
            IOException("synthetic invite disconnect"),
            users(), fullGroupChannels(), memberIds("1", "2", "3"), users(),
        )

        val outcome = repository(transport).createPrivateChatGroupResult(
            "Group", listOf("2", "3"), "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals(setOf("1", "2", "3"), outcome.conversation?.memberIds?.toSet())
        assertEquals(1, transport.methods().count { it == "invite" })
    }

    @Test
    fun `群聊创建提交后取消只最终回读且不继续加入或邀请`() = runBlocking {
        val transport = BlockingGroupCreateInterceptor()
        val repo = repository(transport)
        var status: MutationResultStatus? = null
        val worker = launch(Dispatchers.IO) {
            status = repo.createPrivateChatGroupResult(
                "Group", listOf("2", "3"), "request-1",
            ).result.status
        }
        assertTrue(transport.createStarted.await(2, TimeUnit.SECONDS))

        worker.cancel()
        transport.allowCreate.countDown()
        worker.join()

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, status)
        assertEquals(1, transport.createRequests.get())
        assertEquals(0, transport.joinRequests.get())
        assertEquals(0, transport.inviteRequests.get())
        assertEquals(2, transport.channelListRequests.get())
        assertEquals(1, transport.memberReadRequests.get())
    }

    private fun repository(
        interceptor: Interceptor,
        anonymousVersion: Int = 2,
    ) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "synthetic-session", "synthetic-token"),
        DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build(),
        ),
        mapOf(
            "SYNO.Chat.User" to ApiCapability("SYNO.Chat.User", "entry.cgi", 1, 3),
            "SYNO.Chat.Channel" to ApiCapability("SYNO.Chat.Channel", "entry.cgi", 1, 5),
            "SYNO.Chat.Channel.Anonymous" to ApiCapability(
                "SYNO.Chat.Channel.Anonymous", "entry.cgi", 1, anonymousVersion,
            ),
            "SYNO.Chat.Channel.Named" to ApiCapability(
                "SYNO.Chat.Channel.Named", "entry.cgi", 1, 1,
            ),
            "SYNO.Chat.Channel.Member" to ApiCapability(
                "SYNO.Chat.Channel.Member", "entry.cgi", 1, 1,
            ),
        ),
    )
}

private class ScriptedConversationResultInterceptor(vararg steps: Any) : Interceptor {
    private val pending = ArrayDeque(steps.toList())
    val requests: MutableList<Request> = Collections.synchronizedList(mutableListOf())

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val step = pending.removeFirstOrNull() ?: error("缺少合成 Chat 会话响应")
        if (step is IOException) throw step
        return conversationResultResponse(request, step as String)
    }

    fun methods(): List<String?> = requests.map { it.conversationResultFields()["method"] }
}

private class BlockingDirectConversationInterceptor(
    private val conversationAppears: Boolean,
) : Interceptor {
    val writeStarted = CountDownLatch(1)
    val allowWrite = CountDownLatch(1)
    val writeRequests = AtomicInteger()
    val channelListRequests = AtomicInteger()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val fields = request.conversationResultFields()
        val response = when {
            fields["api"] == "SYNO.Chat.User" -> users()
            fields["method"] == "initiate" -> {
                writeRequests.incrementAndGet()
                writeStarted.countDown()
                check(allowWrite.await(2, TimeUnit.SECONDS)) { "等待 Chat 单聊请求超时" }
                success("""{"channel_id":"27"}""")
            }
            else -> {
                val count = channelListRequests.incrementAndGet()
                if (count > 1 && conversationAppears) directChannels() else emptyChannels()
            }
        }
        return conversationResultResponse(request, response)
    }
}

private class BlockingGroupCreateInterceptor : Interceptor {
    val createStarted = CountDownLatch(1)
    val allowCreate = CountDownLatch(1)
    val createRequests = AtomicInteger()
    val joinRequests = AtomicInteger()
    val inviteRequests = AtomicInteger()
    val channelListRequests = AtomicInteger()
    val memberReadRequests = AtomicInteger()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val fields = request.conversationResultFields()
        val response = when {
            fields["api"] == "SYNO.Chat.User" -> users()
            fields["api"] == "SYNO.Chat.Channel.Member" -> {
                memberReadRequests.incrementAndGet()
                memberIds("1", "2")
            }
            fields["method"] == "create" -> {
                createRequests.incrementAndGet()
                createStarted.countDown()
                check(allowCreate.await(2, TimeUnit.SECONDS)) { "等待 Chat 群聊创建请求超时" }
                success("""{"channel_id":"42"}""")
            }
            fields["method"] == "join" -> {
                joinRequests.incrementAndGet()
                success("{}")
            }
            fields["method"] == "invite" -> {
                inviteRequests.incrementAndGet()
                success("{}")
            }
            else -> {
                val count = channelListRequests.incrementAndGet()
                if (count > 1) partialGroupChannels() else emptyChannels()
            }
        }
        return conversationResultResponse(request, response)
    }
}

private fun Request.conversationResultFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}

private fun conversationResultResponse(request: Request, body: String) = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody())
    .build()

private fun success(data: String) = """{"success":true,"data":$data}"""

private fun users() = """{"success":true,"data":{"current_user_id":"1","users":[
    {"user_id":"1","username":"operator","nickname":"Current"},
    {"user_id":"2","username":"member2","nickname":"Member 2"},
    {"user_id":"3","username":"member3","nickname":"Member 3"}
]}}"""

private fun emptyChannels() = """{"success":true,"data":{"channels":[]}}"""

private fun directChannels() = """{"success":true,"data":{"channels":[
    {"channel_id":"27","type":"anonymous","members":["1","2"],"member_count":2}
]}}"""

private fun partialGroupChannels() = """{"success":true,"data":{"channels":[
    {"channel_id":"42","type":"private","name":"Group","members":["1","2"],"member_count":2}
]}}"""

private fun fullGroupChannels() = """{"success":true,"data":{"channels":[
    {"channel_id":"42","type":"private","name":"Group","members":["1","2","3"],"member_count":3}
]}}"""

private fun memberIds(vararg ids: String) =
    """{"success":true,"data":{"user_ids":[${ids.joinToString(",") { "\"$it\"" }}],"broken_user_ids":[]}}"""
