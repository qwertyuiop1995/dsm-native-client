package io.github.qwertyuiop1995.dsmnativeclient

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePreviewContent
import io.github.qwertyuiop1995.dsmnativeclient.domain.MediaDetails
import io.github.qwertyuiop1995.dsmnativeclient.ui.FilePreviewDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import java.io.File
import java.text.DateFormat
import java.util.Date
import org.junit.After
import org.junit.Rule
import org.junit.Test

class PhotoMediaViewerTest {
    @get:Rule
    val rule = createComposeRule()

    private var temporaryImage: File? = null

    @After
    fun 清理临时图片() {
        temporaryImage?.delete()
        temporaryImage = null
    }

    @Test
    fun 图片详情和缩放控制可用() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val capturedAt = 1_704_164_645_000L
        val imageFile = createTemporaryPng()
        val item = FileItem(
            path = "/synthetic/viewer-photo.png",
            name = "Synthetic viewer photo.png",
            isDirectory = false,
            size = imageFile.length(),
            mimeType = "image/png",
        )
        rule.setContent {
            LanStashTheme {
                FilePreviewDialog(
                    item = item,
                    preview = Loadable.Ready(
                        FilePreviewContent.Image(
                            item = item,
                            localFile = imageFile,
                            mediaDetails = MediaDetails(
                                width = 48,
                                height = 32,
                                capturedAtEpochMillis = capturedAt,
                                camera = "Synthetic Camera",
                            ),
                        ),
                    ),
                    onRetry = {},
                    onClose = {},
                    embedded = true,
                )
            }
        }

        val zoomIn = context.getString(R.string.zoom_in)
        rule.waitUntil(timeoutMillis = 5_000) {
            rule.onAllNodesWithContentDescription(zoomIn).fetchSemanticsNodes().isNotEmpty()
        }

        rule.onNodeWithContentDescription(context.getString(R.string.file_details)).performClick()
        rule.onNodeWithText(context.getString(R.string.file_detail_dimensions)).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_detail_dimensions_value, 48, 32))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_detail_taken)).assertIsDisplayed()
        rule.onNodeWithText(
            DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
                .format(Date(capturedAt)),
        ).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_detail_camera)).assertIsDisplayed()
        rule.onNodeWithText("Synthetic Camera").assertIsDisplayed()

        val zoomOut = rule.onNodeWithContentDescription(context.getString(R.string.zoom_out))
        val resetZoom = rule.onNodeWithContentDescription(context.getString(R.string.reset_zoom))
        zoomOut.assertIsNotEnabled()
        resetZoom.assertIsNotEnabled()
        rule.onNodeWithContentDescription(zoomIn).assertIsEnabled().performClick()
        rule.onNodeWithText(context.getString(R.string.zoom_percent, 150)).assertIsDisplayed()
        zoomOut.assertIsEnabled()
        resetZoom.assertIsEnabled().performClick()
        rule.onNodeWithText(context.getString(R.string.zoom_percent, 100)).assertIsDisplayed()
        zoomOut.assertIsNotEnabled()
        resetZoom.assertIsNotEnabled()
    }

    @Test
    fun 前后导航遵守启用状态并触发回调() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val item = FileItem(
            path = "/synthetic/navigation.txt",
            name = "Synthetic navigation.txt",
            isDirectory = false,
        )
        val previousEnabled = mutableStateOf(false)
        val nextEnabled = mutableStateOf(true)
        var previousCalls = 0
        var nextCalls = 0
        rule.setContent {
            LanStashTheme {
                FilePreviewDialog(
                    item = item,
                    preview = Loadable.Ready(
                        FilePreviewContent.Text(item, "Navigation preview", truncated = false),
                    ),
                    onRetry = {},
                    onClose = {},
                    onPrevious = { previousCalls += 1 },
                    onNext = { nextCalls += 1 },
                    previousEnabled = previousEnabled.value,
                    nextEnabled = nextEnabled.value,
                    embedded = true,
                )
            }
        }

        val previous = rule.onNodeWithContentDescription(context.getString(R.string.previous_photo))
        val next = rule.onNodeWithContentDescription(context.getString(R.string.next_photo))
        previous.assertIsNotEnabled()
        next.assertIsEnabled().performClick()
        rule.runOnIdle {
            check(previousCalls == 0)
            check(nextCalls == 1)
            previousEnabled.value = true
            nextEnabled.value = false
        }
        previous.assertIsEnabled().performClick()
        next.assertIsNotEnabled()
        rule.runOnIdle {
            check(previousCalls == 1)
            check(nextCalls == 1)
        }
    }

    @Test
    fun 视频没有可播放来源时显示确定性降级() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val item = FileItem(
            path = "/synthetic/no-source.mp4",
            name = "Synthetic no-source.mp4",
            isDirectory = false,
            mimeType = "video/mp4",
        )
        rule.setContent {
            LanStashTheme {
                FilePreviewDialog(
                    item = item,
                    preview = Loadable.Ready(FilePreviewContent.Video(item = item)),
                    onRetry = {},
                    onClose = {},
                    embedded = true,
                )
            }
        }

        val failure = context.getString(R.string.video_playback_failed)
        rule.waitUntil(timeoutMillis = 5_000) {
            rule.onAllNodesWithText(failure).fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNodeWithText(failure).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.video_playback_failed_recovery))
            .assertIsDisplayed()
        rule.onNodeWithContentDescription(
            context.getString(R.string.preview_video_description, item.name),
        ).assertIsDisplayed()
    }

    private fun createTemporaryPng(): File {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("photo-media-viewer-", ".png", context.cacheDir)
        temporaryImage = file
        val bitmap = Bitmap.createBitmap(48, 32, Bitmap.Config.ARGB_8888)
        try {
            bitmap.eraseColor(Color.rgb(32, 96, 160))
            file.outputStream().use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, output))
            }
        } finally {
            bitmap.recycle()
        }
        return file
    }
}
