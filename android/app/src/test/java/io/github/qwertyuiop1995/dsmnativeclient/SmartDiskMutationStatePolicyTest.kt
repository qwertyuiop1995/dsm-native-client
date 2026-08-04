package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDiskTestStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDiskTestType
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasStorageDisk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartDiskMutationStatePolicyTest {
    @Test
    fun `检测状态必须匹配硬盘且运行状态包含明确类型`() {
        val disk = disk()
        assertTrue(isTrustedDiskTestStatus(disk, stopped()))
        assertTrue(isTrustedDiskTestStatus(disk, running()))
        assertFalse(isTrustedDiskTestStatus(disk, stopped().copy(diskId = "other")))
        assertFalse(isTrustedDiskTestStatus(disk, running().copy(runningType = null)))
        assertFalse(isTrustedDiskTestStatus(disk, stopped().copy(runningType = NasDiskTestType.QUICK)))
        assertFalse(isTrustedDiskTestStatus(disk, running().copy(isBusyWithOtherTest = true)))
    }

    @Test
    fun `请求要求完整硬盘和原始状态基线未漂移`() {
        val disk = disk()
        val baseline = stopped()
        val snapshot = snapshot(disk)
        val statuses = mapOf(disk.id to Loadable.Ready(baseline))
        assertTrue(canRequestDiskTestMutation(snapshot, statuses, disk, baseline, NasDiskTestType.QUICK))
        assertFalse(canRequestDiskTestMutation(snapshot, statuses, disk, baseline, null))
        assertTrue(
            canRequestDiskTestMutation(
                snapshot.copy(
                    storageDisks = listOf(
                        disk.copy(temperatureCelsius = 42.0, status = "warning", smartStatus = "warning"),
                    ),
                ),
                statuses,
                disk,
                baseline,
                NasDiskTestType.QUICK,
            ),
        )
        assertFalse(
            canRequestDiskTestMutation(
                snapshot.copy(storageDisks = listOf(disk.copy(deviceId = "changed-device"))),
                statuses,
                disk,
                baseline,
                NasDiskTestType.QUICK,
            ),
        )
        assertFalse(
            canRequestDiskTestMutation(
                snapshot.copy(storageDisks = listOf(disk.copy(supportsSmartTest = false))),
                statuses,
                disk,
                baseline,
                NasDiskTestType.QUICK,
            ),
        )
        assertFalse(
            canRequestDiskTestMutation(
                snapshot,
                mapOf(disk.id to Loadable.Ready(baseline.copy(lastResult = "changed"))),
                disk,
                baseline,
                NasDiskTestType.QUICK,
            ),
        )
        assertTrue(
            canRequestDiskTestMutation(snapshot, mapOf(disk.id to Loadable.Ready(running())), disk, running(), null),
        )
    }

    @Test
    fun `启动成功必须匹配具体类型且停止必须是明确非运行状态`() {
        val disk = disk()
        assertTrue(diskTestMutationTargetReached(disk, running(), NasDiskTestType.QUICK))
        assertFalse(
            diskTestMutationTargetReached(
                disk,
                running().copy(runningType = NasDiskTestType.EXTENDED),
                NasDiskTestType.QUICK,
            ),
        )
        assertTrue(diskTestMutationTargetReached(disk, stopped(), null))
        assertFalse(diskTestMutationTargetReached(disk, stopped().copy(isBusyWithOtherTest = true), null))
        assertFalse(diskTestMutationTargetReached(disk, running().copy(runningType = null), null))
    }

    @Test
    fun `专项刷新以活动状态为准并保留同硬盘既有历史`() {
        val previous = stopped().copy(
            lastQuickTest = "quick-history",
            lastExtendedTest = "extended-history",
            lastResult = "normal",
            isHistoryAvailable = true,
        )
        val active = running().copy(
            progressDescription = "active-progress",
            isHistoryAvailable = false,
        )
        val merged = mergeDiskTestStatusHistory(active, previous)
        assertTrue(merged.isRunning)
        assertEquals(NasDiskTestType.QUICK, merged.runningType)
        assertEquals("active-progress", merged.progressDescription)
        assertEquals("quick-history", merged.lastQuickTest)
        assertEquals("extended-history", merged.lastExtendedTest)
        assertEquals("normal", merged.lastResult)
        assertTrue(merged.isHistoryAvailable)

        val authoritativeHistory = active.copy(lastResult = "new", isHistoryAvailable = true)
        assertEquals(authoritativeHistory, mergeDiskTestStatusHistory(authoritativeHistory, previous))
        assertEquals(active, mergeDiskTestStatusHistory(active, previous.copy(diskId = "other")))
    }

    @Test
    fun `确认成功回退只接受严格相同硬盘和状态基线`() {
        val disk = disk()
        val baseline = stopped()
        val statuses = mapOf(disk.id to Loadable.Ready(baseline))
        val started = confirmedDiskTestMutationFallback(
            snapshot(disk), statuses, disk, baseline, NasDiskTestType.EXTENDED,
        )
        assertEquals(
            NasDiskTestType.EXTENDED,
            ((started?.get(disk.id) as? Loadable.Ready)?.value as? NasDiskTestStatus)?.runningType,
        )
        assertEquals(
            NasDiskTestType.QUICK,
            confirmedDiskTestMutationFallback(
                snapshot(disk.copy(temperatureCelsius = 41.0)),
                statuses,
                disk,
                baseline,
                NasDiskTestType.QUICK,
            )?.let { ((it[disk.id] as? Loadable.Ready)?.value as? NasDiskTestStatus)?.runningType },
        )
        assertNull(
            confirmedDiskTestMutationFallback(
                snapshot(disk.copy(deviceId = "changed-device")),
                statuses,
                disk,
                baseline,
                NasDiskTestType.QUICK,
            ),
        )
        assertNull(
            confirmedDiskTestMutationFallback(
                snapshot(disk),
                mapOf(disk.id to Loadable.Ready(baseline.copy(lastResult = "changed"))),
                disk,
                baseline,
                NasDiskTestType.QUICK,
            ),
        )
    }

    @Test
    fun `确认成功缺少可信目标状态时降级为提交未核对`() {
        val success = MutationResult(
            schemaVersion = 1,
            status = MutationResultStatus.CONFIRMED_SUCCESS,
            operation = "diskTestStart",
            submitted = true,
            requiresRefresh = false,
            counts = MutationResultCounts(1, 0, 0),
        )
        assertEquals(success, diskTestMutationResultAfterStateCheck(success, true))
        val unverified = diskTestMutationResultAfterStateCheck(success, false)
        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, unverified.status)
        assertTrue(unverified.requiresRefresh)
        assertEquals(MutationResultCounts(0, 0, 1), unverified.counts)
    }

    @Test
    fun `旧Repository NAS或任一代次的迟到回调必须被拒绝`() {
        assertTrue(scopedMutationCallbackMatches(true, true, 11, 11, 11))
        assertFalse(scopedMutationCallbackMatches(false, true, 11, 11, 11))
        assertFalse(scopedMutationCallbackMatches(true, false, 11, 11, 11))
        assertFalse(scopedMutationCallbackMatches(true, true, 10, 11, 11))
        assertFalse(scopedMutationCallbackMatches(true, true, 11, 11, 12))
        val disk = disk()
        assertTrue(diskTestStatusLoadCallbackMatches(true, true, 11, 11, 21, 21, disk, disk))
        assertFalse(diskTestStatusLoadCallbackMatches(false, true, 11, 11, 21, 21, disk, disk))
        assertFalse(diskTestStatusLoadCallbackMatches(true, false, 11, 11, 21, 21, disk, disk))
        assertFalse(diskTestStatusLoadCallbackMatches(true, true, 11, 12, 21, 21, disk, disk))
        assertFalse(diskTestStatusLoadCallbackMatches(true, true, 11, 11, 21, 22, disk, disk))
        assertTrue(
            diskTestStatusLoadCallbackMatches(
                true,
                true,
                11,
                11,
                21,
                21,
                disk,
                disk.copy(temperatureCelsius = 44.0, status = "warning", smartStatus = "warning"),
            ),
        )
        assertFalse(
            diskTestStatusLoadCallbackMatches(
                true,
                true,
                11,
                11,
                21,
                21,
                disk,
                disk.copy(deviceId = "changed-device"),
            ),
        )
        assertFalse(
            diskTestStatusLoadCallbackMatches(
                true,
                true,
                11,
                11,
                21,
                21,
                disk,
                disk.copy(supportsSmartTest = false),
            ),
        )
    }

    @Test
    fun `NAS设置刷新会清除失效加载且仅保留稳定身份相同的硬盘状态`() {
        val original = disk()
        val other = original.copy(id = "other-id", deviceId = "other-device", name = "Disk 2")
        val statuses = mapOf(
            original.id to Loadable.Ready(stopped()),
            other.id to Loadable.Failed(DsmFailure(null, "synthetic", "retry")),
            "pending-id" to Loadable.Loading,
        )
        assertEquals(
            setOf(original.id, other.id),
            diskTestStatusesWithoutPendingLoads(statuses).keys,
        )

        val previous = snapshot(original).copy(storageDisks = listOf(original, other))
        val unchanged = snapshot(original).copy(storageDisks = listOf(original, other))
        assertEquals(
            setOf(original.id, other.id),
            reconciledDiskTestStatusesAfterSettingsRefresh(previous, unchanged, statuses).keys,
        )

        val replacedDevice = original.copy(deviceId = "replacement-device")
        assertFalse(
            reconciledDiskTestStatusesAfterSettingsRefresh(
                previous,
                snapshot(replacedDevice).copy(storageDisks = listOf(replacedDevice, other)),
                statuses,
            ).containsKey(original.id),
        )
        val changedCapability = original.copy(supportsSmartTest = false)
        assertFalse(
            reconciledDiskTestStatusesAfterSettingsRefresh(
                previous,
                snapshot(changedCapability).copy(storageDisks = listOf(changedCapability, other)),
                statuses,
            ).containsKey(original.id),
        )
        assertTrue(
            reconciledDiskTestStatusesAfterSettingsRefresh(null, unchanged, statuses).isEmpty(),
        )
    }

    @Test
    fun `SMART危险结果和刷新状态纳入切换与退出门禁`() {
        val profile = NasProfile("profile", "NAS", "nas.example", "user")
        val dangerous = MutationResult(
            schemaVersion = 1,
            status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            operation = "diskTestStart",
            submitted = true,
            requiresRefresh = true,
            counts = MutationResultCounts(0, 0, 1),
        )
        assertTrue(
            WorkspaceState(profile = profile, diskTestMutationInProgress = true)
                .hasBlockingStructuredNasMutation(),
        )
        assertTrue(
            WorkspaceState(profile = profile, diskTestMutationRefreshInProgress = true)
                .hasBlockingStructuredNasMutation(),
        )
        assertTrue(
            WorkspaceState(profile = profile, diskTestMutationResult = dangerous)
                .hasBlockingStructuredNasMutation(),
        )
        assertFalse(
            WorkspaceState(
                profile = profile,
                diskTestMutationResult = dangerous,
                diskTestMutationRefreshCompleted = true,
            ).hasBlockingStructuredNasMutation(),
        )
    }

    private fun disk() = NasStorageDisk(
        id = "disk-id",
        deviceId = "device-id",
        name = "Disk 1",
        model = "Synthetic",
        status = "normal",
        smartStatus = "normal",
        temperatureCelsius = 30.0,
        supportsSmartTest = true,
    )

    private fun stopped() = NasDiskTestStatus(
        diskId = "disk-id",
        isRunning = false,
        isBusyWithOtherTest = false,
        runningType = null,
        progressDescription = null,
        lastQuickTest = null,
        lastExtendedTest = null,
        lastResult = null,
        isHistoryAvailable = true,
    )

    private fun running() = stopped().copy(
        isRunning = true,
        runningType = NasDiskTestType.QUICK,
    )

    private fun snapshot(disk: NasStorageDisk) = NasSettingsSnapshot(
        system = null,
        volumes = emptyList(), pools = emptyList(), disks = emptyList(), storageDisks = listOf(disk),
        packages = emptyList(), scheduledTasks = emptyList(), accounts = emptyList(), groups = emptyList(),
        logs = emptyList(), connections = emptyList(), connectionsAvailable = true,
        networkInterfaces = emptyList(), networkInterfacesAvailable = true,
        ddnsDirectory = null, ddnsDirectoryAvailable = true, fileServiceSettings = null,
        terminalSettings = null, proxySettings = null, regionSettings = null,
        securitySettings = null, hardwareSettings = null, security = emptyList(),
    )
}
