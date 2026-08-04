package io.github.qwertyuiop1995.dsmnativeclient.storage

import org.junit.Assert.assertEquals
import org.junit.Test

class RecentDirectoriesTest {
    @Test
    fun `最近目录去重置顶并排除回收站`() {
        val current = listOf("/home/a", "/home/b")

        assertEquals(
            listOf("/home/b", "/home/a"),
            updateRecentDirectories(current, "/home/b"),
        )
        assertEquals(current, updateRecentDirectories(current, "/home/#recycle/old"))
    }

    @Test
    fun `最近目录最多保留二十项`() {
        val current = (1..20).map { "/home/$it" }
        val updated = updateRecentDirectories(current, "/home/new")

        assertEquals(20, updated.size)
        assertEquals("/home/new", updated.first())
    }
}
