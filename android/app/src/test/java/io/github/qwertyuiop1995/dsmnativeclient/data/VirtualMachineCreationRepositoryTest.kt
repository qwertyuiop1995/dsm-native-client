package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineCreation
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSettings
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
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

class VirtualMachineCreationRepositoryTest {
    @Test
    fun `公开 VMM 创建轮询任务应用配置并完整回读`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            """{"success":true,"data":{"task_id":"synthetic-task"}}""",
            """{"success":true,"data":{"finish":true,"task_info":{"guest_id":"guest-1","progress":100,"status":"create"}}}""",
            """{"success":true,"data":{}}""",
            guestDetails(cpu = 4, memory = 4096, autorun = 2, description = "Synthetic description"),
            """{"success":true,"data":{}}""",
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(2, result.counts.succeeded)
        assertEquals(
            listOf("list", "list", "list", "create", "get", "set", "get", "clear"),
            transport.requests.map { it.vmmCreationFields()["method"] },
        )
        val create = transport.requests[3].vmmCreationFields()
        assertEquals("1", create["version"])
        assertEquals("false", create["auto_clean_task"])
        assertEquals("storage-1", create["storage_id"])
        assertEquals("Synthetic VM", create["guest_name"])
        val disk = Json.parseToJsonElement(checkNotNull(create["vdisks"]))
            .jsonArray.single().jsonObject
        assertEquals(0, disk.getValue("create_type").jsonPrimitive.content.toInt())
        assertEquals(32 * 1024, disk.getValue("vdisk_size").jsonPrimitive.content.toInt())
        val network = Json.parseToJsonElement(checkNotNull(create["vnics"]))
            .jsonArray.single().jsonObject
        assertEquals("network-1", network.getValue("network_id").jsonPrimitive.content)
        val set = transport.requests[5].vmmCreationFields()
        assertEquals("4", set["vcpu_num"])
        assertEquals("4096", set["vram_size"])
        assertEquals("2", set["autorun"])
        assertEquals("synthetic-task", transport.requests.last().vmmCreationFields()["task_id"])
    }

    @Test
    fun `公开 VMM 创建无网络时按官方契约发送空网络标识`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            """{"success":true,"data":{"task_id":"synthetic-task"}}""",
            """{"success":true,"data":{"finish":true,"task_info":{"guest_id":"guest-1"}}}""",
            """{"success":true,"data":{}}""",
            guestDetails(cpu = 4, memory = 4096, autorun = 2, description = "Synthetic description"),
            """{"success":true,"data":{}}""",
        )

        val result = repository(transport).createVirtualMachineResult(configuration(networkId = null))

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        val create = transport.requests.single { it.vmmCreationFields()["method"] == "create" }
            .vmmCreationFields()
        val network = Json.parseToJsonElement(checkNotNull(create["vnics"]))
            .jsonArray.single().jsonObject
        assertEquals("", network.getValue("network_id").jsonPrimitive.content)
    }

    @Test
    fun `创建成功但常规配置未确认时报告部分成功且不重放创建`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            """{"success":true,"data":{"task_id":"synthetic-task"}}""",
            """{"success":true,"data":{"finish":true,"task_info":{"guest_id":"guest-1"}}}""",
            """{"success":false,"error":{"code":402}}""",
            guestDetails(cpu = 1, memory = 1024, autorun = 0, description = ""),
            """{"success":true,"data":{}}""",
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertEquals(1, transport.requests.count { it.vmmCreationFields()["method"] == "create" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "clear" })
    }

    @Test
    fun `同名虚拟机预检冲突时零创建请求`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList("""{"guest_id":"existing","guest_name":"synthetic vm","status":"shutdown"}"""),
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.requests.map { it.vmmCreationFields()["method"] })
    }

    @Test
    fun `名称预检取消按提交前取消且零写返回`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(CANCEL_RESPONSE)

        val result = cancelledCreationResult(repository(transport), transport, configuration())

        assertCreationPreflightCancelled(result, transport)
    }

    @Test
    fun `存储预检取消按提交前取消且零写返回`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(guestList(), CANCEL_RESPONSE)

        val result = cancelledCreationResult(repository(transport), transport, configuration())

        assertCreationPreflightCancelled(result, transport)
    }

    @Test
    fun `网络预检取消按提交前取消且零写返回`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            CANCEL_RESPONSE,
        )

        val result = cancelledCreationResult(repository(transport), transport, configuration())

        assertCreationPreflightCancelled(result, transport)
    }

    @Test
    fun `映像预检取消按提交前取消且零写返回`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            CANCEL_RESPONSE,
        )

        val result = cancelledCreationResult(
            repository(transport),
            transport,
            configuration(diskImageId = "image-1"),
        )

        assertCreationPreflightCancelled(result, transport)
    }

    @Test
    fun `缺少公开任务能力时创建入口关闭`() {
        val repository = repository(VirtualMachineCreationInterceptor(), includeTaskApi = false)

        assertFalse(repository.supportsOfficialVirtualMachineCreation())
    }

    @Test
    fun `缺少公开 Guest 能力时设置入口零请求关闭`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor()
        val repository = repository(transport, includeGuestApi = false)

        val result = repository.updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Synthetic VM", "", 1, 1024, false),
            VirtualMachineSettings("Synthetic VM", "", 1, 1024, false),
        )

        assertEquals(MutationResultStatus.UNSUPPORTED, result.status)
        assertFalse(result.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `公开 VMM 常规设置提交后完整回读`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList("""{"guest_id":"guest-1","guest_name":"Old name","status":"shutdown"}"""),
            guestDetails(cpu = 1, memory = 1024, autorun = 0, description = ""),
            """{"success":true,"data":{}}""",
            guestDetails(cpu = 2, memory = 2048, autorun = 2, description = "Updated"),
        )

        val result = repository(transport).updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Synthetic VM", "", 1, 1024, false),
            VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "get", "set", "get"), transport.requests.map {
            it.vmmCreationFields()["method"]
        })
        assertEquals("1", transport.requests[2].vmmCreationFields()["version"])
        assertEquals("guest-1", transport.requests[2].vmmCreationFields()["guest_id"])
    }

    @Test
    fun `常规设置名称冲突时不提交`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(
                """{"guest_id":"guest-1","guest_name":"Old name","status":"shutdown"}""",
                """{"guest_id":"guest-2","guest_name":"Synthetic VM","status":"shutdown"}""",
            ),
        )

        val result = repository(transport).updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Old name", "", 1, 1024, false),
            VirtualMachineSettings("Synthetic VM", "", 1, 1024, false),
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("list"), transport.requests.map { it.vmmCreationFields()["method"] })
    }

    @Test
    fun `常规设置只发送发生变化的字段`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList("""{"guest_id":"guest-1","guest_name":"Old name","status":"shutdown"}"""),
            guestDetails(name = "Old name", cpu = 2, memory = 2048, autorun = 2, description = "Updated"),
            """{"success":true,"data":{}}""",
            guestDetails(cpu = 2, memory = 2048, autorun = 2, description = "Updated"),
        )

        val result = repository(transport).updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Old name", "Updated", 2, 2048, true),
            VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        val set = transport.requests.single { it.vmmCreationFields()["method"] == "set" }
            .vmmCreationFields()
        val payloadKeys = set.keys - setOf("api", "method", "version", "_sid", "SynoToken")
        assertEquals(setOf("guest_id", "new_guest_name"), payloadKeys)
    }

    @Test
    fun `常规设置无变化时不发送 set`() = runBlocking {
        val current = guestDetails(cpu = 2, memory = 2048, autorun = 2, description = "Updated")
        val transport = VirtualMachineCreationInterceptor(
            guestList("""{"guest_id":"guest-1","guest_name":"Synthetic VM","status":"shutdown"}"""),
            current,
        )

        val result = repository(transport).updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
            VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("list", "get"), transport.requests.map {
            it.vmmCreationFields()["method"]
        })
    }

    @Test
    fun `常规设置锁内发现用户所见基线漂移时零写拒绝`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList("""{"guest_id":"guest-1","guest_name":"Old name","status":"shutdown"}"""),
            guestDetails(name = "Changed elsewhere", cpu = 2, memory = 2048, autorun = 2, description = "Updated"),
        )

        val result = repository(transport).updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Old name", "Updated", 2, 2048, true),
            VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("list", "get"), transport.requests.map {
            it.vmmCreationFields()["method"]
        })
    }

    @Test
    fun `常规设置提交断线后只回读且不重放`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList("""{"guest_id":"guest-1","guest_name":"Old name","status":"shutdown"}"""),
            guestDetails(name = "Old name", cpu = 1, memory = 1024, autorun = 0, description = ""),
            "not-json",
            guestDetails(cpu = 2, memory = 2048, autorun = 2, description = "Updated"),
        )

        val result = repository(transport).updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Old name", "", 1, 1024, false),
            VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        val methods = transport.requests.map { it.vmmCreationFields()["method"] }
        assertEquals(listOf("list", "get", "set"), methods.take(3))
        assertTrue(methods.drop(3).all { it == "get" })
        assertEquals(1, transport.requests.count { it.vmmCreationFields()["method"] == "set" })
    }

    @Test
    fun `常规设置写后回读结构失败保持未确认`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList("""{"guest_id":"guest-1","guest_name":"Old name","status":"shutdown"}"""),
            guestDetails(name = "Old name", cpu = 1, memory = 1024, autorun = 0, description = ""),
            """{"success":true,"data":{}}""",
            """{"success":true,"data":{"guest_id":"guest-1"}}""",
        )

        val result = repository(transport).updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Old name", "", 1, 1024, false),
            VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.submitted)
        assertTrue(result.requiresRefresh)
        assertEquals(1, transport.requests.count { it.vmmCreationFields()["method"] == "set" })
    }

    @Test
    fun `常规设置写请求在途取消只回读且不重放`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList("""{"guest_id":"guest-1","guest_name":"Old name","status":"shutdown"}"""),
            guestDetails(name = "Old name", cpu = 1, memory = 1024, autorun = 0, description = ""),
            CANCEL_RESPONSE,
            guestDetails(name = "Old name", cpu = 1, memory = 1024, autorun = 0, description = ""),
        )
        val repo = repository(transport)
        val captured = CompletableDeferred<io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult>()
        val job = launch(Dispatchers.Default) {
            captured.complete(
                repo.updateVirtualMachineSettingsResult(
                    "guest-1",
                    VirtualMachineSettings("Old name", "", 1, 1024, false),
                    VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
                ),
            )
        }
        assertTrue(transport.cancellationRequestEntered.await(5, TimeUnit.SECONDS))
        job.cancel()
        transport.releaseCancellationRequest.countDown()
        job.join()
        val result = captured.await()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result.status)
        assertTrue(result.submitted)
        assertEquals(1, transport.requests.count { it.vmmCreationFields()["method"] == "set" })
        val methods = transport.requests.map { it.vmmCreationFields()["method"] }
        assertEquals(listOf("list", "get", "set"), methods.take(3))
        assertTrue(methods.drop(3).all { it == "get" })
    }

    @Test
    fun `缺少用户所见基线的旧设置入口零请求拒绝`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor()

        val result = repository(transport).updateVirtualMachineSettingsResult(
            "guest-1",
            VirtualMachineSettings("Synthetic VM", "Updated", 2, 2048, true),
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertFalse(result.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `创建响应缺任务标识时同名回读也绝不认领或设置`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            """{"success":true,"data":{}}""",
            guestList("""{"guest_id":"other-guest","guest_name":"Synthetic VM","status":"shutdown"}"""),
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(1, transport.requests.count { it.vmmCreationFields()["method"] == "create" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "set" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "clear" })
    }

    @Test
    fun `创建提交响应模糊时同名回读也不重放或设置`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            "not-json",
            guestList("""{"guest_id":"other-guest","guest_name":"Synthetic VM","status":"shutdown"}"""),
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(1, transport.requests.count { it.vmmCreationFields()["method"] == "create" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "set" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "clear" })
    }

    @Test
    fun `任务终态结构无效时只做任务回读且不按名称设置`() = runBlocking {
        val malformedTask = """{"success":true,"data":{"finish":"true","task_info":{"guest_id":"guest-1"}}}"""
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            """{"success":true,"data":{"task_id":"synthetic-task"}}""",
            malformedTask,
            malformedTask,
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "set" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "clear" })
    }

    @Test
    fun `任务终态缺 guest 标识时不设置且保留任务证据`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            """{"success":true,"data":{"task_id":"synthetic-task"}}""",
            """{"success":true,"data":{"finish":true,"task_info":{}}}""",
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "set" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "clear" })
    }

    @Test
    fun `任务轮询取消只回读且保留任务证据`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            """{"success":true,"data":{"task_id":"synthetic-task"}}""",
            CANCEL_RESPONSE,
            """{"success":true,"data":{"finish":false}}""",
        )

        val result = cancelledCreationResult(repository(transport), transport, configuration())

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result.status)
        assertTrue(result.submitted)
        assertEquals(1, transport.requests.count { it.vmmCreationFields()["method"] == "create" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "set" })
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "clear" })
    }

    @Test
    fun `创建配置提交未知且回读不匹配时保留任务证据`() = runBlocking {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            """{"success":true,"data":{"task_id":"synthetic-task"}}""",
            """{"success":true,"data":{"finish":true,"task_info":{"guest_id":"guest-1"}}}""",
            "not-json",
            guestDetails(cpu = 1, memory = 1024, autorun = 0, description = ""),
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(1, result.counts.unknown)
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "clear" })
    }

    @Test
    fun `创建配置回读 guest 标识错配时不确认且保留任务证据`() = runBlocking {
        assertStrictCreationReadbackRejected(
            """{"success":true,"data":{"guest_id":"other-guest","guest_name":"Synthetic VM","vcpu_num":4,"vram_size":4096,"autorun":2,"description":"Synthetic description"}}""",
        )
    }

    @Test
    fun `创建配置回读缺字段时不确认且保留任务证据`() = runBlocking {
        assertStrictCreationReadbackRejected(
            """{"success":true,"data":{"guest_id":"guest-1","guest_name":"Synthetic VM","vcpu_num":4,"vram_size":4096,"autorun":2}}""",
        )
    }

    @Test
    fun `创建配置回读字段类型畸形时不确认且保留任务证据`() = runBlocking {
        assertStrictCreationReadbackRejected(
            """{"success":true,"data":{"guest_id":"guest-1","guest_name":"Synthetic VM","vcpu_num":"4","vram_size":4096,"autorun":2,"description":"Synthetic description"}}""",
        )
    }

    private fun repository(
        interceptor: Interceptor,
        includeTaskApi: Boolean = true,
        includeGuestApi: Boolean = true,
    ) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        DsmSession("test", "synthetic-session", "synthetic-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        buildList {
            if (includeGuestApi) {
                add(ApiCapability("SYNO.Virtualization.API.Guest", "entry.cgi", 1, 1))
            }
            add(ApiCapability("SYNO.Virtualization.API.Storage", "entry.cgi", 1, 1))
            add(ApiCapability("SYNO.Virtualization.API.Network", "entry.cgi", 1, 1))
            add(ApiCapability("SYNO.Virtualization.API.Guest.Image", "entry.cgi", 1, 1))
            if (includeTaskApi) {
                add(ApiCapability("SYNO.Virtualization.API.Task.Info", "entry.cgi", 1, 1))
            }
        }.associateBy(ApiCapability::name),
    )

    private fun assertCreationPreflightCancelled(
        result: io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult,
        transport: VirtualMachineCreationInterceptor,
    ) {
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, result.status)
        assertFalse(result.submitted)
        assertFalse(transport.requests.any {
            it.vmmCreationFields()["method"] in setOf("create", "set", "clear")
        })
    }

    private suspend fun cancelledCreationResult(
        repository: DsmRepository,
        transport: VirtualMachineCreationInterceptor,
        configuration: VirtualMachineCreation,
    ) = coroutineScope {
        val captured = CompletableDeferred<io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult>()
        val job = launch(Dispatchers.Default) {
            captured.complete(repository.createVirtualMachineResult(configuration))
        }
        assertTrue(transport.cancellationRequestEntered.await(5, TimeUnit.SECONDS))
        job.cancel()
        transport.releaseCancellationRequest.countDown()
        job.join()
        captured.await()
    }

    private suspend fun assertStrictCreationReadbackRejected(readback: String) {
        val transport = VirtualMachineCreationInterceptor(
            guestList(),
            storageList(),
            networkList(),
            """{"success":true,"data":{"task_id":"synthetic-task"}}""",
            """{"success":true,"data":{"finish":true,"task_info":{"guest_id":"guest-1"}}}""",
            """{"success":true,"data":{}}""",
            readback,
        )

        val result = repository(transport).createVirtualMachineResult(configuration())

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertFalse(transport.requests.any { it.vmmCreationFields()["method"] == "clear" })
    }

    private fun configuration(
        networkId: String? = "network-1",
        diskImageId: String? = null,
    ) = VirtualMachineCreation(
        name = "Synthetic VM",
        description = "Synthetic description",
        cpuCount = 4,
        memoryMiB = 4096,
        diskGiB = 32,
        storageId = "storage-1",
        networkId = networkId,
        diskImageId = diskImageId,
        autoStart = true,
    )

    private fun guestList(vararg guests: String) =
        """{"success":true,"data":{"guests":[${guests.joinToString(",")}]}}"""

    private fun storageList() =
        """{"success":true,"data":{"storages":[{"storage_id":"storage-1","storage_name":"Synthetic storage","status":"online"}]}}"""

    private fun networkList() =
        """{"success":true,"data":{"networks":[{"network_id":"network-1","network_name":"Synthetic network"}]}}"""

    private fun guestDetails(
        name: String = "Synthetic VM",
        cpu: Int,
        memory: Int,
        autorun: Int,
        description: String,
    ) = """{"success":true,"data":{"guest_id":"guest-1","guest_name":"$name","status":"shutdown","vcpu_num":$cpu,"vram_size":$memory,"autorun":$autorun,"description":"$description"}}"""
}

private class VirtualMachineCreationInterceptor(vararg responses: String) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()
    val cancellationRequestEntered = CountDownLatch(1)
    val releaseCancellationRequest = CountDownLatch(1)

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val response = pending.removeFirstOrNull() ?: error("缺少合成 VMM 创建响应")
        if (response == CANCEL_RESPONSE) {
            cancellationRequestEntered.countDown()
            check(releaseCancellationRequest.await(5, TimeUnit.SECONDS)) { "合成取消请求未释放" }
        }
        return Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body(
                (if (response == CANCEL_RESPONSE) """{"success":true,"data":{}}""" else response)
                    .toResponseBody("application/json".toMediaType()),
            )
            .build()
    }
}

private const val CANCEL_RESPONSE = "__synthetic_cancellation__"

private fun Request.vmmCreationFields(): Map<String, String> {
    val form = body as? FormBody ?: return emptyMap()
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}
