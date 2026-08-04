package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class FileServiceFeedbackPolicyTest {
    @Test
    fun `只有无结构化结果也无异常时才恢复编辑器`() {
        val result = result(MutationResultStatus.CONFIRMED_FAILURE)
        val failure = DsmFailure(null, "", "")

        assertTrue(shouldReopenFileServiceEditor(true, false, null, null))
        assertFalse(shouldReopenFileServiceEditor(true, true, null, null))
        assertFalse(shouldReopenFileServiceEditor(true, false, result, null))
        assertFalse(shouldReopenFileServiceEditor(true, false, null, failure))
        assertFalse(shouldReopenFileServiceEditor(false, false, null, null))
    }

    @Test
    fun `八类结果均映射到稳定标题消息和恢复策略`() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to Triple(
                R.string.file_service_feedback_saved_title,
                R.string.file_service_settings_saved,
                false,
            ),
            MutationResultStatus.PARTIAL_SUCCESS to Triple(
                R.string.file_service_feedback_partial_title,
                R.string.file_service_feedback_partial_message,
                true,
            ),
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to Triple(
                R.string.file_service_feedback_check_title,
                R.string.file_service_feedback_unverified_message,
                true,
            ),
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to Triple(
                R.string.file_service_feedback_check_title,
                R.string.file_service_cancel_after_submission,
                true,
            ),
            MutationResultStatus.PERMISSION_DENIED to Triple(
                R.string.file_service_feedback_permission_title,
                R.string.file_service_feedback_permission_message,
                false,
            ),
            MutationResultStatus.UNSUPPORTED to Triple(
                R.string.file_service_feedback_unavailable_title,
                R.string.file_service_feedback_unsupported_message,
                false,
            ),
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to Triple(
                R.string.file_service_feedback_cancelled_title,
                R.string.file_service_feedback_cancelled_message,
                false,
            ),
            MutationResultStatus.CONFIRMED_FAILURE to Triple(
                R.string.file_service_feedback_failed_title,
                R.string.file_service_feedback_failed_message,
                false,
            ),
        )

        expected.forEach { (status, resources) ->
            val policy = fileServiceFeedbackPolicy(result(status))
            assertEquals(resources.first, policy.title)
            assertEquals(resources.second, policy.message)
            assertEquals(resources.third, policy.canRefresh)
            assertEquals(status !in setOf(
                MutationResultStatus.CONFIRMED_SUCCESS,
                MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            ), policy.isAssertive)
        }
        listOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ).forEach { status ->
            assertTrue(fileServiceFeedbackPolicy(result(status)).mustRefreshBeforeEditing)
        }
        assertFalse(
            fileServiceFeedbackPolicy(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION))
                .mustRefreshBeforeEditing,
        )
    }

    @Test
    fun `冲突和已提交权限失败要求先刷新核对`() {
        val conflict = fileServiceFeedbackPolicy(
            result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
        )
        assertEquals(R.string.file_service_feedback_conflict_title, conflict.title)
        assertEquals(R.string.file_service_feedback_conflict_message, conflict.message)
        assertTrue(conflict.canRefresh)
        assertTrue(conflict.mustRefreshBeforeEditing)

        val submittedPermission = fileServiceFeedbackPolicy(
            result(MutationResultStatus.PERMISSION_DENIED, submittedOverride = true),
        )
        assertTrue(submittedPermission.canRefresh)
        assertTrue(submittedPermission.mustRefreshBeforeEditing)
        assertTrue(
            fileServiceFeedbackPolicy(
                result(MutationResultStatus.UNSUPPORTED, submittedOverride = true),
            ).mustRefreshBeforeEditing,
        )
        assertTrue(
            fileServiceFeedbackPolicy(
                result(MutationResultStatus.CONFIRMED_FAILURE, submittedOverride = true),
            ).mustRefreshBeforeEditing,
        )
        assertFalse(fileServiceFeedbackPolicy(result(MutationResultStatus.PERMISSION_DENIED)).canRefresh)
    }

    @Test
    fun `拒绝把其他操作的结果放入文件服务反馈`() {
        assertThrows(IllegalArgumentException::class.java) {
            fileServiceFeedbackPolicy(
                result(MutationResultStatus.CONFIRMED_SUCCESS).copy(operation = "terminalSettingsUpdate"),
            )
        }
    }

    private fun result(
        status: MutationResultStatus,
        errorCategory: MutationErrorCategory? = null,
        submittedOverride: Boolean? = null,
    ): MutationResult {
        val submitted = submittedOverride ?: when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> true
            else -> false
        }
        val requiresRefresh = status in setOf(
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
            else -> MutationResultCounts(0, 1, 0)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "fileServiceSettingsUpdate",
            submitted = submitted,
            requiresRefresh = requiresRefresh,
            counts = counts,
            errorCategory = errorCategory,
        )
    }
}
