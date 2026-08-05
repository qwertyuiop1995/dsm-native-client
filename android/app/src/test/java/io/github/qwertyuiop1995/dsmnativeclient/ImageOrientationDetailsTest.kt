package io.github.qwertyuiop1995.dsmnativeclient

import org.junit.Assert.assertEquals
import org.junit.Test

class ImageOrientationDetailsTest {
    @Test
    fun `EXIF 方向一到八仅在换轴方向交换媒体详情尺寸`() {
        val original = 400 to 300

        listOf(1, 2, 3, 4).forEach { orientation ->
            assertEquals(
                "orientation=$orientation",
                original,
                imageDimensionsAfterExifOrientation(
                    width = original.first,
                    height = original.second,
                    orientation = orientation,
                ),
            )
        }
        listOf(5, 6, 7, 8).forEach { orientation ->
            assertEquals(
                "orientation=$orientation",
                original.second to original.first,
                imageDimensionsAfterExifOrientation(
                    width = original.first,
                    height = original.second,
                    orientation = orientation,
                ),
            )
        }
    }
}
