import DsmCore
import Foundation
import Observation

@MainActor
@Observable
final class ChatWorkspaceModel {
    private(set) var availability = ChatAvailability(status: .requiresValidation)
    private(set) var conversations: [ChatConversation] = []
    private(set) var users: [ChatUser] = []
    private(set) var messages: [ChatMessage] = []
    private(set) var selectedConversationID: String?
    private(set) var isLoading = false
    private(set) var isLoadingMessages = false
    private(set) var isPerformingAction = false
    private(set) var statusMessage: String?
    private(set) var statusIsError = false

    @ObservationIgnored private let repository: any ChatRepository
    @ObservationIgnored private var hasLoaded = false

    init(repository: any ChatRepository) {
        self.repository = repository
    }

    var selectedConversation: ChatConversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    var currentUserID: String? {
        users.first(where: { $0.isCurrentUser == true })?.id
    }

    func displayName(for userID: String) -> String? {
        users.first(where: { $0.id == userID })?.displayName
    }

    func isCurrentUser(_ message: ChatMessage) -> Bool {
        if let explicit = message.isFromCurrentUser { return explicit }
        if message.clientRequestID != nil { return true }
        return currentUserID.map { $0 == message.senderID } ?? false
    }

    func memberSummary(for conversation: ChatConversation) -> String {
        guard conversation.kind == .group else { return "一对一聊天" }
        let names = conversation.memberIDs.compactMap(displayName(for:))
        let count = conversation.memberCount ?? conversation.memberIDs.count
        if !names.isEmpty {
            let prefix = count > 0 ? "\(count) 位成员 · " : ""
            return prefix + names.prefix(4).joined(separator: "、")
                + (names.count > 4 ? " 等" : "")
        }
        return count > 0 ? "\(count) 位成员" : "群聊"
    }

    var canUseMessaging: Bool {
        availability.status == .available
    }

    var canCreateDirectConversation: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.directConversation)
    }

    var canCreateGroupConversation: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.groupConversation)
    }

    var canSendText: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.textMessage)
    }

    var canSendAttachments: Bool {
        let features = availability.supportedFeatures
        return canUseMessaging && (
            features.contains(.imageAttachment)
                || features.contains(.videoAttachment)
                || features.contains(.fileAttachment)
        )
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = nil
        statusIsError = false
        defer {
            isLoading = false
            hasLoaded = true
        }

        let discoveredAvailability = await repository.availability()
        availability = discoveredAvailability
        guard discoveredAvailability.status == .available else {
            conversations = []
            users = []
            messages = []
            selectedConversationID = nil
            statusMessage = availabilityMessage(for: discoveredAvailability.status)
            return
        }

        do {
            async let loadedConversations = repository.listConversations()
            async let loadedUsers = repository.listUsers()
            conversations = try await loadedConversations.sorted(by: Self.conversationSort)
            users = try await loadedUsers
                .filter { !$0.isDisabled }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

            if let selectedConversationID,
               conversations.contains(where: { $0.id == selectedConversationID }) {
                await selectConversation(id: selectedConversationID)
            } else if let first = conversations.first {
                await selectConversation(id: first.id)
            } else {
                selectedConversationID = nil
                messages = []
            }
        } catch {
            show(error)
        }
    }

    func selectConversation(id: String?) async {
        guard canUseMessaging else { return }
        guard let id else {
            selectedConversationID = nil
            messages = []
            return
        }
        guard conversations.contains(where: { $0.id == id }) else { return }
        selectedConversationID = id
        isLoadingMessages = true
        statusMessage = nil
        statusIsError = false
        defer { isLoadingMessages = false }
        do {
            let page = try await repository.listMessages(
                conversationID: id,
                before: nil,
                limit: 50
            )
            guard selectedConversationID == id else { return }
            messages = page.messages.sorted { $0.sentAt < $1.sentAt }
        } catch {
            guard selectedConversationID == id else { return }
            messages = []
            show(error)
        }
    }

    func openDirectConversation(userID: String) async -> Bool {
        guard canCreateDirectConversation, !isPerformingAction else { return false }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let conversation = try await repository.openDirectConversation(
                userID: userID,
                clientRequestID: UUID()
            )
            merge(conversation)
            await selectConversation(id: conversation.id)
            return true
        } catch {
            show(error)
            return false
        }
    }

    func createGroup(title: String, memberIDs: [String], isEncrypted: Bool) async -> Bool {
        guard canCreateGroupConversation, !isPerformingAction else { return false }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let draft = try ChatGroupDraft(
                title: title,
                memberIDs: memberIDs,
                isEncrypted: isEncrypted
            )
            let conversation = try await repository.createGroup(draft)
            merge(conversation)
            await selectConversation(id: conversation.id)
            return true
        } catch {
            show(error)
            return false
        }
    }

    func send(text: String?, attachmentURLs: [URL] = []) async -> Bool {
        guard let selectedConversationID, !isPerformingAction else { return false }
        guard canSendText || (!attachmentURLs.isEmpty && canSendAttachments) else { return false }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let draft = try ChatMessageDraft(
                conversationID: selectedConversationID,
                text: text,
                localAttachmentURLs: attachmentURLs
            )
            let message = try await repository.sendMessage(draft)
            guard self.selectedConversationID == selectedConversationID else { return true }
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            } else {
                messages.append(message)
            }
            messages.sort { $0.sentAt < $1.sentAt }
            return true
        } catch {
            show(error)
            return false
        }
    }

    func clearStatus() {
        statusMessage = nil
        statusIsError = false
    }

    private func merge(_ conversation: ChatConversation) {
        conversations.removeAll { $0.id == conversation.id }
        conversations.append(conversation)
        conversations.sort(by: Self.conversationSort)
    }

    private func show(_ error: Error) {
        statusIsError = true
        if let appError = error as? AppError {
            statusMessage = appError.safeUserMessage
        } else if let localizedError = error as? LocalizedError,
                  let description = localizedError.errorDescription {
            statusMessage = description
        } else {
            statusMessage = "消息暂时没有完成，请稍后重试。"
        }
    }

    private func availabilityMessage(for status: ChatAvailabilityStatus) -> String {
        switch status {
        case .available:
            "消息服务已就绪。"
        case .requiresValidation:
            "岚仓暂时还不能安全连接这台 NAS 的消息服务。准备完成前不会尝试发送消息，你仍可以继续使用文件和照片功能。"
        case .unavailable:
            "这台 NAS 当前没有可用的消息服务。请确认已安装并启用 Synology Chat Server，且当前账号具有使用权限。"
        }
    }

    private static func conversationSort(_ lhs: ChatConversation, _ rhs: ChatConversation) -> Bool {
        switch (lhs.lastActivityAt, rhs.lastActivityAt) {
        case let (left?, right?) where left != right:
            left > right
        case (nil, _?):
            false
        case (_?, nil):
            true
        default:
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
