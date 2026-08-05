package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.PackageInfo
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.PackageManagementContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.PackageManagementRow
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.PackageMutationConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class PackageManagementUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 套件动作是独立Role按钮并在深色2倍字体达到48dp() {
        val context = context()
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 2f)) {
                LanStashTheme(darkTheme = true) { PackageManagementRow(pkg(), true, { _, _ -> }) }
            }
        }
        rule.onNodeWithContentDescription(context.getString(R.string.start_package_description, pkg().name))
            .assertHeightIsAtLeast(48.dp)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
    }

    @Test
    fun 危险确认拒绝和保存状态恢复后弹窗仍保留() {
        val context = context()
        val restoration = StateRestorationTester(rule)
        var calls = 0
        restoration.setContent {
            var visible by rememberSaveable { mutableStateOf(true) }
            LanStashTheme {
                if (visible) PackageMutationConfirmationDialog(
                    pkg(), PackageMutationOperation.UNINSTALL,
                    onConfirm = { calls += 1; false }, onDismiss = { visible = false },
                )
            }
        }
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.uninstall)).performClick()
        rule.onNodeWithText(context.getString(R.string.uninstall_package_title, pkg().name)).assertIsDisplayed()
        rule.runOnIdle { check(calls == 1) }
    }

    @Test
    fun 套件不可用可信空正常和保存中状态文案明确() {
        val context = context()
        val stage = mutableStateOf(0)
        rule.setContent { LanStashTheme {
            PackageManagementContent(
                packages = if (stage.value == 2) listOf(pkg()) else emptyList(),
                packagesAvailable = stage.value != 0,
                target = pkg().takeIf { stage.value == 3 },
                operation = PackageMutationOperation.START.takeIf { stage.value == 3 },
                mutationInProgress = stage.value == 3,
                result = null, failure = null, refreshFailure = null,
                refreshInProgress = false, refreshCompleted = false,
                enabled = stage.value == 2,
                onRequest = { _, _ -> }, onRefresh = {}, onContinue = {}, onCloseResult = {},
            )
        } }
        rule.onNodeWithText(context.getString(R.string.packages_unavailable)).assertIsDisplayed()
        rule.runOnIdle { stage.value = 1 }
        rule.onNodeWithText(context.getString(R.string.packages_empty)).assertIsDisplayed()
        rule.runOnIdle { stage.value = 2 }
        rule.onNodeWithText(pkg().name).assertIsDisplayed()
        rule.runOnIdle { stage.value = 3 }
        rule.onNodeWithText(context.getString(R.string.package_action_in_progress)).assertIsDisplayed()
    }

    @Test
    fun 只有服务端明确允许升级时显示DSM只读更新提示() {
        val context = context()
        rule.setContent {
            LanStashTheme {
                PackageManagementRow(
                    packageInfo = pkg().copy(isUpgradeAvailable = true),
                    enabled = true,
                    onRequest = { _, _ -> },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.package_upgrade_available)).assertIsDisplayed()
    }

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun pkg() = PackageInfo(
        "synthetic-package", "Synthetic Package", "1.0", ResourceState.STOPPED,
        "Synthetic package", true, false, true,
    )
}
