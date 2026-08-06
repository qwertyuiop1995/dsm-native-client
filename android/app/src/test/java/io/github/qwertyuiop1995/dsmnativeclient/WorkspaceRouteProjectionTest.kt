package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerRegistryImage
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoViewerState
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.WorkspaceRoute
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class WorkspaceRouteProjectionTest {
    @Test
    fun `不同文件选择只投影为同一个无载荷路由`() {
        val first = state(setOf("/synthetic/first-secret.txt")).workspaceRouteStack()
        val second = state(setOf("/different/private-item.bin")).workspaceRouteStack()

        assertEquals(first, second)
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.FILES),
                WorkspaceRoute.FileDirectory(depth = 1),
                WorkspaceRoute.FileSelection,
            ),
            first.entries,
        )
        val serialized = first.entries.toString()
        assertFalse(serialized.contains("synthetic"))
        assertFalse(serialized.contains("private-item"))
    }

    @Test
    fun `清除文件选择只移除选择路由并保留目录层级`() {
        val selected = state(setOf("/synthetic/item")).workspaceRouteStack().entries
        val cleared = state(emptySet()).workspaceRouteStack().entries

        assertEquals(selected.dropLast(1), cleared)
        assertEquals(WorkspaceRoute.FileSelection, selected.last())
    }

    @Test
    fun `预览只按当前模块和归属投影且路由不携带文件信息`() {
        val item = FileItem("/synthetic/private.txt", "private.txt", false)
        val fileEntries = state(emptySet()).copy(
            previewItem = item,
            previewOwner = PreviewOwner.FILES,
        ).workspaceRouteStack().entries
        val staleEntries = state(emptySet()).copy(
            selectedModule = Module.PHOTOS,
            previewItem = item,
            previewOwner = PreviewOwner.FILES,
        ).workspaceRouteStack().entries
        val photoEntries = state(emptySet()).copy(
            selectedModule = Module.PHOTOS,
            previewItem = item,
            previewOwner = PreviewOwner.PHOTOS,
            photoViewer = PhotoViewerState(listOf(item), 0),
        ).workspaceRouteStack().entries

        assertEquals(WorkspaceRoute.FilePreview, fileEntries.last())
        assertEquals(listOf(WorkspaceRoute.ModuleRoot(Module.PHOTOS)), staleEntries)
        assertEquals(WorkspaceRoute.PhotoViewer, photoEntries.last())
        assertFalse(fileEntries.toString().contains("private.txt"))
        assertFalse(photoEntries.toString().contains("private.txt"))
    }

    @Test
    fun `不同下载任务详情只投影同一个无载荷路由且跨模块不泄漏`() {
        val first = state(emptySet()).copy(
            selectedModule = Module.DOWNLOADS,
            downloadDetailsTask = downloadTask("private-task-a"),
        ).workspaceRouteStack()
        val second = state(emptySet()).copy(
            selectedModule = Module.DOWNLOADS,
            downloadDetailsTask = downloadTask("private-task-b"),
        ).workspaceRouteStack()
        val stale = state(emptySet()).copy(
            selectedModule = Module.FILES,
            downloadDetailsTask = downloadTask("private-task-a"),
        ).workspaceRouteStack()

        assertEquals(first, second)
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.DOWNLOADS), WorkspaceRoute.DownloadTaskDetails),
            first.entries,
        )
        assertEquals(WorkspaceRoute.ModuleRoot(Module.FILES), stale.entries.first())
        assertFalse(stale.entries.contains(WorkspaceRoute.DownloadTaskDetails))
        assertFalse(first.entries.toString().contains("private-task"))
    }

    @Test
    fun `下载任务刷新按稳定标识更新详情且任务消失时关闭详情`() {
        val selected = downloadTask("task-1", title = "Old")
        val refreshed = downloadTask("task-1", title = "Updated")
        val base = state(emptySet()).copy(
            selectedModule = Module.DOWNLOADS,
            downloads = Loadable.Ready(listOf(selected)),
            downloadDetailsTask = selected,
        )

        val updated = base.withDownloads(Loadable.Ready(listOf(refreshed)))
        val removed = updated.withDownloads(Loadable.Ready(emptyList()))
        val loading = base.withDownloads(Loadable.Loading)

        assertEquals("Updated", updated.downloadDetailsTask?.title)
        assertEquals(null, removed.downloadDetailsTask)
        assertEquals(selected, loading.downloadDetailsTask)
    }

    @Test
    fun `容器镜像库不同查询和镜像只投影同一无载荷路由且跨模块不泄漏`() {
        val image = containerRegistryImage("private-image")
        val first = state(emptySet()).copy(
            selectedModule = Module.CONTAINERS,
            containerRegistryVisible = true,
            containerRegistryQuery = "private-query-a",
            selectedContainerRegistryImage = image,
        ).workspaceRouteStack()
        val second = state(emptySet()).copy(
            selectedModule = Module.CONTAINERS,
            containerRegistryVisible = true,
            containerRegistryQuery = "different-query",
            selectedContainerRegistryImage = containerRegistryImage("other-image"),
        ).workspaceRouteStack()
        val stale = state(emptySet()).copy(
            selectedModule = Module.FILES,
            containerRegistryVisible = true,
            selectedContainerRegistryImage = image,
        ).workspaceRouteStack()

        assertEquals(first, second)
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.CONTAINERS), WorkspaceRoute.ContainerRegistry),
            first.entries,
        )
        assertFalse(stale.entries.contains(WorkspaceRoute.ContainerRegistry))
        assertFalse(first.entries.toString().contains("private"))
    }

    @Test
    fun `VMM任务和性能页只投影固定无载荷路由且跨模块不泄漏`() {
        val tasks = state(emptySet()).copy(
            selectedModule = Module.VIRTUAL_MACHINES,
            virtualMachineMutationState = VirtualMachineMutationWorkspaceState(
                selectedTab = VirtualMachineTab.TASKS,
            ),
        ).workspaceRouteStack()
        val performance = state(emptySet()).copy(
            selectedModule = Module.NAS_SETTINGS,
            nasPerformance = NasPerformanceWorkspaceState(
                selectedTab = NasSettingsTab.PERFORMANCE,
            ),
        ).workspaceRouteStack()
        val staleTasks = state(emptySet()).copy(
            selectedModule = Module.FILES,
            virtualMachineMutationState = VirtualMachineMutationWorkspaceState(
                selectedTab = VirtualMachineTab.TASKS,
            ),
        ).workspaceRouteStack()
        val stalePerformance = state(emptySet()).copy(
            selectedModule = Module.FILES,
            nasPerformance = NasPerformanceWorkspaceState(
                selectedTab = NasSettingsTab.PERFORMANCE,
            ),
        ).workspaceRouteStack()

        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.VIRTUAL_MACHINES), WorkspaceRoute.VirtualMachineTasks),
            tasks.entries,
        )
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.NAS_SETTINGS), WorkspaceRoute.NasSettingsPerformance),
            performance.entries,
        )
        val filesRoot = listOf(
            WorkspaceRoute.ModuleRoot(Module.FILES),
            WorkspaceRoute.FileDirectory(1),
        )
        assertEquals(filesRoot, staleTasks.entries)
        assertEquals(filesRoot, stalePerformance.entries)
    }

    @Test
    fun `不同VMM来宾只投影同一个详情路由且跨模块不泄漏`() {
        fun routes(module: Module, guestId: String) = state(emptySet()).copy(
            selectedModule = module,
            virtualMachineMutationState = VirtualMachineMutationWorkspaceState(
                guestDetailsTargetId = guestId,
            ),
        ).workspaceRouteStack()

        val first = routes(Module.VIRTUAL_MACHINES, "private-guest-a")
        val second = routes(Module.VIRTUAL_MACHINES, "private-guest-b")
        val stale = routes(Module.FILES, "private-guest-a")

        assertEquals(first, second)
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.VIRTUAL_MACHINES),
                WorkspaceRoute.VirtualMachineGuestDetails,
            ),
            first.entries,
        )
        assertFalse(stale.entries.contains(WorkspaceRoute.VirtualMachineGuestDetails))
        assertFalse(first.entries.toString().contains("private-guest"))
    }

    private fun state(selectedPaths: Set<String>) = WorkspaceState(
        profile = NasProfile(
            id = "synthetic",
            name = "Synthetic",
            address = "https://nas.example.invalid",
            username = "operator",
        ),
        selectedModule = Module.FILES,
        fileBrowser = FileBrowserState(
            path = "/synthetic/folder",
            pathHistory = listOf(""),
            selectedPaths = selectedPaths,
        ),
    )

    private fun downloadTask(id: String, title: String = "Synthetic") = DownloadTask(
        id = id,
        type = "bt",
        title = title,
        status = ResourceState.RUNNING,
        size = 100,
        transferred = 50,
        downloadSpeed = 10,
        uploadSpeed = 1,
        destination = "/synthetic",
        error = null,
    )

    private fun containerRegistryImage(name: String) = ContainerRegistryImage(
        name = name,
        registry = "registry.example.invalid",
        description = null,
        starCount = 0,
        isOfficial = false,
        isAutomated = false,
        isTrusted = false,
    )
}
