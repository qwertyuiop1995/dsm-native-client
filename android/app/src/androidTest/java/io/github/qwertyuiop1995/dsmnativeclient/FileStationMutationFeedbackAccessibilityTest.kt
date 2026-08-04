package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.foundation.layout.Column
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.FileItem
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileStationMutationFeedbackDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.FileStationMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.fileStationMutationFeedbackPolicy
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class FileStationMutationFeedbackAccessibilityTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 八种结果状态都有明确反馈策略() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to R.string.file_mutation_feedback_confirmed_title,
            MutationResultStatus.PARTIAL_SUCCESS to R.string.file_mutation_feedback_partial_title,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to R.string.file_mutation_feedback_check_title,
            MutationResultStatus.PERMISSION_DENIED to R.string.file_mutation_feedback_permission_title,
            MutationResultStatus.UNSUPPORTED to R.string.file_mutation_feedback_unavailable_title,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to R.string.file_mutation_feedback_cancelled_title,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to
                R.string.file_mutation_feedback_check_title,
            MutationResultStatus.CONFIRMED_FAILURE to R.string.file_mutation_feedback_failed_title,
        )
        MutationResultStatus.entries.forEach { status ->
            check(fileStationMutationFeedbackPolicy(result(status)).title == expected.getValue(status))
        }
        check(
            fileStationMutationFeedbackPolicy(
                result(MutationResultStatus.CONFIRMED_FAILURE, MutationErrorCategory.CONFLICT),
            ).title == R.string.file_mutation_feedback_conflict_title,
        )
    }

    @Test
    fun 未确认结果显示计数强提醒且刷新完成前禁止关闭() {
        val context = context()
        var refreshes = 0
        setFeedback(
            state = state(
                result = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
                verification = FileStationMutationVerification.UNAVAILABLE,
            ),
            onRefresh = { refreshes += 1; true },
        )

        rule.onNodeWithText(context.getString(R.string.file_mutation_counts, 0, 0, 1))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.file_mutation_refresh_unavailable))
            .assertIsDisplayed()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.close_checked_file_mutation))
            .assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_files))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { check(refreshes == 1) }
    }

    @Test
    fun 四种复查结论均使用本地化反馈() {
        val context = context()
        val expected = mapOf(
            FileStationMutationVerification.MATCHES to R.string.file_mutation_refresh_matches,
            FileStationMutationVerification.DIFFERS to R.string.file_mutation_refresh_differs,
            FileStationMutationVerification.DISAPPEARED to R.string.file_mutation_refresh_disappeared,
            FileStationMutationVerification.UNAVAILABLE to R.string.file_mutation_refresh_unavailable,
        )
        rule.setContent {
            LanStashTheme {
                Column {
                    expected.keys.forEach { verification ->
                        FileStationMutationFeedbackCard(
                            state(
                                result = result(MutationResultStatus.CONFIRMED_SUCCESS),
                                verification = verification,
                                refreshCompleted = true,
                            ),
                        )
                    }
                }
            }
        }
        expected.forEach { (_, message) ->
            rule.onNodeWithText(context.getString(message)).assertIsDisplayed()
        }
    }

    @Test
    fun 深色两倍字体下失败仍保留48dp继续编辑操作() {
        val context = context()
        var edits = 0
        setFeedback(
            state = FileStationMutationWorkspaceState(
                draftTarget = renameTarget(),
                target = renameTarget(),
                mutationFailure = DsmFailure(
                    null,
                    "Synthetic failure",
                    "Synthetic recovery",
                    kind = DsmErrorKind.CONNECTION_FAILED,
                ),
            ),
            dark2x = true,
            onContinue = { edits += 1; true },
        )
        rule.onNodeWithText(context.getString(R.string.continue_editing_file_mutation))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { check(edits == 1) }
    }

    @Test
    fun 生命周期失败不误给继续编辑() {
        val context = context()
        setFeedback(
            state = state(
                result = result(MutationResultStatus.CONFIRMED_FAILURE),
                target = restoreTarget(),
            ),
            dark2x = true,
        )
        rule.onAllNodesWithText(context.getString(R.string.continue_editing_file_mutation))
            .assertCountEquals(0)
    }

    private fun setFeedback(
        state: FileStationMutationWorkspaceState,
        dark2x: Boolean = false,
        onRefresh: () -> Boolean = { true },
        onContinue: () -> Boolean = { true },
    ) {
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, if (dark2x) 2f else 1f)) {
                LanStashTheme(darkTheme = dark2x) {
                    FileStationMutationFeedbackDialog(
                        state = state,
                        onRefresh = onRefresh,
                        onContinueEditing = onContinue,
                        onDismiss = { true },
                    )
                }
            }
        }
    }

    private fun state(
        result: MutationResult,
        target: FileStationMutationTarget = renameTarget(),
        verification: FileStationMutationVerification? = null,
        refreshCompleted: Boolean = false,
    ) = FileStationMutationWorkspaceState(
        draftTarget = target,
        target = target,
        mutationResult = result,
        mutationRefreshCompleted = refreshCompleted,
        mutationVerification = verification,
    )

    private fun result(
        status: MutationResultStatus,
        category: MutationErrorCategory? = null,
    ): MutationResult {
        val submitted = status != MutationResultStatus.CANCELLED_BEFORE_SUBMISSION
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            else -> MutationResultCounts(0, 0, 1)
        }
        return MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "fileRename",
            submitted = submitted,
            requiresRefresh = status in setOf(
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ),
            counts = counts,
            errorCategory = category,
        )
    }

    private fun file() = FileItem("/synthetic/source.txt", "source.txt", false, canWrite = true)

    private fun renameTarget() = FileStationMutationTarget(
        "profile-synthetic",
        Module.FILES,
        FileStationMutationOperation.RENAME,
        sourceBaselines = listOf(file()),
        requestedName = "renamed.txt",
    )

    private fun restoreTarget() = FileStationMutationTarget(
        "profile-synthetic",
        Module.FILES,
        FileStationMutationOperation.RESTORE,
        sourceBaselines = listOf(file()),
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
