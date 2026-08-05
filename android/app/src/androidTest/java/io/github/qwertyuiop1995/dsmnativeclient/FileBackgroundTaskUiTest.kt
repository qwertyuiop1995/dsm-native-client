package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskPage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskSummary
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import io.github.qwertyuiop1995.dsmnativeclient.ui.transfers.FileBackgroundTasksContent
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class FileBackgroundTaskUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 加载空错误均有反馈且错误可以重试() {
        val context = context()
        var tasks by mutableStateOf<Loadable<FileBackgroundTaskPage>>(Loadable.Loading)
        var retries = 0
        rule.setContent {
            LanStashTheme {
                FileBackgroundTasksContent(
                    tasks = tasks,
                    isLoadingMore = false,
                    loadMoreFailure = null,
                    onRefresh = {},
                    onRetry = { retries += 1 },
                    onLoadMore = {},
                )
            }
        }
        rule.onNodeWithText(context.getString(R.string.file_background_tasks_loading))
            .assertIsDisplayed()
        rule.onAllNodes(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite),
            useUnmergedTree = true,
        ).assertCountEquals(1)

        rule.runOnIdle { tasks = Loadable.Ready(page(emptyList())) }
        rule.onNodeWithText(context.getString(R.string.no_file_background_tasks)).assertIsDisplayed()

        rule.runOnIdle {
            tasks = Loadable.Failed(DsmFailure(null, "Synthetic failure", "Synthetic recovery"))
        }
        rule.onNodeWithText(context.getString(R.string.retry))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { assertEquals(1, retries) }
        rule.onAllNodes(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Assertive,
            ),
            useUnmergedTree = true,
        ).assertCountEquals(1)
    }

    @Test
    fun 状态筛选与有限分页不把已结束说成成功() {
        val context = context()
        var loads = 0
        setContent(
            tasks = Loadable.Ready(
                page(
                    listOf(
                        task("private-active-id", FileBackgroundTaskKind.COMPRESS, FileBackgroundTaskState.ACTIVE),
                        task("private-finished-id", FileBackgroundTaskKind.EXTRACT, FileBackgroundTaskState.FINISHED),
                    ),
                    hasMore = true,
                ),
            ),
            onLoadMore = { loads += 1 },
        )

        rule.onNode(
            hasText(context.getString(R.string.file_background_task_filter_finished)) and
                hasClickAction(),
        )
            .performClick()
        rule.onNodeWithText(context.getString(R.string.file_background_task_kind_extract))
            .assertIsDisplayed()
        rule.onAllNodesWithText(context.getString(R.string.file_background_task_kind_compress))
            .assertCountEquals(0)
        rule.onAllNodesWithText(context.getString(R.string.file_background_task_state_finished))
            .assertCountEquals(2)
        rule.onAllNodesWithText(context.getString(R.string.transfer_completed)).assertCountEquals(0)
        rule.onAllNodesWithText("private-active-id").assertCountEquals(0)
        rule.onAllNodesWithText("private-finished-id").assertCountEquals(0)
        rule.onNodeWithText(context.getString(R.string.file_background_tasks_load_more))
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { assertEquals(1, loads) }
    }

    @Test
    fun 筛选后为空说明恢复方式并仍可有限分页() {
        val context = context()
        setContent(
            tasks = Loadable.Ready(
                page(
                    listOf(
                        task("private-finished-id", FileBackgroundTaskKind.DELETE, FileBackgroundTaskState.FINISHED),
                    ),
                    hasMore = true,
                ),
            ),
        )

        rule.onNodeWithText(context.getString(R.string.file_background_task_filter_active))
            .performClick()
        rule.onNodeWithText(context.getString(R.string.no_filtered_file_background_tasks))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.no_filtered_file_background_tasks_description))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_background_tasks_load_more))
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun 分页失败保留现有任务并可以重试() {
        val context = context()
        var loads = 0
        setContent(
            tasks = Loadable.Ready(
                page(
                    listOf(
                        task("private-active-id", FileBackgroundTaskKind.COMPRESS, FileBackgroundTaskState.ACTIVE),
                    ),
                    hasMore = true,
                ),
            ),
            loadMoreFailure = DsmFailure(null, "Synthetic failure", "Synthetic recovery"),
            onLoadMore = { loads += 1 },
        )

        rule.onNodeWithText(context.getString(R.string.file_background_task_kind_compress))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_background_tasks_load_more_failed))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_background_tasks_load_more))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { assertEquals(1, loads) }
    }

    @Test
    fun 保存的快照明确标注且刷新期间禁用重复刷新() {
        val context = context()
        var refreshes = 0
        var isRefreshing by mutableStateOf(true)
        rule.setContent {
            LanStashTheme {
                FileBackgroundTasksContent(
                    tasks = Loadable.Ready(
                        page(
                            listOf(
                                task(
                                    "private-active-id",
                                    FileBackgroundTaskKind.COMPRESS,
                                    FileBackgroundTaskState.ACTIVE,
                                ),
                            ),
                        ),
                    ),
                    isLoadingMore = false,
                    loadMoreFailure = null,
                    snapshotObservedAtEpochSeconds = 1_700_000_000,
                    isRefreshing = isRefreshing,
                    refreshFailure = null,
                    onRefresh = { refreshes += 1 },
                    onRetry = {},
                    onLoadMore = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.file_background_tasks_snapshot_refreshing))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_background_task_kind_compress))
            .assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.refresh))
            .assertIsNotEnabled()
        rule.runOnIdle { assertEquals(0, refreshes) }

        rule.runOnIdle { isRefreshing = false }
        rule.onNodeWithText(context.getString(R.string.file_background_tasks_snapshot_saved))
            .assertIsDisplayed()
        rule.onNodeWithContentDescription(context.getString(R.string.refresh))
            .assertHasClickAction()
            .performClick()
        rule.runOnIdle { assertEquals(1, refreshes) }
    }

    @Test
    fun 保存的快照刷新失败时保留任务并说明恢复方式() {
        val context = context()
        val recovery = context.getString(R.string.try_again_later)
        rule.setContent {
            LanStashTheme {
                FileBackgroundTasksContent(
                    tasks = Loadable.Ready(
                        page(
                            listOf(
                                task(
                                    "private-finished-id",
                                    FileBackgroundTaskKind.EXTRACT,
                                    FileBackgroundTaskState.FINISHED,
                                ),
                            ),
                        ),
                    ),
                    isLoadingMore = false,
                    loadMoreFailure = null,
                    snapshotObservedAtEpochSeconds = 1_700_000_000,
                    refreshFailure = DsmFailure(null, "Synthetic failure", "Synthetic recovery"),
                    onRefresh = {},
                    onRetry = {},
                    onLoadMore = {},
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.file_background_tasks_snapshot_refresh_failed))
            .assertIsDisplayed()
        rule.onNodeWithText(recovery).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_background_task_kind_extract))
            .assertIsDisplayed()
        rule.onAllNodes(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Assertive,
            ),
            useUnmergedTree = true,
        ).assertCountEquals(1)
    }

    @Test
    fun 深色两倍字体与320dp宽度下筛选刷新和任务内容仍可操作() {
        val context = context()
        var refreshes = 0
        rule.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, fontScale = 2f)) {
                LanStashTheme(darkTheme = true) {
                    Box(Modifier.width(320.dp).height(640.dp)) {
                        FileBackgroundTasksContent(
                            tasks = Loadable.Ready(
                                page(
                                    listOf(
                                        task(
                                            "private-task-id",
                                            FileBackgroundTaskKind.COPY_OR_MOVE,
                                            FileBackgroundTaskState.ACTIVE,
                                        ),
                                    ),
                                ),
                            ),
                            isLoadingMore = false,
                            loadMoreFailure = null,
                            onRefresh = { refreshes += 1 },
                            onRetry = {},
                            onLoadMore = {},
                        )
                    }
                }
            }
        }

        rule.onNodeWithContentDescription(context.getString(R.string.refresh))
            .assertIsDisplayed()
            .assertHasClickAction()
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { assertEquals(1, refreshes) }
        rule.onNodeWithText(context.getString(R.string.file_background_task_filter_all))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_background_task_kind_copy_move))
            .assertIsDisplayed()
        rule.onAllNodes(
            hasText(context.getString(R.string.file_background_task_state_active)) and
                SemanticsMatcher.expectValue(
                    SemanticsProperties.LiveRegion,
                    LiveRegionMode.Polite,
                ),
        ).assertCountEquals(1)
    }

    private fun setContent(
        tasks: Loadable<FileBackgroundTaskPage>,
        loadMoreFailure: DsmFailure? = null,
        onRetry: () -> Unit = {},
        onLoadMore: () -> Unit = {},
    ) {
        rule.setContent {
            LanStashTheme {
                FileBackgroundTasksContent(
                    tasks = tasks,
                    isLoadingMore = false,
                    loadMoreFailure = loadMoreFailure,
                    onRefresh = {},
                    onRetry = onRetry,
                    onLoadMore = onLoadMore,
                )
            }
        }
    }

    private fun page(
        tasks: List<FileBackgroundTaskSummary>,
        hasMore: Boolean = false,
    ) = FileBackgroundTaskPage(
        tasks = tasks,
        offset = 0,
        nextOffset = tasks.size,
        total = tasks.size + if (hasMore) 1 else 0,
        hasMore = hasMore,
    )

    private fun task(
        id: String,
        kind: FileBackgroundTaskKind,
        state: FileBackgroundTaskState,
    ) = FileBackgroundTaskSummary(
        id = id,
        kind = kind,
        state = state,
        progress = if (state == FileBackgroundTaskState.ACTIVE) 0.5 else null,
        createdAtEpochSeconds = null,
        processedItemCount = 1,
        totalItemCount = 2,
        processedBytes = 512,
        totalBytes = 1_024,
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
