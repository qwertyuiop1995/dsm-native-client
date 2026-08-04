package io.github.qwertyuiop1995.dsmnativeclient.domain

import java.io.File
import java.io.Closeable

enum class FilePreviewKind {
    IMAGE,
    VIDEO,
    AUDIO,
    PDF,
    TEXT,
    UNSUPPORTED,
}

sealed interface FilePreviewContent {
    val item: FileItem

    data class Image(
        override val item: FileItem,
        val localFile: File,
        val mediaDetails: MediaDetails? = null,
    ) : FilePreviewContent

    data class Pdf(
        override val item: FileItem,
        val localFile: File,
    ) : FilePreviewContent

    data class Video(
        override val item: FileItem,
        val localFile: File? = null,
        val mediaSource: RandomAccessMediaSource? = null,
        val mediaDetails: MediaDetails? = null,
    ) : FilePreviewContent

    data class Audio(
        override val item: FileItem,
        val localFile: File? = null,
        val mediaSource: RandomAccessMediaSource? = null,
        val mediaDetails: MediaDetails? = null,
    ) : FilePreviewContent

    data class Text(
        override val item: FileItem,
        val value: String,
        val truncated: Boolean,
    ) : FilePreviewContent
}

interface RandomAccessMediaSource : Closeable {
    val size: Long
    fun readAt(position: Long, buffer: ByteArray, offset: Int, length: Int): Int
}

data class MediaDetails(
    val width: Int? = null,
    val height: Int? = null,
    val durationMillis: Long? = null,
    val capturedAtEpochMillis: Long? = null,
    val camera: String? = null,
)

data class FilePreviewSequence(
    val items: List<FileItem>,
    val index: Int,
) {
    init {
        require(items.isNotEmpty()) { "File preview sequence cannot be empty" }
        require(index in items.indices) { "File preview sequence index is out of bounds" }
    }

    val current: FileItem get() = items[index]
    val hasPrevious: Boolean get() = index > 0
    val hasNext: Boolean get() = index + 1 < items.size
}

fun FileItem.previewKind(): FilePreviewKind {
    if (isDirectory) return FilePreviewKind.UNSUPPORTED
    val normalizedMime = mimeType?.lowercase().orEmpty()
    return when {
        normalizedMime.startsWith("image/") || extension in IMAGE_EXTENSIONS -> FilePreviewKind.IMAGE
        normalizedMime.startsWith("video/") || extension in VIDEO_EXTENSIONS -> FilePreviewKind.VIDEO
        normalizedMime.startsWith("audio/") || extension in AUDIO_EXTENSIONS -> FilePreviewKind.AUDIO
        normalizedMime == "application/pdf" || extension == "pdf" -> FilePreviewKind.PDF
        normalizedMime.startsWith("text/") || extension in TEXT_EXTENSIONS -> FilePreviewKind.TEXT
        else -> FilePreviewKind.UNSUPPORTED
    }
}

private val IMAGE_EXTENSIONS = setOf(
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif",
)

private val VIDEO_EXTENSIONS = setOf(
    "mp4", "mov", "m4v", "3gp", "webm", "mkv",
)

private val AUDIO_EXTENSIONS = setOf(
    "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "wma",
)

private val TEXT_EXTENSIONS = setOf(
    "txt", "md", "markdown", "log", "csv", "json", "xml", "yaml", "yml", "ini", "conf",
    "properties", "kt", "kts", "java", "swift", "cs", "js", "ts", "tsx", "jsx", "html",
    "css", "scss", "sh", "py", "rb", "go", "rs", "c", "h", "cpp", "hpp", "sql",
)
