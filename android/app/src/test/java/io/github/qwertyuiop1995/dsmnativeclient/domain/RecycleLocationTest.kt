package io.github.qwertyuiop1995.dsmnativeclient.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RecycleLocationTest {
    @Test
    fun `共享回收站路径计算原位置`() {
        val location = RecycleLocation.from("/photos/#recycle/旅行/海边.jpg")!!

        assertEquals("/photos/#recycle", location.recycleRoot)
        assertEquals("/旅行/海边.jpg", location.relativePath)
        assertEquals("/photos/旅行/海边.jpg", location.originalPath)
        assertEquals("/photos/旅行", location.originalParentPath)
    }

    @Test
    fun `拒绝嵌套和根级回收站路径`() {
        assertNull(RecycleLocation.from("/photos/archive/#recycle/a.jpg"))
        assertNull(RecycleLocation.from("/#recycle/a.jpg"))
        assertNull(RecycleLocation.from("/photos/#recycle"))
    }
}
