package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasRemoteAccessSettings
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteAccessSettingsMutationTest {
    @Test
    fun `读取使用固定版本严格布尔并只在记录环境开放管理`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            ok(relay(true)), ok(router(false)), ok(recordedSystem()),
        )

        val settings = repository(transport, quickConnectMax = 5, upnpMax = 5)
            .remoteAccessSettings()

        assertEquals(NasRemoteAccessSettings(true, false, false, true), settings)
        assertEquals(listOf("3", "1", "3"), transport.versions())
    }

    @Test
    fun `字符串数字对象数组和缺失值都不是可信布尔`() = runBlocking {
        val malformedValues = listOf("\"true\"", "1", "{}", "[]", null)
        malformedValues.forEach { value ->
            val relayData = value?.let { """{"relay_enabled":$it}""" } ?: "{}"
            val routerData = value?.let { """{"enabled":$it}""" } ?: "{}"
            val transport = RemoteAccessInterceptor(ok(relayData), ok(routerData))
            var failure: Throwable? = null
            try {
                repository(transport).remoteAccessSettings()
            } catch (error: Throwable) {
                failure = error
            }
            assertTrue("非布尔值 $value 不应被接受", failure != null)
            assertEquals(2, transport.requests.size)
        }
    }

    @Test
    fun `单项读取失败保留另一项且不伪装关闭`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            fail(IOException("synthetic relay failure")), ok(router(true)), ok(recordedSystem()),
        )

        val settings = repository(transport).remoteAccessSettings()

        assertNull(settings.isRelayEnabled)
        assertEquals(true, settings.isRouterConfigurationEnabled)
        assertTrue(settings.canManage)
    }

    @Test
    fun `非记录环境只读且保存零写请求`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            ok(relay(true)), ok(router(false)), ok(recordedSystem(update = 11)),
        )
        val repo = repository(transport)
        val original = repo.remoteAccessSettings()

        val result = repo.saveRemoteAccessSettingsResult(
            original,
            original.copy(isRouterConfigurationEnabled = true),
        )

        assertFalse(original.canManage)
        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertFalse(result.submitted)
        assertTrue(transport.methods().none { it == "set" || it == "set_misc_config" })
    }

    @Test
    fun `可信中继连接禁止关闭中继且直连域不被误判`() = runBlocking {
        val blockedTransport = RemoteAccessInterceptor()
        val blocked = repository(
            blockedTransport,
            address = "https://synthetic.r1.quickconnect.to",
        ).saveRemoteAccessSettingsResult(
            settings(relay = true, trustedRelay = true),
            settings(relay = false, trustedRelay = true),
        )
        assertEquals(MutationErrorCategory.CONFLICT, blocked.errorCategory)
        assertTrue(blockedTransport.requests.isEmpty())

        val directTransport = RemoteAccessInterceptor(
            ok(relay(true)), ok(router(false)), ok(recordedSystem()),
            ok(),
            ok(relay(false)), ok(router(false)), ok(recordedSystem()),
        )
        val direct = repository(
            directTransport,
            address = "https://synthetic.direct.quickconnect.to",
        ).saveRemoteAccessSettingsResult(settings(), settings(relay = false))
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, direct.status)
    }

    @Test
    fun `无变化基线漂移和能力缺口均零写入`() = runBlocking {
        val noChangeTransport = RemoteAccessInterceptor()
        val noChange = repository(noChangeTransport).saveRemoteAccessSettingsResult(settings(), settings())
        assertEquals(MutationErrorCategory.CONFLICT, noChange.errorCategory)
        assertTrue(noChangeTransport.requests.isEmpty())

        val driftTransport = RemoteAccessInterceptor(
            ok(relay(false)), ok(router(false)), ok(recordedSystem()),
        )
        val drift = repository(driftTransport).saveRemoteAccessSettingsResult(
            settings(), settings(router = true),
        )
        assertEquals(MutationErrorCategory.CONFLICT, drift.errorCategory)
        assertTrue(driftTransport.methods().none { it == "set" || it == "set_misc_config" })

        val missingTransport = RemoteAccessInterceptor()
        val missing = repository(missingTransport, includeUpnp = false).saveRemoteAccessSettingsResult(
            settings(), settings(relay = false, router = true),
        )
        assertEquals(MutationResultStatus.UNSUPPORTED, missing.status)
        assertTrue(missingTransport.requests.isEmpty())
    }

    @Test
    fun `两项写入按固定顺序执行并完整回读确认`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            ok(relay(true)), ok(router(false)), ok(recordedSystem()),
            ok(), ok(),
            ok(relay(false)), ok(router(true)), ok(recordedSystem()),
        )

        val result = repository(transport).saveRemoteAccessSettingsResult(
            settings(), settings(relay = false, router = true),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(2, result.counts.succeeded)
        assertEquals(
            listOf("get_misc_config", "get", "info", "set_misc_config", "set", "get_misc_config", "get", "info"),
            transport.methods(),
        )
        assertEquals(listOf("3", "1", "3", "3", "1", "3", "1", "3"), transport.versions())
    }

    @Test
    fun `第二步权限失败报告部分成功且不重放`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            ok(relay(true)), ok(router(false)), ok(recordedSystem()),
            ok(), apiError(105),
            ok(relay(false)), ok(router(false)), ok(recordedSystem()),
        )

        val result = repository(transport).saveRemoteAccessSettingsResult(
            settings(), settings(relay = false, router = true),
        )

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertEquals(1, transport.methods().count { it == "set" })
        assertEquals(1, transport.methods().count { it == "set_misc_config" })
    }

    @Test
    fun `提交断线后只回读确认不重放`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            ok(relay(true)), ok(router(false)), ok(recordedSystem()),
            fail(IOException("synthetic disconnect")),
            ok(relay(false)), ok(router(false)), ok(recordedSystem()),
        )

        val result = repository(transport).saveRemoteAccessSettingsResult(
            settings(), settings(relay = false),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(1, transport.methods().count { it == "set_misc_config" })
    }

    @Test
    fun `回读单字段失败必须要求刷新而不是确认成功`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            ok(relay(true)), ok(router(false)), ok(recordedSystem()), ok(),
            fail(IOException("synthetic readback failure")), ok(router(false)), ok(recordedSystem()),
        )

        val result = repository(transport).saveRemoteAccessSettingsResult(
            settings(), settings(relay = false),
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.requiresRefresh)
        assertEquals(1, result.counts.unknown)
    }

    @Test
    fun `预检取消零写入并释放互斥锁供重试`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            cancellation(),
            ok(relay(true)), ok(router(false)), ok(recordedSystem()), ok(),
            ok(relay(false)), ok(router(false)), ok(recordedSystem()),
        )
        val repo = repository(transport)

        val cancelled = repo.saveRemoteAccessSettingsResult(settings(), settings(relay = false))
        val retry = repo.saveRemoteAccessSettingsResult(settings(), settings(relay = false))

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, cancelled.status)
        assertFalse(cancelled.submitted)
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, retry.status)
        assertEquals(1, transport.methods().count { it == "set_misc_config" })
    }

    @Test
    fun `提交阶段取消后仍回读且释放互斥锁供重试`() = runBlocking {
        val transport = RemoteAccessInterceptor(
            ok(relay(true)), ok(router(false)), ok(recordedSystem()), cancellation(),
            ok(relay(true)), ok(router(false)), ok(recordedSystem()),
            ok(relay(true)), ok(router(false)), ok(recordedSystem()), ok(),
            ok(relay(false)), ok(router(false)), ok(recordedSystem()),
        )
        val repo = repository(transport)

        val cancelled = repo.saveRemoteAccessSettingsResult(settings(), settings(relay = false))
        val retry = repo.saveRemoteAccessSettingsResult(settings(), settings(relay = false))

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, cancelled.status)
        assertTrue(cancelled.submitted)
        assertTrue(cancelled.requiresRefresh)
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, retry.status)
        assertEquals(2, transport.methods().count { it == "set_misc_config" })
    }

    @Test
    fun `并发保存由全局互斥拒绝重复写入`() = runBlocking {
        val transport = BlockingRemoteAccessInterceptor()
        val repo = repository(transport)
        val first = async(Dispatchers.IO) {
            repo.saveRemoteAccessSettingsResult(settings(), settings(relay = false))
        }
        assertTrue(transport.submissionStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.saveRemoteAccessSettingsResult(settings(), settings(router = true))

        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)
        transport.allowSubmission.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().status)
        assertEquals(1, transport.methods().count { it == "set_misc_config" })
    }

    private fun repository(
        interceptor: Interceptor,
        quickConnectMax: Int = 5,
        upnpMax: Int = 5,
        includeUpnp: Boolean = true,
        address: String = "https://nas.example.invalid",
    ): DsmRepository {
        val capabilities = mutableMapOf(
            "SYNO.Core.QuickConnect" to ApiCapability(
                "SYNO.Core.QuickConnect", "entry.cgi", 1, quickConnectMax,
            ),
            "SYNO.Core.System" to ApiCapability("SYNO.Core.System", "entry.cgi", 1, 3),
        )
        if (includeUpnp) capabilities["SYNO.Core.QuickConnect.Upnp"] = ApiCapability(
            "SYNO.Core.QuickConnect.Upnp", "entry.cgi", 1, upnpMax,
        )
        return DsmRepository(
            NasProfile("test", "Test", address, "operator"),
            DsmSession("test", "test-session", "test-token"),
            DsmApiClient(
                OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build(),
            ),
            capabilities,
        )
    }

    private fun settings(
        relay: Boolean = true,
        router: Boolean = false,
        trustedRelay: Boolean = false,
    ) = NasRemoteAccessSettings(relay, router, trustedRelay, true)

    private fun relay(enabled: Boolean) = """{"relay_enabled":$enabled}"""
    private fun router(enabled: Boolean) = """{"enabled":$enabled}"""
    private fun recordedSystem(update: Int = 12) =
        """{"firmware_ver":"DSM 7.2.1-69057 Update $update","buildnumber":"69057","smallfixnumber":"$update"}"""
    private fun ok(data: String = "{}") = RemoteAccessStep.Body("""{"success":true,"data":$data}""")
    private fun apiError(code: Int) = RemoteAccessStep.Body("""{"success":false,"error":{"code":$code}}""")
    private fun fail(error: IOException) = RemoteAccessStep.Failure(error)
    private fun cancellation() = RemoteAccessStep.Cancellation
}

private sealed interface RemoteAccessStep {
    data class Body(val value: String) : RemoteAccessStep
    data class Failure(val error: IOException) : RemoteAccessStep
    data object Cancellation : RemoteAccessStep
}

private class RemoteAccessInterceptor(vararg steps: RemoteAccessStep) : Interceptor {
    private val queue = ArrayDeque(steps.toList())
    val requests = CopyOnWriteArrayList<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return when (val step = queue.removeFirstOrNull() ?: error("未预期的请求：${request.url}")) {
            is RemoteAccessStep.Failure -> throw step.error
            RemoteAccessStep.Cancellation -> response(request, RemoteAccessCancellationBody())
            is RemoteAccessStep.Body -> response(
                request,
                step.value.toResponseBody("application/json".toMediaType()),
            )
        }
    }

    fun fields(): List<Map<String, String>> = requests.map(Request::remoteAccessFields)
    fun methods(): List<String> = fields().map { it["method"].orEmpty() }
    fun versions(): List<String> = fields().map { it["version"].orEmpty() }
}

private class RemoteAccessCancellationBody : ResponseBody() {
    override fun contentType() = "application/json".toMediaType()
    override fun contentLength() = -1L
    override fun source(): BufferedSource =
        throw kotlinx.coroutines.CancellationException("synthetic remote access cancellation")
}

private class BlockingRemoteAccessInterceptor : Interceptor {
    val submissionStarted = CountDownLatch(1)
    val allowSubmission = CountDownLatch(1)
    private val requests = CopyOnWriteArrayList<Request>()
    private var relayEnabled = true

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val fields = request.remoteAccessFields()
        val data = when (fields["api"] to fields["method"]) {
            "SYNO.Core.QuickConnect" to "get_misc_config" -> """{"relay_enabled":$relayEnabled}"""
            "SYNO.Core.QuickConnect.Upnp" to "get" -> """{"enabled":false}"""
            "SYNO.Core.System" to "info" ->
                """{"firmware_ver":"DSM 7.2.1-69057 Update 12","buildnumber":"69057","smallfixnumber":"12"}"""
            "SYNO.Core.QuickConnect" to "set_misc_config" -> {
                submissionStarted.countDown()
                check(allowSubmission.await(2, TimeUnit.SECONDS)) { "等待远程访问合成写请求放行超时" }
                relayEnabled = false
                "{}"
            }
            else -> error("未预期的请求：$fields")
        }
        return response(
            request,
            """{"success":true,"data":$data}""".toResponseBody("application/json".toMediaType()),
        )
    }

    fun methods() = requests.map { it.remoteAccessFields()["method"].orEmpty() }
}

private fun Request.remoteAccessFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return buildMap { repeat(form.size) { put(form.name(it), form.value(it)) } }
}

private fun response(request: Request, body: ResponseBody): Response = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body)
    .build()
