package io.github.qwertyuiop1995.dsmnativeclient.domain

import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PhotoBrowserStateTest {
    @Test
    fun `切换照片空间会重置目录和搜索但保留媒体筛选`() {
        val state = PhotoBrowserState(
            folderPath = "/home/Photos/Trips",
            pathHistory = listOf("/home/Photos"),
            searchQuery = "sea",
            activeSearchQuery = "sea",
            filter = PhotoMediaFilter.PHOTOS,
        )

        val switched = state.selectSpace(SHARED_PHOTO_SPACE.id)

        assertEquals(SHARED_PHOTO_SPACE.id, switched.selectedSpaceId)
        assertEquals(SHARED_PHOTO_SPACE.rootPath, switched.folderPath)
        assertTrue(switched.pathHistory.isEmpty())
        assertEquals("", switched.searchQuery)
        assertNull(switched.activeSearchQuery)
        assertEquals(PhotoMediaFilter.PHOTOS, switched.filter)
    }

    @Test
    fun `进入目录后可以按历史返回且根目录不再消费返回`() {
        val root = PhotoBrowserState()
        val child = root.enterFolder("/home/Photos/Trips")

        assertEquals("/home/Photos/Trips", child.folderPath)
        assertEquals(root.folderPath, child.navigateUp()?.folderPath)
        assertNull(root.navigateUp())
    }

    @Test
    fun `搜索草稿提交前不改变可见内容且筛选仍保留文件夹`() {
        val page = PhotoPage(
            folderPath = "/home/Photos",
            items = listOf(
                photo("/home/Photos/Trips", true),
                photo("/home/Photos/sea.jpg", false),
                photo("/home/Photos/clip.mp4", false),
            ),
            offset = 0,
            nextOffset = 3,
            sourceTotal = 3,
            hasMore = false,
        )
        val draft = PhotoBrowserState(searchQuery = "sea", filter = PhotoMediaFilter.VIDEOS)

        assertEquals(2, draft.visibleItems(page).size)
        val submitted = draft.submitSearch()
        assertTrue(submitted.visibleItems(page).isEmpty())
    }

    @Test
    fun `图片查看器在首中末位置提供稳定边界`() {
        val items = listOf(
            FileItem("/home/Photos/a.jpg", "a.jpg", false),
            FileItem("/home/Photos/b.jpg", "b.jpg", false),
            FileItem("/home/Photos/c.jpg", "c.jpg", false),
        )

        val first = PhotoViewerState(items, 0)
        val middle = PhotoViewerState(items, 1)
        val last = PhotoViewerState(items, 2)

        assertEquals(items[0], first.current)
        assertFalse(first.hasPrevious)
        assertTrue(first.hasNext)
        assertEquals(items[1], middle.current)
        assertTrue(middle.hasPrevious)
        assertTrue(middle.hasNext)
        assertEquals(items[2], last.current)
        assertTrue(last.hasPrevious)
        assertFalse(last.hasNext)
    }

    @Test
    fun `图片查看器拒绝空列表和越界索引`() {
        val items = listOf(FileItem("/home/Photos/a.jpg", "a.jpg", false))

        assertThrows(IllegalArgumentException::class.java) {
            PhotoViewerState(emptyList(), index = 0)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PhotoViewerState(items, index = -1)
        }
        assertThrows(IllegalArgumentException::class.java) {
            PhotoViewerState(items, index = items.size)
        }
    }

    @Test
    fun `时间轴可按年份月份和媒体类型定位`() {
        val timeline = PhotoTimelineProgress(
            items = listOf(
                datedPhoto("/home/Photos/a.jpg", PhotoItemKind.IMAGE, 1_704_067_200), // 2024-01-01 UTC
                datedPhoto("/home/Photos/b.mp4", PhotoItemKind.VIDEO, 1_717_200_000), // 2024-06-01 UTC
                datedPhoto("/home/Photos/c.jpg", PhotoItemKind.IMAGE, 1_735_689_600), // 2025-01-01 UTC
            ),
            isComplete = true,
        )
        val browser = PhotoBrowserState(
            mode = PhotoBrowseMode.TIMELINE,
            filter = PhotoMediaFilter.PHOTOS,
            selectedYear = 2024,
            selectedMonth = 1,
        )

        val visible = browser.visibleTimelineItems(timeline, ZoneOffset.UTC)

        assertEquals(listOf("a.jpg"), visible.map { it.file.name })
        assertNull(browser.selectYear(2025).selectedMonth)
    }

    private fun photo(path: String, directory: Boolean): PhotoItem {
        val file = FileItem(path, path.substringAfterLast('/'), directory)
        val kind = when {
            directory -> PhotoItemKind.FOLDER
            path.endsWith(".mp4") -> PhotoItemKind.VIDEO
            else -> PhotoItemKind.IMAGE
        }
        return PhotoItem(path, file, kind, null)
    }

    private fun datedPhoto(path: String, kind: PhotoItemKind, epochSeconds: Long): PhotoItem =
        PhotoItem(
            id = path,
            file = FileItem(path, path.substringAfterLast('/'), isDirectory = false),
            kind = kind,
            takenAtEpochSeconds = epochSeconds,
        )
}
