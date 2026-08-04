package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasRemoteAccessSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteAccessSettingsPolicyTest {
    @Test
    fun `八类结果保持刷新和强提醒策略`() {
        MutationResultStatus.entries.forEach { status ->
            val policy = settingsFeedbackPolicy(result(status))
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

    @Test
    fun `刷新目标区分匹配差异和不可用`() {
        val expected = settings(relay = false, router = true)
        assertNull(remoteAccessCurrentMatches(expected, expected, settingsAvailable = true, refreshCompleted = false))
        assertNull(remoteAccessCurrentMatches(expected, null, settingsAvailable = true, refreshCompleted = true))
        assertNull(remoteAccessCurrentMatches(expected, expected, settingsAvailable = false, refreshCompleted = true))
        assertTrue(remoteAccessCurrentMatches(
            expected,
            expected.copy(isConnectedThroughTrustedRelay = true, canManage = false),
            settingsAvailable = true,
            refreshCompleted = true,
        ) == true)
        assertFalse(remoteAccessCurrentMatches(
            expected,
            expected.copy(isRouterConfigurationEnabled = false),
            settingsAvailable = true,
            refreshCompleted = true,
        ) == true)
        assertNull(remoteAccessCurrentMatches(
            expected,
            expected.copy(isRouterConfigurationEnabled = null),
            settingsAvailable = true,
            refreshCompleted = true,
        ))
        assertTrue(remoteAccessCurrentMatches(
            settings(relay = null, router = true),
            settings(relay = false, router = true),
            settingsAvailable = true,
            refreshCompleted = true,
        ) == true)
    }

    private fun settings(relay: Boolean?, router: Boolean?) = NasRemoteAccessSettings(
        isRelayEnabled = relay,
        isRouterConfigurationEnabled = router,
        isConnectedThroughTrustedRelay = false,
        canManage = true,
    )

    private fun result(status: MutationResultStatus) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "remoteAccess",
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
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(2, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 2)
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
