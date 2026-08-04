package io.github.qwertyuiop1995.dsmnativeclient.network

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import java.io.ByteArrayOutputStream
import java.nio.file.Files
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

class BinaryPreviewTest {
    @Test
    fun `范围读取携带认证且严格核对响应区间`() = runBlocking {
        val transport = BinaryInterceptor(
            BinaryResponse(206, "hello".encodeToByteArray(), "text/plain", "bytes 0-4/10"),
        )

        val bytes = client(transport).readBinary(
            profile,
            session,
            downloadCapability,
            2,
            "download",
            mapOf("path" to "[\"/share/readme.txt\"]", "mode" to "download"),
            maximumBytes = 8,
            range = 0L..4L,
        )

        assertEquals("hello", bytes.decodeToString())
        val request = transport.requests.single()
        assertEquals("bytes=0-4", request.header("Range"))
        assertEquals("id=test-session", request.header("Cookie"))
        assertEquals("test-token", request.header("X-SYNO-TOKEN"))
        assertFalse(request.url.queryParameterNames.any {
            it.equals("_sid", true) || it.contains("token", true)
        })
        assertEquals("download", request.url.queryParameter("method"))
    }

    @Test
    fun `范围请求收到完整响应时拒绝继续读取`() = runBlocking {
        val transport = BinaryInterceptor(BinaryResponse(200, "hello".encodeToByteArray()))

        val failure = runCatching {
            client(transport).readBinary(
                profile,
                session,
                downloadCapability,
                2,
                "download",
                emptyMap(),
                maximumBytes = 8,
                range = 0L..4L,
            )
        }.exceptionOrNull() as DsmFailure

        assertEquals(DsmErrorKind.INVALID_RESPONSE, failure.kind)
    }

    @Test
    fun `未请求Range的流式下载拒绝任何部分响应`() = runBlocking {
        listOf(
            BinaryResponse(206, "partial".encodeToByteArray(), contentRange = "bytes 0-6/20"),
            BinaryResponse(206, "partial".encodeToByteArray()),
            BinaryResponse(200, "partial".encodeToByteArray(), contentRange = "bytes 0-6/20"),
        ).forEach { response ->
            val output = ByteArrayOutputStream()
            val failure = runCatching {
                client(BinaryInterceptor(response)).downloadBinaryToOutput(
                    profile = profile,
                    session = session,
                    capability = downloadCapability,
                    preferredVersion = 2,
                    method = "download",
                    parameters = emptyMap(),
                    output = output,
                    expectedBytes = null,
                )
            }.exceptionOrNull() as DsmFailure

            assertEquals(DsmErrorKind.INVALID_RESPONSE, failure.kind)
            assertEquals(0, output.size())
        }
    }

    @Test
    fun `范围预览拒绝与请求结束位置不一致的响应`() = runBlocking {
        val transport = BinaryInterceptor(
            BinaryResponse(206, "hell".encodeToByteArray(), contentRange = "bytes 0-3/10"),
        )

        val failure = runCatching {
            client(transport).readBinary(
                profile,
                session,
                downloadCapability,
                2,
                "download",
                emptyMap(),
                maximumBytes = 8,
                range = 0L..4L,
            )
        }.exceptionOrNull() as DsmFailure

        assertEquals(DsmErrorKind.INVALID_RESPONSE, failure.kind)
    }

    @Test
    fun `范围预览始终核对响应体与Content Range跨度`() = runBlocking {
        listOf("four", "sixsix").forEach { body ->
            val transport = BinaryInterceptor(
                BinaryResponse(206, body.encodeToByteArray(), contentRange = "bytes 0-4/10"),
            )

            val failure = runCatching {
                client(transport).readBinary(
                    profile,
                    session,
                    downloadCapability,
                    2,
                    "download",
                    emptyMap(),
                    maximumBytes = 8,
                    range = 0L..4L,
                )
            }.exceptionOrNull() as DsmFailure

            assertEquals(DsmErrorKind.INVALID_RESPONSE, failure.kind)
        }
    }

    @Test
    fun `响应超过预览上限时在分配前拒绝`() = runBlocking {
        val transport = BinaryInterceptor(BinaryResponse(200, "12345".encodeToByteArray()))

        val failure = runCatching {
            client(transport).readBinary(
                profile,
                session,
                thumbCapability,
                2,
                "get",
                emptyMap(),
                maximumBytes = 4,
            )
        }.exceptionOrNull() as DsmFailure

        assertEquals(DsmErrorKind.PREVIEW_TOO_LARGE, failure.kind)
    }

    @Test
    fun `预览下载大小不一致时删除不完整文件`() = runBlocking {
        val transport = BinaryInterceptor(BinaryResponse(200, "short".encodeToByteArray()))
        val destination = Files.createTempDirectory("preview-test").resolve("preview.bin").toFile()

        val failure = runCatching {
            client(transport).downloadBinaryToFile(
                profile,
                session,
                downloadCapability,
                2,
                "download",
                emptyMap(),
                destination,
                expectedBytes = 8,
                maximumBytes = 16,
            )
        }.exceptionOrNull() as DsmFailure

        assertEquals(DsmErrorKind.DOWNLOAD_LENGTH_MISMATCH, failure.kind)
        assertFalse(destination.exists())
        assertTrue(requireNotNull(destination.parentFile).delete())
    }

    private fun client(interceptor: Interceptor) = DsmApiClient(
        OkHttpClient.Builder()
            .retryOnConnectionFailure(false)
            .addInterceptor(interceptor)
            .build(),
    )

    private companion object {
        val profile = NasProfile("test", "Test", "https://nas.example.invalid", "tester")
        val session = DsmSession("test", "test-session", "test-token")
        val downloadCapability = ApiCapability("SYNO.FileStation.Download", "entry.cgi", 1, 2)
        val thumbCapability = ApiCapability("SYNO.FileStation.Thumb", "entry.cgi", 1, 2)
    }
}

private data class BinaryResponse(
    val code: Int,
    val body: ByteArray,
    val contentType: String = "application/octet-stream",
    val contentRange: String? = null,
)

private class BinaryInterceptor(vararg responses: BinaryResponse) : Interceptor {
    private val pending = ArrayDeque(responses.toList())
    val requests = mutableListOf<Request>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        requests += request
        val response = pending.removeFirstOrNull() ?: error("缺少合成响应")
        return Response.Builder()
            .request(request)
            .protocol(Protocol.HTTP_1_1)
            .code(response.code)
            .message(if (response.code in 200..299) "OK" else "Error")
            .apply { response.contentRange?.let { header("Content-Range", it) } }
            .body(response.body.toResponseBody(response.contentType.toMediaType()))
            .build()
    }
}
