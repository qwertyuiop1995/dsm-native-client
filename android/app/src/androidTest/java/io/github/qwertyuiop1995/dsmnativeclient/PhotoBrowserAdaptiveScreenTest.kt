package io.github.qwertyuiop1995.dsmnativeclient

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.isDialog
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePreviewContent
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoItemKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoPage
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoViewerState
import io.github.qwertyuiop1995.dsmnativeclient.ui.PhotosScreen
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

class PhotoBrowserAdaptiveScreenTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 宽屏照片网格和预览同时可见() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assumeTrue(context.resources.configuration.screenWidthDp >= 1_200)
        val previewFile = FileItem(
            path = "/synthetic/photo.jpg",
            name = "Synthetic preview photo.jpg",
            isDirectory = false,
            size = 22,
            canRead = true,
        )
        val folderFile = FileItem(
            path = "/synthetic/album",
            name = "Synthetic photo album",
            isDirectory = true,
            canRead = true,
        )
        val folder = PhotoItem(
            id = folderFile.path,
            file = folderFile,
            kind = PhotoItemKind.FOLDER,
            takenAtEpochSeconds = null,
        )
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        rule.setContent {
            LanStashTheme {
                PhotosScreen(
                    state = WorkspaceState(
                        profile = NasProfile(
                            "synthetic",
                            "Synthetic",
                            "https://nas.example.invalid",
                            "operator",
                        ),
                        photos = Loadable.Ready(
                            PhotoPage(
                                folderPath = "/synthetic",
                                items = listOf(folder),
                                offset = 0,
                                nextOffset = 1,
                                sourceTotal = 1,
                                hasMore = false,
                            ),
                        ),
                        previewItem = previewFile,
                        previewOwner = PreviewOwner.PHOTOS,
                        photoViewer = PhotoViewerState(listOf(previewFile), 0),
                        preview = Loadable.Ready(
                            FilePreviewContent.Text(
                                item = previewFile,
                                value = "Synthetic photo detail",
                                truncated = false,
                            ),
                        ),
                    ),
                    model = model,
                )
            }
        }

        rule.onNodeWithText("Synthetic photo album").assertIsDisplayed()
        rule.onNodeWithText("Synthetic photo detail").assertIsDisplayed()
    }

    @Test
    fun 页面实际宽度收窄后改用全屏预览() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assumeTrue(context.resources.configuration.screenWidthDp >= 1_200)
        val previewFile = FileItem(
            path = "/synthetic/photo.jpg",
            name = "Synthetic constrained photo.jpg",
            isDirectory = false,
            canRead = true,
        )
        val folderFile = FileItem(
            path = "/synthetic/album",
            name = "Synthetic constrained album",
            isDirectory = true,
            canRead = true,
        )
        val folder = PhotoItem(
            id = folderFile.path,
            file = folderFile,
            kind = PhotoItemKind.FOLDER,
            takenAtEpochSeconds = null,
        )
        val model = AppViewModel(ApplicationProvider.getApplicationContext<Application>())
        var availableWidth by mutableStateOf(1_200.dp)
        rule.setContent {
            LanStashTheme {
                Box(Modifier.width(availableWidth).fillMaxHeight()) {
                    PhotosScreen(
                        state = WorkspaceState(
                            profile = NasProfile(
                                "synthetic",
                                "Synthetic",
                                "https://nas.example.invalid",
                                "operator",
                            ),
                            photos = Loadable.Ready(
                                PhotoPage(
                                    folderPath = "/synthetic",
                                    items = listOf(folder),
                                    offset = 0,
                                    nextOffset = 1,
                                    sourceTotal = 1,
                                    hasMore = false,
                                ),
                            ),
                            previewItem = previewFile,
                            previewOwner = PreviewOwner.PHOTOS,
                            photoViewer = PhotoViewerState(listOf(previewFile), 0),
                            preview = Loadable.Ready(
                                FilePreviewContent.Text(
                                    item = previewFile,
                                    value = "Synthetic constrained photo detail",
                                    truncated = false,
                                ),
                            ),
                        ),
                        model = model,
                    )
                }
            }
        }

        rule.onNode(isDialog()).assertDoesNotExist()
        rule.onNodeWithText("Synthetic constrained album").assertIsDisplayed()
        rule.onNodeWithText("Synthetic constrained photo detail").assertIsDisplayed()

        rule.runOnIdle { availableWidth = 700.dp }

        rule.onNode(isDialog()).assertExists()
        rule.onNodeWithText("Synthetic constrained photo detail").assertIsDisplayed()
    }
}
