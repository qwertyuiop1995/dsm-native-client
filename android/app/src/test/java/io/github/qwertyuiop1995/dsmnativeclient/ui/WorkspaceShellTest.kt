package io.github.qwertyuiop1995.dsmnativeclient.ui

import androidx.activity.BackEventCompat
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.WorkspaceRouteStack
import io.github.qwertyuiop1995.dsmnativeclient.domain.deriveWorkspaceRouteStack
import org.junit.Assert.assertEquals
import org.junit.Test

class WorkspaceShellTest {
    @Test
    fun `手机抽屉打开时返回键优先关闭抽屉`() {
        val action = workspaceBackAction(
            isExpanded = false,
            isDrawerOpen = true,
            routeStack = stack(Module.FILES, fileDepth = 1),
        )

        assertEquals(WorkspaceBackAction.CLOSE_DRAWER, action)
    }

    @Test
    fun `文件目录存在历史时返回上级目录`() {
        val action = workspaceBackAction(
            isExpanded = false,
            isDrawerOpen = false,
            routeStack = stack(Module.FILES, fileDepth = 1),
        )

        assertEquals(WorkspaceBackAction.NAVIGATE_UP, action)
    }

    @Test
    fun `文件选择态即使在根目录也由工作区先消费返回`() {
        val action = workspaceBackAction(
            isExpanded = true,
            isDrawerOpen = false,
            routeStack = stack(Module.FILES, hasFileSelection = true),
        )

        assertEquals(WorkspaceBackAction.NAVIGATE_UP, action)
        assertEquals(
            WorkspaceBackAction.EXIT,
            workspaceBackAction(
                isExpanded = true,
                isDrawerOpen = false,
                routeStack = stack(Module.FILES),
            ),
        )
    }

    @Test
    fun `文件子目录清除选择后仍由工作区返回目录`() {
        assertEquals(
            WorkspaceBackAction.NAVIGATE_UP,
            workspaceBackAction(
                isExpanded = true,
                isDrawerOpen = false,
                routeStack = stack(Module.FILES, fileDepth = 1, hasFileSelection = true),
            ),
        )
        assertEquals(
            WorkspaceBackAction.NAVIGATE_UP,
            workspaceBackAction(
                isExpanded = true,
                isDrawerOpen = false,
                routeStack = stack(Module.FILES, fileDepth = 1),
            ),
        )
    }

    @Test
    fun `照片目录存在历史时返回上级目录`() {
        val action = workspaceBackAction(
            isExpanded = false,
            isDrawerOpen = false,
            routeStack = stack(Module.PHOTOS, photoDepth = 1),
        )

        assertEquals(WorkspaceBackAction.NAVIGATE_UP, action)
    }

    @Test
    fun `消息详情存在时返回会话列表`() {
        val action = workspaceBackAction(
            isExpanded = false,
            isDrawerOpen = false,
            routeStack = stack(Module.CHAT, hasConversation = true),
        )

        assertEquals(WorkspaceBackAction.NAVIGATE_UP, action)
    }

    @Test
    fun `下载任务详情存在时返回任务列表`() {
        val action = workspaceBackAction(
            isExpanded = false,
            isDrawerOpen = false,
            routeStack = stack(Module.DOWNLOADS, hasDownloadTaskDetails = true),
        )

        assertEquals(WorkspaceBackAction.NAVIGATE_UP, action)
    }

    @Test
    fun `其他模块不消费目录历史`() {
        val action = workspaceBackAction(
            isExpanded = false,
            isDrawerOpen = false,
            routeStack = stack(Module.DOWNLOADS, fileDepth = 3),
        )

        assertEquals(WorkspaceBackAction.EXIT, action)
    }

    @Test
    fun `根目录返回交给系统退出`() {
        val action = workspaceBackAction(
            isExpanded = true,
            isDrawerOpen = false,
            routeStack = stack(Module.FILES),
        )

        assertEquals(WorkspaceBackAction.EXIT, action)
    }

    @Test
    fun `预测返回进度限制范围并尊重关闭系统动画`() {
        assertEquals(0f, predictiveBackVisualProgress(-0.2f, animationsEnabled = true))
        assertEquals(0.4f, predictiveBackVisualProgress(0.4f, animationsEnabled = true))
        assertEquals(1f, predictiveBackVisualProgress(1.4f, animationsEnabled = true))
        assertEquals(0f, predictiveBackVisualProgress(0.8f, animationsEnabled = false))
    }

    @Test
    fun `预测返回位移方向跟随系统手势边缘`() {
        assertEquals(1f, predictiveBackDirection(BackEventCompat.EDGE_LEFT))
        assertEquals(-1f, predictiveBackDirection(BackEventCompat.EDGE_RIGHT))
    }

    private fun stack(
        module: Module,
        fileDepth: Int = 0,
        hasFileSelection: Boolean = false,
        photoDepth: Int = 0,
        hasConversation: Boolean = false,
        hasFilePreview: Boolean = false,
        hasPhotoViewer: Boolean = false,
        hasDownloadTaskDetails: Boolean = false,
    ): WorkspaceRouteStack = deriveWorkspaceRouteStack(
        module = module,
        fileHistoryDepth = fileDepth,
        hasFileSelection = hasFileSelection,
        photoHistoryDepth = photoDepth,
        hasConversation = hasConversation,
        hasFilePreview = hasFilePreview,
        hasPhotoViewer = hasPhotoViewer,
        hasDownloadTaskDetails = hasDownloadTaskDetails,
    )
}
