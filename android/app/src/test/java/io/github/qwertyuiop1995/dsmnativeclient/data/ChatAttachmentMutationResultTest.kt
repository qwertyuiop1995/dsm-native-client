package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.io.ByteArrayInputStream
import java.io.IOException
import java.io.InputStream
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatAttachmentMutationResultTest {
    @Test
    fun `完整上传后断线且近期附件匹配时确认成功且不重放`() = runBlocking {
        val transport = ScriptedAttachmentResultInterceptor(
            IOException("synthetic disconnect"),
            recentAttachmentPosts(),
        )

        val outcome = repository(transport).sendChatAttachmentMessageResult(
            "channel-1", "caption", source(), "request-1", { _, _ -> },
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals("post-readback", outcome.message?.id)
        assertEquals(1, transport.requests.count { it.body is MultipartBody })
        assertEquals(2, transport.requests.size)
    }

    @Test
    fun `完整上传后断线且回读无匹配时保持未确认`() = runBlocking {
        val transport = ScriptedAttachmentResultInterceptor(
            IOException("synthetic disconnect"),
            emptyPosts(),
        )

        val outcome = repository(transport).sendChatAttachmentMessageResult(
            "channel-1", "caption", source(), "request-1", { _, _ -> },
        )

        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, outcome.result.status)
        assertTrue(outcome.result.requiresRefresh)
        assertEquals(1, transport.requests.count { it.body is MultipartBody })
    }

    @Test
    fun `响应缺少消息ID但回读附件匹配时确认成功`() = runBlocking {
        val transport = ScriptedAttachmentResultInterceptor(
            """{"success":true,"data":{}}""",
            recentAttachmentPosts(),
        )

        val outcome = repository(transport).sendChatAttachmentMessageResult(
            "channel-1", "caption", source(), "request-1", { _, _ -> },
        )

        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, outcome.result.status)
        assertEquals("sample.txt", outcome.message?.attachments?.single()?.name)
    }

    @Test
    fun `完整上传后权限拒绝且回读无附件时报告权限不足`() = runBlocking {
        val transport = ScriptedAttachmentResultInterceptor(
            """{"success":false,"error":{"code":105}}""",
            emptyPosts(),
        )

        val outcome = repository(transport).sendChatAttachmentMessageResult(
            "channel-1", "caption", source(), "request-1", { _, _ -> },
        )

        assertEquals(MutationResultStatus.PERMISSION_DENIED, outcome.result.status)
        assertEquals(MutationErrorCategory.PERMISSION, outcome.result.errorCategory)
    }

    @Test
    fun `附件流未上传完成时失败不回读且不标记已提交`() = runBlocking {
        val transport = ScriptedAttachmentResultInterceptor(IOException("synthetic source failure"))
        val broken = source(open = {
            object : InputStream() {
                private var count = 0
                override fun read(): Int {
                    if (count++ < 2) return 'x'.code
                    throw IOException("synthetic source failure")
                }
            }
        })

        val outcome = repository(transport).sendChatAttachmentMessageResult(
            "channel-1", "caption", broken, "request-1", { _, _ -> },
        )

        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, outcome.result.status)
        assertFalse(outcome.result.submitted)
        assertEquals(1, transport.requests.size)
    }

    @Test
    fun `非法输入不支持能力和提交前取消均零请求关闭`() {
        val invalidTransport = ScriptedAttachmentResultInterceptor()
        runBlocking {
            val invalid = repository(invalidTransport).sendChatAttachmentMessageResult(
                "channel-1", "caption", source(name = "bad/name"), "request-1", { _, _ -> },
            )
            assertEquals(MutationErrorCategory.VALIDATION, invalid.result.errorCategory)
        }
        assertTrue(invalidTransport.requests.isEmpty())

        val unsupportedTransport = ScriptedAttachmentResultInterceptor()
        runBlocking {
            val unsupported = repository(unsupportedTransport, maximumVersion = 4)
                .sendChatAttachmentMessageResult(
                    "channel-1", "caption", source(), "request-1", { _, _ -> },
                )
            assertEquals(MutationResultStatus.UNSUPPORTED, unsupported.result.status)
        }
        assertTrue(unsupportedTransport.requests.isEmpty())

        val cancelledTransport = ScriptedAttachmentResultInterceptor()
        val job = Job()
        var status: MutationResultStatus? = null
        runCatching {
            runBlocking(job) {
                job.cancel()
                status = repository(cancelledTransport).sendChatAttachmentMessageResult(
                    "channel-1", "caption", source(), "request-1", { _, _ -> },
                ).result.status
            }
        }
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, status)
        assertTrue(cancelledTransport.requests.isEmpty())
    }

    @Test
    fun `同一客户端请求上传中拒绝重复提交`() = runBlocking {
        val transport = BlockingAttachmentResultInterceptor()
        val repo = repository(transport)
        val first = async(Dispatchers.IO) {
            repo.sendChatAttachmentMessageResult(
                "channel-1", "caption", source(), "request-1", { _, _ -> },
            )
        }
        assertTrue(transport.uploadStarted.await(2, TimeUnit.SECONDS))

        val duplicate = repo.sendChatAttachmentMessageResult(
            "channel-1", "caption", source(), "request-1", { _, _ -> },
        )
        assertEquals(MutationResultStatus.CONFIRMED_FAILURE, duplicate.result.status)
        assertEquals(MutationErrorCategory.CONFLICT, duplicate.result.errorCategory)

        transport.allowResponse.countDown()
        assertEquals(MutationResultStatus.CONFIRMED_SUCCESS, first.await().result.status)
        assertEquals(1, transport.uploadRequests.get())
    }

    @Test
    fun `完整上传后取消只回读且不重放`() = runBlocking {
        val transport = CancellableAttachmentResultInterceptor()
        val repo = repository(transport)
        var status: MutationResultStatus? = null
        val worker = launch(Dispatchers.IO) {
            status = repo.sendChatAttachmentMessageResult(
                "channel-1", "caption", source(), "request-1", { _, _ -> },
            ).result.status
        }
        assertTrue(transport.uploadStarted.await(2, TimeUnit.SECONDS))

        worker.cancel()
        transport.allowResponse.countDown()
        worker.join()

        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, status)
        assertEquals(1, transport.uploadRequests.get())
        assertEquals(1, transport.readbackRequests.get())
    }

    private fun repository(interceptor: Interceptor, maximumVersion: Int = 5) = DsmRepository(
        NasProfile("test", "Test", "https://nas.example.invalid", "operator"),
        DsmSession("test", "synthetic-session", "synthetic-token"),
        DsmApiClient(
            OkHttpClient.Builder().retryOnConnectionFailure(false).addInterceptor(interceptor).build(),
        ),
        mapOf(
            "SYNO.Chat.Post" to ApiCapability("SYNO.Chat.Post", "entry.cgi", 1, maximumVersion),
        ),
    )

    private fun source(
        name: String = "sample.txt",
        open: () -> InputStream = { ByteArrayInputStream("synthetic".toByteArray()) },
    ) = UploadSource(name, "text/plain", 9, open)
}

private class ScriptedAttachmentResultInterceptor(vararg steps: Any) : Interceptor {
    private val pending = ArrayDeque(steps.toList())
    val requests: MutableList<Request> = Collections.synchronizedList(mutableListOf())

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        if (request.body is MultipartBody) request.body?.writeTo(Buffer())
        val step = pending.removeFirstOrNull() ?: error("缺少合成 Chat 附件响应")
        if (step is IOException) throw step
        return attachmentResultResponse(request, step as String)
    }
}

private class BlockingAttachmentResultInterceptor : Interceptor {
    val uploadStarted = CountDownLatch(1)
    val allowResponse = CountDownLatch(1)
    val uploadRequests = AtomicInteger()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        request.body?.writeTo(Buffer())
        uploadRequests.incrementAndGet()
        uploadStarted.countDown()
        check(allowResponse.await(2, TimeUnit.SECONDS)) { "等待 Chat 附件响应超时" }
        return attachmentResultResponse(
            request,
            """{"success":true,"data":{"post_id":"post-1","channel_id":"channel-1","message":"caption","files":[{"file_id":"file-1","file_name":"sample.txt","size":9}]}}""",
        )
    }
}

private class CancellableAttachmentResultInterceptor : Interceptor {
    val uploadStarted = CountDownLatch(1)
    val allowResponse = CountDownLatch(1)
    val uploadRequests = AtomicInteger()
    val readbackRequests = AtomicInteger()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val body = if (request.body is MultipartBody) {
            request.body?.writeTo(Buffer())
            uploadRequests.incrementAndGet()
            uploadStarted.countDown()
            check(allowResponse.await(2, TimeUnit.SECONDS)) { "等待 Chat 附件响应超时" }
            """{"success":true,"data":{"post_id":"post-1"}}"""
        } else {
            readbackRequests.incrementAndGet()
            emptyPosts()
        }
        return attachmentResultResponse(request, body)
    }
}

private fun attachmentResultResponse(request: Request, body: String) = Response.Builder()
    .request(request)
    .protocol(Protocol.HTTP_1_1)
    .code(200)
    .message("OK")
    .body(body.toResponseBody("application/json".toMediaType()))
    .build()

private fun recentAttachmentPosts(): String =
    """{"success":true,"data":{"total":1,"posts":[{"post_id":"post-readback","channel_id":"channel-1","message":"caption","create_at":${System.currentTimeMillis()},"is_my_post":true,"files":[{"file_id":"file-1","file_name":"sample.txt","size":9}]}]}}"""

private fun emptyPosts() = """{"success":true,"data":{"total":0,"posts":[]}}"""
