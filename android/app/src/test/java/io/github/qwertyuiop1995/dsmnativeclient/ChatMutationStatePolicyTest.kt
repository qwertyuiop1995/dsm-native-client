package io.github.qwertyuiop1995.dsmnativeclient

import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatMessage
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatAttachment
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatPoll
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatPollOption
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatReminder
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatScheduledMessage
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatUser
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatDeliveryState
import io.github.qwertyuiop1995.dsmnativeclient.domain.ChatMessagePage
import io.github.qwertyuiop1995.dsmnativeclient.domain.DsmFailure
import io.github.qwertyuiop1995.dsmnativeclient.domain.NasProfile
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationErrorCategory
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResult
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultCounts
import io.github.qwertyuiop1995.dsmnativeclient.domain.MutationResultStatus
import io.github.qwertyuiop1995.dsmnativeclient.domain.Module
import io.github.qwertyuiop1995.dsmnativeclient.ui.canRetryChatMutation
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatMutationStatePolicyTest {
    @Test
    fun `九类操作使用稳定标识并且目标不保存正文`() {
        val secret = "仅用于内存中的正文"
        ChatMutationOperation.entries.forEachIndexed { index, operation ->
            val target = chatMutationTarget(
                profileId = "profile-a",
                operation = operation,
                requestId = "request-$index",
                conversationId = "conversation-a",
                requestParts = listOf(secret, operation.name),
            )
            assertEquals(operation, target.operation)
            assertEquals(64, target.requestFingerprint.length)
            assertFalse(target.toString().contains(secret))
        }
        assertEquals(9, ChatMutationOperation.entries.size)
    }

    @Test
    fun `内容指纹区分字段边界并且配置重建保持一致`() {
        assertNotEquals(
            chatPayloadFingerprint(listOf("ab", "c")),
            chatPayloadFingerprint(listOf("a", "bc")),
        )
        val first = target(ChatMutationOperation.TEXT_SEND)
        assertEquals(first, first.copy())
    }

    @Test
    fun `八种原始结果状态均完整保留`() {
        MutationResultStatus.entries.forEach { status ->
            val entry = ChatMutationEntry(target(ChatMutationOperation.TEXT_SEND), mutationResult = result(status))
            assertEquals(status, entry.mutationResult?.status)
            assertEquals(result(status).counts, entry.mutationResult?.counts)
        }
        assertEquals(8, MutationResultStatus.entries.size)
    }

    @Test
    fun `回调必须同时匹配仓库配置目标和代次`() {
        val target = target(ChatMutationOperation.ATTACHMENT_SEND)
        val entry = ChatMutationEntry(target, mutationInProgress = true, generation = 7)
        assertTrue(chatMutationCallbackMatches(true, true, entry, target, 7, 7))
        assertFalse(chatMutationCallbackMatches(false, true, entry, target, 7, 7))
        assertFalse(chatMutationCallbackMatches(true, false, entry, target, 7, 7))
        assertFalse(chatMutationCallbackMatches(true, true, entry, target.copy(requestId = "other"), 7, 7))
        assertFalse(chatMutationCallbackMatches(true, true, entry, target, 6, 7))
        assertFalse(chatMutationCallbackMatches(true, true, entry, target, 7, 8))
    }

    @Test
    fun `在途和未回读未知结果阻止退出而收敛结果不阻止`() {
        val target = target(ChatMutationOperation.SCHEDULE_DELETE)
        assertTrue(chatMutationBlocksWorkspaceExit(ChatMutationWorkspaceState(mapOf(
            target.requestId to ChatMutationEntry(target, mutationInProgress = true),
        ))))
        val unknown = ChatMutationEntry(target, mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED))
        assertTrue(chatMutationBlocksWorkspaceExit(ChatMutationWorkspaceState(mapOf(target.requestId to unknown))))
        assertFalse(chatMutationBlocksWorkspaceExit(ChatMutationWorkspaceState(mapOf(
            target.requestId to unknown.copy(
                mutationRefreshCompleted = true,
                mutationVerification = ChatMutationVerification.DIFFERS,
            ),
        ))))
        val success = ChatMutationEntry(target, mutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS))
        assertFalse(chatMutationBlocksWorkspaceExit(ChatMutationWorkspaceState(mapOf(target.requestId to success))))
    }

    @Test
    fun `删除回读和发送回读按稳定目标核验`() {
        val reminder = ChatReminder("reminder-a", "message-a", 1000)
        val reminderTarget = chatMutationTarget(
            "profile-a", ChatMutationOperation.REMINDER_DELETE, "request-reminder",
            "conversation-a", resourceIds = listOf("message-a"), requestParts = listOf("message-a"),
            reminderBaseline = reminder,
        )
        assertEquals(ChatMutationVerification.DISAPPEARED, chatMutationVerification(reminderTarget, reminders = emptyList()))

        val schedule = ChatScheduledMessage("schedule-a", "conversation-a", "later", 2000)
        val scheduleTarget = chatMutationTarget(
            "profile-a", ChatMutationOperation.SCHEDULE_DELETE, "request-schedule",
            "conversation-a", resourceIds = listOf("schedule-a"), requestParts = listOf("schedule-a"),
            scheduleBaseline = schedule,
        )
        assertEquals(ChatMutationVerification.DIFFERS, chatMutationVerification(scheduleTarget, schedules = listOf(schedule)))

        val textTarget = chatMutationTarget(
            "profile-a", ChatMutationOperation.TEXT_SEND, "request-text", "conversation-a",
            expectedEpochMillis = 1_000,
            requestParts = listOf("hello"),
        )
        val sent = ChatMessage(
            "message-b", "conversation-a", ChatUser("me", "Me", "me"), "hello", 1, true,
        )
        assertEquals(ChatMutationVerification.MATCHES, chatMutationVerification(textTarget, messages = listOf(sent)))
        assertEquals(
            ChatMutationVerification.DIFFERS,
            chatMutationVerification(
                textTarget,
                messages = listOf(sent.copy(createdAtEpochSeconds = 122)),
            ),
        )
    }

    @Test
    fun `投票和附件的同内容历史消息不能认领当前提交`() {
        val pollTarget = chatMutationTarget(
            "profile-a", ChatMutationOperation.POLL_CREATE, "request-poll", "conversation-a",
            expectedEpochMillis = 1_000,
            requestParts = listOf("Question", "false", "false", "A", "B"),
        )
        val pollMessage = ChatMessage(
            "poll-message", "conversation-a", ChatUser("me", "Me", "me"), "", 122, true,
            poll = ChatPoll(
                "poll-a", "Question", false, false,
                options = listOf(ChatPollOption("a", "A"), ChatPollOption("b", "B")),
            ),
        )
        assertEquals(
            ChatMutationVerification.DIFFERS,
            chatMutationVerification(pollTarget, messages = listOf(pollMessage)),
        )

        val attachmentTarget = chatMutationTarget(
            "profile-a", ChatMutationOperation.ATTACHMENT_SEND, "request-file", "conversation-a",
            expectedEpochMillis = 1_000,
            requestParts = listOf("body", "photo.jpg", "42"),
        )
        val attachmentMessage = ChatMessage(
            "file-message", "conversation-a", ChatUser("me", "Me", "me"), "body", 122, true,
            attachments = listOf(ChatAttachment("file-a", "photo.jpg", "image/jpeg", 42)),
        )
        assertEquals(
            ChatMutationVerification.DIFFERS,
            chatMutationVerification(attachmentTarget, messages = listOf(attachmentMessage)),
        )
    }

    @Test
    fun `提交后取消保留未知计数并要求刷新`() {
        val result = cancelledChatMutationResult(target(ChatMutationOperation.ATTACHMENT_SEND))
        assertEquals(MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION, result.status)
        assertTrue(result.submitted)
        assertTrue(result.requiresRefresh)
        assertEquals(MutationResultCounts(0, 0, 1), result.counts)
    }

    @Test
    fun `刷新匹配会原子替换失败消息并收敛投票编辑器`() {
        val textTarget = chatMutationTarget(
            "profile-a", ChatMutationOperation.TEXT_SEND, "request-text", "conversation-a",
            expectedEpochMillis = 1_000, requestParts = listOf("hello"),
        )
        val local = ChatMessage(
            "local:request-text", "conversation-a", ChatUser("me", "Me", "me"),
            "hello", 1, true, clientRequestId = "request-text",
            deliveryState = ChatDeliveryState.FAILED,
        )
        val remote = local.copy(id = "remote-text", clientRequestId = null, deliveryState = ChatDeliveryState.SENT)
        val state = workspace().copy(
            selectedConversation = io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation(
                "conversation-a", "A", io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind.DIRECT,
            ),
            chatOutgoingMessages = mapOf("conversation-a" to listOf(local)),
            chatMessages = Loadable.Ready(ChatMessagePage(listOf(local), null, false)),
        )
        val converged = convergeChatMutationRefreshMatch(state, textTarget, listOf(remote))
        val visible = (converged.chatMessages as Loadable.Ready).value.messages
        assertFalse(visible.any { it.id == local.id })
        assertEquals("request-text", visible.single { it.id == remote.id }.clientRequestId)

        val pollTarget = chatMutationTarget(
            "profile-a", ChatMutationOperation.POLL_CREATE, "request-poll", "conversation-a",
            expectedEpochMillis = 1_000,
            requestParts = listOf("Question", "false", "false", "A", "B"),
        )
        val poll = ChatMessage(
            "remote-poll", "conversation-a", ChatUser("me", "Me", "me"), "", 1, true,
            poll = ChatPoll(
                "poll", "Question", false, false,
                options = listOf(ChatPollOption("a", "A"), ChatPollOption("b", "B")),
            ),
        )
        val pollState = convergeChatMutationRefreshMatch(
            workspace().copy(
                selectedConversation = io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation(
                    "conversation-a", "A", io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind.DIRECT,
                ),
                chatPollComposerVisible = true,
                chatPollQuestion = "Question",
                chatPollOptions = listOf("A", "B"),
                chatMessages = Loadable.Ready(ChatMessagePage(emptyList(), null, false)),
            ),
            pollTarget,
            listOf(poll),
        )
        assertFalse(pollState.chatPollComposerVisible)
        assertTrue((pollState.chatMessages as Loadable.Ready).value.messages.any { it.id == poll.id })
    }

    @Test
    fun `附件刷新匹配替换失败气泡`() {
        val target = chatMutationTarget(
            "profile-a", ChatMutationOperation.ATTACHMENT_SEND, "request-file", "conversation-a",
            expectedEpochMillis = 1_000, requestParts = listOf("body", "photo.jpg", "42"),
        )
        val attachment = ChatAttachment("file", "photo.jpg", "image/jpeg", 42)
        val local = ChatMessage(
            "local:request-file", "conversation-a", ChatUser("me", "Me", "me"), "body", 1, true,
            attachments = listOf(attachment), clientRequestId = "request-file",
            deliveryState = ChatDeliveryState.FAILED,
        )
        val remote = local.copy(id = "remote-file", clientRequestId = null, deliveryState = ChatDeliveryState.SENT)
        val converged = convergeChatMutationRefreshMatch(
            workspace().copy(
                selectedConversation = io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation(
                    "conversation-a", "A", io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind.DIRECT,
                ),
                chatOutgoingMessages = mapOf("conversation-a" to listOf(local)),
                chatMessages = Loadable.Ready(ChatMessagePage(listOf(local), null, false)),
            ),
            target,
            listOf(remote),
        )
        assertFalse(converged.chatOutgoingMessages.values.flatten().any { it.id == local.id })
        assertTrue(converged.chatOutgoingMessages.values.flatten().any { it.id == remote.id })
        assertFalse(converged.chatPendingAttachmentUris.containsKey(local.id))
    }

    @Test
    fun `未完成回读拒绝处置而明确不匹配后允许原子移除和继续编辑`() {
        val target = target(ChatMutationOperation.TEXT_SEND)
        val unknown = ChatMutationEntry(
            target,
            mutationResult = result(MutationResultStatus.SUBMITTED_BUT_UNVERIFIED),
        )
        assertFalse(chatMutationCanRemoveFailed(unknown))
        assertFalse(chatMutationCanContinueEditing(unknown))
        val checkedDifferent = unknown.copy(
            mutationRefreshCompleted = true,
            mutationVerification = ChatMutationVerification.DIFFERS,
        )
        assertTrue(chatMutationCanRemoveFailed(checkedDifferent))
        assertTrue(chatMutationCanContinueEditing(checkedDifferent))
        val settled = ChatMutationEntry(
            target,
            mutationResult = result(MutationResultStatus.CONFIRMED_FAILURE),
        )
        assertTrue(chatMutationCanRemoveFailed(settled))
        assertTrue(chatMutationCanContinueEditing(settled))
    }

    @Test
    fun `跨会话迟到完成和刷新匹配只收敛目标分桶不污染当前消息页`() {
        val conversationA = io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation(
            "conversation-a", "A", io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind.DIRECT,
        )
        val conversationB = io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation(
            "conversation-b", "B", io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind.DIRECT,
        )
        val target = chatMutationTarget(
            "profile-a", ChatMutationOperation.TEXT_SEND, "request-a", conversationA.id,
            expectedEpochMillis = 1_000, requestParts = listOf("from A"),
        )
        val local = ChatMessage(
            "local:request-a", conversationA.id, ChatUser("me", "Me", "me"),
            "from A", 1, true, clientRequestId = "request-a",
            deliveryState = ChatDeliveryState.FAILED,
        )
        val remote = local.copy(
            id = "remote-a", clientRequestId = null, deliveryState = ChatDeliveryState.SENT,
        )
        val visibleB = ChatMessage(
            "message-b", conversationB.id, ChatUser("other", "Other", "other"),
            "stay in B", 1, false,
        )
        val state = workspace().copy(
            selectedConversation = conversationB,
            chatOutgoingMessages = mapOf(conversationA.id to listOf(local)),
            chatMessages = Loadable.Ready(ChatMessagePage(listOf(visibleB), null, false)),
        )

        val converged = convergeChatMutationRefreshMatch(state, target, listOf(remote))

        assertEquals(listOf(visibleB), (converged.chatMessages as Loadable.Ready).value.messages)
        assertFalse(converged.chatOutgoingMessages.getValue(conversationA.id).any { it.id == local.id })
        assertTrue(converged.chatOutgoingMessages.getValue(conversationA.id).any { it.id == remote.id })
    }

    @Test
    fun `明确移除附件失败气泡会清理目标分桶和待释放URI且不污染其他会话`() {
        val conversationA = io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation(
            "conversation-a", "A", io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind.DIRECT,
        )
        val conversationB = io.github.qwertyuiop1995.dsmnativeclient.domain.ChatConversation(
            "conversation-b", "B", io.github.qwertyuiop1995.dsmnativeclient.domain.ConversationKind.DIRECT,
        )
        val local = ChatMessage(
            "local:file", conversationA.id, ChatUser("me", "Me", "me"), "", 1, true,
            clientRequestId = "request-file", deliveryState = ChatDeliveryState.FAILED,
        )
        val visibleB = ChatMessage(
            "message-b", conversationB.id, ChatUser("other", "Other", "other"), "B", 1, false,
        )
        val state = workspace().copy(
            selectedConversation = conversationB,
            chatOutgoingMessages = mapOf(conversationA.id to listOf(local)),
            chatMessages = Loadable.Ready(ChatMessagePage(listOf(visibleB), null, false)),
            chatPendingAttachmentUris = mapOf(local.id to Uri.EMPTY),
        )

        val removed = removeLocalChatMessage(state, local)

        assertTrue(removed.chatOutgoingMessages.getValue(conversationA.id).isEmpty())
        assertFalse(removed.chatPendingAttachmentUris.containsKey(local.id))
        assertEquals(listOf(visibleB), (removed.chatMessages as Loadable.Ready).value.messages)
    }

    @Test
    fun `销毁工作区时待释放附件URI会去重`() {
        val state = workspace().copy(
            chatPendingAttachmentUris = mapOf(
                "local-a" to Uri.EMPTY,
                "local-a-retry" to Uri.EMPTY,
            ),
        )

        assertEquals(listOf(Uri.EMPTY), chatPendingAttachmentUrisForRelease(state))
    }

    @Test
    fun `重试回读失败保留失败态只有明确不匹配才重发`() {
        val failure = DsmFailure(null, "read failed", "retry")
        assertEquals(
            ChatRetryReadbackDecision.KEEP_FAILED,
            chatRetryReadbackDecision(true, failure, null),
        )
        assertEquals(
            ChatRetryReadbackDecision.KEEP_FAILED,
            chatRetryReadbackDecision(false, null, ChatMutationVerification.DIFFERS),
        )
        assertEquals(
            ChatRetryReadbackDecision.RESEND,
            chatRetryReadbackDecision(true, null, ChatMutationVerification.DIFFERS),
        )
        assertEquals(
            ChatRetryReadbackDecision.CONVERGE,
            chatRetryReadbackDecision(true, null, ChatMutationVerification.MATCHES),
        )
    }

    @Test
    fun `附件预检离开再返回的ABA代次失配且claim失败会释放已取得权限`() {
        assertTrue(chatAttachmentPreflightIsCurrent(true, true, true, true, true))
        assertFalse(chatAttachmentPreflightIsCurrent(true, true, false, true, true))
        assertFalse(chatAttachmentPreflightIsCurrent(true, true, true, false, true))
        // 即使模块和会话已经返回原值，离开时递增的代次仍拒绝旧回调。
        assertFalse(chatAttachmentPreflightIsCurrent(true, true, true, true, false))
        assertTrue(releaseChatAttachmentPermissionAfterPreflight(true, false, false))
        assertTrue(releaseChatAttachmentPermissionAfterPreflight(true, true, false))
        assertFalse(releaseChatAttachmentPermissionAfterPreflight(true, true, true))
        assertFalse(releaseChatAttachmentPermissionAfterPreflight(false, false, false))
    }

    @Test
    fun `附件预检失败形成提交前结构化结果且无需回读即可处置`() {
        val target = target(ChatMutationOperation.ATTACHMENT_SEND)
        val result = chatMutationFailedBeforeSubmissionResult(target)
        val entry = ChatMutationEntry(target, mutationResult = result, mutationFailure = DsmFailure(null, "failed", "retry"))

        assertEquals(MutationResultStatus.CANCELLED_BEFORE_SUBMISSION, result.status)
        assertFalse(result.submitted)
        assertFalse(result.requiresRefresh)
        assertEquals(MutationResultCounts(0, 0, 0), result.counts)
        assertFalse(chatMutationRequiresRefresh(entry))
        assertTrue(chatMutationCanRemoveFailed(entry))
        assertTrue(chatMutationCanContinueEditing(entry))
    }

    @Test
    fun `重试只在失败entry空闲时可用且UI策略与状态策略一致`() {
        val target = target(ChatMutationOperation.TEXT_SEND)
        val failed = ChatMutationEntry(
            target,
            mutationResult = result(MutationResultStatus.CONFIRMED_FAILURE),
        )
        val unavailable = listOf(
            null,
            failed.copy(confirmationRequested = true),
            failed.copy(mutationInProgress = true),
            failed.copy(mutationRefreshInProgress = true),
        )
        assertTrue(failed.retryEnabled)
        assertTrue(canRetryChatMutation(failed))
        unavailable.forEach { entry ->
            assertFalse(entry?.retryEnabled ?: false)
            assertFalse(canRetryChatMutation(entry))
        }
        val succeeded = failed.copy(
            mutationResult = result(MutationResultStatus.CONFIRMED_SUCCESS),
        )
        assertFalse(succeeded.retryEnabled)
        assertFalse(canRetryChatMutation(succeeded))
    }

    @Test
    fun `真实模块导航策略阻止带未收敛Chat写操作离开`() {
        val target = target(ChatMutationOperation.TEXT_SEND)
        val blocked = workspace().copy(
            chatMutationState = ChatMutationWorkspaceState(
                mapOf(target.requestId to ChatMutationEntry(target, mutationInProgress = true)),
            ),
        )
        assertTrue(workspaceNavigationBlockedByChat(blocked, Module.FILES))
        assertFalse(workspaceNavigationBlockedByChat(blocked, Module.CHAT))
        assertFalse(workspaceNavigationBlockedByChat(workspace(), Module.FILES))
        assertFalse(
            canSafelySwitchNas(
                emptyList(),
                emptyList(),
                emptyList(),
                hasActiveChatMutation = chatMutationBlocksWorkspaceExit(blocked.chatMutationState),
            ),
        )
    }

    private fun target(operation: ChatMutationOperation) = chatMutationTarget(
        "profile-a", operation, "request-a", "conversation-a", expectedEpochMillis = 1_000,
        requestParts = listOf("payload"),
    )

    private fun workspace() = WorkspaceState(
        NasProfile("profile-a", "NAS", "https://example.invalid", "user"),
        selectedModule = Module.CHAT,
    )

    private fun result(status: MutationResultStatus): MutationResult {
        val uncertain = status in setOf(
            MutationResultStatus.PARTIAL_SUCCESS,
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
        )
        val counts = when (status) {
            MutationResultStatus.CONFIRMED_SUCCESS -> MutationResultCounts(1, 0, 0)
            MutationResultStatus.PARTIAL_SUCCESS -> MutationResultCounts(1, 0, 1)
            MutationResultStatus.SUBMITTED_BUT_UNVERIFIED,
            MutationResultStatus.CANCELLATION_REQUESTED_AFTER_SUBMISSION,
            -> MutationResultCounts(0, 0, 1)
            MutationResultStatus.CANCELLED_BEFORE_SUBMISSION -> MutationResultCounts(0, 0, 0)
            else -> MutationResultCounts(0, 1, 0)
        }
        return MutationResult(
            1,
            status,
            "chatTextSend",
            submitted = status !in setOf(
                MutationResultStatus.CANCELLED_BEFORE_SUBMISSION,
                MutationResultStatus.CONFIRMED_FAILURE,
                MutationResultStatus.PERMISSION_DENIED,
                MutationResultStatus.UNSUPPORTED,
            ),
            requiresRefresh = uncertain,
            counts = counts,
            errorCategory = if (status == MutationResultStatus.CONFIRMED_SUCCESS) null
                else MutationErrorCategory.UNKNOWN,
        )
    }
}
