package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadDestinationEditStatePolicyTest {
    @Test
    fun `目标绑定完整任务与可写目录基线且同路径零操作`() {
        val task = task(destination = "/downloads")
        val folder = folder("/archive")
        val target = downloadDestinationEditTarget(
            "profile-a",
            Loadable.Ready(listOf(task)),
            task.id,
            folder,
        )

        assertNotNull(target)
        assertEquals(task, target?.taskBaseline)
        assertEquals(folder, target?.destinationBaseline)
        assertNull(
            downloadDestinationEditTarget(
                "profile-a",
                Loadable.Ready(listOf(task)),
                task.id,
                folder("/downloads"),
            ),
        )
    }

    @Test
    fun `缺失歧义只读或非目录均不能建立目标`() {
        val task = task()
        assertNull(downloadDestinationEditTarget("profile", Loadable.Loading, task.id, folder()))
        assertNull(
            downloadDestinationEditTarget(
                "profile",
                Loadable.Ready(listOf(task, task.copy(title = "重复"))),
                task.id,
                folder(),
            ),
        )
        assertNull(
            downloadDestinationEditTarget(
                "profile",
                Loadable.Ready(listOf(task)),
                task.id,
                folder().copy(canWrite = false),
            ),
        )
        assertNull(
            downloadDestinationEditTarget(
                "profile",
                Loadable.Ready(listOf(task)),
                task.id,
                folder().copy(isDirectory = false),
            ),
        )
    }

    @Test
    fun `动态传输字段不构成漂移而稳定任务字段变化拒绝确认`() {
        val target = target()
        val dynamic = target.taskBaseline.copy(transferred = 80, downloadSpeed = 4)
        assertTrue(
            downloadDestinationEditTargetIsCurrent(
                target,
                "profile-a",
                Loadable.Ready(listOf(dynamic)),
            ),
        )
        assertFalse(
            downloadDestinationEditTargetIsCurrent(
                target,
                "profile-a",
                Loadable.Ready(listOf(dynamic.copy(title = "已变化"))),
            ),
        )
        assertFalse(
            downloadDestinationEditTargetIsCurrent(
                target,
                "profile-b",
                Loadable.Ready(listOf(dynamic)),
            ),
        )
    }

    @Test
    fun `专项刷新只在同一任务精确返回新目录时匹配`() {
        val target = target()
        assertTrue(
            downloadDestinationEditRefreshMatches(
                target,
                listOf(target.taskBaseline.copy(destination = "/archive")),
            ),
        )
        assertFalse(downloadDestinationEditRefreshMatches(target, listOf(target.taskBaseline)))
        assertFalse(downloadDestinationEditRefreshMatches(target, emptyList()))
    }

    @Test
    fun `旧Repository旧NAS旧目标和代次均拒绝回调`() {
        val target = target()
        assertTrue(downloadDestinationEditCallbackMatches(true, true, target, target, 5, 5, 5))
        assertFalse(downloadDestinationEditCallbackMatches(false, true, target, target, 5, 5, 5))
        assertFalse(downloadDestinationEditCallbackMatches(true, false, target, target, 5, 5, 5))
        assertFalse(downloadDestinationEditCallbackMatches(true, true, null, target, 5, 5, 5))
        assertFalse(downloadDestinationEditCallbackMatches(true, true, target, target, 4, 5, 5))
    }

    @Test
    fun `确认执行和未核对结果阻止离开而可信刷新后允许关闭`() {
        val target = target()
        assertTrue(
            downloadDestinationEditBlocksWorkspaceExit(
                DownloadDestinationEditWorkspaceState(selectionTaskBaseline = target.taskBaseline),
            ),
        )
        assertTrue(
            downloadDestinationEditBlocksWorkspaceExit(
                DownloadDestinationEditWorkspaceState(target = target, confirmationRequested = true),
            ),
        )
        val unknown = DownloadDestinationEditWorkspaceState(
            target = target,
            mutationResult = MutationResult(
                schemaVersion = 1,
                status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                operation = "downloadEditDestination",
                submitted = true,
                requiresRefresh = true,
                counts = MutationResultCounts(0, 0, 1),
                diagnosticTag = "synthetic",
            ),
        )
        assertTrue(downloadDestinationEditBlocksWorkspaceExit(unknown))
        assertFalse(canDismissDownloadDestinationEditMutation(unknown))
        val checked = unknown.copy(mutationRefreshCompleted = true, mutationRefreshMatches = true)
        assertFalse(downloadDestinationEditBlocksWorkspaceExit(checked))
        assertTrue(canDismissDownloadDestinationEditMutation(checked))
    }

    @Test
    fun `外部取消保持已提交待核对语义`() {
        val result = cancelledDownloadDestinationEditResult()
        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result.status)
        assertTrue(result.submitted)
        assertTrue(result.requiresRefresh)
        assertEquals(1, result.counts.unknown)
    }

    private fun target() = DownloadDestinationEditTarget(
        profileId = "profile-a",
        taskBaseline = task(),
        destinationBaseline = folder(),
    )

    private fun task(destination: String? = "/downloads") = DownloadTask(
        id = "task-1",
        type = "http",
        title = "Synthetic",
        status = ResourceState.RUNNING,
        size = 100,
        transferred = 10,
        downloadSpeed = 1,
        uploadSpeed = 0,
        destination = destination,
        error = null,
    )

    private fun folder(path: String = "/archive") = FileItem(
        path = path,
        name = path.substringAfterLast('/'),
        isDirectory = true,
        canWrite = true,
    )
}
