package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation
import io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.ContainerRegistryImage
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePreviewContent
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleAvailability
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoBrowseMode
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoViewerState
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.WorkspaceRoute
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.Job
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkspaceTypedNavigationTest {
    @Test
    fun 文件预览返回先关闭且保留选择和目录() {
        val model = model()
        val workspace = workspace(model)
        val item = syntheticTextItem()
        val browser = FileBrowserState(
            path = "/synthetic/folder",
            pathHistory = listOf(""),
            selectedPaths = setOf(item.path),
        )
        workspace.value = syntheticWorkspace(
            selectedModule = Module.FILES,
            fileBrowser = browser,
        ).copy(
            previewItem = item,
            preview = Loadable.Ready(FilePreviewContent.Text(item, "saved", truncated = false)),
            previewOwner = PreviewOwner.FILES,
        )

        assertEquals(WorkspaceRoute.FilePreview, workspace.value?.workspaceRouteStack()?.entries?.last())
        assertTrue(model.navigateUp())
        assertEquals(null, workspace.value?.previewItem)
        assertEquals(browser, workspace.value?.fileBrowser)
        assertEquals(WorkspaceRoute.FileSelection, workspace.value?.workspaceRouteStack()?.entries?.last())
    }

    @Test
    fun 未保存文本返回需确认且确认前不改变路由() {
        val model = model()
        val workspace = workspace(model)
        val item = syntheticTextItem()
        workspace.value = syntheticWorkspace(selectedModule = Module.FILES).copy(
            previewItem = item,
            preview = Loadable.Ready(FilePreviewContent.Text(item, "saved", truncated = false)),
            previewOwner = PreviewOwner.FILES,
            textPreviewDraft = "changed",
        )

        assertTrue(model.navigateUp())
        assertTrue(workspace.value?.previewDiscardConfirmationVisible == true)
        assertEquals(item, workspace.value?.previewItem)
        model.dismissPreviewDiscardConfirmation()
        assertEquals("changed", workspace.value?.textPreviewDraft)
        assertEquals(item, workspace.value?.previewItem)
        model.requestClosePreview()
        model.confirmDiscardTextPreview()
        assertEquals(null, workspace.value?.previewItem)
        assertEquals(Loadable.Idle, workspace.value?.preview)
    }

    @Test
    fun 未保存文本阻止模块切换且确认后才应用目标模块() {
        val model = model()
        val workspace = workspace(model)
        val item = syntheticTextItem()
        workspace.value = syntheticWorkspace(selectedModule = Module.FILES).copy(
            previewItem = item,
            preview = Loadable.Ready(FilePreviewContent.Text(item, "saved", truncated = false)),
            previewOwner = PreviewOwner.FILES,
            textPreviewDraft = "changed",
        )

        assertEquals(
            WorkspaceNavigationResult.DEFERRED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.PHOTOS)),
        )
        assertEquals(Module.FILES, workspace.value?.selectedModule)
        assertEquals(item, workspace.value?.previewItem)
        model.confirmDiscardTextPreview()
        assertEquals(Module.PHOTOS, workspace.value?.selectedModule)
        assertEquals(null, workspace.value?.previewItem)
    }

    @Test
    fun 再次打开同一文本不会清除未保存草稿() {
        val model = model()
        val workspace = workspace(model)
        val item = syntheticTextItem()
        workspace.value = syntheticWorkspace(selectedModule = Module.FILES).copy(
            previewItem = item,
            preview = Loadable.Ready(FilePreviewContent.Text(item, "saved", truncated = false)),
            previewOwner = PreviewOwner.FILES,
            textPreviewDraft = "changed",
        )

        model.openPreview(item)

        assertEquals("changed", workspace.value?.textPreviewDraft)
        assertEquals(item, workspace.value?.previewItem)
        assertFalse(workspace.value?.previewDiscardConfirmationVisible == true)
    }

    @Test
    fun 文本保存进行中模块切换和放弃确认均不会关闭预览() {
        val model = model()
        val workspace = workspace(model)
        val item = syntheticTextItem()
        val target = textSaveTarget(item)
        workspace.value = syntheticWorkspace(selectedModule = Module.FILES).copy(
            previewItem = item,
            preview = Loadable.Ready(FilePreviewContent.Text(item, "saved", truncated = false)),
            previewOwner = PreviewOwner.FILES,
            textPreviewDraft = "changed",
            isPerformingAction = true,
            fileStationMutationState = FileStationMutationWorkspaceState(
                target = target,
                mutationInProgress = true,
            ),
        )

        assertEquals(
            WorkspaceNavigationResult.REJECTED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.PHOTOS)),
        )
        assertFalse(workspace.value?.previewDiscardConfirmationVisible == true)
        model.confirmDiscardTextPreview()
        assertEquals(Module.FILES, workspace.value?.selectedModule)
        assertEquals(item, workspace.value?.previewItem)
    }

    @Test
    fun 文本保存进行中会阻止退出登录并保留任务证据() {
        val model = model()
        val workspace = workspace(model)
        val item = syntheticTextItem()
        val target = textSaveTarget(item)
        workspace.value = syntheticWorkspace(selectedModule = Module.FILES).copy(
            fileStationMutationState = FileStationMutationWorkspaceState(
                target = target,
                mutationInProgress = true,
            ),
        )

        model.logout()

        assertEquals(target, workspace.value?.fileStationMutationState?.target)
        assertTrue(workspace.value?.fileStationMutationState?.mutationInProgress == true)
    }

    private fun textSaveTarget(item: FileItem) = FileStationMutationTarget(
        profileId = "synthetic-profile",
        module = Module.FILES,
        operation = FileStationMutationOperation.TEXT_SAVE,
        sourceBaselines = listOf(item),
        expectedContentSha256 = sha256Hex("changed".encodeToByteArray()),
        expectedContentByteCount = 7,
    )

    @Test
    fun 照片查看器返回先关闭并保留文件夹历史() {
        val model = model()
        val workspace = workspace(model)
        val item = FileItem("/photos/synthetic.jpg", "synthetic.jpg", false)
        val browser = PhotoBrowserState(
            folderPath = "/photos/folder",
            pathHistory = listOf("/photos"),
        )
        workspace.value = syntheticWorkspace(
            selectedModule = Module.PHOTOS,
            photoBrowser = browser,
        ).copy(
            previewItem = item,
            previewOwner = PreviewOwner.PHOTOS,
            photoViewer = PhotoViewerState(listOf(item), 0),
        )

        assertEquals(WorkspaceRoute.PhotoViewer, workspace.value?.workspaceRouteStack()?.entries?.last())
        assertTrue(model.navigateUp())
        assertEquals(null, workspace.value?.previewItem)
        assertEquals(browser, workspace.value?.photoBrowser)
        assertEquals(WorkspaceRoute.PhotoFolder(1), workspace.value?.workspaceRouteStack()?.entries?.last())
    }
    @Test
    fun 文件根目录返回先清除选择且再次返回交给系统退出() {
        val model = model()
        val workspace = workspace(model)
        val selected = FileBrowserState(
            path = "",
            selectedPaths = setOf("/synthetic-a"),
        )
        workspace.value = syntheticWorkspace(
            selectedModule = Module.FILES,
            fileBrowser = selected,
        )

        assertTrue(model.navigateUp())
        assertEquals(selected.path, workspace.value?.fileBrowser?.path)
        assertEquals(selected.pathHistory, workspace.value?.fileBrowser?.pathHistory)
        assertTrue(workspace.value?.fileBrowser?.selectedPaths.isNullOrEmpty())
        assertFalse(model.navigateUp())
    }

    @Test
    fun 文件子目录返回先清除选择再逐层返回且与顶部关闭等价() {
        val selected = FileBrowserState(
            path = "/synthetic/folder",
            pathHistory = listOf(""),
            selectedPaths = setOf("/synthetic/folder/item"),
        )
        val backModel = model()
        val backWorkspace = workspace(backModel)
        backWorkspace.value = syntheticWorkspace(
            selectedModule = Module.FILES,
            fileBrowser = selected,
        )
        val closeModel = model()
        val closeWorkspace = workspace(closeModel)
        closeWorkspace.value = syntheticWorkspace(
            selectedModule = Module.FILES,
            fileBrowser = selected,
        )

        assertTrue(backModel.navigateUp())
        closeModel.clearFileSelection()
        assertEquals(closeWorkspace.value?.fileBrowser, backWorkspace.value?.fileBrowser)
        assertEquals(selected.path, backWorkspace.value?.fileBrowser?.path)
        assertEquals(selected.pathHistory, backWorkspace.value?.fileBrowser?.pathHistory)

        assertTrue(backModel.navigateUp())
        assertEquals("", backWorkspace.value?.fileBrowser?.path)
        assertTrue(backWorkspace.value?.fileBrowser?.pathHistory.isNullOrEmpty())
        assertFalse(backModel.navigateUp())
    }

    @Test
    fun 文件和照片路由按领域历史逐层返回() {
        val model = model()
        val workspace = workspace(model)
        workspace.value = syntheticWorkspace(
            selectedModule = Module.FILES,
            fileBrowser = FileBrowserState(
                path = "/share/second",
                pathHistory = listOf("", "/share"),
            ),
            photoBrowser = PhotoBrowserState(
                folderPath = "/photos/second",
                pathHistory = listOf("/photos", "/photos/first"),
            ),
        )

        assertTrue(model.navigateUp())
        assertEquals(listOf(""), workspace.value?.fileBrowser?.pathHistory)
        assertTrue(model.navigateUp())
        assertTrue(workspace.value?.fileBrowser?.pathHistory.isNullOrEmpty())
        assertFalse(model.navigateUp())

        assertEquals(
            WorkspaceNavigationResult.APPLIED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.PHOTOS)),
        )
        assertTrue(model.navigateUp())
        assertEquals(listOf("/photos"), workspace.value?.photoBrowser?.pathHistory)
        assertTrue(model.navigateUp())
        assertTrue(workspace.value?.photoBrowser?.pathHistory.isNullOrEmpty())
        assertFalse(model.navigateUp())
    }

    @Test
    fun 消息详情只占一层且模块根不形成顶层返回历史() {
        val model = model()
        val workspace = workspace(model)
        workspace.value = syntheticWorkspace(
            selectedModule = Module.CHAT,
            selectedConversation = ChatConversation(
                id = "synthetic-conversation",
                title = "Synthetic conversation",
                kind = ConversationKind.DIRECT,
            ),
        )

        assertTrue(model.navigateUp())
        assertEquals(null, workspace.value?.selectedConversation)
        assertFalse(model.navigateUp())
        assertEquals(
            WorkspaceNavigationResult.APPLIED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.DOWNLOADS)),
        )
        assertFalse(model.navigateUp())
    }

    @Test
    fun 下载任务详情返回只关闭详情并保留任务列表() {
        val model = model()
        val workspace = workspace(model)
        val task = syntheticDownloadTask("task-1")
        workspace.value = syntheticWorkspace(selectedModule = Module.DOWNLOADS).copy(
            downloads = Loadable.Ready(listOf(task)),
        )

        model.openDownloadTaskDetails(task)

        assertEquals(task, workspace.value?.downloadDetailsTask)
        assertEquals(
            WorkspaceRoute.DownloadTaskDetails,
            workspace.value?.workspaceRouteStack()?.entries?.last(),
        )
        assertTrue(model.navigateUp())
        assertEquals(null, workspace.value?.downloadDetailsTask)
        assertEquals(Loadable.Ready(listOf(task)), workspace.value?.downloads)
        assertFalse(model.navigateUp())
    }

    @Test
    fun 下载详情切换模块后清除且返回下载不会复活旧详情() {
        val model = model()
        val workspace = workspace(model)
        val task = syntheticDownloadTask("task-private")
        workspace.value = syntheticWorkspace(selectedModule = Module.DOWNLOADS).copy(
            downloads = Loadable.Ready(listOf(task)),
        )
        model.openDownloadTaskDetails(task)

        assertEquals(
            WorkspaceNavigationResult.APPLIED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.FILES)),
        )
        assertEquals(null, workspace.value?.downloadDetailsTask)
        assertEquals(
            WorkspaceNavigationResult.APPLIED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.DOWNLOADS)),
        )
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.DOWNLOADS)),
            workspace.value?.workspaceRouteStack()?.entries,
        )
    }

    @Test
    fun 下载详情拒绝不在当前列表的任务并使用列表中的最新对象() {
        val model = model()
        val workspace = workspace(model)
        val current = syntheticDownloadTask("task-1", title = "Current")
        val stale = syntheticDownloadTask("task-1", title = "Stale")
        workspace.value = syntheticWorkspace(selectedModule = Module.DOWNLOADS).copy(
            downloads = Loadable.Ready(listOf(current)),
        )

        model.openDownloadTaskDetails(stale)
        assertEquals(current, workspace.value?.downloadDetailsTask)

        model.openDownloadTaskDetails(syntheticDownloadTask("missing"))
        assertEquals(null, workspace.value?.downloadDetailsTask)
    }

    @Test
    fun 容器镜像库返回只关闭详情并保留查询结果() {
        val model = model()
        val workspace = workspace(model)
        val image = syntheticContainerRegistryImage()
        workspace.value = syntheticWorkspace(selectedModule = Module.CONTAINERS).copy(
            supportsContainerRegistry = true,
            containerRegistryQuery = "synthetic-query",
            containerRegistryResults = Loadable.Ready(listOf(image)),
        )

        model.showContainerRegistry()

        assertEquals(WorkspaceRoute.ContainerRegistry, workspace.value?.workspaceRouteStack()?.entries?.last())
        assertTrue(model.navigateUp())
        assertFalse(workspace.value?.containerRegistryVisible == true)
        assertEquals("synthetic-query", workspace.value?.containerRegistryQuery)
        assertEquals(Loadable.Ready(listOf(image)), workspace.value?.containerRegistryResults)
        assertFalse(model.navigateUp())
    }

    @Test
    fun 容器镜像库离开模块后清除且返回不会复活旧详情() {
        val model = model()
        val workspace = workspace(model)
        workspace.value = syntheticWorkspace(selectedModule = Module.CONTAINERS).copy(
            supportsContainerRegistry = true,
        )
        model.showContainerRegistry()

        assertEquals(
            WorkspaceNavigationResult.APPLIED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.FILES)),
        )
        assertFalse(workspace.value?.containerRegistryVisible == true)
        assertEquals(
            WorkspaceNavigationResult.APPLIED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.CONTAINERS)),
        )
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.CONTAINERS)),
            workspace.value?.workspaceRouteStack()?.entries,
        )
    }

    @Test
    fun 容器镜像库仅在当前容器模块且能力可用时打开() {
        val model = model()
        val workspace = workspace(model)
        workspace.value = syntheticWorkspace(selectedModule = Module.FILES).copy(
            supportsContainerRegistry = true,
        )
        model.showContainerRegistry()
        assertFalse(workspace.value?.containerRegistryVisible == true)

        workspace.value = syntheticWorkspace(selectedModule = Module.CONTAINERS).copy(
            supportsContainerRegistry = false,
        )
        model.showContainerRegistry()
        assertFalse(workspace.value?.containerRegistryVisible == true)
    }

    @Test
    fun 固定镜像库导航入口返回精确结果并复用既有返回栈() {
        val model = model()
        val workspace = workspace(model)

        assertEquals(WorkspaceNavigationResult.DEFERRED, model.navigateToContainerRegistry())

        workspace.value = syntheticWorkspace(selectedModule = Module.FILES).copy(
            supportsContainerRegistry = false,
        )
        assertEquals(WorkspaceNavigationResult.REJECTED, model.navigateToContainerRegistry())
        assertEquals(Module.FILES, workspace.value?.selectedModule)
        assertFalse(workspace.value?.containerRegistryVisible == true)

        workspace.value = workspace.value?.copy(supportsContainerRegistry = true)
        assertEquals(WorkspaceNavigationResult.APPLIED, model.navigateToContainerRegistry())
        assertEquals(Module.CONTAINERS, workspace.value?.selectedModule)
        assertEquals(
            WorkspaceRoute.ContainerRegistry,
            workspace.value?.workspaceRouteStack()?.entries?.last(),
        )
        assertEquals(WorkspaceNavigationResult.ALREADY_SELECTED, model.navigateToContainerRegistry())
        assertTrue(model.navigateUp())
        assertFalse(workspace.value?.containerRegistryVisible == true)
    }

    @Test
    fun 容器镜像库编辑查询会清除旧结果和镜像选择并允许重新搜索() {
        val model = model()
        val workspace = workspace(model)
        val image = syntheticContainerRegistryImage()
        workspace.value = syntheticWorkspace(selectedModule = Module.CONTAINERS).copy(
            supportsContainerRegistry = true,
            containerRegistryVisible = true,
            containerRegistryQuery = "old-query",
            containerRegistryResults = Loadable.Loading,
            selectedContainerRegistryImage = image,
            containerRegistryTags = Loadable.Ready(listOf("old-tag")),
        )

        model.updateContainerRegistryQuery("new-query")

        assertEquals("new-query", workspace.value?.containerRegistryQuery)
        assertEquals(Loadable.Idle, workspace.value?.containerRegistryResults)
        assertEquals(null, workspace.value?.selectedContainerRegistryImage)
        assertEquals(Loadable.Idle, workspace.value?.containerRegistryTags)
    }

    @Test
    fun 容器镜像库关闭或离开模块会收敛失效的搜索加载态() {
        val model = model()
        val workspace = workspace(model)
        workspace.value = syntheticWorkspace(selectedModule = Module.CONTAINERS).copy(
            supportsContainerRegistry = true,
            containerRegistryVisible = true,
            containerRegistryResults = Loadable.Loading,
        )

        model.closeContainerRegistry()
        assertEquals(Loadable.Idle, workspace.value?.containerRegistryResults)

        workspace.value = workspace.value?.copy(
            containerRegistryVisible = true,
            containerRegistryResults = Loadable.Loading,
        )
        assertEquals(
            WorkspaceNavigationResult.APPLIED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.FILES)),
        )
        assertEquals(Loadable.Idle, workspace.value?.containerRegistryResults)
        assertEquals(
            WorkspaceNavigationResult.APPLIED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.CONTAINERS)),
        )
        model.showContainerRegistry()
        assertFalse(workspace.value?.containerRegistryResults is Loadable.Loading)
    }

    @Test
    fun 不可用模块拒绝导航且不会改变当前根路由() {
        val model = model()
        val workspace = workspace(model)
        workspace.value = syntheticWorkspace(
            selectedModule = Module.FILES,
            availability = listOf(
                ModuleAvailability(Module.FILES, isAvailable = true),
                ModuleAvailability(Module.CHAT, isAvailable = false),
            ),
        )

        assertEquals(
            WorkspaceNavigationResult.REJECTED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.CHAT)),
        )
        assertEquals(Module.FILES, workspace.value?.selectedModule)
        assertTrue(workspace.value?.message?.isNotBlank() == true)
        assertEquals(
            WorkspaceNavigationResult.ALREADY_SELECTED,
            model.navigateTo(WorkspaceRoute.ModuleRoot(Module.FILES)),
        )
    }

    @Test
    fun 时间轴忽略隐藏文件夹历史且切回文件夹后仍可返回() {
        val model = model()
        val workspace = workspace(model)
        workspace.value = syntheticWorkspace(
            selectedModule = Module.PHOTOS,
            photoBrowser = PhotoBrowserState(
                mode = PhotoBrowseMode.TIMELINE,
                folderPath = "/photos/second",
                pathHistory = listOf("/photos", "/photos/first"),
            ),
        )

        assertEquals(1, workspace.value?.workspaceRouteStack()?.entries?.size)
        assertFalse(model.navigateUp())
        assertEquals(2, workspace.value?.photoBrowser?.pathHistory?.size)

        workspace.value = workspace.value?.copy(
            photoBrowser = workspace.value!!.photoBrowser.copy(mode = PhotoBrowseMode.FOLDERS),
        )
        assertTrue(model.navigateUp())
        assertEquals(listOf("/photos"), workspace.value?.photoBrowser?.pathHistory)
    }

    @Test
    fun 缺少具体原因的不可用模块仍提供通用恢复提示() {
        val model = model()
        val workspace = workspace(model)
        workspace.value = syntheticWorkspace(
            selectedModule = Module.TRANSFERS,
            availability = listOf(
                ModuleAvailability(Module.TRANSFERS, isAvailable = true),
                ModuleAvailability(Module.FILES, isAvailable = false),
                ModuleAvailability(Module.PHOTOS, isAvailable = false),
                ModuleAvailability(Module.NAS_SETTINGS, isAvailable = false),
            ),
        )

        listOf(Module.FILES, Module.PHOTOS, Module.NAS_SETTINGS).forEach { unavailable ->
            assertEquals(
                WorkspaceNavigationResult.REJECTED,
                model.navigateTo(WorkspaceRoute.ModuleRoot(unavailable)),
            )
            assertEquals(Module.TRANSFERS, workspace.value?.selectedModule)
            assertTrue(workspace.value?.message?.isNotBlank() == true)
        }
    }

    private fun model(): AppViewModel =
        AppViewModel(ApplicationProvider.getApplicationContext<Application>())

    @Suppress("UNCHECKED_CAST")
    private fun workspace(model: AppViewModel): MutableStateFlow<WorkspaceState?> {
        val field = AppViewModel::class.java.getDeclaredField("_workspace").apply {
            isAccessible = true
        }
        return field.get(model) as MutableStateFlow<WorkspaceState?>
    }

    private fun syntheticWorkspace(
        selectedModule: Module,
        fileBrowser: FileBrowserState = FileBrowserState(),
        photoBrowser: PhotoBrowserState = PhotoBrowserState(),
        selectedConversation: ChatConversation? = null,
        availability: List<ModuleAvailability> = emptyList(),
    ) = WorkspaceState(
        profile = NasProfile(
            id = "synthetic",
            name = "Synthetic",
            address = "https://nas.example.invalid",
            username = "operator",
        ),
        selectedModule = selectedModule,
        fileBrowser = fileBrowser,
        photoBrowser = photoBrowser,
        selectedConversation = selectedConversation,
        availability = availability,
    )

    private fun syntheticTextItem() = FileItem(
        path = "/synthetic/folder/note.txt",
        name = "note.txt",
        isDirectory = false,
        mimeType = "text/plain",
        canWrite = true,
    )

    private fun syntheticDownloadTask(id: String, title: String = "Synthetic") = DownloadTask(
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

    private fun syntheticContainerRegistryImage() = ContainerRegistryImage(
        name = "synthetic/image",
        registry = "registry.example.invalid",
        description = null,
        starCount = 0,
        isOfficial = false,
        isAutomated = false,
        isTrusted = false,
    )
}
