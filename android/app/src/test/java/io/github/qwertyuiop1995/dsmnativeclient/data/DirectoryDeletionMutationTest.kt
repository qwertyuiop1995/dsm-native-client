package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasAccount
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasGroup
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import okhttp3.FormBody
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.BufferedSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectoryDeletionMutationTest {
    @Test
    fun `账号删除使用名称数组并在目录消失后确认成功`() = runBlocking {
        val transport = DirectoryInterceptor(userList(), SUCCESS, emptyUsers())

        val result = repository(transport).deleteAccountResult(account())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "delete", "list"), transport.methods())
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "users/delete/synthetic-account/request.json",
        )
        assertEquals(USER_API, transport.requests[1].directoryFields()["api"])
        assertEquals("[\"$ACCOUNT\"]", transport.requests[1].directoryFields()["name"])
        assertTrue(transport.requests.all { it.directoryFields()["version"] == "1" })
    }

    @Test
    fun `群组删除使用专用 API 与名称数组`() = runBlocking {
        val transport = DirectoryInterceptor(groupList(), SUCCESS, emptyGroups())

        val result = repository(transport).deleteGroupResult(group())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "groups/delete/synthetic-group/request.json",
        )
        assertEquals(GROUP_API, transport.requests[1].directoryFields()["api"])
        assertEquals("[\"$GROUP\"]", transport.requests[1].directoryFields()["name"])
    }

    @Test
    fun `当前登录账号与系统保留目标在访问网络前被拒绝`() = runBlocking {
        val accountTransport = DirectoryInterceptor()
        val groupTransport = DirectoryInterceptor()

        val account = repository(accountTransport).deleteAccountResult(
            NasAccount(null, "operator", null, null, false),
        )
        val group = repository(groupTransport).deleteGroupResult(
            NasGroup(null, "administrators", null),
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, account.status)
        assertEquals(MutationResultStatus.PERMISSION_DENIED, group.status)
        assertFalse(account.submitted)
        assertFalse(group.submitted)
        assertTrue(accountTransport.requests.isEmpty())
        assertTrue(groupTransport.requests.isEmpty())
    }

    @Test
    fun `目录未明确允许删除时不发送写请求`() = runBlocking {
        val transport = DirectoryInterceptor(userList(canDelete = false))

        val result = repository(transport).deleteAccountResult(account(canDelete = false))

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertEquals(MutationErrorCategory.PERMISSION, result.errorCategory)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `账号完整基线变化时严格冲突且零写入`() = runBlocking {
        val transport = DirectoryInterceptor(userList(description = "changed"))

        val result = repository(transport).deleteAccountResult(account())

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `账号删除后回读根缺失不得冒充目标消失`() = runBlocking {
        val transport = DirectoryInterceptor(userList(), SUCCESS, SUCCESS)

        val result = repository(transport).deleteAccountResult(account())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.submitted)
        assertEquals(1, transport.methods().count { it == "delete" })
    }

    @Test
    fun `账号 API 最低版本高于已验证版本时零请求返回不支持`() = runBlocking {
        val transport = DirectoryInterceptor()

        val result = repository(transport, userMinVersion = 2).deleteAccountResult(account())

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertFalse(result.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `账号删除明确权限拒绝时不自动重放`() = runBlocking {
        val transport = DirectoryInterceptor(userList(), PERMISSION_DENIED)

        val result = repository(transport).deleteAccountResult(account())

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertTrue(result.submitted)
        assertEquals(1, transport.methods().count { it == "delete" })
    }

    @Test
    fun `账号删除响应丢失后只回读且目标消失时确认成功`() = runBlocking {
        val transport = AmbiguousDirectoryInterceptor()

        val result = repository(transport).deleteAccountResult(account())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "delete", "list"), transport.methods())
    }

    @Test
    fun `群组删除响应丢失后只回读且不重放`() = runBlocking {
        val transport = AmbiguousDirectoryInterceptor(groupList(), emptyGroups())

        val result = repository(transport).deleteGroupResult(group())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "delete", "list"), transport.methods())
        assertEquals(1, transport.methods().count { it == "delete" })
    }

    @Test
    fun `群组删除写后畸形回读保持未确认`() = runBlocking {
        val transport = DirectoryInterceptor(groupList(), SUCCESS, SUCCESS)

        val result = repository(transport).deleteGroupResult(group())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.submitted)
        assertEquals(1, transport.methods().count { it == "delete" })
    }

    @Test
    fun `同一账号已有删除请求时第二次调用不访问网络`() = runBlocking {
        val transport = BlockingDirectoryInterceptor()
        val repo = repository(transport)
        val first = async(Dispatchers.IO) { repo.deleteAccountResult(account()) }
        assertTrue(transport.submissionStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.deleteAccountResult(account().copy(name = ACCOUNT.uppercase()))
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)

        transport.allowSubmission.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().status)
        assertEquals(listOf("list", "delete", "list"), transport.methods())
    }

    @Test
    fun `账号与群组删除在途取消只回读且不重放`() = runBlocking {
        val accountTransport = CancellingDirectoryInterceptor(userList(), SUCCESS)
        val accountResult = repository(accountTransport).deleteAccountResult(account())
        assertEquals(
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            accountResult.status,
        )
        assertTrue(accountResult.submitted)
        assertEquals(listOf("list", "delete", "list"), accountTransport.methods())
        assertEquals(1, accountTransport.methods().count { it == "delete" })

        val groupTransport = CancellingDirectoryInterceptor(groupList(), SUCCESS)
        val groupResult = repository(groupTransport).deleteGroupResult(group())
        assertEquals(
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            groupResult.status,
        )
        assertTrue(groupResult.submitted)
        assertEquals(listOf("list", "delete", "list"), groupTransport.methods())
        assertEquals(1, groupTransport.methods().count { it == "delete" })
    }

    @Test
    fun `Android 请求层可按公共 Fixture 编码账号创建`() = runBlocking {
        val transport = DirectoryInterceptor(SUCCESS)
        val api = DsmApiClient(OkHttpClient.Builder().addInterceptor(transport).build())

        api.call(
            NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
            DsmSession("test", "test-session", "test-token"),
            ApiCapability(USER_API, "entry.cgi", 1, 1),
            "create",
            mapOf(
                "name" to "synthetic-account",
                "password" to "synthetic-secret",
                "password_confirm" to "synthetic-secret",
                "description" to "synthetic-description",
                "email" to "synthetic@example.invalid",
                "expired" to "false",
            ),
        )

        RequestFixtureAssertions.assertRequest(
            transport.requests.single(),
            "users/create/synthetic-account/request.json",
        )
    }

    private fun repository(interceptor: Interceptor, userMinVersion: Int = 1) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        mapOf(
            USER_API to ApiCapability(USER_API, "entry.cgi", userMinVersion, 5),
            GROUP_API to ApiCapability(GROUP_API, "entry.cgi", 1, 5),
        ),
    )

    companion object {
        const val USER_API = "SYNO.Core.User"
        const val GROUP_API = "SYNO.Core.Group"
        const val ACCOUNT = "synthetic-account"
        const val GROUP = "synthetic-group"
        const val SUCCESS = """{"success":true,"data":{}}"""
        const val PERMISSION_DENIED = """{"success":false,"error":{"code":105}}"""
        fun userList(canDelete: Boolean = true, description: String? = null): String {
            val descriptionField = description?.let { "\"description\":\"$it\"," }.orEmpty()
            return """{"success":true,"data":{"users":[{$descriptionField"name":"$ACCOUNT","additional":{"can_delete":$canDelete}}]}}"""
        }
        fun groupList() =
            """{"success":true,"data":{"groups":[{"name":"$GROUP","additional":{"can_delete":true}}]}}"""
        fun emptyUsers() = """{"success":true,"data":{"users":[]}}"""
        fun emptyGroups() = """{"success":true,"data":{"groups":[]}}"""
        fun account(canDelete: Boolean = true) =
            NasAccount(null, ACCOUNT, null, null, false, canDelete)
        fun group() = NasGroup(null, GROUP, null, true)
    }
}

private class DirectoryInterceptor(vararg responses: String) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return directoryResponse(request, pending.removeFirstOrNull() ?: error("缺少合成目录响应"))
    }
    fun methods() = requests.map { it.directoryFields()["method"] }
}

private class AmbiguousDirectoryInterceptor(
    private val initialList: String = DirectoryDeletionMutationTest.userList(),
    private val finalList: String = DirectoryDeletionMutationTest.emptyUsers(),
) : Interceptor {
    val requests = mutableListOf<Request>()
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        if (requests.size == 2) throw IOException("synthetic ambiguous account delete")
        return directoryResponse(
            request,
            if (requests.size == 1) initialList else finalList,
        )
    }
    fun methods() = requests.map { it.directoryFields()["method"] }
}

private class BlockingDirectoryInterceptor : Interceptor {
    val submissionStarted = CountDownLatch(1)
    val allowSubmission = CountDownLatch(1)
    private val requests = mutableListOf<Request>()
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val index = synchronized(requests) { requests += request; requests.size }
        val body = when (index) {
            1 -> DirectoryDeletionMutationTest.userList()
            2 -> {
                submissionStarted.countDown()
                check(allowSubmission.await(2, TimeUnit.SECONDS)) { "等待合成账号删除请求放行超时" }
                DirectoryDeletionMutationTest.SUCCESS
            }
            else -> DirectoryDeletionMutationTest.emptyUsers()
        }
        return directoryResponse(request, body)
    }
    fun methods() = synchronized(requests) { requests.map { it.directoryFields()["method"] } }
}

private class CancellingDirectoryInterceptor(
    private val initialList: String,
    private val readbackList: String,
) : Interceptor {
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return when (requests.size) {
            1 -> directoryResponse(request, initialList)
            2 -> Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(DirectoryCancellationBody())
                .build()
            else -> directoryResponse(request, readbackList)
        }
    }

    fun methods() = requests.map { it.directoryFields()["method"] }
}

private class DirectoryCancellationBody : ResponseBody() {
    override fun contentType() = "application/json".toMediaType()
    override fun contentLength() = -1L
    override fun source(): BufferedSource =
        throw kotlinx.coroutines.CancellationException("synthetic directory cancellation")
}

private fun directoryResponse(request: Request, body: String): Response = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody("application/json".toMediaType()))
    .build()

private fun Request.directoryFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}
