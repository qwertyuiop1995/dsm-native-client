package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.getValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDoSProtectionSetting
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasHardwareSettings
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasPowerAction
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasUpsSettings
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.HardwareConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.HardwareSettingsDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.PowerActionConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSecuritySettings
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SecurityConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SecuritySettingsDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class SecurityHardwareRestorationTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 安全草稿和确认阶段由可保存状态恢复() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val restoration = StateRestorationTester(rule)
        val baseline = NasSecuritySettings(true, 5, 10, null, listOf(NasDoSProtectionSetting("eth0", "LAN", true)), true, "Default", true)
        restoration.setContent {
            var autoBlock by rememberSaveable { mutableStateOf(true) }
            var confirmation by rememberSaveable { mutableStateOf(false) }
            val draft = baseline.copy(isAutoBlockEnabled = autoBlock)
            LanStashTheme {
                if (confirmation) SecurityConfirmationDialog(baseline, draft, { false }, { confirmation = false })
                else SecuritySettingsDialog(baseline, draft, true, { autoBlock = it.isAutoBlockEnabled }, { confirmation = true; true }, {})
            }
        }
        rule.onNodeWithText(context.getString(R.string.auto_block)).performClick()
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.continue_action)).performClick()
        rule.onNodeWithText(context.getString(R.string.save_security_settings_title)).assertIsDisplayed()
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.save_security_settings_title)).assertIsDisplayed()
    }

    @Test
    fun 硬件草稿和确认阶段由可保存状态恢复() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val restoration = StateRestorationTester(rule)
        val baseline = hardware()
        restoration.setContent {
            var fanMode by rememberSaveable { mutableStateOf("quietfan") }
            var confirmation by rememberSaveable { mutableStateOf(false) }
            val draft = baseline.copy(fanMode = fanMode)
            LanStashTheme {
                if (confirmation) HardwareConfirmationDialog(baseline, draft, { false }, { confirmation = false })
                else HardwareSettingsDialog(baseline, draft, true, { fanMode = it.fanMode.orEmpty() }, { confirmation = true; true }, {})
            }
        }
        rule.onNodeWithText(context.getString(R.string.fan_cool)).performClick()
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.continue_action)).performClick()
        rule.onNodeWithText(context.getString(R.string.save_hardware_settings_title)).assertIsDisplayed()
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.save_hardware_settings_title)).assertIsDisplayed()
    }

    @Test
    fun 电源确认目标由可保存状态恢复且拒绝确认留框() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val restoration = StateRestorationTester(rule)
        restoration.setContent {
            var actionName by rememberSaveable { mutableStateOf(NasPowerAction.REBOOT.name) }
            LanStashTheme {
                PowerActionConfirmationDialog(
                    action = NasPowerAction.valueOf(actionName),
                    onConfirm = { false },
                    onDismiss = { actionName = NasPowerAction.SHUTDOWN.name },
                )
            }
        }
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.restart_nas)).performClick()
        rule.onNodeWithText(context.getString(R.string.restart_nas_title)).assertIsDisplayed()
    }

    private fun hardware() = NasHardwareSettings(
        true, 2, 0, 3, "quietfan", true, true, true, true, true,
        true, true, true, true, true,
        NasUpsSettings(true, "USB", 30, true, false, null, null),
    )
}
