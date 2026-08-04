package io.github.qwertyuiop1995.dsmnativeclient.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhotoAdaptiveLayoutTest {
    @Test
    fun `照片详情仅在足够宽且已有预览时嵌入`() {
        assertFalse(useInlinePhotoPreview(screenWidthDp = 1_199, hasPreview = true))
        assertFalse(useInlinePhotoPreview(screenWidthDp = 1_200, hasPreview = false))
        assertTrue(useInlinePhotoPreview(screenWidthDp = 1_200, hasPreview = true))
    }
}
