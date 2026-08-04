package io.github.qwertyuiop1995.dsmnativeclient.ui

import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class PageUiStateTest {
    @Test
    fun `空闲和加载数据映射为加载状态`() {
        assertEquals(PageUiState.Loading, Loadable.Idle.toPageUiState<String>())
        assertEquals(PageUiState.Loading, Loadable.Loading.toPageUiState<String>())
    }

    @Test
    fun `错误和内容保留原始值`() {
        val failure = DsmFailure(null, "synthetic", "retry")
        val error = Loadable.Failed(failure).toPageUiState<String>()
        val content = Loadable.Ready("content").toPageUiState()

        assertSame(failure, (error as PageUiState.Error).failure)
        assertEquals("content", (content as PageUiState.Content).value)
    }

    @Test
    fun `筛选后为空优先于普通空状态`() {
        val value = Loadable.Ready(emptyList<String>())

        assertEquals(
            PageUiState.FilteredEmpty,
            value.toPageUiState(isEmpty = List<String>::isEmpty, isFilteredEmpty = { true }),
        )
        assertEquals(
            PageUiState.Empty,
            value.toPageUiState(isEmpty = List<String>::isEmpty),
        )
    }
}
