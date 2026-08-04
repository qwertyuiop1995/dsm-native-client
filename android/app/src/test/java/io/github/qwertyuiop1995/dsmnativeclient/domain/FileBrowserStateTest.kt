package io.github.qwertyuiop1995.dsmnativeclient.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FileBrowserStateTest {
    @Test
    fun `进入目录时保存历史并清除搜索`() {
        val initial = FileBrowserState(
            path = "/share",
            searchQuery = "report",
            activeSearchQuery = "report",
        )

        val next = initial.enterDirectory("/share/folder")

        assertEquals("/share/folder", next.path)
        assertEquals(listOf("/share"), next.pathHistory)
        assertEquals("", next.searchQuery)
        assertNull(next.activeSearchQuery)
    }

    @Test
    fun `返回上级目录时恢复路径并移除一层历史`() {
        val initial = FileBrowserState(
            path = "/share/folder/child",
            pathHistory = listOf("/share", "/share/folder"),
        )

        val previous = initial.navigateUp()

        assertEquals("/share/folder", previous?.path)
        assertEquals(listOf("/share"), previous?.pathHistory)
    }

    @Test
    fun `编辑搜索草稿不会提前改变当前结果`() {
        val initial = FileBrowserState(activeSearchQuery = "old")

        val edited = initial.editSearchQuery("new")

        assertEquals("new", edited.searchQuery)
        assertEquals("old", edited.activeSearchQuery)
    }

    @Test
    fun `提交搜索会规范化关键词且空关键词恢复目录`() {
        val searched = FileBrowserState(searchQuery = "  report  ").submitSearch()
        val cleared = searched.editSearchQuery("   ").submitSearch()

        assertEquals("report", searched.activeSearchQuery)
        assertNull(cleared.activeSearchQuery)
    }

    @Test
    fun `面包屑导航只允许回到已访问路径`() {
        val initial = FileBrowserState(
            path = "/share/folder/child",
            pathHistory = listOf("", "/share", "/share/folder"),
            activeSearchQuery = "photo",
            selectedPaths = setOf("/share/folder/child/item"),
        )

        val share = initial.navigateTo("/share")

        assertEquals("/share", share?.path)
        assertEquals(listOf(""), share?.pathHistory)
        assertNull(share?.activeSearchQuery)
        assertTrue(share?.selectedPaths.isNullOrEmpty())
        assertNull(initial.navigateTo("/other"))
        assertNull(initial.navigateTo(initial.path))
    }

    @Test
    fun `再次选择相同排序会切换方向`() {
        val initial = FileBrowserState()

        val descending = initial.changeSort(FileSortOption.NAME)
        val bySize = descending.changeSort(FileSortOption.SIZE)

        assertEquals(FileSortOption.NAME, descending.sortOption)
        assertEquals(false, descending.sortAscending)
        assertEquals(FileSortOption.SIZE, bySize.sortOption)
        assertTrue(bySize.sortAscending)
    }

    @Test
    fun `类型筛选不改变原始分页内容`() {
        val items = listOf(
            FileItem(path = "/share/folder", name = "folder", isDirectory = true),
            FileItem(path = "/share/file.txt", name = "file.txt", isDirectory = false),
        )

        val folders = FileBrowserState(typeFilter = FileTypeFilter.FOLDERS).visibleItems(items)
        val files = FileBrowserState(typeFilter = FileTypeFilter.FILES).visibleItems(items)

        assertEquals(listOf("folder"), folders.map(FileItem::name))
        assertEquals(listOf("file.txt"), files.map(FileItem::name))
        assertEquals(2, items.size)
    }

    @Test
    fun `视图模式和筛选可独立保留`() {
        val state = FileBrowserState()
            .changeFilter(FileTypeFilter.FILES)
            .changeViewMode(FileViewMode.GRID)

        assertEquals(FileTypeFilter.FILES, state.typeFilter)
        assertEquals(FileViewMode.GRID, state.viewMode)
    }

    @Test
    fun `可见内容遵循名称和大小排序方向`() {
        val items = listOf(
            FileItem(path = "/b", name = "beta", isDirectory = false, size = 2),
            FileItem(path = "/a", name = "Alpha", isDirectory = false, size = 9),
        )

        val byName = FileBrowserState().visibleItems(items)
        val bySizeDescending = FileBrowserState(
            sortOption = FileSortOption.SIZE,
            sortAscending = false,
        ).visibleItems(items)

        assertEquals(listOf("Alpha", "beta"), byName.map(FileItem::name))
        assertEquals(listOf(9L, 2L), bySizeDescending.map(FileItem::size))
    }

    @Test
    fun `多选可切换并在进入目录时自动清除`() {
        val selected = FileBrowserState()
            .toggleSelection("/share/a")
            .toggleSelection("/share/b")
            .toggleSelection("/share/a")

        assertEquals(setOf("/share/b"), selected.selectedPaths)
        assertTrue(selected.enterDirectory("/share/folder").selectedPaths.isEmpty())
        assertTrue(selected.clearSelection().selectedPaths.isEmpty())
    }

    @Test
    fun `快捷位置从共享根建立可返回路径`() {
        val shortcut = FileBrowserState(
            path = "/old",
            pathHistory = listOf(""),
            activeSearchQuery = "draft",
            selectedPaths = setOf("/old/a"),
        ).openShortcut("/share/favorite")

        assertEquals("/share/favorite", shortcut.path)
        assertEquals(listOf(""), shortcut.pathHistory)
        assertNull(shortcut.activeSearchQuery)
        assertTrue(shortcut.selectedPaths.isEmpty())
    }
}
