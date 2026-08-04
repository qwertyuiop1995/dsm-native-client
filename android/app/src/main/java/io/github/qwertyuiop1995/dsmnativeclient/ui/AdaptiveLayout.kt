package io.github.qwertyuiop1995.dsmnativeclient.ui

/**
 * 统一的大窗口宽度策略。断点采用 Material 3 的 compact / medium / expanded 语义，
 * 各功能仍可根据内容所需最小宽度选择更保守的双栏阈值。
 */
internal enum class AdaptiveWindowWidth {
    COMPACT,
    MEDIUM,
    EXPANDED,
}

internal enum class AdaptiveNavigationType {
    BOTTOM_BAR,
    RAIL,
    PERMANENT_DRAWER,
}

internal fun adaptiveWindowWidth(widthDp: Float): AdaptiveWindowWidth = when {
    widthDp < 600f -> AdaptiveWindowWidth.COMPACT
    widthDp < 840f -> AdaptiveWindowWidth.MEDIUM
    else -> AdaptiveWindowWidth.EXPANDED
}

internal object AdaptiveLayoutPolicy {
    fun navigationType(widthDp: Float): AdaptiveNavigationType = when (
        adaptiveWindowWidth(widthDp)
    ) {
        AdaptiveWindowWidth.COMPACT -> AdaptiveNavigationType.BOTTOM_BAR
        AdaptiveWindowWidth.MEDIUM -> AdaptiveNavigationType.RAIL
        AdaptiveWindowWidth.EXPANDED -> AdaptiveNavigationType.PERMANENT_DRAWER
    }

    fun usesPermanentNavigation(widthDp: Float): Boolean =
        navigationType(widthDp) == AdaptiveNavigationType.PERMANENT_DRAWER

    fun usesNavigationRail(widthDp: Float): Boolean =
        navigationType(widthDp) == AdaptiveNavigationType.RAIL

    fun usesChatListDetail(widthDp: Float): Boolean =
        adaptiveWindowWidth(widthDp) == AdaptiveWindowWidth.EXPANDED

    fun usesDownloadListDetail(widthDp: Float): Boolean =
        adaptiveWindowWidth(widthDp) == AdaptiveWindowWidth.EXPANDED

    fun usesFileListDetail(widthDp: Int, hasPreview: Boolean): Boolean =
        widthDp >= 1_120 && hasPreview

    fun usesPhotoListDetail(widthDp: Int, hasPreview: Boolean): Boolean =
        widthDp >= 1_200 && hasPreview
}
