package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadRssFeed
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadRssSite
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadRssMutationStatePolicyTest {
    @Test
    fun `目标绑定profile与规范站点ID`() {
        assertEquals("site-1", DownloadRssRefreshTarget("profile-a", "site-1").siteId)
        assertThrows(IllegalArgumentException::class.java) { DownloadRssRefreshTarget("", "site-1") }
        assertThrows(IllegalArgumentException::class.java) { DownloadRssRefreshTarget("profile-a", " site-1 ") }
    }

    @Test
    fun `回调必须同时匹配Repository模块profile站点目标与两层代次`() {
        val target = target()
        assertTrue(callback(target = target))
        assertFalse(callback(target = target, repositoryMatches = false))
        assertFalse(callback(target = target, profileMatches = false))
        assertFalse(callback(target = target, selectedModule = Module.FILES))
        assertFalse(callback(target = target, selectedSiteId = "site-2"))
        assertFalse(callback(target = target, stateTarget = target.copy(siteId = "site-2")))
        assertFalse(callback(target = target, stateGeneration = 6))
        assertFalse(callback(target = target, callbackGeneration = 6))
        assertFalse(callback(target = target, globalGeneration = 8))
    }

    @Test
    fun `站点与条目回读严格区分四种验证状态`() {
        val target = target(baselineUpdatedAt = 1L)
        val site = site()
        assertEquals(
            DownloadRssRefreshVerification.MATCHES,
            downloadRssRefreshVerification(target, listOf(site.copy(lastUpdatedAtEpochSeconds = 2L)), listOf(feed())),
        )
        assertEquals(
            DownloadRssRefreshVerification.DIFFERS,
            downloadRssRefreshVerification(target, listOf(site, site.copy(title = "重复")), emptyList()),
        )
        assertEquals(
            DownloadRssRefreshVerification.DISAPPEARED,
            downloadRssRefreshVerification(target, listOf(site.copy(id = "site-2")), emptyList()),
        )
        assertEquals(
            DownloadRssRefreshVerification.UNAVAILABLE,
            downloadRssRefreshVerification(target, null, null),
        )
        assertEquals(
            DownloadRssRefreshVerification.UNAVAILABLE,
            downloadRssRefreshVerification(target, listOf(site), null),
        )
        assertEquals(
            DownloadRssRefreshVerification.UNAVAILABLE,
            downloadRssRefreshVerification(
                target,
                listOf(site.copy(isUpdating = true, lastUpdatedAtEpochSeconds = 2L)),
                listOf(feed()),
            ),
        )
        assertEquals(
            DownloadRssRefreshVerification.DIFFERS,
            downloadRssRefreshVerification(target, listOf(site), listOf(feed())),
        )
    }

    @Test
    fun `已提交未知结果与异常都要求只读回读`() {
        val unknown = state(result = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED))
        assertTrue(downloadRssRefreshRequiresReadback(unknown))
        assertTrue(downloadRssRefreshRequiresReadback(state(failure = failure())))
        assertFalse(
            downloadRssRefreshRequiresReadback(
                state(result = result(MutationResultStatus.CONFIRMED_FAILURE)),
            ),
        )
    }

    @Test
    fun `提交前取消形成可关闭终态且不要求回读`() {
        val cancelled = cancelledDownloadRssRefreshResult()

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, cancelled.status)
        assertFalse(cancelled.submitted)
        assertFalse(cancelled.requiresRefresh)
        assertEquals(0, cancelled.counts.unknown)
        val cancelledState = state(result = cancelled)
        assertFalse(downloadRssRefreshRequiresReadback(cancelledState))
        assertFalse(downloadRssRefreshBlocksWorkspaceExit(cancelledState))
        assertTrue(canDismissDownloadRssRefreshMutation(cancelledState))
    }

    @Test
    fun `写入或尚未核对时阻止离开工作区`() {
        assertTrue(downloadRssRefreshBlocksWorkspaceExit(state(inProgress = true)))
        assertTrue(downloadRssRefreshBlocksWorkspaceExit(state(refreshInProgress = true)))
        val unknown = state(result = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED))
        assertTrue(downloadRssRefreshBlocksWorkspaceExit(unknown))
        assertFalse(downloadRssRefreshBlocksWorkspaceExit(unknown.copy(mutationRefreshCompleted = true)))
    }

    @Test
    fun `仅安全终态允许明确关闭`() {
        val unknown = state(result = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED))
        assertFalse(canDismissDownloadRssRefreshMutation(unknown))
        assertFalse(
            canDismissDownloadRssRefreshMutation(
                unknown.copy(
                    mutationRefreshCompleted = true,
                    mutationVerification = DownloadRssRefreshVerification.UNAVAILABLE,
                ),
            ),
        )
        assertFalse(
            canDismissDownloadRssRefreshMutation(
                unknown.copy(
                    mutationRefreshFailure = failure(),
                    mutationVerification = DownloadRssRefreshVerification.MATCHES,
                ),
            ),
        )
        assertTrue(
            canDismissDownloadRssRefreshMutation(
                unknown.copy(
                    mutationRefreshCompleted = true,
                    mutationVerification = DownloadRssRefreshVerification.DISAPPEARED,
                ),
            ),
        )
        assertTrue(
            canDismissDownloadRssRefreshMutation(
                state(result = result(MutationResultStatus.CONFIRMED_FAILURE)),
            ),
        )
    }

    private fun callback(
        target: DownloadRssRefreshTarget,
        repositoryMatches: Boolean = true,
        profileMatches: Boolean = true,
        selectedModule: Module = Module.DOWNLOADS,
        selectedSiteId: String? = target.siteId,
        stateTarget: DownloadRssRefreshTarget? = target,
        stateGeneration: Long = 7,
        callbackGeneration: Long = 7,
        globalGeneration: Long = 7,
    ) = downloadRssRefreshCallbackMatches(
        repositoryMatches,
        profileMatches,
        selectedModule,
        selectedSiteId,
        stateTarget,
        target,
        stateGeneration,
        callbackGeneration,
        globalGeneration,
    )

    private fun state(
        result: MutationResult? = null,
        failure: DsmFailure? = null,
        inProgress: Boolean = false,
        refreshInProgress: Boolean = false,
    ) = DownloadRssRefreshWorkspaceState(
        target = target(),
        mutationInProgress = inProgress,
        mutationResult = result,
        mutationFailure = failure,
        mutationRefreshInProgress = refreshInProgress,
    )

    private fun target(baselineUpdatedAt: Long? = null) = DownloadRssRefreshTarget(
        "profile-a",
        "site-1",
        baselineUpdatedAt,
    )

    private fun site() = DownloadRssSite("site-1", "站点", false, 1L)

    private fun feed() = DownloadRssFeed("条目", 1L, 1L, "https://example.invalid/item", null)

    private fun failure() = DsmFailure(null, "Synthetic RSS failure", "Read the site again.")

    private fun result(status: MutationResultStatus): MutationResult {
        val submitted = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "downloadRssRefresh",
            submitted = submitted,
            requiresRefresh = status in setOf(
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ),
            counts = when (status) {
                MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
                MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                -> MutationResultCounts(0, 0, 1)
                MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
                else -> MutationResultCounts(0, 1, 0)
            },
        )
    }
}
