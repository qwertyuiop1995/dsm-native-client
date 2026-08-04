package io.github.qwertyuiop1995.dsmnativeclient.ui.nas

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDoSProtectionSetting
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasHardwareSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSecuritySettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasUpsSettings
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityHardwareFeedbackPolicyTest {
    @Test
    fun `confirmed success and pre-submit cancellation can close without refresh`() {
        assertFalse(settingsFeedbackPolicy(result(MutationResultStatus.CONFIRMED_SUCCESS)).mustRefresh)
        assertFalse(settingsFeedbackPolicy(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)).mustRefresh)
    }

    @Test
    fun `uncertain submitted outcomes require a targeted refresh`() {
        listOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ).forEach { assertTrue(settingsFeedbackPolicy(result(it)).mustRefresh) }
    }

    @Test
    fun `submitted permission unsupported conflict and failure require refresh`() {
        assertTrue(settingsFeedbackPolicy(result(MutationResultStatus.PERMISSION_DENIED, submitted = true)).mustRefresh)
        assertTrue(settingsFeedbackPolicy(result(MutationResultStatus.UNSUPPORTED, submitted = true)).mustRefresh)
        assertTrue(settingsFeedbackPolicy(result(MutationResultStatus.CONFIRMED_FAILURE, submitted = true)).mustRefresh)
        assertTrue(settingsFeedbackPolicy(result(
            MutationResultStatus.CONFIRMED_FAILURE,
            submitted = false,
            category = MutationErrorCategory.CONFLICT,
        )).mustRefresh)
    }

    @Test
    fun `security matching ignores adapter order and read-only labels but compares writable values`() {
        val current = security()
        val reordered = current.copy(
            dosProtection = current.dosProtection.reversed().map { it.copy(displayName = "Renamed ${it.id}") },
            firewallProfileName = "Server-renamed profile",
        )
        assertTrue(securitySettingsMatch(current, reordered))
        assertFalse(securitySettingsMatch(current, reordered.copy(isFirewallEnabled = false)))
        assertFalse(securitySettingsMatch(current, reordered.copy(
            dosProtection = reordered.dosProtection.map { if (it.id == "eth0") it.copy(isEnabled = false) else it },
        )))
    }

    @Test
    fun `hardware matching normalizes UPS addresses and ignores read-only LED range`() {
        val current = hardware()
        val normalized = current.copy(
            ledBrightnessMinimum = 10,
            ledBrightnessMaximum = 10,
            ups = current.ups?.copy(networkServerAddress = " 192.0.2.10 ", snmpServerAddress = " "),
        )
        assertTrue(hardwareSettingsMatch(current, normalized))
        assertFalse(hardwareSettingsMatch(current, normalized.copy(fanMode = "fullfan")))
    }

    @Test
    fun `all submitted non-success power results require external device check`() {
        assertFalse(powerResultRequiresDeviceCheck(result(MutationResultStatus.CONFIRMED_SUCCESS)))
        assertFalse(powerResultRequiresDeviceCheck(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION)))
        listOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            MutationResultStatus.CONFIRMED_FAILURE,
        ).forEach { assertTrue(powerResultRequiresDeviceCheck(result(it, submitted = true))) }
    }

    private fun security() = NasSecuritySettings(
        isAutoBlockEnabled = true,
        failedAttempts = 5,
        withinMinutes = 10,
        expirationDays = 7,
        dosProtection = listOf(
            NasDoSProtectionSetting("eth0", "LAN 1", true),
            NasDoSProtectionSetting("eth1", "LAN 2", false),
        ),
        isFirewallEnabled = true,
        firewallProfileName = "Default",
        isPortScanProtectionEnabled = true,
    )

    private fun hardware() = NasHardwareSettings(
        true, 2, 0, 3, "quietfan", true, true, true, true, true,
        true, true, true, true, true,
        NasUpsSettings(true, "SLAVE", 30, true, false, "192.0.2.10", null),
    )

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
    ): MutationResult {
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION -> MutationResultCounts(0, 0, 1)
            MutationResultStatus.CONFIRMED_FAILURE -> MutationResultCounts(0, if (submitted) 1 else 0, 0)
            else -> MutationResultCounts(0, 0, 0)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "saveSettings",
            submitted = submitted,
            requiresRefresh = status in setOf(
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ),
            counts = counts,
            errorCategory = category,
        )
    }
}
