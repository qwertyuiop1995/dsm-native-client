package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDiskTestStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasDiskTestType
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasStorageDisk
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SmartTestConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SmartTestDiskCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.SmartTestManagementContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class SmartTestManagementUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 三类动作是目标化Role按钮并在深色2倍字体达到48dp() {
        val context = context()
        val running = mutableStateOf(false)
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(2f, 2f)) {
                LanStashTheme(darkTheme = true) {
                    SmartTestDiskCard(
                        disk(),
                        Loadable.Ready(status(running.value)),
                        enabled = true,
                        onLoad = {},
                        onRequest = {},
                    )
                }
            }
        }
        listOf(
            R.string.quick_smart_test_description,
            R.string.extended_smart_test_description,
        ).forEach { label ->
            rule.onNodeWithContentDescription(context.getString(label, disk().name))
                .assertHeightIsAtLeast(48.dp)
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        }
        rule.runOnIdle { running.value = true }
        rule.onNodeWithContentDescription(context.getString(R.string.stop_smart_test_description, disk().name))
            .assertHeightIsAtLeast(48.dp)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
    }

    @Test
    fun 确认返回false和保存状态恢复后仍保留完整硬盘目标() {
        val context = context()
        val restoration = StateRestorationTester(rule)
        var calls = 0
        restoration.setContent {
            var visible by rememberSaveable { mutableStateOf(true) }
            LanStashTheme {
                if (visible) SmartTestConfirmationDialog(
                    disk(), NasDiskTestType.EXTENDED,
                    onConfirm = { calls += 1; false },
                    onDismiss = { visible = false },
                )
            }
        }
        restoration.emulateSavedInstanceStateRestore()
        rule.onNodeWithText(context.getString(R.string.extended_test)).performClick()
        rule.onNodeWithText(context.getString(R.string.smart_test_target_summary, disk().name, disk().model)).assertIsDisplayed()
        rule.runOnIdle { check(calls == 1) }
    }

    @Test
    fun 空不可用加载错误和正常状态都有恢复路径() {
        val context = context()
        val stage = mutableIntStateOf(0)
        rule.setContent { LanStashTheme {
            val disks = when (stage.intValue) {
                0 -> emptyList()
                1 -> listOf(disk().copy(supportsSmartTest = false))
                else -> listOf(disk())
            }
            val statuses = when (stage.intValue) {
                2 -> mapOf(disk().id to Loadable.Loading)
                3 -> mapOf(disk().id to Loadable.Failed(DsmFailure(null, "Synthetic failure", "Retry")))
                4 -> mapOf(disk().id to Loadable.Ready(status(false)))
                else -> emptyMap()
            }
            content(disks, statuses)
        } }
        rule.onNodeWithText(context.getString(R.string.smart_test_empty_title)).assertIsDisplayed()
        rule.runOnIdle { stage.intValue = 1 }
        rule.onNodeWithText(context.getString(R.string.smart_test_all_unavailable_title)).assertIsDisplayed()
        rule.runOnIdle { stage.intValue = 2 }
        rule.onNodeWithText(context.getString(R.string.smart_test_loading_title)).assertIsDisplayed()
        rule.runOnIdle { stage.intValue = 3 }
        rule.onNodeWithContentDescription(context.getString(R.string.retry_smart_test_description, disk().name)).assertIsDisplayed()
        rule.runOnIdle { stage.intValue = 4 }
        rule.onNodeWithContentDescription(context.getString(R.string.quick_smart_test_description, disk().name)).assertIsDisplayed()
    }

    @Test
    fun 不可信状态只显示可访问的刷新操作() {
        val context = context()
        val invalidStatus = mutableStateOf(status(false).copy(diskId = "different-disk"))
        rule.setContent { LanStashTheme {
            SmartTestDiskCard(
                disk = disk(),
                status = Loadable.Ready(invalidStatus.value),
                enabled = true,
                onLoad = {},
                onRequest = {},
            )
        } }

        fun assertOnlyRefreshIsAvailable() {
            rule.onNodeWithText(context.getString(R.string.smart_test_status_unavailable_title)).assertIsDisplayed()
            rule.onNode(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive))
                .assertIsDisplayed()
            rule.onNodeWithContentDescription(context.getString(R.string.refresh_smart_test_description, disk().name))
                .assertIsDisplayed()
                .assertHeightIsAtLeast(48.dp)
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            rule.onNodeWithContentDescription(context.getString(R.string.quick_smart_test_description, disk().name))
                .assertDoesNotExist()
            rule.onNodeWithContentDescription(context.getString(R.string.extended_smart_test_description, disk().name))
                .assertDoesNotExist()
            rule.onNodeWithContentDescription(context.getString(R.string.stop_smart_test_description, disk().name))
                .assertDoesNotExist()
        }

        assertOnlyRefreshIsAvailable()
        rule.runOnIdle {
            invalidStatus.value = status(true).copy(isBusyWithOtherTest = true)
        }
        assertOnlyRefreshIsAvailable()
    }

    @Test
    fun 未确认结果显示计数强提醒且刷新前禁止继续和关闭() {
        val context = context()
        rule.setContent { LanStashTheme {
            content(
                disks = listOf(disk()),
                statuses = mapOf(disk().id to Loadable.Ready(status(false))),
                target = disk(),
                type = NasDiskTestType.QUICK,
                result = unverified(),
            )
        } }
        rule.onNodeWithText(context.getString(R.string.smart_test_feedback_counts, 0, 0, 1)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_managing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.close_result)).assertIsNotEnabled()
        rule.onNode(SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive)).assertIsDisplayed()
    }

    @Test
    fun 专项刷新完成后继续和关闭均可用() {
        val context = context()
        rule.setContent { LanStashTheme {
            content(
                disks = listOf(disk()),
                statuses = mapOf(disk().id to Loadable.Ready(status(false))),
                target = disk(),
                type = NasDiskTestType.QUICK,
                result = unverified(),
                refreshCompleted = true,
            )
        } }
        rule.onNodeWithText(context.getString(R.string.continue_managing)).assertIsEnabled()
        rule.onNodeWithText(context.getString(R.string.close_result)).assertIsEnabled()
    }

    @Test
    fun 专项刷新失败时结果保留且仍禁止离开() {
        val context = context()
        rule.setContent { LanStashTheme {
            content(
                disks = listOf(disk()),
                statuses = mapOf(disk().id to Loadable.Ready(status(false))),
                target = disk(),
                type = NasDiskTestType.QUICK,
                result = unverified(),
                refreshFailure = DsmFailure(null, "Synthetic refresh failure", "Retry"),
            )
        } }
        rule.onNodeWithText(context.getString(R.string.continue_managing)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.close_result)).assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_smart_test)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.smart_test_feedback_counts, 0, 0, 1)).assertIsDisplayed()
    }

    @androidx.compose.runtime.Composable
    private fun content(
        disks: List<NasStorageDisk>,
        statuses: Map<String, Loadable<NasDiskTestStatus>>,
        target: NasStorageDisk? = null,
        type: NasDiskTestType? = null,
        result: MutationResult? = null,
        refreshCompleted: Boolean = false,
        refreshFailure: DsmFailure? = null,
    ) = SmartTestManagementContent(
        disks = disks,
        statuses = statuses,
        target = target,
        baseline = status(false),
        type = type,
        mutationInProgress = false,
        result = result,
        failure = null,
        refreshFailure = refreshFailure,
        refreshInProgress = false,
        refreshCompleted = refreshCompleted,
        enabled = true,
        onLoad = {},
        onRequest = { _, _ -> },
        onRefresh = {},
        onContinue = {},
        onCloseResult = {},
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun disk() = NasStorageDisk(
        id = "disk-1", deviceId = "synthetic-device", name = "Synthetic drive", model = "Example",
        status = "normal", smartStatus = "normal", temperatureCelsius = 30.0, supportsSmartTest = true,
    )

    private fun status(running: Boolean) = NasDiskTestStatus(
        diskId = "disk-1", isRunning = running, isBusyWithOtherTest = false,
        runningType = NasDiskTestType.QUICK.takeIf { running }, progressDescription = "50%",
        lastQuickTest = null, lastExtendedTest = null, lastResult = null, isHistoryAvailable = true,
    )

    private fun unverified() = MutationResult(
        1, MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, "smartTest", true, true,
        MutationResultCounts(0, 0, 1),
    )
}
