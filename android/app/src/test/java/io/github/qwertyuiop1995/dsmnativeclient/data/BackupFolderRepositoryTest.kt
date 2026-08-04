package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
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
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupFolderRepositoryTest {
    @Test
    fun `自动备份只在配置根目录下逐层创建子目录`() = runBlocking {
        val transport = BackupFolderInterceptor(
            """{"success":true,"data":{"offset":0,"total":0,"files":[]}}""",
            """{"success":true,"data":{"files":[{"name":"移动备份","path":"/photo/移动备份","isdir":true,"additional":{"perm":{"write":true}}}]}}""",
            """{"success":true,"data":{"offset":0,"total":0,"files":[]}}""",
            """{"success":true,"data":{}}""",
            """{"success":true,"data":{"files":[{"name":"旅行","path":"/photo/移动备份/旅行","isdir":true,"additional":{"perm":{"write":true}}}]}}""",
        )

        repository(transport).ensureSubdirectory("/photo/移动备份", "/photo/移动备份/旅行")

        assertEquals(
            listOf("list", "getinfo", "list", "create", "getinfo"),
            transport.requests.map { it.backupFields()["method"] },
        )
        assertEquals("/photo/移动备份", transport.requests[3].backupFields()["folder_path"])
        assertEquals("旅行", transport.requests[3].backupFields()["name"])
    }

    @Test
    fun `拒绝在配置根目录之外创建备份目录`() = runBlocking {
        val transport = BackupFolderInterceptor()

        val failure = runCatching {
            repository(transport).ensureSubdirectory("/photo/移动备份", "/photo/其他")
        }.exceptionOrNull()

        assertTrue(failure is IllegalArgumentException)
        assertTrue(transport.requests.isEmpty())
    }

    private fun repository(interceptor: Interceptor) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        DsmSession("test", "test-session", "test-token"),
        DsmApiClient(OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build()),
        listOf(
            ApiCapability("SYNO.FileStation.List", "entry.cgi", 1, 2),
            ApiCapability("SYNO.FileStation.CreateFolder", "entry.cgi", 1, 2),
        ).associateBy(ApiCapability::name),
    )
}

private class BackupFolderInterceptor(vararg responses: String) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        return Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body(
                (pending.removeFirstOrNull() ?: error("缺少合成备份目录响应"))
                    .toResponseBody("application/json".toMediaType()),
            )
            .build()
    }
}

private fun Request.backupFields(): Map<String, String> {
    val form = body as FormBody
    return (0 until form.size).associate { form.name(it) to form.value(it) }
}
