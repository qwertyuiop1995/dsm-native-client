package io.github.qwertyuiop1995.dsmnativeclient.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import io.github.qwertyuiop1995.dsmnativeclient.ChatMutationEntry
import io.github.qwertyuiop1995.dsmnativeclient.ChatMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.ChatMutationTarget
import io.github.qwertyuiop1995.dsmnativeclient.ChatMutationVerification
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.chatAttachmentSendMessageResource
import io.github.qwertyuiop1995.dsmnativeclient.chatConversationMutationMessageResource
import io.github.qwertyuiop1995.dsmnativeclient.chatMutationRequiresRefresh
import io.github.qwertyuiop1995.dsmnativeclient.chatMutationCanContinueEditing
import io.github.qwertyuiop1995.dsmnativeclient.chatPollMutationMessageResource
import io.github.qwertyuiop1995.dsmnativeclient.chatReminderMutationMessageResource
import io.github.qwertyuiop1995.dsmnativeclient.chatScheduleMutationMessageResource
import io.github.qwertyuiop1995.dsmnativeclient.chatTextSendMessageResource
import io.github.qwertyuiop1995.dsmnativeclient.canDismissChatMutation
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize

internal data class ChatMutationFeedbackPolicy(
    @StringRes val title: Int,
    val assertive: Boolean,
)

internal fun chatMutationFeedbackPolicy(result: MutationResult): ChatMutationFeedbackPolicy =
    when (result.status) {
        MutationResultStatus.CONFIRMED_SUCCESS -> ChatMutationFeedbackPolicy(
            R.string.chat_mutation_feedback_success_title,
            false,
        )
        MutationResultStatus.PARTIAL_SUCCESS -> ChatMutationFeedbackPolicy(
            R.string.chat_mutation_feedback_partial_title,
            true,
        )
        MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
        MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        -> ChatMutationFeedbackPolicy(R.string.chat_mutation_feedback_check_title, true)
        MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> ChatMutationFeedbackPolicy(
            R.string.chat_mutation_feedback_cancelled_title,
            true,
        )
        MutationResultStatus.PERMISSION_DENIED,
        MutationResultStatus.UNSUPPORTED,
        MutationResultStatus.CONFIRMED_FAILURE,
        -> ChatMutationFeedbackPolicy(R.string.chat_mutation_feedback_failed_title, true)
    }

internal fun canDismissChatMutationFeedback(entry: ChatMutationEntry): Boolean =
    canDismissChatMutation(entry)

internal fun canContinueEditingChatMutationFeedback(entry: ChatMutationEntry): Boolean =
    entry.target.operation in setOf(
        ChatMutationOperation.DIRECT_CONVERSATION_CREATE,
        ChatMutationOperation.PRIVATE_GROUP_CREATE,
        ChatMutationOperation.SCHEDULE_CREATE,
        ChatMutationOperation.POLL_CREATE,
        ChatMutationOperation.TEXT_SEND,
        ChatMutationOperation.ATTACHMENT_SEND,
    ) && chatMutationCanContinueEditing(entry) &&
        entry.mutationResult?.status != MutationResultStatus.CONFIRMED_SUCCESS

internal fun canRetryChatMutation(entry: ChatMutationEntry?): Boolean = entry?.retryEnabled == true

@Composable
internal fun ChatMutationConfirmationDialog(
    target: ChatMutationTarget,
    onConfirm: () -> Boolean,
    onDismiss: () -> Boolean,
) {
    val title = when (target.operation) {
        ChatMutationOperation.REMINDER_DELETE -> R.string.remove_chat_reminder_title
        ChatMutationOperation.SCHEDULE_DELETE -> R.string.cancel_scheduled_message_title
        else -> return
    }
    val message = when (target.operation) {
        ChatMutationOperation.REMINDER_DELETE -> R.string.remove_chat_reminder_message
        ChatMutationOperation.SCHEDULE_DELETE -> R.string.cancel_scheduled_message_message
        else -> return
    }
    val confirm = when (target.operation) {
        ChatMutationOperation.REMINDER_DELETE -> R.string.confirm_remove_chat_reminder
        ChatMutationOperation.SCHEDULE_DELETE -> R.string.confirm_cancel_scheduled_message
        else -> return
    }
    val keep = when (target.operation) {
        ChatMutationOperation.REMINDER_DELETE -> R.string.keep_chat_reminder
        ChatMutationOperation.SCHEDULE_DELETE -> R.string.keep_scheduled_message
        else -> return
    }
    AlertDialog(
        onDismissRequest = { onDismiss() },
        title = { Text(stringResource(title)) },
        text = {
            Text(
                stringResource(message),
                modifier = Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()),
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm() },
                colors = ButtonDefaults.textButtonColors(
                    contentColor = MaterialTheme.colorScheme.error,
                ),
                modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
            ) { Text(stringResource(confirm)) }
        },
        dismissButton = {
            TextButton(
                onClick = { onDismiss() },
                modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
            ) { Text(stringResource(keep)) }
        },
    )
}

@Composable
internal fun ChatMutationFeedbackDialog(
    entry: ChatMutationEntry,
    onRefresh: () -> Boolean,
    onContinueEditing: () -> Boolean,
    onDismiss: () -> Boolean,
) {
    val canDismiss = canDismissChatMutationFeedback(entry)
    AlertDialog(
        onDismissRequest = { if (canDismiss) onDismiss() },
        title = { Text(stringResource(chatMutationTitle(entry))) },
        text = { ChatMutationFeedbackCard(entry) },
        dismissButton = {
            Column {
                if (canContinueEditingChatMutationFeedback(entry)) {
                    TextButton(
                        onClick = { onContinueEditing() },
                        modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
                    ) { Text(stringResource(R.string.chat_mutation_continue_editing)) }
                }
                if (chatMutationRequiresRefresh(entry) && !canDismiss) {
                    TextButton(
                        onClick = { onRefresh() },
                        enabled = !entry.mutationInProgress && !entry.mutationRefreshInProgress,
                        modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
                    ) { Text(stringResource(R.string.chat_mutation_refresh_and_check)) }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onDismiss() },
                enabled = canDismiss,
                modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
            ) {
                Text(
                    stringResource(
                        if (chatMutationRequiresRefresh(entry)) {
                            R.string.chat_mutation_close_checked
                        } else {
                            R.string.close
                        },
                    ),
                )
            }
        },
    )
}

@Composable
internal fun ChatSendMutationFeedback(
    entry: ChatMutationEntry,
    onRefresh: () -> Boolean,
    onContinueEditing: () -> Boolean,
    onDismiss: () -> Boolean,
    onCancel: () -> Boolean,
    canClose: Boolean = canDismissChatMutationFeedback(entry),
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        ChatMutationFeedbackCard(entry)
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (entry.mutationInProgress) {
                TextButton(
                    onClick = { onCancel() },
                    modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
                ) { Text(stringResource(R.string.cancel)) }
            } else {
                if (canContinueEditingChatMutationFeedback(entry)) {
                    TextButton(
                        onClick = { onContinueEditing() },
                        modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
                    ) { Text(stringResource(R.string.chat_mutation_continue_editing)) }
                }
                if (chatMutationRequiresRefresh(entry) && !entry.mutationRefreshCompleted) {
                    TextButton(
                        onClick = { onRefresh() },
                        enabled = !entry.mutationRefreshInProgress,
                        modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
                    ) { Text(stringResource(R.string.refresh)) }
                }
                TextButton(
                    onClick = { onDismiss() },
                    enabled = canClose,
                    modifier = Modifier.heightIn(min = 48.dp).semantics { role = Role.Button },
                ) { Text(stringResource(R.string.close)) }
            }
        }
    }
}

@Composable
internal fun ChatMutationFeedbackCard(entry: ChatMutationEntry) {
    val policy = entry.mutationResult?.let(::chatMutationFeedbackPolicy)
    val verificationNeedsAttention = entry.mutationVerification != null &&
        entry.mutationVerification != ChatMutationVerification.MATCHES
    val liveRegion = if (
        entry.mutationFailure != null || entry.mutationRefreshFailure != null ||
        policy?.assertive == true || verificationNeedsAttention
    ) LiveRegionMode.Assertive else LiveRegionMode.Polite
    Card(Modifier.fillMaxWidth().semantics { this.liveRegion = liveRegion }) {
        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(max = 360.dp)
                .verticalScroll(rememberScrollState())
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            chatMutationFeedbackMessage(entry)?.let { message ->
                Text(message)
                if (entry.mutationInProgress) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                }
            }
            entry.mutationResult?.counts?.let { counts ->
                Text(
                    stringResource(
                        R.string.chat_mutation_counts,
                        counts.succeeded,
                        counts.failed,
                        counts.unknown,
                    ),
                )
            }
            if (entry.mutationRefreshInProgress) {
                Text(stringResource(R.string.chat_mutation_refreshing))
                LinearProgressIndicator(Modifier.fillMaxWidth())
            }
            entry.mutationRefreshFailure?.let { failure ->
                Text(failure.localize(LocalContext.current).combined)
            }
            entry.mutationVerification?.let { verification ->
                Text(stringResource(verification.messageResource()))
            }
        }
    }
}

@Composable
internal fun chatMutationFeedbackMessage(entry: ChatMutationEntry): String? = when {
    entry.mutationInProgress -> stringResource(R.string.chat_mutation_in_progress_message)
    entry.mutationFailure != null -> entry.mutationFailure.localize(LocalContext.current).combined
    entry.mutationResult != null -> stringResource(
        chatMutationMessageResource(entry.target.operation, entry.mutationResult),
    )
    else -> null
}

@StringRes
private fun chatMutationTitle(entry: ChatMutationEntry): Int = when {
    entry.mutationInProgress -> R.string.chat_mutation_in_progress_title
    entry.mutationFailure != null -> R.string.chat_mutation_feedback_failed_title
    else -> chatMutationFeedbackPolicy(checkNotNull(entry.mutationResult)).title
}

@StringRes
private fun chatMutationMessageResource(
    operation: ChatMutationOperation,
    result: MutationResult,
): Int = when (operation) {
    ChatMutationOperation.DIRECT_CONVERSATION_CREATE,
    ChatMutationOperation.PRIVATE_GROUP_CREATE,
    -> chatConversationMutationMessageResource(result)
    ChatMutationOperation.REMINDER_SET,
    ChatMutationOperation.REMINDER_DELETE,
    -> chatReminderMutationMessageResource(result)
    ChatMutationOperation.SCHEDULE_CREATE,
    ChatMutationOperation.SCHEDULE_DELETE,
    -> chatScheduleMutationMessageResource(result)
    ChatMutationOperation.POLL_CREATE -> chatPollMutationMessageResource(result)
    ChatMutationOperation.TEXT_SEND -> chatTextSendMessageResource(result)
    ChatMutationOperation.ATTACHMENT_SEND -> chatAttachmentSendMessageResource(result)
}

@StringRes
private fun ChatMutationVerification.messageResource(): Int = when (this) {
    ChatMutationVerification.MATCHES -> R.string.chat_mutation_refresh_matches
    ChatMutationVerification.DIFFERS -> R.string.chat_mutation_refresh_differs
    ChatMutationVerification.DISAPPEARED -> R.string.chat_mutation_refresh_disappeared
    ChatMutationVerification.UNAVAILABLE -> R.string.chat_mutation_refresh_unavailable
}
