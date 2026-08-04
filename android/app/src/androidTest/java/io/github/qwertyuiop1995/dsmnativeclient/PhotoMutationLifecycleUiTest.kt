package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import android.app.Application
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.PERSONAL_PHOTO_SPACE
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoItemKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoPage
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileStationMutationConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.PhotosScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class PhotoMutationLifecycleUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 相册删除使用危险操作Workspace确认() {
        var confirmed = 0
        val target = photoTarget(FileStationMutationOperation.DELETE)
        rule.setContent {
            LanStashTheme {
                FileStationMutationConfirmationDialog(
                    target = target,
                    onConfirm = { confirmed += 1; true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNodeWithText(
            context().getString(R.string.delete_named_item, "photo.jpg"),
        ).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.delete_recycle_note)).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.delete)).performClick()

        assertEquals(1, confirmed)
    }

    @Test
    fun 相册移动确认显示单个文件和目的地() {
        var dismissed = 0
        val target = photoTarget(FileStationMutationOperation.MOVE)
        rule.setContent {
            LanStashTheme {
                FileStationMutationConfirmationDialog(
                    target = target,
                    onConfirm = { true },
                    onDismiss = { dismissed += 1; true },
                )
            }
        }

        rule.onNodeWithText(context().getString(R.string.confirm_move_photo)).assertIsDisplayed()
        rule.onNodeWithText(
            context().getString(
                R.string.confirm_move_photo_message,
                "photo.jpg",
                "Album",
            ),
        ).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.cancel)).performClick()

        assertEquals(1, dismissed)
    }

    @Test
    fun 相册移动草稿显示空间根且允许选择根目录() {
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        val root = FileItem(
            path = PERSONAL_PHOTO_SPACE.rootPath,
            name = "Photos",
            isDirectory = true,
            canRead = true,
            canWrite = true,
        )
        val move = PhotoMoveState(
            item = photoItem(),
            space = PERSONAL_PHOTO_SPACE,
            location = PhotoMoveLocation(root.path, canWrite = true, baseline = root),
        )
        val target = photoTarget(FileStationMutationOperation.MOVE).copy(
            destinationPath = null,
            destinationBaseline = null,
        )
        val state = WorkspaceState(
            profile = profile(),
            selectedModule = Module.PHOTOS,
            photoMove = move,
            photoMoveFolders = Loadable.Ready(
                PhotoPage(root.path, emptyList(), 0, 0, 0, hasMore = false),
            ),
            fileStationMutationState = FileStationMutationWorkspaceState(
                draftTarget = target,
                editorVisible = true,
            ),
        )

        rule.setContent {
            LanStashTheme { PhotosScreen(state = state, model = model) }
        }

        rule.onNodeWithText(context().getString(R.string.move_photo)).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.move_here))
            .assertIsDisplayed()
            .assertIsEnabled()
    }

    @Test
    fun 取消相册移动确认会返回目的地选择器并保留草稿() {
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        val destination = FileItem(
            path = "/home/Photos/Album",
            name = "Album",
            isDirectory = true,
            canRead = true,
            canWrite = true,
        )
        val move = PhotoMoveState(
            item = photoItem(),
            space = PERSONAL_PHOTO_SPACE,
            location = PhotoMoveLocation(
                destination.path,
                canWrite = true,
                baseline = destination,
            ),
        )
        val target = photoTarget(FileStationMutationOperation.MOVE).copy(
            destinationPath = destination.path,
            destinationBaseline = destination,
        )
        workspace(model).value = WorkspaceState(
            profile = profile(),
            selectedModule = Module.PHOTOS,
            photoMove = move,
            fileStationMutationState = FileStationMutationWorkspaceState(
                draftTarget = target,
                confirmationRequested = true,
            ),
        )

        assertTrue(model.cancelPendingFileStationMutation())
        val state = checkNotNull(workspace(model).value)
        assertNotNull(state.photoMove)
        assertEquals(destination.path, state.photoMove?.location?.path)
        assertTrue(state.fileStationMutationState.editorVisible)
        assertFalse(state.fileStationMutationState.confirmationRequested)
        assertEquals(target, state.fileStationMutationState.draftTarget)
    }

    @Test
    fun 丢弃相册移动提交前失败会同时清理目的地草稿() {
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        val move = PhotoMoveState(
            item = photoItem(),
            space = PERSONAL_PHOTO_SPACE,
            location = PhotoMoveLocation("/home/Photos/Album", canWrite = true),
        )
        val target = photoTarget(FileStationMutationOperation.MOVE)
        workspace(model).value = WorkspaceState(
            profile = profile(),
            selectedModule = Module.PHOTOS,
            photoMove = move,
            photoMoveFolders = Loadable.Ready(
                PhotoPage(move.location.path, emptyList(), 0, 0, 0, hasMore = false),
            ),
            fileStationMutationState = FileStationMutationWorkspaceState(
                draftTarget = target,
                target = target,
                mutationResult = MutationResult(
                    schemaVersion = 1,
                    status = MutationResultStatus.CONFIRMED_FAILURE,
                    operation = "fileMove",
                    submitted = false,
                    requiresRefresh = false,
                    counts = MutationResultCounts(0, 1, 0),
                ),
            ),
        )

        assertTrue(model.dismissFileStationMutationResult(discardDraft = true))
        val state = checkNotNull(workspace(model).value)
        assertEquals(null, state.photoMove)
        assertEquals(Loadable.Idle, state.photoMoveFolders)
        assertEquals(FileStationMutationWorkspaceState(), state.fileStationMutationState)
    }

    private fun photoTarget(operation: FileStationMutationOperation): FileStationMutationTarget {
        val destination = FileItem(
            path = "/photos/Album",
            name = "Album",
            isDirectory = true,
            canRead = true,
            canWrite = true,
        )
        return FileStationMutationTarget(
            profileId = "profile-synthetic",
            module = Module.PHOTOS,
            operation = operation,
            sourceBaselines = listOf(
                FileItem(
                    path = "/photos/photo.jpg",
                    name = "photo.jpg",
                    isDirectory = false,
                    canRead = true,
                    canWrite = true,
                    canDelete = true,
                ),
            ),
            destinationPath = destination.path.takeIf { operation == FileStationMutationOperation.MOVE },
            destinationBaseline = destination.takeIf { operation == FileStationMutationOperation.MOVE },
        )
    }

    private fun photoItem() = PhotoItem(
        id = "photo-synthetic",
        file = FileItem(
            path = "/home/Photos/Source/photo.jpg",
            name = "photo.jpg",
            isDirectory = false,
            canRead = true,
            canWrite = true,
            canDelete = true,
        ),
        kind = PhotoItemKind.IMAGE,
        takenAtEpochSeconds = null,
    )

    private fun profile() = NasProfile(
        id = "profile-synthetic",
        name = "Synthetic",
        address = "https://nas.example.invalid",
        username = "operator",
    )

    @Suppress("UNCHECKED_CAST")
    private fun workspace(model: AppViewModel): MutableStateFlow<WorkspaceState?> {
        val field = AppViewModel::class.java.getDeclaredField("_workspace").apply {
            isAccessible = true
        }
        return field.get(model) as MutableStateFlow<WorkspaceState?>
    }

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
