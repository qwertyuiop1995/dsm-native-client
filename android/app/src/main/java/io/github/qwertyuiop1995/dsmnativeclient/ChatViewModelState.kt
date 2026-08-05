package io.github.qwertyuiop1995.dsmnativeclient

import android.net.Uri
import io.github.qwertyuiop1995.dsmnativeclient.domain.*
import java.security.MessageDigest

enum class ChatMutationOperation {
    DIRECT_CONVERSATION_CREATE,
    PRIVATE_GROUP_CREATE,
    REMINDER_SET,
    REMINDER_DELETE,
    SCHEDULE_CREATE,
    SCHEDULE_DELETE,
    POLL_CREATE,
    TEXT_SEND,
    ATTACHMENT_SEND,
    ;

    val isOutgoingMessage: Boolean
        get() = this == TEXT_SEND || this == ATTACHMENT_SEND
}

enum class ChatMutationVerification {
    MATCHES,
    DIFFERS,
    DISAPPEARED,
    UNAVAILABLE,
}

/** Chat 写目标只保留稳定标识与内容指纹；正文、群名和投票选项不复制到目标。 */
data class ChatMutationTarget(
    val profileId: String,
    val operation: ChatMutationOperation,
    val requestId: String,
    val conversationId: String? = null,
    val resourceIds: List<String> = emptyList(),
    val expectedEpochMillis: Long? = null,
    val requestFingerprint: String,
    val reminderBaseline: ChatReminder? = null,
    val scheduleBaseline: ChatScheduledMessage? = null,
) {
    init {
        require(profileId.isNotBlank() && requestId.isNotBlank()) { "chat_mutation.invalid_identity" }
        require(resourceIds.none(String::isBlank) && resourceIds.distinct().size == resourceIds.size) {
            "chat_mutation.invalid_resources"
        }
        require(requestFingerprint.length == 64 && requestFingerprint.all { it in "0123456789abcdef" }) {
            "chat_mutation.invalid_fingerprint"
        }
    }
}

data class ChatMutationEntry(
    val target: ChatMutationTarget,
    val confirmationRequested: Boolean = false,
    val mutationInProgress: Boolean = false,
    val mutationResult: MutationResult? = null,
    val mutationFailure: DsmFailure? = null,
    val mutationRefreshFailure: DsmFailure? = null,
    val mutationRefreshInProgress: Boolean = false,
    val mutationRefreshCompleted: Boolean = false,
    val mutationVerification: ChatMutationVerification? = null,
    val generation: Long = 0L,
) {
    val retryEnabled: Boolean
        get() = target.operation.isOutgoingMessage && !confirmationRequested &&
            !mutationInProgress && !mutationRefreshInProgress &&
            (mutationFailure != null || mutationResult?.status != MutationResultStatus.CONFIRMED_SUCCESS)
}

data class ChatMutationWorkspaceState(
    val entries: Map<String, ChatMutationEntry> = emptyMap(),
) {
    fun entry(requestId: String?): ChatMutationEntry? = requestId?.let(entries::get)

    val latestManagementEntry: ChatMutationEntry?
        get() = entries.values.filterNot { it.target.operation.isOutgoingMessage }
            .maxByOrNull(ChatMutationEntry::generation)
}


internal fun chatPayloadFingerprint(parts: List<String>): String {
    val digest = MessageDigest.getInstance("SHA-256")
    parts.forEach { value ->
        val bytes = value.toByteArray(Charsets.UTF_8)
        digest.update(
            byteArrayOf(
                (bytes.size ushr 24).toByte(),
                (bytes.size ushr 16).toByte(),
                (bytes.size ushr 8).toByte(),
                bytes.size.toByte(),
            ),
        )
        digest.update(bytes)
    }
    return digest.digest().joinToString("") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }
}

internal fun chatMutationTarget(
    profileId: String,
    operation: ChatMutationOperation,
    requestId: String,
    conversationId: String? = null,
    resourceIds: List<String> = emptyList(),
    expectedEpochMillis: Long? = null,
    requestParts: List<String> = emptyList(),
    reminderBaseline: ChatReminder? = null,
    scheduleBaseline: ChatScheduledMessage? = null,
): ChatMutationTarget = ChatMutationTarget(
    profileId = profileId,
    operation = operation,
    requestId = requestId,
    conversationId = conversationId,
    resourceIds = resourceIds,
    expectedEpochMillis = expectedEpochMillis,
    requestFingerprint = chatPayloadFingerprint(requestParts),
    reminderBaseline = reminderBaseline,
    scheduleBaseline = scheduleBaseline,
)

internal fun chatMutationCallbackMatches(
    repositoryMatches: Boolean,
    profileMatches: Boolean,
    stateEntry: ChatMutationEntry?,
    callbackTarget: ChatMutationTarget,
    callbackGeneration: Long,
    registeredGeneration: Long?,
): Boolean = repositoryMatches && profileMatches && stateEntry?.target == callbackTarget &&
    stateEntry.generation == callbackGeneration && registeredGeneration == callbackGeneration

internal fun chatMutationRequiresRefresh(entry: ChatMutationEntry): Boolean =
    entry.mutationFailure != null && entry.mutationResult?.submitted != false ||
        entry.mutationResult?.let { result ->
        result.requiresRefresh || result.counts.unknown > 0 || result.status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
    } == true

internal fun chatMutationFailedBeforeSubmissionResult(
    target: ChatMutationTarget,
): MutationResult = MutationResult(
    schemaVersion = 1,
    status = MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
    operation = target.operation.resultOperation,
    submitted = false,
    requiresRefresh = false,
    counts = MutationResultCounts(0, 0, 0),
    errorCategory = MutationErrorCategory.VALIDATION,
    diagnosticTag = "chat.attachment.preflight-failed",
)

internal fun chatMutationBlocksWorkspaceExit(state: ChatMutationWorkspaceState): Boolean =
    state.entries.values.any { entry ->
        entry.confirmationRequested || entry.mutationInProgress || entry.mutationRefreshInProgress ||
            chatMutationRequiresRefresh(entry) && !entry.mutationRefreshCompleted
    }

internal fun canDismissChatMutation(entry: ChatMutationEntry): Boolean =
    !entry.confirmationRequested && !entry.mutationInProgress && !entry.mutationRefreshInProgress &&
        (!chatMutationRequiresRefresh(entry) || entry.mutationRefreshCompleted)

internal fun cancelledChatMutationResult(target: ChatMutationTarget): MutationResult = MutationResult(
    schemaVersion = 1,
    status = MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
    operation = target.operation.resultOperation,
    submitted = true,
    requiresRefresh = true,
    counts = MutationResultCounts(0, 0, 1),
    errorCategory = MutationErrorCategory.UNKNOWN,
    diagnosticTag = "chat.mutation.cancelled-after-start",
)

private val ChatMutationOperation.resultOperation: String
    get() = when (this) {
        ChatMutationOperation.DIRECT_CONVERSATION_CREATE -> "chatDirectConversationCreate"
        ChatMutationOperation.PRIVATE_GROUP_CREATE -> "chatGroupCreate"
        ChatMutationOperation.REMINDER_SET -> "chatReminderSet"
        ChatMutationOperation.REMINDER_DELETE -> "chatReminderDelete"
        ChatMutationOperation.SCHEDULE_CREATE -> "chatScheduleCreate"
        ChatMutationOperation.SCHEDULE_DELETE -> "chatScheduleDelete"
        ChatMutationOperation.POLL_CREATE -> "chatPollCreate"
        ChatMutationOperation.TEXT_SEND -> "chatTextSend"
        ChatMutationOperation.ATTACHMENT_SEND -> "chatAttachmentSend"
    }

internal fun chatMutationVerification(
    target: ChatMutationTarget,
    conversations: List<ChatConversation>? = null,
    reminders: List<ChatReminder>? = null,
    schedules: List<ChatScheduledMessage>? = null,
    messages: List<ChatMessage>? = null,
): ChatMutationVerification = when (target.operation) {
    ChatMutationOperation.DIRECT_CONVERSATION_CREATE,
    ChatMutationOperation.PRIVATE_GROUP_CREATE,
    -> conversations?.let { values ->
        val expectedKind = if (target.operation == ChatMutationOperation.DIRECT_CONVERSATION_CREATE) {
            ConversationKind.DIRECT
        } else {
            ConversationKind.GROUP
        }
        if (values.any { conversation ->
                conversation.kind == expectedKind &&
                    conversation.memberIds.containsAll(target.resourceIds)
            }
        ) ChatMutationVerification.MATCHES else ChatMutationVerification.DIFFERS
    } ?: ChatMutationVerification.UNAVAILABLE
    ChatMutationOperation.REMINDER_SET -> reminders?.let { values ->
        val messageId = target.resourceIds.singleOrNull()
            ?: return ChatMutationVerification.UNAVAILABLE
        if (values.any { it.messageId == messageId && it.remindAtEpochMillis == target.expectedEpochMillis }) {
            ChatMutationVerification.MATCHES
        } else ChatMutationVerification.DIFFERS
    } ?: ChatMutationVerification.UNAVAILABLE
    ChatMutationOperation.REMINDER_DELETE -> reminders?.let { values ->
        val messageId = target.resourceIds.singleOrNull()
            ?: return ChatMutationVerification.UNAVAILABLE
        if (values.none { it.messageId == messageId }) ChatMutationVerification.DISAPPEARED
        else ChatMutationVerification.DIFFERS
    } ?: ChatMutationVerification.UNAVAILABLE
    ChatMutationOperation.SCHEDULE_CREATE -> schedules?.let { values ->
        if (values.any { scheduled ->
                scheduled.sendAtEpochMillis == target.expectedEpochMillis &&
                    chatPayloadFingerprint(listOf(scheduled.text)) == target.requestFingerprint
            }
        ) ChatMutationVerification.MATCHES else ChatMutationVerification.DIFFERS
    } ?: ChatMutationVerification.UNAVAILABLE
    ChatMutationOperation.SCHEDULE_DELETE -> schedules?.let { values ->
        val id = target.resourceIds.singleOrNull() ?: return ChatMutationVerification.UNAVAILABLE
        if (values.none { it.id == id }) ChatMutationVerification.DISAPPEARED
        else ChatMutationVerification.DIFFERS
    } ?: ChatMutationVerification.UNAVAILABLE
    ChatMutationOperation.POLL_CREATE -> messages?.let { values ->
        val expectedEpochSeconds = target.expectedEpochMillis?.div(1_000)
            ?: return ChatMutationVerification.UNAVAILABLE
        if (values.any { message ->
                message.isMine && kotlin.math.abs(
                    message.createdAtEpochSeconds - expectedEpochSeconds,
                ) <= CHAT_RETRY_MATCH_WINDOW_SECONDS && message.poll?.let { poll ->
                    chatPayloadFingerprint(
                        listOf(
                            poll.question,
                            poll.allowsMultipleSelection.toString(),
                            poll.isAnonymous.toString(),
                        ) + poll.options.map { it.text },
                    ) == target.requestFingerprint
                } == true
            }
        ) ChatMutationVerification.MATCHES else ChatMutationVerification.DIFFERS
    } ?: ChatMutationVerification.UNAVAILABLE
    ChatMutationOperation.TEXT_SEND -> messages?.let { values ->
        val expectedEpochSeconds = target.expectedEpochMillis?.div(1_000)
            ?: return ChatMutationVerification.UNAVAILABLE
        if (values.any { message ->
                message.isMine && kotlin.math.abs(
                    message.createdAtEpochSeconds - expectedEpochSeconds,
                ) <= CHAT_RETRY_MATCH_WINDOW_SECONDS &&
                    chatPayloadFingerprint(listOf(message.body)) == target.requestFingerprint
            }
        ) ChatMutationVerification.MATCHES else ChatMutationVerification.DIFFERS
    } ?: ChatMutationVerification.UNAVAILABLE
    ChatMutationOperation.ATTACHMENT_SEND -> messages?.let { values ->
        val expectedEpochSeconds = target.expectedEpochMillis?.div(1_000)
            ?: return ChatMutationVerification.UNAVAILABLE
        if (values.any { message ->
                message.isMine && kotlin.math.abs(
                    message.createdAtEpochSeconds - expectedEpochSeconds,
                ) <= CHAT_RETRY_MATCH_WINDOW_SECONDS && message.attachments.isNotEmpty() &&
                    chatPayloadFingerprint(
                        listOf(message.body) + message.attachments.flatMap { attachment ->
                            listOf(attachment.name, attachment.size?.toString().orEmpty())
                        },
                    ) == target.requestFingerprint
            }
        ) ChatMutationVerification.MATCHES else ChatMutationVerification.DIFFERS
    } ?: ChatMutationVerification.UNAVAILABLE
}

internal fun matchingChatMutationMessage(
    target: ChatMutationTarget,
    messages: List<ChatMessage>,
): ChatMessage? = messages.firstOrNull { message ->
    chatMutationVerification(target, messages = listOf(message)) == ChatMutationVerification.MATCHES
}

internal fun convergeChatMutationRefreshMatch(
    state: WorkspaceState,
    target: ChatMutationTarget,
    messages: List<ChatMessage>,
): WorkspaceState {
    val remote = matchingChatMutationMessage(target, messages) ?: return state
    fun addRemote(base: WorkspaceState, message: ChatMessage): WorkspaceState {
        val outgoing = (base.chatOutgoingMessages[message.conversationId].orEmpty()
            .filterNot { it.id == message.id } + message).sortedBy(ChatMessage::createdAtEpochSeconds)
        val page = (base.chatMessages as? Loadable.Ready)?.value
        return base.copy(
            chatOutgoingMessages = base.chatOutgoingMessages + (message.conversationId to outgoing),
            chatMessages = page?.takeIf {
                base.selectedConversation?.id == message.conversationId
            }?.copy(
                messages = (page.messages.filterNot { it.id == message.id } + message)
                    .sortedBy(ChatMessage::createdAtEpochSeconds),
            )?.let { Loadable.Ready(it) } ?: base.chatMessages,
        )
    }
    return when (target.operation) {
        ChatMutationOperation.TEXT_SEND,
        ChatMutationOperation.ATTACHMENT_SEND,
        -> {
            val local = state.chatOutgoingMessages.values.flatten()
                .firstOrNull { it.clientRequestId == target.requestId }
            val remoteWithRequest = remote.copy(clientRequestId = target.requestId)
            val withoutLocal = if (local == null) state else state.copy(
                chatOutgoingMessages = state.chatOutgoingMessages + (
                    local.conversationId to state.chatOutgoingMessages[local.conversationId].orEmpty()
                        .filterNot { it.id == local.id }
                ),
                chatMessages = (state.chatMessages as? Loadable.Ready)?.value?.takeIf {
                    state.selectedConversation?.id == local.conversationId
                }?.let { page ->
                    Loadable.Ready(page.copy(messages = page.messages.filterNot { it.id == local.id }))
                } ?: state.chatMessages,
            )
            val converged = addRemote(withoutLocal, remoteWithRequest)
            if (target.operation == ChatMutationOperation.ATTACHMENT_SEND && local != null) {
                converged.copy(
                    chatPendingAttachmentUris = converged.chatPendingAttachmentUris - local.id,
                )
            } else converged
        }
        ChatMutationOperation.POLL_CREATE -> addRemote(state, remote).let { converged ->
            if (state.selectedConversation?.id == target.conversationId) converged.copy(
                chatPollComposerVisible = false,
                chatPollQuestion = "",
                chatPollOptions = listOf("", ""),
            ) else converged
        }
        else -> state
    }
}

internal fun removeLocalChatMessage(
    state: WorkspaceState,
    local: ChatMessage,
): WorkspaceState {
    val page = (state.chatMessages as? Loadable.Ready)?.value
    return state.copy(
        chatOutgoingMessages = state.chatOutgoingMessages + (
            local.conversationId to state.chatOutgoingMessages[local.conversationId].orEmpty()
                .filterNot { it.id == local.id }
        ),
        chatMessages = page?.takeIf {
            state.selectedConversation?.id == local.conversationId
        }?.copy(messages = page.messages.filterNot { it.id == local.id })
            ?.let { Loadable.Ready(it) } ?: state.chatMessages,
        chatPendingAttachmentUris = state.chatPendingAttachmentUris - local.id,
    )
}

internal fun WorkspaceState.withRefreshedChatConversations(
    visible: List<ChatConversation>,
): WorkspaceState {
    val selected = selectedConversation
    val refreshedSelection = if (selected == null) {
        null
    } else {
        visible.firstOrNull { it.id == selected.id } ?: selected
    }
    return copy(
        conversations = Loadable.Ready(visible),
        selectedConversation = refreshedSelection,
    )
}

internal fun chatPendingAttachmentUrisForRelease(state: WorkspaceState): List<Uri> =
    state.chatPendingAttachmentUris.values.distinct()

internal fun chatMutationCanRemoveFailed(entry: ChatMutationEntry?): Boolean =
    entry != null && canDismissChatMutation(entry)

internal fun chatMutationCanContinueEditing(entry: ChatMutationEntry?): Boolean =
    entry != null && canDismissChatMutation(entry)

internal enum class ChatRetryReadbackDecision { CONVERGE, RESEND, KEEP_FAILED }

internal fun chatRetryReadbackDecision(
    callbackMatches: Boolean,
    readFailure: DsmFailure?,
    verification: ChatMutationVerification?,
): ChatRetryReadbackDecision = when {
    !callbackMatches || readFailure != null -> ChatRetryReadbackDecision.KEEP_FAILED
    verification == ChatMutationVerification.MATCHES -> ChatRetryReadbackDecision.CONVERGE
    verification == ChatMutationVerification.DIFFERS -> ChatRetryReadbackDecision.RESEND
    else -> ChatRetryReadbackDecision.KEEP_FAILED
}

internal fun chatAttachmentPreflightIsCurrent(
    repositoryMatches: Boolean,
    profileMatches: Boolean,
    moduleMatches: Boolean,
    conversationMatches: Boolean,
    generationMatches: Boolean,
): Boolean = repositoryMatches && profileMatches && moduleMatches && conversationMatches &&
    generationMatches

internal fun releaseChatAttachmentPermissionAfterPreflight(
    permissionAcquired: Boolean,
    preflightMatches: Boolean,
    claimSucceeded: Boolean,
): Boolean = permissionAcquired && (!preflightMatches || !claimSucceeded)

internal fun workspaceNavigationBlockedByChat(
    state: WorkspaceState,
    destination: Module,
): Boolean = state.selectedModule == Module.CHAT && destination != Module.CHAT &&
    chatMutationBlocksWorkspaceExit(state.chatMutationState)


private const val CHAT_RETRY_MATCH_WINDOW_SECONDS = 120L

internal fun ChatMessage.matchesPendingChatMessage(pending: ChatMessage): Boolean =
    isMine && body == pending.body && createdAtEpochSeconds > 0 && pending.createdAtEpochSeconds > 0 &&
        kotlin.math.abs(createdAtEpochSeconds - pending.createdAtEpochSeconds) <= CHAT_RETRY_MATCH_WINDOW_SECONDS
