package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePreviewContent
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileBrowserScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

class FileBrowserAdaptiveScreenTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 宽屏文件列表和预览同时可见() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assumeTrue(context.resources.configuration.screenWidthDp >= 1_120)
        val previewItem = FileItem(
            path = "/synthetic/readme.txt",
            name = "Synthetic preview file.txt",
            isDirectory = false,
            size = 22,
            canRead = true,
        )
        val folder = FileItem(
            path = "/synthetic/folder",
            name = "Synthetic list folder",
            isDirectory = true,
            canRead = true,
        )
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        rule.setContent {
            LanStashTheme {
                FileBrowserScreen(
                    state = WorkspaceState(
                        profile = NasProfile(
                            "synthetic",
                            "Synthetic",
                            "https://nas.example.invalid",
                            "operator",
                        ),
                        files = Loadable.Ready(FilePage(listOf(folder, previewItem), 2, 0)),
                        previewItem = previewItem,
                        previewOwner = PreviewOwner.FILES,
                        preview = Loadable.Ready(
                            FilePreviewContent.Text(
                                item = previewItem,
                                value = "Synthetic inline preview",
                                truncated = false,
                            ),
                        ),
                    ),
                    model = model,
                )
            }
        }

        rule.onNodeWithText("Synthetic list folder").assertIsDisplayed()
        rule.onNodeWithText("Synthetic inline preview").assertIsDisplayed()
    }

    @Test
    fun 页面实际宽度收窄后改用全屏预览() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assumeTrue(context.resources.configuration.screenWidthDp >= 1_120)
        val previewItem = FileItem(
            path = "/synthetic/readme.txt",
            name = "Synthetic constrained file.txt",
            isDirectory = false,
            canRead = true,
        )
        val folder = FileItem(
            path = "/synthetic/folder",
            name = "Synthetic constrained folder",
            isDirectory = true,
            canRead = true,
        )
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        var availableWidth by mutableStateOf(1_120.dp)
        rule.setContent {
            LanStashTheme {
                Box(Modifier.width(availableWidth).fillMaxHeight()) {
                    FileBrowserScreen(
                        state = WorkspaceState(
                            profile = NasProfile(
                                "synthetic",
                                "Synthetic",
                                "https://nas.example.invalid",
                                "operator",
                            ),
                            files = Loadable.Ready(FilePage(listOf(folder, previewItem), 2, 0)),
                            previewItem = previewItem,
                            previewOwner = PreviewOwner.FILES,
                            preview = Loadable.Ready(
                                FilePreviewContent.Text(
                                    item = previewItem,
                                    value = "Synthetic constrained preview",
                                    truncated = false,
                                ),
                            ),
                        ),
                        model = model,
                    )
                }
            }
        }

        rule.onNode(isDialog()).assertDoesNotExist()
        rule.onNodeWithText("Synthetic constrained folder").assertIsDisplayed()
        rule.onNodeWithText("Synthetic constrained preview").assertIsDisplayed()

        rule.runOnIdle { availableWidth = 700.dp }

        rule.onNode(isDialog()).assertExists()
        rule.onNodeWithText("Synthetic constrained preview").assertIsDisplayed()
    }
}
