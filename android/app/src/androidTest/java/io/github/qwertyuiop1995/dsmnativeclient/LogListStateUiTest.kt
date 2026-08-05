package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.LogEntry
import io.github.qwertyuiop1995.dsmnativeclient.domain.LogLevel
import io.github.qwertyuiop1995.dsmnativeclient.ui.services.LogList
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class LogListStateUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 源日志为空时说明原因且隐藏筛选控件() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        setLogs(emptyList())

        rule.onNodeWithText(context.getString(R.string.no_log_entries)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.no_log_entries_description)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.no_matching_log_entries)).assertDoesNotExist()
        rule.onNodeWithText(context.getString(R.string.search_logs)).assertDoesNotExist()
        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Polite,
            ),
        ).assertIsDisplayed()
    }

    @Test
    fun 非空日志被搜索筛空时显示可恢复提示和礼貌播报() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        setLogs(listOf(logEntry()))

        rule.onNode(hasSetTextAction()).performTextInput("not-present")

        rule.onNodeWithText(context.getString(R.string.no_matching_log_entries)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.no_matching_log_entries_description))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.no_log_entries)).assertDoesNotExist()
        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Polite,
            ),
        ).assertIsDisplayed()
    }

    @Test
    fun 清除搜索后恢复显示原有日志() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        setLogs(listOf(logEntry()))
        rule.onNode(hasSetTextAction()).performTextInput("not-present")
        rule.onNodeWithText(context.getString(R.string.no_matching_log_entries)).assertIsDisplayed()

        rule.onNode(hasSetTextAction()).performTextClearance()

        rule.onNodeWithText("Synthetic login completed").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.no_matching_log_entries)).assertDoesNotExist()
    }

    @Test
    fun 日志局部读取失败时提供重试且不伪装成源空() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var retryCount = 0
        setLogs(emptyList(), isAvailable = false, onRetry = { retryCount += 1 })

        rule.onNodeWithText(context.getString(R.string.service_section_unavailable_title))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.service_section_unavailable_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.no_log_entries)).assertDoesNotExist()
        rule.onNodeWithText(context.getString(R.string.retry)).performClick()
        assertEquals(1, retryCount)
    }

    @Test
    fun 日志级别暴露选中语义且搜索框具有稳定名称() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        setLogs(listOf(logEntry()))

        val all = rule.onNodeWithText(context.getString(R.string.all))
        val warning = rule.onNodeWithText(context.getString(R.string.warning))
        all.assertIsSelected()
        warning.assertIsNotSelected().performClick()
        warning.assertIsSelected()
        all.assertIsNotSelected()
        rule.onNode(
            hasSetTextAction() and hasText(context.getString(R.string.search_logs)),
        ).assertIsDisplayed()
    }

    private fun setLogs(
        logs: List<LogEntry>,
        isAvailable: Boolean = true,
        onRetry: () -> Unit = {},
    ) {
        rule.setContent {
            LanStashTheme {
                LogList(logs, isAvailable, onRetry)
            }
        }
    }

    private fun logEntry() = LogEntry(
        id = "synthetic-log",
        level = LogLevel.INFO,
        timeEpochSeconds = 1_700_000_000,
        user = "synthetic-user",
        event = "Synthetic login completed",
    )
}
