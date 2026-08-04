package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDiskTestStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDiskTestType
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasStorageDisk
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartTestManagementPolicyTest {
    @Test
    fun `SMART target distinguishes match difference disappearance and unavailable`() {
        val disk = disk()
        val baseline = status(lastQuick = "before", lastExtended = "before")
        assertEquals(ManagementTargetState.UNAVAILABLE, smartTestTargetState(
            disk, baseline, NasDiskTestType.QUICK, listOf(disk), emptyMap(), false,
        ))
        assertEquals(ManagementTargetState.MISSING, smartTestTargetState(
            disk, baseline, NasDiskTestType.QUICK, emptyList(), emptyMap(), true,
        ))
        assertEquals(ManagementTargetState.UNAVAILABLE, smartTestTargetState(
            disk, baseline, NasDiskTestType.QUICK, listOf(disk), mapOf(disk.id to Loadable.Loading), true,
        ))
        assertEquals(ManagementTargetState.MATCHES, smartTestTargetState(
            disk, baseline, NasDiskTestType.QUICK, listOf(disk),
            mapOf(disk.id to Loadable.Ready(status(running = true, type = NasDiskTestType.QUICK))), true,
        ))
        assertEquals(ManagementTargetState.MATCHES, smartTestTargetState(
            disk, baseline, NasDiskTestType.EXTENDED, listOf(disk),
            mapOf(disk.id to Loadable.Ready(status(running = true, type = NasDiskTestType.EXTENDED))), true,
        ))
        assertEquals(ManagementTargetState.DIFFERS, smartTestTargetState(
            disk, baseline, NasDiskTestType.QUICK, listOf(disk),
            mapOf(disk.id to Loadable.Ready(status(lastQuick = "before"))), true,
        ))
        assertEquals(ManagementTargetState.MATCHES, smartTestTargetState(
            disk, baseline, NasDiskTestType.QUICK,
            listOf(disk.copy(model = "Changed", status = "warning", smartStatus = "warning", temperatureCelsius = 48.0)),
            mapOf(disk.id to Loadable.Ready(status(running = true, type = NasDiskTestType.QUICK))), true,
        ))
        assertEquals(ManagementTargetState.DIFFERS, smartTestTargetState(
            disk, baseline, NasDiskTestType.QUICK, listOf(disk.copy(deviceId = "changed-device")),
            mapOf(disk.id to Loadable.Ready(status(running = true, type = NasDiskTestType.QUICK))), true,
        ))
        assertEquals(ManagementTargetState.DIFFERS, smartTestTargetState(
            disk, baseline, NasDiskTestType.QUICK, listOf(disk.copy(supportsSmartTest = false)),
            mapOf(disk.id to Loadable.Ready(status(running = true, type = NasDiskTestType.QUICK))), true,
        ))
        assertEquals(ManagementTargetState.MATCHES, smartTestTargetState(
            disk, baseline, null, listOf(disk), mapOf(disk.id to Loadable.Ready(status())), true,
        ))
    }

    @Test
    fun `SMART feedback preserves all eight statuses and dangerous refresh gates`() {
        MutationResultStatus.entries.forEach { status ->
            val policy = managementFeedbackPolicy(result(status))
            val expectedRefresh = status in setOf(
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            )
            assertEquals(status.name, expectedRefresh, policy.mustRefresh)
            if (status == MutationResultStatus.CONFIRMED_SUCCESS) assertFalse(policy.assertive)
            else assertTrue(policy.assertive)
        }
    }

    private fun disk() = NasStorageDisk(
        id = "disk-1", deviceId = "synthetic-device", name = "Synthetic drive", model = "Example",
        status = "normal", smartStatus = "normal", temperatureCelsius = 30.0, supportsSmartTest = true,
    )

    private fun status(
        running: Boolean = false,
        type: NasDiskTestType? = null,
        lastQuick: String? = null,
        lastExtended: String? = null,
    ) = NasDiskTestStatus(
        diskId = "disk-1", isRunning = running, isBusyWithOtherTest = false, runningType = type,
        progressDescription = null, lastQuickTest = lastQuick, lastExtendedTest = lastExtended,
        lastResult = null, isHistoryAvailable = true,
    )

    private fun result(status: MutationResultStatus) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "smartTest",
        submitted = status !in setOf(
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CONFIRMED_FAILURE,
        ),
        requiresRefresh = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            else -> MutationResultCounts(0, 0, 0)
        },
        errorCategory = when (status) {
            MutationResultStatus.PERMISSION_DENIED -> MutationErrorCategory.PERMISSION
            MutationResultStatus.UNSUPPORTED -> MutationErrorCategory.UNSUPPORTED
            MutationResultStatus.CONFIRMED_FAILURE -> MutationErrorCategory.SERVER
            else -> null
        },
    )
}
