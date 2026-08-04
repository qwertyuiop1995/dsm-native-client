package io.github.qwertyuiop1995.dsmnativeclient

import androidx.work.WorkInfo
import androidx.work.ExistingWorkPolicy
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedDownload
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedUpload
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferTask
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class WorkerCancellationDecisionTest {
    @Test
    fun `只有当前执行处于取消中才解释为用户取消`() {
        assertEquals(
            WorkerCancellationDecision.USER_CANCELLATION,
            workerCancellationDecision(TransferState.CANCELLING, "execution", "execution"),
        )
        assertEquals(
            WorkerCancellationDecision.PRESERVE_CURRENT_STATE,
            workerCancellationDecision(TransferState.RUNNING, "execution", "execution"),
        )
        assertEquals(
            WorkerCancellationDecision.PRESERVE_CURRENT_STATE,
            workerCancellationDecision(TransferState.PAUSED, "execution", "execution"),
        )
        assertEquals(
            WorkerCancellationDecision.PRESERVE_CURRENT_STATE,
            workerCancellationDecision(TransferState.CANCELLING, "new-execution", "old-execution"),
        )
    }

    @Test
    fun `下载系统停止和旧执行不改状态也不请求删除`() {
        val running = download(TransferState.RUNNING)
        val paused = download(TransferState.PAUSED)
        val replaced = download(TransferState.CANCELLING, workId = "new-execution")

        assertSame(running, running.cancelDownloadExecution("execution"))
        assertSame(paused, paused.cancelDownloadExecution("execution"))
        assertSame(replaced, replaced.cancelDownloadExecution("old-execution"))
        assertEquals(false, shouldDeleteCancelledDownload(running.state, running.workId, "execution"))
        assertEquals(false, shouldDeleteCancelledDownload(paused.state, paused.workId, "execution"))
        assertEquals(false, shouldDeleteCancelledDownload(replaced.state, replaced.workId, "old-execution"))
    }

    @Test
    fun `下载显式取消仅由当前执行落取消态`() {
        val cancelling = download(TransferState.CANCELLING, errorKind = "stale")

        val cancelled = cancelling.cancelDownloadExecution("execution")

        assertEquals(TransferState.CANCELLED, cancelled.state)
        assertEquals(null, cancelled.errorKind)
        assertEquals(true, shouldDeleteCancelledDownload(cancelling.state, cancelling.workId, "execution"))
    }

    @Test
    fun `上传系统停止暂停和旧执行保持原状态`() {
        val running = upload(TransferState.RUNNING)
        val paused = upload(TransferState.PAUSED)
        val replaced = upload(TransferState.CANCELLING, workId = "new-execution")

        assertSame(running, running.cancelUploadExecution("execution"))
        assertSame(paused, paused.cancelUploadExecution("execution"))
        assertSame(replaced, replaced.cancelUploadExecution("old-execution"))
    }

    @Test
    fun `上传显式取消按已提交字节决定是否需要刷新`() {
        val ordinary = upload(TransferState.CANCELLING, completedBytes = 7, backupMode = false)
        val backup = upload(TransferState.CANCELLING, completedBytes = 7, backupMode = true)

        assertEquals(TransferState.CANCELLED, ordinary.cancelUploadExecution("execution").state)
        assertEquals(true, ordinary.cancelUploadExecution("execution").requiresRefresh)
        assertEquals(false, backup.cancelUploadExecution("execution").requiresRefresh)
    }

    @Test
    fun `成功和跳过成功清理陈旧错误与刷新标记`() {
        val completedDownload = download(
            state = TransferState.RUNNING,
            errorKind = "stale",
            completedBytes = 4,
            totalBytes = 9,
        ).completeDownloadExecution("execution")
        val completedUpload = upload(
            state = TransferState.RUNNING,
            errorKind = "stale",
            completedBytes = 4,
            requiresRefresh = true,
        ).completeUploadExecution("execution", skippedExisting = false)
        val skippedUpload = upload(
            state = TransferState.RUNNING,
            errorKind = "stale",
            requiresRefresh = true,
        ).completeUploadExecution("execution", skippedExisting = true)

        assertEquals(TransferState.SUCCEEDED, completedDownload.state)
        assertEquals(9, completedDownload.completedBytes)
        assertEquals(null, completedDownload.errorKind)
        assertEquals(TransferState.SUCCEEDED, completedUpload.state)
        assertEquals(null, completedUpload.errorKind)
        assertEquals(false, completedUpload.requiresRefresh)
        assertEquals(false, completedUpload.skippedExisting)
        assertEquals(TransferState.SUCCEEDED, skippedUpload.state)
        assertEquals(null, skippedUpload.errorKind)
        assertEquals(false, skippedUpload.requiresRefresh)
        assertEquals(true, skippedUpload.skippedExisting)
    }

    @Test
    fun `旧执行不能写入成功状态`() {
        val download = download(TransferState.RUNNING, workId = "new-execution")
        val upload = upload(TransferState.RUNNING, workId = "new-execution")

        assertSame(download, download.completeDownloadExecution("old-execution"))
        assertSame(upload, upload.completeUploadExecution("old-execution", skippedExisting = false))
    }

    @Test
    fun `上传观察器先收到显式取消时保留刷新语义`() {
        val cancelling = upload(
            state = TransferState.CANCELLING,
            completedBytes = 7,
            backupMode = false,
        )

        val cancelled = cancelling.applyUploadWorkObservation(
            executionId = "execution",
            workState = WorkInfo.State.CANCELLED,
        )

        assertEquals(TransferState.CANCELLED, cancelled.state)
        assertEquals(true, cancelled.requiresRefresh)
    }

    @Test
    fun `上传Worker先落取消时观察器保持终态`() {
        val cancelledByWorker = upload(
            state = TransferState.CANCELLING,
            completedBytes = 7,
            backupMode = false,
        ).cancelUploadExecution("execution")

        val observed = cancelledByWorker.applyUploadWorkObservation(
            executionId = "execution",
            workState = WorkInfo.State.CANCELLED,
        )

        assertSame(cancelledByWorker, observed)
        assertEquals(true, observed.requiresRefresh)
    }

    @Test
    fun `上传观察器忽略旧执行和暂停状态`() {
        val replaced = upload(TransferState.RUNNING, workId = "new-execution")
        val paused = upload(TransferState.PAUSED)

        assertSame(
            replaced,
            replaced.applyUploadWorkObservation("old-execution", WorkInfo.State.SUCCEEDED),
        )
        assertSame(
            paused,
            paused.applyUploadWorkObservation("execution", WorkInfo.State.RUNNING, 8),
        )
    }

    @Test
    fun `上传系统停止重新排队不伪装用户取消`() {
        val running = upload(TransferState.RUNNING, completedBytes = 7)
        val cancelling = upload(TransferState.CANCELLING, completedBytes = 7)

        val requeued = running.applyUploadWorkObservation(
            executionId = "execution",
            workState = WorkInfo.State.ENQUEUED,
        )

        assertEquals(TransferState.WAITING, requeued.state)
        assertEquals(7, requeued.completedBytes)
        assertSame(
            running,
            running.applyUploadWorkObservation("execution", WorkInfo.State.CANCELLED),
        )
        assertSame(
            cancelling,
            cancelling.applyUploadWorkObservation("execution", WorkInfo.State.ENQUEUED),
        )
    }

    @Test
    fun `上传观察器不覆盖终态并在成功时清理陈旧状态`() {
        TransferState.entries
            .filter { it in setOf(TransferState.SUCCEEDED, TransferState.FAILED, TransferState.CANCELLED) }
            .forEach { terminal ->
                val current = upload(terminal, errorKind = "existing", requiresRefresh = true)
                assertSame(
                    current,
                    current.applyUploadWorkObservation("execution", WorkInfo.State.RUNNING, 9),
                )
            }
        val succeeded = upload(
            state = TransferState.RUNNING,
            errorKind = "stale",
            requiresRefresh = true,
        ).applyUploadWorkObservation("execution", WorkInfo.State.SUCCEEDED)

        assertEquals(TransferState.SUCCEEDED, succeeded.state)
        assertEquals(10, succeeded.completedBytes)
        assertEquals(null, succeeded.errorKind)
        assertEquals(false, succeeded.requiresRefresh)
    }

    @Test
    fun `初次入队保留旧任务而显式重试替换旧任务`() {
        assertEquals(
            ExistingWorkPolicy.KEEP,
            transferEnqueuePolicy(TransferEnqueueReason.INITIAL),
        )
        assertEquals(
            ExistingWorkPolicy.REPLACE,
            transferEnqueuePolicy(TransferEnqueueReason.USER_RETRY),
        )
    }

    @Test
    fun `排队任务只允许当前Work进入显式取消`() {
        val queuedDownload = download(TransferState.WAITING)
        val queuedUpload = upload(TransferState.WAITING)

        assertEquals(
            TransferState.CANCELLING,
            queuedDownload.requestUserCancellation("execution").state,
        )
        assertEquals(
            TransferState.CANCELLING,
            queuedUpload.requestUserCancellation("execution").state,
        )
        assertSame(queuedDownload, queuedDownload.requestUserCancellation("old-execution"))
        assertSame(queuedUpload, queuedUpload.requestUserCancellation("old-execution"))
    }

    @Test
    fun `上传取消中收到任一Work终态都最终化为用户取消`() {
        WorkInfo.State.entries.filter(WorkInfo.State::isFinished).forEach { finished ->
            val cancelling = upload(
                state = TransferState.CANCELLING,
                completedBytes = 7,
                backupMode = false,
            )

            val result = cancelling.applyUploadWorkObservation("execution", finished)

            assertEquals(finished.name, TransferState.CANCELLED, result.state)
            assertEquals(finished.name, true, result.requiresRefresh)
        }
    }

    @Test
    fun `下载取消中收到任一Work终态都最终化并允许清理`() {
        WorkInfo.State.entries.filter(WorkInfo.State::isFinished).forEach { finished ->
            val cancelling = download(TransferState.CANCELLING)

            val result = cancelling.applyDownloadWorkObservation("execution", finished)

            assertEquals(finished.name, TransferState.CANCELLED, result.state)
            assertEquals(
                finished.name,
                true,
                shouldDeleteCancelledDownload(cancelling.state, cancelling.workId, "execution"),
            )
        }
    }

    @Test
    fun `下载观察器忽略旧Work和系统取消`() {
        val replaced = download(TransferState.CANCELLING, workId = "new-execution")
        val running = download(TransferState.RUNNING)

        assertSame(
            replaced,
            replaced.applyDownloadWorkObservation("old-execution", WorkInfo.State.CANCELLED),
        )
        assertSame(
            running,
            running.applyDownloadWorkObservation("execution", WorkInfo.State.CANCELLED),
        )
    }

    @Test
    fun `前台取消完成回调只最终化取消中状态`() {
        val download = download(TransferState.CANCELLING, workId = "")
            .copy(workId = null)
        val uploadTask = TransferTask(
            id = "upload",
            title = "upload.bin",
            detail = "cancelling",
            direction = TransferDirection.UPLOAD,
            state = TransferState.CANCELLING,
            completedBytes = 7,
        )
        val runningTask = uploadTask.copy(state = TransferState.RUNNING)

        assertEquals(
            TransferState.CANCELLED,
            download.finalizeForegroundDownloadCancellation(ownsExecution = true).state,
        )
        assertSame(
            download,
            download.finalizeForegroundDownloadCancellation(ownsExecution = false),
        )
        val cancelledTask = uploadTask.finalizeForegroundUserCancellation("cancelled", "refresh")
        assertEquals(TransferState.CANCELLED, cancelledTask.state)
        assertEquals(true, cancelledTask.requiresRefresh)
        assertEquals("refresh", cancelledTask.detail)
        assertSame(
            runningTask,
            runningTask.finalizeForegroundUserCancellation("cancelled", "refresh"),
        )
    }

    private fun download(
        state: TransferState,
        workId: String = "execution",
        errorKind: String? = null,
        completedBytes: Long = 3,
        totalBytes: Long? = 10,
    ) = PersistedDownload(
        id = "download",
        profileId = "profile",
        sourcePath = "/synthetic/source",
        title = "source.bin",
        destinationUri = "content://synthetic/destination",
        isDirectory = false,
        state = state,
        completedBytes = completedBytes,
        totalBytes = totalBytes,
        errorKind = errorKind,
        workId = workId,
    )

    private fun upload(
        state: TransferState,
        workId: String = "execution",
        errorKind: String? = null,
        completedBytes: Long = 3,
        requiresRefresh: Boolean = false,
        backupMode: Boolean = false,
    ) = PersistedUpload(
        id = "upload",
        profileId = "profile",
        sourceUri = "content://synthetic/source",
        title = "source.bin",
        expectedBytes = 10,
        destinationPath = "/synthetic/destination",
        state = state,
        completedBytes = completedBytes,
        errorKind = errorKind,
        workId = workId,
        backupMode = backupMode,
        requiresRefresh = requiresRefresh,
    )
}
