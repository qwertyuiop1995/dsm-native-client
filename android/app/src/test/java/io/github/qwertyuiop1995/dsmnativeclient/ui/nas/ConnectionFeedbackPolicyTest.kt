package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.connectionMutationRequiresRefreshBeforeDismiss
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectionFeedbackPolicyTest {
    @Test
    fun `连接八类结果均有专属持久反馈策略`() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to Pair(R.string.connection_feedback_disconnected_title, false),
            MutationResultStatus.PARTIAL_SUCCESS to Pair(R.string.connection_feedback_check_title, true),
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to Pair(R.string.connection_feedback_check_title, true),
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to
                Pair(R.string.connection_feedback_check_title, true),
            MutationResultStatus.PERMISSION_DENIED to Pair(R.string.connection_feedback_permission_title, false),
            MutationResultStatus.UNSUPPORTED to Pair(R.string.connection_feedback_unavailable_title, false),
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to
                Pair(R.string.connection_feedback_cancelled_title, false),
            MutationResultStatus.CONFIRMED_FAILURE to Pair(R.string.connection_feedback_failed_title, false),
        )

        expected.forEach { (status, expectation) ->
            val policy = connectionFeedbackPolicy(result(status))
            assertEquals(expectation.first, policy.title)
            assertEquals(expectation.second, policy.canRefresh)
            assertEquals(expectation.second, policy.mustRefreshBeforeDismiss)
            assertEquals(
                expectation.second,
                connectionMutationRequiresRefreshBeforeDismiss(result(status)),
            )
            assertEquals(
                status !in setOf(
                    MutationResultStatus.CONFIRMED_SUCCESS,
                    MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
                ),
                policy.isAssertive,
            )
        }
    }

    @Test
    fun `冲突或已提交的明确失败必须刷新后才能结束反馈`() {
        val conflict = connectionFeedbackPolicy(
            result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
        )
        assertEquals(R.string.connection_feedback_conflict_title, conflict.title)
        assertTrue(conflict.canRefresh)
        assertTrue(conflict.mustRefreshBeforeDismiss)

        listOf(
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CONFIRMED_FAILURE,
        ).forEach { status ->
            val policy = connectionFeedbackPolicy(result(status, submitted = true))
            assertTrue(status.name, policy.canRefresh)
            assertTrue(status.name, policy.mustRefreshBeforeDismiss)
        }
        assertFalse(
            connectionFeedbackPolicy(result(MutationResultStatus.UNSUPPORTED)).canRefresh,
        )
    }

    @Test
    fun `连接反馈不依赖诊断标签且拒绝其他操作`() {
        val baseline = connectionFeedbackPolicy(result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED))
        assertEquals(
            baseline,
            connectionFeedbackPolicy(
                result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED)
                    .copy(diagnosticTag = "synthetic.unknown"),
            ),
        )
        assertThrows(IllegalArgumentException::class.java) {
            connectionFeedbackPolicy(
                result(MutationResultStatus.CONFIRMED_SUCCESS).copy(operation = "other"),
            )
        }
    }

    private fun result(
        status: MutationResultStatus,
        category: MutationErrorCategory? = null,
        submitted: Boolean = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "connectionDisconnect",
        submitted = submitted,
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
