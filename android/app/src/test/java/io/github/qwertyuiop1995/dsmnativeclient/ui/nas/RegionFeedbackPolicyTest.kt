package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasRegionSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class RegionFeedbackPolicyTest {
    @Test
    fun `只有无结果和异常时才恢复区域编辑器`() {
        val result = result(MutationResultStatus.CONFIRMED_FAILURE)
        val failure = DsmFailure(null, "", "")

        assertTrue(shouldReopenRegionEditor(true, false, null, null))
        assertFalse(shouldReopenRegionEditor(true, true, null, null))
        assertFalse(shouldReopenRegionEditor(true, false, result, null))
        assertFalse(shouldReopenRegionEditor(true, false, null, failure))
        assertFalse(shouldReopenRegionEditor(false, false, null, null))
    }

    @Test
    fun `区域八类结果均保留专属文案和恢复策略`() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to Triple(
                R.string.region_feedback_saved_title,
                R.string.region_feedback_sync_accepted_message,
                false,
            ),
            MutationResultStatus.PARTIAL_SUCCESS to Triple(
                R.string.region_feedback_partial_title,
                R.string.region_feedback_partial_message,
                true,
            ),
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to Triple(
                R.string.region_feedback_check_title,
                R.string.region_feedback_unverified_message,
                true,
            ),
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to Triple(
                R.string.region_feedback_check_title,
                R.string.region_cancel_after_submission,
                true,
            ),
            MutationResultStatus.PERMISSION_DENIED to Triple(
                R.string.file_service_feedback_permission_title,
                R.string.region_feedback_permission_message,
                false,
            ),
            MutationResultStatus.UNSUPPORTED to Triple(
                R.string.file_service_feedback_unavailable_title,
                R.string.region_feedback_unsupported_message,
                false,
            ),
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to Triple(
                R.string.file_service_feedback_cancelled_title,
                R.string.region_feedback_cancelled_message,
                false,
            ),
            MutationResultStatus.CONFIRMED_FAILURE to Triple(
                R.string.file_service_feedback_failed_title,
                R.string.region_feedback_failed_message,
                false,
            ),
        )

        expected.forEach { (status, resources) ->
            val policy = regionFeedbackPolicy(result(status))
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
    fun `区域两阶段文案不依赖内部诊断标签`() {
        listOf(
            "region.configuration-not-fully-confirmed",
            "region.sync-unverified",
            "region.sync-readback-unverified",
            "region.sync-readback-mismatch",
            "region.unknown",
        ).forEach { tag ->
            assertEquals(
                R.string.region_feedback_partial_message,
                regionFeedbackPolicy(
                    result(MutationResultStatus.PARTIAL_SUCCESS).copy(diagnosticTag = tag),
                ).message,
            )
        }
        assertEquals(
            R.string.region_feedback_sync_accepted_message,
            regionFeedbackPolicy(
                result(MutationResultStatus.CONFIRMED_SUCCESS)
                    .copy(diagnosticTag = "region.unknown"),
            ).message,
        )
    }

    @Test
    fun `区域冲突和已提交失败必须先刷新且即时校时判定准确`() {
        val conflict = regionFeedbackPolicy(
            result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
        )
        assertTrue(conflict.canRefresh)
        assertTrue(conflict.mustRefreshBeforeEditing)

        listOf(
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CONFIRMED_FAILURE,
        ).forEach { status ->
            val submittedResult = result(status, submittedOverride = true)
            assertTrue("${status.name}-submitted", submittedResult.submitted)
            val policy = regionFeedbackPolicy(submittedResult)
            assertTrue(status.name, policy.canRefresh)
            assertTrue(status.name, policy.mustRefreshBeforeEditing)
        }

        val manual = region(false, listOf("old.example.invalid"))
        assertFalse(regionSettingsNeedsImmediateTimeSync(manual, manual.copy(dateFormat = "Y/m/d")))
        assertTrue(regionSettingsNeedsImmediateTimeSync(manual, region(true, listOf("a.invalid"))))
        val network = region(true, listOf("a.invalid"))
        assertFalse(regionSettingsNeedsImmediateTimeSync(network, network.copy(timeZone = "UTC")))
        assertTrue(regionSettingsNeedsImmediateTimeSync(network, network.copy(timeServers = listOf("b.invalid"))))
    }

    @Test
    fun `拒绝把其他操作结果显示为区域设置反馈`() {
        assertThrows(IllegalArgumentException::class.java) {
            regionFeedbackPolicy(
                result(MutationResultStatus.CONFIRMED_SUCCESS)
                    .copy(operation = "proxySettingsUpdate"),
            )
        }
    }

    private fun region(network: Boolean, servers: List<String>) = NasRegionSettings(
        "Y-m-d", "H:i", "Asia/Shanghai", network, servers, null, emptyList(),
    )

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
            operation = "regionSettingsUpdate",
            submitted = submitted,
            requiresRefresh = requiresRefresh,
            counts = when (status) {
                MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(5, 0, 0)
                MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(3, 0, 2)
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                -> MutationResultCounts(0, 0, 5)
                MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
                else -> MutationResultCounts(0, 5, 0)
            },
            errorCategory = errorCategory,
        )
    }
}
