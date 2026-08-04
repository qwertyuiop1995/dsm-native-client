package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSection
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
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

class VirtualMachineMutationResultTest {
    @Test
    fun `概览附加网络失败时仍返回虚拟机与主机`() = runBlocking {
        val transport = VmmOverviewInterceptor()
        val overview = repository(
            transport,
            GUEST,
            HOST,
            STORAGE,
            NETWORK,
            IMAGE,
        ).virtualMachineOverview()

        assertEquals(listOf("VM 1"), overview.machines.map { it.name })
        assertEquals(listOf("Host 1"), overview.hosts.map { it.name })
        assertTrue(VirtualMachineSection.NETWORKS in overview.unavailableSections)
        assertFalse(VirtualMachineSection.HOSTS in overview.unavailableSections)
        assertEquals("SYNO.Virtualization.Guest", transport.requests.first().formFields()["api"])
    }

    @Test
    fun `正常关机必须在列表回读为停止后才确认成功`() = runBlocking {
        val transport = VmmMutationInterceptor(
            guestList("running"),
            SUCCESS,
            guestList("shutdown"),
        )

        val result = repository(transport, API_GUEST, API_GUEST_ACTION)
            .controlVirtualMachineResult("guest-1", ResourceState.RUNNING, "shutdown")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "shutdown", "list"), transport.methods())
        assertEquals("guest-1", transport.requests[1].formFields()["guest_id"])
    }

    @Test
    fun `删除虚拟机必须回读消失且发送稳定标识`() = runBlocking {
        val transport = VmmMutationInterceptor(
            guestList("stopped"),
            SUCCESS,
            """{"success":true,"data":{"guests":[]}}""",
        )

        val result = repository(transport, API_GUEST).deleteVirtualMachineResult("guest-1")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "delete", "list"), transport.methods())
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "vmm/delete/synthetic-virtual-machine/request.json",
        )
        assertEquals("guest-1", transport.requests[1].formFields()["guest_id"])
    }

    @Test
    fun `内部网络改名契约未行为验证时零请求关闭`() = runBlocking {
        val transport = VmmMutationInterceptor()

        val result = repository(transport, NETWORK)
            .renameVirtualMachineNetworkResult("network-1", "Existing")

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertEquals(MutationErrorCategory.UNSUPPORTED, result.errorCategory)
        assertFalse(result.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `映像删除提交后回读断线标记未确认且不重放`() = runBlocking {
        val transport = VmmImageReadbackFailureInterceptor()

        val result = repository(transport, API_IMAGE).deleteVirtualMachineImageResult("image-1")

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.requiresRefresh)
        assertEquals(listOf("list", "delete", "list"), transport.methods())
        RequestFixtureAssertions.assertRequest(
            transport.requests[1],
            "vmm/delete-image/synthetic-image/request.json",
        )
    }

    @Test
    fun `内部网络删除契约未行为验证时零请求关闭`() = runBlocking {
        val transport = VmmMutationInterceptor()

        val result = repository(transport, NETWORK).deleteVirtualMachineNetworkResult("network-1")

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertFalse(result.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `仅有内部 Guest 时生命周期和删除均零请求关闭`() = runBlocking {
        val transport = VmmMutationInterceptor()
        val repository = repository(transport, GUEST, GUEST_ACTION)

        val control = repository.controlVirtualMachineResult(
            "guest-1",
            ResourceState.RUNNING,
            "shutdown",
        )
        val delete = repository.deleteVirtualMachineResult("guest-1")

        assertEquals(MutationResultStatus.UNSUPPORTED, control.status)
        assertEquals(MutationResultStatus.UNSUPPORTED, delete.status)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `仅有内部映像 API 时删除零请求关闭`() = runBlocking {
        val transport = VmmMutationInterceptor()

        val result = repository(transport, IMAGE).deleteVirtualMachineImageResult("image-1")

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `非官方生命周期动作即使存在公开能力也零请求拒绝`() = runBlocking {
        val transport = VmmMutationInterceptor()

        val result = repository(transport, API_GUEST, API_GUEST_ACTION)
            .controlVirtualMachineResult("guest-1", ResourceState.RUNNING, "pause")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(MutationErrorCategory.VALIDATION, result.errorCategory)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `缺少用户所见状态基线的旧生命周期入口零请求拒绝`() = runBlocking {
        val transport = VmmMutationInterceptor()

        val result = repository(transport, API_GUEST, API_GUEST_ACTION)
            .controlVirtualMachineResult("guest-1", "shutdown")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `生命周期锁内状态偏离用户所见基线时零写拒绝`() = runBlocking {
        val transport = VmmMutationInterceptor(guestList("shutdown"))

        val result = repository(transport, API_GUEST, API_GUEST_ACTION)
            .controlVirtualMachineResult("guest-1", ResourceState.RUNNING, "shutdown")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `生命周期动作与用户所见状态组合非法时零请求拒绝`() = runBlocking {
        val transport = VmmMutationInterceptor()

        val result = repository(transport, API_GUEST, API_GUEST_ACTION)
            .controlVirtualMachineResult("guest-1", ResourceState.PAUSED, "shutdown")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(MutationErrorCategory.VALIDATION, result.errorCategory)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `VMM 删除预检遇到缺失标识时不发送写请求`() = runBlocking {
        val transport = VmmMutationInterceptor(
            """{"success":true,"data":{"guests":[{"guest_name":"Synthetic","status":"shutdown"}]}}""",
        )

        val result = repository(transport, API_GUEST).deleteVirtualMachineResult("guest-1")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    @Test
    fun `VMM 删除预检遇到重复标识时不发送写请求`() = runBlocking {
        val duplicate = """{"success":true,"data":{"guests":[{"guest_id":"guest-1","guest_name":"One"},{"guest_id":"guest-1","guest_name":"Two"}]}}"""
        val transport = VmmMutationInterceptor(duplicate)

        val result = repository(transport, API_GUEST).deleteVirtualMachineResult("guest-1")

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.methods())
    }

    private fun repository(interceptor: Interceptor, vararg capabilities: String) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        capabilities.associateWith { name ->
            ApiCapability(name, "entry.cgi", 1, 1)
        },
    )

    private fun guestList(status: String) =
        """{"success":true,"data":{"guests":[{"id":"guest-1","name":"Synthetic","status":"$status"}]}}"""

    private companion object {
        const val GUEST = "SYNO.Virtualization.Guest"
        const val API_GUEST = "SYNO.Virtualization.API.Guest"
        const val API_GUEST_ACTION = "SYNO.Virtualization.API.Guest.Action"
        const val GUEST_ACTION = "SYNO.Virtualization.Guest.Action"
        const val HOST = "SYNO.Virtualization.Host"
        const val STORAGE = "SYNO.Virtualization.Repo"
        const val NETWORK = "SYNO.Virtualization.Network"
        const val IMAGE = "SYNO.Virtualization.Guest.Image"
        const val API_IMAGE = "SYNO.Virtualization.API.Guest.Image"
        const val SUCCESS = """{"success":true,"data":{}}"""
    }
}

private class VmmOverviewInterceptor : Interceptor {
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val body = when (request.formFields()["api"]) {
            "SYNO.Virtualization.Guest" ->
                """{"success":true,"data":{"guests":[{"id":"g1","name":"VM 1","status":"running"}]}}"""
            "SYNO.Virtualization.Host" ->
                """{"success":true,"data":{"hosts":[{"id":"h1","name":"Host 1","status":"normal"}]}}"""
            "SYNO.Virtualization.Repo" -> """{"success":true,"data":{"repos":[]}}"""
            "SYNO.Virtualization.Network" -> """{"success":false,"error":{"code":105}}"""
            "SYNO.Virtualization.Guest.Image" -> """{"success":true,"data":{"images":[]}}"""
            else -> error("未处理的合成 VMM API")
        }
        return vmmResponse(request, body)
    }
}

private class VmmMutationInterceptor(vararg responses: String) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return vmmResponse(
            request,
            pending.removeFirstOrNull() ?: error("缺少合成 VMM 响应"),
        )
    }

    fun methods(): List<String?> = requests.map { it.formFields()["method"] }
}

private class VmmImageReadbackFailureInterceptor : Interceptor {
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        if (requests.size == 3) throw IOException("synthetic disconnect")
        val body = if (requests.size == 1) {
            """{"success":true,"data":{"images":[{"id":"image-1","name":"Synthetic","status":"normal"}]}}"""
        } else {
            """{"success":true,"data":{}}"""
        }
        return vmmResponse(request, body)
    }

    fun methods(): List<String?> = requests.map { it.formFields()["method"] }
}

private fun vmmResponse(request: Request, body: String): Response = Response.Builder()
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
