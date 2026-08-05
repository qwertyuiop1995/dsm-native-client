package io.github.qwertyuiop1995.dsmnativeclient

import android.graphics.Bitmap
import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePreviewContent
import io.github.qwertyuiop1995.dsmnativeclient.ui.FilePreviewDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import java.io.File
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class FilePreviewAdaptiveTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private var temporaryImage: File? = null

    @After
    fun 清理临时图片() {
        temporaryImage?.delete()
        temporaryImage = null
    }

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

    @Test
    fun 非嵌入预览的顶部和底部操作避开系统安全区() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val imageFile = createTemporaryPng()
        val item = FileItem(
            path = "/synthetic/safe-area.png",
            name = "Synthetic safe area.png",
            isDirectory = false,
            size = imageFile.length(),
            mimeType = "image/png",
        )
        rule.activity.runOnUiThread { rule.activity.enableEdgeToEdge() }
        rule.setContent {
            LanStashTheme {
                FilePreviewDialog(
                    item = item,
                    preview = Loadable.Ready(FilePreviewContent.Image(item, imageFile)),
                    onRetry = {},
                    onClose = {},
                )
            }
        }

        val zoomIn = context.getString(R.string.zoom_in)
        rule.waitUntil(timeoutMillis = 5_000) {
            rule.onAllNodesWithContentDescription(zoomIn).fetchSemanticsNodes().isNotEmpty()
        }

        val closeBounds = rule.onNodeWithContentDescription(context.getString(R.string.close))
            .fetchSemanticsNode()
            .boundsInRoot
        val zoomInBounds = rule.onNodeWithContentDescription(zoomIn).fetchSemanticsNode().boundsInRoot
        var safeTop = 0
        var safeBottom = 0
        var rootHeight = 0
        rule.runOnIdle {
            val insets = ViewCompat.getRootWindowInsets(rule.activity.window.decorView)
                ?: error("测试窗口未提供系统 Insets")
            val safeInsets = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            safeTop = safeInsets.top
            safeBottom = safeInsets.bottom
            rootHeight = rule.activity.window.decorView.height
        }

        assertTrue("测试设备未提供顶部系统安全区", safeTop > 0)
        assertTrue("测试设备未提供底部系统安全区", safeBottom > 0)
        assertTrue(closeBounds.top >= safeTop)
        assertTrue(zoomInBounds.bottom <= rootHeight - safeBottom)
    }

    private fun createTemporaryPng(): File {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File.createTempFile("file-preview-safe-area-", ".png", context.cacheDir)
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
