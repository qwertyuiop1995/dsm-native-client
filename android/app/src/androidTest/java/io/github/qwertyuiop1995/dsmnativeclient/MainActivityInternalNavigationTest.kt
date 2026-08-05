package io.github.qwertyuiop1995.dsmnativeclient

import android.content.Intent
import android.net.Uri
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleAvailability
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationLifecycle
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationTarget
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferTask
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
        val request = InternalRouteRequest.OpenModule(Module.TRANSFERS)
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
        assertEquals(
            InternalRouteRequest.OpenModule(Module.TRANSFERS),
            trueIntent.internalRouteRequest(),
        )
    }

    @Test
    fun 外部模块入口在Workspace就绪后单次打开且消费数据() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/virtual-machines"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity -> workspace(activity).value = syntheticWorkspace() }
            waitForSelectedModule(scenario, Module.VIRTUAL_MACHINES)
            scenario.onActivity { activity -> assertEquals(null, activity.intent.data) }
        }
    }

    @Test
    fun Workspace未就绪时后到的外部入口替换旧目标并可跨Activity重建() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/photos"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                val supersededIntent = activity.intent
                dispatchNewIntent(
                    activity,
                    Intent(Intent.ACTION_VIEW, Uri.parse("lanstash://open/settings")),
                )
                assertEquals(null, supersededIntent.data)
                assertEquals("lanstash://open/settings", activity.intent.dataString)
            }
            scenario.recreate()
            scenario.onActivity { activity -> workspace(activity).value = syntheticWorkspace() }
            waitForSelectedModule(scenario, Module.SETTINGS)
            waitForNavigationIntentConsumed(scenario)
        }
    }

    @Test
    fun 已消费的外部入口在Activity重建后不会重放旧目标() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/photos"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity -> workspace(activity).value = syntheticWorkspace() }
            waitForSelectedModule(scenario, Module.PHOTOS)
            waitForNavigationIntentConsumed(scenario)
            scenario.onActivity { activity ->
                workspace(activity).value = workspace(activity).value!!.copy(
                    selectedModule = Module.FILES,
                )
            }

            scenario.recreate()

            scenario.onActivity { activity ->
                assertEquals(null, activity.intent.data)
                assertEquals(Module.FILES, workspace(activity).value?.selectedModule)
            }
        }
    }

    @Test
    fun 不可用模块外部入口沿用能力回退且不会反复消费() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/chat"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    availability = listOf(ModuleAvailability(Module.CHAT, isAvailable = false)),
                )
            }
            waitForNavigationIntentConsumed(scenario)
            scenario.onActivity { activity ->
                assertEquals(Module.FILES, workspace(activity).value?.selectedModule)
                assertEquals(null, activity.intent.data)
            }
        }
    }

    @Test
    fun Manifest只向系统声明固定无载荷模块入口主机() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("lanstash://open/files")).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            setPackage(context.packageName)
        }
        val resolved = context.packageManager.resolveActivity(intent, 0)

        assertEquals(MainActivity::class.java.name, resolved?.activityInfo?.name)
    }

    @Test
    fun 带载荷的外部入口会立即清除且不改变模块() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/photos?path=private"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace()
                assertEquals(null, activity.intent.data)
                assertEquals(Module.FILES, workspace(activity).value?.selectedModule)
            }
        }
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

    @Test
    fun Activity重建保留文本保存反馈和归档恢复证据且不制造新任务() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val file = FileItem(
            path = "/synthetic/readme.txt",
            name = "readme.txt",
            isDirectory = false,
            size = 7,
            canRead = true,
            canWrite = true,
        )
        val folder = FileItem(
            path = "/synthetic",
            name = "synthetic",
            isDirectory = true,
            canRead = true,
            canWrite = true,
        )
        val result = MutationResult(
            schemaVersion = 1,
            status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            operation = "textSave",
            submitted = true,
            requiresRefresh = true,
            counts = MutationResultCounts(succeeded = 0, failed = 0, unknown = 1),
        )
        val textState = FileStationMutationWorkspaceState(
            target = FileStationMutationTarget(
                profileId = "synthetic",
                module = Module.FILES,
                operation = FileStationMutationOperation.TEXT_SAVE,
                sourceBaselines = listOf(file),
                expectedContentSha256 = "0".repeat(64),
                expectedContentByteCount = 7,
            ),
            mutationResult = result,
        )
        val archiveTask = TransferTask(
            id = "synthetic-archive-task",
            title = "Archive",
            detail = "Synthetic",
            direction = TransferDirection.SERVER,
            state = TransferState.FAILED,
            fileServerMutation = FileServerMutationLifecycle(
                target = FileServerMutationTarget(
                    profileId = "synthetic",
                    module = Module.FILES,
                    operation = FileServerMutationOperation.COMPRESS,
                    sourceBaselines = listOf(file),
                    destinationFolderBaseline = folder,
                ),
                result = cancelledFileServerMutationResult(FileServerMutationOperation.COMPRESS),
                generation = 7,
            ),
        )

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    selectedModule = Module.FILES,
                    fileStationMutationState = textState,
                    transfers = listOf(archiveTask),
                )
            }

            scenario.recreate()

            scenario.onActivity { activity ->
                val rebuilt = workspace(activity).value!!
                assertEquals(textState, rebuilt.fileStationMutationState)
                assertEquals(listOf(archiveTask), rebuilt.transfers)
                assertFalse(rebuilt.fileStationMutationState.mutationInProgress)
                assertEquals(7L, rebuilt.transfers.single().fileServerMutation?.generation)
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

    private fun waitForNavigationIntentConsumed(scenario: ActivityScenario<MainActivity>) {
        val deadline = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < deadline) {
            var consumed = false
            scenario.onActivity { activity -> consumed = activity.intent.data == null }
            if (consumed) return
            Thread.sleep(20)
        }
        scenario.onActivity { activity -> assertEquals(null, activity.intent.data) }
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
