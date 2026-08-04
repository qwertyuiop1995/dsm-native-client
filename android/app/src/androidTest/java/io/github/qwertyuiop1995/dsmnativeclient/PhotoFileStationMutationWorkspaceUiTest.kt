package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.ui.PhotosScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class PhotoFileStationMutationWorkspaceUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 相册共享确认由统一Workspace渲染() {
        val target = photoTarget(FileStationMutationOperation.SHARE_CREATE)
        setPhotos(
            FileStationMutationWorkspaceState(
                draftTarget = target,
                confirmationRequested = true,
            ),
        )

        rule.onAllNodesWithText(context().getString(R.string.create_share_link)).assertCountEquals(2)
        rule.onNodeWithText(
            context().getString(R.string.create_share_link_message, target.sourceBaselines.single().name),
        ).assertIsDisplayed()
    }

    @Test
    fun 相册未确认结果由统一Workspace持续显示() {
        val target = photoTarget(FileStationMutationOperation.RESTORE)
        setPhotos(
            FileStationMutationWorkspaceState(
                draftTarget = target,
                target = target,
                mutationResult = MutationResult(
                    schemaVersion = 1,
                    status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                    operation = "fileRestore",
                    submitted = true,
                    requiresRefresh = true,
                    counts = MutationResultCounts(0, 0, 1),
                ),
            ),
        )

        rule.onNodeWithText(
            context().getString(R.string.file_mutation_feedback_check_title),
        ).assertIsDisplayed()
        rule.onNodeWithText(context().getString(R.string.refresh_and_check_files)).assertIsDisplayed()
    }

    private fun setPhotos(mutation: FileStationMutationWorkspaceState) {
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        rule.setContent {
            LanStashTheme {
                PhotosScreen(
                    state = WorkspaceState(
                        profile = NasProfile(
                            id = "profile-synthetic",
                            name = "Synthetic",
                            address = "https://nas.example.invalid",
                            username = "operator",
                        ),
                        selectedModule = Module.PHOTOS,
                        fileStationMutationState = mutation,
                    ),
                    model = model,
                )
            }
        }
    }

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun photoTarget(operation: FileStationMutationOperation) = FileStationMutationTarget(
        profileId = "profile-synthetic",
        module = Module.PHOTOS,
        operation = operation,
        sourceBaselines = listOf(
            FileItem(
                path = "/synthetic/photo.jpg",
                name = "photo.jpg",
                isDirectory = false,
                canRead = true,
                canWrite = true,
            ),
        ),
    )
}
