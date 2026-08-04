package io.github.qwertyuiop1995.dsmnativeclient

import android.view.KeyEvent
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation
import io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.ui.WorkspaceShell
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class WorkspacePredictiveBackTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 系统返回完成时离开消息详情() {
        var navigateUpCount = 0
        rule.setContent {
            LanStashTheme {
                WorkspaceShell(
                    state = WorkspaceState(
                        profile = NasProfile(
                            "synthetic",
                            "Synthetic",
                            "https://nas.example.invalid",
                            "operator",
                        ),
                        selectedModule = Module.CHAT,
                        selectedConversation = ChatConversation(
                            id = "conversation-1",
                            title = "Synthetic conversation",
                            kind = ConversationKind.DIRECT,
                        ),
                    ),
                    onModuleSelected = {},
                    onRefresh = {},
                    onNavigateUp = { navigateUpCount += 1 },
                    onLogout = {},
                    onMessageShown = {},
                    content = {},
                )
            }
        }

        InstrumentationRegistry.getInstrumentation()
            .sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        rule.waitForIdle()

        assertEquals(1, navigateUpCount)
    }

    @Test
    fun 系统返回完成时按强类型文件路由返回一级() {
        var navigateUpCount = 0
        rule.setContent {
            LanStashTheme {
                WorkspaceShell(
                    state = WorkspaceState(
                        profile = NasProfile(
                            "synthetic-files",
                            "Synthetic",
                            "https://nas.example.invalid",
                            "operator",
                        ),
                        selectedModule = Module.FILES,
                        fileBrowser = FileBrowserState(
                            path = "/share/folder",
                            pathHistory = listOf(""),
                        ),
                    ),
                    onModuleSelected = {},
                    onRefresh = {},
                    onNavigateUp = { navigateUpCount += 1 },
                    onLogout = {},
                    onMessageShown = {},
                    content = {},
                )
            }
        }

        InstrumentationRegistry.getInstrumentation()
            .sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        rule.waitForIdle()

        assertEquals(1, navigateUpCount)
    }

    @Test
    fun 文件根目录选择态会消费系统返回而不是退出() {
        var navigateUpCount = 0
        rule.setContent {
            LanStashTheme {
                WorkspaceShell(
                    state = WorkspaceState(
                        profile = NasProfile(
                            "synthetic-file-selection",
                            "Synthetic",
                            "https://nas.example.invalid",
                            "operator",
                        ),
                        selectedModule = Module.FILES,
                        fileBrowser = FileBrowserState(
                            selectedPaths = setOf("/synthetic/item"),
                        ),
                    ),
                    onModuleSelected = {},
                    onRefresh = {},
                    onNavigateUp = { navigateUpCount += 1 },
                    onLogout = {},
                    onMessageShown = {},
                    content = {},
                )
            }
        }

        InstrumentationRegistry.getInstrumentation()
            .sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        rule.waitForIdle()

        assertEquals(1, navigateUpCount)
    }

    @Test
    fun 下载详情路由会消费系统返回并只导航一级() {
        var navigateUpCount = 0
        val task = DownloadTask(
            id = "synthetic-task",
            type = "bt",
            title = "Synthetic",
            status = ResourceState.RUNNING,
            size = 100,
            transferred = 50,
            downloadSpeed = 10,
            uploadSpeed = 1,
            destination = "/synthetic",
            error = null,
        )
        rule.setContent {
            LanStashTheme {
                WorkspaceShell(
                    state = WorkspaceState(
                        profile = NasProfile(
                            "synthetic-downloads",
                            "Synthetic",
                            "https://nas.example.invalid",
                            "operator",
                        ),
                        selectedModule = Module.DOWNLOADS,
                        downloads = Loadable.Ready(listOf(task)),
                        downloadDetailsTask = task,
                    ),
                    onModuleSelected = {},
                    onRefresh = {},
                    onNavigateUp = { navigateUpCount += 1 },
                    onLogout = {},
                    onMessageShown = {},
                    content = {},
                )
            }
        }

        InstrumentationRegistry.getInstrumentation()
            .sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        rule.waitForIdle()

        assertEquals(1, navigateUpCount)
    }

    @Test
    fun 容器镜像库路由会消费系统返回并只导航一级() {
        var navigateUpCount = 0
        rule.setContent {
            LanStashTheme {
                WorkspaceShell(
                    state = WorkspaceState(
                        profile = NasProfile(
                            "synthetic-container-registry",
                            "Synthetic",
                            "https://nas.example.invalid",
                            "operator",
                        ),
                        selectedModule = Module.CONTAINERS,
                        supportsContainerRegistry = true,
                        containerRegistryVisible = true,
                    ),
                    onModuleSelected = {},
                    onRefresh = {},
                    onNavigateUp = { navigateUpCount += 1 },
                    onLogout = {},
                    onMessageShown = {},
                    content = {},
                )
            }
        }

        InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        rule.waitForIdle()

        assertEquals(1, navigateUpCount)
    }
}
