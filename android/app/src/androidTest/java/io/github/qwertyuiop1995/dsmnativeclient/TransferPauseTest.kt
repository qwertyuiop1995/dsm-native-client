package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import io.github.qwertyuiop1995.dsmnativeclient.ui.transfers.TransferActions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class TransferPauseTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 普通下载等待时显示暂停操作() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var paused = false
        rule.setContent {
            LanStashTheme {
                TransferActions(
                    state = TransferState.WAITING,
                    direction = TransferDirection.DOWNLOAD,
                    canPause = true,
                    canResume = false,
                    canRetry = false,
                    onPause = { paused = true },
                    onResume = {},
                    onCancel = {},
                    onRetry = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.pause_download))
            .assertIsDisplayed()
            .assertIsEnabled()
            .performClick()
        rule.runOnIdle { assertTrue(paused) }
        assertTextAbsent(context.getString(R.string.cancel))
    }

    @Test
    fun 已暂停下载显示继续和取消操作() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var resumeCount = 0
        var cancelCount = 0
        rule.setContent {
            LanStashTheme {
                TransferActions(
                    state = TransferState.PAUSED,
                    direction = TransferDirection.DOWNLOAD,
                    canPause = false,
                    canResume = true,
                    canRetry = false,
                    onPause = {},
                    onResume = { resumeCount += 1 },
                    onCancel = { cancelCount += 1 },
                    onRetry = {},
                )
            }
        }

        val resumeText = context.getString(R.string.resume_download)
        val cancelText = context.getString(R.string.cancel)
        assertAccessibleAction(resumeText)
        rule.onNodeWithText(resumeText).assertIsEnabled().performClick()
        rule.runOnIdle {
            assertEquals(1, resumeCount)
            assertEquals(0, cancelCount)
        }

        assertAccessibleAction(cancelText)
        rule.onNodeWithText(cancelText).assertIsEnabled().performClick()
        rule.runOnIdle {
            assertEquals(1, resumeCount)
            assertEquals(1, cancelCount)
        }
        assertTextAbsent(context.getString(R.string.retry_from_start))
    }

    @Test
    fun 不支持暂停的运行任务只显示取消操作() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        rule.setContent {
            LanStashTheme {
                TransferActions(
                    state = TransferState.RUNNING,
                    direction = TransferDirection.UPLOAD,
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

        rule.onNodeWithText(context.getString(R.string.cancel)).assertIsDisplayed()
        assertTextAbsent(context.getString(R.string.pause_download))
        assertTextAbsent(context.getString(R.string.resume_download))
    }

    @Test
    fun 上传失败仍显示从头重试() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var retryCount = 0
        rule.setContent {
            LanStashTheme {
                TransferActions(
                    state = TransferState.FAILED,
                    direction = TransferDirection.UPLOAD,
                    canPause = false,
                    canResume = false,
                    canRetry = true,
                    onPause = {},
                    onResume = {},
                    onCancel = {},
                    onRetry = { retryCount += 1 },
                )
            }
        }

        val retryText = context.getString(R.string.retry_from_start)
        assertAccessibleAction(retryText)
        rule.onNodeWithText(retryText).performClick()
        rule.runOnIdle { assertEquals(1, retryCount) }
        assertTextAbsent(context.getString(R.string.pause_download))
        assertTextAbsent(context.getString(R.string.resume_download))
    }

    @Test
    fun 下载失败显示继续下载而不宣称从头开始() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var retryCount = 0
        rule.setContent {
            LanStashTheme {
                TransferActions(
                    state = TransferState.FAILED,
                    direction = TransferDirection.DOWNLOAD,
                    canPause = false,
                    canResume = false,
                    canRetry = true,
                    onPause = {},
                    onResume = {},
                    onCancel = {},
                    onRetry = { retryCount += 1 },
                )
            }
        }

        val retryText = context.getString(R.string.resume_download)
        assertAccessibleAction(retryText)
        rule.onNodeWithText(retryText).performClick()
        rule.runOnIdle { assertEquals(1, retryCount) }
        assertTextAbsent(context.getString(R.string.retry_from_start))
    }

    private fun assertAccessibleAction(text: String) {
        rule.onNodeWithText(text)
            .assertIsDisplayed()
            .assertHasClickAction()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
    }

    private fun assertTextAbsent(text: String) {
        rule.onAllNodesWithText(text).fetchSemanticsNodes().also { nodes ->
            assertTrue("不应显示：$text", nodes.isEmpty())
        }
    }
}
