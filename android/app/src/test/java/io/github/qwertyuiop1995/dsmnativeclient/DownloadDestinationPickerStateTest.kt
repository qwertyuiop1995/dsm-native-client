package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadDestinationPickerStateTest {
    @Test
    fun `进入目录并返回时保留准确的写入能力`() {
        val root = DownloadDestinationPickerState()
        val share = FileItem(
            path = "/downloads",
            name = "downloads",
            isDirectory = true,
            canWrite = true,
        )
        val readOnlyChild = FileItem(
            path = "/downloads/archive",
            name = "archive",
            isDirectory = true,
            canWrite = false,
        )

        val inShare = root.enter(share)
        val inChild = inShare.enter(readOnlyChild)

        assertTrue(inShare.canSelectCurrent)
        assertFalse(inChild.canSelectCurrent)
        assertEquals(inShare, inChild.goBack())
        assertEquals(root, inShare.goBack())
        assertNull(root.goBack())
    }
}
