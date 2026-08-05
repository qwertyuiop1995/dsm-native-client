package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadRssFeed
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadRssSite
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.DownloadDiscoveryDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class DownloadDiscoveryDialogTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun RSS条目和BT搜索结果可在标签间切换() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        var selectedTitle: String? = null
        var selectedSource: DownloadCreationSourceKind? = null
        rule.setContent {
            LanStashTheme {
                DownloadDiscoveryDialog(
                    state = populatedState(),
                    model = model,
                    canCreateTask = true,
                    onCreateTask = { title, _, source ->
                        selectedTitle = title
                        selectedSource = source
                    },
                    onDismiss = {},
                )
            }
        }

        rule.onNodeWithText("Synthetic RSS item").assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.download_rss_refresh))
            .assertIsDisplayed().assertIsEnabled()
        rule.onAllNodesWithContentDescription(
            context.getString(R.string.download_discovery_create_task),
        )[0].performClick()
        rule.runOnIdle {
            check(selectedTitle == "Synthetic RSS item")
            check(selectedSource == DownloadCreationSourceKind.RSS)
        }
        rule.onNodeWithText(context.getString(R.string.download_discovery_bt_search)).performClick()
        rule.onNodeWithText("Synthetic search result").assertIsDisplayed()
        rule.onNodeWithText("Synthetic provider", substring = true).assertIsDisplayed()
    }

    @Test
    fun RSS站点为空时显示原因和下一步() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        rule.setContent {
            LanStashTheme {
                DownloadDiscoveryDialog(
                    state = baseState().copy(downloadRssSites = Loadable.Ready(emptyList())),
                    model = model,
                    canCreateTask = true,
                    onCreateTask = { _, _, _ -> },
                    onDismiss = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.download_rss_sites_empty)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.download_rss_sites_empty_description))
            .assertIsDisplayed()
    }

    @Test
    fun RSS刷新中禁用重复操作并显示即时反馈() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        rule.setContent {
            LanStashTheme {
                DownloadDiscoveryDialog(
                    state = populatedState().copy(
                        downloadRssRefreshState = DownloadRssRefreshWorkspaceState(
                            target = DownloadRssRefreshTarget("test", "site-1"),
                            mutationInProgress = true,
                        ),
                    ),
                    model = model,
                    canCreateTask = true,
                    onCreateTask = { _, _, _ -> },
                    onDismiss = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.download_rss_updating))
            .assertIsDisplayed().assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.download_rss_refresh_in_progress_message))
            .assertIsDisplayed()
    }

    private fun populatedState() = baseState().copy(
        supportsDownloadBtSearch = true,
        selectedDownloadRssSite = DownloadRssSite("site-1", "Synthetic RSS", false, 1),
        downloadRssFeeds = Loadable.Ready(
            listOf(
                DownloadRssFeed(
                    title = "Synthetic RSS item",
                    size = 1024,
                    publishedAtEpochSeconds = 1,
                    downloadUri = "https://download.invalid/rss.torrent",
                    externalLink = null,
                ),
            ),
        ),
        downloadBtSearchResults = Loadable.Ready(
            listOf(
                DownloadBtSearchResult(
                    title = "Synthetic search result",
                    size = 2048,
                    listedAt = "2026-01-01 00:00:00",
                    downloadUri = "https://download.invalid/search.torrent",
                    externalLink = null,
                    peers = 4,
                    seeds = 3,
                    leeches = 1,
                    provider = "Synthetic provider",
                ),
            ),
        ),
    )

    private fun baseState() = WorkspaceState(
        profile = NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        supportsDownloadRss = true,
    )
}
