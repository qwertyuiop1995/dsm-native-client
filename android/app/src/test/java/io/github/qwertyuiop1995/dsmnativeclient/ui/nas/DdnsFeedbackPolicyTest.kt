package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.DdnsMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class DdnsFeedbackPolicyTest {
    @Test
    fun `四类操作完整覆盖八种持久结果`() {
        DdnsMutationOperation.entries.forEach { operation ->
            MutationResultStatus.entries.forEach { status ->
                val policy = ddnsFeedbackPolicy(operation, result(operation, status))
                assertEquals(status != MutationResultStatus.CONFIRMED_SUCCESS, policy.isAssertive)
                if (operation == DdnsMutationOperation.TEST) {
                    assertFalse(policy.canRefresh)
                    assertFalse(policy.mustRefreshBeforeDismiss)
                } else if (status in refreshRequiredStatuses) {
                    assertTrue(policy.canRefresh)
                    assertTrue(policy.mustRefreshBeforeDismiss)
                }
            }
        }
    }

    @Test
    fun `测试成功与保存成功使用不同文案且测试明确不要求刷新`() {
        val test = ddnsFeedbackPolicy(
            DdnsMutationOperation.TEST,
            result(DdnsMutationOperation.TEST, MutationResultStatus.CONFIRMED_SUCCESS),
        )
        val save = ddnsFeedbackPolicy(
            DdnsMutationOperation.SAVE,
            result(DdnsMutationOperation.SAVE, MutationResultStatus.CONFIRMED_SUCCESS),
        )

        assertEquals(R.string.ddns_test_succeeded, test.message)
        assertEquals(R.string.ddns_record_saved, save.message)
        assertNotEquals(test.title, save.title)
        assertNotEquals(test.message, save.message)
        assertFalse(test.canRefresh)
    }

    @Test
    fun `冲突按已提交状态门禁刷新且错误operation被拒绝`() {
        val conflict = result(
            DdnsMutationOperation.DELETE,
            MutationResultStatus.CONFIRMED_FAILURE,
        ).copy(submitted = false, requiresRefresh = false, errorCategory = MutationErrorCategory.CONFLICT)
        val policy = ddnsFeedbackPolicy(DdnsMutationOperation.DELETE, conflict)
        assertTrue(policy.canRefresh)
        assertTrue(policy.mustRefreshBeforeDismiss)

        assertThrows(IllegalArgumentException::class.java) {
            ddnsFeedbackPolicy(
                DdnsMutationOperation.TEST,
                result(DdnsMutationOperation.SAVE, MutationResultStatus.CONFIRMED_SUCCESS),
            )
        }
    }

    private fun result(
        operation: DdnsMutationOperation,
        status: MutationResultStatus,
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = ddnsOperationKey(operation),
        submitted = status != MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
        requiresRefresh = status in refreshRequiredStatuses,
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            else -> MutationResultCounts(0, 1, 0)
        },
    )

    private val refreshRequiredStatuses = setOf(
        MutationResultStatus.PARTIAL_SUCCESS,
        MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
        MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
    )
}
