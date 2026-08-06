package io.github.qwertyuiop1995.dsmnativeclient.domain

internal sealed interface WorkspaceRoute {
    data class ModuleRoot(val module: Module) : WorkspaceRoute

    data class FileDirectory(val depth: Int) : WorkspaceRoute {
        init {
            require(depth > 0) { "File directory depth must be positive" }
        }
    }

    data object FileSelection : WorkspaceRoute

    data object FilePreview : WorkspaceRoute

    data class PhotoFolder(val depth: Int) : WorkspaceRoute {
        init {
            require(depth > 0) { "Photo folder depth must be positive" }
        }
    }

    data object PhotoViewer : WorkspaceRoute

    data object ChatConversation : WorkspaceRoute

    data object DownloadTaskDetails : WorkspaceRoute

    data object ContainerRegistry : WorkspaceRoute

    data object VirtualMachineTasks : WorkspaceRoute

    data object VirtualMachineGuestDetails : WorkspaceRoute

    data object NasSettingsPerformance : WorkspaceRoute
}

internal data class WorkspaceRouteStack(
    val entries: List<WorkspaceRoute>,
) {
    init {
        require(entries.firstOrNull() is WorkspaceRoute.ModuleRoot) {
            "Workspace route stack must start with a module root"
        }
        require(entries.drop(1).none { it is WorkspaceRoute.ModuleRoot }) {
            "Workspace route stack must contain exactly one module root"
        }

        val rootModule = (entries.first() as WorkspaceRoute.ModuleRoot).module
        val nestedEntries = entries.drop(1)
        when (rootModule) {
            Module.FILES -> requireFileRoutes(nestedEntries)
            Module.PHOTOS -> requirePhotoRoutes(nestedEntries)
            Module.CHAT -> require(
                nestedEntries.isEmpty() || nestedEntries == listOf(WorkspaceRoute.ChatConversation),
            ) { "Chat supports at most one conversation route" }
            Module.DOWNLOADS -> require(
                nestedEntries.isEmpty() || nestedEntries == listOf(WorkspaceRoute.DownloadTaskDetails),
            ) { "Downloads supports at most one task details route" }
            Module.CONTAINERS -> require(
                nestedEntries.isEmpty() || nestedEntries == listOf(WorkspaceRoute.ContainerRegistry),
            ) { "Containers supports at most one registry route" }
            Module.VIRTUAL_MACHINES -> require(
                nestedEntries.isEmpty() || nestedEntries in listOf(
                    listOf(WorkspaceRoute.VirtualMachineTasks),
                    listOf(WorkspaceRoute.VirtualMachineGuestDetails),
                ),
            ) { "Virtual machines supports at most one nested route" }
            Module.NAS_SETTINGS -> require(
                nestedEntries.isEmpty() || nestedEntries == listOf(WorkspaceRoute.NasSettingsPerformance),
            ) { "NAS settings supports at most one performance route" }
            else -> require(nestedEntries.isEmpty()) { "Module does not support nested routes" }
        }
    }
}

internal fun deriveWorkspaceRouteStack(
    module: Module,
    fileHistoryDepth: Int,
    photoHistoryDepth: Int,
    hasConversation: Boolean,
    hasFileSelection: Boolean,
    hasFilePreview: Boolean = false,
    hasPhotoViewer: Boolean = false,
    hasDownloadTaskDetails: Boolean = false,
    hasContainerRegistry: Boolean = false,
    hasVirtualMachineTasks: Boolean = false,
    hasVirtualMachineGuestDetails: Boolean = false,
    hasNasSettingsPerformance: Boolean = false,
): WorkspaceRouteStack {
    require(fileHistoryDepth >= 0) { "File history depth cannot be negative" }
    require(photoHistoryDepth >= 0) { "Photo history depth cannot be negative" }
    require(!(hasVirtualMachineTasks && hasVirtualMachineGuestDetails)) {
        "Virtual machines cannot show tasks and guest details together"
    }

    val nestedEntries = when (module) {
        Module.FILES -> buildList<WorkspaceRoute> {
            addAll((1..fileHistoryDepth).map(WorkspaceRoute::FileDirectory))
            if (hasFileSelection) add(WorkspaceRoute.FileSelection)
            if (hasFilePreview) add(WorkspaceRoute.FilePreview)
        }
        Module.PHOTOS -> buildList<WorkspaceRoute> {
            addAll((1..photoHistoryDepth).map(WorkspaceRoute::PhotoFolder))
            if (hasPhotoViewer) add(WorkspaceRoute.PhotoViewer)
        }
        Module.CHAT -> if (hasConversation) listOf(WorkspaceRoute.ChatConversation) else emptyList()
        Module.DOWNLOADS -> if (hasDownloadTaskDetails) {
            listOf(WorkspaceRoute.DownloadTaskDetails)
        } else {
            emptyList()
        }
        Module.CONTAINERS -> if (hasContainerRegistry) {
            listOf(WorkspaceRoute.ContainerRegistry)
        } else {
            emptyList()
        }
        Module.VIRTUAL_MACHINES -> when {
            hasVirtualMachineGuestDetails -> listOf(WorkspaceRoute.VirtualMachineGuestDetails)
            hasVirtualMachineTasks -> listOf(WorkspaceRoute.VirtualMachineTasks)
            else -> emptyList()
        }
        Module.NAS_SETTINGS -> if (hasNasSettingsPerformance) {
            listOf(WorkspaceRoute.NasSettingsPerformance)
        } else {
            emptyList()
        }
        else -> emptyList()
    }
    return WorkspaceRouteStack(
        entries = listOf(WorkspaceRoute.ModuleRoot(module)) + nestedEntries,
    )
}

private fun requireFileRoutes(entries: List<WorkspaceRoute>) {
    val directoryEntries = entries.takeWhile { it is WorkspaceRoute.FileDirectory }
    requireSequentialDepth<WorkspaceRoute.FileDirectory>(directoryEntries) { it.depth }
    require(
        entries.drop(directoryEntries.size) in listOf(
            emptyList(),
            listOf(WorkspaceRoute.FileSelection),
            listOf(WorkspaceRoute.FilePreview),
            listOf(WorkspaceRoute.FileSelection, WorkspaceRoute.FilePreview),
        ),
    ) { "Files supports selection followed by preview after directory routes" }
}

private fun requirePhotoRoutes(entries: List<WorkspaceRoute>) {
    val folderEntries = entries.takeWhile { it is WorkspaceRoute.PhotoFolder }
    requireSequentialDepth<WorkspaceRoute.PhotoFolder>(folderEntries) { it.depth }
    require(
        entries.drop(folderEntries.size).let { trailing ->
            trailing.isEmpty() || trailing == listOf(WorkspaceRoute.PhotoViewer)
        },
    ) { "Photos supports at most one viewer route after folder routes" }
}

private inline fun <reified T : WorkspaceRoute> requireSequentialDepth(
    entries: List<WorkspaceRoute>,
    depth: (T) -> Int,
) {
    require(entries.all { it is T }) { "Nested route does not match its module root" }
    require(entries.map { depth(it as T) } == (1..entries.size).toList()) {
        "Nested route depth must be sequential starting at one"
    }
}
