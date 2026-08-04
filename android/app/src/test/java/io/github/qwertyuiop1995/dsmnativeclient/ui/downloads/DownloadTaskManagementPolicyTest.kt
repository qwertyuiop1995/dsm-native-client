package io.github.qwertyuiop1995.dsmnativeclient.ui.downloads

import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadTaskManagementPolicyTest {
    @Test
    fun `八类结果使用下载任务专用反馈且仅确认成功为礼貌播报`() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to R.string.download_control_confirmed_title,
            MutationResultStatus.PARTIAL_SUCCESS to R.string.download_control_partial_title,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to R.string.download_control_check_title,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to
                R.string.download_control_check_title,
            MutationResultStatus.PERMISSION_DENIED to R.string.download_control_permission_title,
            MutationResultStatus.UNSUPPORTED to R.string.download_control_unavailable_title,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to
                R.string.download_control_cancelled_title,
            MutationResultStatus.CONFIRMED_FAILURE to R.string.download_control_failed_title,
        )

        expected.forEach { (status, title) ->
            val policy = downloadControlFeedbackPolicy(result(status))
            assertEquals(title, policy.title)
            assertEquals(status != MutationResultStatus.CONFIRMED_SUCCESS, policy.assertive)
        }
    }

    @Test
    fun `冲突失败使用可恢复冲突文案`() {
        val policy = downloadControlFeedbackPolicy(
            result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
        )

        assertEquals(R.string.download_control_conflict_title, policy.title)
        assertEquals(R.string.download_action_conflict, policy.message)
        assertTrue(policy.assertive)
    }

    @Test
    fun `确认成功与失败播报优先级不同`() {
        assertFalse(downloadControlFeedbackPolicy(
            result(MutationResultStatus.CONFIRMED_SUCCESS),
        ).assertive)
        assertTrue(downloadControlFeedbackPolicy(
            result(MutationResultStatus.PERMISSION_DENIED),
        ).assertive)
    }

    @Test
    fun `删除任务及文件的部分成功使用单任务专用说明`() {
        val policy = downloadControlFeedbackPolicy(
            result(MutationResultStatus.PARTIAL_SUCCESS),
            deleteFiles = true,
        )

        assertEquals(R.string.download_delete_files_partial_title, policy.title)
        assertEquals(R.string.download_delete_files_partial_message, policy.message)
        assertTrue(policy.assertive)
    }

    private fun result(
        status: MutationResultStatus,
        error: MutationErrorCategory? = null,
    ): MutationResult {
        val submitted = status !in setOf(
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CONFIRMED_FAILURE,
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
            operation = "downloadControl",
            submitted = submitted,
            requiresRefresh = submitted && status != MutationResultStatus.CONFIRMED_SUCCESS,
            counts = counts,
            errorCategory = error,
        )
    }
}
