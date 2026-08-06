package io.github.qwertyuiop1995.dsmnativeclient.domain

import java.time.Instant
import java.time.ZoneId

enum class PhotoSpaceKind { PERSONAL, SHARED }

enum class PhotoSpaceAccess { UNKNOWN, AVAILABLE, UNAVAILABLE }

data class PhotoSpace(
    val id: String,
    val title: String,
    val rootPath: String,
    val kind: PhotoSpaceKind,
)

enum class PhotoItemKind { FOLDER, IMAGE, VIDEO }

data class PhotoItem(
    val id: String,
    val file: FileItem,
    val kind: PhotoItemKind,
    val takenAtEpochSeconds: Long?,
    val width: Int? = null,
    val height: Int? = null,
    val isLivePhoto: Boolean = false,
)

data class PhotoPage(
    val folderPath: String,
    val items: List<PhotoItem>,
    val offset: Int,
    val nextOffset: Int,
    val sourceTotal: Int,
    val hasMore: Boolean,
)

enum class PhotoMediaFilter { ALL, PHOTOS, VIDEOS }

enum class PhotoBrowseMode { FOLDERS, TIMELINE }

data class PhotoTimelineProgress(
    val items: List<PhotoItem> = emptyList(),
    val scannedFolderCount: Int = 0,
    val pendingFolderCount: Int = 0,
    val failedFolderCount: Int = 0,
    val isComplete: Boolean = false,
    val isTruncated: Boolean = false,
)

data class PhotoBrowserState(
    val spaces: List<PhotoSpace> = DEFAULT_PHOTO_SPACES,
    val selectedSpaceId: String = PERSONAL_PHOTO_SPACE.id,
    val spaceAccess: Map<String, PhotoSpaceAccess> = emptyMap(),
    val folderPath: String = PERSONAL_PHOTO_SPACE.rootPath,
    val pathHistory: List<String> = emptyList(),
    val searchQuery: String = "",
    val activeSearchQuery: String? = null,
    val filter: PhotoMediaFilter = PhotoMediaFilter.ALL,
    val mode: PhotoBrowseMode = PhotoBrowseMode.FOLDERS,
    val selectedYear: Int? = null,
    val selectedMonth: Int? = null,
    val isLoadingMore: Boolean = false,
) {
    val selectedSpace: PhotoSpace
        get() = spaces.firstOrNull { it.id == selectedSpaceId } ?: PERSONAL_PHOTO_SPACE

    fun selectSpace(spaceId: String): PhotoBrowserState {
        val space = spaces.firstOrNull { it.id == spaceId } ?: return this
        return copy(
            selectedSpaceId = space.id,
            folderPath = space.rootPath,
            pathHistory = emptyList(),
            searchQuery = "",
            activeSearchQuery = null,
            selectedYear = null,
            selectedMonth = null,
            isLoadingMore = false,
        )
    }

    fun enterFolder(path: String): PhotoBrowserState = copy(
        folderPath = path,
        pathHistory = pathHistory + folderPath,
        searchQuery = "",
        activeSearchQuery = null,
        isLoadingMore = false,
    )

    fun navigateUp(): PhotoBrowserState? {
        val previous = pathHistory.lastOrNull() ?: return null
        return copy(
            folderPath = previous,
            pathHistory = pathHistory.dropLast(1),
            searchQuery = "",
            activeSearchQuery = null,
            isLoadingMore = false,
        )
    }

    fun submitSearch(): PhotoBrowserState = copy(
        activeSearchQuery = searchQuery.trim().takeIf(String::isNotEmpty),
    )

    fun visibleItems(page: PhotoPage): List<PhotoItem> {
        val query = activeSearchQuery?.lowercase()
        return page.items.filter { item ->
            val matchesType = when (filter) {
                PhotoMediaFilter.ALL -> true
                PhotoMediaFilter.PHOTOS -> item.kind in setOf(PhotoItemKind.FOLDER, PhotoItemKind.IMAGE)
                PhotoMediaFilter.VIDEOS -> item.kind in setOf(PhotoItemKind.FOLDER, PhotoItemKind.VIDEO)
            }
            val matchesQuery = query == null || item.file.name.lowercase().contains(query)
            matchesType && matchesQuery
        }
    }

    fun visibleTimelineItems(
        timeline: PhotoTimelineProgress,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): List<PhotoItem> {
        val query = activeSearchQuery?.lowercase()
        return timeline.items.filter { item ->
            val matchesType = when (filter) {
                PhotoMediaFilter.ALL -> true
                PhotoMediaFilter.PHOTOS -> item.kind == PhotoItemKind.IMAGE
                PhotoMediaFilter.VIDEOS -> item.kind == PhotoItemKind.VIDEO
            }
            val date = item.takenAtEpochSeconds
                ?.let { Instant.ofEpochSecond(it).atZone(zoneId) }
            val matchesDate = (selectedYear == null || date?.year == selectedYear) &&
                (selectedMonth == null || date?.monthValue == selectedMonth)
            val matchesQuery = query == null || item.file.name.lowercase().contains(query)
            matchesType && matchesDate && matchesQuery
        }
    }

    fun selectYear(year: Int?): PhotoBrowserState = copy(
        selectedYear = year,
        selectedMonth = null,
    )

    fun selectMonth(month: Int?): PhotoBrowserState = copy(selectedMonth = month)

    /**
     * 从已签发的规范文件夹路径恢复照片空间与逐级父目录。
     *
     * 仅恢复用户要查看的文件夹；搜索、筛选、时间线位置和分页状态不会通过外链带回。
     */
    fun restoreCanonicalFolder(spaceId: String, canonicalPath: String): PhotoBrowserState? {
        val space = spaces.firstOrNull { it.id == spaceId } ?: return null
        val lineage = canonicalPhotoFolderLineage(space.rootPath, canonicalPath) ?: return null
        return copy(
            selectedSpaceId = space.id,
            folderPath = lineage.last(),
            pathHistory = lineage.dropLast(1),
            searchQuery = "",
            activeSearchQuery = null,
            filter = PhotoMediaFilter.ALL,
            mode = PhotoBrowseMode.FOLDERS,
            selectedYear = null,
            selectedMonth = null,
            isLoadingMore = false,
        )
    }

    /**
     * 从已签发的规范媒体路径恢复其所属文件夹，供单项查看器的返回栈使用。
     */
    fun restoreCanonicalMediaParent(spaceId: String, canonicalPath: String): PhotoBrowserState? {
        val space = spaces.firstOrNull { it.id == spaceId } ?: return null
        val rootSegments = canonicalPhotoPathSegments(space.rootPath) ?: return null
        val pathSegments = canonicalPhotoPathSegments(canonicalPath) ?: return null
        if (pathSegments.size <= rootSegments.size || pathSegments.take(rootSegments.size) != rootSegments) {
            return null
        }
        val parentPath = "/${pathSegments.dropLast(1).joinToString("/")}"
        return restoreCanonicalFolder(spaceId, parentPath)
    }
}

private fun canonicalPhotoFolderLineage(rootPath: String, path: String): List<String>? {
    val rootSegments = canonicalPhotoPathSegments(rootPath) ?: return null
    val pathSegments = canonicalPhotoPathSegments(path) ?: return null
    if (pathSegments.size < rootSegments.size || pathSegments.take(rootSegments.size) != rootSegments) {
        return null
    }
    return buildList {
        add("/${rootSegments.joinToString("/")}")
        for (index in rootSegments.size until pathSegments.size) {
            add("/${pathSegments.take(index + 1).joinToString("/")}")
        }
    }
}

private fun canonicalPhotoPathSegments(path: String): List<String>? {
    if (!path.startsWith('/') || path == "/" || path.endsWith('/')) return null
    val segments = path.drop(1).split('/')
    if (segments.any { it.isEmpty() || it == "." || it == ".." }) return null
    return segments
}

data class PhotoViewerState(
    val items: List<FileItem>,
    val index: Int,
) {
    init {
        require(items.isNotEmpty()) { "Photo viewer sequence cannot be empty" }
        require(index in items.indices) { "Photo viewer sequence index is out of bounds" }
    }

    val current: FileItem get() = items[index]
    val hasPrevious: Boolean get() = index > 0
    val hasNext: Boolean get() = index + 1 < items.size
}

val PERSONAL_PHOTO_SPACE = PhotoSpace(
    id = "personal",
    title = "Personal",
    rootPath = "/home/Photos",
    kind = PhotoSpaceKind.PERSONAL,
)

val SHARED_PHOTO_SPACE = PhotoSpace(
    id = "shared",
    title = "Shared",
    rootPath = "/photo",
    kind = PhotoSpaceKind.SHARED,
)

val DEFAULT_PHOTO_SPACES = listOf(PERSONAL_PHOTO_SPACE, SHARED_PHOTO_SPACE)

val PHOTO_IMAGE_EXTENSIONS = setOf(
    "jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif", "tif", "tiff",
    "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2",
)

val PHOTO_VIDEO_EXTENSIONS = setOf(
    "mp4", "mov", "m4v", "avi", "mkv", "webm", "mts", "m2ts", "3gp",
)
