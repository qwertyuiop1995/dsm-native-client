package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.DownloadCreationMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.downloads.downloadCreationFeedbackPolicy
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DownloadCreationUiTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 八类结果均保留专用持久反馈策略() {
        val expectedTitles = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to R.string.download_creation_confirmed_title,
            MutationResultStatus.PARTIAL_SUCCESS to R.string.download_creation_partial_title,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to R.string.download_creation_check_title,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to R.string.download_creation_check_title,
            MutationResultStatus.PERMISSION_DENIED to R.string.download_creation_permission_title,
            MutationResultStatus.UNSUPPORTED to R.string.download_creation_unavailable_title,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to R.string.download_creation_cancelled_title,
            MutationResultStatus.CONFIRMED_FAILURE to R.string.download_creation_failed_title,
        )

        expectedTitles.forEach { (status, title) ->
            assertEquals(title, downloadCreationFeedbackPolicy(result(status)).title)
        }
    }

    @Test
    fun 未确认结果必须刷新且不能直接修改重提() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var refreshCount = 0
        var editCount = 0
        show(
            DownloadCreationWorkspaceState(
                target = target(DownloadCreationSourceKind.MAGNET),
                mutationResult = result(
                    MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                    submitted = true,
                    requiresRefresh = true,
                    counts = MutationResultCounts(0, 0, 1),
                ),
            ),
            mustRefresh = true,
            onRefresh = { refreshCount++ },
            onEdit = { editCount++ },
        )

        rule.onNodeWithText(context.getString(R.string.download_creation_feedback_counts, 0, 0, 1))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_download_creation))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.onNodeWithText(context.getString(R.string.close_checked_download_creation))
            .assertIsNotEnabled()
        rule.onNodeWithText(context.getString(R.string.edit_download_creation_and_retry))
            .assertDoesNotExist()
        rule.onNode(
            androidx.compose.ui.test.SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Assertive,
            ),
        ).assertIsDisplayed()
        assertEquals(1, refreshCount)
        assertEquals(0, editCount)
    }

    @Test
    fun 未提交权限结果核对后可修改且操作达到48dp() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var editCount = 0
        show(
            DownloadCreationWorkspaceState(
                target = target(DownloadCreationSourceKind.LINK),
                mutationResult = result(
                    MutationResultStatus.PERMISSION_DENIED,
                    submitted = false,
                ),
            ),
            mustRefresh = false,
            onEdit = { editCount++ },
        )

        rule.onNodeWithText(context.getString(R.string.edit_download_creation_and_retry))
            .assertIsEnabled()
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        assertEquals(1, editCount)
    }

    @Test
    fun 深色两倍字体下异常与恢复操作仍可滚动显示() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalDensity provides Density(density.density, fontScale = 2f),
            ) {
                LanStashTheme(darkTheme = true) {
                    DownloadCreationMutationFeedbackCard(
                        state = DownloadCreationWorkspaceState(
                            target = target(DownloadCreationSourceKind.TASK_FILE),
                            mutationFailure = DsmFailure(
                                code = null,
                                message = "Synthetic creation failure",
                                recovery = "Review the task list before trying again.",
                            ),
                            mutationRefreshCompleted = true,
                        ),
                        mustRefresh = true,
                        onRefresh = {},
                        onDismiss = {},
                        onEdit = {},
                    )
                }
            }
        }

        rule.onNodeWithText(context.getString(R.string.download_creation_failed_title))
            .performScrollTo()
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.edit_download_creation_and_retry))
            .assertDoesNotExist()
        rule.onNodeWithText(context.getString(R.string.close_checked_download_creation))
            .performScrollTo()
            .assertHeightIsAtLeast(48.dp)
    }

    private fun show(
        state: DownloadCreationWorkspaceState,
        mustRefresh: Boolean,
        onRefresh: () -> Unit = {},
        onEdit: () -> Unit = {},
    ) {
        rule.setContent {
            MaterialTheme {
                DownloadCreationMutationFeedbackCard(
                    state = state,
                    mustRefresh = mustRefresh,
                    onRefresh = onRefresh,
                    onDismiss = {},
                    onEdit = onEdit,
                )
            }
        }
    }

    private fun target(source: DownloadCreationSourceKind) = DownloadCreationTarget(
        profileId = "synthetic-profile",
        sourceKind = source,
        requestFingerprint = "a".repeat(64),
        destination = "downloads",
    )

    private fun result(
        status: MutationResultStatus,
        submitted: Boolean = status !in setOf(
            MutationResultStatus.PERMISSION_DENIED,
            MutationResultStatus.UNSUPPORTED,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
            MutationResultStatus.CONFIRMED_FAILURE,
        ),
        requiresRefresh: Boolean = status in setOf(
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        ),
        counts: MutationResultCounts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 1, 0)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            else -> MutationResultCounts(0, 0, 0)
        },
    ) = MutationResult(
        schemaVersion = 1,
        status = status,
        operation = "downloadCreate",
        submitted = submitted,
        requiresRefresh = requiresRefresh,
        counts = counts,
        errorCategory = if (status == MutationResultStatus.CONFIRMED_FAILURE) {
            MutationErrorCategory.UNKNOWN
        } else null,
        diagnosticTag = "synthetic.download.creation",
    )
}
