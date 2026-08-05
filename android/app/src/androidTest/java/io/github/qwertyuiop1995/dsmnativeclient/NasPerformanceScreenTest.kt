package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.PerformanceSample
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.NasPerformanceScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class NasPerformanceScreenTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 性能页首次加载显示明确状态且不显示无样本恢复操作() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var retries = 0
        rule.setContent {
            LanStashTheme {
                NasPerformanceScreen(
                    history = emptyList(),
                    isLoading = true,
                    error = null,
                    isPaused = false,
                    onStart = {},
                    onStop = {},
                    onTogglePause = {},
                    onRetry = { retries += 1 },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.performance_loading)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.performance_empty)).assertDoesNotExist()
        rule.runOnIdle { check(retries == 0) }
    }

    @Test
    fun 性能页无样本显示原因和恢复操作() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var retries = 0
        rule.setContent {
            LanStashTheme {
                NasPerformanceScreen(
                    history = emptyList(),
                    isLoading = false,
                    error = null,
                    isPaused = false,
                    onStart = {},
                    onStop = {},
                    onTogglePause = {},
                    onRetry = { retries += 1 },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.performance_empty)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.performance_empty_message)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.retry)).performClick()
        rule.runOnIdle { check(retries == 1) }
    }

    @Test
    fun 性能页显示精确当前值趋势文字替代并可暂停() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var starts = 0
        var pauses = 0
        rule.setContent {
            LanStashTheme {
                NasPerformanceScreen(
                    history = listOf(sample(100, 20.0), sample(102, 25.0)),
                    isLoading = false,
                    error = null,
                    isPaused = false,
                    onStart = { starts += 1 },
                    onStop = {},
                    onTogglePause = { pauses += 1 },
                    onRetry = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.cpu_usage)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.percentage_value, 25.0)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.pause)).performClick()
        rule.onNodeWithContentDescription(
            context.getString(R.string.performance_processor_memory_title),
            substring = true,
        ).assertExists()
        rule.runOnIdle {
            check(starts == 1)
            check(pauses == 1)
        }
    }

    @Test
    fun 性能读取失败保留恢复操作并通知屏幕阅读器() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var retries = 0
        rule.setContent {
            LanStashTheme {
                NasPerformanceScreen(
                    history = emptyList(),
                    isLoading = false,
                    error = DsmFailure(null, "Synthetic failure", "Try again."),
                    isPaused = false,
                    onStart = {},
                    onStop = {},
                    onTogglePause = {},
                    onRetry = { retries += 1 },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.performance_error_title)).assertIsDisplayed()
        rule.onNode(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Assertive,
            ),
        ).assertExists()
        rule.onNodeWithText(context.getString(R.string.retry)).performClick()
        rule.runOnIdle { check(retries == 1) }
    }

    @Test
    fun 离开性能页会停止实时采样() {
        var show by mutableStateOf(true)
        var starts = 0
        var stops = 0
        rule.setContent {
            LanStashTheme {
                if (show) {
                    NasPerformanceScreen(
                        history = listOf(sample(100, 20.0)),
                        isLoading = false,
                        error = null,
                        isPaused = false,
                        onStart = { starts += 1 },
                        onStop = { stops += 1 },
                        onTogglePause = {},
                        onRetry = {},
                    )
                }
            }
        }

        rule.runOnIdle { check(starts == 1) }
        rule.runOnUiThread { show = false }
        rule.runOnIdle { check(stops == 1) }
    }

    private fun sample(time: Long, cpu: Double) = PerformanceSample(
        timeEpochSeconds = time,
        cpuPercent = cpu,
        cpuUserPercent = cpu / 2,
        cpuSystemPercent = cpu / 4,
        memoryPercent = 40.0,
        swapPercent = 2.0,
        networkReceiveBytesPerSecond = 1_024,
        networkSendBytesPerSecond = 2_048,
        diskReadBytesPerSecond = 4_096,
        diskWriteBytesPerSecond = 8_192,
        volumeReadBytesPerSecond = 3_000,
        volumeWriteBytesPerSecond = 4_000,
        diskUtilizationPercent = 15.0,
    )
}
