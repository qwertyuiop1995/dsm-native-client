package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadStationActivity
import io.github.qwertyuiop1995.dsmnativeclient.domain.DownloadTask
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.ResourceState
import org.junit.Assert.assertEquals
import org.junit.Test

class DownloadActivityStatePolicyTest {
    @Test
    fun `活动重试只进入活动加载态并保留任务列表`() {
        val tasks = Loadable.Ready(listOf(task()))
        val current = state().copy(
            downloads = tasks,
            downloadAdvancedRead = DownloadAdvancedReadWorkspaceState(
                activity = Loadable.Failed(DsmFailure(null, "synthetic", "retry")),
            ),
        )

        val loading = current.withDownloadActivity(Loadable.Loading)

        assertEquals(tasks, loading.downloads)
        assertEquals(Loadable.Loading, loading.downloadAdvancedRead.activity)
    }

    @Test
    fun `活动失败和成功均不遮蔽任务列表`() {
        val tasks = Loadable.Ready(listOf(task()))
        val current = state().copy(downloads = tasks)

        val failed = current.withDownloadActivity(
            Loadable.Failed(DsmFailure(null, "synthetic", "retry")),
        )
        val ready = current.withDownloadActivity(
            Loadable.Ready(DownloadStationActivity(1, 2, 3, 4)),
        )

        assertEquals(tasks, failed.downloads)
        assertEquals(tasks, ready.downloads)
    }

    private fun state() = WorkspaceState(
        profile = NasProfile("test", "Test", "https://nas.example.invalid", "tester"),
    )

    private fun task() = DownloadTask(
        id = "task-1",
        type = "bt",
        title = "Synthetic task",
        status = ResourceState.RUNNING,
        size = 10,
        transferred = 1,
        downloadSpeed = 1,
        uploadSpeed = 0,
        destination = "downloads",
        error = null,
    )
}
