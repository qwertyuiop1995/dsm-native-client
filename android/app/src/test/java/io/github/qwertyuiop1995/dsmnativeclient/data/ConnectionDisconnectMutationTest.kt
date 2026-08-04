package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
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

class ConnectionDisconnectMutationTest {
    @Test
    fun `网页连接使用设备标识且回读消失后确认成功`() = runBlocking {
        val transport = ConnectionInterceptor(httpList(), SUCCESS, EMPTY_LIST)

        val result = repository(transport).disconnectConnectionResult(httpId())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "kick_connection", "list"), transport.methods())
        val fields = transport.requests[1].fields()
        assertEquals("[]", fields["service_conn"])
        val target = Json.parseToJsonElement(fields.getValue("http_conn")).jsonArray.single().jsonObject
        assertEquals(DEVICE_ID, target["did"]?.jsonPrimitive?.content)
        assertEquals("operator", target["who"]?.jsonPrimitive?.content)
        assertEquals("synthetic-source", target["from"]?.jsonPrimitive?.content)
    }

    @Test
    fun `服务连接使用进程标识且不提交设备数组`() = runBlocking {
        val transport = ConnectionInterceptor(serviceList(), SUCCESS, EMPTY_LIST)

        val result = repository(transport).disconnectConnectionResult(serviceId())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        val fields = transport.requests[1].fields()
        assertEquals("[]", fields["http_conn"])
        val target = Json.parseToJsonElement(fields.getValue("service_conn")).jsonArray.single().jsonObject
        assertEquals(PROCESS_ID, target["pid"]?.jsonPrimitive?.content)
        assertEquals("SMB", target["type"]?.jsonPrimitive?.content)
    }

    @Test
    fun `列表未明确允许断开时不发送写请求`() = runBlocking {
        val transport = ConnectionInterceptor(httpList(canDisconnect = false))

        val result = repository(transport).disconnectConnectionResult(httpId())

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `断开请求明确权限拒绝时不自动重放`() = runBlocking {
        val transport = ConnectionInterceptor(httpList(), PERMISSION_DENIED)

        val result = repository(transport).disconnectConnectionResult(httpId())

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertTrue(result.submitted)
        assertEquals(1, transport.methods().count { it == "kick_connection" })
    }

    @Test
    fun `断开请求响应丢失后只回读且目标消失时确认成功`() = runBlocking {
        val transport = AmbiguousConnectionInterceptor()

        val result = repository(transport).disconnectConnectionResult(httpId())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "kick_connection", "list"), transport.methods())
    }

    @Test
    fun `同一连接已有断开请求时第二次调用不访问网络`() = runBlocking {
        val transport = BlockingConnectionInterceptor()
        val repo = repository(transport)
        val first = async(Dispatchers.IO) { repo.disconnectConnectionResult(httpId()) }
        assertTrue(transport.submissionStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.disconnectConnectionResult(httpId())
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)

        transport.allowSubmission.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().status)
        assertEquals(listOf("list", "kick_connection", "list"), transport.methods())
    }

    @Test
    fun `固定使用v1且能力范围不含v1时零请求关闭`() = runBlocking {
        val unsupported = ConnectionInterceptor(httpList())
        val unsupportedResult = repository(unsupported, minVersion = 2, maxVersion = 2)
            .disconnectConnectionResult(httpId())
        assertEquals(MutationResultStatus.UNSUPPORTED, unsupportedResult.status)
        assertFalse(unsupportedResult.submitted)
        assertTrue(unsupported.requests.isEmpty())

        val compatible = ConnectionInterceptor(httpList(), SUCCESS, EMPTY_LIST)
        val result = repository(compatible, minVersion = 1, maxVersion = 2)
            .disconnectConnectionResult(httpId())
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertTrue(compatible.requests.all { it.fields()["version"] == "1" })
    }

    @Test
    fun `写后回读缺少列表根时保持未确认且不重放`() = runBlocking {
        val malformed = """{"success":true,"data":{}}"""
        val transport = ConnectionInterceptor(
            httpList(),
            SUCCESS,
            *Array(8) { malformed },
        )

        val result = repository(transport).disconnectConnectionResult(httpId())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "kick_connection" })
    }

    @Test
    fun `写后目标原始设备标识仍存在时不因派生标识变化误报成功`() = runBlocking {
        val changedClassification =
            """{"success":true,"data":{"items":[{"pid":"99","did":"$DEVICE_ID","who":"operator","from":"synthetic-source","protocol":"SMB","type":"SMB","can_be_kicked":true}]}}"""
        val transport = ConnectionInterceptor(
            httpList(),
            SUCCESS,
            *Array(8) { changedClassification },
        )

        val result = repository(transport).disconnectConnectionResult(httpId())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(1, transport.methods().count { it == "kick_connection" })
    }

    @Test
    fun `写后疑似同一目标缺少设备标识时保持未确认`() = runBlocking {
        val missingIdentity =
            """{"success":true,"data":{"items":[{"pid":"88","who":"operator","from":"synthetic-source","descr":"File Station","protocol":"HTTPS","type":"HTTP/HTTPS","can_be_kicked":true}]}}"""
        val transport = ConnectionInterceptor(httpList(), SUCCESS, missingIdentity)

        val result = repository(transport).disconnectConnectionResult(httpId())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "kick_connection" })
    }

    @Test
    fun `同账号连接缺少明确当前标志时不推断为当前会话`() = runBlocking {
        val transport = ConnectionInterceptor(
            """{"success":true,"data":{"items":[{"pid":"$PROCESS_ID","who":"operator","from":"synthetic-source","protocol":"SMB","type":"SMB","can_be_kicked":true}]}}""",
        )

        val connections = repository(transport).activeConnections()

        assertEquals(1, connections.size)
        assertFalse(connections.single().isCurrent)
    }

    @Test
    fun `列表包含非对象条目时明确失败而不是解释为空列表`() = runBlocking {
        val transport = ConnectionInterceptor(
            """{"success":true,"data":{"items":["invalid"]}}""",
        )

        val result = runCatching { repository(transport).activeConnections() }

        assertTrue(result.isFailure)
    }

    @Test
    fun `连接预检在途取消不会发送断开请求`() = runBlocking {
        val transport = CancellableConnectionInterceptor(
            blockAt = 1,
            bodies = listOf(httpList()),
        )
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport).disconnectConnectionResult(httpId())
        }

        assertTrue(transport.entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        transport.release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, result?.status)
        assertFalse(result?.submitted ?: true)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `断开请求在途取消只回读不重放并报告需核对`() = runBlocking {
        val transport = CancellableConnectionInterceptor(
            blockAt = 2,
            bodies = listOf(httpList(), SUCCESS, httpList()),
        )
        var result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult? = null
        val job = launch(Dispatchers.Default) {
            result = repository(transport).disconnectConnectionResult(httpId())
        }

        assertTrue(transport.entered.await(5, TimeUnit.SECONDS))
        job.cancel()
        transport.release.countDown()
        job.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result?.status)
        assertTrue(result?.submitted == true)
        assertTrue(result?.requiresRefresh == true)
        assertEquals(1, transport.methods().count { it == "kick_connection" })
    }

    private fun repository(
        interceptor: Interceptor,
        minVersion: Int = 1,
        maxVersion: Int = 1,
    ) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        mapOf(API to ApiCapability(API, "entry.cgi", minVersion, maxVersion)),
    )

    companion object {
        const val API = "SYNO.Core.CurrentConnection"
        const val DEVICE_ID = "synthetic-device"
        const val PROCESS_ID = "4242"
        const val SUCCESS = """{"success":true,"data":{}}"""
        const val EMPTY_LIST = """{"success":true,"data":{"items":[]}}"""
        const val PERMISSION_DENIED = """{"success":false,"error":{"code":105}}"""

        fun httpId() = stableId("http", DEVICE_ID)
        fun serviceId() = stableId("service", PROCESS_ID)
        fun stableId(kind: String, identifier: String) = UUID.nameUUIDFromBytes(
            "$kind:$identifier".toByteArray(),
        ).toString()

        fun httpList(canDisconnect: Boolean = true) =
            """{"success":true,"data":{"items":[{"pid":"88","did":"$DEVICE_ID","who":"operator","from":"synthetic-source","descr":"File Station","protocol":"HTTPS","type":"HTTP/HTTPS","time":"2026-08-02 10:00:00","is_current_connected":true,"can_be_kicked":$canDisconnect}]}}"""

        fun serviceList() =
            """{"success":true,"data":{"items":[{"pid":"$PROCESS_ID","who":"operator","from":"synthetic-source","protocol":"SMB","type":"SMB","time":"2026-08-02 10:00:00","can_be_kicked":true}]}}"""
    }
}

private class ConnectionInterceptor(vararg responses: String) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return connectionResponse(
            request,
            pending.removeFirstOrNull() ?: error("缺少合成连接响应"),
        )
    }

    fun methods(): List<String?> = requests.map { it.fields()["method"] }
}

private class AmbiguousConnectionInterceptor : Interceptor {
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        if (requests.size == 2) throw IOException("synthetic ambiguous disconnect")
        val body = if (requests.size == 1) {
            ConnectionDisconnectMutationTest.httpList()
        } else {
            """{"success":true,"data":{"items":[]}}"""
        }
        return connectionResponse(request, body)
    }

    fun methods(): List<String?> = requests.map { it.fields()["method"] }
}

private class BlockingConnectionInterceptor : Interceptor {
    val submissionStarted = CountDownLatch(1)
    val allowSubmission = CountDownLatch(1)
    private val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val index = synchronized(requests) {
            requests += request
            requests.size
        }
        val body = when (index) {
            1 -> ConnectionDisconnectMutationTest.httpList()
            2 -> {
                submissionStarted.countDown()
                check(allowSubmission.await(2, TimeUnit.SECONDS)) { "等待合成断开请求放行超时" }
                """{"success":true,"data":{}}"""
            }
            else -> """{"success":true,"data":{"items":[]}}"""
        }
        return connectionResponse(request, body)
    }

    fun methods(): List<String?> = synchronized(requests) {
        requests.map { it.fields()["method"] }
    }
}

private class CancellableConnectionInterceptor(
    private val blockAt: Int,
    bodies: List<String>,
) : Interceptor {
    val entered = CountDownLatch(1)
    val release = CountDownLatch(1)
    private val pending = ArrayDeque(bodies)
    private val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val index = synchronized(requests) {
            requests += request
            requests.size
        }
        if (index == blockAt) {
            entered.countDown()
            check(release.await(5, TimeUnit.SECONDS)) { "等待合成连接请求放行超时" }
        }
        return connectionResponse(
            request,
            synchronized(pending) { pending.removeFirstOrNull() }
                ?: error("缺少合成连接响应"),
        )
    }

    fun methods(): List<String?> = synchronized(requests) {
        requests.map { it.fields()["method"] }
    }
}

private fun connectionResponse(request: Request, body: String): Response = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody("application/json".toMediaType()))
    .build()

private fun Request.fields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}
