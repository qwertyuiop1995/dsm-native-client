package io.github.qwertyuiop1995.dsmnativeclient.domain

enum class FileSortOption {
    NAME,
    MODIFIED_TIME,
    SIZE,
}

enum class FileTypeFilter {
    ALL,
    FOLDERS,
    FILES,
}

enum class FileViewMode {
    LIST,
    GRID,
}

data class FileBrowserState(
    val path: String = "",
    val pathHistory: List<String> = emptyList(),
    val searchQuery: String = "",
    val activeSearchQuery: String? = null,
    val sortOption: FileSortOption = FileSortOption.NAME,
    val sortAscending: Boolean = true,
    val typeFilter: FileTypeFilter = FileTypeFilter.ALL,
    val viewMode: FileViewMode = FileViewMode.LIST,
    val selectedPaths: Set<String> = emptySet(),
) {
    fun enterDirectory(directoryPath: String): FileBrowserState = copy(
        path = directoryPath,
        pathHistory = pathHistory + path,
        searchQuery = "",
        activeSearchQuery = null,
        selectedPaths = emptySet(),
    )

    fun navigateUp(): FileBrowserState? {
        val previous = pathHistory.lastOrNull() ?: return null
        return copy(
            path = previous,
            pathHistory = pathHistory.dropLast(1),
            searchQuery = "",
            activeSearchQuery = null,
            selectedPaths = emptySet(),
        )
    }

    fun navigateTo(targetPath: String): FileBrowserState? {
        val lineage = pathHistory + path
        val targetIndex = lineage.indexOf(targetPath)
        if (targetIndex < 0 || targetPath == path) return null
        return copy(
            path = targetPath,
            pathHistory = lineage.take(targetIndex),
            searchQuery = "",
            activeSearchQuery = null,
            selectedPaths = emptySet(),
        )
    }

    fun editSearchQuery(query: String): FileBrowserState = copy(searchQuery = query)

    fun submitSearch(): FileBrowserState = copy(
        activeSearchQuery = searchQuery.trim().ifBlank { null },
        selectedPaths = emptySet(),
    )


    fun changeSort(option: FileSortOption): FileBrowserState = when (option) {
        sortOption -> copy(sortAscending = !sortAscending)
        else -> copy(sortOption = option, sortAscending = true)
    }

    fun changeFilter(filter: FileTypeFilter): FileBrowserState = copy(
        typeFilter = filter,
        selectedPaths = emptySet(),
    )

    fun changeViewMode(mode: FileViewMode): FileBrowserState = copy(viewMode = mode)

    fun toggleSelection(path: String): FileBrowserState = copy(
        selectedPaths = if (path in selectedPaths) selectedPaths - path else selectedPaths + path,
    )

    fun clearSelection(): FileBrowserState = copy(selectedPaths = emptySet())

    fun openShortcut(targetPath: String): FileBrowserState = copy(
        path = targetPath,
        pathHistory = listOf(""),
        searchQuery = "",
        activeSearchQuery = null,
        selectedPaths = emptySet(),
    )

    fun visibleItems(items: List<FileItem>): List<FileItem> {
        val filtered = items.filter { item ->
            when (typeFilter) {
                FileTypeFilter.ALL -> true
                FileTypeFilter.FOLDERS -> item.isDirectory
                FileTypeFilter.FILES -> !item.isDirectory
            }
        }
        val comparator = Comparator<FileItem> { left, right ->
            when (sortOption) {
                FileSortOption.NAME -> left.name.compareTo(right.name, ignoreCase = true)
                FileSortOption.MODIFIED_TIME -> compareValues(
                    left.modifiedAtEpochSeconds ?: Long.MIN_VALUE,
                    right.modifiedAtEpochSeconds ?: Long.MIN_VALUE,
                )
                FileSortOption.SIZE -> left.size.compareTo(right.size)
            }
        }
        return filtered.sortedWith(if (sortAscending) comparator else comparator.reversed())
    }
}
