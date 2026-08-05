package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileStationMutationConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileStationMutationFeedbackDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class TextSaveMutationUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 文本覆盖确认复用FileStation确认且操作保持48dp() {
        val context = context()
        var confirms = 0
        var cancels = 0
        rule.setContent {
            LanStashTheme {
                FileStationMutationConfirmationDialog(
                    target = target(),
                    onConfirm = { confirms += 1; true },
                    onDismiss = { cancels += 1; true },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.save_text_changes_title)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.save_text_changes_message)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.replace_existing))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { assertEquals(1, confirms) }
        rule.onNodeWithText(context.getString(R.string.cancel))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { assertEquals(1, cancels) }
    }

    @Test
    fun 深色两倍字体下未确认结果保留刷新入口并强提醒() {
        val context = context()
        var refreshes = 0
        rule.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, fontScale = 2f)) {
                LanStashTheme(darkTheme = true) {
                    Box(Modifier.width(320.dp)) {
                        FileStationMutationFeedbackDialog(
                            state = FileStationMutationWorkspaceState(
                                target = target(),
                                mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
                            ),
                            onRefresh = { refreshes += 1; true },
                            onContinueEditing = { false },
                            onDismiss = { false },
                        )
                    }
                }
            }
        }

        rule.onNodeWithText(context.getString(R.string.text_save_unverified)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_files))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { assertEquals(1, refreshes) }
        rule.onAllNodes(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Assertive,
            ),
            useUnmergedTree = true,
        ).assertCountEquals(1)
    }

    private fun target() = FileStationMutationTarget(
        profileId = "synthetic-profile",
        module = Module.FILES,
        operation = FileStationMutationOperation.TEXT_SAVE,
        sourceBaselines = listOf(
            FileItem(
                path = "/synthetic/readme.txt",
                name = "readme.txt",
                isDirectory = false,
                canRead = true,
                canWrite = true,
            ),
        ),
        expectedContentSha256 = "0".repeat(64),
        expectedContentByteCount = 12,
    )

    private fun result(status: MutationResultStatus) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "textSave",
        counts = MutationResultCounts(succeeded = 0, failed = 0, unknown = 1),
        submitted = true,
        requiresRefresh = true,
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
