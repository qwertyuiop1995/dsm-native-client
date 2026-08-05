package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchCatalog
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchModule
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchModuleScope
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadBtSearchOptions
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadDiscoveryTab
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
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
        var visibleState by mutableStateOf(populatedState())
        var selectedTitle: String? = null
        var selectedSource: DownloadCreationSourceKind? = null
        rule.setContent {
            LanStashTheme {
                DownloadDiscoveryDialog(
                    state = visibleState,
                    model = model,
                    canCreateTask = true,
                    onCreateTask = { title, _, source ->
                        selectedTitle = title
                        selectedSource = source
                    },
                    onDismiss = {},
                    onSelectTab = { tab ->
                        visibleState = visibleState.copy(
                            downloadAdvancedRead = visibleState.downloadAdvancedRead.copy(
                                discoveryTab = tab,
                            ),
                        )
                    },
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

    @Test
    fun BT搜索选项覆盖加载失败空内容和正常状态() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        val states: List<Pair<Loadable<DownloadBtSearchCatalog>, String>> = listOf(
            Loadable.Loading to context.getString(R.string.download_bt_options_loading),
            Loadable.Failed(DsmFailure(null, "synthetic", "retry")) to
                context.getString(R.string.download_bt_options_failed),
            Loadable.Ready(DownloadBtSearchCatalog(emptyList(), emptyList())) to
                context.getString(R.string.download_bt_options_empty),
        )
        var catalogState by mutableStateOf(states.first().first)
        rule.setContent {
                LanStashTheme {
                    DownloadDiscoveryDialog(
                        state = baseState().copy(
                            supportsDownloadBtSearch = true,
                            downloadAdvancedRead = DownloadAdvancedReadWorkspaceState(
                                discoveryTab = DownloadDiscoveryTab.BT_SEARCH,
                                btSearchCatalog = catalogState,
                                btSearchOptions = DownloadBtSearchOptions(keyword = "linux"),
                            ),
                        ),
                        model = model,
                        canCreateTask = true,
                        onCreateTask = { _, _, _ -> },
                        onDismiss = {},
                    )
                }
        }
        states.forEach { (catalog, expected) ->
            rule.runOnIdle { catalogState = catalog }
            rule.onNodeWithText(expected).assertIsDisplayed()
            rule.onNodeWithText(context.getString(R.string.download_bt_search_action))
                .assertIsNotEnabled()
        }
    }

    @Test
    fun BT高级选项在二倍字体下保持可操作() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 2f)) {
                LanStashTheme {
                    DownloadDiscoveryDialog(
                        state = baseState().copy(
                            supportsDownloadBtSearch = true,
                            downloadAdvancedRead = DownloadAdvancedReadWorkspaceState(
                                discoveryTab = DownloadDiscoveryTab.BT_SEARCH,
                                btSearchCatalog = Loadable.Ready(catalog()),
                                btAdvancedOptionsVisible = true,
                                btSearchOptions = DownloadBtSearchOptions(
                                    keyword = "linux",
                                    moduleScope = DownloadBtSearchModuleScope.SELECTED,
                                    selectedModuleIds = setOf("provider-a"),
                                ),
                            ),
                        ),
                        model = model,
                        canCreateTask = true,
                        onCreateTask = { _, _, _ -> },
                        onDismiss = {},
                    )
                }
            }
        }

        rule.onNodeWithText(context.getString(R.string.download_bt_search_action))
            .assertIsDisplayed().assertIsEnabled().assertHeightIsAtLeast(48.dp)
        rule.onNodeWithText(context.getString(R.string.download_bt_hide_options))
            .assertIsDisplayed().assertIsEnabled().assertHeightIsAtLeast(48.dp)
        rule.onNodeWithText("Provider A").assertExists()
        rule.onNodeWithText(context.getString(R.string.download_bt_sort_descending))
            .performScrollTo()
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
            .performClick()
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
        downloadAdvancedRead = DownloadAdvancedReadWorkspaceState(
            btSearchCatalog = Loadable.Ready(catalog()),
            btSearchResults = Loadable.Ready(
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
        ),
    )

    private fun catalog() = DownloadBtSearchCatalog(
        modules = listOf(DownloadBtSearchModule("provider-a", "Provider A", true)),
        categories = listOf(DownloadBtSearchCategory("Books", "Books")),
    )

    private fun baseState() = WorkspaceState(
        profile = NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
        supportsDownloadRss = true,
    )
}
