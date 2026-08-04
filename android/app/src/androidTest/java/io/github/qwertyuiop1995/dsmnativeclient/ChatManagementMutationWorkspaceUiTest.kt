package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.ui.ChatMutationConfirmationDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.ChatMutationFeedbackCard
import io.github.qwertyuiop1995.dsmnativeclient.ui.ChatMutationFeedbackDialog
import io.github.qwertyuiop1995.dsmnativeclient.ui.chatMutationFeedbackPolicy
import io.github.qwertyuiop1995.dsmnativeclient.ui.canContinueEditingChatMutationFeedback
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class ChatManagementMutationWorkspaceUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 八种结果状态都有明确反馈策略() {
        val expected = mapOf(
            MutationResultStatus.CONFIRMED_SUCCESS to R.string.chat_mutation_feedback_success_title,
            MutationResultStatus.PARTIAL_SUCCESS to R.string.chat_mutation_feedback_partial_title,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED to R.string.chat_mutation_feedback_check_title,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION to
                R.string.chat_mutation_feedback_check_title,
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION to
                R.string.chat_mutation_feedback_cancelled_title,
            MutationResultStatus.PERMISSION_DENIED to R.string.chat_mutation_feedback_failed_title,
            MutationResultStatus.UNSUPPORTED to R.string.chat_mutation_feedback_failed_title,
            MutationResultStatus.CONFIRMED_FAILURE to R.string.chat_mutation_feedback_failed_title,
        )
        MutationResultStatus.entries.forEach { status ->
            check(chatMutationFeedbackPolicy(result(status)).title == expected.getValue(status))
        }
    }

    @Test
    fun 删除提醒先显示影响说明和48dp危险操作() {
        val context = context()
        var confirmations = 0
        rule.setContent {
            LanStashTheme {
                ChatMutationConfirmationDialog(
                    target = target(ChatMutationOperation.REMINDER_DELETE),
                    onConfirm = { confirmations += 1; true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.remove_chat_reminder_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.confirm_remove_chat_reminder))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { check(confirmations == 1) }
    }

    @Test
    fun 定时消息删除继续显示原有确认语义() {
        val context = context()
        rule.setContent {
            LanStashTheme {
                ChatMutationConfirmationDialog(
                    target = target(ChatMutationOperation.SCHEDULE_DELETE),
                    onConfirm = { true },
                    onDismiss = { true },
                )
            }
        }
        rule.onNodeWithText(context.getString(R.string.cancel_scheduled_message_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.confirm_cancel_scheduled_message))
            .assertHeightIsAtLeast(48.dp)
    }

    @Test
    fun 未确认结果显示计数强提醒且刷新前禁止关闭() {
        val context = context()
        var refreshes = 0
        val entry = entry(
            operation = ChatMutationOperation.PRIVATE_GROUP_CREATE,
            result = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
            verification = ChatMutationVerification.UNAVAILABLE,
        )
        rule.setContent {
            LanStashTheme {
                ChatMutationFeedbackDialog(
                    entry = entry,
                    onRefresh = { refreshes += 1; true },
                    onContinueEditing = { true },
                    onDismiss = { true },
                )
            }
        }

        rule.onNodeWithText(context.getString(R.string.chat_mutation_counts, 0, 0, 1))
            .assertIsDisplayed()
        rule.onNode(
            SemanticsMatcher.expectValue(SemanticsProperties.LiveRegion, LiveRegionMode.Assertive),
        ).assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.chat_mutation_close_checked))
            .assertIsNotEnabled()
        rule.onAllNodesWithText(context.getString(R.string.chat_mutation_continue_editing))
            .assertCountEquals(0)
        check(!canContinueEditingChatMutationFeedback(entry))
        rule.onNodeWithText(context.getString(R.string.chat_mutation_refresh_and_check))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { check(refreshes == 1) }
    }

    @Test
    fun 深色两倍字体下四种核对结论仍可滚动显示() {
        val context = context()
        val expected = mapOf(
            ChatMutationVerification.MATCHES to R.string.chat_mutation_refresh_matches,
            ChatMutationVerification.DIFFERS to R.string.chat_mutation_refresh_differs,
            ChatMutationVerification.DISAPPEARED to R.string.chat_mutation_refresh_disappeared,
            ChatMutationVerification.UNAVAILABLE to R.string.chat_mutation_refresh_unavailable,
        )
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                LanStashTheme(darkTheme = true) {
                    Column(Modifier.verticalScroll(rememberScrollState())) {
                        expected.keys.forEach { verification ->
                            ChatMutationFeedbackCard(
                                entry(
                                    operation = ChatMutationOperation.SCHEDULE_CREATE,
                                    result = result(MutationResultStatus.CONFIRMED_SUCCESS),
                                    verification = verification,
                                    refreshCompleted = true,
                                ),
                            )
                        }
                    }
                }
            }
        }
        expected.values.forEach { resource ->
            rule.onNodeWithText(context.getString(resource)).performScrollTo().assertIsDisplayed()
        }
    }

    private fun entry(
        operation: ChatMutationOperation,
        result: MutationResult,
        verification: ChatMutationVerification? = null,
        refreshCompleted: Boolean = false,
    ) = ChatMutationEntry(
        target = target(operation),
        mutationResult = result,
        mutationVerification = verification,
        mutationRefreshCompleted = refreshCompleted,
        generation = 1,
    )

    private fun target(operation: ChatMutationOperation) = ChatMutationTarget(
        profileId = "profile-synthetic",
        operation = operation,
        requestId = "request-${operation.name}",
        conversationId = "conversation-synthetic",
        resourceIds = if (
            operation == ChatMutationOperation.REMINDER_DELETE ||
            operation == ChatMutationOperation.SCHEDULE_DELETE
        ) listOf("resource-synthetic") else emptyList(),
        requestFingerprint = "0".repeat(64),
    )

    private fun result(status: MutationResultStatus): MutationResult {
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
            operation = "chatGroupCreate",
            submitted = submitted,
            requiresRefresh = status in setOf(
                MutationResultStatus.PARTIAL_SUCCESS,
                MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
                MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            ),
            counts = counts,
        )
    }

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
