package io.github.qwertyuiop1995.dsmnativeclient.domain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
enum class MutationResultStatus {
    @SerialName("confirmedSuccess")
    CONFIRMED_SUCCESS,

    @SerialName("confirmedFailure")
    CONFIRMED_FAILURE,

    @SerialName("submittedButUnverified")
    SUBMITTED_BUT_UNVERIFIED,

    @SerialName("partialSuccess")
    PARTIAL_SUCCESS,

    @SerialName("cancelledBeforeSubmission")
    CANCELLED_BEFORE_SUBMISSION,

    @SerialName("cancellationRequestedAfterSubmission")
    CANCELLATION_REQUESTED_AFTER_SUBMISSION,

    @SerialName("permissionDenied")
    PERMISSION_DENIED,

    @SerialName("unsupported")
    UNSUPPORTED,
}

@Serializable
enum class MutationErrorCategory {
    @SerialName("validation")
    VALIDATION,

    @SerialName("authentication")
    AUTHENTICATION,

    @SerialName("permission")
    PERMISSION,

    @SerialName("conflict")
    CONFLICT,

    @SerialName("network")
    NETWORK,

    @SerialName("server")
    SERVER,

    @SerialName("unsupported")
    UNSUPPORTED,

    @SerialName("unknown")
    UNKNOWN,
}

@Serializable
data class MutationResultCounts(
    val succeeded: Int,
    val failed: Int,
    val unknown: Int,
) {
    init {
        require(succeeded >= 0 && failed >= 0 && unknown >= 0) {
            "mutation.invalid_count"
        }
    }
}

@Serializable
data class MutationResult(
    val schemaVersion: Int,
    val status: MutationResultStatus,
    val operation: String,
    val submitted: Boolean,
    val requiresRefresh: Boolean,
    val counts: MutationResultCounts,
    val errorCategory: MutationErrorCategory? = null,
    val localizationKey: String? = null,
    val diagnosticTag: String? = null,
) {
    init {
        require(schemaVersion == 1) { "mutation.unsupported_schema" }
        require(OPERATION_PATTERN.matches(operation)) { "mutation.invalid_operation" }
        require(localizationKey == null || SAFE_TAG_PATTERN.matches(localizationKey)) {
            "mutation.invalid_localization_key"
        }
        require(diagnosticTag == null || SAFE_TAG_PATTERN.matches(diagnosticTag)) {
            "mutation.invalid_diagnostic_tag"
        }
        validateState()
    }

    private fun validateState() {
        when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS ->
                require(submitted && counts.failed == 0 && counts.unknown == 0) {
                    "mutation.inconsistent_success"
                }

            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION ->
                require(
                    !submitted &&
                        !requiresRefresh &&
                        counts.succeeded == 0 &&
                        counts.failed == 0 &&
                        counts.unknown == 0,
                ) {
                    "mutation.inconsistent_pre_submission_cancellation"
                }

            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ->
                require(submitted && requiresRefresh) {
                    "mutation.unverified_requires_refresh"
                }

            MutationResultStatus.PARTIAL_SUCCESS ->
                require(
                    submitted &&
                        counts.succeeded > 0 &&
                        counts.failed + counts.unknown > 0,
                ) {
                    "mutation.invalid_partial_success"
                }

            MutationResultStatus.CONFIRMED_FAILURE,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            -> Unit
        }
    }

    private companion object {
        val OPERATION_PATTERN = Regex("^[a-z][A-Za-z0-9]*$")
        val SAFE_TAG_PATTERN = Regex("^[a-z0-9][a-z0-9._-]*$")
    }
}
