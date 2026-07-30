package io.github.qwertyuiop1995.dsmnativeclient.domain

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MutationResultTest {
    @Test
    fun `所有稳定状态序列化后保持线值`() {
        MutationResultStatus.entries.forEach { status ->
            val result = validResult(status)
            val encoded = Json.encodeToString(result)
            val decoded = Json.decodeFromString<MutationResult>(encoded)

            assertEquals(result, decoded)
            assertTrue(encoded.contains(expectedWireValue(status)))
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun `提交未确认必须要求刷新`() {
        MutationResult(
            schemaVersion = 1,
            status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            operation = "delete",
            submitted = true,
            requiresRefresh = false,
            counts = MutationResultCounts(succeeded = 0, failed = 0, unknown = 1),
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun `诊断标签拒绝路径和自由文本`() {
        MutationResult(
            schemaVersion = 1,
            status = MutationResultStatus.CONFIRMED_FAILURE,
            operation = "delete",
            submitted = true,
            requiresRefresh = false,
            counts = MutationResultCounts(succeeded = 0, failed = 1, unknown = 0),
            diagnosticTag = "/volume1/private/file",
        )
    }

    private fun validResult(status: MutationResultStatus): MutationResult =
        when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS ->
                result(status, submitted = true, succeeded = 1)

            MutationResultStatus.CONFIRMED_FAILURE ->
                result(status, submitted = true, failed = 1)

            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ->
                result(status, submitted = true, requiresRefresh = true, unknown = 1)

            MutationResultStatus.PARTIAL_SUCCESS ->
                result(status, submitted = true, requiresRefresh = true, succeeded = 1, failed = 1)

            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION ->
                result(status)

            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            ->
                result(status, failed = 1)
        }

    private fun result(
        status: MutationResultStatus,
        submitted: Boolean = false,
        requiresRefresh: Boolean = false,
        succeeded: Int = 0,
        failed: Int = 0,
        unknown: Int = 0,
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "delete",
        submitted = submitted,
        requiresRefresh = requiresRefresh,
        counts = MutationResultCounts(succeeded, failed, unknown),
    )

    private fun expectedWireValue(status: MutationResultStatus): String =
        when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> "confirmedSuccess"
            MutationResultStatus.CONFIRMED_FAILURE -> "confirmedFailure"
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED -> "submittedButUnverified"
            MutationResultStatus.PARTIAL_SUCCESS -> "partialSuccess"
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> "cancelledBeforeSubmission"
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION ->
                "cancellationRequestedAfterSubmission"

            MutationResultStatus.PERMISSION_DENIED -> "permissionDenied"
            MutationResultStatus.UNSUPPORTED -> "unsupported"
        }
}
