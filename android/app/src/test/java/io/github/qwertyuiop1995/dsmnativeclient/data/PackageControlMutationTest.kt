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
import okio.BufferedSource
import okhttp3.FormBody
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PackageControlMutationTest {
    @Test
    fun `启动按 Fixture 顺序预检并携带稳定 ID 与桌面应用列表`() = runBlocking {
        val transport = PackageMutationInterceptor(
            packageList("stopped", startable = true),
            SUCCESS,
            SUCCESS,
            packageList("running", startable = false),
        )

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "feasibility_check", "start", "list"), transport.methods())
        RequestFixtureAssertions.assertRequest(
            transport.requests[2],
            "packages/start/synthetic-package/request.json",
        )
        assertEquals("start_check", transport.requests[1].formFields()["type"])
        assertEquals("[\"$PACKAGE_ID\"]", transport.requests[1].formFields()["packages"])
        assertEquals(PACKAGE_ID, transport.requests[2].formFields()["id"])
        assertEquals(
            "[\"synthetic-app-one\",\"synthetic-app-two\"]",
            transport.requests[2].formFields()["dsm_apps"],
        )
        assertEquals(listOf("2", "2", "1", "2"), transport.requests.map { it.formFields()["version"] })
    }

    @Test
    fun `停止按 Fixture 只提交稳定 ID 并回读停止状态`() = runBlocking {
        val transport = PackageMutationInterceptor(
            packageList("running", startable = false),
            SUCCESS,
            SUCCESS,
            packageList("stopped", startable = true),
        )

        val result = repository(transport).controlPackageResult(packageInfo("running", false), "stop")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "feasibility_check", "stop", "list"), transport.methods())
        RequestFixtureAssertions.assertRequest(
            transport.requests[2],
            "packages/stop/synthetic-package/request.json",
        )
        assertEquals("stop_check", transport.requests[1].formFields()["type"])
        assertEquals(PACKAGE_ID, transport.requests[2].formFields()["id"])
        assertFalse(transport.requests[2].formFields().containsKey("dsm_apps"))
    }

    @Test
    fun `当前状态不允许操作时不发送可行性检查或写请求`() = runBlocking {
        val transport = PackageMutationInterceptor(
            packageList("running", startable = false),
        )

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `可行性检查权限不足属于提交前权限拒绝`() = runBlocking {
        val transport = PackageMutationInterceptor(
            packageList("stopped", startable = true),
            """{"success":false,"error":{"code":105}}""",
        )

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertEquals(MutationErrorCategory.PERMISSION, result.errorCategory)
        assertFalse(result.submitted)
        assertEquals(listOf("list", "feasibility_check"), transport.methods())
    }

    @Test
    fun `套件权限字段缺失时失败关闭且零写入`() = runBlocking {
        val transport = PackageMutationInterceptor(
            """{"success":true,"data":{"packages":[{"id":"$PACKAGE_ID","name":"Synthetic Package","version":"1.0.0","status":"stopped","startable":true,"dsm_apps":[]}]}}""",
        )

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `套件完整基线变化时冲突且不执行可行性检查`() = runBlocking {
        val transport = PackageMutationInterceptor(packageList("stopped", startable = false))

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationErrorCategory.CONFLICT, result.errorCategory)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `控制写入后畸形回读不得确认成功`() = runBlocking {
        val transport = PackageMutationInterceptor(
            packageList("stopped", true), SUCCESS, SUCCESS, SUCCESS,
        )

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `套件读取最低版本超过二时零请求返回不支持`() = runBlocking {
        val transport = PackageMutationInterceptor()

        val result = repository(transport, packageMinVersion = 3)
            .controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertFalse(result.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `启停专项刷新不要求卸载专属权限字段`() = runBlocking {
        val transport = PackageMutationInterceptor(packageList("stopped", true))

        val packages = repository(transport).activePackagesForControl()

        assertEquals(PACKAGE_ID, packages.single().id)
        assertTrue(packages.single().canStart)
    }

    @Test
    fun `只有 available operation 明确包含 upgrade 才投影只读更新提示`() = runBlocking {
        val withUpgrade = PackageMutationInterceptor(
            """{"success":true,"data":{"packages":[{"id":"$PACKAGE_ID","name":"Synthetic Package","version":"1.0.0","status":"stopped","startable":true,"available_operation":["start","upgrade"],"dsm_apps":[]}]}}""",
        )
        val withoutUpgrade = PackageMutationInterceptor(packageList("stopped", true))

        assertTrue(repository(withUpgrade).activePackagesForControl().single().isUpgradeAvailable)
        assertFalse(repository(withoutUpgrade).activePackagesForControl().single().isUpgradeAvailable)
    }

    @Test
    fun `模糊控制写入最多专项回读三次且绝不重放`() = runBlocking {
        val transport = PackageAmbiguousUnconfirmedInterceptor()

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(3, transport.methods().count { it == "list" } - 1)
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `控制预检取消零写入并释放套件锁`() = runBlocking {
        val transport = CancellingPackageControlInterceptor(cancelMethod = "list")
        val repo = repository(transport)
        val original = packageInfo("stopped", true)

        val cancelled = repo.controlPackageResult(original, "start")

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, cancelled.status)
        assertFalse(cancelled.submitted)
        assertEquals(0, transport.methods().count { it == "start" })
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, repo.controlPackageResult(original, "start").status)
    }

    @Test
    fun `控制写请求在途取消只回读不重放并释放共享锁`() = runBlocking {
        val transport = CancellingPackageControlInterceptor(cancelMethod = "start")
        val repo = repository(transport)

        val cancelledButConfirmed = repo.controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, cancelledButConfirmed.status)
        assertTrue(cancelledButConfirmed.submitted)
        assertEquals(1, transport.methods().count { it == "start" })
        assertEquals(
            MutationResultStatus.CONFIRMED_SUCCESS,
            repo.controlPackageResult(packageInfo("running", false), "stop").status,
        )
        assertEquals(1, transport.methods().count { it == "stop" })
    }

    @Test
    fun `控制写入取消且状态未变化时只执行一次专项回读`() = runBlocking {
        val transport = CancellingPackageControlInterceptor(
            cancelMethod = "start",
            applyCancelledStart = false,
        )

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result.status)
        assertEquals(2, transport.methods().count { it == "list" })
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `写请求断线后只回读且状态已变化时确认成功`() = runBlocking {
        val transport = PackageAmbiguousSubmissionInterceptor()

        val result = repository(transport).controlPackageResult(packageInfo("stopped", true), "start")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertTrue(result.submitted)
        assertEquals(listOf("list", "feasibility_check", "start", "list"), transport.methods())
    }

    @Test
    fun `同一套件已有操作时第二次调用不发送请求`() = runBlocking {
        val transport = BlockingPackageMutationInterceptor()
        val repo = repository(transport)
        val original = packageInfo("stopped", true)
        val first = async(Dispatchers.IO) { repo.controlPackageResult(original, "start") }
        assertTrue(transport.submissionStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.controlPackageResult(original, "stop")
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)

        transport.allowSubmission.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().status)
        assertEquals(listOf("list", "feasibility_check", "start", "list"), transport.methods())
    }

    private fun repository(interceptor: Interceptor, packageMinVersion: Int = 1) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        mapOf(
            PACKAGE_API to ApiCapability(PACKAGE_API, "entry.cgi", packageMinVersion, 5),
            CONTROL_API to ApiCapability(CONTROL_API, "entry.cgi", 1, 5),
        ),
    )

    private fun packageList(status: String, startable: Boolean): String {
        val operation = if (status == "running") "stop" else "start"
        return """{"success":true,"data":{"packages":[{"id":"$PACKAGE_ID","name":"Synthetic Package","version":"1.0.0","status":"$status","startable":$startable,"available_operation":["$operation"],"dsm_apps":["synthetic-app-one","synthetic-app-two"]}]}}"""
    }

    private fun packageInfo(status: String, startable: Boolean) = PackageInfo(
        id = PACKAGE_ID,
        name = "Synthetic Package",
        version = "1.0.0",
        status = if (status == "running") ResourceState.RUNNING else ResourceState.STOPPED,
        description = null,
        canStart = status == "stopped" && startable,
        canStop = status == "running",
        dsmApps = listOf("synthetic-app-one", "synthetic-app-two"),
    )

    private companion object {
        const val PACKAGE_ID = "synthetic-package"
        const val PACKAGE_API = "SYNO.Core.Package"
        const val CONTROL_API = "SYNO.Core.Package.Control"
        const val SUCCESS = """{"success":true,"data":{}}"""
    }
}

private class PackageMutationInterceptor(vararg responses: String) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return packageResponse(
            request,
            pending.removeFirstOrNull() ?: error("缺少合成套件控制响应"),
        )
    }

    fun methods(): List<String?> = requests.map { it.formFields()["method"] }
}

private class PackageAmbiguousSubmissionInterceptor : Interceptor {
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        if (requests.size == 3) throw IOException("synthetic ambiguous submission")
        val body = when (requests.size) {
            1 -> """{"success":true,"data":{"packages":[{"id":"synthetic-package","name":"Synthetic Package","version":"1.0.0","status":"stopped","startable":true,"available_operation":["start"],"dsm_apps":["synthetic-app-one","synthetic-app-two"]}]}}"""
            2 -> """{"success":true,"data":{}}"""
            else -> """{"success":true,"data":{"packages":[{"id":"synthetic-package","name":"Synthetic Package","version":"1.0.0","status":"running","startable":false,"available_operation":["stop"],"dsm_apps":["synthetic-app-one","synthetic-app-two"]}]}}"""
        }
        return packageResponse(request, body)
    }

    fun methods(): List<String?> = requests.map { it.formFields()["method"] }
}

private class PackageAmbiguousUnconfirmedInterceptor : Interceptor {
    private val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val method = request.formFields()["method"]
        if (method == "start") throw IOException("synthetic ambiguous unconfirmed submission")
        val body = if (method == "list") {
            packageControlList("stopped", true, "start")
        } else {
            """{"success":true,"data":{}}"""
        }
        return packageResponse(request, body)
    }

    fun methods(): List<String?> = requests.map { it.formFields()["method"] }
}

private class BlockingPackageMutationInterceptor : Interceptor {
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
            1 -> """{"success":true,"data":{"packages":[{"id":"synthetic-package","name":"Synthetic Package","version":"1.0.0","status":"stopped","startable":true,"available_operation":["start"],"dsm_apps":["synthetic-app-one","synthetic-app-two"]}]}}"""
            2 -> """{"success":true,"data":{}}"""
            3 -> {
                submissionStarted.countDown()
                check(allowSubmission.await(2, TimeUnit.SECONDS)) { "等待合成套件写请求放行超时" }
                """{"success":true,"data":{}}"""
            }
            else -> """{"success":true,"data":{"packages":[{"id":"synthetic-package","name":"Synthetic Package","version":"1.0.0","status":"running","startable":false,"available_operation":["stop"],"dsm_apps":["synthetic-app-one","synthetic-app-two"]}]}}"""
        }
        return packageResponse(request, body)
    }

    fun methods(): List<String?> = synchronized(requests) {
        requests.map { it.formFields()["method"] }
    }
}

private class CancellingPackageControlInterceptor(
    private val cancelMethod: String,
    private val applyCancelledStart: Boolean = true,
) : Interceptor {
    private var cancelled = false
    private var running = false
    private val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val method = request.formFields()["method"]
        if (!cancelled && method == cancelMethod) {
            cancelled = true
            if (method == "start" && applyCancelledStart) running = true
            return Response.Builder()
                .request(request)
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(PackageCancellationResponseBody())
                .build()
        }
        val body = when (method) {
            "list" -> if (running) packageControlList("running", false, "stop")
                else packageControlList("stopped", true, "start")
            "start" -> SUCCESS_BODY.also { running = true }
            "stop" -> SUCCESS_BODY.also { running = false }
            else -> SUCCESS_BODY
        }
        return packageResponse(request, body)
    }

    fun methods(): List<String?> = requests.map { it.formFields()["method"] }

    private companion object {
        const val SUCCESS_BODY = """{"success":true,"data":{}}"""
    }
}

private class PackageCancellationResponseBody : ResponseBody() {
    override fun contentType() = "application/json".toMediaType()
    override fun contentLength() = -1L
    override fun source(): BufferedSource =
        throw kotlinx.coroutines.CancellationException("synthetic package cancellation")
}

private fun packageControlList(status: String, startable: Boolean, operation: String) =
    """{"success":true,"data":{"packages":[{"id":"synthetic-package","name":"Synthetic Package","version":"1.0.0","status":"$status","startable":$startable,"available_operation":["$operation"],"dsm_apps":["synthetic-app-one","synthetic-app-two"]}]}}"""

private fun packageResponse(request: Request, body: String): Response = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody("application/json".toMediaType()))
    .build()

private fun Request.formFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}
