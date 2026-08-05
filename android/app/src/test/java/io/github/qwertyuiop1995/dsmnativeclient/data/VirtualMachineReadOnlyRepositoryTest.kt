package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineDiskController
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineNetworkModel
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSection
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineTaskCenterState
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
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

class VirtualMachineReadOnlyRepositoryTest {
    @Test
    fun `官方 Guest v1 保留磁盘网卡且任务中心只发送 list 和 get`() = runBlocking {
        val transport = VirtualMachineReadOnlyInterceptor(
            taskList = """{"success":true,"data":{"task_ids":["private-task-a","private-task-b"]}}""",
            taskDetails = ArrayDeque(
                listOf(
                    """{"success":true,"data":{"finish":false,"task_info":{"progress":40,"status":"create"}}}""",
                    """{"success":true,"data":{"finish":true,"task_info":{"progress":100,"status":"import"}}}""",
                ),
            ),
        )

        val overview = repository(transport, API_GUEST, TASK_INFO).virtualMachineOverview()

        val hardware = overview.machineHardware.single()
        assertEquals("guest-1", hardware.machineId)
        assertEquals(VirtualMachineDiskController.VIRTIO, hardware.disks.single().controller)
        assertEquals(10_240, hardware.disks.single().sizeMiB)
        assertTrue(hardware.disks.single().spaceReclamationEnabled)
        assertEquals(VirtualMachineNetworkModel.E1000, hardware.networkInterfaces.single().model)
        assertEquals("network-1", hardware.networkInterfaces.single().networkId)
        assertEquals("Default Network", hardware.networkInterfaces.single().networkName)
        assertFalse(hardware.toString().contains("02:11:32", ignoreCase = true))

        assertEquals(VirtualMachineTaskCenterState.AVAILABLE, overview.taskCenterState)
        assertEquals(listOf("task-1", "task-2"), overview.tasks.map { it.id })
        assertEquals(listOf(false, true), overview.tasks.map { it.isFinished })
        assertEquals(listOf(40, 100), overview.tasks.map { it.progressPercent })
        assertFalse(overview.tasks.toString().contains("private-task"))
        assertFalse(VirtualMachineSection.HARDWARE in overview.unavailableSections)
        assertFalse(VirtualMachineSection.TASKS in overview.unavailableSections)

        val guestRequest = transport.requests.first { it.fields()["api"] == API_GUEST }
        assertEquals("1", guestRequest.fields()["version"])
        assertEquals("true", guestRequest.fields()["additional"])
        val taskRequests = transport.requests.filter { it.fields()["api"] == TASK_INFO }
        assertEquals(listOf("list", "get", "get"), taskRequests.map { it.fields()["method"] })
        assertEquals(listOf(null, "private-task-a", "private-task-b"), taskRequests.map {
            it.fields()["task_id"]
        })
        assertFalse(transport.requests.any { it.fields()["method"] == "clear" })
    }

    @Test
    fun `任务能力缺失与合法空列表具有不同状态`() = runBlocking {
        val unavailableTransport = VirtualMachineReadOnlyInterceptor()
        val unavailable = repository(unavailableTransport, API_GUEST).virtualMachineOverview()

        assertEquals(
            VirtualMachineTaskCenterState.CAPABILITY_UNAVAILABLE,
            unavailable.taskCenterState,
        )
        assertTrue(VirtualMachineSection.TASKS in unavailable.unavailableSections)
        assertTrue(unavailable.tasks.isEmpty())
        assertFalse(unavailableTransport.requests.any { it.fields()["api"] == TASK_INFO })

        val emptyTransport = VirtualMachineReadOnlyInterceptor(
            taskList = """{"success":true,"data":{"task_ids":[]}}""",
        )
        val empty = repository(emptyTransport, API_GUEST, TASK_INFO).virtualMachineOverview()

        assertEquals(VirtualMachineTaskCenterState.AVAILABLE, empty.taskCenterState)
        assertFalse(VirtualMachineSection.TASKS in empty.unavailableSections)
        assertTrue(empty.tasks.isEmpty())
        assertEquals(
            listOf("list"),
            emptyTransport.requests.filter { it.fields()["api"] == TASK_INFO }
                .map { it.fields()["method"] },
        )
    }

    @Test
    fun `任务列表畸形时标记无效响应且不继续读取详情`() = runBlocking {
        val transport = VirtualMachineReadOnlyInterceptor(
            taskList = """{"success":true,"data":{"task_ids":{}}}""",
        )

        val overview = repository(transport, API_GUEST, TASK_INFO).virtualMachineOverview()

        assertEquals(VirtualMachineTaskCenterState.INVALID_RESPONSE, overview.taskCenterState)
        assertTrue(VirtualMachineSection.TASKS in overview.unavailableSections)
        assertTrue(overview.tasks.isEmpty())
        assertEquals(
            listOf("list"),
            transport.requests.filter { it.fields()["api"] == TASK_INFO }
                .map { it.fields()["method"] },
        )
    }

    @Test
    fun `任务读取失败只关闭任务分区而保留虚拟机`() = runBlocking {
        val transport = VirtualMachineReadOnlyInterceptor(
            taskList = """{"success":false,"error":{"code":105}}""",
        )

        val overview = repository(transport, API_GUEST, TASK_INFO).virtualMachineOverview()

        assertEquals(listOf("Synthetic VM"), overview.machines.map { it.name })
        assertEquals(VirtualMachineTaskCenterState.LOAD_FAILED, overview.taskCenterState)
        assertTrue(VirtualMachineSection.TASKS in overview.unavailableSections)
    }

    @Test
    fun `任务列表超过上限时零详情请求关闭`() = runBlocking {
        val ids = (1..101).joinToString(",") { "\"task-$it\"" }
        val transport = VirtualMachineReadOnlyInterceptor(
            taskList = """{"success":true,"data":{"task_ids":[$ids]}}""",
        )

        val overview = repository(transport, API_GUEST, TASK_INFO).virtualMachineOverview()

        assertEquals(VirtualMachineTaskCenterState.INVALID_RESPONSE, overview.taskCenterState)
        assertEquals(
            listOf("list"),
            transport.requests.filter { it.fields()["api"] == TASK_INFO }
                .map { it.fields()["method"] },
        )
    }

    @Test
    fun `官方 Guest 磁盘结构畸形时只关闭硬件而保留主列表`() = runBlocking {
        val transport = VirtualMachineReadOnlyInterceptor(
            guestList = """{"success":true,"data":{"guests":[{"guest_id":"guest-1","guest_name":"VM","status":"shutdown","vdisks":{},"vnics":[]}]}}""",
        )

        val overview = repository(transport, API_GUEST).virtualMachineOverview()

        assertEquals(listOf("VM"), overview.machines.map { it.name })
        assertTrue(overview.machineHardware.isEmpty())
        assertTrue(VirtualMachineSection.HARDWARE in overview.unavailableSections)
    }

    @Test
    fun `官方 Guest 附加读取失败时回退普通主列表并只关闭硬件`() = runBlocking {
        val transport = VirtualMachineReadOnlyInterceptor(
            guestList = """{"success":true,"data":{"guests":[{"guest_id":"guest-1","guest_name":"Fallback VM","status":"shutdown"}]}}""",
            guestAdditionalList = """{"success":false,"error":{"code":105}}""",
        )

        val overview = repository(transport, API_GUEST).virtualMachineOverview()

        assertEquals(listOf("Fallback VM"), overview.machines.map { it.name })
        assertTrue(overview.machineHardware.isEmpty())
        assertTrue(VirtualMachineSection.HARDWARE in overview.unavailableSections)
        assertEquals(listOf("true", null), transport.requests.map { it.fields()["additional"] })
    }

    @Test
    fun `已完成任务缺少可选详情时仍保留普通完成状态`() = runBlocking {
        val transport = VirtualMachineReadOnlyInterceptor(
            taskList = """{"success":true,"data":{"task_ids":["private-task-a"]}}""",
            taskDetails = ArrayDeque(
                listOf("""{"success":true,"data":{"finish":true}}"""),
            ),
        )

        val overview = repository(transport, API_GUEST, TASK_INFO).virtualMachineOverview()

        assertEquals(VirtualMachineTaskCenterState.AVAILABLE, overview.taskCenterState)
        assertTrue(overview.tasks.single().isFinished)
        assertEquals(null, overview.tasks.single().progressPercent)
    }

    private fun repository(interceptor: Interceptor, vararg capabilities: String) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        capabilities.associateWith { name -> ApiCapability(name, "entry.cgi", 1, 1) },
    )

    private companion object {
        const val API_GUEST = "SYNO.Virtualization.API.Guest"
        const val TASK_INFO = "SYNO.Virtualization.API.Task.Info"
    }
}

private class VirtualMachineReadOnlyInterceptor(
    private val guestList: String = """{"success":true,"data":{"guests":[{"guest_id":"guest-1","guest_name":"Synthetic VM","status":"shutdown","vdisks":[{"controller":1,"unmap":true,"vdisk_id":"disk-1","vdisk_size":10240}],"vnics":[{"mac":"02:11:32:00:00:01","model":2,"network_id":"network-1","network_name":"Default Network","vnic_id":"nic-1"}]}]}}""",
    private val guestAdditionalList: String = guestList,
    private val taskList: String? = null,
    private val taskDetails: ArrayDeque<String> = ArrayDeque(),
) : Interceptor {
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val fields = request.fields()
        val body = when (fields["api"]) {
            "SYNO.Virtualization.API.Guest" -> if (fields["additional"] == "true") {
                guestAdditionalList
            } else {
                guestList
            }
            "SYNO.Virtualization.API.Task.Info" -> when (fields["method"]) {
                "list" -> checkNotNull(taskList)
                "get" -> taskDetails.removeFirstOrNull() ?: error("缺少合成任务详情响应")
                else -> error("只读测试不允许任务写方法")
            }
            else -> error("未处理的合成 VMM API")
        }
        return Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body(body.toResponseBody("application/json".toMediaType()))
            .build()
    }
}

private fun Request.fields(): Map<String, String> {
    val body = body as? FormBody ?: return emptyMap()
    return buildMap {
        repeat(body.size) { index -> put(body.name(index), body.value(index)) }
    }
}
