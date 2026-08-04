package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasEthernetInterface
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.EthernetConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.EthernetEditDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class EthernetConfirmationRestorationTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 网卡草稿和确认阶段跨保存状态重建且确认拒绝时留框() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val restoration = StateRestorationTester(rule)
        val baseline = ethernet()
        var confirmationCalls = 0
        restoration.setContent {
            var mtu by rememberSaveable { mutableIntStateOf(baseline.mtu) }
            var phase by rememberSaveable { mutableIntStateOf(0) }
            val draft = baseline.copy(mtu = mtu)
            LanStashTheme {
                if (phase == 0) {
                    EthernetEditDialog(
                        initial = baseline,
                        draft = draft,
                        enabled = true,
                        onDraftChange = { mtu = it.mtu },
                        onContinue = {
                            phase = 1
                            true
                        },
                        onDismiss = {},
                    )
                } else {
                    EthernetConfirmationDialog(
                        baseline = baseline,
                        draft = draft,
                        onConfirm = {
                            confirmationCalls += 1
                            false
                        },
                        onDismiss = { phase = 0 },
                    )
                }
            }
        }

        rule.onNodeWithText("1500").performTextReplacement("1400")
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText("1400").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_action)).performClick()
        rule.onNodeWithText(
            context.getString(R.string.save_network_interface_title, baseline.displayName),
        ).assertIsDisplayed()

        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.save_network_settings)).performClick()
        rule.onNodeWithText(
            context.getString(R.string.save_network_interface_title, baseline.displayName),
        ).assertIsDisplayed()
        rule.runOnIdle { check(confirmationCalls == 1) }
    }

    private fun ethernet() = NasEthernetInterface(
        id = "eth0",
        displayName = "Synthetic LAN",
        status = "connected",
        usesDhcp = false,
        address = "192.0.2.10",
        subnetMask = "255.255.255.0",
        gateway = "192.0.2.1",
        dnsServers = "192.0.2.1",
        isDefaultGateway = true,
        mtu = 1_500,
        isVlanEnabled = false,
        vlanId = null,
    )
}
