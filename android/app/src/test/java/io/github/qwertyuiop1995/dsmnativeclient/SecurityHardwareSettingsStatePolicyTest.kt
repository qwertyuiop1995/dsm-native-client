package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDoSProtectionSetting
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasHardwareSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSecuritySettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasUpsSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SecurityHardwareSettingsStatePolicyTest {
    @Test
    fun `电源结果只有明确安全终态允许关闭`() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to true,
            MutationResultStatus.PERMISSION_DENIED to true,
            MutationResultStatus.UNSUPPORTED to true,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to true,
            MutationResultStatus.CONFIRMED_FAILURE to true,
            MutationResultStatus.PARTIAL_SUCCESS to false,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to false,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to false,
        )

        expected.forEach { (status, canDismiss) ->
            assertEquals(status.name, canDismiss, canDismissPowerMutationResult(result(status)))
        }
    }

    @Test
    fun `电源结果要求刷新或含未知计数时不能绕过界面清除`() {
        val confirmedFailure = result(MutationResultStatus.CONFIRMED_FAILURE)
        assertFalse(
            canDismissPowerMutationResult(
                confirmedFailure.copy(submitted = true, requiresRefresh = true),
            ),
        )
        assertFalse(
            canDismissPowerMutationResult(
                confirmedFailure.copy(counts = MutationResultCounts(0, 0, 1)),
            ),
        )
    }

    @Test
    fun `安全与硬件未知结果使用专项刷新门禁`() {
        MutationResultStatus.entries.forEach { status ->
            val result = result(status)
            val expected = when (status) {
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                -> true
                MutationResultStatus.PERMISSION_DENIED,
                MutationResultStatus.UNSUPPORTED,
                MutationResultStatus.CONFIRMED_FAILURE,
                -> result.submitted || result.requiresRefresh
                MutationResultStatus.CONFIRMED_SUCCESS,
                MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
                -> false
            }
            assertEquals(status.name, expected, structuredSettingsMutationRequiresRefreshBeforeDismiss(result))
        }
        assertTrue(
            structuredSettingsMutationRequiresRefreshBeforeDismiss(
                result(
                    MutationResultStatus.CONFIRMED_FAILURE,
                    category = MutationErrorCategory.CONFLICT,
                ),
            ),
        )
    }

    @Test
    fun `安全成功回退要求可用且基线未漂移并替换完整确认字段`() {
        val baseline = security()
        val expected = baseline.copy(
            isAutoBlockEnabled = false,
            failedAttempts = 8,
            withinMinutes = 12,
            expirationDays = 30,
            dosProtection = baseline.dosProtection.map {
                it.copy(displayName = "不能写入的显示名称", isEnabled = false)
            },
            isFirewallEnabled = false,
            firewallProfileName = "trusted-profile",
            isPortScanProtectionEnabled = false,
        )

        val updated = confirmedSecuritySettingsFallback(snapshot(security = baseline), baseline, expected)

        assertEquals(
            expected.copy(dosProtection = baseline.dosProtection.map { it.copy(isEnabled = false) }),
            updated?.securitySettings,
        )
        assertTrue(updated?.securitySettingsAvailable == true)
        assertNull(
            confirmedSecuritySettingsFallback(
                snapshot(security = baseline.copy(failedAttempts = 9)),
                baseline,
                expected,
            ),
        )
        assertNull(
            confirmedSecuritySettingsFallback(
                snapshot(security = baseline, securityAvailable = false),
                baseline,
                expected,
            ),
        )
    }

    @Test
    fun `硬件成功回退要求可用且基线未漂移并替换完整确认字段`() {
        val baseline = hardware()
        val expected = baseline.copy(
            restartsAfterPowerFailure = false,
            ledBrightness = 25,
            ledBrightnessMinimum = -100,
            ledBrightnessMaximum = 1_000,
            fanMode = "cool",
            isFanFailureAlertEnabled = false,
            isExternalDriveDeepSleepEnabled = false,
            ups = baseline.ups?.copy(
                safeModeDelaySeconds = 300,
                networkServerAddress = " 192.0.2.10 ",
            ),
        )

        val updated = confirmedHardwareSettingsFallback(snapshot(hardware = baseline), baseline, expected)

        assertEquals(
            expected.copy(
                ledBrightnessMinimum = baseline.ledBrightnessMinimum,
                ledBrightnessMaximum = baseline.ledBrightnessMaximum,
                ups = expected.ups?.copy(networkServerAddress = "192.0.2.10"),
            ),
            updated?.hardwareSettings,
        )
        assertTrue(updated?.hardwareSettingsAvailable == true)
        assertNull(
            confirmedHardwareSettingsFallback(
                snapshot(hardware = baseline.copy(ledBrightness = 90)),
                baseline,
                expected,
            ),
        )
        assertNull(
            confirmedHardwareSettingsFallback(
                snapshot(hardware = baseline, hardwareAvailable = false),
                baseline,
                expected,
            ),
        )
    }

    @Test
    fun `UPS 地址规范化保留字段存在的空串并只让缺失字段保持 null`() {
        val value = hardware().copy(
            ups = hardware().ups?.copy(
                networkServerAddress = "   ",
                snmpServerAddress = null,
            ),
        )

        val normalized = checkNotNull(normalizedHardwareSettingsDraft(value).ups)

        assertEquals("", normalized.networkServerAddress)
        assertNull(normalized.snmpServerAddress)
    }

    @Test
    fun `专项刷新后继续编辑采用最新安全与硬件基线并保留草稿`() {
        val securityDraft = security().copy(failedAttempts = 7)
        val currentSecurity = security().copy(failedAttempts = 9)
        val securityRebased = checkNotNull(
            rebasedSecuritySettingsDraft(snapshot(security = currentSecurity), securityDraft),
        )
        assertEquals(currentSecurity, securityRebased.first)
        assertEquals(securityDraft, securityRebased.second)

        val hardwareDraft = hardware().copy(ledBrightness = 30)
        val currentHardware = hardware().copy(ledBrightness = 80)
        val hardwareRebased = checkNotNull(
            rebasedHardwareSettingsDraft(snapshot(hardware = currentHardware), hardwareDraft),
        )
        assertEquals(currentHardware, hardwareRebased.first)
        assertEquals(hardwareDraft, hardwareRebased.second)

        assertNull(
            rebasedSecuritySettingsDraft(
                snapshot(security = currentSecurity, securityAvailable = false),
                securityDraft,
            ),
        )
        assertNull(
            rebasedHardwareSettingsDraft(
                snapshot(hardware = currentHardware, hardwareAvailable = false),
                hardwareDraft,
            ),
        )
    }

    @Test
    fun `明确成功和提交前取消不要求无意义专项刷新`() {
        assertFalse(
            structuredSettingsMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.CONFIRMED_SUCCESS),
            ),
        )
        assertFalse(
            structuredSettingsMutationRequiresRefreshBeforeDismiss(
                result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION),
            ),
        )
    }

    private fun security() = NasSecuritySettings(
        isAutoBlockEnabled = true,
        failedAttempts = 5,
        withinMinutes = 10,
        expirationDays = null,
        dosProtection = listOf(NasDoSProtectionSetting("eth0", "LAN 1", true)),
        isFirewallEnabled = true,
        firewallProfileName = "trusted-profile",
        isPortScanProtectionEnabled = true,
    )

    private fun hardware() = NasHardwareSettings(
        restartsAfterPowerFailure = true,
        ledBrightness = 50,
        ledBrightnessMinimum = 0,
        ledBrightnessMaximum = 100,
        fanMode = "quiet",
        isFanFailureAlertEnabled = true,
        isVolumeFailureAlertEnabled = true,
        isPowerOnSoundEnabled = true,
        isPowerOffSoundEnabled = true,
        isResetSoundEnabled = true,
        isExternalDriveDeepSleepEnabled = true,
        isWakeUpLogEnabled = true,
        isSataSleepEnabled = true,
        ignoresNetworkDiscoveryDuringSleep = false,
        isAutomaticPowerOffEnabled = false,
        ups = NasUpsSettings(
            isEnabled = true,
            mode = "usb",
            safeModeDelaySeconds = 120,
            waitsUntilLowBattery = false,
            shutsDownUpsAfterSafeMode = true,
            networkServerAddress = null,
            snmpServerAddress = null,
        ),
    )

    private fun snapshot(
        security: NasSecuritySettings = security(),
        hardware: NasHardwareSettings = hardware(),
        securityAvailable: Boolean = true,
        hardwareAvailable: Boolean = true,
    ) = NasSettingsSnapshot(
        system = null,
        volumes = emptyList(),
        pools = emptyList(),
        disks = emptyList(),
        storageDisks = emptyList(),
        packages = emptyList(),
        scheduledTasks = emptyList(),
        accounts = emptyList(),
        groups = emptyList(),
        logs = emptyList(),
        connections = emptyList(),
        connectionsAvailable = true,
        networkInterfaces = emptyList(),
        networkInterfacesAvailable = true,
        ddnsDirectory = null,
        ddnsDirectoryAvailable = true,
        fileServiceSettings = null,
        terminalSettings = null,
        proxySettings = null,
        regionSettings = null,
        securitySettings = security,
        hardwareSettings = hardware,
        security = emptyList(),
        securitySettingsAvailable = securityAvailable,
        hardwareSettingsAvailable = hardwareAvailable,
    )

    private fun result(
        status: MutationResultStatus,
        category: MutationErrorCategory? = null,
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "settingsUpdate",
        submitted = status in setOf(
            MutationResultStatus.CONFIRMED_SUCCESS,
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        requiresRefresh = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            else -> MutationResultCounts(0, 1, 0)
        },
        errorCategory = category,
    )
}
