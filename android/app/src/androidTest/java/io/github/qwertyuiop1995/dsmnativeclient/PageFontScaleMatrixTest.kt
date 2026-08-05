package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasSettingsSnapshot
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.NasPerformanceScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.NasSettingsScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import io.github.qwertyuiop1995.dsmnativeclient.ui.transfers.TransfersScreen
import org.junit.Rule
import org.junit.Test

/** 主页面在 2× 字体和 360dp 宽度下的可达性补充矩阵。 */
class PageFontScaleMatrixTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 传输页两倍字体可进入文件任务错误状态并到达恢复操作() {
        val context = context()
        val model = model()
        val state = workspace().copy(
            selectedModule = io.github.qwertyuiop1995.dsmnativeclient.domain.Module.TRANSFERS,
            fileBackgroundTasks = Loadable.Failed(failure()),
        )
        setTwoXContent { TransfersScreen(state, model) }

        rule.onNode(
            hasText(context.getString(R.string.file_background_tasks_title)) and hasClickAction(),
        )
            .performScrollTo()
            .performClick()
            .assertIsSelected()
        rule.onNodeWithText(context.getString(R.string.operation_not_completed))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.try_again_later))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.retry)).assertIsDisplayed()
    }

    @Test
    fun 性能页两倍字体错误标题和恢复操作可通过真实滚动到达() {
        val context = context()
        setTwoXContent {
            NasPerformanceScreen(
                history = emptyList(),
                isLoading = false,
                error = failure(),
                isPaused = false,
                onStart = {},
                onStop = {},
                onTogglePause = {},
                onRetry = {},
            )
        }

        rule.onNodeWithText(context.getString(R.string.performance)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.performance_error_title))
            .performScrollTo()
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.retry))
            .performScrollTo()
            .assertIsDisplayed()
    }

    @Test
    fun 设置页两倍字体可进入真实日志页签并到达恢复操作() {
        val context = context()
        val model = model()
        val state = workspace().copy(
            selectedModule = io.github.qwertyuiop1995.dsmnativeclient.domain.Module.NAS_SETTINGS,
            nasSettings = Loadable.Ready(nasSnapshot(logsAvailable = false)),
        )
        setTwoXContent { NasSettingsScreen(state, model) }

        rule.onNodeWithText(context.getString(R.string.logs))
            .performScrollTo()
            .performClick()
            .assertIsSelected()
        rule.onNodeWithText(context.getString(R.string.service_section_unavailable_title))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.retry)).assertIsDisplayed()
    }

    private fun setTwoXContent(content: @Composable () -> Unit) {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale = 2f),
            ) {
                LanStashTheme {
                    Box(Modifier.width(360.dp).height(640.dp)) { content() }
                }
            }
        }
    }

    private fun workspace() = WorkspaceState(
        profile = NasProfile(
            id = "synthetic",
            name = "Synthetic NAS",
            address = "https://nas.example.invalid",
            username = "operator",
        ),
    )

    private fun nasSnapshot(logsAvailable: Boolean) = NasSettingsSnapshot(
        system = null,
        volumes = emptyList(),
        pools = emptyList(),
        disks = emptyList(),
        storageDisks = emptyList(),
        packages = emptyList(),
        scheduledTasks = emptyList(),
        accounts = emptyList(),
        groups = emptyList(),
        logs = emptyList(),
        connections = emptyList(),
        connectionsAvailable = true,
        networkInterfaces = emptyList(),
        networkInterfacesAvailable = true,
        ddnsDirectory = null,
        ddnsDirectoryAvailable = true,
        fileServiceSettings = null,
        terminalSettings = null,
        proxySettings = null,
        regionSettings = null,
        securitySettings = null,
        hardwareSettings = null,
        security = emptyList(),
        logsAvailable = logsAvailable,
    )

    private fun failure() = DsmFailure(
        code = null,
        message = "Synthetic failure",
        recovery = "Synthetic recovery",
    )

    private fun model() = AppViewModel(
        ApplicationProvider.getApplicationContext<Application>(),
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
