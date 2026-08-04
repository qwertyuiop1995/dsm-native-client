package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmErrorKind
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.FileServiceMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.nas.FileServiceMutationFailureCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class FileServiceFeedbackCardTest {
    @get:Rule
    val rule = createComposeRule()

    @Test
    fun 部分成功刷新前只提供刷新核对() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var refreshes = 0
        setFeedback(
            result = result(MutationResultStatus.PARTIAL_SUCCESS, MutationResultCounts(2, 1, 3)),
            canEdit = false,
            onRefresh = { refreshes += 1 },
        )

        rule.onNodeWithText(context.getString(R.string.file_service_feedback_counts, 2, 1, 3))
            .assertIsDisplayed()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertExists()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_settings)).performClick()
        rule.onAllNodesWithText(context.getString(R.string.continue_editing)).assertCountEquals(0)
        rule.runOnIdle { check(refreshes == 1) }
    }

    @Test
    fun 提交后停止要求刷新且不会误报修改已取消() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        setFeedback(
            result = result(
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
                MutationResultCounts(0, 0, 2),
            ),
        )

        rule.onNodeWithText(context.getString(R.string.file_service_cancel_after_submission))
            .assertIsDisplayed()
        rule.onAllNodesWithText(context.getString(R.string.file_service_feedback_cancelled_title))
            .assertCountEquals(0)
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_settings)).assertIsDisplayed()
    }

    @Test
    fun 核对成功只提供完成操作并使用礼貌通知() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var dismissed = 0
        setFeedback(
            result = result(MutationResultStatus.CONFIRMED_SUCCESS, MutationResultCounts(4, 0, 0)),
            canEdit = false,
            onDismiss = { dismissed += 1 },
        )

        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Polite),
        ).assertExists()
        rule.onAllNodesWithText(context.getString(R.string.continue_editing)).assertCountEquals(0)
        rule.onNodeWithText(context.getString(R.string.done)).performClick()
        rule.runOnIdle { check(dismissed == 1) }
    }

    @Test
    fun 提交前取消无需刷新且可以继续编辑草稿() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        setFeedback(
            result = MutationResult(
                schemaVersion = 1,
                status = MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
                operation = "fileServiceSettingsUpdate",
                submitted = false,
                requiresRefresh = false,
                counts = MutationResultCounts(0, 0, 0),
            ),
        )

        rule.onNodeWithText(context.getString(R.string.file_service_feedback_cancelled_title))
            .assertIsDisplayed()
        rule.onAllNodesWithText(context.getString(R.string.refresh_and_check_settings))
            .assertCountEquals(0)
        rule.onNodeWithText(context.getString(R.string.continue_editing)).assertIsDisplayed()
    }

    @Test
    fun 未确认结果刷新完成前不开放继续编辑() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        setFeedback(
            result = result(
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultCounts(0, 0, 2),
            ),
            canEdit = false,
        )

        rule.onNodeWithText(context.getString(R.string.file_service_feedback_unverified_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.refresh_and_check_settings)).assertIsDisplayed()
        rule.onAllNodesWithText(context.getString(R.string.continue_editing)).assertCountEquals(0)
    }

    @Test
    fun 异常失败卡在深色两倍字体下保留草稿恢复操作() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var edits = 0
        rule.setContent {
            LanStashTheme(darkTheme = true) {
                CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                    LazyColumn {
                        item {
                            FileServiceMutationFailureCard(
                                failure = DsmFailure(
                                    null,
                                    "Synthetic failure",
                                    "Synthetic recovery",
                                    kind = DsmErrorKind.CONNECTION_FAILED,
                                ),
                                canContinueEditing = true,
                                onContinueEditing = { edits += 1 },
                                onDismiss = {},
                            )
                        }
                    }
                }
            }
        }

        rule.onNodeWithText(context.getString(R.string.file_service_feedback_failed_title))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_editing))
            .performScrollTo()
            .performClick()
        rule.runOnIdle { check(edits == 1) }
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertExists()
    }

    @Test
    fun 深色模式两倍字体仍可查看结果并操作恢复按钮() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        var edits = 0
        rule.setContent {
            LanStashTheme(darkTheme = true) {
                CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                    LazyColumn {
                        item {
                            FileServiceMutationFeedbackCard(
                                result = result(
                                    MutationResultStatus.PARTIAL_SUCCESS,
                                    MutationResultCounts(2, 1, 3),
                                ),
                                refreshCompleted = true,
                                canContinueEditing = true,
                                onRefresh = {},
                                onContinueEditing = { edits += 1 },
                                onDismiss = {},
                            )
                        }
                    }
                }
            }
        }

        rule.onNodeWithText(context.getString(R.string.file_service_feedback_partial_title))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.continue_editing))
            .performScrollTo()
            .performClick()
        rule.runOnIdle { check(edits == 1) }
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertExists()
    }

    private fun setFeedback(
        result: MutationResult,
        canEdit: Boolean = true,
        onRefresh: () -> Unit = {},
        onEdit: () -> Unit = {},
        onDismiss: () -> Unit = {},
    ) {
        rule.setContent {
            LanStashTheme {
                LazyColumn {
                    item {
                        FileServiceMutationFeedbackCard(
                            result = result,
                            refreshCompleted = false,
                            canContinueEditing = canEdit,
                            onRefresh = onRefresh,
                            onContinueEditing = onEdit,
                            onDismiss = onDismiss,
                        )
                    }
                }
            }
        }
    }

    private fun result(status: MutationResultStatus, counts: MutationResultCounts): MutationResult =
        MutationResult(
            schemaVersion = 1,
            status = status,
            operation = "fileServiceSettingsUpdate",
            submitted = true,
            requiresRefresh = status != MutationResultStatus.CONFIRMED_SUCCESS,
            counts = counts,
        )
}
