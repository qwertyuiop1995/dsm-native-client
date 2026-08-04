package io.github.qwertyuiop1995.dsmnativeclient

import android.content.Intent
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.WorkspaceRoute
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MainActivityInternalNavigationTest {
    @Test
    fun workspace未就绪时重建Activity仍保留并完成传输入口() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, true)
        }
        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity(::assertPendingTransferIntent)
            scenario.recreate()
            scenario.onActivity { activity ->
                assertPendingTransferIntent(activity)
                workspace(activity).value = syntheticWorkspace()
            }

            waitForSelectedModule(scenario, Module.TRANSFERS)
            scenario.onActivity { activity ->
                assertFalse(
                    activity.intent.getBooleanExtra(
                        TransferNotifications.EXTRA_OPEN_TRANSFERS,
                        false,
                    ),
                )
            }
        }
    }

    @Test
    fun 重复或false输入不会制造额外待处理导航且消费后保持清空() {
        val request = InternalRouteRequest.OpenTransfers
        val pending = InternalNavigationState().receive(request)

        assertTrue(pending.pendingOpenTransfers)
        assertEquals(pending, pending.receive(request))
        assertEquals(pending, pending.receive(null))

        val consumed = pending.consume(request)
        assertFalse(consumed.pendingOpenTransfers)
        assertEquals(consumed, consumed.receive(null))
    }

    @Test
    fun 已打开Activity接收重复通知时使用强类型目标并保持幂等() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity -> workspace(activity).value = syntheticWorkspace() }

            repeat(2) {
                scenario.onActivity { activity ->
                    dispatchNewIntent(
                        activity,
                        Intent(activity, MainActivity::class.java).apply {
                            putExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, true)
                        },
                    )
                }
                waitForSelectedModule(scenario, Module.TRANSFERS)
            }

            scenario.onActivity { activity ->
                assertFalse(
                    activity.intent.getBooleanExtra(
                        TransferNotifications.EXTRA_OPEN_TRANSFERS,
                        false,
                    ),
                )
            }
        }
    }

    @Test
    fun 只有明确的内部Extra会解码为传输目标() {
        val empty = Intent()
        val falseIntent = Intent().putExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, false)
        val trueIntent = Intent().putExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, true)

        assertEquals(null, empty.internalRouteRequest())
        assertEquals(null, falseIntent.internalRouteRequest())
        assertEquals(InternalRouteRequest.OpenTransfers, trueIntent.internalRouteRequest())
    }

    @Test
    fun Activity重建后从领域状态重新派生不含路径的路由栈() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    selectedModule = Module.FILES,
                    fileBrowser = FileBrowserState(
                        path = "/share/private",
                        pathHistory = listOf("", "/share"),
                    ),
                )
            }
            scenario.recreate()
            scenario.onActivity { activity ->
                val routes = workspace(activity).value!!.workspaceRouteStack().entries
                assertEquals(
                    listOf(
                        WorkspaceRoute.ModuleRoot(Module.FILES),
                        WorkspaceRoute.FileDirectory(depth = 1),
                        WorkspaceRoute.FileDirectory(depth = 2),
                    ),
                    routes,
                )
                assertFalse(routes.toString().contains("/share"))
            }
        }
    }

    @Test
    fun Activity重建后下载详情从领域状态重新派生且路由不含任务标识() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val task = syntheticDownloadTask("private-task-id")
        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    selectedModule = Module.DOWNLOADS,
                    downloads = Loadable.Ready(listOf(task)),
                    downloadDetailsTask = task,
                )
            }

            scenario.recreate()

            scenario.onActivity { activity ->
                val routes = workspace(activity).value!!.workspaceRouteStack().entries
                assertEquals(
                    listOf(
                        WorkspaceRoute.ModuleRoot(Module.DOWNLOADS),
                        WorkspaceRoute.DownloadTaskDetails,
                    ),
                    routes,
                )
                assertFalse(routes.toString().contains(task.id))
            }
        }
    }

    @Test
    fun Activity重建后容器镜像库从领域状态重新派生且路由不含查询() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    selectedModule = Module.CONTAINERS,
                    supportsContainerRegistry = true,
                    containerRegistryVisible = true,
                    containerRegistryQuery = "private-query",
                )
            }

            scenario.recreate()

            scenario.onActivity { activity ->
                val routes = workspace(activity).value!!.workspaceRouteStack().entries
                assertEquals(
                    listOf(
                        WorkspaceRoute.ModuleRoot(Module.CONTAINERS),
                        WorkspaceRoute.ContainerRegistry,
                    ),
                    routes,
                )
                assertFalse(routes.toString().contains("private-query"))
            }
        }
    }

    private fun waitForSelectedModule(
        scenario: ActivityScenario<MainActivity>,
        expected: Module,
    ) {
        val deadline = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < deadline) {
            var selected: Module? = null
            scenario.onActivity { activity ->
                selected = workspace(activity).value?.selectedModule
            }
            if (selected == expected) return
            Thread.sleep(20)
        }
        scenario.onActivity { activity ->
            assertEquals(expected, workspace(activity).value?.selectedModule)
        }
    }

    private fun assertPendingTransferIntent(activity: MainActivity) {
        assertTrue(
            activity.intent.getBooleanExtra(
                TransferNotifications.EXTRA_OPEN_TRANSFERS,
                false,
            ),
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun workspace(activity: MainActivity): MutableStateFlow<WorkspaceState?> {
        val field = AppViewModel::class.java.getDeclaredField("_workspace").apply {
            isAccessible = true
        }
        return field.get(model(activity)) as MutableStateFlow<WorkspaceState?>
    }

    private fun model(activity: MainActivity): AppViewModel =
        ViewModelProvider(activity)[AppViewModel::class.java]

    private fun dispatchNewIntent(activity: MainActivity, intent: Intent) {
        MainActivity::class.java.getDeclaredMethod("onNewIntent", Intent::class.java).apply {
            isAccessible = true
        }.invoke(activity, intent)
    }

    private fun syntheticWorkspace() = WorkspaceState(
        profile = NasProfile(
            id = "synthetic",
            name = "Synthetic",
            address = "https://nas.example.invalid",
            username = "operator",
        ),
    )

    private fun syntheticDownloadTask(id: String) = DownloadTask(
        id = id,
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
}
