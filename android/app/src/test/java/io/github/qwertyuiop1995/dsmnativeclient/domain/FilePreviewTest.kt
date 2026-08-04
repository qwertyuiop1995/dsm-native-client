package io.github.qwertyuiop1995.dsmnativeclient.domain

import io.github.qwertyuiop1995.dsmnativeclient.data.decodeTextPreview
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class FilePreviewTest {
    @Test
    fun `按MIME和扩展名识别可预览文件`() {
        assertEquals(FilePreviewKind.IMAGE, file("photo.JPG").previewKind())
        assertEquals(FilePreviewKind.IMAGE, file("asset", "image/webp").previewKind())
        assertEquals(FilePreviewKind.VIDEO, file("clip.MOV").previewKind())
        assertEquals(FilePreviewKind.VIDEO, file("asset", "video/mp4").previewKind())
        assertEquals(FilePreviewKind.AUDIO, file("song.FLAC").previewKind())
        assertEquals(FilePreviewKind.AUDIO, file("asset", "audio/mpeg").previewKind())
        assertEquals(FilePreviewKind.PDF, file("guide.pdf").previewKind())
        assertEquals(FilePreviewKind.TEXT, file("README.md").previewKind())
        assertEquals(FilePreviewKind.TEXT, file("data", "text/csv").previewKind())
        assertEquals(FilePreviewKind.UNSUPPORTED, file("archive.zip").previewKind())
        assertEquals(
            FilePreviewKind.UNSUPPORTED,
            FileItem("/share/folder", "folder", isDirectory = true).previewKind(),
        )
    }

    @Test
    fun `文本预览识别UTF8和UTF16字节序标记`() {
        val utf8 = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "你好".encodeToByteArray()
        val utf16 = byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + "你好".toByteArray(Charsets.UTF_16LE)

        assertEquals("你好", decodeTextPreview(utf8))
        assertEquals("你好", decodeTextPreview(utf16))
    }

    @Test
    fun `文件图片序列在首中末位置提供稳定边界`() {
        val first = file("a.jpg")
        val second = file("b.jpg")
        val third = file("c.jpg")
        val items = listOf(first, second, third)
        val start = FilePreviewSequence(items, index = 0)
        val middle = FilePreviewSequence(items, index = 1)
        val end = FilePreviewSequence(items, index = 2)

        assertEquals(first, start.current)
        assertFalse(start.hasPrevious)
        assertTrue(start.hasNext)
        assertEquals(second, middle.current)
        assertTrue(middle.hasPrevious)
        assertTrue(middle.hasNext)
        assertEquals(third, end.current)
        assertTrue(end.hasPrevious)
        assertFalse(end.hasNext)
    }

    @Test
    fun `文件图片序列拒绝空列表和越界索引`() {
        val items = listOf(file("a.jpg"))

        assertThrows(IllegalArgumentException::class.java) {
            FilePreviewSequence(emptyList(), index = 0)
        }
        assertThrows(IllegalArgumentException::class.java) {
            FilePreviewSequence(items, index = -1)
        }
        assertThrows(IllegalArgumentException::class.java) {
            FilePreviewSequence(items, index = items.size)
        }
    }

    private fun file(name: String, mimeType: String? = null) = FileItem(
        path = "/share/$name",
        name = name,
        isDirectory = false,
        mimeType = mimeType,
    )
}
