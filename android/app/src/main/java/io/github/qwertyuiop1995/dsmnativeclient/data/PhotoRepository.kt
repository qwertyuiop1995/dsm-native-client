package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.PHOTO_IMAGE_EXTENSIONS
import io.github.qwertyuiop1995.dsmnativeclient.domain.PHOTO_VIDEO_EXTENSIONS
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoItemKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoPage
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoSpace
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoTimelineProgress

/** 仅使用公开 File Station API 的基础照片库适配器。 */
class PhotoRepository(private val files: DsmRepository) {
    suspend fun page(
        space: PhotoSpace,
        folderPath: String,
        offset: Int = 0,
        limit: Int = DEFAULT_PAGE_SIZE,
    ): PhotoPage {
        require(folderPath.isWithin(space.rootPath)) { "Photo folder is outside the selected space" }
        require(offset >= 0)
        require(limit in 1..MAX_PAGE_SIZE)
        var sourceOffset = offset
        var sourceTotal = offset
        var hasMore: Boolean
        var scannedPages = 0
        val visible = mutableListOf<PhotoItem>()
        do {
            val source = files.listDirectory(folderPath, sourceOffset, limit)
            sourceTotal = source.total
            visible += source.items.mapNotNull(::photoItem)
            val consumed = source.items.size
            sourceOffset += consumed
            hasMore = consumed > 0 && sourceOffset < source.total
            scannedPages++
        } while (visible.isEmpty() && hasMore && scannedPages < MAX_EMPTY_SOURCE_PAGES)
        return PhotoPage(
            folderPath = folderPath,
            items = visible,
            offset = offset,
            nextOffset = sourceOffset,
            sourceTotal = sourceTotal,
            hasMore = hasMore,
        )
    }

    suspend fun thumbnail(item: PhotoItem): ByteArray {
        if (item.kind !in setOf(PhotoItemKind.IMAGE, PhotoItemKind.VIDEO)) {
            throw DsmFailure(
                null,
                "A thumbnail is not available for this item",
                "Open the item to view it.",
                kind = DsmErrorKind.FEATURE_UNSUPPORTED,
            )
        }
        return files.thumbnail(item.file.path)
    }

    /**
     * 使用公开 File Station 列表逐层建立时间轴。单个子文件夹失败不会遮蔽已经读取的内容，
     * 但照片空间根目录失败会交给调用方显示完整错误状态。
     */
    suspend fun scanTimeline(
        space: PhotoSpace,
        maxMediaItems: Int = MAX_TIMELINE_ITEMS,
        onProgress: suspend (PhotoTimelineProgress) -> Unit = {},
    ): PhotoTimelineProgress {
        require(maxMediaItems in 1..MAX_TIMELINE_ITEMS)
        val pending = ArrayDeque<String>().apply { add(space.rootPath) }
        val visited = mutableSetOf<String>()
        val media = mutableListOf<PhotoItem>()
        var scannedFolders = 0
        var failedFolders = 0
        var truncated = false
        while (pending.isNotEmpty() && !truncated) {
            val folder = pending.removeFirst()
            if (!visited.add(folder)) continue
            var offset = 0
            var folderFailed = false
            do {
                val source = runCatching {
                    files.listDirectory(folder, offset, TIMELINE_SOURCE_PAGE_SIZE)
                }.getOrElse { error ->
                    if (folder == space.rootPath) throw error
                    failedFolders++
                    folderFailed = true
                    null
                } ?: break
                source.items.forEach { file ->
                    val item = photoItem(file) ?: return@forEach
                    if (item.kind == PhotoItemKind.FOLDER) {
                        if (file.path.isWithin(space.rootPath) && file.path !in visited) {
                            pending.add(file.path)
                        }
                    } else if (media.size < maxMediaItems) {
                        media += item
                    } else {
                        truncated = true
                    }
                }
                offset += source.items.size
                onProgress(
                    timelineProgress(media, scannedFolders, pending.size, failedFolders, false, truncated),
                )
            } while (!truncated && source.items.isNotEmpty() && offset < source.total)
            if (!folderFailed) scannedFolders++
        }
        return timelineProgress(
            media,
            scannedFolders,
            pending.size,
            failedFolders,
            isComplete = !truncated,
            isTruncated = truncated,
        ).also { onProgress(it) }
    }

    private fun timelineProgress(
        media: List<PhotoItem>,
        scannedFolders: Int,
        pendingFolders: Int,
        failedFolders: Int,
        isComplete: Boolean,
        isTruncated: Boolean,
    ) = PhotoTimelineProgress(
        items = media.sortedByDescending { it.takenAtEpochSeconds ?: Long.MIN_VALUE },
        scannedFolderCount = scannedFolders,
        pendingFolderCount = pendingFolders,
        failedFolderCount = failedFolders,
        isComplete = isComplete,
        isTruncated = isTruncated,
    )

    private fun photoItem(file: io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem): PhotoItem? {
        val kind = when {
            file.isDirectory -> PhotoItemKind.FOLDER
            file.extension in PHOTO_IMAGE_EXTENSIONS -> PhotoItemKind.IMAGE
            file.extension in PHOTO_VIDEO_EXTENSIONS -> PhotoItemKind.VIDEO
            else -> return null
        }
        return PhotoItem(
            id = file.path,
            file = file,
            kind = kind,
            takenAtEpochSeconds = file.modifiedAtEpochSeconds,
        )
    }

    private fun String.isWithin(root: String): Boolean = this == root || startsWith("$root/")

    private companion object {
        const val DEFAULT_PAGE_SIZE = 120
        const val MAX_PAGE_SIZE = 500
        const val MAX_EMPTY_SOURCE_PAGES = 5
        const val TIMELINE_SOURCE_PAGE_SIZE = 200
        const val MAX_TIMELINE_ITEMS = 10_000
    }
}
