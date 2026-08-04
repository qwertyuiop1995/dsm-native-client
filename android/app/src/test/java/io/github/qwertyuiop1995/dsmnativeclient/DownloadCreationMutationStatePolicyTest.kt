package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadCreationMutationStatePolicyTest {
    @Test
    fun `同步claim要求工作区与创建状态全部空闲`() {
        val clean = DownloadCreationWorkspaceState()
        assertTrue(canStartDownloadCreation(workspaceBusy = false, state = clean))
        assertFalse(canStartDownloadCreation(workspaceBusy = true, state = clean))
        assertFalse(canStartDownloadCreation(false, clean.copy(target = target())))
        assertFalse(canStartDownloadCreation(false, clean.copy(mutationInProgress = true)))
        assertFalse(canStartDownloadCreation(false, clean.copy(mutationRefreshInProgress = true)))
        assertFalse(
            canStartDownloadCreation(
                false,
                clean.copy(mutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS)),
            ),
        )
        assertFalse(
            canStartDownloadCreation(
                false,
                clean.copy(mutationFailure = failure()),
            ),
        )
    }

    @Test
    fun `八类原始结果与计数在状态中保持且仅危险结果要求专项刷新`() {
        MutationResultStatus.entries.forEachIndexed { index, status ->
            val result = result(status)
            val state = DownloadCreationWorkspaceState(
                target = target(),
                mutationResult = result,
                mutationGeneration = index.toLong(),
            )
            val requiresRefresh = status in setOf(
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            )

            assertSame(status.name, result, state.mutationResult)
            assertEquals(status.name, result.counts, state.mutationResult?.counts)
            assertEquals(
                status.name,
                requiresRefresh,
                downloadCreationRequiresRefreshBeforeDismiss(state),
            )
        }
    }

    @Test
    fun `未知计数与异常即使没有显式刷新标记也保持刷新门禁`() {
        val unknown = result(MutationResultStatus.CONFIRMED_FAILURE).copy(
            counts = MutationResultCounts(succeeded = 0, failed = 0, unknown = 1),
        )
        assertTrue(
            downloadCreationRequiresRefreshBeforeDismiss(
                DownloadCreationWorkspaceState(target = target(), mutationResult = unknown),
            ),
        )
        assertTrue(
            downloadCreationRequiresRefreshBeforeDismiss(
                DownloadCreationWorkspaceState(target = target(), mutationFailure = failure()),
            ),
        )
    }

    @Test
    fun `旧Repository旧NAS旧目标及任一代次漂移均拒绝回调`() {
        val currentTarget = target()
        assertTrue(downloadCreationCallbackMatches(true, true, currentTarget, currentTarget, 7, 7, 7))
        assertFalse(downloadCreationCallbackMatches(false, true, currentTarget, currentTarget, 7, 7, 7))
        assertFalse(downloadCreationCallbackMatches(true, false, currentTarget, currentTarget, 7, 7, 7))
        assertFalse(downloadCreationCallbackMatches(true, true, null, currentTarget, 7, 7, 7))
        assertFalse(
            downloadCreationCallbackMatches(
                true,
                true,
                currentTarget,
                target(sourceIdentity = "https://example.invalid/other"),
                7,
                7,
                7,
            ),
        )
        assertFalse(downloadCreationCallbackMatches(true, true, currentTarget, currentTarget, 6, 7, 7))
        assertFalse(downloadCreationCallbackMatches(true, true, currentTarget, currentTarget, 7, 6, 7))
        assertFalse(downloadCreationCallbackMatches(true, true, currentTarget, currentTarget, 7, 7, 8))
    }

    @Test
    fun `创建目标只保存稳定摘要且不泄露原始URI`() {
        val secretSource = "magnet:?xt=urn:btih:private-value&dn=private-name"
        val first = target(
            sourceKind = DownloadCreationSourceKind.MAGNET,
            sourceIdentity = secretSource,
        )
        val same = target(
            sourceKind = DownloadCreationSourceKind.MAGNET,
            sourceIdentity = secretSource,
        )
        val changed = target(
            sourceKind = DownloadCreationSourceKind.MAGNET,
            sourceIdentity = "$secretSource-other",
        )

        assertEquals(first, same)
        assertEquals(64, first.requestFingerprint.length)
        assertTrue(first.requestFingerprint.all { it in "0123456789abcdef" })
        assertNotEquals(first.requestFingerprint, changed.requestFingerprint)
        assertFalse(first.requestFingerprint.contains(secretSource))
        assertFalse(first.toString().contains(secretSource))
    }

    @Test
    fun `不同来源类型与目标目录产生不同摘要`() {
        val source = "https://example.invalid/task"
        val link = target(DownloadCreationSourceKind.LINK, source, "downloads")
        val rss = target(DownloadCreationSourceKind.RSS, source, "downloads")
        val otherDestination = target(DownloadCreationSourceKind.LINK, source, "other")

        assertNotEquals(link.requestFingerprint, rss.requestFingerprint)
        assertNotEquals(link.requestFingerprint, otherDestination.requestFingerprint)
    }

    @Test
    fun `launch外层取消保守记录已提交未知且不重放`() {
        DownloadCreationSourceKind.entries.forEach { sourceKind ->
            val target = target(sourceKind = sourceKind)
            val result = cancelledDownloadCreationResult(target)

            assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result.status)
            assertEquals(
                if (sourceKind == DownloadCreationSourceKind.TASK_FILE) {
                    "downloadFileCreate"
                } else {
                    "downloadCreate"
                },
                result.operation,
            )
            assertTrue(result.submitted)
            assertTrue(result.requiresRefresh)
            assertEquals(MutationResultCounts(0, 0, 1), result.counts)
            assertEquals(MutationErrorCategory.UNKNOWN, result.errorCategory)
        }
    }

    @Test
    fun `未知结果在可信刷新前阻止关闭与退出`() {
        val state = DownloadCreationWorkspaceState(
            target = target(),
            mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
        )

        assertTrue(downloadCreationRequiresRefreshBeforeDismiss(state))
        assertTrue(downloadCreationBlocksWorkspaceExit(state))
        assertFalse(canDismissDownloadCreationMutation(state))
    }

    @Test
    fun `可信刷新后允许明确关闭但退出仍等待用户核对`() {
        val state = DownloadCreationWorkspaceState(
            target = target(),
            mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
            mutationRefreshCompleted = true,
        )

        assertTrue(downloadCreationRequiresRefreshBeforeDismiss(state))
        assertTrue(downloadCreationBlocksWorkspaceExit(state))
        assertTrue(canDismissDownloadCreationMutation(state))
    }

    @Test
    fun `明确未提交结果无需刷新即可关闭`() {
        val state = DownloadCreationWorkspaceState(
            target = target(),
            mutationResult = result(MutationResultStatus.CONFIRMED_FAILURE),
        )

        assertFalse(downloadCreationRequiresRefreshBeforeDismiss(state))
        assertFalse(downloadCreationBlocksWorkspaceExit(state))
        assertTrue(canDismissDownloadCreationMutation(state))
    }

    @Test
    fun `写入与专项刷新进行中始终阻止关闭与退出`() {
        val writing = DownloadCreationWorkspaceState(target = target(), mutationInProgress = true)
        val refreshing = DownloadCreationWorkspaceState(
            target = target(),
            mutationRefreshInProgress = true,
            mutationRefreshCompleted = true,
        )

        assertTrue(downloadCreationBlocksWorkspaceExit(writing))
        assertFalse(canDismissDownloadCreationMutation(writing))
        assertTrue(downloadCreationBlocksWorkspaceExit(refreshing))
        assertFalse(canDismissDownloadCreationMutation(refreshing))
    }

    private fun target(
        sourceKind: DownloadCreationSourceKind = DownloadCreationSourceKind.LINK,
        sourceIdentity: String = "https://example.invalid/task",
        destination: String? = "downloads",
    ) = downloadCreationTarget(
        profileId = "profile-a",
        sourceKind = sourceKind,
        sourceIdentity = sourceIdentity,
        destination = destination,
    )

    private fun failure() = DsmFailure(
        code = null,
        message = "Synthetic failure",
        recovery = "Refresh before trying again.",
    )

    private fun result(status: MutationResultStatus): MutationResult {
        val submitted = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            MutationResultStatus.CONFIRMED_FAILURE,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            -> MutationResultCounts(0, 1, 0)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "downloadCreate",
            submitted = submitted,
            requiresRefresh = status in setOf(
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ),
            counts = counts,
            errorCategory = when (status) {
                MutationResultStatus.PERMISSION_DENIED -> MutationErrorCategory.PERMISSION
                MutationResultStatus.UNSUPPORTED -> MutationErrorCategory.UNSUPPORTED
                MutationResultStatus.CONFIRMED_FAILURE -> MutationErrorCategory.VALIDATION
                else -> null
            },
        )
    }
}
