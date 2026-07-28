package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.ActiveConnection
import io.github.qwertyuiop1995.dsmnativeclient.domain.ApiCapability
import io.github.qwertyuiop1995.dsmnativeclient.domain.CapacitySummary
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation
import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmSession
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.LogEntry
import io.github.qwertyuiop1995.dsmnativeclient.domain.LogLevel
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResourceLabel
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleAvailability
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleUnavailableReason
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasAccount
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasGroup
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.PackageInfo
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.SystemSummary
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.network.DsmApiClient
import io.github.qwertyuiop1995.dsmnativeclient.network.arrayValue
import io.github.qwertyuiop1995.dsmnativeclient.network.int
import io.github.qwertyuiop1995.dsmnativeclient.network.long
import io.github.qwertyuiop1995.dsmnativeclient.network.objectValue
import io.github.qwertyuiop1995.dsmnativeclient.network.string
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.coroutines.delay

class DsmRepository(
    private val profile: NasProfile,
    private val session: DsmSession,
    private val api: DsmApiClient,
    private val capabilities: Map<String, ApiCapability>,
) {
    fun availability(): List<ModuleAvailability> = listOf(
        ModuleAvailability(Module.FILES, supports("SYNO.FileStation.List")),
        ModuleAvailability(Module.PHOTOS, supports("SYNO.FileStation.List")),
        ModuleAvailability(
            Module.CHAT,
            supports("SYNO.Chat.Channel"),
            ModuleUnavailableReason.CHAT_SERVICE,
        ),
        ModuleAvailability(
            Module.DOWNLOADS,
            supports("SYNO.DownloadStation.Task") || supports("SYNO.DownloadStation2.Task"),
            ModuleUnavailableReason.DOWNLOAD_STATION,
        ),
        ModuleAvailability(
            Module.CONTAINERS,
            supports("SYNO.Docker.Container"),
            ModuleUnavailableReason.CONTAINER_MANAGER,
        ),
        ModuleAvailability(
            Module.VIRTUAL_MACHINES,
            supports("SYNO.Virtualization.Guest") || supports("SYNO.Virtualization.API.Guest"),
            ModuleUnavailableReason.VIRTUAL_MACHINE_MANAGER,
        ),
        ModuleAvailability(Module.NAS_SETTINGS, supports("SYNO.Core.System")),
        ModuleAvailability(Module.TRANSFERS, true),
        ModuleAvailability(Module.SETTINGS, true),
    )

    suspend fun listShares(): FilePage {
        val data = call(
            "SYNO.FileStation.List",
            "list_share",
            mapOf(
                "offset" to "0",
                "limit" to "1000",
                "sort_by" to "name",
                "sort_direction" to "asc",
                "additional" to "[\"real_path\",\"owner\",\"time\",\"perm\",\"volume_status\"]",
            ),
        )
        return filePage(data, "shares")
    }

    suspend fun listDirectory(path: String, offset: Int = 0, limit: Int = 200): FilePage {
        val data = call(
            "SYNO.FileStation.List",
            "list",
            mapOf(
                "folder_path" to path,
                "offset" to offset.toString(),
                "limit" to limit.toString(),
                "sort_by" to "name",
                "sort_direction" to "asc",
                "filetype" to "all",
                "additional" to "[\"real_path\",\"size\",\"owner\",\"time\",\"perm\"]",
            ),
        )
        return filePage(data, "files")
    }

    suspend fun search(path: String, keyword: String): FilePage {
        val start = call(
            "SYNO.FileStation.Search",
            "start",
            mapOf(
                "folder_path" to path,
                "pattern" to keyword,
                "recursive" to "true",
            ),
        )
        val taskId = start.string("taskid")
            ?: throw DsmFailure(
                null,
                "The NAS did not start the search",
                "Try again later.",
                kind = DsmErrorKind.SEARCH_NOT_STARTED,
            )
        return try {
            val result = call(
                "SYNO.FileStation.Search",
                "list",
                mapOf(
                    "taskid" to taskId,
                    "offset" to "0",
                    "limit" to "1000",
                    "additional" to "[\"size\",\"owner\",\"time\",\"perm\"]",
                ),
            )
            filePage(result, "files")
        } finally {
            runCatching {
                call("SYNO.FileStation.Search", "stop", mapOf("taskid" to taskId))
            }
        }
    }

    suspend fun createFolder(parent: String, name: String) {
        require(name.isNotBlank() && '/' !in name) { "Invalid folder name" }
        call(
            "SYNO.FileStation.CreateFolder",
            "create",
            mapOf(
                "folder_path" to parent,
                "name" to name.trim(),
                "force_parent" to "false",
            ),
        )
        verifyExists(join(parent, name))
    }

    suspend fun rename(path: String, newName: String) {
        require(newName.isNotBlank() && '/' !in newName) { "Invalid name" }
        call(
            "SYNO.FileStation.Rename",
            "rename",
            mapOf("path" to path, "name" to newName.trim()),
        )
        verifyExists(join(path.substringBeforeLast('/', ""), newName.trim()))
    }

    suspend fun delete(paths: List<String>) {
        require(paths.isNotEmpty()) { "No item selected" }
        call(
            "SYNO.FileStation.Delete",
            "start",
            mapOf(
                "path" to jsonStrings(paths),
                "recursive" to "true",
            ),
        )
        waitUntil {
            paths.none { pathExists(it) }
        }
    }

    suspend fun createEmptyFile(parent: String, name: String) {
        require(name.isNotBlank() && '/' !in name) { "Invalid file name" }
        // File Station 没有独立的空文件接口；该能力由 multipart 上传层实现。
        throw DsmFailure(
            null,
            "Creating an empty file directly is not supported",
            "Create the file on this device first, then upload it.",
            kind = DsmErrorKind.EMPTY_FILE_UNSUPPORTED,
        )
    }

    suspend fun listDownloads(): List<DownloadTask> {
        val apiName = preferred("SYNO.DownloadStation2.Task", "SYNO.DownloadStation.Task")
        val data = call(
            apiName,
            if (apiName.contains("Station2")) "list" else "list",
            mapOf(
                "offset" to "0",
                "limit" to "1000",
                "additional" to "detail,transfer",
            ),
        )
        return data.elements("tasks").mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            val additional = item.objectValue("additional")
            val transfer = additional?.objectValue("transfer")
            val detail = additional?.objectValue("detail")
            DownloadTask(
                id = item.string("id") ?: return@mapNotNull null,
                title = item.string("title").orEmpty(),
                status = state(item.string("status")),
                size = item.long("size"),
                transferred = item.long("size_downloaded") ?: transfer?.long("size_downloaded"),
                downloadSpeed = transfer?.long("speed_download"),
                uploadSpeed = transfer?.long("speed_upload"),
                destination = detail?.string("destination"),
                error = detail?.string("error_detail"),
            )
        }
    }

    suspend fun createDownload(uri: String, destination: String?) {
        require(uri.isNotBlank()) { "Download address is required" }
        val apiName = preferred("SYNO.DownloadStation2.Task", "SYNO.DownloadStation.Task")
        call(
            apiName,
            "create",
            buildMap {
                put("uri", uri.trim())
                destination?.takeIf { it.isNotBlank() }?.let { put("destination", it) }
            },
        )
    }

    suspend fun controlDownloads(ids: List<String>, action: String, deleteFiles: Boolean = false) {
        require(action in setOf("pause", "resume", "delete")) { "Unsupported download action" }
        val apiName = preferred("SYNO.DownloadStation2.Task", "SYNO.DownloadStation.Task")
        call(
            apiName,
            action,
            buildMap {
                put("id", ids.joinToString(","))
                if (action == "delete") put("force_complete", deleteFiles.toString())
            },
        )
        if (action == "delete") {
            waitUntil {
                val remaining = listDownloads().map(DownloadTask::id).toSet()
                ids.none(remaining::contains)
            }
        }
    }

    suspend fun containerOverview(): ContainerOverview {
        val containers = resourceList("SYNO.Docker.Container", listOf("list", "get"), "containers")
        val images = resourceList("SYNO.Docker.Image", listOf("list", "get"), "images")
        val networks = resourceList("SYNO.Docker.Network", listOf("list", "get"), "networks")
        val projects = resourceList("SYNO.Docker.Project", listOf("list", "get"), "projects")
        return ContainerOverview(containers, images, networks, projects)
    }

    suspend fun controlContainer(id: String, action: String) {
        require(action in setOf("start", "stop", "restart")) { "Unsupported container action" }
        call("SYNO.Docker.Container", action, mapOf("id" to id))
    }

    suspend fun deleteContainer(id: String) {
        call("SYNO.Docker.Container", "delete", mapOf("id" to id))
        verifyResourceMissing("SYNO.Docker.Container", "containers", id)
    }

    suspend fun deleteContainerImage(id: String) {
        call("SYNO.Docker.Image", "delete", mapOf("id" to id))
        verifyResourceMissing("SYNO.Docker.Image", "images", id)
    }

    suspend fun createContainerNetwork(name: String, driver: String) {
        require(name.isNotBlank()) { "Network name is required" }
        call(
            "SYNO.Docker.Network",
            "create",
            mapOf("name" to name.trim(), "driver" to driver),
        )
        waitUntil {
            containerOverview().networks.any { it.name.equals(name.trim(), ignoreCase = true) }
        }
    }

    suspend fun deleteContainerNetwork(id: String) {
        call("SYNO.Docker.Network", "remove", mapOf("id" to id))
        verifyResourceMissing("SYNO.Docker.Network", "networks", id)
    }

    suspend fun virtualMachineOverview(): VirtualMachineOverview {
        val guestApi = preferred("SYNO.Virtualization.Guest", "SYNO.Virtualization.API.Guest")
        val hostApi = preferredOrNull("SYNO.Virtualization.Host", "SYNO.Virtualization.API.Host")
        val storageApi = preferredOrNull("SYNO.Virtualization.Repo", "SYNO.Virtualization.API.Storage")
        val networkApi = preferredOrNull("SYNO.Virtualization.Network", "SYNO.Virtualization.API.Network")
        val imageApi = preferredOrNull(
            "SYNO.Virtualization.Guest.Image",
            "SYNO.Virtualization.API.Guest.Image",
        )
        val machines = resourceList(guestApi, listOf("list"), "guests", "vms")
        val hosts = hostApi?.let { resourceList(it, listOf("list"), "hosts", "host", "data", "list") }
            .orEmpty()
        val storages = storageApi?.let {
            resourceList(it, listOf("list"), "repos", "storages", "data", "list")
        }.orEmpty()
        val networks = networkApi?.let {
            resourceList(it, listOf("list"), "networks", "network", "data", "list")
        }.orEmpty()
        val images = imageApi?.let {
            resourceList(it, listOf("list"), "images", "image", "data", "list")
        }.orEmpty()
        val protectionData = if (supports("SYNO.Virtualization.GuestProtect.Plan")) {
            runCatching {
                firstSuccessful(
                    "SYNO.Virtualization.GuestProtect.Plan",
                    listOf("list", "get"),
                )
            }.getOrNull()
        } else {
            null
        }
        val plans = protectionData?.let {
            genericResources(
                it,
                "plans",
                "plan",
                "protection_plans",
                "guest_protects",
                "data",
                "list",
            )
        }.orEmpty()
        val schedules = protectionData?.let {
            genericResources(it, "schedule_policies", "schedules", "schedule_policy")
        }.orEmpty()
        val retentions = protectionData?.let {
            genericResources(it, "retention_policies", "retentions", "retention_policy")
        }.orEmpty()
        val logs = runCatching { virtualizationLogs() }.getOrDefault(emptyList())
        return VirtualMachineOverview(
            machines = machines,
            hosts = hosts,
            storages = storages,
            networks = networks,
            images = images,
            protectionPlans = plans,
            protectionSchedules = schedules,
            retentionPolicies = retentions,
            logs = logs,
        )
    }

    suspend fun controlVirtualMachine(id: String, action: String) {
        require(action in setOf("poweron", "poweroff", "shutdown", "reboot", "pause", "resume")) {
            "Unsupported virtual machine action"
        }
        val actionApi = preferred(
            "SYNO.Virtualization.Guest.Action",
            "SYNO.Virtualization.API.Guest.Action",
        )
        call(actionApi, action, mapOf("guest_id" to id, "id" to id))
    }

    suspend fun deleteVirtualMachine(id: String) {
        val guestApi = preferred("SYNO.Virtualization.Guest", "SYNO.Virtualization.API.Guest")
        call(guestApi, "delete", mapOf("guest_id" to id, "id" to id))
        verifyResourceMissing(guestApi, "guests", id)
    }

    suspend fun deleteVirtualMachineImage(id: String) {
        val imageApi = preferred(
            "SYNO.Virtualization.Guest.Image",
            "SYNO.Virtualization.API.Guest.Image",
        )
        call(imageApi, "delete", mapOf("image_id" to id, "id" to id))
        verifyResourceMissing(imageApi, "images", id)
    }

    suspend fun renameVirtualMachineNetwork(id: String, name: String) {
        require(name.isNotBlank()) { "Network name is required" }
        val networkApi = preferred(
            "SYNO.Virtualization.Network",
            "SYNO.Virtualization.API.Network",
        )
        // 内部、实验性契约：网页端在已核对的 VMM 版本使用 set。
        call(networkApi, "set", mapOf("network_id" to id, "id" to id, "name" to name.trim()))
        waitUntil {
            virtualMachineOverview().networks.any { it.id == id && it.name == name.trim() }
        }
    }

    suspend fun deleteVirtualMachineNetwork(id: String) {
        val networkApi = preferred(
            "SYNO.Virtualization.Network",
            "SYNO.Virtualization.API.Network",
        )
        // 内部、实验性契约：必须由界面确认并在完成后回读。
        call(networkApi, "delete", mapOf("network_id" to id, "id" to id))
        verifyResourceMissing(networkApi, "networks", id)
    }

    suspend fun virtualizationLogs(): List<LogEntry> {
        val data = call(
            "SYNO.Virtualization.Log",
            "list",
            mapOf(
                "offset" to "0",
                "limit" to "1000",
                "loglevel" to "",
                "filter_content" to "",
                "datefrom" to "0",
                "dateto" to "0",
                "sort_by" to "time",
                "sort_dir" to "DESC",
            ),
        )
        return parseVirtualizationLogs(data)
    }

    suspend fun chatConversations(): List<ChatConversation> {
        val data = firstSuccessful(
            "SYNO.Chat.Channel",
            listOf("list", "get"),
            mapOf("offset" to "0", "limit" to "500"),
        )
        return sequenceOf("channels", "channel_list", "items")
            .flatMap { data.elements(it).asSequence() }
            .distinctBy { (it as? JsonObject)?.string("channel_id") ?: it.toString() }
            .mapNotNull { element ->
                val item = element as? JsonObject ?: return@mapNotNull null
                val id = item.long("channel_id") ?: item.long("id") ?: return@mapNotNull null
                ChatConversation(
                    id = id,
                    title = item.string("name") ?: item.string("channel_name") ?: "",
                    kind = if ((item.string("type") ?: "").contains("direct", true)) {
                        ConversationKind.DIRECT
                    } else {
                        ConversationKind.GROUP
                    },
                    unreadCount = item.int("unread") ?: item.int("unread_count") ?: 0,
                    memberCount = item.int("member_count") ?: 0,
                    latestPreview = item.string("last_post") ?: item.string("last_message"),
                    latestAtEpochSeconds = item.long("last_update_at") ?: item.long("time"),
                )
            }
            .toList()
    }

    suspend fun nasSettings(): NasSettingsSnapshot {
        val systemJson = runCatching { firstSuccessful("SYNO.Core.System", listOf("info", "get")) }.getOrNull()
        val storageJson = runCatching { firstSuccessful("SYNO.Storage.CGI.Storage", listOf("load_info", "get")) }.getOrNull()
        val packageJson = runCatching {
            firstSuccessful(
                "SYNO.Core.Package",
                listOf("list"),
                mapOf(
                    "additional" to "[\"status\",\"description\",\"startable\",\"available_operation\"]"
                ),
            )
        }.getOrNull()
        val userJson = runCatching { firstSuccessful("SYNO.Core.User", listOf("list")) }.getOrNull()
        val groupJson = runCatching { firstSuccessful("SYNO.Core.Group", listOf("list")) }.getOrNull()
        val logJson = runCatching {
            firstSuccessful(
                preferred("SYNO.LogCenter.History", "SYNO.Core.SyslogClient.Log"),
                listOf("list", "get"),
                mapOf("offset" to "0", "limit" to "200"),
            )
        }.getOrNull()
        val connectionJson = runCatching {
            firstSuccessful("SYNO.Core.CurrentConnection", listOf("list", "get"))
        }.getOrNull()
        return NasSettingsSnapshot(
            system = systemJson?.let(::systemSummary),
            volumes = storageJson?.let(::capacityList).orEmpty(),
            pools = storageJson?.let { genericResources(it, "storagePools", "pools") }.orEmpty(),
            disks = storageJson?.let { genericResources(it, "disks") }.orEmpty(),
            packages = packageJson?.let(::packages).orEmpty(),
            scheduledTasks = runCatching {
                resourceList("SYNO.Core.TaskScheduler", listOf("list", "get"), "tasks")
            }.getOrDefault(emptyList()),
            accounts = userJson?.let(::accounts).orEmpty(),
            groups = groupJson?.let(::groups).orEmpty(),
            logs = logJson?.let(::logs).orEmpty(),
            connections = connectionJson?.let(::connections).orEmpty(),
            networkInterfaces = runCatching {
                resourceList("SYNO.Core.Network.Ethernet", listOf("list", "get"), "interfaces", "ifaces")
            }.getOrDefault(emptyList()),
            ddnsRecords = runCatching {
                resourceList("SYNO.Core.DDNS.Record", listOf("list", "get"), "records")
            }.getOrDefault(emptyList()),
            security = securityResources(),
        )
    }

    suspend fun disconnectConnection(id: String) {
        call("SYNO.Core.CurrentConnection", "disconnect", mapOf("id" to id))
    }

    suspend fun startPackage(id: String) {
        call("SYNO.Core.Package.Control", "start", mapOf("package" to id))
    }

    suspend fun stopPackage(id: String) {
        call("SYNO.Core.Package.Control", "stop", mapOf("package" to id))
    }

    private suspend fun securityResources(): List<ManagedResource> {
        val apis = listOf(
            "SYNO.Core.Security.AutoBlock" to ManagedResourceLabel.SECURITY_AUTO_BLOCK,
            "SYNO.Core.Security.DoS" to ManagedResourceLabel.SECURITY_DOS_PROTECTION,
            "SYNO.Core.Security.Firewall" to ManagedResourceLabel.SECURITY_FIREWALL,
        )
        return apis.mapNotNull { (apiName, label) ->
            if (!supports(apiName)) return@mapNotNull null
            val data = runCatching { firstSuccessful(apiName, listOf("get", "list")) }.getOrNull()
                ?: return@mapNotNull null
            val enabled = data.bool("enable") ?: data.bool("enabled")
            ManagedResource(
                id = apiName,
                name = "",
                detail = "",
                state = if (enabled == false) ResourceState.WARNING else ResourceState.HEALTHY,
                localizedLabel = label,
            )
        }
    }

    private suspend fun resourceList(
        apiName: String,
        methods: List<String>,
        vararg roots: String,
    ): List<ManagedResource> {
        if (!supports(apiName)) return emptyList()
        val data = firstSuccessful(apiName, methods)
        return genericResources(data, *roots)
    }

    private fun genericResources(data: JsonObject, vararg roots: String): List<ManagedResource> {
        val elements = roots.asSequence()
            .flatMap { data.elements(it).asSequence() }
            .ifEmpty { data.arrayValue("items").asSequence() }
        return elements.mapIndexedNotNull { index, element ->
            val item = element as? JsonObject ?: return@mapIndexedNotNull null
            val id = item.string("id")
                ?: item.string("uuid")
                ?: item.string("name")
                ?: item.long("id")?.toString()
                ?: "item-$index"
            val name = item.string("name")
                ?: item.string("title")
                ?: item.string("guest_name")
                ?: item.string("repo")
                ?: id
            val statusText = item.string("status") ?: item.string("state") ?: item.string("health")
            ManagedResource(
                id = id,
                name = name,
                detail = statusText ?: item.string("description") ?: "",
                state = state(statusText),
                metadata = item.entries
                    .filter { (_, value) -> value is JsonPrimitive }
                    .associate { (key, value) ->
                        key to value.jsonPrimitive.contentOrNull.orEmpty()
                    },
            )
        }.distinctBy(ManagedResource::id).toList()
    }

    private suspend fun firstSuccessful(
        apiName: String,
        methods: List<String>,
        parameters: Map<String, String> = emptyMap(),
    ): JsonObject {
        var last: Throwable? = null
        for (method in methods) {
            try {
                return call(apiName, method, parameters)
            } catch (error: DsmFailure) {
                last = error
                if (error.code !in setOf(102, 103)) throw error
            }
        }
        throw last ?: DsmFailure(
            null,
            "Feature unsupported",
            "Update the related package.",
            kind = DsmErrorKind.FEATURE_UNSUPPORTED,
        )
    }

    private suspend fun call(
        apiName: String,
        method: String,
        parameters: Map<String, String> = emptyMap(),
    ): JsonObject {
        val capability = capabilities[apiName]
            ?: throw DsmFailure(
                102,
                "Feature unsupported",
                "Update DSM or the related package.",
                kind = DsmErrorKind.FEATURE_UNSUPPORTED,
            )
        return api.call(profile, session, capability, method, parameters)
    }

    private fun preferredOrNull(vararg names: String): String? =
        names.firstOrNull(::supports)

    private suspend fun verifyExists(path: String) {
        val parent = path.substringBeforeLast('/', "")
        val name = path.substringAfterLast('/')
        val exists = listDirectory(if (parent.isBlank()) "/" else parent).items.any { it.name == name }
        if (!exists) {
            throw DsmFailure(
                null,
                "The NAS did not confirm the change",
                "Refresh the list and check the result.",
                kind = DsmErrorKind.CHANGE_NOT_CONFIRMED,
            )
        }
    }

    private suspend fun verifyResourceMissing(apiName: String, root: String, id: String) {
        waitUntil {
            resourceList(apiName, listOf("list", "get"), root).none { it.id == id }
        }
    }

    private suspend fun pathExists(path: String): Boolean {
        val parent = path.substringBeforeLast('/', "")
        val items = if (parent.isBlank()) {
            listShares().items
        } else {
            listDirectory(parent).items
        }
        return items.any { it.path == path }
    }

    private suspend fun waitUntil(condition: suspend () -> Boolean) {
        repeat(8) {
            if (condition()) return
            delay(500)
        }
        throw DsmFailure(
            null,
            "The NAS did not confirm the change",
            "Refresh the list and check the result.",
            kind = DsmErrorKind.CHANGE_NOT_CONFIRMED,
        )
    }

    private fun filePage(data: JsonObject, root: String): FilePage {
        val items = data.elements(root).mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            val additional = item.objectValue("additional")
            val time = additional?.objectValue("time")
            val permission = additional?.objectValue("perm")
            FileItem(
                path = item.string("path") ?: return@mapNotNull null,
                name = item.string("name") ?: item.string("path")?.substringAfterLast('/').orEmpty(),
                isDirectory = item.bool("isdir") ?: false,
                size = item.long("size") ?: additional?.long("size") ?: 0,
                modifiedAtEpochSeconds = time?.long("mtime") ?: item.long("mtime"),
                owner = additional?.objectValue("owner")?.string("user") ?: additional?.string("owner"),
                canRead = permission?.bool("read") ?: true,
                canWrite = permission?.bool("write") ?: false,
                canDelete = permission?.bool("delete") ?: false,
            )
        }
        return FilePage(
            items = items,
            total = data.int("total") ?: items.size,
            offset = data.int("offset") ?: 0,
        )
    }

    private fun systemSummary(data: JsonObject) = SystemSummary(
        serverName = data.string("server_name") ?: data.string("hostname") ?: "NAS",
        model = data.string("model") ?: "Synology NAS",
        serial = data.string("serial"),
        dsmVersion = data.string("firmware_ver") ?: data.string("version") ?: "DSM",
        uptimeSeconds = data.long("up_time") ?: data.long("uptime"),
        temperatureCelsius = data.string("temperature")?.toDoubleOrNull(),
    )

    private fun capacityList(data: JsonObject): List<CapacitySummary> =
        sequenceOf("volumes", "volume")
            .flatMap { data.elements(it).asSequence() }
            .mapNotNull { element ->
                val item = element as? JsonObject ?: return@mapNotNull null
                val total = item.long("size_total") ?: item.long("total_size") ?: return@mapNotNull null
                val used = item.long("size_used")
                    ?: item.long("used_size")
                    ?: (total - (item.long("size_free") ?: total))
                CapacitySummary(
                    id = item.string("id") ?: item.string("volume_path") ?: "volume",
                    name = item.string("display_name") ?: item.string("volume_path").orEmpty(),
                    totalBytes = total,
                    usedBytes = used,
                    status = state(item.string("status")),
                )
            }
            .toList()

    private fun packages(data: JsonObject): List<PackageInfo> =
        data.elements("packages").mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            val id = item.string("id") ?: item.string("package") ?: return@mapNotNull null
            val status = item.string("status")
            PackageInfo(
                id = id,
                name = item.string("name") ?: id,
                version = item.string("version") ?: "",
                status = state(status),
                description = item.string("description"),
                canStart = item.bool("startable") != false && state(status) == ResourceState.STOPPED,
                canStop = state(status) == ResourceState.RUNNING,
            )
        }

    private fun accounts(data: JsonObject): List<NasAccount> =
        data.elements("users").mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            NasAccount(
                id = item.long("uid") ?: item.long("id"),
                name = item.string("name") ?: item.string("username") ?: return@mapNotNull null,
                description = item.string("description"),
                email = item.string("email"),
                disabled = item.bool("disabled") ?: item.bool("is_disabled") ?: false,
            )
        }

    private fun groups(data: JsonObject): List<NasGroup> =
        data.elements("groups").mapNotNull { element ->
            val item = element as? JsonObject ?: return@mapNotNull null
            NasGroup(
                id = item.long("gid") ?: item.long("id"),
                name = item.string("name") ?: return@mapNotNull null,
                description = item.string("description"),
            )
        }

    private fun logs(data: JsonObject): List<LogEntry> =
        sequenceOf("logs", "items", "data")
            .flatMap { data.elements(it).asSequence() }
            .mapIndexedNotNull { index, element ->
                val item = element as? JsonObject ?: return@mapIndexedNotNull null
                LogEntry(
                    id = item.string("id") ?: "log-$index",
                    level = logLevel(item.string("level") ?: item.string("priority")),
                    timeEpochSeconds = item.long("time") ?: item.long("timestamp"),
                    user = item.string("user") ?: item.string("username") ?: "SYSTEM",
                    event = item.string("event") ?: item.string("message") ?: return@mapIndexedNotNull null,
                )
            }
            .toList()

    private fun connections(data: JsonObject): List<ActiveConnection> =
        sequenceOf("connections", "items")
            .flatMap { data.elements(it).asSequence() }
            .mapIndexedNotNull { index, element ->
                val item = element as? JsonObject ?: return@mapIndexedNotNull null
                ActiveConnection(
                    id = item.string("id") ?: item.string("connection_id") ?: "connection-$index",
                    user = item.string("user") ?: item.string("username") ?: "",
                    service = item.string("service") ?: item.string("type") ?: "DSM",
                    client = item.string("client") ?: item.string("ip") ?: "",
                    connectedAtEpochSeconds = item.long("time") ?: item.long("connected_at"),
                    isCurrent = item.bool("current") ?: false,
                )
            }
            .toList()

    private fun state(value: String?): ResourceState {
        val normalized = value?.lowercase().orEmpty()
        return when {
            normalized in setOf("running", "started", "online", "active", "downloading", "seeding") ->
                ResourceState.RUNNING
            normalized in setOf("stopped", "shutdown", "offline", "inactive", "finished") ->
                ResourceState.STOPPED
            normalized in setOf("paused", "suspended") -> ResourceState.PAUSED
            normalized in setOf("waiting", "pending", "creating", "starting", "stopping") ->
                ResourceState.WAITING
            normalized in setOf("healthy", "normal", "good") -> ResourceState.HEALTHY
            normalized.contains("warn") || normalized.contains("degrad") -> ResourceState.WARNING
            normalized.contains("error") || normalized.contains("fail") || normalized.contains("critical") ->
                ResourceState.ERROR
            else -> ResourceState.UNKNOWN
        }
    }

    private fun logLevel(value: String?): LogLevel = when (value?.lowercase()) {
        "info", "information", "0" -> LogLevel.INFO
        "warning", "warn", "1" -> LogLevel.WARNING
        "error", "err", "2" -> LogLevel.ERROR
        else -> LogLevel.UNKNOWN
    }

    private fun supports(apiName: String) = capabilities.containsKey(apiName)

    private fun preferred(vararg names: String): String =
        names.firstOrNull(::supports)
            ?: throw DsmFailure(
                102,
                "Feature unsupported",
                "Update DSM or the related package.",
                kind = DsmErrorKind.FEATURE_UNSUPPORTED,
            )

    private fun jsonStrings(values: List<String>): String =
        JsonArray(values.map(::JsonPrimitive)).toString()

    private fun join(parent: String, child: String): String =
        if (parent.endsWith('/')) "$parent$child" else "$parent/$child"
}

internal fun parseVirtualizationLogs(data: JsonObject): List<LogEntry> =
    sequenceOf("logs", "log", "events", "records", "entries", "items", "data", "list")
        .flatMap { data.elements(it).asSequence() }
        .distinctBy { it.toString() }
        .mapIndexedNotNull { index, element ->
            val item = element as? JsonObject ?: return@mapIndexedNotNull null
            val rawTime = item.long("time")
                ?: item.long("timestamp")
                ?: item.long("date")
                ?: item.long("event_time")
                ?: item.long("create_time")
                ?: item.long("created_at")
            val event = item.string("event")
                ?: item.string("message")
                ?: item.string("description")
                ?: item.string("msg")
                ?: item.string("content")
                ?: item.string("detail")
                ?: return@mapIndexedNotNull null
            LogEntry(
                id = item.string("id") ?: item.string("log_id") ?: "${rawTime ?: 0}:$index",
                level = parsedLogLevel(
                    item.string("level")
                        ?: item.string("severity")
                        ?: item.string("type")
                        ?: item.string("priority")
                ),
                timeEpochSeconds = rawTime?.let { if (it > 10_000_000_000) it / 1_000 else it },
                user = item.string("user")
                    ?: item.string("username")
                    ?: item.string("owner")
                    ?: item.string("account")
                    ?: item.string("user_name")
                    ?: "SYSTEM",
                event = event,
            )
        }
        .toList()

private fun parsedLogLevel(value: String?): LogLevel = when (value?.lowercase()) {
    "info", "information", "0" -> LogLevel.INFO
    "warning", "warn", "1" -> LogLevel.WARNING
    "error", "err", "2" -> LogLevel.ERROR
    else -> LogLevel.UNKNOWN
}

private fun JsonObject.elements(key: String): List<JsonElement> =
    (this[key] as? JsonArray)?.toList().orEmpty()

private fun JsonObject.bool(key: String): Boolean? =
    this[key]?.jsonPrimitive?.booleanOrNull
