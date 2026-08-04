package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatScheduledMessage
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

class ChatScheduleMutationResultTest {
    @Test
    fun `创建断线但列表回读匹配时确认成功且不重放`() = runBlocking {
        val time = validTime()
        val transport = ScriptedScheduleResultInterceptor(
            emptySchedules(), IOException("synthetic disconnect"), schedules("job-1", time),
        )

        val outcome = repository(transport).createChatScheduledMessageResult(
            "channel-1", "later", time, "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals("job-1", outcome.scheduledMessage?.id)
        assertEquals(listOf("list", "create", "list"), transport.methods())
        assertEquals(1, transport.methods().count { it == "create" })
    }

    @Test
    fun `创建成功响应仍须列表回读确认`() = runBlocking {
        val time = validTime()
        val transport = ScriptedScheduleResultInterceptor(
            emptySchedules(),
            """{"success":true,"data":{"cronjob_id":"job-1","channel_id":"channel-1","message":"later","send_at":$time}}""",
            schedules("job-1", time),
        )

        val outcome = repository(transport).createChatScheduledMessageResult(
            "channel-1", "later", time, "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals(listOf("list", "create", "list"), transport.methods())
    }

    @Test
    fun `创建断线且回读不匹配时保持未确认`() = runBlocking {
        val time = validTime()
        val transport = ScriptedScheduleResultInterceptor(
            emptySchedules(), IOException("synthetic disconnect"), emptySchedules(),
        )

        val outcome = repository(transport).createChatScheduledMessageResult(
            "channel-1", "later", time, "request-1",
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "create" })
    }

    @Test
    fun `创建权限拒绝后回读不匹配时报告权限不足`() = runBlocking {
        val time = validTime()
        val transport = ScriptedScheduleResultInterceptor(
            emptySchedules(), """{"success":false,"error":{"code":105}}""", emptySchedules(),
        )

        val outcome = repository(transport).createChatScheduledMessageResult(
            "channel-1", "later", time, "request-1",
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, outcome.result.status)
        assertEquals(MutationErrorCategory.PERMISSION, outcome.result.errorCategory)
    }

    @Test
    fun `取消定时消息断线但回读已不存在时确认成功`() = runBlocking {
        val time = validTime()
        val transport = ScriptedScheduleResultInterceptor(
            schedules("job-1", time), IOException("synthetic disconnect"), emptySchedules(),
        )

        val outcome = repository(transport).deleteChatScheduledMessageResult(
            "channel-1", "job-1", "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals(listOf("list", "delete", "list"), transport.methods())
        assertEquals(1, transport.methods().count { it == "delete" })
    }

    @Test
    fun `取消定时消息断线且仍存在时保持未确认`() = runBlocking {
        val time = validTime()
        val transport = ScriptedScheduleResultInterceptor(
            schedules("job-1", time), IOException("synthetic disconnect"), schedules("job-1", time),
        )

        val outcome = repository(transport).deleteChatScheduledMessageResult(
            "channel-1", "job-1", "request-1",
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
    }

    @Test
    fun `删除定时消息的用户所见基线漂移时零写拒绝`() = runBlocking {
        val time = validTime()
        val baseline = ChatScheduledMessage("job-1", "channel-1", "later", time)
        val transport = ScriptedScheduleResultInterceptor(
            schedules("job-1", time, text = "changed"),
        )

        val outcome = repository(transport).deleteChatScheduledMessageResult(
            "channel-1", baseline, "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, outcome.result.status)
        assertEquals(MutationErrorCategory.CONFLICT, outcome.result.errorCategory)
        assertFalse(outcome.result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `写前回读失败时不提交定时消息`() = runBlocking {
        val transport = ScriptedScheduleResultInterceptor(IOException("synthetic preflight failure"))

        val outcome = repository(transport).createChatScheduledMessageResult(
            "channel-1", "later", validTime(), "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, outcome.result.status)
        assertFalse(outcome.result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `非法输入不支持能力和提交前取消均零请求关闭`() {
        val invalidTransport = ScriptedScheduleResultInterceptor()
        runBlocking {
            val invalid = repository(invalidTransport).createChatScheduledMessageResult(
                "channel-1", " ", validTime(), "request-1",
            )
            assertEquals(MutationErrorCategory.VALIDATION, invalid.result.errorCategory)
        }
        assertTrue(invalidTransport.requests.isEmpty())

        val unsupportedTransport = ScriptedScheduleResultInterceptor()
        runBlocking {
            val unsupported = repository(unsupportedTransport, maximumVersion = 0)
                .deleteChatScheduledMessageResult("channel-1", "job-1", "request-1")
            assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.result.status)
        }
        assertTrue(unsupportedTransport.requests.isEmpty())

        val cancelledTransport = ScriptedScheduleResultInterceptor()
        val job = Job()
        var status: MutationResultStatus? = null
        runCatching {
            runBlocking(job) {
                job.cancel()
                status = repository(cancelledTransport).createChatScheduledMessageResult(
                    "channel-1", "later", validTime(), "request-1",
                ).result.status
            }
        }
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, status)
        assertTrue(cancelledTransport.requests.isEmpty())
    }

    @Test
    fun `同一正文时间使用不同请求ID并发时仍拒绝重复创建`() = runBlocking {
        val time = validTime()
        val transport = BlockingScheduleResultInterceptor(time, scheduleAppears = true)
        val repo = repository(transport)
        val first = async(Dispatchers.IO) {
            repo.createChatScheduledMessageResult("channel-1", "later", time, "request-1")
        }
        assertTrue(transport.writeStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.createChatScheduledMessageResult(
            "channel-1", "later", time, "request-2",
        )
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.result.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.result.errorCategory)

        transport.allowWrite.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().result.status)
        assertEquals(1, transport.writeRequests.get())
    }

    @Test
    fun `提交后取消只回读并要求刷新且不重放`() = runBlocking {
        val time = validTime()
        val transport = BlockingScheduleResultInterceptor(time, scheduleAppears = false)
        val repo = repository(transport)
        var status: MutationResultStatus? = null
        val worker = launch(Dispatchers.IO) {
            status = repo.createChatScheduledMessageResult(
                "channel-1", "later", time, "request-1",
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

    private fun repository(interceptor: Interceptor, maximumVersion: Int = 1) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "synthetic-session", "synthetic-token"),
        DsmApiClient(OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build()),
        if (maximumVersion > 0) mapOf(
            "SYNO.Chat.Post.Schedule" to ApiCapability(
                "SYNO.Chat.Post.Schedule", "entry.cgi", 1, maximumVersion,
            ),
        ) else emptyMap(),
    )

    private fun validTime() = System.currentTimeMillis() + 3_600_000
}

private class ScriptedScheduleResultInterceptor(vararg steps: Any) : Interceptor {
    private val pending = ArrayDeque(steps.toList())
    val requests: MutableList<Request> = Collections.synchronizedList(mutableListOf())

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val step = pending.removeFirstOrNull() ?: error("缺少合成 Chat 定时消息响应")
        if (step is IOException) throw step
        return scheduleResultResponse(request, step as String)
    }

    fun methods(): List<String?> = requests.map { it.scheduleResultFields()["method"] }
}

private class BlockingScheduleResultInterceptor(
    private val time: Long,
    private val scheduleAppears: Boolean,
) : Interceptor {
    val writeStarted = CountDownLatch(1)
    val allowWrite = CountDownLatch(1)
    val writeRequests = AtomicInteger()
    val listRequests = AtomicInteger()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val body = when (request.scheduleResultFields()["method"]) {
            "create" -> {
                writeRequests.incrementAndGet()
                writeStarted.countDown()
                check(allowWrite.await(2, TimeUnit.SECONDS)) { "等待 Chat 定时消息请求超时" }
                """{"success":true,"data":{"cronjob_id":"job-1"}}"""
            }
            else -> {
                val count = listRequests.incrementAndGet()
                if (count > 1 && scheduleAppears) schedules("job-1", time) else emptySchedules()
            }
        }
        return scheduleResultResponse(request, body)
    }
}

private fun Request.scheduleResultFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}

private fun scheduleResultResponse(request: Request, body: String) = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody("application/json".toMediaType()))
    .build()

private fun schedules(id: String, time: Long, text: String = "later") =
    """{"success":true,"data":{"schedules":[{"cronjob_id":"$id","channel_id":"channel-1","message":"$text","send_at":$time}]}}"""

private fun emptySchedules() = """{"success":true,"data":{"schedules":[]}}"""
