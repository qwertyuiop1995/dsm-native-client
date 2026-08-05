package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.FilePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileShareLink
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FileStationMutationStatePolicyTest {
    private val folder = FileItem(
        path = "/volume1/shared/folder",
        name = "folder",
        isDirectory = true,
        modifiedAtEpochSeconds = 123,
        canRead = true,
        canWrite = true,
        canDelete = true,
    )
    private val file = FileItem(
        path = "/volume1/shared/file.txt",
        name = "file.txt",
        isDirectory = false,
        size = 42,
        modifiedAtEpochSeconds = 456,
        canRead = true,
        canWrite = true,
        canDelete = true,
    )
    private val destination = folder.copy(path = "/volume1/shared/destination", name = "destination")
    private val otherFile = file.copy(
        path = "/volume1/shared/other.txt",
        name = "other.txt",
        size = 84,
    )
    private val link = FileShareLink(
        id = "link-1",
        name = "file.txt",
        path = file.path,
        url = "https://example.invalid/synthetic",
    )

    @Test
    fun `十一类操作目标保留稳定标识和用户所见基线`() {
        val targets = listOf(
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.TEXT_SAVE,
                sourceBaselines = listOf(file),
                expectedContentSha256 = sha256Hex("updated".encodeToByteArray()),
                expectedContentByteCount = 7,
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.CREATE_FOLDER,
                parentPath = folder.path,
                parentBaseline = folder,
                requestedName = "new-folder",
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.RENAME,
                sourceBaselines = listOf(file),
                requestedName = "renamed.txt",
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.FAVORITE_ADD,
                sourceBaselines = listOf(folder),
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.FAVORITE_REMOVE,
                sourceBaselines = listOf(folder.copy(isFavorite = true)),
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.COPY,
                sourceBaselines = listOf(file),
                destinationPath = destination.path,
                destinationBaseline = destination,
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.MOVE,
                sourceBaselines = listOf(file),
                destinationPath = destination.path,
                destinationBaseline = destination,
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.DELETE,
                sourceBaselines = listOf(file, otherFile),
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.RESTORE,
                sourceBaselines = listOf(file),
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.SHARE_CREATE,
                sourceBaselines = listOf(file),
            ),
            FileStationMutationTarget(
                "profile-a",
                Module.FILES,
                FileStationMutationOperation.SHARE_DELETE,
                shareLinkBaselines = listOf(link),
            ),
        )
        assertEquals(FileStationMutationOperation.entries.filterNot {
            it == FileStationMutationOperation.FAVORITE_ADD_BATCH
        }.toSet(), targets.map { it.operation }.toSet())
        assertEquals(file, targets.first { it.operation == FileStationMutationOperation.RENAME }
            .sourceBaselines.single())
        assertEquals(
            listOf(file, otherFile),
            targets.first { it.operation == FileStationMutationOperation.DELETE }.sourceBaselines,
        )
        assertEquals(link, targets.last().shareLinkBaselines.single())
    }

    @Test
    fun `文本保存目标仅保留摘要字节数和文件基线`() {
        val plaintext = "只留摘要，不留明文"
        val bytes = plaintext.encodeToByteArray()
        val target = FileStationMutationTarget(
            profileId = "profile-a",
            module = Module.FILES,
            operation = FileStationMutationOperation.TEXT_SAVE,
            sourceBaselines = listOf(file),
            expectedContentSha256 = sha256Hex(bytes),
            expectedContentByteCount = bytes.size.toLong(),
        )

        assertEquals(file, target.sourceBaselines.single())
        assertEquals(bytes.size.toLong(), target.expectedContentByteCount)
        assertEquals(64, target.expectedContentSha256?.length)
        assertFalse(target.toString().contains(plaintext))
    }

    @Test
    fun `文本保存失败可继续编辑而未知结果在核对前阻止退出`() {
        val target = textSaveTarget()
        assertTrue(canContinueEditingFileStationMutation(
            FileStationMutationWorkspaceState(
                draftTarget = target,
                target = target,
                mutationResult = result(MutationResultStatus.CONFIRMED_FAILURE),
            ),
        ))
        assertTrue(fileStationMutationBlocksWorkspaceExit(
            FileStationMutationWorkspaceState(target = target, mutationResult = unverified()),
        ))
        assertFalse(fileStationMutationBlocksWorkspaceExit(
            FileStationMutationWorkspaceState(
                target = target,
                mutationResult = unverified(),
                mutationRefreshCompleted = true,
            ),
        ))
    }

    @Test
    fun `文本保存迟到回调被旧代次旧NAS和不同摘要目标拒绝`() {
        val target = textSaveTarget()
        assertTrue(fileStationMutationCallbackMatches(true, true, target, target, 12, 12, 12))
        assertFalse(fileStationMutationCallbackMatches(true, true, target, target, 11, 12, 12))
        assertFalse(fileStationMutationCallbackMatches(false, true, target, target, 12, 12, 12))
        assertFalse(fileStationMutationCallbackMatches(true, false, target, target, 12, 12, 12))
        assertFalse(fileStationMutationCallbackMatches(
            true,
            true,
            target.copy(expectedContentSha256 = "0".repeat(64)),
            target,
            12,
            12,
            12,
        ))
    }

    @Test
    fun `目标身份包含完整基线并在配置重建后存活`() {
        val target = FileStationMutationTarget(
            "profile-a",
            Module.PHOTOS,
            FileStationMutationOperation.MOVE,
            sourceBaselines = listOf(file),
            destinationPath = destination.path,
            destinationBaseline = destination,
        )
        val state = FileStationMutationWorkspaceState(
            draftTarget = target,
            target = target,
            confirmationRequested = true,
            mutationGeneration = 9,
        )
        assertEquals(state, state.copy())
        assertNotEquals(target, target.copy(sourceBaselines = listOf(file.copy(size = 43))))
        val editor = FileStationMutationWorkspaceState(
            editorVisible = true,
            nameDraft = "renamed.txt",
            editorSourceBaseline = file,
        )
        assertEquals(editor, editor.copy())
        val picker = FileCopyMoveState(
            items = listOf(file),
            operation = FileCopyMoveOperation.COPY,
            location = FileCopyMoveLocation(destination.path, canWrite = true),
            destinationBaselines = mapOf(destination.path to destination),
        )
        assertEquals(destination, picker.copy().destinationBaselines[destination.path])
        val photoDestination = PhotoMoveLocation(
            path = destination.path,
            canWrite = true,
            baseline = destination,
        )
        assertEquals(destination, photoDestination.copy().baseline)
        assertTrue(canContinueEditingFileStationMutation(
            state.copy(
                confirmationRequested = false,
                mutationResult = result(MutationResultStatus.CONFIRMED_FAILURE),
            ),
        ))
        val deletion = FileStationMutationTarget(
            "profile-a",
            Module.FILES,
            FileStationMutationOperation.DELETE,
            sourceBaselines = listOf(file, otherFile),
        )
        assertEquals(
            deletion,
            FileStationMutationWorkspaceState(
                draftTarget = deletion,
                confirmationRequested = true,
            ).copy().draftTarget,
        )
    }

    @Test
    fun `普通加载和导航在草稿确认及未收敛结果期间被阻止`() {
        assertFalse(fileStationMutationBlocksOrdinaryLoad(FileStationMutationWorkspaceState()))
        assertTrue(fileStationMutationBlocksOrdinaryLoad(
            FileStationMutationWorkspaceState(editorVisible = true),
        ))
        assertTrue(fileStationMutationBlocksOrdinaryLoad(
            FileStationMutationWorkspaceState(confirmationRequested = true),
        ))
        assertTrue(fileStationMutationBlocksOrdinaryLoad(
            FileStationMutationWorkspaceState(target = renameTarget(), mutationResult = unverified()),
        ))
    }

    @Test
    fun `切NAS退出和跨模块导航共用危险证据门禁`() {
        assertTrue(fileStationMutationBlocksWorkspaceExit(
            FileStationMutationWorkspaceState(mutationInProgress = true),
        ))
        assertTrue(fileStationMutationBlocksWorkspaceExit(
            FileStationMutationWorkspaceState(target = renameTarget(), mutationResult = unverified()),
        ))
        assertTrue(fileStationMutationBlocksWorkspaceExit(
            FileStationMutationWorkspaceState(
                target = renameTarget(),
                mutationFailure = DsmFailure(
                    null,
                    "Synthetic failure",
                    "Retry.",
                    kind = DsmErrorKind.UNKNOWN,
                ),
            ),
        ))
        assertFalse(fileStationMutationBlocksWorkspaceExit(
            FileStationMutationWorkspaceState(
                target = renameTarget(),
                mutationResult = result(MutationResultStatus.CONFIRMED_FAILURE),
            ),
        ))
        assertFalse(fileStationMutationBlocksWorkspaceExit(
            FileStationMutationWorkspaceState(
                target = renameTarget(),
                mutationResult = unverified(),
                mutationRefreshCompleted = true,
            ),
        ))
    }

    @Test
    fun `八态结果均可持久记录且仅提交前结果允许继续编辑`() {
        MutationResultStatus.entries.forEach { status ->
            val state = FileStationMutationWorkspaceState(
                draftTarget = renameTarget(),
                target = renameTarget(),
                mutationResult = result(status),
            )
            assertEquals(status, state.copy().mutationResult?.status)
            val editable = status in setOf(
                MutationResultStatus.CONFIRMED_FAILURE,
                MutationResultStatus.PERMISSION_DENIED,
                MutationResultStatus.UNSUPPORTED,
                MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            )
            assertEquals(status.name, editable, canContinueEditingFileStationMutation(state))
        }
        listOf(
            FileStationMutationOperation.FAVORITE_ADD,
            FileStationMutationOperation.FAVORITE_REMOVE,
            FileStationMutationOperation.FAVORITE_ADD_BATCH,
            FileStationMutationOperation.RESTORE,
            FileStationMutationOperation.SHARE_CREATE,
            FileStationMutationOperation.SHARE_DELETE,
        ).forEach { operation ->
            val target = when (operation) {
                FileStationMutationOperation.SHARE_DELETE -> FileStationMutationTarget(
                    "profile-a",
                    Module.FILES,
                    operation,
                    shareLinkBaselines = listOf(link),
                )
                else -> FileStationMutationTarget(
                    "profile-a",
                    Module.FILES,
                    operation,
                    sourceBaselines = listOf(if (operation.name.startsWith("FAVORITE")) folder else file),
                )
            }
            assertFalse(
                operation.name,
                canContinueEditingFileStationMutation(
                    FileStationMutationWorkspaceState(
                        draftTarget = target,
                        target = target,
                        mutationResult = result(MutationResultStatus.CONFIRMED_FAILURE),
                    ),
                ),
            )
        }
        val deletion = FileStationMutationTarget(
            "profile-a",
            Module.FILES,
            FileStationMutationOperation.DELETE,
            sourceBaselines = listOf(file, otherFile),
        )
        MutationResultStatus.entries.forEach { status ->
            assertEquals(
                status.name,
                false,
                canContinueEditingFileStationMutation(
                    FileStationMutationWorkspaceState(
                        draftTarget = deletion,
                        target = deletion,
                        mutationResult = result(status),
                    ),
                ),
            )
        }
        assertTrue(shouldClearFileSelectionAfterDelete(
            result(MutationResultStatus.CONFIRMED_SUCCESS),
        ))
        assertFalse(shouldClearFileSelectionAfterDelete(
            result(MutationResultStatus.PARTIAL_SUCCESS),
        ))
        assertFalse(shouldClearFileSelectionAfterDelete(unverified()))
        assertTrue(shouldClearFileSelectionAfterDelete(unverified(), userDiscarded = true))
        assertTrue(shouldDiscardSettledFileStationMutationOnModuleChange(
            FileStationMutationWorkspaceState(
                draftTarget = deletion,
                target = deletion,
                mutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS),
                mutationRefreshCompleted = true,
            ),
            Module.PHOTOS,
        ))
        assertFalse(shouldDiscardSettledFileStationMutationOnModuleChange(
            FileStationMutationWorkspaceState(
                draftTarget = deletion,
                target = deletion,
                mutationResult = unverified(),
            ),
            Module.PHOTOS,
        ))
        assertFalse(shouldDiscardSettledFileStationMutationOnModuleChange(
            FileStationMutationWorkspaceState(
                draftTarget = deletion,
                target = deletion,
                mutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS),
            ),
            Module.FILES,
        ))
    }

    @Test
    fun `取消产生未提交结果且迟到回调被target和代次门禁拒绝`() {
        val target = renameTarget()
        val cancelled = cancelledFileStationMutationResult(target.operation)
        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, cancelled.status)
        assertFalse(cancelled.submitted)
        assertTrue(fileStationMutationCallbackMatches(true, true, target, target, 7, 7, 7))
        assertFalse(fileStationMutationCallbackMatches(true, true, target, target, 8, 7, 8))
        assertFalse(fileStationMutationCallbackMatches(
            true,
            true,
            target.copy(requestedName = "other.txt"),
            target,
            7,
            7,
            7,
        ))
        assertFalse(fileStationMutationCallbackMatches(false, true, target, target, 7, 7, 7))
        assertFalse(fileStationMutationCallbackMatches(true, false, target, target, 7, 7, 7))
    }

    @Test
    fun `批量收藏聚合保留成功失败和未知计数`() {
        val aggregate = aggregateFileStationMutationResults(
            FileStationMutationOperation.FAVORITE_ADD_BATCH,
            3,
            listOf(
                result(MutationResultStatus.CONFIRMED_SUCCESS),
                result(MutationResultStatus.PERMISSION_DENIED),
                null,
            ),
        )
        assertEquals(MutationResultStatus.PARTIAL_SUCCESS, aggregate.status)
        assertEquals(MutationResultCounts(1, 1, 1), aggregate.counts)
        assertTrue(aggregate.submitted)

        val unknownOnly = aggregateFileStationMutationResults(
            FileStationMutationOperation.FAVORITE_ADD_BATCH,
            2,
            listOf(result(MutationResultStatus.PERMISSION_DENIED), null),
        )
        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, unknownOnly.status)
        assertEquals(MutationResultCounts(0, 1, 1), unknownOnly.counts)
        assertTrue(unknownOnly.submitted)
        assertTrue(unknownOnly.requiresRefresh)

        val cancelledAndUnknown = aggregateFileStationMutationResults(
            FileStationMutationOperation.FAVORITE_ADD_BATCH,
            2,
            listOf(result(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION), null),
        )
        assertEquals(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED, cancelledAndUnknown.status)
        assertEquals(1, cancelledAndUnknown.counts.unknown)
        assertTrue(cancelledAndUnknown.requiresRefresh)
    }

    @Test
    fun `专项核对区分匹配差异消失和不可用`() {
        val rename = renameTarget()
        val renamed = file.copy(
            path = "/volume1/shared/renamed.txt",
            name = "renamed.txt",
        )
        assertEquals(
            FileStationMutationVerification.MATCHES,
            fileStationMutationVerification(rename, files = page(renamed)),
        )
        assertEquals(
            FileStationMutationVerification.DIFFERS,
            fileStationMutationVerification(rename, files = page(file)),
        )
        assertEquals(
            FileStationMutationVerification.DISAPPEARED,
            fileStationMutationVerification(rename, files = page()),
        )
        assertEquals(
            FileStationMutationVerification.UNAVAILABLE,
            fileStationMutationVerification(rename),
        )
        assertNotEquals(
            FileStationMutationVerification.MATCHES,
            fileStationMutationVerification(
                rename,
                files = page(renamed.copy(isDirectory = true)),
            ),
        )
        assertNotEquals(
            FileStationMutationVerification.MATCHES,
            fileStationMutationVerification(
                rename,
                files = page(renamed.copy(size = file.size + 1)),
            ),
        )
        assertNotEquals(
            FileStationMutationVerification.MATCHES,
            fileStationMutationVerification(
                rename,
                files = page(
                    renamed.copy(
                        modifiedAtEpochSeconds = checkNotNull(file.modifiedAtEpochSeconds) + 1,
                    ),
                ),
            ),
        )
        val favorite = FileStationMutationTarget(
            "profile-a",
            Module.FILES,
            FileStationMutationOperation.FAVORITE_ADD,
            sourceBaselines = listOf(folder),
        )
        assertEquals(
            FileStationMutationVerification.MATCHES,
            fileStationMutationVerification(favorite, favoritePaths = setOf(folder.path)),
        )
        val deletion = FileStationMutationTarget(
            "profile-a",
            Module.FILES,
            FileStationMutationOperation.SHARE_DELETE,
            shareLinkBaselines = listOf(link),
        )
        assertEquals(
            FileStationMutationVerification.DISAPPEARED,
            fileStationMutationVerification(deletion, shareLinks = emptyList()),
        )
        val photoDeletion = FileStationMutationTarget(
            "profile-a",
            Module.PHOTOS,
            FileStationMutationOperation.DELETE,
            sourceBaselines = listOf(file),
        )
        assertEquals(
            FileStationMutationVerification.DIFFERS,
            fileStationMutationVerification(photoDeletion, files = page(file)),
        )
        assertEquals(
            FileStationMutationVerification.DISAPPEARED,
            fileStationMutationVerification(photoDeletion, files = page()),
        )
        val fileDeletion = photoDeletion.copy(
            module = Module.FILES,
            sourceBaselines = listOf(file, otherFile),
        )
        assertEquals(
            FileStationMutationVerification.DIFFERS,
            fileStationMutationVerification(fileDeletion, files = page(otherFile)),
        )
        assertEquals(
            FileStationMutationVerification.DISAPPEARED,
            fileStationMutationVerification(fileDeletion, files = page()),
        )
        val shareCreation = FileStationMutationTarget(
            "profile-a",
            Module.FILES,
            FileStationMutationOperation.SHARE_CREATE,
            sourceBaselines = listOf(file),
        )
        assertEquals(
            FileStationMutationVerification.UNAVAILABLE,
            fileStationMutationVerification(shareCreation, shareLinks = listOf(link)),
        )
        assertEquals(
            FileStationMutationVerification.MATCHES,
            fileStationMutationVerification(
                shareCreation.copy(shareLinkBaselines = listOf(link)),
                shareLinks = listOf(link),
            ),
        )

        val cancelledDeletion = cancelledFileStationMutationResult(
            FileStationMutationOperation.DELETE,
        )
        assertEquals("fileDelete", cancelledDeletion.operation)
        assertFalse(cancelledDeletion.submitted)
    }

    @Test
    fun `生产专项核对复用属性和共享链接归属规则`() = runTest {
        val renamedPath = "/volume1/shared/renamed.txt"
        val renamed = file.copy(path = renamedPath, name = "renamed.txt")
        assertEquals(
            FileStationMutationVerification.DIFFERS,
            verifyFileStationMutationOutcome(renameTarget(), { path ->
                when (path) {
                    renamedPath -> renamed.copy(
                        modifiedAtEpochSeconds = checkNotNull(file.modifiedAtEpochSeconds) + 1,
                    )
                    file.path -> file
                    else -> null
                }
            }),
        )
        assertEquals(
            FileStationMutationVerification.MATCHES,
            verifyFileStationMutationOutcome(renameTarget(), { path ->
                renamed.takeIf { path == renamedPath }
            }),
        )

        val shareCreation = FileStationMutationTarget(
            "profile-a",
            Module.FILES,
            FileStationMutationOperation.SHARE_CREATE,
            sourceBaselines = listOf(file),
        )
        assertEquals(
            FileStationMutationVerification.UNAVAILABLE,
            verifyFileStationMutationOutcome(
                shareCreation,
                fileInfo = { null },
                shareLinks = listOf(link),
            ),
        )
        assertEquals(
            FileStationMutationVerification.MATCHES,
            verifyFileStationMutationOutcome(
                shareCreation,
                fileInfo = { null },
                shareLinks = listOf(link),
                createdShareLink = link,
            ),
        )
        val photoDeletion = FileStationMutationTarget(
            "profile-a",
            Module.PHOTOS,
            FileStationMutationOperation.DELETE,
            sourceBaselines = listOf(file),
        )
        assertEquals(
            FileStationMutationVerification.DIFFERS,
            verifyFileStationMutationOutcome(photoDeletion, fileInfo = { file }),
        )
        assertEquals(
            FileStationMutationVerification.DISAPPEARED,
            verifyFileStationMutationOutcome(photoDeletion, fileInfo = { null }),
        )
        val fileDeletion = photoDeletion.copy(
            module = Module.FILES,
            sourceBaselines = listOf(file, otherFile),
        )
        assertEquals(
            FileStationMutationVerification.DIFFERS,
            verifyFileStationMutationOutcome(fileDeletion, fileInfo = { path ->
                otherFile.takeIf { path == otherFile.path }
            }),
        )
        assertEquals(
            FileStationMutationVerification.DISAPPEARED,
            verifyFileStationMutationOutcome(fileDeletion, fileInfo = { null }),
        )
        val photoMove = FileStationMutationTarget(
            "profile-a",
            Module.PHOTOS,
            FileStationMutationOperation.MOVE,
            sourceBaselines = listOf(file),
            destinationPath = destination.path,
            destinationBaseline = destination,
        )
        val moved = file.copy(
            path = "${destination.path}/${file.name}",
            name = file.name,
        )
        assertEquals(
            FileStationMutationVerification.MATCHES,
            verifyFileStationMutationOutcome(photoMove, fileInfo = { path ->
                moved.takeIf { path == moved.path }
            }),
        )
        assertEquals(
            FileStationMutationVerification.DISAPPEARED,
            verifyFileStationMutationOutcome(photoMove, fileInfo = { null }),
        )
    }

    private fun renameTarget() = FileStationMutationTarget(
        "profile-a",
        Module.FILES,
        FileStationMutationOperation.RENAME,
        sourceBaselines = listOf(file),
        requestedName = "renamed.txt",
    )

    private fun textSaveTarget() = FileStationMutationTarget(
        "profile-a",
        Module.FILES,
        FileStationMutationOperation.TEXT_SAVE,
        sourceBaselines = listOf(file),
        expectedContentSha256 = sha256Hex("updated".encodeToByteArray()),
        expectedContentByteCount = 7,
    )

    private fun unverified() = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED)

    private fun page(vararg items: FileItem) = FilePage(items.toList(), items.size, 0)

    private fun result(status: MutationResultStatus): MutationResult {
        val submitted = status !in setOf(
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CONFIRMED_FAILURE,
        )
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            else -> MutationResultCounts(0, 1, 0)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "fileRename",
            submitted = submitted,
            requiresRefresh = status in setOf(
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ),
            counts = counts,
            errorCategory = if (status == MutationResultStatus.PERMISSION_DENIED) {
                MutationErrorCategory.PERMISSION
            } else null,
        )
    }
}
