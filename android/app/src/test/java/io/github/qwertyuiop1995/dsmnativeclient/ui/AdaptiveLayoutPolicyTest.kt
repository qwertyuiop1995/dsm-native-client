package io.github.qwertyuiop1995.dsmnativeclient.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptiveLayoutPolicyTest {
    @Test
    fun `宽度断点统一映射为紧凑中等和展开`() {
        assertEquals(AdaptiveWindowWidth.COMPACT, adaptiveWindowWidth(599f))
        assertEquals(AdaptiveWindowWidth.MEDIUM, adaptiveWindowWidth(600f))
        assertEquals(AdaptiveWindowWidth.MEDIUM, adaptiveWindowWidth(839.9f))
        assertEquals(AdaptiveWindowWidth.EXPANDED, adaptiveWindowWidth(840f))
    }

    @Test
    fun `导航聊天和下载仅在展开宽度切换模式`() {
        assertFalse(AdaptiveLayoutPolicy.usesPermanentNavigation(839f))
        assertFalse(AdaptiveLayoutPolicy.usesChatListDetail(839f))
        assertFalse(AdaptiveLayoutPolicy.usesDownloadListDetail(839f))
        assertTrue(AdaptiveLayoutPolicy.usesPermanentNavigation(840f))
        assertTrue(AdaptiveLayoutPolicy.usesChatListDetail(840f))
        assertTrue(AdaptiveLayoutPolicy.usesDownloadListDetail(840f))
    }

    @Test
    fun `导航按紧凑中等和展开宽度分别使用底栏侧栏和常驻抽屉`() {
        assertEquals(
            AdaptiveNavigationType.BOTTOM_BAR,
            AdaptiveLayoutPolicy.navigationType(599f),
        )
        assertEquals(
            AdaptiveNavigationType.RAIL,
            AdaptiveLayoutPolicy.navigationType(600f),
        )
        assertEquals(
            AdaptiveNavigationType.RAIL,
            AdaptiveLayoutPolicy.navigationType(839.9f),
        )
        assertEquals(
            AdaptiveNavigationType.PERMANENT_DRAWER,
            AdaptiveLayoutPolicy.navigationType(840f),
        )
        assertTrue(AdaptiveLayoutPolicy.usesNavigationRail(600f))
        assertFalse(AdaptiveLayoutPolicy.usesNavigationRail(840f))
    }

    @Test
    fun `媒体预览保留满足内容宽度的保守双栏阈值`() {
        assertFalse(AdaptiveLayoutPolicy.usesFileListDetail(1_119, true))
        assertTrue(AdaptiveLayoutPolicy.usesFileListDetail(1_120, true))
        assertFalse(AdaptiveLayoutPolicy.usesPhotoListDetail(1_199, true))
        assertTrue(AdaptiveLayoutPolicy.usesPhotoListDetail(1_200, true))
    }
}
