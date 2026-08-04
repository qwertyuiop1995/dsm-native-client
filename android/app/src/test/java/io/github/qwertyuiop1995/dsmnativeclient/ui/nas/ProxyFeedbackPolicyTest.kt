package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ProxyFeedbackPolicyTest {
    @Test
    fun `只有无结果和异常时才恢复代理编辑器`() {
        val result = result(MutationResultStatus.CONFIRMED_FAILURE)
        val failure = DsmFailure(null, "", "")

        assertTrue(shouldReopenProxyEditor(true, false, null, null))
        assertFalse(shouldReopenProxyEditor(true, true, null, null))
        assertFalse(shouldReopenProxyEditor(true, false, result, null))
        assertFalse(shouldReopenProxyEditor(true, false, null, failure))
        assertFalse(shouldReopenProxyEditor(false, false, null, null))
    }

    @Test
    fun `代理八类结果均保留专属文案和恢复策略`() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to Triple(
                R.string.file_service_feedback_saved_title,
                R.string.proxy_settings_saved,
                false,
            ),
            MutationResultStatus.PARTIAL_SUCCESS to Triple(
                R.string.file_service_feedback_partial_title,
                R.string.proxy_feedback_partial_message,
                true,
            ),
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to Triple(
                R.string.file_service_feedback_check_title,
                R.string.proxy_feedback_unverified_message,
                true,
            ),
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to Triple(
                R.string.file_service_feedback_check_title,
                R.string.proxy_cancel_after_submission,
                true,
            ),
            MutationResultStatus.PERMISSION_DENIED to Triple(
                R.string.file_service_feedback_permission_title,
                R.string.proxy_feedback_permission_message,
                false,
            ),
            MutationResultStatus.UNSUPPORTED to Triple(
                R.string.file_service_feedback_unavailable_title,
                R.string.proxy_feedback_unsupported_message,
                false,
            ),
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to Triple(
                R.string.file_service_feedback_cancelled_title,
                R.string.proxy_feedback_cancelled_message,
                false,
            ),
            MutationResultStatus.CONFIRMED_FAILURE to Triple(
                R.string.file_service_feedback_failed_title,
                R.string.proxy_feedback_failed_message,
                false,
            ),
        )

        expected.forEach { (status, resources) ->
            val policy = proxyFeedbackPolicy(result(status))
            assertEquals(resources.first, policy.title)
            assertEquals(resources.second, policy.message)
            assertEquals(resources.third, policy.canRefresh)
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
    fun `代理冲突与已提交失败必须先刷新`() {
        val conflict = proxyFeedbackPolicy(
            result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
        )
        assertEquals(R.string.file_service_feedback_conflict_title, conflict.title)
        assertEquals(R.string.proxy_feedback_conflict_message, conflict.message)
        assertTrue(conflict.canRefresh)
        assertTrue(conflict.mustRefreshBeforeEditing)

        listOf(
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CONFIRMED_FAILURE,
        ).forEach { status ->
            val policy = proxyFeedbackPolicy(result(status, submittedOverride = true))
            assertTrue(status.name, policy.canRefresh)
            assertTrue(status.name, policy.mustRefreshBeforeEditing)
        }
        assertFalse(
            proxyFeedbackPolicy(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION))
                .mustRefreshBeforeEditing,
        )
    }

    @Test
    fun `拒绝把其他操作结果显示为代理设置反馈`() {
        assertThrows(IllegalArgumentException::class.java) {
            proxyFeedbackPolicy(
                result(MutationResultStatus.CONFIRMED_SUCCESS)
                    .copy(operation = "terminalSettingsUpdate"),
            )
        }
    }

    private fun result(
        status: MutationResultStatus,
        errorCategory: MutationErrorCategory? = null,
        submittedOverride: Boolean? = null,
    ): MutationResult {
        val submitted = submittedOverride ?: (status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ))
        val requiresRefresh = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "proxySettingsUpdate",
            submitted = submitted,
            requiresRefresh = requiresRefresh,
            counts = when (status) {
                MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(3, 0, 0)
                MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 1)
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                -> MutationResultCounts(0, 0, 3)
                MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
                else -> MutationResultCounts(0, 3, 0)
            },
            errorCategory = errorCategory,
        )
    }
}
