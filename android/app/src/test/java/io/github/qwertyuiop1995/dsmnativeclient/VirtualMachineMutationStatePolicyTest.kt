package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.ManagedResource
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineOverview
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineImageType
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineLocalImageRejection
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineLocalImageValidation
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.VirtualMachineTaskCenterState
import java.lang.reflect.Modifier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VirtualMachineMutationStatePolicyTest {
    @Test
    fun `Guest 外链在 VMM 编辑确认和在途写流程活跃时拒绝`() {
        assertFalse(virtualMachineGuestExternalNavigationBlocked(VirtualMachineMutationWorkspaceState()))
        listOf(
            VirtualMachineMutationWorkspaceState(creationEditorVisible = true),
            VirtualMachineMutationWorkspaceState(imageImportEditorVisible = true),
            VirtualMachineMutationWorkspaceState(settingsEditorVisible = true),
            VirtualMachineMutationWorkspaceState(lifecycleConfirmationRequested = true),
            VirtualMachineMutationWorkspaceState(taskCleanupConfirmationRequested = true),
            VirtualMachineMutationWorkspaceState(mutationInProgress = true),
            VirtualMachineMutationWorkspaceState(mutationRefreshInProgress = true),
        ).forEach { state ->
            assertTrue(virtualMachineGuestExternalNavigationBlocked(state))
        }
    }

    private val target = virtualMachineMutationTarget(
        profileId = "profile-a",
        kind = VirtualMachineMutationKind.SETTINGS,
        operation = "virtualMachineSettings",
        resourceId = "guest-1",
        requestParts = listOf("Synthetic VM", "2", "2048"),
    )

    @Test
    fun `目标指纹稳定且请求或类型变化会改变身份`() {
        assertEquals(
            target,
            virtualMachineMutationTarget(
                "profile-a",
                VirtualMachineMutationKind.SETTINGS,
                "virtualMachineSettings",
                "guest-1",
                listOf("Synthetic VM", "2", "2048"),
            ),
        )
        assertNotEquals(
            target.requestFingerprint,
            virtualMachineMutationTarget(
                "profile-a",
                VirtualMachineMutationKind.SETTINGS,
                "virtualMachineSettings",
                "guest-1",
                listOf("Synthetic VM", "4", "2048"),
            ).requestFingerprint,
        )
        assertNotEquals(
            target.requestFingerprint,
            virtualMachineMutationTarget(
                "profile-a",
                VirtualMachineMutationKind.LIFECYCLE,
                "virtualMachineControl",
                "guest-1",
                listOf("shutdown"),
            ).requestFingerprint,
        )
    }

    @Test
    fun `同步claim写入目标后拒绝创建设置与生命周期竞争请求`() {
        assertTrue(canStartVirtualMachineMutation(false, VirtualMachineMutationWorkspaceState()))
        val claimed = VirtualMachineMutationWorkspaceState(
            target = target,
            mutationInProgress = true,
            mutationGeneration = 7,
        )
        assertFalse(canStartVirtualMachineMutation(false, claimed))
        assertFalse(canStartVirtualMachineMutation(true, VirtualMachineMutationWorkspaceState()))
        assertFalse(
            canStartVirtualMachineMutation(
                false,
                VirtualMachineMutationWorkspaceState(
                    mutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS),
                ),
            ),
        )
    }

    @Test
    fun `编辑器与生命周期确认均阻止工作区退出`() {
        assertTrue(
            virtualMachineMutationBlocksWorkspaceExit(
                VirtualMachineMutationWorkspaceState(
                    creationEditorVisible = true,
                    creationDraft = VirtualMachineCreationDraftState(),
                ),
            ),
        )
        assertTrue(
            virtualMachineMutationBlocksWorkspaceExit(
                VirtualMachineMutationWorkspaceState(
                    settingsEditorVisible = true,
                    settingsTargetId = "guest-1",
                ),
            ),
        )
        assertTrue(
            virtualMachineMutationBlocksWorkspaceExit(
                VirtualMachineMutationWorkspaceState(
                    lifecycleConfirmationTarget = VirtualMachineLifecycleTarget(
                        "profile-a",
                        "guest-1",
                        VirtualMachineLifecycleOperation.CONTROL,
                        ResourceState.RUNNING,
                        "shutdown",
                    ),
                    lifecycleConfirmationRequested = true,
                ),
            ),
        )
    }

    @Test
    fun `四种未提交结果允许创建与设置继续编辑`() {
        val statuses = listOf(
            MutationResultStatus.CONFIRMED_FAILURE,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
        )
        val creationTarget = virtualMachineMutationTarget(
            "profile-a",
            VirtualMachineMutationKind.CREATION,
            "virtualMachineCreate",
            null,
            listOf("Synthetic VM"),
        )
        val baseline = VirtualMachineSettings("Synthetic VM", "Before", 2, 2048, false)
        val settingsDraft = VirtualMachineSettingsDraftState.from(
            baseline.copy(description = "After"),
        )
        statuses.forEach { status ->
            assertTrue(
                status.name,
                canContinueEditingVirtualMachineMutation(
                    VirtualMachineMutationWorkspaceState(
                        creationEditorVisible = true,
                        creationDraft = VirtualMachineCreationDraftState(
                            step = 2,
                            name = "Synthetic VM",
                            storageId = "storage-1",
                        ),
                        target = creationTarget,
                        mutationResult = result(status),
                        mutationGeneration = 7,
                    ),
                ),
            )
            assertTrue(
                status.name,
                canContinueEditingVirtualMachineMutation(
                    VirtualMachineMutationWorkspaceState(
                        settingsEditorVisible = true,
                        settingsTargetId = "guest-1",
                        settingsBaseline = baseline,
                        settingsDraft = settingsDraft,
                        target = target,
                        mutationResult = result(status),
                        mutationGeneration = 7,
                    ),
                ),
            )
        }
    }

    @Test
    fun `已提交需刷新异常与生命周期结果拒绝继续编辑`() {
        val editableCreation = VirtualMachineMutationWorkspaceState(
            creationEditorVisible = true,
            creationDraft = VirtualMachineCreationDraftState(
                step = 2,
                name = "Synthetic VM",
                storageId = "storage-1",
            ),
            target = virtualMachineMutationTarget(
                "profile-a",
                VirtualMachineMutationKind.CREATION,
                "virtualMachineCreate",
                null,
                listOf("Synthetic VM"),
            ),
        )
        assertFalse(
            canContinueEditingVirtualMachineMutation(
                editableCreation.copy(
                    mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
                ),
            ),
        )
        assertFalse(
            canContinueEditingVirtualMachineMutation(
                editableCreation.copy(
                    mutationFailure = DsmFailure(
                        null,
                        "Synthetic failure",
                        "Refresh and review.",
                        kind = DsmErrorKind.UNKNOWN,
                    ),
                ),
            ),
        )
        val lifecycleTarget = virtualMachineMutationTarget(
            "profile-a",
            VirtualMachineMutationKind.LIFECYCLE,
            "virtualMachineControl",
            "guest-1",
            listOf("shutdown"),
        )
        assertFalse(
            canContinueEditingVirtualMachineMutation(
                VirtualMachineMutationWorkspaceState(
                    lifecycleConfirmationTarget = VirtualMachineLifecycleTarget(
                        "profile-a",
                        "guest-1",
                        VirtualMachineLifecycleOperation.CONTROL,
                        ResourceState.RUNNING,
                        "shutdown",
                    ),
                    target = lifecycleTarget,
                    mutationResult = result(MutationResultStatus.CONFIRMED_FAILURE),
                ),
            ),
        )
    }

    @Test
    fun `继续编辑清除目标并推进代次后旧回调失效`() {
        assertFalse(
            virtualMachineMutationCallbackMatches(
                repositoryMatches = true,
                profileMatches = true,
                stateTarget = null,
                callbackTarget = target,
                stateGeneration = 8,
                callbackGeneration = 7,
                globalGeneration = 8,
            ),
        )
    }

    @Test
    fun `回调必须同时匹配仓库NAS目标与双代次`() {
        assertTrue(callbackMatches())
        assertFalse(callbackMatches(repositoryMatches = false))
        assertFalse(callbackMatches(profileMatches = false))
        assertFalse(callbackMatches(stateTarget = target.copy(resourceId = "guest-2")))
        assertFalse(callbackMatches(stateGeneration = 8))
        assertFalse(callbackMatches(callbackGeneration = 8))
        assertFalse(callbackMatches(globalGeneration = 8))
    }

    @Test
    fun `八种结果保持结构化刷新与关闭策略`() {
        MutationResultStatus.entries.forEach { status ->
            val dangerous = status in setOf(
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            )
            val state = VirtualMachineMutationWorkspaceState(
                target = target,
                mutationResult = result(status),
            )
            assertEquals(status.name, dangerous, virtualMachineMutationRequiresRefreshBeforeDismiss(state))
            assertEquals(status.name, dangerous, virtualMachineMutationBlocksWorkspaceExit(state))
            assertEquals(status.name, !dangerous, canDismissVirtualMachineMutation(state))

            val refreshed = state.copy(
                mutationRefreshCompleted = true,
                mutationVerification = VirtualMachineMutationVerification.MATCHES,
            )
            assertTrue(status.name, canDismissVirtualMachineMutation(refreshed))
            assertEquals(
                "刷新不能隐式清除需要明确关闭的证据：${status.name}",
                dangerous,
                virtualMachineMutationBlocksWorkspaceExit(refreshed),
            )
            assertEquals(status, refreshed.mutationResult?.status)
        }
    }

    @Test
    fun `异常与刷新失败持续阻止退出直到成功刷新后明确关闭`() {
        val failure = DsmFailure(
            code = null,
            message = "Synthetic failure",
            recovery = "Refresh and review.",
            kind = DsmErrorKind.UNKNOWN,
        )
        val failed = VirtualMachineMutationWorkspaceState(
            target = target,
            mutationFailure = failure,
            mutationRefreshFailure = failure,
        )
        assertTrue(virtualMachineMutationRequiresRefreshBeforeDismiss(failed))
        assertTrue(virtualMachineMutationBlocksWorkspaceExit(failed))
        assertFalse(canDismissVirtualMachineMutation(failed))

        val refreshed = failed.copy(
            mutationRefreshFailure = null,
            mutationRefreshCompleted = true,
            mutationVerification = VirtualMachineMutationVerification.DIFFERS,
        )
        assertTrue(canDismissVirtualMachineMutation(refreshed))
        assertTrue(virtualMachineMutationBlocksWorkspaceExit(refreshed))
    }

    @Test
    fun `映像任务未清理时即使结果已确认也持续阻止关闭与退出`() {
        val pendingCleanup = VirtualMachineMutationWorkspaceState(
            target = target.copy(kind = VirtualMachineMutationKind.IMAGE_IMPORT),
            imageImportTaskId = "task-1",
            mutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS),
            mutationRefreshCompleted = true,
            mutationVerification = VirtualMachineMutationVerification.MATCHES,
        )

        assertTrue(virtualMachineMutationRequiresRefreshBeforeDismiss(pendingCleanup))
        assertTrue(virtualMachineMutationBlocksWorkspaceExit(pendingCleanup))
        assertFalse(canDismissVirtualMachineMutation(pendingCleanup))

        val cleared = pendingCleanup.copy(imageImportTaskId = null)
        assertFalse(virtualMachineMutationRequiresRefreshBeforeDismiss(cleared))
        assertFalse(virtualMachineMutationBlocksWorkspaceExit(cleared))
        assertTrue(canDismissVirtualMachineMutation(cleared))
    }

    @Test
    fun `任务清理确认和回读只按原始任务基线判断`() {
        val completed = VirtualMachineTask(
            id = "local-a",
            isFinished = true,
            progressPercent = 100,
            taskToken = "task-a",
        )
        val state = VirtualMachineMutationWorkspaceState(
            taskCleanupConfirmationRequested = true,
            taskCleanupBaseline = listOf(completed),
        )
        assertTrue(virtualMachineMutationBlocksWorkspaceExit(state))
        assertTrue(virtualMachineOrdinaryLoadBlocked(state))

        val submitted = state.copy(
            taskCleanupConfirmationRequested = false,
            target = target.copy(kind = VirtualMachineMutationKind.TASK_CLEANUP),
        )
        assertEquals(
            VirtualMachineMutationVerification.DIFFERS,
            virtualMachineMutationVerification(
                submitted,
                overview().copy(
                    tasks = listOf(completed),
                    taskCenterState = VirtualMachineTaskCenterState.AVAILABLE,
                ),
            ),
        )
        assertEquals(
            VirtualMachineMutationVerification.MATCHES,
            virtualMachineMutationVerification(
                submitted,
                overview().copy(
                    tasks = emptyList(),
                    taskCenterState = VirtualMachineTaskCenterState.AVAILABLE,
                ),
            ),
        )
        assertEquals(
            VirtualMachineMutationVerification.UNAVAILABLE,
            virtualMachineMutationVerification(
                submitted,
                overview().copy(taskCenterState = VirtualMachineTaskCenterState.LOAD_FAILED),
            ),
        )
    }

    @Test
    fun `任务清理外部取消只采用 Repository 已解析证据`() {
        val cleanupTarget = target.copy(
            kind = VirtualMachineMutationKind.TASK_CLEANUP,
            operation = "virtualMachineTaskCleanup",
        )
        val withoutEvidence = cancelledVirtualMachineMutationResult(cleanupTarget)
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, withoutEvidence.status)
        assertFalse(withoutEvidence.submitted)
        assertEquals(MutationResultCounts(0, 0, 0), withoutEvidence.counts)

        val resolved = MutationResult(
            schemaVersion = 1,
            status = MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            operation = "virtualMachineTaskCleanup",
            submitted = true,
            requiresRefresh = true,
            counts = MutationResultCounts(succeeded = 1, failed = 1, unknown = 2),
            errorCategory = MutationErrorCategory.UNKNOWN,
            diagnosticTag = "vmm.task.cleanup.cancelled-after-readback",
        )
        assertEquals(resolved, cancelledVirtualMachineMutationResult(cleanupTarget, resolved))
    }

    @Test
    fun `刷新核对区分匹配差异消失与不可用`() {
        val desired = VirtualMachineSettings("Synthetic VM", "Expected", 2, 2048, true)
        val state = VirtualMachineMutationWorkspaceState(
            settingsTargetId = "guest-1",
            settingsBaseline = desired.copy(description = "Before"),
            settingsDraft = VirtualMachineSettingsDraftState.from(desired),
            target = target,
            mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
        )
        val matching = machine("guest-1", desired)
        assertEquals(
            VirtualMachineMutationVerification.MATCHES,
            virtualMachineMutationVerification(state, overview(matching)),
        )
        assertEquals(
            VirtualMachineMutationVerification.DIFFERS,
            virtualMachineMutationVerification(
                state,
                overview(machine("guest-1", desired.copy(memoryMiB = 4096))),
            ),
        )
        assertEquals(
            VirtualMachineMutationVerification.DISAPPEARED,
            virtualMachineMutationVerification(state, overview()),
        )
        assertTrue(
            canDismissVirtualMachineMutation(
                state.copy(
                    mutationRefreshCompleted = true,
                    mutationVerification = VirtualMachineMutationVerification.UNAVAILABLE,
                ),
            ),
        )
    }

    @Test
    fun `设置基线缺字段越界或autorun一律安全关闭`() {
        val valid = machine(
            "guest-1",
            VirtualMachineSettings("Synthetic VM", "Expected", 2, 2048, true),
        )
        assertEquals(2, virtualMachineSettingsBaseline(valid)?.cpuCount)
        assertEquals(null, virtualMachineSettingsBaseline(valid.copy(metadata = valid.metadata - "description")))
        assertEquals(
            null,
            virtualMachineSettingsBaseline(valid.copy(metadata = valid.metadata + ("vcpu_num" to "0"))),
        )
        assertEquals(
            null,
            virtualMachineSettingsBaseline(valid.copy(metadata = valid.metadata + ("vram_size" to "bad"))),
        )
        assertEquals(
            null,
            virtualMachineSettingsBaseline(valid.copy(metadata = valid.metadata + ("autorun" to "1"))),
        )
    }

    @Test
    fun `创建刷新不得把其他客户端同名虚拟机归属为本次结果`() {
        val creationTarget = virtualMachineMutationTarget(
            "profile-a",
            VirtualMachineMutationKind.CREATION,
            "virtualMachineCreate",
            null,
            listOf("Synthetic VM"),
        )
        val state = VirtualMachineMutationWorkspaceState(
            creationDraft = VirtualMachineCreationDraftState(
                step = 2,
                name = "Synthetic VM",
                cpu = "2",
                memory = "2048",
                disk = "20",
                storageId = "storage-1",
            ),
            target = creationTarget,
            mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
        )
        assertEquals(
            VirtualMachineMutationVerification.UNAVAILABLE,
            virtualMachineMutationVerification(
                state,
                overview(
                    machine(
                        "other-client-guest",
                        VirtualMachineSettings("Synthetic VM", "", 2, 2048, false),
                    ),
                ),
            ),
        )
    }

    @Test
    fun `创建与设置草稿保留编辑值并严格解析`() {
        val creation = VirtualMachineCreationDraftState(
            step = 2,
            name = " Synthetic VM ",
            description = " Draft ",
            cpu = "2",
            memory = "2048",
            disk = "20",
            storageId = "storage-1",
        )
        assertEquals("Synthetic VM", creation.toCreationOrNull()?.name)
        assertEquals("Draft", creation.toCreationOrNull()?.description)
        assertEquals(null, creation.copy(cpu = "0").toCreationOrNull())
        assertEquals(
            0,
            creation.copy(disk = "not-used", diskImageId = "image-1")
                .toCreationOrNull()?.diskGiB,
        )
        assertEquals(
            null,
            creation.copy(
                additionalDisks = List(8) { VirtualMachineCreationDiskDraftState() },
            ).toCreationOrNull(),
        )

        val settings = VirtualMachineSettingsDraftState(" VM ", " Note ", "4", "4096", false)
        assertEquals("VM", settings.toSettingsOrNull()?.name)
        assertEquals(null, settings.copy(memory = "bad").toSettingsOrNull())
    }

    @Test
    fun `本地映像草稿不保存URI且严格校验格式大小存储与暂存目录`() {
        val twoTiB = 2_199_023_255_552L
        val local = VirtualMachineImageImportDraftState(
            imageName = " Local disk ",
            source = VirtualMachineImageImportSource.LOCAL,
            storage = eligibleStorage(),
            localFile = VirtualMachineLocalImageSelection("machine.vhdx", twoTiB),
            localStagingDirectory = stagingDirectory(),
        )

        val submission = local.toLocalSubmissionOrNull()
        assertEquals("Local disk", submission?.imageName)
        assertEquals(VirtualMachineImageType.DISK, submission?.image?.imageType)
        assertEquals(twoTiB, submission?.image?.originalSizeBytes)
        assertEquals(null, local.toImportOrNull())
        assertFalse(local.localFile.toString().contains("machine.vhdx"))
        assertFalse(submission.toString().contains("/share/staging"))
        assertEquals(
            setOf("displayName", "sizeBytes"),
            VirtualMachineLocalImageSelection::class.java.declaredFields
                .filterNot { it.isSynthetic || Modifier.isStatic(it.modifiers) }
                .map { it.name }
                .toSet(),
        )

        val ova = local.copy(localFile = VirtualMachineLocalImageSelection("machine.ova", 1L))
        assertEquals(
            VirtualMachineLocalImageValidation.Rejected(
                VirtualMachineLocalImageRejection.UNSUPPORTED_EXTENSION,
            ),
            ova.localValidation(),
        )
        assertEquals(null, ova.toLocalSubmissionOrNull())
        assertEquals(
            null,
            local.copy(
                localFile = VirtualMachineLocalImageSelection("machine.vhdx", twoTiB + 1L),
            ).toLocalSubmissionOrNull(),
        )
        assertEquals(null, local.copy(localStagingDirectory = null).toLocalSubmissionOrNull())
    }

    @Test
    fun `外层取消按提交后未知结果保留并要求刷新`() {
        val result = cancelledVirtualMachineMutationResult(target)
        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result.status)
        assertTrue(result.submitted)
        assertTrue(result.requiresRefresh)
        assertEquals(MutationResultCounts(0, 0, 1), result.counts)
        assertEquals(target.operation, result.operation)
    }

    @Test
    fun `普通概览旧回调按仓库模块NAS和代次隔离`() {
        val token = VirtualMachineOverviewRequestToken("profile-a", 4)
        assertTrue(
            virtualMachineOverviewCallbackMatches(
                true,
                Module.VIRTUAL_MACHINES,
                "profile-a",
                token,
                4,
            ),
        )
        assertFalse(virtualMachineOverviewCallbackMatches(false, Module.VIRTUAL_MACHINES, "profile-a", token, 4))
        assertFalse(virtualMachineOverviewCallbackMatches(true, Module.FILES, "profile-a", token, 4))
        assertFalse(virtualMachineOverviewCallbackMatches(true, Module.VIRTUAL_MACHINES, "profile-b", token, 4))
        assertFalse(virtualMachineOverviewCallbackMatches(true, Module.VIRTUAL_MACHINES, "profile-a", token, 5))
    }

    @Test
    fun `普通概览请求在编辑确认与结构化反馈期间均被阻止`() {
        assertFalse(virtualMachineOrdinaryLoadBlocked(VirtualMachineMutationWorkspaceState()))
        assertTrue(
            virtualMachineOrdinaryLoadBlocked(
                VirtualMachineMutationWorkspaceState(
                    creationEditorVisible = true,
                    creationDraft = VirtualMachineCreationDraftState(),
                ),
            ),
        )
        assertTrue(
            virtualMachineOrdinaryLoadBlocked(
                VirtualMachineMutationWorkspaceState(
                    settingsEditorVisible = true,
                    settingsTargetId = "guest-1",
                ),
            ),
        )
        assertTrue(
            virtualMachineOrdinaryLoadBlocked(
                VirtualMachineMutationWorkspaceState(
                    lifecycleConfirmationRequested = true,
                    lifecycleConfirmationTarget = VirtualMachineLifecycleTarget(
                        "profile-a",
                        "guest-1",
                        VirtualMachineLifecycleOperation.CONTROL,
                        ResourceState.RUNNING,
                        "shutdown",
                    ),
                ),
            ),
        )
        assertTrue(
            virtualMachineOrdinaryLoadBlocked(
                VirtualMachineMutationWorkspaceState(
                    target = target,
                    mutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS),
                ),
            ),
        )
    }

    @Test
    fun `生命周期刷新使用用户所见基线核对目标状态`() {
        val running = machine(
            "guest-1",
            VirtualMachineSettings("Synthetic VM", "Expected", 2, 2048, false),
        ).copy(state = ResourceState.RUNNING)
        val stopped = running.copy(state = ResourceState.STOPPED)
        fun state(baselineState: ResourceState, command: String) =
            VirtualMachineMutationWorkspaceState(
            lifecycleConfirmationTarget = VirtualMachineLifecycleTarget(
                "profile-a",
                "guest-1",
                VirtualMachineLifecycleOperation.CONTROL,
                baselineState,
                command,
            ),
            target = virtualMachineMutationTarget(
                "profile-a",
                VirtualMachineMutationKind.LIFECYCLE,
                "virtualMachineControl",
                "guest-1",
                listOf(command),
            ),
            mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
        )
        assertEquals(
            VirtualMachineMutationVerification.MATCHES,
            virtualMachineMutationVerification(
                state(ResourceState.STOPPED, "poweron"),
                overview(running),
            ),
        )
        assertEquals(
            VirtualMachineMutationVerification.DIFFERS,
            virtualMachineMutationVerification(
                state(ResourceState.STOPPED, "poweron"),
                overview(stopped),
            ),
        )
        assertEquals(
            VirtualMachineMutationVerification.MATCHES,
            virtualMachineMutationVerification(
                state(ResourceState.RUNNING, "shutdown"),
                overview(stopped),
            ),
        )
    }

    @Test
    fun `控制命令仅允许与用户所见状态匹配的安全矩阵`() {
        assertEquals(
            ResourceState.RUNNING,
            virtualMachineControlExpectedState(ResourceState.STOPPED, "poweron"),
        )
        listOf("poweroff", "shutdown").forEach { command ->
            assertEquals(
                command,
                ResourceState.STOPPED,
                virtualMachineControlExpectedState(ResourceState.RUNNING, command),
            )
        }
        ResourceState.entries.forEach { baseline ->
            listOf("poweron", "poweroff", "shutdown", "pause", "resume", "reboot").forEach { command ->
                val allowed = baseline == ResourceState.STOPPED && command == "poweron" ||
                    baseline == ResourceState.RUNNING && command in setOf("poweroff", "shutdown")
                if (!allowed) {
                    assertEquals(
                        "$baseline/$command",
                        null,
                        virtualMachineControlExpectedState(baseline, command),
                    )
                }
            }
        }
    }

    @Test
    fun `生命周期目标重建保留基线且基线参与身份比较`() {
        val lifecycle = VirtualMachineLifecycleTarget(
            profileId = "profile-a",
            resourceId = "guest-1",
            operation = VirtualMachineLifecycleOperation.CONTROL,
            baselineState = ResourceState.RUNNING,
            command = "shutdown",
        )
        val rebuilt = VirtualMachineMutationWorkspaceState(
            lifecycleConfirmationTarget = lifecycle.copy(),
            lifecycleConfirmationRequested = true,
        )
        assertEquals(lifecycle, rebuilt.lifecycleConfirmationTarget)
        assertEquals(ResourceState.RUNNING, rebuilt.lifecycleConfirmationTarget?.baselineState)
        assertNotEquals(
            lifecycle,
            lifecycle.copy(
                baselineState = ResourceState.STOPPED,
                command = "poweron",
            ),
        )
        val runningClaim = virtualMachineMutationTarget(
            "profile-a",
            VirtualMachineMutationKind.LIFECYCLE,
            "virtualMachineControl",
            "guest-1",
            listOf(ResourceState.RUNNING.name, "shutdown"),
        )
        val stoppedClaim = virtualMachineMutationTarget(
            "profile-a",
            VirtualMachineMutationKind.LIFECYCLE,
            "virtualMachineControl",
            "guest-1",
            listOf(ResourceState.STOPPED.name, "poweron"),
        )
        assertNotEquals(runningClaim, stoppedClaim)
        assertFalse(
            virtualMachineMutationCallbackMatches(
                repositoryMatches = true,
                profileMatches = true,
                stateTarget = stoppedClaim,
                callbackTarget = runningClaim,
                stateGeneration = 7,
                callbackGeneration = 7,
                globalGeneration = 7,
            ),
        )
    }

    private fun callbackMatches(
        repositoryMatches: Boolean = true,
        profileMatches: Boolean = true,
        stateTarget: VirtualMachineMutationTarget? = target,
        stateGeneration: Long = 7,
        callbackGeneration: Long = 7,
        globalGeneration: Long = 7,
    ) = virtualMachineMutationCallbackMatches(
        repositoryMatches,
        profileMatches,
        stateTarget,
        target,
        stateGeneration,
        callbackGeneration,
        globalGeneration,
    )

    private fun result(status: MutationResultStatus): MutationResult {
        val dangerous = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 0, 1)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            else -> MutationResultCounts(0, 1, 0)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "virtualMachineSettings",
            submitted = status in setOf(
                MutationResultStatus.CONFIRMED_SUCCESS,
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ),
            requiresRefresh = dangerous,
            counts = counts,
            errorCategory = if (status == MutationResultStatus.CONFIRMED_SUCCESS) {
                null
            } else {
                MutationErrorCategory.UNKNOWN
            },
            diagnosticTag = "synthetic.${status.name.lowercase()}",
        )
    }

    private fun machine(id: String, settings: VirtualMachineSettings) = ManagedResource(
        id = id,
        name = settings.name,
        detail = "Synthetic",
        state = ResourceState.STOPPED,
        metadata = mapOf(
            "description" to settings.description,
            "vcpu_num" to settings.cpuCount.toString(),
            "vram_size" to settings.memoryMiB.toString(),
            "autorun" to if (settings.autoStart) "2" else "0",
        ),
    )

    private fun eligibleStorage() = ManagedResource(
        id = "storage-1",
        name = "Synthetic storage",
        detail = "online",
        state = ResourceState.RUNNING,
        metadata = mapOf("status" to "online"),
    )

    private fun stagingDirectory() = FileItem(
        path = "/share/staging",
        name = "staging",
        isDirectory = true,
        canRead = true,
        canWrite = true,
    )

    private fun overview(vararg machines: ManagedResource) = VirtualMachineOverview(
        machines = machines.toList(),
        hosts = emptyList(),
        storages = emptyList(),
        networks = emptyList(),
        images = emptyList(),
        protectionPlans = emptyList(),
        protectionSchedules = emptyList(),
        retentionPolicies = emptyList(),
        logs = emptyList(),
    )
}
