package io.github.qwertyuiop1995.dsmnativeclient.ui

import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileTypeFilter
import org.junit.Assert.assertEquals
import org.junit.Test

class FilePageUiStateTest {
    private val folderOnlyPage = FilePage(
        items = listOf(FileItem("/folder", "folder", isDirectory = true)),
        offset = 0,
        total = 1,
    )

    @Test
    fun `目录无内容和筛选无结果使用不同状态`() {
        assertEquals(
            PageUiState.Empty,
            filePageUiState(
                Loadable.Ready(folderOnlyPage.copy(items = emptyList(), total = 0)),
                FileBrowserState(),
            ),
        )
        assertEquals(
            PageUiState.FilteredEmpty,
            filePageUiState(
                Loadable.Ready(folderOnlyPage),
                FileBrowserState(typeFilter = FileTypeFilter.FILES),
            ),
        )
    }

    @Test
    fun `有可见文件时保留分页内容`() {
        val state = filePageUiState(Loadable.Ready(folderOnlyPage), FileBrowserState())

        assertEquals(folderOnlyPage, (state as PageUiState.Content).value)
    }
}
