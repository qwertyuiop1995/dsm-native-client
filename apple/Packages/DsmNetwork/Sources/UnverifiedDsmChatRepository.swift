import DsmCore
import Foundation

/// 完整用户聊天协议尚未通过脱敏实机验证时使用的关闭型适配器。
/// 它不会发送任何 Chat 请求，避免把公开 Bot 接口或猜测的内部接口用于普通用户会话。
public actor UnverifiedDsmChatRepository: ChatRepository {
    public init() {}

    public func availability() async -> ChatAvailability {
        ChatAvailability(status: .requiresValidation)
    }

    public func listUsers() async throws -> [ChatUser] {
        throw unavailableError()
    }

    public func listConversations() async throws -> [ChatConversation] {
        throw unavailableError()
    }

    public func listMessages(
        conversationID: String,
        before cursor: String?,
        limit: Int
    ) async throws -> ChatMessagePage {
        throw unavailableError()
    }

    public func openDirectConversation(
        userID: String,
        clientRequestID: UUID
    ) async throws -> ChatConversation {
        throw unavailableError()
    }

    public func createGroup(_ draft: ChatGroupDraft) async throws -> ChatConversation {
        throw unavailableError()
    }

    public func sendMessage(_ draft: ChatMessageDraft) async throws -> ChatMessage {
        throw unavailableError()
    }

    public func deleteMessage(
        conversationID: String,
        messageID: String,
        clientRequestID: UUID
    ) async throws {
        throw unavailableError()
    }

    public func closeConversation(
        conversationID: String,
        clientRequestID: UUID
    ) async throws {
        throw unavailableError()
    }

    public func setReminder(
        messageID: String,
        remindAt: Date,
        clientRequestID: UUID
    ) async throws -> ChatReminder {
        throw unavailableError()
    }

    public func createPoll(_ draft: ChatPollDraft) async throws -> ChatMessage {
        throw unavailableError()
    }

    private func unavailableError() -> AppError {
        AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 的消息功能暂时还不能在岚仓中使用。你仍可以继续使用文件和照片功能。"
        )
    }
}
