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
        val request = InternalRouteRequest.OPEN_TRANSFERS
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
            InternalRouteRequest.OPEN_TRANSFERS,
            trueIntent.internalRouteRequest(),
        )
    }

    @Test
    fun 外部View不能用内部通知Extra绕过URI白名单() {
        val invalid = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/files?path=/private"),
        ).putExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, true)
        val valid = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/containers/registry"),
        ).putExtra(TransferNotifications.EXTRA_OPEN_TRANSFERS, true)
        val tasks = Intent(Intent.ACTION_VIEW, Uri.parse("lanstash://open/virtual-machines/tasks"))
        val performance = Intent(Intent.ACTION_VIEW, Uri.parse("lanstash://open/nas-settings/performance"))

        assertEquals(null, invalid.internalRouteRequest())
        assertEquals(InternalRouteRequest.OPEN_CONTAINER_REGISTRY, valid.internalRouteRequest())
        assertEquals(InternalRouteRequest.OPEN_VIRTUAL_MACHINE_TASKS, tasks.internalRouteRequest())
        assertEquals(InternalRouteRequest.OPEN_NAS_SETTINGS_PERFORMANCE, performance.internalRouteRequest())
    }

    @Test
    fun 第81批保存的模块枚举和传输布尔值仍可恢复() {
        val moduleState = android.os.Bundle().apply {
            putString("pending_module", Module.PHOTOS.name)
        }
        val transferState = android.os.Bundle().apply {
            putBoolean("pending_open_transfers", true)
            putString("pending_module", Module.PHOTOS.name)
        }

        assertEquals(InternalRouteRequest.OPEN_PHOTOS, moduleState.pendingInternalRouteRequest())
        assertEquals(InternalRouteRequest.OPEN_TRANSFERS, transferState.pendingInternalRouteRequest())
    }

    @Test
    fun 固定镜像库入口在Workspace就绪后打开无载荷末级路由并消费数据() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/containers/registry"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    supportsContainerRegistry = true,
                )
            }

            waitForSelectedModule(scenario, Module.CONTAINERS)
            waitForContainerRegistry(scenario, visible = true)
            scenario.onActivity { activity -> assertEquals(null, activity.intent.data) }
        }
    }

    @Test
    fun 固定镜像库入口在Workspace未就绪时跨Activity重建后保持枚举目标() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/containers/registry"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.recreate()
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    supportsContainerRegistry = true,
                )
            }

            waitForSelectedModule(scenario, Module.CONTAINERS)
            waitForContainerRegistry(scenario, visible = true)
            waitForNavigationIntentConsumed(scenario)
        }
    }

    @Test
    fun VMM任务固定入口在Workspace就绪后打开任务深页并返回根页() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/virtual-machines/tasks"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    virtualMachineMutationState = VirtualMachineMutationWorkspaceState(
                        supportsOfficialTasks = true,
                    ),
                )
            }

            waitForSelectedModule(scenario, Module.VIRTUAL_MACHINES)
            waitForVirtualMachineTab(scenario, VirtualMachineTab.TASKS)
            scenario.onActivity { activity ->
                assertEquals(null, activity.intent.data)
                assertTrue(model(activity).navigateUp())
            }
            waitForVirtualMachineTab(scenario, VirtualMachineTab.MACHINES)
        }
    }

    @Test
    fun 性能固定入口在Workspace未就绪且重建后打开性能深页并返回根页() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/nas-settings/performance"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.recreate()
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    nasPerformance = NasPerformanceWorkspaceState(
                        supportsPerformance = true,
                    ),
                )
            }

            waitForSelectedModule(scenario, Module.NAS_SETTINGS)
            waitForNasSettingsTab(scenario, NasSettingsTab.PERFORMANCE)
            scenario.onActivity { activity ->
                assertTrue(model(activity).navigateUp())
            }
            waitForNasSettingsTab(scenario, NasSettingsTab.OVERVIEW)
            waitForNavigationIntentConsumed(scenario)
        }
    }

    @Test
    fun Workspace未就绪时最新固定深页入口覆盖旧目标() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/virtual-machines/tasks"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                val supersededIntent = activity.intent
                dispatchNewIntent(
                    activity,
                    Intent(Intent.ACTION_VIEW, Uri.parse("lanstash://open/nas-settings/performance")),
                )
                assertEquals(null, supersededIntent.data)
            }
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    nasPerformance = NasPerformanceWorkspaceState(
                        supportsPerformance = true,
                    ),
                )
            }

            waitForSelectedModule(scenario, Module.NAS_SETTINGS)
            waitForNasSettingsTab(scenario, NasSettingsTab.PERFORMANCE)
            waitForNavigationIntentConsumed(scenario)
        }
    }

    @Test
    fun Workspace未就绪时最新固定或模块入口替换旧镜像库目标() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/containers/registry"),
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
            }
            scenario.onActivity { activity -> workspace(activity).value = syntheticWorkspace() }

            waitForSelectedModule(scenario, Module.SETTINGS)
            waitForNavigationIntentConsumed(scenario)
            scenario.onActivity { activity ->
                assertFalse(workspace(activity).value?.containerRegistryVisible == true)
            }
        }
    }

    @Test
    fun 不可用容器模块或缺少镜像库能力的固定入口确定拒绝并清除数据() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        fun intent() = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/containers/registry"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(intent()).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    availability = listOf(ModuleAvailability(Module.CONTAINERS, isAvailable = false)),
                )
            }
            waitForNavigationIntentConsumed(scenario)
            scenario.onActivity { activity ->
                assertEquals(Module.FILES, workspace(activity).value?.selectedModule)
                assertFalse(workspace(activity).value?.containerRegistryVisible == true)
            }
        }

        ActivityScenario.launch<MainActivity>(intent()).use { scenario ->
            scenario.onActivity { activity -> workspace(activity).value = syntheticWorkspace() }
            waitForNavigationIntentConsumed(scenario)
            scenario.onActivity { activity ->
                assertEquals(Module.FILES, workspace(activity).value?.selectedModule)
                assertFalse(workspace(activity).value?.containerRegistryVisible == true)
                assertTrue(workspace(activity).value?.message?.isNotBlank() == true)
            }
        }
    }

    @Test
    fun 同模块根入口会关闭先前打开的固定镜像库页() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val launchIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("lanstash://open/containers/registry"),
            context,
            MainActivity::class.java,
        ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }

        ActivityScenario.launch<MainActivity>(launchIntent).use { scenario ->
            scenario.onActivity { activity ->
                workspace(activity).value = syntheticWorkspace().copy(
                    supportsContainerRegistry = true,
                )
            }
            waitForContainerRegistry(scenario, visible = true)
            scenario.onActivity { activity ->
                dispatchNewIntent(
                    activity,
                    Intent(Intent.ACTION_VIEW, Uri.parse("lanstash://open/containers")),
                )
            }
            waitForContainerRegistry(scenario, visible = false)
            waitForNavigationIntentConsumed(scenario)
        }
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

    private fun waitForVirtualMachineTab(
        scenario: ActivityScenario<MainActivity>,
        expected: VirtualMachineTab,
    ) {
        val deadline = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < deadline) {
            var tab: VirtualMachineTab? = null
            scenario.onActivity { activity ->
                tab = workspace(activity).value?.virtualMachineMutationState?.selectedTab
            }
            if (tab == expected) return
            Thread.sleep(20)
        }
        scenario.onActivity {
            activity ->
            assertEquals(
                expected,
                workspace(activity).value?.virtualMachineMutationState?.selectedTab,
            )
        }
    }

    private fun waitForNasSettingsTab(
        scenario: ActivityScenario<MainActivity>,
        expected: NasSettingsTab,
    ) {
        val deadline = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < deadline) {
            var tab: NasSettingsTab? = null
            scenario.onActivity { activity ->
                tab = workspace(activity).value?.nasPerformance?.selectedTab
            }
            if (tab == expected) return
            Thread.sleep(20)
        }
        scenario.onActivity {
            activity -> assertEquals(expected, workspace(activity).value?.nasPerformance?.selectedTab)
        }
    }

    private fun waitForContainerRegistry(
        scenario: ActivityScenario<MainActivity>,
        visible: Boolean,
    ) {
        val deadline = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < deadline) {
            var isVisible = false
            scenario.onActivity { activity ->
                isVisible = workspace(activity).value?.containerRegistryVisible == true
            }
            if (isVisible == visible) return
            Thread.sleep(20)
        }
        scenario.onActivity { activity ->
            assertEquals(visible, workspace(activity).value?.containerRegistryVisible == true)
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
