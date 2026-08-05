package io.github.qwertyuiop1995.dsmnativeclient.domain

data class ChatUser(
    val id: String,
    val displayName: String,
    val username: String,
    val isDisabled: Boolean = false,
    val isCurrent: Boolean = false,
)

enum class ConversationKind { DIRECT, GROUP }

data class ChatConversation(
    val id: String,
    val title: String,
    val kind: ConversationKind,
    val memberIds: List<String> = emptyList(),
    val unreadCount: Int = 0,
    val isPinnedLocally: Boolean = false,
    val memberCount: Int = 0,
    val latestPreview: String? = null,
    val latestAtEpochSeconds: Long? = null,
)

data class ChatAttachment(
    val id: String,
    val name: String,
    val mimeType: String?,
    val size: Long?,
)

data class ChatReminder(
    val id: String,
    val messageId: String,
    val remindAtEpochMillis: Long,
)

data class ChatScheduledMessage(
    val id: String,
    val conversationId: String,
    val text: String,
    val sendAtEpochMillis: Long,
)

data class ChatPollOption(
    val id: String,
    val text: String,
    val voteCount: Int = 0,
    val isSelectedByCurrentUser: Boolean = false,
)

data class ChatPoll(
    val id: String,
    val question: String,
    val allowsMultipleSelection: Boolean,
    val isAnonymous: Boolean,
    val isClosed: Boolean = false,
    val options: List<ChatPollOption>,
)

data class ChatMessage(
    val id: String,
    val conversationId: String,
    val sender: ChatUser?,
    val body: String,
    val createdAtEpochSeconds: Long,
    val isMine: Boolean,
    val attachments: List<ChatAttachment> = emptyList(),
    val isPinned: Boolean = false,
    val clientRequestId: String? = null,
    val deliveryState: ChatDeliveryState = ChatDeliveryState.SENT,
    val attachmentProgress: Float? = null,
    val poll: ChatPoll? = null,
)

enum class ChatDeliveryState { SENDING, SENT, FAILED }

data class ChatMessagePage(
    val messages: List<ChatMessage>,
    val nextOffset: Int?,
    val hasMore: Boolean,
)
