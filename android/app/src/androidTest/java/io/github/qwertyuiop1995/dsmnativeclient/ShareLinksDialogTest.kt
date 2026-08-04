package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileShareLink
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileBrowserScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class ShareLinksDialogTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 共享链接列表提供复制和受保护删除() {
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
                        files = Loadable.Ready(FilePage(emptyList(), total = 0, offset = 0)),
                        supportsSharing = true,
                        fileShareLinks = Loadable.Ready(
                            listOf(
                                FileShareLink(
                                    id = "link-1",
                                    name = "Synthetic report",
                                    path = "/share/synthetic-report.pdf",
                                    url = "https://share.example.invalid/synthetic",
                                    hasPassword = true,
                                    expiresAt = "2026-12-31",
                                ),
                            ),
                        ),
                    ),
                    model = model,
                )
            }
        }

        rule.onNodeWithContentDescription(context.getString(R.string.manage_share_links)).performClick()
        rule.onNodeWithText("Synthetic report").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.share_link_password_protected)).assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.copy_share_link)).assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.delete_share_link)).performClick()
        rule.onNodeWithText(
            context.getString(R.string.delete_share_link_confirmation, "Synthetic report"),
        ).assertIsDisplayed()
    }
}
