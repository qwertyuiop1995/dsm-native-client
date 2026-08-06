package io.github.qwertyuiop1995.dsmnativeclient.storage

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.OpaqueWorkspaceRouteRecord
import io.github.qwertyuiop1995.dsmnativeclient.domain.OpaqueWorkspaceTarget
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoBrowserState
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoBrowseMode
import io.github.qwertyuiop1995.dsmnativeclient.domain.PhotoMediaFilter
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OpaqueWorkspaceRouteStoreModelTest {
    @Test
    fun `令牌固定为三十二字节 Base64URL 且无填充`() {
        val tokens = (1..16).map { createOpaqueWorkspaceToken() }

        assertEquals(16, tokens.distinct().size)
        assertTrue(tokens.all(String::isOpaqueWorkspaceToken))
        assertTrue(tokens.all { it.length == OPAQUE_WORKSPACE_TOKEN_LENGTH })
    }

    @Test
    fun `同一资料和目标复用已签发令牌`() {
        val target = OpaqueWorkspaceTarget.FileDirectory("/share/Projects")
        val existing = route("first-token", target, createdAt = 100)

        val issue = planOpaqueWorkspaceRouteIssue(
            current = listOf(existing),
            candidate = route("second-token", target, createdAt = 200),
        )

        assertEquals(existing.token, issue.token)
        assertTrue(issue.removedTokens.isEmpty())
    }

    @Test
    fun `六类最小目标均可加密记录往返且不引入完整领域对象字段`() {
        val json = Json { ignoreUnknownKeys = true }
        val targets = listOf(
            OpaqueWorkspaceTarget.FileDirectory("/share/Projects"),
            OpaqueWorkspaceTarget.FilePreview("/share/Projects/readme.md"),
            OpaqueWorkspaceTarget.PhotoFolder("personal", "/home/Photos/Trips"),
            OpaqueWorkspaceTarget.PhotoViewer("shared", "/photo/Trips/photo.jpg"),
            OpaqueWorkspaceTarget.ChatConversation("conversation-a"),
            OpaqueWorkspaceTarget.DownloadTask("task-a"),
        )

        targets.forEachIndexed { index, target ->
            val record = route(createOpaqueWorkspaceToken(), target, createdAt = index.toLong())
            val encoded = json.encodeToString(record)

            assertEquals(record, json.decodeFromString<OpaqueWorkspaceRouteRecord>(encoded))
            assertFalse(encoded.contains("\"title\""))
            assertFalse(encoded.contains("\"name\""))
            assertFalse(encoded.contains("\"address\""))
            assertFalse(encoded.contains("\"session\""))
        }
    }

    @Test
    fun `单资料超过上限时淘汰创建时间最早的记录`() {
        val current = (0 until MAX_OPAQUE_WORKSPACE_ROUTES_PER_PROFILE).map { index ->
            route(
                token = "token-$index",
                target = OpaqueWorkspaceTarget.ChatConversation("conversation-$index"),
                createdAt = index.toLong(),
            )
        }

        val issue = planOpaqueWorkspaceRouteIssue(
            current = current,
            candidate = route(
                token = "new-token",
                target = OpaqueWorkspaceTarget.DownloadTask("task-new"),
                createdAt = MAX_OPAQUE_WORKSPACE_ROUTES_PER_PROFILE.toLong(),
            ),
        )

        assertEquals("new-token", issue.token)
        assertEquals(setOf("token-0"), issue.removedTokens)
    }

    @Test
    fun `设备时钟回拨时仍保留新签发令牌并维持容量上限`() {
        val current = (0 until MAX_OPAQUE_WORKSPACE_ROUTES_PER_PROFILE).map { index ->
            route(
                token = "token-$index",
                target = OpaqueWorkspaceTarget.ChatConversation("conversation-$index"),
                createdAt = 10_000L + index,
            )
        }

        val issue = planOpaqueWorkspaceRouteIssue(
            current = current,
            candidate = route(
                token = "new-token",
                target = OpaqueWorkspaceTarget.DownloadTask("task-new"),
                createdAt = 1,
            ),
        )

        assertEquals("new-token", issue.token)
        assertEquals(setOf("token-0"), issue.removedTokens)
        assertFalse("new-token" in issue.removedTokens)
    }

    @Test
    fun `损坏或未知 schema 的记录不会影响其他合法记录`() {
        val json = Json { ignoreUnknownKeys = true }
        val valid = route(
            token = createOpaqueWorkspaceToken(),
            target = OpaqueWorkspaceTarget.ChatConversation("conversation-a"),
            createdAt = 100,
        )
        val values = listOf(
            json.encodeToString(valid),
            json.encodeToString(valid.copy(schemaVersion = 2)),
            "{not-json",
        )

        val decoded = values.mapNotNull { value ->
            decodeOpaqueWorkspaceRouteRecord(json, "profile-a", value)
        }

        assertEquals(listOf(valid), decoded)
        assertNull(decodeOpaqueWorkspaceRouteRecord(json, "profile-b", values.first()))
    }

    @Test
    fun `文件规范路径恢复完整父级返回层级并拒绝非规范路径`() {
        val directory = FileBrowserState.fromCanonicalDirectoryPath("/share/Projects/2026")
        val previewParent = FileBrowserState.fromCanonicalFilePath("/share/Projects/2026/readme.md")

        assertEquals("/share/Projects/2026", directory?.path)
        assertEquals(listOf("", "/share", "/share/Projects"), directory?.pathHistory)
        assertEquals("/share/Projects/2026", previewParent?.path)
        assertEquals(listOf("", "/share", "/share/Projects"), previewParent?.pathHistory)
        assertNull(FileBrowserState.fromCanonicalDirectoryPath("/share//Projects"))
        assertNull(FileBrowserState.fromCanonicalDirectoryPath("/share/../Projects"))
        assertNull(FileBrowserState.fromCanonicalDirectoryPath("/share/#recycle/Projects"))
        assertNull(FileBrowserState.fromCanonicalFilePath("/share"))
    }

    @Test
    fun `照片规范路径恢复空间内父级并拒绝越界`() {
        val initial = PhotoBrowserState(
            searchQuery = "old",
            activeSearchQuery = "old",
            filter = PhotoMediaFilter.VIDEOS,
            mode = PhotoBrowseMode.TIMELINE,
            selectedYear = 2026,
            selectedMonth = 8,
        )

        val folder = initial.restoreCanonicalFolder("personal", "/home/Photos/Trips/2026")
        val viewerParent = initial.restoreCanonicalMediaParent(
            "personal",
            "/home/Photos/Trips/2026/photo.jpg",
        )

        assertEquals("/home/Photos/Trips/2026", folder?.folderPath)
        assertEquals(listOf("/home/Photos", "/home/Photos/Trips"), folder?.pathHistory)
        assertEquals(PhotoMediaFilter.ALL, folder?.filter)
        assertEquals(PhotoBrowseMode.FOLDERS, folder?.mode)
        assertEquals("", folder?.searchQuery)
        assertEquals("/home/Photos/Trips/2026", viewerParent?.folderPath)
        assertEquals(listOf("/home/Photos", "/home/Photos/Trips"), viewerParent?.pathHistory)
        assertNull(initial.restoreCanonicalFolder("personal", "/home/PhotosArchive/Trips"))
        assertNull(initial.restoreCanonicalMediaParent("personal", "/home/Photos/../secret.jpg"))
        assertNull(initial.restoreCanonicalFolder("unknown", "/home/Photos/Trips"))
        assertTrue(folder?.pathHistory?.none { it == "/home" } == true)
    }

    private fun route(
        token: String,
        target: OpaqueWorkspaceTarget,
        createdAt: Long,
    ) = OpaqueWorkspaceRouteRecord(
        token = token,
        profileId = "profile-a",
        target = target,
        createdAtEpochMillis = createdAt,
    )
}
