package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
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

class ChatScheduleRepositoryTest {
    @Test
    fun `纯文字定时消息固定v1且创建前查重`() = runBlocking {
        val time = 1_800_000_000_000L
        val transport = ScheduleInterceptor(
            scheduleBody("""{"schedules":[]}"""),
            scheduleBody("""{"cronjob_id":"job-1","channel_id":"synthetic-channel","message":"Synthetic scheduled message","send_at":$time}"""),
            scheduleBody("""{"schedules":[{"cronjob_id":"job-1","channel_id":"synthetic-channel","message":"Synthetic scheduled message","send_at":$time}]}"""),
        )
        val repo = repository(transport)

        val first = repo.createChatScheduledMessage(
            "synthetic-channel", " Synthetic scheduled message ", time, "request-1",
        )
        val second = repo.createChatScheduledMessage(
            "synthetic-channel", "Synthetic scheduled message", time, "request-1",
        )

        assertEquals(first, second)
        assertEquals("job-1", first.id)
        assertEquals(listOf("list", "create", "list"), transport.requests.map { it.fields()["method"] })
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "chat/create-scheduled-message/synthetic-message/request.json",
        )
        assertEquals("1", transport.requests[1].fields()["version"])
        assertEquals(time.toString(), transport.requests[1].fields()["send_at"])
        assertTrue(transport.requests.flatMap { it.fields().keys }.none { it.contains("request", true) })
    }

    @Test
    fun `定时消息创建断线后只回读不重放`() = runBlocking {
        val time = System.currentTimeMillis() + 7_200_000
        val transport = ScheduleInterceptor(
            scheduleBody("""{"schedules":[]}"""),
            ScheduleStep.Failure(IOException("synthetic disconnect")),
            scheduleBody("""{"schedules":[{"cronjob_id":"job-1","channel_id":"channel-1","message":"稍后见","send_at":$time}]}"""),
        )

        val created = repository(transport).createChatScheduledMessage(
            "channel-1", "稍后见", time, "request-1",
        )

        assertEquals("job-1", created.id)
        assertEquals(listOf("list", "create", "list"), transport.requests.map { it.fields()["method"] })
    }

    @Test
    fun `取消定时消息前后回读并确认消失`() = runBlocking {
        val time = System.currentTimeMillis() + 3_600_000
        val transport = ScheduleInterceptor(
            scheduleBody("""{"schedules":[{"cronjob_id":"synthetic-job","channel_id":"channel-1","message":"稍后见","send_at":$time}]}"""),
            scheduleBody("{}"),
            scheduleBody("""{"schedules":[]}"""),
        )

        repository(transport).deleteChatScheduledMessage("channel-1", "synthetic-job", "request-1")

        assertEquals(listOf("list", "delete", "list"), transport.requests.map { it.fields()["method"] })
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "chat/delete-scheduled-message/synthetic-message/request.json",
        )
        assertEquals("synthetic-job", transport.requests[1].fields()["cronjob_id"])
    }

    private fun repository(interceptor: ScheduleInterceptor) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "synthetic-session", "synthetic-token"),
        DsmApiClient(OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build()),
        mapOf(
            "SYNO.Chat.Post.Schedule" to ApiCapability("SYNO.Chat.Post.Schedule", "entry.cgi", 1, 1),
        ),
    )

    private fun scheduleBody(data: String) = ScheduleStep.Body("""{"success":true,"data":$data}""")
}

private sealed interface ScheduleStep {
    data class Body(val value: String) : ScheduleStep
    data class Failure(val error: IOException) : ScheduleStep
}

private class ScheduleInterceptor(vararg steps: ScheduleStep) : Interceptor {
    private val queue = ArrayDeque(steps.toList())
    val requests = CopyOnWriteArrayList<Request>()
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return when (val step = queue.removeFirstOrNull() ?: error("Unexpected request")) {
            is ScheduleStep.Failure -> throw step.error
            is ScheduleStep.Body -> Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK").body(step.value.toResponseBody()).build()
        }
    }
}

private fun Request.fields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}
