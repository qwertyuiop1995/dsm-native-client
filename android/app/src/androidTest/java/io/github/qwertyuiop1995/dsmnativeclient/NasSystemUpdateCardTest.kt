package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSystemUpdateInfo
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.NasSystemUpdateCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class NasSystemUpdateCardTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 检查期间按钮禁用并显示明确状态() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        rule.setContent {
            LanStashTheme {
                NasSystemUpdateCard(Loadable.Loading, onCheck = {})
            }
        }

        rule.onNodeWithText(context.getString(R.string.checking_system_update)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.system_update_checking_button))
            .assertIsNotEnabled()
    }

    @Test
    fun 可用更新显示版本说明与DSM安装边界() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        rule.setContent {
            LanStashTheme {
                NasSystemUpdateCard(
                    Loadable.Ready(
                        NasSystemUpdateInfo(
                            isUpdateAvailable = true,
                            currentVersion = "DSM 7.2.1",
                            latestVersion = "DSM 7.2.2",
                            releaseNotes = "Synthetic release notes",
                        ),
                    ),
                    onCheck = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.system_update_available)).assertIsDisplayed()
        rule.onNodeWithText(
            context.getString(R.string.system_update_available_version, "DSM 7.2.2"),
        ).assertIsDisplayed()
        rule.onNodeWithText("Synthetic release notes").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.system_update_manage_in_dsm)).assertIsDisplayed()
    }

    @Test
    fun 检查失败提供即时语义通知与手动重试() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var retries = 0
        rule.setContent {
            LanStashTheme {
                NasSystemUpdateCard(
                    Loadable.Failed(
                        DsmFailure(null, "Synthetic failure", "Try again."),
                    ),
                    onCheck = { retries += 1 },
                )
            }
        }

        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Assertive,
            ),
        ).assertExists()
        rule.onNodeWithText(context.getString(R.string.retry)).performClick()
        rule.runOnIdle { check(retries == 1) }
    }
}
