package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasAccount
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasGroup
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.PackageInfo
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectoryPackageMutationStatePolicyTest {
    @Test
    fun `迟到回调必须同时匹配Repository NAS与双代次`() {
        assertTrue(scopedMutationCallbackMatches(true, true, 7, 7, 7))
        assertFalse(scopedMutationCallbackMatches(false, true, 7, 7, 7))
        assertFalse(scopedMutationCallbackMatches(true, false, 7, 7, 7))
        assertFalse(scopedMutationCallbackMatches(true, true, 6, 7, 7))
        assertFalse(scopedMutationCallbackMatches(true, true, 7, 7, 8))
    }

    @Test
    fun `八类结果对目录与套件共用危险刷新门禁`() {
        MutationResultStatus.entries.forEach { status ->
            val result = result(status)
            val expected = status in setOf(
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            )
            assertEquals(
                status.name,
                expected,
                destructiveServiceMutationRequiresRefreshBeforeDismiss(result),
            )
        }
        assertTrue(
            destructiveServiceMutationRequiresRefreshBeforeDismiss(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    category = MutationErrorCategory.CONFLICT,
                ),
            ),
        )
    }

    @Test
    fun `进行中写操作和专项刷新始终阻止退出`() {
        assertTrue(
            structuredMutationBlocksWorkspaceExit(
                mutationInProgress = true,
                refreshInProgress = false,
                result = null,
                failure = null,
                refreshCompleted = false,
            ),
        )
        assertTrue(
            structuredMutationBlocksWorkspaceExit(
                mutationInProgress = false,
                refreshInProgress = true,
                result = null,
                failure = null,
                refreshCompleted = false,
            ),
        )
    }

    @Test
    fun `危险结果或失败完成可信专项刷新前阻止退出`() {
        val dangerous = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED)
        assertTrue(
            structuredMutationBlocksWorkspaceExit(false, false, dangerous, null, false),
        )
        assertFalse(
            structuredMutationBlocksWorkspaceExit(false, false, dangerous, null, true),
        )
        assertTrue(
            structuredMutationBlocksWorkspaceExit(
                mutationInProgress = false,
                refreshInProgress = false,
                result = null,
                failure = io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure(
                    null,
                    "failure",
                    "retry",
                ),
                refreshCompleted = false,
            ),
        )
        assertFalse(
            structuredMutationBlocksWorkspaceExit(
                mutationInProgress = false,
                refreshInProgress = false,
                result = result(MutationResultStatus.CONFIRMED_SUCCESS),
                failure = null,
                refreshCompleted = false,
            ),
        )
        val profile = NasProfile("profile", "NAS", "nas.example", "user")
        assertTrue(
            WorkspaceState(
                profile = profile,
                packageMutationResult = dangerous,
            ).hasBlockingDirectoryOrPackageMutation(),
        )
        assertTrue(
            WorkspaceState(
                profile = profile,
                directoryMutationFailure = io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure(
                    null,
                    "failure",
                    "retry",
                ),
            ).hasBlockingDirectoryOrPackageMutation(),
        )
        assertFalse(WorkspaceState(profile = profile).hasBlockingDirectoryOrPackageMutation())
    }

    @Test
    fun `套件请求要求可信列表完整基线与对应能力`() {
        val target = pkg()
        val snapshot = snapshot(packages = listOf(target))
        assertTrue(canRequestPackageMutation(snapshot, target, PackageMutationOperation.START))
        assertTrue(canRequestPackageMutation(snapshot, target, PackageMutationOperation.UNINSTALL))
        assertFalse(canRequestPackageMutation(snapshot, target, PackageMutationOperation.STOP))
        assertFalse(
            canRequestPackageMutation(
                snapshot.copy(packagesAvailable = false),
                target,
                PackageMutationOperation.START,
            ),
        )
        assertFalse(
            canRequestPackageMutation(
                snapshot.copy(packages = listOf(target.copy(version = "2.0"))),
                target,
                PackageMutationOperation.START,
            ),
        )
    }

    @Test
    fun `套件刷新按稳定id判定启停与卸载结果`() {
        val target = pkg()
        assertTrue(
            packageMutationTargetReached(
                listOf(target.copy(status = ResourceState.RUNNING)),
                target,
                PackageMutationOperation.START,
            ),
        )
        assertTrue(
            packageMutationTargetReached(
                listOf(target.copy(status = ResourceState.STOPPED)),
                target,
                PackageMutationOperation.STOP,
            ),
        )
        assertTrue(packageMutationTargetReached(emptyList(), target, PackageMutationOperation.UNINSTALL))
        assertFalse(
            packageMutationTargetReached(
                listOf(target.copy(status = ResourceState.STOPPED)),
                target,
                PackageMutationOperation.START,
            ),
        )
    }

    @Test
    fun `套件成功回退只在可信且基线未漂移时改目标字段`() {
        val target = pkg()
        val other = pkg("other").copy(name = "Other")
        val snapshot = snapshot(packages = listOf(target, other))
        val started = confirmedPackageMutationFallback(snapshot, target, PackageMutationOperation.START)
        assertEquals(ResourceState.RUNNING, started?.packages?.first()?.status)
        assertEquals(other, started?.packages?.last())
        assertEquals(
            listOf(other),
            confirmedPackageMutationFallback(snapshot, target, PackageMutationOperation.UNINSTALL)?.packages,
        )
        assertNull(
            confirmedPackageMutationFallback(
                snapshot.copy(packagesAvailable = false),
                target,
                PackageMutationOperation.START,
            ),
        )
        assertNull(
            confirmedPackageMutationFallback(
                snapshot.copy(packages = listOf(target.copy(version = "2.0"), other)),
                target,
                PackageMutationOperation.START,
            ),
        )
    }

    @Test
    fun `目录删除请求要求完整目标可删除且列表可信`() {
        val account = account()
        val group = group()
        val accountTarget = DirectoryEntryMutationTarget(DirectoryEntryKind.ACCOUNT, account = account)
        val groupTarget = DirectoryEntryMutationTarget(DirectoryEntryKind.GROUP, group = group)
        val snapshot = snapshot(accounts = listOf(account), groups = listOf(group))
        assertTrue(canRequestDirectoryDeletion(snapshot, accountTarget))
        assertTrue(canRequestDirectoryDeletion(snapshot, groupTarget))
        assertFalse(
            canRequestDirectoryDeletion(snapshot.copy(accountsAvailable = false), accountTarget),
        )
        assertFalse(
            canRequestDirectoryDeletion(
                snapshot.copy(accounts = listOf(account.copy(description = "changed"))),
                accountTarget,
            ),
        )
        assertFalse(
            canRequestDirectoryDeletion(
                snapshot.copy(groups = listOf(group.copy(canDelete = false))),
                groupTarget,
            ),
        )
    }

    @Test
    fun `目录目标消失优先使用稳定id且无id时使用规范化名称`() {
        val account = account()
        val accountTarget = DirectoryEntryMutationTarget(DirectoryEntryKind.ACCOUNT, account = account)
        assertFalse(directoryMutationTargetAbsent(accountTarget, listOf(account.copy(name = "renamed")), emptyList()))
        assertTrue(directoryMutationTargetAbsent(accountTarget, emptyList(), emptyList()))

        val group = group().copy(id = null, name = "Operators")
        val groupTarget = DirectoryEntryMutationTarget(DirectoryEntryKind.GROUP, group = group)
        assertFalse(
            directoryMutationTargetAbsent(
                groupTarget,
                emptyList(),
                listOf(group.copy(name = "operators")),
            ),
        )
        assertTrue(directoryMutationTargetAbsent(groupTarget, emptyList(), emptyList()))
    }

    @Test
    fun `目录成功回退拒绝不可用列表和基线漂移并只移除完整目标`() {
        val account = account()
        val other = account().copy(id = 2, name = "other")
        val target = DirectoryEntryMutationTarget(DirectoryEntryKind.ACCOUNT, account = account)
        val snapshot = snapshot(accounts = listOf(account, other))
        assertEquals(
            listOf(other),
            confirmedDirectoryDeletionFallback(snapshot, target)?.accounts,
        )
        assertNull(
            confirmedDirectoryDeletionFallback(snapshot.copy(accountsAvailable = false), target),
        )
        assertNull(
            confirmedDirectoryDeletionFallback(
                snapshot.copy(accounts = listOf(account.copy(description = "changed"), other)),
                target,
            ),
        )
    }

    private fun pkg(id: String = "pkg") = PackageInfo(
        id = id,
        name = "Package",
        version = "1.0",
        status = ResourceState.STOPPED,
        description = "Description",
        canStart = true,
        canStop = false,
        canUninstall = true,
    )

    private fun account() = NasAccount(1, "user", "description", null, false, true)

    private fun group() = NasGroup(1, "group", "description", true)

    private fun snapshot(
        packages: List<PackageInfo> = emptyList(),
        accounts: List<NasAccount> = emptyList(),
        groups: List<NasGroup> = emptyList(),
    ) = NasSettingsSnapshot(
        system = null,
        volumes = emptyList(), pools = emptyList(), disks = emptyList(), storageDisks = emptyList(),
        packages = packages, scheduledTasks = emptyList(), accounts = accounts, groups = groups,
        logs = emptyList(), connections = emptyList(), connectionsAvailable = true,
        networkInterfaces = emptyList(), networkInterfacesAvailable = true,
        ddnsDirectory = null, ddnsDirectoryAvailable = true, fileServiceSettings = null,
        terminalSettings = null, proxySettings = null, regionSettings = null,
        securitySettings = null, hardwareSettings = null, security = emptyList(),
        packagesAvailable = true, accountsAvailable = true, groupsAvailable = true,
    )

    private fun result(
        status: MutationResultStatus,
        category: MutationErrorCategory? = null,
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "serviceMutation",
        submitted = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        requiresRefresh = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            else -> MutationResultCounts(0, 1, 0)
        },
        errorCategory = category,
    )
}
