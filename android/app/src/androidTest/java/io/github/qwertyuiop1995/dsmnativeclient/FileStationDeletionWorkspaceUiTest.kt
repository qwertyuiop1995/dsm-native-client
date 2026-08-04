package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileBrowserScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileStationMutationConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileStationMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileStationMutationFeedbackDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class FileStationDeletionWorkspaceUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 文件浏览器批量删除由Workspace显示数量和影响() {
        val target = fileDeleteTarget(file("one.txt"), file("two.txt"))
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        rule.setContent {
            LanStashTheme {
                FileBrowserScreen(
                    state = WorkspaceState(
                        profile = profile(),
                        selectedModule = Module.FILES,
                        fileStationMutationState = FileStationMutationWorkspaceState(
                            draftTarget = target,
                            confirmationRequested = true,
                        ),
                    ),
                    model = model,
                )
            }
        }

        rule.onNodeWithText(context().getString(R.string.delete_selected_items)).assertIsDisplayed()
        rule.onNodeWithText(
            context().getString(R.string.delete_selected_items_message, 2),
        ).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.delete))
            .assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun 回收站单项删除明确提示可能永久移除() {
        val item = file("old.txt", path = "/share/#recycle/old.txt")
        rule.setContent {
            LanStashTheme {
                FileStationMutationConfirmationDialog(
                    target = fileDeleteTarget(item),
                    onConfirm = { true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNodeWithText(
            context().getString(R.string.delete_named_item, item.name),
        ).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.delete_permanently_note)).assertIsDisplayed()
    }

    @Test
    fun 文件删除反馈使用文件文案并显示批量计数() {
        val target = fileDeleteTarget(file("one.txt"), file("two.txt"))
        rule.setContent {
            LanStashTheme {
                Column {
                    FileStationMutationFeedbackCard(
                        FileStationMutationWorkspaceState(
                            draftTarget = target,
                            target = target,
                            mutationResult = result(
                                MutationResultStatus.CONFIRMED_SUCCESS,
                                MutationResultCounts(2, 0, 0),
                            ),
                        ),
                    )
                    FileStationMutationFeedbackCard(
                        FileStationMutationWorkspaceState(
                            draftTarget = target,
                            target = target,
                            mutationResult = result(
                                MutationResultStatus.PARTIAL_SUCCESS,
                                MutationResultCounts(1, 1, 0),
                            ),
                        ),
                    )
                }
            }
        }

        rule.onNodeWithText(context().getString(R.string.file_delete_confirmed, 2)).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.file_delete_partial, 1, 1)).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.file_mutation_counts, 2, 0, 0))
            .assertIsDisplayed()
    }

    @Test
    fun 相册删除继续使用相册反馈文案() {
        val target = fileDeleteTarget(file("photo.jpg"), module = Module.PHOTOS)
        rule.setContent {
            LanStashTheme {
                FileStationMutationFeedbackCard(
                    FileStationMutationWorkspaceState(
                        draftTarget = target,
                        target = target,
                        mutationResult = result(
                            MutationResultStatus.CONFIRMED_SUCCESS,
                            MutationResultCounts(1, 0, 0),
                        ),
                    ),
                )
            }
        }

        rule.onNodeWithText(context().getString(R.string.photo_deleted)).assertIsDisplayed()
    }

    @Test
    fun 相册删除结果不会在文件页面串台() {
        val target = fileDeleteTarget(file("photo.jpg"), module = Module.PHOTOS)
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        rule.setContent {
            LanStashTheme {
                FileBrowserScreen(
                    state = WorkspaceState(
                        profile = profile(),
                        selectedModule = Module.FILES,
                        fileStationMutationState = FileStationMutationWorkspaceState(
                            draftTarget = target,
                            target = target,
                            mutationResult = result(
                                MutationResultStatus.CONFIRMED_SUCCESS,
                                MutationResultCounts(1, 0, 0),
                            ),
                        ),
                    ),
                    model = model,
                )
            }
        }

        rule.onAllNodesWithText(context().getString(R.string.photo_deleted)).assertCountEquals(0)
    }

    @Test
    fun 文件删除提交前失败不提供复用旧基线的继续编辑() {
        val target = fileDeleteTarget(file("one.txt"))
        rule.setContent {
            LanStashTheme {
                FileStationMutationFeedbackDialog(
                    state = FileStationMutationWorkspaceState(
                        draftTarget = target,
                        target = target,
                        mutationResult = result(
                            MutationResultStatus.CONFIRMED_FAILURE,
                            MutationResultCounts(0, 1, 0),
                        ),
                    ),
                    onRefresh = { true },
                    onContinueEditing = { true },
                    onDismiss = { true },
                )
            }
        }

        rule.onAllNodesWithText(context().getString(R.string.continue_editing_file_mutation))
            .assertCountEquals(0)
    }

    private fun result(
        status: MutationResultStatus,
        counts: MutationResultCounts,
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "fileDelete",
        submitted = true,
        requiresRefresh = status == MutationResultStatus.PARTIAL_SUCCESS,
        counts = counts,
    )

    private fun fileDeleteTarget(
        vararg files: FileItem,
        module: Module = Module.FILES,
    ) = FileStationMutationTarget(
        profileId = profile().id,
        module = module,
        operation = FileStationMutationOperation.DELETE,
        sourceBaselines = files.toList(),
    )

    private fun file(
        name: String,
        path: String = "/share/$name",
    ) = FileItem(
        path = path,
        name = name,
        isDirectory = false,
        canRead = true,
        canWrite = true,
        canDelete = true,
    )

    private fun profile() = NasProfile(
        id = "profile-synthetic",
        name = "Synthetic",
        address = "https://nas.example.invalid",
        username = "operator",
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
