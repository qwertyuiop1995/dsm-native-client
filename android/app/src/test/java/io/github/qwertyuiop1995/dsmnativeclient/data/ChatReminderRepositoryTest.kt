package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.net.URLDecoder
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.runBlocking
import okhttp3.FormBody
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatReminderRepositoryTest {
    @Test
    fun `提醒固定v1并在写后回读确认且请求ID不出站`() = runBlocking {
        val time = System.currentTimeMillis() + 3_600_000
        val transport = ReminderInterceptor(
            body("""{"success":true,"data":{"reminders":[]}}"""),
            body("""{"success":true}"""),
            reminder("post-1", time),
        )
        val repo = repository(transport)

        val first = repo.setChatReminder("channel-1", "post-1", time, "request-1")
        val second = repo.setChatReminder("channel-1", "post-1", time, "request-1")

        assertEquals(first, second)
        assertEquals(3, transport.requests.size)
        val fields = transport.requests.map(Request::formFields)
        assertEquals(listOf("list", "set", "list"), fields.map { it["method"] })
        assertEquals("1", fields[1]["version"])
        assertEquals(time.toString(), fields[1]["remind_at"])
        assertTrue(fields.flatMap { it.keys }.none { it.contains("request", true) })
    }

    @Test
    fun `提醒写入断线后只回读不自动重放`() = runBlocking {
        val time = System.currentTimeMillis() + 7_200_000
        val transport = ReminderInterceptor(
            body("""{"success":true,"data":{"reminders":[]}}"""),
            failure(IOException("synthetic disconnect")),
            reminder("post-1", time),
        )

        val reminder = repository(transport).setChatReminder(
            "channel-1", "post-1", time, "request-1",
        )

        assertEquals("post-1", reminder.messageId)
        assertEquals(listOf("list", "set", "list"), transport.requests.map { it.formFields()["method"] })
    }

    @Test
    fun `取消提醒前后回读且重复请求不再写入`() = runBlocking {
        val time = System.currentTimeMillis() + 3_600_000
        val transport = ReminderInterceptor(
            reminder("synthetic-post", time),
            body("""{"success":true}"""),
            body("""{"success":true,"data":{"reminders":[]}}"""),
        )
        val repo = repository(transport)

        repo.deleteChatReminder("channel-1", "synthetic-post", "request-1")
        repo.deleteChatReminder("channel-1", "synthetic-post", "request-1")

        assertEquals(3, transport.requests.size)
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "chat/delete-reminder/synthetic-post/request.json",
        )
        assertEquals(listOf("list", "delete", "list"), transport.requests.map { it.formFields()["method"] })
    }

    @Test
    fun `提醒请求层可编码公共 Fixture 的固定时间`() = runBlocking {
        val transport = ReminderInterceptor(body("""{"success":true,"data":{}}"""))
        val api = DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(transport).build(),
        )

        api.call(
            NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
            DsmSession("test", "synthetic-session", "synthetic-token"),
            ApiCapability("SYNO.Chat.Post.Reminder", "entry.cgi", 1, 1),
            "set",
            mapOf("post_id" to "synthetic-post", "remind_at" to "1774166400000"),
        )

        RequestFixtureAssertions.assertRequest(
            transport.requests.single(),
            "chat/set-reminder/synthetic-post/request.json",
        )
    }

    @Test
    fun `提醒能力版本不匹配时零请求拒绝`() = runBlocking {
        val transport = ReminderInterceptor()
        var thrown = false

        try {
            repository(transport, reminderVersion = 2).chatReminders("channel-1")
        } catch (_: Throwable) {
            thrown = true
        }

        assertTrue(thrown)
        assertTrue(transport.requests.isEmpty())
    }

    private fun repository(interceptor: ReminderInterceptor, reminderVersion: Int = 1) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "synthetic-session", "synthetic-token"),
        DsmApiClient(OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build()),
        mapOf(
            "SYNO.Chat.Post.Reminder" to ApiCapability(
                "SYNO.Chat.Post.Reminder", "entry.cgi", reminderVersion, reminderVersion,
            ),
        ),
    )

    private fun reminder(messageId: String, time: Long) = body(
        """{"success":true,"data":{"reminders":[{"reminder_id":"reminder-1","post_id":"$messageId","remind_at":$time}]}}""",
    )

    private fun body(value: String) = ReminderStep.Body(value)
    private fun failure(error: IOException) = ReminderStep.Failure(error)
}

private sealed interface ReminderStep {
    data class Body(val value: String) : ReminderStep
    data class Failure(val error: IOException) : ReminderStep
}

private class ReminderInterceptor(vararg steps: ReminderStep) : Interceptor {
    private val queue = ArrayDeque(steps.toList())
    val requests = CopyOnWriteArrayList<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return when (val step = queue.removeFirstOrNull() ?: error("Unexpected request")) {
            is ReminderStep.Failure -> throw step.error
            is ReminderStep.Body -> Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(step.value.toResponseBody())
                .build()
        }
    }
}

private fun Request.formFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { index ->
        URLDecoder.decode(form.encodedName(index), Charsets.UTF_8) to
            URLDecoder.decode(form.encodedValue(index), Charsets.UTF_8)
    }
}
