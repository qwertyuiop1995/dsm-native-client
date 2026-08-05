package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
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

class VirtualMachineTaskClearRepositoryTest {
    @Test
    fun `完整复核后只清除基线中的已完成任务并严格回读`() = runBlocking {
        val transport = TaskClearInterceptor(
            rounds = ArrayDeque(
                listOf(
                    round("running" to false, "finished-a" to true, "finished-b" to true),
                    round("running" to false, "finished-a" to true, "finished-b" to true),
                    round("running" to false),
                ),
            ),
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val result = repository.clearFinishedVirtualMachineTasksResult(baseline)

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(2, result.counts.succeeded)
        assertEquals(0, result.counts.failed)
        assertEquals(0, result.counts.unknown)
        assertEquals(
            listOf("finished-a", "finished-b"),
            transport.clearRequests().map { it.fields()["task_id"] },
        )
        assertTrue(transport.clearRequests().all {
            it.fields()["api"] == "SYNO.Virtualization.API.Task.Info" &&
                it.fields()["version"] == "1" && it.fields()["method"] == "clear"
        })
        assertFalse(transport.clearRequests().any { it.fields()["task_id"] == "running" })
    }

    @Test
    fun `能力缺失空基线和无已完成任务均零 clear`() = runBlocking {
        val noCapability = TaskClearInterceptor(ArrayDeque())
        val unsupported = repository(noCapability, includeTaskCapability = false)
            .clearFinishedVirtualMachineTasksResult(emptyList())
        assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.status)

        val emptyTransport = TaskClearInterceptor(ArrayDeque())
        val empty = repository(emptyTransport).clearFinishedVirtualMachineTasksResult(emptyList())
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, empty.status)

        val runningTransport = TaskClearInterceptor(
            ArrayDeque(listOf(round("running" to false))),
        )
        val runningRepository = repository(runningTransport)
        val baseline = runningRepository.virtualMachineOverview().tasks
        val running = runningRepository.clearFinishedVirtualMachineTasksResult(baseline)
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, running.status)
        assertTrue(
            listOf(noCapability, emptyTransport, runningTransport).all { it.clearRequests().isEmpty() },
        )
    }

    @Test
    fun `基线任务或状态变化时零 clear`() = runBlocking {
        val transport = TaskClearInterceptor(
            ArrayDeque(
                listOf(
                    round("task-a" to true),
                    round("task-a" to false),
                ),
            ),
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val result = repository.clearFinishedVirtualMachineTasksResult(baseline)

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, result.status)
        assertEquals(0, result.counts.succeeded)
        assertTrue(transport.clearRequests().isEmpty())
    }

    @Test
    fun `任务列表顺序变化但完整集合一致时仍可清除`() = runBlocking {
        val transport = TaskClearInterceptor(
            ArrayDeque(
                listOf(
                    round("running" to false, "finished" to true),
                    round("finished" to true, "running" to false),
                    round("running" to false),
                ),
            ),
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val result = repository.clearFinishedVirtualMachineTasksResult(baseline)

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("finished"), transport.clearRequests().map { it.fields()["task_id"] })
    }

    @Test
    fun `无关任务新增和目标进度变化不阻断已完成目标清理`() = runBlocking {
        val transport = TaskClearInterceptor(
            ArrayDeque(
                listOf(
                    roundAtProgress(20, "finished" to true),
                    roundAtProgress(90, "unrelated" to false, "finished" to true),
                    roundAtProgress(10, "unrelated" to false),
                ),
            ),
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val result = repository.clearFinishedVirtualMachineTasksResult(baseline)

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(listOf("finished"), transport.clearRequests().map { it.fields()["task_id"] })
    }

    @Test
    fun `清除提交异常后只回读一次且不重放`() = runBlocking {
        val transport = TaskClearInterceptor(
            rounds = ArrayDeque(
                listOf(
                    round("task-a" to true, "task-b" to true),
                    round("task-a" to true, "task-b" to true),
                    round("task-a" to true, "task-b" to true),
                ),
            ),
            disconnectClearToken = "task-a",
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val result = repository.clearFinishedVirtualMachineTasksResult(baseline)

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.requiresRefresh)
        assertEquals(1, result.counts.failed)
        assertEquals(1, result.counts.unknown)
        assertEquals(listOf("task-a"), transport.clearRequests().map { it.fields()["task_id"] })
        val clearIndex = transport.requests.indexOfFirst { it.fields()["method"] == "clear" }
        assertEquals(
            1,
            transport.requests.drop(clearIndex + 1).count { it.fields()["method"] == "list" },
        )
    }

    @Test
    fun `未提交任务并发消失不计入本批成功且计数不重叠`() = runBlocking {
        val transport = TaskClearInterceptor(
            rounds = ArrayDeque(
                listOf(
                    round("task-a" to true, "task-b" to true),
                    round("task-a" to true, "task-b" to true),
                    // task-b 未由本批提交，模拟被另一客户端同时清除。
                    round("task-a" to true),
                ),
            ),
            disconnectClearToken = "task-a",
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val result = repository.clearFinishedVirtualMachineTasksResult(baseline)

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(0, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertEquals(1, result.counts.unknown)
        assertEquals(listOf("task-a"), transport.clearRequests().map { it.fields()["task_id"] })
    }

    @Test
    fun `提交后取消只回读且不清除后续任务`() = runBlocking {
        val enteredClear = CountDownLatch(1)
        val continueClear = CountDownLatch(1)
        val enteredReadback = CountDownLatch(1)
        val resultResolved = CountDownLatch(1)
        val resolvedResult = AtomicReference<MutationResult>()
        val transport = TaskClearInterceptor(
            rounds = ArrayDeque(
                listOf(
                    round("task-a" to true, "task-b" to true),
                    round("task-a" to true, "task-b" to true),
                    round("task-a" to true, "task-b" to true),
                ),
            ),
            enteredClear = enteredClear,
            continueClear = continueClear,
            enteredReadback = enteredReadback,
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val result = async(Dispatchers.Default) {
            repository.clearFinishedVirtualMachineTasksResult(baseline) { resolved ->
                resolvedResult.set(resolved)
                resultResolved.countDown()
            }
        }
        assertTrue(enteredClear.await(2, TimeUnit.SECONDS))
        result.cancel()
        continueClear.countDown()
        assertTrue(enteredReadback.await(2, TimeUnit.SECONDS))
        assertTrue(resultResolved.await(2, TimeUnit.SECONDS))

        assertTrue(result.isCancelled)
        assertEquals(
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            resolvedResult.get().status,
        )
        assertEquals(1, resolvedResult.get().counts.failed)
        assertEquals(1, resolvedResult.get().counts.unknown)
        assertEquals(listOf("task-a"), transport.clearRequests().map { it.fields()["task_id"] })
        val clearIndex = transport.requests.indexOfFirst { it.fields()["method"] == "clear" }
        assertEquals(
            1,
            transport.requests.drop(clearIndex + 1).count { it.fields()["method"] == "list" },
        )
    }

    @Test
    fun `clear 成功响应但任务仍存在时保持待核对`() = runBlocking {
        val transport = TaskClearInterceptor(
            rounds = ArrayDeque(
                listOf(
                    round("task-a" to true),
                    round("task-a" to true),
                    round("task-a" to true),
                ),
            ),
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val result = repository.clearFinishedVirtualMachineTasksResult(baseline)

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertEquals(1, result.counts.unknown)
        assertTrue(result.requiresRefresh)
        assertEquals(1, transport.clearRequests().size)
    }

    @Test
    fun `同一批清除并发调用只有一个能够提交`() = runBlocking {
        val enteredClear = CountDownLatch(1)
        val continueClear = CountDownLatch(1)
        val transport = TaskClearInterceptor(
            rounds = ArrayDeque(
                listOf(
                    round("task-a" to true),
                    round("task-a" to true),
                    round(),
                ),
            ),
            enteredClear = enteredClear,
            continueClear = continueClear,
        )
        val repository = repository(transport)
        val baseline = repository.virtualMachineOverview().tasks

        val first = async(Dispatchers.Default) {
            repository.clearFinishedVirtualMachineTasksResult(baseline)
        }
        assertTrue(enteredClear.await(2, TimeUnit.SECONDS))
        val duplicate = async { repository.clearFinishedVirtualMachineTasksResult(baseline) }.await()
        continueClear.countDown()
        val completed = first.await()

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, completed.status)
        assertEquals(1, transport.clearRequests().size)
    }

    private fun repository(
        interceptor: Interceptor,
        includeTaskCapability: Boolean = true,
    ) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().addInterceptor(interceptor).build()),
        buildMap {
            put(API_GUEST, ApiCapability(API_GUEST, "entry.cgi", 1, 1))
            if (includeTaskCapability) {
                put(TASK_INFO, ApiCapability(TASK_INFO, "entry.cgi", 1, 1))
            }
        },
    )

    private companion object {
        const val API_GUEST = "SYNO.Virtualization.API.Guest"
        const val TASK_INFO = "SYNO.Virtualization.API.Task.Info"
    }
}

private data class TaskRound(
    val tasks: List<Pair<String, Boolean>>,
    val progress: Int = 100,
)

private fun round(vararg tasks: Pair<String, Boolean>) = TaskRound(tasks.toList())
private fun roundAtProgress(progress: Int, vararg tasks: Pair<String, Boolean>) =
    TaskRound(tasks.toList(), progress)

private class TaskClearInterceptor(
    private val rounds: ArrayDeque<TaskRound>,
    private val disconnectClearToken: String? = null,
    private val enteredClear: CountDownLatch? = null,
    private val continueClear: CountDownLatch? = null,
    private val enteredReadback: CountDownLatch? = null,
) : Interceptor {
    val requests = mutableListOf<Request>()
    private var activeRound: TaskRound? = null
    private var detailIndex = 0

    fun clearRequests(): List<Request> = synchronized(requests) {
        requests.filter { it.fields()["method"] == "clear" }
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        synchronized(requests) { requests += request }
        val fields = request.fields()
        val body = when (fields["api"]) {
            "SYNO.Virtualization.API.Guest" -> GUEST_LIST
            "SYNO.Virtualization.API.Task.Info" -> when (fields["method"]) {
                "list" -> synchronized(rounds) {
                    if (clearRequests().isNotEmpty()) enteredReadback?.countDown()
                    activeRound = rounds.removeFirstOrNull() ?: error("缺少合成任务轮次")
                    detailIndex = 0
                    val ids = checkNotNull(activeRound).tasks.joinToString(",") { (id, _) ->
                        "\"$id\""
                    }
                    """{"success":true,"data":{"task_ids":[$ids]}}"""
                }
                "get" -> synchronized(rounds) {
                    val task = checkNotNull(activeRound).tasks[detailIndex++]
                    """{"success":true,"data":{"finish":${task.second},"task_info":{"progress":${checkNotNull(activeRound).progress}}}}"""
                }
                "clear" -> {
                    enteredClear?.countDown()
                    continueClear?.await(2, TimeUnit.SECONDS)
                    if (fields["task_id"] == disconnectClearToken) {
                        throw IOException("synthetic disconnect")
                    }
                    """{"success":true,"data":{}}"""
                }
                else -> error("未处理的任务方法")
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

    private companion object {
        const val GUEST_LIST =
            """{"success":true,"data":{"guests":[{"guest_id":"guest-1","guest_name":"VM","status":"shutdown"}]}}"""
    }
}

private fun Request.fields(): Map<String, String> {
    val body = body as? FormBody ?: return emptyMap()
    return buildMap {
        repeat(body.size) { index -> put(body.name(index), body.value(index)) }
    }
}
