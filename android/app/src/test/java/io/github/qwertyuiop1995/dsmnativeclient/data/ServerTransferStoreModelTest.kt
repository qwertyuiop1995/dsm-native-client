package io.github.qwertyuiop1995.dsmnativeclient.data

import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskPage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskState
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileBackgroundTaskSummary
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationExpectedOutput
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationTarget
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileServerMutationVerification
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.TransferState
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerTransferStoreModelTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `旧服务端任务缺少新增字段时使用安全默认值`() {
        val restored = json.decodeFromString<PersistedServerTransfer>(
            """{"id":"server-1","profileId":"profile-a","title":"Archive","operation":"COMPRESS"}""",
        )

        assertEquals(TransferState.WAITING, restored.state)
        assertEquals(PersistedServerSubmissionPhase.PREPARING, restored.submissionPhase)
        assertNull(restored.nasTaskId)
        assertFalse(restored.requiresRefresh)
        assertTrue(restored.sourceBaselines.isEmpty())
        assertTrue(restored.expectedOutputs.isEmpty())
        assertNull(restored.destinationFolderBaseline)
        assertNull(restored.mutationResult)
        assertEquals(0, restored.executionGeneration)
        assertFalse(restored.readOnlyObservation)
        assertFalse(restored.refreshCompleted)
        assertNull(restored.verification)
        assertNull(restored.refreshFailureKind)
    }

    @Test
    fun `服务端任务目标基线和结果可完整往返`() {
        val target = target()
        val persisted = target.toPersistedServerTransfer(
            id = "server-1",
            title = "Archive",
            state = TransferState.RUNNING,
            submissionPhase = PersistedServerSubmissionPhase.SUBMITTED,
            startedAtEpochMillis = 1_000,
        ).copy(
            executionGeneration = 7,
            readOnlyObservation = true,
            nasTaskId = "opaque-task-1",
            completedUnits = 4,
            totalUnits = 10,
            requiresRefresh = true,
            mutationResult = PersistedMutationResult(
                status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                submitted = true,
                requiresRefresh = true,
                counts = MutationResultCounts(0, 0, 1),
            ),
            refreshCompleted = true,
            verification = FileServerMutationVerification.DIFFERS.name,
            refreshFailureKind = "NETWORK",
        )

        val restored = json.decodeFromString<PersistedServerTransfer>(json.encodeToString(persisted))

        assertEquals(persisted, restored)
        assertEquals(target, restored.toFileServerMutationTarget())
        assertEquals(FileServerMutationVerification.DIFFERS, restored.toFileServerMutationVerification())
    }

    @Test
    fun `只有无需核对且已收敛的服务端终态可以清理`() {
        val base = target().toPersistedServerTransfer("server-1", "Archive")

        assertFalse(base.copy(state = TransferState.RUNNING).canRemoveFinishedServer())
        assertFalse(
            base.copy(
                state = TransferState.FAILED,
                submissionPhase = PersistedServerSubmissionPhase.SUBMITTING,
                requiresRefresh = true,
            ).canRemoveFinishedServer(),
        )
        assertFalse(
            base.copy(
                state = TransferState.FAILED,
                submissionPhase = PersistedServerSubmissionPhase.TERMINAL,
                requiresRefresh = false,
                mutationResult = PersistedMutationResult(
                    status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                    submitted = true,
                    requiresRefresh = true,
                    counts = MutationResultCounts(0, 0, 1),
                ),
                refreshCompleted = false,
            ).canRemoveFinishedServer(),
        )
        assertTrue(
            base.copy(
                state = TransferState.FAILED,
                submissionPhase = PersistedServerSubmissionPhase.TERMINAL,
                requiresRefresh = false,
                mutationResult = PersistedMutationResult(
                    status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                    submitted = true,
                    requiresRefresh = true,
                    counts = MutationResultCounts(0, 0, 1),
                ),
                refreshCompleted = true,
                verification = FileServerMutationVerification.DIFFERS.name,
            ).canRemoveFinishedServer(),
        )
        assertFalse(
            base.copy(
                state = TransferState.FAILED,
                submissionPhase = PersistedServerSubmissionPhase.TERMINAL,
                mutationResult = PersistedMutationResult(
                    status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                    submitted = true,
                    requiresRefresh = true,
                    counts = MutationResultCounts(0, 0, 1),
                ),
            ).canRemoveFinishedServer(),
        )
        assertTrue(
            base.copy(
                state = TransferState.SUCCEEDED,
                submissionPhase = PersistedServerSubmissionPhase.TERMINAL,
                mutationResult = PersistedMutationResult(
                    status = MutationResultStatus.CONFIRMED_SUCCESS,
                    submitted = true,
                    counts = MutationResultCounts(1, 0, 0),
                ),
            ).canRemoveFinishedServer(),
        )
    }

    @Test
    fun `BackgroundTask快照只保留脱敏稳定字段`() {
        val page = FileBackgroundTaskPage(
            tasks = listOf(
                FileBackgroundTaskSummary(
                    id = "opaque-task-1",
                    kind = FileBackgroundTaskKind.EXTRACT,
                    state = FileBackgroundTaskState.FINISHED,
                    progress = 0.75,
                    createdAtEpochSeconds = 100,
                    processedItemCount = 3,
                    totalItemCount = 4,
                    processedBytes = 30,
                    totalBytes = 40,
                ),
            ),
            offset = 100,
            nextOffset = 101,
            total = 500,
            hasMore = true,
        )
        val snapshot = page.toPersistedFileBackgroundTaskSnapshot(
            profileId = "profile-a",
            observedAtEpochSeconds = 200,
        )

        val encoded = json.encodeToString(snapshot)
        val restored = json.decodeFromString<PersistedFileBackgroundTaskSnapshot>(encoded)

        assertEquals(snapshot, restored)
        assertEquals(200, restored.observedAtEpochSeconds)
        assertFalse(encoded.contains("path", ignoreCase = true))
        assertFalse(encoded.contains("message", ignoreCase = true))
        assertFalse(encoded.contains("params", ignoreCase = true))
        assertFalse(encoded.contains("processing", ignoreCase = true))
        assertEquals(page.tasks, restored.toFileBackgroundTaskPage().tasks)
        assertFalse(restored.toFileBackgroundTaskPage().hasMore)
    }

    @Test
    fun `未知新字段不影响旧客户端读取服务端任务`() {
        val restored = json.decodeFromString<PersistedServerTransfer>(
            """{
                "id":"server-1",
                "profileId":"profile-a",
                "title":"Archive",
                "operation":"EXTRACT",
                "futureField":{"nested":true}
            }""".trimIndent(),
        )

        assertEquals(PersistedServerOperation.EXTRACT, restored.operation)
        assertEquals(PersistedServerSubmissionPhase.PREPARING, restored.submissionPhase)
    }

    private fun target(): FileServerMutationTarget {
        val source = FileItem(
            path = "/synthetic/source.txt",
            name = "source.txt",
            isDirectory = false,
            size = 12,
            modifiedAtEpochSeconds = 100,
            owner = "synthetic-owner",
            canRead = true,
            canWrite = false,
            canDelete = true,
            mountPointType = "synthetic",
        )
        val destination = FileItem(
            path = "/synthetic",
            name = "synthetic",
            isDirectory = true,
            owner = "synthetic-owner",
            canRead = true,
            canWrite = true,
            mountPointType = "synthetic",
        )
        return FileServerMutationTarget(
            profileId = "profile-a",
            module = Module.FILES,
            operation = FileServerMutationOperation.COMPRESS,
            sourceBaselines = listOf(source),
            destinationFolderBaseline = destination,
            expectedOutputs = listOf(
                FileServerMutationExpectedOutput(
                    path = "/synthetic/archive.zip",
                    isDirectory = false,
                    requiresNonEmptyFile = true,
                ),
            ),
        )
    }
}
