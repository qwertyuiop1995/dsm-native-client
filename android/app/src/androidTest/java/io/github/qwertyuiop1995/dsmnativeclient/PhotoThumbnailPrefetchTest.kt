package io.github.qwertyuiop1995.dsmnativeclient

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoItemKind
import io.github.qwertyuiop1995.dsmnativeclient.ui.PhotoThumbnailArtwork
import io.github.qwertyuiop1995.dsmnativeclient.ui.PhotoThumbnailWindowEffect
import io.github.qwertyuiop1995.dsmnativeclient.ui.thumbnailPrefetchItems
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class PhotoThumbnailPrefetchTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 开头可见范围按顺序预取四个媒体并跳过文件夹() {
        val items = items()

        val result = thumbnailPrefetchItems(items, visibleIndices = listOf(0, 1))

        assertEquals(listOf("image-3", "video-4", "image-5", "video-6"), result.map { it.id })
    }

    @Test
    fun 中间可见范围从最后索引之后继续预取() {
        val result = thumbnailPrefetchItems(items(), visibleIndices = listOf(3, 4))

        assertEquals(listOf("image-5", "video-6", "image-7"), result.map { it.id })
    }

    @Test
    fun 尾部和空可见范围不越界() {
        assertEquals(emptyList<PhotoItem>(), thumbnailPrefetchItems(items(), listOf(7)))
        assertEquals(emptyList<PhotoItem>(), thumbnailPrefetchItems(items(), emptyList()))
        assertEquals(emptyList<PhotoItem>(), thumbnailPrefetchItems(items(), listOf(-1, 99)))
    }

    @Test
    fun 自定义上限保持稳定顺序且不包含当前可见项() {
        val result = thumbnailPrefetchItems(
            items = items(),
            visibleIndices = listOf(4, 1, 4),
            maximumItems = 2,
        )

        assertEquals(listOf("image-5", "video-6"), result.map { it.id })
    }

    @Test
    fun 视频缩略未载入时使用中性语义并显示可访问播放标识() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val video = item("video-fallback", PhotoItemKind.VIDEO)
        rule.setContent {
            LanStashTheme {
                Box(Modifier.size(160.dp)) {
                    PhotoThumbnailArtwork(video, bitmap = null)
                }
            }
        }

        rule.onNodeWithContentDescription(
            context.getString(R.string.video_thumbnail_description, video.file.name),
        ).assertIsDisplayed()
        rule.onNodeWithContentDescription(
            context.getString(R.string.play_video_preview, video.file.name),
        ).assertIsDisplayed()
    }

    @Test
    fun 图片缩略未载入时使用中性语义() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val image = item("image-placeholder", PhotoItemKind.IMAGE)
        rule.setContent {
            LanStashTheme {
                Box(Modifier.size(160.dp)) {
                    PhotoThumbnailArtwork(image, bitmap = null)
                }
            }
        }

        rule.onNodeWithContentDescription(
            context.getString(R.string.photo_thumbnail_description, image.file.name),
        ).assertIsDisplayed()
    }

    @Test
    fun 视频真实缩略图保留可访问播放标识() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val video = item("video-thumbnail", PhotoItemKind.VIDEO)
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
        rule.setContent {
            LanStashTheme {
                Box(Modifier.size(160.dp)) {
                    PhotoThumbnailArtwork(video, bitmap)
                }
            }
        }

        rule.onNodeWithContentDescription(
            context.getString(R.string.video_thumbnail_description, video.file.name),
        ).assertIsDisplayed()
        rule.onNodeWithContentDescription(
            context.getString(R.string.play_video_preview, video.file.name),
        ).assertIsDisplayed()
    }

    @Test
    fun 缩略图窗口在滚动配置变化和退出组合时严格平衡引用() {
        val events = mutableListOf<ThumbnailEvent>()
        var profileId by mutableStateOf("profile-a")
        var enabled by mutableStateOf(true)
        var currentItems by mutableStateOf(lifecycleItems())
        var mounted by mutableStateOf(true)
        lateinit var gridState: LazyGridState

        rule.setContent {
            LanStashTheme {
                if (mounted) {
                    gridState = rememberLazyGridState()
                    PhotoThumbnailWindowEffect(
                        gridState = gridState,
                        items = currentItems,
                        profileId = profileId,
                        enabled = enabled,
                        acquireThumbnail = { item, profile ->
                            events += ThumbnailEvent(profile, item.file.path, acquired = true)
                        },
                        releaseThumbnail = { item, profile ->
                            events += ThumbnailEvent(profile, item.file.path, acquired = false)
                        },
                    )
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(1),
                        state = gridState,
                        modifier = Modifier
                            .size(width = 160.dp, height = 240.dp)
                            .testTag("thumbnail-grid"),
                    ) {
                        items(currentItems, key = PhotoItem::id) {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .height(80.dp),
                            )
                        }
                    }
                }
            }
        }

        rule.waitForIdle()
        val initialExpected = expectedActivePaths(gridState, currentItems)
        assertEquals(4, expectedPrefetchPaths(gridState, currentItems).size)
        assertEquals(initialExpected.withProfile(profileId), events.activeReferences())

        val initialActive = events.activeReferences()
        rule.onNodeWithTag("thumbnail-grid").performScrollToIndex(10)
        rule.waitForIdle()
        val lateExpected = expectedActivePaths(gridState, currentItems).withProfile(profileId)
        val lateActive = events.activeReferences()
        assertEquals(lateExpected, lateActive)
        assertTrue((initialActive - lateActive).isNotEmpty())
        assertTrue((lateActive - initialActive).isNotEmpty())

        rule.onNodeWithTag("thumbnail-grid").performScrollToIndex(0)
        rule.waitForIdle()
        assertEquals(
            expectedActivePaths(gridState, currentItems).withProfile(profileId),
            events.activeReferences(),
        )

        rule.runOnIdle { profileId = "profile-b" }
        rule.waitForIdle()
        assertTrue(events.activeReferences().none { it.first == "profile-a" })
        assertEquals(
            expectedActivePaths(gridState, currentItems).withProfile(profileId),
            events.activeReferences(),
        )

        rule.runOnIdle { enabled = false }
        rule.waitForIdle()
        assertEquals(emptySet<Pair<String, String>>(), events.activeReferences())

        rule.runOnIdle { enabled = true }
        rule.waitForIdle()
        rule.onNodeWithTag("thumbnail-grid").performScrollToIndex(10)
        rule.waitForIdle()
        rule.runOnIdle { currentItems = currentItems.take(5) }
        rule.waitForIdle()
        assertEquals(
            expectedActivePaths(gridState, currentItems).withProfile(profileId),
            events.activeReferences(),
        )
        assertTrue(events.activeReferences().all { (_, path) ->
            currentItems.any { it.file.path == path }
        })

        rule.runOnIdle { mounted = false }
        rule.waitForIdle()
        assertTrue(events.referenceBalances().values.all { it == 0 })
    }

    private fun items() = listOf(
        item("image-0", PhotoItemKind.IMAGE),
        item("video-1", PhotoItemKind.VIDEO),
        item("folder-2", PhotoItemKind.FOLDER),
        item("image-3", PhotoItemKind.IMAGE),
        item("video-4", PhotoItemKind.VIDEO),
        item("image-5", PhotoItemKind.IMAGE),
        item("video-6", PhotoItemKind.VIDEO),
        item("image-7", PhotoItemKind.IMAGE),
    )

    private fun lifecycleItems(): List<PhotoItem> = (0 until 18).map { index ->
        val kind = when {
            index % 5 == 2 -> PhotoItemKind.FOLDER
            index % 2 == 0 -> PhotoItemKind.IMAGE
            else -> PhotoItemKind.VIDEO
        }
        item("lifecycle-$index", kind)
    }

    private fun expectedActivePaths(
        gridState: LazyGridState,
        items: List<PhotoItem>,
    ): Set<String> {
        var result = emptySet<String>()
        rule.runOnIdle {
            val visibleIndices = gridState.layoutInfo.visibleItemsInfo
                .map { it.index }
                .filter { it in items.indices }
                .distinct()
                .sorted()
            val visibleMedia = visibleIndices
                .map(items::get)
                .filter { it.kind != PhotoItemKind.FOLDER }
            result = (visibleMedia + thumbnailPrefetchItems(items, visibleIndices))
                .mapTo(mutableSetOf()) { it.file.path }
        }
        return result
    }

    private fun expectedPrefetchPaths(
        gridState: LazyGridState,
        items: List<PhotoItem>,
    ): Set<String> {
        var result = emptySet<String>()
        rule.runOnIdle {
            val visibleIndices = gridState.layoutInfo.visibleItemsInfo.map { it.index }
            result = thumbnailPrefetchItems(items, visibleIndices)
                .mapTo(mutableSetOf()) { it.file.path }
        }
        return result
    }

    private fun item(id: String, kind: PhotoItemKind): PhotoItem {
        val extension = when (kind) {
            PhotoItemKind.FOLDER -> ""
            PhotoItemKind.IMAGE -> ".jpg"
            PhotoItemKind.VIDEO -> ".mov"
        }
        return PhotoItem(
            id = id,
            file = FileItem(
                path = "/synthetic/$id$extension",
                name = "$id$extension",
                isDirectory = kind == PhotoItemKind.FOLDER,
            ),
            kind = kind,
            takenAtEpochSeconds = null,
        )
    }
}

private data class ThumbnailEvent(
    val profileId: String,
    val path: String,
    val acquired: Boolean,
)

private fun List<ThumbnailEvent>.referenceBalances(): Map<Pair<String, String>, Int> =
    groupBy { it.profileId to it.path }
        .mapValues { (_, events) ->
            events.fold(0) { balance, event ->
                balance + if (event.acquired) 1 else -1
            }
        }

private fun List<ThumbnailEvent>.activeReferences(): Set<Pair<String, String>> =
    referenceBalances()
        .filterValues { it > 0 }
        .keys

private fun Set<String>.withProfile(profileId: String): Set<Pair<String, String>> =
    mapTo(mutableSetOf()) { profileId to it }
