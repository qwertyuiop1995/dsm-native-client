package io.github.qwertyuiop1995.dsmnativeclient.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WorkspaceRouteTest {
    @Test
    fun `每个模块在没有嵌套状态时只包含模块根路由`() {
        Module.entries.forEach { module ->
            val stack = deriveWorkspaceRouteStack(
                module = module,
                fileHistoryDepth = 0,
                photoHistoryDepth = 0,
                hasConversation = false,
                hasFileSelection = false,
                hasFilePreview = false,
                hasPhotoViewer = false,
                hasDownloadTaskDetails = false,
                hasContainerRegistry = false,
            )

            assertEquals(listOf(WorkspaceRoute.ModuleRoot(module)), stack.entries)
        }
    }

    @Test
    fun `文件模块按零层一层和多层历史派生完整路由栈`() {
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.FILES)),
            derive(module = Module.FILES, fileDepth = 0).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.FILES),
                WorkspaceRoute.FileDirectory(depth = 1),
            ),
            derive(module = Module.FILES, fileDepth = 1).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.FILES),
                WorkspaceRoute.FileDirectory(depth = 1),
                WorkspaceRoute.FileDirectory(depth = 2),
                WorkspaceRoute.FileDirectory(depth = 3),
            ),
            derive(module = Module.FILES, fileDepth = 3).entries,
        )
    }

    @Test
    fun `文件多选路由不携带载荷且位于目录历史之后`() {
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.FILES),
                WorkspaceRoute.FileSelection,
            ),
            derive(module = Module.FILES, hasFileSelection = true).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.FILES),
                WorkspaceRoute.FileDirectory(depth = 1),
                WorkspaceRoute.FileDirectory(depth = 2),
                WorkspaceRoute.FileSelection,
            ),
            derive(
                module = Module.FILES,
                fileDepth = 2,
                hasFileSelection = true,
            ).entries,
        )
    }

    @Test
    fun `文件预览路由不携带载荷且位于目录和多选之后`() {
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.FILES),
                WorkspaceRoute.FilePreview,
            ),
            derive(module = Module.FILES, hasFilePreview = true).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.FILES),
                WorkspaceRoute.FileDirectory(depth = 1),
                WorkspaceRoute.FileDirectory(depth = 2),
                WorkspaceRoute.FileSelection,
                WorkspaceRoute.FilePreview,
            ),
            derive(
                module = Module.FILES,
                fileDepth = 2,
                hasFileSelection = true,
                hasFilePreview = true,
            ).entries,
        )
    }

    @Test
    fun `照片模块按零层一层和多层历史派生完整路由栈`() {
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.PHOTOS)),
            derive(module = Module.PHOTOS, photoDepth = 0).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                WorkspaceRoute.PhotoFolder(depth = 1),
            ),
            derive(module = Module.PHOTOS, photoDepth = 1).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                WorkspaceRoute.PhotoFolder(depth = 1),
                WorkspaceRoute.PhotoFolder(depth = 2),
                WorkspaceRoute.PhotoFolder(depth = 3),
            ),
            derive(module = Module.PHOTOS, photoDepth = 3).entries,
        )
    }

    @Test
    fun `照片查看器路由不携带载荷且位于文件夹历史之后`() {
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                WorkspaceRoute.PhotoViewer,
            ),
            derive(module = Module.PHOTOS, hasPhotoViewer = true).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                WorkspaceRoute.PhotoFolder(depth = 1),
                WorkspaceRoute.PhotoFolder(depth = 2),
                WorkspaceRoute.PhotoViewer,
            ),
            derive(
                module = Module.PHOTOS,
                photoDepth = 2,
                hasPhotoViewer = true,
            ).entries,
        )
    }

    @Test
    fun `消息模块只在存在当前会话时派生详情路由`() {
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.CHAT)),
            derive(module = Module.CHAT, hasConversation = false).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.CHAT),
                WorkspaceRoute.ChatConversation,
            ),
            derive(module = Module.CHAT, hasConversation = true).entries,
        )
    }

    @Test
    fun `下载模块只在存在当前任务详情时派生无载荷详情路由`() {
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.DOWNLOADS)),
            derive(module = Module.DOWNLOADS, hasDownloadTaskDetails = false).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.DOWNLOADS),
                WorkspaceRoute.DownloadTaskDetails,
            ),
            derive(module = Module.DOWNLOADS, hasDownloadTaskDetails = true).entries,
        )
    }

    @Test
    fun `容器模块只在显示Registry时派生无载荷详情路由`() {
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.CONTAINERS)),
            derive(module = Module.CONTAINERS, hasContainerRegistry = false).entries,
        )
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.CONTAINERS),
                WorkspaceRoute.ContainerRegistry,
            ),
            derive(module = Module.CONTAINERS, hasContainerRegistry = true).entries,
        )
    }

    @Test
    fun `非当前模块的嵌套状态不会泄露到路由栈`() {
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.PHOTOS)),
            derive(
                module = Module.PHOTOS,
                fileDepth = 3,
                photoDepth = 0,
                hasConversation = true,
                hasFileSelection = true,
                hasFilePreview = true,
                hasPhotoViewer = false,
                hasDownloadTaskDetails = true,
                hasContainerRegistry = true,
            ).entries,
        )
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.DOWNLOADS)),
            derive(
                module = Module.DOWNLOADS,
                fileDepth = 3,
                photoDepth = 2,
                hasConversation = true,
                hasFileSelection = true,
                hasFilePreview = true,
                hasPhotoViewer = true,
                hasDownloadTaskDetails = false,
            ).entries,
        )
        assertEquals(
            listOf(WorkspaceRoute.ModuleRoot(Module.CHAT)),
            derive(
                module = Module.CHAT,
                hasDownloadTaskDetails = true,
            ).entries,
        )
    }

    @Test
    fun `负数历史层级会被拒绝`() {
        assertThrows(IllegalArgumentException::class.java) {
            derive(module = Module.FILES, fileDepth = -1)
        }
        assertThrows(IllegalArgumentException::class.java) {
            derive(module = Module.PHOTOS, photoDepth = -1)
        }
    }

    @Test
    fun `路由栈拒绝缺少根项或与根模块不匹配的嵌套路由`() {
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(entries = listOf(WorkspaceRoute.FileDirectory(depth = 1)))
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                    WorkspaceRoute.FileDirectory(depth = 1),
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                    WorkspaceRoute.FilePreview,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.FILES),
                    WorkspaceRoute.PhotoViewer,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.CHAT),
                    WorkspaceRoute.FileSelection,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.FILES),
                    WorkspaceRoute.DownloadTaskDetails,
                ),
            )
        }
    }

    @Test
    fun `文件多选路由拒绝重复或出现在目录历史之前`() {
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.FILES),
                    WorkspaceRoute.FileSelection,
                    WorkspaceRoute.FileSelection,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.FILES),
                    WorkspaceRoute.FileSelection,
                    WorkspaceRoute.FileDirectory(depth = 1),
                ),
            )
        }
    }

    @Test
    fun `预览和查看器路由拒绝重复或出现在底层历史之前`() {
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.FILES),
                    WorkspaceRoute.FilePreview,
                    WorkspaceRoute.FilePreview,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.FILES),
                    WorkspaceRoute.FilePreview,
                    WorkspaceRoute.FileSelection,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                    WorkspaceRoute.PhotoViewer,
                    WorkspaceRoute.PhotoFolder(depth = 1),
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                    WorkspaceRoute.PhotoViewer,
                    WorkspaceRoute.PhotoViewer,
                ),
            )
        }
    }

    @Test
    fun `下载任务详情路由拒绝重复或挂到错误模块`() {
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.DOWNLOADS),
                    WorkspaceRoute.DownloadTaskDetails,
                    WorkspaceRoute.DownloadTaskDetails,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.PHOTOS),
                    WorkspaceRoute.DownloadTaskDetails,
                ),
            )
        }
    }

    @Test
    fun `容器Registry路由拒绝重复或挂到错误模块`() {
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.CONTAINERS),
                    WorkspaceRoute.ContainerRegistry,
                    WorkspaceRoute.ContainerRegistry,
                ),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.DOWNLOADS),
                    WorkspaceRoute.ContainerRegistry,
                ),
            )
        }
    }

    @Test
    fun `虚拟机来宾详情派生独立无载荷路由`() {
        assertEquals(
            listOf(
                WorkspaceRoute.ModuleRoot(Module.VIRTUAL_MACHINES),
                WorkspaceRoute.VirtualMachineGuestDetails,
            ),
            derive(
                module = Module.VIRTUAL_MACHINES,
                hasVirtualMachineGuestDetails = true,
            ).entries,
        )
    }

    @Test
    fun `虚拟机来宾详情与任务页互斥且拒绝挂到错误模块`() {
        assertThrows(IllegalArgumentException::class.java) {
            deriveWorkspaceRouteStack(
                module = Module.VIRTUAL_MACHINES,
                fileHistoryDepth = 0,
                photoHistoryDepth = 0,
                hasConversation = false,
                hasFileSelection = false,
                hasVirtualMachineTasks = true,
                hasVirtualMachineGuestDetails = true,
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            WorkspaceRouteStack(
                entries = listOf(
                    WorkspaceRoute.ModuleRoot(Module.DOWNLOADS),
                    WorkspaceRoute.VirtualMachineGuestDetails,
                ),
            )
        }
    }

    private fun derive(
        module: Module,
        fileDepth: Int = 0,
        photoDepth: Int = 0,
        hasConversation: Boolean = false,
        hasFileSelection: Boolean = false,
        hasFilePreview: Boolean = false,
        hasPhotoViewer: Boolean = false,
        hasDownloadTaskDetails: Boolean = false,
        hasContainerRegistry: Boolean = false,
        hasVirtualMachineGuestDetails: Boolean = false,
    ): WorkspaceRouteStack = deriveWorkspaceRouteStack(
        module = module,
        fileHistoryDepth = fileDepth,
        photoHistoryDepth = photoDepth,
        hasConversation = hasConversation,
        hasFileSelection = hasFileSelection,
        hasFilePreview = hasFilePreview,
        hasPhotoViewer = hasPhotoViewer,
        hasDownloadTaskDetails = hasDownloadTaskDetails,
        hasContainerRegistry = hasContainerRegistry,
        hasVirtualMachineGuestDetails = hasVirtualMachineGuestDetails,
    )
}
