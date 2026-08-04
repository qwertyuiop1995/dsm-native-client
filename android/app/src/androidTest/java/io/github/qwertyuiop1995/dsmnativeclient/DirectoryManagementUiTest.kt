package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasAccount
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DirectoryAccountRow
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.DirectoryDeletionConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.ManagementMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.ManagementTargetState
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class DirectoryManagementUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 删除是独立Role按钮并在深色2倍字体达到48dp() {
        val context = context()
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 2f)) {
                LanStashTheme(darkTheme = true) { DirectoryAccountRow(account(), true, {}) }
            }
        }
        rule.onNodeWithContentDescription(context.getString(R.string.delete_account_description, account().name))
            .assertHeightIsAtLeast(48.dp)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, androidx.compose.ui.semantics.Role.Button))
    }

    @Test
    fun 确认拒绝和保存状态恢复后弹窗仍保留() {
        val context = context()
        val restoration = StateRestorationTester(rule)
        var calls = 0
        restoration.setContent {
            var visible by rememberSaveable { mutableStateOf(true) }
            LanStashTheme {
                if (visible) DirectoryDeletionConfirmationDialog(
                    DirectoryEntryMutationTarget(DirectoryEntryKind.ACCOUNT, account = account()),
                    onConfirm = { calls += 1; false },
                    onDismiss = { visible = false },
                )
            }
        }
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.delete_account)).performClick()
        rule.onNodeWithText(context.getString(R.string.delete_account_title, account().name)).assertIsDisplayed()
        rule.runOnIdle { check(calls == 1) }
    }

    @Test
    fun 未确认结果显示计数强提醒且刷新前禁止继续和关闭() {
        val context = context()
        rule.setContent { LanStashTheme {
            ManagementMutationFeedbackCard(
                targetName = account().name,
                result = unverified(), failure = null, refreshFailure = null,
                refreshInProgress = false, refreshCompleted = false,
                targetState = ManagementTargetState.UNAVAILABLE,
                countsLabel = R.string.directory_feedback_counts,
                refreshLabel = R.string.refresh_and_check_directory,
                onRefresh = {}, onContinue = {}, onCloseResult = {},
            )
        } }
        rule.onNodeWithText(context.getString(R.string.directory_feedback_counts, 0, 0, 1)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_managing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.close_result)).assertIsNotEnabled()
        rule.onNode(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive)).assertIsDisplayed()
    }

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun account() = NasAccount(1, "Synthetic operator", "Synthetic account", null, false, true)
    private fun unverified() = MutationResult(
        1, MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, "accountDelete", true, true,
        MutationResultCounts(0, 0, 1),
    )
}
