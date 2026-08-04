package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind
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

class ChatConversationRepositoryTest {
    @Test
    fun `首次单聊固定v2且创建前后查重`() = runBlocking {
        val transport = ChatConversationInterceptor(
            body(users()), body(emptyChannels()), body("""{"success":true,"data":{"channel_id":"27"}}"""),
            body(users()), body(directChannels()),
        )
        val repo = repository(transport)

        val first = repo.openDirectChatConversation(" 2 ", "request-direct")
        val second = repo.openDirectChatConversation("2", "request-direct")

        assertEquals(first, second)
        assertEquals("27", first.id)
        assertEquals(ConversationKind.DIRECT, first.kind)
        assertEquals(5, transport.requests.size)
        val fields = transport.fields()[2]
        assertEquals("SYNO.Chat.Channel.Anonymous", fields["api"])
        assertEquals("2", fields["version"])
        assertEquals("initiate", fields["method"])
        assertEquals("[\"2\"]", fields["user_ids"])
        assertEquals("false", fields["encrypted"])
        assertEquals("[]", fields["channel_key_encs"])
        assertTrue(fields.keys.none { it.contains("request", ignoreCase = true) })
    }

    @Test
    fun `已有单聊直接复用且不提交写请求`() = runBlocking {
        val transport = ChatConversationInterceptor(body(users()), body(directChannels()))

        val conversation = repository(transport)
            .openDirectChatConversation("2", "request-existing")

        assertEquals("27", conversation.id)
        assertEquals(listOf("list", "list"), transport.fields().map { it["method"] })
    }

    @Test
    fun `私人群聊按v1创建加入邀请并复查成员`() = runBlocking {
        val transport = ChatConversationInterceptor(
            body(users()), body(emptyChannels()),
            body("""{"success":true,"data":{"channel_id":"42"}}"""),
            body("""{"success":true,"data":{}}"""),
            body("""{"success":true,"data":{}}"""),
            body(users()), body(groupChannels()),
            body("""{"success":true,"data":{"user_ids":[1,2,3],"broken_user_ids":[]}}"""),
            body(users()),
        )

        val group = repository(transport).createPrivateChatGroup(
            " 项目组 ", listOf("3", "2", "2"), "request-group",
        )

        assertEquals("42", group.id)
        assertEquals(ConversationKind.GROUP, group.kind)
        assertEquals(listOf("1", "2", "3"), group.memberIds)
        val fields = transport.fields()
        assertEquals(listOf("create", "join", "invite"), fields.slice(2..4).map { it["method"] })
        assertTrue(fields.slice(2..4).all { it["version"] == "1" })
        assertEquals("项目组", fields[2]["name"])
        assertEquals("private", fields[2]["type"])
        assertEquals("[\"2\",\"3\"]", fields[4]["user_ids"])
        assertEquals("[]", fields[4]["channel_key_encs"])
        assertEquals("get", fields[7]["method"])
        assertEquals("SYNO.Chat.Channel.Member", fields[7]["api"])
    }

    @Test
    fun `单聊能力不覆盖v2时零请求拒绝`() = runBlocking {
        val transport = ChatConversationInterceptor()

        assertThrows {
            repository(transport, anonymousMaximumVersion = 1)
                .openDirectChatConversation("2", "request-direct")
        }

        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `建群邀请断线不会自动重放`() = runBlocking {
        val transport = ChatConversationInterceptor(
            body(users()), body(emptyChannels()),
            body("""{"success":true,"data":{"channel_id":"42"}}"""),
            body("""{"success":true,"data":{}}"""),
            failure(IOException("synthetic disconnect")),
            body(users()), body(partialGroupChannels()),
            body("""{"success":true,"data":{"user_ids":[1],"broken_user_ids":[]}}"""), body(users()),
        )

        assertThrows {
            repository(transport).createPrivateChatGroup(
                "项目组", listOf("2", "3"), "request-group",
            )
        }

        assertEquals(9, transport.requests.size)
        assertEquals(1, transport.fields().count { it["method"] == "invite" })
    }

    @Test
    fun `用户明确重试建群时复用已创建群聊而不重复创建`() = runBlocking {
        val partialMembers = """{"success":true,"data":{"user_ids":[1],"broken_user_ids":[]}}"""
        val allMembers = """{"success":true,"data":{"user_ids":[1,2,3],"broken_user_ids":[]}}"""
        val transport = ChatConversationInterceptor(
            body(users()), body(emptyChannels()),
            body("""{"success":true,"data":{"channel_id":"42"}}"""),
            body("""{"success":true,"data":{}}"""),
            failure(IOException("synthetic disconnect")),
            body(users()), body(partialGroupChannels()), body(partialMembers), body(users()),
            body(users()), body(partialGroupChannels()), body(partialMembers), body(users()),
            body("""{"success":true,"data":{}}"""),
            body(users()), body(groupChannels()), body(allMembers), body(users()),
        )
        val repo = repository(transport)

        assertThrows {
            repo.createPrivateChatGroup("项目组", listOf("2", "3"), "request-first")
        }
        val group = repo.createPrivateChatGroup("项目组", listOf("2", "3"), "request-retry")

        assertEquals("42", group.id)
        val fields = transport.fields()
        assertEquals(1, fields.count { it["method"] == "create" })
        assertEquals(2, fields.count { it["method"] == "invite" })
        assertEquals("[\"2\",\"3\"]", fields.last { it["method"] == "invite" }["user_ids"])
    }

    @Test
    fun `Chat 会话请求层符合四份公共 Fixture`() = runBlocking {
        val transport = ChatConversationInterceptor(
            body("""{"success":true,"data":{}}"""),
            body("""{"success":true,"data":{}}"""),
            body("""{"success":true,"data":{}}"""),
            body("""{"success":true,"data":{}}"""),
        )
        val profile = NasProfile("test", "Test", "https://nas.example.invalid", "operator")
        val session = DsmSession("test", "test-session", "test-token")
        val api = DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(transport).build(),
        )

        api.call(
            profile, session, ApiCapability("SYNO.Chat.Channel.Anonymous", "entry.cgi", 1, 2),
            "initiate",
            mapOf("user_ids" to "[\"synthetic-user\"]", "encrypted" to "false", "channel_key_encs" to "[]"),
        )
        api.call(
            profile, session, ApiCapability("SYNO.Chat.Channel.Named", "entry.cgi", 1, 1),
            "create", mapOf("name" to "Synthetic group", "type" to "private"),
        )
        api.call(
            profile, session, ApiCapability("SYNO.Chat.Channel.Named", "entry.cgi", 1, 1),
            "join", mapOf("channel_id" to "synthetic-channel"),
        )
        api.call(
            profile, session, ApiCapability("SYNO.Chat.Channel.Named", "entry.cgi", 1, 1),
            "invite",
            mapOf(
                "channel_id" to "synthetic-channel",
                "user_ids" to "[\"synthetic-member-a\",\"synthetic-member-b\"]",
                "channel_key_encs" to "[]",
            ),
        )

        listOf(
            "chat/open-direct/synthetic-user/request.json",
            "chat/create-private-group/synthetic-group/request.json",
            "chat/join-private-group/synthetic-group/request.json",
            "chat/invite-private-group/synthetic-members/request.json",
        ).forEachIndexed { index, fixture ->
            RequestFixtureAssertions.assertRequest(transport.requests[index], fixture)
        }
    }

    private fun repository(
        interceptor: ChatConversationInterceptor,
        anonymousMaximumVersion: Int = 2,
    ) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build(),
        ),
        mapOf(
            "SYNO.Chat.User" to ApiCapability("SYNO.Chat.User", "entry.cgi", 1, 3),
            "SYNO.Chat.Channel" to ApiCapability("SYNO.Chat.Channel", "entry.cgi", 1, 5),
            "SYNO.Chat.Channel.Anonymous" to ApiCapability(
                "SYNO.Chat.Channel.Anonymous", "entry.cgi", 1, anonymousMaximumVersion,
            ),
            "SYNO.Chat.Channel.Named" to ApiCapability("SYNO.Chat.Channel.Named", "entry.cgi", 1, 1),
            "SYNO.Chat.Channel.Member" to ApiCapability("SYNO.Chat.Channel.Member", "entry.cgi", 1, 1),
        ),
    )

    private fun users() = """{"success":true,"data":{"current_user_id":"1","users":[
        {"user_id":"1","username":"operator","nickname":"Current"},
        {"user_id":"2","username":"member2","nickname":"Member 2"},
        {"user_id":"3","username":"member3","nickname":"Member 3"}
    ]}}"""

    private fun emptyChannels() = """{"success":true,"data":{"channels":[]}}"""

    private fun directChannels() = """{"success":true,"data":{"channels":[
        {"channel_id":"27","type":"anonymous","members":["1","2"],"member_count":2}
    ]}}"""

    private fun groupChannels() = """{"success":true,"data":{"channels":[
        {"channel_id":"42","type":"private","name":"项目组","members":["1","2","3"],"member_count":3}
    ]}}"""

    private fun partialGroupChannels() = """{"success":true,"data":{"channels":[
        {"channel_id":"42","type":"private","name":"项目组","members":["1"],"member_count":1}
    ]}}"""

    private fun body(value: String) = ChatConversationStep.Body(value)
    private fun failure(error: IOException) = ChatConversationStep.Failure(error)

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

private sealed interface ChatConversationStep {
    data class Body(val value: String) : ChatConversationStep
    data class Failure(val error: IOException) : ChatConversationStep
}

private class ChatConversationInterceptor(vararg steps: ChatConversationStep) : Interceptor {
    private val queue = ArrayDeque(steps.toList())
    val requests = CopyOnWriteArrayList<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return when (val step = queue.removeFirstOrNull() ?: error("Unexpected request")) {
            is ChatConversationStep.Failure -> throw step.error
            is ChatConversationStep.Body -> Response.Builder()
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
