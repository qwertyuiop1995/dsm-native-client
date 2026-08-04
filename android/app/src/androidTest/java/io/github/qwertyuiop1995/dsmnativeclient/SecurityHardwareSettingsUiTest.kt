package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDoSProtectionSetting
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasHardwareSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasPowerAction
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSecuritySettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasUpsSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.HardwareSettingsDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.PowerActionConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.PowerActionFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SecurityConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SecuritySettingsDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SecuritySettingsContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SettingsMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class SecurityHardwareSettingsUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 安全开关整行可操作且达到48dp并适配深色2倍密度() {
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                LanStashTheme(darkTheme = true) {
                    SecuritySettingsDialog(security(), security().copy(isAutoBlockEnabled = false), true, {}, { true }, {})
                }
            }
        }
        rule.onAllNodes(
            SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch) and hasClickAction(),
            useUnmergedTree = true,
        ).onFirst().assertHeightIsAtLeast(48.dp).performClick()
    }

    @Test
    fun 硬件模式具有单选和选中语义() {
        rule.setContent { LanStashTheme { HardwareSettingsDialog(hardware(), hardware().copy(fanMode = "coolfan"), true, {}, { true }, {}) } }
        rule.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.RadioButton), useUnmergedTree = true)
            .onFirst().assertHeightIsAtLeast(48.dp)
        rule.onAllNodes(
            SemanticsMatcher.expectValue(SemanticsProperties.Selected, true),
            useUnmergedTree = true,
        ).onFirst().assertIsDisplayed()
    }

    @Test
    fun 硬件开关在深色2倍密度下整行可操作且达到48dp() {
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 1f)) {
                LanStashTheme(darkTheme = true) {
                    HardwareSettingsDialog(hardware(), hardware().copy(fanMode = "coolfan"), true, {}, { true }, {})
                }
            }
        }
        rule.onAllNodes(
            SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch) and hasClickAction(),
            useUnmergedTree = true,
        ).onFirst().assertHeightIsAtLeast(48.dp).performClick()
    }

    @Test
    fun 安全确认拒绝时保持显示() {
        val context = context()
        var calls = 0
        rule.setContent { LanStashTheme {
            SecurityConfirmationDialog(security(), security().copy(isAutoBlockEnabled = false), { calls += 1; false }, {})
        } }
        rule.onNodeWithText(context.getString(R.string.save)).performClick()
        rule.onNodeWithText(context.getString(R.string.save_security_settings_title)).assertIsDisplayed()
        rule.runOnIdle { check(calls == 1) }

    }

    @Test
    fun 硬件确认拒绝时保持显示() {
        val context = context()
        var calls = 0
        rule.setContent { LanStashTheme {
            HardwareConfirmationDialogForTest(hardware(), hardware().copy(fanMode = "coolfan")) {
                calls += 1
                false
            }
        } }
        rule.onNodeWithText(context.getString(R.string.save)).performClick()
        rule.onNodeWithText(context.getString(R.string.save_hardware_settings_title)).assertIsDisplayed()
        rule.runOnIdle { check(calls == 1) }
    }

    @Test
    fun 未确认结果刷新前禁止离开并播报强提醒() {
        val context = context()
        rule.setContent { LanStashTheme {
            SettingsMutationFeedbackCard(
                result = unverified(), failure = null, refreshFailure = null,
                refreshInProgress = false, refreshCompleted = false, currentMatches = null,
                countsLabel = R.string.security_feedback_counts,
                refreshLabel = R.string.refresh_and_check_security_settings,
                onRefresh = {}, onContinueEditing = {}, onDismiss = {},
            )
        } }
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.discard_changes)).assertIsNotEnabled()
        rule.onNode(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive)).assertIsDisplayed()
    }

    @Test
    fun 电源确认拒绝留框() {
        val context = context()
        rule.setContent { LanStashTheme { PowerActionConfirmationDialog(NasPowerAction.REBOOT, { false }, {}) } }
        rule.onNodeWithText(context.getString(R.string.restart_nas)).performClick()
        rule.onNodeWithText(context.getString(R.string.restart_nas_title)).assertIsDisplayed()

    }

    @Test
    fun 电源成功只说明请求已接受() {
        val context = context()
        rule.setContent { LanStashTheme { PowerActionFeedbackCard(NasPowerAction.REBOOT, success(), null, {}) } }
        rule.onNodeWithText(context.getString(R.string.reboot_accepted)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.power_accepted_not_completed)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.done)).assertIsEnabled()
    }

    @Test
    fun 电源模糊提交要求重新连接核对且没有可用关闭操作() {
        val context = context()
        rule.setContent { LanStashTheme {
            PowerActionFeedbackCard(NasPowerAction.SHUTDOWN, unverified(), null, {})
        } }
        rule.onNodeWithText(context.getString(R.string.power_result_needs_device_check_title)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.power_result_needs_device_check_message)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.done)).assertDoesNotExist()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_settings)).assertDoesNotExist()
        rule.onNode(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive)).assertIsDisplayed()
    }

    @Test
    fun 安全设置覆盖不可用正常保存中成功和异常五状态() {
        val context = context()
        val stage = mutableIntStateOf(0)
        val baseline = security()
        val failure = DsmFailure(
            null,
            "Synthetic security failure",
            "Synthetic recovery",
            kind = DsmErrorKind.CONNECTION_FAILED,
        )
        rule.setContent { LanStashTheme {
            val current = stage.intValue
            SecuritySettingsContent(
                settings = baseline.takeIf { current != 0 },
                settingsAvailable = current != 0,
                fallback = emptyList(),
                baseline = baseline,
                draft = baseline.copy(isAutoBlockEnabled = false),
                mutationInProgress = current == 2,
                mutationResult = success().takeIf { current == 3 },
                mutationFailure = failure.takeIf { current == 4 },
                refreshFailure = null,
                refreshInProgress = false,
                refreshCompleted = current == 3,
                enabled = current == 1,
                onEdit = {}, onRefresh = {}, onContinueEditing = {}, onDismissResult = {},
            )
        } }
        rule.onNodeWithText(context.getString(R.string.security_settings_unavailable)).assertIsDisplayed()
        rule.runOnIdle { stage.intValue = 1 }
        rule.onNodeWithText(context.getString(R.string.security_protection)).assertIsDisplayed()
        rule.runOnIdle { stage.intValue = 2 }
        rule.onNodeWithText(context.getString(R.string.security_saving_title)).assertIsDisplayed()
        rule.runOnIdle { stage.intValue = 3 }
        rule.onNodeWithText(context.getString(R.string.settings_feedback_success_title)).assertIsDisplayed()
        rule.runOnIdle { stage.intValue = 4 }
        rule.onNodeWithText(context.getString(R.string.settings_feedback_failed_title)).assertIsDisplayed()
    }

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun security() = NasSecuritySettings(true, 5, 10, 7, listOf(NasDoSProtectionSetting("eth0", "LAN", true)), true, "Default", true)
    private fun hardware() = NasHardwareSettings(true, 2, 0, 3, "quietfan", true, true, true, true, true, true, true, true, true, true,
        NasUpsSettings(true, "USB", 30, true, false, null, null))
    private fun success() = MutationResult(1, MutationResultStatus.CONFIRMED_SUCCESS, "reboot", true, false, MutationResultCounts(1, 0, 0))
    private fun unverified() = MutationResult(1, MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, "saveSettings", true, true, MutationResultCounts(0, 0, 1))
}

@androidx.compose.runtime.Composable
private fun HardwareConfirmationDialogForTest(
    baseline: NasHardwareSettings,
    draft: NasHardwareSettings,
    onConfirm: () -> Boolean,
) = io.github.qwertyuiop1995.dsmnativeclient.ui.nas.HardwareConfirmationDialog(baseline, draft, onConfirm, {})
