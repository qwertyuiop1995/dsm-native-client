package io.github.qwertyuiop1995.dsmnativeclient

import android.graphics.Bitmap
import android.graphics.Color
import android.media.ExifInterface
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.ui.PreviewExifOrientationTransform
import io.github.qwertyuiop1995.dsmnativeclient.ui.applyPreviewExifOrientation
import io.github.qwertyuiop1995.dsmnativeclient.ui.decodePreviewBitmap
import io.github.qwertyuiop1995.dsmnativeclient.ui.previewExifOrientationTransform
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test

class FilePreviewExifOrientationTest {
    private val temporaryFiles = mutableListOf<File>()

    @After
    fun 清理临时文件() {
        temporaryFiles.forEach(File::delete)
        temporaryFiles.clear()
    }

    @Test
    fun EXIF方向一至八映射为正确的旋转和镜像() {
        val expected = mapOf(
            ExifInterface.ORIENTATION_NORMAL to PreviewExifOrientationTransform.Identity,
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL to PreviewExifOrientationTransform(0, true),
            ExifInterface.ORIENTATION_ROTATE_180 to PreviewExifOrientationTransform(180, false),
            ExifInterface.ORIENTATION_FLIP_VERTICAL to PreviewExifOrientationTransform(180, true),
            ExifInterface.ORIENTATION_TRANSPOSE to PreviewExifOrientationTransform(90, true),
            ExifInterface.ORIENTATION_ROTATE_90 to PreviewExifOrientationTransform(90, false),
            ExifInterface.ORIENTATION_TRANSVERSE to PreviewExifOrientationTransform(270, true),
            ExifInterface.ORIENTATION_ROTATE_270 to PreviewExifOrientationTransform(270, false),
        )

        expected.forEach { (orientation, transform) ->
            assertEquals(transform, previewExifOrientationTransform(orientation))
        }
    }

    @Test
    fun 旋转九十度交换尺寸并保持像素方向() {
        val source = Bitmap.createBitmap(2, 3, Bitmap.Config.ARGB_8888)
        source.setPixel(0, 0, Color.RED)
        source.setPixel(1, 0, Color.GREEN)
        source.setPixel(0, 1, Color.BLUE)
        source.setPixel(1, 1, Color.YELLOW)
        source.setPixel(0, 2, Color.CYAN)
        source.setPixel(1, 2, Color.MAGENTA)

        val transformed = applyPreviewExifOrientation(source, ExifInterface.ORIENTATION_ROTATE_90)
        try {
            assertEquals(3, transformed.width)
            assertEquals(2, transformed.height)
            assertEquals(Color.CYAN, transformed.getPixel(0, 0))
            assertEquals(Color.RED, transformed.getPixel(2, 0))
            assertEquals(Color.MAGENTA, transformed.getPixel(0, 1))
            assertEquals(Color.GREEN, transformed.getPixel(2, 1))
        } finally {
            transformed.recycle()
            source.recycle()
        }
    }

    @Test
    fun 解码预览读取系统Exif方向() {
        val file = File.createTempFile(
            "file-preview-orientation-",
            ".jpg",
            InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
        )
        temporaryFiles += file
        val source = Bitmap.createBitmap(2, 3, Bitmap.Config.ARGB_8888)
        try {
            source.eraseColor(Color.rgb(32, 96, 160))
            file.outputStream().use { output ->
                check(source.compress(Bitmap.CompressFormat.JPEG, 100, output))
            }
        } finally {
            source.recycle()
        }
        ExifInterface(file.path).apply {
            setAttribute(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_ROTATE_90.toString(),
            )
            saveAttributes()
        }

        val decoded = decodePreviewBitmap(file, maximumDimension = 2_048)
        try {
            assertEquals(3, decoded.width)
            assertEquals(2, decoded.height)
        } finally {
            decoded.recycle()
        }
    }
}
