package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePreviewContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.FilePreviewDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class FilePreviewAdaptiveTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 嵌入预览复用内容与关闭操作() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val item = FileItem(
            path = "/synthetic/readme.txt",
            name = "Synthetic readme.txt",
            isDirectory = false,
            size = 22,
            canRead = true,
        )
        var closed = false
        rule.setContent {
            LanStashTheme {
                FilePreviewDialog(
                    item = item,
                    preview = Loadable.Ready(
                        FilePreviewContent.Text(
                            item = item,
                            value = "Synthetic preview body",
                            truncated = false,
                        ),
                    ),
                    onRetry = {},
                    onClose = { closed = true },
                    embedded = true,
                )
            }
        }

        rule.onNodeWithText("Synthetic readme.txt").assertIsDisplayed()
        rule.onNodeWithText("Synthetic preview body").assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.close)).performClick()
        rule.runOnIdle { check(closed) }
    }
}
