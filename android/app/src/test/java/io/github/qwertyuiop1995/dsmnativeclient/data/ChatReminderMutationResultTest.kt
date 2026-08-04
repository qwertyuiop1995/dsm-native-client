package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatReminder
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

class ChatReminderMutationResultTest {
    @Test
    fun `设置提交断线但回读匹配时确认成功且不重放`() = runBlocking {
        val time = validTime()
        val transport = ScriptedReminderResultInterceptor(
            emptyReminders(),
            IOException("synthetic disconnect"),
            reminders("post-1", time),
        )

        val outcome = repository(transport).setChatReminderResult(
            "channel-1", "post-1", time, "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals(time, outcome.reminder?.remindAtEpochMillis)
        assertEquals(listOf("list", "set", "list"), transport.methods())
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `设置提交断线且回读不匹配时保持未确认`() = runBlocking {
        val time = validTime()
        val transport = ScriptedReminderResultInterceptor(
            emptyReminders(),
            IOException("synthetic disconnect"),
            emptyReminders(),
        )

        val outcome = repository(transport).setChatReminderResult(
            "channel-1", "post-1", time, "request-1",
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "set" })
    }

    @Test
    fun `设置权限拒绝后回读不匹配时报告权限不足`() = runBlocking {
        val time = validTime()
        val transport = ScriptedReminderResultInterceptor(
            emptyReminders(),
            """{"success":false,"error":{"code":105}}""",
            emptyReminders(),
        )

        val outcome = repository(transport).setChatReminderResult(
            "channel-1", "post-1", time, "request-1",
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, outcome.result.status)
        assertEquals(MutationErrorCategory.PERMISSION, outcome.result.errorCategory)
    }

    @Test
    fun `成功响应但回读失败时保持未确认`() = runBlocking {
        val time = validTime()
        val transport = ScriptedReminderResultInterceptor(
            emptyReminders(),
            """{"success":true}""",
            IOException("synthetic readback failure"),
        )

        val outcome = repository(transport).setChatReminderResult(
            "channel-1", "post-1", time, "request-1",
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
    }

    @Test
    fun `删除提交断线但回读已不存在时确认成功且不重放`() = runBlocking {
        val time = validTime()
        val transport = ScriptedReminderResultInterceptor(
            reminders("post-1", time),
            IOException("synthetic disconnect"),
            emptyReminders(),
        )

        val outcome = repository(transport).deleteChatReminderResult(
            "channel-1", "post-1", "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertTrue(outcome.reminders?.isEmpty() == true)
        assertEquals(listOf("list", "delete", "list"), transport.methods())
        assertEquals(1, transport.methods().count { it == "delete" })
    }

    @Test
    fun `删除提交断线且提醒仍存在时保持未确认`() = runBlocking {
        val time = validTime()
        val transport = ScriptedReminderResultInterceptor(
            reminders("post-1", time),
            IOException("synthetic disconnect"),
            reminders("post-1", time),
        )

        val outcome = repository(transport).deleteChatReminderResult(
            "channel-1", "post-1", "request-1",
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "delete" })
    }

    @Test
    fun `删除提醒的用户所见基线漂移时零写拒绝`() = runBlocking {
        val time = validTime()
        val baseline = ChatReminder("reminder-1", "post-1", time)
        val transport = ScriptedReminderResultInterceptor(
            reminders("post-1", time + 1_000),
        )

        val outcome = repository(transport).deleteChatReminderResult(
            "channel-1", baseline, "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, outcome.result.status)
        assertEquals(MutationErrorCategory.CONFLICT, outcome.result.errorCategory)
        assertFalse(outcome.result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `写前回读失败时不提交提醒变更`() = runBlocking {
        val transport = ScriptedReminderResultInterceptor(IOException("synthetic preflight failure"))

        val outcome = repository(transport).setChatReminderResult(
            "channel-1", "post-1", validTime(), "request-1",
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, outcome.result.status)
        assertFalse(outcome.result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `非法输入不支持能力和提交前取消均零请求关闭`() {
        val invalidTransport = ScriptedReminderResultInterceptor()
        runBlocking {
            val invalid = repository(invalidTransport).setChatReminderResult(
                "channel-1", "post-1", System.currentTimeMillis(), "request-1",
            )
            assertEquals(MutationErrorCategory.VALIDATION, invalid.result.errorCategory)
        }
        assertTrue(invalidTransport.requests.isEmpty())

        val unsupportedTransport = ScriptedReminderResultInterceptor()
        runBlocking {
            val unsupported = repository(unsupportedTransport, maximumVersion = 0)
                .deleteChatReminderResult("channel-1", "post-1", "request-1")
            assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.result.status)
        }
        assertTrue(unsupportedTransport.requests.isEmpty())

        val cancelledTransport = ScriptedReminderResultInterceptor()
        val job = Job()
        var status: MutationResultStatus? = null
        runCatching {
            runBlocking(job) {
                job.cancel()
                status = repository(cancelledTransport).setChatReminderResult(
                    "channel-1", "post-1", validTime(), "request-1",
                ).result.status
            }
        }
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, status)
        assertTrue(cancelledTransport.requests.isEmpty())
    }

    @Test
    fun `同一消息使用不同请求ID并发时仍拒绝重复提交`() = runBlocking {
        val time = validTime()
        val transport = BlockingReminderResultInterceptor(time, reminderAppears = true)
        val repo = repository(transport)
        val first = async(Dispatchers.IO) {
            repo.setChatReminderResult("channel-1", "post-1", time, "request-1")
        }
        assertTrue(transport.writeStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.setChatReminderResult(
            "channel-1", "post-1", time, "request-2",
        )
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.result.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.result.errorCategory)
        assertFalse(duplicate.result.submitted)

        transport.allowWrite.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().result.status)
        assertEquals(1, transport.writeRequests.get())
    }

    @Test
    fun `提交后取消只回读并要求刷新且不重放`() = runBlocking {
        val time = validTime()
        val transport = BlockingReminderResultInterceptor(time, reminderAppears = false)
        val repo = repository(transport)
        var status: MutationResultStatus? = null
        val worker = launch(Dispatchers.IO) {
            status = repo.setChatReminderResult(
                "channel-1", "post-1", time, "request-1",
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
        DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build(),
        ),
        if (maximumVersion > 0) mapOf(
            "SYNO.Chat.Post.Reminder" to ApiCapability(
                "SYNO.Chat.Post.Reminder", "entry.cgi", 1, maximumVersion,
            ),
        ) else emptyMap(),
    )

    private fun validTime() = System.currentTimeMillis() + 3_600_000
}

private class ScriptedReminderResultInterceptor(vararg steps: Any) : Interceptor {
    private val pending = ArrayDeque(steps.toList())
    val requests: MutableList<Request> = Collections.synchronizedList(mutableListOf())

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val step = pending.removeFirstOrNull() ?: error("缺少合成 Chat 提醒响应")
        if (step is IOException) throw step
        return reminderResultResponse(request, step as String)
    }

    fun methods(): List<String?> = requests.map { it.reminderResultFields()["method"] }
}

private class BlockingReminderResultInterceptor(
    private val time: Long,
    private val reminderAppears: Boolean,
) : Interceptor {
    val writeStarted = CountDownLatch(1)
    val allowWrite = CountDownLatch(1)
    val writeRequests = AtomicInteger()
    val listRequests = AtomicInteger()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val method = request.reminderResultFields()["method"]
        val body = when (method) {
            "set" -> {
                writeRequests.incrementAndGet()
                writeStarted.countDown()
                check(allowWrite.await(2, TimeUnit.SECONDS)) { "等待 Chat 提醒请求超时" }
                """{"success":true}"""
            }
            else -> {
                val count = listRequests.incrementAndGet()
                if (count > 1 && reminderAppears) reminders("post-1", time) else emptyReminders()
            }
        }
        return reminderResultResponse(request, body)
    }
}

private fun Request.reminderResultFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}

private fun reminderResultResponse(request: Request, body: String) = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody("application/json".toMediaType()))
    .build()

private fun reminders(messageId: String, time: Long) =
    """{"success":true,"data":{"reminders":[{"reminder_id":"reminder-1","post_id":"$messageId","remind_at":$time}]}}"""

private fun emptyReminders() = """{"success":true,"data":{"reminders":[]}}"""
