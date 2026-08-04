package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileBrowserScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class FileSelectionToolbarTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 顶部关闭选择只清除选择并保留当前位置() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val selectedItem = FileItem(
            path = "/synthetic/folder/item.txt",
            name = "Synthetic item.txt",
            isDirectory = false,
            size = 1,
            canRead = true,
        )
        val browser = FileBrowserState(
            path = "/synthetic/folder",
            pathHistory = listOf(""),
            selectedPaths = setOf(selectedItem.path),
        )
        val state = WorkspaceState(
            profile = NasProfile(
                "synthetic-file-selection",
                "Synthetic",
                "https://nas.example.invalid",
                "operator",
            ),
            selectedModule = Module.FILES,
            fileBrowser = browser,
            files = Loadable.Ready(FilePage(listOf(selectedItem), 1, 0)),
        )
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        workspace(model).value = state
        rule.setContent {
            LanStashTheme {
                FileBrowserScreen(state = state, model = model)
            }
        }

        rule.onNodeWithContentDescription(context.getString(R.string.clear_selection))
            .performClick()
        rule.waitForIdle()

        val result = workspace(model).value!!.fileBrowser
        assertEquals(browser.path, result.path)
        assertEquals(browser.pathHistory, result.pathHistory)
        assertTrue(result.selectedPaths.isEmpty())
    }

    @Suppress("UNCHECKED_CAST")
    private fun workspace(model: AppViewModel): MutableStateFlow<WorkspaceState?> {
        val field = AppViewModel::class.java.getDeclaredField("_workspace").apply {
            isAccessible = true
        }
        return field.get(model) as MutableStateFlow<WorkspaceState?>
    }
}
