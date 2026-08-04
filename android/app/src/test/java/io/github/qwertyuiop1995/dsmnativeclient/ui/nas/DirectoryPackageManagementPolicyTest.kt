package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.DirectoryEntryKind
import io.github.qwertyuiop1995.dsmnativeclient.DirectoryEntryMutationTarget
import io.github.qwertyuiop1995.dsmnativeclient.PackageMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasAccount
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasGroup
import io.github.qwertyuiop1995.dsmnativeclient.domain.PackageInfo
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DirectoryPackageManagementPolicyTest {
    @Test
    fun `eight result statuses use safe refresh gates`() {
        assertFalse(managementFeedbackPolicy(result(MutationResultStatus.CONFIRMED_SUCCESS)).mustRefresh)
        assertFalse(managementFeedbackPolicy(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)).mustRefresh)
        listOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ).forEach { assertTrue(managementFeedbackPolicy(result(it)).mustRefresh) }
        assertFalse(managementFeedbackPolicy(result(MutationResultStatus.PERMISSION_DENIED)).mustRefresh)
        assertFalse(managementFeedbackPolicy(result(MutationResultStatus.UNSUPPORTED)).mustRefresh)
        assertTrue(managementFeedbackPolicy(result(
            MutationResultStatus.CONFIRMED_FAILURE,
            submitted = false,
            category = MutationErrorCategory.CONFLICT,
        )).mustRefresh)
    }

    @Test
    fun `directory deletion compares names case-insensitively and distinguishes unreadable`() {
        val target = DirectoryEntryMutationTarget(DirectoryEntryKind.ACCOUNT, account = account("Operator"))
        assertEquals(
            ManagementTargetState.DIFFERS,
            directoryTargetState(target, listOf(account("operator")), emptyList(), true, true, true),
        )
        assertEquals(
            ManagementTargetState.MATCHES,
            directoryTargetState(target, emptyList(), emptyList(), true, true, true),
        )
        assertEquals(
            ManagementTargetState.UNAVAILABLE,
            directoryTargetState(target, emptyList(), emptyList(), false, true, true),
        )
    }

    @Test
    fun `group deletion checks only the group collection`() {
        val target = DirectoryEntryMutationTarget(DirectoryEntryKind.GROUP, group = group("operators"))
        assertEquals(
            ManagementTargetState.DIFFERS,
            directoryTargetState(target, listOf(account("operators")), listOf(group("Operators")), true, true, true),
        )
        assertEquals(
            ManagementTargetState.MATCHES,
            directoryTargetState(target, listOf(account("operators")), emptyList(), true, true, true),
        )
    }

    @Test
    fun `package target distinguishes expected state different state missing and unavailable`() {
        val target = pkg(ResourceState.STOPPED)
        assertEquals(ManagementTargetState.MATCHES, packageTargetState(
            target, PackageMutationOperation.START, listOf(pkg(ResourceState.RUNNING)), true, true,
        ))
        assertEquals(ManagementTargetState.DIFFERS, packageTargetState(
            target, PackageMutationOperation.START, listOf(pkg(ResourceState.STOPPED)), true, true,
        ))
        assertEquals(ManagementTargetState.MISSING, packageTargetState(
            target, PackageMutationOperation.START, emptyList(), true, true,
        ))
        assertEquals(ManagementTargetState.MATCHES, packageTargetState(
            target, PackageMutationOperation.UNINSTALL, emptyList(), true, true,
        ))
        assertEquals(ManagementTargetState.UNAVAILABLE, packageTargetState(
            target, PackageMutationOperation.STOP, emptyList(), false, true,
        ))
    }

    private fun account(name: String) = NasAccount(1, name, null, null, false, true)
    private fun group(name: String) = NasGroup(1, name, null, true)
    private fun pkg(state: ResourceState) = PackageInfo("pkg", "Synthetic Package", "1.0", state, null, true, true, true)

    private fun result(
        status: MutationResultStatus,
        submitted: Boolean = status !in setOf(
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
        ),
        category: MutationErrorCategory? = when (status) {
            MutationResultStatus.PERMISSION_DENIED -> MutationErrorCategory.PERMISSION
            MutationResultStatus.UNSUPPORTED -> MutationErrorCategory.UNSUPPORTED
            MutationResultStatus.CONFIRMED_FAILURE -> MutationErrorCategory.SERVER
            else -> null
        },
    ): MutationResult = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "managementAction",
        submitted = submitted,
        requiresRefresh = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> MutationResultCounts(0, 0, 1)
            else -> MutationResultCounts(0, 0, 0)
        },
        errorCategory = category,
    )
}
