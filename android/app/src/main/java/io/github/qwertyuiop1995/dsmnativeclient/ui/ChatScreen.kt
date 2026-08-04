package io.github.qwertyuiop1995.dsmnativeclient.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Group
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.PersonAdd
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.AlarmAdd
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Poll
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.viewinterop.AndroidView
import android.graphics.BitmapFactory
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.net.Uri
import android.widget.MediaController
import android.widget.VideoView
import io.github.qwertyuiop1995.dsmnativeclient.AppViewModel
import io.github.qwertyuiop1995.dsmnativeclient.ChatMutationEntry
import io.github.qwertyuiop1995.dsmnativeclient.ChatMutationOperation
import io.github.qwertyuiop1995.dsmnativeclient.chatMutationCanRemoveFailed
import io.github.qwertyuiop1995.dsmnativeclient.Loadable
import io.github.qwertyuiop1995.dsmnativeclient.R
import io.github.qwertyuiop1995.dsmnativeclient.WorkspaceState
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatMessage
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatDeliveryState
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatAttachment
import io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind
import io.github.qwertyuiop1995.dsmnativeclient.localization.localize
import java.text.DateFormat
import java.util.Date
import java.util.Calendar

@Composable
internal fun ChatScreen(state: WorkspaceState, model: AppViewModel) {
    val selected = state.selectedConversation
    val managementMutation = state.chatMutationState.latestManagementEntry
    BoxWithConstraints(Modifier.fillMaxSize()) {
        if (AdaptiveLayoutPolicy.usesChatListDetail(maxWidth.value)) {
            Row(Modifier.fillMaxSize()) {
                ConversationList(state, model, Modifier.width(360.dp).fillMaxSize())
                VerticalDivider()
                if (selected == null) {
                    Box(Modifier.weight(1f).fillMaxSize()) {
                        EmptyState(
                            title = stringResource(R.string.select_conversation),
                            message = stringResource(R.string.select_conversation_description),
                            icon = Icons.Outlined.ChatBubbleOutline,
                        )
                    }
                } else {
                    ConversationDetail(
                        state,
                        model,
                        showBack = false,
                        modifier = Modifier.weight(1f).fillMaxSize(),
                    )
                }
            }
        } else if (selected == null) {
            ConversationList(state, model)
        } else {
            ConversationDetail(state, model)
        }
    }
    if (state.chatNewConversationVisible) NewConversationDialog(state, model)
    if (state.chatMembersVisible) ChatMembersDialog(state, model)
    if (state.chatRemindersVisible) ChatRemindersDialog(state, model)
    if (state.chatScheduleComposerVisible) {
        ChatScheduleComposerDialog(state, model)
    } else if (state.chatScheduledMessagesVisible) {
        ChatScheduledMessagesDialog(state, model)
    }
    if (state.chatPollComposerVisible) ChatPollComposerDialog(state, model)
    if (state.chatAttachmentPreviewName != null) ChatAttachmentPreviewDialog(state, model)
    managementMutation?.let { entry ->
        if (entry.confirmationRequested) {
            ChatMutationConfirmationDialog(
                target = entry.target,
                onConfirm = { model.confirmChatMutation(entry.target.requestId) },
                onDismiss = { model.cancelChatMutation(entry.target.requestId) },
            )
        } else {
            ChatMutationFeedbackDialog(
                entry = entry,
                onRefresh = { model.refreshChatMutation(entry.target.requestId) },
                onContinueEditing = {
                    model.continueEditingChatMutation(entry.target.requestId)
                },
                onDismiss = { model.dismissChatMutation(entry.target.requestId) },
            )
        }
    }
}

private fun WorkspaceState.chatMutationInProgress(
    vararg operations: ChatMutationOperation,
): Boolean = chatMutationState.entries.values.any { entry ->
    entry.target.operation in operations &&
        (entry.confirmationRequested || entry.mutationInProgress || entry.mutationRefreshInProgress)
}

@Composable
private fun ConversationList(
    state: WorkspaceState,
    model: AppViewModel,
    modifier: Modifier = Modifier.fillMaxSize(),
) {
    Column(modifier) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                stringResource(R.string.module_chat),
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = model::openNewChatConversation) {
                Icon(Icons.Outlined.PersonAdd, stringResource(R.string.new_conversation))
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            LoadableContent(
                value = state.conversations,
                emptyTitle = stringResource(R.string.no_conversations),
                emptyMessage = stringResource(R.string.no_conversations_description),
                onRetry = { model.load(io.github.qwertyuiop1995.dsmnativeclient.domain.Module.CHAT) },
            ) { conversations ->
                LazyColumn(Modifier.fillMaxSize()) {
                    items(conversations, key = { it.id }) { conversation ->
                        ListItem(
                            headlineContent = {
                                Text(conversation.title.ifBlank { stringResource(R.string.unnamed_conversation) })
                            },
                            supportingContent = {
                                Text(
                                    conversation.latestPreview ?: pluralStringResource(
                                        R.plurals.member_count,
                                        conversation.memberCount,
                                        conversation.memberCount,
                                    ),
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            },
                            leadingContent = { Icon(Icons.Outlined.ChatBubbleOutline, contentDescription = null) },
                            trailingContent = {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    if (conversation.unreadCount > 0) {
                                        Badge {
                                            Text(conversation.unreadCount.coerceAtMost(99).toString())
                                        }
                                    }
                                    IconButton(
                                        onClick = { model.toggleChatConversationPin(conversation.id) },
                                    ) {
                                        Icon(
                                            Icons.Outlined.PushPin,
                                            contentDescription = stringResource(
                                                if (conversation.isPinnedLocally) {
                                                    R.string.unpin_conversation
                                                } else {
                                                    R.string.pin_conversation
                                                },
                                                conversation.title,
                                            ),
                                            tint = if (conversation.isPinnedLocally) {
                                                MaterialTheme.colorScheme.primary
                                            } else {
                                                MaterialTheme.colorScheme.onSurfaceVariant
                                            },
                                        )
                                    }
                                }
                            },
                            modifier = Modifier
                                .clickable { model.openConversation(conversation) }
                                .semantics(mergeDescendants = true) {},
                        )
                        HorizontalDivider(Modifier.padding(start = 72.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun ConversationDetail(
    state: WorkspaceState,
    model: AppViewModel,
    showBack: Boolean = true,
    modifier: Modifier = Modifier.fillMaxSize(),
) {
    val conversation = state.selectedConversation ?: return
    val context = LocalContext.current
    val reminderMutationInProgress = state.chatMutationInProgress(
        ChatMutationOperation.REMINDER_SET,
        ChatMutationOperation.REMINDER_DELETE,
    )
    var pendingSave by remember { mutableStateOf<Pair<String, ChatAttachment>?>(null) }
    val attachmentPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
        onResult = { uri -> if (uri != null) model.sendChatAttachment(uri) },
    )
    val attachmentSaver = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.CreateDocument("application/octet-stream"),
        onResult = { uri ->
            val pending = pendingSave
            if (uri != null && pending != null) model.saveChatAttachment(pending.first, pending.second, uri)
            pendingSave = null
        },
    )
    Column(modifier) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (showBack) {
                IconButton(onClick = model::closeConversation) {
                    Icon(
                        Icons.AutoMirrored.Outlined.ArrowBack,
                        contentDescription = stringResource(R.string.back_to_conversations),
                    )
                }
            }
            Text(
                conversation.title.ifBlank { stringResource(R.string.unnamed_conversation) },
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 8.dp).weight(1f),
            )
            if (conversation.kind == ConversationKind.GROUP) {
                IconButton(onClick = model::showChatMembers) {
                    Icon(Icons.Outlined.Group, stringResource(R.string.view_group_members))
                }
            }
            if (state.supportsChatReminders) {
                IconButton(onClick = model::showChatReminders) {
                    Icon(Icons.Outlined.Notifications, stringResource(R.string.manage_chat_reminders))
                }
            }
            if (state.supportsChatScheduledMessages) {
                IconButton(onClick = model::showChatScheduledMessages) {
                    Icon(Icons.Outlined.Schedule, stringResource(R.string.manage_scheduled_messages))
                }
            }
            if (state.supportsChatPollCreation) {
                IconButton(onClick = model::openChatPollComposer) {
                    Icon(Icons.Outlined.Poll, stringResource(R.string.create_chat_poll))
                }
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth()) {
            when (val messages = state.chatMessages) {
                Loadable.Idle, Loadable.Loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
                    CircularProgressIndicator()
                }
                is Loadable.Failed -> PhotoFailureForChat(messages, model, conversation)
                is Loadable.Ready -> if (messages.value.messages.isEmpty()) {
                    EmptyState(
                        stringResource(R.string.no_messages),
                        stringResource(R.string.no_messages_description),
                        Icons.Outlined.ChatBubbleOutline,
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        if (messages.value.hasMore) {
                            item {
                                Box(Modifier.fillMaxWidth().padding(8.dp), Alignment.Center) {
                                    Button(
                                        onClick = model::loadOlderChatMessages,
                                        enabled = !state.chatIsLoadingMore,
                                    ) {
                                        if (state.chatIsLoadingMore) {
                                            CircularProgressIndicator(Modifier.size(18.dp))
                                        }
                                        Text(stringResource(R.string.load_older_messages))
                                    }
                                }
                            }
                        }
                        items(messages.value.messages, key = ChatMessage::id) { message ->
                            val mutation = state.chatMutationState.entry(message.clientRequestId)
                            MessageBubble(
                                message = message,
                                mutation = mutation,
                                onRetry = { model.retryChatMessage(message.id) },
                                onRemove = { model.removeFailedChatMessage(message.id) },
                                onCancelUpload = { model.cancelChatAttachment(message.id) },
                                thumbnail = state.chatAttachmentThumbnails[message.id],
                                onPreviewAttachment = { attachment ->
                                    model.previewChatAttachment(message.id, attachment)
                                },
                                onSaveAttachment = { attachment ->
                                    pendingSave = message.id to attachment
                                    attachmentSaver.launch(attachment.name)
                                },
                                onSetReminder = {
                                    showChatReminderPicker(context) { remindAt ->
                                        model.setChatReminder(message.id, remindAt)
                                    }
                                },
                                canSetReminder = state.supportsChatReminders,
                                reminderMutationInProgress = reminderMutationInProgress,
                                onRefreshMutation = {
                                    mutation?.let { model.refreshChatMutation(it.target.requestId) } ?: false
                                },
                                onContinueEditingMutation = {
                                    mutation?.let {
                                        model.continueEditingChatMutation(it.target.requestId)
                                    } ?: false
                                },
                                onDismissMutation = {
                                    mutation?.let { model.dismissChatMutation(it.target.requestId) } ?: false
                                },
                                onCancelMutation = {
                                    mutation?.let { model.cancelChatMutation(it.target.requestId) } ?: false
                                },
                            )
                        }
                        item { Spacer(Modifier.padding(bottom = 12.dp)) }
                    }
                }
            }
        }
        ChatComposer(
            text = state.chatDrafts[conversation.id].orEmpty(),
            enabled = state.chatMessages is Loadable.Ready,
            onTextChange = model::updateChatDraft,
            onSend = model::sendChatMessage,
            onAttach = { attachmentPicker.launch(arrayOf("image/*", "video/*", "application/*", "text/*", "audio/*")) },
        )
    }
}

@Composable
internal fun NewConversationDialog(state: WorkspaceState, model: AppViewModel) {
    val selectedCount = state.chatSelectedUserIds.size
    val context = LocalContext.current
    val mutationInProgress = state.chatMutationInProgress(
        ChatMutationOperation.DIRECT_CONVERSATION_CREATE,
        ChatMutationOperation.PRIVATE_GROUP_CREATE,
    )
    AlertDialog(
        onDismissRequest = model::closeNewChatConversation,
        icon = { Icon(Icons.Outlined.PersonAdd, contentDescription = null) },
        title = { Text(stringResource(R.string.new_conversation)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.select_people_for_chat))
                when (val users = state.chatUsers) {
                    Loadable.Idle, Loadable.Loading -> Box(
                        Modifier.fillMaxWidth().heightIn(min = 120.dp), Alignment.Center,
                    ) { CircularProgressIndicator() }
                    is Loadable.Failed -> {
                        Text(
                            users.error.localize(context).combined,
                            color = MaterialTheme.colorScheme.error,
                        )
                        TextButton(onClick = model::openNewChatConversation) {
                            Text(stringResource(R.string.retry))
                        }
                    }
                    is Loadable.Ready -> if (users.value.isEmpty()) {
                        Text(stringResource(R.string.no_available_chat_users))
                    } else {
                        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 320.dp)) {
                            items(users.value, key = { it.id }) { user ->
                                val selected = user.id in state.chatSelectedUserIds
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable(
                                            enabled = !mutationInProgress,
                                        ) { model.toggleChatConversationUser(user.id) }
                                        .padding(vertical = 8.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Checkbox(
                                        checked = selected,
                                        onCheckedChange = { model.toggleChatConversationUser(user.id) },
                                        enabled = !mutationInProgress,
                                    )
                                    Column(Modifier.padding(start = 8.dp)) {
                                        Text(user.displayName)
                                        if (user.username.isNotBlank() && user.username != user.displayName) {
                                            Text(user.username, style = MaterialTheme.typography.bodySmall)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if (selectedCount > 1) {
                    OutlinedTextField(
                        value = state.chatGroupTitle,
                        onValueChange = model::updateChatGroupTitle,
                        label = { Text(stringResource(R.string.private_group_name)) },
                        singleLine = true,
                        enabled = !mutationInProgress,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(stringResource(R.string.private_group_description), style = MaterialTheme.typography.bodySmall)
                }
                if (mutationInProgress) {
                    LinearProgressIndicator(
                        modifier = Modifier.fillMaxWidth().semantics {
                            contentDescription = context.getString(
                                R.string.chat_conversation_change_in_progress,
                            )
                        },
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = model::submitChatConversation,
                enabled = selectedCount > 0 &&
                    (selectedCount == 1 || state.chatGroupTitle.isNotBlank()) &&
                    !mutationInProgress,
            ) {
                if (mutationInProgress) {
                    CircularProgressIndicator(Modifier.size(18.dp))
                }
                Text(
                    stringResource(
                        if (selectedCount > 1) R.string.create_private_group else R.string.start_conversation,
                    ),
                )
            }
        },
        dismissButton = {
            TextButton(
                onClick = model::closeNewChatConversation,
                enabled = !mutationInProgress,
            ) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@Composable
internal fun ChatMembersDialog(state: WorkspaceState, model: AppViewModel) {
    AlertDialog(
        onDismissRequest = model::closeChatMembers,
        icon = { Icon(Icons.Outlined.Info, contentDescription = null) },
        title = { Text(stringResource(R.string.group_members)) },
        text = {
            when (val members = state.chatMembers) {
                Loadable.Idle, Loadable.Loading -> Box(
                    Modifier.fillMaxWidth().heightIn(min = 120.dp), Alignment.Center,
                ) { CircularProgressIndicator() }
                is Loadable.Failed -> Column {
                    Text(
                        members.error.localize(androidx.compose.ui.platform.LocalContext.current).combined,
                        color = MaterialTheme.colorScheme.error,
                    )
                    TextButton(onClick = model::showChatMembers) {
                        Text(stringResource(R.string.retry))
                    }
                }
                is Loadable.Ready -> if (members.value.isEmpty()) {
                    Text(stringResource(R.string.no_group_members_available))
                } else {
                    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 360.dp)) {
                        items(members.value, key = { it.id }) { member ->
                            ListItem(
                                headlineContent = { Text(member.displayName) },
                                supportingContent = member.username.takeIf(String::isNotBlank)?.let { username ->
                                    { Text(username) }
                                },
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = model::closeChatMembers) {
                Text(stringResource(R.string.close))
            }
        },
    )
}

@Composable
private fun MessageBubble(
    message: ChatMessage,
    mutation: ChatMutationEntry?,
    onRetry: () -> Unit,
    onRemove: () -> Boolean,
    onCancelUpload: () -> Unit,
    thumbnail: Loadable<ByteArray>?,
    onPreviewAttachment: (ChatAttachment) -> Unit,
    onSaveAttachment: (ChatAttachment) -> Unit,
    onSetReminder: () -> Unit,
    canSetReminder: Boolean,
    reminderMutationInProgress: Boolean,
    onRefreshMutation: () -> Boolean,
    onContinueEditingMutation: () -> Boolean,
    onDismissMutation: () -> Boolean,
    onCancelMutation: () -> Boolean,
) {
    val sender = message.sender?.displayName ?: stringResource(R.string.unknown_sender)
    val time = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
        .format(Date(message.createdAtEpochSeconds * 1_000))
    val mutationDelivery = if (mutation != null) chatMutationFeedbackMessage(mutation) else null
    val delivery = mutationDelivery ?: when (
        message.deliveryState
    ) {
        ChatDeliveryState.SENDING -> stringResource(R.string.message_sending)
        ChatDeliveryState.FAILED -> stringResource(R.string.message_send_failed)
        ChatDeliveryState.SENT -> stringResource(
            if (message.isMine) R.string.message_sent else R.string.message_received,
        )
    }
    val accessibilityContent = when {
        message.body.isNotBlank() -> message.body
        message.attachments.isNotEmpty() -> pluralStringResource(
            R.plurals.message_attachment_content,
            message.attachments.size,
            message.attachments.size,
        )
        message.poll != null -> stringResource(R.string.message_poll_content, message.poll.question)
        else -> stringResource(R.string.message_empty_content)
    }
    val spoken = stringResource(
        R.string.message_accessibility_delivery,
        sender,
        time,
        accessibilityContent,
        delivery,
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp)
            .semantics { contentDescription = spoken },
        horizontalArrangement = if (message.isMine) Arrangement.End else Arrangement.Start,
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 520.dp)
                .background(
                    if (message.isMine) MaterialTheme.colorScheme.primaryContainer
                    else MaterialTheme.colorScheme.surfaceVariant,
                    RoundedCornerShape(16.dp),
                )
                .padding(12.dp),
        ) {
            Text(
                sender,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.clearAndSetSemantics {},
            )
            if (message.body.isNotBlank()) {
                Text(
                    message.body,
                    modifier = Modifier.padding(top = 4.dp).clearAndSetSemantics {},
                )
            }
            message.attachments.forEach { attachment ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                ) {
                    Icon(Icons.Outlined.AttachFile, contentDescription = null)
                    Text(
                        attachment.name,
                        modifier = Modifier.padding(start = 4.dp).weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (message.deliveryState == ChatDeliveryState.SENT) {
                        if (attachment.isPreviewableImage() || attachment.isPreviewableVideo()) {
                            TextButton(onClick = { onPreviewAttachment(attachment) }) {
                                if (thumbnail is Loadable.Loading) {
                                    CircularProgressIndicator(Modifier.size(18.dp))
                                } else {
                                    Text(stringResource(R.string.preview_attachment))
                                }
                            }
                        }
                        IconButton(onClick = { onSaveAttachment(attachment) }) {
                            Icon(
                                Icons.Outlined.Download,
                                stringResource(R.string.save_attachment, attachment.name),
                            )
                        }
                    }
                }
            }
            message.poll?.let { poll ->
                Text(
                    stringResource(
                        if (poll.allowsMultipleSelection) {
                            R.string.chat_poll_multiple
                        } else {
                            R.string.chat_poll_single
                        },
                    ),
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(top = 8.dp),
                )
                poll.options.forEach { option ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                    ) {
                        if (option.isSelectedByCurrentUser) {
                            Icon(
                                Icons.Outlined.Check,
                                contentDescription = stringResource(R.string.chat_poll_selected),
                                modifier = Modifier.size(18.dp),
                            )
                        }
                        Text(
                            stringResource(
                                R.string.chat_poll_option_result,
                                option.text,
                                option.voteCount,
                            ),
                            modifier = Modifier.padding(start = 4.dp),
                        )
                    }
                }
                if (poll.isAnonymous) {
                    Text(
                        stringResource(R.string.chat_poll_anonymous),
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
                if (poll.isClosed) {
                    Text(
                        stringResource(R.string.chat_poll_closed),
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
            message.attachmentProgress?.let { progress ->
                LinearProgressIndicator(
                    progress = { progress },
                    modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                )
                Text(
                    stringResource(R.string.attachment_upload_progress, (progress * 100).toInt()),
                    style = MaterialTheme.typography.labelSmall,
                )
                TextButton(onClick = onCancelUpload, enabled = progress < 1f) {
                    Text(stringResource(R.string.cancel_upload))
                }
            }
            Text(
                time,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp).clearAndSetSemantics {},
            )
            if (canSetReminder && message.deliveryState == ChatDeliveryState.SENT) {
                TextButton(
                    onClick = onSetReminder,
                    enabled = !reminderMutationInProgress,
                ) {
                    Icon(Icons.Outlined.AlarmAdd, contentDescription = null)
                    Text(
                        stringResource(R.string.set_chat_reminder),
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
            }
            when (message.deliveryState) {
                ChatDeliveryState.SENDING -> Text(
                    stringResource(R.string.message_sending),
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier.padding(top = 4.dp).clearAndSetSemantics {},
                )
                ChatDeliveryState.FAILED -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (canRetryChatMutation(mutation)) {
                            Button(onClick = onRetry) {
                                Text(stringResource(R.string.retry_send))
                            }
                        }
                        if (chatMutationCanRemoveFailed(mutation)) {
                            IconButton(onClick = { onRemove() }) {
                                Icon(
                                    Icons.Outlined.Close,
                                    stringResource(R.string.remove_failed_message),
                                )
                            }
                        }
                    }
                }
                ChatDeliveryState.SENT -> Unit
            }
            mutation?.let {
                val failedMessage = message.deliveryState == ChatDeliveryState.FAILED
                ChatSendMutationFeedback(
                    entry = it,
                    onRefresh = onRefreshMutation,
                    onContinueEditing = onContinueEditingMutation,
                    onDismiss = if (failedMessage) onRemove else onDismissMutation,
                    onCancel = onCancelMutation,
                    canClose = if (failedMessage) {
                        chatMutationCanRemoveFailed(it)
                    } else {
                        canDismissChatMutationFeedback(it)
                    },
                )
            }
        }
    }
}

@Composable
internal fun ChatRemindersDialog(state: WorkspaceState, model: AppViewModel) {
    val context = LocalContext.current
    val mutationInProgress = state.chatMutationInProgress(
        ChatMutationOperation.REMINDER_SET,
        ChatMutationOperation.REMINDER_DELETE,
    )
    AlertDialog(
        onDismissRequest = model::closeChatReminders,
        icon = { Icon(Icons.Outlined.Notifications, contentDescription = null) },
        title = { Text(stringResource(R.string.chat_reminders)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (mutationInProgress) {
                    LinearProgressIndicator(
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics {
                                contentDescription = context.getString(
                                    R.string.chat_reminder_change_in_progress,
                                )
                            },
                    )
                }
                when (val reminders = state.chatReminders) {
                    Loadable.Idle, Loadable.Loading -> Box(
                        Modifier.fillMaxWidth().heightIn(min = 120.dp),
                        Alignment.Center,
                    ) { CircularProgressIndicator() }
                    is Loadable.Failed -> Column {
                        Text(
                            reminders.error.localize(context).combined,
                            color = MaterialTheme.colorScheme.error,
                        )
                        TextButton(onClick = model::showChatReminders) {
                            Text(stringResource(R.string.retry))
                        }
                    }
                    is Loadable.Ready -> if (reminders.value.isEmpty()) {
                        Text(stringResource(R.string.no_chat_reminders))
                    } else {
                        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 360.dp)) {
                            items(reminders.value, key = { it.id }) { reminder ->
                                val date = DateFormat.getDateTimeInstance(
                                    DateFormat.MEDIUM,
                                    DateFormat.SHORT,
                                ).format(Date(reminder.remindAtEpochMillis))
                                ListItem(
                                    headlineContent = { Text(date) },
                                    supportingContent = {
                                        Text(stringResource(R.string.chat_reminder_message_reference))
                                    },
                                    trailingContent = {
                                        IconButton(
                                            onClick = {
                                                model.requestDeleteChatReminder(reminder.messageId)
                                            },
                                            enabled = !mutationInProgress,
                                        ) {
                                            Icon(
                                                Icons.Outlined.Close,
                                                stringResource(R.string.remove_chat_reminder, date),
                                            )
                                        }
                                    },
                                )
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = model::closeChatReminders,
                enabled = !mutationInProgress,
            ) { Text(stringResource(R.string.close)) }
        },
    )
}

private fun showChatReminderPicker(context: Context, onSelected: (Long) -> Unit) {
    val initial = Calendar.getInstance().apply { add(Calendar.HOUR_OF_DAY, 1) }
    DatePickerDialog(
        context,
        { _, year, month, day ->
            TimePickerDialog(
                context,
                { _, hour, minute ->
                    val selected = Calendar.getInstance().apply {
                        set(year, month, day, hour, minute, 0)
                        set(Calendar.MILLISECOND, 0)
                    }
                    onSelected(selected.timeInMillis)
                },
                initial.get(Calendar.HOUR_OF_DAY),
                initial.get(Calendar.MINUTE),
                android.text.format.DateFormat.is24HourFormat(context),
            ).show()
        },
        initial.get(Calendar.YEAR),
        initial.get(Calendar.MONTH),
        initial.get(Calendar.DAY_OF_MONTH),
    ).apply {
        datePicker.minDate = System.currentTimeMillis() + 60_000
    }.show()
}

@Composable
internal fun ChatScheduledMessagesDialog(state: WorkspaceState, model: AppViewModel) {
    val context = LocalContext.current
    val mutationInProgress = state.chatMutationInProgress(
        ChatMutationOperation.SCHEDULE_CREATE,
        ChatMutationOperation.SCHEDULE_DELETE,
    )
    AlertDialog(
        onDismissRequest = model::closeChatScheduledMessages,
        icon = { Icon(Icons.Outlined.Schedule, contentDescription = null) },
        title = { Text(stringResource(R.string.scheduled_messages)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (mutationInProgress) {
                    LinearProgressIndicator(
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics {
                                contentDescription = context.getString(
                                    R.string.chat_schedule_change_in_progress,
                                )
                            },
                    )
                }
                when (val messages = state.chatScheduledMessages) {
                    Loadable.Idle, Loadable.Loading -> Box(
                        Modifier.fillMaxWidth().heightIn(min = 120.dp), Alignment.Center,
                    ) { CircularProgressIndicator() }
                    is Loadable.Failed -> Column {
                        Text(
                            messages.error.localize(context).combined,
                            color = MaterialTheme.colorScheme.error,
                        )
                        TextButton(onClick = model::showChatScheduledMessages) {
                            Text(stringResource(R.string.retry))
                        }
                    }
                    is Loadable.Ready -> if (messages.value.isEmpty()) {
                        Text(stringResource(R.string.no_scheduled_messages))
                    } else {
                        LazyColumn(Modifier.fillMaxWidth().heightIn(max = 360.dp)) {
                            items(messages.value, key = { it.id }) { scheduled ->
                                val date = DateFormat.getDateTimeInstance(
                                    DateFormat.MEDIUM,
                                    DateFormat.SHORT,
                                ).format(Date(scheduled.sendAtEpochMillis))
                                ListItem(
                                    headlineContent = {
                                        Text(scheduled.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                    },
                                    supportingContent = { Text(date) },
                                    trailingContent = {
                                        IconButton(
                                            onClick = { model.requestDeleteChatScheduledMessage(scheduled.id) },
                                            enabled = !mutationInProgress,
                                        ) {
                                            Icon(
                                                Icons.Outlined.Close,
                                                stringResource(R.string.remove_scheduled_message),
                                            )
                                        }
                                    },
                                )
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = model::openChatScheduleComposer,
                enabled = !mutationInProgress,
            ) {
                Icon(Icons.Outlined.Add, contentDescription = null)
                Text(stringResource(R.string.new_scheduled_message), Modifier.padding(start = 4.dp))
            }
        },
        dismissButton = {
            TextButton(
                onClick = model::closeChatScheduledMessages,
                enabled = !mutationInProgress,
            ) { Text(stringResource(R.string.close)) }
        },
    )
}

@Composable
internal fun ChatScheduleComposerDialog(state: WorkspaceState, model: AppViewModel) {
    val context = LocalContext.current
    val mutationInProgress = state.chatMutationInProgress(
        ChatMutationOperation.SCHEDULE_CREATE,
        ChatMutationOperation.SCHEDULE_DELETE,
    )
    val sendAt = state.chatScheduleSendAtEpochMillis
    val formatted = sendAt?.let {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it))
    }.orEmpty()
    AlertDialog(
        onDismissRequest = model::closeChatScheduleComposer,
        title = { Text(stringResource(R.string.new_scheduled_message)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = state.chatScheduleDraft,
                    onValueChange = model::updateChatScheduleDraft,
                    label = { Text(stringResource(R.string.scheduled_message_text)) },
                    minLines = 3,
                    maxLines = 8,
                    enabled = !mutationInProgress,
                    modifier = Modifier.fillMaxWidth(),
                )
                TextButton(
                    onClick = {
                        showChatReminderPicker(context, model::updateChatScheduleTime)
                    },
                    enabled = !mutationInProgress,
                ) {
                    Icon(Icons.Outlined.Schedule, contentDescription = null)
                    Text(
                        formatted.ifBlank { stringResource(R.string.choose_scheduled_time) },
                        modifier = Modifier.padding(start = 4.dp),
                    )
                }
                Text(stringResource(R.string.scheduled_message_explanation))
            }
        },
        confirmButton = {
            Button(
                onClick = model::createChatScheduledMessage,
                enabled = state.chatScheduleDraft.isNotBlank() && sendAt != null &&
                    sendAt > System.currentTimeMillis() + 60_000 &&
                    !mutationInProgress,
            ) {
                if (mutationInProgress) {
                    CircularProgressIndicator(Modifier.size(18.dp))
                }
                Text(stringResource(R.string.schedule_message))
            }
        },
        dismissButton = {
            TextButton(
                onClick = model::closeChatScheduleComposer,
                enabled = !mutationInProgress,
            ) { Text(stringResource(R.string.cancel)) }
        },
    )
}

@Composable
internal fun ChatPollComposerDialog(state: WorkspaceState, model: AppViewModel) {
    val normalizedOptions = state.chatPollOptions.map(String::trim).filter(String::isNotBlank)
    val mutationInProgress = state.chatMutationInProgress(ChatMutationOperation.POLL_CREATE)
    val optionsAreValid = normalizedOptions.size >= 2 &&
        normalizedOptions.map { it.lowercase() }.distinct().size == normalizedOptions.size
    val progressDescription = stringResource(R.string.chat_poll_creation_in_progress)
    AlertDialog(
        onDismissRequest = model::closeChatPollComposer,
        icon = { Icon(Icons.Outlined.Poll, contentDescription = null) },
        title = { Text(stringResource(R.string.create_chat_poll)) },
        text = {
            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.fillMaxWidth().heightIn(max = 520.dp),
            ) {
                item {
                    OutlinedTextField(
                        value = state.chatPollQuestion,
                        onValueChange = model::updateChatPollQuestion,
                        label = { Text(stringResource(R.string.chat_poll_question)) },
                        enabled = !mutationInProgress,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                items(state.chatPollOptions.size) { index ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(
                            value = state.chatPollOptions[index],
                            onValueChange = { model.updateChatPollOption(index, it) },
                            label = { Text(stringResource(R.string.chat_poll_option_number, index + 1)) },
                            enabled = !mutationInProgress,
                            singleLine = true,
                            modifier = Modifier.weight(1f),
                        )
                        if (state.chatPollOptions.size > 2) {
                            IconButton(
                                onClick = { model.removeChatPollOption(index) },
                                enabled = !mutationInProgress,
                            ) {
                                Icon(
                                    Icons.Outlined.Close,
                                    stringResource(R.string.remove_chat_poll_option, index + 1),
                                )
                            }
                        }
                    }
                }
                if (state.chatPollOptions.size < 10) {
                    item {
                        TextButton(
                            onClick = model::addChatPollOption,
                            enabled = !mutationInProgress,
                        ) {
                            Icon(Icons.Outlined.Add, contentDescription = null)
                            Text(stringResource(R.string.add_chat_poll_option))
                        }
                    }
                }
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = state.chatPollAllowsMultiple,
                            onCheckedChange = { model.toggleChatPollMultiple() },
                            enabled = !mutationInProgress,
                        )
                        Text(stringResource(R.string.allow_multiple_poll_choices))
                    }
                }
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Checkbox(
                            checked = state.chatPollIsAnonymous,
                            onCheckedChange = { model.toggleChatPollAnonymous() },
                            enabled = !mutationInProgress,
                        )
                        Text(stringResource(R.string.anonymous_chat_poll))
                    }
                }
                if (mutationInProgress) {
                    item {
                        LinearProgressIndicator(
                            modifier = Modifier.fillMaxWidth().semantics {
                                contentDescription = progressDescription
                            },
                        )
                    }
                }
                item {
                    Text(
                        stringResource(R.string.chat_poll_creation_limit),
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        },
        confirmButton = {
            Button(
                onClick = model::createChatPoll,
                enabled = state.chatPollQuestion.isNotBlank() && optionsAreValid &&
                    !mutationInProgress,
            ) {
                if (mutationInProgress) {
                    CircularProgressIndicator(Modifier.size(18.dp))
                }
                Text(stringResource(R.string.create))
            }
        },
        dismissButton = {
            TextButton(
                onClick = model::closeChatPollComposer,
                enabled = !mutationInProgress,
            ) { Text(stringResource(R.string.cancel)) }
        },
    )
}

private fun ChatAttachment.isPreviewableImage(): Boolean =
    mimeType?.startsWith("image/", ignoreCase = true) == true ||
        name.substringAfterLast('.', "").lowercase() in setOf("jpg", "jpeg", "png", "gif", "webp", "heic", "heif")

private fun ChatAttachment.isPreviewableVideo(): Boolean =
    mimeType?.startsWith("video/", ignoreCase = true) == true ||
        name.substringAfterLast('.', "").lowercase() in setOf(
            "mp4", "m4v", "mov", "avi", "mkv", "webm", "mpeg", "mpg", "ts", "m2ts",
        )

@Composable
internal fun ChatAttachmentPreviewDialog(state: WorkspaceState, model: AppViewModel) {
    val name = state.chatAttachmentPreviewName ?: return
    val bytes = state.chatAttachmentPreviewBytes
    val bitmap = remember(bytes) {
        bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
    }
    AlertDialog(
        onDismissRequest = model::closeChatAttachmentPreview,
        title = { Text(name) },
        text = {
            when {
                state.chatAttachmentPreviewIsLoading -> Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    CircularProgressIndicator()
                    Text(stringResource(R.string.preparing_attachment_preview))
                    state.chatAttachmentPreviewProgress?.let { progress ->
                        LinearProgressIndicator(
                            progress = { progress },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Text(
                            stringResource(
                                R.string.attachment_preview_progress,
                                (progress * 100).toInt(),
                            ),
                        )
                    }
                }
                state.chatAttachmentPreviewError != null -> Text(state.chatAttachmentPreviewError)
                state.chatAttachmentPreviewIsVideo && state.chatAttachmentPreviewVideoFile != null ->
                    ChatVideoAttachmentPlayer(state.chatAttachmentPreviewVideoFile, name)
                bitmap != null -> Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = name,
                    modifier = Modifier.fillMaxWidth().heightIn(max = 560.dp),
                )
                else -> Text(stringResource(R.string.attachment_preview_unavailable))
            }
        },
        confirmButton = {
            TextButton(onClick = model::closeChatAttachmentPreview) {
                Text(stringResource(R.string.close))
            }
        },
    )
}

@Composable
private fun ChatVideoAttachmentPlayer(file: java.io.File, name: String) {
    var videoView: VideoView? by remember(file) { mutableStateOf(null) }
    var playbackFailed by remember(file) { mutableStateOf(false) }
    val description = stringResource(R.string.attachment_video_description, name)
    DisposableEffect(file) {
        onDispose {
            videoView?.stopPlayback()
            videoView = null
        }
    }
    if (playbackFailed) {
        Text(stringResource(R.string.attachment_video_unavailable))
        return
    }
    AndroidView(
        factory = { context ->
            VideoView(context).also { view ->
                videoView = view
                val controller = MediaController(context)
                view.setMediaController(controller)
                controller.setAnchorView(view)
                view.setVideoURI(Uri.fromFile(file))
                view.setOnPreparedListener { controller.show(0) }
                view.setOnErrorListener { _, _, _ ->
                    playbackFailed = true
                    true
                }
            }
        },
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 240.dp, max = 560.dp)
            .semantics { contentDescription = description },
    )
}

@Composable
internal fun ChatComposer(
    text: String,
    enabled: Boolean,
    onTextChange: (String) -> Unit,
    onSend: () -> Unit,
    onAttach: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(8.dp),
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (onAttach != null) {
            IconButton(onClick = onAttach, enabled = enabled) {
                Icon(Icons.Outlined.AttachFile, stringResource(R.string.attach_file))
            }
        }
        OutlinedTextField(
            value = text,
            onValueChange = { if (it.length <= 10_000) onTextChange(it) },
            modifier = Modifier.weight(1f),
            enabled = enabled,
            label = { Text(stringResource(R.string.message)) },
            placeholder = { Text(stringResource(R.string.write_a_message)) },
            minLines = 1,
            maxLines = 5,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { if (text.isNotBlank()) onSend() }),
        )
        IconButton(
            onClick = onSend,
            enabled = enabled && text.isNotBlank(),
        ) {
            Icon(
                Icons.AutoMirrored.Outlined.Send,
                contentDescription = stringResource(R.string.send_message),
            )
        }
    }
}

@Composable
private fun PhotoFailureForChat(
    failure: Loadable.Failed,
    model: AppViewModel,
    conversation: io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation,
) {
    val localized = failure.error.localize(androidx.compose.ui.platform.LocalContext.current)
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(localized.message, fontWeight = FontWeight.SemiBold)
        Text(localized.recovery, modifier = Modifier.padding(top = 8.dp))
        Button(onClick = { model.openConversation(conversation) }, modifier = Modifier.padding(top = 16.dp)) {
            Text(stringResource(R.string.retry))
        }
    }
}
