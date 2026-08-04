package io.github.qwertyuiop1995.dsmnativeclient.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FileAdaptiveLayoutTest {
    @Test
    fun `仅在宽屏且已有预览时使用列表详情双栏`() {
        assertFalse(useInlineFilePreview(screenWidthDp = 1_119, hasPreview = true))
        assertFalse(useInlineFilePreview(screenWidthDp = 1_120, hasPreview = false))
        assertTrue(useInlineFilePreview(screenWidthDp = 1_120, hasPreview = true))
        assertTrue(useInlineFilePreview(screenWidthDp = 1_600, hasPreview = true))
    }
}
