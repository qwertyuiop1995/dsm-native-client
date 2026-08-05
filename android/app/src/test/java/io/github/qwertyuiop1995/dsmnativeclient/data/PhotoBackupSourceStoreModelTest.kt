package io.github.qwertyuiop1995.dsmnativeclient.data

import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhotoBackupSourceStoreModelTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `旧自动备份来源缺少关注状态时保持可用`() {
        val restored = json.decodeFromString<PersistedPhotoBackupSource>(
            """{
                "profileId":"profile-a",
                "treeUri":"content://synthetic/tree",
                "destinationPath":"/photo/backup"
            }""".trimIndent(),
        )

        assertTrue(restored.enabled)
        assertFalse(restored.needsAttention)
        assertNull(restored.workId)
    }

    @Test
    fun `需要关注的自动备份来源可完整恢复`() {
        val source = PersistedPhotoBackupSource(
            profileId = "profile-a",
            treeUri = "content://synthetic/tree",
            destinationPath = "/photo/backup",
            workId = "work-a",
            enabled = false,
            needsAttention = true,
        )

        val restored = json.decodeFromString<PersistedPhotoBackupSource>(json.encodeToString(source))

        assertEquals(source, restored)
        assertTrue(restored.needsAttention)
        assertFalse(restored.enabled)
    }
}
