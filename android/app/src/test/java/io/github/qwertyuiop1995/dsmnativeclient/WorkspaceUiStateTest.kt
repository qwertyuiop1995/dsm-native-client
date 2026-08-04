package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileSortOption
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileTypeFilter
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileViewMode
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation
import io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.ModuleAvailability
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.storage.PersistedWorkspaceUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WorkspaceUiStateTest {
    @Test
    fun `恢复目录搜索排序筛选与视图但不恢复危险选择`() {
        val (module, restored) = restoreWorkspaceUiState(
            saved = PersistedWorkspaceUiState(
                filePath = "/home/docs",
                filePathHistory = listOf("", "/home"),
                fileSearchQuery = "report",
                fileActiveSearchQuery = "report",
                fileSortOption = "SIZE",
                fileSortAscending = false,
                fileTypeFilter = "FILES",
                fileViewMode = "GRID",
            ),
            availability = listOf(ModuleAvailability(Module.FILES, isAvailable = true)),
        )

        assertEquals(Module.FILES, module)
        assertEquals("/home/docs", restored.path)
        assertEquals(listOf("", "/home"), restored.pathHistory)
        assertEquals(FileSortOption.SIZE, restored.sortOption)
        assertEquals(FileTypeFilter.FILES, restored.typeFilter)
        assertEquals(FileViewMode.GRID, restored.viewMode)
        assertTrue(restored.selectedPaths.isEmpty())
    }

    @Test
    fun `可用模块按保存状态恢复`() {
        val (module, _) = restoreWorkspaceUiState(
            saved = PersistedWorkspaceUiState(selectedModule = "CHAT"),
            availability = listOf(
                ModuleAvailability(Module.FILES, isAvailable = true),
                ModuleAvailability(Module.CHAT, isAvailable = true),
            ),
        )

        assertEquals(Module.CHAT, module)
    }

    @Test
    fun `不可用或损坏的保存模块安全回退文件`() {
        val availability = listOf(
            ModuleAvailability(Module.FILES, isAvailable = true),
            ModuleAvailability(Module.CHAT, isAvailable = false),
        )

        val unavailable = restoreWorkspaceUiState(
            saved = PersistedWorkspaceUiState(selectedModule = "CHAT"),
            availability = availability,
        )
        val damaged = restoreWorkspaceUiState(
            saved = PersistedWorkspaceUiState(selectedModule = "REMOVED"),
            availability = availability,
        )

        assertEquals(Module.FILES, unavailable.first)
        assertEquals(Module.FILES, damaged.first)
    }

    @Test
    fun `文件不可用时首次进入和损坏状态回退到传输中心`() {
        val availability = listOf(
            ModuleAvailability(Module.FILES, isAvailable = false),
            ModuleAvailability(Module.CHAT, isAvailable = false),
            ModuleAvailability(Module.TRANSFERS, isAvailable = true),
            ModuleAvailability(Module.SETTINGS, isAvailable = true),
        )

        assertEquals(
            Module.TRANSFERS,
            restoreWorkspaceUiState(saved = null, availability = availability).first,
        )
        assertEquals(
            Module.TRANSFERS,
            restoreWorkspaceUiState(
                saved = PersistedWorkspaceUiState(selectedModule = "CHAT"),
                availability = availability,
            ).first,
        )
        assertEquals(
            Module.TRANSFERS,
            restoreWorkspaceUiState(
                saved = PersistedWorkspaceUiState(selectedModule = "REMOVED"),
                availability = availability,
            ).first,
        )
    }

    @Test
    fun `损坏的枚举与非绝对路径安全回退`() {
        val restored = restoreFileBrowserState(
            PersistedWorkspaceUiState(
                filePath = "relative/private",
                filePathHistory = listOf("relative", "/home"),
                fileSortOption = "REMOVED",
                fileTypeFilter = "REMOVED",
                fileViewMode = "REMOVED",
            ),
        )

        assertEquals("", restored.path)
        assertEquals(listOf("/home"), restored.pathHistory)
        assertEquals(FileSortOption.NAME, restored.sortOption)
        assertEquals(FileTypeFilter.ALL, restored.typeFilter)
        assertEquals(FileViewMode.LIST, restored.viewMode)
    }

    @Test
    fun `本地置顶按保存顺序排列且不改变未置顶相对顺序`() {
        val conversations = listOf(
            conversation("a"), conversation("b"), conversation("c"),
        )

        val sorted = applyChatConversationPreferences(conversations, listOf("c", "a"))

        assertEquals(listOf("c", "a", "b"), sorted.map { it.id })
        assertEquals(listOf(true, true, false), sorted.map { it.isPinnedLocally })
    }

    @Test
    fun `工作区未读汇总忽略负数并限制显示上限`() {
        val conversations = Loadable.Ready(
            listOf(conversation("a", 700), conversation("b", 500), conversation("c", -1)),
        )

        assertEquals(999, chatUnreadCount(conversations))
        assertEquals(0, chatUnreadCount(Loadable.Idle))
    }

    @Test
    fun `工作区状态保存去重后的本地置顶`() {
        val saved = WorkspaceState(
            profile = NasProfile("synthetic", "Synthetic", "https://nas.example.invalid", "operator"),
            chatPinnedConversationIds = listOf("c", "c", "a"),
        ).persistedUiState()

        assertEquals(listOf("c", "a"), saved.chatPinnedConversationIds)
    }

    @Test
    fun `打开后的旧会话列表不会反弹未读数`() {
        val marker = ChatLocalReadMarker(latestAtEpochSeconds = 100, latestPreview = "旧消息")

        val first = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 4, latestAt = 100, preview = "旧消息")),
            markers = mapOf("a" to marker),
        )
        val polledAgain = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 4, latestAt = 100, preview = "旧消息")),
            markers = first.markers,
        )

        assertEquals(0, first.conversations.single().unreadCount)
        assertEquals(0, polledAgain.conversations.single().unreadCount)
        assertEquals(marker, polledAgain.markers["a"])
    }

    @Test
    fun `最新活动推进后恢复服务器未读数`() {
        val result = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 1, latestAt = 101)),
            markers = mapOf(
                "a" to ChatLocalReadMarker(latestAtEpochSeconds = 100, latestPreview = null),
            ),
        )

        assertEquals(1, result.conversations.single().unreadCount)
        assertTrue("a" !in result.markers)
    }

    @Test
    fun `缺少活动时间时用预览变化识别后续新消息`() {
        val marker = ChatLocalReadMarker(latestAtEpochSeconds = null, latestPreview = "旧消息")
        val stale = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 2, preview = "旧消息")),
            markers = mapOf("a" to marker),
        )
        val advanced = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 3, preview = "新消息")),
            markers = stale.markers,
        )

        assertEquals(0, stale.conversations.single().unreadCount)
        assertEquals(3, advanced.conversations.single().unreadCount)
        assertTrue("a" !in advanced.markers)
    }

    @Test
    fun `同秒预览变化恢复服务器未读数`() {
        val result = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 1, latestAt = 100, preview = "新消息")),
            markers = mapOf(
                "a" to ChatLocalReadMarker(latestAtEpochSeconds = 100, latestPreview = "旧消息"),
            ),
        )

        assertEquals(1, result.conversations.single().unreadCount)
        assertTrue("a" !in result.markers)
    }

    @Test
    fun `同秒首次出现预览时保守恢复服务器未读数`() {
        val result = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 1, latestAt = 100, preview = "新消息")),
            markers = mapOf(
                "a" to ChatLocalReadMarker(latestAtEpochSeconds = 100, latestPreview = null),
            ),
        )

        assertEquals(1, result.conversations.single().unreadCount)
        assertTrue("a" !in result.markers)
    }

    @Test
    fun `活动时间和预览都缺失时不继续隐藏未读`() {
        assertEquals(null, conversation("new", unread = 2).toChatLocalReadMarker())
        val result = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 2)),
            markers = mapOf(
                "a" to ChatLocalReadMarker(latestAtEpochSeconds = 100, latestPreview = "旧消息"),
            ),
        )

        assertEquals(2, result.conversations.single().unreadCount)
        assertTrue("a" !in result.markers)
    }

    @Test
    fun `服务器未读归零后移除本地覆盖`() {
        val result = applyChatLocalReadOverlay(
            conversations = listOf(conversation("a", unread = 0, latestAt = 100, preview = "旧消息")),
            markers = mapOf(
                "a" to ChatLocalReadMarker(latestAtEpochSeconds = 100, latestPreview = "旧消息"),
            ),
        )

        assertEquals(0, result.conversations.single().unreadCount)
        assertTrue("a" !in result.markers)
    }

    @Test
    fun `零未读会话和已从列表移除的会话不保留覆盖`() {
        assertEquals(null, conversation("zero", unread = 0, latestAt = 100).toChatLocalReadMarker())
        val result = applyChatLocalReadOverlay(
            conversations = listOf(conversation("visible", unread = 0, latestAt = 100)),
            markers = mapOf(
                "removed" to ChatLocalReadMarker(latestAtEpochSeconds = 90, latestPreview = null),
            ),
        )

        assertTrue(result.markers.isEmpty())
    }

    @Test
    fun `本地已读覆盖按会话隔离`() {
        val result = applyChatLocalReadOverlay(
            conversations = listOf(
                conversation("a", unread = 1, latestAt = 11),
                conversation("b", unread = 7, latestAt = 20),
                conversation("c", unread = 5, latestAt = 30),
            ),
            markers = mapOf(
                "a" to ChatLocalReadMarker(latestAtEpochSeconds = 10, latestPreview = null),
                "b" to ChatLocalReadMarker(latestAtEpochSeconds = 20, latestPreview = null),
            ),
        )

        assertEquals(listOf(1, 0, 5), result.conversations.map { it.unreadCount })
        assertEquals(setOf("b"), result.markers.keys)
    }

    private fun conversation(
        id: String,
        unread: Int = 0,
        latestAt: Long? = null,
        preview: String? = null,
    ) = ChatConversation(
        id = id,
        title = id,
        kind = ConversationKind.DIRECT,
        unreadCount = unread,
        latestPreview = preview,
        latestAtEpochSeconds = latestAt,
    )
}
