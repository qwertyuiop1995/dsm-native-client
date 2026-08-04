package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasRemoteAccessSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteAccessSettingsStatePolicyTest {
    @Test
    fun `编辑只接受当前可管理的可信canonical`() {
        val value = settings()
        assertTrue(canRequestRemoteAccessEditing(snapshot(value), value))
        assertFalse(canRequestRemoteAccessEditing(snapshot(value, available = false), value))
        assertFalse(canRequestRemoteAccessEditing(snapshot(value), value.copy(isRelayEnabled = false)))
        assertFalse(canRequestRemoteAccessEditing(snapshot(value.copy(canManage = false)), value.copy(canManage = false)))
    }

    @Test
    fun `没有可编辑能力时拒绝进入编辑`() {
        val value = settings(relay = null, router = null)
        assertFalse(canRequestRemoteAccessEditing(snapshot(value), value))
    }

    @Test
    fun `草稿不能改变空能力连接类别或管理门禁`() {
        val baseline = settings(relay = null)
        assertNull(normalizedRemoteAccessSettingsDraft(baseline, baseline.copy(isRelayEnabled = true)))
        assertNull(normalizedRemoteAccessSettingsDraft(baseline, baseline.copy(isConnectedThroughTrustedRelay = true)))
        assertNull(normalizedRemoteAccessSettingsDraft(baseline, baseline.copy(canManage = false)))
        assertEquals(
            baseline.copy(isRouterConfigurationEnabled = true),
            normalizedRemoteAccessSettingsDraft(
                baseline,
                baseline.copy(isRouterConfigurationEnabled = true),
            ),
        )
    }

    @Test
    fun `无变化草稿不能请求确认`() {
        val baseline = settings()
        assertFalse(canRequestRemoteAccessConfirmation(snapshot(baseline), baseline, baseline))
    }

    @Test
    fun `当前可信中继连接不能请求关闭中继`() {
        val baseline = settings(relay = true, trustedRelay = true)
        assertFalse(
            canRequestRemoteAccessConfirmation(
                snapshot(baseline), baseline, baseline.copy(isRelayEnabled = false),
            ),
        )
    }

    @Test
    fun `当前canonical未漂移时允许修改可写字段`() {
        val baseline = settings()
        val draft = baseline.copy(isRelayEnabled = false, isRouterConfigurationEnabled = true)
        assertTrue(canRequestRemoteAccessConfirmation(snapshot(baseline), baseline, draft))
        assertFalse(
            canRequestRemoteAccessConfirmation(
                snapshot(baseline.copy(isRouterConfigurationEnabled = true)), baseline, draft,
            ),
        )
    }

    @Test
    fun `目标确认精确核对两项可写状态`() {
        val baseline = settings()
        val expected = settings(relay = false, router = true)
        assertTrue(remoteAccessMutationTargetReached(baseline, expected, expected))
        assertFalse(remoteAccessMutationTargetReached(
            baseline, expected.copy(isRelayEnabled = true), expected,
        ))
        assertFalse(
            remoteAccessMutationTargetReached(
                baseline, expected.copy(isRouterConfigurationEnabled = false), expected,
            ),
        )
    }

    @Test
    fun `专项刷新只要求本次变更字段为明确布尔`() {
        val baseline = settings(relay = true, router = false)
        val relayOnly = baseline.copy(isRelayEnabled = false)
        assertTrue(
            remoteAccessMutationRefreshIsComplete(
                baseline,
                relayOnly,
                relayOnly.copy(isRouterConfigurationEnabled = null),
            ),
        )
        assertTrue(
            remoteAccessMutationTargetReached(
                baseline,
                relayOnly.copy(isRouterConfigurationEnabled = null),
                relayOnly,
            ),
        )
    }

    @Test
    fun `任一受影响字段为空时专项刷新保持未完成`() {
        val baseline = settings(relay = true, router = false)
        assertFalse(
            remoteAccessMutationRefreshIsComplete(
                baseline,
                baseline.copy(isRelayEnabled = false),
                settings(relay = null, router = false),
            ),
        )
        assertFalse(
            remoteAccessMutationRefreshIsComplete(
                baseline,
                baseline.copy(isRouterConfigurationEnabled = true),
                settings(relay = true, router = null),
            ),
        )
        assertFalse(remoteAccessMutationRefreshIsComplete(baseline, baseline, baseline))
    }

    @Test
    fun `canonical漂移或不可用可在确认前预判`() {
        val baseline = settings()
        assertFalse(remoteAccessCanonicalHasDrifted(snapshot(baseline), baseline))
        assertTrue(
            remoteAccessCanonicalHasDrifted(
                snapshot(baseline.copy(isRouterConfigurationEnabled = true)), baseline,
            ),
        )
        assertTrue(remoteAccessCanonicalHasDrifted(snapshot(baseline, available = false), baseline))
    }

    @Test
    fun `确认成功fallback只接受严格未漂移缓存`() {
        val baseline = settings()
        val expected = baseline.copy(isRouterConfigurationEnabled = true)
        assertEquals(expected, confirmedRemoteAccessSettingsFallback(
            snapshot(baseline), baseline, expected,
        )?.remoteAccessSettings)
        assertNull(
            confirmedRemoteAccessSettingsFallback(
                snapshot(baseline.copy(isRelayEnabled = false)), baseline, expected,
            ),
        )
        assertNull(
            confirmedRemoteAccessSettingsFallback(
                snapshot(baseline, available = false), baseline, expected,
            ),
        )
    }

    @Test
    fun `继续编辑按最新能力重基且不保留禁止关闭的中继草稿`() {
        val oldDraft = settings(relay = false, router = true)
        val latest = settings(relay = true, router = null, trustedRelay = true)
        val rebased = rebasedRemoteAccessSettingsDraft(snapshot(latest), oldDraft)
        assertEquals(latest, rebased?.first)
        assertEquals(true, rebased?.second?.isRelayEnabled)
        assertNull(rebased?.second?.isRouterConfigurationEnabled)
        assertNull(
            rebasedRemoteAccessSettingsDraft(
                snapshot(latest.copy(canManage = false)), oldDraft,
            ),
        )
    }

    @Test
    fun `Repository NAS局部或全局代次漂移均拒绝回调`() {
        assertTrue(remoteAccessCallbackMatches(true, true, 7, 7, 7))
        assertFalse(remoteAccessCallbackMatches(false, true, 7, 7, 7))
        assertFalse(remoteAccessCallbackMatches(true, false, 7, 7, 7))
        assertFalse(remoteAccessCallbackMatches(true, true, 6, 7, 7))
        assertFalse(remoteAccessCallbackMatches(true, true, 7, 7, 8))
    }

    @Test
    fun `确认成功缺少目标读回时降级为提交未核对`() {
        val success = result(MutationResultStatus.CONFIRMED_SUCCESS, submitted = true)
        assertEquals(success, remoteAccessMutationResultAfterStateCheck(success, true))
        val downgraded = remoteAccessMutationResultAfterStateCheck(success, false)
        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, downgraded.status)
        assertTrue(downgraded.requiresRefresh)
        assertEquals(MutationResultCounts(0, 0, 1), downgraded.counts)
        val twoTargets = success.copy(counts = MutationResultCounts(2, 0, 0))
        assertEquals(
            MutationResultCounts(0, 0, 2),
            remoteAccessMutationResultAfterStateCheck(twoTargets, false).counts,
        )
    }

    @Test
    fun `八类结果遵循统一专项刷新门禁`() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to false,
            MutationResultStatus.PARTIAL_SUCCESS to true,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to true,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to true,
            MutationResultStatus.PERMISSION_DENIED to false,
            MutationResultStatus.UNSUPPORTED to false,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to false,
            MutationResultStatus.CONFIRMED_FAILURE to false,
        )
        expected.forEach { (status, requiresRefresh) ->
            assertEquals(
                status.name,
                requiresRefresh,
                structuredSettingsMutationRequiresRefreshBeforeDismiss(result(status)),
            )
        }
        assertTrue(
            structuredSettingsMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.PERMISSION_DENIED, submitted = true),
            ),
        )
        assertTrue(
            structuredSettingsMutationRequiresRefreshBeforeDismiss(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    errorCategory = MutationErrorCategory.CONFLICT,
                ),
            ),
        )
    }

    @Test
    fun `远程访问进行中异常与危险结果纳入退出门禁`() {
        val profile = NasProfile("profile", "NAS", "nas.example", "user")
        val dangerous = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, submitted = true)
        assertTrue(
            WorkspaceState(
                profile,
                remoteAccessState = RemoteAccessWorkspaceState(mutationInProgress = true),
            )
                .hasBlockingStructuredNasMutation(),
        )
        assertTrue(
            WorkspaceState(
                profile,
                remoteAccessState = RemoteAccessWorkspaceState(mutationRefreshInProgress = true),
            )
                .hasBlockingStructuredNasMutation(),
        )
        assertTrue(
            WorkspaceState(
                profile,
                remoteAccessState = RemoteAccessWorkspaceState(mutationResult = dangerous),
            )
                .hasBlockingStructuredNasMutation(),
        )
        assertTrue(
            WorkspaceState(
                profile,
                remoteAccessState = RemoteAccessWorkspaceState(
                    mutationFailure = DsmFailure(null, "failed", "retry"),
                ),
            ).hasBlockingStructuredNasMutation(),
        )
        assertTrue(
            WorkspaceState(
                profile,
                remoteAccessState = RemoteAccessWorkspaceState(
                    mutationRefreshFailure = DsmFailure(null, "failed", "retry"),
                ),
            ).hasBlockingStructuredNasMutation(),
        )
        assertFalse(
            WorkspaceState(
                profile,
                remoteAccessState = RemoteAccessWorkspaceState(
                    mutationResult = dangerous,
                    mutationRefreshCompleted = true,
                ),
            ).hasBlockingStructuredNasMutation(),
        )
    }

    private fun settings(
        relay: Boolean? = true,
        router: Boolean? = false,
        trustedRelay: Boolean = false,
        canManage: Boolean = true,
    ) = NasRemoteAccessSettings(relay, router, trustedRelay, canManage)

    private fun snapshot(
        settings: NasRemoteAccessSettings?,
        available: Boolean = settings != null,
    ) = NasSettingsSnapshot(
        system = null,
        volumes = emptyList(), pools = emptyList(), disks = emptyList(), storageDisks = emptyList(),
        packages = emptyList(), scheduledTasks = emptyList(), accounts = emptyList(), groups = emptyList(),
        logs = emptyList(), connections = emptyList(), connectionsAvailable = true,
        networkInterfaces = emptyList(), networkInterfacesAvailable = true,
        ddnsDirectory = null, ddnsDirectoryAvailable = true, fileServiceSettings = null,
        terminalSettings = null, proxySettings = null, regionSettings = null,
        securitySettings = null, hardwareSettings = null, security = emptyList(),
        remoteAccessSettings = settings,
        remoteAccessSettingsAvailable = available,
    )

    private fun result(
        status: MutationResultStatus,
        submitted: Boolean = false,
        errorCategory: MutationErrorCategory? = null,
    ): MutationResult {
        val unverified = status in setOf(
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        val effectiveSubmitted = submitted || unverified || status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
        )
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "remoteAccessSave",
            submitted = effectiveSubmitted,
            requiresRefresh = unverified,
            counts = MutationResultCounts(
                succeeded = if (status in setOf(
                        MutationResultStatus.CONFIRMED_SUCCESS,
                        MutationResultStatus.PARTIAL_SUCCESS,
                    )
                ) 1 else 0,
                failed = 0,
                unknown = if (unverified || status == MutationResultStatus.PARTIAL_SUCCESS) 1 else 0,
            ),
            errorCategory = errorCategory,
        )
    }
}
