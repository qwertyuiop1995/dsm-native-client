package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileTypeFilter
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileBrowserScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class FileFilteredEmptyStateTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 文件筛选无结果说明原因和下一步() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
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
                        files = Loadable.Ready(
                            FilePage(
                                items = listOf(
                                    FileItem("/folder", "folder", isDirectory = true),
                                ),
                                offset = 0,
                                total = 1,
                            ),
                        ),
                        fileBrowser = FileBrowserState(typeFilter = FileTypeFilter.FILES),
                    ),
                    model = model,
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.no_items_match_filter)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.change_file_filter_hint)).assertIsDisplayed()
    }
}
