package io.github.qwertyuiop1995.dsmnativeclient.data.container

import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerSection
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class ContainerRepositoryReadOnlyBoundaryTest {
    @Test
    fun `仅支持 v2 的附属 API 和日志不会发出请求`() = runBlocking {
        val gateway = FakeContainerRepositoryGateway(
            versions = containerApis.associateWith { apiName ->
                if (apiName == containerApi) 1..1 else 2..2
            },
        )

        val overview = ContainerRepository(gateway).overview()

        assertEquals(
            setOf(
                ContainerSection.IMAGES,
                ContainerSection.NETWORKS,
                ContainerSection.PROJECTS,
                ContainerSection.EVENTS,
            ),
            overview.unavailableSections,
        )
        assertEquals(listOf(containerApi), gateway.calls.map(FakeContainerRepositoryGateway.Call::apiName))
    }

    @Test
    fun `概览所有 Container Manager 读取都强制使用 v1`() = runBlocking {
        val gateway = FakeContainerRepositoryGateway(
            versions = containerApis.associateWith { 1..2 },
        )

        ContainerRepository(gateway).overview()

        assertEquals(containerApis, gateway.calls.map(FakeContainerRepositoryGateway.Call::apiName))
        assertTrue(gateway.calls.all { it.version == 1 })
    }

    @Test
    fun `附属读取的取消和认证失败不会降级为不可用`() = runBlocking {
        val cancellation = CancellationException("synthetic cancellation")
        val sessionExpired = DsmFailure(
            null,
            "session expired",
            "sign in again",
            kind = DsmErrorKind.SESSION_EXPIRED,
        )
        val authenticationFailed = DsmFailure(
            null,
            "authentication failed",
            "sign in again",
            kind = DsmErrorKind.AUTHENTICATION_FAILED,
        )
        val scenarios = listOf(
            FailureScenario("SYNO.Docker.Image", cancellation),
            FailureScenario("SYNO.Docker.Image", sessionExpired),
            FailureScenario("SYNO.Docker.Log", authenticationFailed),
        )

        scenarios.forEach { scenario ->
            val gateway = FakeContainerRepositoryGateway(
                versions = containerApis.associateWith { 1..1 },
                failures = mapOf(scenario.apiName to scenario.failure),
            )

            val failure = runCatching { ContainerRepository(gateway).overview() }.exceptionOrNull()

            assertSame(scenario.failure, failure)
        }
    }

    @Test
    fun `概览不会保留 Container 响应中的 detail 或 metadata`() = runBlocking {
        val gateway = FakeContainerRepositoryGateway(
            versions = mapOf(containerApi to (1..1)),
            resources = mapOf(
                containerApi to listOf(
                    ManagedResource(
                        id = "container-1",
                        name = "Container 1",
                        detail = "/private/volume/secret",
                        state = ResourceState.RUNNING,
                        metadata = mapOf(
                            "path" to "/private/volume/secret",
                            "token" to "sensitive-token",
                        ),
                    ),
                ),
            ),
        )

        val container = ContainerRepository(gateway).overview().containers.single()

        assertEquals("container-1", container.id)
        assertEquals("Container 1", container.name)
        assertEquals(ResourceState.RUNNING, container.state)
        assertEquals("", container.detail)
        assertTrue(container.metadata.isEmpty())
    }

    private data class FailureScenario(
        val apiName: String,
        val failure: Throwable,
    )

    private class FakeContainerRepositoryGateway(
        private val versions: Map<String, IntRange>,
        private val resources: Map<String, List<ManagedResource>> = emptyMap(),
        private val failures: Map<String, Throwable> = emptyMap(),
    ) : ContainerRepositoryGateway {
        data class Call(
            val apiName: String,
            val method: String,
            val parameters: Map<String, String>,
            val version: Int?,
        )

        val calls = mutableListOf<Call>()

        override fun supports(apiName: String): Boolean = apiName in versions

        override fun supportsVersion(apiName: String, version: Int): Boolean {
            val range = versions[apiName] ?: return false
            return version in range
        }

        override suspend fun call(
            apiName: String,
            method: String,
            parameters: Map<String, String>,
            version: Int?,
        ): JsonObject {
            calls += Call(apiName, method, parameters, version)
            failures[apiName]?.let { throw it }
            return JsonObject(mapOf(sourceKey to JsonPrimitive(apiName)))
        }

        override fun strictResources(data: JsonObject, vararg roots: String): List<ManagedResource> =
            resources[data[sourceKey]?.jsonPrimitive?.contentOrNull].orEmpty()

        override fun elements(data: JsonObject, key: String): List<JsonElement> = emptyList()

        override fun firstNonBlank(data: JsonObject, vararg keys: String): String? = null

        override fun bool(data: JsonObject, key: String): Boolean? = null

        override suspend fun resourceList(
            apiName: String,
            methods: List<String>,
            vararg roots: String,
        ): List<ManagedResource> = emptyList()

        override fun unsupportedMutation(operation: String, diagnosticTag: String): MutationResult =
            error("只读概览测试不应调用写操作")

        override fun mutationResult(
            operation: String,
            status: MutationResultStatus,
            submitted: Boolean,
            requiresRefresh: Boolean,
            errorCategory: MutationErrorCategory?,
            diagnosticTag: String,
            affectedCount: Int,
        ): MutationResult = error("只读概览测试不应调用写操作")

        override suspend fun verifiedMutation(
            operation: String,
            targetKey: String,
            requiredApi: String,
            preflight: suspend () -> Boolean,
            submit: suspend () -> Unit,
            verify: suspend () -> Boolean,
        ): MutationResult = error("只读概览测试不应调用写操作")

        override suspend fun deleteResourceResult(
            operation: String,
            targetType: String,
            id: String,
            apiName: String,
            root: String,
            method: String,
        ): MutationResult = error("只读概览测试不应调用写操作")
    }

    private companion object {
        const val containerApi = "SYNO.Docker.Container"
        const val sourceKey = "source"
        val containerApis = listOf(
            containerApi,
            "SYNO.Docker.Image",
            "SYNO.Docker.Network",
            "SYNO.Docker.Project",
            "SYNO.Docker.Log",
        )
    }
}
