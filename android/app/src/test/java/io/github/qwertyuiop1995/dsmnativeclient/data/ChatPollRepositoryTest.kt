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

class ChatPollRepositoryTest {
    @Test
    fun `无附件投票固定v1且写后回读`() = runBlocking {
        val transport = PollInterceptor(
            posts("[]"),
            body("{}"),
            posts("""[{"post_id":"post-1","channel_id":"synthetic-channel","creator_id":"current","is_my_post":true,"create_at":${System.currentTimeMillis()},"message":"Synthetic question?","vote":{"vote_id":"vote-1","choices":[{"choice_id":"c1","text":"First choice"},{"choice_id":"c2","text":"Second choice"}],"options":"{\"multiple\":true,\"anonymous\":false}"}}]"""),
        )
        val repo = repository(transport)

        val created = repo.createChatPoll(
            "synthetic-channel", " Synthetic question? ",
            listOf("First choice", "Second choice"), true, false, "request-1",
        )

        assertEquals("vote-1", created.poll?.id)
        assertEquals(listOf("First choice", "Second choice"), created.poll?.options?.map { it.text })
        assertEquals(listOf("list", "create", "list"), transport.requests.map { it.pollFields()["method"] })
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "chat/create-poll/synthetic-poll/request.json",
        )
        val fields = transport.requests[1].pollFields()
        assertEquals("1", fields["version"])
        assertEquals("[\"First choice\",\"Second choice\"]", fields["choices"])
        assertEquals("{\"add_option\":false,\"anonymous\":false,\"multiple\":true}", fields["options"])
    }

    @Test
    fun `投票创建断线后只回读不重放`() = runBlocking {
        val now = System.currentTimeMillis()
        val transport = PollInterceptor(
            posts("[]"),
            PollStep.Failure(IOException("synthetic disconnect")),
            posts("""[{"post_id":"post-1","channel_id":"channel-1","is_my_post":true,"create_at":$now,"message":"问题","vote":{"choices":["A","B"],"options":"{\"multiple\":false,\"anonymous\":true}"}}]"""),
        )

        val created = repository(transport).createChatPoll(
            "channel-1", "问题", listOf("A", "B"), false, true, "request-1",
        )

        assertEquals("post-1", created.id)
        assertEquals(3, transport.requests.size)
    }

    @Test
    fun `重复投票选项在零请求时拒绝`() = runBlocking {
        val transport = PollInterceptor()
        var thrown = false
        try {
            repository(transport).createChatPoll(
                "channel-1", "问题", listOf("A", "a"), false, false, "request-1",
            )
        } catch (_: Throwable) {
            thrown = true
        }
        assertTrue(thrown)
        assertTrue(transport.requests.isEmpty())
    }

    private fun repository(interceptor: PollInterceptor) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "synthetic-session", "synthetic-token"),
        DsmApiClient(OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build()),
        mapOf(
            "SYNO.Chat.Post" to ApiCapability("SYNO.Chat.Post", "entry.cgi", 1, 8),
            "SYNO.Chat.Post.Vote" to ApiCapability("SYNO.Chat.Post.Vote", "entry.cgi", 1, 1),
        ),
    )

    private fun posts(value: String) = body("""{"posts":$value,"total":0}""")
    private fun body(data: String) = PollStep.Body("""{"success":true,"data":$data}""")
}

private sealed interface PollStep {
    data class Body(val value: String) : PollStep
    data class Failure(val error: IOException) : PollStep
}

private class PollInterceptor(vararg steps: PollStep) : Interceptor {
    private val queue = ArrayDeque(steps.toList())
    val requests = CopyOnWriteArrayList<Request>()
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return when (val step = queue.removeFirstOrNull() ?: error("Unexpected request")) {
            is PollStep.Failure -> throw step.error
            is PollStep.Body -> Response.Builder().request(request).protocol(Protocol.HTTP_1_1)
                .code(200).message("OK").body(step.value.toResponseBody()).build()
        }
    }
}

private fun Request.pollFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}
