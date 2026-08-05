package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedDownload
import io.github.qwertyuiop1995.dsmnativeclient.data.PersistedUpload
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationLifecycle
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationTarget
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferDirection
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferTask
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SwitchNasStateTest {
    @Test
    fun `后台持久传输和已暂停前台文件下载允许切换`() {
        assertTrue(
            canSafelySwitchNas(
                downloads = listOf(
                    download(state = TransferState.RUNNING, workId = "download-work"),
                    download(state = TransferState.CANCELLING, workId = "cancelling-work"),
                    download(state = TransferState.PAUSED, workId = null),
                ),
                uploads = listOf(upload(state = TransferState.WAITING, workId = "upload-work")),
                transfers = emptyList(),
            ),
        )
    }

    @Test
    fun `未暂停的前台普通文件下载阻止切换`() {
        listOf(
            TransferState.WAITING,
            TransferState.RUNNING,
            TransferState.CANCELLING,
        ).forEach { state ->
            assertFalse(
                canSafelySwitchNas(
                    downloads = listOf(download(state = state, workId = null)),
                    uploads = emptyList(),
                    transfers = emptyList(),
                ),
            )
        }
    }

    @Test
    fun `前台目录下载即使出现暂停状态也阻止切换`() {
        assertFalse(
            canSafelySwitchNas(
                downloads = listOf(
                    download(
                        state = TransferState.PAUSED,
                        workId = null,
                        isDirectory = true,
                    ),
                ),
                uploads = emptyList(),
                transfers = emptyList(),
            ),
        )
    }

    @Test
    fun `持久与非持久前台上传均阻止切换`() {
        assertFalse(
            canSafelySwitchNas(
                downloads = emptyList(),
                uploads = listOf(upload(state = TransferState.RUNNING, workId = null)),
                transfers = emptyList(),
            ),
        )
        assertFalse(
            canSafelySwitchNas(
                downloads = emptyList(),
                uploads = emptyList(),
                transfers = listOf(
                    transfer(direction = TransferDirection.UPLOAD, state = TransferState.WAITING),
                ),
            ),
        )
    }

    @Test
    fun `运行中NAS任务和页面写操作阻止切换但终态任务不阻止`() {
        assertFalse(
            canSafelySwitchNas(
                downloads = emptyList(),
                uploads = emptyList(),
                transfers = listOf(
                    transfer(direction = TransferDirection.SERVER, state = TransferState.RUNNING),
                ),
            ),
        )
        assertFalse(
            canSafelySwitchNas(
                downloads = emptyList(),
                uploads = emptyList(),
                transfers = emptyList(),
                isPerformingAction = true,
            ),
        )
        assertFalse(
            canSafelySwitchNas(
                downloads = emptyList(),
                uploads = emptyList(),
                transfers = emptyList(),
                hasActiveChatMutation = true,
            ),
        )
        assertTrue(
            canSafelySwitchNas(
                downloads = emptyList(),
                uploads = emptyList(),
                transfers = listOf(
                    transfer(direction = TransferDirection.SERVER, state = TransferState.SUCCEEDED),
                ),
            ),
        )
    }

    @Test
    fun `退出门禁保留运行中和待核对NAS文件任务`() {
        assertTrue(
            hasBlockingFileServerTransfer(
                listOf(transfer(TransferDirection.SERVER, TransferState.RUNNING)),
            ),
        )
        assertTrue(
            hasBlockingFileServerTransfer(
                listOf(
                    transfer(
                        TransferDirection.SERVER,
                        TransferState.CANCELLED,
                        requiresRefresh = true,
                        fileServerMutation = pendingFileServerMutation(),
                    ),
                ),
            ),
        )
        assertFalse(
            hasBlockingFileServerTransfer(
                listOf(transfer(TransferDirection.SERVER, TransferState.SUCCEEDED)),
            ),
        )
    }

    private fun download(
        state: TransferState,
        workId: String?,
        isDirectory: Boolean = false,
    ) = PersistedDownload(
        id = "download-${state.name}-$workId-$isDirectory",
        profileId = "profile",
        sourcePath = "/synthetic/source",
        title = "synthetic",
        destinationUri = "content://synthetic/destination",
        isDirectory = isDirectory,
        state = state,
        workId = workId,
    )

    private fun upload(
        state: TransferState,
        workId: String?,
    ) = PersistedUpload(
        id = "upload-${state.name}-$workId",
        profileId = "profile",
        sourceUri = "content://synthetic/source",
        title = "synthetic",
        expectedBytes = 1,
        destinationPath = "/synthetic",
        state = state,
        workId = workId,
    )

    private fun transfer(
        direction: TransferDirection,
        state: TransferState,
        requiresRefresh: Boolean = false,
        fileServerMutation: FileServerMutationLifecycle? = null,
    ) = TransferTask(
        id = "transfer-${direction.name}-${state.name}",
        title = "synthetic",
        detail = "synthetic",
        direction = direction,
        state = state,
        requiresRefresh = requiresRefresh,
        fileServerMutation = fileServerMutation,
    )

    private fun pendingFileServerMutation(): FileServerMutationLifecycle {
        val destination = FileItem(
            path = "/synthetic",
            name = "synthetic",
            isDirectory = true,
            canRead = true,
            canWrite = true,
            canDelete = false,
        )
        return FileServerMutationLifecycle(
            target = FileServerMutationTarget(
                profileId = "profile",
                module = Module.FILES,
                operation = FileServerMutationOperation.COMPRESS,
                sourceBaselines = listOf(
                    FileItem(
                        path = "/synthetic/source.txt",
                        name = "source.txt",
                        isDirectory = false,
                        size = 1,
                        canRead = true,
                        canWrite = true,
                        canDelete = true,
                    ),
                ),
                destinationFolderBaseline = destination,
            ),
            result = cancelledFileServerMutationResult(FileServerMutationOperation.COMPRESS),
        )
    }
}
