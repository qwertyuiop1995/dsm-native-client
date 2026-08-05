package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.ui.PageStateContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.PageUiState
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class PageStateContentFiveStateTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 通用容器显示可访问的加载状态() {
        setState(PageUiState.Loading)
        val context = InstrumentationRegistry.getInstrumentation().targetContext

        rule.onNodeWithContentDescription(context.getString(R.string.loading)).assertIsDisplayed()
    }

    @Test
    fun 通用容器区分源内容为空() {
        setState(PageUiState.Empty)

        rule.onNodeWithText("synthetic-empty-title").assertIsDisplayed()
        rule.onNodeWithText("synthetic-empty-message").assertIsDisplayed()
    }

    @Test
    fun 通用容器区分筛选后为空() {
        setState(PageUiState.FilteredEmpty)

        rule.onNodeWithText("synthetic-filtered-title").assertIsDisplayed()
        rule.onNodeWithText("synthetic-filtered-message").assertIsDisplayed()
    }

    @Test
    fun 通用容器显示错误和恢复操作() {
        setState(PageUiState.Error(DsmFailure(null, "synthetic-error", "synthetic-retry")))
        val context = InstrumentationRegistry.getInstrumentation().targetContext

        rule.onNodeWithText(context.getString(R.string.operation_not_completed)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.try_again_later)).assertIsDisplayed()
    }

    @Test
    fun 通用容器显示正常内容() {
        setState(PageUiState.Content("synthetic-content"))

        rule.onNodeWithText("synthetic-content").assertIsDisplayed()
    }

    private fun setState(state: PageUiState<String>) {
        rule.setContent {
            LanStashTheme {
                PageStateContent(
                    state = state,
                    emptyTitle = "synthetic-empty-title",
                    emptyMessage = "synthetic-empty-message",
                    emptyIcon = Icons.Outlined.Info,
                    filteredEmptyTitle = "synthetic-filtered-title",
                    filteredEmptyMessage = "synthetic-filtered-message",
                    filteredEmptyIcon = Icons.Outlined.Info,
                    onRetry = {},
                    content = { androidx.compose.material3.Text(it) },
                )
            }
        }
    }
}
