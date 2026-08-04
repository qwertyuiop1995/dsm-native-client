package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.PackageInfo
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
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
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PackageUninstallMutationTest {
    @Test
    fun `卸载按共享 Fixture 传递稳定 ID 与 additional 中的桌面应用标识`() = runBlocking {
        val transport = UninstallInterceptor(
            packageList(uninstallable = true),
            SUCCESS,
            SUCCESS,
            EMPTY_LIST,
        )

        val result = repository(transport).uninstallPackageResult(packageInfo())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "feasibility_check", "uninstall", "list"), transport.methods())
        assertEquals("uninstall_check", transport.requests[1].fields()["type"])
        assertEquals("[\"$PACKAGE_ID\"]", transport.requests[1].fields()["packages"])
        assertEquals(UNINSTALL_API, transport.requests[2].fields()["api"])
        assertEquals(PACKAGE_ID, transport.requests[2].fields()["id"])
        assertEquals(
            "[\"synthetic-app-one\",\"synthetic-app-two\"]",
            transport.requests[2].fields()["dsm_apps"],
        )
        val request = transport.requests[2]
        RequestFixtureAssertions.assertRequest(
            request,
            "packages/uninstall/synthetic-package/request.json",
        )
        assertEquals(listOf("2", "2", "1", "2"), transport.requests.map { it.fields()["version"] })
    }

    @Test
    fun `系统或未明确允许卸载的套件不会发送检查与写请求`() = runBlocking {
        val transport = UninstallInterceptor(packageList(uninstallable = false))

        val result = repository(transport).uninstallPackageResult(packageInfo())

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `卸载可行性检查权限不足属于提交前拒绝`() = runBlocking {
        val transport = UninstallInterceptor(
            packageList(uninstallable = true),
            PERMISSION_DENIED,
        )

        val result = repository(transport).uninstallPackageResult(packageInfo())

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("list", "feasibility_check"), transport.methods())
    }

    @Test
    fun `卸载写请求被明确拒绝时不自动重放`() = runBlocking {
        val transport = UninstallInterceptor(
            packageList(uninstallable = true),
            SUCCESS,
            PERMISSION_DENIED,
        )

        val result = repository(transport).uninstallPackageResult(packageInfo())

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertTrue(result.submitted)
        assertEquals(1, transport.methods().count { it == "uninstall" })
    }

    @Test
    fun `卸载写请求断线后只回读且目标消失时确认成功`() = runBlocking {
        val transport = AmbiguousUninstallInterceptor()

        val result = repository(transport).uninstallPackageResult(packageInfo())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertTrue(result.submitted)
        assertEquals(listOf("list", "feasibility_check", "uninstall", "list"), transport.methods())
    }

    @Test
    fun `卸载后畸形回读不得把缺失列表根当作已消失`() = runBlocking {
        val transport = UninstallInterceptor(packageList(true), SUCCESS, SUCCESS, SUCCESS)

        val result = repository(transport).uninstallPackageResult(packageInfo())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(1, transport.methods().count { it == "uninstall" })
    }

    @Test
    fun `卸载 API 不支持已验证版本时零请求返回不支持`() = runBlocking {
        val transport = UninstallInterceptor()

        val result = repository(transport, uninstallMinVersion = 2)
            .uninstallPackageResult(packageInfo())

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertFalse(result.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `卸载专项刷新缺少卸载许可字段时严格失败`() = runBlocking {
        val body = """{"success":true,"data":{"packages":[{"id":"$PACKAGE_ID","name":"Synthetic Package","version":"1.0.0","status":"stopped","startable":true,"available_operation":["start"],"dsm_apps":[]}]}}"""
        val transport = UninstallInterceptor(body)

        val failure = runCatching { repository(transport).activePackagesForUninstall() }

        assertTrue(failure.isFailure)
    }

    @Test
    fun `同一套件正在卸载时启动操作共享目标锁`() = runBlocking {
        val transport = BlockingUninstallInterceptor()
        val repo = repository(transport)
        val original = packageInfo()
        val uninstall = async(Dispatchers.IO) { repo.uninstallPackageResult(original) }
        assertTrue(transport.submissionStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.controlPackageResult(original, "start")
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)

        transport.allowSubmission.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, uninstall.await().status)
        assertEquals(listOf("list", "feasibility_check", "uninstall", "list"), transport.methods())
    }

    private fun repository(interceptor: Interceptor, uninstallMinVersion: Int = 1) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        mapOf(
            PACKAGE_API to ApiCapability(PACKAGE_API, "entry.cgi", 1, 5),
            CONTROL_API to ApiCapability(CONTROL_API, "entry.cgi", 1, 5),
            UNINSTALL_API to ApiCapability(UNINSTALL_API, "entry.cgi", uninstallMinVersion, 5),
        ),
    )

    private fun packageList(uninstallable: Boolean): String {
        val installType = if (uninstallable) "user" else "system"
        val operations = if (uninstallable) "[\"uninstall\"]" else "[]"
        return """{"success":true,"data":{"packages":[{"id":"$PACKAGE_ID","name":"Synthetic Package","version":"1.0.0","additional":{"status":"stopped","startable":true,"install_type":"$installType","ctl_uninstall":$uninstallable,"available_operation":$operations,"dsm_apps":"synthetic-app-one synthetic-app-two"}}]}}"""
    }

    private fun packageInfo() = PackageInfo(
        id = PACKAGE_ID,
        name = "Synthetic Package",
        version = "1.0.0",
        status = ResourceState.STOPPED,
        description = null,
        canStart = false,
        canStop = false,
        canUninstall = true,
        dsmApps = listOf("synthetic-app-one", "synthetic-app-two"),
    )

    private companion object {
        const val PACKAGE_ID = "synthetic-package"
        const val PACKAGE_API = "SYNO.Core.Package"
        const val CONTROL_API = "SYNO.Core.Package.Control"
        const val UNINSTALL_API = "SYNO.Core.Package.Uninstallation"
        const val SUCCESS = """{"success":true,"data":{}}"""
        const val EMPTY_LIST = """{"success":true,"data":{"packages":[]}}"""
        const val PERMISSION_DENIED = """{"success":false,"error":{"code":105}}"""
    }
}

private class UninstallInterceptor(vararg responses: String) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return uninstallResponse(
            request,
            pending.removeFirstOrNull() ?: error("缺少合成套件卸载响应"),
        )
    }

    fun methods(): List<String?> = requests.map { it.fields()["method"] }
}

private class AmbiguousUninstallInterceptor : Interceptor {
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        if (requests.size == 3) throw IOException("synthetic ambiguous uninstall")
        val body = when (requests.size) {
            1 -> uninstallablePackageList()
            2 -> """{"success":true,"data":{}}"""
            else -> """{"success":true,"data":{"packages":[]}}"""
        }
        return uninstallResponse(request, body)
    }

    fun methods(): List<String?> = requests.map { it.fields()["method"] }
}

private class BlockingUninstallInterceptor : Interceptor {
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
            1 -> uninstallablePackageList()
            2 -> """{"success":true,"data":{}}"""
            3 -> {
                submissionStarted.countDown()
                check(allowSubmission.await(2, TimeUnit.SECONDS)) { "等待合成套件卸载请求放行超时" }
                """{"success":true,"data":{}}"""
            }
            else -> """{"success":true,"data":{"packages":[]}}"""
        }
        return uninstallResponse(request, body)
    }

    fun methods(): List<String?> = synchronized(requests) {
        requests.map { it.fields()["method"] }
    }
}

private fun uninstallablePackageList() =
    """{"success":true,"data":{"packages":[{"id":"synthetic-package","name":"Synthetic Package","version":"1.0.0","additional":{"status":"stopped","startable":true,"install_type":"user","ctl_uninstall":true,"available_operation":["uninstall"],"dsm_apps":"synthetic-app-one synthetic-app-two"}}]}}"""

private fun uninstallResponse(request: Request, body: String): Response = Response.Builder()
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
