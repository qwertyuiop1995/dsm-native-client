package io.github.qwertyuiop1995.dsmnativeclient.data.container

import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerRegistryImage
import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerSection
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.data.parseVirtualizationLogs
import io.github.qwertyuiop1995.dsmnativeclient.network.int
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Container Manager 的内部数据边界。
 *
 * `DsmRepository` 仍是应用层唯一入口；本类只通过窄 gateway 复用会话请求、统一写操作结果
 * 和并发门禁，避免复制 Repository 的公共基础设施或扩大其私有可见性。
 */
internal class ContainerRepository(
    private val gateway: ContainerRepositoryGateway,
) {
    suspend fun overview(): ContainerOverview {
        if (!gateway.supportsVersion("SYNO.Docker.Container", 1)) throw DsmFailure(
            102,
            "Container Manager is unavailable",
            "Update Container Manager and try again.",
            kind = DsmErrorKind.FEATURE_UNSUPPORTED,
        )
        val containers = gateway.strictResources(
            gateway.call(
                "SYNO.Docker.Container",
                "list",
                mapOf("offset" to "0", "limit" to "-1", "type" to "all"),
                version = 1,
            ),
            "containers", "container", "data", "list",
        ).map { it.toContainerReadOnlyResource() }
        val unavailable = mutableSetOf<ContainerSection>()
        suspend fun supplementary(
            section: ContainerSection,
            apiName: String,
            method: String,
            parameters: Map<String, String> = emptyMap(),
            vararg roots: String,
        ): List<ManagedResource> {
            if (!gateway.supportsVersion(apiName, 1)) {
                unavailable += section
                return emptyList()
            }
            return runCatching {
                gateway.strictResources(
                    gateway.call(apiName, method, parameters, version = 1),
                    *roots,
                ).map { it.toContainerReadOnlyResource() }
            }.getOrElse { error ->
                error.rethrowIfContainerBoundaryFailure()
                unavailable += section
                emptyList()
            }
        }
        val images = supplementary(
            ContainerSection.IMAGES,
            "SYNO.Docker.Image",
            "list",
            roots = arrayOf("images", "image", "data", "list"),
        )
        val networks = supplementary(
            ContainerSection.NETWORKS,
            "SYNO.Docker.Network",
            "list",
            roots = arrayOf("networks", "network", "data", "list"),
        )
        val projects = supplementary(
            ContainerSection.PROJECTS,
            "SYNO.Docker.Project",
            "list",
            roots = arrayOf("projects", "project", "data", "list"),
        )
        val eventData = if (gateway.supportsVersion("SYNO.Docker.Log", 1)) runCatching {
            gateway.call(
                "SYNO.Docker.Log",
                "list",
                mapOf("offset" to "0", "limit" to "200"),
                version = 1,
            )
        }.getOrElse { error ->
            error.rethrowIfContainerBoundaryFailure()
            unavailable += ContainerSection.EVENTS
            null
        } else {
            unavailable += ContainerSection.EVENTS
            null
        }
        return ContainerOverview(
            containers,
            images,
            networks,
            projects,
            events = eventData?.let(::parseVirtualizationLogs).orEmpty(),
            unavailableSections = unavailable,
        )
    }

    fun supportsRegistry(): Boolean = gateway.supportsVersion("SYNO.Docker.Registry", 1)

    /** 版本化行为证据完成前，Container 写操作始终关闭。 */
    fun supportsVerifiedWrites(): Boolean = false

    suspend fun searchRegistry(query: String): List<ContainerRegistryImage> {
        val normalizedQuery = query.trim()
        require(normalizedQuery.isNotEmpty() && normalizedQuery.length <= 200)
        if (!supportsRegistry()) throw DsmFailure(
            102,
            "Container image search is unavailable",
            "Search for the image in Container Manager.",
            kind = DsmErrorKind.FEATURE_UNSUPPORTED,
        )
        val data = gateway.call(
            "SYNO.Docker.Registry",
            "search",
            mapOf(
                "offset" to "0",
                "limit" to "50",
                "page_size" to "50",
                "q" to normalizedQuery,
            ),
            version = 1,
        )
        return sequenceOf("data", "items", "results", "_array")
            .flatMap { gateway.elements(data, it).asSequence() }
            .distinctBy(JsonElement::toString)
            .mapNotNull { element ->
                val item = element as? JsonObject ?: return@mapNotNull null
                val name = gateway.firstNonBlank(item, "name", "repository", "repo")
                    ?: return@mapNotNull null
                ContainerRegistryImage(
                    name = name,
                    registry = gateway.firstNonBlank(item, "registry") ?: "docker.io",
                    description = gateway.firstNonBlank(item, "description"),
                    starCount = item.int("star_count") ?: item.int("stars") ?: 0,
                    isOfficial = gateway.bool(item, "is_official")
                        ?: gateway.bool(item, "official") ?: false,
                    isAutomated = gateway.bool(item, "is_automated")
                        ?: gateway.bool(item, "automated") ?: false,
                    isTrusted = gateway.bool(item, "is_trusted")
                        ?: gateway.bool(item, "trusted") ?: false,
                )
            }
            .distinctBy(ContainerRegistryImage::id)
            .toList()
    }

    suspend fun registryTags(repository: String): List<String> {
        val normalizedRepository = repository.trim()
        require(normalizedRepository.isNotEmpty() && normalizedRepository.length <= 500)
        if (!supportsRegistry()) throw DsmFailure(
            102,
            "Container image tags are unavailable",
            "View the image tags in Container Manager.",
            kind = DsmErrorKind.FEATURE_UNSUPPORTED,
        )
        val data = gateway.call(
            "SYNO.Docker.Registry",
            "tags",
            mapOf("repo" to normalizedRepository),
            version = 1,
        )
        return sequenceOf("data", "tags", "items", "_array")
            .flatMap { gateway.elements(data, it).asSequence() }
            .mapNotNull { element ->
                when (element) {
                    is JsonObject -> gateway.firstNonBlank(element, "tag", "name")
                    is JsonPrimitive -> element.contentOrNull?.trim()?.takeIf(String::isNotBlank)
                    else -> null
                }
            }
            .distinct()
            .toList()
    }

    suspend fun controlResult(id: String, action: String): MutationResult {
        if (!supportsVerifiedWrites()) return gateway.unsupportedMutation(
            "containerControl",
            "container.control.behavior-unverified",
        )
        val normalizedId = id.trim()
        if (normalizedId.isEmpty() || action !in setOf("start", "stop", "restart")) {
            return gateway.mutationResult(
                operation = "containerControl",
                status = MutationResultStatus.CONFIRMED_FAILURE,
                submitted = false,
                errorCategory = MutationErrorCategory.VALIDATION,
                diagnosticTag = "container.control.invalid-input",
            )
        }
        val expectedState = if (action == "stop") ResourceState.STOPPED else ResourceState.RUNNING
        return gateway.verifiedMutation(
            operation = "containerControl",
            targetKey = "container:$normalizedId",
            requiredApi = "SYNO.Docker.Container",
            preflight = {
                gateway.resourceList(
                    "SYNO.Docker.Container",
                    listOf("list", "get"),
                    "containers",
                ).any { it.id == normalizedId }
            },
            submit = {
                gateway.call("SYNO.Docker.Container", action, mapOf("id" to normalizedId))
            },
            verify = {
                gateway.resourceList(
                    "SYNO.Docker.Container",
                    listOf("list", "get"),
                    "containers",
                ).any { it.id == normalizedId && it.state == expectedState }
            },
        )
    }

    suspend fun deleteResult(id: String): MutationResult {
        if (!supportsVerifiedWrites()) return gateway.unsupportedMutation(
            "containerDelete",
            "container.delete.behavior-unverified",
        )
        return gateway.deleteResourceResult(
            operation = "containerDelete",
            targetType = "container",
            id = id,
            apiName = "SYNO.Docker.Container",
            root = "containers",
            method = "delete",
        )
    }

    suspend fun deleteImageResult(id: String): MutationResult {
        if (!supportsVerifiedWrites()) return gateway.unsupportedMutation(
            "containerImageDelete",
            "container.image.delete.behavior-unverified",
        )
        return gateway.deleteResourceResult(
            operation = "containerImageDelete",
            targetType = "container-image",
            id = id,
            apiName = "SYNO.Docker.Image",
            root = "images",
            method = "delete",
        )
    }

    suspend fun createNetworkResult(name: String, driver: String): MutationResult {
        if (!supportsVerifiedWrites()) return gateway.unsupportedMutation(
            "containerNetworkCreate",
            "container.network.create.behavior-unverified",
        )
        val normalizedName = name.trim()
        if (normalizedName.isEmpty() || driver !in setOf("bridge", "host", "macvlan", "ipvlan")) {
            return gateway.mutationResult(
                operation = "containerNetworkCreate",
                status = MutationResultStatus.CONFIRMED_FAILURE,
                submitted = false,
                errorCategory = MutationErrorCategory.VALIDATION,
                diagnosticTag = "container.network.create.invalid-input",
            )
        }
        return gateway.verifiedMutation(
            operation = "containerNetworkCreate",
            targetKey = "container-network-name:${normalizedName.lowercase(Locale.ROOT)}",
            requiredApi = "SYNO.Docker.Network",
            preflight = {
                gateway.resourceList(
                    "SYNO.Docker.Network",
                    listOf("list", "get"),
                    "networks",
                ).none { it.name.equals(normalizedName, ignoreCase = true) }
            },
            submit = {
                gateway.call(
                    "SYNO.Docker.Network",
                    "create",
                    mapOf("name" to normalizedName, "driver" to driver),
                )
            },
            verify = {
                gateway.resourceList(
                    "SYNO.Docker.Network",
                    listOf("list", "get"),
                    "networks",
                ).any { it.name.equals(normalizedName, ignoreCase = true) }
            },
        )
    }

    suspend fun deleteNetworkResult(id: String): MutationResult {
        if (!supportsVerifiedWrites()) return gateway.unsupportedMutation(
            "containerNetworkDelete",
            "container.network.delete.behavior-unverified",
        )
        return gateway.deleteResourceResult(
            operation = "containerNetworkDelete",
            targetType = "container-network",
            id = id,
            apiName = "SYNO.Docker.Network",
            root = "networks",
            method = "remove",
        )
    }
}

private fun ManagedResource.toContainerReadOnlyResource(): ManagedResource = ManagedResource(
    id = id,
    name = name,
    detail = "",
    state = state,
)

private fun Throwable.rethrowIfContainerBoundaryFailure() {
    if (this is CancellationException) {
        throw this
    }
    val failure = this as? DsmFailure ?: return
    if (
        failure.kind == DsmErrorKind.SESSION_EXPIRED ||
        failure.kind == DsmErrorKind.AUTHENTICATION_FAILED
    ) {
        throw failure
    }
}

internal interface ContainerRepositoryGateway {
    fun supports(apiName: String): Boolean

    fun supportsVersion(apiName: String, version: Int): Boolean

    suspend fun call(
        apiName: String,
        method: String,
        parameters: Map<String, String> = emptyMap(),
        version: Int? = null,
    ): JsonObject

    fun strictResources(data: JsonObject, vararg roots: String): List<ManagedResource>

    fun elements(data: JsonObject, key: String): List<JsonElement>

    fun firstNonBlank(data: JsonObject, vararg keys: String): String?

    fun bool(data: JsonObject, key: String): Boolean?

    suspend fun resourceList(
        apiName: String,
        methods: List<String>,
        vararg roots: String,
    ): List<ManagedResource>

    fun unsupportedMutation(operation: String, diagnosticTag: String): MutationResult

    fun mutationResult(
        operation: String,
        status: MutationResultStatus,
        submitted: Boolean,
        requiresRefresh: Boolean = false,
        errorCategory: MutationErrorCategory? = null,
        diagnosticTag: String,
        affectedCount: Int = 1,
    ): MutationResult

    suspend fun verifiedMutation(
        operation: String,
        targetKey: String,
        requiredApi: String,
        preflight: suspend () -> Boolean,
        submit: suspend () -> Unit,
        verify: suspend () -> Boolean,
    ): MutationResult

    suspend fun deleteResourceResult(
        operation: String,
        targetType: String,
        id: String,
        apiName: String,
        root: String,
        method: String,
    ): MutationResult
}
