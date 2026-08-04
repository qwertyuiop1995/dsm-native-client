package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskPage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskSummary
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FileBackgroundTaskStatePolicyTest {
    @Test
    fun `回调必须同时匹配仓库配置模块和单调代次`() {
        val token = FileBackgroundTaskRequestToken(
            profileId = "profile-a",
            generation = 7,
            offset = 0,
            kind = FileBackgroundTaskRequestKind.REFRESH,
        )

        assertTrue(
            fileBackgroundTaskCallbackMatches(
                repositoryMatches = true,
                selectedModule = Module.TRANSFERS,
                currentProfileId = "profile-a",
                token = token,
                currentGeneration = 7,
            ),
        )
        assertFalse(matches(token, repositoryMatches = false))
        assertFalse(matches(token, profileId = "profile-b"))
        assertFalse(matches(token, module = Module.FILES))
        assertFalse(matches(token, generation = 8))
    }

    @Test
    fun `分页追加按稳定ID去重并采用新页游标和hasMore`() {
        val current = page(
            tasks = listOf(task("a"), task("b")),
            offset = 0,
            nextOffset = 2,
            total = 5,
            hasMore = true,
        )
        val incoming = page(
            tasks = listOf(task("b"), task("c")),
            offset = 2,
            nextOffset = 4,
            total = 4,
            hasMore = false,
        )

        val merged = appendFileBackgroundTaskPage(current, incoming, expectedOffset = 2)

        assertEquals(listOf("a", "b", "c"), merged?.tasks?.map { it.id })
        assertEquals(0, merged?.offset)
        assertEquals(4, merged?.nextOffset)
        assertEquals(4, merged?.total)
        assertFalse(checkNotNull(merged).hasMore)
    }

    @Test
    fun `分页总数不会小于已保留的唯一任务数`() {
        val current = page(listOf(task("a"), task("b")), 0, 2, 2, true)
        val incoming = page(listOf(task("c"), task("d")), 2, 4, 1, false)

        val merged = checkNotNull(appendFileBackgroundTaskPage(current, incoming, 2))

        assertEquals(4, merged.total)
        assertEquals(4, merged.tasks.size)
    }

    @Test
    fun `分页基线或服务端偏移漂移时拒绝合并`() {
        val current = page(listOf(task("a")), 0, 1, 3, true)

        assertNull(
            appendFileBackgroundTaskPage(
                current,
                page(listOf(task("b")), 2, 3, 3, false),
                expectedOffset = 1,
            ),
        )
        assertNull(
            appendFileBackgroundTaskPage(
                current,
                page(listOf(task("b")), 1, 2, 3, false),
                expectedOffset = 2,
            ),
        )
    }

    @Test
    fun `已结束状态保持领域语义且不会在合并时改写`() {
        val finished = task("done", FileBackgroundTaskState.FINISHED)
        val merged = checkNotNull(
            appendFileBackgroundTaskPage(
                page(emptyList(), 0, 0, 1, true),
                page(listOf(finished), 0, 1, 1, false),
                expectedOffset = 0,
            ),
        )

        assertEquals(FileBackgroundTaskState.FINISHED, merged.tasks.single().state)
    }

    private fun matches(
        token: FileBackgroundTaskRequestToken,
        repositoryMatches: Boolean = true,
        module: Module = Module.TRANSFERS,
        profileId: String = "profile-a",
        generation: Long = 7,
    ) = fileBackgroundTaskCallbackMatches(
        repositoryMatches,
        module,
        profileId,
        token,
        generation,
    )

    private fun task(
        id: String,
        state: FileBackgroundTaskState = FileBackgroundTaskState.ACTIVE,
    ) = FileBackgroundTaskSummary(
        id = id,
        kind = FileBackgroundTaskKind.COPY_OR_MOVE,
        state = state,
        progress = null,
        createdAtEpochSeconds = null,
        processedItemCount = null,
        totalItemCount = null,
        processedBytes = null,
        totalBytes = null,
    )

    private fun page(
        tasks: List<FileBackgroundTaskSummary>,
        offset: Int,
        nextOffset: Int,
        total: Int,
        hasMore: Boolean,
    ) = FileBackgroundTaskPage(tasks, offset, nextOffset, total, hasMore)
}
