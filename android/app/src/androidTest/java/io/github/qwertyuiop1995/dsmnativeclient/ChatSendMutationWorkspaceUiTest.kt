package io.github.qwertyuiop1995.dsmnativeclient

import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.ui.ChatSendMutationFeedback
import io.github.qwertyuiop1995.dsmnativeclient.ui.theme.LanStashTheme
import org.junit.Rule
import org.junit.Test

class ChatSendMutationWorkspaceUiTest {
    @get:Rule val rule = createComposeRule()

    @Test
    fun 文字和附件反馈按请求并发显示不互相覆盖() {
        val context = context()
        rule.setContent {
            LanStashTheme {
                Column {
                    sendFeedback(entry(ChatMutationOperation.TEXT_SEND, "text", unverifiedResult("chatTextSend")))
                    sendFeedback(
                        entry(
                            ChatMutationOperation.ATTACHMENT_SEND,
                            "attachment",
                            cancelledResult("chatAttachmentSend"),
                        ),
                    )
                }
            }
        }
        rule.onNodeWithText(context.getString(R.string.chat_text_send_unverified))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.chat_attachment_send_cancelled))
            .assertIsDisplayed()
    }

    @Test
    fun 两倍字体下发送失败仍提供48dp继续编辑和明确关闭() {
        val context = context()
        var edits = 0
        var dismissals = 0
        rule.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, 2f)) {
                LanStashTheme(darkTheme = true) {
                    ChatSendMutationFeedback(
                        entry = entry(
                            ChatMutationOperation.TEXT_SEND,
                            "text-failed",
                            failedResult("chatTextSend"),
                        ),
                        onRefresh = { true },
                        onContinueEditing = { edits += 1; true },
                        onDismiss = { dismissals += 1; true },
                        onCancel = { true },
                    )
                }
            }
        }
        rule.onNodeWithText(context.getString(R.string.message_send_failed))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.chat_mutation_continue_editing))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.onNodeWithText(context.getString(R.string.close))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { check(edits == 1 && dismissals == 1) }
    }

    @Test
    fun 发送中反馈可通过48dp操作请求取消() {
        val context = context()
        var cancellations = 0
        val target = target(ChatMutationOperation.ATTACHMENT_SEND, "uploading")
        rule.setContent {
            LanStashTheme {
                ChatSendMutationFeedback(
                    entry = ChatMutationEntry(
                        target = target,
                        mutationInProgress = true,
                        generation = 1,
                    ),
                    onRefresh = { true },
                    onContinueEditing = { true },
                    onDismiss = { true },
                    onCancel = { cancellations += 1; true },
                )
            }
        }
        rule.onNodeWithText(context.getString(R.string.chat_mutation_in_progress_message))
            .assertIsDisplayed()
        rule.onNodeWithText(context.getString(R.string.cancel))
            .assertHeightIsAtLeast(48.dp)
            .performClick()
        rule.runOnIdle { check(cancellations == 1) }
    }

    @Test
    fun 未确认发送只保留刷新和关闭不允许继续编辑() {
        val context = context()
        rule.setContent {
            LanStashTheme {
                ChatSendMutationFeedback(
                    entry = entry(
                        ChatMutationOperation.TEXT_SEND,
                        "text-unverified",
                        unverifiedResult("chatTextSend"),
                    ),
                    onRefresh = { true },
                    onContinueEditing = { error("未知结果不得继续编辑") },
                    onDismiss = { true },
                    onCancel = { true },
                )
            }
        }
        rule.onAllNodesWithText(context.getString(R.string.chat_mutation_continue_editing))
            .assertCountEquals(0)
        rule.onNodeWithText(context.getString(R.string.refresh))
            .assertHeightIsAtLeast(48.dp)
        rule.onNodeWithText(context.getString(R.string.close))
            .assertIsNotEnabled()
    }

    @androidx.compose.runtime.Composable
    private fun sendFeedback(entry: ChatMutationEntry) {
        ChatSendMutationFeedback(
            entry = entry,
            onRefresh = { true },
            onContinueEditing = { true },
            onDismiss = { true },
            onCancel = { true },
        )
    }

    private fun entry(
        operation: ChatMutationOperation,
        requestId: String,
        result: MutationResult,
    ) = ChatMutationEntry(
        target = target(operation, requestId),
        mutationResult = result,
        generation = 1,
    )

    private fun target(operation: ChatMutationOperation, requestId: String) = ChatMutationTarget(
        profileId = "profile-synthetic",
        operation = operation,
        requestId = requestId,
        conversationId = "conversation-synthetic",
        requestFingerprint = "1".repeat(64),
    )

    private fun unverifiedResult(operation: String) = MutationResult(
        schemaVersion = 1,
        status = MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
        operation = operation,
        submitted = true,
        requiresRefresh = true,
        counts = MutationResultCounts(0, 0, 1),
    )

    private fun cancelledResult(operation: String) = MutationResult(
        schemaVersion = 1,
        status = MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
        operation = operation,
        submitted = false,
        requiresRefresh = false,
        counts = MutationResultCounts(0, 0, 0),
    )

    private fun failedResult(operation: String) = MutationResult(
        schemaVersion = 1,
        status = MutationResultStatus.CONFIRMED_FAILURE,
        operation = operation,
        submitted = true,
        requiresRefresh = false,
        counts = MutationResultCounts(0, 1, 0),
    )

    private fun context() = InstrumentationRegistry.getInstrumentation().targetContext
}
