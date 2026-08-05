package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationLifecycle
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationTarget
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferTask
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import io.github.qwertyuiop1995.dsmnativeclient.ui.transfers.TransferTaskCard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class TransferTargetRefreshUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 深色两倍字体与320dp下恢复操作位于卡片底部且不显示路径或任务Id() {
        val context = context()
        var refreshes = 0
        rule.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, fontScale = 2f)) {
                LanStashTheme(darkTheme = true) {
                    Box(Modifier.width(320.dp)) {
                        TransferTaskCard(
                            task = task(withTarget = true),
                            canPause = false,
                            canResume = false,
                            canRetry = false,
                            onPause = {},
                            onResume = {},
                            onCancel = {},
                            onRetry = {},
                            canRefreshTarget = true,
                            onOpenAndRefreshTarget = { refreshes += 1 },
                        )
                    }
                }
            }
        }

        val action = rule.onNodeWithText(context.getString(R.string.open_and_refresh_affected_folder))
            .assertIsDisplayed()
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .fetchSemanticsNode()
        val detail = rule.onNodeWithText("Synthetic archive result").fetchSemanticsNode()
        assertTrue(action.boundsInRoot.top >= detail.boundsInRoot.bottom)
        rule.onAllNodesWithText("private-task-id").assertCountEquals(0)
        rule.onAllNodesWithText("/private/affected/folder").assertCountEquals(0)
        rule.onNodeWithText(context.getString(R.string.open_and_refresh_affected_folder)).performClick()
        rule.runOnIdle { assertEquals(1, refreshes) }
    }

    @Test
    fun 没有恢复目标时不显示不可执行操作() {
        val context = context()
        rule.setContent {
            LanStashTheme {
                TransferTaskCard(
                    task = task(withTarget = false),
                    canPause = false,
                    canResume = false,
                    canRetry = false,
                    onPause = {},
                    onResume = {},
                    onCancel = {},
                    onRetry = {},
                )
            }
        }

        rule.onAllNodesWithText(context.getString(R.string.open_and_refresh_affected_folder))
            .assertCountEquals(0)
    }

    private fun task(withTarget: Boolean) = TransferTask(
        id = "private-task-id",
        title = "Archive task",
        detail = "Synthetic archive result",
        direction = TransferDirection.SERVER,
        state = TransferState.FAILED,
        errorMessage = "Synthetic result needs review",
        requiresRefresh = true,
        fileServerMutation = if (withTarget) {
            FileServerMutationLifecycle(
                target = FileServerMutationTarget(
                    profileId = "synthetic-profile",
                    module = Module.FILES,
                    operation = FileServerMutationOperation.COMPRESS,
                    sourceBaselines = listOf(
                        FileItem("/private/source.txt", "source.txt", false, canRead = true),
                    ),
                    destinationFolderBaseline = FileItem(
                        "/private/affected/folder",
                        "folder",
                        true,
                        canRead = true,
                        canWrite = true,
                    ),
                ),
            )
        } else null,
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
