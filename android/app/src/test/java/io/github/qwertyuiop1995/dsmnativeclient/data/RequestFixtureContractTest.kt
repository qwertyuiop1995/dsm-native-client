package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import java.nio.file.Files
import java.nio.file.Path
import java.util.Collections
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RequestFixtureContractTest {
    @Test
    fun `File Station 删除请求与共享 Fixture 一致`() = runTest {
        val fixture = loadFixture(
            "file-station/delete/synthetic-task/request.json"
        )
        val harness = RequestHarness(fixture)

        harness.repository.delete(listOf("<synthetic-path>"))

        assertRequestMatchesFixture(harness.mutationRequest(), fixture)
    }

    @Test
    fun `容器删除请求与共享 Fixture 一致`() = runTest {
        val fixture = loadFixture(
            "container-manager/delete/synthetic-container/request.json"
        )
        val harness = RequestHarness(fixture)

        harness.repository.deleteContainer("<synthetic-container>")

        assertRequestMatchesFixture(harness.mutationRequest(), fixture)
    }

    @Test
    fun `官方虚拟机删除请求与共享 Fixture 一致且没有多余参数`() = runTest {
        val fixture = loadFixture(
            "vmm/delete/synthetic-virtual-machine/request.json"
        )
        val harness = RequestHarness(fixture)

        harness.repository.deleteVirtualMachine("<synthetic-virtual-machine>")

        assertRequestMatchesFixture(harness.mutationRequest(), fixture)
    }

    private fun assertRequestMatchesFixture(
        request: Request,
        fixture: JsonObject,
    ) {
        val api = fixture.getValue("api").jsonObject
        val transport = fixture.getValue("transport").jsonObject
        val authentication = fixture.getValue("authentication").jsonObject
        val body = request.body as FormBody
        val values = (0 until body.size).associate { body.name(it) to body.value(it) }
        val expectedParameters = fixture.getValue("parameters").jsonArray.associate { value ->
            val parameter = value.jsonObject
            parameter.getValue("name").jsonPrimitive.content to
                parameter.getValue("encodedValue").jsonPrimitive.content
        }
        val actualParameters = values.filterKeys {
            it !in setOf("api", "version", "method", "_sid")
        }

        assertEquals(
            transport.getValue("httpMethod").jsonPrimitive.content,
            request.method,
        )
        assertEquals(
            "form",
            transport.getValue("requestFormat").jsonPrimitive.content,
        )
        assertEquals(
            "/webapi/${api.getValue("resolvedPath").jsonPrimitive.content}",
            request.url.encodedPath,
        )
        assertEquals(api.getValue("name").jsonPrimitive.content, values["api"])
        assertEquals(api.getValue("method").jsonPrimitive.content, values["method"])
        assertEquals(api.getValue("resolvedVersion").jsonPrimitive.content, values["version"])
        assertEquals(expectedParameters, actualParameters)

        if (authentication.getValue("required").jsonPrimitive.content == "true") {
            val sessionLocations = authentication.getValue("sessionLocations")
                .jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }.toSet()
            assertTrue("cookie" in sessionLocations)
            assertTrue("form" in sessionLocations)
            assertNotNull(request.header("Cookie"))
            assertNotNull(values["_sid"])
        }
        if (request.header("X-SYNO-TOKEN") != null) {
            val tokenLocations = authentication.getValue("synoTokenLocations")
                .jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }.toSet()
            assertTrue("header" in tokenLocations)
        }
    }

    private fun loadFixture(relativePath: String): JsonObject {
        var current = Path.of(System.getProperty("user.dir")).toAbsolutePath()
        repeat(8) {
            val candidate = current.resolve("contracts/request-fixtures/$relativePath")
            if (Files.isRegularFile(candidate)) {
                return Json.parseToJsonElement(candidate.toFile().readText()).jsonObject
            }
            current = current.parent
        }
        error("找不到共享请求 Fixture：$relativePath")
    }
}

private class RequestHarness(fixture: JsonObject) {
    private val requests = Collections.synchronizedList(mutableListOf<Request>())
    private val api = fixture.getValue("api").jsonObject
    private val apiName = api.getValue("name").jsonPrimitive.content
    private val method = api.getValue("method").jsonPrimitive.content
    private val version = api.getValue("resolvedVersion").jsonPrimitive.content.toInt()
    private val client = OkHttpClient.Builder()
        .addInterceptor { chain ->
            requests += chain.request()
            Response.Builder()
                .request(chain.request())
                .protocol(Protocol.HTTP_1_1)
                .code(200)
                .message("OK")
                .body(
                    """{"success":true,"data":{"shares":[],"containers":[],"guests":[]}}"""
                        .toResponseBody("application/json".toMediaType())
                )
                .build()
        }
        .build()

    val repository = DsmRepository(
        profile = NasProfile(
            id = "test-profile",
            name = "测试 NAS",
            address = "nas.example.invalid",
            username = "test-account",
        ),
        session = DsmSession(
            profileId = "test-profile",
            sid = "synthetic-session",
            synoToken = "synthetic-token",
        ),
        api = DsmApiClient(client),
        capabilities = mapOf(
            apiName to ApiCapability(
                name = apiName,
                path = api.getValue("resolvedPath").jsonPrimitive.content,
                minVersion = version,
                maxVersion = version,
            ),
            "SYNO.FileStation.List" to ApiCapability(
                name = "SYNO.FileStation.List",
                path = "entry.cgi",
                minVersion = 2,
                maxVersion = 2,
            ),
        ),
    )

    fun mutationRequest(): Request = requests.first { request ->
        val body = request.body as? FormBody ?: return@first false
        val values = (0 until body.size).associate { body.name(it) to body.value(it) }
        values["api"] == apiName && values["method"] == method
    }
}
