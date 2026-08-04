package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.ArchiveCompressionLevel
import io.github.qwertyuiop1995.dsmnativeclient.domain.ArchiveFormat
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.IOException
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
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

class ArchiveRepositoryTest {
    @Test
    fun `压缩使用公开任务接口且完成后复查目标`() = runBlocking {
        val transport = ArchiveInterceptor(
            success("""{"files":[{"name":"home","path":"/home","isdir":true,"additional":{"perm":{"write":true}}}]}"""),
            listResponse(),
            success("""{"taskid":"compress-task"}"""),
            success("""{"finished":true}"""),
            listResponse("""{"name":"资料.7z","path":"/home/资料.7z","isdir":false}"""),
        )

        repository(transport).compress(
            paths = listOf("/home/图片", "/home/说明.txt"),
            destinationFilePath = "/home/资料.7z",
            format = ArchiveFormat.SEVEN_ZIP,
            level = ArchiveCompressionLevel.BEST,
            password = "REDACTED_ARCHIVE_PASSWORD",
        )

        val start = transport.requests.first { it.formFields()["method"] == "start" }.formFields()
        assertEquals("SYNO.FileStation.Compress", start["api"])
        assertEquals("[\"/home/图片\",\"/home/说明.txt\"]", start["path"])
        assertEquals("/home/资料.7z", start["dest_file_path"])
        assertEquals("7z", start["format"])
        assertEquals("best", start["level"])
        assertEquals("REDACTED_ARCHIVE_PASSWORD", start["password"])
        assertFalse(transport.requests.first().url.toString().contains("REDACTED_ARCHIVE_PASSWORD"))
        RequestFixtureAssertions.assertRequest(
            transport.requests.first { it.formFields()["method"] == "start" },
            "file-station/compress/synthetic-selection/request.json",
        )
    }

    @Test
    fun `解压先读取内容拒绝覆盖并在任务完成后复查`() = runBlocking {
        val transport = ArchiveInterceptor(
            success("""{"files":[{"name":"target","path":"/home/target","isdir":true,"additional":{"perm":{"write":true}}}]}"""),
            success("""{"items":[{"itemid":7,"name":"存档","path":"/存档","is_dir":true}]}"""),
            listResponse(),
            success("""{"taskid":"extract-task"}"""),
            success("""{"finished":true,"progress":0.75}"""),
            listResponse("""{"name":"存档","path":"/home/target/存档","isdir":true}"""),
        )

        repository(transport).extract(
            filePath = "/home/资料.zip",
            destinationFolder = "/home/target",
            codepage = "chs",
        )

        val list = transport.requests.first { it.formFields()["method"] == "list" && it.formFields()["api"] == "SYNO.FileStation.Extract" }.formFields()
        assertEquals("-1", list["item_id"])
        assertEquals("chs", list["codepage"])
        val start = transport.requests.first { it.formFields()["method"] == "start" }.formFields()
        assertEquals("false", start["overwrite"])
        assertEquals("true", start["keep_dir"])
        assertEquals("false", start["create_subfolder"])
        RequestFixtureAssertions.assertRequest(
            transport.requests.first { it.formFields()["method"] == "start" },
            "file-station/extract/synthetic-archive/request.json",
        )
    }

    @Test
    fun `压缩目标目录只读时提交前拒绝`() = runBlocking {
        val transport = ArchiveInterceptor(directoryResponse("/home", canWrite = false))

        val result = repository(transport).compressResult(
            paths = listOf("/home/source.txt"),
            destinationFilePath = "/home/archive.zip",
            format = ArchiveFormat.ZIP,
            level = ArchiveCompressionLevel.MODERATE,
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertEquals(MutationErrorCategory.PERMISSION, result.errorCategory)
        assertFalse(result.submitted)
        assertFalse(transport.methods().contains("start"))
    }

    @Test
    fun `压缩启动断线但目标回读存在时确认成功且不重放`() = runBlocking {
        val transport = ArchiveInterceptor(
            directoryResponse("/home", canWrite = true),
            listResponse(),
            IOException("synthetic disconnect"),
            listResponse("""{"name":"archive.zip","path":"/home/archive.zip","isdir":false}"""),
        )

        val result = repository(transport).compressResult(
            paths = listOf("/home/source.txt"),
            destinationFilePath = "/home/archive.zip",
            format = ArchiveFormat.ZIP,
            level = ArchiveCompressionLevel.MODERATE,
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `压缩启动断线且目标不存在时保持未确认`() = runBlocking {
        val transport = ArchiveInterceptor(
            directoryResponse("/home", canWrite = true),
            listResponse(),
            IOException("synthetic disconnect"),
            listResponse(),
        )

        val result = repository(transport).compressResult(
            paths = listOf("/home/source.txt"),
            destinationFilePath = "/home/archive.zip",
            format = ArchiveFormat.ZIP,
            level = ArchiveCompressionLevel.MODERATE,
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, result.status)
        assertTrue(result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `压缩提交权限拒绝不重放`() = runBlocking {
        val transport = ArchiveInterceptor(
            directoryResponse("/home", canWrite = true),
            listResponse(),
            """{"success":false,"error":{"code":105}}""",
        )

        val result = repository(transport).compressResult(
            paths = listOf("/home/source.txt"),
            destinationFilePath = "/home/archive.zip",
            format = ArchiveFormat.ZIP,
            level = ArchiveCompressionLevel.MODERATE,
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `解压只确认部分目标时返回部分成功`() = runBlocking {
        val responses = mutableListOf<Any>(
            directoryResponse("/home/target", canWrite = true),
            success("""{"items":[{"itemid":1,"name":"a","path":"/a","is_dir":false},{"itemid":2,"name":"b","path":"/b","is_dir":false}]}"""),
            listResponse(),
            listResponse(),
            success("""{"taskid":"extract-task"}"""),
            success("""{"finished":true}"""),
        )
        repeat(8) {
            responses += listResponse("""{"name":"a","path":"/home/target/a","isdir":false}""")
            responses += listResponse()
        }
        val transport = ArchiveInterceptor(*responses.toTypedArray())

        val result = repository(transport).extractResult("/home/archive.zip", "/home/target")

        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, result.status)
        assertEquals(1, result.counts.succeeded)
        assertEquals(1, result.counts.failed)
        assertTrue(result.requiresRefresh)
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `解压目标目录只读时提交前拒绝`() = runBlocking {
        val transport = ArchiveInterceptor(directoryResponse("/home/target", canWrite = false))

        val result = repository(transport).extractResult("/home/archive.zip", "/home/target")

        assertEquals(MutationResultStatus.PERMISSION_DENIED, result.status)
        assertFalse(result.submitted)
        assertEquals(listOf("getinfo"), transport.methods())
    }

    @Test
    fun `解压启动断线但全部目标回读存在时确认成功且不重放`() = runBlocking {
        val transport = ArchiveInterceptor(
            directoryResponse("/home/target", canWrite = true),
            success("""{"items":[{"itemid":1,"name":"a","path":"/a","is_dir":false}]}"""),
            listResponse(),
            IOException("synthetic disconnect"),
            listResponse("""{"name":"a","path":"/home/target/a","isdir":false}"""),
        )

        val result = repository(transport).extractResult("/home/archive.zip", "/home/target")

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, result.status)
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `压缩解压非法输入和能力不足均不发送请求`() = runBlocking {
        val transport = ArchiveInterceptor()
        val invalid = repository(transport).compressResult(
            paths = emptyList(),
            destinationFilePath = "/home/archive.zip",
            format = ArchiveFormat.ZIP,
            level = ArchiveCompressionLevel.MODERATE,
        )
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, invalid.status)
        assertEquals(MutationErrorCategory.VALIDATION, invalid.errorCategory)
        assertTrue(transport.requests.isEmpty())

        val unsupportedRepo = repository(transport, supportsArchives = false)
        val unsupported = unsupportedRepo.extractResult("/home/archive.zip", "/home/target")
        assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.status)
        assertFalse(unsupported.submitted)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `压缩提交前协程取消时不访问网络`() {
        val transport = ArchiveInterceptor()
        val job = Job()
        var status: MutationResultStatus? = null

        runCatching {
            runBlocking(job) {
                job.cancel()
                status = repository(transport).compressResult(
                    paths = listOf("/home/source.txt"),
                    destinationFilePath = "/home/archive.zip",
                    format = ArchiveFormat.ZIP,
                    level = ArchiveCompressionLevel.MODERATE,
                ).status
            }
        }

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, status)
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `压缩提交后取消会停止任务并只要求刷新`() = runBlocking {
        val transport = BlockingArchiveInterceptor()
        val repo = repository(transport)
        var status: MutationResultStatus? = null
        val worker = launch(Dispatchers.IO) {
            status = repo.compressResult(
                paths = listOf("/home/source.txt"),
                destinationFilePath = "/home/archive.zip",
                format = ArchiveFormat.ZIP,
                level = ArchiveCompressionLevel.MODERATE,
            ).status
        }
        assertTrue(transport.statusStarted.await(2, TimeUnit.SECONDS))

        worker.cancel()
        transport.allowStatus.countDown()
        worker.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, status)
        assertEquals(1, transport.methods().count { it == "start" })
        assertEquals(1, transport.methods().count { it == "stop" })
    }

    @Test
    fun `同一压缩目标进行中时拒绝重复提交`() = runBlocking {
        val transport = BlockingArchiveInterceptor(targetAppears = true)
        val repo = repository(transport)
        val first = async(Dispatchers.IO) {
            repo.compressResult(
                paths = listOf("/home/source.txt"),
                destinationFilePath = "/home/archive.zip",
                format = ArchiveFormat.ZIP,
                level = ArchiveCompressionLevel.MODERATE,
            )
        }
        assertTrue(transport.statusStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.compressResult(
            paths = listOf("/home/source.txt"),
            destinationFilePath = "/home/archive.zip",
            format = ArchiveFormat.ZIP,
            level = ArchiveCompressionLevel.MODERATE,
        )
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.errorCategory)
        assertFalse(duplicate.submitted)

        transport.allowStatus.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().status)
        assertEquals(1, transport.methods().count { it == "start" })
    }

    @Test
    fun `压缩进行中时拒绝删除源文件`() = runBlocking {
        val transport = BlockingArchiveInterceptor(targetAppears = true)
        val repo = repository(transport)
        val compression = async(Dispatchers.IO) {
            repo.compressResult(
                paths = listOf("/home/source.txt"),
                destinationFilePath = "/home/archive.zip",
                format = ArchiveFormat.ZIP,
                level = ArchiveCompressionLevel.MODERATE,
            )
        }
        assertTrue(transport.statusStarted.await(2, TimeUnit.SECONDS))

        val deletion = repo.deleteResult(listOf("/home/source.txt"))
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, deletion.status)
        assertEquals(MutationErrorCategory.CONFLICT, deletion.errorCategory)
        assertFalse(deletion.submitted)

        transport.allowStatus.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, compression.await().status)
        assertFalse(transport.methods().contains("delete"))
    }

    private fun repository(
        interceptor: Interceptor,
        supportsArchives: Boolean = true,
    ): DsmRepository = DsmRepository(
        profile = NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        session = DsmSession("test", "test-session", "test-token"),
        api = DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build(),
        ),
        capabilities = buildList {
            add(
            ApiCapability("SYNO.FileStation.List", "entry.cgi", 1, 2),
            )
            add(
            ApiCapability("SYNO.FileStation.Delete", "entry.cgi", 1, 2),
            )
            if (supportsArchives) {
                add(ApiCapability("SYNO.FileStation.Compress", "entry.cgi", 3, 3))
                add(ApiCapability("SYNO.FileStation.Extract", "entry.cgi", 2, 2))
            }
        }.associateBy(ApiCapability::name),
    )

    private fun success(data: String) = """{"success":true,"data":$data}"""

    private fun directoryResponse(path: String, canWrite: Boolean) = success(
        """{"files":[{"name":"${path.substringAfterLast('/')}","path":"$path","isdir":true,"additional":{"perm":{"write":$canWrite}}}]}""",
    )

    private fun listResponse(item: String? = null) = success(
        """{"offset":0,"total":${if (item == null) 0 else 1},"files":[${item.orEmpty()}]}""",
    )
}

private class ArchiveInterceptor(vararg responses: Any) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val step = pending.removeFirstOrNull() ?: error("缺少合成压缩响应")
        if (step is IOException) throw step
        val body = step as String
        return Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body(body.toResponseBody("application/json".toMediaType()))
            .build()
    }

    fun methods(): List<String?> = requests.map { it.formFields()["method"] }
}

private class BlockingArchiveInterceptor(
    private val targetAppears: Boolean = false,
) : Interceptor {
    val statusStarted = CountDownLatch(1)
    val allowStatus = CountDownLatch(1)
    val requests: MutableList<Request> = Collections.synchronizedList(mutableListOf())

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val fields = request.formFields()
        val method = fields["method"]
        val body = when (method) {
            "getinfo" -> """{"success":true,"data":{"files":[{"name":"home","path":"/home","isdir":true,"additional":{"perm":{"write":true}}}]}}"""
            "start" -> """{"success":true,"data":{"taskid":"compress-task"}}"""
            "status" -> {
                statusStarted.countDown()
                check(allowStatus.await(2, TimeUnit.SECONDS)) { "等待压缩状态响应超时" }
                """{"success":true,"data":{"finished":true}}"""
            }
            "stop" -> """{"success":true,"data":{}}"""
            "list" -> if (targetAppears && statusStarted.count == 0L) {
                """{"success":true,"data":{"offset":0,"total":1,"files":[{"name":"archive.zip","path":"/home/archive.zip","isdir":false}]}}"""
            } else {
                """{"success":true,"data":{"offset":0,"total":0,"files":[]}}"""
            }
            else -> error("未处理的压缩方法：$method")
        }
        return Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(200)
            .message("OK")
            .body(body.toResponseBody("application/json".toMediaType()))
            .build()
    }

    fun methods(): List<String?> = requests.map { it.formFields()["method"] }
}

private fun Request.formFields(): Map<String, String> {
    val body = body as? okhttp3.FormBody ?: return emptyMap()
    return (0 until body.size).associate { body.name(it) to body.value(it) }
}
